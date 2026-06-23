variable "cluster_name" {
  description = "Name of the EKS cluster. Must be unique per region/account."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes control plane version."
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "VPC the cluster is deployed into."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the EKS control plane ENIs and node groups. Use private subnets."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS requires subnets in at least two Availability Zones."
  }
}

variable "endpoint_public_access" {
  description = "Whether the EKS API server has a public endpoint. Default false enforces a private-only API server."
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint when endpoint_public_access is true (e.g. corporate egress / VPN). Ignored when private-only."
  type        = list(string)
  default     = []
}

variable "cluster_log_types" {
  description = "Control plane log types to ship to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_log_retention_days" {
  description = "Retention period for control plane CloudWatch log group."
  type        = number
  default     = 90
}

variable "kms_deletion_window_days" {
  description = "Deletion window for the KMS key used for envelope encryption of Kubernetes secrets."
  type        = number
  default     = 30
}

variable "node_groups" {
  description = <<-EOT
    Map of managed node group definitions. Each entry supports a mixed
    On-Demand + Spot capacity strategy and a clear eviction posture.

    Keys:
      capacity_type            - "ON_DEMAND" or "SPOT".
      instance_types           - list of instance types (multiple recommended for Spot to widen the pool).
      desired_size/min_size/max_size - autoscaling bounds.
      disk_size                - root EBS size in GiB.
      ami_type                 - e.g. "AL2023_x86_64_STANDARD" / "BOTTLEROCKET_x86_64".
      labels                   - Kubernetes node labels.
      taints                   - list of { key, value, effect } taints.
  EOT

  type = map(object({
    capacity_type  = optional(string, "ON_DEMAND")
    instance_types = list(string)
    desired_size   = number
    min_size       = number
    max_size       = number
    disk_size      = optional(number, 50)
    ami_type       = optional(string, "AL2023_x86_64_STANDARD")
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))

  default = {}
}

variable "addon_versions" {
  description = "Optional explicit add-on versions keyed by add-on name (vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver). When unset, the latest compatible version is resolved automatically."
  type        = map(string)
  default     = {}
}

variable "enable_ebs_csi_driver" {
  description = "Whether to install the AWS EBS CSI driver add-on (with its own IRSA role)."
  type        = bool
  default     = true
}

variable "irsa_roles" {
  description = <<-EOT
    Map of IRSA (IAM Roles for Service Accounts) roles to create. Each role is
    scoped to a specific namespace/service-account via the OIDC trust policy.

    Keys:
      namespace            - Kubernetes namespace of the service account.
      service_account      - service account name.
      policy_arns          - list of managed/customer IAM policy ARNs to attach.
  EOT

  type = map(object({
    namespace       = string
    service_account = string
    policy_arns     = list(string)
  }))

  default = {}
}

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}
