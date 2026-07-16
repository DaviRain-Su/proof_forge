#!/usr/bin/env bash
# Z1.5: execute oracle for Counter DPN path.
#
# When dargo is present, runs the existing Counter smoke (dargo compile/execute
# on .psy → DPN). Direct dpn-json is not a dargo input format; behavioral
# equivalence is "same golden DPN document as dargo compile", already gated by
# psy-dpn-direct + dargo rebuild diffs in psy-dpn-goldens.
#
# Without dargo: exit 0 with honest skip (experimental).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

note() { echo "psy-dpn-execute-oracle: $1"; }

DARGO_BIN="${DARGO:-dargo}"
if [[ "$DARGO_BIN" == "dargo" && ! -x "$(command -v dargo 2>/dev/null || true)" && -x "${PSY_HOME:-}/bin/dargo" ]]; then
  DARGO_BIN="${PSY_HOME}/bin/dargo"
fi

if ! command -v "$DARGO_BIN" >/dev/null 2>&1; then
  note "SKIP: dargo not on PATH — execute oracle deferred"
  note "install: curl -fsSL https://raw.githubusercontent.com/QEDProtocol/psyup/main/install.sh | bash"
  note "direct DPN emit still verified by just psy-dpn-direct against goldens"
  echo "=== psy-dpn-execute-oracle: SKIP (no dargo) ==="
  exit 0
fi

note "dargo present ($DARGO_BIN) — running Counter psy-smoke execute path"
scripts/psy/counter-smoke.sh
note "ok: dargo Counter execute path green; DPN golden equivalence via psy-dpn-goldens/direct"
echo "=== psy-dpn-execute-oracle: PASS ==="
