# ==============================================================================
# Core Configuration Variables
# ==============================================================================
# These variables define the fundamental configuration for your EKS cluster.
# Values should be provided via terraform.tfvars or as CLI arguments.
# ==============================================================================

variable "project_name" {
  description = "Name of the project, used for resource naming and tagging"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
  }
}

# ==============================================================================
# Network Configuration Variables
# ==============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}


variable "public_subnets" {
  description = "List of CIDR blocks for public subnets (typically 3 for high availability)"
  type        = list(string)

  validation {
    condition     = length(var.public_subnets) >= 2
    error_message = "At least 2 public subnets are required for high availability."
  }
}




# ==============================================================================
# EKS Cluster Configuration Variables
# ==============================================================================

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster (e.g., 1.31, 1.30)"
  type        = string
}

# ==============================================================================
# Node Group Configuration Variables
# ==============================================================================

variable "node_group_min_size" {
  description = "Minimum number of nodes in the node group"
  type        = number

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "Minimum node group size must be at least 1."
  }
}

variable "node_group_desired_size" {
  description = "Desired number of nodes in the node group"
  type        = number

  validation {
    condition     = var.node_group_desired_size >= var.node_group_min_size
    error_message = "Desired size must be greater than or equal to minimum size."
  }
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in the node group"
  type        = number

  validation {
    condition     = var.node_group_max_size >= var.node_group_desired_size
    error_message = "Maximum size must be greater than or equal to desired size."
  }
}

variable "instance_types" {
  description = "List of EC2 instance types for the node group (e.g., [\"t3.medium\", \"t3.large\"])"
  type        = list(string)

  validation {
    condition     = length(var.instance_types) > 0
    error_message = "At least one instance type must be specified."
  }
}

variable "capacity_type" {
  description = "Capacity type for node group: ON_DEMAND for stable workloads, SPOT for cost savings"
  type        = string

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "Capacity type must be either ON_DEMAND or SPOT."
  }
}

variable "disk_size" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 50

  validation {
    condition     = var.disk_size >= 20
    error_message = "Disk size must be at least 20 GB."
  }
}

# ==============================================================================
# NAT Gateway Configuration Variables
# ==============================================================================
# NAT Gateways provide outbound internet access for private subnets.
# Cost implications:
# - Single NAT: ~$32/month (cost-optimized, not AZ-resilient)
# - Multi-AZ NAT: ~$96/month (highly available, one per AZ)
# - No NAT: $0/month (private subnets have no internet access)
# ==============================================================================

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnet internet access"
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all AZs (cost-optimized, not HA)"
  type        = bool
  default     = false
}