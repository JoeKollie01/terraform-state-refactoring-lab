# =====================================================================
# PLAT-105 (platform side): give the DB password to the database team
# Apply ../database FIRST, then this.
# =====================================================================

terraform {
  required_version = ">= 1.7"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

variable "services" {
  description = "Microservices running on the cluster"
  type        = list(string)
  default     = ["auth", "payments", "catalog"]
}

resource "random_pet" "cluster_name" {
  length = 2
  prefix = "shopstack"
}

resource "local_file" "cluster_manifest" {
  filename = "${path.module}/infra/cluster.json"
  content = jsonencode({
    cluster_name = random_pet.cluster_name.id
    region       = "us-east-1"
    k8s_version  = "1.30"
  })
}

# One module instance per service, tracked by NAME.
module "service" {
  source   = "./modules/service"
  for_each = toset(var.services)

  name         = each.key
  cluster_name = random_pet.cluster_name.id
  output_dir   = "${path.module}/infra/services"
}

# The database team now owns the password (see ../database).
# Platform READS it from their state instead of managing it.
data "terraform_remote_state" "database" {
  backend = "local"

  config = {
    path = "${path.module}/../database/terraform.tfstate"
  }
}

resource "local_sensitive_file" "db_env" {
  filename = "${path.module}/infra/secrets/db.env"
  content  = "DB_HOST=shopstack-db.internal\nDB_USER=app\nDB_PASSWORD=${data.terraform_remote_state.database.outputs.db_password}\n"
}

# Payments webhook secret. Created BY HAND during incident INC-2291,
# now managed by Terraform. Rotating it would break the payment partner.
resource "random_password" "payments_webhook" {
  length = 32
}

resource "local_sensitive_file" "payments_webhook_env" {
  filename = "${path.module}/infra/secrets/payments-webhook.env"
  content  = "WEBHOOK_SECRET=${random_password.payments_webhook.result}\n"
}

# ---------------------------------------------------------------------
# PLAT-105: hand the database password to the database team.
# "removed" + destroy = false means: forget it, do NOT delete it.
# ---------------------------------------------------------------------
removed {
  from = random_password.db

  lifecycle {
    destroy = false
  }
}

# ---------------------------------------------------------------------
# Refactoring history. Moves chain together, so a state file from ANY
# earlier stage can catch up in a single plan.
# ---------------------------------------------------------------------
# PLAT-101: real names
moved {
  from = random_pet.x
  to   = random_pet.cluster_name
}
moved {
  from = local_file.file1
  to   = local_file.cluster_manifest
}

# PLAT-102: list position -> service name.
# Index order MUST match the original list: auth=0, payments=1, catalog=2
moved {
  from = random_id.svc[0]
  to   = random_id.svc["auth"]
}
moved {
  from = random_id.svc[1]
  to   = random_id.svc["payments"]
}
moved {
  from = random_id.svc[2]
  to   = random_id.svc["catalog"]
}
moved {
  from = local_file.svc[0]
  to   = local_file.svc["auth"]
}
moved {
  from = local_file.svc[1]
  to   = local_file.svc["payments"]
}
moved {
  from = local_file.svc[2]
  to   = local_file.svc["catalog"]
}

# PLAT-103: resources -> module instances
moved {
  from = random_id.svc["auth"]
  to   = module.service["auth"].random_id.this
}
moved {
  from = random_id.svc["payments"]
  to   = module.service["payments"].random_id.this
}
moved {
  from = random_id.svc["catalog"]
  to   = module.service["catalog"].random_id.this
}
moved {
  from = local_file.svc["auth"]
  to   = module.service["auth"].local_file.manifest
}
moved {
  from = local_file.svc["payments"]
  to   = module.service["payments"].local_file.manifest
}
moved {
  from = local_file.svc["catalog"]
  to   = module.service["catalog"].local_file.manifest
}

output "cluster_name" {
  value = random_pet.cluster_name.id
}

output "service_ids" {
  value = { for name, svc in module.service : name => svc.id }
}
