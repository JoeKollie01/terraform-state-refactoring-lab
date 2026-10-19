# Terraform State Refactoring Lab: The ShopStack Cleanup

A hands-on, scenario-based lab for refactoring Terraform **state** safely: renaming resources, migrating `count` to `for_each`, extracting modules, importing hand-made resources, splitting one state into two, and recovering from a state mistake.

Everything runs locally with the `random` and `local` providers. **No cloud account, no cost.** The patterns are the same ones you'd use on AWS, Azure, or GCP.

---

## The scenario

You just joined **ShopStack**, a growing e-commerce company, as a platform engineer. The production platform is managed by a Terraform config written two years ago by an engineer who has since left.

It works. Customers are buying things. But the code is a mess:

- The production cluster is literally named `random_pet.x`
- Services are tracked by list position, so removing one quietly corrupts another
- The same service pattern is copy-pasted
- During an incident, on-call created a webhook secret **by hand** that Terraform doesn't know about
- The database team wants to own the database credentials in **their own** state

Your manager has given you five tickets. The rule for every one of them:

> **Refactor the code. Change nothing real. Every plan must end in `0 to destroy`.**

---

## What you'll practice

| Ticket | Real-world problem | Tool you'll use |
|---|---|---|
| Stage 1 | Explore a legacy state, see why `count` is dangerous | `state list`, `state show`, `output` |
| PLAT-101 | Rename resources | `moved` block |
| PLAT-102 | Migrate `count` to `for_each` | `moved` with instance keys |
| PLAT-103 | Extract a reusable module | `moved` into module addresses, chained moves |
| PLAT-104 | Adopt a resource created by hand (ClickOps) | `import` block |
| PLAT-105 | Split one state into two team-owned states | `removed` block + `import` + `terraform_remote_state` |
| Break-glass | Someone ran `terraform state rm` by mistake | State backups and restore |

---

## Requirements

- **Terraform 1.7 or newer** (`terraform version`). Stage 6 uses the `removed` block with `lifecycle { destroy = false }`, which arrived in 1.7.
- Bash (Linux, macOS, or WSL on Windows)

---

## How the lab works (read this first)

```
terraform-state-refactoring-lab/
├── stages/            <- the code for each ticket (read-only reference)
│   ├── 01-legacy/
│   ├── 02-rename/
│   ├── 03-count-to-for-each/
│   ├── 04-extract-module/
│   ├── 05-import-clickops/
│   └── 06-split-state/
│       ├── platform/
│       └── database/
├── scripts/           <- helpers, run from anywhere
└── workspace/         <- created by the scripts; this is where you run terraform
    ├── platform/      <- YOUR working directory (state lives here)
    ├── database/      <- created in stage 6
    └── backups/
```

You always run Terraform in **`workspace/platform`**. To move to the next ticket, run:

```bash
./scripts/use-stage.sh <number>
```

That script **swaps the `.tf` files** but **keeps `terraform.tfstate`**. The code changes; the "infrastructure" (the files in `workspace/platform/infra/`) and the state do not. That's exactly what happens in a real refactoring PR.

The scripts find the repo on their own, so they work from any folder. Don't copy stage folders by hand.

### The golden rules of state refactoring

1. **Back up state before you touch it.** (`./scripts/backup-state.sh`)
2. **Always `plan` before `apply`, and read every line.**
3. **If the plan says `destroy` or `must be replaced` and you didn't expect it, STOP.**
4. **Prefer config-driven changes** (`moved`, `import`, `removed` blocks) over CLI surgery (`state mv`, `state rm`, `terraform import`). Blocks are code-reviewed, show up in plans, and apply consistently for every teammate and every CI pipeline.

---

## Stage 1: Explore the legacy platform

```bash
./scripts/use-stage.sh 1
cd workspace/platform
terraform init
terraform apply
```

You've just "deployed production": 10 resources. Look around:

```bash
find infra -type f            # the "real infrastructure"
cat infra/services/catalog.json
terraform state list          # every resource address Terraform tracks
terraform state show random_pet.x
terraform output
```

**Write down the three `service_ids`.** You'll use them to prove nothing changed in later stages.

### Demo: why `count` is dangerous (plan only, do NOT apply)

Product wants to retire the `payments` service. Simulate removing it from the list:

```bash
terraform plan -var='services=["auth","catalog"]'
```

Read the plan carefully. You'll see something like:

```
# local_file.svc[1] must be replaced
    ~ service_id = "payments-77e54acd" -> "catalog-77e54acd"

# local_file.svc[2] will be destroyed
# random_id.svc[2] will be destroyed
```

Removing `payments` (index 1) shifted `catalog` from index 2 to index 1. Terraform doesn't know services by name, only by position. So `catalog` would **inherit payments' ID**, and catalog's real ID would be destroyed. In AWS, this is how people accidentally delete the wrong EC2 instance or database.

