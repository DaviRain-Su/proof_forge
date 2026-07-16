#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${ROOT}/build/cosmwasm"
WAT_FILE="${BUILD_DIR}/Counter.wat"
WASM_FILE="${BUILD_DIR}/Counter.wasm"
GOLDEN_FILE="${ROOT}/Examples/Backend/CosmWasm/Counter.golden.wat"
WAT2WASM_BIN="${WAT2WASM_BIN:-wat2wasm}"
COSMWASM_CHECK_BIN="${COSMWASM_CHECK_BIN:-cosmwasm-check}"
VM_RUNNER_DIR="${ROOT}/tools/cosmwasm-vm-runner"
VM_RUNNER_BIN="${VM_RUNNER_DIR}/target/debug/cosmwasm-vm-runner"

info() {
    echo "[cosmwasm-smoke] $*"
}

die() {
    echo "[cosmwasm-smoke] ERROR: $*" >&2
    exit 1
}

info "building proof-forge"
cd "${ROOT}"
lake build proof-forge

info "generating CosmWasm Counter WAT via ProofForge CLI"
mkdir -p "${BUILD_DIR}"
lake exe proof-forge emit --target wasm-cosmwasm --fixture counter --format wat -o "${WAT_FILE}"

if [ ! -s "${WAT_FILE}" ]; then
    die "generated WAT is empty"
fi

info "diffing generated WAT against golden fixture"
diff -u "${GOLDEN_FILE}" "${WAT_FILE}"

info "converting WAT to WASM with ${WAT2WASM_BIN}"
"${WAT2WASM_BIN}" "${WAT_FILE}" -o "${WASM_FILE}"

if [ ! -s "${WASM_FILE}" ]; then
    die "generated WASM is empty"
fi

info "validating WASM with ${COSMWASM_CHECK_BIN}"
"${COSMWASM_CHECK_BIN}" "${WASM_FILE}"

info "running Counter lifecycle in cosmwasm-vm"
cd "${VM_RUNNER_DIR}"
cargo build
cd "${ROOT}"
"${VM_RUNNER_BIN}" "${WASM_FILE}"

info "CosmWasm counter smoke completed successfully"
echo ""
echo "Artifacts:"
ls -lh "${WAT_FILE}" "${WASM_FILE}"
