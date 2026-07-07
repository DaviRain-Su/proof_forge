#!/usr/bin/env bash
# Compatibility wrapper for the old Web3.js gate name.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$REPO_ROOT/scripts/solana/token-2022-non-transferable-live-smoke.sh" "$@"
