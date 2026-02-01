# ==============================================================================
# VPC Module
# ==============================================================================
# Creates a production-ready VPC with configurable subnet architecture
# ==============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name                                            = "${var.project_name}-vpc"
    "kubernetes.io/cluster/${var.project_name}-eks" = "shared"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

# ==============================================================================
# NAT Gateway Configuration
# ==============================================================================


# ==============================================================================
# Subnets
# ==============================================================================

resource "aws_subnet" "public" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  lifecycle {
    ignore_changes = [
      map_public_ip_on_launch
    ]
  }

  tags = merge(var.common_tags, {
    Name                                            = "${var.project_name}-public-subnet-${count.index + 1}"
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/${var.project_name}-eks" = "shared"
    Tier                                            = "Public"
  })
}





# ==============================================================================
# Route Tables
# ==============================================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-public-rt"
    Tier = "Public"
  })
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


