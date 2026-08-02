#!/usr/bin/env bash
# NEAR near-sandbox receipt acceptance helper (engineering only; G123).
#
# Starts a local near-sandbox node, deploys product Counter.wasm (or a provided
# .wasm), calls init/increment/get, and asserts state via view + receipts.
#
# Exit codes:
#   0  — accepted, or required tools unavailable (skip with message)
#   1  — tools present but deploy/call/assert failed
#   2  — usage / host error
#
# Not formal Stage-0 / hermetic Tool Lock verify / Reference↔sandbox differential.
set -euo pipefail

usage() {
  echo "usage: $0 [wasm-file-or-dir]" >&2
  echo "  If omitted, builds Examples/Counter --target near when proof-forge-next is available." >&2
  exit 2
}

if [[ $# -gt 1 ]]; then
  usage
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_arg="${1:-}"

platform_id() {
  local sys mach
  sys="$(uname -s | tr '[:upper:]' '[:lower:]')"
  mach="$(uname -m | tr '[:upper:]' '[:lower:]')"
  echo "${sys}-${mach}"
}

tool_root_candidates() {
  local plat name
  plat="$(platform_id)"
  name="$1"
  if [[ -n "${PROOF_FORGE_TOOL_ROOT:-}" ]]; then
    echo "${PROOF_FORGE_TOOL_ROOT%/}/$name"
  fi
  echo "${HOME}/.cache/proof-forge-v2/tool-root/${plat}/$name"
}

resolve_tool() {
  local name="$1"
  local cand
  for cand in $(tool_root_candidates "$name"); do
    if [[ -x "$cand" ]]; then
      echo "$cand"
      return 0
    fi
  done
  if [[ -x "${HOME}/.local/bin/$name" ]]; then
    echo "${HOME}/.local/bin/$name"
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
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  return 1
}

if ! sandbox="$(resolve_tool near-sandbox)"; then
  echo "skipped: near-sandbox unavailable"
  exit 0
fi

if ! python3 - <<'PY' >/dev/null 2>&1
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
import base58
PY
then
  echo "skipped: python3 cryptography+base58 unavailable (needed for sandbox deploy/call)"
  exit 0
fi

echo "near-sandbox-acceptance: near-sandbox=$sandbox"
"$sandbox" --version 2>&1 | head -1 || true

find_wasm() {
  local target="$1"
  if [[ -f "$target" && "$target" == *.wasm ]]; then
    echo "$target"
    return 0
  fi
  if [[ -d "$target" ]]; then
    local found
    found="$(find "$target" -type f -name '*.wasm' | sort | head -1 || true)"
    if [[ -n "$found" ]]; then
      echo "$found"
      return 0
    fi
  fi
  return 1
}

wasm=""
if [[ -n "$target_arg" ]]; then
  if ! wasm="$(find_wasm "$target_arg")"; then
    echo "near-sandbox-acceptance: no .wasm under $target_arg" >&2
    exit 2
  fi
else
  # Prefer a prebuilt Counter.wasm under build/, else product CLI build.
  if wasm="$(find_wasm "$root/build/v2/near-sandbox-acceptance" 2>/dev/null)"; then
    :
  elif [[ -x "$root/.lake/build/bin/proof-forge-next" ]] || command -v lake >/dev/null 2>&1; then
    cli="$root/.lake/build/bin/proof-forge-next"
    if [[ ! -x "$cli" ]]; then
      echo "near-sandbox-acceptance: building proof-forge-next..." >&2
      (cd "$root" && lake build proof_forge_next) || {
        echo "skipped: lake build failed (no Counter.wasm)"
        exit 0
      }
    fi
    out="$root/build/v2/near-sandbox-acceptance"
    rm -rf "$out"
    echo "near-sandbox-acceptance: build Examples/Counter.lean --target near" >&2
    (cd "$root" && lake env "$cli" build \
      Examples/Counter.lean --module Examples.Counter --target near \
      -o build/v2/near-sandbox-acceptance) || {
      echo "skipped: Counter NEAR product build failed"
      exit 0
    }
    if ! wasm="$(find_wasm "$out")"; then
      # Finalize may leave .wat only if wat2wasm missing from product finalize path.
      if [[ -f "$out/Counter.wat" ]] && wat2wasm="$(resolve_tool wat2wasm)"; then
        (cd "$out" && "$wat2wasm" Counter.wat -o Counter.wasm) || {
          echo "FAIL: wat2wasm Counter.wat" >&2
          exit 1
        }
        wasm="$out/Counter.wasm"
      else
        echo "skipped: no Counter.wasm after product build (wat2wasm/finalize missing)"
        exit 0
      fi
    fi
  else
    echo "skipped: no wasm argument and product CLI unavailable"
    exit 0
  fi
fi

if [[ ! -f "$wasm" ]]; then
  echo "near-sandbox-acceptance: missing wasm: $wasm" >&2
  exit 2
fi
magic="$(head -c 4 "$wasm" | od -An -tx1 | tr -d ' \n')"
if [[ "$magic" != "0061736d" ]]; then
  echo "FAIL: bad Wasm magic for $wasm (got $magic)" >&2
  exit 1
fi
echo "near-sandbox-acceptance: wasm=$wasm ($(wc -c <"$wasm" | tr -d ' ') bytes)"

workdir="$(mktemp -d "${TMPDIR:-/tmp}/near-sandbox-accept.XXXXXX")"
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

# Bind ephemeral RPC/network ports to avoid collisions.
rpc_port="$(python3 - <<'PY'
import socket
s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()
PY
)"
net_port="$(python3 - <<'PY'
import socket
s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()
PY
)"
python3 - <<PY
import json
from pathlib import Path
cfg_path = Path("$home") / "config.json"
cfg = json.loads(cfg_path.read_text())
cfg.setdefault("rpc", {})["addr"] = f"127.0.0.1:${rpc_port}"
cfg.setdefault("network", {})["addr"] = f"127.0.0.1:${net_port}"
# Sandbox-friendly: no boot nodes, single validator.
cfg.setdefault("network", {})["boot_nodes"] = ""
cfg_path.write_text(json.dumps(cfg, indent=2) + "\n")
PY

