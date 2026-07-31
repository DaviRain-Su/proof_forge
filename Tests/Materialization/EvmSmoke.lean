import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import Tests.Language.ParserSession

namespace Tests.Materialization.EvmSmoke

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def materializeSelected (target : TargetId) (compiled : CompiledSemanticV1) :
    CompileResult MaterializedArtifactsV1 := do
  let selection ← resolveBuildSelectionV1 target none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.materializeResult capability

private def planEvm (compiled : CompiledSemanticV1) : CompileResult Targets.Evm.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.evm none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Evm.planFromCapability capability

private def testSemanticPlanSourceAuthority : IO Unit := do
  let path := "ProofForgeV2/Targets/Evm.lean"
  let forbidden ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "alphaResidualOf|makePlanFromAlpha", path]
  }
  expect (forbidden.exitCode == 1)
    s!"EVM Plan body must not retain the alpha residual route:\n{forbidden.stdout}"
  let required ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "semanticV1Of|validateSemanticProgramV1|makePlanFromSemanticV1", path]
  }
  expect (required.exitCode == 0 &&
      required.stdout.contains "semanticV1Of" &&
      required.stdout.contains "validateSemanticProgramV1" &&
      required.stdout.contains "makePlanFromSemanticV1")
    s!"EVM Plan body must be visibly SemanticProgramV1-native:\n{required.stdout}"

private unsafe def testRichUInt64SemanticPlan : IO Unit := do
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Ledger where\n" ++
    "  state left : UInt64\n" ++
    "  state right : UInt64\n" ++
    "  init(a : UInt64, b : UInt64) do\n" ++
    "    left := a\n" ++
    "    right := b\n" ++
    "  entry mix(x : UInt64, y : UInt64) : UInt64 do\n" ++
    "    left := left + x - y\n" ++
    "    right := right - x\n" ++
    "    return left\n" ++
    "  view getRight() : UInt64 do\n" ++
    "    return right\n"
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load rich UInt64" (← session.selectProgramV1
    sourceText "<evm-semantic-rich>" "Tests.EvmSemantic" none)
  let compiled ← liftResult "compile rich UInt64" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan rich UInt64" <| planEvm compiled
  expect (plan.objectName == "Ledger")
    "EVM object name must be the final SemanticProgramV1 qualified component"
  expect (plan.storageLayout == #[
      { sourceId := 0, name := "left", slot := 0 },
      { sourceId := 1, name := "right", slot := 1 }])
    "EVM SemanticProgramV1 state ids must map to declaration-order slots"
  match plan.constructor with
  | none => throw <| IO.userError "rich S1 stateful plan must retain its initializer"
  | some constructor =>
      expect (constructor.params == #[
          { sourceId := 0, name := "a", wordIndex := 0 },
          { sourceId := 1, name := "b", wordIndex := 1 }])
        "EVM constructor ValueIds must map to canonical ABI words"
      expect (constructor.stores == #[
          { slot := 0, value := .param 0 },
          { slot := 1, value := .param 1 }])
        "EVM constructor stores must preserve source order"
  expect (plan.entries.map (·.name) == #["mix", "getRight"])
    "EVM entries must preserve callable source order"
  let mix := plan.entries[0]!
  expect (mix.params == #[
      { sourceId := 0, name := "x", wordIndex := 0 },
      { sourceId := 1, name := "y", wordIndex := 1 }])
    "EVM entry ValueIds must map to canonical ABI words"
  expect (mix.body == #[
      .store {
        slot := 0
        value := .checkedSub
          (.checkedAdd (.storageLoad 0) (.param 0)) (.param 1)
      },
      .store {
        slot := 1
        value := .checkedSub (.storageLoad 1) (.param 0)
      },
      .returnValue (.storageLoad 0)])
    "EVM SSA lowering must preserve nested add/sub, store order, and post-store return"
  expect (plan.entries[1]!.body == #[.returnValue (.storageLoad 1)])
    "EVM view lowering must preserve the selected storage slot"
  let output ← liftResult "materialize rich add/sub" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "Ledger.yul") |
    throw <| IO.userError "rich add/sub: missing Ledger.yul"
  let yul := yulFile.contents
  expect (yul.contains "if lt(expr2, expr3) { revert(0, 0) }" &&
      yul.contains "let expr4 := sub(expr2, expr3)")
    "EVM Yul must check UInt64 underflow before subtraction"

/-- Guarded counter: assert count >= delta before checked subtract. -/
private def guardedCounterSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program Guarded where\n" ++
  "  state count : UInt64\n" ++
  "  init(i : UInt64) do\n" ++
  "    count := i\n" ++
  "  entry decrement(delta : UInt64) : UInt64 do\n" ++
  "    assert count >= delta\n" ++
  "    count := count - delta\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

/-- Init with assert interleaved before the store. -/
private def initAssertSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program InitGuard where\n" ++
  "  state count : UInt64\n" ++
  "  init(i : UInt64) do\n" ++
  "    assert i >= 0\n" ++
  "    count := i\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

private partial def nestedCompareExpr : Nat → Targets.Evm.Expr
  | 0 => .literal 0
  | level + 1 => .compare .eq (nestedCompareExpr level) (.literal 0)

private partial def fullCompareExpr : Nat → Targets.Evm.Expr
  | 0 => .literal 0
  | level + 1 =>
      let child := fullCompareExpr level
      .compare .eq child child

private unsafe def testGuardedCounterSemanticPlan : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load Guarded" (← session.selectProgramV1
    guardedCounterSourceText "<evm-guarded>" "Tests.EvmGuarded" none)
  let compiled ← liftResult "compile Guarded" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan Guarded" <| planEvm compiled
  expect (plan.objectName == "Guarded")
    "guarded counter object name must be Guarded"
  expect (plan.storageLayout.map (·.name) == #["count"])
    "guarded counter must retain count storage"
  expect (plan.entries.map (·.name) == #["decrement", "get"])
    "guarded counter must preserve entry order"
  let decrement := plan.entries[0]!
  expect (decrement.params == #[{ sourceId := 0, name := "delta", wordIndex := 0 }])
    "decrement param must map to ABI word 0"
  expect (decrement.body == #[
      .assert (.compare .ge (.storageLoad 0) (.param 0)),
      .store {
        slot := 0
        value := .checkedSub (.storageLoad 0) (.param 0)
      },
      .returnValue (.storageLoad 0)])
    "decrement must lower assert(count >= delta) then store(count - delta) then return"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"guarded plan must validate: {e.render}"
  let ir ← liftResult "ir Guarded" <| (do
    let selection ← resolveBuildSelectionV1 TargetId.evm none
    let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
    Targets.Evm.irFromCapability capability)
  let yul := ir.yul
  -- Comparison Yul: ge → iszero(lt(l,r)); assert → if iszero(cond) revert
  expect (yul.contains "iszero(lt(expr0, expr1))")
    "EVM Yul must render >= as iszero(lt(...))"
  expect (yul.contains "if iszero(expr2) { revert(0, 0) }")
    "EVM Yul must revert when assert condition is zero"
  expect (yul.contains "sub(expr" || yul.contains "let expr" && yul.contains "sub(")
    "EVM Yul must still emit checked subtraction after assert"
  -- Materialize product path for the real guarded source (ge + assert).
  let output ← liftResult "materialize Guarded" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "Guarded.yul") |
    throw <| IO.userError "guarded: missing Guarded.yul"
  expect (yulFile.contents.contains "iszero(lt(expr0, expr1))" &&
      yulFile.contents.contains "if iszero(expr2) { revert(0, 0) }")
    "materialized Guarded Yul must contain ge comparison and assert revert"
  -- All six comparison ops via product source (Yul substring pins).
  let allCmpText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program AllCmp where\n" ++
    "  view check(x : UInt64, y : UInt64) : UInt64 do\n" ++
    "    assert x == y\n" ++
    "    assert x != y\n" ++
    "    assert x < y\n" ++
    "    assert x <= y\n" ++
    "    assert x > y\n" ++
    "    assert x >= y\n" ++
    "    return x\n"
  let allCmpSource ← liftResult "load AllCmp" (← session.selectProgramV1
    allCmpText "<evm-all-cmp>" "Tests.EvmAllCmp" none)
  let allCmpCompiled ← liftResult "compile AllCmp" <|
    Compiler.compileValidatedSourceV1 allCmpSource
  let allCmpPlan ← liftResult "plan AllCmp" <| planEvm allCmpCompiled
  let checkBody := allCmpPlan.entries[0]!.body
  expect (checkBody == #[
      .assert (.compare .eq (.param 0) (.param 1)),
      .assert (.compare .ne (.param 0) (.param 1)),
      .assert (.compare .lt (.param 0) (.param 1)),
      .assert (.compare .le (.param 0) (.param 1)),
      .assert (.compare .gt (.param 0) (.param 1)),
      .assert (.compare .ge (.param 0) (.param 1)),
      .returnValue (.param 0)])
    "AllCmp must lower all six comparison ops in source order"
  let allCmpOutput ← liftResult "materialize AllCmp" <|
    materializeSelected TargetId.evm allCmpCompiled
  let some allCmpYul := (MaterializedArtifactsV1.filesOf allCmpOutput).find?
      (·.path == "AllCmp.yul") |
    throw <| IO.userError "AllCmp: missing AllCmp.yul"
  let allYul := allCmpYul.contents
  expect (allYul.contains "eq(expr0, expr1)")
    "AllCmp Yul must render eq"
  expect (allYul.contains "iszero(eq(expr")
    "AllCmp Yul must render ne as iszero(eq(...))"
  expect (allYul.contains "lt(expr")
    "AllCmp Yul must render lt"
  expect (allYul.contains "iszero(gt(expr")
    "AllCmp Yul must render le as iszero(gt(...))"
  expect (allYul.contains "gt(expr")
    "AllCmp Yul must render gt"
  expect (allYul.contains "iszero(lt(expr")
    "AllCmp Yul must render ge as iszero(lt(...))"
  expect (allYul.contains "if iszero(expr")
    "AllCmp Yul must render assert reverts"

