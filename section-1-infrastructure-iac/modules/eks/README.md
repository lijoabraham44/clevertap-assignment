# EKS Module

A reusable, opinionated, security-hardened EKS cluster module. Designed to be instantiated identically per region so every cluster in the fleet is standardized (directly addressing the "clusters are not standardized — each was provisioned differently" problem).

## Features

- **Private API server endpoint** by default (`endpoint_public_access = false`). The control plane is only reachable from inside the VPC / over VPN; a tightly-scoped public endpoint is opt-in via `endpoint_public_access_cidrs`.
- **IRSA** — registers the cluster OIDC provider and mints least-privilege IAM roles scoped to a single `namespace:serviceaccount` via the OIDC `sub` claim. No static keys, no node-role credential sharing.
- **Mixed On-Demand + Spot node groups** with a clear eviction strategy (see below).
- **Terraform-managed add-ons**: `vpc-cni` (with its own IRSA role), `coredns`, `kube-proxy`, and optionally `aws-ebs-csi-driver`. `resolve_conflicts_on_*=OVERWRITE` makes Terraform the source of truth and reconciles manual drift.
- **Secrets envelope encryption** with a dedicated, auto-rotating KMS key.
- **Control plane audit logging** (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`) to CloudWatch.
- **SSM-based node access** (no SSH keys/bastion) via `AmazonSSMManagedInstanceCore`.
- **API access mode** (`API_AND_CONFIG_MAP`) so cluster access is managed in IaC.

## Capacity & eviction strategy

| Concern | How it's handled |
|---------|------------------|
| Critical workloads | `ON_DEMAND` node group, untainted |
| Stateless/burst workloads | `SPOT` node group with **multiple instance types** to widen the capacity pool and lower interruption rate; tainted + labelled so only tolerant pods schedule there |
| Spot interruption | AWS Node Termination Handler (deployed as a workload) drains on the 2-min warning |
| Availability during scale-in | Workload `PodDisruptionBudgets` |
| Rolling upgrades | `update_config.max_unavailable_percentage = 33` bounds blast radius |
| Autoscaler ownership | `desired_size` is in `ignore_changes` so the autoscaler isn't fought by Terraform |

## Usage

```hcl
module "eks" {
  source = "../../modules/eks"

  cluster_name       = "clevertap-prod-use1"
  kubernetes_version = "1.30"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids

  endpoint_public_access = false # private-only API server

  node_groups = {
    system = {
      capacity_type  = "ON_DEMAND"
      instance_types = ["m6i.large"]
      desired_size   = 3
      min_size       = 3
      max_size       = 6
    }
    spot = {
      capacity_type  = "SPOT"
      instance_types = ["m6i.large", "m6a.large", "m5.large", "m5a.large"]
      desired_size   = 4
      min_size       = 2
      max_size       = 30
      labels         = { workload = "burstable" }
      taints = [{
        key    = "spot"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }
  }

  irsa_roles = {
    external-secrets = {
      namespace       = "external-secrets"
      service_account = "external-secrets"
      policy_arns     = ["arn:aws:iam::aws:policy/SecretsManagerReadWrite"]
    }
  }

  tags = { Environment = "prod", Region = "us-east-1" }
}
```

See `variables.tf` for the full input reference and `outputs.tf` for exported values.
