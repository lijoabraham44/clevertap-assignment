###############################################################################
# Locals
#
# Subnets are carved deterministically out of the VPC CIDR using cidrsubnet so
# the same module call produces an identical, predictable layout in every
# region. Public subnets occupy the first block of indexes, private the second,
# and intra the third, keeping ranges non-overlapping.
###############################################################################

locals {
  az_count = length(var.azs)

  # Stable per-tier index offsets so the three tiers never collide.
  public_subnets = [
    for i in range(local.az_count) :
    cidrsubnet(var.cidr_block, var.public_subnet_newbits, i)
  ]

  private_subnets = [
    for i in range(local.az_count) :
    cidrsubnet(var.cidr_block, var.private_subnet_newbits, i + local.az_count)
  ]

  intra_subnets = [
    for i in range(local.az_count) :
    cidrsubnet(var.cidr_block, var.intra_subnet_newbits, i + (local.az_count * 2))
  ]

  nat_gateway_count = var.single_nat_gateway ? 1 : local.az_count

  # Subnet tags that let the AWS Load Balancer Controller auto-discover subnets.
  eks_shared_tags = {
    for cluster in var.eks_cluster_names :
    "kubernetes.io/cluster/${cluster}" => "shared"
  }

  common_tags = merge(
    {
      "ManagedBy" = "terraform"
      "Module"    = "vpc"
    },
    var.tags,
  )
}

###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = var.name })
}

###############################################################################
# Internet Gateway (public egress/ingress)
###############################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${var.name}-igw" })
}

###############################################################################
# Public subnets + route table
###############################################################################

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnets[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    local.eks_shared_tags,
    {
      Name                     = "${var.name}-public-${var.azs[count.index]}"
      Tier                     = "public"
      "kubernetes.io/role/elb" = "1"
    },
  )
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

###############################################################################
# NAT gateways (one per AZ in prod, single shared in non-prod)
###############################################################################

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(local.common_tags, { Name = "${var.name}-nat-${count.index}" })
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, { Name = "${var.name}-nat-${count.index}" })

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# Private (application) subnets + per-AZ route tables
###############################################################################

resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(
    local.common_tags,
    local.eks_shared_tags,
    {
      Name                              = "${var.name}-private-${var.azs[count.index]}"
      Tier                              = "private"
      "kubernetes.io/role/internal-elb" = "1"
    },
  )
}

resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${var.name}-private-${var.azs[count.index]}" })
}

resource "aws_route" "private_nat" {
  count = local.az_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"

  # When single_nat_gateway is true, every private RT points at NAT #0.
  nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

###############################################################################
# Intra (database / isolated) subnets — no route to the internet
###############################################################################

resource "aws_subnet" "intra" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.intra_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name}-intra-${var.azs[count.index]}"
      Tier = "intra"
    },
  )
}

resource "aws_route_table" "intra" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${var.name}-intra" })
}

resource "aws_route_table_association" "intra" {
  count = local.az_count

  subnet_id      = aws_subnet.intra[count.index].id
  route_table_id = aws_route_table.intra.id
}
