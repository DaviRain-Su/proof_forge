#!/usr/bin/env bash
# Developer-facing EVM StateCell smoke via `pf` (project flow).
# Full multi-fixture corpus remains scripts/evm_*_anvil_smoke.sh + differential.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/pf_resolve.sh
source "$root/scripts/pf_resolve.sh"
pf_require || exit $?

case "$(uname -s)" in
  Darwin) default_tr="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux)  default_tr="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *) default_tr="" ;;
esac
export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_tr}"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/evm-pf-sc.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

echo "evm-pf-statecell: pf new → build → test → deploy(save)"
"$PF" new cell --target evm --path "$tmp/cell" >/dev/null
(
  cd "$tmp/cell"
  "$PF" build
  "$PF" test
  "$PF" deploy
  test -n "$(ls build/evm/tx/*package.json 2>/dev/null)"
)
echo "evm-pf-statecell: ok"
