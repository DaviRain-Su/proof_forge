#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${ROOT}/build/aleo"
LEO_FILE="${BUILD_DIR}/Counter.leo"

info() {
    echo "[aleo-smoke] $*"
}

die() {
    echo "[aleo-smoke] ERROR: $*" >&2
    exit 1
}

info "building proof-forge"
cd "${ROOT}"
lake build proof-forge

info "verifying full Counter fails closed instead of changing get() -> U64 to Final"
mkdir -p "${BUILD_DIR}"
rm -f "${LEO_FILE}"
set +e
diagnostic="$(lake exe proof-forge emit --target aleo-leo --fixture counter --format leo -o "${LEO_FILE}" 2>&1)"
status=$?
set -e

[[ "$status" -ne 0 ]] || die "full Counter unexpectedly emitted Leo source"
[[ ! -e "${LEO_FILE}" ]] || die "failed Counter emission left a misleading artifact"
echo "$diagnostic" | grep -Fq 'mapping-backed `get() -> U64` result cannot cross `final`' \
    || die "unexpected Counter rejection diagnostic: ${diagnostic}"

info "Counter rejection is stable; PureMath is the executable sourcegen smoke"
