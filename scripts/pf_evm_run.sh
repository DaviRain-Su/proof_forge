#!/usr/bin/env bash
# One-shot local Anvil call for `pf run -t evm -- <method> [u64…]`.
#
# Inputs:
#   PF_EVM_ARTIFACT_DIR  — OutputSet with *.bin + *.abi.json (required)
#   PF_EVM_METHOD        — method name, or init|constructor|deploy for deploy-only
#   PF_EVM_ARGS          — space-separated u64 decimals (optional)
#   PF_EVM_INIT_ARGS     — constructor u64 args when method is not init
#                          (default: 0 for single-uint ctor; empty for 0-arg)
#   PROOF_FORGE_TOOL_ROOT / FOUNDRY_BIN — locked anvil+cast
#   PF_EVM_PRIVATE_KEY   — Anvil account key (default account #0)
#   PF_EVM_CHAIN_ID      — default 31338
#
# Honesty: engineering local Anvil only — not formal, not mainnet.
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${_script_dir}/.." && pwd)"

die() { echo "pf-evm-run: FAIL: $*" >&2; exit 1; }
skip_clean() {
  echo "pf-evm-run: skipped: $*" >&2
  exit 0
}

artifact_dir="${PF_EVM_ARTIFACT_DIR:-}"
method="${PF_EVM_METHOD:-}"
args_str="${PF_EVM_ARGS:-}"
init_args_str="${PF_EVM_INIT_ARGS:-}"

[[ -n "$artifact_dir" && -d "$artifact_dir" ]] || die "PF_EVM_ARTIFACT_DIR missing (run pf build -t evm)"
artifact_dir="$(cd "$artifact_dir" && pwd)"
[[ -f "$artifact_dir/manifest.json" ]] || die "missing manifest.json under $artifact_dir"
[[ -n "$method" ]] || die "PF_EVM_METHOD required"

case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *) skip_clean "unsupported host $(uname -s)" ;;
esac
foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}}"
anvil="$foundry_bin/anvil"
cast="$foundry_bin/cast"
if [[ ! -x "$anvil" || ! -x "$cast" ]]; then
  skip_clean "missing locked anvil/cast under $foundry_bin"
fi
command -v python3 >/dev/null 2>&1 || skip_clean "python3 not on PATH"

if [[ -f "$artifact_dir/StateCell.bin" ]]; then
  bin_path="$artifact_dir/StateCell.bin"
elif [[ -f "$artifact_dir/Counter.bin" ]]; then
  bin_path="$artifact_dir/Counter.bin"
else
  bin_path="$(find "$artifact_dir" -maxdepth 2 -type f -name '*.bin' | sort | head -n 1 || true)"
fi
[[ -n "$bin_path" && -f "$bin_path" ]] || die "no *.bin under $artifact_dir"
program="$(basename "$bin_path" .bin)"
abi_path="$artifact_dir/${program}.abi.json"
if [[ ! -f "$abi_path" ]]; then
  abi_path="$(find "$artifact_dir" -maxdepth 2 -type f -name '*.abi.json' | sort | head -n 1 || true)"
fi
[[ -n "$abi_path" && -f "$abi_path" ]] || die "no *.abi.json under $artifact_dir"

bytecode="$(tr -d '\n\r ' < "$bin_path")"
[[ -n "$bytecode" ]] || die "empty bytecode"

# Resolve ABI into key=value lines. Values may contain '()' so we cannot
# `source` them — parse KEY=VALUE with a single split on first '='.
abi_info="$(mktemp "${TMPDIR:-/tmp}/pf-evm-abi.XXXXXX")"
PF_EVM_ABI_PATH="$abi_path" PF_EVM_ABI_METHOD="$method" python3 - <<'PY' >"$abi_info"
import json, os, sys
abi = json.loads(open(os.environ["PF_EVM_ABI_PATH"], encoding="utf-8").read())
method = os.environ["PF_EVM_ABI_METHOD"]
ctor = next((i for i in abi if i.get("type") == "constructor"), None)
ctor_types = [x.get("type", "uint64") for x in (ctor or {}).get("inputs") or []]
print("CTOR_TYPES=" + ",".join(ctor_types))
print("HAS_GET=" + ("1" if any(i.get("type")=="function" and i.get("name")=="get" for i in abi) else "0"))
if method in ("init", "constructor", "deploy"):
    print("KIND=deploy")
    raise SystemExit(0)
