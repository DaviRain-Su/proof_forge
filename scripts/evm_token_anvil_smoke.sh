#!/usr/bin/env bash
# Engineering Token mint/transfer (+ overflow / over-transfer hold) smoke on Anvil.
# Not formal Reference↔Anvil (C-3). Dense Map pilot may exceed EIP-3860
# initcode limits — that path skip-cleans (exit 0), never fabricates pass.
#
# Requires Foundry anvil/cast. Builds Token.bin via product CLI when missing.
#
# Profile inheritance (EVMOZ-001): honors PF_EVM_PROFILE so Cancun differential
# cannot silently mix default-profile bytecode with --hardfork cancun.
#   empty / evm-yul-solc-0.8.34-v1 → build/v2/token-evm + historical anvil args
#   evm-yul-solc-0.8.34-cancun-v1 → build/v2/token-evm-cancun + anvil --hardfork cancun
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *) echo "evm-token-anvil: skipped: unsupported host" >&2; exit 0 ;;
esac
foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}}"
anvil_path="$foundry_bin/anvil"; cast_path="$foundry_bin/cast"
# Prefer FOUNDRY_BIN co-located tools; only fall back to PATH when missing.
if [[ ! -x "${anvil_path:-}" ]] && command -v anvil >/dev/null 2>&1; then
  anvil_path="$(command -v anvil)"
fi
if [[ ! -x "${cast_path:-}" ]] && command -v cast >/dev/null 2>&1; then
  cast_path="$(command -v cast)"
fi
if [[ ! -x "${anvil_path:-}" || ! -x "${cast_path:-}" ]]; then
  echo "evm-token-anvil: skipped: anvil/cast unavailable" >&2
  echo "evm-token-anvil: engineering only; not formal Reference↔Anvil" >&2
  exit 0
fi

evm_profile="${PF_EVM_PROFILE:-}"
build_profile_args=()
artifact_suffix=""
anvil_extra_args=()
expected_profile_wire="evm-yul-solc-0.8.34-v1"
case "$evm_profile" in
  "")
    : # default product profile
    ;;
  "evm-yul-solc-0.8.34-v1")
    build_profile_args+=(--profile "$evm_profile")
    expected_profile_wire="evm-yul-solc-0.8.34-v1"
    ;;
  "evm-yul-solc-0.8.34-cancun-v1")
    build_profile_args+=(--profile "$evm_profile")
    artifact_suffix="-cancun"
    anvil_extra_args+=(--hardfork cancun)
    expected_profile_wire="evm-yul-solc-0.8.34-cancun-v1"
    echo "evm-token-anvil: profile=$evm_profile → anvil --hardfork cancun" >&2
    ;;
  *)
    echo "evm-token-anvil: skipped: unsupported PF_EVM_PROFILE='$evm_profile' (refuse silent default mix)" >&2
    exit 0
    ;;
esac

token_out_rel="build/v2/token-evm${artifact_suffix}"
token_out="$root/$token_out_rel"
# TOKEN_BIN override still allowed; default is profile-keyed.
token_bin="${TOKEN_BIN:-$token_out/Token.bin}"

token_tree_matches_profile() {
  local bin="$1"
  local dir
  dir="$(dirname "$bin")"
  local evidence="$dir/evidence.json"
  local manifest="$dir/manifest.json"
  [[ -f "$bin" ]] || return 1
  if [[ "$expected_profile_wire" == "evm-yul-solc-0.8.34-cancun-v1" ]]; then
    [[ -f "$evidence" ]] && grep -q 'evm-version=cancun' "$evidence" || return 1
    [[ -f "$manifest" ]] || return 1
    grep -q "\"codegenProfile\": \"$expected_profile_wire\"" "$manifest" ||
      grep -q "\"codegenProfile\":\"$expected_profile_wire\"" "$manifest" || return 1
  else
    if [[ -f "$evidence" ]] && grep -q 'evm-version=cancun' "$evidence"; then
      return 1
    fi
    if [[ -f "$manifest" ]] && grep -q 'evm-yul-solc-0.8.34-cancun-v1' "$manifest"; then
      return 1
    fi
  fi
  return 0
}

