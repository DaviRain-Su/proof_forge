#!/usr/bin/env bash
set -euo pipefail

# Generate Psy source from the hand-written ArrayProbe IR and validate
# fixed-array value and storage lowering through Psy's official Dargo toolchain.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${PSY_OUT_DIR:-$ROOT/build/psy}"
PROJECT_DIR="$OUT_DIR/dargo-array"
PSY_FILE="$OUT_DIR/ArrayProbe.psy"
GOLDEN_FILE="${PSY_GOLDEN:-$ROOT/Examples/Backend/Psy/ArrayProbe.golden.psy}"
DARGO_BIN="${DARGO:-dargo}"
PSY_HOME="${PSY_HOME:-$HOME/.psy}"
EXEC_LOG="$PROJECT_DIR/target/array-execute.log"
ABI_FILE="$PROJECT_DIR/target/ArrayProbe.json"
DEPLOY_JSON_FILE="$PROJECT_DIR/target/proof-forge-deploy.json"
METADATA_FILE="$PROJECT_DIR/target/proof-forge-artifact.json"
PLAN_METADATA_FILE="$PROJECT_DIR/target/plan-metadata.json"
ARRAY_LITERAL_RESULT="result_vm: [60]"
ARRAY_STORAGE_RESULT="result_vm: [31]"
ARRAY_PREDICATES_RESULT="result_vm: [1]"

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
"$ROOT/.lake/build/bin/proof-forge" emit --target psy-dpn --fixture array -o "$PSY_FILE"
lake env lean --run "$ROOT/Tests/PsyMetadataExport.lean" ArrayProbe > "$PLAN_METADATA_FILE"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$PSY_FILE"
fi

if ! command -v "$DARGO_BIN" >/dev/null 2>&1; then
  echo "psy-array-smoke: dargo not found. Install the Psy toolchain with psyup, then re-run this script." >&2
  echo "psy-array-smoke: generated $PSY_FILE for inspection." >&2
  echo "psy-array-smoke: install: curl -fsSL https://raw.githubusercontent.com/QEDProtocol/psyup/main/install.sh | bash" >&2
  echo "psy-array-smoke: macOS arm64 note: psyup latest may not have a matching tarball; v0.1.0 is known to include one." >&2
  echo "psy-array-smoke: docs: https://docs.psy-protocol.xyz/language/dargo.html" >&2
  exit 127
fi

"$DARGO_BIN" test --file "$PSY_FILE"

python3 "$ROOT/scripts/psy/write-dargo-package.py" \
  --project-dir "$PROJECT_DIR" \
  --source "$PSY_FILE" \
  --package-name "proof_forge_array" \
  --description "ProofForge generated ArrayProbe IR Psy smoke"

(
  cd "$PROJECT_DIR"
  "$DARGO_BIN" compile --contract-name ArrayProbe --method-names sum_literal storage_lifecycle array_predicates
  : > "$EXEC_LOG"
  "$DARGO_BIN" execute --contract-name ArrayProbe --method-names sum_literal | tee -a "$EXEC_LOG"
  "$DARGO_BIN" execute --contract-name ArrayProbe --method-names storage_lifecycle | tee -a "$EXEC_LOG"
  "$DARGO_BIN" execute --contract-name ArrayProbe --method-names array_predicates | tee -a "$EXEC_LOG"
  "$DARGO_BIN" generate-abi --contract-name ArrayProbe --output-dir target --pretty
  "$DARGO_BIN" compile --contract-name ArrayProbe --method-names sum_literal storage_lifecycle array_predicates
)

ARTIFACT="$PROJECT_DIR/target/proof_forge_array.json"
if [[ ! -s "$ARTIFACT" ]]; then
  echo "psy-array-smoke: expected non-empty Dargo artifact at $ARTIFACT" >&2
  exit 1
fi

if ! grep -Fq "$ARRAY_LITERAL_RESULT" "$EXEC_LOG"; then
  echo "psy-array-smoke: expected sum_literal execute to return $ARRAY_LITERAL_RESULT" >&2
  echo "psy-array-smoke: execution log: $EXEC_LOG" >&2
  exit 1
fi

if ! grep -Fq "$ARRAY_STORAGE_RESULT" "$EXEC_LOG"; then
  echo "psy-array-smoke: expected storage_lifecycle execute to return $ARRAY_STORAGE_RESULT" >&2
  echo "psy-array-smoke: execution log: $EXEC_LOG" >&2
  exit 1
fi

if ! grep -Fq "$ARRAY_PREDICATES_RESULT" "$EXEC_LOG"; then
  echo "psy-array-smoke: expected array_predicates execute to return $ARRAY_PREDICATES_RESULT" >&2
  echo "psy-array-smoke: execution log: $EXEC_LOG" >&2
  exit 1
fi

if [[ ! -s "$ABI_FILE" ]]; then
  echo "psy-array-smoke: expected non-empty Dargo ABI at $ABI_FILE" >&2
  exit 1
fi

"$ROOT/scripts/psy/write-smoke-deploy-manifest.sh" \
  "$ROOT" \
  "ArrayProbe" \
  "ArrayProbe" \
  "$PSY_FILE" \
  "$ARTIFACT" \
  "$ABI_FILE" \
  "$DEPLOY_JSON_FILE"

python3 "$ROOT/scripts/psy/write-artifact-metadata.py" \
  --root "$ROOT" \
  --fixture ArrayProbe \
  --source "$PSY_FILE" \
  --package-source "$PROJECT_DIR/src/main.psy" \
  --circuit-json "$ARTIFACT" \
  --abi-json "$ABI_FILE" \
  --execute-log "$EXEC_LOG" \
  --deploy-json "$DEPLOY_JSON_FILE" \
  --dargo-manifest "$PROJECT_DIR/Dargo.toml" \
  --out "$METADATA_FILE" \
  --dargo "$DARGO_BIN" \
  --execute-result "$ARRAY_LITERAL_RESULT; $ARRAY_STORAGE_RESULT; $ARRAY_PREDICATES_RESULT" \
  --dargo-ran \
  --capability data.fixed_array \
  --capability storage.array \
  --capability zk.circuit \
  --plan-metadata "$PLAN_METADATA_FILE"

python3 "$ROOT/scripts/psy/validate-artifact-metadata.py" \
  --root "$ROOT" \
  "$METADATA_FILE"

echo "psy-array-smoke: wrote $PSY_FILE"
echo "psy-array-smoke: Dargo artifact $ARTIFACT"
echo "psy-array-smoke: Dargo execute log $EXEC_LOG"
echo "psy-array-smoke: Dargo ABI $ABI_FILE"
echo "psy-array-smoke: ProofForge deploy JSON $DEPLOY_JSON_FILE"
echo "psy-array-smoke: ProofForge metadata $METADATA_FILE"
