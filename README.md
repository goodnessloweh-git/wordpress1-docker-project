# WordPress on Kubernetes (Local + AWS EKS)

This project deploys WordPress + MySQL using Helm on Kubernetes.

Use one of these paths:
- **Local**: Minikube (quick test)
- **Cloud**: AWS EKS via Terraform

## Quick Start (Local Minikube)

### Prerequisites
- Docker
- kubectl
- Minikube
- Helm

### Required environment variables
```bash
export MYSQL_ROOT_PASSWORD='your-strong-root-password'
export MYSQL_PASSWORD='your-strong-user-password'
export MYSQL_USER='wpuser'
export MYSQL_DATABASE='wordpress'
```

### Deploy
```bash
chmod +x k8s/deploy-local.sh
./k8s/deploy-local.sh
```

The script prints a local URL at the end (from `minikube service ... --url`). Open it in your browser.

### Verify
```bash
kubectl -n wordpress get pods,svc,hpa
```

You should see `mysql` and `wordpress` pods in `Running` state.

---

## Quick Start (AWS EKS)

### Prerequisites
- AWS account + IAM permissions for EKS, EC2, IAM, VPC
- aws CLI configured (`aws configure`)
- Terraform
- kubectl
- Helm

### Configure Terraform inputs
Update `eks-terraform/terraform.tfvars` with valid subnets in your target region:
```hcl
region = "us-east-1"
subnet_ids = [
	"subnet-xxxxx",
	"subnet-yyyyy",
	"subnet-zzzzz"
]
```

### Required environment variables
```bash
export MYSQL_ROOT_PASSWORD='your-strong-root-password'
export MYSQL_PASSWORD='your-strong-user-password'
export MYSQL_USER='wpuser'
export MYSQL_DATABASE='wordpress'
```

### Optional image settings
By default, scripts deploy:
- `DOCKER_REGISTRY=docker.io`
- `DOCKER_REPOSITORY=goodness21/wordpress-custom`
- `DOCKER_IMAGE_TAG=latest`

Override if needed:
```bash
export DOCKER_REGISTRY='docker.io'
export DOCKER_REPOSITORY='your-user/your-wordpress-image'
export DOCKER_IMAGE_TAG='latest'
```

If your image is private, also set:
```bash
export DOCKER_USERNAME='your-registry-username'
export DOCKER_PASSWORD='your-registry-password-or-token'
```

### Deploy
```bash
chmod +x k8s/deploy-eks.sh
./k8s/deploy-eks.sh
```

### Verify and access
```bash
kubectl -n wordpress get pods,svc,hpa
kubectl -n wordpress get svc wordpress
```

Open the WordPress external endpoint from the `EXTERNAL-IP` column (often a DNS hostname).

---

## Security Notes

- Never commit real credentials to git.
- Use environment variables or GitHub Actions Secrets.
- Do not commit `terraform.tfvars`, `.tfstate`, `.env`, kubeconfig, or private key files.
- This repository includes ignore rules in `.gitignore` for common sensitive files.

---

## Troubleshooting

### Pods not ready
```bash
kubectl -n wordpress get pods
kubectl -n wordpress describe pod <pod-name>
kubectl -n wordpress logs <pod-name>
```

### EKS node group create fails
- Re-check subnet IDs in `eks-terraform/terraform.tfvars`
- Ensure subnets are in the same region and VPC
- Re-run `./k8s/deploy-eks.sh`

### No external endpoint yet
- Wait 2-5 minutes and run:
```bash
kubectl -n wordpress get svc wordpress
```

### No default StorageClass on cluster
`deploy-eks.sh` automatically switches to ephemeral storage if no default StorageClass exists.

---

## Cleanup

### Local
```bash
kubectl delete namespace wordpress
```

### EKS (destroy infrastructure)
```bash
terraform -chdir=eks-terraform destroy -auto-approve
```

---

## Project entry points

- `k8s/deploy-local.sh` - Local Minikube deployment
- `k8s/deploy-eks.sh` - Terraform + EKS + Helm deployment
- `charts/wordpress/` - Helm chart templates and values
- `.github/workflows/deploy-infra.yml` - Infra pipeline
- `.github/workflows/deploy-app.yml` - App build/deploy pipeline

For deeper setup and CI/CD guidance, see `SETUP.md` and `DEPLOY_INSTRUCTIONS.md`.
