#!/usr/bin/env bash
# NEAR local near-sandbox test for `pf test -t near` / `proof-forge-next local --target near`.
#
# Bundle-first script (shipped under scripts/ in engineering-dist).
#
# Modes:
#   artifact (default when PF_NEAR_ARTIFACT_DIR has *.wasm)
#     — run ONE suite against the prebuilt Wasm (no lake rebuild of the full corpus).
#     Maps program stem → suite (StateCell → state_cell, PoseTransform → posetransform, …).
#     Unknown / unsupported shapes fail closed (not silent pass).
#   corpus
#     — full scripts/near_runtime_test.sh (rebuilds all fixtures; monorepo-heavy).
#     Force with: PF_NEAR_TEST_MODE=corpus
#
# Inputs:
#   PF_NEAR_ARTIFACT_DIR     — OutputSet from `pf build -t near` (required for artifact mode)
#   PF_NEAR_TEST_MODE        — auto | artifact | corpus  (default: auto)
#   PF_NEAR_SUITE            — override suite name in artifact mode
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

resolve_tool() {
  local name="$1"
  if [[ -n "${PROOF_FORGE_TOOL_ROOT:-}" && -x "${PROOF_FORGE_TOOL_ROOT%/}/$name" ]]; then
    echo "${PROOF_FORGE_TOOL_ROOT%/}/$name"
    return 0
  fi
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  return 1
}

artifact_dir="${PF_NEAR_ARTIFACT_DIR:-${1:-}}"
mode_req="${PF_NEAR_TEST_MODE:-auto}"

has_wasm=0
wasm_path=""
program_stem=""
if [[ -n "$artifact_dir" ]]; then
  [[ -d "$artifact_dir" ]] || die "artifact dir missing: $artifact_dir (run \`pf build -t near\` first)"
  artifact_dir="$(cd "$artifact_dir" && pwd)"
  [[ -f "$artifact_dir/manifest.json" ]] || die "missing manifest.json under $artifact_dir"
  # Prefer StateCell.wasm (pf new default), else first *.wasm
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

# Resolve mode
mode=""
case "$mode_req" in
  auto)
    if [[ "$has_wasm" -eq 1 ]]; then
      mode="artifact"
    else
      mode="corpus"
    fi
    ;;
  artifact)
    mode="artifact"
    ;;
  corpus)
    mode="corpus"
    ;;
  *)
    die "unknown PF_NEAR_TEST_MODE='$mode_req' (want auto|artifact|corpus)"
    ;;
esac

echo "pf-near-test: mode=$mode" >&2
echo "pf-near-test: honesty — not formal / not testnet / Promise=async / sync call FC" >&2

# --- suite mapping for artifact mode -----------------------------------------
map_program_to_suite() {
  local stem="$1"
  case "$stem" in
    StateCell|state_cell|state-cell) echo "state_cell" ;;
    PairRet|pairret) echo "pairret" ;;
    ArrayRet|arrayret) echo "arrayret" ;;
    OptionRet|optionret) echo "optionret" ;;
    OptionState|optionstate) echo "optionstate" ;;
    VerifiedVaultPF|VerifiedVault|verifiedvault) echo "verifiedvault" ;;
    TipJarAsync|tipjarasync) echo "tipjarasync" ;;
    TokenJarAsync|tokenjarasync) echo "tokenjarasync" ;;
    EnvReadJar|envreadjar) echo "envreadjar" ;;
    CallerCheck|callercheck) echo "callercheck" ;;
    PoseTransform|posetransform) echo "posetransform" ;;
    BlockHeightCheck|blockheightcheck) echo "blockheightcheck" ;;
    ConstAnswer|constanswer) echo "constanswer" ;;
    UnixTimeCheck|unixtimecheck) echo "unixtimecheck" ;;
    BytesRet|bytesret) echo "bytesret" ;;
    # Do not map Counter/Hello — ABI differs from StateCell suite (init/delta).
    *) echo "" ;;
  esac
}

