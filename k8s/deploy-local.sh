#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="wordpress"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="${ROOT_DIR}/charts/wordpress"

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_USER="${MYSQL_USER:-wpuser}"
MYSQL_DATABASE="${MYSQL_DATABASE:-wordpress}"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io}"
DOCKER_REPOSITORY="${DOCKER_REPOSITORY:-goodness21/wordpress-custom}"
DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-latest}"
INGRESS_HOST="${INGRESS_HOST:-}"
INGRESS_TLS_SECRET_NAME="${INGRESS_TLS_SECRET_NAME:-}"
INGRESS_MANAGED_CERT_NAME="${INGRESS_MANAGED_CERT_NAME:-}"

for cmd in kubectl minikube helm; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[error] ${cmd} is required but not installed"
    exit 1
  fi
done

if [[ -z "${MYSQL_ROOT_PASSWORD}" || -z "${MYSQL_PASSWORD}" ]]; then
  echo "[error] MYSQL_ROOT_PASSWORD and MYSQL_PASSWORD environment variables are required"
  exit 1
fi

echo "[1/6] Starting Minikube if needed..."
if ! minikube status >/dev/null 2>&1; then
  minikube start --driver=docker
fi
kubectl config use-context minikube >/dev/null

echo "[2/6] Enabling required Minikube addons..."
minikube addons enable metrics-server >/dev/null

INGRESS_READY="false"
if minikube addons enable ingress >/dev/null 2>&1; then
  if kubectl -n ingress-nginx wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx --timeout=180s >/dev/null 2>&1; then
    INGRESS_READY="true"
  else
    echo "[warn] ingress addon enabled but controller is not ready yet; continuing without ingress routing"
  fi
else
  echo "[warn] could not enable ingress addon (likely image pull/network issue); continuing without ingress routing"
fi

echo "[3/6] Recreating namespace for a clean local run..."
kubectl delete namespace "${NAMESPACE}" --ignore-not-found --wait=true >/dev/null
kubectl apply -f k8s/namespace.yaml

echo "[4/6] Creating runtime secrets..."
kubectl -n "${NAMESPACE}" create secret generic mysql-secret \
  --from-literal=mysql-root-password="${MYSQL_ROOT_PASSWORD}" \
  --from-literal=mysql-password="${MYSQL_PASSWORD}" \
  --from-literal=mysql-user="${MYSQL_USER}" \
  --from-literal=mysql-database="${MYSQL_DATABASE}" \
  --dry-run=client -o yaml | kubectl apply -f -

if [[ -n "${DOCKER_USERNAME:-}" && -n "${DOCKER_PASSWORD:-}" ]]; then
  kubectl -n "${NAMESPACE}" create secret docker-registry regcred \
    --docker-server="${DOCKER_REGISTRY}" \
    --docker-username="${DOCKER_USERNAME}" \
    --docker-password="${DOCKER_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

echo "[5/6] Deploying with Helm..."
HELM_ARGS=(
  --namespace "${NAMESPACE}"
  --set "image.repository=${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}"
  --set "image.tag=${DOCKER_IMAGE_TAG}"
)

if [[ "${INGRESS_READY}" == "true" && -n "${INGRESS_HOST}" ]]; then
  HELM_ARGS+=(--set ingress.enabled=true --set "ingress.host=${INGRESS_HOST}")
  if [[ -n "${INGRESS_MANAGED_CERT_NAME}" ]]; then
    HELM_ARGS+=(
      --set ingress.className=gce
      --set ingress.managedCertificate.enabled=true
      --set "ingress.managedCertificate.name=${INGRESS_MANAGED_CERT_NAME}"
    )
  fi
  if [[ -n "${INGRESS_TLS_SECRET_NAME}" ]]; then
    HELM_ARGS+=(--set ingress.tls.enabled=true --set "ingress.tls.secretName=${INGRESS_TLS_SECRET_NAME}")
  fi
elif [[ "${INGRESS_READY}" != "true" ]]; then
  echo "[info] Ingress controller is not ready. Deploying without ingress."
fi

if kubectl api-resources | grep -q '^verticalpodautoscalers[[:space:]]'; then
  HELM_ARGS+=(--set vpa.enabled=true)
fi

helm upgrade --install wordpress "${CHART_DIR}" "${HELM_ARGS[@]}"

echo "[6/6] Waiting for readiness and printing access info..."
kubectl -n "${NAMESPACE}" wait --for=condition=available deployment/mysql --timeout=600s
kubectl -n "${NAMESPACE}" wait --for=condition=available deployment/wordpress --timeout=600s
if [[ "${INGRESS_READY}" == "true" ]]; then
  kubectl -n "${NAMESPACE}" get pods,svc,ingress,hpa
else
  kubectl -n "${NAMESPACE}" get pods,svc,hpa
fi

echo
minikube service wordpress -n "${NAMESPACE}" --url
