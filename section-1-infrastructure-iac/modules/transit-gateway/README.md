# Transit Gateway Module

Creates a per-region **AWS Transit Gateway (TGW)**, attaches a VPC to it, and injects routes from the VPC's route tables toward remote-region CIDRs.

## Why Transit Gateway over VPC Peering?

> The assignment asks to "justify your choice." Here it is.

| Criterion | VPC Peering | **Transit Gateway (chosen)** |
|-----------|-------------|------------------------------|
| Topology | Full mesh — `N(N-1)/2` connections | Hub-and-spoke — `N` attachments |
| Transitive routing | ❌ Not supported (A↔B, B↔C does **not** give A↔C) | ✅ Native |
| Scaling to many VPCs/regions/accounts | Connection count explodes; route tables become unmanageable | Add one attachment per new VPC |
| Centralized control / inspection | Hard | Easy (central route tables, optional inspection VPC) |
| Cross-region | Supported | Supported via inter-region **TGW peering** |
| Cost | No hourly TGW fee, but operational cost grows fast | Hourly attachment + data processing fee |

For a **multi-region, multi-account, multi-VPC** platform that is actively expanding (now into the EU), the operational simplicity and transitive routing of TGW outweigh its per-GB cost. VPC peering would require a new connection and route entries on *every* existing VPC each time a region/VPC is added — exactly the kind of click-ops sprawl this initiative is trying to kill.

> Note on data residency: for the EU region we deliberately do **not** peer the EU TGW into the global mesh for data-plane traffic. See `docs/1c-eu-data-residency.md`.

## Cross-region peering (wired at the `live/` layer)

This module creates the regional TGW. To connect two regions you create a peering attachment between their TGWs (requires provider aliases for each region):

```hcl
# Requester side (us-east-1)
resource "aws_ec2_transit_gateway_peering_attachment" "use1_to_aps1" {
  provider                = aws.use1
  transit_gateway_id      = module.tgw_use1.transit_gateway_id
  peer_transit_gateway_id = module.tgw_aps1.transit_gateway_id
  peer_region             = "ap-south-1"
  tags                    = { Name = "use1-to-aps1" }
}

# Accepter side (ap-south-1)
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "aps1" {
  provider                      = aws.aps1
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.use1_to_aps1.id
}
```

Then add TGW route-table routes pointing each region's remote CIDR at the peering attachment. Because every VPC CIDR in the fleet is **non-overlapping** (enforced by the `vpc` module convention), this routing is unambiguous.
