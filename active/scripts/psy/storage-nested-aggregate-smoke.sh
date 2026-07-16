#!/usr/bin/env bash
set -euo pipefail

# Generate Psy source from the hand-written StorageNestedAggregateProbe IR and
# validate storage-backed nested aggregate paths through Dargo.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${PSY_OUT_DIR:-$ROOT/build/psy}"
PROJECT_DIR="$OUT_DIR/dargo-storage-nested-aggregate"
PSY_FILE="$OUT_DIR/StorageNestedAggregateProbe.psy"
GOLDEN_FILE="${PSY_GOLDEN:-$ROOT/Examples/Backend/Psy/StorageNestedAggregateProbe.golden.psy}"
DARGO_BIN="${DARGO:-dargo}"
PSY_HOME="${PSY_HOME:-$HOME/.psy}"
EXEC_LOG="$PROJECT_DIR/target/storage-nested-aggregate-execute.log"
ABI_FILE="$PROJECT_DIR/target/StorageNestedAggregateProbe.json"
DEPLOY_JSON_FILE="$PROJECT_DIR/target/proof-forge-deploy.json"
METADATA_FILE="$PROJECT_DIR/target/proof-forge-artifact.json"
PLAN_METADATA_FILE="$PROJECT_DIR/target/plan-metadata.json"
STORAGE_NESTED_AGGREGATE_RESULT="result_vm: [252]"

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
"$ROOT/.lake/build/bin/proof-forge" emit --target psy-dpn --fixture storage-nested-aggregate -o "$PSY_FILE"
lake env lean --run "$ROOT/Tests/PsyMetadataExport.lean" StorageNestedAggregateProbe > "$PLAN_METADATA_FILE"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$PSY_FILE"
fi

if ! command -v "$DARGO_BIN" >/dev/null 2>&1; then
  echo "psy-storage-nested-aggregate-smoke: dargo not found. Install the Psy toolchain with psyup, then re-run this script." >&2
  echo "psy-storage-nested-aggregate-smoke: generated $PSY_FILE for inspection." >&2
  echo "psy-storage-nested-aggregate-smoke: install: curl -fsSL https://raw.githubusercontent.com/QEDProtocol/psyup/main/install.sh | bash" >&2
  echo "psy-storage-nested-aggregate-smoke: macOS arm64 note: psyup latest may not have a matching tarball; v0.1.0 is known to include one." >&2
  echo "psy-storage-nested-aggregate-smoke: docs: https://docs.psy-protocol.xyz/language/dargo.html" >&2
  exit 127
fi

"$DARGO_BIN" test --file "$PSY_FILE"

python3 "$ROOT/scripts/psy/write-dargo-package.py" \
  --project-dir "$PROJECT_DIR" \
  --source "$PSY_FILE" \
  --package-name "proof_forge_storage_nested_aggregate" \
  --description "ProofForge generated StorageNestedAggregateProbe IR Psy smoke"

(
  cd "$PROJECT_DIR"
  "$DARGO_BIN" compile --contract-name StorageNestedAggregateProbe --method-names storage_nested_lifecycle
  "$DARGO_BIN" execute --contract-name StorageNestedAggregateProbe --method-names storage_nested_lifecycle | tee "$EXEC_LOG"
  "$DARGO_BIN" generate-abi --contract-name StorageNestedAggregateProbe --output-dir target --pretty
  "$DARGO_BIN" compile --contract-name StorageNestedAggregateProbe --method-names storage_nested_lifecycle
)

ARTIFACT="$PROJECT_DIR/target/proof_forge_storage_nested_aggregate.json"
if [[ ! -s "$ARTIFACT" ]]; then
  echo "psy-storage-nested-aggregate-smoke: expected non-empty Dargo artifact at $ARTIFACT" >&2
  exit 1
fi

if ! grep -Fq "$STORAGE_NESTED_AGGREGATE_RESULT" "$EXEC_LOG"; then
  echo "psy-storage-nested-aggregate-smoke: expected storage_nested_lifecycle execute to return $STORAGE_NESTED_AGGREGATE_RESULT" >&2
  echo "psy-storage-nested-aggregate-smoke: execution log: $EXEC_LOG" >&2
  exit 1
fi

if [[ ! -s "$ABI_FILE" ]]; then
  echo "psy-storage-nested-aggregate-smoke: expected non-empty Dargo ABI at $ABI_FILE" >&2
  exit 1
fi

"$ROOT/scripts/psy/write-smoke-deploy-manifest.sh" \
  "$ROOT" \
  "StorageNestedAggregateProbe" \
  "StorageNestedAggregateProbe" \
  "$PSY_FILE" \
  "$ARTIFACT" \
  "$ABI_FILE" \
  "$DEPLOY_JSON_FILE"

python3 "$ROOT/scripts/psy/write-artifact-metadata.py" \
  --root "$ROOT" \
  --fixture StorageNestedAggregateProbe \
  --source "$PSY_FILE" \
  --package-source "$PROJECT_DIR/src/main.psy" \
  --circuit-json "$ARTIFACT" \
  --abi-json "$ABI_FILE" \
  --execute-log "$EXEC_LOG" \
  --deploy-json "$DEPLOY_JSON_FILE" \
  --dargo-manifest "$PROJECT_DIR/Dargo.toml" \
  --out "$METADATA_FILE" \
  --dargo "$DARGO_BIN" \
  --execute-result "$STORAGE_NESTED_AGGREGATE_RESULT" \
  --dargo-ran \
  --capability data.struct \
  --capability data.fixed_array \
  --capability storage.scalar \
  --capability storage.array \
  --capability zk.circuit \
  --plan-metadata "$PLAN_METADATA_FILE"

python3 "$ROOT/scripts/psy/validate-artifact-metadata.py" \
  --root "$ROOT" \
  "$METADATA_FILE"

echo "psy-storage-nested-aggregate-smoke: wrote $PSY_FILE"
echo "psy-storage-nested-aggregate-smoke: Dargo artifact $ARTIFACT"
echo "psy-storage-nested-aggregate-smoke: Dargo execute log $EXEC_LOG"
echo "psy-storage-nested-aggregate-smoke: Dargo ABI $ABI_FILE"
echo "psy-storage-nested-aggregate-smoke: ProofForge deploy JSON $DEPLOY_JSON_FILE"
echo "psy-storage-nested-aggregate-smoke: ProofForge metadata $METADATA_FILE"
