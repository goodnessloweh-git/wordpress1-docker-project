#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/eks-terraform"
K8S_DIR="${ROOT_DIR}/k8s"
NAMESPACE="wordpress"
CHART_DIR="${ROOT_DIR}/charts/wordpress"

DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io}"
DOCKER_REPOSITORY="${DOCKER_REPOSITORY:-goodness21/wordpress-custom}"
DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-latest}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_USER="${MYSQL_USER:-wpuser}"
MYSQL_DATABASE="${MYSQL_DATABASE:-wordpress}"
INGRESS_HOST="${INGRESS_HOST:-}"
INGRESS_TLS_SECRET_NAME="${INGRESS_TLS_SECRET_NAME:-}"
INGRESS_MANAGED_CERT_NAME="${INGRESS_MANAGED_CERT_NAME:-}"

for cmd in terraform aws kubectl helm; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[error] ${cmd} is required but not installed"
    exit 1
  fi
done

if [[ -z "${MYSQL_ROOT_PASSWORD}" || -z "${MYSQL_PASSWORD}" ]]; then
  echo "[error] MYSQL_ROOT_PASSWORD and MYSQL_PASSWORD environment variables are required"
  exit 1
fi

echo "[1/6] Ensuring Terraform is initialized..."
terraform -chdir="${TF_DIR}" init -input=false >/dev/null

echo "[1/6] Importing existing IAM roles if present..."
if ! terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -q '^aws_iam_role.cluster$'; then
  terraform -chdir="${TF_DIR}" import aws_iam_role.cluster eks-cluster-wordpress >/dev/null 2>&1 || true
fi
if ! terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -q '^aws_iam_role.node_group$'; then
  terraform -chdir="${TF_DIR}" import aws_iam_role.node_group eks-nodegroup-wordpress >/dev/null 2>&1 || true
fi
if ! terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -q '^aws_eks_cluster.wordpress$'; then
  terraform -chdir="${TF_DIR}" import aws_eks_cluster.wordpress wordpress >/dev/null 2>&1 || true
fi
if ! terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -q '^aws_eks_node_group.wordpress$'; then
  terraform -chdir="${TF_DIR}" import aws_eks_node_group.wordpress wordpress:wordpress-workers >/dev/null 2>&1 || true
fi

echo "[2/6] Applying Terraform (EKS control plane + nodes)..."
terraform -chdir="${TF_DIR}" apply -auto-approve

CLUSTER_NAME="$(terraform -chdir="${TF_DIR}" output -raw cluster_name)"
AWS_REGION="$(terraform -chdir="${TF_DIR}" output -raw cluster_region)"

echo "[3/6] Updating kubeconfig for cluster ${CLUSTER_NAME}..."
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"

echo "[4/6] Creating runtime secrets and deploying with Helm..."
kubectl apply -f "${K8S_DIR}/namespace.yaml"
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

HELM_ARGS=(
  --namespace "${NAMESPACE}"
  --set "image.repository=${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}"
  --set "image.tag=${DOCKER_IMAGE_TAG}"
)

if ! kubectl get sc -o jsonpath='{range .items[*]}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' | grep -q '^true$'; then
  echo "[info] No default StorageClass found; deploying with ephemeral storage"
  HELM_ARGS+=(
    --set persistence.mysql.enabled=false
    --set persistence.wordpress.enabled=false
  )
fi

if [[ -n "${INGRESS_HOST}" ]]; then
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
fi

helm upgrade --install wordpress "${CHART_DIR}" "${HELM_ARGS[@]}"

echo "[5/6] Waiting for deployments to become available..."
kubectl -n "${NAMESPACE}" wait --for=condition=available deployment/mysql --timeout=600s
kubectl -n "${NAMESPACE}" wait --for=condition=available deployment/wordpress --timeout=600s

echo "[6/6] Deployment status and access endpoint:"
kubectl -n "${NAMESPACE}" get pods,svc,hpa

echo
echo "WordPress external endpoint (run again until EXTERNAL-IP is assigned):"
kubectl -n "${NAMESPACE}" get svc wordpress
