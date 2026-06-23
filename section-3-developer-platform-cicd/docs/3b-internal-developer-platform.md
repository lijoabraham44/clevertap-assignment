# 3b. Internal Developer Platform — Safe Self-Serve Environments

**Ask:** product engineers want to spin up **isolated environments** (databases, queues, caches) for feature testing **without waiting on DevOps**. Design an IDP capability that allows this *safely*, balancing **speed of provisioning** vs **cost governance, security guardrails, and cleanup automation**.

> **Why this approach** is recorded in [`design-rationale.md`](design-rationale.md) (ADR-08). The short version: expose **curated golden paths**, not raw cloud access — developers get speed, the platform keeps governance.

## The core idea: a paved road, not a blank cheque

The failure mode to avoid is "give everyone Terraform/IAM and hope" — that recreates the click-ops sprawl and cost overruns this whole initiative is fighting. Instead, the platform team builds **opinionated, parameter-limited templates** once; developers self-serve **instances** of them.

```
 Developer                      Platform (golden paths)                 AWS / EKS
 ─────────                      ───────────────────────                 ─────────
 Backstage portal  ─┐
   or               ├─►  Environment Claim (small YAML/form)  ─►  Crossplane Composition
 `kubectl apply`  ─┘         name, ttl, size(t-shirt),             (encodes defaults:
                              needs: [postgres, redis, kafka]        encryption, private
                                                                     subnets, tags, size caps)
                                                       │
                                                       ▼
                                       Provisions an ISOLATED stack:
                                       namespace + RDS + ElastiCache + MSK/SQS
                                       (private, tagged, TTL-stamped)
```

## Architecture & tooling

| Layer | Choice | Role |
|-------|--------|------|
| **Portal / interface** | **Backstage** (or Port) software catalog + a `kubectl`-applyable **Claim** | The self-serve front door: a form or a small YAML, not Terraform. |
| **Provisioning control plane** | **Crossplane** Compositions (XRDs) | Turns a high-level Claim (`needs: [postgres, redis]`) into the concrete cloud resources, with all guardrails baked into the Composition. (Alternative: Terraform modules behind Atlantis/a service — Crossplane chosen for its k8s-native, continuously-reconciled, self-service Claim model.) |
| **GitOps** | Argo CD | Claims live in Git; environments are reconciled and auditable; deleting the Claim deletes the environment. |
| **Policy** | OPA Gatekeeper / Kyverno | Admission-time guardrails (size caps, required tags, no public exposure). |
| **Cost** | Tags + Kubecost/CE budgets | Per-environment cost attribution and caps. |

A developer's request looks like [`../idp/environment-claim.example.yaml`](../idp/environment-claim.example.yaml) — a dozen lines, no cloud knowledge required.

## Balancing the four forces

### 1. Speed of provisioning
- **Self-service, no ticket:** apply a Claim (or click in Backstage) → environment in minutes; no DevOps in the loop.
- **T-shirt sizes** (`small/medium/large`) instead of dozens of knobs — pick one, go.
- **Pre-baked Compositions** mean the hard/slow decisions (networking, encryption, subnet placement) are already made and reused.
- **Templated, reproducible:** every environment is identical and disposable, so engineers trust and recreate them freely.

### 2. Cost governance
- **TTL by default** (see cleanup) — the biggest cost lever; nothing lives forever.
- **Size caps in the Composition:** the platform decides the max instance class; a Claim physically cannot request a `db.r6g.16xlarge`.
- **Mandatory tagging** (`owner`, `team`, `cost-center`, `ttl`, `environment=ephemeral`) injected by the Composition → enables showback/chargeback (ties into Section 4 FinOps) and per-team budgets.
- **Per-team quotas & budgets:** ResourceQuotas on the namespace; AWS Budgets/Kubecost alerts per `team` tag; a cap on concurrent ephemeral environments per team.
- **Cheap defaults:** Spot-backed nodes, single-AZ, smallest viable instance classes, auto-stop of idle DBs.

### 3. Security guardrails
- **Secure-by-default Compositions:** private subnets only, encryption at rest (KMS) + in transit, no public endpoints, security groups scoped to the environment namespace.
- **No raw cloud credentials to developers:** they interact with the Claim API; Crossplane (running with a tightly-scoped IRSA role) does the privileged work. Least privilege is the platform's, not the user's.
- **Isolation:** each environment is its own namespace + dedicated data stores; network policies prevent cross-environment and prod access. Ephemeral envs run in a **separate non-prod account** — they can never touch production data.
- **Admission policy (OPA/Kyverno):** rejects Claims missing required tags, exceeding size caps, or requesting disallowed regions/public access.
- **Synthetic/anonymized data only** for feature testing — no production PII in ephemeral environments.

### 4. Cleanup automation (the part teams always forget)
- **TTL is mandatory** on every Claim (e.g. `ttl: 72h`); a controller/CronJob garbage-collects expired environments automatically. Default + maximum TTL enforced by policy.
- **Idle detection:** environments with no traffic/activity for N hours are flagged and reaped (or auto-stopped to save cost, restartable on demand).
- **GitOps deletion:** because the environment *is* the Claim, removing the Claim (or PR-close hook for per-PR preview envs) tears everything down — no orphaned resources.
- **Expiry warnings:** Slack/email to the `owner` tag before reaping, with one-click extend (still bounded by max TTL).
- **Drift/orphan sweeper:** a scheduled job reconciles tagged ephemeral resources against live Claims and deletes orphans — closes the "someone left a database running" gap that drives cost waste.

## Why this is the Staff-level answer

It reframes "self-serve" from *access* to *abstraction*: the platform team invests once in golden-path Compositions that **encode** cost caps, security defaults, and TTLs, so every developer self-serves at speed **without** the platform team losing governance. Speed and control stop being a trade-off because the guardrails are built into the paved road rather than enforced by a human gatekeeper.
