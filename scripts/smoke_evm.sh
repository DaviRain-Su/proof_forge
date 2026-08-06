#!/usr/bin/env bash
# Engineering Anvil runtime differential for product EVM bytecode.
#
# Coverage (when artifacts under build/v2/* exist):
#   - Counter: init / view+storage / increment / overflow revert+state hold
#   - Accumulator: init / view+storage / add / overflow revert+state hold
#   - ArithOps (optional artifact): masked bitNot + checkedMul overflow
#   - EventFlow (optional artifact): emit Moved log topic+data + Cap revert
#
# Preconditions:
#   - FOUNDRY_BIN (or PROOF_FORGE_TOOL_ROOT / default tool-root) has locked
#     anvil + cast (exact sha256 + version pin from toolchains.lock.json).
#   - Product CLI already wrote Counter.bin / Accumulator.bin (etc.).
#
# NOT formal TASK-D4-05 / TST-EVM-005 / Reference↔Anvil closure (C-3).
# This is an engineering local_runtime gate only.
#
# Optional Cancun hardfork pin (EVMOZ-001):
#   PF_EVM_PROFILE=evm-yul-solc-0.8.34-cancun-v1 → anvil --hardfork cancun
# Legacy/default path keeps historical anvil args (no ambient hardfork flag).
#
# Optional EVMOZ-004 corpus observation emit:
#   PF_EVM_CORPUS_OBS_DIR=<dir> → write proof-forge.evm-observation.v1 JSON
#   (canonical PF-JCS) for key steps after assertions. Not formal C-3.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
corpus_obs_dir="${PF_EVM_CORPUS_OBS_DIR:-}"
case "$(uname -s)" in
  Darwin)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"
    lock_file="$root/toolchains.lock.json"
    ;;
  Linux)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)"
    lock_file="$root/toolchains-linux-$(uname -m).lock.json"
    ;;
  *)
    echo "evm-smoke: unsupported host platform" >&2
    exit 2
    ;;
esac
foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}}"
anvil="$foundry_bin/anvil"
cast="$foundry_bin/cast"
port="${PF_EVM_PORT:-18545}"
chain_id="${PF_EVM_CHAIN_ID:-31338}"
rpc="http://127.0.0.1:$port"
private_key="${PF_EVM_PRIVATE_KEY:-ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
# Second default Anvil account (index 1) for OwnableLike unauthorized paths.
stranger_private_key="${PF_EVM_STRANGER_PRIVATE_KEY:-59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d}"
log="$root/build/v2/anvil.log"
UINT64_MAX="18446744073709551615"
# Optional product profile → runtime hardfork pin + profile-keyed artifact trees.
# Empty / legacy: build/v2/evm, build/v2/evm-accumulator, … (historical paths).
# Cancun: build/v2/evm-cancun, build/v2/evm-accumulator-cancun, …
# Must match scripts/evm_anvil_differential.sh so Cancun never reuses legacy bins.
evm_profile="${PF_EVM_PROFILE:-}"
anvil_extra_args=()
artifact_suffix=""
case "$evm_profile" in
  ""|"evm-yul-solc-0.8.34-v1")
    : # legacy default: do not pass ambient --hardfork; no path suffix
    ;;
  "evm-yul-solc-0.8.34-cancun-v1")
    anvil_extra_args+=(--hardfork cancun)
    artifact_suffix="-cancun"
    echo "evm-smoke: profile=$evm_profile → anvil --hardfork cancun; artifacts *${artifact_suffix}" >&2
    ;;
  *)
    echo "evm-smoke: unsupported PF_EVM_PROFILE='$evm_profile' (expected empty, evm-yul-solc-0.8.34-v1, or evm-yul-solc-0.8.34-cancun-v1)" >&2
    exit 2
    ;;
esac

# Logical program dir name → absolute tree: build/v2/<name>${artifact_suffix}
artifact_dir() {
  echo "$root/build/v2/${1}${artifact_suffix}"
}

