# Internal Developer Platform (IDP) — self-serve environments

Supporting artifacts for [`../docs/3b-internal-developer-platform.md`](../docs/3b-internal-developer-platform.md).

## What's here

- `environment-claim.example.yaml` — the **entire interface** a product engineer uses to spin up an isolated environment (Postgres + Redis + Kafka). A dozen lines, no Terraform/cloud knowledge.

## How it works (one paragraph)

The developer applies a small `EphemeralEnvironment` Claim (or fills the equivalent Backstage form). A **Crossplane Composition** — built once by the platform team — expands it into an isolated stack with **all guardrails baked in**: private/encrypted resources, mandatory `owner`/`team`/`cost-center`/`ttl` tags, platform-capped instance sizes, and a TTL that a controller uses to **auto-reap** the environment at expiry. Admission policy (OPA/Kyverno) rejects any Claim that omits a TTL/tags or exceeds size caps. Because the environment *is* the Claim, deleting the Claim tears everything down — no orphans.

## Why an example Claim instead of the full Composition

The Claim is the developer-facing contract and best illustrates the "speed with guardrails" balance. The Crossplane Composition/XRD (the platform-team-owned implementation that enforces sizes, tags, encryption, and TTL) is substantial cloud-specific YAML; its design — what it enforces and why — is described in `../docs/3b-internal-developer-platform.md`.