**Do not apply.** That's what PLAT-102 fixes.

---

## PLAT-101: Rename resources

> *"Nobody knows what `random_pet.x` and `local_file.file1` are. Give them real names."*

```bash
cd ../..                     # back to the repo root
./scripts/backup-state.sh plat-101
./scripts/use-stage.sh 2
cd workspace/platform
terraform plan
```

Open `main.tf` and find the `moved` blocks at the bottom. The plan should show:

```
# random_pet.x has moved to random_pet.cluster_name
# local_file.file1 has moved to local_file.cluster_manifest

Plan: 0 to add, 0 to change, 0 to destroy.
```

```bash
terraform apply
terraform state list
```

### Experiment: life without `moved`

Comment out both `moved` blocks and run `terraform plan`. Terraform now thinks you deleted `random_pet.x` and created a brand-new `random_pet.cluster_name`, so the production cluster gets a new name. Uncomment them before you continue. (If you already applied, this experiment shows nothing; run it before the apply next time.)

---

## PLAT-102: Migrate `count` to `for_each`

> *"Make it safe to remove a service."*

```bash
cd ../..
./scripts/backup-state.sh plat-102
./scripts/use-stage.sh 3
cd workspace/platform
terraform plan
```

The `moved` blocks map each **position** to a **name**:

```hcl
moved {
  from = random_id.svc[1]
  to   = random_id.svc["payments"]
}
```

The index order must match the original list (`auth`=0, `payments`=1, `catalog`=2). Getting it wrong would swap service identities, so this is the step to double-check in code review.

Expected: 6 resources "have moved", `0 to add, 0 to change, 0 to destroy`. Then:

```bash
terraform apply
terraform output service_ids     # same IDs as Stage 1?
```

### Re-run the demo (plan only)

```bash
terraform plan -var='services=["auth","catalog"]'
```

Now only `payments` is destroyed (2 resources), and `catalog` is untouched. That's the fix.

---

## PLAT-103: Extract a reusable module

> *"New services keep getting copy-pasted. Make a module."*

```bash
cd ../..
./scripts/backup-state.sh plat-103
./scripts/use-stage.sh 4
cd workspace/platform
terraform init                   # required: you added a module
terraform plan
```

Look at:

