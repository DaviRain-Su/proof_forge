#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 7 ]]; then
  echo "usage: write-smoke-deploy-manifest.sh <root> <fixture> <contract-name> <source.psy> <circuit.json> <abi.json> <out.json>" >&2
  exit 2
fi

ROOT="$1"
FIXTURE="$2"
CONTRACT_NAME="$3"
SOURCE_FILE="$4"
CIRCUIT_JSON="$5"
ABI_JSON="$6"
OUT_JSON="$7"

python3 "$ROOT/scripts/psy/write-deploy-manifest.py" \
  --root "$ROOT" \
  --fixture "$FIXTURE" \
  --contract-name "$CONTRACT_NAME" \
  --source "$SOURCE_FILE" \
  --circuit-json "$CIRCUIT_JSON" \
  --abi-json "$ABI_JSON" \
  --out "$OUT_JSON"

python3 "$ROOT/scripts/psy/validate-deploy-manifest.py" \
  --root "$ROOT" \
  "$OUT_JSON"
