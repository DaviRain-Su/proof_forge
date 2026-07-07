#!/usr/bin/env bash
# Compatibility wrapper for the former Web3.js-backed Token-2022 transfer-hook gate.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$REPO_ROOT/scripts/solana/spl-token-2022-transfer-hook-live-smoke.sh" "$@"
