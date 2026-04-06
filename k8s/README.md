# Kubernetes deployment for this WordPress project

Prerequisites:
- A kubernetes cluster with `kubectl` configured
- An ingress controller (NGINX / GKE Ingress) and cert-manager if using TLS
- If using GKE: enable backendconfig and managedcertificates features as needed

Local Minikube quick run (recommended):

```bash
chmod +x k8s/deploy-local.sh
./k8s/deploy-local.sh
```

AWS EKS quick run:

```bash
chmod +x k8s/deploy-eks.sh
./k8s/deploy-eks.sh
```

**AWS EKS script** (`deploy-eks.sh`):
- runs Terraform in `eks-terraform/` to create/update the EKS cluster and node group
- updates your local kubeconfig with `aws eks update-kubeconfig`
- applies core Kubernetes manifests (namespace, secrets, configmaps, deployments)
- workloads use emptyDir volumes (no persistent storage)
- waits for MySQL and WordPress readiness
- prints service status and LoadBalancer endpoint

**Local Minikube script** (`deploy-local.sh`):
- starts Minikube (docker driver) if needed
- enables `ingress` and `metrics-server` addons
- applies all local-compatible manifests in the correct order
- workloads use PersistentVolumeClaims with hostPath storage
- applies `vpa.yaml` only when the VPA CRD exists

If ingress image pull fails in your network, the script continues with core services and HPA so WordPress still runs locally via service URL.

Quick manual deployment steps (for Minikube with PVCs):

1. Create namespace (optional):
   ```bash
   kubectl apply -f k8s/namespace.yaml
   ```
2. Create secrets and configmaps:
   ```bash
   kubectl apply -f k8s/mysql-secret.yaml
   kubectl apply -f k8s/wordpress-configmap.yaml
   ```
3. Create PersistentVolumes and PersistentVolumeClaims:
   ```bash
   kubectl apply -f k8s/mysql-pv.yaml -f k8s/wordpress-pv.yaml
   kubectl apply -f k8s/mysql-pvc.yaml -f k8s/wordpress-pvc.yaml
   ```
4. Deploy MySQL then WordPress:
   ```bash
   kubectl apply -f k8s/mysql-deployment.yaml -f k8s/wordpress-deployment.yaml
   ```
5. Expose via Ingress (if using LoadBalancer service you may skip):
   ```bash
   kubectl apply -f k8s/ingress.yaml
   ```
6. Add autoscaling if desired:
   ```bash
   kubectl apply -f k8s/hpa.yaml
   kubectl apply -f k8s/vpa.yaml  # optional, requires VPA admission controller
   ```

For EKS deployment, use `./k8s/deploy-eks.sh` or `./github/workflows/deploy-infra.yml` (no PVCs needed).

Notes & troubleshooting:
- **Storage**: Minikube uses hostPath PVCs (local-only). EKS uses emptyDir volumes (data is not persisted across pod restarts). For production EKS, add an EBS storage class and update the deployments to use PVCs.
- **Secrets**: The included `mysql-secret.yaml` uses `stringData` for convenience in local/dev. For production, use sealed-secrets or your cloud provider secret manager.
- **Readiness/Liveness probes**: Both deployments include health checks. MySQL uses TCP probes; WordPress uses HTTP probes.
- **GKE-specific files**: `k8s/backendconfig.yaml` and `k8s/managedcertificate.yaml` are GKE-only and will not work on Minikube or EKS without modification.
- **LoadBalancer IP pending**: If `EXTERNAL-IP` stays pending on EKS, confirm your subnets are tagged for ELB and worker nodes have public IP or NAT egress.

CI/CD:
- **Infrastructure**: GitHub Actions workflow (`.github/workflows/deploy-infra.yml`) applies Terraform to create/update EKS cluster and deploys the Kubernetes manifests.
- **Application**: GitHub Actions workflow (`.github/workflows/deploy-app.yml`) builds and pushes the Docker image, creates the registry pull secret, and triggers a rollout update.

Both workflows require GitHub secrets:
- AWS: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
- Docker Registry: `DOCKER_REGISTRY`, `DOCKER_USERNAME`, `DOCKER_PASSWORD`, `DOCKER_REPOSITORY`
- Kubernetes: `KUBE_CONFIG_DATA` (base64-encoded kubeconfig)

-- end
