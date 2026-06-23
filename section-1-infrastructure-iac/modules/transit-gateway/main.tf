###############################################################################
# Transit Gateway (per region)
#
# Each region gets its own Transit Gateway with a VPC attachment. Inter-region
# connectivity is achieved by peering the regional TGWs (see live/ layer and the
# README), which scales far better than a full mesh of VPC peering connections.
###############################################################################

locals {
  common_tags = merge(
    {
      "ManagedBy" = "terraform"
      "Module"    = "transit-gateway"
    },
    var.tags,
  )
}

resource "aws_ec2_transit_gateway" "this" {
  description                     = "${var.name} transit gateway"
  amazon_side_asn                 = var.amazon_side_asn
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(local.common_tags, { Name = var.name })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = var.vpc_id
  subnet_ids         = var.attachment_subnet_ids

  dns_support                                     = "enable"
  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true

  tags = merge(local.common_tags, { Name = "${var.name}-vpc-attachment" })
}

# Routes from VPC subnets toward remote-region CIDRs via the TGW.
# Cartesian product of (route tables) x (remote CIDRs).
locals {
  routes = {
    for pair in setproduct(var.route_table_ids, var.remote_cidr_blocks) :
    "${pair[0]}::${pair[1]}" => {
      route_table_id = pair[0]
      cidr_block     = pair[1]
    }
  }
}

resource "aws_route" "to_tgw" {
  for_each = local.routes

  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}
