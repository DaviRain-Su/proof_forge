#!/usr/bin/env bash
# Host-heavy Aleo integration: fresh DevNet → product build → explicit deploy
# and execute → separate receipt + mapping observation. Not ordinary CI/formal.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

keep="${PROOF_FORGE_ALEO_DEVNET_INTEGRATION_KEEP:-0}"
workdir="$(mktemp -d "$root/build/aleo-devnet-integration.XXXXXX")"
out="$workdir/output"
receipt="$workdir/deployment-receipt"
endpoint="http://127.0.0.1:${PROOF_FORGE_ALEO_DEVNET_PORT_BASE:-3030}"

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  set +e
  bash scripts/aleo_devnet.sh stop
  if [[ "$keep" == "1" ]]; then
    echo "integration(aleo-devnet): retained workdir=$workdir"
  else
    rm -rf "$workdir"
  fi
  exit "$rc"
}

on_int() {
  trap - INT TERM
  exit 130
}

on_term() {
  trap - INT TERM
  exit 143
}

trap cleanup EXIT
trap on_int INT
trap on_term TERM

echo "integration(aleo-devnet): start fresh loopback-only DevNet"
bash scripts/aleo_devnet.sh start
bash scripts/aleo_devnet.sh wait --timeout-seconds 180

echo "integration(aleo-devnet): build compile-profile OutputSet (network-free)"
PROOF_FORGE_ALEO_EMIT_LEO=1 \
  lake env .lake/build/bin/proof-forge-next build \
    Examples/StateCell.lean \
    --module Examples.StateCell \
    --target aleo \
    --profile aleo-leo-4.0.2-u64-compile-v1 \
    -o "$out"

echo "integration(aleo-devnet): deploy existing OutputSet with funded local dev-key 0"
/usr/bin/python3 -I -S scripts/aleo_network_receipt.py \
  --output-dir "$out" \
  --receipt-dir "$receipt" \
  --network devnet \
  --endpoint "$endpoint" \
  --dev-key 0 \
  --broadcast \
  --execute-state-cell \
  --priority-fee 1000000 \
  --wait-timeout-seconds 600 \
  --visibility-timeout-seconds 600

/usr/bin/python3 -I -S - "$receipt/receipt.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
receipt = json.loads(path.read_text(encoding="utf-8"))
assert receipt["schema"] == "proof-forge.aleo-deployment-receipt.engineering.v1"
assert receipt["network"]["environment"] == "local"
assert receipt["networkProfile"]["registrationStatus"] == "unregistered-engineering"
assert receipt["deployment"]["status"] == "confirmed"
assert receipt["deployment"]["programVisible"] is True
assert receipt["build"]["programId"] == "statecell.aleo"
assert [item["function"] for item in receipt["executions"]] == ["initialize", "increment"]
observed = {(item["path"], item["value"]) for item in receipt["observations"]}
assert ("pf_state_0/0u8", "3u64") in observed
assert ("initialized/0u8", "true") in observed
assert receipt["security"]["privateKeyRecorded"] is False
assert receipt["security"]["privateKeyPathRecorded"] is False
print("integration(aleo-devnet): receipt + mapping assertions passed")
PY

echo "integration(aleo-devnet): PASS"
