output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Endpoint of the Kubernetes API server (private)."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate for the cluster."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the control plane."
  value       = aws_security_group.cluster.id
}

output "cluster_primary_security_group_id" {
  description = "EKS-managed cluster security group that all nodes/pods are placed in."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL (without scheme) for building additional IRSA trust policies."
  value       = local.oidc_provider_host
}

output "node_role_arn" {
  description = "IAM role ARN shared by managed node groups."
  value       = aws_iam_role.node.arn
}

output "node_group_names" {
  description = "Names of the managed node groups."
  value       = [for ng in aws_eks_node_group.this : ng.node_group_name]
}

output "irsa_role_arns" {
  description = "Map of IRSA role key -> created IAM role ARN. Annotate service accounts with these."
  value       = { for k, r in aws_iam_role.irsa : k => r.arn }
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for secret envelope encryption."
  value       = aws_kms_key.eks.arn
}
