#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${ROOT}/build/aleo"
LEO_FILE="${BUILD_DIR}/PureMath.leo"
GOLDEN_FILE="${ROOT}/Examples/Backend/Aleo/PureMath.golden.leo"
PROJECT_DIR="${BUILD_DIR}/pure-math"
SOURCE_FILE="${PROJECT_DIR}/src/main.leo"
METADATA_FILE="${PROJECT_DIR}/proof-forge-artifact.json"
LEO_BIN="${LEO_BIN:-leo}"

info() {
    echo "[aleo-pure-math-smoke] $*"
}

die() {
    echo "[aleo-pure-math-smoke] ERROR: $*" >&2
    exit 1
}

info "building proof-forge"
cd "${ROOT}"
lake build proof-forge

info "generating Aleo PureMath Leo source via ProofForge CLI"
mkdir -p "${BUILD_DIR}"
lake exe proof-forge emit --target aleo-leo --fixture pure-math --format leo -o "${LEO_FILE}"

if [ ! -s "${LEO_FILE}" ]; then
    die "generated Leo source is empty"
fi

info "diffing generated source against golden fixture"
diff -u "${GOLDEN_FILE}" "${LEO_FILE}"

if ! command -v "${LEO_BIN}" >/dev/null 2>&1; then
    echo "aleo-pure-math-smoke: leo not found. Install the Aleo CLI." >&2
    echo "aleo-pure-math-smoke: generated ${LEO_FILE} for inspection." >&2
    exit 127
fi

info "writing Leo package layout"
python3 "${ROOT}/scripts/aleo/write-pure-math-package.py" \
    --project-dir "${PROJECT_DIR}" \
    --source "${LEO_FILE}" \
    --program-name puremath

info "running 'leo build'"
cd "${PROJECT_DIR}"
"${LEO_BIN}" build

info "running 'leo test'"
"${LEO_BIN}" test

info "writing artifact metadata"
python3 "${ROOT}/scripts/aleo/write-pure-math-artifact-metadata.py" \
    --root "${ROOT}" \
    --source "${SOURCE_FILE}" \
    --leo-project "${PROJECT_DIR}" \
    --out "${METADATA_FILE}" \
    --leo "${LEO_BIN}"

info "validating artifact metadata"
python3 "${ROOT}/scripts/aleo/validate-artifact-metadata.py" \
    --root "${ROOT}" \
    "${METADATA_FILE}"

info "Aleo PureMath smoke completed successfully"
echo ""
echo "Artifacts:"
ls -lh "${PROJECT_DIR}/build/"
echo ""
echo "Metadata: ${METADATA_FILE}"
