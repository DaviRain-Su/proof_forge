#!/usr/bin/env bash
# Compatibility wrapper for the former Web3.js-backed PDA derivation gate name.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$REPO_ROOT/scripts/solana/pda-rust-smoke.sh" "$@"
