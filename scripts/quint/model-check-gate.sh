#!/usr/bin/env bash
set -euo pipefail

# Quint model-check gate: emit Counter/ValueVault .qnt models and run
# `quint verify`. Skips gracefully when `quint` is missing or Java < 17.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build/quint"

mkdir -p "${BUILD_DIR}"

cd "${REPO_ROOT}"

if ! command -v quint &>/dev/null; then
  echo "SKIP: quint not found on PATH"
  exit 0
fi

# Apalache (used by quint verify) requires Java 17+.
java_version=""
if command -v java &>/dev/null; then
  java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print substr($2,1,2)}' | head -1)
  if [[ "${java_version}" =~ ^1\. ]]; then
    java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print substr($2,4,2)}' | head -1)
  fi
fi

if [[ -z "${java_version}" ]] || [[ "${java_version}" -lt 17 ]]; then
  echo "SKIP: quint verify requires Java 17+ (found ${java_version:-none})"
  exit 0
fi

echo "Emitting Quint models..."
lake env proof-forge emit --target quint --fixture counter -o "${BUILD_DIR}/Counter.qnt"
lake env proof-forge emit --target quint --fixture value-vault \
  --scenario "${REPO_ROOT}/Tests/Quint/ValueVault.scenario.toml" \
  -o "${BUILD_DIR}/ValueVault.qnt"

echo "Running quint verify on Counter..."
quint verify "${BUILD_DIR}/Counter.qnt" --invariants countNonNegative --max-steps 10

echo "Running quint verify on ValueVault..."
quint verify "${BUILD_DIR}/ValueVault.qnt" \
  --invariant balanceNonNegative,releasedNonNegative,feesNonNegative,totalCoversReleased,totalCoversFees \
  --max-steps 5

echo "Quint model-check gate passed."
