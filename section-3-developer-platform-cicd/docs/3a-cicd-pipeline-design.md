# 3a. CI/CD Pipeline Design

A single **paved-road** pipeline for any containerized microservice on EKS. The same flow gives the weekly-deployer the same safety as the 10x/day team — confidence comes from consistency, not heroics.

> **Why this approach** is recorded in [`design-rationale.md`](design-rationale.md). This document is the end-to-end design; the PR and staging stages are fully implemented in [`../.github/workflows/`](../.github/workflows/), production is described here with the implemented config under [`../deploy/`](../deploy/).

## End-to-end flow

```
 PR opened
   └─► PR STAGE (.github/workflows/pr.yaml)            [no deploy]
         lint (go + helm) ─ unit tests (+coverage) ─ SAST (Semgrep)
         ─ build image ─ Trivy CVE scan ─ push image:<commit-sha> to ECR
                                   │  all checks required to merge
 merge to main
   └─► STAGING PROMOTION (.github/workflows/staging.yaml)
         deploy image:<sha> to staging (Helm, --atomic) ─ smoke tests
         ─ ⛔ MANUAL APPROVAL GATE (GitHub Environment "production")
   └─► PRODUCTION (on approval)
         Helm applies the Argo Rollout ─ canary 10% → 50% → 100%
         with metric ANALYSIS gating each step ─ AUTO-ROLLBACK on breach
```

Key invariant: **build once, promote the same artifact.** The image built and scanned in the PR (tagged with the commit SHA) is the exact digest deployed to staging and production — no rebuilds, no `:latest`.

---

## PR stage (implemented — `pr.yaml`)

| Requirement | How it's met |
|-------------|--------------|
| **Lint** | `golangci-lint` for code + `helm lint` for the chart. |
| **Unit tests** | `go test -race` with a coverage floor (fails < 70%). |
| **Container image build** | `docker/build-push-action` with GHA layer cache; built with `load: true` so it can be **scanned before push**. |
| **SAST scan** | **Semgrep** (`p/security-audit`, `p/secrets`, `p/dockerfile`) on source **and Trivy** for image/dependency CVEs — satisfies "Trivy or Semgrep" with both layers. HIGH/CRITICAL fail the PR; SARIF uploaded to GitHub code scanning. |
| **Push to ECR with commit-SHA tag** | Pushes `…/event-ingestion:<head-sha>` only after the scan passes. |
| **No static cloud keys** | AWS auth via **OIDC** (`configure-aws-credentials` + `role-to-assume`); `id-token: write`. |

---

## Staging promotion (implemented — `staging.yaml`)

| Requirement | How it's met |
|-------------|--------------|
| **Helm-based deploy to staging** | `helm upgrade --install --atomic --wait` with `values-staging.yaml`, pinned to `image.tag=<sha>`; verifies the image exists in ECR first. |
| **Automated smoke tests** | [`scripts/smoke-test.sh`](../scripts/smoke-test.sh): health, readiness, a real `POST /v1/events` (expects 202), and Kafka-producer health via `/metrics`. Failure blocks promotion. |
| **Manual approval gate** | The `promote-to-production` job uses the **GitHub Environment `production`** with required reviewers (+ optional wait timer). The gate is GitHub-enforced and auditable — not a bypassable in-YAML check. |

---

## Production promotion — Canary with Argo Rollouts (config implemented)

Production uses **Argo Rollouts** (`../deploy/helm/event-ingestion/templates/rollout.yaml`). Helm only updates the `Rollout` object; Argo Rollouts then drives the canary autonomously.

### Rollout strategy (10 → 50 → 100)

```yaml
strategy:
  canary:
    stableService: event-ingestion-stable
    canaryService:  event-ingestion-canary
    analysis:                      # runs in the background during the canary
      templates: [{ templateName: success-rate }, { templateName: latency-p99 }]
      startingStep: 1
    steps:
      - setWeight: 10
      - pause: { duration: 5m }    # bake at 10% while analysis samples metrics
      - setWeight: 50
      - pause: { duration: 10m }   # bake at 50%
      - setWeight: 100
```

