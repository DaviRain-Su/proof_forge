#!/usr/bin/env bash
# Compatibility wrapper for the former Surfpool/Web3.js Counter gate name.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$REPO_ROOT/scripts/solana/counter-live-smoke.sh" "$@"
