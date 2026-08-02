#!/usr/bin/env bash
# CosmWasm cosmwasm-check acceptance helper (engineering only; A2 Tool Lock lane).
#
# Layer 1 — tool fixture matrix (hand-written minimal ABI WAT):
#   wat2wasm → cosmwasm-check on:
#     positive: minimal_abi (allocate/deallocate/interface_version_8 + entry/query)
#     negative: missing interface_version_*, multi-memory, memory maximum set
#
# Layer 2 — product Counter (conditional):
#   If `proof-forge-next build --target cosmwasm` produces a .wasm under a
#   staging dir, run cosmwasm-check on it. When the product CosmWasm emitter is
#   absent (A1 not merged) or build fails, skip-clean with an explicit message.
#
# Exit codes:
#   0  — fixtures accepted / rejected as expected, product skipped or ok;
#        or required tools unavailable (skip with message)
#   1  — tools present but fixture matrix or product check failed
#   2  — usage / host error
#
# Not wasmd / cosmwasm-vm runtime / formal Stage-0 / hermetic Tool Lock verify.
# Float opcodes: cosmwasm-check 3.0.9 does not reject f32/f64 at static check
# (verified); third hard negative is memory-with-maximum instead.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_DIR="$ROOT/testdata/cosmwasm-check"
STAGING="${PROOF_FORGE_COSMWASM_CHECK_STAGING:-$ROOT/build/v2/cosmwasm-check-acceptance}"

usage() {
  echo "usage: $0" >&2
  echo "  (no args; uses repo testdata/cosmwasm-check fixtures)" >&2
  exit 2
}

[[ $# -eq 0 ]] || usage

platform_id() {
  local sys mach
  sys="$(uname -s | tr '[:upper:]' '[:lower:]')"
  mach="$(uname -m | tr '[:upper:]' '[:lower:]')"
  case "${sys}-${mach}" in
    darwin-arm64|darwin-aarch64) echo "darwin-arm64" ;;
    linux-x86_64|linux-amd64) echo "linux-x86_64" ;;
    *) echo "${sys}-${mach}" ;;
  esac
}

