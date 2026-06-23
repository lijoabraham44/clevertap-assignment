# VPC Module

A reusable, region-agnostic VPC module designed to be instantiated **identically across regions**. A single set of inputs (`name`, `cidr_block`, `azs`) produces a deterministic three-tier subnet layout, so `us-east-1`, `ap-south-1`, and `eu-west-1` all share the same topology and only differ by non-overlapping CIDR.

## What it creates

| Tier | Purpose | Internet route | Typical workloads |
|------|---------|----------------|-------------------|
| **public** | Ingress / NAT | IGW (`0.0.0.0/0`) | ALB/NLB, NAT gateways |
| **private** | Application | Per-AZ NAT gateway | EKS nodes & pods |
| **intra** | Database / isolated | **None** | RDS, ElastiCache, internal-only services |

Also provisions:

- **Internet Gateway** + public route table.
- **NAT gateways** — one per AZ in production (`single_nat_gateway = false`) for AZ-fault isolation, or a single shared NAT in non-prod for cost savings.
- **VPC Flow Logs → S3** in Parquet with Hive partitioning, KMS encryption, TLS-only bucket policy, and tiered lifecycle (Standard → Standard-IA → Glacier IR → expire).
- **EKS subnet discovery tags** (`kubernetes.io/role/elb`, `internal-elb`, and `kubernetes.io/cluster/<name>=shared`) when `eks_cluster_names` is set.

## Subnet addressing

Subnets are carved with `cidrsubnet()` so the layout is predictable and collision-free. With the defaults (`newbits = 4`) and 3 AZs on a `/16`:

```
public  -> /20 x3   (index 0,1,2)
private -> /20 x3   (index 3,4,5)
intra   -> /20 x3   (index 6,7,8)
```

## Design decisions

- **Direct-to-S3 flow logs** instead of CloudWatch Logs: at 30B events/day the CloudWatch ingestion cost is prohibitive; S3 + Athena is an order of magnitude cheaper and Parquet/Hive partitioning keeps scans fast.
- **Per-AZ NAT in prod**: avoids a single NAT becoming an AZ-wide blast radius and removes cross-AZ data-processing charges for egress.
- **Non-overlapping CIDRs are the caller's responsibility**: required so Transit Gateway can route between regions without NAT.

## Usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name       = "clevertap-prod-use1"
  cidr_block = "10.10.0.0/16"
  azs        = ["us-east-1a", "us-east-1b", "us-east-1c"]

  single_nat_gateway = false
  enable_flow_logs   = true
  eks_cluster_names  = ["clevertap-prod-use1"]

  tags = {
    Environment = "prod"
    Region      = "us-east-1"
  }
}
```

See `variables.tf` for the full input reference and `outputs.tf` for exported values.