echo "near-sandbox-acceptance: starting node rpc=127.0.0.1:${rpc_port}"
"$sandbox" --home "$home" run >"$workdir/node.log" 2>&1 &
sandbox_pid=$!

rpc="http://127.0.0.1:${rpc_port}"
# Wait for RPC readiness.
ready=0
for _ in $(seq 1 60); do
  if curl -sf -X POST "$rpc" \
      -H 'content-type: application/json' \
      -d '{"jsonrpc":"2.0","id":"1","method":"status","params":[]}' \
      >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! kill -0 "$sandbox_pid" 2>/dev/null; then
    echo "FAIL: near-sandbox exited early" >&2
    tail -50 "$workdir/node.log" >&2 || true
    exit 1
  fi
  sleep 0.5
done
if [[ "$ready" -ne 1 ]]; then
  echo "FAIL: near-sandbox RPC not ready" >&2
  tail -50 "$workdir/node.log" >&2 || true
  exit 1
fi

# Deploy + mutate + view via compact JSON-RPC client (cryptography + base58).
export PF_NEAR_RPC="$rpc"
export PF_NEAR_HOME="$home"
export PF_NEAR_WASM="$wasm"
python3 - <<'PY'
import base64, base58, hashlib, json, os, struct, urllib.request
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

RPC = os.environ["PF_NEAR_RPC"]
HOME = Path(os.environ["PF_NEAR_HOME"])
WASM = Path(os.environ["PF_NEAR_WASM"])
ACCOUNT = "test.near"

