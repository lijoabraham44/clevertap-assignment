variable "name" {
  description = "Name prefix for the Transit Gateway and its attachment (e.g. \"clevertap-prod-use1\")."
  type        = string
}

variable "amazon_side_asn" {
  description = "Private ASN for the Amazon side of the TGW BGP session. Must be unique per region to allow inter-region peering."
  type        = number
  default     = 64512
}

variable "vpc_id" {
  description = "VPC to attach to the Transit Gateway."
  type        = string
}

variable "attachment_subnet_ids" {
  description = "Subnet IDs (one per AZ, typically the intra/private subnets) used for the TGW VPC attachment ENIs."
  type        = list(string)
}

variable "route_table_ids" {
  description = "Route table IDs that should receive routes toward remote-region CIDRs via the TGW."
  type        = list(string)
  default     = []
}

variable "remote_cidr_blocks" {
  description = "List of remote-region VPC CIDR blocks to route toward this TGW (added to every route table in route_table_ids)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}
