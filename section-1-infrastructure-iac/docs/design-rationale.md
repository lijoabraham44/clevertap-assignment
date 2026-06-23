# Section 1 — Design Rationale (Why this approach)

This document explains **why** the Section 1 code is built the way it is. It is written as a set of lightweight ADRs (Architecture Decision Records): each records the context, the decision, the alternatives considered, and the trade-offs. The goal is that a reviewer can understand not just *what* the Terraform does, but *why* each choice was made against CleverTap's reality (40B+ events/day, multi-tenant, 10–50x spikes, inherited drift and click-ops, $420K bill).

---

## ADR-01: Terraform (HCL) as the IaC tool

**Context.** The inherited estate is ~60% CDK and ~40% click-ops, provisioned inconsistently over time. We need a single, standardized, auditable tool.

**Decision.** Standardize on **Terraform** with reusable modules.

**Why over the alternatives:**
- **vs. CDK (current partial state):** CDK generates CloudFormation, which has slow stack operations, 500-resource/stack limits that bite at multi-region scale, painful drift handling, and couples infra logic to a programming language runtime. Terraform's `plan` is a first-class, reviewable diff — essential for the drift problem that caused two P0s.
- **vs. raw CloudFormation:** no first-class modules/registry, weaker multi-account/multi-region ergonomics, no provider ecosystem beyond AWS.
- **vs. Pulumi:** great tool, but Terraform/HCL has the larger talent pool and ecosystem (modules, `tfsec`, OPA, Atlantis/Spacelift), reducing onboarding friction for a platform many teams contribute to.

**Trade-off.** We must migrate existing CDK over time (via `import`/refactor). Accepted: standardization and drift-control outweigh migration cost.

---

## ADR-02: Module + `live/` (environments) separation

**Context.** Many teams contribute; clusters today are snowflakes.

**Decision.** Reusable, versioned **`modules/`** (the "how") consumed by thin **`live/<env>/<region>/`** roots (the "where/what"). The two regional `main.tf` files are intentionally near-identical — only `locals` differ.

**Why.** This is what makes the fleet *standardized and reproducible*: every cluster comes from the same audited module, so "each was provisioned differently" can't recur. Thin roots keep environment config obvious and reviewable; versioned module refs (`?ref=vX.Y.Z`) make upgrades explicit and gradual (canary one region first).

**Alternative rejected.** A single mega-root with workspaces — couples regions/accounts into one state, large blast radius, slow plans. (See ADR-07.)

---

## ADR-03: Private-only EKS API server by default

**Context.** Multi-tenant SaaS handling customer data; security is evaluated explicitly.

**Decision.** `endpoint_public_access = false` by default; public access is opt-in and CIDR-restricted.

**Why.** Removes the API server from the public internet entirely — the control plane is reachable only from inside the VPC or over VPN/Direct Connect. This is the single highest-leverage hardening for an EKS fleet. Public access remains *possible* (some orgs need it for SaaS CI) but must be a conscious, narrow decision.

**Trade-off.** Operators/CI need network reachability (VPN, peered runner subnet, or TGW). Accepted — encoded as a documented assumption.

---

## ADR-04: IRSA for all workload identity (no node-role sharing, no static keys)

**Decision.** Register the cluster OIDC provider and mint IAM roles scoped to a single `namespace:serviceaccount` via the OIDC `sub` condition.

**Why.** The alternative — attaching broad policies to the shared **node instance role** — means *every* pod on a node inherits those permissions (privilege escalation by co-tenancy), which is unacceptable in a multi-tenant platform. Static IAM keys in secrets are worse (rotation, leakage). IRSA gives per-workload least privilege with short-lived, auto-rotated credentials and a clean audit trail.

---

## ADR-05: Mixed On-Demand + Spot node groups with an explicit eviction strategy

**Context.** Traffic spikes 10–50x within minutes; Finance wants 25–30% cost reduction without SLA impact.

**Decision.** Separate **On-Demand** group (critical/stateful, untainted) and **Spot** group (stateless/burst, tainted + labelled, multiple instance types).

