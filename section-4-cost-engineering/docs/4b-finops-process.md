# 4b. FinOps Process Design — Institutionalizing Cost Visibility

A Staff engineer doesn't just cut cost once; they make cost a **first-class, owned engineering metric** so savings don't erode. This is the durable feedback loop: **tag → allocate → show back → alert → own**.

> **Why FinOps-as-a-process** (not a one-time cleanup) is in [`design-rationale.md`](design-rationale.md) (ADR-06). Supporting artifacts: [`../tagging/aws-tag-policy.json`](../tagging/aws-tag-policy.json), [`../budgets/budgets.tf`](../budgets/budgets.tf), [`../finops/showback-query.sql`](../finops/showback-query.sql).

---

## 1. Tagging strategy (the foundation — nothing works without it)

Cost can only be owned if every dollar maps to a team/service. We enforce a **mandatory tag taxonomy** at provisioning time.

### Mandatory tags

| Tag | Purpose | Example |
|-----|---------|---------|
| `team` | owning team → showback/chargeback unit | `ingestion` |
| `service` | application/workload | `event-ingestion` |
| `environment` | prod / staging / dev / ephemeral | `prod` |
| `cost-center` | Finance chargeback code | `cc-1234` |
| `owner` | accountable person/email | `jane@clevertap.com` |
| `managed-by` | terraform / crossplane / console (flags click-ops) | `terraform` |
| `data-residency` | region constraint (ties to Section 1c) | `eu-only` |

### Enforcement (defense in depth — measure *and* prevent)
1. **AWS Organizations Tag Policy** ([`aws-tag-policy.json`](../tagging/aws-tag-policy.json)) defines the allowed keys/values and reports non-compliant resources.
2. **SCP / OPA / Terraform `default_tags`** make tags non-optional: the Section 1 modules apply `default_tags`; the Section 3 IDP Compositions inject `team`/`owner`/`cost-center`; an SCP can deny creation of taggable resources missing required tags.
3. **`managed-by` tag** surfaces click-ops (untagged/console resources) — directly attacking the inherited 40% click-ops.
4. **Activate as cost allocation tags** in the billing console so they appear in CUR/Cost Explorer.
5. **Continuous compliance**: a scheduled job + AWS Config rule reports untagged spend; the goal is **<5% untagged** (an SLI for the FinOps program itself).

> Kubernetes adds a wrinkle: many teams share EKS nodes, so EC2 tags alone can't split EKS cost. We use **Kubecost/OpenCost** to allocate shared-cluster cost down to namespace/label/team, then reconcile with CUR.

---

## 2. Showback → Chargeback model

**Start with showback, evolve to chargeback** (cultural buy-in before internal billing).

### Showback (months 1–3)
- A **monthly cost dashboard per team** (Grafana/Cost Explorer/Kubecost), powered by the CUR query in [`showback-query.sql`](../finops/showback-query.sql): cost by `team` × `service` × `environment`, month-over-month trend, and **shared-cost allocation** (cluster overhead, data transfer, support) spread by usage.
- Each team sees: their total, their trend, their top cost drivers, their **commitment coverage**, and an **efficiency metric** (e.g. $ per million events processed) — unit economics matter more than raw $.
- Reviewed in a **monthly FinOps review** with Eng + Finance.

### Chargeback (month 3+)
- Once the data is trusted, allocated costs are **billed back to each team's budget/cost-center**, including a fair share of shared/overhead cost.
- This creates real accountability: a team's spend hits its own budget, so efficiency becomes self-interested.

### Allocating the un-attributable
Shared costs (control planes, NAT, cross-AZ, support, untagged) are allocated by a documented, fair key (usage-proportional), not hidden — otherwise teams distrust the numbers.

---

## 3. Alerting thresholds (so overspend is caught early, by the right team)

Two complementary mechanisms, both routing to the **owning team** (via the `team` tag), implemented in [`budgets.tf`](../budgets/budgets.tf):

### a) Budgets (expected-spend guardrails)
- **Per-team monthly budgets** with alerts at **50% / 80% / 100% of actual**, plus a **forecasted-to-exceed-100%** alert (catches runaway spend *before* month-end).
- **Org-level budget** for the whole account/region as a backstop.
- **Commitment budgets**: alert if **Savings Plan/RI utilization < 95%** (over-committed, wasting money) or **coverage drops** (un-optimized On-Demand creep).

### b) Cost Anomaly Detection (unexpected-spend guardrails)
- AWS **Cost Anomaly Detection** monitors per service and per `team`/`cost-center`, using ML to flag spikes a static threshold would miss (e.g. a forgotten `r6g.16xlarge`, a runaway cross-region transfer, a misconfigured autoscaler).
- Alerts go to the owning team's Slack + the FinOps channel, with a $ impact threshold to avoid noise (consistent with Section 2's noise discipline).

### Routing & ownership
- Alerts are **actionable and owned** — routed by `team` tag, never to a generic inbox. Each anomaly/budget breach is triaged by the owning team like any other alert.

---

## 4. Ownership model & governance (making it cultural)

- **Decentralized ownership, central enablement.** A small **FinOps function** (or guild) owns tooling, standards, commitment purchasing, and the monthly review; **each engineering team owns its own spend** and efficiency metric.
- **Cost in the engineering loop:**
  - Cost is a **team KPI** (efficiency: $ per unit of business value), reviewed monthly.
  - **Infracost** in the Section 3 CI pipeline shows the $ delta of a Terraform PR *before* merge — cost-awareness shifts left.
  - The Section 3 **IDP enforces TTLs, size caps, and tags**, so self-serve can't create runaway cost.
  - New services define a budget at launch (definition-of-done).
- **Commitment management** (SP/RI purchasing, coverage/utilization) is centralized in FinOps so teams don't each over-commit.
- **Quarterly optimization review** re-runs the 4a analysis to catch regressions — cost is never "done."

### FinOps health metrics (the program measured like a product)
| Metric | Target / direction |
|--------|--------------------|
| % spend with mandatory tags | **> 95%** |
| Savings Plan / RI **coverage** of eligible spend | **70–80%** of baseline |
| Savings Plan / RI **utilization** | **> 95%** |
| % spend under chargeback | trending to 100% |
| Unit cost ($ / million events) | trending down |
| Anomaly mean-time-to-acknowledge | low |
| Idle/waste spend (orphaned, untagged, idle) | trending to 0 |

**Net effect:** every team can see, is alerted on, and is accountable for its own cloud spend — so the 25–30% reduction from 4a is *held*, and future growth stays efficient by default.
