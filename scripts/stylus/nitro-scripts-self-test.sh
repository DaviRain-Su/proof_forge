#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scripts=(
  "$root/scripts/stylus/cargo-stylus-workspace.sh"
  "$root/scripts/stylus/nitro-doctor.sh"
  "$root/scripts/stylus/require-nitro-ready.sh"
  "$root/tools/stylus-nitro/manage.sh"
  "$root/scripts/stylus/nitro-check.sh"
  "$root/scripts/stylus/nitro-deploy.sh"
  "$root/scripts/stylus/nitro-e2e.sh"
  "$root/scripts/stylus/value-vault-nitro-e2e.sh"
  "$root/scripts/stylus/token-nitro-e2e.sh"
  "$root/scripts/stylus/remote-call-nitro-e2e.sh"
  "$root/scripts/stylus/aggregate-nitro-e2e.sh"
  "$root/scripts/stylus/sepolia-e2e.sh"
)
for script in "${scripts[@]}"; do
  bash -n "$script"
done
"$root/tools/stylus-nitro/manage.sh" --self-test
address="$(printf 'deployed code at address: \033[38;5;183;1m0xa6e41ffd769491a42a6e5ce453259b93983a22ef\033[0m\n' |
  python3 "$root/scripts/stylus/parse-deployed-address.py")"
[[ "$address" == "0xa6e41ffd769491a42a6e5ce453259b93983a22ef" ]]
doctor="$("$root/scripts/stylus/nitro-doctor.sh" --self-test)"
[[ "$doctor" == *'"cargoStylus"'* && "$doctor" == *'"nitroRevision"'* &&
   "$doctor" == *'"rpcChainId"'* ]]
grep -Fq -- '--wasm-file=' "$root/scripts/stylus/nitro-check.sh"
grep -Fq 'cargo-stylus-workspace' "$root/scripts/stylus/nitro-check.sh"
grep -Fq 'Stylus.toml' "$root/scripts/stylus/cargo-stylus-workspace.sh"
grep -Fq 'http://127.0.0.1:8547' "$root/tools/stylus-nitro/manage.sh"
grep -Fq 'PROOF_FORGE_NITRO_RESET' "$root/tools/stylus-nitro/manage.sh"
grep -Fq 'public RPC requires PROOF_FORGE_STYLUS_PRIVATE_KEY_PATH' "$root/scripts/stylus/nitro-deploy.sh"
grep -Fq 'deploy_args+=(--no-verify)' "$root/scripts/stylus/nitro-deploy.sh"
grep -Fq 'local Nitro E2E only accepts' "$root/scripts/stylus/nitro-e2e.sh"
grep -Fq 'require-nitro-ready.sh' "$root/scripts/stylus/nitro-e2e.sh"
grep -Fq '.foundry/bin' "$root/scripts/stylus/nitro-e2e.sh"
grep -Fq 'build/evidence/stylus/value-vault' "$root/scripts/stylus/value-vault-nitro-e2e.sh"
grep -Fq 'charge_fee(uint64,uint64)' "$root/scripts/stylus/value-vault-nitro-e2e.sh"
grep -Fq 'proof-forge.stylus.nitro-gate.v1' "$root/scripts/stylus/value-vault-nitro-e2e.sh"
grep -Fq 'require-nitro-ready.sh' "$root/scripts/stylus/value-vault-nitro-e2e.sh"
grep -Fq 'build/evidence/stylus/token' "$root/scripts/stylus/token-nitro-e2e.sh"
grep -Fq 'mapping-events-summary.json' "$root/scripts/stylus/token-nitro-e2e.sh"
grep -Fq "Transfer(address,address,uint256)" "$root/scripts/stylus/token-nitro-e2e.sh"
grep -Fq 'require-nitro-ready.sh' "$root/scripts/stylus/token-nitro-e2e.sh"
grep -Fq 'peer.callee=' "$root/scripts/stylus/remote-call-nitro-e2e.sh"
grep -Fq 'proof-forge.stylus.nitro-gate.v1' "$root/scripts/stylus/remote-call-nitro-e2e.sh"
grep -Fq 'require-nitro-ready.sh' "$root/scripts/stylus/remote-call-nitro-e2e.sh"
grep -Fq 'echo_bytes(bytes)' "$root/scripts/stylus/aggregate-nitro-e2e.sh"
grep -Fq 'proof-forge.stylus.nitro-gate.v1' "$root/scripts/stylus/aggregate-nitro-e2e.sh"
grep -Fq 'require-nitro-ready.sh' "$root/scripts/stylus/aggregate-nitro-e2e.sh"
python3 "$root/scripts/stylus/nitro-evidence-self-test.py"
grep -Fq 'sepolia-rollup.arbitrum.io/rpc' "$root/scripts/stylus/sepolia-e2e.sh"
echo "stylus-nitro-scripts: ok"
