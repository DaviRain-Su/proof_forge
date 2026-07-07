#!/usr/bin/env bash
# Compatibility wrapper for the former Learn-token EVM VM smoke name.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "$REPO_ROOT/scripts/evm/token-intent-evm-vm-smoke.sh" "$@"
