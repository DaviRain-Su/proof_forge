import ProofForge.IR.Examples.EvmStorageStructProbe
import ProofForge.Backend.Quint.Lower
import ProofForge.Backend.Quint.GuardAst

namespace Tests.Quint.StructDynamicPathGuard

open ProofForge.IR (Effect Statement StoragePathSegment)
open ProofForge.IR.Examples.EvmStorageStructProbe
open ProofForge.Backend.Quint.Lower
open ProofForge.Backend.Quint.GuardAst

abbrev Qx := ProofForge.Backend.Quint.Expr

def returnReadEffect : Effect :=
  .storagePathRead "points" #[.index (ProofForge.IR.Expr.local "index"), pathField "x"]

def mkDynamicPathCtx : LowerCtx :=
  { stateDecls := emitQuintDynamicStructPathModule.state,
    structs := emitQuintDynamicStructPathModule.structs,
    locals := [("index", ProofForge.Backend.Quint.Expr.local "index")] }

def lowerFixtureGuardPair : Except LowerError (Qx × Qx) := do
  let ctx ← lowerStatements mkDynamicPathCtx dynamicArrayPathLifecycle.body
  match ctx.guards[0]? >>= findDynamicPathReturnGuard? with
  | some pair => pure pair
  | none => throw ⟨"lowered fixture must contain dynamic-path return guard read == 45"⟩

def stubRead := ProofForge.Backend.Quint.Expr.literalInt 0
def stubExpected := ProofForge.Backend.Quint.Expr.literalInt 45

def assertNegativeProofs : Option String :=
  if exprIsDynamicArrayStructRead stubRead then
    some "negative proof failed: stub zero literal must not pass dynamic read check"
  else if (validateDynamicPathReturnGuard stubRead stubExpected).isNone then
    some "negative proof failed: stub read `0` with expected `45` must be rejected"
  else
    match lowerReturnGuardPair mkDynamicPathCtx returnReadEffect with
    | .error _ => none
    | .ok (_, expectedWithoutWrites) =>
        if exprIsLiteralInt 45 expectedWithoutWrites then
          some "negative proof failed: expected must not fold to 45 without write trace"
        else
          none

def main : IO UInt32 := do
  match lowerFixtureGuardPair with
  | .error err =>
      IO.eprintln s!"FAIL lower: {err.message}"
      return 1
  | .ok (readExpr, expectedExpr) =>
      match validateDynamicPathReturnGuard readExpr expectedExpr with
      | some err =>
          IO.eprintln s!"FAIL guard AST: {err}"
          return 1
      | none =>
          match assertNegativeProofs with
          | some err =>
              IO.eprintln s!"FAIL {err}"
              return 1
          | none =>
              IO.println "PASS"
              return 0

end Tests.Quint.StructDynamicPathGuard

def main : IO UInt32 := Tests.Quint.StructDynamicPathGuard.main