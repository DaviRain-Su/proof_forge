#!/usr/bin/env bash
set -euo pipefail

# Unified Quint IR model gate (design spec §6.3):
#   1. Emit .qnt from portable IR
#   2. quint verify
#   3. quint run --mbt
#   4. Replay ITF through ProofForge IR semantics
#   5. Replay sampled trace through EVM backend (Counter Foundry smoke)
#
# Skips gracefully when quint or Java 17+ are missing locally; fails in CI.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build/quint"
SCENARIO="${REPO_ROOT}/Tests/Quint/ValueVault.scenario.toml"

export PATH="$HOME/.foundry/bin:$PATH"

mkdir -p "${BUILD_DIR}"
cd "${REPO_ROOT}"

if ! command -v quint &>/dev/null; then
  if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "ERROR: quint not found on PATH (required in CI)" >&2
    exit 1
  fi
  echo "SKIP: quint not found on PATH"
  exit 0
fi

java_version=""
if command -v java &>/dev/null; then
  java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print substr($2,1,2)}' | head -1)
  if [[ "${java_version}" =~ ^1\. ]]; then
    java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print substr($2,4,2)}' | head -1)
  fi
fi

if [[ -z "${java_version}" ]] || [[ "${java_version}" -lt 17 ]]; then
  if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "ERROR: quint verify requires Java 17+ (found ${java_version:-none})" >&2
    exit 1
  fi
  echo "SKIP: quint verify requires Java 17+ (found ${java_version:-none})"
  exit 0
fi

echo "Building proof-forge CLI..."
lake build proof-forge

echo "Building Quint replay dependencies..."
lake build ProofForge.Backend.Quint.Replay ProofForge.Backend.Quint.EvmReplay

echo "=== Counter: steps 1-5 (emit, verify, mbt, IR replay, EVM replay) ==="
echo "[1/5] Emit Counter .qnt from portable IR..."
lake env proof-forge emit --target quint --fixture counter \
  -o "${BUILD_DIR}/CounterIrModel.qnt"

echo "[2/5] quint verify Counter..."
quint verify "${BUILD_DIR}/CounterIrModel.qnt" --invariants countNonNegative --max-steps 10

echo "[3-5/5] Counter MBT, IR replay, and EVM backend replay..."
lake env lean --run Tests/Quint/CounterIrModelGate.lean

echo "=== ValueVault: steps 1-4 (emit, verify, mbt, IR replay) ==="
echo "[1/4] Emit ValueVault .qnt from portable IR..."
lake env proof-forge emit --target quint --fixture value-vault \
  --scenario "${SCENARIO}" \
  -o "${BUILD_DIR}/ValueVaultIrModel.qnt"

echo "[2/4] quint verify ValueVault..."
quint verify "${BUILD_DIR}/ValueVaultIrModel.qnt" \
  --invariant balanceNonNegative,releasedNonNegative,feesNonNegative,totalCoversReleased,totalCoversFees \
  --max-steps 5

echo "[3-4/4] ValueVault MBT and IR replay..."
lake env lean --run Tests/Quint/ValueVaultIrModelGate.lean

echo "Quint IR model gate passed."
