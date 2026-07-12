#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
endpoint="${PROOF_FORGE_STYLUS_ENDPOINT:-http://127.0.0.1:8547}"
wasm="${PROOF_FORGE_STYLUS_WASM:-$root/build/stylus/counter-differential/counter.wasm}"
toolchain="${PROOF_FORGE_STYLUS_RUST:-1.91.0}"

"$root/tools/stylus-nitro/manage.sh" wait
[[ -f "$wasm" ]] || "$root/scripts/stylus/vm-runner-smoke.sh"
rustup run "$toolchain" cargo stylus --version >/dev/null 2>&1 || {
  echo "stylus-nitro-check: install the pinned cargo-stylus for Rust $toolchain" >&2
  exit 1
}
rustup run "$toolchain" cargo stylus check --wasm-file="$wasm" --endpoint="$endpoint"