run_artifact_suite() {
  local suite wasm
  suite="${PF_NEAR_SUITE:-}"
  if [[ -z "$suite" ]]; then
    suite="$(map_program_to_suite "$program_stem")"
  fi
  if [[ -z "$suite" ]]; then
    die "unsupported near program shape for artifact fast-path: stem='$program_stem'
  known: StateCell, PairRet, ArrayRet, OptionRet, OptionState, VerifiedVaultPF,
         TipJarAsync, TokenJarAsync, EnvReadJar, CallerCheck, PoseTransform,
         BlockHeightCheck, ConstAnswer, UnixTimeCheck, BytesRet
  force suite: PF_NEAR_SUITE=state_cell
  full corpus: PF_NEAR_TEST_MODE=corpus"
  fi

  wasm="$wasm_path"
  [[ -f "$wasm" ]] || die "wasm missing: $wasm"
  # Wasm magic \0asm
  local magic
  magic="$(head -c 4 "$wasm" | od -An -tx1 | tr -d ' \n')"
  [[ "$magic" == "0061736d" ]] || die "bad Wasm magic for $wasm ($magic)"

  if ! sandbox="$(resolve_tool near-sandbox)"; then
    skip_clean "near-sandbox not found under $PROOF_FORGE_TOOL_ROOT"
  fi
  if ! "$sandbox" --version >/dev/null 2>&1; then
    skip_clean "near-sandbox not runnable on this host"
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    skip_clean "python3 not on PATH"
  fi
  if ! command -v curl >/dev/null 2>&1; then
    skip_clean "curl not on PATH"
  fi
  if ! python3 - <<'PY' >/dev/null 2>&1
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
import base58
PY
  then
    req="$root/runtime-tests/near/requirements.txt"
    if [[ -f "$req" ]] && python3 -m pip --version >/dev/null 2>&1; then
      echo "pf-near-test: installing python deps from $req" >&2
      python3 -m pip install --user -q -r "$req" || skip_clean "python cryptography+base58 unavailable"
    else
      skip_clean "python3 cryptography+base58 unavailable"
    fi
  fi

  crate_dir="$root/runtime-tests/near"
  [[ -f "$crate_dir/run_tests.py" ]] || skip_clean "missing $crate_dir/run_tests.py (bundle/monorepo incomplete)"

  # Optional mock token for tokenjarasync
  if [[ "$suite" == "tokenjarasync" ]]; then
    export PF_NEAR_WAT2WASM
    if ! PF_NEAR_WAT2WASM="$(resolve_tool wat2wasm)"; then
      skip_clean "wat2wasm required for tokenjarasync suite"
    fi
    export PF_NEAR_MOCK_TOKEN_WAT="${PF_NEAR_MOCK_TOKEN_WAT:-$crate_dir/mock_token.wat}"
  fi

  pick_port() {
    python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
  }

  workdir="$(mktemp -d "${TMPDIR:-/tmp}/pf-near-artifact.XXXXXX")"
  sandbox_pid=""
  cleanup() {
    if [[ -n "${sandbox_pid:-}" ]] && kill -0 "$sandbox_pid" 2>/dev/null; then
      kill "$sandbox_pid" 2>/dev/null || true
      wait "$sandbox_pid" 2>/dev/null || true
    fi
    rm -rf "$workdir"
  }
  trap cleanup EXIT

  home="$workdir/home"
  mkdir -p "$home"
  echo "pf-near-test: [$suite] artifact=$wasm" >&2
  echo "pf-near-test: near-sandbox init --home $home" >&2
  "$sandbox" --home "$home" init >/dev/null

  rpc_port="$(pick_port)"
  net_port="$(pick_port)"
  python3 - <<PY
import json
from pathlib import Path
cfg = json.loads(Path("$home/config.json").read_text())
cfg.setdefault("rpc", {})["addr"] = f"127.0.0.1:${rpc_port}"
cfg.setdefault("network", {})["addr"] = f"127.0.0.1:${net_port}"
cfg.setdefault("network", {})["boot_nodes"] = ""
Path("$home/config.json").write_text(json.dumps(cfg, indent=2) + "\n")
PY

  echo "pf-near-test: starting node rpc=127.0.0.1:${rpc_port}" >&2
  "$sandbox" --home "$home" run >"$workdir/node.log" 2>&1 &
  sandbox_pid=$!
  rpc="http://127.0.0.1:${rpc_port}"
  ready=0
  for _ in $(seq 1 90); do
    if curl -sf -X POST "$rpc" \
        -H 'content-type: application/json' \
        -d '{"jsonrpc":"2.0","id":"1","method":"status","params":[]}' \
        >/dev/null 2>&1; then
      ready=1
      break
    fi
    if ! kill -0 "$sandbox_pid" 2>/dev/null; then
      die "near-sandbox exited early; log: $(tail -40 "$workdir/node.log")"
    fi
    sleep 0.5
  done
  [[ "$ready" -eq 1 ]] || die "near-sandbox RPC not ready; log: $(tail -40 "$workdir/node.log")"

  export PF_NEAR_RPC="$rpc"
  export PF_NEAR_HOME="$home"
  export PF_NEAR_WASM="$wasm"
  export PF_NEAR_SUITE="$suite"
  export PYTHONPATH="$crate_dir${PYTHONPATH:+:$PYTHONPATH}"

  echo "pf-near-test: running suite=$suite" >&2
  if ! (
    cd "$crate_dir"
    python3 run_tests.py
  ); then
    tail -40 "$workdir/node.log" >&2 || true
    die "harness suite $suite failed"
  fi

  cleanup
  trap - EXIT
  echo "pf-near-test: ok (artifact suite=$suite program=$program_stem)"
  exit 0
}

run_corpus() {
  local runtime="$root/scripts/near_runtime_test.sh"
  [[ -f "$runtime" ]] || skip_clean "missing $runtime (bundle/monorepo incomplete)"
  echo "pf-near-test: full corpus via $runtime" >&2
  log="$(mktemp "${TMPDIR:-/tmp}/pf-near-test.XXXXXX.log")"
  cleanup_log() { rm -f "$log"; }
  trap cleanup_log EXIT
  set +e
  bash -p "$runtime" >"$log" 2>&1
  rc=$?
  set -e
  cat "$log"
  if [[ "$rc" -ne 0 ]]; then
    die "near_runtime_test.sh failed (exit $rc)"
  fi
  if grep -q "skipped:" "$log"; then
    echo "pf-near-test: skipped: near-sandbox tools or deps unavailable (see log above)" >&2
    exit 0
  fi
  if grep -q "near-runtime-test: PASS" "$log"; then
    echo "pf-near-test: ok (near-sandbox engineering corpus)"
    exit 0
  fi
  echo "pf-near-test: ok (near_runtime_test exit 0; see log)"
  exit 0
}

if [[ "$mode" == "artifact" ]]; then
  if [[ "$has_wasm" -ne 1 ]]; then
    die "artifact mode requires *.wasm under PF_NEAR_ARTIFACT_DIR (got: ${artifact_dir:-empty})
  run: pf build -t near && pf test -t near
  or:  PF_NEAR_TEST_MODE=corpus pf test -t near"
  fi
  run_artifact_suite
else
  run_corpus
fi
