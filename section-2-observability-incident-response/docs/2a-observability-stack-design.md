# 2a. Unified Observability Stack Design

Goal: replace the fragmented setup (CloudWatch for infra, self-hosted single-node Prometheus/Grafana for apps, no unified alerting) with one architecture covering the **four pillars — metrics, logs, traces, events** — that scales to 30B+ events/day and is *quiet by default*.

> **Why this approach** is summarized in [`design-rationale.md`](design-rationale.md). This document is the detailed design.

---

## 1. Tooling choices per pillar (with justification)

| Pillar | Choice | Why this, justified |
|--------|--------|---------------------|
| **Collection (all pillars)** | **OpenTelemetry Collector** (agent DaemonSet → gateway Deployment) | One vendor-neutral pipeline for all signals. Instrument once; swap backends without re-instrumenting services. Lets us retire the CloudWatch agent + custom scrapers and unify resource attributes (`service.name`, `k8s.*`, `tenant_tier`) so signals correlate. |
| **Metrics** | **Prometheus-compatible, horizontally scalable store: Amazon Managed Prometheus (AMP)** *or* **Grafana Mimir/Thanos**; **Grafana** for viz | Keeps existing PromQL/Grafana skills and the self-hosted dashboards, but replaces the single-node Prometheus that cannot survive this cardinality. AMP = no ops burden; Mimir = cheaper at very large scale / self-managed. Both are remote-write targets from the OTel gateway. |
| **Logs** | **Grafana Loki** (label-indexed, object-storage backed) | Indexes only labels (not full text), so storage is S3-cheap — essential at this volume. Shares Grafana + label model with metrics/traces for one-click correlation. (OpenSearch is the alternative when rich full-text search/SIEM is required; costs more.) |
| **Traces** | **Grafana Tempo** (or **AWS X-Ray**) with **tail-based sampling** | Object-storage backed, cheap, integrates with Grafana. Tail sampling (done in the OTel gateway) keeps the *interesting* traces (errors, slow, specific tenants) instead of blind head sampling. X-Ray is the AWS-native fallback if managed-only is required. |
| **Events** | **K8s events + change/deploy events** routed through OTel/Loki, annotated on Grafana dashboards | "What changed?" is the fastest path to root cause (two P0s were config drift). Correlating deploys/config changes on the same timeline as metrics is high-leverage. |
| **Alerting** | **Prometheus/Mimir ruler + Alertmanager** | Evaluates the SLO burn-rate rules; Alertmanager does routing/grouping/inhibition/silencing. Single alerting brain across the fleet (fixes "no unified alerting strategy"). |

**Commercial alternative:** a single SaaS (Datadog/Grafana Cloud/New Relic) collapses ops burden but is costly at 30B events/day and risks lock-in. Because collection is OTel, we can move to such a backend later **without re-instrumenting** — that optionality is the point.

---

## 2. Data flow: collection → aggregation → storage → alerting

```
                              ┌──────────────────────────────────────────────┐
   App pods (OTel SDK)        │  every signal tagged with resource attributes │
   K8s/infra (kubelet, KSM)   │  service.name, k8s.namespace, tenant_tier ... │
            │                 └──────────────────────────────────────────────┘
            ▼
   ┌───────────────────┐   OTLP    ┌─────────────────────────┐
   │ OTel Collector    │ ────────► │ OTel Collector GATEWAY  │   (collection + aggregation)
   │ AGENT (DaemonSet) │           │  - batching              │
   │  - scrape /metrics│           │  - cardinality control   │
   │  - tail pod logs  │           │  - tail-based sampling    │
   │  - receive OTLP   │           │  - PII redaction          │
   └───────────────────┘           └───────────┬──────────────┘
                                                │ fan-out by signal
                  ┌───────────────────┬─────────┼───────────────────┐
                  ▼                   ▼          ▼                   ▼
            metrics(remote_write) logs(push)  traces(OTLP)      events
                  │                   │          │                   │
          ┌───────▼──────┐   ┌────────▼───┐ ┌────▼─────┐    ┌────────▼────────┐
          │ AMP / Mimir  │   │   Loki     │ │  Tempo   │    │ Loki (events)   │   (storage,
          │ (TSDB + S3)  │   │ (S3 chunks)│ │ (S3)     │    │                 │    S3-backed)
          └───────┬──────┘   └────────┬───┘ └────┬─────┘    └────────┬────────┘
                  │                   └─────┬─────┴───────────────────┘
                  ▼ ruler (SLO burn-rate)   ▼
          ┌──────────────┐          ┌───────────────┐
          │ Alertmanager │◄─────────│   Grafana     │  (unified query + correlation across pillars)
          │  route/group │          │ dashboards/   │
          │  inhibit     │          │ exemplars→trace
          └──────┬───────┘          └───────────────┘
                 ▼
       PagerDuty / Slack / email  (severity-routed; see alerting/)
```

