# ==============================================================================
# VPC Module Variables
# ==============================================================================

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}


variable "public_subnets" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
}




variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

data "aws_availability_zones" "available" {
  state = "available"
}