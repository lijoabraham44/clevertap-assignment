###############################################################################
# Cluster add-ons (managed via Terraform)
#
# vpc-cni, coredns, and kube-proxy are managed as EKS-managed add-ons so their
# lifecycle and version are declared in code rather than drifting. The VPC CNI
# and EBS CSI driver run with their own IRSA roles (least privilege) instead of
# borrowing the node instance role.
#
# resolve_conflicts_on_* = OVERWRITE means Terraform is the source of truth and
# will reconcile any manual changes back to the declared state.
###############################################################################

# --- IRSA role for the VPC CNI ----------------------------------------------
data "aws_iam_policy_document" "vpc_cni_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:kube-system:aws-node"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpc_cni" {
  name               = "${var.cluster_name}-vpc-cni"
  assume_role_policy = data.aws_iam_policy_document.vpc_cni_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# --- IRSA role for the EBS CSI driver ---------------------------------------
data "aws_iam_policy_document" "ebs_csi_assume_role" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  name               = "${var.cluster_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role[0].json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# --- Add-ons ----------------------------------------------------------------
# kube-proxy and CoreDNS first; they have no special IAM requirements.
resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "kube-proxy"
  addon_version = lookup(var.addon_versions, "kube-proxy", null)

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "coredns"
  addon_version = lookup(var.addon_versions, "coredns", null)

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # CoreDNS schedules on worker nodes, so wait for at least one node group.
  depends_on = [aws_eks_node_group.this]

  tags = local.common_tags
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "vpc-cni"
  addon_version            = lookup(var.addon_versions, "vpc-cni", null)
  service_account_role_arn = aws_iam_role.vpc_cni.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags
}

resource "aws_eks_addon" "ebs_csi" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = lookup(var.addon_versions, "aws-ebs-csi-driver", null)
  service_account_role_arn = aws_iam_role.ebs_csi[0].arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]

  tags = local.common_tags
}
