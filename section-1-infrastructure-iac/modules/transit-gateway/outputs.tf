output "transit_gateway_id" {
  description = "ID of the Transit Gateway."
  value       = aws_ec2_transit_gateway.this.id
}

output "transit_gateway_arn" {
  description = "ARN of the Transit Gateway (needed to create a cross-region peering attachment)."
  value       = aws_ec2_transit_gateway.this.arn
}

output "vpc_attachment_id" {
  description = "ID of the VPC attachment."
  value       = aws_ec2_transit_gateway_vpc_attachment.this.id
}

output "association_default_route_table_id" {
  description = "Default association route table of the TGW (used to wire up peering routes)."
  value       = aws_ec2_transit_gateway.this.association_default_route_table_id
}