die() {
  echo "evm-smoke: $*" >&2
  exit 1
}

require_equal() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  [[ "$actual" == "$expected" ]] || die "$message (expected '$expected', got '$actual')"
}

require_uint_equal() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  local canonical
  if [[ "$actual" =~ ^([0-9]+)(\ \[[0-9.eE+-]+\])?$ ]]; then
    canonical="${BASH_REMATCH[1]}"
  else
    die "$message (expected uint output, got '$actual')"
  fi
  require_equal "$canonical" "$expected" "$message"
}

# Normalize cast storage / hex / decimal to a decimal integer string.
to_dec() {
  local x="$1"
  x="${x//$'\n'/}"
  x="${x// /}"
  if [[ -z "$x" ]]; then
    echo ""
    return
  fi
  if [[ "$x" == 0x* || "$x" == 0X* ]]; then
    /usr/bin/python3 -I -S -c "print(int('$x', 16))"
  elif [[ "$x" =~ ^([0-9]+)(\ \[[0-9.eE+-]+\])?$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "$x"
  fi
}

require_storage_uint() {
  local addr="$1"
  local slot="$2"
  local expected="$3"
  local message="$4"
  local raw actual
  raw="$("$cast" storage --rpc-url "$rpc" "$addr" "$slot")"
  actual="$(to_dec "$raw")"
  require_equal "$actual" "$expected" "$message (storage slot $slot raw=$raw)"
}

# Word32 hex for EVM storage observation (0x + 64 lowercase hex).
storage_word32_from_uint() {
  local n="$1"
  /usr/bin/python3 -I -S -c "print('0x' + format(int('$n'), '064x'))"
}

# Emit one proof-forge.evm-observation.v1 (canonical) when OBS dir is set.
# Shared face must match Reference (decimal-string UInt, ordered effects).
# Args: caseId step status returnJson logicalJson effectsJson rollback
#       slotWord valueWord [logsJson] [revertData]
emit_corpus_obs() {
  [[ -n "$corpus_obs_dir" ]] || return 0
  local case_id="$1"
  local step_index="$2"
  local status="$3"
  local return_json="$4"
  local logical_json="$5"
  local effects_json="$6"
  local rollback_equal="$7"
  local slot_word="${8:-}"
  local value_word="${9:-}"
  local logs_json="${10:-[]}"
  local revert_data="${11:-null}"
  local storage_json="[]"
  if [[ -n "$slot_word" && -n "$value_word" ]]; then
    storage_json="[{\"slot\":\"$slot_word\",\"value\":\"$value_word\"}]"
  fi
  local rev_json="null"
  if [[ "$revert_data" != "null" ]]; then
    rev_json="\"$revert_data\""
  fi
  local evm_json
  evm_json="$(/usr/bin/python3 -I -S -c "
import json
print(json.dumps({
  'balances': [{'id': 'deployer', 'wei': '0'}],
  'calldata': '0x',
  'externalCalls': [],
  'logs': json.loads('''$logs_json'''),
  'returndata': '0x',
  'revertData': None if '''$rev_json''' == 'null' else json.loads('''$rev_json'''),
  'storageSlots': json.loads('''$storage_json'''),
}))
")"
  /usr/bin/python3 -I -S "$root/scripts/evm_corpus_obs_write.py" \
    "$corpus_obs_dir" "$case_id" "pf-anvil" "$step_index" \
    "$status" "$return_json" "$logical_json" "$effects_json" "$rollback_equal" \
    "$evm_json"
}

# Send a state-changing tx; return the tx hash on stdout. Fail if send fails.
send_tx() {
  local out
  out="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" "$@")"
  /usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin)["transactionHash"])' <<<"$out"
}

