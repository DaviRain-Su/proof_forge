#!/usr/bin/env bash
# Psy dargo v0.1.0 local VM / base-proof engineering runtime lane.
#
# Independent host-heavy recipe (NOT ordinary ci):
#   product CLI build Counter + explicit-profile WideCounter → inspect closure →
#   wrap each `.psy` as a Dargo project → compile / generate-abi →
#   execute UInt64 happy/overflow and UInt128 carry/borrow/multiply/divide/remainder/
#   compare/overflow/zero-divisor paths.
#
# Locked tool contract (never PATH fallback):
#   $PROOF_FORGE_TOOL_ROOT/dargo
#   $PROOF_FORGE_TOOL_ROOT/lib/psy-std/std.psy
# Platform paths supported only:
#   linux-x86_64 | darwin-arm64
# Engineering runtime label:
#   psy-dargo-0.1.0-local-proof-v1
# Product default remains psy-dargo-u64-v1; UInt128 uses the explicit
# psy-dargo-0.1.0-vm-v1 profile and does not change default semantics.
#
# Hard-fails with PF-TOOLCHAIN-MISSING when locked dargo/std are absent.
# Proprietary Psy toolchain is dev/test-only; no redistribution, no network/UPS,
# no formal/hermetic/deploy claim. Product Finalize remains zero-tool
# deployable=false; this lane is external to product finalize.
#
# Exit codes:
#   0 success
#   1 product / dargo / assert failure
#   2 missing tools / unsupported host / usage (PF-TOOLCHAIN-MISSING)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="psy-runtime-test"
PROFILE_LABEL="psy-dargo-0.1.0-local-proof-v1"
# Local VM execute can build/prove several circuits; keep bounded.
# Restoring UInt128 div/mod local base-proof is heavier than add/mul; allow override.
EXECUTE_TIMEOUT_SEC="${PSY_RUNTIME_EXECUTE_TIMEOUT:-300}"
OUTPUT_BYTES_CAP="${PSY_RUNTIME_OUTPUT_BYTES_CAP:-2097152}"

die() {
  echo "${PREFIX}: $*" >&2
  exit 1
}

missing() {
  echo "${PREFIX}: PF-TOOLCHAIN-MISSING: $*" >&2
  exit 2
}

usage_err() {
  echo "${PREFIX}: $*" >&2
  exit 2
}

if ! [[ "$EXECUTE_TIMEOUT_SEC" =~ ^[1-9][0-9]*$ ]] || \
    (( EXECUTE_TIMEOUT_SEC > 3600 )); then
  usage_err "PSY_RUNTIME_EXECUTE_TIMEOUT must be an integer in 1..3600"
fi
if ! [[ "$OUTPUT_BYTES_CAP" =~ ^[1-9][0-9]*$ ]] || \
    (( OUTPUT_BYTES_CAP > 67108864 )); then
  usage_err "PSY_RUNTIME_OUTPUT_BYTES_CAP must be an integer in 1..67108864"
fi
OUTPUT_FILE_BLOCKS=$(( (OUTPUT_BYTES_CAP + 1023) / 1024 ))

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    platform_id="linux-x86_64"
    psy_asset_id="psy-compiler-0.1.0-x86_64-unknown-linux-gnu"
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-x86_64"
    ;;
  Darwin-arm64)
    platform_id="darwin-arm64"
    psy_asset_id="psy-compiler-0.1.0-aarch64-apple-darwin"
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"
    ;;
  *)
    missing "unsupported host platform $(uname -s)-$(uname -m) (only linux-x86_64 and darwin-arm64)"
    ;;
esac

export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"
TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT%/}"
DARGO="${TOOL_ROOT}/dargo"
STD="${TOOL_ROOT}/lib/psy-std/std.psy"

if [[ ! -x "$DARGO" ]]; then
  missing "locked dargo not executable at $DARGO (platform=$platform_id; never falls back to PATH)"
