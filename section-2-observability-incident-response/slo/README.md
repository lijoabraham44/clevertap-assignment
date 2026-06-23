# SLO & burn-rate alerting

Implements the **SLO-based alerting** required by task 2a — the core lever that turns >200 noisy alerts/day into a handful of actionable, urgency-ranked pages.

## Why SLO burn-rate beats threshold alerting

| | Threshold alerting (today) | **SLO burn-rate (this design)** |
|--|----------------------------|---------------------------------|
| Fires on | causes (`CPU>80%`, pod restart, queue depth) | symptoms (user-facing error budget burn) |
| Auto-healing blip | pages anyway → noise (the 60% that self-resolve) | **no page** if the SLI isn't dented |
| Flapping | common | filtered by the two-window (long+short) requirement |
| Severity | manual, inconsistent | derived from burn speed (fast=page, slow=ticket) |
| Across services | bespoke per service | one consistent model fleet-wide |

## Files

- `slo-definitions.yaml` — OpenSLO-style spec (the targets: 99.9% availability, 99% < 500ms). Source of truth.
- `prometheus-recording-rules.yaml` — pre-computes the SLI error ratio over 5m/30m/1h/2h/6h/1d/3d windows (cheap, canonical).
- `prometheus-burn-rate-alerts.yaml` — multi-window, multi-burn-rate alerts that page only on fast burn and ticket on slow burn.

## The burn-rate model (99.9% / 30d SLO, error budget = 0.1%)

| Burn rate | Budget consumed | Time to exhaust | Long+short windows | Action |
|-----------|-----------------|-----------------|--------------------|--------|
| 14.4x | 2% | ~2 days | 1h & 5m | **Page (critical)** |
| 6x | 5% | ~5 days | 6h & 30m | **Page (critical)** |
| 3x | 10% | ~10 days | 1d & 2h | Ticket (warning) |
| 1x | on pace | 30 days | 3d & 6h | Ticket (warning) |

An alert fires only when **both** the long and short windows exceed the threshold — the long window proves the burn is sustained, the short window proves it's still happening *right now* (so it auto-resolves quickly once fixed).

## Validate

```bash
promtool check rules prometheus-recording-rules.yaml prometheus-burn-rate-alerts.yaml
# optional: unit-test alert firing with promtool test rules <tests.yaml>
```