found = next((i for i in abi if i.get("type")=="function" and i.get("name")==method), None)
if found is None:
    print(f"unknown method {method!r}", file=sys.stderr)
    raise SystemExit(2)
ins = [x.get("type", "uint64") for x in found.get("inputs") or []]
outs = [x.get("type", "uint64") for x in found.get("outputs") or []]
mut = found.get("stateMutability") or "nonpayable"
print("KIND=call")
print("MUT=" + mut)
print("IN_TYPES=" + ",".join(ins))
print("OUT_TYPES=" + ",".join(outs))
if outs:
    print("CALL_SIG=" + f"{method}({','.join(ins)})({','.join(outs)})")
else:
    print("CALL_SIG=" + f"{method}({','.join(ins)})")
print("SEND_SIG=" + f"{method}({','.join(ins)})")
PY
KIND=""; MUT=""; CTOR_TYPES=""; HAS_GET="0"
CALL_SIG=""; SEND_SIG=""; IN_TYPES=""; OUT_TYPES=""
while IFS= read -r line || [[ -n "$line" ]]; do
  key="${line%%=*}"
  val="${line#*=}"
  case "$key" in
    KIND) KIND="$val" ;;
    MUT) MUT="$val" ;;
    CTOR_TYPES) CTOR_TYPES="$val" ;;
    HAS_GET) HAS_GET="$val" ;;
    CALL_SIG) CALL_SIG="$val" ;;
    SEND_SIG) SEND_SIG="$val" ;;
    IN_TYPES) IN_TYPES="$val" ;;
    OUT_TYPES) OUT_TYPES="$val" ;;
  esac
done < "$abi_info"
rm -f "$abi_info"
[[ -n "$KIND" ]] || die "ABI parse produced no KIND"

# Ephemeral anvil
port="${PF_EVM_PORT:-$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')}"
chain_id="${PF_EVM_CHAIN_ID:-31338}"
rpc="http://127.0.0.1:$port"
private_key="${PF_EVM_PRIVATE_KEY:-ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/pf-evm-run.XXXXXX")"
log="$workdir/anvil.log"
anvil_pid=""
cleanup() {
  if [[ -n "${anvil_pid:-}" ]] && kill -0 "$anvil_pid" 2>/dev/null; then
    kill "$anvil_pid" 2>/dev/null || true
    wait "$anvil_pid" 2>/dev/null || true
  fi
  rm -rf "$workdir"
}
trap cleanup EXIT

"$anvil" --host 127.0.0.1 --port "$port" --chain-id "$chain_id" --silent >"$log" 2>&1 &
anvil_pid=$!
ready=0
for _ in $(seq 1 60); do
  if ! kill -0 "$anvil_pid" 2>/dev/null; then
    die "anvil exited early; log: $(tail -20 "$log")"
  fi
  if "$cast" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
[[ "$ready" -eq 1 ]] || die "anvil failed to start (see $log)"