fi
if [[ ! -f "$STD" ]]; then
  missing "locked psy-std not found at $STD (platform=$platform_id; never falls back to PATH)"
fi

verify_log=""
if ! verify_log="$(/usr/bin/python3 -I -S scripts/toolchain_assets.py \
    verify-asset-members --asset "$psy_asset_id" --root "$TOOL_ROOT" 2>&1)"; then
  printf '%s\n' "$verify_log" >&2
  missing "Psy Tool Lock exact-member verification failed for $TOOL_ROOT"
fi
printf '%s\n' "$verify_log"

if ! command -v lake >/dev/null 2>&1; then
  usage_err "lake not on PATH (required to build proof-forge-next)"
fi
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="$(command -v timeout)"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="$(command -v gtimeout)"
else
  usage_err "timeout(1) or gtimeout(1) required for bounded dargo execute"
fi
[[ "$TIMEOUT_BIN" == /* && -x "$TIMEOUT_BIN" ]] || \
  usage_err "resolved timeout tool is not an absolute executable: $TIMEOUT_BIN"

cli="$root/.lake/build/bin/proof-forge-next"
out_parent="$root/build/v2"
mkdir -p "$out_parent" || die "cannot create runtime staging parent $out_parent"
out_dir="$(mktemp -d "$out_parent/psy-runtime.XXXXXX")" || \
  die "cannot create unique runtime staging under $out_parent"
dargo_project="${out_dir}/dargo-counter"
wide_dargo_project="${out_dir}/dargo-wide-counter"
log_dir="${out_dir}/logs"

cleanup() {
  # `out_dir` is a unique mktemp child of the package-owned build/v2 parent.
  if [[ "${PSY_RUNTIME_KEEP_STAGING:-}" != "1" ]]; then
    rm -rf -- "$out_dir"
  fi
}
trap cleanup EXIT

echo "${PREFIX}: engineering dargo local VM/base-proof lane (${PROFILE_LABEL})"
echo "${PREFIX}: platform=${platform_id} tool_root=${TOOL_ROOT}"
echo "${PREFIX}: dargo=${DARGO}"
echo "${PREFIX}: DARGO_STD_PATH=${STD}"
dargo_version="$("$DARGO" --version 2>&1)" || die "locked dargo --version failed"
dargo_first_line="$(printf '%s\n' "$dargo_version" | head -n 1)"
[[ "$dargo_first_line" == "dargo 0.1.0" ]] || \
  die "locked dargo version mismatch: expected 'dargo 0.1.0', got '$dargo_first_line'"
echo "$dargo_first_line"

echo "${PREFIX}: building proof-forge-next (lake build proof_forge_next)"
lake build proof_forge_next || die "lake build proof_forge_next failed"
[[ -x "$cli" ]] || die "CLI missing after build: $cli"

# CLI rejects pre-existing -o paths (PF-OUTPUT-COLLISION); the unique staging
# root exists, but its `product` child does not.
mkdir -p "$log_dir" "$dargo_project/src" "$wide_dargo_project/src"

echo "${PREFIX}: product build Examples/Counter.lean --target psy"
if ! "$cli" build Examples/Counter.lean \
    --module Examples.Counter \
    --target psy \
    -o "$out_dir/product" \
    >"$log_dir/product-build.log" 2>&1; then
  cat "$log_dir/product-build.log" >&2 || true
  die "proof-forge-next build --target psy failed"
fi

[[ -f "$out_dir/product/Counter.psy" ]] || die "missing product Counter.psy"
[[ -f "$out_dir/product/manifest.json" ]] || die "missing product manifest.json"
[[ -f "$out_dir/product/evidence.json" ]] || die "missing product evidence.json"

echo "${PREFIX}: inspect exact output closure"
if ! "$cli" inspect "$out_dir/product" >"$log_dir/inspect.log" 2>&1; then
  cat "$log_dir/inspect.log" >&2 || true
  die "proof-forge-next inspect failed"
fi
if ! grep -q 'exact-disk-closure' "$log_dir/inspect.log"; then
  cat "$log_dir/inspect.log" >&2 || true
  die "inspect log missing exact-disk-closure marker"
fi

# Wrap product source as a minimal Dargo project (product emits sole Counter.psy).
cat >"$dargo_project/Dargo.toml" <<'EOF'
[package]
name = "counter"
type = "bin"
authors = ["proof-forge-next"]

[dependencies]
EOF
cp -f "$out_dir/product/Counter.psy" "$dargo_project/src/main.psy"

export DARGO_STD_PATH="$STD"
# Product CLI may spawn the package Lean toolchain; preserve its original PATH
# for later product builds. Dargo itself still runs with a minimal PATH and an
# absolute locked executable.
BUILD_PATH="$PATH"
export PATH="/usr/bin:/bin"

run_dargo_in() {
  local project="$1"
  shift
  local label="$1"
  shift
  local log="$log_dir/${label}.log"
  local ec=0
  # Enforce the file-size ceiling while the process runs; post-run byte checks
  # remain as a second defense. Bash `ulimit -f` uses 1024-byte blocks.
  set +e
  (
    cd "$project" || exit 125
    ulimit -f "$OUTPUT_FILE_BLOCKS" || exit 125
    "$TIMEOUT_BIN" "${EXECUTE_TIMEOUT_SEC}" "$DARGO" "$@"
  ) >"$log" 2>&1
  ec=$?
  set -e
  local bytes
  bytes="$(wc -c <"$log" | tr -d ' ')"
  if [[ "$bytes" -gt "$OUTPUT_BYTES_CAP" ]]; then
    die "dargo $* output exceeded ${OUTPUT_BYTES_CAP} bytes ($bytes)"
  fi
  if [[ "$ec" -eq 124 ]]; then
    die "dargo $* timed out after ${EXECUTE_TIMEOUT_SEC}s (see $log)"
  fi
  if [[ "$ec" -ne 0 ]]; then
    # Checked-failure executes are expected non-zero; callers inspect exact logs.
    return "$ec"
  fi
  return 0
}

run_dargo() {
  run_dargo_in "$dargo_project" "$@"
}

run_wide_dargo() {
  run_dargo_in "$wide_dargo_project" "$@"
}

echo "${PREFIX}: dargo compile --contract-name Counter"
run_dargo compile compile --contract-name Counter \
  || { cat "$log_dir/compile.log" >&2 || true; die "dargo compile failed"; }

echo "${PREFIX}: dargo generate-abi --contract-name Counter"
run_dargo generate-abi generate-abi --contract-name Counter \
  || { cat "$log_dir/generate-abi.log" >&2 || true; die "dargo generate-abi failed"; }

abi_json="$dargo_project/target/Counter.abi.json"
pkg_json="$dargo_project/target/counter.json"
[[ -f "$abi_json" && -s "$abi_json" ]] || die "missing/empty $abi_json"
[[ -f "$pkg_json" && -s "$pkg_json" ]] || die "missing/empty package json $pkg_json"
echo "${PREFIX}: abi=$(wc -c <"$abi_json" | tr -d ' ')B package_json=$(wc -c <"$pkg_json" | tr -d ' ')B"

echo "${PREFIX}: happy execute initialize(5)/increment(3)/get → 8"
happy_ec=0
run_dargo execute-happy execute \
  --contract-name Counter \
  --method-names initialize \
  --method-names increment \
  --method-names get \
  --parameters 5 \
  --parameters 3 || happy_ec=$?
if [[ "$happy_ec" -ne 0 ]]; then
  cat "$log_dir/execute-happy.log" >&2 || true
  die "dargo execute happy path failed (exit $happy_ec)"
fi
happy_log="$log_dir/execute-happy.log"

# Observable structure only — do not pin random public_inputs values or timestamps.
for method in initialize increment get; do
  if ! grep -qE "circuit_stats[[:space:]]+method=${method}([[:space:]]|$)" "$happy_log"; then
    cat "$happy_log" >&2 || true
    die "happy execute missing circuit_stats method=${method}"
  fi
done

# Portable line collect (bash 3.2 on Darwin has no mapfile).
result_vm_count=0
result_vm_seq=""
while IFS= read -r line; do
  val="${line#result_vm:}"
  val="${val#"${val%%[![:space:]]*}"}"
  result_vm_count=$((result_vm_count + 1))
  if [[ -n "$result_vm_seq" ]]; then
    result_vm_seq="${result_vm_seq}|${val}"
  else
    result_vm_seq="$val"
  fi
done < <(grep -E '^result_vm:' "$happy_log" || true)

result_events_count=0
result_events_bad=0
while IFS= read -r line; do
  val="${line#result_events:}"
  val="${val#"${val%%[![:space:]]*}"}"
  result_events_count=$((result_events_count + 1))
  if [[ "$val" != "[]" ]]; then
    result_events_bad=1
  fi
done < <(grep -E '^result_events:' "$happy_log" || true)

public_inputs_count="$(grep -cE '^public_inputs:' "$happy_log" || true)"

if [[ "$result_vm_count" -ne 3 ]]; then
  cat "$happy_log" >&2 || true
  die "happy execute expected 3 result_vm lines, got ${result_vm_count}"
fi
if [[ "$result_vm_seq" != "[]|[8]|[8]" ]]; then
  cat "$happy_log" >&2 || true
  die "happy execute result_vm sequence want [], [8], [8]; got ${result_vm_seq}"
fi
if [[ "$result_events_count" -ne 3 || "$result_events_bad" -ne 0 ]]; then
  cat "$happy_log" >&2 || true
  die "happy execute expected 3 empty result_events lines, got count=${result_events_count} bad=${result_events_bad}"
fi
if [[ "$public_inputs_count" -ne 3 ]]; then
  cat "$happy_log" >&2 || true
  die "happy execute expected exactly 3 public_inputs lines, got ${public_inputs_count}"
fi
echo "${PREFIX}: happy path observables ok (result_vm [], [8], [8]; 3 public_inputs; events empty)"

echo "${PREFIX}: overflow execute initialize(p-1)/increment(1)"
# Goldilocks p-1 = 2^64 - 2^32 = 18446744069414584320
ovf_ec=0
run_dargo execute-overflow execute \
  --contract-name Counter \
  --method-names initialize \
  --method-names increment \
  --parameters 18446744069414584320 \
  --parameters 1 || ovf_ec=$?
ovf_log="$log_dir/execute-overflow.log"
if [[ "$ovf_ec" -eq 0 ]]; then
  cat "$ovf_log" >&2 || true
  die "overflow execute unexpectedly succeeded"
fi
if ! grep -q 'assertion failed: u64 add overflow' "$ovf_log"; then
  cat "$ovf_log" >&2 || true
  die "overflow execute missing exact 'assertion failed: u64 add overflow'"
fi
# Local VM assert trap only — do not claim full-state rollback snapshot parity.
echo "${PREFIX}: overflow assert ok (nonzero exit + exact message; no rollback-snapshot claim)"

# ---------------------------------------------------------------------------
# Explicit dargo-v0.1.0 VM profile: UInt128 = 4×UInt32 little-endian Felt limbs.
# ---------------------------------------------------------------------------
wide_product="$out_dir/wide-product"
echo "${PREFIX}: product build Examples/WideCounter.lean --target psy --profile psy-dargo-0.1.0-vm-v1"
if ! PATH="$BUILD_PATH" "$cli" build Examples/WideCounter.lean \
    --module Examples.WideCounter \
    --target psy \
    --profile psy-dargo-0.1.0-vm-v1 \
    -o "$wide_product" \
    >"$log_dir/wide-product-build.log" 2>&1; then
  cat "$log_dir/wide-product-build.log" >&2 || true
  die "proof-forge-next WideCounter VM-profile build failed"
fi

[[ -f "$wide_product/WideCounter.psy" ]] || die "missing product WideCounter.psy"
[[ -f "$wide_product/manifest.json" ]] || die "missing WideCounter manifest.json"
[[ -f "$wide_product/evidence.json" ]] || die "missing WideCounter evidence.json"
if ! grep -q '"codegenProfile": "psy-dargo-0.1.0-vm-v1"' \
    "$wide_product/manifest.json"; then
  die "WideCounter manifest is not bound to psy-dargo-0.1.0-vm-v1"
fi

if ! PATH="$BUILD_PATH" "$cli" inspect "$wide_product" >"$log_dir/wide-inspect.log" 2>&1; then
  cat "$log_dir/wide-inspect.log" >&2 || true
  die "proof-forge-next inspect WideCounter failed"
fi
if ! grep -q 'exact-disk-closure' "$log_dir/wide-inspect.log"; then
  cat "$log_dir/wide-inspect.log" >&2 || true
  die "WideCounter inspect log missing exact-disk-closure marker"
fi

cat >"$wide_dargo_project/Dargo.toml" <<'EOF'
[package]
name = "wide_counter"
type = "bin"
authors = ["proof-forge-next"]

[dependencies]
EOF
cp -f "$wide_product/WideCounter.psy" "$wide_dargo_project/src/main.psy"

echo "${PREFIX}: dargo compile/generate-abi WideCounter"
run_wide_dargo wide-compile compile --contract-name WideCounter \
  || { cat "$log_dir/wide-compile.log" >&2 || true; die "WideCounter dargo compile failed"; }
run_wide_dargo wide-generate-abi generate-abi --contract-name WideCounter \
  || { cat "$log_dir/wide-generate-abi.log" >&2 || true; die "WideCounter dargo generate-abi failed"; }
[[ -s "$wide_dargo_project/target/WideCounter.abi.json" ]] || \
  die "missing/empty WideCounter ABI"
[[ -s "$wide_dargo_project/target/wide_counter.json" ]] || \
  die "missing/empty WideCounter package json"

# Carry across the low limb: (2^32−1) + 1 = [0,1,0,0]. Dargo groups one
# method's parameters as one comma-separated --parameters value.
echo "${PREFIX}: UInt128 carry execute (2^32-1)+1"
wide_carry_ec=0
run_wide_dargo wide-execute-carry execute \
  --contract-name WideCounter \
  --method-names initialize \
  --method-names add \
  --method-names get \
  --parameters 4294967295,0,0,0 \
  --parameters 1,0,0,0 || wide_carry_ec=$?
if [[ "$wide_carry_ec" -ne 0 ]]; then
  cat "$log_dir/wide-execute-carry.log" >&2 || true
  die "WideCounter carry execute failed (exit $wide_carry_ec)"
fi
wide_carry_seq=""
wide_carry_count=0
while IFS= read -r line; do
  val="${line#result_vm:}"
  val="${val#"${val%%[![:space:]]*}"}"
  wide_carry_count=$((wide_carry_count + 1))
  if [[ -n "$wide_carry_seq" ]]; then
    wide_carry_seq="${wide_carry_seq}|${val}"
  else
    wide_carry_seq="$val"
  fi
done < <(grep -E '^result_vm:' "$log_dir/wide-execute-carry.log" || true)
if [[ "$wide_carry_count" -ne 3 || \
    "$wide_carry_seq" != "[]|[0, 1, 0, 0]|[0, 1, 0, 0]" ]]; then
  cat "$log_dir/wide-execute-carry.log" >&2 || true
  die "WideCounter carry observables mismatch: count=$wide_carry_count seq=$wide_carry_seq"
fi
if [[ "$(grep -cE '^result_events: \[\]$' "$log_dir/wide-execute-carry.log" || true)" -ne 3 || \
    "$(grep -cE '^public_inputs:' "$log_dir/wide-execute-carry.log" || true)" -ne 3 ]]; then
  cat "$log_dir/wide-execute-carry.log" >&2 || true
  die "WideCounter carry expected 3 empty events and 3 public_inputs lines"
fi

# Borrow across the low limb plus unsigned comparison:
# 2^32 - 1 = [4294967295,0,0,0], and result <= same bound is true.
echo "${PREFIX}: UInt128 borrow/compare execute"
wide_borrow_ec=0
run_wide_dargo wide-execute-borrow execute \
  --contract-name WideCounter \
  --method-names initialize \
  --method-names subtract \
  --method-names leq \
  --method-names get \
  --parameters 0,1,0,0 \
  --parameters 1,0,0,0 \
  --parameters 4294967295,0,0,0 || wide_borrow_ec=$?
if [[ "$wide_borrow_ec" -ne 0 ]]; then
  cat "$log_dir/wide-execute-borrow.log" >&2 || true
  die "WideCounter borrow/compare execute failed (exit $wide_borrow_ec)"
fi
wide_borrow_seq=""
wide_borrow_count=0
while IFS= read -r line; do
  val="${line#result_vm:}"
  val="${val#"${val%%[![:space:]]*}"}"
  wide_borrow_count=$((wide_borrow_count + 1))
  if [[ -n "$wide_borrow_seq" ]]; then
    wide_borrow_seq="${wide_borrow_seq}|${val}"
  else
    wide_borrow_seq="$val"
  fi
done < <(grep -E '^result_vm:' "$log_dir/wide-execute-borrow.log" || true)
if [[ "$wide_borrow_count" -ne 4 || \
    "$wide_borrow_seq" != "[]|[4294967295, 0, 0, 0]|[1]|[4294967295, 0, 0, 0]" ]]; then
  cat "$log_dir/wide-execute-borrow.log" >&2 || true
  die "WideCounter borrow/compare observables mismatch: count=$wide_borrow_count seq=$wide_borrow_seq"
fi
if [[ "$(grep -cE '^result_events: \[\]$' "$log_dir/wide-execute-borrow.log" || true)" -ne 4 || \
    "$(grep -cE '^public_inputs:' "$log_dir/wide-execute-borrow.log" || true)" -ne 4 ]]; then
  cat "$log_dir/wide-execute-borrow.log" >&2 || true
  die "WideCounter borrow expected 4 empty events and 4 public_inputs lines"
fi

# Exact 8×UInt16 schoolbook: (2^32−1)^2 = [1,2^32−2,0,0].
echo "${PREFIX}: UInt128 multiply execute (2^32-1)^2"
wide_mul_ec=0
run_wide_dargo wide-execute-mul execute \
  --contract-name WideCounter \
  --method-names initialize \
  --method-names multiply \
  --method-names get \
  --parameters 4294967295,0,0,0 \
  --parameters 4294967295,0,0,0 || wide_mul_ec=$?
if [[ "$wide_mul_ec" -ne 0 ]]; then
  cat "$log_dir/wide-execute-mul.log" >&2 || true
  die "WideCounter multiply execute failed (exit $wide_mul_ec)"
fi
wide_mul_seq=""
wide_mul_count=0
while IFS= read -r line; do
  val="${line#result_vm:}"
  val="${val#"${val%%[![:space:]]*}"}"
  wide_mul_count=$((wide_mul_count + 1))
  if [[ -n "$wide_mul_seq" ]]; then
    wide_mul_seq="${wide_mul_seq}|${val}"
  else
    wide_mul_seq="$val"
  fi
done < <(grep -E '^result_vm:' "$log_dir/wide-execute-mul.log" || true)
if [[ "$wide_mul_count" -ne 3 || \
    "$wide_mul_seq" != "[]|[1, 4294967294, 0, 0]|[1, 4294967294, 0, 0]" ]]; then
  cat "$log_dir/wide-execute-mul.log" >&2 || true
  die "WideCounter multiply observables mismatch: count=$wide_mul_count seq=$wide_mul_seq"
fi
if [[ "$(grep -cE '^result_events: \[\]$' "$log_dir/wide-execute-mul.log" || true)" -ne 3 || \
    "$(grep -cE '^public_inputs:' "$log_dir/wide-execute-mul.log" || true)" -ne 3 ]]; then
  cat "$log_dir/wide-execute-mul.log" >&2 || true
  die "WideCounter multiply expected 3 empty events and 3 public_inputs lines"
fi

# Exact restoring unsigned div/mod on a multi-limb oracle vector.
# dividend = 0xfedcba98765432100123456789abcdef
# divisor  = 0x000000001234567800000001fedcba99
# quotient = 0x00000000000000000000000e00000077
# remainder= 0x000000000000002c1111110c11111150
echo "${PREFIX}: UInt128 divide execute (mixed multi-limb)"
wide_div_ec=0
run_wide_dargo wide-execute-div execute \
  --contract-name WideCounter \
  --method-names initialize \
  --method-names divide \
  --method-names get \
  --parameters 2309737967,19088743,1985229328,4275878552 \
  --parameters 4275878553,1,305419896,0 || wide_div_ec=$?
if [[ "$wide_div_ec" -ne 0 ]]; then
  cat "$log_dir/wide-execute-div.log" >&2 || true
  die "WideCounter divide execute failed (exit $wide_div_ec)"
fi
wide_div_seq=""
wide_div_count=0
while IFS= read -r line; do
  val="${line#result_vm:}"
  val="${val#"${val%%[![:space:]]*}"}"
  wide_div_count=$((wide_div_count + 1))
  if [[ -n "$wide_div_seq" ]]; then
    wide_div_seq="${wide_div_seq}|${val}"
  else
    wide_div_seq="$val"
  fi
done < <(grep -E '^result_vm:' "$log_dir/wide-execute-div.log" || true)
if [[ "$wide_div_count" -ne 3 || \
    "$wide_div_seq" != "[]|[119, 14, 0, 0]|[119, 14, 0, 0]" ]]; then
  cat "$log_dir/wide-execute-div.log" >&2 || true
  die "WideCounter divide observables mismatch: count=$wide_div_count seq=$wide_div_seq"
fi

echo "${PREFIX}: UInt128 remainder execute (mixed multi-limb)"
wide_rem_ec=0
run_wide_dargo wide-execute-rem execute \
  --contract-name WideCounter \
  --method-names initialize \
  --method-names remainder \
  --method-names get \
  --parameters 2309737967,19088743,1985229328,4275878552 \
  --parameters 4275878553,1,305419896,0 || wide_rem_ec=$?
if [[ "$wide_rem_ec" -ne 0 ]]; then
  cat "$log_dir/wide-execute-rem.log" >&2 || true
  die "WideCounter remainder execute failed (exit $wide_rem_ec)"
fi
wide_rem_seq=""
wide_rem_count=0
while IFS= read -r line; do
  val="${line#result_vm:}"
  val="${val#"${val%%[![:space:]]*}"}"
  wide_rem_count=$((wide_rem_count + 1))
  if [[ -n "$wide_rem_seq" ]]; then
    wide_rem_seq="${wide_rem_seq}|${val}"
  else
    wide_rem_seq="$val"
  fi
done < <(grep -E '^result_vm:' "$log_dir/wide-execute-rem.log" || true)
if [[ "$wide_rem_count" -ne 3 || \
    "$wide_rem_seq" != "[]|[286331088, 286330908, 44, 0]|[286331088, 286330908, 44, 0]" ]]; then
  cat "$log_dir/wide-execute-rem.log" >&2 || true
  die "WideCounter remainder observables mismatch: count=$wide_rem_count seq=$wide_rem_seq"
fi

# Checked negatives: full-width overflow/underflow/multiplication and physical limb range.
wide_overflow_ec=0
run_wide_dargo wide-execute-overflow execute \
  --contract-name WideCounter \
  --method-names initialize \
  --method-names add \
  --parameters 4294967295,4294967295,4294967295,4294967295 \
  --parameters 1,0,0,0 || wide_overflow_ec=$?
if [[ "$wide_overflow_ec" -eq 0 ]] || \
    ! grep -q 'assertion failed: u128 add overflow' "$log_dir/wide-execute-overflow.log"; then
  cat "$log_dir/wide-execute-overflow.log" >&2 || true
  die "WideCounter UInt128 add overflow did not fail with the exact message"
fi

wide_mul_overflow_ec=0
run_wide_dargo wide-execute-mul-overflow execute \
  --contract-name WideCounter \
  --method-names initialize \
  --method-names multiply \
  --parameters 4294967295,4294967295,4294967295,4294967295 \
  --parameters 2,0,0,0 || wide_mul_overflow_ec=$?
if [[ "$wide_mul_overflow_ec" -eq 0 ]] || \
    ! grep -q 'assertion failed: u128 mul overflow' "$log_dir/wide-execute-mul-overflow.log"; then
  cat "$log_dir/wide-execute-mul-overflow.log" >&2 || true
  die "WideCounter UInt128 multiplication overflow did not fail with the exact message"
fi

wide_underflow_ec=0
run_wide_dargo wide-execute-underflow execute \
  --contract-name WideCounter \
  --method-names initialize \
  --method-names subtract \
  --parameters 0,0,0,0 \
  --parameters 1,0,0,0 || wide_underflow_ec=$?
if [[ "$wide_underflow_ec" -eq 0 ]] || \
    ! grep -q 'assertion failed: u128 sub underflow' "$log_dir/wide-execute-underflow.log"; then
  cat "$log_dir/wide-execute-underflow.log" >&2 || true
  die "WideCounter UInt128 underflow did not fail with the exact message"
fi

wide_div_zero_ec=0
run_wide_dargo wide-execute-div-zero execute \
  --contract-name WideCounter \
  --method-names initialize \
  --method-names divide \
  --parameters 123,0,0,0 \
  --parameters 0,0,0,0 || wide_div_zero_ec=$?
if [[ "$wide_div_zero_ec" -eq 0 ]] || \
    ! grep -q 'assertion failed: u128 div by zero' "$log_dir/wide-execute-div-zero.log"; then
  cat "$log_dir/wide-execute-div-zero.log" >&2 || true
  die "WideCounter UInt128 div-by-zero did not fail with the exact message"
fi

wide_mod_zero_ec=0
run_wide_dargo wide-execute-mod-zero execute \
  --contract-name WideCounter \
  --method-names initialize \
  --method-names remainder \
  --parameters 123,0,0,0 \
  --parameters 0,0,0,0 || wide_mod_zero_ec=$?
if [[ "$wide_mod_zero_ec" -eq 0 ]] || \
    ! grep -q 'assertion failed: u128 mod by zero' "$log_dir/wide-execute-mod-zero.log"; then
  cat "$log_dir/wide-execute-mod-zero.log" >&2 || true
  die "WideCounter UInt128 mod-by-zero did not fail with the exact message"
fi

wide_range_ec=0
run_wide_dargo wide-execute-range execute \
  --contract-name WideCounter \
  --method-names initialize \
  --parameters 4294967296,0,0,0 || wide_range_ec=$?
if [[ "$wide_range_ec" -eq 0 ]] || \
    ! grep -q 'assertion failed: u32 param out of range' "$log_dir/wide-execute-range.log"; then
  cat "$log_dir/wide-execute-range.log" >&2 || true
  die "WideCounter out-of-range limb did not fail with the exact UInt32 ABI message"
fi

echo "${PREFIX}: UInt128 VM observables ok (carry/borrow/multiply/divide/remainder/compare + checked negatives)"
echo "${PREFIX}: ok (${PROFILE_LABEL}; engineering only; not formal/hermetic/deploy)"
exit 0
