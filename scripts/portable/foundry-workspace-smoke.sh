#!/usr/bin/env bash
set -euo pipefail

# Validate that a portable Counter project can feed stable build/evm artifacts
# into the checked-in Foundry workspace (forge test + forge script).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="${PROOF_FORGE_INIT_OUT:-build/foundry-workspace-smoke}"
export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "foundry-workspace-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "foundry-workspace-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"

(cd "$ROOT" && lake build proof-forge >/dev/null)

echo "foundry-workspace-smoke: scaffold project"
lake env proof-forge init "$OUT"

if [[ "${INIT_USE_LOCAL_PROOF_FORGE:-1}" == "1" ]]; then
  cat >"$OUT/lakefile.lean" <<'EOF'
import Lake
open Lake DSL

require proofForge from "../.."

package «foundry-workspace-smoke» where
  version := v!"0.1.0"

lean_lib Counter where
  roots := #[`Counter]
EOF
fi

test -d "$OUT/foundry/test"
test -f "$OUT/foundry/foundry.toml"
test -f "$OUT/foundry/script/DeployCounter.s.sol"

echo "foundry-workspace-smoke: build EVM artifacts"
(cd "$OUT" && lake update >/dev/null && just build-evm)

test -f "$OUT/build/evm/Counter.bin"
test -f "$OUT/build/evm/Counter.init.bin"

echo "foundry-workspace-smoke: forge test"
(cd "$OUT" && just forge-test)

echo "foundry-workspace-smoke: forge script"
(cd "$OUT" && just forge-script)

echo "foundry-workspace-smoke: ok"
