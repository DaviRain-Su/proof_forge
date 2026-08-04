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

# #125 CLI/product acceptance shell for opt-in solana-sbpf-cpi-elf-v1.
# Builds proof-forge.output.v1 EscrowCpi under PROOF_FORGE_CPI_PRODUCT_OUT
# (default build/v2/solana-cpi-product) via ordinary product activation path.
# Fail-closed on product build/inspect/exact-closure failure; does not replace
# #118–#124 preactivation envs or alter Mollusk's existing cpi_escrow (36)
# fixture wiring.
product_out="${PROOF_FORGE_CPI_PRODUCT_OUT:-$root/build/v2/solana-cpi-product}"
export PROOF_FORGE_CPI_PRODUCT_OUT="$product_out"
echo "solana-runtime-test: CPI product acceptance → $product_out"
if ! bash "$root/scripts/solana_cpi_product_acceptance.sh"; then
  die "Solana CPI product acceptance failed"
fi
# Re-export resolved path if the acceptance script canonicalized it.
if [[ -n "${PROOF_FORGE_CPI_PRODUCT_OUT:-}" ]]; then
  product_out="$PROOF_FORGE_CPI_PRODUCT_OUT"
fi
if [[ -d "$product_out" ]]; then
  product_out="$(cd "$product_out" && pwd -P)"
  export PROOF_FORGE_CPI_PRODUCT_OUT="$product_out"
fi

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

# #115 harness-only companion/caller ELFs (not proof-forge.output.v1).
harness_out="${PROOF_FORGE_HARNESS_OUT:-$root/build/v2/solana-harness}"
export PROOF_FORGE_HARNESS_OUT="$harness_out"
echo "solana-runtime-test: harness build → $harness_out"
if ! bash "$root/scripts/solana_harness_build.sh"; then
  die "solana harness build failed"
fi
[[ -f "$harness_out/caller.so" ]] || die "harness caller.so missing"
[[ -f "$harness_out/companion.so" ]] || die "harness companion.so missing"

# #118 production-code-generated preflight ELF. This remains a strictly
# manifest-bound test-preactivation artifact: no product OutputFile or CPI.
preflight_out="${PROOF_FORGE_CPI_PREFLIGHT_OUT:-$root/build/v2/solana-cpi-preflight}"
export PROOF_FORGE_CPI_PREFLIGHT_OUT="$preflight_out"
echo "solana-runtime-test: CPI preflight build → $preflight_out"
if ! bash "$root/scripts/solana_cpi_preflight_build.sh"; then
  die "Solana CPI preflight build failed"
fi
[[ -f "$preflight_out/account_roles_preflight.s" ]] \
  || die "CPI preflight assembly missing"
[[ -f "$preflight_out/account_roles_preflight.so" ]] \
  || die "CPI preflight ELF missing"
preflight_out="$(cd "$preflight_out" && pwd -P)"
export PROOF_FORGE_CPI_PREFLIGHT_OUT="$preflight_out"

# #119 production-code-generated unsigned companion CPI ELF (test-preactivation).
# Independent of #118; dual-program with #115 companion; no product OutputFile.
unsigned_out="${PROOF_FORGE_CPI_UNSIGNED_OUT:-$root/build/v2/solana-cpi-unsigned}"
export PROOF_FORGE_CPI_UNSIGNED_OUT="$unsigned_out"
echo "solana-runtime-test: CPI unsigned build → $unsigned_out"
if ! bash "$root/scripts/solana_cpi_unsigned_build.sh"; then
  die "Solana CPI unsigned build failed"
fi
[[ -f "$unsigned_out/companion_cpi_unsigned.s" ]]   || die "CPI unsigned assembly missing"
[[ -f "$unsigned_out/companion_cpi_unsigned.so" ]]   || die "CPI unsigned ELF missing"
unsigned_out="$(cd "$unsigned_out" && pwd -P)"
export PROOF_FORGE_CPI_UNSIGNED_OUT="$unsigned_out"

# #120 production-code-generated PDA / signed companion CPI ELF (test-preactivation).
# Independent of #118/#119; dual-program with #115 companion; no product OutputFile.
pda_out="${PROOF_FORGE_CPI_PDA_OUT:-$root/build/v2/solana-cpi-pda}"
export PROOF_FORGE_CPI_PDA_OUT="$pda_out"
echo "solana-runtime-test: CPI PDA build → $pda_out"
if ! bash "$root/scripts/solana_cpi_pda_build.sh"; then
  die "Solana CPI PDA build failed"
fi
[[ -f "$pda_out/companion_cpi_pda.s" ]] || die "CPI PDA assembly missing"
[[ -f "$pda_out/companion_cpi_pda.so" ]] || die "CPI PDA ELF missing"
pda_out="$(cd "$pda_out" && pwd -P)"
export PROOF_FORGE_CPI_PDA_OUT="$pda_out"

# #121 production-code-generated native System CPI ELF (test-preactivation).
# Mollusk native System Program only; no generated System ELF; no product OutputFile.
system_out="${PROOF_FORGE_CPI_SYSTEM_OUT:-$root/build/v2/solana-cpi-system}"
export PROOF_FORGE_CPI_SYSTEM_OUT="$system_out"
echo "solana-runtime-test: CPI System build → $system_out"
if ! bash "$root/scripts/solana_cpi_system_build.sh"; then
  die "Solana CPI System build failed"
fi
[[ -f "$system_out/system_cpi.s" ]] || die "CPI System assembly missing"
[[ -f "$system_out/system_cpi.so" ]] || die "CPI System ELF missing"
system_out="$(cd "$system_out" && pwd -P)"
export PROOF_FORGE_CPI_SYSTEM_OUT="$system_out"

