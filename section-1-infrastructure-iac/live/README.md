# `live/` — Root configurations (environments)

This layer composes the reusable modules in `../modules/` into concrete, deployable stacks. It follows a **state-per-(account × region × stack)** layout so blast radius stays small and teams can work in parallel (full rationale in `../docs/1b-state-and-drift-management.md`).

```
live/
├── bootstrap/            # Run once per account: creates S3 state bucket + DynamoDB lock table
└── prod/
    ├── us-east-1/        # prod platform stack in us-east-1
    └── ap-south-1/       # IDENTICAL module calls, different locals -> standardized fleet
```

In a full repo you'd also have `dev/` and `staging/` mirroring `prod/`, each pointed at a different AWS account.

## Order of operations

1. **Bootstrap each account** (creates the remote state backend):

```bash
cd live/bootstrap
terraform init
terraform apply -var account_name=prod
# note the state_bucket / lock_table outputs, plug them into each backend.tf
```

2. **Apply a regional stack**:

```bash
cd live/prod/us-east-1
terraform init
terraform plan
terraform apply
```

3. **Repeat for ap-south-1.** Note the two `main.tf` files are intentionally near-identical — only the `locals` block changes. That is the whole point: one set of audited modules, instantiated uniformly.

4. **Cross-region TGW peering** is described in `../modules/transit-gateway/README.md` and is normally its own small dual-provider stack (e.g. `live/prod/networking/`).

## Conventions

- **Non-overlapping VPC CIDRs** across the fleet: `us-east-1 = 10.10.0.0/16`, `ap-south-1 = 10.20.0.0/16`, `eu-west-1 = 10.30.0.0/16`. Required for TGW routing.
- **Unique TGW ASN per region** (`64512`, `64513`, …) so inter-region peering BGP sessions are valid.
- **Account IDs / bucket names** in `backend.tf` are placeholders (`111122223333`) — replace with real values from `bootstrap`.