to_dec() {
  local x="$1"
  if [[ "$x" =~ ^([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$x" =~ ^0x[0-9a-fA-F]+$ ]]; then
    python3 -c "print(int('$x', 16))"
  else
    echo "$x"
  fi
}

# shellcheck disable=SC2206
method_args=()
[[ -n "$args_str" ]] && method_args=($args_str)
# shellcheck disable=SC2206
init_vals=()
[[ -n "$init_args_str" ]] && init_vals=($init_args_str)

ctor_suffix() {
  # args: values for constructor (may be empty → default single-uint to 0)
  if [[ -z "${CTOR_TYPES:-}" ]]; then
    echo ""
    return 0
  fi
  local -a types=()
  IFS=',' read -r -a types <<< "$CTOR_TYPES"
  local -a vals=()
  if [[ "$#" -gt 0 ]]; then
    vals=("$@")
  elif [[ ${#types[@]} -eq 1 ]]; then
    vals=(0)
  elif [[ ${#types[@]} -eq 0 ]]; then
    echo ""
    return 0
  else
    die "constructor needs ${#types[@]} args; pass them after -- init, or set PF_EVM_INIT_ARGS"
  fi
  [[ ${#vals[@]} -eq ${#types[@]} ]] || die "constructor arity: want ${#types[@]} got ${#vals[@]}"
  local joined
  joined="$(IFS=,; echo "${types[*]}")"
  local sig="constructor(${joined})"
  local enc
  enc="$("$cast" abi-encode "$sig" "${vals[@]}")" \
    || die "abi-encode $sig failed for values: ${vals[*]}"
  echo "${enc#0x}"
}

deploy() {
  local suffix
  if [[ "$#" -gt 0 ]]; then
    suffix="$(ctor_suffix "$@")"
  else
    suffix="$(ctor_suffix)"
  fi
  local receipt addr
  receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
    --create "0x${bytecode}${suffix}" 2>"$workdir/cast-send.err")" \
    || die "cast send --create failed: $(cat "$workdir/cast-send.err" 2>/dev/null || true)"
  addr="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])' <<<"$receipt")"
  [[ -n "$addr" && "$addr" != "null" ]] || die "deploy failed: $receipt"
  echo "$addr"
}

if [[ "${KIND:-}" == "deploy" ]]; then
  if [[ ${#method_args[@]} -gt 0 ]]; then
    addr="$(deploy "${method_args[@]}")"
  else
    addr="$(deploy)"
  fi
  echo "$addr"
  echo "pf-evm-run: ok mode=deploy program=$program addr=$addr" >&2
  exit 0
fi

# Deploy with init args (default 0 for single-uint pad), then call method.
if [[ ${#init_vals[@]} -gt 0 ]]; then
  addr="$(deploy "${init_vals[@]}")"
else
  addr="$(deploy)"
fi

if [[ "${MUT:-}" == "view" || "${MUT:-}" == "pure" ]]; then
  if [[ ${#method_args[@]} -gt 0 ]]; then
    out="$("$cast" call --rpc-url "$rpc" "$addr" "$CALL_SIG" "${method_args[@]}")"
  else
    out="$("$cast" call --rpc-url "$rpc" "$addr" "$CALL_SIG")"
  fi
  to_dec "$out"
  echo "pf-evm-run: ok mode=call program=$program method=$method addr=$addr" >&2
  exit 0
fi

# Mutating: eth_call first for return value (pre-state), then send to commit.
ret=""
if [[ -n "${OUT_TYPES:-}" ]]; then
  if [[ ${#method_args[@]} -gt 0 ]]; then
    ret="$("$cast" call --rpc-url "$rpc" "$addr" "$CALL_SIG" "${method_args[@]}" 2>/dev/null || true)"
  else
    ret="$("$cast" call --rpc-url "$rpc" "$addr" "$CALL_SIG" 2>/dev/null || true)"
  fi
fi

if [[ ${#method_args[@]} -gt 0 ]]; then
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" "$SEND_SIG" "${method_args[@]}" >/dev/null
else
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" "$SEND_SIG" >/dev/null
fi

if [[ -n "$ret" ]]; then
  to_dec "$ret"
elif [[ "${HAS_GET:-0}" == "1" ]]; then
  out="$("$cast" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
  to_dec "$out"
else
  echo "ok"
fi
echo "pf-evm-run: ok mode=send program=$program method=$method addr=$addr" >&2