1. **10%** of production traffic shifts to the new version; it bakes for 5 minutes while analysis samples real metrics.
2. If healthy, **50%** for 10 minutes.
3. If still healthy, **100%** — the canary becomes the new stable.
4. At any step, a failing analysis **aborts and reverts to stable** automatically.

> Traffic splitting is done via the stable/canary Services (`service.yaml`); with an ingress/mesh (ALB, NGINX, or Istio) the rollout uses `trafficRouting` for precise weight control rather than replica-count approximation.

### Automated rollback triggers (config: `analysistemplate.yaml`)

Argo Rollouts queries **Prometheus** (the same Section 2 SLIs) on an interval; breaching a threshold fails the analysis → automatic abort + rollback:

| AnalysisTemplate | Query (essence) | Success condition | On breach |
|------------------|-----------------|-------------------|-----------|
| `success-rate` | non-5xx ÷ total for the **canary** service | `>= 0.99` | auto-abort + rollback |
| `latency-p99` | p99 of request duration for canary | `<= 0.5s` | auto-abort + rollback |

`failureLimit: 1` means a single bad measurement reverts the deploy. Additional triggers can be added (error-budget burn rate, Kafka producer error rate, saturation). **Why this matters:** a bad deploy degrades only ~10% of traffic for ~1 minute, then self-heals with no human in the loop — this is what removes the "fear of breakage" and lets every team deploy often.

### Manual safety valves

```bash
kubectl argo rollouts -n event-ingestion get rollout event-ingestion --watch
kubectl argo rollouts -n event-ingestion promote event-ingestion   # skip a pause
kubectl argo rollouts -n event-ingestion abort   event-ingestion   # force rollback
```

---

## Secret management — no secrets in YAML (implemented)

The inherited problem is **hardcoded secrets in pipeline YAMLs**. This design removes secrets from CI and from manifests entirely:

```
AWS Secrets Manager  (source of truth, native rotation, audit)
      ▲ read (IRSA, no static keys)
External Secrets Operator (ClusterSecretStore: aws-secrets-manager)
      │ syncs by NAME -> materializes a K8s Secret at runtime
      ▼
K8s Secret  event-ingestion-secrets  ──envFrom──►  the Rollout's pods
```

- **Pipeline:** holds **zero** cloud secrets — it authenticates with **OIDC** short-lived credentials. The only thing it needs is permission to deploy.
- **Manifests:** `ExternalSecret` (`templates/externalsecret.yaml`) and `values*.yaml` reference secret **paths/properties** (e.g. `prod/event-ingestion/kafka#sasl_password`), never values.
- **Runtime injection:** ESO (`deploy/external-secrets/clustersecretstore.yaml`) authenticates to Secrets Manager via an **IRSA**-scoped role (least privilege, only this app's secret paths), pulls the values, and keeps a Kubernetes Secret in sync; the pod consumes it via `envFrom`. Rotation in Secrets Manager propagates automatically on the refresh interval.
- **Why ESO over alternatives:** keeps the source of truth in Secrets Manager (rotation + central audit) rather than committing ciphertext (Sealed Secrets) or plaintext. CSI Secrets Store is an equally valid file-mount alternative.

---

## How this raises velocity & confidence (mapped to the brief)

| Problem | This pipeline |
|---------|---------------|
| Inconsistent pipelines | one reusable paved-road workflow + chart |
| Fear of breakage → weekly deploys | canary + auto-analysis + auto-rollback |
| No promotion gates | smoke tests + GitHub Environment approval gate |
| Secrets hardcoded in YAML | OIDC + ESO; nothing sensitive in the repo |
| No drift detection (Section 1) | immutable SHA artifacts + GitOps-applied manifests |
