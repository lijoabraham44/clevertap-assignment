# Customer-Facing Incident Communication Template

> **Why:** customers need timely, honest, jargon-free updates. Over-communicating
> calmly preserves trust; speculation or silence destroys it. Published via the
> status page and/or Support, **approved by the IC/Comms lead** before posting.

## Principles

- **Factual, not speculative** — describe impact and what we're doing, never guess the root cause publicly.
- **No internal jargon** — no pod names, no "Kafka", no rollback revisions.
- **Acknowledge → Update → Resolve → Postmortem (if warranted)** cadence.
- **Commit to a next-update time** and honor it.
- **One owner** for external comms to avoid contradictory messages.

## 1. Initial acknowledgement (Investigating)

```
[Investigating] Elevated errors with event ingestion — <region>
<DATE TIME UTC>

We are investigating an issue causing elevated errors and possible delays in
processing incoming events in <region>, starting at approximately <time UTC>.
Some events may be delayed. We are actively working to identify and resolve the
cause. Next update within 30 minutes.
```

## 2. Identified / mitigating

```
[Identified] Event ingestion delays — <region>
<DATE TIME UTC>

We have identified the cause of the elevated errors affecting event ingestion in
<region> and are applying a fix. Event processing is recovering. Next update
within 30 minutes (or sooner if status changes).
```

## 3. Resolved

```
[Resolved] Event ingestion delays — <region>
<DATE TIME UTC>

Event ingestion in <region> returned to normal at <time UTC>. Events received
during the incident <were queued and processed / a small number may have been
affected — see below>. We apologize for the disruption. A summary will follow
for impacted customers.
```

## 4. Post-incident summary (for SEV1 / customer-requested)

```
Summary of <date> event-ingestion incident

What happened:   <plain-language description>
Duration:        <start–end UTC>
Customer impact: <what customers experienced; data delayed vs lost>
What we did:     <mitigation, in plain terms>
Prevention:      <high-level remediation we're committing to>
```

> Data-loss disclosure, regulatory/contractual notification timelines, and which
> tier of customers receive proactive outreach are decided with Support, Legal,
> and Customer Success per the incident-response policy.
