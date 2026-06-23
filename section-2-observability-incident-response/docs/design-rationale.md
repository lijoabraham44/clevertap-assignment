# Section 2 — Design Rationale (Why this approach)

ADR-style record of the major observability/IR decisions, with alternatives and trade-offs, mapped to CleverTap's reality: 40B+ events/day, fragmented tooling (CloudWatch + self-hosted Prom/Grafana, no unified alerting), >200 alerts/day (mostly non-actionable), 60% auto-resolving in 5 min, two P0s from drift, no runbooks.

---

## ADR-01: OpenTelemetry as the single instrumentation/collection standard

**Context.** Observability is fragmented: CloudWatch for infra, self-hosted Prometheus/Grafana for apps, nothing unified. Services are polyglot.

**Decision.** Standardize collection on **OpenTelemetry** (OTel SDKs + Collector), with an **agent (DaemonSet) → gateway** topology.

**Why over alternatives:**
- **vs. per-vendor agents (Datadog Agent, CloudWatch agent, etc.):** OTel is vendor-neutral. Instrument once; change backends without touching application code. Critical when the org already has sunk cost in Prom/Grafana and may adopt a commercial backend later — we don't want to re-instrument hundreds of services to switch.
- **vs. keeping the split (Prom + CloudWatch):** the split *is* the problem (no unified alerting, no correlation across pillars). A common collection layer with consistent resource attributes (`service.name`, `k8s.*`, `tenant`) is what lets us correlate a metric spike → the relevant logs → a trace.

**Trade-off.** Running and scaling Collectors is operational work. Mitigated by the gateway tier doing the heavy lifting (sampling, batching, cardinality control) centrally.

---

## ADR-02: Backend choice per pillar — reuse Prometheus-compatible + scalable stores

**Decision.**
- **Metrics:** Prometheus-compatible store that scales horizontally — **Amazon Managed Prometheus (AMP)** or **Mimir/Thanos** — fed by the OTel gateway via remote-write. Grafana for dashboards (already in use).
- **Logs:** **Loki** (label-indexed, cheap object storage) or OpenSearch; ship to S3-backed storage.
- **Traces:** **Tempo** (or AWS X-Ray) with **tail-based sampling** at the gateway.
- **Events:** Kubernetes events + deploy/change events into the same store, correlated by time + `service.name`.

**Why.** Keep Grafana and PromQL (existing skills, no retraining), but replace the *self-hosted single-node* Prometheus (which won't survive 30B events/day cardinality) with a horizontally scalable, object-storage-backed Prometheus-compatible system. Loki/Tempo share Grafana's label model so the three pillars correlate in one UI.

**Trade-off.** Managed (AMP) costs more per sample but removes the operational burden of running Cortex/Mimir; choice depends on team size. Either is Prometheus-compatible, so the rules in `slo/` work unchanged.

---

## ADR-03: SLO burn-rate alerting instead of threshold alerting

**Context.** >200 alerts/day, majority non-actionable; 60% auto-resolve in 5 min. This is the headline problem.

**Decision.** Alert on **error-budget burn rate** against **user-facing SLOs**, using **multi-window, multi-burn-rate** rules (Google SRE method). Threshold alerts (`CPU > 80%`, `pod restarted`) become dashboards/diagnostics, not pages.

**Why.** Threshold alerts fire on *causes* that may not affect users (a pod restarting that auto-heals in 5 min = exactly the 60% noise). Burn-rate alerts fire only when the user-visible error budget is being consumed *fast enough to matter*, with severity proportional to urgency (page for fast burn, ticket for slow burn). This structurally collapses hundreds of cause-based alerts into a few symptom-based, actionable ones. Full reasoning in `slo/README.md` and `docs/2a`.

**Trade-off.** Requires defining good SLIs/SLOs per service — upfront work. Worth it; it's the single biggest noise reducer.

---

## ADR-04: Cardinality managed deliberately at the edge

**Context.** 30B events/day; high-cardinality labels (per-tenant, per-campaign, per-device) would explode the metrics store cost and break ingestion.

**Decision.** Control cardinality in the OTel gateway and rules: drop/aggregate high-cardinality labels, keep tenant_tier rather than tenant_id on metrics, push high-cardinality detail to **exemplars/traces/logs** (sampled), enforce metric allow-lists, and use recording rules to pre-aggregate.

**Why.** Metrics are for trends/alerting (low cardinality); traces/logs are for per-request detail (sampled). Putting per-tenant/per-campaign IDs on metrics is the classic way to a runaway bill at this scale. See `collection/README.md` and `docs/2a` (cardinality section).

---

## ADR-05: Runbooks are code, written for a junior responder

**Context.** No formal runbooks; on-call has 6-month-experience first responders.

**Decision.** Every alert links to a versioned runbook in this repo. Runbooks are explicit, ordered, copy-paste-ready, and include an explicit **rollback vs hotfix vs scale-out decision tree** and comms templates.

**Why.** A Staff engineer scales themselves by making the *median* responder effective at 3am, not by being the hero. Versioned-in-Git runbooks get reviewed, stay current, and are testable in game days. See `runbooks/`.

---

## ADR-06: Blameless PIRs with tracked actions, and alerting-as-a-product metrics

**Decision.** Standardize a blameless **PIR template**; treat the alerting system itself as a product with health SLIs (actionability, precision, MTTA, auto-resolve %) reviewed regularly.

**Why.** The two P0s and the alert fatigue won't be fixed once — they need an institutionalized feedback loop. Measuring the alerting system is how you keep noise from creeping back. See `docs/2c` and `templates/pir-template.md`.
