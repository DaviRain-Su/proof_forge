#!/usr/bin/env bash
# Full MiniAmmAssets business matrix on Surfpool (engineering).
#
# Flow:
#   1. start Surfpool (default SURFPOOL_NETWORK=mainnet for classic Token/ATA)
#   2. product build + deploy MiniAmmAssets.so (SBPFv3)
#   3. Rust runner: init → addLiquidity → swap0to1 → slippage → removeLiquidity
#   4. tear down
#
# Requires Surfpool ≥1.5, Solana CLI 4.x, network for mainnet fork.
# Not formal / not Mollusk substitute.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

die() { echo "solana-miniamm-assets-surfpool-business: FAIL: $*" >&2; exit 1; }

if [[ -x "${HOME}/.local/bin/surfpool" ]]; then
  PATH="${HOME}/.local/bin:${PATH}"
  export PATH
fi
if [[ -d "${HOME}/.local/share/solana/install/active_release/bin" ]]; then
  PATH="${HOME}/.local/share/solana/install/active_release/bin:${PATH}"
  export PATH
fi
for tool in surfpool solana solana-keygen cargo; do
  command -v "$tool" >/dev/null 2>&1 || die "missing $tool"
done

cli="$root/.lake/build/bin/proof-forge-next"
if [[ ! -x "$cli" ]]; then
  echo "solana-miniamm-assets-surfpool-business: building proof-forge-next..." >&2
  lake build proof_forge_next || die "lake build proof_forge_next failed"
fi

case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *) die "unsupported host" ;;
esac
tool_root="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"
[[ -f "$tool_root/sbpf" || -x "$tool_root/sbpf" ]] || die "sbpf missing under $tool_root"

out_rel="build/v2/solana-miniamm-assets-surfpool"
out="$root/$out_rel"
program_name="MiniAmmAssets"
elf="$out/${program_name}.so"

if [[ -n "${PROOF_FORGE_MINIAMM_ASSETS_OUT:-}" && -f "${PROOF_FORGE_MINIAMM_ASSETS_OUT}/${program_name}.so" ]]; then
  out="$PROOF_FORGE_MINIAMM_ASSETS_OUT"
  elf="$out/${program_name}.so"
else
  echo "solana-miniamm-assets-surfpool-business: building MiniAmmAssets..." >&2
  rm -rf "$out"
  lake env "$cli" build Examples/MiniAmmAssets.lean \
    --module Examples.MiniAmmAssets \
    --target solana \
    --profile solana-sbpf-cpi-elf-v1 \
    -o "$out_rel" \
    || die "product build failed"
fi
[[ -f "$elf" ]] || die "missing $elf"
elf_size="$(wc -c <"$elf" | tr -d ' ')"

surf_dir="$root/runtime-tests/solana/surfpool"
cleanup() {
  bash "$root/scripts/solana_surfpool_down.sh" || true
}
trap cleanup EXIT

# Mainnet fork so classic Token + ATA exist at fixed program ids.
export SURFPOOL_NETWORK="${SURFPOOL_NETWORK:-mainnet}"
echo "solana-miniamm-assets-surfpool-business: SURFPOOL_NETWORK=$SURFPOOL_NETWORK" >&2
bash "$root/scripts/solana_surfpool_up.sh" >/dev/null
rpc="$(tr -d '[:space:]' <"$surf_dir/rpc-url.txt")"
payer_kp="$surf_dir/keys/payer.json"
program_kp="$surf_dir/keys/program.json"
[[ -f "$payer_kp" && -f "$program_kp" ]] || die "keypairs missing"
program_id="$(solana-keygen pubkey "$program_kp")"
echo "solana-miniamm-assets-surfpool-business: rpc=$rpc program_id=$program_id" >&2

# Deploy product ELF.
echo "solana-miniamm-assets-surfpool-business: deploying elf=${elf_size}B..." >&2
solana program deploy "$elf" \
  --url "$rpc" \
  --keypair "$payer_kp" \
  --program-id "$program_kp" \
  --max-len "$((elf_size + 65536))" \
  || die "program deploy failed"
solana program show "$program_id" --url "$rpc" --keypair "$payer_kp" >/dev/null \
  || die "program show failed"

# Build + run business runner.
runner="$root/runtime-tests/solana/surfpool/runner"
echo "solana-miniamm-assets-surfpool-business: cargo build runner..." >&2
cargo build --manifest-path "$runner/Cargo.toml" --release \
  || die "runner cargo build failed"
export SURFPOOL_RPC_URL="$rpc"
export SURFPOOL_PAYER_KEYPAIR="$payer_kp"
export SURFPOOL_PROGRAM_KEYPAIR="$program_kp"
"$runner/target/release/pf-surfpool-miniamm-business" \
  || die "business runner failed"

echo "solana-miniamm-assets-surfpool-business: ok" >&2
echo "solana-miniamm-assets-surfpool-business: engineering only; not formal/mainnet claim" >&2
