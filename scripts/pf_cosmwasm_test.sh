#!/usr/bin/env bash
# CosmWasm local mock-runtime test for `pf test -t cosmwasm`.
#
# Bundle-first script (shipped under scripts/ in engineering-dist).
#
# Modes:
#   artifact (default when PF_COSMWASM_ARTIFACT_DIR has *.wasm)
#     — run ONE cargo integration test against the prebuilt Wasm
#       (no lake rebuild of the full corpus).
#     Maps program stem → Rust test binary name.
#     Unknown / unsupported shapes fail closed (not silent pass).
#   corpus
#     — full scripts/cosmwasm_runtime_test.sh (rebuilds all fixtures; monorepo-heavy).
#     Force with: PF_COSMWASM_TEST_MODE=corpus
#
# Inputs:
#   PF_COSMWASM_ARTIFACT_DIR     — OutputSet from `pf build -t cosmwasm`
#   PF_COSMWASM_TEST_MODE        — auto | artifact | corpus  (default: auto)
#   PF_COSMWASM_SUITE            — override cargo test binary name in artifact mode
#   PROOF_FORGE_ROOT             — monorepo or bundle root
#   PROOF_FORGE_TOOL_ROOT        — Tool Lock root (wat2wasm for corpus rebuild)
#   PF_COSMWASM_RUNTIME_REQUIRED — set 1 to hard-fail when tools missing
#
# Honesty: engineering cosmwasm-vm mock only — not formal, not wasmd mainnet,
# not public broadcast. Generic sync call FC; schedule = SubMsg reply_on=never.
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${_script_dir}/.." && pwd)"
export PROOF_FORGE_ROOT="${PROOF_FORGE_ROOT:-$root}"

die() { echo "pf-cosmwasm-test: FAIL: $*" >&2; exit 1; }
skip_clean() {
  echo "pf-cosmwasm-test: skipped: $*" >&2
  if [[ "${PF_COSMWASM_RUNTIME_REQUIRED:-0}" == "1" ]]; then
    exit 2
  fi
  exit 0
}

case "$(uname -s)" in
  Darwin)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"
    ;;
  Linux)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)"
    ;;
  *)
    skip_clean "unsupported host platform $(uname -s)"
    ;;
esac

export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"

artifact_dir="${PF_COSMWASM_ARTIFACT_DIR:-${1:-}}"
mode_req="${PF_COSMWASM_TEST_MODE:-auto}"

has_wasm=0
wasm_path=""
program_stem=""
if [[ -n "$artifact_dir" ]]; then
  [[ -d "$artifact_dir" ]] || die "artifact dir missing: $artifact_dir (run \`pf build -t cosmwasm\` first)"
  artifact_dir="$(cd "$artifact_dir" && pwd)"
  [[ -f "$artifact_dir/manifest.json" ]] || die "missing manifest.json under $artifact_dir"
  if [[ -f "$artifact_dir/StateCell.wasm" ]]; then
    wasm_path="$artifact_dir/StateCell.wasm"
  else
    wasm_path="$(find "$artifact_dir" -maxdepth 2 -type f -name '*.wasm' | sort | head -n 1 || true)"
  fi
  if [[ -n "$wasm_path" && -f "$wasm_path" ]]; then
    has_wasm=1
    program_stem="$(basename "$wasm_path" .wasm)"
  fi
fi

mode=""
case "$mode_req" in
  auto)
    if [[ "$has_wasm" -eq 1 ]]; then
      mode="artifact"
    else
      mode="corpus"
    fi
    ;;
  artifact) mode="artifact" ;;
  corpus) mode="corpus" ;;
  *)
    die "unknown PF_COSMWASM_TEST_MODE='$mode_req' (want auto|artifact|corpus)"
    ;;
esac

echo "pf-cosmwasm-test: mode=$mode" >&2
echo "pf-cosmwasm-test: honesty — not formal / not wasmd mainnet / sync call FC / schedule=SubMsg never" >&2

# stem → cargo --test <name>
map_program_to_suite() {
  local stem="$1"
  case "$stem" in
    StateCell|state_cell|state-cell) echo "state_cell" ;;
    Accumulator|accumulator) echo "accumulator" ;;
    PairRet|pairret) echo "pair_ret" ;;
    ArrayRet|arrayret) echo "array_ret" ;;
    OptionRet|optionret) echo "option_ret" ;;
    OptionState|optionstate) echo "option_state" ;;
    NarrowStateCell|narrowstatecell) echo "narrow_state_cell" ;;
    EventFlow|eventflow) echo "events" ;;
    ScheduleFlow|scheduleflow) echo "schedule" ;;
    TipJar|tipjar) echo "tipjar" ;;
    TokenJar|tokenjar) echo "tokenjar" ;;
    EnvReadJar|envreadjar) echo "envreadjar" ;;
    CallerGate|callergate) echo "caller_gate" ;;
    BlockHeightCheck|blockheightcheck) echo "block_height" ;;
    ConstAnswer|constanswer) echo "const_answer" ;;
    BytesRet|bytesret) echo "bytes_ret" ;;
    UnixTimeCheck|unixtimecheck) echo "unix_time" ;;
    PoseTransform|posetransform) echo "pose_transform" ;;
    MapMini|mapmini) echo "map_mini" ;;
    Token|token) echo "token" ;;
    MapDump|mapdump) echo "map_dump" ;;
    *) echo "" ;;
  esac
}

