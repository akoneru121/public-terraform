# ==============================================================================
# Main Terraform Configuration
# ==============================================================================
# This file serves as the entry point for the EKS infrastructure.
# Uses modular architecture for better organization and reusability.
# ==============================================================================

# Data sources
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

# ==============================================================================
# Local Values
# ==============================================================================
locals {
  cluster_name = "${var.project_name}-eks"
  account_id   = data.aws_caller_identity.current.account_id

  common_tags = {
    Project     = var.project_name
    ManagedBy   = "Terraform"
    CreatedBy   = "EKS-Wizard"
    ClusterName = local.cluster_name
  }
}

# ==============================================================================
# VPC Module
# ==============================================================================
module "vpc" {
  source = "./modules/vpc"

  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr

  public_subnets = var.public_subnets


  common_tags = local.common_tags
}

# ==============================================================================
# EKS Module
# ==============================================================================
module "eks" {
  source = "./modules/eks"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id

  subnet_ids = module.vpc.public_subnet_ids

  kubernetes_version     = var.kubernetes_version
  endpoint_public_access = true
  common_tags            = local.common_tags

  depends_on = [module.vpc]
}

# ==============================================================================
# Node Groups Module
# ==============================================================================
module "node_groups" {
  source = "./modules/node_groups"

  project_name              = var.project_name
  vpc_id                    = module.vpc.vpc_id
  cluster_name              = module.eks.cluster_name
  cluster_security_group_id = module.eks.cluster_security_group_id

  subnet_ids = module.vpc.public_subnet_ids

  instance_types = var.instance_types
  capacity_type  = var.capacity_type
  desired_size   = var.node_group_desired_size
  min_size       = var.node_group_min_size
  max_size       = var.node_group_max_size
  common_tags    = local.common_tags

  depends_on = [module.eks]
}