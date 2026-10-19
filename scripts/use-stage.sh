#!/usr/bin/env bash
# Copies a stage's configuration into workspace/ WITHOUT touching state.
# Usage: ./scripts/use-stage.sh <1-6>      (works from any folder)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WS="$ROOT/workspace"
STAGE="${1:-}"

if [[ ! "$STAGE" =~ ^[1-6]$ ]]; then
  echo "Usage: $0 <1-6>"
  ls -1 "$ROOT/stages"
  exit 1
fi

SRC="$(ls -d "$ROOT"/stages/0"$STAGE"-* | head -1)"

# Replace the .tf files and modules/ in a folder, keep everything else
# (terraform.tfstate, .terraform/, infra/ ...).
swap_config() {
  local src="$1" dest="$2"
  mkdir -p "$dest"
  rm -f "$dest"/*.tf
  rm -rf "$dest/modules"
  cp -r "$src"/. "$dest"/
}

if [[ "$STAGE" == "6" ]]; then
  swap_config "$SRC/platform" "$WS/platform"
  swap_config "$SRC/database" "$WS/database"
else
  swap_config "$SRC" "$WS/platform"
fi

echo "Loaded stage: $(basename "$SRC")"
echo "Working folder: $WS/platform"
[[ "$STAGE" == "6" ]] && echo "Also created:   $WS/database"
echo
echo "Next: cd \"$WS/platform\" && terraform init && terraform plan"
