# Section 4 — Cost Engineering

Implementation for **Section 4** of the CleverTap Staff DevOps assessment. The AWS bill is **$420K/month**; Finance wants a **25–30% reduction ($105–126K/month)** with **no SLA impact**. This section delivers a structured 90-day reduction plan **and** the FinOps process to keep cost under control permanently.

Every part ships with a **"why this approach" rationale** — see [`docs/design-rationale.md`](docs/design-rationale.md).

## Repository layout

```
section-4-cost-engineering/
├── README.md
├── docs/
│   ├── design-rationale.md            # WHY this cost approach (ADR-style)
│   ├── 4a-cost-reduction-plan.md      # 4a: 90-day plan w/ savings %, effort, risk + SP vs RI
│   └── 4b-finops-process.md           # 4b: tagging, showback/chargeback, alerting thresholds
├── tagging/
│   └── aws-tag-policy.json            # AWS Organizations Tag Policy (enforces the tag taxonomy)
├── budgets/
│   └── budgets.tf                     # AWS Budgets + Cost Anomaly Detection (Terraform)
└── finops/
    └── showback-query.sql             # Athena/CUR query: monthly cost per team/service (showback)
```

## How this maps to the task

| Task | Deliverable |
|------|-------------|
| **4a** 90-day cost reduction plan (quick wins / medium / architectural) with savings %, effort, risk | [`docs/4a-cost-reduction-plan.md`](docs/4a-cost-reduction-plan.md) |
| **4a** Savings Plans vs Reserved Instances — when to use which | [`docs/4a-cost-reduction-plan.md`](docs/4a-cost-reduction-plan.md#commitment-strategy-savings-plans-vs-reserved-instances) |
| **4b** FinOps process: tagging, showback/chargeback, alerting | [`docs/4b-finops-process.md`](docs/4b-finops-process.md) + [`tagging/`](tagging/), [`budgets/`](budgets/), [`finops/`](finops/) |

## Headline: the path to ~28%

| Phase | Net savings | Lever |
|-------|------------|-------|
| Quick wins (Wk 1–2) | **~6%** | delete waste, schedule non-prod, storage lifecycle, gp3 |
| Medium-term (Mo 1–2) | **~16%** | right-sizing + Spot + **Savings Plans/RIs** on the baseline |
| Architectural (Mo 2–3) | **~6%** | cut inter-region transfer, Graviton, Karpenter consolidation |
| **Total** | **~28%** (≈ $118K/mo) | within the 25–30% target, SLA-safe |

> Figures use an assumed service-level cost breakdown (stated in 4a). The first FinOps action — turning on cost allocation tags + CUR — replaces these estimates with real per-service numbers in week one.

## Principles (the thread through everything)

1. **Measure before cutting.** Tagging + CUR + Cost Explorer first, so every initiative is targeted and its savings provable.
2. **Sequence by risk-adjusted ROI.** Bank the low-risk quick wins first; commit (SP/RI) only after right-sizing so we don't lock in waste.
3. **Never trade SLA for cost.** Commitments cover only the stable baseline; Spot only for fault-tolerant workloads; keep the On-Demand floor for critical paths.
4. **Make it stick (FinOps).** Cost is a shared engineering KPI with showback, budgets, anomaly alerts, and team ownership — not a one-time cleanup.
