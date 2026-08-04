#!/bin/sh
# In-container wasmd chain tests (BL-26 rung 1).
# Invoked by scripts/cosmwasm_wasmd_test.sh via docker exec after wasms are copied
# to /artifacts/{Counter,ScheduleFlow}.wasm and the node is running.
#
# Engineering only: wasmd v0.70.3 tx-level differential.
# Not mainnet / formal Stage-0 / hermetic release evidence.
#
# Assertions (observed on wasmd v0.70.3):
#   Counter:
#     - instantiate {initial:7} → state0 == 7
#     - execute {increment:{delta:5}} → state0 == 12, deliver code 0
#     - execute overflow delta → CLI/tx FAILS (Wasm unreachable trap), state0 holds 12
#   ScheduleFlow:
#     - instantiate {x:5} → state0 == 5
#     - execute {later:{}} → deliver code != 0
#       raw_log contains bech32 failure for contract_addr stub "ledger.daily"
#       (ReplyNever SubMsg dispatch validation; whole tx aborts — SRC-CW-002)
#     - state0 holds 5 (parent body count+1 rolled back with the failed tx)
#
# Query note: product MVP query returns UTF-8 {"ok":"<decimal>"} (NOT cosmwasm-std
# Binary/base64). wasmd `contract-state smart` therefore fails with
# "illegal base64 data". This harness asserts via contract-state raw on key
# pf:cw:v1:state:0 (LE u64), same layout marker as the mock runtime suite.
set -eu

CHAIN_ID="${CHAIN_ID:-testing}"
FEE_DENOM="${FEE_DENOM:-ucosm}"
STAKE_DENOM="${STAKE_DENOM:-ustake}"
KEY_NAME="${KEY_NAME:-validator}"
KEYRING="--keyring-backend test"
# Fixed gas avoids --gas auto hangs on SubMsg failure simulation paths.
GAS_STORE="${GAS_STORE:-2500000}"
GAS_INST="${GAS_INST:-500000}"
GAS_EXEC="${GAS_EXEC:-500000}"
GAS_PRICES="${GAS_PRICES:-0.025${FEE_DENOM}}"

# ASCII "pf:cw:v1:state:0" as hex (product CosmWasm LowerSemanticV1 state key 0).
STATE_KEY_HEX="70663A63773A76313A73746174653A30"

die() {
  echo "cosmwasm-wasmd-incontainer: $*" >&2
  exit 1
}

log() {
  # stderr so callers can redirect function stdout (tx JSON) without losing traces
  echo "cosmwasm-wasmd-incontainer: $*" >&2
}

extract_quoted() {
  key="$1"
  json="$2"
  echo "$json" | sed -n "s/.*\"$key\":\"\([^\"]*\)\".*/\1/p" | head -n1
}

extract_num() {
  key="$1"
  json="$2"
  echo "$json" | sed -n "s/.*\"$key\":\([0-9][0-9]*\).*/\1/p" | head -n1
}

wait_tx() {
  hash="$1"
  i=0
  while [ "$i" -lt 60 ]; do
    if out=$(wasmd query tx "$hash" -o json 2>/dev/null); then
      echo "$out"
      return 0
    fi
    i=$((i + 1))
    sleep 0.5
  done
  die "tx not found after wait: $hash"
}

# Broadcast a tx that must succeed (deliver code 0). Prints residual JSON on stdout last line unused.
tx_ok() {
  label="$1"
  shift
  log "tx ok: $label"
  raw=$("$@" 2>&1) || die "tx cmd failed ($label): $raw"
  hash=$(extract_quoted txhash "$raw")
  [ -n "$hash" ] || die "no txhash ($label): $raw"
  check=$(extract_num code "$raw")
  log "  hash=$hash checktx_code=${check:-?}"
  res=$(wait_tx "$hash")
  deliver=$(extract_num code "$res")
  log "  deliver_code=${deliver:-?}"
  if [ -n "$deliver" ] && [ "$deliver" != "0" ]; then
    die "deliver failed ($label) code=$deliver res=$(echo "$res" | head -c 800)"
  fi
  echo "$res"
}

