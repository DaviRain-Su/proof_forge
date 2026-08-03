#!/usr/bin/env bash
# EVMOZ-004 full corpus runtime (engineering closure; not formal C-3 / OZ credit).
#
# full phase (default):
#   1) schema-validate ALL business cases under cases/ (incl. blocked)
#   2) select runnable set: class∈{primitive,adapter} ∧ runner=anvil-matrix
#      (exact 4 primitive + 1 adapter; blocked never closed as pass/skip)
#   3) Darwin-only ToolLockV4Digest + per-case pin exact join
#   4) required tools hard-fail; export PROOF_FORGE_CLI to downstream
#   5) safe OBS root (under build/) then Reference + Anvil + close-case
#
# validate-only: case schema only (no tools).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

cases_dir="$root/testdata/evm-corpus/v1/cases"
programs_dir="$root/testdata/evm-corpus/v1/programs"
validator="$root/scripts/evm_corpus_v1.py"
obs_requested="${PF_EVM_CORPUS_OBS_DIR:-$root/build/v2/evm-corpus-obs}"
export PF_EVM_PROFILE="${PF_EVM_PROFILE:-evm-yul-solc-0.8.34-cancun-v1}"
phase="${PF_EVM_CORPUS_PHASE:-full}" # full | validate-only

die() { echo "evm-corpus-runtime: $*" >&2; exit 1; }

case "$phase" in
  full|validate-only) ;;
  *)
    die "unknown PF_EVM_CORPUS_PHASE='$phase' (only full|validate-only)"
    ;;
esac

echo "evm-corpus-runtime: phase=$phase profile=$PF_EVM_PROFILE" >&2

[[ -f "$validator" ]] || die "missing $validator"
[[ -d "$cases_dir" ]] || die "missing cases dir"
[[ -f "$programs_dir/EventFlow.lean" ]] || die "missing EventFlow fixture"

# ---------------------------------------------------------------------------
# 1) Schema-validate every case file (including blocked/lean-focused)
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
# 2) Runnable set + pin join (never close blocked as runtime pass)
# ---------------------------------------------------------------------------
runnable_list="$(/usr/bin/python3 -I -S "$validator" list-runnable-cases "$cases_dir")" || \
  die "list-runnable-cases / pin join failed"
echo "evm-corpus-runtime: runnable cases:" >&2
echo "$runnable_list" | sed 's/^/  /' >&2
primitive_count="$(echo "$runnable_list" | grep -c '^pf\.primitive\.' || true)"
adapter_count="$(echo "$runnable_list" | grep -c '^pf\.adapter\.' || true)"
[[ "$primitive_count" -eq 4 ]] || die "expected 4 primitive runnables, got $primitive_count"
[[ "$adapter_count" -eq 1 ]] || die "expected 1 adapter runnable, got $adapter_count"

# ---------------------------------------------------------------------------
# 3) Host / ToolLock / profile fail-closed
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
expected_digest="$(/usr/bin/python3 -I -S "$validator" tool-lock-digest "$lock_file")" \
  || die "tool-lock-digest failed for $lock_file"
[[ "$expected_digest" == "63eadb99743addf944ce478b3763ca3258dd101a0c3df6a47213e64ff5386edf" ]] || \
  die "host ToolLockV4Digest $expected_digest != Darwin KAT"
[[ "$PF_EVM_PROFILE" == "evm-yul-solc-0.8.34-cancun-v1" ]] || \
  die "full runtime requires Cancun profile (got $PF_EVM_PROFILE)"

# ---------------------------------------------------------------------------
# 4) Required tools — HARD FAIL if missing; export PROOF_FORGE_CLI
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

# CLI discovery: PROOF_FORGE_CLI → local .lake → PATH
cli=""
if [[ -n "${PROOF_FORGE_CLI:-}" && -x "${PROOF_FORGE_CLI}" ]]; then
  cli="$PROOF_FORGE_CLI"
elif [[ -x "$root/.lake/build/bin/proof-forge-next" ]]; then
  cli="$root/.lake/build/bin/proof-forge-next"
elif command -v proof-forge-next >/dev/null 2>&1; then
  cli="$(command -v proof-forge-next)"
fi
[[ -n "$cli" && -x "$cli" ]] || die "required tool missing: proof-forge-next CLI"
export PROOF_FORGE_CLI="$cli"
export FOUNDRY_BIN="$(cd "$(dirname "$anvil")" && pwd)"
echo "evm-corpus-runtime: PROOF_FORGE_CLI=$PROOF_FORGE_CLI" >&2

# ---------------------------------------------------------------------------
# 5) Safe OBS root (must be under build/; never rm -rf arbitrary paths)
# ---------------------------------------------------------------------------
# Sole stdout line is the resolved path (spaces-safe; no awk field split).
obs_root="$(/usr/bin/python3 -I -S "$validator" safe-obs-root "$root" "$obs_requested")" \
  || die "safe-obs-root failed for $obs_requested"
[[ -n "$obs_root" ]] || die "safe-obs-root returned empty path for $obs_requested"
# Destroy only the validated path.
rm -rf "$obs_root"
mkdir -p "$obs_root"
export PF_EVM_CORPUS_OBS_DIR="$obs_root"

# ---------------------------------------------------------------------------
# 6) Reference leg (hard fail) + Token pin check via Lean runner
# ---------------------------------------------------------------------------
bash "$root/scripts/evm_corpus_reference.sh" || die "Reference leg failed"

# ---------------------------------------------------------------------------
# 7) Product Cancun Anvil differential + pf-anvil observations
# ---------------------------------------------------------------------------
bash "$root/scripts/evm_anvil_differential.sh" || die "Anvil differential failed"

# ---------------------------------------------------------------------------
# 8) Case-level exact closure on runnable cases only
# ---------------------------------------------------------------------------
primitive_pass=0
adapter_closed=0
while IFS= read -r case_id; do
  [[ -n "$case_id" ]] || continue
  case_path="$cases_dir/${case_id}.json"
  [[ -f "$case_path" ]] || die "missing case file for runnable id $case_id"
  out="$(/usr/bin/python3 -I -S "$validator" close-case "$case_path" "$obs_root" 2>&1)" || {
    echo "$out" >&2
    die "close-case failed for $case_id"
  }
  echo "$out" >&2
  if echo "$out" | grep -q 'corpus-case-closed-pass'; then
    if [[ "$case_id" == pf.primitive.* ]]; then
      primitive_pass=$((primitive_pass + 1))
    fi
    if [[ "$case_id" == pf.adapter.* ]]; then
      adapter_closed=$((adapter_closed + 1))
    fi
  elif echo "$out" | grep -q 'corpus-case-closed-skip'; then
    if [[ "$case_id" == pf.adapter.* ]]; then
      adapter_closed=$((adapter_closed + 1))
    else
      die "primitive case must not skip: $case_id"
    fi
  else
    die "unexpected close-case output for $case_id"
  fi
done <<<"$runnable_list"

[[ "$primitive_pass" -eq 4 ]] || \
  die "expected 4 primitive case pass closures, got $primitive_pass"
[[ "$adapter_closed" -eq 1 ]] || \
  die "expected 1 adapter close (pass or explicit skip), got $adapter_closed"

echo "evm-corpus-runtime: ok (engineering corpus closure; not formal C-3; no OZ family/ABI/standard credit)" >&2
