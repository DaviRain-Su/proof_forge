#!/usr/bin/env bash
# EVMOZ-004 thin corpus runtime orchestration (not CI-registered; EVMOZ-006 owns that).
#
# Phases:
#   1) Validate all testdata/evm-corpus/v1/cases/*.json with scripts/evm_corpus_v1.py
#   2) When tools + product CLI present: run Cancun (or PF_EVM_PROFILE) Anvil
#      differential with PF_EVM_CORPUS_OBS_DIR so smoke/token emit observations
#   3) Re-validate every emitted observation as proof-forge.evm-observation.v1
#
# Explicit non-claims:
#   - not formal Reference↔Anvil / TASK-D4-05 / C-3
#   - not OZ family / ABI / standard credit (primitive + adapter only)
#   - not manifest/CI registration
#   - Token StackTooDeep / initcode skip is verdict=skip, never pass
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

cases_dir="$root/testdata/evm-corpus/v1/cases"
programs_dir="$root/testdata/evm-corpus/v1/programs"
validator="$root/scripts/evm_corpus_v1.py"
obs_root="${PF_EVM_CORPUS_OBS_DIR:-$root/build/v2/evm-corpus-obs}"
# Default Cancun for corpus pins (EVMOZ-001 profile identity).
export PF_EVM_PROFILE="${PF_EVM_PROFILE:-evm-yul-solc-0.8.34-cancun-v1}"
phase="${PF_EVM_CORPUS_PHASE:-full}" # full | validate-only | observe-after-smoke

die() { echo "evm-corpus-runtime: $*" >&2; exit 1; }

echo "evm-corpus-runtime: phase=$phase profile=$PF_EVM_PROFILE" >&2

[[ -f "$validator" ]] || die "missing $validator"
[[ -d "$cases_dir" ]] || die "missing cases dir $cases_dir"
[[ -f "$programs_dir/EventFlow.lean" ]] || die "missing committed EventFlow fixture"

# ---------------------------------------------------------------------------
# 1) Schema-validate every case (exact canonical bytes)
# ---------------------------------------------------------------------------
case_count=0
# Portable (bash 3.2 / macOS): no mapfile.
while IFS= read -r case_path; do
  [[ -n "$case_path" ]] || continue
  /usr/bin/python3 -I -S "$validator" validate-case "$case_path" \
    || die "case validate failed: $case_path"
  case_count=$((case_count + 1))
done < <(find "$cases_dir" -maxdepth 1 -type f -name '*.json' | sort)
[[ "$case_count" -gt 0 ]] || die "no case JSON under $cases_dir"
echo "evm-corpus-runtime: validated $case_count case file(s)" >&2

if [[ "$phase" == "validate-only" ]]; then
  echo "evm-corpus-runtime: validate-only ok (no Anvil)" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# 2) Tool presence gate (skip-clean when tools absent; hard fail when present)
# ---------------------------------------------------------------------------
case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *)
    echo "evm-corpus-runtime: skipped: unsupported host $(uname -s)" >&2
    exit 0
    ;;
esac
foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}}"
anvil="$foundry_bin/anvil"
cast="$foundry_bin/cast"
if [[ ! -x "$anvil" ]] && command -v anvil >/dev/null 2>&1; then anvil="$(command -v anvil)"; fi
if [[ ! -x "$cast" ]] && command -v cast >/dev/null 2>&1; then cast="$(command -v cast)"; fi

if [[ ! -x "${anvil:-}" || ! -x "${cast:-}" ]]; then
  echo "evm-corpus-runtime: skipped: anvil/cast unavailable (cases still schema-valid)" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# 3) Run product Anvil differential with observation emit
# ---------------------------------------------------------------------------
if [[ "$phase" != "observe-after-smoke" ]]; then
  rm -rf "$obs_root"
  mkdir -p "$obs_root"
  export PF_EVM_CORPUS_OBS_DIR="$obs_root"
  export FOUNDRY_BIN="$(cd "$(dirname "$anvil")" && pwd)"
  echo "evm-corpus-runtime: running evm_anvil_differential.sh (obs → $obs_root)" >&2
  bash "$root/scripts/evm_anvil_differential.sh" \
    || die "Anvil differential failed (hard when tools present)"
fi

# ---------------------------------------------------------------------------
# 4) Validate every emitted observation
# ---------------------------------------------------------------------------
if [[ ! -d "$obs_root" ]]; then
  echo "evm-corpus-runtime: note: no observation dir $obs_root (smoke may not have emitted)" >&2
else
  obs_count=0
  while IFS= read -r obs_path; do
    [[ -n "$obs_path" ]] || continue
    /usr/bin/python3 -I -S "$validator" validate-observation "$obs_path" \
      || die "observation validate failed: $obs_path"
    obs_count=$((obs_count + 1))
  done < <(find "$obs_root" -type f -name '*.json' | sort)
  if [[ "$obs_count" -eq 0 ]]; then
    echo "evm-corpus-runtime: note: zero observation files under $obs_root" >&2
  else
    echo "evm-corpus-runtime: validated $obs_count observation file(s)" >&2
  fi
fi

# Require at least one primitive observation when full phase ran with tools.
if [[ "$phase" == "full" ]]; then
  primitive_obs=0
  for id in \
    pf.primitive.counter.overflow-hold.v1 \
    pf.primitive.accumulator.overflow-hold.v1 \
    pf.primitive.arithops.bitnot-scale.v1 \
    pf.primitive.eventflow.emit-cap.v1
  do
    if compgen -G "$obs_root/$id/*.json" >/dev/null 2>&1; then
      primitive_obs=$((primitive_obs + 1))
    fi
  done
  [[ "$primitive_obs" -ge 1 ]] || die "expected at least one primitive observation under $obs_root"
  # Token may be skip-only (StackTooDeep); presence of any token obs (pass or skip) is enough note.
  if compgen -G "$obs_root/pf.adapter.token.conservation.v1/*.json" >/dev/null 2>&1; then
    echo "evm-corpus-runtime: Token adapter observation present (pass or explicit skip)" >&2
  else
    echo "evm-corpus-runtime: note: no Token adapter observation (token script may have skipped before obs)" >&2
  fi
fi

echo "evm-corpus-runtime: ok (engineering corpus runtime; not formal C-3; no OZ/family credit)" >&2