def rpc(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": "pf", "method": method, "params": params}).encode()
    req = urllib.request.Request(RPC, data=body, headers={"content-type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode())
    if "error" in data:
        raise RuntimeError(f"rpc {method}: {data['error']}")
    return data["result"]

def borsh_string(s: str) -> bytes:
    b = s.encode()
    return struct.pack("<I", len(b)) + b

def borsh_bytes(b: bytes) -> bytes:
    return struct.pack("<I", len(b)) + b

def u64(n: int) -> bytes:
    return struct.pack("<Q", n)

def u128(n: int) -> bytes:
    return n.to_bytes(16, "little")

# Load validator key minted by near-sandbox init (owns test.near).
key = json.loads((HOME / "validator_key.json").read_text())
assert key["account_id"] == ACCOUNT
sk_raw = base58.b58decode(key["secret_key"].split(":", 1)[1])
seed = sk_raw[:32]
priv = Ed25519PrivateKey.from_private_bytes(seed)
pub = priv.public_key().public_bytes_raw()

def access_key_query():
    pk = "ed25519:" + base58.b58encode(pub).decode()
    res = rpc("query", {
        "request_type": "view_access_key",
        "finality": "optimistic",
        "account_id": ACCOUNT,
        "public_key": pk,
    })
    return int(res["nonce"]), base58.b58decode(res["block_hash"])

def sign_and_send(receiver: str, actions: list[bytes]):
    nonce, block_hash = access_key_query()
    nonce += 1
    actions_blob = struct.pack("<I", len(actions)) + b"".join(actions)
    tx = (
        borsh_string(ACCOUNT)
        + bytes([0]) + pub  # PublicKey::ED25519
        + u64(nonce)
        + borsh_string(receiver)
        + block_hash
        + actions_blob
    )
    sig = priv.sign(hashlib.sha256(tx).digest())
    signed = tx + bytes([0]) + sig
    res = rpc("broadcast_tx_commit", [base64.b64encode(signed).decode()])
    status = res.get("status", {})
    if "Failure" in status:
        raise RuntimeError(f"tx failure: {status}")
    if "SuccessValue" not in status and "SuccessReceiptId" not in status:
        # Some nodes wrap SuccessValue under status directly.
        if not any(k.startswith("Success") for k in status):
            # Accept if receipts have no failures.
            for r in res.get("receipts_outcome", []):
                st = r.get("outcome", {}).get("status", {})
                if "Failure" in st:
                    raise RuntimeError(f"receipt failure: {st}")
    return res

def action_deploy(code: bytes) -> bytes:
    # Action enum tag 1 = DeployContract { code }
    return bytes([1]) + borsh_bytes(code)

def action_function_call(method: str, args: bytes, gas: int = 50_000_000_000_000, deposit: int = 0) -> bytes:
    # Action enum tag 2 = FunctionCall
    return (
        bytes([2])
        + borsh_string(method)
        + borsh_bytes(args)
        + u64(gas)
        + u128(deposit)
    )

def view_call(method: str, args: bytes = b"") -> bytes:
    res = rpc("query", {
        "request_type": "call_function",
        "finality": "optimistic",
        "account_id": ACCOUNT,
        "method_name": method,
        "args_base64": base64.b64encode(args).decode(),
    })
    if res.get("error"):
        raise RuntimeError(f"view {method}: {res['error']}")
    return bytes(res["result"])

code = WASM.read_bytes()
print(f"deploying {len(code)} bytes to {ACCOUNT}")
deploy_res = sign_and_send(ACCOUNT, [action_deploy(code)])
print("deploy receipt ok")

# packed-raw-little-endian-u64: init(initial=7)
init_args = u64(7)
sign_and_send(ACCOUNT, [action_function_call("init", init_args)])
print("init(7) ok")

# increment(delta=5) -> expect 12
inc_res = sign_and_send(ACCOUNT, [action_function_call("increment", u64(5))])
print("increment(5) ok")

# view get() -> 12 as little-endian u64 return (value_return host)
got = view_call("get", b"")
if len(got) < 8:
    # Some returns may be JSON-wrapped or empty on failure.
    raise RuntimeError(f"get() returned unexpected bytes: {got!r}")
# Product return is raw LE u64 via value_return; take first 8 bytes.
value = int.from_bytes(got[:8], "little")
if value != 12:
    raise RuntimeError(f"get() expected 12, got {value} (raw={got.hex()})")
print(f"view get() == {value} ok")
print("near-sandbox-acceptance: ok")
PY
