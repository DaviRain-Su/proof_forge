#!/usr/bin/env bash
# TransferSol offline product path via developer CLI `pf` (was raw cargo client).
# Build + offline verify (+ adapter pins). No RPC.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/pf_resolve.sh
source "$root/scripts/pf_resolve.sh"
pf_require || exit $?

export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-${HOME}/.cache/proof-forge-v2/tool-root/darwin-arm64}"
# Prefer built solana-client for verify
if [[ -z "${PROOF_FORGE_SOLANA_CLIENT:-}" ]]; then
  for c in \
    "$root/clients/solana-client/target/release/proof-forge-solana-client" \
    "$root/clients/solana-client/target/debug/proof-forge-solana-client"
  do
    [[ -x "$c" ]] && export PROOF_FORGE_SOLANA_CLIENT="$c" && break
  done
fi
if [[ -z "${PROOF_FORGE_SOLANA_CLIENT:-}" ]]; then
  cargo build --manifest-path "$root/clients/solana-client/Cargo.toml" --locked --release
  export PROOF_FORGE_SOLANA_CLIENT="$root/clients/solana-client/target/release/proof-forge-solana-client"
fi

out="${PROOF_FORGE_TRANSFER_SOL_OUT:-$root/build/v2/solana-transfer-sol-product}"
rm -rf "$out"
echo "solana-transfer-sol-offline: pf build → $out"
"$PF" build Examples/TransferSol.lean \
  --module Examples.TransferSol \
  --target solana \
  -o "$out"
echo "solana-transfer-sol-offline: pf verify (+ adapter)"
"$PF" verify -t solana --artifact "$out"
"$PF" verify -t solana --artifact "$out" --adapter transfer-sol-v1
echo "solana-transfer-sol-offline: ok"
