#!/usr/bin/env bash
set -euo pipefail

# Quint MBT replay gate: emit Counter and ValueVault .qnt models, run
# `quint run --mbt`, and replay generated ITF traces against ProofForge IR
# semantics. Skips gracefully when `quint` is not on PATH.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build/quint"

mkdir -p "${BUILD_DIR}"

cd "${REPO_ROOT}"

if ! command -v quint &>/dev/null; then
  echo "SKIP: quint not found on PATH"
  exit 0
fi

echo "Running Quint control-flow model render tests..."
lake env lean --run Tests/Quint/ConditionalModel.lean
lake env lean --run Tests/Quint/LoopModel.lean

echo "Running Counter MBT replay test..."
lake env lean --run Tests/Quint/CounterReplay.lean

echo "Running ValueVault MBT replay test..."
lake env lean --run Tests/Quint/ValueVaultReplay.lean

echo "Running ConditionalProbe MBT replay test..."
lake env lean --run Tests/Quint/ConditionalReplay.lean

echo "Running LoopProbe MBT replay test..."
lake env lean --run Tests/Quint/LoopReplay.lean

echo "Quint MBT replay gate passed."
