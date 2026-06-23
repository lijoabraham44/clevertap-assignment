# Section 4 — Design Rationale (Why this approach)

ADR-style record of the cost-engineering decisions, with alternatives and trade-offs, mapped to the brief: $420K/month bill, mandate to cut 25–30% with **no SLA impact**, workload profile = EKS-on-EC2 + RDS + ElastiCache + S3 + heavy inter-region data transfer.

---

## ADR-01: Measure first — tagging + CUR before any cut

**Context.** We have a top-line number ($420K) but no reliable per-team/per-service breakdown (the FinOps gap).

**Decision.** Day-one action is to enable **cost allocation tags**, the **Cost & Usage Report (CUR)** into Athena, and Cost Explorer/Kubecost — before executing reductions.

**Why.** You can't safely cut what you can't see. Targeting the biggest line items first maximizes ROI and avoids cutting something load-bearing. It also makes every initiative's savings **provable** to Finance, which matters for a Staff-level mandate. Cutting blind risks an SLA incident — the one thing we're told not to do.

**Trade-off.** A few days before the first dollar is saved. Worth it; the quick wins still land in week 1–2.

---

## ADR-02: Sequence by risk-adjusted ROI — waste → right-size → commit

**Decision.** Phase the plan: (1) delete waste & schedule non-prod, (2) right-size & adopt Spot, (3) **then** buy Savings Plans/RIs, (4) architectural changes.

**Why.** **Order matters for commitments.** If you buy a 3-year Savings Plan *before* right-sizing, you lock in your current waste. Right-sizing first shrinks the baseline, so you commit to a smaller, accurate floor. Quick wins are banked first because they're low-risk and fund credibility for the harder changes.

---

## ADR-03: Commitments cover only the stable baseline; Spot only for fault-tolerant work

**Decision.** Buy Savings Plans/RIs to cover roughly the **floor** of demand (the always-on baseline), run the **variable top** (campaign spikes, 10–50x) on On-Demand + **Spot** for stateless workloads. Keep an On-Demand floor for critical/stateful pods.

**Why (SLA protection).** Over-committing to handle peaks wastes money at the trough; under-provisioning critical capacity risks SLA. Splitting baseline (committed) from burst (Spot/On-Demand) gives the best price *and* protects reliability — and it dovetails with the Section 1 mixed On-Demand+Spot node groups. This is the central "cut cost without SLA impact" mechanism.

---

## ADR-04: Savings Plans for compute, Reserved Instances for the managed data services

**Decision.** Use **Compute Savings Plans** for EKS/EC2 (and Fargate/Lambda) compute; use **Reserved Instances** for **RDS and ElastiCache** (which Savings Plans don't cover).

**Why.** Compute Savings Plans are flexible across instance family/size/AZ/region/OS, so they keep saving even as we right-size, adopt Graviton, or shift node shapes — no re-purchasing. RDS/ElastiCache have **no Savings Plan**, so RIs (Reserved Nodes) are the only commitment vehicle there; use them once those engines are right-sized and stable. Full decision matrix in `4a`.

**Trade-off.** Compute Savings Plans give a slightly smaller discount than the rigid EC2-Instance Savings Plan; we accept that for flexibility (avoids stranded commitments mid-modernization).

---

## ADR-05: Attack inter-region data transfer as a first-class line item

**Decision.** Treat "heavy data transfer between regions" as a named workstream: VPC endpoints to bypass NAT, compression/batching, caching, and colocating chatty services.

**Why.** Cross-region and NAT data-processing charges are silent, fast-growing, and architectural — they don't show up as an obvious "instance to delete." At CleverTap's scale they're material, and the Section 1 design (per-AZ NAT, flow-logs-to-S3, TGW) already sets up the levers. This is structural savings that also improves latency.

---

## ADR-06: Institutionalize cost (FinOps), don't just cut once

**Decision.** Stand up a FinOps process: enforced tag taxonomy (Org Tag Policy + SCP), **showback** moving toward **chargeback**, per-team budgets, and **anomaly detection** alerts routed to owning teams.

**Why.** The brief explicitly asks to *institutionalize cost visibility*. One-time cuts regress as new services launch. Making each team see and own its spend (with a monthly efficiency KPI) creates a durable feedback loop, the same philosophy as the Section 2 alerting-as-a-product approach. Showback-before-chargeback because cultural buy-in precedes billing teams internally; chargeback once the data is trusted.

---

## ADR-07: Automation over willpower for cleanup

**Decision.** Non-prod scheduling, idle-resource reaping, storage lifecycle, and ephemeral-env TTLs (Section 3 IDP) are **automated**, not left to engineers to remember.

**Why.** Waste accumulates because cleanup is nobody's job. Encoding it (schedulers, lifecycle rules, TTL controllers, anomaly alerts) makes the efficient state the default and keeps savings from eroding.
