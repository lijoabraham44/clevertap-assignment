# Section 2 — Reliability, Observability & Incident Response

Implementation for **Section 2** of the CleverTap Staff DevOps assessment. The current setup is noisy (>200 alerts/day, mostly non-actionable; 60% auto-resolve in 5 min) and reactive (two P0s from config drift, no runbooks). This section builds a system for **fast detection, diagnosis, and resolution**.

Every part ships with a **"why this approach" rationale** — see [`docs/design-rationale.md`](docs/design-rationale.md) and the rationale section embedded in each design doc.

## Repository layout

```
section-2-observability-incident-response/
├── README.md
├── docs/
│   ├── design-rationale.md                 # WHY the overall observability approach was chosen
│   ├── 2a-observability-stack-design.md    # 2a: 4 pillars, tooling, data flow, cardinality, SLO alerting
│   └── 2c-alert-noise-reduction.md         # 2c: audit/classify/remediate + alerting health metrics
├── collection/
│   ├── otel-collector-agent.yaml           # node-level OTel Collector (DaemonSet) config
│   ├── otel-collector-gateway.yaml         # gateway OTel Collector (tail sampling, cardinality control)
│   └── README.md                           # why OTel + data-flow walkthrough
├── slo/
│   ├── slo-definitions.yaml                # OpenSLO-style SLO spec for the event-ingestion service
│   ├── prometheus-recording-rules.yaml     # SLI + multi-window burn-rate recording rules
│   ├── prometheus-burn-rate-alerts.yaml    # multi-window multi-burn-rate SLO alerts
│   └── README.md                           # why SLO burn-rate beats threshold alerting
├── alerting/
│   ├── alertmanager.yaml                   # routing, grouping, inhibition, severity-based paging
│   └── README.md                           # why this routing model reduces noise
├── runbooks/
│   └── kubepodcrashlooping-event-ingestion.md   # 2b: the runbook (implementation)
└── templates/
    ├── incident-comms-internal.md          # internal status update template
    ├── incident-comms-customer.md          # customer-facing status template
    └── pir-template.md                     # Post-Incident Review template
```

## How this maps to the task

| Task | Deliverable |
|------|-------------|
| **2a** Observability stack design | [`docs/2a-observability-stack-design.md`](docs/2a-observability-stack-design.md) + working configs in `collection/`, `slo/`, `alerting/` |
| **2b** Runbook & incident response (impl) | [`runbooks/kubepodcrashlooping-event-ingestion.md`](runbooks/kubepodcrashlooping-event-ingestion.md) + `templates/` |
| **2c** Alert-noise reduction design | [`docs/2c-alert-noise-reduction.md`](docs/2c-alert-noise-reduction.md) |

## Design principles (the thread through everything)

1. **Single pane, open standards.** Instrument once with **OpenTelemetry**; avoid vendor lock-in on the collection layer so backends can change without re-instrumenting 100s of services.
2. **Alert on symptoms, not causes.** **SLO burn-rate** alerting on user-facing SLIs replaces threshold alerts — this is the core lever that turns >200 noisy alerts/day into a handful of actionable, urgency-ranked pages.
3. **Control cardinality at the edge.** At 30B events/day, cardinality is the scaling bottleneck; we manage it deliberately (allow-lists, aggregation, exemplars) rather than letting it explode the metrics bill.
4. **Every page has a runbook.** No alert ships without a linked runbook; runbooks are written for a 6-month on-call, not a tribal expert.
5. **Learn from every incident.** Blameless PIRs with action items tracked to closure; the alerting system itself has SLIs and is continuously pruned.
