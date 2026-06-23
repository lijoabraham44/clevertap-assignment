# 1c. EU Data Residency with a Single Control Plane

## The constraint

- **Data plane:** EU customer data (PII, event payloads, backups, logs, derived state) must **never leave `eu-west-1`**. This is a hard legal boundary (GDPR / data residency).
- **Control plane:** We must still operate **one deployment control plane** so the EU region is managed with the same pipelines, modules, and release process as every other region — not a manually-operated snowflake.

The key insight: **separate the control plane (how we deploy) from the data plane (where customer data lives).** The control plane carries *instructions and artifacts*; the data plane carries *customer data*. Only the latter is residency-constrained.

## Architecture: isolation, not federation

For a strict legal boundary I choose **hard cluster isolation over cluster federation.**

- A dedicated **EU cell**: its own AWS account (`prod-eu`), its own region (`eu-west-1`), its own VPC (`10.30.0.0/16`), its own EKS cluster, its own RDS/ElastiCache/S3/Kafka — all provisioned from the **same Terraform modules** as `us-east-1`/`ap-south-1` (just another `live/prod/eu-west-1/` directory).
- Federated control planes (e.g. KubeFed, or a single global EKS with remote nodes) are explicitly **rejected**: they create cross-region control/data paths and shared etcd/secret surfaces that are hard to prove never carry EU data. Isolation is far easier to *audit and legally attest*.
- The EU cell's **Transit Gateway is NOT peered into the global data mesh.** Inter-region TGW peering connects only `us-east-1 ↔ ap-south-1`. The EU TGW (if present) is used purely for intra-EU connectivity. There is no network route over which EU data could transit to another region.

```
            ┌─────────────────── Global Control Plane (CI/CD) ───────────────────┐
            │  GitHub Actions + Terraform + Helm/Argo (artifacts & manifests only) │
            └───────┬───────────────────┬────────────────────────┬───────────────┘
        assume-role │       assume-role  │            assume-role  │
                    ▼                    ▼                         ▼
            ┌──────────────┐     ┌──────────────┐         ┌──────────────────┐
            │ prod (US)    │     │ prod (APAC)  │         │ prod-eu (ISOLATED)│
            │ us-east-1    │◄───►│ ap-south-1   │         │ eu-west-1         │
            │ 10.10/16     │ TGW │ 10.20/16     │         │ 10.30/16          │
            └──────────────┘     └──────────────┘         └──────────────────┘
                  ▲ data plane peered (US↔APAC)                 ▲ NO data peering
```

## How the single control plane still works

The CI/CD system lives in a management account and **never stores or processes customer data** — it only pushes container images and applies manifests/Terraform. It reaches the EU cell by **assuming a role in the `prod-eu` account** (OIDC-federated, short-lived credentials), exactly as it does for US/APAC. So one pipeline, one set of modules, three (soon four) targets.

What crosses the EU boundary from the control plane:
- ✅ Container images (from a **replicated-into-EU ECR**, so even image pulls stay in-region), Helm charts, Kubernetes manifests, Terraform plans.
- ❌ Never: customer event payloads, database contents, backups, or logs containing PII.

## IAM boundary enforcement

This is enforced in depth, not by convention:

1. **Account boundary** — EU resources live in a separate account; the blast radius and credential boundary are the account itself.
2. **Service Control Policies (SCPs)** at the Organizations OU level for the EU account:
   - **Deny any API call whose region is not `eu-west-1`** (`aws:RequestedRegion` condition) — so even a compromised/misconfigured role physically cannot create resources or move data outside the EU. (Carve-outs only for genuinely global services like IAM/CloudFront, scoped tightly.)
   - **Deny disabling** CloudTrail, Config, and the residency guardrails.
   - **Deny S3 cross-region replication** destinations outside the EU and deny creating un-encrypted buckets.
3. **Permission boundaries** on the deploy roles so the pipeline can manage infra but cannot, say, create a replication rule or a peering attachment to a non-EU region.
4. **KMS key policies** keep EU data keys EU-only; keys are not shared cross-region, so even if an encrypted object leaked it couldn't be decrypted elsewhere.
5. **Data-tier controls** — RDS/S3/Kafka in the EU cell have cross-region snapshot/replication disabled; backups target EU-only buckets.

## How CI/CD enforces the residency constraint

The pipeline treats residency as a **policy gate**, failing closed:

1. **Routing by tenant** — a tenant→region mapping (config/registry) determines that EU customers are served only by the EU cell. The deployment job for the EU cell can target *only* the `prod-eu` account/region.
2. **Region pinning** — the EU workflow hard-codes `eu-west-1` and assumes only the EU deploy role; there is no path in that job to talk to another region.
3. **Policy-as-code checks (OPA/Conftest + `tfsec`)** run on every plan and **block the merge/apply** if a change to EU stacks would:
   - create a resource in a non-EU region,
   - add S3 cross-region replication / RDS cross-region snapshot copy leaving the EU,
   - create a TGW peering or VPC peering from the EU VPC to a non-EU VPC,
   - add a KMS grant or bucket policy exposing EU data outside the EU account.
4. **Provenance / artifact policy** — the EU deploy pulls images only from the EU ECR replica; a check rejects manifests referencing non-EU registries or non-EU endpoints.
5. **Continuous attestation** — AWS Config conformance pack + a nightly job assert "no EU resource has a cross-region data path," feeding the compliance dashboard used for audits.

### Net result

- **One control plane, one pipeline, one set of modules** → operational consistency and no EU snowflake.
- **Physically and legally isolated data plane** → EU data cannot leave `eu-west-1`, enforced by SCPs (preventive), policy-as-code in CI (preventive), and AWS Config (detective) — defense in depth rather than trust.
