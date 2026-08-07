#!/usr/bin/env bash
# Start a local Surfpool Surfnet for ProofForge engineering deploys.
# Engineering only — not formal / mainnet / hermetic.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
surf_dir="$root/runtime-tests/solana/surfpool"
keys_dir="$surf_dir/keys"
mkdir -p "$keys_dir" "$surf_dir/.surfpool/logs"

die() { echo "solana-surfpool-up: FAIL: $*" >&2; exit 1; }

# Prefer the official installer binary (~/.local/bin) over a stale cargo install.
if [[ -x "${HOME}/.local/bin/surfpool" ]]; then
  PATH="${HOME}/.local/bin:${PATH}"
  export PATH
fi
if ! command -v surfpool >/dev/null 2>&1; then
  die "surfpool not on PATH (install: curl -sL https://run.surfpool.run/ | bash)"
fi
if ! command -v solana-keygen >/dev/null 2>&1; then
  die "solana-keygen not on PATH"
fi
surfpool_ver="$(surfpool --version 2>/dev/null | head -1 || true)"
echo "solana-surfpool-up: using $(command -v surfpool) ($surfpool_ver)" >&2

# Ephemeral local keypairs (never committed).
payer_kp="$keys_dir/payer.json"
program_kp="$keys_dir/program.json"
# Keygen may print paths to stdout — keep machine-readable stdout = RPC only.
if [[ ! -f "$payer_kp" ]]; then
  solana-keygen new --no-bip39-passphrase --silent -o "$payer_kp" >/dev/null \
    || die "generate payer keypair"
fi
if [[ ! -f "$program_kp" ]]; then
  solana-keygen new --no-bip39-passphrase --silent -o "$program_kp" >/dev/null \
    || die "generate program keypair"
fi

port="${SURFPOOL_PORT:-$((19000 + RANDOM % 500))}"
host="${SURFPOOL_HOST:-127.0.0.1}"
rpc="http://${host}:${port}"
ws_port="${SURFPOOL_WS_PORT:-$((port + 1))}"
studio_port="${SURFPOOL_STUDIO_PORT:-$((port + 2))}"

# Mode: offline (default) or network fork (mainnet|devnet|testnet).
network_mode="${SURFPOOL_NETWORK:-offline}"
extra_args=()
case "$network_mode" in
  offline)
    extra_args+=(--offline)
    ;;
  mainnet|devnet|testnet)
    extra_args+=(--network "$network_mode")
    ;;
  *)
    die "SURFPOOL_NETWORK must be offline|mainnet|devnet|testnet (got '$network_mode')"
    ;;
esac

if [[ -f "$surf_dir/pid" ]]; then
  old_pid="$(cat "$surf_dir/pid" 2>/dev/null || true)"
  if [[ -n "${old_pid:-}" ]] && kill -0 "$old_pid" 2>/dev/null; then
    die "Surfpool already running (pid=$old_pid). Run: just solana-surfpool-down"
  fi
  rm -f "$surf_dir/pid"
fi

log="$surf_dir/.surfpool/logs/surfnet.log"
: >"$log"

# Prefer no TUI/Studio for scripting; airdrop payer for deploy fees.
#
# SBPFv3 must be on for ProofForge locked-sbpf product ELFs.
# Surfpool 1.5 feature gate id (SIMD-0178/0189/0377) — not the older Agave id.
sbpf_v3_feature="5cC3foj77CWun58pC51ebHFUWavHWKarWyR5UUik7dnC"
feature_args=()
if surfpool start --help 2>&1 | grep -q -- '--feature'; then
  # Explicit gate is more reliable than --features-all (which may leave SBPFv3 off).
  feature_args+=(--feature "$sbpf_v3_feature")
  # Also enable v1/v2 gates for completeness when present in this release.
  feature_args+=(--feature "JE86WkYvTrzW8HgNmrHY7dFYpCmSptUpKupbo2AdQ9cG")
  feature_args+=(--feature "F6UVKh1ujTEFK3en2SyAL3cdVnqko1FVEXWhmdLRu6WP")
  echo "solana-surfpool-up: enabling SBPFv1/v2/v3 feature gates" >&2
else
  echo "solana-surfpool-up: WARN: surfpool lacks --feature; product ELF deploy may fail (need ≥1.x)" >&2
fi

# Note: always pass our local payer keypair for airdrop (do not rely on id.json).
nohup surfpool start \
  --host "$host" \
  --port "$port" \
  --ws-port "$ws_port" \
  --studio-port "$studio_port" \
  --no-tui \
  --no-studio \
  --no-deploy \
  --airdrop-keypair-path "$payer_kp" \
  --airdrop-amount "${SURFPOOL_AIRDROP_LAMPORTS:-10000000000000}" \
  --log-path "$surf_dir/.surfpool/logs" \
  --log-level "${SURFPOOL_LOG_LEVEL:-info}" \
  "${feature_args[@]}" \
  "${extra_args[@]}" \
  >"$log" 2>&1 &
echo $! >"$surf_dir/pid"
echo "$rpc" >"$surf_dir/rpc-url.txt"

ready=0
for _ in $(seq 1 80); do
  if curl -sS -m 1 "$rpc" -X POST -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' 2>/dev/null \
      | grep -q '"result":"ok"'; then
    ready=1
    break
  fi
  # Process died?
  if [[ -f "$surf_dir/pid" ]] && ! kill -0 "$(cat "$surf_dir/pid")" 2>/dev/null; then
    echo "solana-surfpool-up: process exited early; log:" >&2
    tail -40 "$log" >&2 || true
    rm -f "$surf_dir/pid" "$surf_dir/rpc-url.txt"
    exit 1
  fi
  sleep 0.15
done

if [[ "$ready" != 1 ]]; then
  echo "solana-surfpool-up: RPC not healthy after wait; log:" >&2
  tail -40 "$log" >&2 || true
  if [[ -f "$surf_dir/pid" ]]; then
    kill "$(cat "$surf_dir/pid")" 2>/dev/null || true
  fi
  rm -f "$surf_dir/pid" "$surf_dir/rpc-url.txt"
  exit 1
fi

payer_pk="$(solana-keygen pubkey "$payer_kp")"
program_pk="$(solana-keygen pubkey "$program_kp")"
echo "solana-surfpool-up: ok mode=$network_mode rpc=$rpc pid=$(cat "$surf_dir/pid")" >&2
echo "solana-surfpool-up: payer=$payer_pk program_id=$program_pk" >&2
echo "solana-surfpool-up: engineering only — not formal/mainnet" >&2
echo "$rpc"
