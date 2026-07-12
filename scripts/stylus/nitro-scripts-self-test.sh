#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scripts=(
  "$root/tools/stylus-nitro/manage.sh"
  "$root/scripts/stylus/nitro-check.sh"
  "$root/scripts/stylus/nitro-deploy.sh"
  "$root/scripts/stylus/nitro-e2e.sh"
  "$root/scripts/stylus/sepolia-e2e.sh"
)
for script in "${scripts[@]}"; do
  bash -n "$script"
done
"$root/tools/stylus-nitro/manage.sh" --self-test
grep -Fq -- '--wasm-file=' "$root/scripts/stylus/nitro-check.sh"
grep -Fq 'http://127.0.0.1:8547' "$root/tools/stylus-nitro/manage.sh"
grep -Fq 'PROOF_FORGE_NITRO_RESET' "$root/tools/stylus-nitro/manage.sh"
grep -Fq 'public RPC requires PROOF_FORGE_STYLUS_PRIVATE_KEY_PATH' "$root/scripts/stylus/nitro-deploy.sh"
grep -Fq 'deploy_args+=(--no-verify)' "$root/scripts/stylus/nitro-deploy.sh"
grep -Fq 'local Nitro E2E only accepts' "$root/scripts/stylus/nitro-e2e.sh"
grep -Fq 'sepolia-rollup.arbitrum.io/rpc' "$root/scripts/stylus/sepolia-e2e.sh"
echo "stylus-nitro-scripts: ok"
