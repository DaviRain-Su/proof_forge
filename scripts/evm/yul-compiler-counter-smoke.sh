#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${PF_YUL_COMPILER_COUNTER_OUT:-$ROOT/build/evm-yul-compiler}"
PROOF_FORGE_BIN="${PROOF_FORGE_BIN:-$ROOT/.lake/build/bin/proof-forge}"

# `EvmRefinement.CounterRuntime.hex` is also decoded by the formal powdr runtime.
# Strip metadata below because local solc versions may emit a different version
# tag while preserving the executable runtime bytes.
EXPECTED_FULL_HEX="$(
  cd "$ROOT"
  lake build EvmRefinement.CounterRuntime >/dev/null
  lake env lean --run scripts/evm/print-counter-runtime-witness.lean
)"
EXPECTED_SHA256="$(python3 - "$EXPECTED_FULL_HEX" <<'PY'
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

if ! command -v solc >/dev/null 2>&1; then
  echo "solc not found on PATH" >&2
  echo "install solc 0.8.30 to run the Yul→bytecode verification gate" >&2
  exit 1
fi

"$PROOF_FORGE_BIN" emit --target evm --fixture counter --format bytecode \
  --yul-output "$OUT_DIR/Counter.yul" \
  --artifact-output "$OUT_DIR/Counter.proof-forge-artifact.json" \
  -o "$OUT_DIR/Counter.bin" >/dev/null

solc --strict-assembly "$OUT_DIR/Counter.yul" --bin >"$OUT_DIR/Counter.solc.log" 2>&1

compiled_hex="$(sed -n '/Binary representation:/,$p' "$OUT_DIR/Counter.solc.log" | tail -n +2 | tr -d '\n[:space:]')"

if [[ -z "$compiled_hex" ]]; then
  echo "solc did not emit binary representation (see $OUT_DIR/Counter.solc.log)" >&2
  exit 1
fi

# Strip the CBOR metadata suffix from the CLI bytecode so we compare runtime code
# only. solc --strict-assembly returns runtime code without metadata, while the
# CLI --format bytecode output appends the CBOR metadata + 2-byte length.
strip_metadata() {
  python3 - "$1" <<'PY'
import sys
hex_text = sys.argv[1].strip()
if len(hex_text) < 4:
    print(hex_text)
else:
    meta_len = int(hex_text[-4:], 16)
    total_suffix = (meta_len + 2) * 2
    if len(hex_text) < total_suffix:
        print(hex_text)
    else:
        print(hex_text[:-total_suffix])
PY
}

cli_runtime_hex="$(strip_metadata "$(tr -d '\n[:space:]' < "$OUT_DIR/Counter.bin")")"
expected_runtime_hex="$(strip_metadata "$EXPECTED_FULL_HEX")"

if [[ "$compiled_hex" != "$expected_runtime_hex" ]]; then
  echo "Yul→bytecode compilation drifted from EvmRefinement.counterCompiledRuntimeCode runtime" >&2
  echo "expected runtime: $expected_runtime_hex" >&2
  echo "actual  compiled: $compiled_hex" >&2
  echo "solc log: $OUT_DIR/Counter.solc.log" >&2
  exit 1
fi

if [[ "$cli_runtime_hex" != "$compiled_hex" ]]; then
  echo "CLI bytecode runtime does not match solc --strict-assembly output" >&2
  echo "CLI runtime: $cli_runtime_hex" >&2
  echo "solc output: $compiled_hex" >&2
  exit 1
fi

echo "evm-yul-compiler-counter-smoke: Counter Yul→bytecode via solc reproduces powdr witness runtime (canonical full sha256: $EXPECTED_SHA256)"
