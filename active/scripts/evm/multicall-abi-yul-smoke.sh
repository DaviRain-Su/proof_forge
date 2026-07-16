#!/usr/bin/env bash
# Wave δ follow-on: Multicall Call[] Plan → full Yul object (+ optional solc).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.elan/bin:$HOME/.local/bin:$HOME/.foundry/bin:$PATH"

OUT="${MULTICALL_ABI_YUL_OUT:-build/portable/multicall-abi-yul}"
YUL="$OUT/MulticallAggregate.yul"
DRIVER="$OUT/emit.lean"

fail() { echo "FAIL: $1" >&2; exit 1; }
require_file() { [[ -f "$1" ]] || fail "missing $1"; }
require_contains() { grep -Fq -- "$2" "$1" || fail "$3 missing '$2' in $1"; }

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "=== multicall-abi-yul: emit Plan → Yul object ==="
lake build Examples.Backend.Evm.Contracts.MulticallAggregateYul \
  ProofForge.Backend.Evm.ToYul.AbiEncode >/dev/null \
  || fail "lake build MulticallAggregateYul failed"

cat >"$DRIVER" <<'EOF'
import Examples.Backend.Evm.Contracts.MulticallAggregateYul

def main : IO Unit := do
  let yul := Examples.Backend.Evm.Contracts.MulticallAggregateYul.yulSource
  let path := System.FilePath.mk "build/portable/multicall-abi-yul/MulticallAggregate.yul"
  IO.FS.writeFile path yul
  IO.println s!"wrote {path} ({yul.length} chars)"
  IO.println s!"plan size={Examples.Backend.Evm.Contracts.MulticallAggregateYul.demoPlan.size}"
  IO.println s!"inSize={Examples.Backend.Evm.Contracts.MulticallAggregateYul.expectedInSize}"
EOF

lake env lean --run "$DRIVER" || fail "emit MulticallAggregate.yul failed"
require_file "$YUL"
require_contains "$YUL" "object" "Yul object"
require_contains "$YUL" "mstore" "mstore packing"
require_contains "$YUL" "shl" "selector shl"
require_contains "$YUL" "call(" "CALL"
require_contains "$YUL" "623753794" "aggregate selector 0x252dba42"
# Inner transfer selector bytes appear in plan dense region (0xa9059cbb packing)

if command -v solc >/dev/null 2>&1; then
  echo "=== multicall-abi-yul: solc --strict-assembly ==="
  # Assembly mode rejects --output-dir; print bin to stdout.
  solc --strict-assembly "$YUL" --bin >"$OUT/MulticallAggregate.solc.log" 2>&1 \
    || fail "solc --strict-assembly failed (see $OUT/MulticallAggregate.solc.log)"
  require_contains "$OUT/MulticallAggregate.solc.log" "Binary representation" \
    "solc should emit binary representation"
  echo "solc strict-assembly: ok"
else
  echo "SKIP: solc not on PATH (Yul emit still validated)"
fi

echo "multicall-abi-yul: ok"
