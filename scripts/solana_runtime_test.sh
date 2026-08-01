#!/usr/bin/env bash
# Solana S3a: build Counter ELF (solana-sbpf-elf-v1) and run Mollusk runtime
# differential tests against ReferenceV1 Counter semantics.
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

echo "solana-runtime-test: building proof-forge-next (lake build proof_forge_next)"
# Lean exe target is `proof_forge_next`; on-disk name is `proof-forge-next`.
lake build proof_forge_next || die "lake build proof_forge_next failed"
[[ -x "$cli" ]] || die "CLI missing after build: $cli"

echo "solana-runtime-test: tool root=$PROOF_FORGE_TOOL_ROOT"
echo "solana-runtime-test: sbpf=$("$sbpf_bin" --version 2>&1 || true)"

# CLI rejects pre-existing -o paths (PF-OUTPUT-COLLISION); remove and let it create.
rm -rf "$out_dir"
mkdir -p "$(dirname "$out_dir")"

echo "solana-runtime-test: build-counter --target solana --profile solana-sbpf-elf-v1 -o $out_dir"
if ! lake env "$cli" build-counter \
  --target solana \
  --profile solana-sbpf-elf-v1 \
  -o "$out_dir"; then
  die "proof-forge-next build-counter failed"
fi

so_path=""
plan_path=""
# Prefer top-level Counter.so / Counter.sbpf-plan; also accept nested layouts.
if [[ -f "$out_dir/Counter.so" ]]; then
  so_path="$out_dir/Counter.so"
elif [[ -f "$out_dir/deploy/Counter.so" ]]; then
  so_path="$out_dir/deploy/Counter.so"
else
  so_path="$(find "$out_dir" -name 'Counter.so' -type f 2>/dev/null | head -n 1 || true)"
fi
if [[ -f "$out_dir/Counter.sbpf-plan" ]]; then
  plan_path="$out_dir/Counter.sbpf-plan"
else
  plan_path="$(find "$out_dir" -name 'Counter.sbpf-plan' -type f 2>/dev/null | head -n 1 || true)"
fi

[[ -n "$so_path" && -f "$so_path" ]] || die "Counter.so not found under $out_dir"
[[ -n "$plan_path" && -f "$plan_path" ]] || die "Counter.sbpf-plan not found under $out_dir"

so_dir="$(cd "$(dirname "$so_path")" && pwd)"
plan_path="$(cd "$(dirname "$plan_path")" && pwd)/$(basename "$plan_path")"

echo "solana-runtime-test: Counter.so=$so_path ($(wc -c <"$so_path" | tr -d ' ') bytes)"
echo "solana-runtime-test: plan=$plan_path"
echo "solana-runtime-test: cargo test (cwd=$crate_dir)"

export PROOF_FORGE_SO_DIR="$so_dir"
export PROOF_FORGE_PLAN="$plan_path"

if ! (
  cd "$crate_dir"
  cargo test -- --nocapture
); then
  die "cargo test failed (see output above)"
fi

echo "solana-runtime-test: ok"
