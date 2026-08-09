#!/usr/bin/env bash
# NEAR near-sandbox engineering runtime differential (BL-13 / BL-20 / BL-30):
#   product CLI build → StateCell/PairRet/ArrayRet/OptionRet/OptionState.wasm
#   (wat2wasm) → near-sandbox init/run → JSON-RPC deploy/call/view assert → kill
#
# Covers:
#   StateCell: init(7) / increment(5) / get==12 / overflow state-hold / recovery
#   PairRet: named Struct aggregate return (init + setPair/getPair N×8 LE)
#   ArrayRet: anonymous Array UInt64 2 return (init + setArr/getArr N×8 LE)
#   OptionRet: anonymous Option UInt64 none/some (2×8 LE tag+payload)
#   OptionState: Option UInt64 state tag+payload (none default / some / clear zero)
#
# Not testnet, not mainnet, not formal Stage-0 / hermetic release evidence /
# Reference↔sandbox formal differential (main agent decides just recipe wiring).
#
# Requires:
#   - lake / Lean toolchain on PATH
#   - python3 with cryptography + base58 (see runtime-tests/near/requirements.txt)
#   - locked near-sandbox under PROOF_FORGE_TOOL_ROOT (or default cache root)
#   - locked wat2wasm under PROOF_FORGE_TOOL_ROOT (or PATH) for finalize
#   - curl (RPC readiness probe)
#
# Exit codes:
#   0 success (or skip-clean when tools/python deps absent)
#   1 product / sandbox / assert failure
#   2 missing tools / usage (hard miss on unsupported host)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

die() {
  echo "near-runtime-test: $*" >&2
  exit 1
}

missing() {
  echo "near-runtime-test: $*" >&2
  exit 2
}

skip_clean() {
  echo "near-runtime-test: skipped: $*" >&2
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
    missing "unsupported host platform: $(uname -s)"
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
  if [[ -x "/opt/homebrew/bin/$name" ]]; then
    echo "/opt/homebrew/bin/$name"
    return 0
  fi
  if [[ -x "/usr/local/bin/$name" ]]; then
    echo "/usr/local/bin/$name"
    return 0
  fi
  return 1
}

if ! command -v lake >/dev/null 2>&1; then
  skip_clean "lake not on PATH"
fi
if ! command -v python3 >/dev/null 2>&1; then
  skip_clean "python3 not on PATH"
fi
if ! command -v curl >/dev/null 2>&1; then
  skip_clean "curl not on PATH"
fi

if ! sandbox="$(resolve_tool near-sandbox)"; then
  skip_clean "near-sandbox not found under $PROOF_FORGE_TOOL_ROOT (or PATH)"
fi
if ! wat2wasm="$(resolve_tool wat2wasm)"; then
  skip_clean "wat2wasm not found under $PROOF_FORGE_TOOL_ROOT (or PATH)"
fi

# cryptography + base58 required for Ed25519 tx signing / key wire.
if ! python3 - <<'PY' >/dev/null 2>&1
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
import base58
PY
then
  # Try offline install from requirements if pip present; otherwise skip-clean.
  req="$root/runtime-tests/near/requirements.txt"
  if command -v pip3 >/dev/null 2>&1 || python3 -m pip --version >/dev/null 2>&1; then
    echo "near-runtime-test: installing python deps from $req" >&2
    if ! python3 -m pip install --user -q -r "$req"; then
      skip_clean "python3 cryptography+base58 unavailable (pip install failed; see runtime-tests/near/requirements.txt)"
    fi
    if ! python3 - <<'PY' >/dev/null 2>&1
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
import base58
PY
    then
      skip_clean "python3 cryptography+base58 still unavailable after pip install"
    fi
  else
    skip_clean "python3 cryptography+base58 unavailable (install per runtime-tests/near/requirements.txt)"
  fi
fi

cli="$root/.lake/build/bin/proof-forge-next"
out_dir="${PROOF_FORGE_RUNTIME_OUT:-$root/build/v2/near-runtime}"
crate_dir="$root/runtime-tests/near"

programs=(
  "Examples/StateCell.lean:Examples.StateCell:StateCell"
  "runtime-tests/near/fixtures/PairRet.lean:Examples.PairRet:PairRet"
  "runtime-tests/near/fixtures/ArrayRet.lean:Examples.ArrayRet:ArrayRet"
  "runtime-tests/near/fixtures/OptionRet.lean:Examples.OptionRet:OptionRet"
  "runtime-tests/near/fixtures/OptionState.lean:Examples.OptionState:OptionState"
  "Examples/TipJarAsync.lean:Examples.TipJarAsync:TipJarAsync"
  "runtime-tests/near/fixtures/TokenJarAsync.lean:Examples.TokenJarAsync:TokenJarAsync"
  "runtime-tests/near/fixtures/EnvReadJar.lean:Examples.EnvReadJar:EnvReadJar"
  "runtime-tests/near/fixtures/CallerCheck.lean:Examples.CallerCheck:CallerCheck"
)