private unsafe def testInitWithAssert : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load InitGuard" (← session.selectProgramV1
    initAssertSourceText "<evm-init-assert>" "Tests.EvmInitAssert" none)
  let compiled ← liftResult "compile InitGuard" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan InitGuard" <| planEvm compiled
  match plan.constructor with
  | none => throw <| IO.userError "InitGuard must retain constructor"
  | some ctor =>
      expect (ctor.body == #[
          .assert (.compare .ge (.param 0) (.literal 0)),
          .store { slot := 0, value := .param 0 },
          .returnNone])
        "constructor body must interleave assert then store in source order, closed by the bare-return marker"
      expect (ctor.stores.isEmpty)
        "constructor with assert must leave stores empty (body is authority)"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"InitGuard plan must validate: {e.render}"
  let output ← liftResult "materialize InitGuard" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "InitGuard.yul") |
    throw <| IO.userError "InitGuard: missing InitGuard.yul"
  let yul := yulFile.contents
  expect (yul.contains "iszero(lt(" && yul.contains "if iszero(" &&
      yul.contains "sstore(0,")
    "InitGuard Yul must render assert guard before sstore"

private def testCompareAssertPlanMutations : IO Unit := do
  -- Minimal valid plan shell for mutation negatives.
  let basePlan : Targets.Evm.Plan := {
    objectName := "Mut"
    runtimeObjectName := "__proof_forge_runtime"
    storageLayout := #[{ sourceId := 0, name := "count", slot := 0 }]
    events := #[]
    errors := #[]
    constructor := some {
      params := #[{ sourceId := 0, name := "i", wordIndex := 0 }]
      stores := #[{ slot := 0, value := .param 0 }]
    }
    entries := #[{
      name := "get"
      selector := Targets.Evm.Keccak.selector "get" #[]
      params := #[]
      mutability := .view
      body := #[.returnValue (.storageLoad 0)]
    }]
  }
  match Targets.Evm.validatePlan basePlan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"base mutation plan must validate: {e.render}"
  -- Dangling compare operand (unknown storage slot).
  let danglingCompare := { basePlan with entries := #[{
    basePlan.entries[0]! with body := #[
      .assert (.compare .ge (.storageLoad 99) (.literal 0)),
      .returnValue (.storageLoad 0)
    ]
  }] }
  match Targets.Evm.validatePlan danglingCompare with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject dangling compare storageLoad"
  -- Assert condition referencing unknown param word.
  let danglingParam := { basePlan with entries := #[{
    basePlan.entries[0]! with body := #[
      .assert (.compare .eq (.param 7) (.literal 0)),
      .returnValue (.storageLoad 0)
    ]
  }] }
  match Targets.Evm.validatePlan danglingParam with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject assert with unknown param word"
  -- Depth budget rejection on nested compare.
  let deepOk := { basePlan with entries := #[{
    basePlan.entries[0]! with body := #[
      .assert (nestedCompareExpr 255),
      .returnValue (.storageLoad 0)
    ]
  }] }
  match Targets.Evm.validatePlan deepOk with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"depth-255 compare must accept: {e.render}"
  let deepBad := { basePlan with entries := #[{
    basePlan.entries[0]! with body := #[
      .assert (nestedCompareExpr 256),
      .returnValue (.storageLoad 0)
    ]
  }] }
  match Targets.Evm.validatePlan deepBad with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "depth-256 compare must reject"
  -- Node budget rejection.
  let nodeBad := { basePlan with entries := #[{
    basePlan.entries[0]! with body := #[
      .assert (fullCompareExpr 16),
      .returnValue (.storageLoad 0)
    ]
  }] }
  match Targets.Evm.validatePlan nodeBad with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "oversized compare tree must reject"
  -- Constructor body with assert + store validates; return in constructor body rejects.
  let ctorAssert : Targets.Evm.Plan := {
    basePlan with constructor := some {
      params := #[{ sourceId := 0, name := "i", wordIndex := 0 }]
      stores := #[]
      body := #[
        .assert (.compare .ge (.param 0) (.literal 0)),
        .store { slot := 0, value := .param 0 }
      ]
    }
  }
  match Targets.Evm.validatePlan ctorAssert with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"constructor assert body must accept: {e.render}"
  let ctorReturn : Targets.Evm.Plan := {
    basePlan with constructor := some {
      params := #[{ sourceId := 0, name := "i", wordIndex := 0 }]
      stores := #[]
      body := #[.returnValue (.param 0)]
    }
  }
  match Targets.Evm.validatePlan ctorReturn with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "constructor returnValue must reject"

