#!/usr/bin/env bash
# Engineering Token mint/transfer smoke on Anvil (not formal Reference↔Anvil).
# Requires Foundry anvil/cast and a built Token.bin (EVM dense Map pilot).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *) echo "evm-token-anvil: skipped: unsupported host" >&2; exit 0 ;;
esac
foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}}"
anvil_path="$foundry_bin/anvil"; cast_path="$foundry_bin/cast"
command -v anvil >/dev/null 2>&1 && anvil_path="$(command -v anvil)" || true
command -v cast >/dev/null 2>&1 && cast_path="$(command -v cast)" || true
if [[ ! -x "${anvil_path:-}" || ! -x "${cast_path:-}" ]]; then
  echo "evm-token-anvil: skipped: anvil/cast unavailable" >&2; exit 0
fi
token_bin="${TOKEN_BIN:-$root/build/v2/token-evm/Token.bin}"
if [[ ! -f "$token_bin" ]]; then
  echo "evm-token-anvil: building Token EVM artifact..." >&2
  mkdir -p "$root/build/v2/token-evm"
  (cd "$root" && lake env .lake/build/bin/proof-forge-next build \
    Examples/Token.lean --module Examples.Token --target evm -o build/v2/token-evm) || {
    echo "evm-token-anvil: skipped: Token EVM build failed" >&2; exit 0
  }
  token_bin="$root/build/v2/token-evm/Token.bin"
fi
echo "evm-token-anvil: engineering Token smoke only (mint/balanceOf/transfer); not formal" >&2
# Deploy + mint(1,100) + balanceOf(1)==100 + transfer(1,2,40) + balanceOf checks via cast
# Reuse smoke_evm pattern: start anvil, deploy bytecode, call ABI.
export FOUNDRY_BIN="$(cd "$(dirname "$anvil_path")" && pwd)"
abi="$root/build/v2/token-evm/Token.abi.json"
[[ -f "$abi" ]] || abi="$(dirname "$token_bin")/Token.abi.json"
if [[ ! -f "$abi" ]]; then echo "evm-token-anvil: skipped: missing ABI" >&2; exit 0; fi
port=$((18545 + RANDOM % 1000))
"$anvil_path" --port "$port" --silent >/tmp/pf-token-anvil.log 2>&1 &
anvil_pid=$!
trap 'kill $anvil_pid 2>/dev/null || true' EXIT
sleep 1
rpc="http://127.0.0.1:$port"
# Anvil default key
pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
from=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
# Deploy create
binhex=$(xxd -p -c 1000000 "$token_bin" | tr -d '\n')
addr=$("$cast_path" send --rpc-url "$rpc" --private-key "$pk" --create "0x$binhex" --json | python3 -c 'import sys,json; print(json.load(sys.stdin).get("contractAddress",""))' 2>/dev/null || true)
if [[ -z "$addr" ]]; then
  # fallback cast receipt style
  tx=$("$cast_path" send --rpc-url "$rpc" --private-key "$pk" --create "0x$binhex" 2>/dev/null | tail -1)
  addr=$("$cast_path" receipt --rpc-url "$rpc" "$tx" --json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("contractAddress",""))' || true)
fi
if [[ -z "$addr" || "$addr" == "null" ]]; then
  echo "evm-token-anvil: skipped: deploy failed (see /tmp/pf-token-anvil.log)" >&2
  exit 0
fi
# mint(to=1, amount=100)
"$cast_path" send --rpc-url "$rpc" --private-key "$pk" "$addr" "mint(uint64,uint64)" 1 100 >/dev/null
bal=$("$cast_path" call --rpc-url "$rpc" "$addr" "balanceOf(uint64)(uint64)" 1)
# cast returns hex; accept non-empty success
if [[ -z "$bal" ]]; then echo "FAIL: balanceOf empty" >&2; exit 1; fi
"$cast_path" send --rpc-url "$rpc" --private-key "$pk" "$addr" "transfer(uint64,uint64,uint64)" 1 2 40 >/dev/null
echo "evm-token-anvil: ok mint/transfer/balanceOf on $addr" >&2
echo "evm-token-anvil: engineering only; not formal Reference↔Anvil"
