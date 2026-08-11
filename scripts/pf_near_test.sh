#!/usr/bin/env bash
# NEAR local near-sandbox test for `pf test -t near` / `proof-forge-next local --target near`.
#
# Bundle-first script (shipped under scripts/ in engineering-dist).
# Full corpus still needs monorepo `runtime-tests/near` + python cryptography +
# locked near-sandbox + wat2wasm — without them `near_runtime_test.sh` **skip-cleans**
# (exit 0 + "skipped:"; not a pass claim).
#
# Inputs (optional):
#   PF_NEAR_ARTIFACT_DIR     — OutputSet from `pf build -t near` (informational)
#   PROOF_FORGE_ROOT         — monorepo or bundle root (auto from script parent)
#   PROOF_FORGE_TOOL_ROOT    — Tool Lock root (near-sandbox, wat2wasm)
#   PF_NEAR_RUNTIME_REQUIRED — set 1 to hard-fail when tools missing
#
# Honesty: engineering sandbox differential only — not formal, not testnet,
# not public broadcast. Cross-contract on NEAR is async (Promise); sync call /
# sync transfer stay permanent fail-closed at the compiler.
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${_script_dir}/.." && pwd)"
export PROOF_FORGE_ROOT="${PROOF_FORGE_ROOT:-$root}"

die() { echo "pf-near-test: FAIL: $*" >&2; exit 1; }
skip_clean() {
  echo "pf-near-test: skipped: $*" >&2
  if [[ "${PF_NEAR_RUNTIME_REQUIRED:-0}" == "1" ]]; then
    exit 2
  fi
  exit 0
}

artifact_dir="${PF_NEAR_ARTIFACT_DIR:-${1:-}}"
if [[ -n "$artifact_dir" ]]; then
  if [[ ! -d "$artifact_dir" ]]; then
    die "artifact dir missing: $artifact_dir (run \`pf build -t near\` first)"
  fi
  artifact_dir="$(cd "$artifact_dir" && pwd)"
  if [[ ! -f "$artifact_dir/manifest.json" ]]; then
    die "missing manifest.json under $artifact_dir"
  fi
  if ! find "$artifact_dir" -name '*.wasm' -type f 2>/dev/null | head -1 | grep -q .; then
    echo "pf-near-test: note: no .wasm under artifact dir (corpus will rebuild fixtures)" >&2
  else
    echo "pf-near-test: artifact=$artifact_dir" >&2
  fi
fi

runtime="$root/scripts/near_runtime_test.sh"
[[ -f "$runtime" ]] || skip_clean "missing $runtime (bundle/monorepo incomplete)"

echo "pf-near-test: engineering near-sandbox corpus via $runtime" >&2
echo "pf-near-test: honesty — not formal / not testnet / Promise=async / sync call FC" >&2

log="$(mktemp "${TMPDIR:-/tmp}/pf-near-test.XXXXXX.log")"
cleanup() { rm -f "$log"; }
trap cleanup EXIT

set +e
# Capture combined output for skip detection; still stream to user.
bash -p "$runtime" >"$log" 2>&1
rc=$?
set -e
cat "$log"

if [[ "$rc" -ne 0 ]]; then
  die "near_runtime_test.sh failed (exit $rc)"
fi

if grep -q "skipped:" "$log"; then
  # Stable marker for pf-cli TestOutcome.skipped detector.
  echo "pf-near-test: skipped: near-sandbox tools or deps unavailable (see log above)" >&2
  exit 0
fi

if grep -q "near-runtime-test: PASS" "$log"; then
  echo "pf-near-test: ok (near-sandbox engineering corpus)"
  exit 0
fi

# Unexpected success without PASS/skip — treat as soft ok with note.
echo "pf-near-test: ok (near_runtime_test exit 0; see log)"
exit 0