private unsafe def testBoolResultPositive : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- Wave-A plan-seam rejection flipped: Bool entry/view results are now accepted.
  let isZeroText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program IsZero where\n" ++
    "  view isZero(x : UInt64) : Bool do\n" ++
    "    return x == 0\n"
  let isZeroSource ← liftResult "load IsZero" (← session.selectProgramV1
    isZeroText "<evm-bool-result>" "Tests.EvmBoolResult" none)
  let isZeroCompiled ← liftResult "compile IsZero" <|
    Compiler.compileValidatedSourceV1 isZeroSource
  let isZeroPlan ← liftResult "plan IsZero" <| planEvm isZeroCompiled
  expect (isZeroPlan.entries.size == 1)
    "IsZero must produce exactly one entry"
  let isZeroEntry := isZeroPlan.entries[0]!
  expect (isZeroEntry.name == "isZero" && isZeroEntry.resultKind == .bool)
    "isZero must declare Bool resultKind"
  expect (isZeroEntry.body == #[.returnValue (.compare .eq (.param 0) (.literal 0))])
    "isZero body must return the comparison expression"
  match Targets.Evm.validatePlan isZeroPlan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"IsZero plan must validate: {e.render}"
  let isZeroOutput ← liftResult "materialize IsZero" <|
    materializeSelected TargetId.evm isZeroCompiled
  let some isZeroAbi := (MaterializedArtifactsV1.filesOf isZeroOutput).find?
      (·.path == "IsZero.abi.json") |
    throw <| IO.userError "IsZero: missing IsZero.abi.json"
  expect (isZeroAbi.contents.contains "\"type\":\"bool\"" &&
      isZeroAbi.contents.contains "\"name\":\"isZero\"")
    "IsZero ABI must render bool outputs"
  let some isZeroYul := (MaterializedArtifactsV1.filesOf isZeroOutput).find?
      (·.path == "IsZero.yul") |
    throw <| IO.userError "IsZero: missing IsZero.yul"
  expect (isZeroYul.contents.contains "eq(expr" &&
      isZeroYul.contents.contains "mstore(0," &&
      isZeroYul.contents.contains "return(0, 32)")
    "IsZero Yul must return the comparison word"
  -- Rebuild determinism.
  let isZeroPlan2 ← liftResult "plan IsZero again" <| planEvm isZeroCompiled
  expect (isZeroPlan == isZeroPlan2)
    "IsZero plan rebuild must be deterministic"

private def boolPredicateSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program BoolPredicate where\n" ++
  "  state count : UInt64\n" ++
  "  init(i : UInt64) do\n" ++
  "    count := i\n" ++
  "  entry bump(d : UInt64) : UInt64 do\n" ++
  "    count := count + d\n" ++
  "    return count\n" ++
  "  view positive() : Bool do\n" ++
  "    return count > 0\n" ++
  "  entry equalsCount(d : UInt64) : Bool do\n" ++
  "    return count == d\n"

private unsafe def testBoolPredicateEndToEnd : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load BoolPredicate" (← session.selectProgramV1
    boolPredicateSourceText "<evm-bool-predicate>" "Tests.EvmBoolPred" none)
  let compiled ← liftResult "compile BoolPredicate" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan BoolPredicate" <| planEvm compiled
  expect (plan.objectName == "BoolPredicate")
    "BoolPredicate object name"
  expect (plan.storageLayout.map (·.name) == #["count"])
    "BoolPredicate storage layout"
  expect (plan.entries.map (·.name) == #["bump", "positive", "equalsCount"])
    "BoolPredicate entry order"
  expect (plan.entries.map (·.resultKind) == #[.uint64, .bool, .bool])
    "BoolPredicate result kinds must be uint64/bool/bool"
  expect (plan.entries[0]!.body == #[
      .store {
        slot := 0
        value := .checkedAdd (.storageLoad 0) (.param 0)
      },
      .returnValue (.storageLoad 0)])
    "bump must remain UInt64 store+return"
  expect (plan.entries[1]!.body == #[
      .returnValue (.compare .gt (.storageLoad 0) (.literal 0))])
    "positive must return count > 0 comparison"
  expect (plan.entries[2]!.body == #[
      .returnValue (.compare .eq (.storageLoad 0) (.param 0))])
    "equalsCount must return count == d comparison"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"BoolPredicate plan must validate: {e.render}"
  let plan2 ← liftResult "plan BoolPredicate again" <| planEvm compiled
  expect (plan == plan2)
    "BoolPredicate plan rebuild must be deterministic"
  let output ← liftResult "materialize BoolPredicate" <|
    materializeSelected TargetId.evm compiled
  let some abiFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "BoolPredicate.abi.json") |
    throw <| IO.userError "BoolPredicate: missing ABI"
  let abi := abiFile.contents
  expect (abi.contains "\"name\":\"bump\"" &&
      abi.contains "\"name\":\"positive\"" &&
      abi.contains "\"name\":\"equalsCount\"")
    "BoolPredicate ABI must name all three entries"
  expect (abi.contains "\"type\":\"bool\"")
    "BoolPredicate ABI must contain bool outputs"
  expect (abi.contains "\"type\":\"uint64\"")
    "BoolPredicate ABI must still contain uint64 (params/bump result)"
  -- Exact ABI pin: three functions with correct output types in source order.
  let expectedAbi :=
    "[\n" ++
    "  {\"type\":\"constructor\",\"stateMutability\":\"nonpayable\",\"inputs\":[{\"name\":\"i\",\"type\":\"uint64\"}]},\n" ++
    "  {\"type\":\"function\",\"name\":\"bump\",\"stateMutability\":\"nonpayable\",\"inputs\":[{\"name\":\"d\",\"type\":\"uint64\"}],\"outputs\":[{\"name\":\"\",\"type\":\"uint64\"}]},\n" ++
    "  {\"type\":\"function\",\"name\":\"positive\",\"stateMutability\":\"view\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"bool\"}]},\n" ++
    "  {\"type\":\"function\",\"name\":\"equalsCount\",\"stateMutability\":\"nonpayable\",\"inputs\":[{\"name\":\"d\",\"type\":\"uint64\"}],\"outputs\":[{\"name\":\"\",\"type\":\"bool\"}]}\n" ++
    "]\n"
  expect (abi == expectedAbi)
    s!"BoolPredicate ABI exact text mismatch:\n{abi}"
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "BoolPredicate.yul") |
    throw <| IO.userError "BoolPredicate: missing Yul"
  let yul := yulFile.contents
  expect (yul.contains "gt(expr" && yul.contains "eq(expr")
    "BoolPredicate Yul must render gt and eq comparisons"
  expect (yul.contains "mstore(0," && yul.contains "return(0, 32)")
    "BoolPredicate Yul must ABI-return words for Bool results"
  -- Mutation negatives: kind consistency.
  let base := plan
  let boolEntry := base.entries[1]!
  -- Bool entry returning a UInt64-typed expression (storageLoad) rejected.
  let boolReturnsUInt := { base with entries := base.entries.set! 1 {
    boolEntry with body := #[.returnValue (.storageLoad 0)]
  } }
  match Targets.Evm.validatePlan boolReturnsUInt with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject Bool entry returning UInt64 expression"
  -- UInt64 entry returning a comparison rejected.
  let uintEntry := base.entries[0]!
  let uintReturnsBool := { base with entries := base.entries.set! 0 {
    uintEntry with body := #[.returnValue (.compare .eq (.param 0) (.literal 0))]
  } }
  match Targets.Evm.validatePlan uintReturnsBool with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject UInt64 entry returning comparison"
  -- Forged resultKind (uint64 body tagged bool) rejected.
  let forgedKind := { base with entries := base.entries.set! 0 {
    uintEntry with resultKind := .bool
  } }
  match Targets.Evm.validatePlan forgedKind with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject forged resultKind"
  -- Forged resultKind (bool body tagged uint64) rejected.
  let forgedKind2 := { base with entries := base.entries.set! 1 {
    boolEntry with resultKind := .uint64
  } }
  match Targets.Evm.validatePlan forgedKind2 with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject forged uint64 resultKind on Bool body"
  -- Store of comparison into UInt64 slot rejected.
  let storeBool := { base with entries := base.entries.set! 0 {
    uintEntry with body := #[
      .store { slot := 0, value := .compare .eq (.param 0) (.literal 0) },
      .returnValue (.storageLoad 0)
    ]
  } }
  match Targets.Evm.validatePlan storeBool with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject storing Bool comparison into slot"

/-- If/else multi-block program: branch diamond lowered to ifThenElse. -/
private def ifFlowSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program IfFlow where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    if count > 0 then\n" ++
  "      count := count + delta\n" ++
  "    else\n" ++
  "      count := delta\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

