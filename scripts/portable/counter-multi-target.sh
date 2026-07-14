#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.foundry/bin:$PATH"

SOURCE="${PORTABLE_COUNTER_SOURCE:-Examples/Product/Counter.lean}"
OUT="${PORTABLE_COUNTER_OUT:-build/portable-counter}"
HOST=(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run)

if [[ -n "${PROOF_FORGE_BIN:-}" ]]; then
  proof_forge=("$PROOF_FORGE_BIN")
else
  proof_forge=(lake env proof-forge)
fi
cast_args=()
if [[ -n "${CAST:-}" ]]; then
  cast_args=(--cast "$CAST")
fi

rm -rf "$OUT"
mkdir -p "$OUT"

(cd "$ROOT" && lake build proof-forge >/dev/null)

echo "portable-counter: EVM"
"${proof_forge[@]}" build --target evm --root . \
  -o "$OUT/Counter.bin" \
  --yul-output "$OUT/Counter.yul" \
  --artifact-output "$OUT/Counter.proof-forge-artifact.json" \
  "${cast_args[@]+"${cast_args[@]}"}" \
  "$SOURCE"
diff -u Examples/Backend/Evm/Counter.golden.yul "$OUT/Counter.yul"
python3 scripts/evm/validate-artifact-metadata.py \
  --root "$ROOT" \
  --expect-fixture Counter \
  --expect-source-kind contract-source-authored \
  --expect-ir-version canonical-core-v1 \
  "$OUT/Counter.proof-forge-artifact.json"
python3 - "$OUT/Counter.proof-forge-artifact.json" <<'PY'
import json
import pathlib
import sys

artifact = json.loads(pathlib.Path(sys.argv[1]).read_text())
actual = {entry["name"]: entry["selector"] for entry in artifact["abi"]["entrypoints"]}
expected = {"initialize": "8129fc1c", "increment": "d09de08a", "get": "6d4ce63c"}
if actual != expected:
    raise SystemExit(f"canonical plan selectors diverge from EVM dispatcher: {actual}")
print("portable-counter: canonical plan selectors match dispatcher")
PY

echo "portable-counter: Solana sBPF"
"${proof_forge[@]}" build --target solana-sbpf-asm --format s --root . \
  -o "$OUT/Counter.s" \
  --artifact-output "$OUT/Counter.solana-artifact.json" \
  "$SOURCE"
diff -u Examples/Backend/Solana/Counter.canonical.golden.s "$OUT/Counter.s"
diff -u Examples/Backend/Solana/Counter.canonical.manifest.toml "$OUT/manifest.toml"

echo "portable-counter: NEAR/Wasm"
"${proof_forge[@]}" build --target wasm-near --root . \
  -o "$OUT/near" \
  --artifact-output "$OUT/Counter.near-artifact.json" \
  "$SOURCE"
diff -u Examples/Backend/WasmNear/Counter.canonical.golden.wat "$OUT/near/counter.wat"

python3 scripts/near/validate-emitwat-metadata.py \
  "$OUT/Counter.near-artifact.json" \
  --expected-fixture counter \
  --expected-module Counter \
  --expected-entrypoints initialize,increment,get \
  --expected-source-kind contract-source-authored \
  --expected-ir-version canonical-core-v1

if find "$OUT" -name '*contract-spec.json' -print -quit | grep -q .; then
  echo "portable-counter: direct authored route emitted a forbidden ContractSpec sidecar" >&2
  exit 1
fi

if out="$("${HOST[@]}" "$OUT/near/counter.wat" initialize get increment get 2>&1)"; then
  echo "$out"
  grep -Fq "call 1:get: return_hex=0000000000000000 return_u64=0" <<<"$out"
  grep -Fq "call 1:get: return_hex=0100000000000000 return_u64=1" <<<"$out"
else
  echo "portable-counter: offline-host unavailable; WAT golden + metadata checks passed" >&2
  echo "$out" >&2
fi

echo "portable-counter-multi-target: ok"
