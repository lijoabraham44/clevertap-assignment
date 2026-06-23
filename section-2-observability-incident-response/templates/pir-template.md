# Post-Incident Review (PIR) Template

> **Why:** the brief calls out two P0s and no formal process. A blameless PIR
> turns each incident into durable learning and tracked improvements, so the same
> failure can't recur. **Blameless** = focus on systems and process, never on
> individuals. Open within 24h of resolution; review in the weekly reliability sync.

---

## Metadata

| Field | Value |
|-------|-------|
| Incident ID | `INC-____` |
| Title | |
| Severity | SEV1 / SEV2 / SEV3 |
| Status | Draft / In review / Complete |
| Authors | |
| Incident Commander | |
| Date of incident | |
| Date of PIR | |
| Services affected | |

## 1. Summary (2–4 sentences)

What happened, the customer impact, and how it was resolved — readable by someone outside the team.

## 2. Impact

- **Duration:** detection → mitigation → full resolution (with timestamps).
- **Customer impact:** % requests failed, events delayed vs **dropped**, tenants/regions affected, customer tiers.
- **SLO / error budget:** how much of the 30-day budget was consumed; is the SLO now at risk?
- **Business impact:** SLA credits, support tickets, reputational.

## 3. Timeline (UTC, factual)

| Time | Event |
|------|-------|
| | <change/deploy that set the stage> |
| | First impact begins |
| | Alert fired (`<alertname>`) |
| | On-call acknowledged |
| | Mitigation applied (`<action>`) |
| | Service recovered |
| | Incident resolved / monitoring ended |

## 4. Root cause & contributing factors

- **Trigger:** the immediate change/event that started it.
- **Root cause:** the underlying technical reason (use 5-whys).
- **Contributing factors:** process/observability/architecture gaps that made it possible, worse, or slower to resolve (e.g. config drift, missing PDB, noisy alert masked the real one, runbook step unclear).

## 5. Detection & response assessment

- **How was it detected?** SLO burn-rate alert (good) vs noisy symptom alert vs customer report (bad)?
- **Time to detect / acknowledge / mitigate** — and where time was lost.
- **Did the runbook help?** Note any step that was wrong, missing, or slow → file a runbook fix.

## 6. What went well / what went poorly

- ✅ Went well: …
- ⚠️ Went poorly / got lucky: …

## 7. Action items (the most important section)

> Each item: **specific, owned, dated, tracked**. Prefer systemic fixes (prevent the class) over point fixes.

| # | Action | Type (Prevent/Detect/Mitigate) | Owner | Due | Ticket |
|---|--------|-------------------------------|-------|-----|--------|
| 1 | | Prevent | | | |
| 2 | | Detect | | | |
| 3 | | Mitigate | | | |

Examples: codify the temporary mem-limit bump in Helm; add a PodDisruptionBudget; add a pre-deploy config validation; tune liveness probe; add a dependency-health pre-check; add a game-day for this scenario; tune/retire the alert that misled the responder.

## 8. Lessons & follow-up verification

- Broader lessons for other services/teams.
- How and when we'll **verify** the action items actually prevent recurrence (e.g. game-day, chaos test, dashboard check).
