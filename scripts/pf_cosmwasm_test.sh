#!/usr/bin/env bash
# CosmWasm local mock-runtime test for `pf test -t cosmwasm`.
#
# Thin wrapper around scripts/cosmwasm_runtime_test.sh (host-heavy cargo + wat2wasm).
# Missing tools → skip-clean (exit 0 + "skipped:"; not a pass claim).
#
# Honesty: engineering only — not wasmd mainnet, not formal.
# Sync call FC; async schedule → SubMsg reply_on=never (same-tx).
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${_script_dir}/.." && pwd)"
export PROOF_FORGE_ROOT="${PROOF_FORGE_ROOT:-$root}"

die() { echo "pf-cosmwasm-test: FAIL: $*" >&2; exit 1; }
skip_clean() {
  echo "pf-cosmwasm-test: skipped: $*" >&2
  exit 0
}

artifact_dir="${PF_COSMWASM_ARTIFACT_DIR:-${1:-}}"
if [[ -n "$artifact_dir" ]]; then
  [[ -d "$artifact_dir" ]] || die "artifact dir missing: $artifact_dir"
  [[ -f "$artifact_dir/manifest.json" ]] || die "missing manifest.json under $artifact_dir"
  echo "pf-cosmwasm-test: artifact=$artifact_dir (corpus still uses package fixtures)" >&2
fi

runtime="$root/scripts/cosmwasm_runtime_test.sh"
[[ -f "$runtime" ]] || skip_clean "missing $runtime"

echo "pf-cosmwasm-test: engineering cosmwasm-vm corpus via $runtime" >&2
echo "pf-cosmwasm-test: honesty — not formal/mainnet; sync call FC; schedule=SubMsg never" >&2

log="$(mktemp "${TMPDIR:-/tmp}/pf-cw-test.XXXXXX.log")"
trap 'rm -f "$log"' EXIT
set +e
bash -p "$runtime" >"$log" 2>&1
rc=$?
set -e
cat "$log"

if [[ "$rc" -ne 0 ]]; then
  if grep -q "skipped:" "$log"; then
    echo "pf-cosmwasm-test: skipped: tools or deps unavailable" >&2
    exit 0
  fi
  # exit 2 from script = missing tools
  if [[ "$rc" -eq 2 ]]; then
    echo "pf-cosmwasm-test: skipped: cosmwasm-runtime-test exit 2 (tools)" >&2
    exit 0
  fi
  die "cosmwasm_runtime_test.sh failed (exit $rc)"
fi

if grep -q "skipped:" "$log"; then
  echo "pf-cosmwasm-test: skipped: tools or deps unavailable" >&2
  exit 0
fi

echo "pf-cosmwasm-test: ok (cosmwasm-vm engineering corpus)"
exit 0
