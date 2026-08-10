#!/usr/bin/env bash
# Record an Aleo `pf` demo with asciinema.
# Default: save-only (safe). Set PF_ALEO_BROADCAST=1 + PF_ALEO_TESTNET_KEY for real testnet.
#
# Usage:
#   export PROOF_FORGE_CLI=...
#   bash scripts/demo_aleo_record.sh
#   PF_ALEO_BROADCAST=1 PF_ALEO_TESTNET_KEY=... bash scripts/demo_aleo_record.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/pf_resolve.sh
source "$root/scripts/pf_resolve.sh"
pf_require || exit $?

OUT_DIR="${PF_DEMO_OUT:-$root/build/demos/aleo}"
mkdir -p "$OUT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
CAST="$OUT_DIR/pf-aleo-demo-$STAMP.cast"
LOG="$OUT_DIR/pf-aleo-demo-$STAMP.log"

export PS1='demo$ '
export PROOF_FORGE_ROOT="${PROOF_FORGE_ROOT:-$root}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pf-aleo-rec.XXXXXX")"
# shellcheck disable=SC2064
trap 'echo "work dir: $WORK" | tee -a "$LOG"' EXIT

run_demo() {
  set -euo pipefail
  export PATH="$(dirname "$PF"):$PATH"
  cd "$WORK"

  echo "======== 1) pf setup ========"
  pf setup --target aleo

  echo "======== 2) pf new ========"
  pf new helloworld --target aleo
  cd helloworld
  echo "--- pf.toml ---"
  cat pf.toml
  echo "--- source ---"
  cat src/Helloworld.lean

  echo "======== 3) pf build ========"
  pf build
  ls -la build/aleo/
  echo "--- program head ---"
  head -25 build/aleo/*.aleo | head -40

  echo "======== 4) pf run (local VM) ========"
  pf run -- initialize 5u64
  pf run -- increment 3u64

  echo "======== 5) pf deploy save-only (testnet packaging) ========"
  pf deploy --network testnet
  ls -la build/aleo/tx/
  echo "--- deployment json size ---"
  wc -c build/aleo/tx/*.deployment.json

  echo "======== 6) pf execute save-only ========"
  pf execute --network testnet -- initialize 5u64
  ls -la build/aleo/tx/

  echo "======== 7) safety: mainnet refused ========"
  set +e
  pf deploy --network mainnet
  echo "mainnet exit=$?"
  set -e

  if [[ "${PF_ALEO_BROADCAST:-0}" == "1" ]]; then
    if [[ -z "${PF_ALEO_TESTNET_KEY:-}" ]]; then
      echo "PF_ALEO_BROADCAST=1 but PF_ALEO_TESTNET_KEY unset — skip broadcast"
    else
      echo "======== 8) REAL testnet broadcast deploy ========"
      echo "(private key loaded from env name only; value not printed)"
      # Stable on-chain program id for deploy + subsequent executes.
      PROGRAM_ID="${PF_ALEO_PROGRAM_ID:-pfdemo$(date +%s | tail -c 7)}"
      echo "program_id=$PROGRAM_ID.aleo"
      set +e
      # Real certificate generation (no --skip-deploy-certificate) so base fee matches chain.
      pf deploy --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY         --program-id "$PROGRAM_ID" --json | tee /tmp/pf-aleo-deploy-out.json
      dep_rc=${PIPESTATUS[0]}
      set -e
      echo "broadcast deploy exit=$dep_rc"
      if [[ "$dep_rc" -eq 0 ]]; then
        echo "======== 9) REAL testnet broadcast execute ========"
        pf execute --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY           --program-id "$PROGRAM_ID" -- initialize 5u64
        pf execute --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY           --program-id "$PROGRAM_ID" -- increment 3u64
        echo "BROADCAST OK — program $PROGRAM_ID.aleo"
        echo "Explorer: https://testnet.explorer.provable.com/program/$PROGRAM_ID.aleo"
      else
        echo "BROADCAST FAILED — check fee / network / name collision."
        echo "Fund address via https://faucet.aleo.org/ then re-run with same key."
      fi
    fi
  else
    echo "======== 8) broadcast skipped (set PF_ALEO_BROADCAST=1 for real chain) ========"
  fi

  echo "======== DONE ========"
  echo "cast will be at: $CAST"
}

export -f run_demo
export PF PROOF_FORGE_CLI PROOF_FORGE_ROOT WORK CAST
export PF_ALEO_BROADCAST="${PF_ALEO_BROADCAST:-0}"
# Pass key only if set (asciinema child inherits env; do not echo it)
if [[ -n "${PF_ALEO_TESTNET_KEY:-}" ]]; then
  export PF_ALEO_TESTNET_KEY
fi

if ! command -v asciinema >/dev/null 2>&1; then
  echo "asciinema not found; running without cast recording" | tee "$LOG"
  run_demo 2>&1 | tee -a "$LOG"
else
  # Record interactive-looking session
  asciinema rec --overwrite -c "bash -lc 'run_demo'" "$CAST" 2>&1 | tee "$LOG"
fi

# Also write a plain log via script(1) style summary
{
  echo "cast=$CAST"
  echo "log=$LOG"
  echo "work=$WORK"
  echo "broadcast=${PF_ALEO_BROADCAST:-0}"
  date -u +%Y-%m-%dT%H:%M:%SZ
} >"$OUT_DIR/pf-aleo-demo-$STAMP.meta.txt"

echo "demo-aleo-record: cast=$CAST"
echo "demo-aleo-record: log=$LOG"
if command -v asciinema >/dev/null 2>&1; then
  echo "demo-aleo-record: replay: asciinema play $CAST"
  echo "demo-aleo-record: upload: asciinema upload $CAST   # optional public URL"
fi