private unsafe def testIfFlowMultiBlock : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load IfFlow" (← session.selectProgramV1
    ifFlowSourceText "<evm-if-flow>" "Tests.EvmIfFlow" none)
  let compiled ← liftResult "compile IfFlow" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan IfFlow" <| planEvm compiled
  expect (plan.entries.map (·.name) == #["bump", "get"])
    "IfFlow must preserve entry order"
  let bump := plan.entries[0]!
  expect (bump.body == #[
      .ifThenElse (.compare .gt (.storageLoad 0) (.literal 0))
        #[.store { slot := 0, value := .checkedAdd (.storageLoad 0) (.param 0) }]
        #[.store { slot := 0, value := .param 0 }],
      .returnValue (.storageLoad 0)])
    "IfFlow bump must lower the branch diamond then join return"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"IfFlow plan must validate: {e.render}"
  let plan2 ← liftResult "plan IfFlow again" <| planEvm compiled
  expect (plan == plan2) "IfFlow plan must be deterministic"
  let output ← liftResult "materialize IfFlow" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "IfFlow.yul") |
    throw <| IO.userError "IfFlow: missing IfFlow.yul"
  let yul := yulFile.contents
  expect (yul.contains "gt(expr0, expr1)")
    "IfFlow Yul must render the gt comparison"
  expect (yul.contains "if expr")
    "IfFlow Yul must render the then-branch if"
  expect (yul.contains "if iszero(expr")
    "IfFlow Yul must render the else-branch guard"
  expect (yul.contains "add(expr" && yul.contains "sstore(0, expr")
    "IfFlow Yul must render the then-branch checked add store"
  expect (yul.contains "arg0")
    "IfFlow Yul must reference the else-branch param"
  expect (yul.contains "mstore(0, expr")
    "IfFlow Yul must render the join return"

/-- No-else if: absent else falls into the join; only the then if renders. -/
private unsafe def testIfNoElse : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program IfNoElse where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    if count > 0 then\n" ++
    "      count := count + delta\n" ++
    "    return count\n"
  let source ← liftResult "load IfNoElse" (← session.selectProgramV1
    text "<evm-if-noelse>" "Tests.EvmIfNoElse" none)
  let compiled ← liftResult "compile IfNoElse" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan IfNoElse" <| planEvm compiled
  expect (plan.entries[0]!.body == #[
      .ifThenElse (.compare .gt (.storageLoad 0) (.literal 0))
        #[.store { slot := 0, value := .checkedAdd (.storageLoad 0) (.param 0) }]
        #[],
      .returnValue (.storageLoad 0)])
    "IfNoElse must lower an empty else body and keep the join"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"IfNoElse plan must validate: {e.render}"
  let output ← liftResult "materialize IfNoElse" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "IfNoElse.yul") |
    throw <| IO.userError "IfNoElse: missing IfNoElse.yul"
  let yul := yulFile.contents
  let thenIfs := yul.splitOn "if expr"
  expect (thenIfs.length == 2)
    s!"IfNoElse must render exactly one branch if (no else guard), got {thenIfs.length - 1}"

/-- Both branches return: the if is the final statement (no join). -/
private unsafe def testIfBothReturn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program IfBoth where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry pick(delta : UInt64) : UInt64 do\n" ++
    "    if count > 0 then\n" ++
    "      return count\n" ++
    "    else\n" ++
    "      return delta\n"
  let source ← liftResult "load IfBoth" (← session.selectProgramV1
    text "<evm-if-both>" "Tests.EvmIfBoth" none)
  let compiled ← liftResult "compile IfBoth" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan IfBoth" <| planEvm compiled
  expect (plan.entries[0]!.body == #[
      .ifThenElse (.compare .gt (.storageLoad 0) (.literal 0))
        #[.returnValue (.storageLoad 0)]
        #[.returnValue (.param 0)]])
    "IfBoth must lower both-returning branches without a join statement"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"IfBoth plan must validate: {e.render}"

/-- Nested if: inner diamond inside the then branch. -/
private unsafe def testNestedIf : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program NestedIf where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    if count > 0 then\n" ++
    "      if delta > 0 then\n" ++
    "        count := count + delta\n" ++
    "      else\n" ++
    "        count := 1\n" ++
    "    else\n" ++
    "      count := 2\n" ++
    "    return count\n"
  let source ← liftResult "load NestedIf" (← session.selectProgramV1
    text "<evm-nested-if>" "Tests.EvmNestedIf" none)
  let compiled ← liftResult "compile NestedIf" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan NestedIf" <| planEvm compiled
  expect (plan.entries[0]!.body == #[
      .ifThenElse (.compare .gt (.storageLoad 0) (.literal 0))
        #[.ifThenElse (.compare .gt (.param 0) (.literal 0))
          #[.store { slot := 0, value := .checkedAdd (.storageLoad 0) (.param 0) }]
          #[.store { slot := 0, value := .literal 1 }]]
        #[.store { slot := 0, value := .literal 2 }],
      .returnValue (.storageLoad 0)])
    "NestedIf must nest the inner diamond inside the then branch"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"NestedIf plan must validate: {e.render}"
  let output ← liftResult "materialize NestedIf" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "NestedIf.yul") |
    throw <| IO.userError "NestedIf: missing NestedIf.yul"
  expect ((yulFile.contents.splitOn "sstore(0,").length >= 4 &&
      yulFile.contents.contains "add(expr" &&
      yulFile.contents.contains "let expr")
    "NestedIf Yul must render all three branch stores"

/-- Assert inside a branch: revert renders inside the branch body. -/
private unsafe def testAssertInBranch : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BranchAssert where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry withdraw(delta : UInt64) : UInt64 do\n" ++
    "    if delta > 0 then\n" ++
    "      assert count >= delta\n" ++
    "      count := count - delta\n" ++
    "    else\n" ++
    "      count := 0\n" ++
    "    return count\n"
  let source ← liftResult "load BranchAssert" (← session.selectProgramV1
    text "<evm-branch-assert>" "Tests.EvmBranchAssert" none)
  let compiled ← liftResult "compile BranchAssert" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan BranchAssert" <| planEvm compiled
  expect (plan.entries[0]!.body == #[
      .ifThenElse (.compare .gt (.param 0) (.literal 0))
        #[.assert (.compare .ge (.storageLoad 0) (.param 0)),
          .store { slot := 0, value := .checkedSub (.storageLoad 0) (.param 0) }]
        #[.store { slot := 0, value := .literal 0 }],
      .returnValue (.storageLoad 0)])
    "BranchAssert must keep assert-then-store order inside the taken branch"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"BranchAssert plan must validate: {e.render}"
  let output ← liftResult "materialize BranchAssert" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "BranchAssert.yul") |
    throw <| IO.userError "BranchAssert: missing BranchAssert.yul"
  let yul := yulFile.contents
  expect (yul.contains "if iszero(expr" && yul.contains "revert(0, 0)")
    "BranchAssert Yul must render the assert revert inside the branch"

/-- Match on UInt64 literals: switch with two cases and a wildcard default. -/
private unsafe def testMatchUIntLiterals : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MatchUint where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry apply(delta : UInt64) : UInt64 do\n" ++
    "    match delta with\n" ++
    "    | 0 => do\n" ++
    "      return count\n" ++
    "    | 1 => do\n" ++
    "      count := count + 1\n" ++
    "    | _ => do\n" ++
    "      count := delta\n" ++
    "    return count\n"
  let source ← liftResult "load MatchUint" (← session.selectProgramV1
    text "<evm-match-uint>" "Tests.EvmMatchUint" none)
  let compiled ← liftResult "compile MatchUint" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan MatchUint" <| planEvm compiled
  expect (plan.entries[0]!.body == #[
      .switchOn (.param 0)
        #[(0, #[.returnValue (.storageLoad 0)]),
          (1, #[.store { slot := 0, value := .checkedAdd (.storageLoad 0) (.literal 1) }])]
        #[.store { slot := 0, value := .param 0 }],
      .returnValue (.storageLoad 0)])
    "MatchUint must lower literal cases to switchOn with a default store"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"MatchUint plan must validate: {e.render}"
  let output ← liftResult "materialize MatchUint" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "MatchUint.yul") |
    throw <| IO.userError "MatchUint: missing MatchUint.yul"
  let yul := yulFile.contents
  expect (yul.contains "eq(expr" && yul.contains ", 0)")
    "MatchUint Yul must compare the scrutinee against literal 0"
  expect (yul.contains ", 1)")
    "MatchUint Yul must compare the scrutinee against literal 1"
  expect (yul.contains "iszero(or(eq(")
    "MatchUint Yul must guard the default with the disjunction of cases"
  expect (yul.contains "arg0")
    "MatchUint Yul must render the default store from the scrutinee param"