echo "near-runtime-test: engineering near-sandbox differential (not formal/testnet)"
echo "near-runtime-test: building proof-forge-next (lake build proof_forge_next)"
lake build proof_forge_next || die "lake build proof_forge_next failed"
[[ -x "$cli" ]] || die "CLI missing after build: $cli"

echo "near-runtime-test: tool root=$PROOF_FORGE_TOOL_ROOT"
echo "near-runtime-test: near-sandbox=$sandbox"
"$sandbox" --version 2>&1 | head -1 || true
echo "near-runtime-test: wat2wasm=$wat2wasm ($("$wat2wasm" --version 2>&1 | head -1 || true))"
echo "near-runtime-test: python3=$(python3 --version 2>&1)"

# CLI rejects pre-existing -o paths (PF-OUTPUT-COLLISION); remove and let it create.
rm -rf "$out_dir"
mkdir -p "$out_dir"

normalize_wasm() {
  local name="$1"
  local fixture_out="$2"
  local wasm=""
  if [[ -f "$fixture_out/${name}.wasm" ]]; then
    wasm="$fixture_out/${name}.wasm"
  else
    wasm="$(find "$fixture_out" -name "${name}.wasm" -type f 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$wasm" || ! -f "$wasm" ]]; then
    local wat=""
    if [[ -f "$fixture_out/${name}.wat" ]]; then
      wat="$fixture_out/${name}.wat"
    else
      wat="$(find "$fixture_out" -name "${name}.wat" -type f 2>/dev/null | head -n 1 || true)"
    fi
    [[ -n "$wat" && -f "$wat" ]] || return 1
    wasm="$fixture_out/${name}.wasm"
    if ! "$wat2wasm" "$wat" -o "$wasm" 2>"$out_dir/${name}.wat2wasm.err"; then
      echo "near-runtime-test: wat2wasm failed for $name" >&2
      cat "$out_dir/${name}.wat2wasm.err" >&2 || true
      return 1
    fi
  fi
  if [[ "$(cd "$(dirname "$wasm")" && pwd)" != "$(cd "$fixture_out" && pwd)" ]]; then
    cp -f "$wasm" "$fixture_out/${name}.wasm"
  fi
  # Optional ABI sidecar normalize
  local abi=""
  if [[ -f "$fixture_out/${name}.near-abi.json" ]]; then
    abi="$fixture_out/${name}.near-abi.json"
  else
    abi="$(find "$fixture_out" -name "${name}.near-abi.json" -type f 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -n "$abi" && -f "$abi" && "$(cd "$(dirname "$abi")" && pwd)" != "$(cd "$fixture_out" && pwd)" ]]; then
    cp -f "$abi" "$fixture_out/${name}.near-abi.json"
  fi
  [[ -f "$fixture_out/${name}.wasm" ]] || return 1
  local magic
  magic="$(head -c 4 "$fixture_out/${name}.wasm" | od -An -tx1 | tr -d ' \n')"
  [[ "$magic" == "0061736d" ]] || {
    echo "near-runtime-test: bad Wasm magic for $name ($magic)" >&2
    return 1
  }
  echo "near-runtime-test: ${name}.wasm=$(wc -c <"$fixture_out/${name}.wasm" | tr -d ' ') bytes"
  return 0
}

for entry in "${programs[@]}"; do
  IFS=':' read -r rel_src module name <<<"$entry"
  src="$root/$rel_src"
  [[ -f "$src" ]] || die "source missing: $src"
  fixture_out="$out_dir/$name"
  echo "near-runtime-test: build $rel_src --module $module --target near -o $fixture_out"
  if ! lake env "$cli" build \
    "$rel_src" \
    --module "$module" \
    --target near \
    -o "$fixture_out"; then
    die "proof-forge-next build failed for $name"
  fi
  normalize_wasm "$name" "$fixture_out" || die "${name}.wasm not found under $fixture_out (need wat2wasm finalize)"
done

state_cell_wasm="$out_dir/StateCell/StateCell.wasm"
pairret_wasm="$out_dir/PairRet/PairRet.wasm"
arrayret_wasm="$out_dir/ArrayRet/ArrayRet.wasm"
optionret_wasm="$out_dir/OptionRet/OptionRet.wasm"
optionstate_wasm="$out_dir/OptionState/OptionState.wasm"
tipjarasync_wasm="$out_dir/TipJarAsync/TipJarAsync.wasm"
tokenjarasync_wasm="$out_dir/TokenJarAsync/TokenJarAsync.wasm"
envreadjar_wasm="$out_dir/EnvReadJar/EnvReadJar.wasm"
callercheck_wasm="$out_dir/CallerCheck/CallerCheck.wasm"
[[ -f "$state_cell_wasm" ]] || die "missing $state_cell_wasm"
[[ -f "$pairret_wasm" ]] || die "missing $pairret_wasm"
[[ -f "$arrayret_wasm" ]] || die "missing $arrayret_wasm"
[[ -f "$optionret_wasm" ]] || die "missing $optionret_wasm"
[[ -f "$optionstate_wasm" ]] || die "missing $optionstate_wasm"
[[ -f "$tipjarasync_wasm" ]] || die "missing $tipjarasync_wasm"
[[ -f "$tokenjarasync_wasm" ]] || die "missing $tokenjarasync_wasm"
[[ -f "$envreadjar_wasm" ]] || die "missing $envreadjar_wasm"
[[ -f "$callercheck_wasm" ]] || die "missing $callercheck_wasm"

