# =====================================================================
# ShopStack platform - LEGACY configuration
# Inherited from an engineer who left the company. Works in production.
# Your job: clean it up WITHOUT destroying anything.
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

# The production cluster name. Yes, it is really called "x".
resource "random_pet" "x" {
  length = 2
  prefix = "shopstack"
}

resource "local_file" "file1" {
  filename = "${path.module}/infra/cluster.json"
  content = jsonencode({
    cluster_name = random_pet.x.id
    region       = "us-east-1"
    k8s_version  = "1.30"
  })
}

# One ID per service, tracked by list POSITION (count).
resource "random_id" "svc" {
  count       = length(var.services)
  byte_length = 4
}

resource "local_file" "svc" {
  count    = length(var.services)
  filename = "${path.module}/infra/services/${var.services[count.index]}.json"
  content = jsonencode({
    service    = var.services[count.index]
    service_id = "${var.services[count.index]}-${random_id.svc[count.index].hex}"
    cluster    = random_pet.x.id
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

output "cluster_name" {
  value = random_pet.x.id
}

output "service_ids" {
  value = { for i, s in var.services : s => random_id.svc[i].hex }
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
