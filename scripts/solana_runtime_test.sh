#!/usr/bin/env bash
# Solana engineering runtime: build Counter ELF + target fixture ELFs
# (solana-sbpf-elf-v1; control flow, effects, aggregates, narrow/wide ABI)
# and run Mollusk runtime differential tests.
#
# Requires:
#   - lake / Lean toolchain on PATH
#   - cargo / rustc on PATH
#   - locked sbpf under PROOF_FORGE_TOOL_ROOT (or default cache root)
#
# Exit codes:
#   0 success
#   1 product / cargo test failure
#   2 missing tools / usage
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

die() {
  echo "solana-runtime-test: $*" >&2
  exit 1
}

missing() {
  echo "solana-runtime-test: $*" >&2
  exit 2
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
sbpf_bin="$PROOF_FORGE_TOOL_ROOT/sbpf"

if [[ ! -x "$sbpf_bin" ]]; then
  missing "sbpf not found at $sbpf_bin (set PROOF_FORGE_TOOL_ROOT or run just toolchains-materialize-external)"
fi

if ! command -v lake >/dev/null 2>&1; then
  missing "lake not on PATH"
fi
if ! command -v cargo >/dev/null 2>&1; then
  missing "cargo not on PATH (install Rust toolchain)"
fi

cli="$root/.lake/build/bin/proof-forge-next"
out_dir="${PROOF_FORGE_RUNTIME_OUT:-$root/build/v2/solana-runtime}"
crate_dir="$root/runtime-tests/solana"
fixtures_src="$root/runtime-tests/solana/fixtures"

# S3b fixture programs (source stem == program name == artifact stem).
fixtures=(
  LoopSum
  MathOps
  FnCall
  Events
  MultiField
  MatchOps
  NarrowGates
  NarrowAbi
  NarrowResult
  ArraySlots
  MapMini
  PrincipalStore
  WideMul
  PairRet
  MaybeRet
  ArrayRet
  OptionRet
  OptionState
  CpiCaller
)

echo "solana-runtime-test: building proof-forge-next (lake build proof_forge_next)"
# Lean exe target is `proof_forge_next`; on-disk name is `proof-forge-next`.
lake build proof_forge_next || die "lake build proof_forge_next failed"
[[ -x "$cli" ]] || die "CLI missing after build: $cli"

echo "solana-runtime-test: tool root=$PROOF_FORGE_TOOL_ROOT"
echo "solana-runtime-test: sbpf=$("$sbpf_bin" --version 2>&1 || true)"

# CLI rejects pre-existing -o paths (PF-OUTPUT-COLLISION); remove and let it create.
rm -rf "$out_dir"
mkdir -p "$out_dir"

echo "solana-runtime-test: build Examples/Counter.lean --module Examples.Counter --target solana --profile solana-sbpf-elf-v1 -o $out_dir/Counter"
if ! lake env "$cli" build Examples/Counter.lean --module Examples.Counter \
  --target solana \
  --profile solana-sbpf-elf-v1 \
  -o "$out_dir/Counter"; then
  die "proof-forge-next build Counter failed"
fi

so_path=""
plan_path=""
if [[ -f "$out_dir/Counter/Counter.so" ]]; then
  so_path="$out_dir/Counter/Counter.so"
elif [[ -f "$out_dir/Counter/deploy/Counter.so" ]]; then
  so_path="$out_dir/Counter/deploy/Counter.so"
else
  so_path="$(find "$out_dir/Counter" -name 'Counter.so' -type f 2>/dev/null | head -n 1 || true)"
fi
if [[ -f "$out_dir/Counter/Counter.sbpf-plan" ]]; then
  plan_path="$out_dir/Counter/Counter.sbpf-plan"
else
  plan_path="$(find "$out_dir/Counter" -name 'Counter.sbpf-plan' -type f 2>/dev/null | head -n 1 || true)"
fi

[[ -n "$so_path" && -f "$so_path" ]] || die "Counter.so not found under $out_dir/Counter"
[[ -n "$plan_path" && -f "$plan_path" ]] || die "Counter.sbpf-plan not found under $out_dir/Counter"

so_dir="$(cd "$(dirname "$so_path")" && pwd)"
plan_path="$(cd "$(dirname "$plan_path")" && pwd)/$(basename "$plan_path")"

echo "solana-runtime-test: Counter.so=$so_path ($(wc -c <"$so_path" | tr -d ' ') bytes)"
echo "solana-runtime-test: plan=$plan_path"

# Build each S3b fixture under $out_dir/<Name>/.
for name in "${fixtures[@]}"; do
  src="$fixtures_src/${name}.lean"
  [[ -f "$src" ]] || die "fixture source missing: $src"
  fixture_out="$out_dir/$name"
  echo "solana-runtime-test: build --source runtime-tests/solana/fixtures/${name}.lean --module Examples.${name} --target solana --profile solana-sbpf-elf-v1 -o $fixture_out"
  if ! lake env "$cli" build \
    "runtime-tests/solana/fixtures/${name}.lean" \
    --module "Examples.${name}" \
    --target solana \
    --profile solana-sbpf-elf-v1 \
    -o "$fixture_out"; then
    die "proof-forge-next build failed for fixture $name"
  fi

  fixture_so=""
  fixture_plan=""
  if [[ -f "$fixture_out/${name}.so" ]]; then
    fixture_so="$fixture_out/${name}.so"
  elif [[ -f "$fixture_out/deploy/${name}.so" ]]; then
    fixture_so="$fixture_out/deploy/${name}.so"
  else
    fixture_so="$(find "$fixture_out" -name "${name}.so" -type f 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -f "$fixture_out/${name}.sbpf-plan" ]]; then
    fixture_plan="$fixture_out/${name}.sbpf-plan"
  else
    fixture_plan="$(find "$fixture_out" -name "${name}.sbpf-plan" -type f 2>/dev/null | head -n 1 || true)"
  fi
  [[ -n "$fixture_so" && -f "$fixture_so" ]] || die "${name}.so not found under $fixture_out"
  [[ -n "$fixture_plan" && -f "$fixture_plan" ]] || die "${name}.sbpf-plan not found under $fixture_out"

  # Normalize layout for Rust: PROOF_FORGE_FIXTURES_DIR/<Name>/<Name>.{so,sbpf-plan}
  # If sbpf stages under deploy/, copy/link into the fixture root for stable env paths.
  if [[ "$(cd "$(dirname "$fixture_so")" && pwd)" != "$(cd "$fixture_out" && pwd)" ]]; then
    cp -f "$fixture_so" "$fixture_out/${name}.so"
  fi
  if [[ "$(cd "$(dirname "$fixture_plan")" && pwd)" != "$(cd "$fixture_out" && pwd)" ]]; then
    cp -f "$fixture_plan" "$fixture_out/${name}.sbpf-plan"
  fi
  # BL-27: keep .s next to .so for CPI plan/asm marker pins (when ELF profile).
  if [[ -f "$fixture_out/${name}.s" ]]; then
    :
  elif [[ -f "$fixture_out/deploy/${name}.s" ]]; then
    cp -f "$fixture_out/deploy/${name}.s" "$fixture_out/${name}.s"
  else
    fixture_s="$(find "$fixture_out" -name "${name}.s" -type f 2>/dev/null | head -n 1 || true)"
    if [[ -n "$fixture_s" && -f "$fixture_s" ]]; then
      cp -f "$fixture_s" "$fixture_out/${name}.s"
    fi
  fi
  [[ -f "$fixture_out/${name}.so" ]] || die "normalized ${name}.so missing"
  [[ -f "$fixture_out/${name}.sbpf-plan" ]] || die "normalized ${name}.sbpf-plan missing"
  echo "solana-runtime-test: ${name}.so=$(wc -c <"$fixture_out/${name}.so" | tr -d ' ') bytes"
done

# BL-27: assemble zero-account mock CPI callee (SBPF assembly via locked sbpf).
mock_src="$crate_dir/mock-callee"
mock_so=""
echo "solana-runtime-test: build mock-callee (sbpf)"
if ! (
  cd "$mock_src"
  "$sbpf_bin" build
); then
  die "sbpf build mock-callee failed"
fi
if [[ -f "$mock_src/deploy/mock-callee.so" ]]; then
  mock_so="$mock_src/deploy/mock-callee.so"
elif [[ -f "$mock_src/target/deploy/mock-callee.so" ]]; then
  mock_so="$mock_src/target/deploy/mock-callee.so"
else
  mock_so="$(find "$mock_src" -name 'mock-callee.so' -type f 2>/dev/null | head -n 1 || true)"
fi
[[ -n "$mock_so" && -f "$mock_so" ]] || die "mock-callee.so not found under $mock_src"
# Stage next to fixtures for stable env path.
cp -f "$mock_so" "$out_dir/mock-callee.so"
mock_so="$out_dir/mock-callee.so"
echo "solana-runtime-test: mock-callee.so=$mock_so ($(wc -c <"$mock_so" | tr -d ' ') bytes)"

echo "solana-runtime-test: cargo test (cwd=$crate_dir)"

export PROOF_FORGE_SO_DIR="$so_dir"
export PROOF_FORGE_PLAN="$plan_path"
export PROOF_FORGE_FIXTURES_DIR="$out_dir"
export PROOF_FORGE_MOCK_CALLEE_SO="$mock_so"

if ! (
  cd "$crate_dir"
  cargo test -- --nocapture
); then
  die "cargo test failed (see output above)"
fi

echo "solana-runtime-test: ok"
