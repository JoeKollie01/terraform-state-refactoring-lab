#!/usr/bin/env bash
# Exports the CURRENT db password from platform state so the database
# team can import it (instead of generating a new one).
# Usage: ./scripts/handoff-db-password.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="${TF_BIN:-terraform}"
DIR="$ROOT/workspace/handoff"
mkdir -p "$DIR"

( cd "$ROOT/workspace/platform" && "$TF" output -raw db_password ) > "$DIR/db_password.txt"
chmod 600 "$DIR/db_password.txt"
echo "Exported to $DIR/db_password.txt (delete it after the database import!)"