run_artifact_suite() {
  local suite wasm name fixtures work
  suite="${PF_COSMWASM_SUITE:-}"
  if [[ -z "$suite" ]]; then
    suite="$(map_program_to_suite "$program_stem")"
  fi
  if [[ -z "$suite" ]]; then
    die "unsupported cosmwasm program shape for artifact fast-path: stem='$program_stem'
  known: StateCell, Accumulator, PairRet, ArrayRet, OptionRet, OptionState,
         NarrowStateCell, EventFlow, ScheduleFlow, TipJar, TokenJar, EnvReadJar,
         CallerGate, BlockHeightCheck, ConstAnswer, BytesRet,
         UnixTimeCheck, PoseTransform, MapMini, Token, MapDump
  force suite: PF_COSMWASM_SUITE=state_cell
  full corpus: PF_COSMWASM_TEST_MODE=corpus"
  fi

  wasm="$wasm_path"
  [[ -f "$wasm" ]] || die "wasm missing: $wasm"
  local magic
  magic="$(head -c 4 "$wasm" | od -An -tx1 | tr -d ' \n')"
  [[ "$magic" == "0061736d" ]] || die "bad Wasm magic for $wasm ($magic)"

  if ! command -v cargo >/dev/null 2>&1; then
    skip_clean "cargo not on PATH (install Rust toolchain)"
  fi

  crate_dir="$root/runtime-tests/cosmwasm"
  [[ -f "$crate_dir/Cargo.toml" ]] || skip_clean "missing $crate_dir/Cargo.toml (bundle/monorepo incomplete)"
  [[ -f "$crate_dir/tests/${suite}.rs" ]] || die "missing cargo test binary $crate_dir/tests/${suite}.rs for suite=$suite"

  name="$program_stem"
  work="$(mktemp -d "${TMPDIR:-/tmp}/pf-cw-artifact.XXXXXX")"
  cleanup() { rm -rf "$work"; }
  trap cleanup EXIT

  # cosmwasm-vm tests expect PROOF_FORGE_FIXTURES_DIR/<Name>/<Name>.wasm
  fixtures="$work/fixtures"
  mkdir -p "$fixtures/$name"
  cp -f "$wasm" "$fixtures/$name/${name}.wasm"
  # Optional ABI sidecar next to wasm (same dir or parent)
  if [[ -f "${wasm%.wasm}.cosmwasm-abi.json" ]]; then
    cp -f "${wasm%.wasm}.cosmwasm-abi.json" "$fixtures/$name/${name}.cosmwasm-abi.json"
  elif [[ -f "$artifact_dir/${name}.cosmwasm-abi.json" ]]; then
    cp -f "$artifact_dir/${name}.cosmwasm-abi.json" "$fixtures/$name/${name}.cosmwasm-abi.json"
  fi

  export PROOF_FORGE_FIXTURES_DIR="$fixtures"
  echo "pf-cosmwasm-test: [$suite] artifact=$wasm fixtures=$fixtures" >&2

  if ! (
    cd "$crate_dir"
    if [[ -f Cargo.lock ]] && cargo test --offline --test "$suite" -- --nocapture; then
      exit 0
    fi
    echo "pf-cosmwasm-test: offline unavailable or failed; cargo test with network" >&2
    cargo test --test "$suite" -- --nocapture
  ); then
    die "cargo test --test $suite failed"
  fi

  cleanup
  trap - EXIT
  echo "pf-cosmwasm-test: ok (artifact suite=$suite program=$program_stem)"
  exit 0
}

run_corpus() {
  local runtime="$root/scripts/cosmwasm_runtime_test.sh"
  [[ -f "$runtime" ]] || skip_clean "missing $runtime (bundle/monorepo incomplete)"
  echo "pf-cosmwasm-test: full corpus via $runtime" >&2
  log="$(mktemp "${TMPDIR:-/tmp}/pf-cw-test.XXXXXX.log")"
  cleanup_log() { rm -f "$log"; }
  trap cleanup_log EXIT
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
}

if [[ "$mode" == "artifact" ]]; then
  if [[ "$has_wasm" -ne 1 ]]; then
    die "artifact mode requires *.wasm under PF_COSMWASM_ARTIFACT_DIR (got: ${artifact_dir:-empty})
  run: pf build -t cosmwasm && pf test -t cosmwasm
  or:  PF_COSMWASM_TEST_MODE=corpus pf test -t cosmwasm"
  fi
  run_artifact_suite
else
  run_corpus
fi
