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
# Args: caseId stepIndex status logicalStateJson returnValueJson rollbackEqual
#       addr slotWord valueWord [calldata] [returndata] [revertData] [logsJson]
emit_corpus_obs() {
  [[ -n "$corpus_obs_dir" ]] || return 0
  local case_id="$1"
  local step_index="$2"
  local status="$3"
  local logical_state="$4"
  local return_value="$5"
  local rollback_equal="$6"
  local addr="${7:-}"
  local slot_word="${8:-}"
  local value_word="${9:-}"
  local calldata="${10:-0x}"
  local returndata="${11:-0x}"
  local revert_data="${12:-null}"
  local logs_json="${13:-[]}"
  mkdir -p "$corpus_obs_dir/$case_id"
  local out="$corpus_obs_dir/$case_id/pf-anvil-step-${step_index}.json"
  CORPUS_VALIDATOR="$root/scripts/evm_corpus_v1.py" \
  /usr/bin/python3 -I -S - "$out" "$case_id" "$step_index" "$status" \
      "$logical_state" "$return_value" "$rollback_equal" "$addr" \
      "$slot_word" "$value_word" "$calldata" "$returndata" "$revert_data" \
      "$logs_json" <<'PY'
import importlib.util, json, os, sys
from pathlib import Path

out, case_id, step_s, status, logical_s, ret_s, rb_s = sys.argv[1:8]
addr, slot_w, value_w, calldata, returndata, rev_s, logs_s = sys.argv[8:15]
mod_path = Path(os.environ["CORPUS_VALIDATOR"])
spec = importlib.util.spec_from_file_location("evm_corpus_v1", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

logical = json.loads(logical_s)
ret = json.loads(ret_s)
rb = rb_s.lower() == "true"
logs = json.loads(logs_s)
rev = None if rev_s == "null" else rev_s

storage = []
if slot_w and value_w:
    storage = [{"slot": slot_w, "value": value_w}]

calldata = calldata if calldata.startswith("0x") else ("0x" + calldata)
returndata = returndata if returndata.startswith("0x") else ("0x" + returndata)
if rev is not None and not rev.startswith("0x"):
    rev = "0x" + rev

balances = []
if addr:
    balances = [{"id": "deployer", "wei": "0"}]

evm = {
    "balances": balances,
    "calldata": calldata,
    "externalCalls": [],
    "logs": logs,
    "returndata": returndata,
    "revertData": rev,
    "storageSlots": storage,
}
obs = {
    "schema": mod.SCHEMA_OBS,
    "caseId": case_id,
    "leg": "pf-anvil",
    "stepIndex": int(step_s),
    "verdict": "pass",
    "skipReason": None,
    "shared": {
        "status": status,
        "returnValue": ret,
        "logicalState": logical,
        "effects": [],
        "rollbackEqual": rb,
    },
    "evm": evm,
}
mod.validate_observation(obs)
raw = mod.dumps_canonical(obs)
Path(out).write_bytes(raw)
print(f"evm-smoke: wrote corpus obs {out} ({len(raw)} bytes)", file=sys.stderr)
PY
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

bytecode="$(tr -d '\n\r ' < "$(artifact_dir evm)/Counter.bin")"
encoded="$($cast abi-encode 'constructor(uint64)' 7)"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" --value 1 --create \
    "0x${bytecode}${encoded#0x}" >/dev/null 2>&1; then
  die "nonpayable constructor unexpectedly accepted value"
fi

max_counter="$(deploy evm "$UINT64_MAX")"
require_storage_uint "$max_counter" 0 "$UINT64_MAX" "Counter max constructor storage"
# Corpus case step 3: deploy max (status success, storage holds max).
slot0_max="$(storage_word32_from_uint "$UINT64_MAX")"
emit_corpus_obs "pf.primitive.counter.overflow-hold.v1" 3 "success" \
  "{\"count\":\"$UINT64_MAX\"}" "null" "true" \
  "$max_counter" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" \
  "$slot0_max"
require_revert_preserves_slot0 "$max_counter" "$UINT64_MAX" "Counter overflow" \
  'increment(uint64)' 1
require_uint_equal "$($cast call --rpc-url "$rpc" "$max_counter" 'get()(uint64)')" \
  "$UINT64_MAX" "Counter overflow changed view state"
# Corpus case step 4: overflow revert + raw storage hold + no committed logs.
emit_corpus_obs "pf.primitive.counter.overflow-hold.v1" 4 "revert" \
  "{\"count\":\"$UINT64_MAX\"}" "null" "true" \
  "$max_counter" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" \
  "$slot0_max" \
  "0x" "0x" "0x" "[]"
# Happy-path step 1 after increment(5) from 7 → 12 (earlier block state).
slot0_12="$(storage_word32_from_uint 12)"
emit_corpus_obs "pf.primitive.counter.overflow-hold.v1" 1 "success" \
  "{\"count\":12}" "12" "true" \
  "$counter" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" \
  "$slot0_12"

# ---------------------------------------------------------------------------
# Accumulator — same matrix as Counter (add entry)
# ---------------------------------------------------------------------------
[[ -f "$(artifact_dir evm-accumulator)/Accumulator.bin" ]] \
  || die "missing Accumulator artifact at $(artifact_dir evm-accumulator)/Accumulator.bin"

accumulator="$(deploy evm-accumulator 7)"
accumulator_before="$($cast call --rpc-url "$rpc" "$accumulator" 'current()(uint64)')"
require_uint_equal "$accumulator_before" "7" "Accumulator constructor state mismatch (view)"
require_storage_uint "$accumulator" 0 "7" "Accumulator constructor state mismatch (storage)"
accumulator_simulated="$($cast call --rpc-url "$rpc" "$accumulator" 'add(uint64)(uint64)' 5)"
require_uint_equal "$accumulator_simulated" "12" "Accumulator add return mismatch"
require_uint_equal "$($cast call --rpc-url "$rpc" "$accumulator" 'current()(uint64)')" "7" \
  "Accumulator eth_call unexpectedly committed state"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$accumulator" 'add(uint64)' 5 >/dev/null
accumulator_after="$($cast call --rpc-url "$rpc" "$accumulator" 'current()(uint64)')"
require_uint_equal "$accumulator_after" "12" "Accumulator add state mismatch (view)"
require_storage_uint "$accumulator" 0 "12" "Accumulator add state mismatch (storage)"
max_accumulator="$(deploy evm-accumulator "$UINT64_MAX")"
require_revert_preserves_slot0 "$max_accumulator" "$UINT64_MAX" "Accumulator overflow" \
  'add(uint64)' 1
require_uint_equal "$($cast call --rpc-url "$rpc" "$max_accumulator" 'current()(uint64)')" \
  "$UINT64_MAX" "Accumulator overflow changed view state"
slot0_max_acc="$(storage_word32_from_uint "$UINT64_MAX")"
slot0_12_acc="$(storage_word32_from_uint 12)"
emit_corpus_obs "pf.primitive.accumulator.overflow-hold.v1" 1 "success" \
  "{\"total\":12}" "12" "true" \
  "$accumulator" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" \
  "$slot0_12_acc"
emit_corpus_obs "pf.primitive.accumulator.overflow-hold.v1" 4 "revert" \
  "{\"total\":\"$UINT64_MAX\"}" "null" "true" \
  "$max_accumulator" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" \
  "$slot0_max_acc" \
  "0x" "0x" "0x" "[]"

# ---------------------------------------------------------------------------
# ArithOps (optional — present when target-smoke / differential built it)
# ---------------------------------------------------------------------------
if [[ -f "$(artifact_dir evm-arithops)/ArithOps.bin" ]]; then
  # ArithOps differential: masked bitNot (`~x = 2^64-1-x`) and checkedMul
  # overflow (scale with count = UInt64.max and factor = 2 must revert).
  arith="$(deploy evm-arithops 7)"
  bits_zero="$($cast call --rpc-url "$rpc" "$arith" 'bits(uint64)(uint64)' 0)"
  require_uint_equal "$bits_zero" "$UINT64_MAX" "ArithOps bits(0) must be UInt64.max (masked bitNot)"
  bits_five="$($cast call --rpc-url "$rpc" "$arith" 'bits(uint64)(uint64)' 5)"
  require_uint_equal "$bits_five" "18446744073709551610" "ArithOps bits(5) must be UInt64.max - 5"
  scale_ok="$($cast call --rpc-url "$rpc" "$arith" 'scale(uint64,uint64)(uint64)' 3 2)"
  require_uint_equal "$scale_ok" "11" "ArithOps scale(3,2) mismatch"
  require_storage_uint "$arith" 0 "7" "ArithOps eth_call must not write storage"
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$arith" 'scale(uint64,uint64)' 3 2 >/dev/null
  require_storage_uint "$arith" 0 "11" "ArithOps scale committed storage mismatch"
  max_arith="$(deploy evm-arithops "$UINT64_MAX")"
  require_revert_preserves_slot0 "$max_arith" "$UINT64_MAX" "ArithOps checkedMul overflow" \
    'scale(uint64,uint64)' 2 1
  slot0_11="$(storage_word32_from_uint 11)"
  slot0_max_ar="$(storage_word32_from_uint "$UINT64_MAX")"
  emit_corpus_obs "pf.primitive.arithops.bitnot-scale.v1" 3 "success" \
    "{\"count\":11}" "11" "true" \
    "$arith" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" \
    "$slot0_11"
  emit_corpus_obs "pf.primitive.arithops.bitnot-scale.v1" 5 "revert" \
    "{\"count\":\"$UINT64_MAX\"}" "null" "true" \
    "$max_arith" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" \
    "$slot0_max_ar" \
    "0x" "0x" "0x" "[]"
fi

# ---------------------------------------------------------------------------
# EventFlow (optional — product CLI build of emit/revert surface)
# ---------------------------------------------------------------------------
if [[ -f "$(artifact_dir evm-eventflow)/EventFlow.bin" ]]; then
  # EventFlow: emit Moved(src,dst) as log1; Cap(limit) ABI custom-error revert.
  # Deploy with count=0 so bump(5) takes the success arm (count > delta is false).
  eventflow="$(deploy evm-eventflow 0)"
  require_storage_uint "$eventflow" 0 "0" "EventFlow constructor storage"
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

  # Corpus observations: ordered log on success, empty logs + rollback on Cap.
  slot0_5="$(storage_word32_from_uint 5)"
  log_obs="$(/usr/bin/python3 -I -S -c '
import json,sys
topic=sys.argv[1].lower()
addr=sys.argv[2].lower()
# ABI data for Moved(0,5): two 32-byte words
data="0x"+"0"*63+"0"+"0"*63+"5"
print(json.dumps([{"address":addr,"topics":[topic],"data":data}]))
' "$moved_topic" "$eventflow")"
  emit_corpus_obs "pf.primitive.eventflow.emit-cap.v1" 1 "success" \
    "{\"count\":5}" "5" "true" \
    "$eventflow" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" \
    "$slot0_5" \
    "0x" "0x" "null" "$log_obs"
  emit_corpus_obs "pf.primitive.eventflow.emit-cap.v1" 3 "revert" \
    "{\"count\":5}" "null" "true" \
    "$eventflow" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" \
    "$slot0_5" \
    "0x" "0x" "0x" "[]"
fi

covered="Counter + Accumulator"
[[ -f "$(artifact_dir evm-arithops)/ArithOps.bin" ]] && covered+=" + ArithOps"
[[ -f "$(artifact_dir evm-eventflow)/EventFlow.bin" ]] && covered+=" + EventFlow"
echo "evm-smoke: ok ($covered; view+storage dual-read; overflow/Cap revert state hold; engineering only — not formal Reference↔Anvil)"
