# ==============================================================================
# Node Groups Module Outputs
# ==============================================================================

output "node_group_id" {
  description = "EKS node group ID"
  value       = aws_eks_node_group.main.id
}

output "node_group_arn" {
  description = "ARN of the EKS node group"
  value       = aws_eks_node_group.main.arn
}

output "node_role_arn" {
  description = "ARN of the node IAM role"
  value       = aws_iam_role.eks_nodes.arn
}

output "node_security_group_id" {
  description = "Security group ID for nodes"
  value       = aws_security_group.eks_nodes.id
}