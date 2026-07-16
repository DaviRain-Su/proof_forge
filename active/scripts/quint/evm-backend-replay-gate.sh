#!/usr/bin/env bash
set -euo pipefail

# Quint MBT trace replay through the EVM backend (Foundry smoke, Counter v1).
# Skips gracefully when quint, forge, or solc are missing locally; fails in CI.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"

cd "${REPO_ROOT}"

missing=()
command -v quint &>/dev/null || missing+=("quint")
command -v forge &>/dev/null || missing+=("forge")
command -v solc &>/dev/null || missing+=("solc")

if ((${#missing[@]} > 0)); then
  if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "ERROR: required tools missing for EVM backend replay gate: ${missing[*]}" >&2
    exit 1
  fi
  echo "SKIP: EVM backend replay gate missing tools: ${missing[*]}"
  exit 0
fi

echo "Building proof-forge CLI..."
lake build proof-forge

echo "Running Counter EVM backend MBT replay test..."
lake env lean --run Tests/Quint/CounterEvmReplay.lean

echo "Quint EVM backend replay gate passed."