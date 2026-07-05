#!/usr/bin/env bash
set -euo pipefail

# Quint MBT replay gate: emit Counter .qnt model, run `quint run --mbt`,
# and replay generated ITF traces against ProofForge IR semantics.
# Skips gracefully when `quint` is not on PATH.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build/quint"

mkdir -p "${BUILD_DIR}"

cd "${REPO_ROOT}"

if ! command -v quint &>/dev/null; then
  echo "SKIP: quint not found on PATH"
  exit 0
fi

echo "Running MBT replay test..."
lake env lean --run Tests/Quint/CounterReplay.lean

echo "Quint MBT replay gate passed."
