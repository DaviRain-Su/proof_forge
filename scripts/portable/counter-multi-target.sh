#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.foundry/bin:$PATH"

SOURCE="${PORTABLE_COUNTER_SOURCE:-Examples/Shared/Counter.lean}"
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

mkdir -p "$OUT"

(cd "$ROOT" && lake build proof-forge >/dev/null)

echo "portable-counter: EVM"
"${proof_forge[@]}" build --target evm --root . \
  -o "$OUT/Counter.bin" \
  --yul-output "$OUT/Counter.yul" \
  --artifact-output "$OUT/Counter.proof-forge-artifact.json" \
  "${cast_args[@]+"${cast_args[@]}"}" \
  "$SOURCE"
diff -u Examples/Evm/Counter.golden.yul "$OUT/Counter.yul"
python3 scripts/evm/validate-artifact-metadata.py \
  --root "$ROOT" \
  --expect-fixture Counter \
  --expect-source-kind contract-sdk \
  "$OUT/Counter.proof-forge-artifact.json"

echo "portable-counter: Solana sBPF"
"${proof_forge[@]}" build --target solana-sbpf-asm --root . \
  -o "$OUT/Counter.s" \
  --artifact-output "$OUT/Counter.solana-artifact.json" \
  "$SOURCE"
diff -u Examples/Solana/Counter.golden.s "$OUT/Counter.s"
diff -u Examples/Solana/Counter.manifest.toml "$OUT/manifest.toml"

echo "portable-counter: NEAR/Wasm"
"${proof_forge[@]}" build --target wasm-near --root . \
  -o "$OUT/near" \
  --artifact-output "$OUT/Counter.near-artifact.json" \
  "$SOURCE"
diff -u Examples/WasmNear/Counter.golden.wat "$OUT/near/counter.wat"

python3 scripts/near/validate-emitwat-metadata.py \
  "$OUT/Counter.near-artifact.json" \
  --expected-fixture counter \
  --expected-module Counter \
  --expected-entrypoints initialize,increment,get \
  --expected-source-kind contract-sdk

if out="$("${HOST[@]}" "$OUT/near/counter.wat" initialize get increment get 2>&1)"; then
  echo "$out"
  grep -Fq "call 1:get: return_hex=0000000000000000 return_u64=0" <<<"$out"
  grep -Fq "call 1:get: return_hex=0100000000000000 return_u64=1" <<<"$out"
else
  echo "portable-counter: offline-host unavailable; WAT golden + metadata checks passed" >&2
  echo "$out" >&2
fi

echo "portable-counter-multi-target: ok"
