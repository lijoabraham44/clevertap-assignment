# Section 1 — Infrastructure Architecture & IaC

Implementation for **Section 1** of the CleverTap Staff DevOps assessment: standardize and harden the multi-region EKS infrastructure so it is **reproducible, auditable, and secure**.

The deliverable is production-grade **Terraform** (reusable modules + composed environments) plus the two written design answers (1b, 1c).

## Repository layout

```
section-1-infrastructure-iac/
├── modules/
│   ├── vpc/                 # 1a: reusable multi-region VPC (public/private/intra, flow logs->S3)
│   ├── eks/                 # 1a: reusable EKS (private endpoint, IRSA, On-Demand+Spot, TF add-ons)
│   └── transit-gateway/     # 1a: per-region TGW + cross-region peering (justified vs VPC peering)
├── live/
│   ├── bootstrap/           # per-account S3 state bucket + DynamoDB lock table
│   └── prod/
│       ├── us-east-1/       # composed prod stack
│       └── ap-south-1/      # identical module calls, different locals -> standardized fleet
└── docs/
    ├── design-rationale.md                # WHY each design choice was made (ADR-style)
    ├── 1b-state-and-drift-management.md   # 1b: state structure + drift detection/remediation
    └── 1c-eu-data-residency.md            # 1c: EU data residency w/ single control plane
```

> **Why this approach?** See [`docs/design-rationale.md`](docs/design-rationale.md) for the
> ADR-style record of every major decision (Terraform vs CDK, private endpoint, IRSA,
> Spot strategy, Transit Gateway, state isolation, flow-logs-to-S3, …) with the
> alternatives considered and trade-offs.

## How this maps to the task

### 1a. Module design (implementation)

**Reusable EKS cluster module** — [`modules/eks/`](modules/eks/README.md)
- ✅ **Private API server endpoint** (`endpoint_public_access = false` by default).
- ✅ **IRSA** — OIDC provider + least-privilege roles scoped to a single `namespace:serviceaccount`.
- ✅ **Mixed On-Demand + Spot** node groups with a documented **eviction strategy** (taints/labels, NTH drain on Spot warning, PDBs, bounded `max_unavailable`).
- ✅ **Add-ons managed via Terraform** — `vpc-cni` (own IRSA role), `coredns`, `kube-proxy`, `aws-ebs-csi-driver`, with `OVERWRITE` so Terraform is the source of truth.
- Plus: secrets envelope encryption (KMS, rotation on), control-plane audit logging, SSM node access (no SSH).

**Multi-region VPC module** — [`modules/vpc/`](modules/vpc/README.md)
- ✅ **Public, private, and intra (database) subnets**, deterministically carved so every region is identical.
- ✅ **Transit Gateway** for inter-region connectivity — **justification** in [`modules/transit-gateway/README.md`](modules/transit-gateway/README.md) (transitive routing + hub-and-spoke scaling vs. an `N²` peering mesh).
- ✅ **VPC Flow Logs → S3** (Parquet + Hive partitions, KMS, TLS-only) with **lifecycle policies** (Standard → IA → Glacier IR → expire).

### 1b. State & drift management (design)
See [`docs/1b-state-and-drift-management.md`](docs/1b-state-and-drift-management.md) — state structure across accounts/regions/teams, plus drift detection tooling and remediation workflow. The `live/` layout implements it.

### 1c. EU data residency (design)
See [`docs/1c-eu-data-residency.md`](docs/1c-eu-data-residency.md) — cluster isolation vs federation, IAM boundary enforcement (SCPs, permission boundaries, KMS), and CI/CD enforcement of the residency constraint.

## Security highlights

- Private-only EKS API server; nodes reachable only via SSM (no SSH, no bastion).
- IRSA everywhere — no static credentials, no node-role credential sharing.
- KMS encryption for EKS secrets, flow-log bucket, and state bucket; key rotation enabled.
- S3 buckets: public access blocked, TLS-only bucket policy, versioned.
- `default_route_table` + intra subnets have **no internet route** for data tiers.

## Validate locally

```bash
# format check + static validation for every module and root
terraform fmt -recursive -check
cd modules/vpc            && terraform init -backend=false && terraform validate
cd ../eks                 && terraform init -backend=false && terraform validate
cd ../transit-gateway     && terraform init -backend=false && terraform validate
```

> `terraform validate` on the `live/` roots requires the remote backend + AWS
> credentials; use `terraform plan` against a sandbox account there. Backend
> bucket names / account IDs in `live/**/backend.tf` are placeholders.

## Assumptions

- AWS Organizations with one account per environment (`dev`/`staging`/`prod`) and a separate `prod-eu` account for residency.
- Workload-level controllers (Cluster Autoscaler/Karpenter, AWS Node Termination Handler, External Secrets Operator, AWS Load Balancer Controller) are deployed on top via GitOps — the IAM/IRSA hooks for them are provisioned here; their Helm releases belong to Section 3's delivery layer.
- Kubernetes `1.30`; provider AWS `>= 5.40`, Terraform `>= 1.6`.
