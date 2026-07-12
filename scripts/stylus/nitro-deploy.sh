#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
endpoint="${PROOF_FORGE_STYLUS_ENDPOINT:-http://127.0.0.1:8547}"
wasm="${PROOF_FORGE_STYLUS_WASM:-$root/build/stylus/counter-differential/counter.wasm}"
toolchain="${PROOF_FORGE_STYLUS_RUST:-1.91.0}"
if [[ "$endpoint" == "http://127.0.0.1:8547" ]]; then
  key_path="${PROOF_FORGE_STYLUS_PRIVATE_KEY_PATH:-$("$root/tools/stylus-nitro/manage.sh" key)}"
else
  key_path="${PROOF_FORGE_STYLUS_PRIVATE_KEY_PATH:-}"
  [[ -n "$key_path" ]] || {
    echo "stylus-nitro-deploy: public RPC requires PROOF_FORGE_STYLUS_PRIVATE_KEY_PATH" >&2
    exit 1
  }
fi
output_dir="$root/build/stylus/nitro"

"$root/scripts/stylus/nitro-check.sh"
mkdir -p "$output_dir"
log="$output_dir/deploy.log"
deploy_args=(stylus deploy --wasm-file="$wasm" --endpoint="$endpoint" --private-key-path="$key_path")
if [[ "$endpoint" == "http://127.0.0.1:8547" ]]; then
  deploy_args+=(--no-verify)
fi
workspace="$("$root/scripts/stylus/cargo-stylus-workspace.sh")"
(cd "$workspace" && rustup run "$toolchain" cargo "${deploy_args[@]}") | tee "$log"
address="$(python3 "$root/scripts/stylus/parse-deployed-address.py" "$log")"
[[ "$address" =~ ^0x[0-9a-fA-F]{40}$ ]] || {
  echo "stylus-nitro-deploy: could not parse deployed address from $log" >&2
  exit 1
}
printf '%s\n' "$address" > "$output_dir/address"
echo "stylus-nitro-deploy: $address"
