#!/usr/bin/env bash
set -euo pipefail

# Generate Psy source from the portable EventProbe IR and validate event emission
# through Psy's official Dargo toolchain.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${PSY_OUT_DIR:-$ROOT/build/psy}"
PROJECT_DIR="$OUT_DIR/dargo-event"
PSY_FILE="$OUT_DIR/EventProbe.psy"
GOLDEN_FILE="${PSY_GOLDEN:-$ROOT/Examples/Psy/EventProbe.golden.psy}"
DARGO_BIN="${DARGO:-dargo}"
PSY_HOME="${PSY_HOME:-$HOME/.psy}"
TEST_LOG="$OUT_DIR/event-test.log"
ABI_FILE="$PROJECT_DIR/target/EventProbe.json"
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
"$ROOT/.lake/build/bin/proof-forge" emit --target psy-dpn --fixture event -o "$PSY_FILE"
lake env lean --run "$ROOT/Tests/PsyMetadataExport.lean" EventProbe > "$PLAN_METADATA_FILE"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$PSY_FILE"
fi

if ! command -v "$DARGO_BIN" >/dev/null 2>&1; then
  echo "psy-event-smoke: dargo not found. Install the Psy toolchain with psyup, then re-run this script." >&2
  exit 127
fi

"$DARGO_BIN" test --file "$PSY_FILE" | tee "$TEST_LOG"

if ! grep -Fq "result_events: [PsyUserEventRecord" "$TEST_LOG"; then
  echo "psy-event-smoke: expected dargo test to emit a user event" >&2
  exit 1
fi

if ! grep -Fq "data: [42]" "$TEST_LOG"; then
  echo "psy-event-smoke: expected event data to contain [42]" >&2
  exit 1
fi

python3 "$ROOT/scripts/psy/write-dargo-package.py" \
  --project-dir "$PROJECT_DIR" \
  --source "$PSY_FILE" \
  --package-name "proof_forge_event" \
  --description "ProofForge generated EventProbe IR Psy smoke"

(
  cd "$PROJECT_DIR"
  "$DARGO_BIN" compile --contract-name EventProbe --method-names emit_value_event
  "$DARGO_BIN" generate-abi --contract-name EventProbe --output-dir target --pretty
  # Restore the deploy-oriented compile artifact after ABI generation.
  "$DARGO_BIN" compile --contract-name EventProbe --method-names emit_value_event
)

ARTIFACT="$PROJECT_DIR/target/proof_forge_event.json"
if [[ ! -s "$ARTIFACT" ]]; then
  echo "psy-event-smoke: expected non-empty Dargo artifact at $ARTIFACT" >&2
  exit 1
fi

if [[ ! -s "$ABI_FILE" ]]; then
  echo "psy-event-smoke: expected non-empty Dargo ABI at $ABI_FILE" >&2
  exit 1
fi

"$ROOT/scripts/psy/write-smoke-deploy-manifest.sh" \
  "$ROOT" \
  "EventProbe" \
  "EventProbe" \
  "$PSY_FILE" \
  "$ARTIFACT" \
  "$ABI_FILE" \
  "$DEPLOY_JSON_FILE"

python3 "$ROOT/scripts/psy/write-artifact-metadata.py" \
  --root "$ROOT" \
  --fixture EventProbe \
  --source "$PSY_FILE" \
  --package-source "$PROJECT_DIR/src/main.psy" \
  --circuit-json "$ARTIFACT" \
  --abi-json "$ABI_FILE" \
  --execute-log "$TEST_LOG" \
  --deploy-json "$DEPLOY_JSON_FILE" \
  --dargo-manifest "$PROJECT_DIR/Dargo.toml" \
  --out "$METADATA_FILE" \
  --dargo "$DARGO_BIN" \
  --execute-result "result_events: [PsyUserEventRecord" \
  --capability events.emit \
  --capability zk.circuit \
  --plan-metadata "$PLAN_METADATA_FILE"

python3 "$ROOT/scripts/psy/validate-artifact-metadata.py" \
  --root "$ROOT" \
  "$METADATA_FILE"

echo "psy-event-smoke: wrote $PSY_FILE"
echo "psy-event-smoke: Dargo artifact $ARTIFACT"
echo "psy-event-smoke: Dargo test log $TEST_LOG"
echo "psy-event-smoke: Dargo ABI $ABI_FILE"
echo "psy-event-smoke: ProofForge deploy JSON $DEPLOY_JSON_FILE"
echo "psy-event-smoke: ProofForge metadata $METADATA_FILE"
