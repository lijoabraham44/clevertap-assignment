variable "name" {
  description = "Name prefix for all VPC resources (e.g. \"clevertap-prod-use1\")."
  type        = string
}

variable "cidr_block" {
  description = "Primary IPv4 CIDR block for the VPC. Must be unique and non-overlapping across all regions to allow Transit Gateway routing."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR (e.g. 10.0.0.0/16)."
  }
}

variable "azs" {
  description = "List of Availability Zones to spread subnets across. Provide >= 3 for production HA."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least two Availability Zones are required for high availability."
  }
}

variable "public_subnet_newbits" {
  description = "Number of additional subnet bits for public subnets (added to the VPC prefix length via cidrsubnet)."
  type        = number
  default     = 4
}

variable "private_subnet_newbits" {
  description = "Number of additional subnet bits for private (application) subnets."
  type        = number
  default     = 4
}

variable "intra_subnet_newbits" {
  description = "Number of additional subnet bits for intra (database/isolated) subnets."
  type        = number
  default     = 4
}

variable "single_nat_gateway" {
  description = "If true, route all private subnets through a single NAT gateway (cost saving for non-prod). If false, one NAT gateway per AZ (recommended for prod)."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Whether to enable VPC Flow Logs shipped to S3."
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Number of days to retain VPC Flow Log objects in S3 before expiration."
  type        = number
  default     = 365
}

variable "flow_logs_transition_ia_days" {
  description = "Days after which flow log objects transition to S3 Standard-IA."
  type        = number
  default     = 30
}

variable "flow_logs_transition_glacier_days" {
  description = "Days after which flow log objects transition to Glacier Instant Retrieval."
  type        = number
  default     = 90
}

variable "flow_logs_traffic_type" {
  description = "Type of traffic to capture in flow logs (ACCEPT, REJECT, or ALL)."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs_traffic_type)
    error_message = "flow_logs_traffic_type must be one of ACCEPT, REJECT, ALL."
  }
}

variable "eks_cluster_names" {
  description = "EKS cluster names that will use this VPC. Used to add the shared kubernetes.io/cluster/<name> subnet tags required for ELB auto-discovery. Leave empty if no EKS clusters use this VPC."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}
