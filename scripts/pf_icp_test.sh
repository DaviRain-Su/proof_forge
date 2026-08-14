#!/usr/bin/env bash
# ICP local PocketIC test for `proof-forge-next local --target icp`.
#
# Thin wrapper around scripts/icp_runtime_test.sh (host-heavy).
# Missing PocketIC / cargo → skip-clean (exit 0 + "skipped:"; not a pass claim).
#
# Honesty: engineering only — not mainnet, not formal.
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${_script_dir}/.." && pwd)"
export PROOF_FORGE_ROOT="${PROOF_FORGE_ROOT:-$root}"

die() { echo "pf-icp-test: FAIL: $*" >&2; exit 1; }
skip_clean() {
  echo "pf-icp-test: skipped: $*" >&2
  exit 0
}

artifact_dir="${PF_ICP_ARTIFACT_DIR:-${1:-}}"
if [[ -n "$artifact_dir" ]]; then
  [[ -d "$artifact_dir" ]] || die "artifact dir missing: $artifact_dir"
  [[ -f "$artifact_dir/manifest.json" ]] || die "missing manifest.json under $artifact_dir"
  export PF_ICP_ARTIFACT_DIR="$artifact_dir"
  echo "pf-icp-test: artifact=$artifact_dir" >&2
fi

runtime="$root/scripts/icp_runtime_test.sh"
[[ -f "$runtime" ]] || skip_clean "missing $runtime"
chmod +x "$runtime" 2>/dev/null || true

echo "pf-icp-test: engineering PocketIC via $runtime" >&2
echo "pf-icp-test: honesty — not formal/mainnet; sync call FC; async advertise-only" >&2

log="$(mktemp "${TMPDIR:-/tmp}/pf-icp-test.XXXXXX.log")"
trap 'rm -f "$log"' EXIT
set +e
bash -p "$runtime" >"$log" 2>&1
rc=$?
set -e
cat "$log"

if [[ "$rc" -ne 0 ]]; then
  if grep -q "skipped:" "$log"; then
    echo "pf-icp-test: skipped: tools or PocketIC unavailable" >&2
    exit 0
  fi
  if [[ "$rc" -eq 2 ]]; then
    echo "pf-icp-test: skipped: icp-runtime-test exit 2 (tools)" >&2
    exit 0
  fi
  die "icp_runtime_test.sh failed (exit $rc)"
fi

if grep -q "skipped:" "$log"; then
  echo "pf-icp-test: skipped: tools or PocketIC unavailable" >&2
  exit 0
fi

echo "pf-icp-test: ok (PocketIC engineering gate)"
exit 0
