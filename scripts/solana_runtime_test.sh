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
if [[ -x /usr/bin/python3 ]]; then
  python_bin=/usr/bin/python3
elif command -v python3 >/dev/null 2>&1; then
  python_bin="$(command -v python3)"
else
  missing "python3 not found (required for independent artifact closure validation)"
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
)

bind_output() {
  local tree="$1"
  local name="$2"
  echo "solana-runtime-test: inspect exact closure $name"
  if ! lake env "$cli" inspect --output-dir "$tree" --json >/dev/null; then
    die "product inspect failed for $name under $tree"
  fi
  if ! "$python_bin" -I -S scripts/solana_runtime_bind_output.py "$tree" "$name"; then
    die "independent artifact binding failed for $name under $tree"
  fi
}

echo "solana-runtime-test: artifact binding self-test"
"$python_bin" -I -S scripts/solana_runtime_bind_output_self_test.py \
  || die "artifact binding self-test failed"

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

counter_out="$out_dir/Counter"
bind_output "$counter_out" "Counter"
so_path="$counter_out/Counter.so"
plan_path="$counter_out/Counter.sbpf-plan"
[[ -f "$so_path" ]] || die "manifest-bound Counter.so missing: $so_path"
[[ -f "$plan_path" ]] || die "manifest-bound Counter.sbpf-plan missing: $plan_path"

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

  bind_output "$fixture_out" "$name"
  fixture_so="$fixture_out/${name}.so"
  fixture_plan="$fixture_out/${name}.sbpf-plan"
  [[ -f "$fixture_so" ]] || die "manifest-bound ${name}.so missing"
  [[ -f "$fixture_plan" ]] || die "manifest-bound ${name}.sbpf-plan missing"
  echo "solana-runtime-test: ${name}.so=$(wc -c <"$fixture_so" | tr -d ' ') bytes"
done

echo "solana-runtime-test: cargo test (cwd=$crate_dir)"

export PROOF_FORGE_COUNTER_OUT="$counter_out"
export PROOF_FORGE_FIXTURES_DIR="$out_dir"

if ! (
  cd "$crate_dir"
  cargo test --locked -- --nocapture
); then
  die "cargo test failed (see output above)"
fi

echo "solana-runtime-test: ok"
