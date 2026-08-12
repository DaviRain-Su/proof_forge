#!/usr/bin/env bash
# One-shot near-sandbox call/view for `pf run -t near -- <method> [u64…]`.
#
# Inputs:
#   PF_NEAR_ARTIFACT_DIR   — OutputSet with *.wasm + manifest.json (required)
#   PF_NEAR_METHOD         — export method name (required)
#   PF_NEAR_ARGS           — space-separated u64 decimals (optional)
#   PF_NEAR_MODE           — call | view  (default: auto from method name)
#   PROOF_FORGE_TOOL_ROOT  — Tool Lock root (near-sandbox)
#
# Honesty: engineering sandbox only — not testnet/mainnet, not formal.
# Sync call / transfer stay FC at the compiler; this only drives one contract method.
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${_script_dir}/.." && pwd)"
export PROOF_FORGE_ROOT="${PROOF_FORGE_ROOT:-$root}"

die() { echo "pf-near-run: FAIL: $*" >&2; exit 1; }
skip_clean() {
  echo "pf-near-run: skipped: $*" >&2
  exit 0
}

case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *) skip_clean "unsupported host $(uname -s)" ;;
esac
export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"

resolve_tool() {
  local name="$1"
  if [[ -n "${PROOF_FORGE_TOOL_ROOT:-}" && -x "${PROOF_FORGE_TOOL_ROOT%/}/$name" ]]; then
    echo "${PROOF_FORGE_TOOL_ROOT%/}/$name"; return 0
  fi
  command -v "$name" 2>/dev/null || return 1
}

artifact_dir="${PF_NEAR_ARTIFACT_DIR:-}"
method="${PF_NEAR_METHOD:-}"
mode="${PF_NEAR_MODE:-}"
args_str="${PF_NEAR_ARGS:-}"

[[ -n "$artifact_dir" && -d "$artifact_dir" ]] || die "PF_NEAR_ARTIFACT_DIR missing (run pf build -t near)"
artifact_dir="$(cd "$artifact_dir" && pwd)"
[[ -f "$artifact_dir/manifest.json" ]] || die "missing manifest.json under $artifact_dir"
[[ -n "$method" ]] || die "PF_NEAR_METHOD required"

if [[ -z "$mode" ]]; then
  # Prefer exact export mode from *.near-abi.json when present.
  abi="$(find "$artifact_dir" -maxdepth 2 -type f -name '*.near-abi.json' | sort | head -n 1 || true)"
  if [[ -n "$abi" && -f "$abi" ]]; then
    mode="$(PF_NEAR_ABI_PATH="$abi" PF_NEAR_ABI_METHOD="$method" python3 - <<'PY'
import json, os
abi_path = os.environ["PF_NEAR_ABI_PATH"]
method = os.environ["PF_NEAR_ABI_METHOD"]
try:
    data = json.loads(open(abi_path, encoding="utf-8").read())
except Exception:
    print("")
    raise SystemExit(0)
for ex in data.get("exports") or []:
    if ex.get("name") == method:
        m = ex.get("mode") or ""
        print("view" if m == "view" else "call")
        raise SystemExit(0)
print("")
PY
)"
  fi
  if [[ -z "$mode" ]]; then
    case "$method" in
      get*|view*|native*|seconds|height|getPose|getBuf|getArr|getPair|getOpt|dump|*Balance|*BalanceU128|selfIsContract|callerIsContract)
        mode="view" ;;
      *) mode="call" ;;
    esac
  fi
fi

if [[ -f "$artifact_dir/StateCell.wasm" ]]; then
  wasm="$artifact_dir/StateCell.wasm"
else
  wasm="$(find "$artifact_dir" -maxdepth 2 -type f -name '*.wasm' | sort | head -n 1 || true)"
fi
[[ -n "$wasm" && -f "$wasm" ]] || die "no *.wasm under $artifact_dir"

if ! sandbox="$(resolve_tool near-sandbox)"; then
  skip_clean "near-sandbox not found under $PROOF_FORGE_TOOL_ROOT"
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
    python3 -m pip install --user -q -r "$req" || skip_clean "python cryptography+base58 unavailable"
  else
    skip_clean "python cryptography+base58 unavailable"
  fi
fi

crate_dir="$root/runtime-tests/near"
[[ -f "$crate_dir/near_rpc.py" ]] || skip_clean "missing $crate_dir/near_rpc.py"

pick_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

workdir="$(mktemp -d "${TMPDIR:-/tmp}/pf-near-run.XXXXXX")"
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
    die "near-sandbox exited early; log: $(tail -20 "$workdir/node.log")"
  fi
  sleep 0.5
done
[[ "$ready" -eq 1 ]] || die "near-sandbox RPC not ready"

export PYTHONPATH="$crate_dir${PYTHONPATH:+:$PYTHONPATH}"
export PF_NEAR_RPC="$rpc"
export PF_NEAR_HOME="$home"
export PF_NEAR_WASM="$wasm"
export PF_NEAR_METHOD="$method"
export PF_NEAR_MODE="$mode"
export PF_NEAR_ARGS="$args_str"

python3 - <<'PY'
import os
import sys
from pathlib import Path

from near_rpc import NearClient, NearRpcError

rpc = os.environ["PF_NEAR_RPC"]
home = Path(os.environ["PF_NEAR_HOME"])
wasm = Path(os.environ["PF_NEAR_WASM"])
method = os.environ["PF_NEAR_METHOD"]
mode = os.environ.get("PF_NEAR_MODE", "call")
args_str = os.environ.get("PF_NEAR_ARGS", "").strip()
u64s = [int(x) for x in args_str.split()] if args_str else []
wire = b"".join(NearClient.encode_u64_le(n) for n in u64s)

client = NearClient(rpc, home)
client.deploy(wasm)

try:
    if mode == "view":
        raw = client.view(method, wire)
        if len(raw) >= 8:
            # print all full u64 words
            words = [NearClient.decode_u64_le(raw, i) for i in range(0, len(raw) - (len(raw) % 8), 8)]
            print(" ".join(str(w) for w in words))
        else:
            print(raw.hex() or "ok")
    else:
        receipt = client.call(method, wire)
        sv = NearClient.success_value_bytes(receipt)
        if sv is not None and len(sv) >= 8:
            words = [NearClient.decode_u64_le(sv, i) for i in range(0, len(sv) - (len(sv) % 8), 8)]
            print(" ".join(str(w) for w in words))
        else:
            print("ok")
except NearRpcError as e:
    print(f"pf-near-run: FAIL: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"pf-near-run: FAIL: {e}", file=sys.stderr)
    sys.exit(1)
print("pf-near-run: ok", file=sys.stderr)
PY

cleanup
trap - EXIT
exit 0
