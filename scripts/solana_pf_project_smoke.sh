#!/usr/bin/env bash
# Developer-facing Solana project smoke via `pf` (StateCell-shaped).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/pf_resolve.sh
source "$root/scripts/pf_resolve.sh"
pf_require || exit $?

export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64}"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/sol-pf-proj.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

echo "solana-pf-project: pf new → build → test → deploy(save)"
"$PF" new counter --target solana --path "$tmp/counter" >/dev/null
(
  cd "$tmp/counter"
  "$PF" build
  "$PF" test
  "$PF" deploy
  test -n "$(ls build/solana/tx/*package.json 2>/dev/null)"
)
echo "solana-pf-project: ok"
