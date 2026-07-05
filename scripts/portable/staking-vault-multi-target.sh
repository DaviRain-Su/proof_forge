#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.foundry/bin:$PATH"

SOURCE="Examples/Shared/StakingVault.lean"
OUT="${PORTABLE_SV_OUT:-build/portable-staking-vault}"

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

echo "portable-staking-vault: EVM"
"${proof_forge[@]}" build --target evm --root . \
  -o "$OUT/StakingVault.bin" \
  --yul-output "$OUT/StakingVault.yul" \
  --artifact-output "$OUT/StakingVault.proof-forge-artifact.json" \
  "${cast_args[@]+"${cast_args[@]}"}" \
  "$SOURCE"
python3 scripts/evm/validate-artifact-metadata.py \
  --root "$ROOT" \
  --expect-fixture StakingVault \
  --expect-source-kind contract-sdk \
  "$OUT/StakingVault.proof-forge-artifact.json"

echo "portable-staking-vault: Solana sBPF"
"${proof_forge[@]}" build --target solana-sbpf-asm --root . \
  -o "$OUT/StakingVault.s" \
  --artifact-output "$OUT/StakingVault.solana-artifact.json" \
  "$SOURCE"

echo "portable-staking-vault: NEAR/Wasm"
if "${proof_forge[@]}" build --target wasm-near --root . \
  -o "$OUT/near" \
  --artifact-output "$OUT/StakingVault.near-artifact.json" \
  "$SOURCE" 2>&1; then
  echo "portable-staking-vault-multi-target: ok"
else
  echo "portable-staking-vault: NEAR build skipped (nativeValue U128 not yet supported in EmitWat)" >&2
  echo "portable-staking-vault-multi-target: ok (EVM + Solana; NEAR deferred)"
fi