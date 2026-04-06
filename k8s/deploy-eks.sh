#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/eks-terraform"
K8S_DIR="${ROOT_DIR}/k8s"
NAMESPACE="wordpress"

for cmd in terraform aws kubectl; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[error] ${cmd} is required but not installed"
    exit 1
  fi
done

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

echo "[4/6] Applying core Kubernetes manifests..."
kubectl apply -f "${K8S_DIR}/namespace.yaml"
kubectl apply -f "${K8S_DIR}/mysql-secret.yaml" -f "${K8S_DIR}/wordpress-configmap.yaml"
kubectl apply -f "${K8S_DIR}/mysql-deployment.yaml" -f "${K8S_DIR}/wordpress-deployment.yaml"

if kubectl api-resources | grep -q '^horizontalpodautoscalers[[:space:]]'; then
  kubectl apply -f "${K8S_DIR}/hpa.yaml"
fi

echo "[5/6] Waiting for deployments to become available..."
kubectl -n "${NAMESPACE}" wait --for=condition=available deployment/mysql --timeout=600s
kubectl -n "${NAMESPACE}" wait --for=condition=available deployment/wordpress --timeout=600s

echo "[6/6] Deployment status and access endpoint:"
kubectl -n "${NAMESPACE}" get pods,svc,hpa

echo
echo "WordPress external endpoint (run again until EXTERNAL-IP is assigned):"
kubectl -n "${NAMESPACE}" get svc wordpress
