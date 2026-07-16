#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="${PROOF_FORGE_INIT_OUT:-$ROOT/build/init-smoke-project}"
REPORT_DIR="${PROOF_FORGE_CHECK_OUT:-$ROOT/build/portable-check-smoke}"

rm -rf "$OUT"
rm -rf "$REPORT_DIR"
mkdir -p "$REPORT_DIR"

lake build proof-forge >/dev/null

echo "check-smoke: scaffold project"
lake env proof-forge init "$OUT"

if [[ "${INIT_USE_LOCAL_PROOF_FORGE:-1}" == "1" ]]; then
  cat >"$OUT/lakefile.lean" <<'EOF'
import Lake
open Lake DSL

require proofForge from "../.."

package «init-smoke» where
  version := v!"0.1.0"

lean_lib Counter where
  roots := #[`Counter]
EOF
fi

(
  cd "$OUT"
  lake update >/dev/null
  lake build Counter >/dev/null
)

test -f "$OUT/.vscode/extensions.json"
test -f "$OUT/.vscode/settings.json"
test -f "$OUT/.vscode/tasks.json"

echo "check-smoke: text check EVM"
(
  cd "$OUT"
  lake env proof-forge check --target evm --root . Counter.lean
)

echo "check-smoke: json check EVM"
(
  cd "$OUT"
  lake env proof-forge check --target evm --root . Counter.lean \
    --report-format json \
    >"$REPORT_DIR/evm-check.json"
)

python3 "$ROOT/scripts/evm/validate-check-report.py" \
  --expect-target evm \
  --expect-status ok \
  --expect-input Counter.lean \
  "$REPORT_DIR/evm-check.json"

echo "check-smoke: fixture check wasm-near"
lake env proof-forge check --target wasm-near --fixture counter --format wat

echo "check-smoke: negative contract_source capability"
NEG_OUT="$REPORT_DIR/unsupported-near"
mkdir -p "$NEG_OUT"
set +e
lake env proof-forge check --target wasm-near --root . \
  Tests/ContractSource/UnsupportedNear.lean \
  --report-format json \
  >"$NEG_OUT/stdout.json" 2>"$NEG_OUT/stderr.log"
status=$?
set -e
if [[ "$status" -eq 0 ]]; then
  echo "check-smoke: expected unsupported capability check to fail" >&2
  exit 1
fi

python3 "$ROOT/scripts/evm/validate-check-report.py" \
  --expect-target wasm-near \
  --expect-status failed \
  --expect-input Tests/ContractSource/UnsupportedNear.lean \
  "$NEG_OUT/stdout.json"

grep -Fq "capability.unsupported" "$NEG_OUT/stdout.json"

echo "check-smoke: ok"
