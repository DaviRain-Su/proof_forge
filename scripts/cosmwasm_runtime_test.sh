#!/usr/bin/env bash
# CosmWasm engineering mock-runtime differential:
#   product CLI build → .wasm (wat2wasm finalize) → cosmwasm-vm 3.0.9 cargo tests.
#
# Covers Counter / Accumulator / EventFlow under cosmwasm-vm MockStorage/Api/Querier.
# Not wasmd, not formal Stage-0 / hermetic release evidence / CI-registered shard
# (main agent decides just recipe wiring).
#
# Requires:
#   - lake / Lean toolchain on PATH
#   - cargo / rustc on PATH
#   - wat2wasm (PROOF_FORGE_TOOL_ROOT or default tool-root / PATH) for finalize
#
# Exit codes:
#   0 success
#   1 product / cargo test failure
#   2 missing tools / usage (skip-clean when tools absent)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

die() {
  echo "cosmwasm-runtime-test: $*" >&2
  exit 1
}

missing() {
  echo "cosmwasm-runtime-test: skipped: $*" >&2
  exit 2
}

skip_clean() {
  echo "cosmwasm-runtime-test: skipped: $*" >&2
  exit 0
}

case "$(uname -s)" in
  Darwin)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"
    ;;
  Linux)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)"
    ;;
  *)
    missing "unsupported host platform: $(uname -s)"
    ;;
esac

export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"

resolve_tool() {
  local name="$1"
  if [[ -n "${PROOF_FORGE_TOOL_ROOT:-}" && -x "${PROOF_FORGE_TOOL_ROOT%/}/$name" ]]; then
    echo "${PROOF_FORGE_TOOL_ROOT%/}/$name"
    return 0
  fi
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
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
  return 1
}

if ! command -v lake >/dev/null 2>&1; then
  skip_clean "lake not on PATH"
fi
if ! command -v cargo >/dev/null 2>&1; then
  skip_clean "cargo not on PATH (install Rust toolchain)"
fi
if ! wat2wasm="$(resolve_tool wat2wasm)"; then
  skip_clean "wat2wasm unavailable (set PROOF_FORGE_TOOL_ROOT or install wabt)"
fi

cli="$root/.lake/build/bin/proof-forge-next"
out_dir="${PROOF_FORGE_RUNTIME_OUT:-$root/build/v2/cosmwasm-runtime}"
crate_dir="$root/runtime-tests/cosmwasm"
fixtures_src="$root/runtime-tests/cosmwasm/fixtures"

# Product examples + local fixtures (source stem == program name == artifact stem).
programs=(
  "Examples/Counter.lean:Examples.Counter:Counter"
  "Examples/Accumulator.lean:Examples.Accumulator:Accumulator"
  "runtime-tests/cosmwasm/fixtures/EventFlow.lean:Examples.EventFlow:EventFlow"
  "runtime-tests/cosmwasm/fixtures/IntMul.lean:Examples.IntMul:IntMul"
  "runtime-tests/cosmwasm/fixtures/EmitLoop.lean:Examples.EmitLoop:EmitLoop"
  "runtime-tests/cosmwasm/fixtures/ScheduleFlow.lean:Examples.ScheduleFlow:ScheduleFlow"
  "runtime-tests/cosmwasm/fixtures/PairRet.lean:Examples.PairRet:PairRet"
  "runtime-tests/cosmwasm/fixtures/ArrayRet.lean:Examples.ArrayRet:ArrayRet"
  "runtime-tests/cosmwasm/fixtures/OptionRet.lean:Examples.OptionRet:OptionRet"
  "runtime-tests/cosmwasm/fixtures/OptionState.lean:Examples.OptionState:OptionState"
  "runtime-tests/cosmwasm/fixtures/NarrowCounter.lean:Examples.NarrowCounter:NarrowCounter"
  "Examples/TipJar.lean:Examples.TipJar:TipJar"
)

echo "cosmwasm-runtime-test: building proof-forge-next (lake build proof_forge_next)"
# Lean exe target is `proof_forge_next`; on-disk name is `proof-forge-next`.
lake build proof_forge_next || die "lake build proof_forge_next failed"
[[ -x "$cli" ]] || die "CLI missing after build: $cli"

