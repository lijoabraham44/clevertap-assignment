# 1b. State & Drift Management

> No code required — this is the design narrative. The `live/` layout already
> implements the structure described here.

## 1. Structuring Terraform state

The guiding principle is **isolate state by the dimensions that change independently**, so a change (or a corrupt/locked state) in one place can never block or damage another. The unit of isolation is:

```
state key = <account/env> × <region> × <stack>
```

### 1.1 Across multiple AWS accounts (dev / staging / prod)

- **One AWS account per environment** (`dev`, `staging`, `prod`), ideally under AWS Organizations. This is the strongest blast-radius and security boundary — prod credentials never touch dev.
- **State lives in the same account as the resources it manages.** Each account gets its own S3 state bucket + DynamoDB lock table, created by `live/bootstrap`:
  - `clevertap-tfstate-prod-<acct-id>` / `clevertap-tflock-prod`
  - `clevertap-tfstate-staging-<acct-id>` / `clevertap-tflock-staging`
  - `clevertap-tfstate-dev-<acct-id>` / `clevertap-tflock-dev`
- This avoids a central "shared services" account becoming a single point of failure and keeps the IAM story simple: a pipeline assuming a role in the prod account can read/write only prod state.
- Buckets are **versioned + KMS-encrypted + public-access-blocked**; the lock table prevents concurrent applies.

### 1.2 Across multiple regions

- **One state file per region**, never a single global state spanning regions. Keys are namespaced by region:
  - `prod/us-east-1/platform/terraform.tfstate`
  - `prod/ap-south-1/platform/terraform.tfstate`
- Benefits: a region can be planned/applied/rolled back independently, plans are small and fast, and an outage or mistake in one region doesn't lock the other. This mirrors the `live/prod/<region>/` directory structure.
- The state **bucket** can be central (e.g. in `us-east-1`) while still keying objects per region — S3 is global-enough for this; what matters is the per-region object key.

### 1.3 Multiple stacks (further splitting within a region)

Within a region, split state by lifecycle/ownership and dependency direction, e.g.:

```
prod/us-east-1/network/      # VPC, TGW   (changes rarely, owned by platform/net team)
prod/us-east-1/platform/     # EKS, addons (changes often)
prod/us-east-1/data/         # RDS, ElastiCache
```

Downstream stacks consume upstream outputs via `terraform_remote_state` data sources (or, better, via **explicit input variables / SSM parameters** to avoid tight coupling). This keeps a noisy, frequently-changing EKS stack from forcing a re-plan of the slow-moving network layer.

### 1.4 Multiple teams contributing to the same codebase

- **Modules are versioned and immutable**: `modules/` are referenced by Git tag/registry version (`source = "...//modules/eks?ref=v1.4.0"`), so a team upgrading a module is an explicit, reviewable bump rather than an implicit change.
- **CODEOWNERS** gates the `modules/` directory to the platform team and each `live/<env>/<region>/` directory to its owning team. PRs require owner review.
- **DynamoDB state locking** serializes concurrent applies to the same state; teams working on different stacks never contend because their state keys differ.
- **CI is the only writer to prod state.** Humans run `plan` locally with read-only credentials; `apply` to staging/prod happens only through the pipeline (with OIDC-federated, short-lived credentials — no long-lived keys), giving a single audited path and consistent provider versions.
- **`.terraform.lock.hcl` is committed** so every contributor and CI uses identical provider versions.
- A consistent **directory + naming convention** (`<company>-<env>-<region-short>`) and enforced `terraform fmt` / `tflint` / `tfsec` in CI keep the codebase uniform across teams.

## 2. Drift detection & remediation

Config drift caused two P0s last quarter, so this is treated as a first-class control, not an afterthought.

### 2.1 Tooling to detect & alert on drift

| Layer | Tooling | What it catches |
|-------|---------|-----------------|
| **Scheduled plan** | A nightly CI job (GitHub Actions) running `terraform plan -detailed-exitcode` for every stack. Exit code `2` = drift → open/refresh a ticket + page `#infra-drift` Slack. | Any divergence between code and reality (the catch-all). |
| **Managed runner** | If budget allows, **Terraform Cloud/Enterprise**, **Spacelift**, or **env0** provide built-in drift detection, run history, policy-as-code, and per-workspace RBAC out of the box. | Same as above, plus governance + audit UI. |
| **Real-time guardrails** | **AWS Config** rules + **CloudTrail** alerts on out-of-band changes (e.g. someone editing a security group in the console). Conformance packs flag non-compliant resources immediately. | Detects the *act* of click-ops as it happens, not just at the nightly plan. |
| **Policy as code** | **OPA/Conftest** or **Sentinel** in the pipeline rejects non-compliant plans (e.g. public EKS endpoint, unencrypted bucket) before apply. | Prevents drift-by-merge. |

### 2.2 Remediation workflow

1. **Detect** — nightly `plan` (or managed runner) surfaces a non-empty diff; AWS Config flags the resource.
2. **Triage** — automation files a ticket with the plan output and pages the owning team via CODEOWNERS mapping. Classify: *expected* (someone forgot to codify a change) vs. *unauthorized/console hotfix*.
3. **Decide direction**:
   - **Code is source of truth (default):** run `terraform apply` to revert the resource back to declared state. This is the standard answer and what kills recurring drift.
   - **Reality should win (legitimate emergency change):** back-port the change into Terraform code via PR, review, merge, then `apply` (now a no-op). Never leave it only in the console.
4. **Prevent recurrence** — tighten IAM so humans cannot make the out-of-band change next time (read-only console in prod; mutations only via pipeline). Add an OPA/Config rule for the specific class of drift.
5. **Eliminate click-ops** — for the inherited 40% click-ops resources, run **`terraform import`** (or generate config with `import` blocks / Terraformer) to bring them under management, then they too are covered by drift detection.

### 2.3 Guardrails that make drift rare in the first place

- Prod console access is **read-only** for humans; all mutations go through CI with OIDC short-lived creds.
- **Branch protection + required checks** (`fmt`, `validate`, `tflint`, `tfsec`, `plan`, OPA) on the IaC repo.
- **`prevent_destroy`** lifecycle on stateful resources (state buckets, RDS, KMS keys).
- A weekly **drift dashboard** (count of drifted resources per stack) tracked as an SLI — the goal is to drive it to zero and keep it there.
