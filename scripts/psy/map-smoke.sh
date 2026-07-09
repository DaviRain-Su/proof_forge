#!/usr/bin/env bash
set -euo pipefail

# Generate Psy source from the hand-written MapProbe IR and validate
# storage.map lowering through Psy's official Dargo toolchain.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${PSY_OUT_DIR:-$ROOT/build/psy}"
PROJECT_DIR="$OUT_DIR/dargo-map"
PSY_FILE="$OUT_DIR/MapProbe.psy"
GOLDEN_FILE="${PSY_GOLDEN:-$ROOT/Examples/Backend/Psy/MapProbe.golden.psy}"
DARGO_BIN="${DARGO:-dargo}"
PSY_HOME="${PSY_HOME:-$HOME/.psy}"
EXEC_LOG="$PROJECT_DIR/target/map-execute.log"
ABI_FILE="$PROJECT_DIR/target/MapProbe.json"
DEPLOY_JSON_FILE="$PROJECT_DIR/target/proof-forge-deploy.json"
METADATA_FILE="$PROJECT_DIR/target/proof-forge-artifact.json"
PLAN_METADATA_FILE="$PROJECT_DIR/target/plan-metadata.json"
MAP_RESULT="result_vm: [55, 66, 77, 88]"
MAP_PATH_RESULT="result_vm: [77, 88, 99, 111]"
MAP_SET_RETURN_RESULT="result_vm: [31, 32, 33, 34]"
MAP_INSERT_RETURN_RESULT="result_vm: [5, 6, 7, 8]"

if [[ -z "${DARGO_STD_PATH:-}" && -f "$PSY_HOME/env" ]]; then
  # psyup writes DARGO_STD_PATH here; sourcing avoids a slow stdlib fallback.
  # shellcheck source=/dev/null
  source "$PSY_HOME/env"
fi

if [[ "$DARGO_BIN" == "dargo" && ! -x "$(command -v dargo 2>/dev/null || true)" && -x "$PSY_HOME/bin/dargo" ]]; then
  DARGO_BIN="$PSY_HOME/bin/dargo"
fi

mkdir -p "$OUT_DIR"

lake build proof-forge >/dev/null
lake build ProofForge.Backend.Psy.Metadata >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target psy-dpn --fixture map -o "$PSY_FILE"
lake env lean --run "$ROOT/Tests/PsyMetadataExport.lean" MapProbe > "$PLAN_METADATA_FILE"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$PSY_FILE"
fi

if ! command -v "$DARGO_BIN" >/dev/null 2>&1; then
  echo "psy-map-smoke: dargo not found. Install the Psy toolchain with psyup, then re-run this script." >&2
  echo "psy-map-smoke: generated $PSY_FILE for inspection." >&2
  echo "psy-map-smoke: install: curl -fsSL https://raw.githubusercontent.com/QEDProtocol/psyup/main/install.sh | bash" >&2
  echo "psy-map-smoke: macOS arm64 note: psyup latest may not have a matching tarball; v0.1.0 is known to include one." >&2
  echo "psy-map-smoke: docs: https://docs.psy-protocol.xyz/language/dargo.html" >&2
  exit 127
fi

"$DARGO_BIN" test --file "$PSY_FILE"

python3 "$ROOT/scripts/psy/write-dargo-package.py" \
  --project-dir "$PROJECT_DIR" \
  --source "$PSY_FILE" \
  --package-name "proof_forge_map" \
  --description "ProofForge generated MapProbe IR Psy smoke"

(
  cd "$PROJECT_DIR"
  "$DARGO_BIN" compile --contract-name MapProbe --method-names map_lifecycle get_seed_balance has_seed_balance upsert_balance set_balance path_lifecycle set_return_lifecycle insert_return_lifecycle
  : > "$EXEC_LOG"
  "$DARGO_BIN" execute --contract-name MapProbe --method-names map_lifecycle | tee -a "$EXEC_LOG"
  "$DARGO_BIN" execute --contract-name MapProbe --method-names path_lifecycle | tee -a "$EXEC_LOG"
  "$DARGO_BIN" execute --contract-name MapProbe --method-names set_return_lifecycle | tee -a "$EXEC_LOG"
  "$DARGO_BIN" execute --contract-name MapProbe --method-names insert_return_lifecycle | tee -a "$EXEC_LOG"
  "$DARGO_BIN" generate-abi --contract-name MapProbe --output-dir target --pretty
  "$DARGO_BIN" compile --contract-name MapProbe --method-names map_lifecycle get_seed_balance has_seed_balance upsert_balance set_balance path_lifecycle set_return_lifecycle insert_return_lifecycle
)