**Why.**
- Spot is ~60–90% cheaper — directly serves the cost mandate, and burst traffic is exactly the fault-tolerant workload Spot suits.
- **Multiple instance types** per Spot group widens the capacity pool, lowering interruption frequency and improving the odds of fulfilling a 50x scale-out.
- Taints/labels ensure only Spot-tolerant pods land there, so an interruption can never take down a critical singleton.
- Eviction is handled in depth: Node Termination Handler drains on the 2-min Spot signal, PodDisruptionBudgets protect availability during scale-in, and `max_unavailable_percentage` bounds upgrade blast radius. `desired_size` is left to the autoscaler (`ignore_changes`) so Terraform and the autoscaler don't fight.

**Trade-off.** Spot can be reclaimed; mitigated by the above and by keeping the On-Demand baseline sized for the floor of demand. Reserved/Savings Plans for that baseline is a Section 4 concern.

---

## ADR-06: Transit Gateway for inter-region/inter-VPC connectivity

**Decision.** Per-region TGW with cross-region peering, rather than a VPC-peering mesh.

**Why.** Peering is non-transitive and grows as `N(N-1)/2`; with multiple VPCs/regions/accounts and active EU expansion, that becomes unmanageable click-ops sprawl. TGW is hub-and-spoke (`N` attachments), supports transitive routing, and centralizes route control. Non-overlapping CIDRs (a module convention) make routing unambiguous. Full table in `modules/transit-gateway/README.md`.

**Trade-off.** TGW has per-attachment + per-GB data-processing cost. Accepted for operational scalability; and for EU we deliberately *don't* peer the data plane (see `docs/1c`).

---

## ADR-07: State isolated per (account × region × stack), S3 + DynamoDB backend

**Decision.** One state object per account/region/stack; remote state in S3 (versioned, KMS, TLS-only) with DynamoDB locking; bootstrap stack creates the backend per account.

**Why.** Small blast radius, fast plans, and safe parallel work across teams — directly addresses "multiple teams contributing." A drift or lock in one stack can't block another. State lives in the same account as its resources, so prod credentials never touch dev. Full reasoning in `docs/1b`.

---

## ADR-08: VPC Flow Logs to S3 (Parquet/Hive) with lifecycle tiering — not CloudWatch

**Decision.** Ship flow logs straight to an encrypted S3 bucket in Parquet with Hive partitioning and a Standard → IA → Glacier IR → expire lifecycle.

**Why.** At 40B+ events/day, CloudWatch Logs ingestion for flow logs is prohibitively expensive. S3 + Athena is an order of magnitude cheaper, Parquet/partitioning keeps queries fast, and lifecycle tiering controls long-term cost while preserving an auditable network record. This is both a security control (auditability) and a cost-conscious one — consistent with the platform's two themes.

---

## ADR-09: Three-tier subnets with deterministic CIDR math

**Decision.** Public / private / **intra (DB, no internet route)** subnets carved via `cidrsubnet()`; per-AZ NAT in prod.

**Why.** Deterministic math means the layout is identical and collision-free in every region (reproducibility). The intra tier with no egress is the correct home for RDS/ElastiCache (defense in depth). Per-AZ NAT in prod removes a single NAT as an AZ-wide blast radius and avoids cross-AZ egress data-processing charges; `single_nat_gateway` is offered for non-prod cost savings.

---

## ADR-10: Defaults are secure; security is not optional

Cross-cutting decision reflected throughout: KMS encryption + rotation (EKS secrets, flow-log and state buckets), public-access-block + TLS-only bucket policies, SSM-only node access (no SSH/bastion), control-plane audit logging on by default, and `OVERWRITE` add-on reconciliation so Terraform is the source of truth. The rationale is that a platform team sets the floor — teams consuming the modules inherit a secure baseline rather than having to remember to opt in.

---

### Summary mapping (decision → problem it solves)

| Decision | Problem from the brief it addresses |
|----------|-------------------------------------|
| Terraform + modules + `live/` | "clusters not standardized", "40% click-ops" |
| Private endpoint, IRSA, KMS, audit logs | "secure", multi-tenant hardening |
| Spot + autoscaling node groups | 10–50x spikes, 25–30% cost reduction |
| Transit Gateway | multi-region today, EU expansion next |
| State isolation + drift tooling (1b) | "two P0s from config drift", many teams |
| Flow logs → S3, lifecycle, per-AZ NAT trade-offs | auditable + cost-aware |
