# Section 3 — Design Rationale (Why this approach)

ADR-style record of the major CI/CD and developer-platform decisions, with alternatives and trade-offs, mapped to CleverTap's reality: inconsistent pipelines, deploy frequency ranging 10x/day to weekly (fear of breakage), secrets hardcoded in pipeline YAMLs, no promotion gates, and teams wanting to self-serve infra without waiting on DevOps.

---

## ADR-01: One reusable "paved road" pipeline, not per-team snowflakes

**Context.** Pipelines are inconsistent; the weekly-deployers are afraid because their path is untested and manual.

**Decision.** A single, opinionated, reusable pipeline (GitHub Actions reusable workflows + a shared Helm chart library) that every service adopts. Per-service config is a thin `values.yaml`, not a bespoke pipeline.

**Why.** Velocity at a large org comes from **consistency**, not heroics. When the safe path (tests, scanning, canary, rollback) is also the *easy* path, the weekly-deployers inherit the same confidence as the 10x/day teams. It also lets the platform team improve safety for everyone in one place.

**Trade-off.** Less per-team flexibility. Accepted — escape hatches exist, but the default is the paved road.

---

## ADR-02: GitHub Actions with OIDC federation — no long-lived cloud keys

**Context.** Secrets are hardcoded in some pipeline YAMLs today (a serious finding).

**Decision.** Keep GitHub Actions (already in use), but authenticate to AWS via **OIDC role assumption** (`aws-actions/configure-aws-credentials` with `role-to-assume`), and store zero static cloud credentials in the repo.

**Why over alternatives:**
- **vs. static IAM access keys in GH secrets:** OIDC issues short-lived, automatically-rotated credentials scoped to a specific repo/branch/environment via the role trust policy. No key to leak or rotate. This directly kills the "hardcoded secrets" problem at the CI layer.
- **vs. switching CI tools (GitLab/Jenkins/Buildkite):** no compelling reason to migrate; the gaps (gates, drift, secrets) are fixable in GH Actions and migration is pure cost.

---

## ADR-03: Immutable images tagged by commit SHA; build once, promote the same artifact

**Decision.** The PR stage builds the image and tags it with the **commit SHA**, pushes to ECR. Staging and prod deploy *that exact digest* — never a rebuild, never `:latest`.

**Why.** Guarantees what you tested is what you ship (no "works in staging" drift from a re-build). SHA tags give precise traceability from a running pod back to a commit. `:latest` is banned because it's ambiguous and unrollbackable.

**Trade-off.** Must plumb the SHA/digest through promotion. Cheap and worth it.

---

## ADR-04: Shift-left security — SAST + image scan as a required PR gate

**Decision.** Every PR runs **Semgrep** (SAST on source) and **Trivy** (dependency + container image CVE scan). High/critical findings fail the check; results upload to GitHub code scanning (SARIF).

**Why.** Catch vulnerabilities before merge, where they're cheapest to fix, and make security a non-optional, visible part of the developer loop rather than a late audit. Trivy + Semgrep are best-in-class OSS (no license cost, strong rules), satisfying the "Trivy or Semgrep" requirement with both layers.

---

## ADR-05: Manual approval gate via GitHub Environments (not in-YAML hacks)

**Decision.** Staging→prod promotion is gated by a **GitHub Environment** (`production`) with required reviewers and optional wait timer. The gate is platform config, not a script.

**Why.** Environment protection rules give an auditable, RBAC-controlled approval with deployment history — the "environment promotion gates" the org lacks. It's enforced by GitHub, not bypassable by editing a job.

---

## ADR-06: Progressive delivery with Argo Rollouts (canary 10→50→100) + automated rollback

**Decision.** Production deploys as an **Argo Rollouts** canary stepping 10%→50%→100%, with `AnalysisTemplate`s querying Prometheus (success rate, p99 latency, the SLO error budget from Section 2). Failing analysis **auto-aborts and rolls back**.

**Why over alternatives:**
- **vs. plain `kubectl`/Deployment rolling update:** no traffic-percentage control, no metric-driven gates, manual rollback. That's the source of "fear of breakage."
- **vs. Flagger:** equivalent capability; Argo Rollouts chosen for its first-class `Rollout` CRD, mature dashboard/CLI, and tight fit with Argo CD GitOps. (Flagger is a fine substitute and the design is portable.)
- **vs. blue/green:** canary limits blast radius to a small % of real traffic and validates with production signals before full rollout — better for unpredictable 10–50x spike traffic.

Automated, metric-based rollback is the single biggest lever for deployment confidence: a bad deploy hurts ~10% of traffic for a minute, then self-reverts.

---

## ADR-07: No secrets in YAML — runtime injection via External Secrets Operator + AWS Secrets Manager

**Decision.** Secrets live in **AWS Secrets Manager**; **External Secrets Operator (ESO)** syncs them into Kubernetes Secrets at runtime via an IRSA-scoped `ClusterSecretStore`. Manifests reference secret *names*, never values. ESO authenticates with IRSA (no static keys).

**Why over alternatives:**
- **vs. secrets in pipeline/Helm YAML (today):** eliminates the hardcoded-secret class entirely; nothing sensitive is ever committed.
- **vs. Sealed Secrets:** encrypted-in-git is better than plaintext, but rotation is awkward and the ciphertext still lives in the repo. ESO keeps the source of truth in Secrets Manager with native rotation and centralized audit.
- **vs. CSI Secrets Store driver:** also valid (mounts as files); ESO chosen for the simpler "materialize as a normal K8s Secret/env" UX and broad provider support. Both avoid secrets-in-YAML.

---

## ADR-08: Self-serve via a golden-path IDP (Crossplane/Backstage), not raw cloud access

**Context (3b).** Product engineers want to spin up isolated DBs/queues/caches for feature testing without waiting on DevOps.

**Decision.** Expose **curated, parameter-limited templates** (Crossplane Compositions surfaced through a Backstage/Port portal or a `kubectl`-applied Claim) rather than handing out Terraform or console access.

**Why.** This is the balance the question asks for: developers get **speed** (apply a Claim, get an environment in minutes) while the platform retains **governance** — the template encodes security defaults, size/cost caps, mandatory tags, and a TTL for auto-cleanup. Raw self-serve (give everyone Terraform/IAM) would re-create the click-ops and cost sprawl this whole initiative is fighting.

**Trade-off.** The platform team must build and maintain the templates. That's the point of a platform team — build the abstraction once, everyone self-serves safely.