/-- Match-bind arm: the binder aliases the scrutinee in the arm body. -/
private unsafe def testMatchBindArm : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MatchBind where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry apply(delta : UInt64) : UInt64 do\n" ++
    "    match delta with\n" ++
    "    | rest => do\n" ++
    "      count := count + rest\n" ++
    "    return count\n"
  let source ← liftResult "load MatchBind" (← session.selectProgramV1
    text "<evm-match-bind>" "Tests.EvmMatchBind" none)
  let compiled ← liftResult "compile MatchBind" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan MatchBind" <| planEvm compiled
  -- Catch-all-only match: scrutinee is not re-materialized; the arm body
  -- reads the binder as the scrutinee value (param 0) directly.
  expect (plan.entries[0]!.body == #[
      .store { slot := 0, value := .checkedAdd (.storageLoad 0) (.param 0) },
      .returnValue (.storageLoad 0)])
    "MatchBind must alias the binder to the scrutinee value without a switch"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"MatchBind plan must validate: {e.render}"

/-- validatePlan negatives for the new control-flow constructors. -/
private unsafe def testRegionValidationNegatives : IO Unit := do
  let base : Targets.Evm.Plan := {
    objectName := "NegRegion"
    runtimeObjectName := "NegRegion_runtime"
    storageLayout := #[{ sourceId := 0, name := "count", slot := 0 }]
    events := #[]
    errors := #[]
    constructor := none
    entries := #[
      { name := "go"
        selector := Targets.Evm.Keccak.selector "go" #[]
        params := #[]
        mutability := .nonpayable
        resultKind := .uint64
        body := #[
          .ifThenElse (.compare .gt (.storageLoad 0) (.literal 0))
            #[.store { slot := 0, value := .literal 1 }]
            #[],
          .returnValue (.storageLoad 0)] }
    ]
  }
  match Targets.Evm.validatePlan base with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"base region plan must validate: {e.render}"
  -- If condition must be Bool-typed (arithmetic is not).
  let badCond := { base with entries := base.entries.map fun e =>
    { e with body := #[
        .ifThenElse (.checkedAdd (.storageLoad 0) (.literal 1))
          #[.store { slot := 0, value := .literal 1 }] #[],
        .returnValue (.storageLoad 0)] } }
  match Targets.Evm.validatePlan badCond with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject non-Bool if condition"
  -- Statement after a both-returning branch at the same level.
  let afterReturn := { base with entries := base.entries.map fun e =>
    { e with body := #[
        .ifThenElse (.compare .gt (.storageLoad 0) (.literal 0))
          #[.returnValue (.storageLoad 0)] #[.returnValue (.literal 0)],
        .store { slot := 0, value := .literal 1 }] } }
  match Targets.Evm.validatePlan afterReturn with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject a statement after a both-returning branch"
  -- Store inside a view branch is rejected.
  let viewStore := { base with entries := base.entries.map fun e =>
    { e with
        mutability := .view
        body := #[
          .ifThenElse (.compare .gt (.storageLoad 0) (.literal 0))
            #[.store { slot := 0, value := .literal 1 }] #[],
          .returnValue (.storageLoad 0)] } }
  match Targets.Evm.validatePlan viewStore with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject a store inside a view branch"

/-- Early valued return in the then arm with a trailing join (the mirror
    guard-clause shape): the trailing join folds after the region. -/
private unsafe def testEarlyReturnJoin : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program EarlyReturn where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry cap(limit : UInt64) : UInt64 do\n" ++
    "    if count > limit then\n" ++
    "      return limit\n" ++
    "    else\n" ++
    "      count := count + 1\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let source ← liftResult "load EarlyReturn" (← session.selectProgramV1
    text "<evm-early-return>" "Tests.EvmEarlyReturn" none)
  let compiled ← liftResult "compile EarlyReturn" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan EarlyReturn" <| planEvm compiled
  expect (plan.entries[0]!.body == #[
      .ifThenElse (.compare .gt (.storageLoad 0) (.param 0))
        #[.returnValue (.param 0)]
        #[.store { slot := 0, value := .checkedAdd (.storageLoad 0) (.literal 1) }],
      .returnValue (.storageLoad 0)])
    "EarlyReturn cap must fold the trailing join return after the region"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"EarlyReturn plan must validate: {e.render}"
  let output ← liftResult "materialize EarlyReturn" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "EarlyReturn.yul") |
    throw <| IO.userError "EarlyReturn: missing EarlyReturn.yul"
  let yul := yulFile.contents
  expect (yul.contains "if expr" && yul.contains "if iszero(expr")
    "EarlyReturn Yul must render both branch guards"
  expect ((yul.splitOn "return(0, 32)").length == 4)
    "EarlyReturn Yul must render the early return, the join return, and the view return"

/-- An early bare return inside an initializer branch arm fails closed: the
    deployment epilogue must run on every path. Normalize currently rejects
    explicit bare `return` at the source boundary; the Plan validator
    independently rejects an in-arm bare-return marker. -/
private unsafe def testInitEarlyBareReturnClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program InitEarlyReturn where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    if initial > 0 then\n" ++
    "      return\n" ++
    "    else\n" ++
    "      count := initial\n" ++
    "    count := 0\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  match ← session.selectProgramV1 text "<evm-init-early-return>"
      "Tests.EvmInitEarlyReturn" none with
  | .error e => throw <| IO.userError s!"InitEarlyReturn must load, got {e.render}"
  | .ok source =>
      match Compiler.compileValidatedSourceV1 source with
      | .error (.invalidProgram message) =>
          expect (message.contains "bare return")
            s!"InitEarlyReturn must fail closed at Normalize, got {message}"
      | .error e =>
          throw <| IO.userError
            s!"InitEarlyReturn must fail with invalidProgram, got {e.render}"
      | .ok _ =>
          throw <| IO.userError "InitEarlyReturn must not compile (bare return)"
  -- Validator level: an in-arm bare-return marker in a constructor body is
  -- rejected even though a final top-level marker is the canonical shape.
  let base : Targets.Evm.Plan := {
    objectName := "InitEarly"
    runtimeObjectName := "InitEarly_runtime"
    storageLayout := #[{ sourceId := 0, name := "count", slot := 0 }]
    events := #[]
    errors := #[]
    constructor := some {
      params := #[{ sourceId := 0, name := "i", wordIndex := 0 }]
      stores := #[]
      body := #[
        .ifThenElse (.compare .gt (.param 0) (.literal 0))
          #[.returnNone]
          #[.store { slot := 0, value := .param 0 }],
        .store { slot := 0, value := .literal 0 },
        .returnNone
      ]
    }
    entries := #[
      { name := "get"
        selector := Targets.Evm.Keccak.selector "get" #[]
        params := #[]
        mutability := .view
        resultKind := .uint64
        body := #[.returnValue (.storageLoad 0)] }
    ]
  }
  match Targets.Evm.validatePlan base with
  | .error (.planInvariant .evm message) =>
      expect (message.contains "early bare return")
        s!"validatePlan must reject the in-arm bare return, got {message}"
  | .error e =>
      throw <| IO.userError s!"validatePlan must fail with planInvariant, got {e.render}"
  | .ok () => throw <| IO.userError "validatePlan must reject an in-arm bare return"

/-- Declared event/error: emit lowers to log1 with the Keccak topic, revert
    lowers to an ABI custom-error revert with the Keccak selector. -/
