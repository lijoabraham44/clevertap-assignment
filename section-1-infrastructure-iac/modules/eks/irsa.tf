###############################################################################
# IRSA — IAM Roles for Service Accounts
#
# 1. Register the cluster's OIDC issuer as an IAM OIDC provider.
# 2. For each entry in var.irsa_roles, mint a least-privilege IAM role whose
#    trust policy is scoped to a single namespace/service-account pair via the
#    OIDC "sub" claim. Workloads assume these roles by annotating their service
#    account with the role ARN — no node-level credentials, no static keys.
###############################################################################

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = local.common_tags
}

locals {
  oidc_provider_arn  = aws_iam_openid_connect_provider.this.arn
  oidc_provider_host = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

# Trust policy per IRSA role, restricted to the exact service account.
data "aws_iam_policy_document" "irsa_assume_role" {
  for_each = var.irsa_roles

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
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = var.irsa_roles

  name               = "${var.cluster_name}-irsa-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume_role[each.key].json

  tags = merge(local.common_tags, {
    "irsa/namespace"       = each.value.namespace
    "irsa/service-account" = each.value.service_account
  })
}

# Flatten { role => [policy_arns] } into individual attachments.
locals {
  irsa_policy_attachments = merge([
    for role_key, role in var.irsa_roles : {
      for policy_arn in role.policy_arns :
      "${role_key}::${policy_arn}" => {
        role_key   = role_key
        policy_arn = policy_arn
      }
    }
  ]...)
}

resource "aws_iam_role_policy_attachment" "irsa" {
  for_each = local.irsa_policy_attachments

  role       = aws_iam_role.irsa[each.value.role_key].name
  policy_arn = each.value.policy_arn
}
