#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
endpoint="${PROOF_FORGE_STYLUS_ENDPOINT:-http://127.0.0.1:8547}"
[[ "$endpoint" == "http://127.0.0.1:8547" ]] || {
  echo "stylus-nitro-e2e: local Nitro E2E only accepts http://127.0.0.1:8547" >&2
  exit 1
}
key_path="${PROOF_FORGE_STYLUS_PRIVATE_KEY_PATH:-$("$root/tools/stylus-nitro/manage.sh" key)}"
key="$(tr -d '[:space:]' < "$key_path")"

command -v cast >/dev/null || { echo "stylus-nitro-e2e: cast is required" >&2; exit 1; }
"$root/scripts/stylus/nitro-deploy.sh"
address="$(tr -d '[:space:]' < "$root/build/stylus/nitro/address")"
cast send --rpc-url "$endpoint" --private-key "$key" "$address" "initialize()" >/dev/null
cast send --rpc-url "$endpoint" --private-key "$key" "$address" "increment()" >/dev/null
value="$(cast call --rpc-url "$endpoint" "$address" "get()(uint64)")"
[[ "$value" == "1" || "$value" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]] || {
  echo "stylus-nitro-e2e: expected Counter value 1, received $value" >&2
  exit 1
}
echo "stylus-nitro-e2e: ok ($address -> 1)"
