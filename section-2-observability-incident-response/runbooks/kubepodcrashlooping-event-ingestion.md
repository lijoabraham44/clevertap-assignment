# Runbook: `KubePodCrashLooping` — Event-Ingestion Service (Production)

| | |
|--|--|
| **Service** | `event-ingestion` (accepts inbound campaign events → produces to Kafka topic `events.raw`) |
| **Criticality** | P1 service. Sustained outage = dropped customer campaign events = data loss + SLA breach. |
| **Alert** | `KubePodCrashLooping` (pod restarting repeatedly) |
| **Intended responder** | First on-call, **~6 months experience**. This runbook assumes no tribal knowledge. |
| **Owning team / escalation** | `#team-ingestion` · secondary on-call · Eng Manager (see §4) |
| **Related dashboards** | Event-Ingestion SLO · Kafka Producer · Pod Health |

> **Why this runbook exists (rationale).** Two P0s last quarter and no formal runbooks. A Staff engineer scales the team by making the *median* responder effective at 3am. This runbook is ordered, copy-paste-ready, and ends every branch with a clear action + escalation. It is versioned in Git so it's reviewed and kept current, and exercised in game days.

---

## 0. First 60 seconds — orient (do this before touching anything)

1. **Acknowledge** the page in PagerDuty (stops auto-escalation, signals you're on it).
2. **Open the incident channel**: `/incident declare` in Slack → creates `#inc-<id>`. Post: *"Investigating KubePodCrashLooping on event-ingestion, prod. Triage in progress."*
3. **Check if it's already known**: is there an active deploy, a change-freeze override, or another firing alert? Look at the `#incidents` channel and the SLO dashboard.

> **Mindset:** your first job is **mitigation** (restore service), not root cause. Root cause comes in the PIR. If users are impacted, bias to **rollback/scale-out** over debugging.

Set context once and reuse:

```bash
export NS=production
export SVC=event-ingestion
kubectl config use-context prod-us-east-1   # or the region that paged
```

---

## 1. Initial triage — what to check, in order

Work top-to-bottom. Stop as soon as a step points you to a clear branch in §3.

### 1.1 Confirm scope — is this real and how bad?

```bash
# Are pods actually crashlooping, how many, since when?
kubectl -n $NS get pods -l app=$SVC -o wide

# Quick health: how many ready vs desired?
kubectl -n $NS get deploy $SVC
```

- **All replicas down** → full outage, treat as SEV1/P1, jump to §3 fast.
- **Some replicas down / flapping** → partial; service may still be serving — still urgent.
- **Is the SLO actually burning?** Check the SLO dashboard / `EventIngestionErrorBudgetBurnFast`. If pods restart but the SLO is healthy (the burst is absorbed), you have more time — but still fix it.

### 1.2 Why is it crashing? Read the pod's own story

```bash
# Restart count + last termination reason/exit code (OOMKilled? Error? exit 1?)
kubectl -n $NS describe pod -l app=$SVC | sed -n '/Last State/,/Ready/p'

# Logs from the CURRENT crashing container...
kubectl -n $NS logs -l app=$SVC --tail=200
# ...and from the PREVIOUS (already-crashed) container — usually the real cause:
kubectl -n $NS logs -l app=$SVC --previous --tail=200
```

Map what you see to a cause:

| Signal in `describe`/logs | Likely cause | Go to |
|---------------------------|--------------|-------|
| `Reason: OOMKilled`, exit 137 | Memory limit too low / leak / traffic spike | §3 (scale-out / rollback) |
| `Liveness probe failed` / readiness failing | App slow to start or dependency down | §1.3, §1.4 |
| `CrashLoopBackOff` + stack trace / `panic` / `exit 1` on startup | Bad code or bad config in latest deploy | §3 (rollback) |
| `CreateContainerConfigError` / `ImagePullBackOff` | Missing secret/config or bad image tag | §1.3, §3 (rollback) |
| `Error: connection refused` to Kafka / DB | Downstream dependency unhealthy | §1.4 |

### 1.3 Did something just change? (config drift caused both prior P0s)

```bash
# Recent rollout history + when the latest one happened
kubectl -n $NS rollout history deploy/$SVC
kubectl -n $NS get deploy $SVC -o jsonpath='{.metadata.annotations.kubernetes\.io/change-cause}{"\n"}'

# Recent k8s events (config/secret changes, scheduling failures)
kubectl -n $NS get events --sort-by=.lastTimestamp | tail -30
```

- **Crash started right after a deploy/config change?** → strong rollback candidate (§3).
- Also check the deploy pipeline / Argo Rollouts UI and the change log for the last hour.

### 1.4 Is a dependency the real problem?

```bash
# Kafka reachable & topic healthy? (producer errors will crash the service)
kubectl -n $NS exec deploy/$SVC -- sh -c 'nc -zv $KAFKA_BOOTSTRAP 9092' 2>&1 | tail
# Check Kafka producer dashboard: broker availability, under-replicated partitions,
# producer send error rate. Check any DB/cache the service needs.
```

- **Dependency is down/degraded** → this service is a *victim*. Do **not** rollback this service (won't help). Mitigate (§3 scale-out won't help either) and **escalate to the dependency owner** (§4).

### 1.5 Capacity / node problems?

```bash
kubectl -n $NS top pods -l app=$SVC
kubectl top nodes
kubectl -n $NS describe pod -l app=$SVC | grep -A3 -i 'events\|FailedScheduling'
```

- `FailedScheduling` / `Insufficient cpu|memory` → cluster can't place pods → §3 (scale-out nodes / check autoscaler).

---

## 2. Mitigate first, capture evidence as you go

Before changing things, **grab one crashed-pod log + describe** into the incident channel (needed for the PIR; it disappears once pods churn):

```bash
kubectl -n $NS logs -l app=$SVC --previous --tail=500 > /tmp/$SVC-crash.log
kubectl -n $NS describe pod -l app=$SVC > /tmp/$SVC-describe.txt
# attach both to #inc-<id>
```

If inbound events risk being dropped, confirm whether the upstream load balancer / API gateway buffers or sheds — note it for customer comms (§4).

---

## 3. Decision tree — rollback vs hotfix vs scale-out

```
                 ┌─────────────────────────────────────────────┐
                 │ Did the crash start right after a deploy or  │
                 │ config/secret change in the last ~1h?        │
                 └───────────────┬───────────────┬─────────────┘
                            YES  │               │  NO
                                 ▼               ▼
                    ┌────────────────────┐   ┌──────────────────────────────┐
                    │  ROLLBACK NOW       │   │ Is a DOWNSTREAM dependency    │
                    │ (fastest safe mit.) │   │ (Kafka/DB/cache) unhealthy?   │
                    └─────────┬──────────┘    └───────┬───────────────┬──────┘
                              │                   YES │               │ NO
                              ▼                       ▼               ▼
                   service recovers?        ┌──────────────────┐  ┌──────────────────────────┐
                       │      │             │ Don't rollback.  │  │ Is it resource/traffic    │
                    YES│    NO│             │ Escalate to dep  │  │ (OOMKilled / scheduling /  │
                       ▼      ▼             │ owner; mitigate  │  │ spike absorbing capacity)? │
                  monitor   treat as        │ (failover/queue) │  └────────┬─────────────┬─────┘
                  + PIR     dependency/      └──────────────────┘      YES  │             │ NO
                            code issue ↓                                    ▼             ▼
                                                              ┌──────────────────┐  ┌───────────────┐
                                                              │ SCALE-OUT:       │  │ HOTFIX:        │
                                                              │ raise replicas / │  │ targeted fix   │
                                                              │ bump mem limit / │  │ (config/flag), │
                                                              │ add nodes        │  │ deploy via     │
                                                              └──────────────────┘  │ pipeline       │
                                                                                    └───────────────┘
```

### 3a. ROLLBACK — default when a recent change caused it (fastest, safest)

```bash
# Roll back to the previous known-good revision
kubectl -n $NS rollout undo deploy/$SVC
kubectl -n $NS rollout status deploy/$SVC --timeout=180s
```

If you use **Argo Rollouts**:

```bash
kubectl argo rollouts -n $NS abort $SVC      # stop the bad canary
kubectl argo rollouts -n $NS undo $SVC       # revert to stable
```

> **Prefer rollback over hotfix during an active incident.** Rollback is a known-good state; a hotfix is untested code written under pressure. Only hotfix when rollback is impossible (e.g. a forward-only DB migration) or won't fix it.

### 3b. SCALE-OUT — when it's capacity/traffic (OOMKilled, spike, scheduling)

```bash
# More replicas to absorb load (campaign spikes are 10–50x baseline)
kubectl -n $NS scale deploy/$SVC --replicas=<2x current>

# If OOMKilled: raise the memory limit (temporary mitigation; codify later)
kubectl -n $NS set resources deploy/$SVC --limits=memory=<higher> --requests=memory=<higher>

# If FailedScheduling: confirm Cluster Autoscaler/Karpenter is adding nodes
kubectl -n kube-system logs -l app=cluster-autoscaler --tail=50
```

> Spot interruptions can present as capacity loss — check whether nodes were reclaimed; the On-Demand baseline should still hold critical pods (see Section 1 node-group strategy).

### 3c. HOTFIX — only when rollback/scale-out don't apply

- Use a **feature flag / config toggle** to disable the broken path if one exists (fastest, no deploy).
- Otherwise make the **smallest possible** change, get a second pair of eyes in `#inc-<id>`, and ship through the **normal pipeline** (canary if available) — never `kubectl edit` raw in prod (that *creates* drift, the cause of the prior P0s).

### After ANY mitigation

```bash
kubectl -n $NS get pods -l app=$SVC -w     # confirm pods stay Ready
```

Confirm on dashboards: SLO burn rate dropping, Kafka producer error rate back to baseline, no event backlog growing. Post status to `#inc-<id>`.

---

## 4. Escalation criteria & communication

### When to escalate (don't be a hero)

Escalate to **secondary on-call / team-ingestion** immediately if **any** is true:

- Full outage (all replicas down) and rollback didn't recover within **10 minutes**.
- Root cause is a **downstream dependency** you don't own (Kafka, DB, platform) → page that owner.
- You are **unsure** which action is safe, or the decision tree leads to HOTFIX.
- Customer data loss is occurring or likely (events being dropped).
- **15 minutes** elapsed with no mitigation → escalate to **Eng Manager** + declare higher severity / **Incident Commander**.

| Time / condition | Action |
|------------------|--------|
| T+0 | Ack page, declare incident, start triage |
| T+10m, not mitigated | Page secondary on-call |
| T+15m, not mitigated | Page Eng Manager, assign Incident Commander, start customer comms |
| Data loss / SLA at risk | Notify Support + Customer Success leads now |

### Internal update template (post in `#inc-<id>`, every ~15 min)

> See [`../templates/incident-comms-internal.md`](../templates/incident-comms-internal.md). Short form:
>
> **[SEV1] event-ingestion crashlooping — UPDATE T+XXm**
> **Impact:** inbound campaign events delayed/dropped in <region>, ~X% requests failing.
> **Current status:** investigating / mitigating / monitoring.
> **Actions taken:** <e.g. rolled back to rev N>.
> **Next step / ETA:** <…>. **IC:** <name>. **Next update:** T+XXm.

### Customer-facing template (via Support / status page)

> See [`../templates/incident-comms-customer.md`](../templates/incident-comms-customer.md). Keep it factual, no internal jargon, no root-cause speculation:
>
> *"We are investigating elevated errors affecting event ingestion in <region> beginning <time UTC>. Some campaign events may be delayed. We are actively working to restore normal service and will update within 30 minutes."*

---

## 5. Closeout & Post-Incident Review (PIR)

Once stable for **30 minutes**:

1. Downgrade severity, post "monitoring → resolved" in `#inc-<id>`, update the status page.
2. **Open a PIR within 24h** using [`../templates/pir-template.md`](../templates/pir-template.md).
3. Ensure any *temporary* mitigation (bumped mem limit, extra replicas, raw edit) is **codified in IaC/Helm** so it doesn't become drift.

### The PIR must capture

- **Timeline** (detection → mitigation → resolution, with timestamps).
- **Impact**: duration, % requests failed, events delayed/dropped, customers/tenants affected, SLO/error-budget consumed.
- **Root cause** (technical) **and contributing factors** (process/observability gaps) — **blameless**.
- **Detection quality**: did we alert fast? was the right alert (SLO burn) the one that fired, or did a noisy symptom alert mislead?
- **What went well / what was hard** (e.g. missing logs, unclear runbook step → fix the runbook).
- **Action items**: each with an owner, due date, and tracking ticket — e.g. add a PodDisruptionBudget, fix the memory leak, add a pre-deploy check, tune the liveness probe, add a dependency-health pre-check.
- **Follow-up verification**: how we'll confirm the fix (and whether to add a game-day scenario).

---

## Appendix — one-shot triage snippet

```bash
NS=production SVC=event-ingestion
kubectl -n $NS get deploy $SVC
kubectl -n $NS get pods -l app=$SVC -o wide
kubectl -n $NS describe pod -l app=$SVC | sed -n '/Last State/,/Ready/p'
kubectl -n $NS logs -l app=$SVC --previous --tail=200
kubectl -n $NS rollout history deploy/$SVC
kubectl -n $NS get events --sort-by=.lastTimestamp | tail -30
```
