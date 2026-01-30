project_name = "public"
aws_region   = "us-east-1"

vpc_cidr        = "10.0.0.0/16"

public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]



kubernetes_version = "1.31"

node_group_min_size     = 2
node_group_desired_size = 2
node_group_max_size     = 3

instance_types = ["t3.medium", "t3.large"]
capacity_type  = "ON_DEMAND"