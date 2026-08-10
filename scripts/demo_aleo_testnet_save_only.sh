#!/usr/bin/env bash
# Rehearsal for Aleo video demo: setup → new → build → run → deploy/execute save-only.
# No --broadcast. Safe to run in CI-like environments with leo + proof-forge-next.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/pf_resolve.sh
source "$root/scripts/pf_resolve.sh"
pf_require || exit $?

echo "demo-aleo: setup"
"$PF" setup --target aleo

work="$(mktemp -d "${TMPDIR:-/tmp}/pf-aleo-demo.XXXXXX")"
trap 'echo "demo-aleo: artifacts kept at $work"' EXIT

echo "demo-aleo: project at $work/hello"
"$PF" new hello --target aleo --path "$work/hello"
cd "$work/hello"

echo "demo-aleo: build"
"$PF" build

echo "demo-aleo: local run"
"$PF" run -- initialize 5u64
"$PF" run -- increment 3u64

echo "demo-aleo: deploy save-only (testnet packaging, no broadcast)"
"$PF" deploy --network testnet

echo "demo-aleo: execute save-only"
"$PF" execute --network testnet -- initialize 5u64

echo "demo-aleo: outputs"
ls -la build/aleo/
ls -la build/aleo/tx/ || true
echo "demo-aleo: SAVE-ONLY OK"
echo "demo-aleo: for real Testnet broadcast (off-script):"
echo "  export PF_ALEO_TESTNET_KEY=...   # funded testnet key, never well-known dev key"
echo "  pf deploy  --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY"
echo "  pf execute --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY -- initialize 5u64"
