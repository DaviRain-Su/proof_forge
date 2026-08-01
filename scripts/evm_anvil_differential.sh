#!/usr/bin/env bash
# Engineering scaffold: Reference↔Anvil differential for the narrow public
# EVM surface (Counter init/increment/get/overflow).
#
# M4 contract (engineering only — not formal TASK-D4-05 / TST-EVM-005):
#   1. Prefer locked tool-root anvil/cast when present (same pins as smoke_evm.sh).
#   2. If anvil or cast is unavailable, print a clear skip diagnostic and exit 0
#      so ordinary CI never fails on missing Foundry.
#   3. If required EVM artifacts (Counter.bin) are missing, skip exit 0 —
#      this scaffold does not invent a build; product `just target-cli-positive`
#      / smoke_evm preconditions own artifact production.
#   4. When tools + artifacts are available, delegate to scripts/smoke_evm.sh.
#   5. NEVER fabricate Anvil results; never claim runtime validation that did
#      not run.
#
# Formal Reference machine step parity remains pending.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(uname -s)" in
  Darwin)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"
    ;;
  Linux)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)"
    ;;
  *)
    echo "evm-anvil-differential: skipped: unsupported host platform $(uname -s)" >&2
    exit 0
    ;;
esac

foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}}"
anvil_path="$foundry_bin/anvil"
cast_path="$foundry_bin/cast"

if [[ ! -x "$anvil_path" ]]; then
  if command -v anvil >/dev/null 2>&1; then
    anvil_path="$(command -v anvil)"
  fi
fi
if [[ ! -x "$cast_path" ]]; then
  if command -v cast >/dev/null 2>&1; then
    cast_path="$(command -v cast)"
  fi
fi

if [[ ! -x "${anvil_path:-}" ]]; then
  echo "evm-anvil-differential: skipped: anvil unavailable (looked in $foundry_bin and PATH)" >&2
  echo "evm-anvil-differential: engineering scaffold only; not formal Anvil differential" >&2
  exit 0
fi
if [[ ! -x "${cast_path:-}" ]]; then
  echo "evm-anvil-differential: skipped: cast unavailable (looked in $foundry_bin and PATH)" >&2
  echo "evm-anvil-differential: engineering scaffold only; not formal Anvil differential" >&2
  exit 0
fi

counter_bin="$root/build/v2/evm/Counter.bin"
if [[ ! -f "$counter_bin" ]]; then
  echo "evm-anvil-differential: skipped: missing artifact $counter_bin" >&2
  echo "evm-anvil-differential: build EVM Counter first (e.g. product CLI build --target evm)" >&2
  echo "evm-anvil-differential: engineering scaffold only; not formal Anvil differential" >&2
  exit 0
fi

anvil_dir="$(cd "$(dirname "$anvil_path")" && pwd)"
if [[ -x "$anvil_dir/anvil" && -x "$anvil_dir/cast" ]]; then
  export FOUNDRY_BIN="$anvil_dir"
elif [[ -x "$foundry_bin/anvil" && -x "$foundry_bin/cast" ]]; then
  export FOUNDRY_BIN="$foundry_bin"
else
  echo "evm-anvil-differential: skipped: anvil and cast are not co-located for smoke_evm.sh" >&2
  exit 0
fi

echo "evm-anvil-differential: running scripts/smoke_evm.sh via FOUNDRY_BIN=$FOUNDRY_BIN" >&2
echo "evm-anvil-differential: engineering runtime only; not formal Reference↔Anvil closure" >&2
exec bash "$root/scripts/smoke_evm.sh"
