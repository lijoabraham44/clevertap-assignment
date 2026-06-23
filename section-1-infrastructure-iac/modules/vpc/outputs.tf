output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "Primary CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private (application) subnets — use these for EKS node groups and pods."
  value       = aws_subnet.private[*].id
}

output "intra_subnet_ids" {
  description = "IDs of the intra (database/isolated) subnets — use these for RDS/ElastiCache subnet groups."
  value       = aws_subnet.intra[*].id
}

output "private_route_table_ids" {
  description = "IDs of the private route tables (for adding TGW/peering routes)."
  value       = aws_route_table.private[*].id
}

output "intra_route_table_id" {
  description = "ID of the intra route table (for adding TGW/peering routes)."
  value       = aws_route_table.intra.id
}

output "nat_gateway_public_ips" {
  description = "Public IPs of the NAT gateways (useful for downstream IP allow-listing)."
  value       = aws_eip.nat[*].public_ip
}

output "availability_zones" {
  description = "Availability Zones the subnets are spread across."
  value       = var.azs
}

output "flow_logs_bucket_arn" {
  description = "ARN of the S3 bucket receiving VPC Flow Logs (null when disabled)."
  value       = var.enable_flow_logs ? aws_s3_bucket.flow_logs[0].arn : null
}
