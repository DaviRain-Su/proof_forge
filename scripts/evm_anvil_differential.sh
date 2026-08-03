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
# Profile-keyed output trees (must match smoke_evm.sh artifact_dir):
#   legacy/default → build/v2/evm, … (no suffix; historical paths)
#   cancun         → build/v2/evm-cancun, …
artifact_suffix=""
expected_profile_wire="evm-yul-solc-0.8.34-v1"
case "$evm_profile" in
  "")
    : # default product profile (legacy); keep historical output dirs
    ;;
  "evm-yul-solc-0.8.34-v1")
    build_profile_args+=(--profile "$evm_profile")
    expected_profile_wire="evm-yul-solc-0.8.34-v1"
    echo "evm-anvil-differential: explicit profile=$evm_profile" >&2
    ;;
  "evm-yul-solc-0.8.34-cancun-v1")
    build_profile_args+=(--profile "$evm_profile")
    artifact_suffix="-cancun"
    expected_profile_wire="evm-yul-solc-0.8.34-cancun-v1"
    echo "evm-anvil-differential: explicit profile=$evm_profile (artifact suffix=$artifact_suffix)" >&2
    ;;
  *)
    echo "evm-anvil-differential: unsupported PF_EVM_PROFILE='$evm_profile'" >&2
    exit 1
    ;;
esac

# Logical base dir name → product -o path (relative to repo root).
profile_out_dir() {
  echo "build/v2/${1}${artifact_suffix}"
}

# Refuse to reuse bins that do not match the requested profile/hardfork pin.
# Cancun: require evidence note + manifest profile identity.
# Legacy: refuse trees whose evidence claims cancun (would mix hardforks).
validate_profile_tree() {
  local out_dir="$1"
  local bin_name="$2"
  local bin_path="$root/$out_dir/$bin_name"
  local evidence="$root/$out_dir/evidence.json"
  local manifest="$root/$out_dir/manifest.json"
  [[ -f "$bin_path" ]] || return 1
  if [[ "$expected_profile_wire" == "evm-yul-solc-0.8.34-cancun-v1" ]]; then
    [[ -f "$evidence" ]] || {
      echo "evm-anvil-differential: refuse reuse $out_dir: missing evidence.json" >&2
      return 1
    }
    grep -q 'evm-version=cancun' "$evidence" || {
      echo "evm-anvil-differential: refuse reuse $out_dir: evidence missing evm-version=cancun" >&2
      return 1
    }
    [[ -f "$manifest" ]] || {
      echo "evm-anvil-differential: refuse reuse $out_dir: missing manifest.json" >&2
      return 1
    }
    grep -q "\"codegenProfile\": \"$expected_profile_wire\"" "$manifest" ||
      grep -q "\"codegenProfile\":\"$expected_profile_wire\"" "$manifest" || {
        echo "evm-anvil-differential: refuse reuse $out_dir: manifest codegenProfile != $expected_profile_wire" >&2
        return 1
      }
  else
    # Legacy/default: never reuse a Cancun-finalized tree under a legacy path.
    if [[ -f "$evidence" ]] && grep -q 'evm-version=cancun' "$evidence"; then
      echo "evm-anvil-differential: refuse reuse $out_dir: cancun evidence under legacy path" >&2
      return 1
    fi
    if [[ -f "$manifest" ]] && grep -q 'evm-yul-solc-0.8.34-cancun-v1' "$manifest"; then
      echo "evm-anvil-differential: refuse reuse $out_dir: cancun profile under legacy path" >&2
      return 1
    fi
  fi
  return 0
}

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

# CLI discovery: PROOF_FORGE_CLI → local .lake → PATH (export selection downstream).
cli=""
if [[ -n "${PROOF_FORGE_CLI:-}" && -x "${PROOF_FORGE_CLI}" ]]; then
  cli="$PROOF_FORGE_CLI"
  echo "evm-anvil-differential: using PROOF_FORGE_CLI=$cli" >&2
elif [[ -x "$root/.lake/build/bin/proof-forge-next" ]]; then
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
export PROOF_FORGE_CLI="$cli"

run_cli() {
  # Prefer lake env so Lean runtime dylibs resolve; fall back to bare binary.
  # When PF_LAKE_ROOT is set (worktree without oleans), use that package root.
  # Fixed single-quoted script + positional args — no path/command interpolation.
  local lake_root="${PF_LAKE_ROOT:-$root}"
  if command -v lake >/dev/null 2>&1; then
    (cd "$lake_root" && lake env bash -c 'cd "$1"; shift; exec "$@"' _ "$root" "$cli" "$@")
  else
    (cd "$root" && "$cli" "$@")
  fi
}

