#!/usr/bin/env bash
# Engineering EVM Anvil state differential gate (not formal C-3 / TASK-D4-05).
#
# Flow when Foundry tools are present:
#   1. Resolve locked anvil/cast (tool-root preferred; PATH co-located fallback).
#   2. Product CLI-build Counter + Accumulator (+ ArithOps + EventFlow emit fixture).
#   3. Delegate runtime matrix to scripts/smoke_evm.sh (view+storage, overflow
#      state hold, emit log topic/data when EventFlow artifact present).
#   4. Best-effort Token dense-Map smoke via scripts/evm_token_anvil_smoke.sh
#      (initcode-limit skip is clean; not a hard failure of this gate).
#
# Skip-clean (exit 0) when:
#   - host platform unsupported
#   - anvil or cast unavailable
#   - product CLI binary missing and cannot be built
#
# Hard fail (exit 1) when tools+CLI are present but required product builds or
# the Anvil matrix assertions fail. NEVER fabricate Anvil results.
# NEVER claim formal Reference↔Anvil closure.
#
# Optional explicit Cancun path (EVMOZ-001):
#   PF_EVM_PROFILE=evm-yul-solc-0.8.34-cancun-v1
#   → product build uses --profile evm-yul-solc-0.8.34-cancun-v1
#   → smoke_evm.sh starts anvil with --hardfork cancun
# Empty / legacy profile keeps historical default (no --profile, no hardfork flag).
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
evm_profile="${PF_EVM_PROFILE:-}"
build_profile_args=()
case "$evm_profile" in
  "")
    : # default product profile (legacy evm-yul-solc-0.8.34-v1)
    ;;
  "evm-yul-solc-0.8.34-v1"|"evm-yul-solc-0.8.34-cancun-v1")
    build_profile_args+=(--profile "$evm_profile")
    echo "evm-anvil-differential: explicit profile=$evm_profile" >&2
    ;;
  *)
    echo "evm-anvil-differential: unsupported PF_EVM_PROFILE='$evm_profile'" >&2
    exit 1
    ;;
esac

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
  echo "evm-anvil-differential: engineering only; not formal Reference↔Anvil closure" >&2
  exit 0
fi
if [[ ! -x "${cast_path:-}" ]]; then
  echo "evm-anvil-differential: skipped: cast unavailable (looked in $foundry_bin and PATH)" >&2
  echo "evm-anvil-differential: engineering only; not formal Reference↔Anvil closure" >&2
  exit 0
fi

anvil_dir="$(cd "$(dirname "$anvil_path")" && pwd)"
if [[ -x "$anvil_dir/anvil" && -x "$anvil_dir/cast" ]]; then
  export FOUNDRY_BIN="$anvil_dir"
elif [[ -x "$foundry_bin/anvil" && -x "$foundry_bin/cast" ]]; then
  export FOUNDRY_BIN="$foundry_bin"
else
  echo "evm-anvil-differential: skipped: anvil and cast are not co-located for smoke_evm.sh" >&2
  echo "evm-anvil-differential: engineering only; not formal Reference↔Anvil closure" >&2
  exit 0
fi

# Optional forge presence note (not required by this gate; recorded for operators).
if [[ -x "$FOUNDRY_BIN/forge" ]] || command -v forge >/dev/null 2>&1; then
  : # forge available; unused by product EVM differential
else
  echo "evm-anvil-differential: note: forge not required and not found (ok)" >&2
fi

cli=""
if [[ -x "$root/.lake/build/bin/proof-forge-next" ]]; then
  cli="$root/.lake/build/bin/proof-forge-next"
elif command -v proof-forge-next >/dev/null 2>&1; then
  cli="$(command -v proof-forge-next)"
fi

if [[ -z "$cli" ]]; then
  if command -v lake >/dev/null 2>&1; then
    echo "evm-anvil-differential: building product CLI via lake..." >&2
    (cd "$root" && lake build proof-forge-next) || {
      echo "evm-anvil-differential: skipped: lake build proof-forge-next failed" >&2
      echo "evm-anvil-differential: engineering only; not formal Reference↔Anvil closure" >&2
      exit 0
    }
    cli="$root/.lake/build/bin/proof-forge-next"
  fi
fi

if [[ -z "${cli:-}" || ! -x "$cli" ]]; then
  echo "evm-anvil-differential: skipped: product CLI proof-forge-next unavailable" >&2
  echo "evm-anvil-differential: engineering only; not formal Reference↔Anvil closure" >&2
  exit 0
fi

run_cli() {
  # Prefer lake env so Lean runtime dylibs resolve; fall back to bare binary.
  if command -v lake >/dev/null 2>&1; then
    (cd "$root" && lake env "$cli" "$@")
  else
    (cd "$root" && "$cli" "$@")
  fi
}