# Assert a tx reverts (cast send non-zero) AND that storage slot 0 is unchanged.
# PRD Phase-1 DoD: overflow attempt reverts and state is unchanged.
require_revert_preserves_slot0() {
  local addr="$1"
  local expected_slot="$2"
  local label="$3"
  shift 3
  if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
      "$addr" "$@" >/dev/null 2>&1; then
    die "$label: overflow/revert transaction unexpectedly succeeded"
  fi
  require_storage_uint "$addr" 0 "$expected_slot" \
    "$label: overflow must leave storage slot 0 unchanged"
}

for tool in "$anvil" "$cast"; do
  if [[ ! -x "$tool" ]]; then
    echo "evm-smoke: missing $tool" >&2
    exit 2
  fi
done

expected_hash() {
  /usr/bin/python3 -I -S -c 'import json,sys; data=json.load(open(sys.argv[1], encoding="utf-8")); print(next(tool["executableSha256"] for tool in data["tools"] if tool["id"] == sys.argv[2]))' \
    "$lock_file" "$1"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

actual_anvil_hash="$(sha256_of "$anvil")"
actual_cast_hash="$(sha256_of "$cast")"
require_equal "$actual_anvil_hash" "$(expected_hash anvil)" "Anvil hash mismatch"
require_equal "$actual_cast_hash" "$(expected_hash cast)" "cast hash mismatch"

if ! "$anvil" --version | grep -Fq '0.3.0 (5a8bd89'; then
  die "unexpected Anvil version"
fi
if ! "$cast" --version | grep -Fq '0.3.0 (5a8bd89'; then
  die "unexpected cast version"
fi

mkdir -p "$root/build/v2"
if "$cast" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
  die "RPC endpoint $rpc is already occupied"
fi
# set -u + empty array: expand only when non-empty (bash 3.2/macOS).
if ((${#anvil_extra_args[@]})); then
  "$anvil" --host 127.0.0.1 --port "$port" --chain-id "$chain_id" \
    "${anvil_extra_args[@]}" --silent >"$log" 2>&1 &
else
  "$anvil" --host 127.0.0.1 --port "$port" --chain-id "$chain_id" \
    --silent >"$log" 2>&1 &
fi
anvil_pid=$!
cleanup() {
  kill "$anvil_pid" 2>/dev/null || true
  wait "$anvil_pid" 2>/dev/null || true
}
trap cleanup EXIT

anvil_running() {
  local running_jobs
  running_jobs="$(jobs -pr)"
  [[ "$running_jobs" == "$anvil_pid" ]]
}

ready=0
for _ in $(seq 1 50); do
  if ! anvil_running; then
    wait "$anvil_pid" 2>/dev/null || true
    echo "evm-smoke: launched Anvil exited before readiness; see $log" >&2
    exit 1
  fi
  if "$cast" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "$ready" != 1 ]]; then
  echo "evm-smoke: anvil failed to start; see $log" >&2
  exit 1
fi
if ! anvil_running; then
  echo "evm-smoke: launched Anvil exited after readiness; refusing an incumbent RPC" >&2
  exit 1
fi
require_equal "$($cast chain-id --rpc-url "$rpc")" "$chain_id" \
  "launched Anvil chain identity mismatch"

deploy() {
  local program="$1"
  local initial="$2"
  local artifact bytecode encoded receipt
  case "$program" in
    evm) artifact=Counter ;;
    evm-accumulator) artifact=Accumulator ;;
    evm-arithops) artifact=ArithOps ;;
    evm-eventflow) artifact=EventFlow ;;
    *) echo "evm-smoke: unknown program artifact '$program'" >&2; return 2 ;;
  esac
  local bin_path="$(artifact_dir "$program")/$artifact.bin"
  [[ -f "$bin_path" ]] || die "missing artifact $bin_path"
  bytecode="$(tr -d '\n\r ' < "$bin_path")"
  # All current fixtures take a single uint64 constructor arg.
  encoded="$($cast abi-encode 'constructor(uint64)' "$initial")"
  receipt="$($cast send --json --rpc-url "$rpc" --private-key "$private_key" --create "0x${bytecode}${encoded#0x}")"
  /usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])' <<<"$receipt"
}

