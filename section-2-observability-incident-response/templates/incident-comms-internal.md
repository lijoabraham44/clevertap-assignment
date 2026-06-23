# Internal Incident Communication Template

> **Why:** consistent, scannable updates keep responders, leadership, and adjacent
> teams aligned without anyone having to ask "what's the status?". Post in the
> incident channel (`#inc-<id>`) at declaration and every ~15 minutes until resolved.

## Declaration (T+0)

```
:rotating_light: [SEV<1/2/3>] <service> — <one-line symptom> — DECLARED
Impact:        <who/what is affected, region, approx % or scope>
Started:       <time UTC> (detected by <alert/human>)
Incident Commander: <name>   Comms lead: <name>   Scribe: <name>
Channel:       #inc-<id>      Bridge: <link if used>
Current focus: <triage / mitigation>
Next update:   T+15m
```

## Progress update (every ~15 min)

```
[SEV<n>] <service> — UPDATE T+<XX>m
Status:        Investigating | Mitigating | Monitoring | Resolved
Impact now:    <current, e.g. "~8% of ingestion requests failing in us-east-1; events delayed not lost">
Actions taken: <e.g. rolled back to rev 142; scaled to 12 replicas>
Working theory: <short; mark as unconfirmed>
Next step:     <action + owner + ETA>
Next update:   T+<XX>m
```

## Resolution

```
:white_check_mark: [SEV<n>] <service> — RESOLVED
Duration:      <start → end UTC> (<total mins>)
Impact summary:<final scope: % failed, events delayed/dropped, tenants affected, SLO budget consumed>
Root cause:    <one line; full analysis in PIR>
Mitigation:    <what restored service>
Follow-ups:    PIR due <date> — owner <name> — ticket <link>
Thanks:        <responders>
```

## Severity quick-reference

| Sev | Criteria | Cadence |
|-----|----------|---------|
| SEV1 | Full/major outage, data loss, or SLA breach imminent | 15 min, exec-visible |
| SEV2 | Partial degradation, single region/tenant tier | 30 min |
| SEV3 | Minor, no customer impact, working hours | as needed |