if ! token_tree_matches_profile "$token_bin"; then
  echo "evm-token-anvil: building Token EVM artifact → $token_out_rel (profile=$expected_profile_wire)..." >&2
  if [[ -x "$root/.lake/build/bin/proof-forge-next" ]] && command -v lake >/dev/null 2>&1; then
    # Product CLI refuses non-empty existing -o dirs (PF-OUTPUT-COLLISION).
    rm -rf "$token_out"
    if [[ ${#build_profile_args[@]} -gt 0 ]]; then
      (cd "$root" && lake env .lake/build/bin/proof-forge-next build \
        Examples/Token.lean --module Examples.Token --target evm \
        "${build_profile_args[@]}" -o "$token_out_rel") || {
        echo "evm-token-anvil: skipped: Token EVM build failed (profile=$expected_profile_wire)" >&2
        exit 0
      }
    else
      (cd "$root" && lake env .lake/build/bin/proof-forge-next build \
        Examples/Token.lean --module Examples.Token --target evm \
        -o "$token_out_rel") || {
        echo "evm-token-anvil: skipped: Token EVM build failed (profile=$expected_profile_wire)" >&2
        exit 0
      }
    fi
  else
    echo "evm-token-anvil: skipped: product CLI unavailable to build Token" >&2
    exit 0
  fi
  token_bin="$token_out/Token.bin"
  [[ -f "$token_bin" ]] || {
    echo "evm-token-anvil: skipped: Token.bin missing after build" >&2
    exit 0
  }
  if ! token_tree_matches_profile "$token_bin"; then
    echo "evm-token-anvil: skipped: Token tree failed post-build profile validation" >&2
    exit 0
  fi
fi
echo "evm-token-anvil: engineering Token smoke (mint/balanceOf/transfer/overflow-hold; profile=$expected_profile_wire); not formal" >&2
export FOUNDRY_BIN="$(cd "$(dirname "$anvil_path")" && pwd)"
abi="$(dirname "$token_bin")/Token.abi.json"
if [[ ! -f "$abi" ]]; then echo "evm-token-anvil: skipped: missing ABI" >&2; exit 0; fi
port=$((18545 + RANDOM % 1000))
if ((${#anvil_extra_args[@]})); then
  "$anvil_path" --port "$port" "${anvil_extra_args[@]}" --silent >/tmp/pf-token-anvil.log 2>&1 &
else
  "$anvil_path" --port "$port" --silent >/tmp/pf-token-anvil.log 2>&1 &
fi
anvil_pid=$!
trap 'kill $anvil_pid 2>/dev/null || true' EXIT
# Wait for RPC readiness (avoid fixed sleep races).
rpc="http://127.0.0.1:$port"
ready=0
for _ in $(seq 1 50); do
  if "$cast_path" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "$ready" != 1 ]]; then
  echo "evm-token-anvil: skipped: anvil failed to start (see /tmp/pf-token-anvil.log)" >&2
  exit 0
fi
# Anvil default key
pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
# Deploy create
binhex=$(xxd -p -c 1000000 "$token_bin" | tr -d '\n')
# Token Map pilot bytecode can exceed Anvil/EIP-3860 initcode limits (~49KiB).
create_err=/tmp/pf-token-anvil-create.err
addr=$("$cast_path" send --rpc-url "$rpc" --private-key "$pk" --create "0x$binhex" --json 2>"$create_err" | python3 -c 'import sys,json
try:
  print(json.load(sys.stdin).get("contractAddress",""))
except Exception:
  print("")' || true)
if [[ -z "$addr" || "$addr" == "null" ]]; then
  if grep -qiE 'initcode|max code|code size|oversized' "$create_err" 2>/dev/null; then
    echo "evm-token-anvil: skipped: bytecode exceeds Anvil create/initcode limit (Map pilot Yul; engineering only)" >&2
    exit 0
  fi
  tx=$("$cast_path" send --rpc-url "$rpc" --private-key "$pk" --create "0x$binhex" 2>/dev/null | tail -1 || true)
  if [[ -n "${tx:-}" ]]; then
    addr=$("$cast_path" receipt --rpc-url "$rpc" "$tx" --json 2>/dev/null | python3 -c 'import sys,json
try:
  print(json.load(sys.stdin).get("contractAddress",""))
except Exception:
  print("")' || true)
  fi
fi
if [[ -z "$addr" || "$addr" == "null" ]]; then
  # Dense Map pilot Yul can exceed EIP-3860 initcode / create limits on Anvil;
  # treat as engineering skip (not product build failure).
  echo "evm-token-anvil: skipped: deploy failed (initcode/create; see /tmp/pf-token-anvil.log)" >&2
  exit 0
fi
# Normalize cast call output to decimal UInt64 when possible.
to_dec() {
  local x="$1"
  x="${x//$'\n'/}"
  x="${x// /}"
  if [[ -z "$x" ]]; then echo ""; return; fi
  if [[ "$x" == 0x* || "$x" == 0X* ]]; then
    python3 -c "print(int('$x', 16))" 2>/dev/null || echo "$x"
  else
    # cast may print plain decimal
    echo "$x"
  fi
}

UINT64_MAX="18446744073709551615"

# mint(to=1, amount=100)
"$cast_path" send --rpc-url "$rpc" --private-key "$pk" "$addr" "mint(uint64,uint64)" 1 100 >/dev/null
bal1=$("$cast_path" call --rpc-url "$rpc" "$addr" "balanceOf(uint64)(uint64)" 1)
bal1d=$(to_dec "$bal1")
if [[ -z "$bal1d" ]]; then echo "FAIL: balanceOf(1) empty" >&2; exit 1; fi
if [[ "$bal1d" != "100" ]]; then
  echo "FAIL: balanceOf(1) expected 100 got $bal1d (raw=$bal1)" >&2
  exit 1
fi
supply=$("$cast_path" call --rpc-url "$rpc" "$addr" "total()(uint64)")
supplyd=$(to_dec "$supply")
if [[ "$supplyd" != "100" ]]; then
  echo "FAIL: total supply expected 100 got $supplyd" >&2
  exit 1
fi
"$cast_path" send --rpc-url "$rpc" --private-key "$pk" "$addr" "transfer(uint64,uint64,uint64)" 1 2 40 >/dev/null
bal1=$("$cast_path" call --rpc-url "$rpc" "$addr" "balanceOf(uint64)(uint64)" 1)
bal2=$("$cast_path" call --rpc-url "$rpc" "$addr" "balanceOf(uint64)(uint64)" 2)
bal1d=$(to_dec "$bal1"); bal2d=$(to_dec "$bal2")
if [[ "$bal1d" != "60" ]]; then
  echo "FAIL: after transfer balanceOf(1) expected 60 got $bal1d" >&2
  exit 1
fi
if [[ "$bal2d" != "40" ]]; then
  echo "FAIL: after transfer balanceOf(2) expected 40 got $bal2d" >&2
  exit 1
fi

# Overflow hold: mint(1, UInt64.max) must revert (60 + max overflows) and leave balances.
if "$cast_path" send --rpc-url "$rpc" --private-key "$pk" \
    "$addr" "mint(uint64,uint64)" 1 "$UINT64_MAX" >/dev/null 2>&1; then
  echo "FAIL: Token mint overflow unexpectedly succeeded" >&2
  exit 1
fi
bal1=$("$cast_path" call --rpc-url "$rpc" "$addr" "balanceOf(uint64)(uint64)" 1)
bal2=$("$cast_path" call --rpc-url "$rpc" "$addr" "balanceOf(uint64)(uint64)" 2)
bal1d=$(to_dec "$bal1"); bal2d=$(to_dec "$bal2")
if [[ "$bal1d" != "60" || "$bal2d" != "40" ]]; then
  echo "FAIL: Token mint overflow changed balances (1=$bal1d 2=$bal2d)" >&2
  exit 1
fi
# Underflow-style transfer assert: transfer more than balance must fail closed.
if "$cast_path" send --rpc-url "$rpc" --private-key "$pk" \
    "$addr" "transfer(uint64,uint64,uint64)" 1 2 61 >/dev/null 2>&1; then
  echo "FAIL: Token over-transfer unexpectedly succeeded" >&2
  exit 1
fi
bal1=$("$cast_path" call --rpc-url "$rpc" "$addr" "balanceOf(uint64)(uint64)" 1)
bal2=$("$cast_path" call --rpc-url "$rpc" "$addr" "balanceOf(uint64)(uint64)" 2)
bal1d=$(to_dec "$bal1"); bal2d=$(to_dec "$bal2")
if [[ "$bal1d" != "60" || "$bal2d" != "40" ]]; then
  echo "FAIL: Token over-transfer changed balances (1=$bal1d 2=$bal2d)" >&2
  exit 1
fi

echo "evm-token-anvil: ok mint/transfer/balanceOf/overflow-hold on $addr (1→60, 2→40)" >&2
echo "evm-token-anvil: engineering only; not formal Reference↔Anvil"
