# 4a. 90-Day Cost Reduction Plan

**Goal:** cut the $420K/month bill by **25–30% ($105–126K/month)** with **no SLA impact**.

> **Why this sequencing** (waste → right-size → commit → re-architect) is in [`design-rationale.md`](design-rationale.md). This document is the plan with per-initiative savings, effort, and reliability risk.

## Assumed cost breakdown (validated in Week 1 via CUR)

No reliable per-service split exists today, so the plan opens by enabling cost allocation tags + CUR. Working assumption based on the stated workload profile:

| Service | % of bill | $/month |
|---------|-----------|---------|
| EC2 / EKS compute | 45% | $189K |
| RDS | 18% | $75.6K |
| Data transfer (inter-region + NAT) | 12% | $50.4K |
| ElastiCache | 8% | $33.6K |
| S3 | 7% | $29.4K |
| Other (EBS, ELB, CloudWatch, etc.) | 10% | $42K |
| **Total** | **100%** | **$420K** |

Percentages below are expressed against the **total bill** and are stated **net of overlap** (e.g. Spot savings are counted on capacity *after* right-sizing) so the column sums honestly.

---

## Phase 1 — Quick wins (Week 1–2)  ·  net ≈ 6%

Immediately actionable, low-risk, no architecture change.

| # | Initiative | Est. savings | Effort | Risk | Notes |
|---|-----------|-------------|--------|------|-------|
| 1 | Enable cost allocation tags + CUR/Athena + Cost Explorer/Kubecost | enabler (0%) | Low | Low | Prereq for everything; makes savings provable |
| 2 | Delete waste: unattached EBS, old/orphaned snapshots & AMIs, idle EIPs, idle ELBs, zombie RDS/test DBs | ~2% ($8.4K) | Low | Low | Use Trusted Advisor / Compute Optimizer findings |
| 3 | Schedule non-prod off-hours (stop dev/staging nights+weekends) | ~2% ($8.4K) | Low | Low | ~70% uptime cut on non-prod EC2/RDS; zero prod impact |
| 4 | S3 lifecycle + Intelligent-Tiering + abort incomplete multipart uploads | ~1% ($4.2K) | Low | Low | Tier cold data to IA/Glacier; expire logs |
| 5 | EBS `gp2 → gp3` migration + CloudWatch log retention/Flow-Logs-to-S3 | ~1% ($4.2K) | Low | Low | gp3 is ~20% cheaper with better baseline perf |

**Phase 1 subtotal: ~6% (~$25K/mo).**

---

## Phase 2 — Medium-term (Month 1–2)  ·  net ≈ 16%

Right-size first, then commit. This phase carries the largest savings.

| # | Initiative | Est. savings | Effort | Risk | Notes |
|---|-----------|-------------|--------|------|-------|
| 6 | **Right-size EKS**: tune pod requests/limits, bin-pack, enable Karpenter/Cluster Autoscaler consolidation; right-size RDS/ElastiCache per Compute Optimizer | ~5% ($21K) | Medium | Medium | Validate against SLOs (Section 2) before/after; do gradually |
| 7 | **Spot for stateless/burst** EKS workloads (Section 1 node strategy: multi-instance Spot pool + NTH + PDBs) | ~5% ($21K) | Medium | Medium | Keep On-Demand floor for critical/stateful; Spot ~70% cheaper |
| 8 | **Compute Savings Plans** on the right-sized On-Demand baseline (1-yr no-upfront first) | ~4% ($17K) | Low | Low | Flexible across family/region; covers EKS/Fargate/Lambda |
| 9 | **RDS + ElastiCache Reserved Instances** on stable, right-sized nodes | ~2% ($8.4K) | Low | Low | No Savings Plan for these engines → RIs are the vehicle |

**Phase 2 subtotal: ~16% (~$67K/mo).**

> Sequencing within the phase: **#6 right-size → #7 Spot → then #8/#9 commit.** Buying commitments before right-sizing would lock in waste (see rationale ADR-02).

---