ARTIFACT="$PROJECT_DIR/target/proof_forge_map.json"
if [[ ! -s "$ARTIFACT" ]]; then
  echo "psy-map-smoke: expected non-empty Dargo artifact at $ARTIFACT" >&2
  exit 1
fi

if ! grep -Fq "$MAP_RESULT" "$EXEC_LOG"; then
  echo "psy-map-smoke: expected map_lifecycle execute to return $MAP_RESULT" >&2
  echo "psy-map-smoke: execution log: $EXEC_LOG" >&2
  exit 1
fi

if ! grep -Fq "$MAP_PATH_RESULT" "$EXEC_LOG"; then
  echo "psy-map-smoke: expected path_lifecycle execute to return $MAP_PATH_RESULT" >&2
  echo "psy-map-smoke: execution log: $EXEC_LOG" >&2
  exit 1
fi

if ! grep -Fq "$MAP_SET_RETURN_RESULT" "$EXEC_LOG"; then
  echo "psy-map-smoke: expected set_return_lifecycle execute to return $MAP_SET_RETURN_RESULT" >&2
  echo "psy-map-smoke: execution log: $EXEC_LOG" >&2
  exit 1
fi

if ! grep -Fq "$MAP_INSERT_RETURN_RESULT" "$EXEC_LOG"; then
  echo "psy-map-smoke: expected insert_return_lifecycle execute to return $MAP_INSERT_RETURN_RESULT" >&2
  echo "psy-map-smoke: execution log: $EXEC_LOG" >&2
  exit 1
fi

if [[ ! -s "$ABI_FILE" ]]; then
  echo "psy-map-smoke: expected non-empty Dargo ABI at $ABI_FILE" >&2
  exit 1
fi

"$ROOT/scripts/psy/write-smoke-deploy-manifest.sh" \
  "$ROOT" \
  "MapProbe" \
  "MapProbe" \
  "$PSY_FILE" \
  "$ARTIFACT" \
  "$ABI_FILE" \
  "$DEPLOY_JSON_FILE"

python3 "$ROOT/scripts/psy/write-artifact-metadata.py" \
  --root "$ROOT" \
  --fixture MapProbe \
  --source "$PSY_FILE" \
  --package-source "$PROJECT_DIR/src/main.psy" \
  --circuit-json "$ARTIFACT" \
  --abi-json "$ABI_FILE" \
  --execute-log "$EXEC_LOG" \
  --deploy-json "$DEPLOY_JSON_FILE" \
  --dargo-manifest "$PROJECT_DIR/Dargo.toml" \
  --out "$METADATA_FILE" \
  --dargo "$DARGO_BIN" \
  --execute-result "$MAP_RESULT; $MAP_PATH_RESULT; $MAP_SET_RETURN_RESULT; $MAP_INSERT_RETURN_RESULT" \
  --dargo-ran \
  --capability storage.map \
  --capability zk.circuit \
  --plan-metadata "$PLAN_METADATA_FILE"

python3 "$ROOT/scripts/psy/validate-artifact-metadata.py" \
  --root "$ROOT" \
  "$METADATA_FILE"

echo "psy-map-smoke: wrote $PSY_FILE"
echo "psy-map-smoke: Dargo artifact $ARTIFACT"
echo "psy-map-smoke: Dargo execute log $EXEC_LOG"
echo "psy-map-smoke: Dargo ABI $ABI_FILE"
echo "psy-map-smoke: ProofForge deploy JSON $DEPLOY_JSON_FILE"
echo "psy-map-smoke: ProofForge metadata $METADATA_FILE"
