# WordPress on AWS EKS (Terraform + Kubernetes + CI/CD)

This repository deploys a custom WordPress app with MySQL using:
- Terraform (to provision AWS EKS)
- Kubernetes manifests (to run WordPress + MySQL)
- GitHub Actions (to automate infra and app deployment)

## What this project is about

Goal: package WordPress as a containerized app and deploy it on Kubernetes (EKS), with repeatable infrastructure and CI/CD pipelines.

## Where to look first

- This file (`README.md`) → what this repo is and how to run/test quickly
- `SETUP.md` → full end-to-end setup guide
- `.github/workflows/deploy-infra.yml` → Terraform + cluster/app infra deployment
- `.github/workflows/deploy-app.yml` → image build/push + app rollout
- `eks-terraform/` → Terraform code for EKS cluster and node group
- `k8s/` → Kubernetes manifests and helper scripts

## Repository structure

- `eks-terraform/`
  - `main.tf` : EKS cluster + managed node group + IAM roles
  - `variables.tf` : Terraform variables
  - `outputs.tf` : Cluster outputs
- `k8s/`
  - `deploy-eks.sh` : deploy/update to AWS EKS
  - `deploy-local.sh` : local Minikube deploy
  - `mysql-deployment.yaml`, `wordpress-deployment.yaml`
  - `mysql-secret.yaml`, `wordpress-configmap.yaml`
  - `hpa.yaml`, `ingress.yaml`, `namespace.yaml`
- `.github/workflows/`
  - `deploy-infra.yml`
  - `deploy-app.yml`

## Run the app now (quick test)

### Option A: Local test (fastest)

1. Install prerequisites: `docker`, `kubectl`, `minikube`.
2. Run:
   ```bash
   chmod +x k8s/deploy-local.sh
   ./k8s/deploy-local.sh
   ```
3. Verify:
   ```bash
   kubectl -n wordpress get pods,svc
   ```
4. Open WordPress URL printed by the script.

### Option B: AWS EKS test

1. Configure AWS credentials and set `eks-terraform/terraform.tfvars` subnet IDs.
2. Run:
   ```bash
   chmod +x k8s/deploy-eks.sh
   ./k8s/deploy-eks.sh
   ```
3. Verify:
   ```bash
   kubectl -n wordpress get pods,svc
   kubectl -n wordpress get svc wordpress
   ```
4. Open the LoadBalancer endpoint shown in `EXTERNAL-IP`.

## How to verify it works

Run:
```bash
kubectl -n wordpress get pods,svc
```

Expected:
- `mysql` and `wordpress` pods show `Running`
- `wordpress` service has an external endpoint (EKS) or local URL (Minikube)

## CI/CD behavior

- Push to `main`:
  - `deploy-app.yml` builds and pushes Docker image, then updates WordPress deployment.
- Push changes in `eks-terraform/**` or `k8s/**`:
  - `deploy-infra.yml` runs Terraform and applies k8s manifests.

Required GitHub secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `DOCKER_REGISTRY`
- `DOCKER_USERNAME`
- `DOCKER_PASSWORD`
- `DOCKER_REPOSITORY`
- `KUBE_CONFIG_DATA`

## Notes

- Current EKS manifests use `emptyDir` storage for simplicity (non-persistent).
- Minikube path supports PV/PVC local storage files in `k8s/`.
- Sensitive files and Terraform state are ignored in `.gitignore`.

## Cleanup

Destroy cloud resources:
```bash
terraform -chdir=eks-terraform destroy -auto-approve
```
