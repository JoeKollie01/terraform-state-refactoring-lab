#!/usr/bin/env bash
# Simulates an on-call engineer creating a secret BY HAND during an incident.
# Usage: ./scripts/simulate-clickops.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/workspace/clickops"
FILE="$DIR/payments-webhook-secret.txt"
mkdir -p "$DIR"

if [[ -f "$FILE" ]]; then
  echo "Already exists (not overwriting): $FILE"
  exit 0
fi

# 32 random letters and digits ("|| true": head closing the pipe early is expected)
SECRET="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 || true)"
if [[ ${#SECRET} -ne 32 ]]; then
  echo "Could not generate the secret." >&2
  exit 1
fi
printf '%s' "$SECRET" > "$FILE"
chmod 600 "$FILE"

echo "INC-2291: on-call created the payments webhook secret by hand."
echo "It is already configured at the payment partner, so it must NOT change."
echo "Stored at: $FILE"