ensure_build() {
  local src="$1"
  local module="$2"
  local out_dir="$3"
  local bin_name="$4"
  local bin_path="$root/$out_dir/$bin_name"
  if [[ -f "$bin_path" ]]; then
    echo "evm-anvil-differential: reuse $bin_path" >&2
    return 0
  fi
  echo "evm-anvil-differential: product build $module → $out_dir${evm_profile:+ (profile=$evm_profile)}" >&2
  # Product CLI refuses non-empty existing -o dirs (PF-OUTPUT-COLLISION).
  rm -rf "$root/$out_dir"
  mkdir -p "$(dirname "$root/$out_dir")"
  run_cli build "$src" --module "$module" --target evm "${build_profile_args[@]}" -o "$out_dir"
  [[ -f "$bin_path" ]] || {
    echo "evm-anvil-differential: product build missing $bin_path" >&2
    return 1
  }
  if [[ "$evm_profile" == "evm-yul-solc-0.8.34-cancun-v1" ]]; then
    # Observability: Cancun finalize must record the hardfork pin in evidence.
    if [[ -f "$root/$out_dir/evidence.json" ]]; then
      if ! grep -q 'evm-version=cancun' "$root/$out_dir/evidence.json"; then
        echo "evm-anvil-differential: cancun profile evidence missing evm-version=cancun" >&2
        return 1
      fi
    fi
  fi
}

# Required programs for the differential matrix.
ensure_build Examples/Counter.lean Examples.Counter build/v2/evm Counter.bin
ensure_build Examples/Accumulator.lean Examples.Accumulator build/v2/evm-accumulator Accumulator.bin

# Optional but expected when testdata is present (target-smoke parity).
if [[ -f "$root/testdata/valid/ArithOps.lean" ]]; then
  ensure_build testdata/valid/ArithOps.lean ArithOps build/v2/evm-arithops ArithOps.bin \
    || {
      echo "evm-anvil-differential: ArithOps build failed (hard)" >&2
      exit 1
    }
fi

# EventFlow emit/revert fixture: written under build/ (not a committed Example).
# Product surface only — module EventFlow, single public-UInt64 event + error.
eventflow_src_dir="$root/build/v2/_eventflow_src"
eventflow_src="$eventflow_src_dir/EventFlow.lean"
mkdir -p "$eventflow_src_dir"
cat >"$eventflow_src" <<'LEAN'
import ProofForgeV2

open ProofForgeV2.Language

-- Engineering Anvil emit/revert fixture (not a product Example; generated by
-- scripts/evm_anvil_differential.sh). log1 Moved(src,dst); Cap revert arm.
program EventFlow where
  state count : UInt64

  event Moved(src : UInt64, dst : UInt64)
  error Cap(limit : UInt64)

  init(initial : UInt64) do
    count := initial

  entry bump(delta : UInt64) : UInt64 do
    emit Moved(count, delta)
    if count > delta then
      revert Cap(delta)
    else
      count := count + delta
    return count

  view get() : UInt64 do
    return count
LEAN

# Source path must be project-relative under repo root.
if [[ ! -f "$root/build/v2/evm-eventflow/EventFlow.bin" ]]; then
  echo "evm-anvil-differential: product build EventFlow → build/v2/evm-eventflow${evm_profile:+ (profile=$evm_profile)}" >&2
  rm -rf "$root/build/v2/evm-eventflow"
  run_cli build build/v2/_eventflow_src/EventFlow.lean --module EventFlow --target evm \
    "${build_profile_args[@]}" -o build/v2/evm-eventflow || {
    echo "evm-anvil-differential: EventFlow build failed (hard — emit coverage required when tools present)" >&2
    exit 1
  }
  [[ -f "$root/build/v2/evm-eventflow/EventFlow.bin" ]] || {
    echo "evm-anvil-differential: missing EventFlow.bin after build" >&2
    exit 1
  }
else
  echo "evm-anvil-differential: reuse build/v2/evm-eventflow/EventFlow.bin" >&2
fi

echo "evm-anvil-differential: running scripts/smoke_evm.sh via FOUNDRY_BIN=$FOUNDRY_BIN${evm_profile:+ profile=$evm_profile}" >&2
echo "evm-anvil-differential: engineering runtime only; not formal Reference↔Anvil closure" >&2
# Propagate profile so smoke_evm pins anvil --hardfork cancun when requested.
export PF_EVM_PROFILE="$evm_profile"
bash "$root/scripts/smoke_evm.sh"

# Token: best-effort companion (Map pilot may exceed initcode limits → skip-clean).
if [[ -x "$root/scripts/evm_token_anvil_smoke.sh" ]]; then
  echo "evm-anvil-differential: companion Token smoke (skip-clean on initcode/deploy limits)" >&2
  bash "$root/scripts/evm_token_anvil_smoke.sh" || {
    # Token script exits 0 on skip and 1 on real assertion failure.
    echo "evm-anvil-differential: Token smoke failed (hard)" >&2
    exit 1
  }
fi

echo "evm-anvil-differential: ok (engineering Anvil state differential; not formal C-3)" >&2
