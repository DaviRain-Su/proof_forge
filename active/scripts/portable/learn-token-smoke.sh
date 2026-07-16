#!/usr/bin/env bash
# Compatibility wrapper for the former Learn-token-centric smoke name.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "$ROOT/scripts/portable/token-intent-smoke.sh" "$@"
