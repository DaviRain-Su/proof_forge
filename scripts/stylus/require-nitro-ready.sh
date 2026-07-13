#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
gate="${1:-stylus-nitro-e2e}"
report="$root/build/evidence/stylus/nitro-doctor.json"

if ! "$root/scripts/stylus/nitro-doctor.sh" >/dev/null; then
  echo "$gate: Nitro doctor is not ready; see $report" >&2
  exit 1
fi