# ---------------------------------------------------------------------------
# Counter — view + storage dual-read, increment, overflow state hold
# ---------------------------------------------------------------------------
[[ -f "$(artifact_dir evm)/Counter.bin" ]] \
  || die "missing Counter artifact (required by differential matrix) at $(artifact_dir evm)/Counter.bin"

counter="$(deploy evm 7)"
before="$($cast call --rpc-url "$rpc" "$counter" 'get()(uint64)')"
require_uint_equal "$before" "7" "Counter constructor state mismatch (view)"
require_storage_uint "$counter" 0 "7" "Counter constructor state mismatch (storage)"
slot0_7="$(storage_word32_from_uint 7)"
# step 0: deploy 7
emit_corpus_obs "pf.primitive.counter.overflow-hold.v1" 0 "success" \
  "null" '{"count":"7"}' '[]' "true" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_7"

counter_simulated="$($cast call --rpc-url "$rpc" "$counter" 'increment(uint64)(uint64)' 5)"
require_uint_equal "$counter_simulated" "12" "Counter increment return mismatch"
require_uint_equal "$($cast call --rpc-url "$rpc" "$counter" 'get()(uint64)')" "7" \
  "Counter eth_call unexpectedly committed state"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" --value 2 \
    "$counter" 'increment(uint64)' 5 >/dev/null 2>&1; then
  die "nonpayable increment unexpectedly accepted value"
fi
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$counter" 'increment(uint64)' 5 >/dev/null
after="$($cast call --rpc-url "$rpc" "$counter" 'get()(uint64)')"
require_uint_equal "$after" "12" "Counter increment state mismatch (view)"
require_storage_uint "$counter" 0 "12" "Counter increment state mismatch (storage)"
balance="$($cast balance --rpc-url "$rpc" "$counter")"
require_equal "$balance" "0" "Counter accepted native value"
slot0_12="$(storage_word32_from_uint 12)"
# step 1: increment 5 → 12
emit_corpus_obs "pf.primitive.counter.overflow-hold.v1" 1 "success" \
  '"12"' '{"count":"12"}' '[]' "true" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_12"
# step 2: view get
emit_corpus_obs "pf.primitive.counter.overflow-hold.v1" 2 "success" \
  '"12"' '{"count":"12"}' '[]' "true" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_12"

