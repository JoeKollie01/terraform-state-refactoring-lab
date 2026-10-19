# =====================================================================
# PLAT-105 (database side): the database team's own configuration
# Adopts the EXISTING password from platform. Apply this FIRST.
# =====================================================================

terraform {
  required_version = ">= 1.7"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Same arguments as in platform, so the imported object matches exactly.
resource "random_password" "db" {
  length = 24
}

# Adopt the existing password. The handoff file is written by:
#   ./scripts/handoff-db-password.sh
# Delete the file once this has been applied.
import {
  to = random_password.db
  id = trimspace(file("${path.module}/../handoff/db_password.txt"))
}

# Other teams read this through terraform_remote_state.
output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
