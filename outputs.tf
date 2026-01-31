# ==============================================================================
# Root Module Outputs
# ==============================================================================

# output "cluster_id" {
#   description = "EKS cluster ID"
#   value       = module.eks.cluster_id
# }

# output "cluster_name" {
#   description = "EKS cluster name"
#   value       = module.eks.cluster_name
# }

# output "cluster_endpoint" {
#   description = "Endpoint for EKS control plane"
#   value       = module.eks.cluster_endpoint
# }

# output "cluster_security_group_id" {
#   description = "Security group ID attached to the EKS cluster"
#   value       = module.eks.cluster_security_group_id
# }

# output "cluster_certificate_authority_data" {
#   description = "Base64 encoded certificate data required to communicate with the cluster"
#   value       = module.eks.cluster_certificate_authority_data
#   sensitive   = true
# }

# output "cluster_oidc_issuer_url" {
#   description = "The URL on the EKS cluster OIDC Issuer"
#   value       = module.eks.oidc_provider_url
# }

# output "node_group_id" {
#   description = "EKS node group ID"
#   value       = module.node_groups.node_group_id
# }

# output "node_security_group_id" {
#   description = "Security group ID attached to the EKS nodes"
#   value       = module.node_groups.node_security_group_id
# }

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}


output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnet_ids
}




# output "configure_kubectl" {
#   description = "Command to configure kubectl"
#   value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
# }