#!/usr/bin/env bash
# One-shot @ton/sandbox call for `pf run -t ton -- <method> [u64…]`.
#
# Inputs:
#   PF_TON_ARTIFACT_DIR  — OutputSet with *.compiled.boc + *.ton-abi.json
#   PF_TON_METHOD        — method name
#   PF_TON_ARGS          — space-separated u64 decimals
#   PF_TON_INIT_ARGS     — auto-init args when method ≠ init (default 0)
#   PROOF_FORGE_ROOT     — monorepo root (runtime-tests/ton)
#
# Honesty: engineering @ton/sandbox only — not mainnet, not formal.
# Sync call FC at compiler; schedule = createMessage subset.
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${_script_dir}/.." && pwd)"
export PROOF_FORGE_ROOT="${PROOF_FORGE_ROOT:-$root}"

die() { echo "pf-ton-run: FAIL: $*" >&2; exit 1; }
skip_clean() {
  echo "pf-ton-run: skipped: $*" >&2
  exit 0
}

artifact_dir="${PF_TON_ARTIFACT_DIR:-}"
method="${PF_TON_METHOD:-}"
args_str="${PF_TON_ARGS:-}"
init_args_str="${PF_TON_INIT_ARGS:-}"

[[ -n "$artifact_dir" && -d "$artifact_dir" ]] || die "PF_TON_ARTIFACT_DIR missing (run pf build -t ton)"
artifact_dir="$(cd "$artifact_dir" && pwd)"
[[ -f "$artifact_dir/manifest.json" ]] || die "missing manifest.json under $artifact_dir"
[[ -n "$method" ]] || die "PF_TON_METHOD required"

crate_dir="$root/runtime-tests/ton"
if [[ ! -f "$crate_dir/package.json" ]]; then
  walk="$root"
  for _ in 1 2 3 4 5 6; do
    if [[ -f "$walk/runtime-tests/ton/package.json" ]]; then
      crate_dir="$walk/runtime-tests/ton"
      root="$walk"
      export PROOF_FORGE_ROOT="$root"
      break
    fi
    walk="$(dirname "$walk")"
  done
fi
[[ -f "$crate_dir/package.json" ]] || skip_clean "missing runtime-tests/ton"
[[ -f "$crate_dir/oneshot.mjs" ]] || skip_clean "missing oneshot.mjs"
command -v node >/dev/null 2>&1 || skip_clean "node not on PATH (need >=18)"

# Ensure deps
if [[ ! -d "$crate_dir/node_modules/@ton/sandbox" ]]; then
  echo "pf-ton-run: npm install (@ton/sandbox) under $crate_dir" >&2
  (
    cd "$crate_dir"
    npm install --silent --no-fund --no-audit 2>"$crate_dir/npm-install.log" \
      || {
        tail -30 "$crate_dir/npm-install.log" >&2 || true
        skip_clean "npm install failed for runtime-tests/ton"
      }
  )
fi

export PF_TON_ARTIFACT_DIR="$artifact_dir"
export PF_TON_METHOD="$method"
export PF_TON_ARGS="$args_str"
export PF_TON_INIT_ARGS="$init_args_str"

exec node "$crate_dir/oneshot.mjs"