private unsafe def testEmitRevertFlow : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program EventFlow where\n" ++
    "  state count : UInt64\n" ++
    "  event Moved(src : UInt64, dst : UInt64)\n" ++
    "  error Cap(limit : UInt64)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    emit Moved(count, delta)\n" ++
    "    if count > delta then\n" ++
    "      revert Cap(delta)\n" ++
    "    else\n" ++
    "      count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let source ← liftResult "load EventFlow" (← session.selectProgramV1
    text "<evm-event-flow>" "Tests.EvmEventFlow" none)
  let compiled ← liftResult "compile EventFlow" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan EventFlow" <| planEvm compiled
  expect (plan.events.map (·.name) == #["Moved"] &&
      plan.events[0]!.fieldCount == 2 &&
      plan.errors.map (·.name) == #["Cap"] &&
      plan.errors[0]!.fieldCount == 1)
    "EventFlow must carry the declared event/error bindings"
  expect (plan.entries[0]!.body == #[
      .emitEvent 0 #[.storageLoad 0, .param 0],
      .ifThenElse (.compare .gt (.storageLoad 0) (.param 0))
        #[.revertError 0 #[.param 0]]
        #[.store { slot := 0, value := .checkedAdd (.storageLoad 0) (.param 0) }],
      .returnValue (.storageLoad 0)])
    "EventFlow bump must lower emit, branch revert, join return"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"EventFlow plan must validate: {e.render}"
  let output ← liftResult "materialize EventFlow" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "EventFlow.yul") |
    throw <| IO.userError "EventFlow: missing EventFlow.yul"
  let yul := yulFile.contents
  let expectedTopic := Targets.Evm.Keccak.keccak256Hex "Moved(uint64,uint64)".toUTF8
  expect (yul.contains s!"log1(0, 64, 0x{expectedTopic})")
    "EventFlow Yul must emit log1 with the Keccak Moved topic and two words"
  let expectedSelector := Targets.Evm.Keccak.selector "Cap" #["uint64"]
  expect ((yul.contains s!"revert(0, 36)") && (yul.contains expectedSelector))
    "EventFlow Yul must revert with the ABI Cap(uint64) selector and one word"
  let some abiFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "EventFlow.abi.json") |
    throw <| IO.userError "EventFlow: missing EventFlow.abi.json"
  expect (abiFile.contents.contains "\"type\":\"event\",\"name\":\"Moved\"" &&
      abiFile.contents.contains "\"type\":\"error\",\"name\":\"Cap\"")
    "EventFlow ABI must declare the Moved event and Cap error"

/-- Wave E: pureFn + PureCall lower into Plan.fns and callFn expressions.
    Nested localCall (quadruple → double) pins dense fn indices and Yul
    function defs in both constructor and runtime objects. -/
