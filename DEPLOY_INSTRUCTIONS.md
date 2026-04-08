# Full Deployment Test Guide

## Step 1: Set up AWS credentials (if not already done)

```bash
aws configure
# Enter: AWS Access Key ID, Secret Access Key, Region (us-east-1), Output format (json)
```

Or set environment variables:
```bash
export AWS_ACCESS_KEY_ID='your-key'
export AWS_SECRET_ACCESS_KEY='your-secret'
export AWS_REGION='us-east-1'
```

## Step 2: Set MySQL credentials (never hardcode!)

```bash
export MYSQL_ROOT_PASSWORD='your-strong-root-password'
export MYSQL_PASSWORD='your-strong-user-password'
export MYSQL_USER='wpuser'
export MYSQL_DATABASE='wordpress'
```

## Step 3: Deploy to AWS EKS (full infrastructure + app)

```bash
chmod +x k8s/deploy-eks.sh
./k8s/deploy-eks.sh
```

This will:
- Initialize and apply Terraform (creates EKS cluster, node groups, IAM roles)
- Configure kubectl to access your cluster
- Create Kubernetes namespace
- Create MySQL secret
- Deploy WordPress + MySQL with Helm
- Wait for pods to be ready
- Show you the access details

## Step 4: Access WordPress

After deployment finishes, it will print:
```
WordPress external endpoint (run again until EXTERNAL-IP is assigned):
```

Copy the external IP into your browser to open WordPress.

## Step 5: Verify everything is running

```bash
kubectl -n wordpress get pods,svc
kubectl -n wordpress get hpa
```

## Cleanup (destroy all AWS resources)

```bash
terraform -chdir=eks-terraform destroy -auto-approve
```

## Troubleshooting

**If Terraform fails:**
```bash
terraform -chdir=eks-terraform refresh
terraform -chdir=eks-terraform plan
```

**If kubectl can't connect:**
```bash
aws eks update-kubeconfig --name wordpress --region us-east-1
```

**If pods are stuck:**
```bash
kubectl -n wordpress describe pod <pod-name>
kubectl -n wordpress logs <pod-name>
```

**If LoadBalancer IP is not assigned:**
- Can take 2-5 minutes
- Run: `kubectl -n wordpress get svc wordpress` and wait

---

Once everything is verified working, you can push to GitHub and the CI/CD pipelines will handle future deployments automatically.
