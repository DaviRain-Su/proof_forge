#!/usr/bin/env bash
# Run all CI-safe Solana Pinocchio reference-equivalence smokes.
#
# This gate compares ProofForge source/artifact metadata against checked-in
# Pinocchio reference manifests and sources. It intentionally avoids sbpf,
# Surfpool, and cargo-build-sbf; live dual-deploy equivalence remains in the
# per-fixture *-live-equivalence.sh gates.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

scripts=(
  scripts/solana/pinocchio-system-transfer-equivalence.sh
  scripts/solana/pinocchio-system-create-account-equivalence.sh
  scripts/solana/pinocchio-spl-token-transfer-equivalence.sh
  scripts/solana/pinocchio-spl-token-ops-equivalence.sh
  scripts/solana/pinocchio-spl-token-authority-equivalence.sh
  scripts/solana/pinocchio-spl-token-close-account-equivalence.sh
  scripts/solana/pinocchio-memo-equivalence.sh
)

for script in "${scripts[@]}"; do
  echo "=== running ${script} ==="
  "$script"
done

echo "=== Solana Pinocchio reference-equivalence suite: PASS ==="
