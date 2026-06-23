# 2c. Systematic Alert-Noise Reduction

**Situation:** 60% of alerts auto-resolve within 5 minutes with no human action; >200 alerts/day, majority non-actionable; on-call is fatigued.

**Reframe:** alert fatigue is a **reliability risk**, not an annoyance. A team drowning in non-actionable pages will miss the one that matters (and burn out). So I treat the alerting system as a **product with its own SLIs**, and run a structured audit → classify → remediate program, then keep it healthy with metrics.

> **Why this approach** (rationale): you can't fix what you don't measure, and one-off cleanups regress. The combination of a *data-driven backlog audit* + a *standing health metric* is what makes the improvement durable rather than a temporary purge.

---

## 1. Guiding principle: every alert must be actionable

The bar for a *paging* alert (Rob Ewaschuk's "My Philosophy on Alerting"):

> **Page a human only when a human must take immediate action to prevent or mitigate user-visible harm.**

If an alert is informational, auto-heals, or can wait until morning, it is **not a page** — it's a dashboard, a ticket, or it should be deleted. The 60% auto-resolving in 5 minutes fail this test by definition.

---

## 2. Audit — measure the backlog before changing anything

You can't prioritize what you can't see. First, get data on every alert over the last 30–90 days (from Alertmanager / PagerDuty APIs):

For each **alert rule**, compute:
- **Volume** — fires/day.
- **Auto-resolve rate** — % that resolve before/without human action (proxy: resolved < 5 min, no ack or no linked action). High = noise.
- **Actionability** — % that led to a real remediation (correlate with incident records / ack→action).
- **MTTA / ack rate** — are people even acknowledging it, or banner-blind?
- **Flap count** — fire/resolve cycles per day.
- **Time distribution** — does it page off-hours?
- **Runbook?** — does a linked runbook exist?

Rank rules by **noise score** (high volume × low actionability × high auto-resolve). The top ~20 rules almost always produce ~80% of the noise — start there.

---

## 3. Classify — bucket each alert and assign a disposition

| Bucket | Definition | Disposition |
|--------|------------|-------------|
| **Actionable page** | Needs immediate human action; user impact | **Keep** as page. Ensure SLO-based + runbook linked. |
| **Auto-resolving / transient** | Self-heals in minutes (the 60%) | **Delete or downgrade.** Add `for:` duration so it must persist; convert to SLO burn-rate so it only fires on real impact; or fix the underlying flap. |
| **Cause-based / symptom-noise** | Fires on a cause that may not impact users (CPU>80%, single pod restart) | **Demote** to dashboard/diagnostic. Replace with a symptom (SLO) alert. |
| **Duplicate / cascade** | Many alerts for one root cause | **Group + inhibit** in Alertmanager so one incident = one notification. |
| **Misrouted / wrong severity** | Pages when it should ticket (or vice-versa) | **Re-route** by severity; warnings → ticket channel, never page. |
| **Stale / orphaned** | For a deprecated service or no longer meaningful | **Delete.** |
| **Threshold needs tuning** | Right intent, wrong number / window | **Tune** threshold + `for:` duration; add hysteresis. |

---

## 4. Remediate — fix the backlog, highest-noise first

Concrete actions, mapped to the implemented configs:

1. **Convert cause→symptom.** Replace threshold rules with **SLO burn-rate** alerts (`../slo/`). This single change eliminates most of the auto-resolving noise because a blip that doesn't dent the SLI no longer pages.
2. **Require persistence.** Add `for:` durations and multi-window confirmation so transient spikes self-filter (already built into the burn-rate rules).
3. **Group + inhibit.** Alertmanager `group_by` collapses storms; `inhibit_rules` suppress downstream symptoms when a root-cause alert is firing (`../alerting/alertmanager.yaml`).
4. **Route by severity.** `page="true"` → PagerDuty; `severity=warning` → Slack ticket channel. Off-hours paging only for true user impact.
5. **Delete fearlessly.** Stale/duplicate/non-actionable rules are removed (in Git, reviewed). A deleted noisy alert is a feature.
6. **Attach a runbook to every page.** No runbook → it's not ready to page. (Each burn-rate alert carries a `runbook_url`.)
7. **Fix root causes of flapping** — e.g. tune liveness probes, add PDBs, fix the actual leak — so the alert stops needing to exist.
8. **Govern new alerts (alerts-as-code).** All rules live in Git, peer-reviewed, with a required template (severity, runbook, SLO linkage, owner). This stops noise from creeping back in.

**Process:** run this as a time-boxed program — weekly "alert review" with the on-call team, burning down the ranked backlog; pair each top-noise rule with a decision from §3. Track progress on a dashboard.

---

## 5. Metrics to measure alerting-system health (ongoing)

Treat alerting as a product; review these in the weekly reliability sync and set targets:

| Metric | Definition | Target / direction |
|--------|------------|--------------------|
| **Alert actionability rate** | % of pages that led to a human action | **> 90%** (north star) |
| **Auto-resolve / self-heal rate** | % resolving < 5 min without action | **< 10%** (was 60%) |
| **Pages per on-call shift** | paging notifications per 12h shift | **≤ ~2**; trend down |
| **Signal-to-noise** | actionable alerts ÷ total alerts | trending to 1.0 |
| **MTTA** | time to acknowledge a page | low & stable (high = fatigue/banner-blindness) |
| **MTTR** | time to mitigate | trending down (good runbooks/alerts) |
| **% alerts with runbook** | paging rules linked to a runbook | **100%** |
| **% alerts SLO-based** | pages tied to an SLO vs raw threshold | trending up |
| **Off-hours page rate** | % pages outside business hours | minimize |
| **Flap rate** | alerts firing/resolving repeatedly | → 0 |
| **Alert backlog size** | count of active rules + un-triaged noisy rules | shrinking |
| **On-call sentiment / load** | survey + shift fatigue (qualitative) | improving |

**Guardrails so it stays healthy:**
- A **Watchdog/deadman's-switch** alert (in `../alerting/`) proves the pipeline itself is alive — silence ≠ healthy.
- **Per-page review:** any alert that pages and turns out non-actionable generates a follow-up to fix/tune/delete it (closed-loop).
- **New-alert PR template** enforces actionability + runbook + owner before merge.
- **Quarterly alert audit** re-runs §2 so regressions are caught early.

**Net effect:** symptom-based SLO alerting (cuts the volume) + grouping/inhibition/routing (cuts duplicates and mis-paging) + a standing health metric and review loop (prevents regression) → on-call hears only what matters, and trusts it when it does.