# #122 production-code-generated classic Token CPI ELF (test-preactivation).
# Uses an exact vendored source-built classic Token v9 ELF; no product OutputFile or sync claim.
token_out="${PROOF_FORGE_CPI_TOKEN_OUT:-$root/build/v2/solana-cpi-token}"
export PROOF_FORGE_CPI_TOKEN_OUT="$token_out"
echo "solana-runtime-test: CPI Token build → $token_out"
if ! bash "$root/scripts/solana_cpi_token_build.sh"; then
  die "Solana CPI Token build failed"
fi
[[ -f "$token_out/token_cpi.s" ]] || die "CPI Token assembly missing"
[[ -f "$token_out/token_cpi.so" ]] || die "CPI Token caller ELF missing"
[[ -f "$token_out/token_classic_v1.so" ]] || die "classic Token callee ELF missing"
token_out="$(cd "$token_out" && pwd -P)"
export PROOF_FORGE_CPI_TOKEN_OUT="$token_out"

# #123 production-code-generated classic ATA CPI ELF (test-preactivation).
# Vendored official ATA v8 + classic Token v9 ELFs as runtime deps only; no
# product OutputFile or activated sync claim. Independent of #118–#122 lanes.
ata_out="${PROOF_FORGE_CPI_ATA_OUT:-$root/build/v2/solana-cpi-ata}"
export PROOF_FORGE_CPI_ATA_OUT="$ata_out"
echo "solana-runtime-test: CPI ATA build → $ata_out"
if ! bash "$root/scripts/solana_cpi_ata_build.sh"; then
  die "Solana CPI ATA build failed"
fi
[[ -f "$ata_out/ata_cpi.s" ]] || die "CPI ATA assembly missing"
[[ -f "$ata_out/ata_cpi.so" ]] || die "CPI ATA caller ELF missing"
[[ -f "$ata_out/ata_classic_v1.so" ]] || die "classic ATA callee ELF missing"
[[ -f "$ata_out/token_classic_v1.so" ]] || die "classic Token dependency ELF missing"
ata_out="$(cd "$ata_out" && pwd -P)"
export PROOF_FORGE_CPI_ATA_OUT="$ata_out"

# #124 production-code-generated composite escrow CPI ELF (test-preactivation).
# Forces native System + official classic ATA/Token in one generated caller;
# still no product OutputFile or activated sync claim.
escrow_out="${PROOF_FORGE_CPI_ESCROW_OUT:-$root/build/v2/solana-cpi-escrow}"
export PROOF_FORGE_CPI_ESCROW_OUT="$escrow_out"
echo "solana-runtime-test: CPI escrow build → $escrow_out"
if ! bash "$root/scripts/solana_cpi_escrow_build.sh"; then
  die "Solana CPI escrow build failed"
fi
[[ -f "$escrow_out/escrow_cpi.s" ]] || die "CPI escrow assembly missing"
[[ -f "$escrow_out/escrow_cpi.so" ]] || die "CPI escrow caller ELF missing"
[[ -f "$escrow_out/escrow_cpi.calls.json" ]] || die "CPI escrow call inventory missing"
[[ -f "$escrow_out/ata_classic_v1.so" ]] || die "classic ATA dependency ELF missing"
[[ -f "$escrow_out/token_classic_v1.so" ]] || die "classic Token dependency ELF missing"
[[ -f "$escrow_out/manifest.json" ]] || die "CPI escrow manifest missing"
escrow_out="$(cd "$escrow_out" && pwd -P)"
export PROOF_FORGE_CPI_ESCROW_OUT="$escrow_out"

# ADR-0029 Phase B1 TipJarAssets product ELF (pf.assets + solana-sbpf-cpi-elf-v1).
# Additive: does not alter the 19 solana-sbpf-elf-v1 Counter/fixture programs.
# Mollusk suite: runtime-tests/solana/tests/tipjar_assets.rs (new test binary).
tipjar_out="${PROOF_FORGE_TIPJAR_ASSETS_OUT:-$root/build/v2/solana-tipjar-assets}"
export PROOF_FORGE_TIPJAR_ASSETS_OUT="$tipjar_out"
echo "solana-runtime-test: TipJarAssets product build → $tipjar_out"
rm -rf "$tipjar_out"
mkdir -p "$(dirname "$tipjar_out")"
if ! lake env "$cli" build \
  "runtime-tests/solana/fixtures/TipJarAssets.lean" \
  --module "Examples.TipJarAssets" \
  --target solana \
  --profile solana-sbpf-cpi-elf-v1 \
  -o "$tipjar_out"; then
  die "proof-forge-next build failed for TipJarAssets (cpi profile)"
fi
[[ -f "$tipjar_out/manifest.json" ]] || die "TipJarAssets manifest.json missing"
[[ -f "$tipjar_out/TipJarAssets.so" ]] || die "TipJarAssets.so missing"
# Content-bound CPI product closure (six leaves + evidence + manifest); not
# bind_output (that helper pins solana-sbpf-elf-v1 .sbpf-plan trees only).
if ! lake env "$cli" inspect --output-dir "$tipjar_out" --json >/dev/null; then
  die "product inspect failed for TipJarAssets under $tipjar_out"
fi
tipjar_out="$(cd "$tipjar_out" && pwd -P)"
export PROOF_FORGE_TIPJAR_ASSETS_OUT="$tipjar_out"
echo "solana-runtime-test: TipJarAssets.so=$(wc -c <"$tipjar_out/TipJarAssets.so" | tr -d ' ') bytes"

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
