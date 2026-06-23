# Collection layer — OpenTelemetry Collector

Implements the **collection → aggregation** stages of the data flow in [`../docs/2a-observability-stack-design.md`](../docs/2a-observability-stack-design.md).

## Why this design

| Decision | Why |
|----------|-----|
| **OpenTelemetry (not per-vendor agents)** | Vendor-neutral: instrument once, swap backends without re-instrumenting hundreds of services. Replaces the fragmented CloudWatch-agent + custom-scraper setup with one pipeline and consistent resource attributes for cross-pillar correlation. |
| **Agent (DaemonSet) → Gateway (Deployment) topology** | The **agent** is small and cheap, collecting locally per node. The **gateway** is the single, horizontally-scaled choke point for the expensive/stateful work: cardinality control, tail-based sampling, PII redaction. One place to review and change policy. |
| **`loadbalancing` exporter agent→gateway** | Tail-based sampling needs *all spans of a trace* on one gateway replica. The load-balancing exporter routes by trace ID so that invariant holds. |
| **Cardinality control + allow-list in the gateway** | At 30B events/day this is the difference between a sane metrics bill and a runaway one. High-cardinality IDs are dropped from metrics and pushed to traces/logs; only allow-listed metrics are stored. |
| **PII redaction before storage** | Multi-tenant customer data must never leak into telemetry; redaction happens centrally so it can't be forgotten per-service. |

## Files

- `otel-collector-agent.yaml` — per-node DaemonSet config (receive OTLP, scrape node-local pods, tail logs, enrich, forward).
- `otel-collector-gateway.yaml` — gateway config (redaction, cardinality control, tail sampling, fan-out to AMP/Mimir, Loki, Tempo).

## Environment inputs (injected via Deployment env / IRSA)

| Var | Purpose |
|-----|---------|
| `NODE_NAME`, `CLUSTER_NAME`, `AWS_REGION` | resource attributes / scrape scoping |
| `METRICS_REMOTE_WRITE_URL` | AMP/Mimir remote-write endpoint (SigV4-authed via IRSA) |
| `LOKI_OTLP_ENDPOINT`, `TEMPO_OTLP_ENDPOINT` | log/trace backends |

> These ConfigMaps are the core config; the DaemonSet/Deployment/Service/RBAC
> wrappers are standard and deployed via the GitOps layer (Section 3). The OTel
> Collector's IRSA role is provisioned by the Section 1 EKS module's `irsa_roles`.

## Validate

```bash
# schema-validate the embedded collector config:
otelcol validate --config <(yq '.data."config.yaml"' otel-collector-gateway.yaml)
```
