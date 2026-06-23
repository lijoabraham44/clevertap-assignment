###############################################################################
# prod / us-east-1 platform stack
#
# Instantiates the reusable VPC, EKS, and Transit Gateway modules. The
# ap-south-1 stack is an identical copy of this file with different locals,
# proving the modules are truly region-agnostic.
###############################################################################

locals {
  environment = "prod"
  region      = "us-east-1"
  name        = "clevertap-prod-use1"

  # Non-overlapping CIDR across the fleet (use1=10.10, aps1=10.20, euw1=10.30).
  vpc_cidr = "10.10.0.0/16"
  azs      = ["us-east-1a", "us-east-1b", "us-east-1c"]

  # Remote-region CIDRs reachable via the TGW peering mesh.
  remote_cidrs = ["10.20.0.0/16"] # ap-south-1

  tags = {
    Environment = local.environment
    Region      = local.region
    Project     = "platform-modernization"
  }
}

provider "aws" {
  region = local.region

  default_tags {
    tags = local.tags
  }
}

module "vpc" {
  source = "../../../modules/vpc"

  name              = local.name
  cidr_block        = local.vpc_cidr
  azs               = local.azs
  eks_cluster_names = [local.name]

  single_nat_gateway = false
  enable_flow_logs   = true

  tags = local.tags
}

module "eks" {
  source = "../../../modules/eks"

  cluster_name       = local.name
  kubernetes_version = "1.30"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids

  endpoint_public_access = false # private-only API server

  node_groups = {
    system = {
      capacity_type  = "ON_DEMAND"
      instance_types = ["m6i.large"]
      desired_size   = 3
      min_size       = 3
      max_size       = 6
      labels         = { role = "system" }
    }
    spot = {
      capacity_type  = "SPOT"
      instance_types = ["m6i.large", "m6a.large", "m5.large", "m5a.large"]
      desired_size   = 4
      min_size       = 2
      max_size       = 40
      labels         = { workload = "burstable" }
      taints = [{
        key    = "spot"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }
  }

  irsa_roles = {
    external-secrets = {
      namespace       = "external-secrets"
      service_account = "external-secrets"
      policy_arns     = ["arn:aws:iam::aws:policy/SecretsManagerReadWrite"]
    }
    cluster-autoscaler = {
      namespace       = "kube-system"
      service_account = "cluster-autoscaler"
      policy_arns     = [aws_iam_policy.cluster_autoscaler.arn]
    }
  }

  tags = local.tags
}

module "tgw" {
  source = "../../../modules/transit-gateway"

  name                  = local.name
  amazon_side_asn       = 64512
  vpc_id                = module.vpc.vpc_id
  attachment_subnet_ids = module.vpc.intra_subnet_ids
  route_table_ids       = concat(module.vpc.private_route_table_ids, [module.vpc.intra_route_table_id])
  remote_cidr_blocks    = local.remote_cidrs

  tags = local.tags
}

# Example customer-managed policy consumed by an IRSA role above.
resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${local.name}-cluster-autoscaler"
  description = "Permissions for the Kubernetes Cluster Autoscaler"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeImages",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/kubernetes.io/cluster/${local.name}" = "owned"
          }
        }
      }
    ]
  })

  tags = local.tags
}
