#!/usr/bin/env bash
# ProofShip rwa-share-v1 — AI gate loop helper.
# One command an agent (or the Studio backend) calls after writing a candidate
# source file: check → build --target evm → inspect exact closure.
#
# Usage:
#   scripts/gate.sh <source-file-name-in-src> [ModuleName]
# Example:
#   scripts/gate.sh RwaShareRegistry.lean RwaShareRegistry
#
# Exit 0 = gate passed (safe to deploy lane). Non-zero = gate rejected; stdout
# shows the PF-* diagnostics to feed back into the agent repair loop.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$root"
proj="proofship/rwa-share-v1"

src_name="${1:-RwaShareRegistry.lean}"
module="${2:-${src_name%.lean}}"
cli="$root/.lake/build/bin/proof-forge-next"

[[ -x "$cli" ]] || { echo "gate: product CLI missing (run just build first)" >&2; exit 70; }
[[ -f "$proj/src/$src_name" ]] || { echo "gate: no such source: $proj/src/$src_name" >&2; exit 64; }

echo "== gate: check ==" >&2
"$cli" check "src/$src_name" --module "$module" --root "$proj"

echo "== gate: build (evm) ==" >&2
out="out-evm-$(echo "$module" | tr '[:upper:]' '[:lower:]')"
rm -rf "$proj/$out"  # product build fails closed on pre-existing output dir
"$cli" build "src/$src_name" --module "$module" --root "$proj" --target evm -o "$out"

echo "== gate: inspect (exact disk closure) ==" >&2
"$cli" inspect --output-dir "$proj/$out"

echo "gate: PASS $module → $proj/$out" >&2