private unsafe def testFnLocalCall : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program FnCall where\n" ++
    "  state count : UInt64\n" ++
    "  fn double(x : UInt64) : UInt64 do\n" ++
    "    return x + x\n" ++
    "  fn quadruple(y : UInt64) : UInt64 do\n" ++
    "    return double(y) + double(y)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := double(initial)\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    count := count + quadruple(delta)\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let source ← liftResult "load FnCall" (← session.selectProgramV1
    text "<evm-fn-call>" "Tests.EvmFnCall" none)
  let compiled ← liftResult "compile FnCall" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan FnCall" <| planEvm compiled
  expect (plan.fns.size == 2)
    "FnCall must lower two pureFn bindings"
  expect (plan.fns.map (·.name) == #["double", "quadruple"])
    "FnCall fn table must preserve pureFn source order"
  expect (plan.fns[0]!.params.map (·.name) == #["x"] &&
      !plan.fns[0]!.resultIsBool &&
      plan.fns[0]!.body == #[.returnValue (.checkedAdd (.param 0) (.param 0))])
    "double body must return x + x"
  expect (plan.fns[1]!.params.map (·.name) == #["y"] &&
      !plan.fns[1]!.resultIsBool &&
      plan.fns[1]!.body == #[.returnValue
        (.checkedAdd (.callFn 0 #[.param 0]) (.callFn 0 #[.param 0]))])
    "quadruple body must call double twice and add"
  match plan.constructor with
  | none => throw <| IO.userError "FnCall must retain constructor"
  | some ctor =>
      expect (ctor.body == #[.store {
          slot := 0
          value := .callFn 0 #[.param 0] }] ||
          ctor.stores == #[{ slot := 0, value := .callFn 0 #[.param 0] }])
        "init must store double(initial)"
  expect (plan.entries[0]!.body == #[
      .store {
        slot := 0
        value := .checkedAdd (.storageLoad 0) (.callFn 1 #[.param 0])
      },
      .returnValue (.storageLoad 0)])
    "bump must add quadruple(delta) into count"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"FnCall plan must validate: {e.render}"
  let output ← liftResult "materialize FnCall" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "FnCall.yul") |
    throw <| IO.userError "FnCall: missing FnCall.yul"
  let yul := yulFile.contents
  expect (yul.contains "function pf_fn0(" && yul.contains "function pf_fn1(")
    "FnCall Yul must define pf_fn0 and pf_fn1"
  -- Both constructor and runtime objects carry identical defs (self-contained).
  expect ((yul.splitOn "function pf_fn0(").length == 3)
    "FnCall Yul must emit pf_fn0 in both objects (two defs + one split remainder)"
  expect ((yul.splitOn "function pf_fn1(").length == 3)
    "FnCall Yul must emit pf_fn1 in both objects"
  expect (yul.contains "pf_fn0(" && yul.contains "pf_fn1(")
    "FnCall Yul must contain call sites for both pure functions"
  -- Negative: out-of-range fnIndex fails closed at validatePlan.
  let badPlan : Targets.Evm.Plan := {
    plan with entries := plan.entries.map fun e =>
      if e.name == "bump" then
        { e with body := #[
            .returnValue (.callFn 99 #[.param 0])] }
      else e
  }
  match Targets.Evm.validatePlan badPlan with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "out-of-range callFn must not validate"

private unsafe def testComparisonNegatives : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- Bool in state position must fail closed before EVM Plan (typed/normalize).
  let boolState :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BadBoolState where\n" ++
    "  state flag : Bool\n" ++
    "  init() do\n" ++
    "    flag := true\n" ++
    "  view get() : UInt64 do\n" ++
    "    return 0\n"
  match ← session.selectProgramV1 boolState "<evm-bool-state>" "Tests.EvmBoolState" none with
  | .error _ => pure ()
  | .ok source =>
      match Compiler.compileValidatedSourceV1 source with
      | .error _ => pure ()
      | .ok compiled =>
          match planEvm compiled with
          | .error (.planInvariant .evm _) => pure ()
          | .error e => throw <| IO.userError s!"Bool state must fail closed, got {e.render}"
          | .ok _ => throw <| IO.userError "Bool state must not produce an EVM plan"
  -- Bool as param fails closed.
  let boolParam :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BadBoolParam where\n" ++
    "  view pick(flag : Bool) : UInt64 do\n" ++
    "    return 1\n"
  match ← session.selectProgramV1 boolParam "<evm-bool-param>" "Tests.EvmBoolParam" none with
  | .error _ => pure ()
  | .ok source =>
      match Compiler.compileValidatedSourceV1 source with
      | .error _ => pure ()
      | .ok compiled =>
          match planEvm compiled with
          | .error (.planInvariant .evm _) => pure ()
          | .error e => throw <| IO.userError s!"Bool param must fail closed, got {e.render}"
          | .ok _ => throw <| IO.userError "Bool param must not produce an EVM plan"

/-- Wave F: mul/div/mod + unary bitNot/boolNot Plan lowering and Yul. -/
private unsafe def testArithOps : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArithOps where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry scale(factor : UInt64, divisor : UInt64) : UInt64 do\n" ++
    "    count := count * factor / divisor + count % divisor\n" ++
    "    return count\n" ++
    "  entry bits(x : UInt64) : UInt64 do\n" ++
    "    return ~x\n" ++
    "  entry neg5(x : UInt64) : Bool do\n" ++
    "    return !(x > 5)\n"
  let source ← liftResult "load ArithOps" (← session.selectProgramV1
    sourceText "<evm-arith-ops>" "Tests.EvmArithOps" none)
  let compiled ← liftResult "compile ArithOps" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan ArithOps" <| planEvm compiled
  expect (plan.entries.map (·.name) == #["scale", "bits", "neg5"])
    "ArithOps must lower three entries in source order"
  let scale := plan.entries[0]!
  expect (scale.body == #[
      .store {
        slot := 0
        value := .checkedAdd
          (.checkedDiv
            (.checkedMul (.storageLoad 0) (.param 0))
            (.param 1))
          (.checkedMod (.storageLoad 0) (.param 1))
      },
      .returnValue (.storageLoad 0)])
    "scale must lower mul/div/mod into checkedMul/checkedDiv/checkedMod with left-assoc + lower-tier add"
  let bits := plan.entries[1]!
  expect (bits.body == #[.returnValue (.bitNot (.param 0))])
    "bits must lower ~x to bitNot on the param"
  let neg5 := plan.entries[2]!
  expect (neg5.resultKind == .bool)
    "neg5 must declare a Bool result"
  expect (neg5.body == #[
      .returnValue (.boolNot (.compare .gt (.param 0) (.literal 5)))])
    "neg5 must lower !(x > 5) to boolNot over a gt compare"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ArithOps plan must validate: {e.render}"
  let output ← liftResult "materialize ArithOps" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "ArithOps.yul") |
    throw <| IO.userError "ArithOps: missing ArithOps.yul"
  let yul := yulFile.contents
  expect (yul.contains "mul(")
    "ArithOps Yul must render mul("
  expect (yul.contains "div(")
    "ArithOps Yul must render div("
  expect (yul.contains "mod(")
    "ArithOps Yul must render mod("
  expect (yul.contains "not(")
    "ArithOps Yul must render bitwise not("
  expect (yul.contains "and(not(")
    "ArithOps Yul must mask bitwise not() to the UInt64 word (2^64-1 - x)"
  expect (yul.contains "iszero(")
    "ArithOps Yul must render iszero( for boolNot and/or zero-divisor guards"
  expect (yul.contains "revert(0, 0)")
    "ArithOps Yul must contain overflow/zero-divisor revert(0, 0) guards"
  -- The UInt64 ceiling appears once per guarded op: sload, checkedMul,
  -- checkedAdd (sub(max, rhs)), and the bitNot mask. Fewer occurrences
  -- means a guard regressed (e.g. checkedMul previously used a round-trip
  -- div check that could never fire on 256-bit Yul arithmetic).
  let maskCount := (yul.splitOn "0xffffffffffffffff").length - 1
  expect (maskCount >= 4)
    s!"ArithOps Yul must carry four UInt64-ceiling guard uses, got {maskCount}"
  -- Hand-crafted negative: store a boolNot into a UInt64 slot fails closed.
  let base := plan
  let scaleEntry := base.entries[0]!
  let storeBoolNot := { base with entries := base.entries.set! 0 {
    scaleEntry with body := #[
      .store { slot := 0, value := .boolNot (.compare .gt (.param 0) (.literal 5)) },
      .returnValue (.storageLoad 0)
    ]
  } }
  match Targets.Evm.validatePlan storeBoolNot with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject storing boolNot into a UInt64 slot"
  -- Bool entry returning bitNot (UInt64-typed) fails closed.
  let neg5Entry := base.entries[2]!
  let boolReturnsBitNot := { base with entries := base.entries.set! 2 {
    neg5Entry with body := #[.returnValue (.bitNot (.param 0))]
  } }
  match Targets.Evm.validatePlan boolReturnsBitNot with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject Bool entry returning bitNot"

/-- Wave H: shift / bitwise / strict logical binary Plan lowering and Yul. -/
private unsafe def testShiftBitwiseLogical : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BitLogic where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry shiftMask(x : UInt64) : UInt64 do\n" ++
    "    count := (x << 2) & 15 | (x >> 1) ^ 3\n" ++
    "    return count\n" ++
    "  entry both(a : UInt64, b : UInt64) : Bool do\n" ++
    "    return a > 0 && b > 0\n" ++
    "  entry strictOr(a : UInt64, b : UInt64) : Bool do\n" ++
    "    let one : UInt64 := 1\n" ++
    "    return a > 0 || (one / b) == one\n" ++
    "  entry bigShift(x : UInt64) : UInt64 do\n" ++
    "    return x >> (32 + 32)\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let source ← liftResult "load BitLogic" (← session.selectProgramV1
    sourceText "<evm-bit-logic>" "Tests.EvmBitLogic" none)
  let compiled ← liftResult "compile BitLogic" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan BitLogic" <| planEvm compiled
  expect (plan.entries.map (·.name) ==
      #["shiftMask", "both", "strictOr", "bigShift", "get"])
    "BitLogic must lower five entries in source order"
  let shiftMask := plan.entries[0]!
  -- Precedence: shift > bitAnd > bitXor > bitOr
  -- ((x << 2) & 15) | ((x >> 1) ^ 3)
  expect (shiftMask.body == #[
      .store {
        slot := 0
        value := .bitOr
          (.bitAnd
            (.shl (.param 0) (.literal 2))
            (.literal 15))
          (.bitXor
            (.shr (.param 0) (.literal 1))
            (.literal 3))
      },
      .returnValue (.storageLoad 0)])
    "shiftMask must lower shl/bitAnd/shr/bitXor/bitOr with exact nesting"
  let both := plan.entries[1]!
  expect (both.resultKind == .bool)
    "both must declare a Bool result"
  expect (both.body == #[
      .returnValue
        (.logicalAnd
          (.compare .gt (.param 0) (.literal 0))
          (.compare .gt (.param 1) (.literal 0)))])
    "both must lower a > 0 && b > 0 to logicalAnd over two gt compares"
  let strictOr := plan.entries[2]!
  expect (strictOr.resultKind == .bool)
    "strictOr must declare a Bool result"
  expect (strictOr.body == #[
      .returnValue
        (.logicalOr
          (.compare .gt (.param 0) (.literal 0))
          (.compare .eq
            (.checkedDiv (.literal 1) (.param 1))
            (.literal 1)))])
    "strictOr must lower a > 0 || (one / b) == one to logicalOr(gt, eq(div))"
  let bigShift := plan.entries[3]!
  -- Computed UInt32 count: only way to reach invalidShift at runtime (CheckV1
  -- rejects a literal count ≥ 64). Count is checkedAdd of two UInt32 lits.
  expect (bigShift.body == #[
      .returnValue
        (.shr (.param 0) (.checkedAdd (.literal 32) (.literal 32)))])
    "bigShift must lower x >> (32 + 32) to shr(param, checkedAdd(32, 32))"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"BitLogic plan must validate: {e.render}"
  let output ← liftResult "materialize BitLogic" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "BitLogic.yul") |
    throw <| IO.userError "BitLogic: missing BitLogic.yul"
  let yul := yulFile.contents
  expect (yul.contains "shl(")
    "BitLogic Yul must render shl("
  expect (yul.contains "shr(")
    "BitLogic Yul must render shr("
  expect (yul.contains "and(")
    "BitLogic Yul must render and("
  expect (yul.contains "xor(")
    "BitLogic Yul must render xor("
  expect (yul.contains "or(")
    "BitLogic Yul must render or("
  expect (yul.contains "lt(")
    "BitLogic Yul must render lt( for the shift-count guard"
  expect (yul.contains "iszero(lt(")
    "BitLogic Yul must count-guard with iszero(lt(k, 64)) (covers bigShift=64)"
  expect (yul.contains "gt(expr")
    "BitLogic Yul must overflow-guard shl with gt(exprN, 0xffffffffffffffff)"
  expect (yul.contains "revert(0, 0)")
    "BitLogic Yul must contain shift/overflow/zero-divisor revert(0, 0) guards"
  -- bigShift's computed count materialises as add of two 32 literals under the
  -- ordinary checked-add form; the shift-count guard reverts at runtime.
  expect (yul.contains "add(")
    "BitLogic Yul must render add( for the bigShift UInt32 count expression"
  pure ()

