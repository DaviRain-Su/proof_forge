#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${PF_POWDR_COUNTER_OUT:-$ROOT/build/evm-powdr}"
PROOF_FORGE_BIN="${PROOF_FORGE_BIN:-$ROOT/.lake/build/bin/proof-forge}"
SOLC_BIN="${PF_POWDR_SOLC:-${SOLC:-solc}}"

EXPECTED_HEX="$(
  cd "$ROOT"
  lake build EvmRefinement.CounterRuntime >/dev/null
  lake env lean --run scripts/evm/print-counter-runtime-witness.lean
)"
EXPECTED_SHA256="$(python3 - "$EXPECTED_HEX" <<'PY'
import hashlib
import sys
print(hashlib.sha256(bytes.fromhex(sys.argv[1])).hexdigest())
PY
)"

mkdir -p "$OUT_DIR"

if [[ ! -x "$PROOF_FORGE_BIN" ]]; then
  echo "proof-forge binary not found: $PROOF_FORGE_BIN" >&2
  echo "run: lake build proof-forge" >&2
  exit 1
fi

if ! solc_version="$("$SOLC_BIN" --version 2>/dev/null)"; then
  echo "solc 0.8.30 not available: $SOLC_BIN" >&2
  exit 1
fi
if ! grep -q 'Version: 0\.8\.30' <<<"$solc_version"; then
  echo "powdr Counter witness requires solc 0.8.30, got:" >&2
  echo "$solc_version" >&2
  echo "set PF_POWDR_SOLC to a solc 0.8.30 binary" >&2
  exit 1
fi

"$PROOF_FORGE_BIN" emit --target evm --fixture counter --format bytecode \
  --solc "$SOLC_BIN" \
  --yul-output "$OUT_DIR/Counter.yul" \
  --artifact-output "$OUT_DIR/Counter.proof-forge-artifact.json" \
  -o "$OUT_DIR/Counter.bin" >/dev/null

actual_hex="$(tr -d '\n[:space:]' < "$OUT_DIR/Counter.bin")"
actual_sha256="$(python3 - "$OUT_DIR/Counter.bin" <<'PY'
from pathlib import Path
import hashlib
import sys

hex_text = Path(sys.argv[1]).read_text(encoding="utf-8").strip()
print(hashlib.sha256(bytes.fromhex(hex_text)).hexdigest())
PY
)"

if [[ "$actual_hex" != "$EXPECTED_HEX" ]]; then
  echo "Counter runtime bytecode drifted from EvmRefinement.counterCompiledRuntimeCode" >&2
  echo "expected sha256(bytes): $EXPECTED_SHA256" >&2
  echo "actual   sha256(bytes): $actual_sha256" >&2
  echo "artifact: $OUT_DIR/Counter.bin" >&2
  exit 1
fi

if [[ "$actual_sha256" != "$EXPECTED_SHA256" ]]; then
  echo "Counter runtime sha256 mismatch" >&2
  echo "expected: $EXPECTED_SHA256" >&2
  echo "actual:   $actual_sha256" >&2
  exit 1
fi

echo "evm-powdr-counter-runtime: Counter runtime matches embedded powdr witness ($actual_sha256)"