ensure_build() {
  local src="$1"
  local module="$2"
  local logical_dir="$3" # e.g. evm, evm-accumulator (suffix applied here)
  local bin_name="$4"
  local out_dir
  out_dir="$(profile_out_dir "$logical_dir")"
  local bin_path="$root/$out_dir/$bin_name"
  if validate_profile_tree "$out_dir" "$bin_name"; then
    echo "evm-anvil-differential: reuse $bin_path (profile=$expected_profile_wire)" >&2
    return 0
  fi
  if [[ -f "$bin_path" ]]; then
    echo "evm-anvil-differential: rebuild $out_dir (existing tree failed profile validation)" >&2
  fi
  echo "evm-anvil-differential: product build $module → $out_dir (profile=$expected_profile_wire)" >&2
  # Product CLI refuses non-empty existing -o dirs (PF-OUTPUT-COLLISION).
  rm -rf "$root/$out_dir"
  mkdir -p "$(dirname "$root/$out_dir")"
  # set -u: empty array expansion is unbound on some bashes; only expand when set.
  if [[ ${#build_profile_args[@]} -gt 0 ]]; then
    run_cli build "$src" --module "$module" --target evm "${build_profile_args[@]}" -o "$out_dir"
  else
    run_cli build "$src" --module "$module" --target evm -o "$out_dir"
  fi
  [[ -f "$bin_path" ]] || {
    echo "evm-anvil-differential: product build missing $bin_path" >&2
    return 1
  }
  validate_profile_tree "$out_dir" "$bin_name" || {
    echo "evm-anvil-differential: post-build profile validation failed for $out_dir" >&2
    return 1
  }
}

# Required programs for the differential matrix (profile-keyed dirs).
ensure_build Examples/Counter.lean Examples.Counter evm Counter.bin
ensure_build Examples/Accumulator.lean Examples.Accumulator evm-accumulator Accumulator.bin

# Optional but expected when testdata is present (target-smoke parity).
if [[ -f "$root/testdata/valid/ArithOps.lean" ]]; then
  ensure_build testdata/valid/ArithOps.lean ArithOps evm-arithops ArithOps.bin \
    || {
      echo "evm-anvil-differential: ArithOps build failed (hard)" >&2
      exit 1
    }
fi

# EventFlow emit/revert fixture: committed under testdata/evm-corpus/v1/programs/
# (EVMOZ-004). Do not generate under build/ — product build uses the fixture.
eventflow_src="testdata/evm-corpus/v1/programs/EventFlow.lean"
eventflow_out="$(profile_out_dir evm-eventflow)"
if [[ ! -f "$root/$eventflow_src" ]]; then
  echo "evm-anvil-differential: missing committed EventFlow fixture $eventflow_src" >&2
  exit 1
fi

# Source path must be project-relative under repo root. Reuse only when bin +
# evidence/manifest match the active profile (Cancun requires both markers).
if validate_profile_tree "$eventflow_out" "EventFlow.bin"; then
  echo "evm-anvil-differential: reuse $eventflow_out/EventFlow.bin (profile=$expected_profile_wire)" >&2
else
  echo "evm-anvil-differential: product build EventFlow → $eventflow_out (profile=$expected_profile_wire)" >&2
  rm -rf "$root/$eventflow_out"
  if [[ ${#build_profile_args[@]} -gt 0 ]]; then
    run_cli build "$eventflow_src" --module EventFlow --target evm \
      "${build_profile_args[@]}" -o "$eventflow_out" || {
      echo "evm-anvil-differential: EventFlow build failed (hard — emit coverage required when tools present)" >&2
      exit 1
    }
  else
    run_cli build "$eventflow_src" --module EventFlow --target evm \
      -o "$eventflow_out" || {
      echo "evm-anvil-differential: EventFlow build failed (hard — emit coverage required when tools present)" >&2
      exit 1
    }
  fi
  [[ -f "$root/$eventflow_out/EventFlow.bin" ]] || {
    echo "evm-anvil-differential: missing EventFlow.bin after build" >&2
    exit 1
  }
  validate_profile_tree "$eventflow_out" "EventFlow.bin" || {
    echo "evm-anvil-differential: EventFlow post-build profile validation failed" >&2
    exit 1
  }
fi

echo "evm-anvil-differential: running scripts/smoke_evm.sh via FOUNDRY_BIN=$FOUNDRY_BIN profile=$expected_profile_wire" >&2
echo "evm-anvil-differential: engineering runtime only; not formal Reference↔Anvil closure" >&2
# Propagate profile so smoke_evm pins hardfork + profile-keyed artifact dirs.
export PF_EVM_PROFILE="$evm_profile"
bash "$root/scripts/smoke_evm.sh"

# Token: adapter companion (Map pilot may StackTooDeep / exceed initcode →
# explicit case skip, never silent pass). Must inherit the same PF_EVM_PROFILE.
if [[ -x "$root/scripts/evm_token_anvil_smoke.sh" ]]; then
  echo "evm-anvil-differential: companion Token adapter smoke (explicit StackTooDeep/initcode skip; profile=$expected_profile_wire)" >&2
  PF_EVM_PROFILE="$evm_profile" bash "$root/scripts/evm_token_anvil_smoke.sh" || {
    # Token script exits 0 on explicit skip and 1 on real assertion failure.
    echo "evm-anvil-differential: Token smoke failed (hard)" >&2
    exit 1
  }
fi

echo "evm-anvil-differential: ok (engineering Anvil state differential; not formal C-3)" >&2
