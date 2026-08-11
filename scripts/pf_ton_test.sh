#!/usr/bin/env bash
# TON local @ton/sandbox test for `pf test -t ton`.
#
# Thin wrapper around scripts/ton_runtime_test.sh (host-heavy node + tolk).
# Missing tools → skip-clean (exit 0 + "skipped:"; not a pass claim).
#
# Honesty: engineering only — not mainnet, not formal.
# Sync call FC; async schedule → createMessage subset (TON assets frozen).
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${_script_dir}/.." && pwd)"
export PROOF_FORGE_ROOT="${PROOF_FORGE_ROOT:-$root}"

die() { echo "pf-ton-test: FAIL: $*" >&2; exit 1; }
skip_clean() {
  echo "pf-ton-test: skipped: $*" >&2
  exit 0
}

artifact_dir="${PF_TON_ARTIFACT_DIR:-${1:-}}"
if [[ -n "$artifact_dir" ]]; then
  [[ -d "$artifact_dir" ]] || die "artifact dir missing: $artifact_dir"
  [[ -f "$artifact_dir/manifest.json" ]] || die "missing manifest.json under $artifact_dir"
  echo "pf-ton-test: artifact=$artifact_dir (corpus still uses package fixtures)" >&2
fi

runtime="$root/scripts/ton_runtime_test.sh"
[[ -f "$runtime" ]] || skip_clean "missing $runtime"

echo "pf-ton-test: engineering @ton/sandbox corpus via $runtime" >&2
echo "pf-ton-test: honesty — not formal/mainnet; sync call FC; schedule=createMessage" >&2

log="$(mktemp "${TMPDIR:-/tmp}/pf-ton-test.XXXXXX.log")"
trap 'rm -f "$log"' EXIT
set +e
bash -p "$runtime" >"$log" 2>&1
rc=$?
set -e
cat "$log"

if [[ "$rc" -ne 0 ]]; then
  if grep -q "skipped:" "$log"; then
    echo "pf-ton-test: skipped: tools or deps unavailable" >&2
    exit 0
  fi
  if [[ "$rc" -eq 2 ]]; then
    echo "pf-ton-test: skipped: ton-runtime-test exit 2 (tools)" >&2
    exit 0
  fi
  die "ton_runtime_test.sh failed (exit $rc)"
fi

if grep -q "skipped:" "$log"; then
  echo "pf-ton-test: skipped: tools or deps unavailable" >&2
  exit 0
fi

echo "pf-ton-test: ok (@ton/sandbox engineering corpus)"
exit 0
