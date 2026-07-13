#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASELINE="$ROOT/scripts/ir/target-boundary-baseline.txt"

FILES=(
  "ProofForge/IR/Contract.lean"
  "ProofForge/IR/Canonical.lean"
  "ProofForge/IR/Core/Syntax.lean"
  "ProofForge/IR/Core/HostOp.lean"
  "ProofForge/IR/Core/Semantics.lean"
  "ProofForge/IR/Core/Validate.lean"
)

# Target/protocol identifiers that must migrate out of the shared boundary.
# Counts make the temporary baseline monotonic: deletion is allowed, additions
# and new occurrences are rejected.
PATTERN='\b(?:near[A-Z][A-Za-z0-9_]*|Near[A-Z][A-Za-z0-9_]*|solidity[A-Z][A-Za-z0-9_]*|Solidity[A-Z][A-Za-z0-9_]*|eip[0-9][A-Za-z0-9_]*|EIP[0-9][A-Za-z0-9_-]*|checkErc[A-Za-z0-9_]*|Erc[0-9][A-Za-z0-9_]*|evm[A-Z][A-Za-z0-9_]*|Evm[A-Za-z0-9_]*|prepaidGas|usedGas|baseFee|prevRandao|origin|coinbase|blockHash|fallback|receive|crosscallCreate2?|delegateInvoke|staticInvoke)\b'

scan() {
  (
    cd "$ROOT"
    rg --pcre2 --only-matching "$PATTERN" "${FILES[@]}" || true
  ) | LC_ALL=C sort | uniq -c | awk '{ print $2, $1 }'
}

if [[ "${1:-}" == "--print" ]]; then
  scan
  exit 0
fi

if [[ ! -f "$BASELINE" ]]; then
  echo "missing target-boundary baseline: $BASELINE" >&2
  exit 1
fi

CURRENT="$(mktemp)"
trap 'rm -f "$CURRENT"' EXIT
scan >"$CURRENT"

awk '
  NR == FNR { allowed[$1] = $2; next }
  {
    if (!($1 in allowed)) {
      printf "new shared-layer target identifier: %s (count %s)\n", $1, $2 > "/dev/stderr"
      failed = 1
    } else if ($2 > allowed[$1]) {
      printf "shared-layer target identifier increased: %s (%s -> %s)\n", $1, allowed[$1], $2 > "/dev/stderr"
      failed = 1
    }
  }
  END { exit failed }
' "$BASELINE" "$CURRENT"

echo "ir-target-boundary: ok"
