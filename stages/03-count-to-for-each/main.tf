# =====================================================================
# PLAT-102: Track services by NAME (for_each), not POSITION (count)
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

# One ID per service, tracked by NAME (for_each).
resource "random_id" "svc" {
  for_each    = toset(var.services)
  byte_length = 4
}

resource "local_file" "svc" {
  for_each = toset(var.services)
  filename = "${path.module}/infra/services/${each.key}.json"
  content = jsonencode({
    service    = each.key
    service_id = "${each.key}-${random_id.svc[each.key].hex}"
    cluster    = random_pet.cluster_name.id
  })
}

# Production database master password.
resource "random_password" "db" {
  length = 24
}

resource "local_sensitive_file" "db_env" {
  filename = "${path.module}/infra/secrets/db.env"
  content  = "DB_HOST=shopstack-db.internal\nDB_USER=app\nDB_PASSWORD=${random_password.db.result}\n"
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

output "cluster_name" {
  value = random_pet.cluster_name.id
}

output "service_ids" {
  value = { for name, id in random_id.svc : name => id.hex }
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
