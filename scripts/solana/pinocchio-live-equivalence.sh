#!/usr/bin/env bash
# Run all Solana ProofForge-vs-Pinocchio live dual-deploy equivalence gates.
#
# Each child gate builds the generated ProofForge ELF and the checked-in
# Pinocchio reference ELF, deploys both programs to one Surfpool instance, and
# compares observable Rust live behavior. A child exit code of 2 means the gate
# skipped because a live prerequisite is missing.
set -u -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

scripts=(
  scripts/solana/pinocchio-system-transfer-live-equivalence.sh
  scripts/solana/pinocchio-system-create-account-live-equivalence.sh
  scripts/solana/pinocchio-spl-token-transfer-live-equivalence.sh
  scripts/solana/pinocchio-spl-token-ops-live-equivalence.sh
  scripts/solana/pinocchio-spl-token-authority-live-equivalence.sh
)

passed=0
skipped=0
failed=0

for script in "${scripts[@]}"; do
  echo "=== running ${script} ==="
  "$script"
  status=$?
  case "$status" in
    0)
      passed=$((passed + 1))
      ;;
    2)
      skipped=$((skipped + 1))
      echo "=== ${script}: SKIPPED ==="
      ;;
    *)
      failed=$((failed + 1))
      echo "=== ${script}: FAILED (${status}) ===" >&2
      ;;
  esac
done

echo "=== Solana Pinocchio live-equivalence suite summary: ${passed} passed, ${skipped} skipped, ${failed} failed ==="

if [ "$failed" -ne 0 ]; then
  exit 1
fi

if [ "$skipped" -ne 0 ]; then
  if [ "${PROOF_FORGE_PINOCCHIO_LIVE_ALLOW_SKIP:-0}" = "1" ]; then
    echo "=== Solana Pinocchio live-equivalence suite: SKIPPED prerequisites accepted ==="
    exit 0
  fi
  echo "=== Solana Pinocchio live-equivalence suite: SKIPPED prerequisites missing ===" >&2
  echo "Set PROOF_FORGE_PINOCCHIO_LIVE_ALLOW_SKIP=1 only for explicit probe lanes." >&2
  exit 2
fi

echo "=== Solana Pinocchio live-equivalence suite: PASS ==="