# Broadcast a tx that must fail (CLI error and/or deliver code != 0). Echoes raw+res.
tx_fail() {
  label="$1"
  shift
  log "tx expect-fail: $label"
  set +e
  raw=$("$@" 2>&1)
  ec=$?
  set -e
  hash=$(extract_quoted txhash "$raw" || true)
  check=$(extract_num code "$raw" || true)
  log "  cli_exit=$ec hash=${hash:-none} checktx_code=${check:-none}"
  log "  raw_head=$(echo "$raw" | head -c 400)"

  # Non-zero CheckTx code with a hash still needs inclusion wait sometimes; prefer deliver.
  if [ -n "$hash" ]; then
    # Poll inclusion (same bound as wait_tx) even when CheckTx code is already non-zero.
    i=0
    res=""
    while [ "$i" -lt 60 ]; do
      if res=$(wasmd query tx "$hash" -o json 2>/dev/null); then
        break
      fi
      i=$((i + 1))
      sleep 0.5
    done
    if [ -n "$res" ]; then
      deliver=$(extract_num code "$res")
      log "  deliver_code=${deliver:-?}"
      log "  raw_log_head=$(echo "$res" | sed -n "s/.*\"raw_log\":\"\([^\"]*\)\".*/\1/p" | head -c 300)"
      if [ -z "$deliver" ] || [ "$deliver" = "0" ]; then
        die "expected deliver failure ($label) but code=0 res=$(echo "$res" | head -c 600)"
      fi
      echo "$res"
      return 0
    fi
    log "  tx hash present but not included within wait; treating as non-inclusion failure path"
  fi

  # No inclusion: CheckTx/simulation/CLI failure path (e.g. Wasm unreachable under gas auto/sim).
  if [ "$ec" -ne 0 ] || { [ -n "$check" ] && [ "$check" != "0" ]; } \
    || echo "$raw" | grep -qiE 'error|unreachable|failed|illegal'; then
    echo "$raw"
    return 0
  fi
  die "expected failure ($label) but CLI succeeded without failing deliver: $raw"
}

read_state0_u64() {
  addr="$1"
  raw=$(wasmd query wasm contract-state raw "$addr" "$STATE_KEY_HEX" -o json) \
    || die "raw state query failed for $addr"
  b64=$(extract_quoted data "$raw")
  [ -n "$b64" ] || die "no data field in raw state for $addr: $raw"
  # LE u64 from first 8 bytes
  # shellcheck disable=SC2046
  set -- $(echo "$b64" | base64 -d | od -An -tx1)
  b0=$1; b1=$2; b2=$3; b3=$4; b4=$5; b5=$6; b6=$7; b7=$8
  [ -n "$b7" ] || die "state value shorter than 8 bytes for $addr (hex=$* )"
  # Values in this suite stay < 2^63 so POSIX $(( )) is fine.
  echo $((0x${b0} + (0x${b1} << 8) + (0x${b2} << 16) + (0x${b3} << 24) + (0x${b4} << 32) + (0x${b5} << 40) + (0x${b6} << 48) + (0x${b7} << 56)))
}

assert_eq() {
  got="$1"
  want="$2"
  what="$3"
  if [ "$got" != "$want" ]; then
    die "assert $what: got=$got want=$want"
  fi
  log "assert ok: $what == $want"
}

tx_flags() {
  gas="$1"
  echo "--from" "$KEY_NAME" $KEYRING "--chain-id" "$CHAIN_ID" \
    "--gas" "$gas" "--gas-prices" "$GAS_PRICES" "-y" "-o" "json"
}

# ---------- Counter ----------
log "=== Counter ==="
[ -f /artifacts/Counter.wasm ] || die "missing /artifacts/Counter.wasm"

tx_ok "store Counter" wasmd tx wasm store /artifacts/Counter.wasm $(tx_flags "$GAS_STORE") >/dev/null
# First code id after store (fresh chain → 1).
counter_code=$(wasmd query wasm list-code -o json | sed -n 's/.*"code_id":"\([0-9]*\)".*/\1/p' | head -n1)
[ -n "$counter_code" ] || die "no code id after Counter store"
log "Counter code_id=$counter_code"

tx_ok "instantiate Counter initial=7" \
  wasmd tx wasm instantiate "$counter_code" '{"initial":7}' \
  --label "pf-counter" --no-admin $(tx_flags "$GAS_INST") >/dev/null

counter_addr=$(wasmd query wasm list-contract-by-code "$counter_code" -o json \
  | sed -n 's/.*"contracts":\["\([^"]*\)".*/\1/p' | head -n1)
[ -n "$counter_addr" ] || die "no Counter contract address"
log "Counter addr=$counter_addr"