## Phase 3 — Architectural (Month 2–3)  ·  net ≈ 6%

Structural redesigns that unlock durable savings (and often better latency).

| # | Initiative | Est. savings | Effort | Risk | Notes |
|---|-----------|-------------|--------|------|-------|
| 10 | **Cut inter-region data transfer**: VPC Gateway/Interface Endpoints (bypass NAT $/GB), compress + batch cross-region payloads, cache, colocate chatty services, prefer in-region reads | ~3% ($12.6K) | High | Medium | Biggest "hidden" line item; validate no data-residency break |
| 11 | **Graviton (arm64) migration** for EKS nodes + RDS/ElastiCache where supported | ~2% ($8.4K) | Medium | Medium | ~20% better price/perf; needs multi-arch images (Section 3 build) |
| 12 | **Storage/data tiering**: Kafka tiered storage, log/data lifecycle to S3 + Glacier, dedup | ~1% ($4.2K) | High | Medium | Reduces hot-storage footprint |

**Phase 3 subtotal: ~6% (~$25K/mo).**

---

## Total

| Phase | Net savings | $/month |
|-------|------------|---------|
| Quick wins | ~6% | ~$25K |
| Medium-term | ~16% | ~$67K |
| Architectural | ~6% | ~$25K |
| **Total** | **~28%** | **~$117K** |

**~28% (~$117K/month)** — squarely inside the 25–30% target. The biggest, lowest-risk lever is **right-size-then-commit** (Phase 2). All SLA-sensitive changes (right-sizing, Spot, transfer redesign) are rolled out gradually and verified against the Section 2 SLOs.

---

## Commitment strategy: Savings Plans vs Reserved Instances

**Rule of thumb:**
- **Compute Savings Plans → all compute** (EC2/EKS, Fargate, Lambda).
- **Reserved Instances → managed data services** that Savings Plans don't cover (RDS, ElastiCache, Redshift, OpenSearch).
- **Commit to the baseline only; never the peak.**

| Dimension | **Compute Savings Plans** | **EC2 Instance Savings Plans** | **Reserved Instances (Standard)** | **Convertible RIs** |
|-----------|---------------------------|-------------------------------|-----------------------------------|---------------------|
| Discount vs On-Demand | up to ~66% | up to ~72% (highest) | up to ~72% | up to ~66% |
| Flexibility | family, size, AZ, **region**, OS, tenancy; EC2+Fargate+Lambda | locked to **instance family + region** | locked to type/region (size-flex within family for Linux) | can exchange type/family |
| Covers RDS/ElastiCache? | ❌ | ❌ | ✅ (as Reserved Nodes) | ✅ |
| Capacity reservation | ❌ | ❌ | optional (zonal RI) | optional |
| Best for | **modernizing compute** (we're right-sizing + Graviton; flexibility avoids stranded commitments) | very stable compute where shape won't change | **RDS/ElastiCache** stable baseline | data services where you expect engine/size changes |

**When to use which — our decision:**
- **EKS/EC2 compute → Compute Savings Plans.** We're actively right-sizing, adopting Spot, and migrating to Graviton, so flexibility matters more than the last few % of discount. A rigid EC2-Instance SP or Standard RI would be stranded the moment we change instance shape.
- **RDS & ElastiCache → Reserved Instances** (Standard if the engine/size is settled; **Convertible** if a Graviton/engine change is likely), purchased *after* right-sizing.
- **Term & payment:** start **1-year, no-upfront** to preserve cash and de-risk during modernization; **layer to 3-year, partial-upfront** for the proven, stable floor once usage stabilizes. Buy in **tranches** as confidence grows rather than one big commit.
- **Coverage target:** ~70–80% of the *baseline* on commitments; leave headroom on On-Demand/Spot for the 10–50x campaign spikes so we never pay for idle reserved capacity or starve a spike.
- **Govern it:** track Savings Plan/RI **coverage** and **utilization** in Cost Explorer; alert if utilization drops (a sign we over-committed) or coverage falls (a sign of un-optimized On-Demand creep).
