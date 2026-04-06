# WordPress on EKS - Setup Guide

This guide walks you through deploying WordPress and MySQL on AWS EKS using Terraform and Kubernetes.

## Prerequisites

- AWS account with appropriate IAM permissions
- `aws` CLI configured
- `terraform` CLI installed
- `kubectl` installed
- `docker` CLI installed (for pushing images)
- A Docker registry (Docker Hub, ECR, etc.)

## Step 1: Configure AWS Credentials

```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, region, and output format
```

Or set environment variables:
```bash
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
export AWS_REGION=us-east-1
```

## Step 2: Update Terraform Variables

Edit `eks-terraform/terraform.tfvars`:

```bash
# Find your VPC subnets in AWS Console -> VPC -> Subnets
# Update subnet_ids to your actual subnet IDs (must be in different AZs)
region = "us-east-1"
node_instance_types = ["t3.micro"]  # or your preferred instance type
subnet_ids = [
  "subnet-xxxxx",  # Replace with your subnet IDs
  "subnet-xxxxx",
  "subnet-xxxxx"
]
```

## Step 3: Build and Push Docker Image

Edit `k8s/wordpress-deployment.yaml` and update the image:

```yaml
image: your-registry/your-repo:latest  # Change this
```

Build and push the image:

```bash
docker build -t your-registry/your-repo:latest .
docker push your-registry/your-repo:latest
```

Or use the GitHub Actions workflow (see Step 6).

## Step 4: Update Kubernetes Secrets

Edit `k8s/mysql-secret.yaml` with strong passwords:

```yaml
stringData:
  mysql-root-password: YourStrongRootPassword!
  mysql-password: YourStrongUserPassword!
```

## Step 5: Deploy to EKS (Local)

Run the EKS deployment script:

```bash
chmod +x k8s/deploy-eks.sh
./k8s/deploy-eks.sh
```

This will:
- Create/update the EKS cluster and node group via Terraform
- Configure kubectl
- Deploy MySQL and WordPress
- Output the WordPress external URL

Access WordPress:
```bash
kubectl -n wordpress get svc wordpress
# Use the EXTERNAL-IP value in your browser
```

## Step 6: Set Up GitHub Actions (CI/CD)

In your GitHub repository, add these secrets:

**Settings → Secrets and variables → Actions → New repository secret**

### AWS Secrets
- `AWS_ACCESS_KEY_ID`: Your AWS access key
- `AWS_SECRET_ACCESS_KEY`: Your AWS secret key

### Docker Registry Secrets
- `DOCKER_REGISTRY`: `docker.io` (or your registry URL)
- `DOCKER_USERNAME`: Your Docker Hub username
- `DOCKER_PASSWORD`: Your Docker Hub token (or password)
- `DOCKER_REPOSITORY`: `your-username/wordpress-custom`

### Kubernetes Secret
- `KUBE_CONFIG_DATA`: Base64-encoded kubeconfig

Generate it:
```bash
cat ~/.kube/config | base64 -w 0 | pbcopy  # macOS
# or on Linux:
cat ~/.kube/config | base64 -w 0
# Paste the output into the secret
```

## Step 7: Push to GitHub

```bash
git add .
git commit -m "Deploy WordPress on EKS"
git push origin main
```

This will trigger both workflows:
1. **deploy-infra.yml** - Updates EKS cluster (if you modify `eks-terraform/` or `k8s/` files)
2. **deploy-app.yml** - Builds image and updates WordPress deployment (on every push to main)

## Troubleshooting

### Pods stuck in Pending
```bash
kubectl -n wordpress describe pod <pod-name>
kubectl -n wordpress logs <pod-name>
```

### LoadBalancer IP not assigned
- Check if subnets are tagged for ELB
- Confirm security groups allow traffic

### Database connection fails
- Verify MySQL pod is running: `kubectl -n wordpress get pods`
- Check passwords match between secret and WordPress env vars

### Image pull fails
- Check registry credentials: `kubectl -n wordpress get secret regcred -o yaml`
- Verify image exists: `docker pull your-registry/your-repo:latest`

## Local Minikube Deployment (Alternative)

For local testing with persistent storage:

```bash
chmod +x k8s/deploy-local.sh
./k8s/deploy-local.sh
```

This starts Minikube and uses hostPath storage (data not persistent on pod restart).

## Production Considerations

- **Secrets Management**: Use AWS Secrets Manager or sealed-secrets instead of plain YAML
- **Persistent Storage**: Switch from emptyDir to EBS volumes for data persistence
- **TLS/SSL**: Add cert-manager and Let's Encrypt for HTTPS
- **Backup**: Set up EBS snapshots and database backups
- **Monitoring**: Add CloudWatch or Prometheus for metrics
- **Ingress**: Replace LoadBalancer with ingress controller for DNS routing

## Cleanup

To destroy the EKS cluster and all resources:

```bash
kubectl -n wordpress delete deployment,svc,secret,configmap --all
terraform -chdir=eks-terraform destroy -auto-approve
```

Or just delete specific resources:
```bash
kubectl delete namespace wordpress
```
