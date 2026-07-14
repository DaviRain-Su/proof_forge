#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECKER="$REPO_ROOT/scripts/canonical/check-boundary.sh"

make_fixture() {
  local root="$1"
  mkdir -p \
    "$root/ProofForge/Target" \
    "$root/ProofForge/Backend/Evm/Plan" \
    "$root/ProofForge/Backend/Solana/Plan" \
    "$root/ProofForge/Backend/WasmHost/NearModulePlan" \
    "$root/ProofForge/Backend/WasmHost/ModulePlan" \
    "$root/ProofForge/Backend/WasmHost" \
    "$root/ProofForge/IR/Core" \
    "$root/ProofForge/Cli" \
    "$root/Tests" \
    "$root/scripts/canonical"
  printf '%s\n' 'def ids := #["evm"]' > "$root/ProofForge/Target/Registry.lean"
  printf '%s\n' 'structure EvmPlan where' '  value : Nat' > "$root/ProofForge/Backend/Evm/Plan.lean"
  printf '%s\n' 'structure SolanaPlan where' '  value : Nat' > "$root/ProofForge/Backend/Solana/Plan.lean"
  printf '%s\n' 'structure NearPlan where' '  value : Nat' > "$root/ProofForge/Backend/WasmHost/NearModulePlan.lean"
  printf '%s\n' 'structure HostPlan where' '  value : Nat' > "$root/ProofForge/Backend/WasmHost/Plan.lean"
  : > "$root/ProofForge/Backend/Evm/Plan/Core.lean"
  : > "$root/ProofForge/Backend/Solana/Plan/Core.lean"
  : > "$root/ProofForge/Backend/WasmHost/NearModulePlan/Core.lean"
  : > "$root/ProofForge/Backend/WasmHost/ModulePlan/Lower.lean"
  printf '%s\n' 'inductive ContextField' '  | sender | gas' '  deriving Repr' \
    > "$root/ProofForge/IR/Core/Type.lean"
}

expect_failure() {
  local label="$1"
  local root="$2"
  if PROOF_FORGE_BOUNDARY_ROOT="$root" PROOF_FORGE_BOUNDARY_SKIP_LEGACY_FREEZE=1 \
      "$CHECKER" >/dev/null 2>&1; then
    echo "boundary-self-test: checker missed $label" >&2
    exit 1
  fi
}

expect_success() {
  local label="$1"
  local root="$2"
  if ! PROOF_FORGE_BOUNDARY_ROOT="$root" PROOF_FORGE_BOUNDARY_SKIP_LEGACY_FREEZE=1 \
      "$CHECKER" >/dev/null 2>&1; then
    echo "boundary-self-test: checker rejected $label" >&2
    exit 1
  fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/proof-forge-boundary.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

root="$TMP/target"
make_fixture "$root"
printf '%s\n' 'def target := {' '  id := "evm-core"' '}' > "$root/ProofForge/Target/Registry.lean"
expect_failure "public -core target" "$root"

root="$TMP/frontend"
make_fixture "$root"
printf '%s\n' 'import ProofForge.Frontend.Surface' > "$root/ProofForge/Backend/Evm/Bad.lean"
expect_failure "backend frontend import" "$root"

root="$TMP/legacy"
make_fixture "$root"
printf '%s\n' 'import ProofForge.IR.Contract' > "$root/ProofForge/Backend/Evm/Plan/Core.lean"
expect_failure "canonical Legacy import" "$root"

root="$TMP/near-legacy"
make_fixture "$root"
printf '%s\n' 'import ProofForge.Backend.WasmHost.NearModulePlan.Legacy' \
  > "$root/ProofForge/Backend/WasmHost/NearModulePlan/Core.lean"
expect_failure "canonical NEAR compatibility import" "$root"

root="$TMP/legacy-namespace"
make_fixture "$root"
printf '%s\n' 'import ProofForge.IR.Legacy.Adapter' \
  > "$root/ProofForge/Backend/WasmHost/ModulePlan/Lower.lean"
expect_failure "canonical legacy namespace import" "$root"

root="$TMP/raw-ast"
make_fixture "$root"
printf '%s\n' 'structure EvmPlan where' '  statement :' '    Yul.Statement' > "$root/ProofForge/Backend/Evm/Plan.lean"
expect_failure "multiline raw target AST" "$root"

root="$TMP/spike"
make_fixture "$root"
touch "$root/ProofForge/Backend/Evm/CorePlan.lean"
expect_failure "remaining spike file" "$root"

root="$TMP/wasm-plan-legacy-layout"
make_fixture "$root"
printf '%s\n' 'structure LowerCtxSeed where' '  structs : Array StructDecl' \
  > "$root/ProofForge/Backend/WasmHost/ModulePlan.lean"
expect_failure "Wasm-host legacy layout type" "$root"

root="$TMP/target-context"
make_fixture "$root"
printf '%s\n' 'inductive ContextField' '  | sender | origin' '  deriving Repr' \
  > "$root/ProofForge/IR/Core/Type.lean"
expect_failure "target-native Core context" "$root"

root="$TMP/comments"
make_fixture "$root"
printf '%s\n' '-- historical id: "evm-core"' 'def ids := #["evm"]' > "$root/ProofForge/Target/Registry.lean"
printf '%s\n' '-- import ProofForge.Frontend.Surface' 'def ok := true' > "$root/ProofForge/Backend/Evm/Comment.lean"
expect_success "comment-only references" "$root"

echo "canonical-boundary-self-test: ok"
