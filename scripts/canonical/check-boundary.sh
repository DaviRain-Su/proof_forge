#!/usr/bin/env bash
#
# scripts/canonical/check-boundary.sh — Mechanical architecture boundary gate.
#
# Fails on any of:
#   1. public target id ending in -core
#   2. backend importing ProofForge.Frontend.Surface
#   3. canonical target builder/lowerer importing retired IR compatibility
#   4. target plan declaration containing Yul.Statement, AstNode, or Wasm.Insn
#   5. legacy constructor change without classification change
#   6. remaining EvmCorePlan, SolanaCorePlan, or WasmCorePlan declaration
#   7. Wasm-host plan storing v1 StructDecl or AllocatorConfig values
#   8. target-native context fields leaking into Canonical Core
#   9. product/public authoring modules importing or constructing Surface
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

# ── 3. Canonical target paths cannot import retired compatibility ───
# Core builders and plan-only lowerers must remain independent of the v1 IR
# and target compatibility modules.
CANONICAL_PATHS=(
  ProofForge/Backend/Evm/Plan/Core.lean
  ProofForge/Backend/Solana/Plan/Core.lean
  ProofForge/Backend/WasmHost/NearModulePlan/Core.lean
  ProofForge/Backend/WasmHost/ModulePlan/Lower.lean
  ProofForge/Backend/WasmHost/ModulePlan.lean
  ProofForge/Backend/WasmHost/Plan.lean
  ProofForge/Backend/WasmHost/Plan/Types.lean
  ProofForge/Backend/WasmHost/AbiPlan.lean
  ProofForge/Backend/WasmHost/StructPlan.lean
)
for f in "${CANONICAL_PATHS[@]}"; do
  if rg -n '^\s*import\s+(ProofForge\.IR\.(Contract|Legacy)(\.|\s|$)|ProofForge\.Backend\.WasmHost\.[A-Za-z0-9_.]*Legacy(\s|$))' "$f" >/dev/null 2>&1; then
    report "canonical path $f imports retired IR compatibility"
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
  ProofForge/IR/Legacy/Core.lean
  ProofForge/IR/Legacy/Validate.lean
  ProofForge/IR/Legacy/Refinement.lean
  ProofForge/IR/Elaborate.lean
  ProofForge/IR/Elaborate/Smoke.lean
  ProofForge/Contract/Surface.lean
  ProofForge/Solana/Surface.lean
  ProofForge/Solana.lean
  ProofForge/Psy.lean
  ProofForge/Contract/Stdlib/Surface/Policies.lean
)
for f in "${SPIKE_FILES[@]}"; do
  if [ -f "$f" ]; then
    report "spike file still exists: $f"
  fi
done

# ── 7. Wasm-host plan fields are target-owned ─────────────────────
if rg -n '\b(?:StructDecl|AllocatorConfig)\b' \
    ProofForge/Backend/WasmHost/ModulePlan.lean >/dev/null 2>&1; then
  report "Wasm-host module plan stores retired v1 layout types"
fi

# ── 8. Canonical Core context stays target-neutral ─────────────────
# Native environment reads are typed HostOps owned by their target catalog.
CORE_TYPE=ProofForge/IR/Core/Type.lean
if [ -f "$CORE_TYPE" ] && sed -n \
    '/^inductive ContextField$/,/^[[:space:]]*deriving /p' "$CORE_TYPE" \
    | rg -n '^\s*\|.*\b(origin|prevRandao|epochHeight|randomSeed|accountId|prepaidGas|usedGas)\b' \
      >/dev/null 2>&1; then
  report "target-native constructor found in Core.ContextField"
fi

# ── 9. Surface is a compiler-owned normalization representation ────
# Product contracts are authored only through `contract_source`. Public source
# modules may implement the macro, but must not expose Surface as an authoring
# API. Direct Surface fixtures belong under TestFixtures.
AUTHORING_PATHS=(Examples/Product)
if [ -f ProofForge/Contract/Source.lean ]; then
  AUTHORING_PATHS+=(ProofForge/Contract/Source.lean)
fi
if [ -d ProofForge/Contract/Source ]; then
  AUTHORING_PATHS+=(ProofForge/Contract/Source)
fi
if rg -n '^\s*import\s+ProofForge\.Frontend\.Surface(\.|\s|$)' \
    "${AUTHORING_PATHS[@]}" >/dev/null 2>&1; then
  report "public authoring path imports internal Frontend.Surface"
fi
if rg -n '\bSurfaceContract\b' Examples/Product >/dev/null 2>&1; then
  report "product source constructs internal SurfaceContract"
fi
INTERNAL_AUTHOR_PATHS=(Examples/Product)
if [ -d ProofForge/Contract/Stdlib ]; then
  INTERNAL_AUTHOR_PATHS+=(ProofForge/Contract/Stdlib)
fi
if rg -n '^\s*import\s+ProofForge\.Contract\.Source\.(?:Internal|Solana\.Internal)(\s|$)' \
    "${INTERNAL_AUTHOR_PATHS[@]}" >/dev/null 2>&1; then
  report "product/stdlib source imports compiler-internal authoring implementation"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "canonical-boundary: ok"
  exit 0
else
  exit 1
fi
