#!/usr/bin/env bash
# Aleo local DevNet lifecycle (host-heavy; NOT ordinary ci).
#
# Authority: docs/targets/09c-aleo-network.md
# Requires: locked leo 4.0.2 + snarkos with `test_network` feature.
#
# Usage:
#   aleo_devnet.sh start|stop|status|wait
#
# Storage: build/aleo-devnet/ (repo-local)
# REST:    http://127.0.0.1:3030  (validator 0)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="aleo-devnet"
DEVDIR="${PROOF_FORGE_ALEO_DEVNET_DIR:-$root/build/aleo-devnet}"
LEO_DEFAULT="$HOME/.cache/proof-forge-v2/tool-root/linux-x86_64/leo"
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) LEO_DEFAULT="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64/leo" ;;
esac
LEO="${PROOF_FORGE_TOOL_ROOT:+${PROOF_FORGE_TOOL_ROOT%/}/leo}"
LEO="${LEO:-$LEO_DEFAULT}"
SNARKOS="${PROOF_FORGE_ALEO_SNARKOS:-$HOME/.cache/proof-forge-v2/aleo-devnet/cargo-install/bin/snarkos}"
REST="${PROOF_FORGE_ALEO_ENDPOINT:-http://127.0.0.1:3030}"

usage() {
  cat <<'EOF'
usage: aleo_devnet.sh start|stop|status|wait

  start  — leo devnet (4 validators) with snarkos test_network binary
  stop   — stop leo parent + snarkos validators
  status — REST height + process check
  wait   — block until REST answers (up to ~3 min)

  snarkos must include feature test_network (prebuilt release binaries usually
  do not). Build once:
    LIBCLANG_PATH=... cargo install snarkos --version 4.9.0 --features test_network --locked \
      --root ~/.cache/proof-forge-v2/aleo-devnet/cargo-install
EOF
}

cmd="${1:-}"
case "$cmd" in
  start|stop|status|wait) ;;
  -h|--help|"") usage; exit 0 ;;
  *) echo "${PREFIX}: unknown command: $cmd" >&2; usage >&2; exit 2 ;;
esac

if [[ ! -x "$LEO" ]]; then
  echo "${PREFIX}: PF-TOOLCHAIN-MISSING: leo not found at $LEO" >&2
  exit 2
fi
if [[ ! -x "$SNARKOS" ]]; then
  echo "${PREFIX}: PF-TOOLCHAIN-MISSING: snarkos (test_network) not found at $SNARKOS" >&2
  echo "${PREFIX}: see usage for cargo install with --features test_network" >&2
  exit 2
fi

stop_devnet() {
  if [[ -f "$DEVDIR/devnet.pid" ]]; then
    kill "$(cat "$DEVDIR/devnet.pid")" 2>/dev/null || true
    rm -f "$DEVDIR/devnet.pid"
  fi
  if pgrep -x snarkos >/dev/null 2>&1; then
    # shellcheck disable=SC2046
    kill $(pgrep -x snarkos) 2>/dev/null || true
  fi
  sleep 1
  echo "${PREFIX}: stopped"
}

status_devnet() {
  local n h
  n="$(pgrep -x snarkos 2>/dev/null | wc -l | tr -d ' ')"
  h="$(curl -sf --max-time 2 "${REST}/testnet/block/height/latest" 2>/dev/null || echo down)"
  echo "${PREFIX}: snarkos_procs=${n} rest_height=${h} endpoint=${REST}"
  if [[ "$h" != "down" && "$n" -gt 0 ]]; then
    echo "${PREFIX}: UP"
    return 0
  fi
  echo "${PREFIX}: DOWN"
  return 1
}

wait_rest() {
  local i
  for i in $(seq 1 36); do
    if curl -sf --max-time 2 "${REST}/testnet/block/height/latest" >/dev/null 2>&1; then
      echo "${PREFIX}: REST ready $(curl -sf --max-time 2 "${REST}/testnet/block/height/latest")"
      return 0
    fi
    sleep 5
  done
  echo "${PREFIX}: REST not ready" >&2
  return 1
}

start_devnet() {
  stop_devnet || true
  mkdir -p "$DEVDIR"
  : >"$DEVDIR/devnet.log"
  nohup "$LEO" devnet \
    --disable-update-check \
    --snarkos "$SNARKOS" \
    --num-validators 4 \
    --num-clients 0 \
    --network testnet \
    --storage "$DEVDIR" \
    --clear-storage \
    --yes \
    --verbosity 1 \
    >>"$DEVDIR/devnet.log" 2>&1 &
  echo $! >"$DEVDIR/devnet.pid"
  echo "${PREFIX}: started pid=$(cat "$DEVDIR/devnet.pid") snarkos=$SNARKOS"
  wait_rest
  status_devnet
}

case "$cmd" in
  start) start_devnet ;;
  stop) stop_devnet ;;
  status) status_devnet ;;
  wait) wait_rest ;;
esac
