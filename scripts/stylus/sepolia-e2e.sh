#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${PROOF_FORGE_STYLUS_PRIVATE_KEY_PATH:?set PROOF_FORGE_STYLUS_PRIVATE_KEY_PATH for Sepolia}"
export PROOF_FORGE_STYLUS_ENDPOINT="${PROOF_FORGE_STYLUS_ENDPOINT:-https://sepolia-rollup.arbitrum.io/rpc}"

"$root/scripts/stylus/nitro-deploy.sh"