resolve_tool() {
  local name="$1"
  local plat cand
  plat="$(platform_id)"
  if [[ -n "${PROOF_FORGE_TOOL_ROOT:-}" && -x "${PROOF_FORGE_TOOL_ROOT%/}/$name" ]]; then
    echo "${PROOF_FORGE_TOOL_ROOT%/}/$name"
    return 0
  fi
  cand="${HOME}/.cache/proof-forge-v2/tool-root/${plat}/$name"
  if [[ -x "$cand" ]]; then
    echo "$cand"
    return 0
  fi
  # cargo-git provision cache under asset cache root (sourceBuild; not tool-root)
  # Default: $XDG_CACHE_HOME/proof-forge-v2/assets or ~/.cache/proof-forge-v2/assets
  if [[ "$name" == "cosmwasm-check" ]]; then
    local asset_root git_cache
    if [[ -n "${PROOF_FORGE_ASSET_CACHE:-}" ]]; then
      asset_root="${PROOF_FORGE_ASSET_CACHE}"
    elif [[ -n "${XDG_CACHE_HOME:-}" ]]; then
      asset_root="${XDG_CACHE_HOME}/proof-forge-v2/assets"
    else
      asset_root="${HOME}/.cache/proof-forge-v2/assets"
    fi
    git_cache="${asset_root}/cargo-git/fe5b55d283f5987c7fa0f95d5ad923be7a3d9283/cosmwasm-check-3.0.9-git-fe5b55d283f5/target/release/cosmwasm-check"
    if [[ -x "$git_cache" ]]; then
      echo "$git_cache"
      return 0
    fi
  fi
  if [[ -x "${HOME}/.cargo/bin/$name" ]]; then
    echo "${HOME}/.cargo/bin/$name"
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

if ! wat2wasm="$(resolve_tool wat2wasm)"; then
  echo "skipped: wat2wasm unavailable"
  exit 0
fi

if ! cwcheck="$(resolve_tool cosmwasm-check)"; then
  echo "skipped: cosmwasm-check unavailable"
  exit 0
fi

echo "cosmwasm-check-acceptance: wat2wasm=$wat2wasm"
echo "cosmwasm-check-acceptance: cosmwasm-check=$cwcheck"
"$wat2wasm" --version 2>&1 | head -1 || true
"$cwcheck" --version 2>&1 | head -1 || true

if [[ ! -d "$FIXTURE_DIR" ]]; then
  echo "cosmwasm-check-acceptance: missing fixture dir $FIXTURE_DIR" >&2
  exit 2
fi

rm -rf "$STAGING"
mkdir -p "$STAGING"
trap 'rm -rf "$STAGING"' EXIT

assemble() {
  # Usage: assemble <wat> <wasm> [extra wat2wasm flags...]
  # bash 3.2 + set -u: never expand an empty array with [@].
  local wat="$1"
  local wasm="$2"
  shift 2
  if [[ "$#" -gt 0 ]]; then
    if ! "$wat2wasm" "$@" "$wat" -o "$wasm" 2>"$STAGING/wat2wasm.err"; then
      echo "FAIL: wat2wasm rejected $wat" >&2
      cat "$STAGING/wat2wasm.err" >&2
      return 1
    fi
  else
    if ! "$wat2wasm" "$wat" -o "$wasm" 2>"$STAGING/wat2wasm.err"; then
      echo "FAIL: wat2wasm rejected $wat" >&2
      cat "$STAGING/wat2wasm.err" >&2
      return 1
    fi
  fi
  return 0
}

expect_pass() {
  local label="$1"
  local wasm="$2"
  echo "--- positive: $label"
  if ! out="$("$cwcheck" "$wasm" 2>&1)"; then
    echo "FAIL: cosmwasm-check rejected positive $label" >&2
    echo "$out" >&2
    return 1
  fi
  if ! grep -q 'pass' <<<"$out"; then
    echo "FAIL: positive $label missing pass marker" >&2
    echo "$out" >&2
    return 1
  fi
  echo "ok: $label passed cosmwasm-check"
  return 0
}

expect_fail() {
  local label="$1"
  local wasm="$2"
  local needle="$3"
  echo "--- negative: $label (expect reject)"
  set +e
  out="$("$cwcheck" "$wasm" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: cosmwasm-check accepted negative $label" >&2
    echo "$out" >&2
    return 1
  fi
  if [[ -n "$needle" ]] && ! grep -qiE "$needle" <<<"$out"; then
    echo "FAIL: negative $label exit $rc but missing expected diagnostic /$needle/" >&2
    echo "$out" >&2
    return 1
  fi
  echo "ok: $label rejected by cosmwasm-check (exit $rc)"
  return 0
}

failed=0

# Positive
if assemble "$FIXTURE_DIR/minimal_abi.wat" "$STAGING/minimal_abi.wasm"; then
  expect_pass "minimal_abi" "$STAGING/minimal_abi.wasm" || failed=1
else
  failed=1
fi

# Negative: missing interface_version_*
if assemble "$FIXTURE_DIR/missing_interface_version.wat" "$STAGING/missing_interface_version.wasm"; then
  expect_fail "missing_interface_version" "$STAGING/missing_interface_version.wasm" \
    'interface_version' || failed=1
else
  failed=1
fi

# Negative: multi-memory (requires multi-memory proposal flag for wat2wasm)
if assemble "$FIXTURE_DIR/multi_memory.wat" "$STAGING/multi_memory.wasm" \
    --enable-multi-memory; then
  expect_fail "multi_memory" "$STAGING/multi_memory.wasm" \
    'memory|memories|deserialize' || failed=1
else
  failed=1
fi

# Negative: memory maximum set (third hard negative; floats not rejected by 3.0.9)
if assemble "$FIXTURE_DIR/memory_with_maximum.wat" "$STAGING/memory_with_maximum.wasm"; then
  expect_fail "memory_with_maximum" "$STAGING/memory_with_maximum.wasm" \
    'maximum' || failed=1
else
  failed=1
fi

if [[ "$failed" -ne 0 ]]; then
  echo "cosmwasm-check-acceptance: fixture matrix failures" >&2
  exit 1
fi
echo "cosmwasm-check-acceptance: fixture matrix ok"

# ---------------------------------------------------------------------------
# Layer 2: product Counter (conditional; A1 CosmWasm emitter may be absent)
# ---------------------------------------------------------------------------
product_skip() {
  echo "skipped: product cosmwasm Counter check ($1)"
}

resolve_cli() {
  if [[ -n "${PROOF_FORGE_CLI:-}" && -x "${PROOF_FORGE_CLI}" ]]; then
    echo "$PROOF_FORGE_CLI"
    return 0
  fi
  local cand
  for cand in \
    "$ROOT/.lake/build/bin/proof-forge-next" \
    "$ROOT/build/bin/proof-forge-next"; do
    if [[ -x "$cand" ]]; then
      echo "$cand"
      return 0
    fi
  done
  if command -v proof-forge-next >/dev/null 2>&1; then
    command -v proof-forge-next
    return 0
  fi
  return 1
}

if ! cli="$(resolve_cli)"; then
  product_skip "proof-forge-next CLI not built"
  echo "cosmwasm-check-acceptance: ok (fixtures only)"
  exit 0
fi

PRODUCT_OUT="$STAGING/product-out"
rm -rf "$PRODUCT_OUT"
mkdir -p "$PRODUCT_OUT"

# Prefer Examples/Counter if present; otherwise skip product without failing.
COUNTER_SRC=""
for cand in \
  "$ROOT/Examples/Counter.lean" \
  "$ROOT/ProofForgeV2/Examples/Counter.lean"; do
  if [[ -f "$cand" ]]; then
    COUNTER_SRC="$cand"
    break
  fi
done

if [[ -z "$COUNTER_SRC" ]]; then
  product_skip "Counter example source missing"
  echo "cosmwasm-check-acceptance: ok (fixtures only)"
  exit 0
fi

# Product CLI: build <source.lean> --module <Name> --target <t> [-o <dir>]
# Module for Examples/Counter.lean is Examples.Counter (see Emit.lean docs).
module_name="Examples.Counter"
case "$COUNTER_SRC" in
  *ProofForgeV2/Examples/Counter.lean) module_name="ProofForgeV2.Examples.Counter" ;;
