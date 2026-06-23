# Alerting layer — Alertmanager

Implements the **alerting** stage of the data flow. SLO burn-rate rules decide *what* is wrong; Alertmanager decides *who hears about it and how loudly*.

## Why this routing model reduces noise

| Mechanism | What it does | Noise impact |
|-----------|--------------|--------------|
| **Severity routing** (`page="true"` → PagerDuty, `severity=warning` → Slack) | Only genuinely urgent, user-impacting burns wake a human; everything else is a trackable ticket. | Collapses pages to a handful/day. |
| **Grouping** (`group_by: [alertname, service, cluster]`) | One incident affecting 50 pods = **one** notification, not 50. | Kills alert storms. |
| **Inhibition** | When the SLO-burn page is already firing, suppress the lower-level `KubePodCrashLooping` symptom for the same service; critical inhibits warning. | Removes duplicate/cascading alerts for a single root cause. |
| **Repeat/group intervals** | Sensible re-notify cadence instead of constant re-paging. | Stops nagging. |
| **Deadman's switch (Watchdog)** | An always-firing heartbeat; an external monitor pages if it *stops* arriving. | Catches the scariest failure: silence because monitoring itself is down. |

These are exactly the dedupe/suppression levers referenced in [`../docs/2c-alert-noise-reduction.md`](../docs/2c-alert-noise-reduction.md).

## Validate

```bash
amtool check-config alertmanager.yaml
```

> Secrets (Slack webhook, PagerDuty key) are mounted from files, never inlined —
> consistent with the "no secrets in YAML" principle. They are delivered by the
> External Secrets Operator (AWS Secrets Manager), wired via the EKS module's IRSA.
