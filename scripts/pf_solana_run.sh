#!/usr/bin/env bash
# One-shot Mollusk call for `pf run -t solana -- <method> [u64…]`.
#
# Inputs:
#   PF_SOLANA_ARTIFACT_DIR / PF_SOL_ARTIFACT_DIR — OutputSet with *.so + idl
#   PF_SOL_METHOD         — method name (init|increment|get|…)
#   PF_SOL_ARGS           — space-separated u64 decimals
#   PF_SOL_INIT_ARGS      — auto-init u64 when method ≠ init (default 0)
#   PROOF_FORGE_ROOT      — monorepo root (for runtime-tests/solana)
#
# Honesty: engineering Mollusk only — not mainnet, not formal, not RPC.
# Body-only StateCell-shaped programs. CPI multi-role → use pf test.
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${_script_dir}/.." && pwd)"
export PROOF_FORGE_ROOT="${PROOF_FORGE_ROOT:-$root}"

die() { echo "pf-solana-run: FAIL: $*" >&2; exit 1; }
skip_clean() {
  echo "pf-solana-run: skipped: $*" >&2
  exit 0
}

artifact_dir="${PF_SOL_ARTIFACT_DIR:-${PF_SOLANA_ARTIFACT_DIR:-}}"
method="${PF_SOL_METHOD:-}"
args_str="${PF_SOL_ARGS:-}"
init_args_str="${PF_SOL_INIT_ARGS:-}"

[[ -n "$artifact_dir" && -d "$artifact_dir" ]] || die "PF_SOL_ARTIFACT_DIR missing (run pf build -t solana)"
artifact_dir="$(cd "$artifact_dir" && pwd)"
[[ -f "$artifact_dir/manifest.json" ]] || die "missing manifest.json under $artifact_dir"
[[ -n "$method" ]] || die "PF_SOL_METHOD required"

crate_dir="$root/runtime-tests/solana"
if [[ ! -f "$crate_dir/Cargo.toml" ]]; then
  walk="$root"
  for _ in 1 2 3 4 5 6; do
    if [[ -f "$walk/runtime-tests/solana/Cargo.toml" ]]; then
      crate_dir="$walk/runtime-tests/solana"
      root="$walk"
      export PROOF_FORGE_ROOT="$root"
      break
    fi
    walk="$(dirname "$walk")"
  done
fi
[[ -f "$crate_dir/Cargo.toml" ]] || skip_clean "missing runtime-tests/solana (bundle-only; use pf verify)"
[[ -f "$crate_dir/src/bin/sol_oneshot.rs" ]] || skip_clean "missing sol_oneshot source"
command -v cargo >/dev/null 2>&1 || skip_clean "cargo not on PATH"
command -v rustc >/dev/null 2>&1 || skip_clean "rustc not on PATH"

echo "pf-solana-run: building sol_oneshot (Mollusk)" >&2
(
  cd "$crate_dir"
  cargo build --quiet --bin sol_oneshot 2>"$crate_dir/target/sol_oneshot.build.log" \
    || {
      tail -40 "$crate_dir/target/sol_oneshot.build.log" >&2 || true
      die "cargo build --bin sol_oneshot failed"
    }
)

bin="$crate_dir/target/debug/sol_oneshot"
[[ -x "$bin" ]] || die "sol_oneshot missing after build: $bin"

export PF_SOL_ARTIFACT_DIR="$artifact_dir"
export PF_SOL_METHOD="$method"
export PF_SOL_ARGS="$args_str"
export PF_SOL_INIT_ARGS="$init_args_str"
# Quiet SVM chatter unless the caller set RUST_LOG.
export RUST_LOG="${RUST_LOG:-error}"

exec "$bin"