1. **Collection.** OTel **agent** on each node scrapes `/metrics`, tails container logs, and receives OTLP from app SDKs. Everything is stamped with consistent resource attributes.
2. **Aggregation.** OTel **gateway** centralizes batching, **cardinality control**, **tail-based trace sampling**, and **PII redaction** before anything is stored — the single choke point where cost and noise are controlled.
3. **Storage.** Metrics → AMP/Mimir (TSDB + S3); logs/events → Loki; traces → Tempo. All object-storage backed for cost.
4. **Alerting.** The ruler evaluates **SLO burn-rate** recording/alerting rules; **Alertmanager** routes by severity, groups, inhibits, and silences. Grafana provides correlation (metric exemplar → trace → logs).

---

## 3. Cardinality management (the scaling problem at 30B events/day)

Cardinality = number of unique time series = `product of label value counts`. Per-tenant (4B devices) or per-campaign labels on metrics would create billions of series and bankrupt the metrics store. Strategy, applied **at the gateway** so it's enforced centrally:

1. **Right signal for the job.** Metrics = low-cardinality aggregates (trends, SLOs). Per-request/per-tenant detail belongs in **traces and logs** (sampled), not metrics.
2. **Drop/aggregate high-cardinality labels.** Strip `tenant_id`, `campaign_id`, `device_id`, raw `url`, `user_agent` from metrics; keep bounded labels like `tenant_tier` (free/paid/enterprise), `route` (templated `/v1/events/:id`), `status_class` (2xx/4xx/5xx). Implemented via OTel `transform`/`filter` processors and metric_relabel rules (see `collection/otel-collector-gateway.yaml`).
3. **Allow-list, not deny-list.** Only explicitly approved metrics/labels are persisted; new high-cardinality series require review. Prevents silent cardinality creep.
4. **Pre-aggregate with recording rules.** Compute SLIs as recording rules so dashboards/alerts query a few pre-aggregated series instead of raw ones.
5. **Exemplars bridge metrics↔traces.** Keep metrics low-cardinality but attach exemplars (trace IDs) so you can still jump from an SLI spike to a concrete trace for the offending tenant.
6. **Bound retention by tier.** High-res metrics short retention, downsampled long retention (Mimir/Thanos compaction); traces/logs sampled + lifecycle to cold storage.
7. **Guardrails.** Per-tenant/per-namespace ingestion limits and active-series quotas in Mimir/AMP so one team's bad label can't take down ingestion for everyone.

---

## 4. SLO-based alerting with error-budget burn rate (and why it cuts noise)

**Threshold alerting** (today) pages on *causes* (`CPU>80%`, `pod restarted`, `queue depth>N`). Most don't affect users and self-heal — that's the 60% auto-resolving in 5 minutes and most of the 200/day.

**SLO burn-rate alerting** pages on *symptoms*: "are we burning our error budget fast enough to threaten the SLO?"

- **SLO** example for the event-ingestion service: 99.9% of inbound events accepted successfully over 30 days → **error budget = 0.1%** of requests.
- **Burn rate** = how fast the budget is being consumed relative to "even" spend. Burn rate `1` = exactly on pace to exhaust the budget at the end of the window; burn rate `14.4` = exhausting a 30-day budget in ~2 days.
- **Multi-window, multi-burn-rate** (Google SRE) fires:
  - **Page (critical)** when a **fast** burn is confirmed by both a long and short window (e.g. 14.4x over 1h *and* 5m) → real, urgent user impact.
  - **Ticket (warning)** for **slow** burns (e.g. 6x/6h, 1x/3d) → degradation worth fixing, not worth waking someone.

**Why this reduces noise:**
- Alerts fire **only on user-impacting** budget consumption — the auto-healing pod restart that doesn't dent the SLI produces **zero pages**.
- The **two-window requirement** filters transient spikes (the short window resets), killing flapping.
- **Severity = urgency** by construction, so paging volume drops to a handful of genuinely actionable events and slow burns become trackable tickets.
- One consistent alerting model across all services replaces hundreds of bespoke thresholds → the "no unified alerting strategy" gap is closed.

Concrete rules are implemented in [`../slo/`](../slo/) (`prometheus-recording-rules.yaml`, `prometheus-burn-rate-alerts.yaml`) with their own rationale in `slo/README.md`.