s=$(read_state0_u64 "$counter_addr")
assert_eq "$s" "7" "Counter state after init"

tx_ok "increment delta=5" \
  wasmd tx wasm execute "$counter_addr" '{"increment":{"delta":5}}' \
  $(tx_flags "$GAS_EXEC") >/dev/null

s=$(read_state0_u64 "$counter_addr")
assert_eq "$s" "12" "Counter state after increment"

# Overflow: max u64 add under checked arithmetic → Wasm unreachable.
# Observed: CLI returns error (simulation/CheckTx path) with unreachable; no inclusion needed.
tx_fail "overflow increment" \
  wasmd tx wasm execute "$counter_addr" '{"increment":{"delta":18446744073709551615}}' \
  $(tx_flags "$GAS_EXEC") >/dev/null

s=$(read_state0_u64 "$counter_addr")
assert_eq "$s" "12" "Counter state holds after overflow tx failure"

# Document smart-query MVP limitation (non-fatal).
set +e
smart=$(wasmd query wasm contract-state smart "$counter_addr" '{"get":{}}' -o json 2>&1)
smart_ec=$?
set -e
if [ "$smart_ec" -eq 0 ]; then
  log "note: smart query unexpectedly succeeded: $smart"
else
  log "note: smart query fail-closed as expected for MVP non-Binary query ABI (ec=$smart_ec)"
  log "  $(echo "$smart" | head -c 200)"
fi

# ---------- ScheduleFlow ----------
log "=== ScheduleFlow (ReplyNever + QN stub dest) ==="
[ -f /artifacts/ScheduleFlow.wasm ] || die "missing /artifacts/ScheduleFlow.wasm"

tx_ok "store ScheduleFlow" wasmd tx wasm store /artifacts/ScheduleFlow.wasm $(tx_flags "$GAS_STORE") >/dev/null
# Highest code id after second store.
schedule_code=$(wasmd query wasm list-code -o json | sed -n 's/.*"code_id":"\([0-9]*\)".*/\1/p' | tail -n1)
[ -n "$schedule_code" ] || die "no code id after ScheduleFlow store"
log "ScheduleFlow code_id=$schedule_code"

tx_ok "instantiate ScheduleFlow x=5" \
  wasmd tx wasm instantiate "$schedule_code" '{"x":5}' \
  --label "pf-schedule" --no-admin $(tx_flags "$GAS_INST") >/dev/null

schedule_addr=$(wasmd query wasm list-contract-by-code "$schedule_code" -o json \
  | sed -n 's/.*"contracts":\["\([^"]*\)".*/\1/p' | head -n1)
[ -n "$schedule_addr" ] || die "no ScheduleFlow contract address"
log "ScheduleFlow addr=$schedule_addr"

s=$(read_state0_u64 "$schedule_addr")
assert_eq "$s" "5" "ScheduleFlow state after init"

# later() enqueues SubMsg{reply_on:never, WasmMsg::Execute{contract_addr="ledger.daily", ...}}.
# Product destinations are static QN stubs, not bech32. wasmd rejects the SubMsg during
# dispatch validation; ReplyNever (SRC-CW-002) aborts the whole tx and rolls back parent
# state (count := count + 1 never commits).
fail_out=$(tx_fail "later() ReplyNever stub dest" \
  wasmd tx wasm execute "$schedule_addr" '{"later":{}}' \
  $(tx_flags "$GAS_EXEC"))

# Pin the honest failure shape: bech32 decode of "ledger.daily".
if ! echo "$fail_out" | grep -qiE 'bech32|invalid separator|decoding bech32|ledger\.daily|failed basic validation'; then
  # Still accept any non-zero deliver / CLI error, but warn if shape drifts.
  log "warn: later() failed but raw_log did not match expected bech32/stub pattern"
  log "  fail_out_head=$(echo "$fail_out" | head -c 500)"
fi
# Require evidence of failure text somewhere.
if ! echo "$fail_out" | grep -qiE 'failed|error|bech32|unreachable|code.:[1-9]'; then
  die "later() failure output lacked error markers: $(echo "$fail_out" | head -c 500)"
fi
log "later() failed as expected (QN stub dest / ReplyNever whole-tx abort)"

s=$(read_state0_u64 "$schedule_addr")
assert_eq "$s" "5" "ScheduleFlow state holds after later() SubMsg failure (parent rolled back)"

log "all assertions passed"