esac

set +e
build_out="$(
  cd "$ROOT" && "$cli" build \
    "$COUNTER_SRC" \
    --module "$module_name" \
    --target cosmwasm \
    -o "$PRODUCT_OUT" 2>&1
)"
build_rc=$?
set -e

if [[ "$build_rc" -ne 0 ]]; then
  product_skip "build --target cosmwasm failed (exit $build_rc; A1 emitter may be unmerged)"
  echo "$build_out" | head -20 || true
  echo "cosmwasm-check-acceptance: ok (fixtures only)"
  exit 0
fi

# Find any .wasm under product output (bash 3.2-safe: no mapfile).
product_wasms=()
while IFS= read -r line; do
  [[ -n "$line" ]] && product_wasms+=("$line")
done < <(find "$PRODUCT_OUT" -type f -name '*.wasm' | sort)

if [[ "${#product_wasms[@]}" -eq 0 ]]; then
  # Some emitters ship .wat only; assemble first when present.
  product_wats=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && product_wats+=("$line")
  done < <(find "$PRODUCT_OUT" -type f -name '*.wat' | sort)
  if [[ "${#product_wats[@]}" -eq 0 ]]; then
    product_skip "no .wasm/.wat in product output"
    echo "cosmwasm-check-acceptance: ok (fixtures only)"
    exit 0
  fi
  for wat in "${product_wats[@]}"; do
    wasm="${wat%.wat}.wasm"
    if ! "$wat2wasm" "$wat" -o "$wasm" 2>"$STAGING/product-wat2wasm.err"; then
      echo "FAIL: product wat2wasm rejected $wat" >&2
      cat "$STAGING/product-wat2wasm.err" >&2
      exit 1
    fi
    product_wasms+=("$wasm")
  done
fi

for wasm in "${product_wasms[@]}"; do
  echo "--- product: $wasm"
  if ! out="$("$cwcheck" "$wasm" 2>&1)"; then
    echo "FAIL: cosmwasm-check rejected product artifact $wasm" >&2
    echo "$out" >&2
    exit 1
  fi
  echo "ok: product artifact passed cosmwasm-check ($wasm)"
done

echo "cosmwasm-check-acceptance: ok (fixtures + product)"
exit 0