/-- Wave G: bounded for-loop Plan recovery, runtime maxIterations back-edge
    enforcement, and Yul `for` rendering. -/
private unsafe def testForLoop : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program LoopSum where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry addUp(n : UInt64) : UInt64 do\n" ++
    "    let limit : UInt64 := n + 4\n" ++
    "    for i in n ..< limit bounded 8 do\n" ++
    "      count := count + i\n" ++
    "    return count\n" ++
    "  entry scan(n : UInt64) : UInt64 do\n" ++
    "    for i in n ..< n bounded 2 do\n" ++
    "      count := count + 1\n" ++
    "    return count\n" ++
    "  entry addUpTight(n : UInt64) : UInt64 do\n" ++
    "    for i in n ..< n + 4 bounded 3 do\n" ++
    "      count := count + i\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let source ← liftResult "load LoopSum" (← session.selectProgramV1
    sourceText "<evm-for-loop>" "Tests.EvmForLoop" none)
  let compiled ← liftResult "compile LoopSum" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan LoopSum" <| planEvm compiled
  expect (plan.entries.map (·.name) == #["addUp", "scan", "addUpTight", "get"])
    "LoopSum must lower four entries in source order"
  let addUp := plan.entries[0]!
  -- Induction temp = block-param ValueId 1; counter temp = maxBp+1+loopIdx = 2.
  expect (addUp.body == #[
      .forLoop 1 2 8
        (.param 0)
        (.compare .lt (.temp 1) (.checkedAdd (.param 0) (.literal 4)))
        (.add (.temp 1) (.literal 1))
        #[.store {
          slot := 0
          value := .checkedAdd (.storageLoad 0) (.temp 1)
        }],
      .returnValue (.storageLoad 0)])
    "addUp must lower let+for into forLoop with counter/maxIterations/init/cond/update/body"
  let scan := plan.entries[1]!
  expect (scan.body == #[
      .forLoop 1 2 2
        (.param 0)
        (.compare .lt (.temp 1) (.param 0))
        (.add (.temp 1) (.literal 1))
        #[.store {
          slot := 0
          value := .checkedAdd (.storageLoad 0) (.literal 1)
        }],
      .returnValue (.storageLoad 0)])
    "scan must lower a zero-trip for (n ..< n) with maxIterations=2"
  let addUpTight := plan.entries[2]!
  -- Over-declared: range spans 4 values but bound is 3 — Plan carries 3;
  -- Yul reverts at the back edge after the 4th body (reference-exact).
  expect (addUpTight.body == #[
      .forLoop 1 2 3
        (.param 0)
        (.compare .lt (.temp 1) (.checkedAdd (.param 0) (.literal 4)))
        (.add (.temp 1) (.literal 1))
        #[.store {
          slot := 0
          value := .checkedAdd (.storageLoad 0) (.temp 1)
        }],
      .returnValue (.storageLoad 0)])
    "addUpTight must pin forLoop maxIterations=3 for the over-bound case"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"LoopSum plan must validate: {e.render}"
  let output ← liftResult "materialize LoopSum" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "LoopSum.yul") |
    throw <| IO.userError "LoopSum: missing LoopSum.yul"
  let yul := yulFile.contents
  expect (yul.contains "for {")
    "LoopSum Yul must render native for {"
  expect (yul.contains "lt(")
    "LoopSum Yul must render lt( for the loop condition"
  expect (yul.contains "add(")
    "LoopSum Yul must render add( for limit/body/update arithmetic"
  expect (yul.contains "t1 :=")
    "LoopSum Yul must assign the induction temporary (t1 := ...)"
  expect (yul.contains "t1 := add(" || yul.contains "t1 := add")
    "LoopSum Yul must update the induction temporary via add"
  expect (yul.contains "t2 := 0")
    "LoopSum Yul must init the completed-iteration counter to 0"
  expect (yul.contains "if eq(t2, 8)")
    "LoopSum Yul must back-edge check addUp bound 8"
  expect (yul.contains "if eq(t2, 3)")
    "LoopSum Yul must back-edge check addUpTight bound 3"
  expect (yul.contains "if eq(t2," && yul.contains "revert(0, 0)")
    "LoopSum Yul must revert(0, 0) when the static bound is exceeded at the back edge"
  expect (yul.contains "t2 := add(t2, 1)")
    "LoopSum Yul must increment the completed-iteration counter after the bound check"
  -- No-loop programs remain accepted (regression guard via Counter path in run).
  pure ()

unsafe def run : IO Unit := do
  testSemanticPlanSourceAuthority
  testRichUInt64SemanticPlan
  testGuardedCounterSemanticPlan
  testInitWithAssert
  testCompareAssertPlanMutations
  testBoolResultPositive
  testBoolPredicateEndToEnd
  testIfFlowMultiBlock
  testIfNoElse
  testIfBothReturn
  testNestedIf
  testAssertInBranch
  testMatchUIntLiterals
  testMatchBindArm
  testEarlyReturnJoin
  testInitEarlyBareReturnClosed
  testEmitRevertFlow
  testFnLocalCall
  testArithOps
  testShiftBitwiseLogical
  testForLoop
  testRegionValidationNegatives
  testComparisonNegatives
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load Counter" (← session.selectProgramV1
    Examples.counterSourceText "<evm-smoke-counter>" Examples.counterModuleNameV1 none)
  let compiled ← liftResult "compile Counter" <| Compiler.compileValidatedSourceV1 source
  let sourceDigest := CompiledSemanticV1.sourceDigestOf compiled
  let semanticDigest := CompiledSemanticV1.semanticDigestOf compiled
  let plan ← liftResult "plan EVM" <| planEvm compiled
  expect (plan.objectName == "Counter" && plan.storageLayout.map (·.name) == #["count"])
    "EVM smoke must preserve the Counter identity and storage layout"
  expect (plan.entries.map (·.name) == #["increment", "get"])
    "EVM smoke must preserve both Counter entries"
  expect (plan.entries.map (·.resultKind) == #[.uint64, .uint64])
    "Counter entries remain UInt64 resultKind"
  -- Store-only constructor remains stores-authoritative (body empty).
  match plan.constructor with
  | none => throw <| IO.userError "Counter must retain constructor"
  | some ctor =>
      expect (ctor.body.isEmpty && !ctor.stores.isEmpty)
        "store-only Counter constructor must keep body empty for aggregate compatibility"

  -- S6: no public Plan→IR; capability materialize is sole emit path.
  let output ← liftResult "materialize EVM" <| materializeSelected TargetId.evm compiled
  let files := MaterializedArtifactsV1.filesOf output
  expect (files.map (·.path) == #["Counter.yul", "Counter.abi.json"])
    "EVM smoke must emit deterministic target-owned source artifacts"
  let yul ← match files.find? (·.path == "Counter.yul") with
    | some f => pure f.contents
    | none => throw <| IO.userError "EVM smoke missing Counter.yul"
  let abi ← match files.find? (·.path == "Counter.abi.json") with
    | some f => pure f.contents
    | none => throw <| IO.userError "EVM smoke missing Counter.abi.json"
  expect (yul.contains "case 0xdd9a82bc" && yul.contains "case 0x6d4ce63c")
    "EVM smoke must render canonical increment/get selectors"
  expect (abi.contains "\"name\":\"increment\"" && abi.contains "\"name\":\"get\"")
    "EVM smoke must render the Counter ABI"
  expect (abi.contains "\"type\":\"uint64\"" && !(abi.contains "\"type\":\"bool\""))
    "Counter ABI must remain all-uint64 (no bool outputs)"
  expect (MaterializedArtifactsV1.sourceDigestOf output == sourceDigest &&
      MaterializedArtifactsV1.semanticDigestOf output == semanticDigest)
    "EVM smoke carrier must bind canonical source and semantic digests"
  -- plan is still capability-gated and used for layout assertions above
  let _ := plan
  IO.println "Tests.Materialization.EvmSmoke: ok"

end Tests.Materialization.EvmSmoke