echo "cosmwasm-runtime-test: tool root=$PROOF_FORGE_TOOL_ROOT"
echo "cosmwasm-runtime-test: wat2wasm=$wat2wasm ($("$wat2wasm" --version 2>&1 | head -1 || true))"

# CLI rejects pre-existing -o paths (PF-OUTPUT-COLLISION); remove and let it create.
rm -rf "$out_dir"
mkdir -p "$out_dir"

normalize_wasm() {
  local name="$1"
  local fixture_out="$2"
  local wasm=""
  if [[ -f "$fixture_out/${name}.wasm" ]]; then
    wasm="$fixture_out/${name}.wasm"
  else
    wasm="$(find "$fixture_out" -name "${name}.wasm" -type f 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$wasm" || ! -f "$wasm" ]]; then
    # Some hosts leave .wat only when finalize is skipped — assemble with wat2wasm.
    local wat=""
    if [[ -f "$fixture_out/${name}.wat" ]]; then
      wat="$fixture_out/${name}.wat"
    else
      wat="$(find "$fixture_out" -name "${name}.wat" -type f 2>/dev/null | head -n 1 || true)"
    fi
    [[ -n "$wat" && -f "$wat" ]] || return 1
    wasm="$fixture_out/${name}.wasm"
    if ! "$wat2wasm" "$wat" -o "$wasm" 2>"$out_dir/${name}.wat2wasm.err"; then
      echo "cosmwasm-runtime-test: wat2wasm failed for $name" >&2
      cat "$out_dir/${name}.wat2wasm.err" >&2 || true
      return 1
    fi
  fi
  if [[ "$(cd "$(dirname "$wasm")" && pwd)" != "$(cd "$fixture_out" && pwd)" ]]; then
    cp -f "$wasm" "$fixture_out/${name}.wasm"
  fi
  # Optional ABI sidecar normalize
  local abi=""
  if [[ -f "$fixture_out/${name}.cosmwasm-abi.json" ]]; then
    abi="$fixture_out/${name}.cosmwasm-abi.json"
  else
    abi="$(find "$fixture_out" -name "${name}.cosmwasm-abi.json" -type f 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -n "$abi" && -f "$abi" && "$(cd "$(dirname "$abi")" && pwd)" != "$(cd "$fixture_out" && pwd)" ]]; then
    cp -f "$abi" "$fixture_out/${name}.cosmwasm-abi.json"
  fi
  [[ -f "$fixture_out/${name}.wasm" ]] || return 1
  echo "cosmwasm-runtime-test: ${name}.wasm=$(wc -c <"$fixture_out/${name}.wasm" | tr -d ' ') bytes"
  return 0
}

for entry in "${programs[@]}"; do
  IFS=':' read -r rel_src module name <<<"$entry"
  src="$root/$rel_src"
  [[ -f "$src" ]] || die "source missing: $src"
  fixture_out="$out_dir/$name"
  echo "cosmwasm-runtime-test: build $rel_src --module $module --target cosmwasm -o $fixture_out"
  if ! lake env "$cli" build \
    "$rel_src" \
    --module "$module" \
    --target cosmwasm \
    -o "$fixture_out"; then
    die "proof-forge-next build failed for $name"
  fi
  normalize_wasm "$name" "$fixture_out" || die "${name}.wasm not found under $fixture_out"
done

echo "cosmwasm-runtime-test: cargo test (cwd=$crate_dir)"
export PROOF_FORGE_FIXTURES_DIR="$out_dir"

# Prefer offline when Cargo.lock exists and registry is warm; fall back to network.
# First cold run needs network to fetch cosmwasm-vm 3.0.9 + wasmer graph (~300 crates).
if ! (
  cd "$crate_dir"
  if [[ -f Cargo.lock ]] && cargo test --offline -- --nocapture; then
    echo "cosmwasm-runtime-test: cargo test --offline ok"
    exit 0
  fi
  echo "cosmwasm-runtime-test: offline unavailable or failed; cargo test with network (if needed)"
  cargo test -- --nocapture
); then
  die "cargo test failed (see output above)"
fi

echo "cosmwasm-runtime-test: ok (engineering mock-runtime differential; not wasmd/formal)"
