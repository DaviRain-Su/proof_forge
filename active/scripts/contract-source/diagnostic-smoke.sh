#!/usr/bin/env bash
set -euo pipefail

# Validate that contract_source builds reject capabilities unsupported by the
# selected target before backend-specific lowering runs.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="$ROOT/build/contract-source-diagnostics/unsupported-near"
STDOUT_LOG="$OUT/stdout.log"
STDERR_LOG="$OUT/stderr.log"

rm -rf "$OUT"
mkdir -p "$OUT"

lake build proof-forge >/dev/null

set +e
lake env proof-forge build --target wasm-near \
  --root . \
  -o "$OUT/near" \
  Tests/ContractSource/UnsupportedNear.lean \
  >"$STDOUT_LOG" 2>"$STDERR_LOG"
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  echo "contract-source-diagnostics: expected wasm-near unsupported capability to fail" >&2
  echo "stdout:" >&2
  cat "$STDOUT_LOG" >&2
  echo "stderr:" >&2
  cat "$STDERR_LOG" >&2
  exit 1
fi

require_stderr() {
  local expected="$1"
  if ! grep -Fq -- "$expected" "$STDERR_LOG"; then
    echo "contract-source-diagnostics: missing expected diagnostic fragment" >&2
    echo "expected: $expected" >&2
    echo "stdout:" >&2
    cat "$STDOUT_LOG" >&2
    echo "stderr:" >&2
    cat "$STDERR_LOG" >&2
    exit 1
  fi
}

require_stderr "target \`wasm-near\` does not support capability \`crosscall.cpi\`"
require_stderr "on operation \`contract_source.solana_cpi\`"
require_stderr "Tests/ContractSource/UnsupportedNear.lean:contract_source.use"

echo "contract-source-diagnostics: ok"
