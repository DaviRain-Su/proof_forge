#!/usr/bin/env bash
# Compatibility wrapper for the former Web3.js-backed gate name.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$REPO_ROOT/scripts/solana/epoch-schedule-sysvar-live-smoke.sh" "$@"
