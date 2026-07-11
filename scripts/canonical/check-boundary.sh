#!/usr/bin/env bash
#
# scripts/canonical/check-boundary.sh — Mechanical architecture boundary gate.
#
# Fails on any of:
#   1. public target id ending in -core
#   2. backend importing ProofForge.Frontend.Surface
#   3. canonical target builder importing ProofForge.IR.Contract
#   4. target plan declaration containing Yul.Statement, AstNode, or Wasm.Insn
#   5. legacy constructor change without classification change
#   6. remaining EvmCorePlan, SolanaCorePlan, or WasmCorePlan declaration
#
# This is a required static gate in `just check`.

set -euo pipefail

REPO_ROOT="${PROOF_FORGE_BOUNDARY_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$REPO_ROOT"

FAIL=0
report() { echo "canonical-boundary: $1"; FAIL=1; }

# ── 1. No public target ID ending in -core ──────────────────────────
if rg -n '^\s*id\s*:=\s*"[^"]*-core"' ProofForge/Target/Registry.lean >/dev/null; then
  report "public target ID ending in -core found in Registry.lean"
fi

# ── 2. No backend importing ProofForge.Frontend.Surface ─────────────
if rg -n '^\s*import\s+ProofForge\.Frontend\.Surface(\s|$)' ProofForge/Backend/ >/dev/null 2>&1; then
  report "backend imports ProofForge.Frontend.Surface"
fi

# ── 3. No canonical target builder importing ProofForge.IR.Contract ─
# Canonical Core builders (Plan/Core.lean) must not import Legacy IR.
CANONICAL_BUILDERS=(
  ProofForge/Backend/Evm/Plan/Core.lean
  ProofForge/Backend/Solana/Plan/Core.lean
  ProofForge/Backend/WasmHost/NearModulePlan/Core.lean
)
for f in "${CANONICAL_BUILDERS[@]}"; do
  if rg -n '^\s*import\s+ProofForge\.IR\.Contract(\s|$)' "$f" >/dev/null 2>&1; then
    report "canonical builder $f imports ProofForge.IR.Contract"
  fi
done

# ── 4. No target plan containing raw target AST nodes ──────────────
# Target plan files should contain semantic operations, not Yul.Statement,
# AstNode, or Wasm.Insn in their plan type declarations.
PLAN_FILES=(
  ProofForge/Backend/Evm/Plan.lean
  ProofForge/Backend/Solana/Plan.lean
  ProofForge/Backend/WasmHost/NearModulePlan.lean
  ProofForge/Backend/WasmHost/Plan.lean
)
for f in "${PLAN_FILES[@]}"; do
  if ! python3 - "$f" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read().splitlines()
declaration = []
in_plan_type = False
banned = re.compile(r"\b(?:Yul\.Statement|Asm\.AstNode|Wasm\.Insn)\b")
top_level = re.compile(r"^(?:structure|inductive|def|private def|protected def|abbrev|instance|namespace|end)\b")

for line in text + ["def __boundary_sentinel := ()"]:
    if line.startswith(("structure ", "inductive ")):
        if in_plan_type and banned.search("\n".join(declaration)):
            raise SystemExit(1)
        declaration = [line]
        in_plan_type = True
    elif in_plan_type and top_level.match(line):
        if banned.search("\n".join(declaration)):
            raise SystemExit(1)
        declaration = []
        in_plan_type = False
    elif in_plan_type:
        declaration.append(line)
PY
  then
    report "target plan $f contains raw target AST in plan type declaration"
  fi
done

# ── 5. Legacy IR freeze: constructor change without classification ──
# (Reuse the existing legacy-freeze script.)
if [ "${PROOF_FORGE_BOUNDARY_SKIP_LEGACY_FREEZE:-0}" != "1" ] && \
    [ -x scripts/canonical/check-legacy-freeze.sh ]; then
  if ! scripts/canonical/check-legacy-freeze.sh; then
    FAIL=1
  fi
fi

# ── 6. No remaining parallel spike plan declarations ────────────────
SPIKE_FILES=(
  ProofForge/Backend/Evm/CorePlan.lean
  ProofForge/Backend/Evm/CoreLower.lean
  ProofForge/Backend/Solana/CorePlan.lean
  ProofForge/Backend/Solana/CoreLower.lean
  ProofForge/Backend/WasmHost/CorePlan.lean
  ProofForge/Backend/WasmHost/CoreLower.lean
  ProofForge/Target/CoreBackend.lean
  ProofForge/Cli/CoreBackend.lean
  Tests/EvmCoreSmoke.lean
  Tests/SolanaCoreSmoke.lean
  Tests/WasmHostCoreSmoke.lean
)
for f in "${SPIKE_FILES[@]}"; do
  if [ -f "$f" ]; then
    report "spike file still exists: $f"
  fi
done

if [ "$FAIL" -eq 0 ]; then
  echo "canonical-boundary: ok"
  exit 0
else
  exit 1
fi