# --- sandbox helpers --------------------------------------------------------

pick_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

# Run one suite against a fresh near-sandbox home (avoids state key collisions
# between fixtures on the same account without subaccount machinery).
run_suite() {
  local suite_name="$1"
  local wasm_path="$2"
  local workdir sandbox_pid rpc_port net_port home rpc ready

  workdir="$(mktemp -d "${TMPDIR:-/tmp}/near-runtime-${suite_name}.XXXXXX")"
  sandbox_pid=""

  cleanup_suite() {
    if [[ -n "${sandbox_pid:-}" ]] && kill -0 "$sandbox_pid" 2>/dev/null; then
      kill "$sandbox_pid" 2>/dev/null || true
      wait "$sandbox_pid" 2>/dev/null || true
    fi
    rm -rf "$workdir"
  }
  trap cleanup_suite EXIT

  home="$workdir/home"
  mkdir -p "$home"
  echo "near-runtime-test: [$suite_name] near-sandbox init --home $home"
  "$sandbox" --home "$home" init >/dev/null

  rpc_port="$(pick_port)"
  net_port="$(pick_port)"
  python3 - <<PY
import json
from pathlib import Path
cfg_path = Path("$home") / "config.json"
cfg = json.loads(cfg_path.read_text())
cfg.setdefault("rpc", {})["addr"] = f"127.0.0.1:${rpc_port}"
cfg.setdefault("network", {})["addr"] = f"127.0.0.1:${net_port}"
cfg.setdefault("network", {})["boot_nodes"] = ""
cfg_path.write_text(json.dumps(cfg, indent=2) + "\n")
PY

  echo "near-runtime-test: [$suite_name] starting node rpc=127.0.0.1:${rpc_port}"
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
      echo "near-runtime-test: FAIL: near-sandbox exited early ($suite_name)" >&2
      tail -80 "$workdir/node.log" >&2 || true
      cleanup_suite
      trap - EXIT
      return 1
    fi
    sleep 0.5
  done
  if [[ "$ready" -ne 1 ]]; then
    echo "near-runtime-test: FAIL: near-sandbox RPC not ready ($suite_name)" >&2
    tail -80 "$workdir/node.log" >&2 || true
    cleanup_suite
    trap - EXIT
    return 1
  fi

  echo "near-runtime-test: [$suite_name] RPC ready; running python harness"
  export PF_NEAR_RPC="$rpc"
  export PF_NEAR_HOME="$home"
  export PF_NEAR_WASM="$wasm_path"
  export PF_NEAR_SUITE="$suite_name"
  export PYTHONPATH="$crate_dir${PYTHONPATH:+:$PYTHONPATH}"

  if ! (
    cd "$crate_dir"
    python3 run_tests.py
  ); then
    echo "near-runtime-test: FAIL: harness suite $suite_name" >&2
    tail -40 "$workdir/node.log" >&2 || true
    cleanup_suite
    trap - EXIT
    return 1
  fi

  cleanup_suite
  trap - EXIT
  echo "near-runtime-test: [$suite_name] ok"
  return 0
}

echo "near-runtime-test: running StateCell suite against near-sandbox"
run_suite state_cell "$state_cell_wasm" || die "StateCell suite failed"

echo "near-runtime-test: running PairRet suite against near-sandbox"
run_suite pairret "$pairret_wasm" || die "PairRet suite failed"

echo "near-runtime-test: running ArrayRet suite against near-sandbox"
run_suite arrayret "$arrayret_wasm" || die "ArrayRet suite failed"

echo "near-runtime-test: running OptionRet suite against near-sandbox"
run_suite optionret "$optionret_wasm" || die "OptionRet suite failed"

echo "near-runtime-test: running OptionState suite against near-sandbox"
run_suite optionstate "$optionstate_wasm" || die "OptionState suite failed"

echo "near-runtime-test: running TipJarAsync suite against near-sandbox"
run_suite tipjarasync "$tipjarasync_wasm" || die "TipJarAsync suite failed"

echo "near-runtime-test: running TokenJarAsync suite against near-sandbox"
export PF_NEAR_WAT2WASM="$wat2wasm"
run_suite tokenjarasync "$tokenjarasync_wasm" || die "TokenJarAsync suite failed"

echo "near-runtime-test: running EnvReadJar suite against near-sandbox"
run_suite envreadjar "$envreadjar_wasm" || die "EnvReadJar suite failed"

echo "near-runtime-test: running CallerCheck suite against near-sandbox"
run_suite callercheck "$callercheck_wasm" || die "CallerCheck suite failed"

echo "near-runtime-test: PASS (StateCell + PairRet + ArrayRet + OptionRet + OptionState + TipJarAsync + TokenJarAsync + EnvReadJar + CallerCheck engineering sandbox differential)"
exit 0
