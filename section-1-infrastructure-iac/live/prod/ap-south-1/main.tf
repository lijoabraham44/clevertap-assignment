###############################################################################
# prod / ap-south-1 platform stack
#
# Byte-for-byte the same module calls as us-east-1, only the locals differ.
# This is the proof that the modules are region-agnostic and the fleet is
# standardized.
###############################################################################

locals {
  environment = "prod"
  region      = "ap-south-1"
  name        = "clevertap-prod-aps1"

  vpc_cidr = "10.20.0.0/16"
  azs      = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]

  remote_cidrs = ["10.10.0.0/16"] # us-east-1

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

  endpoint_public_access = false

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
  }

  tags = local.tags
}

module "tgw" {
  source = "../../../modules/transit-gateway"

  name                  = local.name
  amazon_side_asn       = 64513 # unique per region for inter-region peering
  vpc_id                = module.vpc.vpc_id
  attachment_subnet_ids = module.vpc.intra_subnet_ids
  route_table_ids       = concat(module.vpc.private_route_table_ids, [module.vpc.intra_route_table_id])
  remote_cidr_blocks    = local.remote_cidrs

  tags = local.tags
}
