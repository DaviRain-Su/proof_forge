#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.foundry/bin:$PATH"

SOURCE="Examples/Product/RoleGatedToken.lean"
OUT="${PORTABLE_RGT_OUT:-build/portable-role-gated-token}"

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

echo "portable-role-gated-token: EVM"
"${proof_forge[@]}" build --target evm --root . \
  -o "$OUT/RoleGatedToken.bin" \
  --yul-output "$OUT/RoleGatedToken.yul" \
  --artifact-output "$OUT/RoleGatedToken.proof-forge-artifact.json" \
  "${cast_args[@]+"${cast_args[@]}"}" \
  "$SOURCE"
python3 scripts/evm/validate-artifact-metadata.py \
  --root "$ROOT" \
  --expect-fixture RoleGatedToken \
  --expect-source-kind contract-sdk \
  "$OUT/RoleGatedToken.proof-forge-artifact.json"

echo "portable-role-gated-token: Solana sBPF"
"${proof_forge[@]}" build --target solana-sbpf-asm --format s --root . \
  -o "$OUT/RoleGatedToken.s" \
  --artifact-output "$OUT/RoleGatedToken.solana-artifact.json" \
  "$SOURCE"

echo "portable-role-gated-token: NEAR/Wasm"
"${proof_forge[@]}" build --target wasm-near --root . \
  -o "$OUT/near" \
  --artifact-output "$OUT/RoleGatedToken.near-artifact.json" \
  "$SOURCE"

echo "portable-role-gated-token-multi-target: ok"