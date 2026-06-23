###############################################################################
# Managed node groups (mixed On-Demand + Spot)
#
# Capacity strategy
# -----------------
# Two distinct managed node groups are typically passed in by the caller:
#   * an ON_DEMAND group for stateful / non-interruptible critical workloads,
#   * a SPOT group (with several instance types to widen the capacity pool and
#     reduce interruption frequency) for stateless, fault-tolerant workloads.
#
# Eviction strategy
# -----------------
# 1. Spot interruptions: the AWS Node Termination Handler (deployed as a
#    workload, out of scope of IaC) drains nodes on the 2-minute Spot warning.
# 2. Scheduling: Spot nodes carry a taint + label so only workloads that
#    explicitly tolerate Spot land there; critical pods stay on On-Demand.
# 3. Disruption budgets: workloads define PodDisruptionBudgets so Cluster
#    Autoscaler / Karpenter respect minimum availability during scale-in.
# 4. update_config.max_unavailable_percentage bounds blast radius during
#    rolling AMI/version upgrades.
###############################################################################

# --- Node IAM role (shared by all groups) -----------------------------------
data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    # Required for SSM Session Manager access (no SSH keys / bastion needed).
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# --- Managed node groups ----------------------------------------------------
resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-${each.key}"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  version         = var.kubernetes_version

  capacity_type  = each.value.capacity_type
  instance_types = each.value.instance_types
  ami_type       = each.value.ami_type
  disk_size      = each.value.disk_size

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  update_config {
    max_unavailable_percentage = 33
  }

  labels = merge(
    each.value.labels,
    { "capacity-type" = lower(each.value.capacity_type) },
  )

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(local.common_tags, { Name = "${var.cluster_name}-${each.key}" })

  lifecycle {
    # desired_size is owned by the autoscaler at runtime; don't fight it.
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}
