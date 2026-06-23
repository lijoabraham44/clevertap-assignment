###############################################################################
# EKS control plane
#
# - Private API server endpoint by default (endpoint_public_access = false).
# - Envelope encryption of Kubernetes secrets with a dedicated KMS key.
# - Control plane audit/auth logs shipped to CloudWatch.
# - API + ConfigMap authentication mode so access entries can be managed in IaC.
###############################################################################

locals {
  common_tags = merge(
    {
      "ManagedBy"                                 = "terraform"
      "Module"                                    = "eks"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    },
    var.tags,
  )
}

# --- KMS key for envelope encryption of secrets -----------------------------
resource "aws_kms_key" "eks" {
  description             = "EKS secrets envelope encryption for ${var.cluster_name}"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true

  tags = merge(local.common_tags, { Name = "${var.cluster_name}-eks-secrets" })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks.key_id
}

# --- Control plane log group ------------------------------------------------
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days

  tags = local.common_tags
}

# --- Cluster IAM role -------------------------------------------------------
data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# --- Dedicated security group for the cluster -------------------------------
resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  description = "EKS control plane security group for ${var.cluster_name}"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${var.cluster_name}-cluster" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "cluster_all" {
  security_group_id = aws_security_group.cluster.id
  description       = "Allow all outbound from control plane"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- The cluster ------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  enabled_cluster_log_types = var.cluster_log_types

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.endpoint_public_access_cidrs : null
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.eks,
  ]
}
