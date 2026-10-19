#!/usr/bin/env bash
# Deletes workspace/ (all state and simulated infrastructure) to start over.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
read -r -p "Delete $ROOT/workspace and start over? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  rm -rf "$ROOT/workspace"
  echo "Workspace removed. Start again with: ./scripts/use-stage.sh 1"
else
  echo "Cancelled."
fi
