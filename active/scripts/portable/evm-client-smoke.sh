#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="${PROOF_FORGE_INIT_OUT:-build/evm-client-smoke}"
export PATH="$HOME/.foundry/bin:$PATH"

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"

(cd "$ROOT" && lake build proof-forge >/dev/null)

echo "evm-client-smoke: scaffold project"
lake env proof-forge init "$OUT"

if [[ "${INIT_USE_LOCAL_PROOF_FORGE:-1}" == "1" ]]; then
  cat >"$OUT/lakefile.lean" <<'EOF'
import Lake
open Lake DSL

require proofForge from "../.."

package «evm-client-smoke» where
  version := v!"0.1.0"

lean_lib Counter where
  roots := #[`Counter]
EOF
fi

echo "evm-client-smoke: build EVM artifacts + client"
(cd "$OUT" && lake update >/dev/null && just build-evm)

CLIENT="$OUT/build/evm/proof-forge-evm-abi.ts"
SPEC="$OUT/build/evm/Counter.contract-spec.json"
METADATA="$OUT/build/evm/Counter.proof-forge-artifact.json"

test -f "$CLIENT"
test -f "$SPEC"
test -f "$METADATA"
grep -Fq "deployFromArtifactDir" "$CLIENT"
grep -Fq "ARTIFACT_PATHS" "$CLIENT"
grep -Fq '"client"' "$METADATA"
grep -Fq '"contractSpec"' "$METADATA"

echo "evm-client-smoke: ok"
