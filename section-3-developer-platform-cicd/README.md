# Section 3 — Developer Platform, CI/CD & Engineering Velocity

Implementation for **Section 3** of the CleverTap Staff DevOps assessment. Pipelines are inconsistent across teams — some deploy 10x/day, others weekly out of fear. The goal is to raise **deployment confidence and velocity** across the org with one paved-road pipeline and a safe self-serve developer platform.

Every part ships with a **"why this approach" rationale** — see [`docs/design-rationale.md`](docs/design-rationale.md).

## Repository layout

```
section-3-developer-platform-cicd/
├── README.md
├── docs/
│   ├── design-rationale.md                 # WHY the CI/CD + IDP approach was chosen (ADR-style)
│   ├── 3a-cicd-pipeline-design.md          # 3a: full pipeline incl. prod canary + rollback + secrets
│   └── 3b-internal-developer-platform.md   # 3b: self-serve IDP w/ cost/security/cleanup guardrails
├── .github/workflows/
│   ├── pr.yaml                             # 3a: PR stage (lint, test, build, SAST, ECR push w/ SHA)
│   └── staging.yaml                        # 3a: staging promotion (Helm deploy, smoke tests, approval gate)
├── deploy/
│   ├── helm/event-ingestion/              # Helm chart for the microservice (Argo Rollout-based)
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── values-staging.yaml
│   │   ├── values-production.yaml
│   │   └── templates/
│   │       ├── rollout.yaml               # 3a: Argo Rollouts canary 10→50→100
│   │       ├── analysistemplate.yaml      # 3a: automated rollback triggers (success-rate/latency)
│   │       ├── service.yaml               # stable + canary services
│   │       ├── serviceaccount.yaml        # IRSA-annotated SA
│   │       ├── externalsecret.yaml        # 3a: secrets injected at runtime (ESO + Secrets Manager)
│   │       └── _helpers.tpl
│   └── external-secrets/
│       └── clustersecretstore.yaml        # ESO ClusterSecretStore -> AWS Secrets Manager
├── scripts/
│   └── smoke-test.sh                       # staging smoke tests run by the pipeline
└── idp/
    ├── README.md                           # how the self-serve catalog works
    └── environment-claim.example.yaml      # 3b: a developer's ephemeral-env request (Crossplane Claim)
```

## How this maps to the task

| Task | Deliverable |
|------|-------------|
| **3a** PR stage (lint, unit tests, image build, SAST, ECR push w/ SHA) | [`.github/workflows/pr.yaml`](.github/workflows/pr.yaml) |
| **3a** Staging promotion (Helm deploy, smoke tests, manual approval gate) | [`.github/workflows/staging.yaml`](.github/workflows/staging.yaml) + [`scripts/smoke-test.sh`](scripts/smoke-test.sh) |
| **3a** Production canary (10→50→100, Argo Rollouts) + rollback triggers | [`docs/3a-cicd-pipeline-design.md`](docs/3a-cicd-pipeline-design.md) + [`deploy/helm/event-ingestion/templates/rollout.yaml`](deploy/helm/event-ingestion/templates/rollout.yaml) |
| **3a** Secret management (no secrets in YAML; runtime injection) | [`deploy/external-secrets/`](deploy/external-secrets/) + [`...templates/externalsecret.yaml`](deploy/helm/event-ingestion/templates/externalsecret.yaml) |
| **3b** Internal Developer Platform (self-serve, safe) | [`docs/3b-internal-developer-platform.md`](docs/3b-internal-developer-platform.md) + [`idp/`](idp/) |

## The paved road (one consistent flow for every service)

```
 PR opened ──► PR stage (lint · unit test · build · SAST/Trivy · push image:<sha> to ECR)
     │                                   (no deploy; fast feedback, security gate)
     ▼
 merge to main ──► Staging promotion (Helm deploy image:<sha> · smoke tests · MANUAL APPROVAL gate)
                                                                              │
                                                                              ▼
                                              Production (Argo Rollouts canary 10→50→100,
                                                  auto-analysis + auto-rollback on SLO breach)
```

## Principles (the thread through everything)

1. **One paved road.** A single reusable pipeline + Helm chart so a team deploying weekly gets the same safety as one deploying 10x/day — confidence comes from consistency.
2. **Shift-left security.** SAST + image scanning on every PR; **OIDC, no long-lived cloud keys**; **no secrets in YAML** (the inherited problem) — injected at runtime via ESO.
3. **Immutable, traceable artifacts.** Images tagged by **commit SHA**; the exact artifact built in PR is what reaches prod.
4. **Progressive delivery.** Canary + automated metric analysis + automatic rollback removes the "fear of breakage" that throttles velocity.
5. **Self-serve with guardrails.** Developers provision ephemeral environments themselves through a golden-path catalog — fast, but cost-capped, secure-by-default, and auto-cleaned.
