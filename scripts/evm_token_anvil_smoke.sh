#!/usr/bin/env bash
# Engineering Token mint/transfer (+ overflow / over-transfer hold) smoke on Anvil.
# Adapter observation for pf.adapter.token.conservation.v1 (EVMOZ-004).
# Not formal Reference↔Anvil (C-3). Not OZ/family/ABI/standard credit.
#
# Dense Map pilot may hit solc StackTooDeep or EIP-3860 initcode limits —
# those paths are **explicit skip** (exit 0 + skip observation when OBS dir set),
# never silent pass and never skip-as-pass on assertion failure after deploy.
#
# Requires Foundry anvil/cast. Builds Token.bin via product CLI when missing.
#
# Profile inheritance (EVMOZ-001): honors PF_EVM_PROFILE so Cancun differential
# cannot silently mix default-profile bytecode with --hardfork cancun.
#   empty / evm-yul-solc-0.8.34-v1 → build/v2/token-evm + historical anvil args
#   evm-yul-solc-0.8.34-cancun-v1 → build/v2/token-evm-cancun + anvil --hardfork cancun
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
corpus_obs_dir="${PF_EVM_CORPUS_OBS_DIR:-}"
case_id="pf.adapter.token.conservation.v1"

write_token_skip_obs() {
  # Explicit optional-leg skip for all 9 case steps (never pass).
  local reason="$1"
  [[ -n "$corpus_obs_dir" ]] || return 0
  mkdir -p "$corpus_obs_dir/$case_id"
  CORPUS_VALIDATOR="$root/scripts/evm_corpus_v1.py" \
  /usr/bin/python3 -I -S - "$corpus_obs_dir/$case_id" "$case_id" "$reason" <<'PY'
import importlib.util, os, sys
from pathlib import Path
out_dir, case_id, reason = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
if len(reason.encode()) > 128:
    reason = reason[:120] + "..."
spec = importlib.util.spec_from_file_location("evm_corpus_v1", os.environ["CORPUS_VALIDATOR"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
for step in range(9):
    obs = {
        "schema": mod.SCHEMA_OBS,
        "caseId": case_id,
        "leg": "pf-anvil",
        "stepIndex": step,
        "verdict": "skip",
        "skipReason": reason,
        "shared": {
            "status": "success",
            "returnValue": None,
            "logicalState": {},
            "effects": [],
            "rollbackEqual": True,
        },
        "evm": {
            "balances": [],
            "calldata": "0x",
            "externalCalls": [],
            "logs": [],
            "returndata": "0x",
            "revertData": None,
            "storageSlots": [],
        },
    }
    mod.validate_observation(obs)
    path = out_dir / f"pf-anvil-step-{step}.json"
    path.write_bytes(mod.dumps_canonical(obs))
print(f"evm-token-anvil: wrote 9 skip observations under {out_dir}", file=sys.stderr)
PY
}

case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *)
    echo "evm-token-anvil: explicit skip: unsupported host (optional adapter leg; not pass)" >&2
    write_token_skip_obs "missing-optional-tool:unsupported-host"
    exit 0
    ;;
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
  echo "evm-token-anvil: explicit skip: anvil/cast unavailable (optional adapter leg; not pass)" >&2
  echo "evm-token-anvil: engineering only; not formal Reference↔Anvil" >&2
  write_token_skip_obs "missing-optional-tool:anvil-or-cast"
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
    echo "evm-token-anvil: explicit skip: unsupported PF_EVM_PROFILE='$evm_profile' (optional adapter; not pass)" >&2
    write_token_skip_obs "missing-optional-tool:unsupported-profile"
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
  # CLI discovery: PROOF_FORGE_CLI → local .lake → PATH
  token_cli=""
  if [[ -n "${PROOF_FORGE_CLI:-}" && -x "${PROOF_FORGE_CLI}" ]]; then
    token_cli="$PROOF_FORGE_CLI"
  elif [[ -x "$root/.lake/build/bin/proof-forge-next" ]]; then
    token_cli="$root/.lake/build/bin/proof-forge-next"
  elif command -v proof-forge-next >/dev/null 2>&1; then
    token_cli="$(command -v proof-forge-next)"
  fi
  if [[ -n "$token_cli" ]] && command -v lake >/dev/null 2>&1; then
    # Product CLI refuses non-empty existing -o dirs (PF-OUTPUT-COLLISION).
    rm -rf "$token_out"
    build_log="$(mktemp "${TMPDIR:-/tmp}/pf-token-build.XXXXXX.log")"
    lake_root="${PF_LAKE_ROOT:-$root}"
    set +e
    # Fixed single-quoted bash -c + positional args (no path injection into -c source).
    if [[ ${#build_profile_args[@]} -gt 0 ]]; then
      (cd "$lake_root" && lake env bash -c 'cd "$1"; shift; exec "$@"' _ "$root" \
        "$token_cli" build Examples/Token.lean --module Examples.Token --target evm \
        "${build_profile_args[@]}" -o "$token_out_rel") >"$build_log" 2>&1
      build_rc=$?
    else
      (cd "$lake_root" && lake env bash -c 'cd "$1"; shift; exec "$@"' _ "$root" \
        "$token_cli" build Examples/Token.lean --module Examples.Token --target evm \
        -o "$token_out_rel") >"$build_log" 2>&1
      build_rc=$?
    fi
    set -e
    if [[ "$build_rc" -ne 0 ]]; then
      if grep -qiE 'StackTooDeep|stack too deep' "$build_log" 2>/dev/null; then
        echo "evm-token-anvil: explicit skip: solc StackTooDeep on dense Map pilot (profile=$expected_profile_wire; adapter case; not pass)" >&2
        write_token_skip_obs "solc-StackTooDeep:dense-Map-cap8-pilot"
        rm -f "$build_log"
        exit 0
      fi
      echo "evm-token-anvil: Token EVM build failed (hard when tools present; profile=$expected_profile_wire)" >&2
      tail -40 "$build_log" >&2 || true
      rm -f "$build_log"
      exit 1
    fi
    rm -f "$build_log"
  else
    echo "evm-token-anvil: explicit skip: product CLI unavailable (optional adapter leg; not pass)" >&2
    write_token_skip_obs "missing-optional-tool:product-cli"
    exit 0
  fi
  token_bin="$token_out/Token.bin"
  [[ -f "$token_bin" ]] || {
    echo "evm-token-anvil: Token.bin missing after successful build (hard)" >&2
    exit 1
  }
  if ! token_tree_matches_profile "$token_bin"; then
    echo "evm-token-anvil: Token tree failed post-build profile validation (hard)" >&2
    exit 1
  fi
fi
echo "evm-token-anvil: engineering Token adapter smoke (mint/balanceOf/transfer/overflow-hold; profile=$expected_profile_wire); not formal; no OZ/family credit" >&2
export FOUNDRY_BIN="$(cd "$(dirname "$anvil_path")" && pwd)"
abi="$(dirname "$token_bin")/Token.abi.json"
if [[ ! -f "$abi" ]]; then
  echo "evm-token-anvil: missing ABI after build (hard)" >&2
  exit 1
fi
port=$((18545 + RANDOM % 1000))
anvil_log="$(mktemp "${TMPDIR:-/tmp}/pf-token-anvil.XXXXXX.log")"
create_err="$(mktemp "${TMPDIR:-/tmp}/pf-token-anvil-create.XXXXXX.err")"
cleanup_token() {
  kill "${anvil_pid:-}" 2>/dev/null || true
  rm -f "$anvil_log" "$create_err"
}
trap cleanup_token EXIT
if ((${#anvil_extra_args[@]})); then
  "$anvil_path" --port "$port" "${anvil_extra_args[@]}" --silent >"$anvil_log" 2>&1 &
else
  "$anvil_path" --port "$port" --silent >"$anvil_log" 2>&1 &
fi
anvil_pid=$!
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
  echo "evm-token-anvil: explicit skip: anvil failed to start (optional adapter; not pass; see $anvil_log)" >&2
  write_token_skip_obs "missing-optional-tool:anvil-start-failed"
  exit 0
fi
# Anvil default key
pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
# Deploy create
binhex=$(xxd -p -c 1000000 "$token_bin" | tr -d '\n')
# Token Map pilot bytecode can exceed Anvil/EIP-3860 initcode limits (~49KiB).
addr=$("$cast_path" send --rpc-url "$rpc" --private-key "$pk" --create "0x$binhex" --json 2>"$create_err" | /usr/bin/python3 -I -S -c 'import sys,json
try:
  print(json.load(sys.stdin).get("contractAddress",""))
except Exception:
  print("")' || true)
if [[ -z "$addr" || "$addr" == "null" ]]; then
  if grep -qiE 'initcode|max code|code size|oversized' "$create_err" 2>/dev/null; then
    echo "evm-token-anvil: explicit skip: bytecode exceeds Anvil create/initcode limit (Map pilot; adapter; not pass)" >&2
    write_token_skip_obs "anvil-initcode-limit:dense-Map-cap8-pilot"
    exit 0
  fi
  tx=$("$cast_path" send --rpc-url "$rpc" --private-key "$pk" --create "0x$binhex" 2>/dev/null | tail -1 || true)
  if [[ -n "${tx:-}" ]]; then
    addr=$("$cast_path" receipt --rpc-url "$rpc" "$tx" --json 2>/dev/null | /usr/bin/python3 -I -S -c 'import sys,json
try:
  print(json.load(sys.stdin).get("contractAddress",""))
except Exception:
  print("")' || true)
  fi
fi
if [[ -z "$addr" || "$addr" == "null" ]]; then
  if grep -qiE 'initcode|max code|code size|oversized|StackTooDeep' "$create_err" 2>/dev/null \
      || grep -qiE 'initcode|max code|code size|oversized' "$anvil_log" 2>/dev/null; then
    echo "evm-token-anvil: explicit skip: deploy initcode/create limit (Map pilot; adapter; not pass)" >&2
    write_token_skip_obs "anvil-deploy-limit:dense-Map-cap8-pilot"
    exit 0
  fi
  echo "evm-token-anvil: deploy failed (hard; see $anvil_log and $create_err)" >&2
  exit 1
fi
# Normalize cast call output to decimal UInt64 when possible.
to_dec() {
  local x="$1"
  x="${x//$'\n'/}"
  x="${x// /}"
  if [[ -z "$x" ]]; then echo ""; return; fi
  if [[ "$x" == 0x* || "$x" == 0X* ]]; then
    /usr/bin/python3 -I -S -c "print(int('$x', 16))" 2>/dev/null || echo "$x"
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

# Adapter corpus observations — all 9 steps (pass path; decimal-string UInts).
if [[ -n "$corpus_obs_dir" ]]; then
  mkdir -p "$corpus_obs_dir/$case_id"
  CORPUS_VALIDATOR="$root/scripts/evm_corpus_v1.py" \
  /usr/bin/python3 -I -S - "$corpus_obs_dir/$case_id" "$case_id" <<'PY'
import importlib.util, os, sys
from pathlib import Path
obs_dir, case_id = Path(sys.argv[1]), sys.argv[2]
spec = importlib.util.spec_from_file_location("evm_corpus_v1", os.environ["CORPUS_VALIDATOR"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def write(step, status, logical, ret, rollback):
    obs = {
        "schema": mod.SCHEMA_OBS,
        "caseId": case_id,
        "leg": "pf-anvil",
        "stepIndex": step,
        "verdict": "pass",
        "skipReason": None,
        "shared": {
            "status": status,
            "returnValue": ret,
            "logicalState": logical,
            "effects": [],
            "rollbackEqual": rollback,
        },
        "evm": {
            "balances": [
                {"id": "alice", "wei": "0"},
                {"id": "bob", "wei": "0"},
                {"id": "deployer", "wei": "0"},
            ],
            "calldata": "0x",
            "externalCalls": [],
            "logs": [],
            "returndata": "0x",
            "revertData": None if status == "success" else "0x",
            "storageSlots": [],
        },
    }
    mod.validate_observation(obs)
    path = obs_dir / f"pf-anvil-step-{step}.json"
    path.write_bytes(mod.dumps_canonical(obs))
    print(f"evm-token-anvil: wrote {path}", file=sys.stderr)

empty = {"balances": {}, "supply": "0"}
after_mint = {"balances": {"1": "100"}, "supply": "100"}
conserved = {"balances": {"1": "60", "2": "40"}, "supply": "100"}
write(0, "success", empty, None, True)
write(1, "success", after_mint, "100", True)
write(2, "success", after_mint, "100", True)
write(3, "success", after_mint, "100", True)
write(4, "success", conserved, True, True)
write(5, "success", conserved, "60", True)
write(6, "success", conserved, "40", True)
write(7, "revert", conserved, None, True)
write(8, "revert", conserved, None, True)
PY
fi

echo "evm-token-anvil: ok mint/transfer/balanceOf/overflow-hold on $addr (1→60, 2→40; adapter conservation)" >&2
echo "evm-token-anvil: engineering only; not formal Reference↔Anvil; no OZ/family/ABI credit"
