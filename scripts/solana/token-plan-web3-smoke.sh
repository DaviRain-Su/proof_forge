#!/usr/bin/env bash
# Compatibility wrapper for the old Web3.js gate name.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$REPO_ROOT/scripts/solana/token-plan-live-smoke.sh" "$@"