bytecode="$(tr -d '\n\r ' < "$(artifact_dir evm)/Counter.bin")"
encoded="$($cast abi-encode 'constructor(uint64)' 7)"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" --value 1 --create \
    "0x${bytecode}${encoded#0x}" >/dev/null 2>&1; then
  die "nonpayable constructor unexpectedly accepted value"
fi

max_counter="$(deploy evm "$UINT64_MAX")"
require_storage_uint "$max_counter" 0 "$UINT64_MAX" "Counter max constructor storage"
slot0_max="$(storage_word32_from_uint "$UINT64_MAX")"
# step 3: deploy max
emit_corpus_obs "pf.primitive.counter.overflow-hold.v1" 3 "success" \
  "null" "{\"count\":\"$UINT64_MAX\"}" '[]' "true" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_max"
require_revert_preserves_slot0 "$max_counter" "$UINT64_MAX" "Counter overflow" \
  'increment(uint64)' 1
require_uint_equal "$($cast call --rpc-url "$rpc" "$max_counter" 'get()(uint64)')" \
  "$UINT64_MAX" "Counter overflow changed view state"
# step 4: overflow revert
emit_corpus_obs "pf.primitive.counter.overflow-hold.v1" 4 "revert" \
  "null" "{\"count\":\"$UINT64_MAX\"}" '[]' "true" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_max" \
  "[]" "0x"
# step 5: view get holds max
emit_corpus_obs "pf.primitive.counter.overflow-hold.v1" 5 "success" \
  "\"$UINT64_MAX\"" "{\"count\":\"$UINT64_MAX\"}" '[]' "true" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_max"

# ---------------------------------------------------------------------------
# Accumulator — same matrix as Counter (add entry)
# ---------------------------------------------------------------------------
[[ -f "$(artifact_dir evm-accumulator)/Accumulator.bin" ]] \
  || die "missing Accumulator artifact at $(artifact_dir evm-accumulator)/Accumulator.bin"

accumulator="$(deploy evm-accumulator 7)"
accumulator_before="$($cast call --rpc-url "$rpc" "$accumulator" 'current()(uint64)')"
require_uint_equal "$accumulator_before" "7" "Accumulator constructor state mismatch (view)"
require_storage_uint "$accumulator" 0 "7" "Accumulator constructor state mismatch (storage)"
slot0_7_acc="$(storage_word32_from_uint 7)"
emit_corpus_obs "pf.primitive.accumulator.overflow-hold.v1" 0 "success" \
  "null" '{"total":"7"}' '[]' "true" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_7_acc"
accumulator_simulated="$($cast call --rpc-url "$rpc" "$accumulator" 'add(uint64)(uint64)' 5)"
require_uint_equal "$accumulator_simulated" "12" "Accumulator add return mismatch"
require_uint_equal "$($cast call --rpc-url "$rpc" "$accumulator" 'current()(uint64)')" "7" \
  "Accumulator eth_call unexpectedly committed state"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$accumulator" 'add(uint64)' 5 >/dev/null
accumulator_after="$($cast call --rpc-url "$rpc" "$accumulator" 'current()(uint64)')"
require_uint_equal "$accumulator_after" "12" "Accumulator add state mismatch (view)"
require_storage_uint "$accumulator" 0 "12" "Accumulator add state mismatch (storage)"
slot0_12_acc="$(storage_word32_from_uint 12)"
emit_corpus_obs "pf.primitive.accumulator.overflow-hold.v1" 1 "success" \
  '"12"' '{"total":"12"}' '[]' "true" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_12_acc"
emit_corpus_obs "pf.primitive.accumulator.overflow-hold.v1" 2 "success" \
  '"12"' '{"total":"12"}' '[]' "true" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_12_acc"
max_accumulator="$(deploy evm-accumulator "$UINT64_MAX")"
require_revert_preserves_slot0 "$max_accumulator" "$UINT64_MAX" "Accumulator overflow" \
  'add(uint64)' 1
require_uint_equal "$($cast call --rpc-url "$rpc" "$max_accumulator" 'current()(uint64)')" \
  "$UINT64_MAX" "Accumulator overflow changed view state"
slot0_max_acc="$(storage_word32_from_uint "$UINT64_MAX")"
emit_corpus_obs "pf.primitive.accumulator.overflow-hold.v1" 3 "success" \
  "null" "{\"total\":\"$UINT64_MAX\"}" '[]' "true" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_max_acc"
emit_corpus_obs "pf.primitive.accumulator.overflow-hold.v1" 4 "revert" \
  "null" "{\"total\":\"$UINT64_MAX\"}" '[]' "true" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_max_acc" \
  "[]" "0x"
emit_corpus_obs "pf.primitive.accumulator.overflow-hold.v1" 5 "success" \
  "\"$UINT64_MAX\"" "{\"total\":\"$UINT64_MAX\"}" '[]' "true" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_max_acc"

# ---------------------------------------------------------------------------
# ArithOps (optional — present when target-smoke / differential built it)
# ---------------------------------------------------------------------------
if [[ -f "$(artifact_dir evm-arithops)/ArithOps.bin" ]]; then
  # ArithOps differential: masked bitNot (`~x = 2^64-1-x`) and checkedMul
  # overflow (scale with count = UInt64.max and factor = 2 must revert).
  arith="$(deploy evm-arithops 7)"
  slot0_7_ar="$(storage_word32_from_uint 7)"
  emit_corpus_obs "pf.primitive.arithops.bitnot-scale.v1" 0 "success" \
    "null" '{"count":"7"}' '[]' "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_7_ar"
  bits_zero="$($cast call --rpc-url "$rpc" "$arith" 'bits(uint64)(uint64)' 0)"
  require_uint_equal "$bits_zero" "$UINT64_MAX" "ArithOps bits(0) must be UInt64.max (masked bitNot)"
  # step 1: bits(0) eth_call — Reference also does not store; use call path via cast call
  # For corpus shared face we use call semantics matching Reference (no storage write).
  emit_corpus_obs "pf.primitive.arithops.bitnot-scale.v1" 1 "success" \
    "\"$UINT64_MAX\"" '{"count":"7"}' '[]' "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_7_ar"
  bits_five="$($cast call --rpc-url "$rpc" "$arith" 'bits(uint64)(uint64)' 5)"
  require_uint_equal "$bits_five" "18446744073709551610" "ArithOps bits(5) must be UInt64.max - 5"
  emit_corpus_obs "pf.primitive.arithops.bitnot-scale.v1" 2 "success" \
    '"18446744073709551610"' '{"count":"7"}' '[]' "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_7_ar"
  scale_ok="$($cast call --rpc-url "$rpc" "$arith" 'scale(uint64,uint64)(uint64)' 3 2)"
  require_uint_equal "$scale_ok" "11" "ArithOps scale(3,2) mismatch"
  require_storage_uint "$arith" 0 "7" "ArithOps eth_call must not write storage"
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$arith" 'scale(uint64,uint64)' 3 2 >/dev/null
  require_storage_uint "$arith" 0 "11" "ArithOps scale committed storage mismatch"
  slot0_11="$(storage_word32_from_uint 11)"
  emit_corpus_obs "pf.primitive.arithops.bitnot-scale.v1" 3 "success" \
    '"11"' '{"count":"11"}' '[]' "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_11"
  max_arith="$(deploy evm-arithops "$UINT64_MAX")"
  require_revert_preserves_slot0 "$max_arith" "$UINT64_MAX" "ArithOps checkedMul overflow" \
    'scale(uint64,uint64)' 2 1
  slot0_max_ar="$(storage_word32_from_uint "$UINT64_MAX")"
  emit_corpus_obs "pf.primitive.arithops.bitnot-scale.v1" 4 "success" \
    "null" "{\"count\":\"$UINT64_MAX\"}" '[]' "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_max_ar"
  emit_corpus_obs "pf.primitive.arithops.bitnot-scale.v1" 5 "revert" \
    "null" "{\"count\":\"$UINT64_MAX\"}" '[]' "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_max_ar" \
    "[]" "0x"
fi

# ---------------------------------------------------------------------------
# EventFlow (optional — product CLI build of emit/revert surface)
# ---------------------------------------------------------------------------
if [[ -f "$(artifact_dir evm-eventflow)/EventFlow.bin" ]]; then
  # EventFlow: emit Moved(src,dst) as log1; Cap(limit) ABI custom-error revert.
  # Deploy with count=0 so bump(5) takes the success arm (count > delta is false).
  eventflow="$(deploy evm-eventflow 0)"
  require_storage_uint "$eventflow" 0 "0" "EventFlow constructor storage"
  slot0_0="$(storage_word32_from_uint 0)"
  emit_corpus_obs "pf.primitive.eventflow.emit-cap.v1" 0 "success" \
    "null" '{"count":"0"}' '[]' "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_0"
  moved_topic="$("$cast" keccak "Moved(uint64,uint64)")"
  # Normalize topic to 0x + 64 hex lowercase.
  moved_topic="$(/usr/bin/python3 -I -S -c "t='$moved_topic'.lower(); print(t if t.startswith('0x') else '0x'+t)")"

  tx_hash="$(send_tx "$eventflow" 'bump(uint64)' 5)"
  require_storage_uint "$eventflow" 0 "5" "EventFlow bump success storage"
  require_uint_equal "$($cast call --rpc-url "$rpc" "$eventflow" 'get()(uint64)')" "5" \
    "EventFlow bump success view"

  # Receipt must contain exactly one log with Moved topic and ABI data (0, 5).
  receipt_json="$("$cast" receipt --rpc-url "$rpc" --json "$tx_hash")"
  /usr/bin/python3 -I -S -c '
import json, sys
topic = sys.argv[1].lower()
addr = sys.argv[2].lower()
r = json.load(sys.stdin)
logs = r.get("logs") or []
if not logs:
    raise SystemExit("EventFlow: receipt has no logs (emit missing)")
matched = []
for lg in logs:
    topics = [t.lower() for t in (lg.get("topics") or [])]
    if topics and topics[0] == topic and (lg.get("address") or "").lower() == addr:
        matched.append(lg)
if len(matched) != 1:
    raise SystemExit(f"EventFlow: expected 1 Moved log, got {len(matched)} (total logs={len(logs)})")
data = (matched[0].get("data") or "").lower()
if data.startswith("0x"):
    data = data[2:]
# Two 32-byte words: src=0, dst=5 (pre-bump count, delta)
if len(data) != 128:
    raise SystemExit(f"EventFlow: log data length {len(data)} != 128 hex chars")
src = int(data[0:64], 16)
dst = int(data[64:128], 16)
if src != 0 or dst != 5:
    raise SystemExit(f"EventFlow: Moved data expected (0,5) got ({src},{dst})")
print("EventFlow: Moved(0,5) log ok")
' "$moved_topic" "$eventflow" <<<"$receipt_json"

  slot0_5="$(storage_word32_from_uint 5)"
  log_obs="$(/usr/bin/python3 -I -S -c '
import json,sys
topic=sys.argv[1].lower()
addr=sys.argv[2].lower()
data="0x"+"0"*64+"0"*63+"5"
print(json.dumps([{"address":addr,"topics":[topic],"data":data}]))
' "$moved_topic" "$eventflow")"
  # step 1: shared effects must match Reference OrderedEffect (Moved 0,5)
  effects_moved='[{"kind":"event","eventId":0,"args":["0","5"]}]'
  emit_corpus_obs "pf.primitive.eventflow.emit-cap.v1" 1 "success" \
    '"5"' '{"count":"5"}' "$effects_moved" "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_5" \
    "$log_obs"
  emit_corpus_obs "pf.primitive.eventflow.emit-cap.v1" 2 "success" \
    '"5"' '{"count":"5"}' '[]' "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_5"

  # Second bump with count=5, delta=3: count > delta → Cap revert.
  # Source order: emit first, then if count > delta revert Cap. On EVM a full
  # tx revert rolls back the log as well — state stays 5; no new committed log.
  if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
      "$eventflow" 'bump(uint64)' 3 >/dev/null 2>&1; then
    die "EventFlow Cap revert path unexpectedly succeeded"
  fi
  require_storage_uint "$eventflow" 0 "5" "EventFlow Cap revert must leave storage unchanged"
  require_uint_equal "$($cast call --rpc-url "$rpc" "$eventflow" 'get()(uint64)')" "5" \
    "EventFlow Cap revert changed view"
  emit_corpus_obs "pf.primitive.eventflow.emit-cap.v1" 3 "revert" \
    "null" '{"count":"5"}' '[]' "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_5" \
    "[]" "0x"
  emit_corpus_obs "pf.primitive.eventflow.emit-cap.v1" 4 "success" \
    '"5"' '{"count":"5"}' '[]' "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" "$slot0_5"
fi

# ---------------------------------------------------------------------------
# OwnableLike (optional artifact) — corpus case
# pf.primitive.ownablelike.caller-admit.v1: init records msg.sender as owner
# (Principal); setValue only-owner; unauthorized reverts with state hold.
# Storage layout: owner Principal slots 0..8, value UInt64 slot 9.
# ---------------------------------------------------------------------------
if [[ -f "$(artifact_dir evm-ownablelike)/OwnableLike.bin" ]]; then
  ownable_bin="$(artifact_dir evm-ownablelike)/OwnableLike.bin"
  bytecode="$(tr -d '\n\r ' < "$ownable_bin")"
  receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" --create "0x${bytecode}")"
  ownable="$(/usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])' <<<"$receipt")"
  [[ -n "$ownable" && "$ownable" != "null" ]] || die "OwnableLike deploy failed"
  # step 0: deploy — owner := msg.sender (account 0); value = 0 (slot 9)
  require_storage_uint "$ownable" 9 "0" "OwnableLike constructor value slot"
  slot9_0="$(storage_word32_from_uint 0)"
  emit_corpus_obs "pf.primitive.ownablelike.caller-admit.v1" 0 "success" \
    "null" '{"value":"0"}' '[]' "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000009" "$slot9_0"
  # step 1: authorized setValue(42) from owner
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$ownable" 'setValue(uint64)(uint64)' 42 >/dev/null
  require_uint_equal "$($cast call --rpc-url "$rpc" "$ownable" 'getValue()(uint64)')" "42" \
    "OwnableLike authorized setValue view"
  require_storage_uint "$ownable" 9 "42" "OwnableLike authorized setValue storage"
  slot9_42="$(storage_word32_from_uint 42)"
  emit_corpus_obs "pf.primitive.ownablelike.caller-admit.v1" 1 "success" \
    '"42"' '{"value":"42"}' '[]' "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000009" "$slot9_42"
  # step 2: view getValue → 42
  emit_corpus_obs "pf.primitive.ownablelike.caller-admit.v1" 2 "success" \
    '"42"' '{"value":"42"}' '[]' "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000009" "$slot9_42"
  # step 3: unauthorized setValue(7) from stranger (account 1) → revert; state holds
  if "$cast" send --rpc-url "$rpc" --private-key "$stranger_private_key" \
      "$ownable" 'setValue(uint64)(uint64)' 7 >/dev/null 2>&1; then
    die "OwnableLike unauthorized setValue unexpectedly succeeded"
  fi
  require_storage_uint "$ownable" 9 "42" "OwnableLike unauthorized revert must hold value"
  require_uint_equal "$($cast call --rpc-url "$rpc" "$ownable" 'getValue()(uint64)')" "42" \
    "OwnableLike unauthorized revert changed view"
  emit_corpus_obs "pf.primitive.ownablelike.caller-admit.v1" 3 "revert" \
    "null" '{"value":"42"}' '[]' "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000009" "$slot9_42" \
    "[]" "0x"
  # step 4: view getValue still 42
  emit_corpus_obs "pf.primitive.ownablelike.caller-admit.v1" 4 "success" \
    '"42"' '{"value":"42"}' '[]' "true" \
    "0x0000000000000000000000000000000000000000000000000000000000000009" "$slot9_42"
else
  echo "evm-smoke: note: OwnableLike artifact missing (skip ownable corpus leg)" >&2
fi

covered="Counter + Accumulator"
[[ -f "$(artifact_dir evm-arithops)/ArithOps.bin" ]] && covered+=" + ArithOps"
[[ -f "$(artifact_dir evm-eventflow)/EventFlow.bin" ]] && covered+=" + EventFlow"
[[ -f "$(artifact_dir evm-ownablelike)/OwnableLike.bin" ]] && covered+=" + OwnableLike"
echo "evm-smoke: ok ($covered; view+storage dual-read; overflow/Cap revert state hold; engineering only — not formal Reference↔Anvil)"