- `modules/service/`: the reusable module (one service's resources)
- `main.tf`: one `module "service"` block with `for_each`
- The new `moved` blocks, e.g. `random_id.svc["auth"]` -> `module.service["auth"].random_id.this`

Expected: `0 to add, 0 to change, 0 to destroy`. Apply it and check `terraform state list`.

### Why the old `moved` blocks are still there

Moves **chain**. Because every stage keeps the full history, a state file from *any* earlier stage can catch up in one plan: `random_id.svc[0]` -> `random_id.svc["auth"]` -> `module.service["auth"].random_id.this`. In a real team, this protects the teammate who's been on vacation, or a forgotten environment. You can delete old `moved` blocks once you're sure every state has been applied. If you publish a module that others consume, keep them much longer.

---

## PLAT-104: Import a hand-made (ClickOps) resource

> *"During incident INC-2291, on-call created the payments webhook secret by hand. It's already configured at our payment partner. Bring it under Terraform. If it changes, payments break."*

First, simulate the incident:

```bash
cd ../..
./scripts/simulate-clickops.sh
./scripts/backup-state.sh plat-104
./scripts/use-stage.sh 5
cd workspace/platform
terraform plan
```

The `import` block tells Terraform to **adopt** the existing secret instead of creating a new one:

```hcl
import {
  to = random_password.payments_webhook
  id = trimspace(file("${path.module}/../clickops/payments-webhook-secret.txt"))
}
```

(For a real cloud resource, `id` would be the resource's identifier, like an S3 bucket name or an EC2 instance ID.)

### The trap: read the plan!

This plan is **wrong on purpose**. Look for:

```
# random_password.payments_webhook must be replaced
# (imported from "...")
~ special = true -> false # forces replacement
```

The import worked, but the resource block in `main.tf` doesn't match the real object. Terraform would import the secret and then **immediately replace it**, which breaks payments. This is the #1 real-world import mistake.

**Your task:** fix `main.tf` so the configuration matches the imported object, then plan again until you see:

```
# random_password.payments_webhook will be imported
Plan: 1 to import, 1 to add, 0 to change, 0 to destroy.
```

<details>
<summary>Hint</summary>

The plan tells you exactly which argument "forces replacement." The hand-made secret was created with the provider's default for that argument.
</details>

<details>
<summary>Solution</summary>

Delete the `special = false` line from `random_password.payments_webhook`.
</details>

Then apply and verify the secret didn't change:

```bash
terraform apply
cat infra/secrets/payments-webhook.env
cat ../clickops/payments-webhook-secret.txt     # same value
```

> **Pro tip:** in real life, `terraform plan -generate-config-out=generated.tf` writes a resource block that matches the imported object, which avoids this trap.

---

## PLAT-105: Split the state between two teams

> *"The database team will own the database password in their own Terraform config. Platform must keep working, and the password must NOT change."*

This is the most realistic and most delicate ticket, because **order matters**.

```
platform state                         database state
──────────────                         ──────────────
random_password.db   ── hand-off ──▶   random_password.db   (import)
       │ removed (forget, don't destroy)        │
       ▼                                        ▼
local_sensitive_file.db_env  ◀── reads ── output "db_password"
                (terraform_remote_state)
```

**Step 1. Back up and export the current password** (while platform still owns it):

```bash
cd ../..
./scripts/backup-state.sh plat-105
./scripts/handoff-db-password.sh
./scripts/use-stage.sh 6
```

**Step 2. The database team adopts the password first:**

```bash
cd workspace/database
terraform init
terraform plan        # expect: 1 to import, 0 to add, 0 to destroy
terraform apply
rm ../handoff/db_password.txt    # never leave secrets lying around
```

**Step 3. Platform lets go, and reads it from the database team instead:**

```bash
cd ../platform
terraform init
terraform plan
```

Look at the `removed` block:

```hcl
removed {
  from = random_password.db

  lifecycle {
    destroy = false     # forget it, do NOT delete it
  }
}
```

Expected: Terraform reports that `random_password.db` will **no longer be managed** (removed from state), **0 to destroy**, and `local_sensitive_file.db_env` is **unchanged**, because it now reads the same password through `terraform_remote_state`.

```bash
terraform apply
terraform state list                         # no random_password.db
(cd ../database && terraform state list)     # random_password.db lives here now
```

### Why the order matters

Try to imagine doing step 3 first. Platform would try to read `db_password` from a database state that doesn't exist yet, and the plan would fail. Worse, without `destroy = false`, Terraform would **delete** the password before the database team had it. With real infrastructure, that's a production outage.

---

## Break-glass: recover from a state mistake

> *"A teammate ran a `terraform state rm` they found on Stack Overflow. Now the plan wants to recreate things."*

```bash
cd ../..
./scripts/backup-state.sh before-oops
cd workspace/platform
terraform state rm 'module.service["auth"].random_id.this'
terraform plan
```

Terraform has "forgotten" the auth service ID, so it plans to create a **new** one and replace the auth manifest. (`2 to add, 1 to destroy`.)

Restore from your backup:

```bash
ls ../backups/
cp ../backups/platform-<timestamp>-before-oops.tfstate terraform.tfstate
terraform plan        # back to "No changes"
```

> `terraform state rm` also writes its own `terraform.tfstate.<timestamp>.backup` next to your state. With a **remote backend** (S3, HCP Terraform), use `terraform state pull > backup.tfstate` to back up, and turn on bucket versioning or HCP state history so you can roll back.

---

## Cheat sheet: blocks vs. CLI commands

| Goal | Modern (in code, reviewable) | Legacy CLI (one-off, unreviewed) |
|---|---|---|
| Rename / move a resource | `moved { from = ... to = ... }` | `terraform state mv` |
| Adopt an existing resource | `import { to = ... id = ... }` | `terraform import` |
| Stop managing without deleting | `removed { from = ... lifecycle { destroy = false } }` | `terraform state rm` |
| Read another team's outputs | `data "terraform_remote_state"` | (copy/paste values) |
| Back up state | `terraform state pull > file` | (copy the file) |

The CLI commands still exist and are good to know (they show up on the Terraform Associate exam), but they change state immediately, without a plan, and only for the person running them.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `Blocks of type "lifecycle" are not expected here` in a `removed` block | Upgrade to Terraform 1.7+ |
| Plan shows `destroy` or `must be replaced` unexpectedly | Stop. Check the `moved` blocks and that you applied the previous stage. Compare with `terraform state list`. |
| `Module not installed` | Run `terraform init` (needed whenever a stage adds a module) |
| `Unsupported attribute` on `terraform_remote_state` in stage 6 | Apply `workspace/database` first |
| `no such file` for `clickops/...` in stage 5 | Run `./scripts/simulate-clickops.sh` |
| Everything is a mess | `./scripts/reset.sh`, then start at stage 1 |

---

## Cleanup

```bash
./scripts/reset.sh
```

Everything the lab creates lives in `workspace/`, so deleting it removes all state and simulated infrastructure.

## Next challenge

Redo the lab against a real cloud: swap `random_pet` + `local_file` for an S3 bucket, `random_id` + `local_file` for per-service SQS queues, and `random_password` for an `aws_secretsmanager_secret`. The `moved`, `import`, and `removed` steps stay exactly the same; only the resource types and import IDs change.
