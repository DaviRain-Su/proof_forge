#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="${PROOF_FORGE_INIT_OUT:-build/init-smoke-project}"

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"

(cd "$ROOT" && lake build proof-forge >/dev/null)

echo "init-smoke: scaffold project"
lake env proof-forge init "$OUT"

if [[ "${INIT_USE_LOCAL_PROOF_FORGE:-1}" == "1" ]]; then
  cat >"$OUT/lakefile.lean" <<'EOF'
import Lake
open Lake DSL

require proofForge from "../.."

package «init-smoke» where
  version := v!"0.1.0"

lean_lib Counter where
  roots := #[`Counter]
EOF
fi

echo "init-smoke: build Counter source"
(cd "$OUT" && lake update >/dev/null && lake build Counter >/dev/null)

echo "init-smoke: EVM"
(cd "$OUT" && just build-evm)

echo "init-smoke: Solana"
(cd "$OUT" && just build-solana)

test -f "$OUT/build/evm/Counter.bin"
test -f "$OUT/build/solana/Counter.s"

echo "init-smoke: ok"
