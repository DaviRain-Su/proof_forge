#!/usr/bin/env bash
# One-shot cosmwasm-vm mock call/query for `pf run -t cosmwasm -- <method> [u64…]`.
#
# Inputs:
#   PF_CW_ARTIFACT_DIR   — OutputSet with *.wasm + manifest.json (required)
#   PF_CW_METHOD         — method name (required)
#   PF_CW_ARGS           — space-separated u64 decimals (optional)
#   PF_CW_MODE           — instantiate | execute | query | auto  (default: auto)
#   PF_CW_SENDER         — MessageInfo.sender (default: creator)
#   PROOF_FORGE_ROOT     — monorepo / bundle root
#
# Honesty: engineering cosmwasm-vm mock only — not wasmd, not mainnet, not formal.
# Generic sync call FC at compiler; schedule = SubMsg reply_on=never.
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${_script_dir}/.." && pwd)"
export PROOF_FORGE_ROOT="${PROOF_FORGE_ROOT:-$root}"

die() { echo "pf-cosmwasm-run: FAIL: $*" >&2; exit 1; }
skip_clean() {
  echo "pf-cosmwasm-run: skipped: $*" >&2
  exit 0
}

artifact_dir="${PF_CW_ARTIFACT_DIR:-}"
method="${PF_CW_METHOD:-}"
mode="${PF_CW_MODE:-auto}"
args_str="${PF_CW_ARGS:-}"
sender="${PF_CW_SENDER:-creator}"

[[ -n "$artifact_dir" && -d "$artifact_dir" ]] || die "PF_CW_ARTIFACT_DIR missing (run pf build -t cosmwasm)"
artifact_dir="$(cd "$artifact_dir" && pwd)"
[[ -f "$artifact_dir/manifest.json" ]] || die "missing manifest.json under $artifact_dir"
[[ -n "$method" ]] || die "PF_CW_METHOD required"

if [[ -f "$artifact_dir/StateCell.wasm" ]]; then
  wasm="$artifact_dir/StateCell.wasm"
else
  wasm="$(find "$artifact_dir" -maxdepth 2 -type f -name '*.wasm' | sort | head -n 1 || true)"
fi
[[ -n "$wasm" && -f "$wasm" ]] || die "no *.wasm under $artifact_dir"

abi="$(find "$artifact_dir" -maxdepth 2 -type f -name '*.cosmwasm-abi.json' | sort | head -n 1 || true)"

crate_dir="$root/runtime-tests/cosmwasm"
[[ -f "$crate_dir/Cargo.toml" ]] || skip_clean "missing $crate_dir/Cargo.toml"
[[ -f "$crate_dir/src/bin/cw_oneshot.rs" ]] || skip_clean "missing cw_oneshot binary source"

if ! command -v cargo >/dev/null 2>&1; then
  skip_clean "cargo not on PATH (needed to build cw_oneshot)"
fi
if ! command -v rustc >/dev/null 2>&1; then
  skip_clean "rustc not on PATH"
fi

# Build oneshot binary (cached under crate target/).
echo "pf-cosmwasm-run: building cw_oneshot (cosmwasm-vm mock)" >&2
(
  cd "$crate_dir"
  cargo build --quiet --bin cw_oneshot 2>"$crate_dir/target/cw_oneshot.build.log" \
    || {
      tail -40 "$crate_dir/target/cw_oneshot.build.log" >&2 || true
      die "cargo build --bin cw_oneshot failed"
    }
)

bin="$crate_dir/target/debug/cw_oneshot"
[[ -x "$bin" ]] || die "cw_oneshot binary missing after build: $bin"

export PF_CW_WASM="$wasm"
export PF_CW_METHOD="$method"
export PF_CW_MODE="$mode"
export PF_CW_ARGS="$args_str"
export PF_CW_SENDER="$sender"
if [[ -n "$abi" && -f "$abi" ]]; then
  export PF_CW_ABI="$abi"
fi

exec "$bin"
