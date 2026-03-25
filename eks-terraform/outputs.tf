output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.wordpress.name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.wordpress.endpoint
}

output "cluster_region" {
  description = "AWS region"
  value       = var.region
}
