# Reusable module: everything ONE service needs.

terraform {
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

resource "random_id" "this" {
  byte_length = 4
}

resource "local_file" "manifest" {
  filename = "${var.output_dir}/${var.name}.json"
  content = jsonencode({
    service    = var.name
    service_id = "${var.name}-${random_id.this.hex}"
    cluster    = var.cluster_name
  })
}
