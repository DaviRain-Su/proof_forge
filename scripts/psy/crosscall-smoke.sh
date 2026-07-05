#!/usr/bin/env bash
set -euo pipefail

# Generate Psy source from the portable CrosscallProbe IR and validate that
# cross-contract invocation syntax is accepted by Dargo compilation.
# Dargo 0.1.0 does not yet execute synchronous cross-contract calls locally, so
# this smoke validates test/compile/ABI only.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${PSY_OUT_DIR:-$ROOT/build/psy}"
PROJECT_DIR="$OUT_DIR/dargo-crosscall"
PSY_FILE="$OUT_DIR/CrosscallProbe.psy"
GOLDEN_FILE="${PSY_GOLDEN:-$ROOT/Examples/Psy/CrosscallProbe.golden.psy}"
DARGO_BIN="${DARGO:-dargo}"
PSY_HOME="${PSY_HOME:-$HOME/.psy}"
TEST_LOG="$OUT_DIR/crosscall-test.log"
ABI_FILE="$PROJECT_DIR/target/CrosscallProbe.json"
DEPLOY_JSON_FILE="$PROJECT_DIR/target/proof-forge-deploy.json"
METADATA_FILE="$PROJECT_DIR/target/proof-forge-artifact.json"
PLAN_METADATA_FILE="$PROJECT_DIR/target/plan-metadata.json"

if [[ -z "${DARGO_STD_PATH:-}" && -f "$PSY_HOME/env" ]]; then
  # shellcheck source=/dev/null
  source "$PSY_HOME/env"
fi

if [[ "$DARGO_BIN" == "dargo" && ! -x "$(command -v dargo 2>/dev/null || true)" && -x "$PSY_HOME/bin/dargo" ]]; then
  DARGO_BIN="$PSY_HOME/bin/dargo"
fi

mkdir -p "$OUT_DIR" "$PROJECT_DIR"

lake build proof-forge >/dev/null
lake build ProofForge.Backend.Psy.Metadata >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target psy-dpn --fixture crosscall -o "$PSY_FILE"
lake env lean --run "$ROOT/Tests/PsyMetadataExport.lean" CrosscallProbe > "$PLAN_METADATA_FILE"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$PSY_FILE"
fi

if ! command -v "$DARGO_BIN" >/dev/null 2>&1; then
  echo "psy-crosscall-smoke: dargo not found. Install the Psy toolchain with psyup, then re-run this script." >&2
  exit 127
fi

"$DARGO_BIN" test --file "$PSY_FILE" | tee "$TEST_LOG"

python3 "$ROOT/scripts/psy/write-dargo-package.py" \
  --project-dir "$PROJECT_DIR" \
  --source "$PSY_FILE" \
  --package-name "proof_forge_crosscall" \
  --description "ProofForge generated CrosscallProbe IR Psy smoke"

(
  cd "$PROJECT_DIR"
  "$DARGO_BIN" compile --contract-name CrosscallProbe --method-names call_remote
  "$DARGO_BIN" generate-abi --contract-name CrosscallProbe --output-dir target --pretty
  # Restore the deploy-oriented compile artifact after ABI generation.
  "$DARGO_BIN" compile --contract-name CrosscallProbe --method-names call_remote
)

ARTIFACT="$PROJECT_DIR/target/proof_forge_crosscall.json"
if [[ ! -s "$ARTIFACT" ]]; then
  echo "psy-crosscall-smoke: expected non-empty Dargo artifact at $ARTIFACT" >&2
  exit 1
fi

if [[ ! -s "$ABI_FILE" ]]; then
  echo "psy-crosscall-smoke: expected non-empty Dargo ABI at $ABI_FILE" >&2
  exit 1
fi

"$ROOT/scripts/psy/write-smoke-deploy-manifest.sh" \
  "$ROOT" \
  "CrosscallProbe" \
  "CrosscallProbe" \
  "$PSY_FILE" \
  "$ARTIFACT" \
  "$ABI_FILE" \
  "$DEPLOY_JSON_FILE"

python3 "$ROOT/scripts/psy/write-artifact-metadata.py" \
  --root "$ROOT" \
  --fixture CrosscallProbe \
  --source "$PSY_FILE" \
  --package-source "$PROJECT_DIR/src/main.psy" \
  --circuit-json "$ARTIFACT" \
  --abi-json "$ABI_FILE" \
  --execute-log "$TEST_LOG" \
  --deploy-json "$DEPLOY_JSON_FILE" \
  --dargo-manifest "$PROJECT_DIR/Dargo.toml" \
  --out "$METADATA_FILE" \
  --dargo "$DARGO_BIN" \
  --execute-result "result_vm: []" \
  --capability crosscall.invoke \
  --capability zk.circuit \
  --plan-metadata "$PLAN_METADATA_FILE"

python3 "$ROOT/scripts/psy/validate-artifact-metadata.py" \
  --root "$ROOT" \
  "$METADATA_FILE"

echo "psy-crosscall-smoke: wrote $PSY_FILE"
echo "psy-crosscall-smoke: Dargo artifact $ARTIFACT"
echo "psy-crosscall-smoke: Dargo test log $TEST_LOG"
echo "psy-crosscall-smoke: Dargo ABI $ABI_FILE"
echo "psy-crosscall-smoke: ProofForge deploy JSON $DEPLOY_JSON_FILE"
echo "psy-crosscall-smoke: ProofForge metadata $METADATA_FILE"
