#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="wordpress"

echo "[1/7] Starting Minikube if needed..."
if ! minikube status >/dev/null 2>&1; then
  minikube start --driver=docker
fi
kubectl config use-context minikube >/dev/null

echo "[2/7] Enabling required Minikube addons..."
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

echo "[3/7] Recreating namespace for a clean local run..."
kubectl delete namespace "${NAMESPACE}" --ignore-not-found --wait=true >/dev/null
kubectl apply -f k8s/namespace.yaml

echo "[4/7] Applying core config and storage..."
kubectl apply -f k8s/mysql-secret.yaml -f k8s/wordpress-configmap.yaml
kubectl apply -f k8s/mysql-pv.yaml -f k8s/wordpress-pv.yaml
kubectl apply -f k8s/mysql-pvc.yaml -f k8s/wordpress-pvc.yaml

echo "[5/7] Applying core workloads..."
kubectl apply -f k8s/mysql-deployment.yaml -f k8s/wordpress-deployment.yaml

echo "[6/7] Applying local-compatible extras..."
kubectl apply -f k8s/hpa.yaml

if [[ "${INGRESS_READY}" == "true" ]]; then
  kubectl apply -f k8s/ingress.yaml
else
  echo "[info] Skipping k8s/ingress.yaml because ingress controller is not ready"
fi

if kubectl api-resources | grep -q '^verticalpodautoscalers[[:space:]]'; then
  kubectl apply -f k8s/vpa.yaml
else
  echo "[info] VPA CRD not installed. Skipping k8s/vpa.yaml"
fi

echo "[7/7] Waiting for readiness and printing access info..."
kubectl -n "${NAMESPACE}" wait --for=condition=available deployment/mysql --timeout=300s
kubectl -n "${NAMESPACE}" wait --for=condition=available deployment/wordpress --timeout=300s
if [[ "${INGRESS_READY}" == "true" ]]; then
  kubectl -n "${NAMESPACE}" get pods,svc,ingress,hpa
else
  kubectl -n "${NAMESPACE}" get pods,svc,hpa
fi

echo
minikube service wordpress -n "${NAMESPACE}" --url
