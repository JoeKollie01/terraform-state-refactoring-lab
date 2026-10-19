#!/usr/bin/env bash
# Snapshot every state file in workspace/ before you touch anything.
# Usage: ./scripts/backup-state.sh [label]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WS="$ROOT/workspace"
LABEL="${1:-manual}"
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$WS/backups"

found=0
for dir in "$WS"/platform "$WS"/database; do
  if [[ -f "$dir/terraform.tfstate" ]]; then
    name="$(basename "$dir")"
    cp "$dir/terraform.tfstate" "$WS/backups/$name-$STAMP-$LABEL.tfstate"
    echo "Backed up $name -> backups/$name-$STAMP-$LABEL.tfstate"
    found=1
  fi
done
[[ $found == 1 ]] || echo "No state files found yet. Nothing to back up."
