#!/usr/bin/env bash
# EVMOZ-004 full corpus runtime (engineering closure; not formal C-3 / OZ credit).
#
# full phase (default):
#   1) schema-validate all cases
#   2) Darwin-only ToolLockV4Digest + profile/hardfork pin fail-closed
#   3) required tools present (anvil/solc/lean/lake/CLI) — else HARD FAIL
#   4) Reference leg (real stepReferenceSliceV1)
#   5) product Cancun Anvil differential + all-step pf-anvil observations
#   6) case-level exact closure (shared equality, status, logs)
#
# validate-only: case schema only (no tools).
# Token adapter: optional pf-anvil may explicit-skip (StackTooDeep); never pass-as-skip.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

cases_dir="$root/testdata/evm-corpus/v1/cases"
programs_dir="$root/testdata/evm-corpus/v1/programs"
validator="$root/scripts/evm_corpus_v1.py"
obs_root="${PF_EVM_CORPUS_OBS_DIR:-$root/build/v2/evm-corpus-obs}"
export PF_EVM_PROFILE="${PF_EVM_PROFILE:-evm-yul-solc-0.8.34-cancun-v1}"
phase="${PF_EVM_CORPUS_PHASE:-full}" # full | validate-only

die() { echo "evm-corpus-runtime: $*" >&2; exit 1; }

echo "evm-corpus-runtime: phase=$phase profile=$PF_EVM_PROFILE" >&2

[[ -f "$validator" ]] || die "missing $validator"
[[ -d "$cases_dir" ]] || die "missing cases dir"
[[ -f "$programs_dir/EventFlow.lean" ]] || die "missing EventFlow fixture"

# ---------------------------------------------------------------------------
# 1) Schema-validate every case
# ---------------------------------------------------------------------------
case_count=0
while IFS= read -r case_path; do
  [[ -n "$case_path" ]] || continue
  /usr/bin/python3 -I -S "$validator" validate-case "$case_path" \
    || die "case validate failed: $case_path"
  case_count=$((case_count + 1))
done < <(find "$cases_dir" -maxdepth 1 -type f -name '*.json' | sort)
[[ "$case_count" -gt 0 ]] || die "no cases"
echo "evm-corpus-runtime: validated $case_count case file(s)" >&2

if [[ "$phase" == "validate-only" ]]; then
  echo "evm-corpus-runtime: validate-only ok (no tools)" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# 2) Host / ToolLock / profile pin fail-closed (Darwin-pinned cases)
# ---------------------------------------------------------------------------
case "$(uname -s)" in
  Darwin)
    lock_file="$root/toolchains.lock.json"
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"
    ;;
  Linux)
    die "Darwin-pinned corpus cases refuse Linux host (ToolLockV4Digest lane fail-closed)"
    ;;
  *)
    die "unsupported host $(uname -s) for full runtime"
    ;;
esac

[[ -f "$lock_file" ]] || die "missing $lock_file"
expected_digest="$(/usr/bin/python3 -I -S -c "
import importlib.util
from pathlib import Path
spec=importlib.util.spec_from_file_location('m', Path(r'''$validator'''))
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.darwin_tool_lock_v4_digest(Path(r'''$lock_file''')))
")"
# All primitive cases pin this Darwin ToolLockV4Digest.
case_pin="$(/usr/bin/python3 -I -S -c "
import json
from pathlib import Path
c=json.loads(Path(r'''$cases_dir/pf.primitive.counter.overflow-hold.v1.json''').read_text())
print(c['pins']['toolLockDigest'])
")"
[[ "$expected_digest" == "$case_pin" ]] || \
  die "ToolLockV4Digest mismatch host=$expected_digest case=$case_pin"
[[ "$PF_EVM_PROFILE" == "evm-yul-solc-0.8.34-cancun-v1" ]] || \
  die "full runtime requires Cancun profile (got $PF_EVM_PROFILE)"

# ---------------------------------------------------------------------------
# 3) Required tools — HARD FAIL if missing (primitive required legs)
# ---------------------------------------------------------------------------
foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}}"
anvil="$foundry_bin/anvil"
cast="$foundry_bin/cast"
solc="$foundry_bin/solc"
[[ -x "$anvil" ]] || die "required tool missing: anvil"
[[ -x "$cast" ]] || die "required tool missing: cast"
[[ -x "$solc" ]] || die "required tool missing: solc"
command -v lake >/dev/null 2>&1 || die "required tool missing: lake"
command -v lean >/dev/null 2>&1 || die "required tool missing: lean"
cli=""
if [[ -x "$root/.lake/build/bin/proof-forge-next" ]]; then
  cli="$root/.lake/build/bin/proof-forge-next"
elif command -v proof-forge-next >/dev/null 2>&1; then
  cli="$(command -v proof-forge-next)"
fi
# Allow parent worktree binary when worktree has no local build.
if [[ -z "$cli" && -x "${PROOF_FORGE_CLI:-}" ]]; then
  cli="$PROOF_FORGE_CLI"
fi
[[ -n "$cli" && -x "$cli" ]] || die "required tool missing: proof-forge-next CLI"
export FOUNDRY_BIN="$(cd "$(dirname "$anvil")" && pwd)"

# ---------------------------------------------------------------------------
# 4) Reference leg (hard fail)
# ---------------------------------------------------------------------------
rm -rf "$obs_root"
mkdir -p "$obs_root"
export PF_EVM_CORPUS_OBS_DIR="$obs_root"
bash "$root/scripts/evm_corpus_reference.sh" || die "Reference leg failed"

# ---------------------------------------------------------------------------
# 5) Product Cancun builds + Anvil matrix with all-step pf-anvil observations
# ---------------------------------------------------------------------------
bash "$root/scripts/evm_anvil_differential.sh" || die "Anvil differential failed"

# ---------------------------------------------------------------------------
# 6) Case-level exact closure
# ---------------------------------------------------------------------------
primitive_pass=0
while IFS= read -r case_path; do
  [[ -n "$case_path" ]] || continue
  base="$(basename "$case_path")"
  # Token adapter may skip — close-case reports skip vs pass.
  out="$(/usr/bin/python3 -I -S "$validator" close-case "$case_path" "$obs_root" 2>&1)" || {
    echo "$out" >&2
    die "close-case failed for $base"
  }
  echo "$out" >&2
  if echo "$out" | grep -q 'corpus-case-closed-pass'; then
    if [[ "$base" == pf.primitive.* ]]; then
      primitive_pass=$((primitive_pass + 1))
    fi
  fi
done < <(find "$cases_dir" -maxdepth 1 -type f -name '*.json' | sort)

[[ "$primitive_pass" -eq 4 ]] || \
  die "expected 4 primitive case pass closures, got $primitive_pass"

echo "evm-corpus-runtime: ok (engineering corpus closure; not formal C-3; no OZ family/ABI/standard credit)" >&2
