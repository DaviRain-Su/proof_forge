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
  if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "ERROR: quint not found on PATH (required in CI)"
    exit 1
  fi
  echo "SKIP: quint not found on PATH"
  exit 0
fi

echo "Running Quint fixture registry test..."
lake env lean --run Tests/Quint/CliEmit.lean

echo "Running Counter/ValueVault model render tests..."
lake env lean --run Tests/Quint/CounterModel.lean
lake env lean --run Tests/Quint/ValueVaultModel.lean

echo "Running Quint control-flow model render tests..."
lake env lean --run Tests/Quint/ConditionalModel.lean
lake env lean --run Tests/Quint/LoopModel.lean
lake env lean --run Tests/Quint/WhileModel.lean
lake env lean --run Tests/Quint/ArrayModel.lean
lake env lean --run Tests/Quint/MapModel.lean
lake env lean --run Tests/Quint/MapPathModel.lean
lake env lean --run Tests/Quint/MapNestedPathModel.lean
lake env lean --run Tests/Quint/MapPathAssignModel.lean
lake env lean --run Tests/Quint/MapHashPathAssignModel.lean
lake env lean --run Tests/Quint/StructModel.lean
lake env lean --run Tests/Quint/ArrayPathModel.lean
lake env lean --run Tests/Quint/StructPathModel.lean
lake env lean --run Tests/Quint/StructDynamicPathGuard.lean
lake env lean --run Tests/Quint/StructDynamicPathModel.lean
lake env lean --run Tests/Quint/AssignmentModel.lean
lake env lean --run Tests/Quint/CrosscallModel.lean
lake env lean --run Tests/Quint/AssertModel.lean

echo "Running Counter MBT replay test..."
lake env lean --run Tests/Quint/CounterReplay.lean

echo "Running ValueVault MBT replay test..."
lake env lean --run Tests/Quint/ValueVaultReplay.lean

echo "Running ConditionalProbe MBT replay test..."
lake env lean --run Tests/Quint/ConditionalReplay.lean

echo "Running LoopProbe MBT replay test..."
lake env lean --run Tests/Quint/LoopReplay.lean

echo "Running WhileProbe MBT replay test..."
lake env lean --run Tests/Quint/WhileReplay.lean

echo "Running ArrayProbe MBT replay test..."
lake env lean --run Tests/Quint/ArrayReplay.lean

echo "Running MapProbe MBT replay test..."
lake env lean --run Tests/Quint/MapReplay.lean

echo "Running MapProbe path MBT replay test..."
lake env lean --run Tests/Quint/MapPathReplay.lean

echo "Running MapProbe nested path MBT replay test..."
lake env lean --run Tests/Quint/MapNestedPathReplay.lean

echo "Running MapProbe path assign MBT replay test..."
lake env lean --run Tests/Quint/MapPathAssignReplay.lean

echo "Running MapProbe hash path assign MBT replay test..."
lake env lean --run Tests/Quint/MapHashPathAssignReplay.lean

echo "Running StructProbe MBT replay test..."
lake env lean --run Tests/Quint/StructReplay.lean

echo "Running ArrayPathProbe MBT replay test..."
lake env lean --run Tests/Quint/ArrayPathReplay.lean

echo "Running StructPathProbe MBT replay test..."
lake env lean --run Tests/Quint/StructPathReplay.lean

echo "Running StructDynamicPathProbe MBT replay test..."
lake env lean --run Tests/Quint/StructDynamicPathReplay.lean

echo "Running AssignmentProbe MBT replay test..."
lake env lean --run Tests/Quint/AssignmentReplay.lean

echo "Running CrosscallProbe MBT replay test..."
lake env lean --run Tests/Quint/CrosscallReplay.lean

echo "Running AssertProbe MBT replay test..."
lake env lean --run Tests/Quint/AssertReplay.lean

echo "Building proof-forge CLI for emit smoke..."
lake build proof-forge

echo "Running Quint CLI emit smoke..."
lake env proof-forge emit --target quint --fixture conditional -o build/quint/CliConditional.qnt
lake env proof-forge emit --target quint --fixture loop -o build/quint/CliLoop.qnt
lake env proof-forge emit --target quint --fixture while -o build/quint/CliWhile.qnt
test "$(wc -c < build/quint/CliWhile.qnt)" -lt 8192
lake env proof-forge emit --target quint --fixture array -o build/quint/CliArray.qnt
lake env proof-forge emit --target quint --fixture map -o build/quint/CliMap.qnt
lake env proof-forge emit --target quint --fixture map-path -o build/quint/CliMapPath.qnt
lake env proof-forge emit --target quint --fixture map-nested-path -o build/quint/CliMapNestedPath.qnt
lake env proof-forge emit --target quint --fixture map-path-assign -o build/quint/CliMapPathAssign.qnt
lake env proof-forge emit --target quint --fixture map-hash-path-assign -o build/quint/CliMapHashPathAssign.qnt
lake env proof-forge emit --target quint --fixture struct -o build/quint/CliStruct.qnt
lake env proof-forge emit --target quint --fixture array-path -o build/quint/CliArrayPath.qnt
lake env proof-forge emit --target quint --fixture struct-path -o build/quint/CliStructPath.qnt
lake env proof-forge emit --target quint --fixture struct-dynamic-path -o build/quint/CliStructDynamicPath.qnt
lake env proof-forge emit --target quint --fixture assignment -o build/quint/CliAssignment.qnt
lake env proof-forge emit --target quint --fixture crosscall -o build/quint/CliCrosscall.qnt
lake env proof-forge emit --target quint --fixture assert -o build/quint/CliAssert.qnt

echo "Quint MBT replay gate passed."
