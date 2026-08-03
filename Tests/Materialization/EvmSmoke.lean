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

/-- EVM pilot String layout: length UInt64 + 8×UInt64 data words (max 64 payload). -/
private def stringLeafEqAgainstParams (payload : String) : Targets.Evm.Expr := Id.run do
  let utf8 := payload.toUTF8
  let len : UInt64 := UInt64.ofNat utf8.size
  let mut words : Array UInt64 := #[]
  for w in [0:8] do
    let mut word : Nat := 0
    let mut place : Nat := 1
    for b in [0:8] do
      let idx := w * 8 + b
      let byte := if idx < utf8.size then (utf8.get! idx).toNat else 0
      word := word + byte * place
      place := place * 256
    words := words.push (UInt64.ofNat word)
  -- Leaf-wise AND of eq(param_i, literal_i) for length + 8 data words.
  let mut acc : Targets.Evm.Expr :=
    .compare .eq (.param 0) (.literal len)
  for i in [0:8] do
    acc := .logicalAnd acc
      (.compare .eq (.param (i + 1)) (.literal words[i]!))
  pure acc

/-- N-A1: match on String scrutinee desugars to leaf-wise eq + nested if chains
    (Plan `switchOn` remains UInt64-case only). Pins exact Plan shape + Yul. -/
private unsafe def testMatchStringLiterals : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MatchString where\n" ++
    "  state pad : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    pad := initial\n" ++
    "  entry classify(x : String) : UInt64 do\n" ++
    "    match x with\n" ++
    "    | \"hello\" => do\n" ++
    "      return 1\n" ++
    "    | \"world\" => do\n" ++
    "      return 2\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let source ← liftResult "load MatchString" (← session.selectProgramV1
    text "<evm-match-string>" "Tests.EvmMatchString" none)
  let compiled ← liftResult "compile MatchString" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan MatchString" <| planEvm compiled
  let helloEq := stringLeafEqAgainstParams "hello"
  let worldEq := stringLeafEqAgainstParams "world"
  -- First-match nesting: if hello then 1 else (if world then 2 else 0).
  expect (plan.entries[0]!.body == #[
      .ifThenElse helloEq
        #[.returnValue (.literal 1)]
        #[.ifThenElse worldEq
            #[.returnValue (.literal 2)]
            #[.returnValue (.literal 0)]]])
    "MatchString must desugar String match to nested ifThenElse + leaf-wise eq"
  -- No residual switchOn on the String entry (scalar UInt match still uses switchOn).
  let hasSwitch := plan.entries[0]!.body.any fun s =>
    match s with | .switchOn .. => true | _ => false
  expect (!hasSwitch) "MatchString must not emit switchOn for String scrutinee"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"MatchString plan must validate: {e.render}"
  let output ← liftResult "materialize MatchString" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "MatchString.yul") |
    throw <| IO.userError "MatchString: missing MatchString.yul"
  let yul := yulFile.contents
  -- Exact Yul pins: leaf-wise eq chain on ABI words + nested if / iszero fallthrough.
  -- EmitIR renders compare/logicalAnd as stepwise temps:
  --   let exprN := arg0; let exprN+1 := 5; let exprN+2 := eq(exprN, exprN+1)
  --   let … := and(…)
  -- not a single nested and(and(...eq(arg0,5)...)).
  expect (yul.contains "let arg0 := calldataload(4)" &&
      yul.contains "let arg8 := calldataload(260)")
    "MatchString Yul must load all 9 String ABI words (len + 8 data)"
  expect (yul.contains ":= 5")
    "MatchString Yul must materialize String length literal 5"
  -- Prefer exact stepwise form when present; also accept compact eq(arg0, 5).
  expect (yul.contains "eq(expr0, expr1)" || yul.contains "eq(arg0, 5)")
    "MatchString Yul must compare String length leaf against 5"
  -- "hello" first data word little-endian packing of h,e,l,l,o.
  expect (yul.contains "478560413032")
    "MatchString Yul must compare first data word of \"hello\""
  -- "world" first data word.
  expect (yul.contains "431316168567")
    "MatchString Yul must compare first data word of \"world\""
  expect (yul.contains ":= and(")
    "MatchString Yul must fold leaf eqs with stepwise and"
  expect (yul.contains "if expr")
    "MatchString Yul must branch on the leaf-wise equality result temp"
  expect (yul.contains "if iszero(expr")
    "MatchString Yul must emit iszero fallthrough for nested else arms"
  -- Zero-padded remaining data words of short strings appear as literal 0 temps.
  expect (yul.contains ":= 0")
    "MatchString Yul must compare zero-padded String data words"

/-- N-A1 negative: non-String literal pattern on String scrutinee fails closed
    at TypeCheck/Normalize (never reaches EVM Plan). -/
private unsafe def testMatchStringNonStringPatternRejected : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MatchStringBad where\n" ++
    "  state pad : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    pad := initial\n" ++
    "  entry classify(x : String) : UInt64 do\n" ++
    "    match x with\n" ++
    "    | 0 => do\n" ++
    "      return 1\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let source ← liftResult "load MatchStringBad" (← session.selectProgramV1
    text "<evm-match-string-bad>" "Tests.EvmMatchStringBad" none)
  match Compiler.compileValidatedSourceV1 source with
  | .ok _ =>
      throw <| IO.userError
        "MatchStringBad: integer pattern on String scrutinee must fail closed"
  | .error e =>
      let msg := e.render
      expect (msg.contains "String" || msg.contains "PF-SRC-INVALID" ||
          msg.contains "pattern" || msg.contains "type" || msg.contains "match")
        s!"MatchStringBad must cite pattern/type/String boundary, got {msg}"

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
  -- rejects a literal count ≥ 64). UInt32 body arith uses narrowCheckedAdd 32
  -- (T7 multi-width); UInt64 shr constructor is unchanged.
  expect (bigShift.body == #[
      .returnValue
        (.shr (.param 0) (.narrowCheckedAdd 32 (.literal 32) (.literal 32)))])
    "bigShift must lower x >> (32 + 32) to shr(param, narrowCheckedAdd 32 (32, 32))"
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

/-- T10: Principal state + param leaf storage (N4 String-isomorphic layout).
    * state owner : Principal → 9 storage slots (owner_len + owner_w0..w7)
    * init/entry Principal params → 9 ABI words each (leaf tuple, not `bytes`)
    * eq/ne and state load/store via aggregate leaf path
    * multi-word Principal entry/view *result* still fail closed
    * Principal is not an EVM address (CALL remains static QN) -/
private unsafe def testPrincipalStateStorage : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PrincipalOwner where\n" ++
    "  state owner : Principal\n" ++
    "  init(initial : Principal) do\n" ++
    "    owner := initial\n" ++
    "  entry setOwner(who : Principal) : Bool do\n" ++
    "    owner := who\n" ++
    "    return true\n" ++
    "  entry same(a : Principal, b : Principal) : Bool do\n" ++
    "    return a == b\n" ++
    "  entry matchesOwner(who : Principal) : Bool do\n" ++
    "    return owner == who\n"
  let source ← liftResult "load PrincipalOwner" (← session.selectProgramV1
    text "<evm-principal-owner>" "Tests.EvmPrincipalOwner" none)
  let compiled ← liftResult "compile PrincipalOwner" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan PrincipalOwner" <| planEvm compiled
  expect (plan.storageLayout.size == 9)
    s!"PrincipalOwner storage must be 9 leaves, got {plan.storageLayout.size}"
  expect (plan.storageLayout.map (·.name) ==
      #["owner_len", "owner_w0", "owner_w1", "owner_w2", "owner_w3",
        "owner_w4", "owner_w5", "owner_w6", "owner_w7"])
    s!"PrincipalOwner leaf names must be owner_len + owner_w0..w7, got {plan.storageLayout.map (·.name)}"
  for b in plan.storageLayout do
    expect (b.byteWidth == 8)
      s!"PrincipalOwner leaf {b.name} must be 64-bit word, got byteWidth={b.byteWidth}"
  match plan.constructor with
  | none => throw <| IO.userError "PrincipalOwner must retain initializer"
  | some ctor =>
      expect (ctor.params.size == 9)
        s!"PrincipalOwner init must expand Principal param to 9 ABI words, got {ctor.params.size}"
      expect (ctor.params[0]!.name == "initial_len")
        s!"PrincipalOwner init first leaf must be initial_len, got {ctor.params[0]!.name}"
      -- Principal is multi-leaf: storeAtomic (body) or historical 9 scalar stores.
      let atomicOk :=
        ctor.body.any fun s =>
          match s with
          | Targets.Evm.Statement.storeAtomic ops =>
              ops.size == 9 &&
                (Id.run do
                  let mut ok := true
                  for i in [0:9] do
                    if !(ops[i]!.slot == i && ops[i]!.value == .param i) then
                      ok := false
                  pure ok)
          | _ => false
      expect (ctor.stores.size == 9 || atomicOk)
        "PrincipalOwner init must store all 9 Principal leaves (storeAtomic or stores)"
      if ctor.stores.size == 9 then
        for i in [0:9] do
          expect (ctor.stores[i]!.slot == i)
            s!"PrincipalOwner init store[{i}] slot must be {i}"
          expect (ctor.stores[i]!.value == .param i)
            s!"PrincipalOwner init store[{i}] must be param {i}"
  let setOwner := plan.entries[0]!
  expect (setOwner.name == "setOwner")
    s!"first entry must be setOwner, got {setOwner.name}"
  expect (setOwner.params.size == 9)
    s!"setOwner must expand Principal param to 9 ABI words, got {setOwner.params.size}"
  expect (setOwner.params[0]!.name == "who_len")
    s!"setOwner first leaf must be who_len, got {setOwner.params[0]!.name}"
  let same := plan.entries[1]!
  expect (same.name == "same")
    s!"second entry must be same, got {same.name}"
  expect (same.params.size == 18)
    s!"same(a,b : Principal) must expand to 18 ABI words, got {same.params.size}"
  let matchesOwner := plan.entries[2]!
  expect (matchesOwner.name == "matchesOwner")
    s!"third entry must be matchesOwner, got {matchesOwner.name}"
  expect (matchesOwner.params.size == 9)
    s!"matchesOwner must expand Principal param to 9 ABI words, got {matchesOwner.params.size}"
  -- stateLoad + leaf-wise eq against multi-word param (pins Semantic ValueId
  -- paramCount boundary; ABI word count must not be used as ValueId bound).
  expect (matchesOwner.body.size ≥ 1)
    "matchesOwner must emit at least a return of leaf-wise Principal eq"
  -- Yul materializes multi-word param/state load/store and leaf-wise eq.
  let output ← liftResult "materialize PrincipalOwner" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "PrincipalOwner.yul") |
    throw <| IO.userError "PrincipalOwner: missing PrincipalOwner.yul"
  let yul := yulFile.contents
  expect (yul.contains "sstore(0," || yul.contains "sstore(0, ")
    "PrincipalOwner Yul must sstore leaf 0 (len)"
  expect (yul.contains "sstore(8," || yul.contains "sstore(8, ")
    "PrincipalOwner Yul must sstore leaf 8 (last payload word)"
  expect (yul.contains "sload(0)" || yul.contains "sload(0,")
    "PrincipalOwner Yul must sload leaf 0 for matchesOwner"
  expect (yul.contains "sload(8)" || yul.contains "sload(8,")
    "PrincipalOwner Yul must sload leaf 8 for matchesOwner"
  expect (yul.contains "eq(")
    "PrincipalOwner Yul must emit leaf-wise eq for Principal comparison"
  -- ABI: Principal params render as successive uint64 leaf words (N4 String pattern).
  let some abiFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "PrincipalOwner.abi.json") |
    throw <| IO.userError "PrincipalOwner: missing PrincipalOwner.abi.json"
  expect (abiFile.contents.contains "\"type\":\"uint64\"")
    "PrincipalOwner ABI must use uint64 leaf words for Principal params"
  expect (abiFile.contents.contains "who_len" ||
      abiFile.contents.contains "initial_len")
    "PrincipalOwner ABI must name Principal length leaf (*_len)"
  -- Multi-word Principal return remains fail closed.
  let retText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PrincipalRet where\n" ++
    "  state owner : Principal\n" ++
    "  init(initial : Principal) do\n" ++
    "    owner := initial\n" ++
    "  view getOwner() : Principal do\n" ++
    "    return owner\n"
  let retSource ← liftResult "load PrincipalRet" (← session.selectProgramV1
    retText "<evm-principal-ret>" "Tests.EvmPrincipalRet" none)
  let retCompiled ← liftResult "compile PrincipalRet" <|
    Compiler.compileValidatedSourceV1 retSource
  match planEvm retCompiled with
  | .ok _ =>
      throw <| IO.userError
        "Principal multi-word entry/view result must fail closed"
  | .error e =>
      expect ((e.render).contains "return" || (e.render).contains "Principal" ||
          (e.render).contains "UInt" || (e.render).contains "public" ||
          (e.render).contains "unsupported")
        s!"Principal return fail-closed message, got {e.render}"
  pure ()

/-- AddressBearing product path: EVM admits static QualifiedName call/schedule
    (wire Op.ExternalCall/Schedule take compile-time QN, not a dynamic address
    ValueId). Plan lowers CALL to a fixed keccak-derived 20-byte address.
    T10 opens Principal *storage* only — still not a CALL target. -/
private unsafe def testExternalCallGate : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let callText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CallGate where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    call Oracle.feed(count)\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let callSource ← liftResult "load CallGate" (← session.selectProgramV1
    callText "<evm-call-gate>" "Tests.EvmCallGate" none)
  let callCompiled ← liftResult "compile CallGate" <|
    Compiler.compileValidatedSourceV1 callSource
  let callSelection ← liftResult "select EVM (call)" <|
    resolveBuildSelectionV1 TargetId.evm none
  let callCap ← liftResult "resolve CallGate" <|
    Targets.resolveEngineeringRequirementsV1 callSelection callCompiled
  let callPlan ← liftResult "plan CallGate" <| Targets.Evm.planFromCapability callCap
  let bump := callPlan.entries[0]!
  match bump.body[0]? with
  | some (stmt : Targets.Evm.Statement) =>
      match stmt with
      | .externalCall #["Oracle", "feed"] #[.storageLoad 0] => pure ()
      | _ => throw <| IO.userError "CallGate bump must start with externalCall Oracle.feed"
  | none => throw <| IO.userError "CallGate bump body is empty"
  let callIr ← liftResult "ir CallGate" <| Targets.Evm.irFromCapability callCap
  expect (callIr.yul.contains "call(gas(), 0x")
    "CallGate Yul must emit CALL to the fixed keccak-derived address"
  expect (callIr.yul.contains "if iszero(")
    "CallGate Yul must revert on CALL failure (sync external call)"

  let scheduleText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ScheduleGate where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    schedule Ledger.daily(count)\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let scheduleSource ← liftResult "load ScheduleGate" (← session.selectProgramV1
    scheduleText "<evm-schedule-gate>" "Tests.EvmScheduleGate" none)
  let scheduleCompiled ← liftResult "compile ScheduleGate" <|
    Compiler.compileValidatedSourceV1 scheduleSource
  let scheduleSelection ← liftResult "select EVM (schedule)" <|
    resolveBuildSelectionV1 TargetId.evm none
  let scheduleCap ← liftResult "resolve ScheduleGate" <|
    Targets.resolveEngineeringRequirementsV1 scheduleSelection scheduleCompiled
  let schedulePlan ← liftResult "plan ScheduleGate" <|
    Targets.Evm.planFromCapability scheduleCap
  match schedulePlan.entries[0]!.body[0]? with
  | some (stmt : Targets.Evm.Statement) =>
      match stmt with
      | .schedule #["Ledger", "daily"] #[.storageLoad 0] => pure ()
      | _ => throw <| IO.userError "ScheduleGate must start with schedule Ledger.daily"
  | none => throw <| IO.userError "ScheduleGate bump body is empty"
  let scheduleIr ← liftResult "ir ScheduleGate" <|
    Targets.Evm.irFromCapability scheduleCap
  expect (scheduleIr.yul.contains "call(gas(), 0x")
    "ScheduleGate Yul must emit CALL (fire-and-forget)"
  expect (scheduleIr.yul.contains "pop(")
    "ScheduleGate Yul must ignore CALL success (async schedule)"
  pure ()

/-- Walk Plan Expr trees for a narrow UInt8 checked-add. -/
private partial def exprHasNarrowCheckedAdd8 : Targets.Evm.Expr → Bool
  | .narrowCheckedAdd 8 _ _ => true
  | .narrowCheckedAdd _ l r | .narrowCheckedSub _ l r | .narrowCheckedMul _ l r
  | .narrowCheckedDiv _ l r | .narrowCheckedMod _ l r
  | .narrowBitAnd _ l r | .narrowBitOr _ l r | .narrowBitXor _ l r
  | .narrowShl _ l r | .narrowShr _ l r
  | .checkedAdd l r | .checkedSub l r | .checkedMul l r | .checkedDiv l r
  | .checkedMod l r | .compare _ l r | .bitAnd l r | .bitOr l r | .bitXor l r
  | .shl l r | .shr l r | .logicalAnd l r | .logicalOr l r | .add l r =>
      exprHasNarrowCheckedAdd8 l || exprHasNarrowCheckedAdd8 r
  | .bitNot o | .boolNot o | .narrowBitNot _ o => exprHasNarrowCheckedAdd8 o
  | .callFn _ args => args.any exprHasNarrowCheckedAdd8
  | _ => false

private partial def stmtHasNarrowCheckedAdd8 : Targets.Evm.Statement → Bool
  | .store s => exprHasNarrowCheckedAdd8 s.value
  | .returnValue e | .assert e => exprHasNarrowCheckedAdd8 e
  | .ifThenElse c t e =>
      exprHasNarrowCheckedAdd8 c || t.any stmtHasNarrowCheckedAdd8 ||
        e.any stmtHasNarrowCheckedAdd8
  | .switchOn s cs d =>
      exprHasNarrowCheckedAdd8 s ||
        cs.any (fun (_, b) => b.any stmtHasNarrowCheckedAdd8) ||
        d.any stmtHasNarrowCheckedAdd8
  | .forLoop _ _ _ i c u b =>
      exprHasNarrowCheckedAdd8 i || exprHasNarrowCheckedAdd8 c ||
        exprHasNarrowCheckedAdd8 u || b.any stmtHasNarrowCheckedAdd8
  | .emitEvent _ args | .revertError _ args => args.any exprHasNarrowCheckedAdd8
  | _ => false

private partial def exprHasNarrowShl8 : Targets.Evm.Expr → Bool
  | .narrowShl 8 _ _ => true
  | .narrowCheckedAdd _ l r | .narrowCheckedSub _ l r | .narrowCheckedMul _ l r
  | .narrowCheckedDiv _ l r | .narrowCheckedMod _ l r
  | .narrowBitAnd _ l r | .narrowBitOr _ l r | .narrowBitXor _ l r
  | .narrowShl _ l r | .narrowShr _ l r
  | .checkedAdd l r | .checkedSub l r | .compare _ l r | .shl l r | .shr l r
  | .bitAnd l r | .bitOr l r | .bitXor l r | .logicalAnd l r | .logicalOr l r
  | .add l r =>
      exprHasNarrowShl8 l || exprHasNarrowShl8 r
  | .bitNot o | .boolNot o | .narrowBitNot _ o => exprHasNarrowShl8 o
  | .callFn _ args => args.any exprHasNarrowShl8
  | _ => false

private partial def stmtHasNarrowShl8 : Targets.Evm.Statement → Bool
  | .store s => exprHasNarrowShl8 s.value
  | .returnValue e | .assert e => exprHasNarrowShl8 e
  | .ifThenElse c t e =>
      exprHasNarrowShl8 c || t.any stmtHasNarrowShl8 || e.any stmtHasNarrowShl8
  | _ => false

/-- T7-EVM: body multi-width UInt8/16/32 lets + arith + compare; entry ABI stays UInt64. -/
private unsafe def testBodyMultiWidthUInt : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BodyMw where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    let a : UInt8 := 10\n" ++
    "    let b : UInt8 := 20\n" ++
    "    let c : UInt8 := a + b\n" ++
    "    assert c > 5\n" ++
    "    let d : UInt16 := 300\n" ++
    "    let e : UInt16 := d - 1\n" ++
    "    assert e > 0\n" ++
    "    let f : UInt32 := 1000\n" ++
    "    let g : UInt32 := f * 2\n" ++
    "    assert g > 0\n" ++
    "    return x\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let source ← liftResult "load BodyMw" (← session.selectProgramV1
    sourceText "<evm-body-mw>" "Tests.EvmBodyMw" none)
  let compiled ← liftResult "compile BodyMw" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan BodyMw" <| planEvm compiled
  expect (plan.storageLayout.map (·.name) == #["count"])
    "BodyMw state remains single UInt64 count"
  let run := plan.entries[0]!
  expect (run.resultKind == .uint64)
    "BodyMw entry ABI result stays UInt64"
  expect (run.body.any stmtHasNarrowCheckedAdd8)
    "BodyMw plan must lower UInt8 add to narrowCheckedAdd 8"
  let output ← liftResult "materialize BodyMw" <| materializeSelected TargetId.evm compiled
  let yul ← match (MaterializedArtifactsV1.filesOf output).find? (·.path.endsWith ".yul") with
    | some f => pure f.contents
    | none => throw <| IO.userError "BodyMw missing yul"
  expect (yul.contains "0xff")
    "BodyMw Yul must emit UInt8 mask 0xff for narrow overflow/guards"
  expect (yul.contains "0xffff")
    "BodyMw Yul must emit UInt16 mask 0xffff"
  expect (yul.contains "0xffffffff")
    "BodyMw Yul must emit UInt32 mask 0xffffffff"
  let abi ← match (MaterializedArtifactsV1.filesOf output).find? (·.path.endsWith ".abi.json") with
    | some f => pure f.contents
    | none => throw <| IO.userError "BodyMw missing abi"
  expect (abi.contains "\"type\":\"uint64\"")
    "BodyMw ABI must still use uint64 for state/entry surface"
  expect (!(abi.contains "\"type\":\"uint8\""))
    "BodyMw ABI must not expose body UInt8 types"

/-- T7-EVM: UInt8 overflow lowers to narrowCheckedAdd and Yul reverts when sum > 0xff. -/
private unsafe def testBodyUInt8OverflowPlan : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program U8Overflow where\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    let a : UInt8 := 200\n" ++
    "    let b : UInt8 := 100\n" ++
    "    let c : UInt8 := a + b\n" ++
    "    assert c > 0\n" ++
    "    return x\n"
  let source ← liftResult "load U8Overflow" (← session.selectProgramV1
    sourceText "<evm-u8-ovf>" "Tests.EvmU8Ovf" none)
  let compiled ← liftResult "compile U8Overflow" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan U8Overflow" <| planEvm compiled
  let run := plan.entries[0]!
  expect (run.body.any stmtHasNarrowCheckedAdd8)
    "U8Overflow plan must contain narrowCheckedAdd 8"
  let output ← liftResult "materialize U8Overflow" <| materializeSelected TargetId.evm compiled
  let yul ← match (MaterializedArtifactsV1.filesOf output).find? (·.path.endsWith ".yul") with
    | some f => pure f.contents
    | none => throw <| IO.userError "U8Overflow missing yul"
  expect (yul.contains "0xff" && yul.contains "revert(0, 0)")
    "UInt8 overflow path must emit mask 0xff and revert"

/-- T7-EVM: multi-width shift on UInt8 body value (count UInt32). -/
private unsafe def testBodyMultiWidthShift : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BodyShift where\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    let a : UInt8 := 3\n" ++
    "    let b : UInt8 := a << 1\n" ++
    "    assert b > 0\n" ++
    "    return x\n"
  let source ← liftResult "load BodyShift" (← session.selectProgramV1
    sourceText "<evm-body-shift>" "Tests.EvmBodyShift" none)
  let compiled ← liftResult "compile BodyShift" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan BodyShift" <| planEvm compiled
  let run := plan.entries[0]!
  expect (run.body.any stmtHasNarrowShl8)
    "BodyShift plan must contain narrowShl 8"
  let output ← liftResult "materialize BodyShift" <| materializeSelected TargetId.evm compiled
  let yul ← match (MaterializedArtifactsV1.filesOf output).find? (·.path.endsWith ".yul") with
    | some f => pure f.contents
    | none => throw <| IO.userError "BodyShift missing yul"
  expect (yul.contains "lt(" && yul.contains "8")
    "BodyShift Yul must guard shift count against width 8"

/-- T8b-EVM: UInt8/16/32 state + param ABI multi-width product path.
    Keep every value live through a store/return so segment consumption
    does not see dead lets. Entry result stays UInt64 (out of T8b scope). -/
private unsafe def testAbiMultiWidthStateParam : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program AbiMw where\n" ++
    "  state flag : UInt8\n" ++
    "  state score : UInt16\n" ++
    "  state ticks : UInt32\n" ++
    "  init(f : UInt8, s : UInt16, t : UInt32) do\n" ++
    "    flag := f\n" ++
    "    score := s\n" ++
    "    ticks := t\n" ++
    "  entry bump(delta : UInt8) : UInt64 do\n" ++
    "    flag := flag + delta\n" ++
    "    score := score + 1\n" ++
    "    ticks := ticks + 1\n" ++
    "    return 1\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return 1\n"
  let source ← liftResult "load AbiMw" (← session.selectProgramV1
    sourceText "<evm-abi-mw>" "Tests.EvmAbiMw" none)
  let compiled ← liftResult "compile AbiMw" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan AbiMw" <| planEvm compiled
  expect (plan.storageLayout.map (·.name) == #["flag", "score", "ticks"])
    "AbiMw storage names"
  expect (plan.storageLayout.map (·.byteWidth) == #[1, 2, 4])
    "AbiMw storage byteWidth UInt8/16/32 → 1/2/4"
  match plan.constructor with
  | none => throw <| IO.userError "AbiMw must have constructor"
  | some ctor =>
      expect (ctor.params.map (·.byteWidth) == #[1, 2, 4])
        "AbiMw constructor params byteWidth 1/2/4"
  let bump := plan.entries[0]!
  expect (bump.params.size == 1 && bump.params[0]!.byteWidth == 1)
    "AbiMw bump param is UInt8 (byteWidth 1)"
  expect (bump.params[0]!.name == "delta")
    "AbiMw bump param name"
  let expectedSel := Targets.Evm.Keccak.selector "bump" #["uint8"]
  expect (bump.selector == expectedSel)
    s!"AbiMw selector must be keccak(bump(uint8))={expectedSel}, got {bump.selector}"
  -- Plan body must use narrow storage load/param constructors for UInt8 add.
  let hasNarrowU8Store :=
    bump.body.any fun s =>
      match s with
      | .store st =>
          st.byteWidth == 1 &&
            match st.value with
            | .narrowCheckedAdd 8 (.narrowStorageLoad 8 0) (.narrowParam 8 0) => true
            | .narrowCheckedAdd 8 _ _ => true
            | _ => false
      | _ => false
  expect hasNarrowU8Store
    "AbiMw plan must lower UInt8 state/param add to narrow forms"
  let hasNarrowU16Store :=
    bump.body.any fun s =>
      match s with
      | .store st => st.byteWidth == 2
      | _ => false
  let hasNarrowU32Store :=
    bump.body.any fun s =>
      match s with
      | .store st => st.byteWidth == 4
      | _ => false
  expect (hasNarrowU16Store && hasNarrowU32Store)
    "AbiMw plan must store UInt16/UInt32 slots with matching byteWidth"
  let output ← liftResult "materialize AbiMw" <| materializeSelected TargetId.evm compiled
  let yul ← match (MaterializedArtifactsV1.filesOf output).find? (·.path.endsWith ".yul") with
    | some f => pure f.contents
    | none => throw <| IO.userError "AbiMw missing yul"
  expect (yul.contains "and(calldataload(")
    "AbiMw Yul must mask narrow entry calldata with and(calldataload(...), mask)"
  expect (yul.contains "0xff" && yul.contains "0xffff" && yul.contains "0xffffffff")
    "AbiMw Yul must emit UInt8/16/32 masks"
  expect (yul.contains "and(sload(")
    "AbiMw Yul must mask narrow sload"
  expect (yul.contains s!"case 0x{expectedSel}")
    s!"AbiMw Yul must use updated selector case 0x{expectedSel}"
  let abi ← match (MaterializedArtifactsV1.filesOf output).find? (·.path.endsWith ".abi.json") with
    | some f => pure f.contents
    | none => throw <| IO.userError "AbiMw missing abi"
  expect (abi.contains "\"type\":\"uint8\"")
    "AbiMw ABI must expose uint8 for narrow param"
  expect (abi.contains "\"type\":\"uint16\"" && abi.contains "\"type\":\"uint32\"")
    "AbiMw ABI constructor must expose uint16/uint32"
  expect (abi.contains "\"type\":\"uint64\"")
    "AbiMw ABI result remains uint64"

/-- T9c-EVM: Int8 state + Int16 param + body arith + Int8 result; ABI types;
    Int128 fail closed. -/
private unsafe def testNarrowIntBodyAndAbi : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program NarrowInt where\n" ++
    "  state score : Int8\n" ++
    "  init(s : Int8) do\n" ++
    "    score := s\n" ++
    "  entry bump(delta : Int16) : Int8 do\n" ++
    "    let d : Int8 := 1\n" ++
    "    score := score + d\n" ++
    "    assert delta == delta\n" ++
    "    return score\n" ++
    "  view peek() : Int8 do\n" ++
    "    return score\n"
  let source ← liftResult "load NarrowInt" (← session.selectProgramV1
    sourceText "<evm-narrow-int>" "Tests.EvmNarrowInt" none)
  let compiled ← liftResult "compile NarrowInt" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan NarrowInt" <| planEvm compiled
  expect (plan.storageLayout.map (·.byteWidth) == #[1])
    "T9c: Int8 state byteWidth 1"
  expect (plan.storageLayout[0]!.name == "score")
    "T9c: Int8 state name"
  match plan.constructor with
  | none => throw <| IO.userError "NarrowInt must have constructor"
  | some ctor =>
      expect (ctor.params.size == 1 && ctor.params[0]!.isInt &&
          ctor.params[0]!.byteWidth == 1)
        "T9c: constructor Int8 param isInt byteWidth 1"
  let bump := plan.entries[0]!
  expect (bump.resultKind == .int8)
    "T9c: bump resultKind int8"
  expect (bump.params.size == 1 && bump.params[0]!.isInt &&
      bump.params[0]!.byteWidth == 2)
    "T9c: bump Int16 param isInt byteWidth 2"
  let expectedSel := Targets.Evm.Keccak.selector "bump" #["int16"]
  expect (bump.selector == expectedSel)
    s!"T9c: bump selector keccak(bump(int16))={expectedSel}, got {bump.selector}"
  let hasNarrowSignedAdd :=
    bump.body.any fun s =>
      match s with
      | .store st =>
          match st.value with
          | .narrowSignedCheckedAdd 8 _ _ => true
          | _ => false
      | _ => false
  expect hasNarrowSignedAdd
    "T9c: Int8 body add must lower to narrowSignedCheckedAdd 8"
  expect (plan.entries[1]!.resultKind == .int8)
    "T9c: peek resultKind int8"
  let output ← liftResult "materialize NarrowInt" <|
    materializeSelected TargetId.evm compiled
  let yul ← match (MaterializedArtifactsV1.filesOf output).find? (·.path.endsWith ".yul") with
    | some f => pure f.contents
    | none => throw <| IO.userError "NarrowInt missing yul"
  expect (yul.contains "signextend(")
    "T9c: Yul must sign-extend narrow Int ops"
  expect (yul.contains "0xff")
    "T9c: Yul must mask Int8 with 0xff"
  let abi ← match (MaterializedArtifactsV1.filesOf output).find? (·.path.endsWith ".abi.json") with
    | some f => pure f.contents
    | none => throw <| IO.userError "NarrowInt missing abi"
  expect (abi.contains "\"type\":\"int8\"" && abi.contains "\"type\":\"int16\"")
    "T9c: ABI must expose int8/int16"
  -- Int128 fail closed at plan type-closure.
  let wideText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program WideInt where\n" ++
    "  entry run(x : Int128) : Int128 do\n" ++
    "    return x\n"
  let wideSrc ← liftResult "load WideInt" (← session.selectProgramV1
    wideText "<evm-wide-int>" "Tests.EvmWideInt" none)
  match Compiler.compileValidatedSourceV1 wideSrc with
  | .error _ => pure ()
  | .ok compiledW =>
      match planEvm compiledW with
      | .error e =>
          expect (e.render.contains "Int" || e.render.contains "width" ||
              e.render.contains "supported" || e.render.contains "128")
            s!"Int128 must fail at EVM plan, got {e.render}"
      | .ok _ =>
          throw <| IO.userError "EVM plan must reject Int128"


/-- T9a-EVM: entry/view may return UInt8/16/32; ABI outputs and resultKind match. -/
private unsafe def testNarrowResultAdmitted : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program NarrowResult where\n" ++
    "  entry get8(x : UInt8) : UInt8 do\n" ++
    "    return x\n" ++
    "  entry get16(x : UInt16) : UInt16 do\n" ++
    "    return x\n" ++
    "  entry get32(x : UInt32) : UInt32 do\n" ++
    "    return x\n"
  let source ← liftResult "load NarrowResult" (← session.selectProgramV1
    sourceText "<evm-narrow-result>" "Tests.EvmNarrowResult" none)
  let compiled ← liftResult "compile NarrowResult"
    (Compiler.compileValidatedSourceV1 source)
  let plan ← liftResult "plan NarrowResult" (planEvm compiled)
  expect (plan.entries.map (·.resultKind) == #[.uint8, .uint16, .uint32])
    "T9a: EVM entry resultKinds must be uint8/16/32"
  let output ← liftResult "materialize NarrowResult" <|
    materializeSelected TargetId.evm compiled
  let abi ← match (MaterializedArtifactsV1.filesOf output).find? (·.path.endsWith ".abi.json") with
    | some f => pure f.contents
    | none => throw <| IO.userError "NarrowResult missing abi"
  expect (abi.contains "\"type\":\"uint8\"" &&
      abi.contains "\"type\":\"uint16\"" &&
      abi.contains "\"type\":\"uint32\"")
    "T9a: EVM ABI must declare uint8/16/32 outputs"


/-- T9b-EVM: UInt128/256 state + param + body + result admitted. -/
private unsafe def testWideUintProduct : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program WideUint where\n" ++
    "  state a : UInt128\n" ++
    "  state b : UInt256\n\n" ++
    "  init(x : UInt128, y : UInt256) do\n" ++
    "    a := x\n" ++
    "    b := y\n\n" ++
    "  entry add128(delta : UInt128) : UInt128 do\n" ++
    "    a := a + delta\n" ++
    "    return a\n\n" ++
    "  entry add256(delta : UInt256) : UInt256 do\n" ++
    "    b := b + delta\n" ++
    "    return b\n\n" ++
    "  view get128() : UInt128 do\n" ++
    "    return a\n\n" ++
    "  view get256() : UInt256 do\n" ++
    "    return b\n"
  let source ← liftResult "load WideUint" (← session.selectProgramV1
    sourceText "<evm-wide-uint>" "Tests.EvmWideUint" none)
  let compiled ← liftResult "compile WideUint"
    (Compiler.compileValidatedSourceV1 source)
  let plan ← liftResult "plan WideUint" (planEvm compiled)
  expect (plan.storageLayout.size == 2 &&
      plan.storageLayout[0]!.byteWidth == 16 &&
      plan.storageLayout[1]!.byteWidth == 32)
    "T9b: UInt128/256 state byteWidth must be 16/32"
  expect (plan.entries.map (·.resultKind) ==
      #[.uint128, .uint256, .uint128, .uint256])
    "T9b: entry/view resultKinds must be uint128/256"
  let add128 := plan.entries.find? (·.name == "add128")
  expect (match add128 with
    | some e => e.params.size == 1 && e.params[0]!.byteWidth == 16
    | none => false)
    "T9b: add128 param byteWidth 16"
  let output ← liftResult "materialize WideUint" <|
    materializeSelected TargetId.evm compiled
  let abi ← match (MaterializedArtifactsV1.filesOf output).find? (·.path.endsWith ".abi.json") with
    | some f => pure f.contents
    | none => throw <| IO.userError "WideUint missing abi"
  expect (abi.contains "\"type\":\"uint128\"" && abi.contains "\"type\":\"uint256\"")
    "T9b: ABI must declare uint128/uint256"
  let yul ← match (MaterializedArtifactsV1.filesOf output).find? (·.path.endsWith ".yul") with
    | some f => pure f.contents
    | none => throw <| IO.userError "WideUint missing yul"
  expect (yul.contains "0xffffffffffffffffffffffffffffffff")
    "T9b: Yul must emit UInt128 mask"

/-- T9b-EVM: UInt128 entry result admitted (was fail-closed under T9a). -/
private unsafe def testUInt128ResultAdmitted : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program U128Result where\n" ++
    "  entry run(x : UInt128) : UInt128 do\n" ++
    "    return x\n"
  let source ← liftResult "load U128Result" (← session.selectProgramV1
    sourceText "<evm-u128-result>" "Tests.EvmU128Result2" none)
  let compiled ← liftResult "compile U128Result"
    (Compiler.compileValidatedSourceV1 source)
  let plan ← liftResult "plan U128Result" (planEvm compiled)
  expect (plan.entries.map (·.resultKind) == #[.uint128])
    "T9b: UInt128 entry resultKind"

/-- Unit/void entry (`entry run() do`, no result type) fails closed at the EVM
    Plan seam: makeEntryV1 rejects non-UInt64/Bool entry results. -/
private unsafe def testVoidEntryRejected : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program VoidEntry where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry run() do\n" ++
    "    count := count + 1\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let source ← liftResult "load VoidEntry" (← session.selectProgramV1
    text "<evm-void-entry>" "Tests.EvmVoidEntry" none)
  match Compiler.compileValidatedSourceV1 source with
  | .error e =>
      -- Normalize may reject Unit entry before the plan seam (no bare/implicit
      -- return for entry). That is still product fail-closed for void entry.
      expect (e.render.contains "return" || e.render.contains "Unit" ||
          e.render.contains "unsupported" || e.render.contains "PF-SRC-INVALID")
        s!"void entry compile failure must mention return/Unit/unsupported, got {e.render}"
  | .ok compiled =>
      match materializeSelected TargetId.evm compiled with
      | .error (.planInvariant .evm msg) =>
          expect (msg.contains "run" &&
              msg.contains "does not return public UInt64 or Bool")
            s!"void entry planInvariant must match makeEntryV1, got: {msg}"
      | .error e =>
          throw <| IO.userError s!"void entry must fail with planInvariant .evm, got {e.render}"
      | .ok _ =>
          throw <| IO.userError "void entry must not materialize on EVM"

/-- Two declared events emitted in one entry: pin both log topics and ABI. -/
private unsafe def testMultipleEvents : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MultiEvent where\n" ++
    "  state count : UInt64\n" ++
    "  event A(x : UInt64)\n" ++
    "  event B(x : UInt64, y : UInt64)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry go(x : UInt64) : UInt64 do\n" ++
    "    emit A(x)\n" ++
    "    emit B(count, x)\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let source ← liftResult "load MultiEvent" (← session.selectProgramV1
    text "<evm-multi-event>" "Tests.EvmMultiEvent" none)
  let compiled ← liftResult "compile MultiEvent" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan MultiEvent" <| planEvm compiled
  expect (plan.events.map (·.name) == #["A", "B"] &&
      plan.events[0]!.fieldCount == 1 &&
      plan.events[1]!.fieldCount == 2)
    "MultiEvent must carry A(1 field) then B(2 fields) in source order"
  expect (plan.entries[0]!.body == #[
      .emitEvent 0 #[.param 0],
      .emitEvent 1 #[.storageLoad 0, .param 0],
      .returnValue (.storageLoad 0)])
    "MultiEvent go must emit A then B then return count"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"MultiEvent plan must validate: {e.render}"
  let output ← liftResult "materialize MultiEvent" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "MultiEvent.yul") |
    throw <| IO.userError "MultiEvent: missing MultiEvent.yul"
  let yul := yulFile.contents
  let topicA := Targets.Evm.Keccak.keccak256Hex "A(uint64)".toUTF8
  let topicB := Targets.Evm.Keccak.keccak256Hex "B(uint64,uint64)".toUTF8
  expect (yul.contains s!"log1(0, 32, 0x{topicA})")
    "MultiEvent Yul must emit log1 for A with one word"
  expect (yul.contains s!"log1(0, 64, 0x{topicB})")
    "MultiEvent Yul must emit log1 for B with two words"
  let some abiFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "MultiEvent.abi.json") |
    throw <| IO.userError "MultiEvent: missing MultiEvent.abi.json"
  expect (abiFile.contents.contains "\"type\":\"event\",\"name\":\"A\"" &&
      abiFile.contents.contains "\"type\":\"event\",\"name\":\"B\"")
    "MultiEvent ABI must declare both events"
  -- Cross-event emission order: A's log1 must appear before B's log1 in Yul.
  let headA := (yul.splitOn s!"log1(0, 32, 0x{topicA})").head?.getD ""
  let headB := (yul.splitOn s!"log1(0, 64, 0x{topicB})").head?.getD ""
  expect (headA.length < headB.length)
    "MultiEvent Yul must emit log1 for A before log1 for B"

/-- Zero-field declared error + bare `revert E` → empty custom-error selector. -/
private unsafe def testZeroArgRevert : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ZeroRev where\n" ++
    "  state count : UInt64\n" ++
    "  error E()\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry go(x : UInt64) : UInt64 do\n" ++
    "    if x == 0 then\n" ++
    "      revert E\n" ++
    "    else\n" ++
    "      count := count + x\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let source ← liftResult "load ZeroRev" (← session.selectProgramV1
    text "<evm-zero-rev>" "Tests.EvmZeroRev" none)
  let compiled ← liftResult "compile ZeroRev" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan ZeroRev" <| planEvm compiled
  expect (plan.errors.map (·.name) == #["E"] && plan.errors[0]!.fieldCount == 0)
    "ZeroRev must carry zero-field error E"
  expect (plan.entries[0]!.body == #[
      .ifThenElse (.compare .eq (.param 0) (.literal 0))
        #[.revertError 0 #[]]
        #[.store {
          slot := 0
          value := .checkedAdd (.storageLoad 0) (.param 0)
        }],
      .returnValue (.storageLoad 0)])
    "ZeroRev go must branch to bare revertError 0 with empty args"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ZeroRev plan must validate: {e.render}"
  let output ← liftResult "materialize ZeroRev" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "ZeroRev.yul") |
    throw <| IO.userError "ZeroRev: missing ZeroRev.yul"
  let yul := yulFile.contents
  let expectedSelector := Targets.Evm.Keccak.selector "E" #[]
  expect (yul.contains expectedSelector)
    s!"ZeroRev Yul must contain empty-error selector {expectedSelector}"
  expect (yul.contains "revert(0, 4)")
    "ZeroRev Yul must revert with selector-only length 4"
  let some abiFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "ZeroRev.abi.json") |
    throw <| IO.userError "ZeroRev: missing ZeroRev.abi.json"
  expect (abiFile.contents.contains "\"type\":\"error\",\"name\":\"E\"")
    "ZeroRev ABI must declare error E"

/-- Bool-result pureFn called from a Bool entry: pin resultIsBool + Yul fn path. -/
private unsafe def testBoolResultPureFn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BoolFn where\n" ++
    "  state count : UInt64\n" ++
    "  fn flag(a : UInt64) : Bool do\n" ++
    "    return a > 0\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry check(x : UInt64) : Bool do\n" ++
    "    return flag(x)\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let source ← liftResult "load BoolFn" (← session.selectProgramV1
    text "<evm-bool-fn>" "Tests.EvmBoolFn" none)
  let compiled ← liftResult "compile BoolFn" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan BoolFn" <| planEvm compiled
  expect (plan.fns.size == 1 && plan.fns[0]!.name == "flag" &&
      plan.fns[0]!.resultIsBool)
    "BoolFn must lower flag with resultIsBool"
  expect (plan.fns[0]!.body == #[
      .returnValue (.compare .gt (.param 0) (.literal 0))])
    "flag body must return a > 0"
  expect (plan.entries[0]!.name == "check" &&
      plan.entries[0]!.resultKind == .bool &&
      plan.entries[0]!.body == #[.returnValue (.callFn 0 #[.param 0])])
    "check must return flag(x) as Bool callFn"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"BoolFn plan must validate: {e.render}"
  let output ← liftResult "materialize BoolFn" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "BoolFn.yul") |
    throw <| IO.userError "BoolFn: missing BoolFn.yul"
  let yul := yulFile.contents
  expect (yul.contains "function pf_fn0(" && yul.contains "pf_fn0(")
    "BoolFn Yul must define and call pf_fn0"
  expect (yul.contains "gt(")
    "BoolFn Yul must render the comparison inside the pureFn"
  expect (yul.contains "mstore(0," && yul.contains "return(0, 32)")
    "BoolFn entry must return the Bool word via mstore/return"
  let some abiFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "BoolFn.abi.json") |
    throw <| IO.userError "BoolFn: missing BoolFn.abi.json"
  expect (abiFile.contents.contains "\"name\":\"check\"" &&
      abiFile.contents.contains "\"type\":\"bool\"")
    "BoolFn ABI must declare check with bool outputs"

/-- Omitted-type `let x := a + b` still lowers to checkedAdd. -/
private unsafe def testOmittedTypeLet : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program LetOmit where\n" ++
    "  entry sum(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    let x := a + b\n" ++
    "    return x\n"
  let source ← liftResult "load LetOmit" (← session.selectProgramV1
    text "<evm-let-omit>" "Tests.EvmLetOmit" none)
  let compiled ← liftResult "compile LetOmit" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan LetOmit" <| planEvm compiled
  expect (plan.entries[0]!.body == #[
      .returnValue (.checkedAdd (.param 0) (.param 1))])
    "omitted-type let must lower to checkedAdd of both params"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"LetOmit plan must validate: {e.render}"
  let output ← liftResult "materialize LetOmit" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "LetOmit.yul") |
    throw <| IO.userError "LetOmit: missing LetOmit.yul"
  let yul := yulFile.contents
  expect (yul.contains "add(")
    "LetOmit Yul must render the add from the omitted-type let"

/-- Normalize admits zero-arg `assert … else`; the current EVM Plan
    explicitly fails closed on an error-bound assert. -/
private unsafe def testAssertElseRejected : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let text :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program AssertElse where\n" ++
    "  state count : UInt64\n" ++
    "  error Guard()\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry f(x : UInt64) : UInt64 do\n" ++
    "    assert x > 0 else Guard\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let source ← liftResult "load AssertElse" (← session.selectProgramV1
    text "<evm-assert-else>" "Tests.EvmAssertElse" none)
  let compiled ← liftResult "compile AssertElse" <|
    Compiler.compileValidatedSourceV1 source
  match planEvm compiled with
  | .error (.planInvariant .evm msg) =>
      expect (msg.contains "assert" && msg.contains "errorId=none")
        s!"assert-else planInvariant must pin the errorId boundary, got: {msg}"
  | .error e =>
      throw <| IO.userError s!"assert-else must fail closed at EVM Plan, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "assert-else must not produce an EVM plan"

/-- N2b-EVM: Field (bn254 Fr) state/params/results + Yul addmod/mulmod pins.
    Exact sequences: add = addmod(a,b,p); sub = addmod(a, sub(p, addmod(b,0,p)), p)
    (EVM SUB is mod 2^256 and 2^256 mod bn254-p != 0, so sub(0,b) would be wrong);
    mul = mulmod(a,b,p); div = zero-check + Fermat inv (mulmod chain) + mulmod;
    neg = addmod(0, sub(p, addmod(a,0,p)), p). Ordering / % fail closed.
    Nested-slot .fieldDiv is rejected by validateIR (marker), never a multiply.
    solc acceptance out of scope. -/
private unsafe def testFieldBn254Lane : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let p := "0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001"
  let exp := "0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593efffffff"
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program FieldLane where\n" ++
    "  state acc : Field bn254_fr\n" ++
    "  init(initial : Field bn254_fr) do\n" ++
    "    acc := initial\n" ++
    "  entry add(delta : Field bn254_fr) : Field bn254_fr do\n" ++
    "    acc := acc + delta\n" ++
    "    return acc\n" ++
    "  entry sub(delta : Field bn254_fr) : Field bn254_fr do\n" ++
    "    acc := acc - delta\n" ++
    "    return acc\n" ++
    "  entry mul(factor : Field bn254_fr) : Field bn254_fr do\n" ++
    "    acc := acc * factor\n" ++
    "    return acc\n" ++
    "  entry div(den : Field bn254_fr) : Field bn254_fr do\n" ++
    "    return acc / den\n" ++
    "  entry neg(x : Field bn254_fr) : Field bn254_fr do\n" ++
    "    return -x\n" ++
    "  entry eq(a : Field bn254_fr, b : Field bn254_fr) : Bool do\n" ++
    "    return a == b\n" ++
    "  entry ne(a : Field bn254_fr, b : Field bn254_fr) : Bool do\n" ++
    "    return a != b\n" ++
    "  view get() : Field bn254_fr do\n" ++
    "    return acc\n"
  let source ← liftResult "load FieldLane" (← session.selectProgramV1
    sourceText "<evm-field-lane>" "Tests.EvmFieldLane" none)
  let compiled ← liftResult "compile FieldLane" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan FieldLane" <| planEvm compiled
  expect (plan.objectName == "FieldLane")
    "FieldLane object name"
  expect (plan.storageLayout.size == 1 &&
      plan.storageLayout[0]!.byteWidth == 32 &&
      plan.storageLayout[0]!.name == "acc")
    "Field state is one 32-byte slot named acc"
  expect (plan.entries.any fun e => e.name == "add" && e.resultKind == .field)
    "add returns Field"
  expect (plan.entries.any fun e => e.name == "eq" && e.resultKind == .bool)
    "eq returns Bool"
  -- Constructor takes one Field ABI word.
  match plan.constructor with
  | none => throw <| IO.userError "FieldLane requires constructor"
  | some ctor =>
      expect (ctor.params.size == 1 && ctor.params[0]!.byteWidth == 32)
        "Field init param is 32-byte ABI word"
  let output ← liftResult "materialize FieldLane" <|
    materializeSelected TargetId.evm compiled
  let files := MaterializedArtifactsV1.filesOf output
  let some yulFile := files.find? (·.path == "FieldLane.yul") |
    throw <| IO.userError "missing FieldLane.yul"
  let yul := yulFile.contents
  let some abiFile := files.find? (·.path == "FieldLane.abi.json") |
    throw <| IO.userError "missing FieldLane.abi.json"
  let abi := abiFile.contents
  -- Exact modulus pin + op families.
  expect (yul.contains p) "Yul must embed bn254 Fr modulus"
  expect (yul.contains "addmod(") "Yul must emit addmod for Field add"
  expect (yul.contains "mulmod(") "Yul must emit mulmod for Field mul/div"
  expect (yul.contains exp) "Yul must embed Fermat p-2 exponent for fieldDiv"
  expect (yul.contains "if iszero(") "fieldDiv zero-divisor guard"
  expect (yul.contains "shr(1,") "Fermat inv square-and-multiply shift"
  -- Exact mod-p sub/neg shapes: (a + (p - (b mod p))) mod p and
  -- (0 + (p - (a mod p))) mod p. EVM SUB is mod 2^256, so the old
  -- sub(0, ...) form was NOT mod-p subtraction — pin the corrected shape
  -- (p is the embedded hex modulus literal).
  expect (yul.contains ("sub(" ++ p ++ ", addmod("))
    "Field sub/neg must use sub(p, addmod(..., 0, p)) (mod-p subtraction)"
  expect (yul.contains ("addmod(0, sub(" ++ p ++ ", addmod("))
    "Field neg must use addmod(0, sub(p, addmod(..., 0, p)), p)"
  expect (!yul.contains "sub(0, expr" && !yul.contains "addmod(0, sub(0,")
    "no mod-2^256 sub(0, ...) shape may appear for Field ops"
  -- Nested-slot fieldDiv marker must never appear in shipped Yul.
  expect (!yul.contains "pf_unsupported_nested_field_div")
    "valid EVM Yul must not contain the nested fieldDiv marker"
  -- fieldStorageLoad: bare sload (no UInt64 range gate on Field loads).
  expect (yul.contains "sload(0)") "Field state load via sload(0)"
  -- ABI: Field params/results as uint256.
  expect (abi.contains "\"type\":\"uint256\"") "Field ABI uses uint256"
  expect (abi.contains "\"name\":\"add\"" && abi.contains "\"name\":\"div\"")
    "FieldLane ABI lists add/div"
  -- Ordering fail closed.
  let ordSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program FieldOrd where\n" ++
    "  state a : Field bn254_fr\n" ++
    "  init(x : Field bn254_fr) do\n" ++
    "    a := x\n" ++
    "  entry lt(x : Field bn254_fr, y : Field bn254_fr) : Bool do\n" ++
    "    return x < y\n" ++
    "  view get() : Field bn254_fr do\n" ++
    "    return a\n"
  let ordSrc ← liftResult "load FieldOrd" (← session.selectProgramV1
    ordSource "<evm-field-ord>" "Tests.EvmFieldOrd" none)
  match Compiler.compileValidatedSourceV1 ordSrc with
  | .error e =>
      -- Normalize/typed may reject Field ordering before Plan.
      expect (e.render.contains "Field" || e.render.contains "unsupported" ||
          e.render.contains "order" || e.render.contains "comparison" ||
          e.render.contains "PF-")
        s!"Field ordering compile must fail closed, got {e.render}"
  | .ok ordCompiled =>
      match planEvm ordCompiled with
      | .error e =>
          expect (e.render.contains "Field" || e.render.contains "ordering" ||
              e.render.contains "unsupported" || e.render.contains "==")
            s!"Field ordering plan must fail closed, got {e.render}"
      | .ok _ =>
          throw <| IO.userError "Field ordering must not produce an EVM plan"
  -- Mod (%) fail closed.
  let modSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program FieldMod where\n" ++
    "  state a : Field bn254_fr\n" ++
    "  init(x : Field bn254_fr) do\n" ++
    "    a := x\n" ++
    "  entry rem(x : Field bn254_fr, y : Field bn254_fr) : Field bn254_fr do\n" ++
    "    return x % y\n" ++
    "  view get() : Field bn254_fr do\n" ++
    "    return a\n"
  let modSrc ← liftResult "load FieldMod" (← session.selectProgramV1
    modSource "<evm-field-mod>" "Tests.EvmFieldMod" none)
  match Compiler.compileValidatedSourceV1 modSrc with
  | .error e =>
      expect (e.render.contains "Field" || e.render.contains "mod" ||
          e.render.contains "unsupported" || e.render.contains "PF-")
        s!"Field mod compile must fail closed, got {e.render}"
  | .ok modCompiled =>
      match planEvm modCompiled with
      | .error e =>
          expect (e.render.contains "Field" || e.render.contains "mod" ||
              e.render.contains "remainder" || e.render.contains "unsupported")
            s!"Field mod plan must fail closed, got {e.render}"
      | .ok _ =>
          throw <| IO.userError "Field mod must not produce an EVM plan"

/-- EvmIndex: Array UInt64 state with literal IndexGet/IndexSet + product Yul.
    Pins storage layout, literal rebind stores, and runtime-index Yul
    (`if iszero(lt(...)) { revert }` + `add(base,idx)` + `sload`). Map state
    is separately admitted by the I1 dense pilot (see MapBox pin below and
    `Tests.Product.TokenV1` for full mint/transfer). -/
private unsafe def testArrayStateIndexOps : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- Literal-index ArrayBox (product path).
  let literalSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrayBox where\n" ++
    "  state slots : Array UInt64 2\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n" ++
    "  view get0() : UInt64 do\n" ++
    "    return slots[0]\n" ++
    "  entry set1(v : UInt64) : UInt64 do\n" ++
    "    slots[1] := v\n" ++
    "    return slots[1]\n"
  let litSrc ← liftResult "load ArrayBox" (← session.selectProgramV1
    literalSource "<evm-array-box>" "Tests.EvmArrayBox" none)
  let litCompiled ← liftResult "compile ArrayBox" <|
    Compiler.compileValidatedSourceV1 litSrc
  let litPlan ← liftResult "plan ArrayBox" <| planEvm litCompiled
  expect (litPlan.storageLayout.size == 2)
    s!"ArrayBox must flatten to 2 slots, got {litPlan.storageLayout.size}"
  expect (litPlan.storageLayout[0]!.name == "slots_0" &&
      litPlan.storageLayout[0]!.slot == 0 &&
      litPlan.storageLayout[0]!.byteWidth == 8)
    "ArrayBox slots_0 must occupy storage slot 0 (8-byte UInt64)"
  expect (litPlan.storageLayout[1]!.name == "slots_1" &&
      litPlan.storageLayout[1]!.slot == 1 &&
      litPlan.storageLayout[1]!.byteWidth == 8)
    "ArrayBox slots_1 must occupy storage slot 1 (8-byte UInt64)"
  expect (litPlan.entries.map (·.name) == #["set0", "get0", "set1"])
    "ArrayBox entry order"
  -- set0: IndexSet literal 0 → atomic multi-leaf store (leaf 0 = param,
  -- leaf 1 keeps sload(1)); single StateStore must not expand to sequential
  -- stores that re-sload mid-batch.
  let set0 := litPlan.entries[0]!
  expect (set0.body.size >= 2)
    "set0 must store then return"
  match set0.body[0]? with
  | some stmt =>
      match stmt with
      | Targets.Evm.Statement.storeAtomic ops =>
          expect (ops.size == 2)
            s!"set0 storeAtomic must write 2 leaves, got {ops.size}"
          expect (ops[0]!.slot == 0 && ops[0]!.byteWidth == 8)
            "set0 first leaf targets slot 0"
          expect (ops[1]!.slot == 1 && ops[1]!.byteWidth == 8)
            "set0 second leaf targets slot 1"
      | Targets.Evm.Statement.store s =>
          -- Single-leaf only path; Array 2 must be atomic.
          throw <| IO.userError
            s!"set0 body[0] must be storeAtomic for 2-leaf Array, got scalar store slot={s.slot}"
      | _ => throw <| IO.userError "set0 body[0] must be storeAtomic"
  | none => throw <| IO.userError "set0 body[0] missing"
  -- get0 returns storageLoad of leaf 0 (literal IndexGet).
  expect (litPlan.entries[1]!.body == #[.returnValue (.storageLoad 0)])
    "get0 must return sload(0) via literal IndexGet"
  match Targets.Evm.validatePlan litPlan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ArrayBox plan must validate: {e.render}"
  let litOut ← liftResult "materialize ArrayBox" <|
    materializeSelected TargetId.evm litCompiled
  let some litYul := (MaterializedArtifactsV1.filesOf litOut).find?
      (·.path == "ArrayBox.yul") |
    throw <| IO.userError "ArrayBox: missing ArrayBox.yul"
  expect (litYul.contents.contains "sstore(0," && litYul.contents.contains "sload(0)")
    "ArrayBox Yul must sstore/sload slot 0 for set0/get0"
  expect (litYul.contents.contains "sstore(1," || litYul.contents.contains "sload(1)")
    "ArrayBox Yul must touch slot 1 for the second leaf"
  let litPlan2 ← liftResult "plan ArrayBox again" <| planEvm litCompiled
  expect (litPlan == litPlan2) "ArrayBox plan rebuild must be deterministic"

  -- Runtime-index product path: IndexGet/IndexSet with a UInt32 param index
  -- (wire Array index type is UInt32).
  let runtimeSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrayIdx where\n" ++
    "  state slots : Array UInt64 3\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n" ++
    "    slots[2] := 0\n" ++
    "  entry getAt(i : UInt32) : UInt64 do\n" ++
    "    return slots[i]\n" ++
    "  entry setAt(i : UInt32, v : UInt64) : UInt64 do\n" ++
    "    slots[i] := v\n" ++
    "    return slots[i]\n"
  let rtSrc ← liftResult "load ArrayIdx" (← session.selectProgramV1
    runtimeSource "<evm-array-idx>" "Tests.EvmArrayIdx" none)
  let rtCompiled ← liftResult "compile ArrayIdx" <|
    Compiler.compileValidatedSourceV1 rtSrc
  let rtPlan ← liftResult "plan ArrayIdx" <| planEvm rtCompiled
  expect (rtPlan.storageLayout.size == 3)
    s!"ArrayIdx must flatten to 3 slots, got {rtPlan.storageLayout.size}"
  -- getAt body must use indexedStorageLoad (runtime IndexGet on contiguous storage).
  let getAt := rtPlan.entries[0]!
  let hasIndexed :=
    match getAt.body[0]? with
    | some stmt =>
        match stmt with
        | .returnValue (.indexedStorageLoad base len _idx bw) =>
            base == 0 && len == 3 && bw == 8
        | _ => false
    | none => false
  expect hasIndexed
    "getAt must lower to indexedStorageLoad base=0 length=3 byteWidth=8"
  match Targets.Evm.validatePlan rtPlan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ArrayIdx plan must validate: {e.render}"
  let rtOut ← liftResult "materialize ArrayIdx" <|
    materializeSelected TargetId.evm rtCompiled
  let some rtYul := (MaterializedArtifactsV1.filesOf rtOut).find?
      (·.path == "ArrayIdx.yul") |
    throw <| IO.userError "ArrayIdx: missing ArrayIdx.yul"
  expect (rtYul.contents.contains "if iszero(lt(" &&
      rtYul.contents.contains "revert(0, 0)" &&
      rtYul.contents.contains "add(0," &&
      rtYul.contents.contains "sload(")
    "ArrayIdx Yul must pin bounds guard + add(base,idx) + sload"
  -- setAt must bounds-check (boundsCheckedIndex or indexed path) and sstore leaves.
  expect (rtYul.contents.contains "sstore(")
    "ArrayIdx setAt Yul must sstore array leaves"

  -- Hand-built OOB plan negative: indexedStorageLoad with length beyond layout.
  let badOob : Targets.Evm.Plan := {
    objectName := "BadOob"
    runtimeObjectName := "__proof_forge_runtime"
    storageLayout := #[
      { sourceId := 0, name := "a0", slot := 0 },
      { sourceId := 1, name := "a1", slot := 1 }
    ]
    events := #[]
    errors := #[]
    constructor := none
    entries := #[{
      name := "get"
      selector := Targets.Evm.Keccak.selector "get" #["uint64"]
      params := #[{ sourceId := 0, name := "i", wordIndex := 0 }]
      mutability := .view
      body := #[.returnValue
        (.indexedStorageLoad 0 4 (.param 0) 8)]  -- length 4 > 2 slots
      resultKind := .uint64
    }]
    fns := #[]
  }
  match Targets.Evm.validatePlan badOob with
  | .ok () => throw <| IO.userError "validatePlan must reject OOR indexedStorageLoad range"
  | .error _ => pure ()

  -- I1 Map pilot: empty Map UInt64 UInt64 state is admitted on EVM (dense
  -- capacity-8 occ/key/val leaves). IndexGet/Set covered by Token/MapMini.
  let mapSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapBox where\n" ++
    "  state m : Map UInt64 UInt64\n" ++
    "  state dummy : UInt64\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "    dummy := 0\n" ++
    "  view get() : UInt64 do\n" ++
    "    return dummy\n"
  let mapSrc ← liftResult "load MapBox" (← session.selectProgramV1
    mapSource "<evm-map-box>" "Tests.EvmMapBox" none)
  let mapCompiled ← liftResult "compile MapBox" <|
    Compiler.compileValidatedSourceV1 mapSrc
  match planEvm mapCompiled with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError s!"EVM must accept Map state (I1), got {e.render}"

/-- Dense Map put-into-empty: single aggregate StateStore must two-phase
    evaluate all leaf Expr (sload snapshot) before any sstore of that batch.
    Sequential per-leaf store re-sloads sibling occ after writing it, flipping
    insertHere and dropping the key/val write (store-then-read hazard). -/
private unsafe def testMapPutIntoEmptyAtomicStore : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapPut where\n" ++
    "  state m : Map UInt64 UInt64\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    m[k] := v\n" ++
    "    match m[k] with\n" ++
    "    | Option.some(x) => do\n" ++
    "      return x\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let src ← liftResult "load MapPut" (← session.selectProgramV1
    source "<evm-map-put>" "Tests.EvmMapPut" none)
  let compiled ← liftResult "compile MapPut" <|
    Compiler.compileValidatedSourceV1 src
  let plan ← liftResult "plan MapPut" <| planEvm compiled
  -- Dense pilot: 8 entries × 3 leaves = 24 storage slots for Map only.
  expect (plan.storageLayout.size == 24)
    s!"MapPut must flatten to 24 Map leaves, got {plan.storageLayout.size}"
  expect (plan.entries.size == 1 && plan.entries[0]!.name == "put")
    "MapPut must have single put entry"
  let putBody := plan.entries[0]!.body
  -- First statement is the IndexSet→StateStore of the full Map aggregate.
  match putBody[0]? with
  | none => throw <| IO.userError "Map put body empty"
  | some stmt =>
      match stmt with
      | Targets.Evm.Statement.storeAtomic ops =>
          expect (ops.size == 24)
            s!"Map put StateStore must be one storeAtomic of 24 leaves, got {ops.size}"
          for i in [0:ops.size] do
            expect (ops[i]!.slot == i && ops[i]!.byteWidth == 8)
              s!"Map put leaf {i} must target slot {i} width 8"
      | Targets.Evm.Statement.store _ =>
          throw <| IO.userError
            "Map put must not lower to sequential scalar stores (store-then-read hazard)"
      | _ =>
          throw <| IO.userError "Map put body[0] must be storeAtomic"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"MapPut plan must validate: {e.render}"
  let out ← liftResult "materialize MapPut" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf out).find?
      (·.path == "MapPut.yul") |
    throw <| IO.userError "MapPut: missing MapPut.yul"
  let yul := yulFile.contents
  -- Scope to put case only (constructor also has 24 Map sstores).
  let putSel := plan.entries[0]!.selector
  let caseMarker := s!"case 0x{putSel}"
  expect (yul.contains caseMarker)
    s!"MapPut Yul must contain put case 0x{putSel}"
  -- Char-list slice after put case marker through end of runtime object.
  let rec indexOf (hay needle : List Char) (i : Nat) : Option Nat :=
    match hay with
    | [] => none
    | _ :: rest =>
        if needle.isPrefixOf hay then some i else indexOf rest needle (i + 1)
  let yulCs := yul.toList
  let some caseAt := indexOf yulCs caseMarker.toList 0 |
    throw <| IO.userError "MapPut: put case marker not found"
  let putRegion := String.ofList (yulCs.drop caseAt)
  -- B-EVM-MAP-STACK + B-MAP-STRUCT-PIN: compute/spill phase (nested blocks +
  -- mstore to reserved high spill 0x10000+32*i) completes before any sstore;
  -- write phase is a contiguous 24-sstore run with no mid-batch sload.
  let some firstSstore := indexOf putRegion.toList "sstore(".toList 0 |
    throw <| IO.userError "MapPut put case must contain sstore"
  let beforeSstore := String.ofList (putRegion.toList.take firstSstore)
  expect (beforeSstore.contains "sload(")
    "Map put leaf evaluation must sload the empty table before first sstore"
  expect (!beforeSstore.contains "sstore(")
    "Map put compute/spill phase must contain no sstore before the write batch"
  -- Exactly 24 spill mstores at fixed high base (0x10000 + 32*i).
  let mut spillCount := 0
  for i in [0:24] do
    let addr := 0x10000 + 32 * i
    let needle := s!"mstore({addr},"
    expect (beforeSstore.contains needle)
      s!"Map put spill phase must mstore leaf {i} at {addr} before first sstore"
    spillCount := spillCount + 1
  expect (spillCount == 24) "Map put must spill all 24 leaves before sstore"
  -- Nested compute blocks: each leaf ends with its spill mstore then `}`.
  expect (beforeSstore.contains "{\n" || beforeSstore.contains "{")
    "Map put leaf compute must use nested Yul blocks for stack release"
  let mut pos := firstSstore
  let mut count := 0
  let putCs := putRegion.toList
  while count < 24 do
    let tail := putCs.drop pos
    match indexOf tail "sstore(".toList 0 with
    | none =>
        throw <| IO.userError
          s!"MapPut put case expected 24 sstores in write batch, found {count}"
    | some rel =>
        let sPos := pos + rel
        if count > 0 then
          let between := String.ofList ((putCs.drop pos).take rel)
          expect (!between.contains "sload(")
            s!"Map put atomic batch must not sload between sstore {count} and next (store-then-read)"
          expect (!between.contains "mstore(")
            s!"Map put write batch must not mstore between sstore {count} and next"
        -- Write phase reloads spilled words (mload of high spill addr).
        let sstoreSlice := String.ofList ((putCs.drop sPos).take 80)
        expect (sstoreSlice.contains "mload(")
          s!"Map put sstore {count} must mload spilled leaf value"
        count := count + 1
        pos := sPos + "sstore(".length
  expect (count == 24) "Map put write batch must be exactly 24 sstores"
  -- Dual StateStore still separate: init Map.empty is its own atomic batch.
  match plan.constructor with
  | none => throw <| IO.userError "MapPut must have constructor"
  | some ctor =>
      if ctor.body.isEmpty then
        throw <| IO.userError
          "Map.empty constructor must retain body with storeAtomic (not scalar store-only flatten)"
      else
        let hasAtomic :=
          ctor.body.any fun s =>
            match s with
            | Targets.Evm.Statement.storeAtomic ops => ops.size == 24
            | _ => false
        expect hasAtomic
          "Map.empty init must lower to storeAtomic of 24 zero leaves"
  IO.println "  MapPut atomic store-then-read pin ok"

/-- B-MAP-STRUCT-PIN: Token transfer dual Map StateStores must stay two
    separate 24-leaf `storeAtomic` batches (not merged). Within each batch Yul
    evaluates leaf exprs then contiguous sstores; between batches sload is
    allowed so the second StateStore observes the first write. -/
private unsafe def testTokenDualStoreBatchSeparation : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Token where\n" ++
    "  state balances : Map UInt64 UInt64\n" ++
    "  state supply : UInt64\n" ++
    "  init() do\n" ++
    "    balances := Map.empty()\n" ++
    "    supply := 0\n" ++
    "  entry mint(to : UInt64, amount : UInt64) : UInt64 do\n" ++
    "    match balances[to] with\n" ++
    "    | Option.some(v) => do\n" ++
    "      balances[to] := v + amount\n" ++
    "      supply := supply + amount\n" ++
    "      return supply\n" ++
    "    | _ => do\n" ++
    "      balances[to] := amount\n" ++
    "      supply := supply + amount\n" ++
    "      return supply\n" ++
    "  entry transfer(src : UInt64, dst : UInt64, amount : UInt64) : Bool do\n" ++
    "    match balances[src] with\n" ++
    "    | Option.some(fromBal) => do\n" ++
    "      assert fromBal >= amount\n" ++
    "      match balances[dst] with\n" ++
    "      | Option.some(toBal) => do\n" ++
    "        balances[src] := fromBal - amount\n" ++
    "        balances[dst] := toBal + amount\n" ++
    "        return true\n" ++
    "      | _ => do\n" ++
    "        balances[src] := fromBal - amount\n" ++
    "        balances[dst] := amount\n" ++
    "        return true\n" ++
    "    | _ => do\n" ++
    "      assert false\n" ++
    "      return false\n" ++
    "  view balanceOf(who : UInt64) : UInt64 do\n" ++
    "    match balances[who] with\n" ++
    "    | Option.some(v) => do\n" ++
    "      return v\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let src ← liftResult "load Token dual" (← session.selectProgramV1
    source "<evm-token-dual>" "Tests.EvmTokenDual" none)
  let compiled ← liftResult "compile Token dual" <|
    Compiler.compileValidatedSourceV1 src
  let plan ← liftResult "plan Token dual" <| planEvm compiled
  -- 24 Map leaves + supply scalar.
  expect (plan.storageLayout.size == 25)
    s!"Token dual: Map+supply must be 25 slots, got {plan.storageLayout.size}"
  let some transfer := plan.entries.find? (·.name == "transfer") |
    throw <| IO.userError "Token dual: missing transfer entry"
  -- Recursive count of 24-leaf storeAtomic vs scalar store.
  let rec countAtomic (stmts : Array Targets.Evm.Statement) : Nat × Nat :=
    stmts.foldl (fun (a24, seq) stmt =>
      match stmt with
      | Targets.Evm.Statement.storeAtomic ops =>
          (a24 + (if ops.size == 24 then 1 else 0), seq)
      | Targets.Evm.Statement.store _ =>
          (a24, seq + 1)
      | Targets.Evm.Statement.ifThenElse _ t e =>
          let (a1, s1) := countAtomic t
          let (a2, s2) := countAtomic e
          (a24 + a1 + a2, seq + s1 + s2)
      | Targets.Evm.Statement.switchOn _ cases d =>
          let (ad, sd) := countAtomic d
          let (ac, sc) := cases.foldl (fun (a, s) (_, b) =>
            let (ab, sb) := countAtomic b
            (a + ab, s + sb)) (0, 0)
          (a24 + ad + ac, seq + sd + sc)
      | Targets.Evm.Statement.forLoop _ _ _ _ _ _ b =>
          let (ab, sb) := countAtomic b
          (a24 + ab, seq + sb)
      | _ => (a24, seq)) (0, 0)
  let (agg24, _) := countAtomic transfer.body
  -- Dual-write arms (some/some and some/none) each keep two storeAtomic(24).
  expect (agg24 >= 4)
    s!"Token transfer Plan must keep ≥4 separate 24-leaf storeAtomic (dual StateStores × arms), got {agg24}"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"Token dual plan must validate: {e.render}"
  let out ← liftResult "materialize Token dual" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf out).find?
      (·.path == "Token.yul") |
    throw <| IO.userError "Token dual: missing Token.yul"
  let yul := yulFile.contents
  let caseMarker := s!"case 0x{transfer.selector}"
  expect (yul.contains caseMarker)
    s!"Token dual Yul must contain transfer case 0x{transfer.selector}"
  let rec indexOf (hay needle : List Char) (i : Nat) : Option Nat :=
    match hay with
    | [] => none
    | _ :: rest =>
        if needle.isPrefixOf hay then some i else indexOf rest needle (i + 1)
  let some caseAt := indexOf yul.toList caseMarker.toList 0 |
    throw <| IO.userError "Token dual: transfer case marker not found"
  let transferRegion := String.ofList (yul.toList.drop caseAt)
  -- Collect every sstore( position in the transfer case.
  let rec collectSstores (hay : List Char) (base : Nat) (acc : Array Nat) : Array Nat :=
    match indexOf hay "sstore(".toList 0 with
    | none => acc
    | some rel =>
        let pos := base + rel
        collectSstores (hay.drop (rel + "sstore(".length)) (pos + "sstore(".length)
          (acc.push pos)
  let sstorePoses := collectSstores transferRegion.toList 0 #[]
  -- Dual-write path emits 2 × 24 = 48 sstores per arm; both arms are present
  -- in the lowered switch, so expect ≥ 48 (often 96 for two full dual arms).
  expect (sstorePoses.size >= 48)
    s!"Token transfer Yul must emit ≥48 Map sstores (dual 24-leaf batches), got {sstorePoses.size}"
  -- B-EVM-MAP-STACK: every write-batch sstore reloads from the fixed spill
  -- region (0x10000+); compute/spill mstores precede the first sstore of
  -- each contiguous 24-leaf batch.
  expect (transferRegion.contains "mstore(65536," || transferRegion.contains "mstore(0x10000,")
    "Token transfer Yul must spill leaf 0 to reserved base 0x10000 (65536)"
  expect (transferRegion.contains "mload(65536)" || transferRegion.contains "mload(0x10000)")
    "Token transfer Yul write phase must mload spill base for sstore"
  -- Find at least one contiguous 24-sstore run with no sload between members
  -- (intra-batch atomic write), and ensure a later batch is separated by sload
  -- (cross-batch re-read, not merged).
  let mut foundAtomic24 := false
  let mut foundSeparatedBatches := false
  let mut foundSpillBeforeBatch := false
  let trCs := transferRegion.toList
  let mut bi := 0
  while bi + 24 ≤ sstorePoses.size do
    let mut contiguous := true
    let mut j := 1
    while j < 24 && contiguous do
      let prev := sstorePoses[bi + j - 1]!
      let cur := sstorePoses[bi + j]!
      let between := String.ofList ((trCs.drop (prev + "sstore(".length)).take
        (cur - (prev + "sstore(".length)))
      if between.contains "sload(" then
        contiguous := false
      j := j + 1
    if contiguous then
      foundAtomic24 := true
      -- Spill mstores for this batch must sit after the previous sstore (if
      -- any) and before this batch's first sstore — compute phase has no sstore.
      let batchStart := sstorePoses[bi]!
      let preStart := if bi == 0 then 0 else sstorePoses[bi - 1]! + "sstore(".length
      let preBatch := String.ofList ((trCs.drop preStart).take (batchStart - preStart))
      if preBatch.contains "mstore(65536," || preBatch.contains "mstore(0x10000," then
        if !preBatch.contains "sstore(" then
          foundSpillBeforeBatch := true
      -- Look for a later sstore after this batch that has sload in between
      -- (second StateStore batch re-reads storage).
      if bi + 24 < sstorePoses.size then
        let batchEnd := sstorePoses[bi + 23]!
        let nextStore := sstorePoses[bi + 24]!
        let gap := String.ofList ((trCs.drop (batchEnd + "sstore(".length)).take
          (nextStore - (batchEnd + "sstore(".length)))
        if gap.contains "sload(" then
          foundSeparatedBatches := true
    bi := bi + 1
  expect foundAtomic24
    "Token transfer Yul must contain a contiguous 24-sstore atomic write batch (no mid-batch sload)"
  expect foundSeparatedBatches
    "Token transfer Yul dual StateStores must re-sload between consecutive 24-sstore batches (not merge)"
  expect foundSpillBeforeBatch
    "Token transfer Yul each atomic batch must spill (mstore high region) before its sstore run"
  -- mint: Map storeAtomic + scalar supply store stay distinct statement kinds.
  let some mint := plan.entries.find? (·.name == "mint") |
    throw <| IO.userError "Token dual: missing mint entry"
  let (mintAgg, mintSeq) := countAtomic mint.body
  expect (mintAgg >= 2)
    s!"Token mint Plan must have ≥2 Map storeAtomic (match arms), got {mintAgg}"
  expect (mintSeq >= 2)
    s!"Token mint Plan must keep scalar supply .store separate from Map aggregate, got seq={mintSeq}"
  IO.println "  Token dual StateStore batch separation pin ok"

/-- D4-E2: Bytes N state flattens to N×UInt8 leaves with IndexGet/IndexSet
    (Normalize-admitted; Map is I1 dense pilot, not Bytes). -/
private unsafe def testBytesStateIndexOps : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ByteBox where\n" ++
    "  state data : Bytes 2\n" ++
    "  init() do\n" ++
    "    data[0] := 0\n" ++
    "    data[1] := 0\n" ++
    "  entry set0(v : UInt8) : UInt8 do\n" ++
    "    data[0] := v\n" ++
    "    return data[0]\n" ++
    "  view get1() : UInt8 do\n" ++
    "    return data[1]\n"
  let src ← liftResult "load ByteBox" (← session.selectProgramV1
    source "<evm-byte-box>" "Tests.EvmByteBox" none)
  let compiled ← liftResult "compile ByteBox" <|
    Compiler.compileValidatedSourceV1 src
  let plan ← liftResult "plan ByteBox" <| planEvm compiled
  expect (plan.storageLayout.size == 2)
    s!"ByteBox must flatten to 2 UInt8 slots, got {plan.storageLayout.size}"
  expect (plan.storageLayout.any fun b =>
      b.name == "data_0" && b.slot == 0 && b.byteWidth == 1)
    "ByteBox data_0 must be slot 0 with 1-byte width"
  expect (plan.storageLayout.any fun b =>
      b.name == "data_1" && b.slot == 1 && b.byteWidth == 1)
    "ByteBox data_1 must be slot 1 with 1-byte width"
  expect (plan.entries.any fun e => e.name == "set0")
    "ByteBox must have set0 entry"
  expect (plan.entries.any fun e => e.name == "get1")
    "ByteBox must have get1 view"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ByteBox plan must validate: {e.render}"
  let out ← liftResult "materialize ByteBox" <|
    materializeSelected TargetId.evm compiled
  let yul ← match (MaterializedArtifactsV1.filesOf out).find?
      (·.path == "ByteBox.yul") with
    | some f => pure f.contents
    | none => throw <| IO.userError "ByteBox: missing ByteBox.yul"
  expect (yul.contains "sstore" && yul.contains "sload")
    "ByteBox Yul must sstore/sload Bytes leaves"
  -- Map remains admitted after Bytes path (orthogonal I1 pilot).
  let mapSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapStillOpen where\n" ++
    "  state m : Map UInt64 UInt64\n" ++
    "  state d : UInt64\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "    d := 0\n" ++
    "  view get() : UInt64 do\n" ++
    "    return d\n"
  let mapSrc ← liftResult "load MapStillOpen" (← session.selectProgramV1
    mapSource "<evm-map-still>" "Tests.EvmMapStill" none)
  let mapCompiled ← liftResult "compile MapStillOpen" <|
    Compiler.compileValidatedSourceV1 mapSrc
  match planEvm mapCompiled with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError s!"EVM must accept Map after I1, got {e.render}"

/-- EVM ContextRead research-pin: both admitted closed wire keys
    (`context.unixTimeSeconds` → UInt64, `context.caller` → Principal) reach
    the EVM Plan layer from Normalize (init/entry/view) and MUST fail closed
    with an explicit ContextRead boundary — never a silent TIMESTAMP/CALLER
    opcode mapping. `unix-time-seconds` is deferred (PlanSchema frozen); the
    caller key is pinned fail-closed by the B-3 PrincipalAddr boundary. -/
private unsafe def testContextReadFailClosedBoundary : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- unix-time-seconds → UInt64 result.
  let timeSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CtxTime where\n" ++
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry now() : UInt64 do\n" ++
    "    return context.unixTimeSeconds\n" ++
    "  view get() : UInt64 do\n" ++
    "    return pad\n"
  let timeSrc ← liftResult "load CtxTime" (← session.selectProgramV1
    timeSource "<evm-ctx-time>" "Tests.EvmCtxTime" none)
  let timeCompiled ← liftResult "compile CtxTime" <|
    Compiler.compileValidatedSourceV1 timeSrc
  match planEvm timeCompiled with
  | .error (.planInvariant .evm msg) =>
      expect (msg.contains "ContextRead" && msg.contains "unix-time-seconds")
        s!"EVM unix-time ContextRead must cite the ContextRead/unix-time boundary, got: {msg}"
  | .error e =>
      throw <| IO.userError s!"EVM unix-time ContextRead must fail closed at plan, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "EVM unix-time ContextRead must not produce a plan"
  -- context.caller → Principal result (B-3 PrincipalAddr pin).
  let callerSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CtxCaller where\n" ++
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry who(a : Principal) : Bool do\n" ++
    "    return context.caller == a\n" ++
    "  view get() : UInt64 do\n" ++
    "    return pad\n"
  let callerSrc ← liftResult "load CtxCaller" (← session.selectProgramV1
    callerSource "<evm-ctx-caller>" "Tests.EvmCtxCaller" none)
  let callerCompiled ← liftResult "compile CtxCaller" <|
    Compiler.compileValidatedSourceV1 callerSrc
  match planEvm callerCompiled with
  | .error (.planInvariant .evm msg) =>
      expect (msg.contains "ContextRead" && msg.contains "caller")
        s!"EVM caller ContextRead must cite the ContextRead/caller boundary, got: {msg}"
  | .error e =>
      throw <| IO.userError s!"EVM caller ContextRead must fail closed at plan, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "EVM caller ContextRead must not produce a plan"
  -- Unknown context key stays fail-closed too (closed wire surface).
  let unknownSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CtxBad where\n" ++
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry bad() : UInt64 do\n" ++
    "    return context.nonexistent\n" ++
    "  view get() : UInt64 do\n" ++
    "    return pad\n"
  let badSrc ← liftResult "load CtxBad" (← session.selectProgramV1
    unknownSource "<evm-ctx-bad>" "Tests.EvmCtxBad" none)
  match Compiler.compileValidatedSourceV1 badSrc with
  | .error _ => pure ()  -- Normalize rejects the unknown context field first.
  | .ok badCompiled =>
      match planEvm badCompiled with
      | .error _ => pure ()
      | .ok _ =>
          throw <| IO.userError "EVM unknown-context must not produce a plan"

/-- B-RET-ABI: named Struct entry/view return lowers to `.returnAggregate`
with preorder leaves and emits a Solidity tuple ABI. -/
private unsafe def testAggregateStructReturn : IO Unit := do
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PairBox where\n" ++
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  state p : Pair\n" ++
    "  init(x : UInt64, y : UInt64) do\n" ++
    "    p := Pair.new(x, y)\n" ++
    "  view getPair() : Pair do\n" ++
    "    return p\n"
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load PairBox" (← session.selectProgramV1
    sourceText "<evm-aggregate-ret>" "Tests.EvmAggregateRet" none)
  let compiled ← liftResult "compile PairBox" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan PairBox" <| planEvm compiled
  expect (plan.entries.size == 1) "PairBox must have one entry"
  let viewEntry := plan.entries[0]!
  expect (viewEntry.name == "getPair") "PairBox entry name"
  match viewEntry.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"PairBox aggregate return must have 2 leaves, got {leaves.size}"
      expect (!leaves[0]!.isInt && !leaves[1]!.isInt)
        "PairBox aggregate leaves must be uint64"
  | _ =>
      throw <| IO.userError
        s!"PairBox getPair resultKind must be .aggregate, got {repr viewEntry.resultKind}"
  expect (viewEntry.body.size == 1) "PairBox getPair body must be one return statement"
  match viewEntry.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2)
        s!"returnAggregate must have 2 leaves, got {leaves.size}"
      expect (leafIsInt == #[false, false])
        "returnAggregate leafIsInt must be #[false, false]"
  | _ =>
      throw <| IO.userError "PairBox getPair body must be .returnAggregate"
  -- Materialize to check Yul + ABI.
  let output ← liftResult "materialize PairBox" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "PairBox.yul") |
    throw <| IO.userError "PairBox: missing PairBox.yul"
  let yul := yulFile.contents
  expect (yul.contains "mstore(0, ") "PairBox Yul must mstore leaf 0"
  expect (yul.contains "mstore(32, ") "PairBox Yul must mstore leaf 1"
  expect (yul.contains "return(0, 64)") "PairBox Yul must return 64 bytes"
  let some abiFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "PairBox.abi.json") |
    throw <| IO.userError "PairBox: missing PairBox.abi.json"
  let abi := abiFile.contents
  expect (abi.contains "(uint64,uint64)")
    s!"PairBox ABI must declare tuple (uint64,uint64), got: {abi}"
  expect (abi.contains "components")
    "PairBox ABI must have components for tuple"

/-- BL-18: anonymous `Array UInt64 2` entry/view return lowers to
`.returnAggregate` with 2 UInt64 leaves (tuple ABI), same path as named. -/
private unsafe def testAnonymousArrayUInt64Return : IO Unit := do
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrayRet where\n" ++
    "  state slots : Array UInt64 2\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n" ++
    "  view getArr() : Array UInt64 2 do\n" ++
    "    return slots\n"
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load ArrayRet" (← session.selectProgramV1
    sourceText "<evm-array-ret>" "Tests.EvmArrayRet" none)
  let compiled ← liftResult "compile ArrayRet" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan ArrayRet" <| planEvm compiled
  expect (plan.entries.size == 1) "ArrayRet must have one entry"
  let viewEntry := plan.entries[0]!
  expect (viewEntry.name == "getArr") "ArrayRet entry name"
  match viewEntry.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"ArrayRet aggregate return must have 2 leaves, got {leaves.size}"
      expect (!leaves[0]!.isInt && !leaves[1]!.isInt)
        "ArrayRet aggregate leaves must be uint64"
  | _ =>
      throw <| IO.userError
        s!"ArrayRet getArr resultKind must be .aggregate, got {repr viewEntry.resultKind}"
  expect (viewEntry.body.size == 1) "ArrayRet getArr body must be one return statement"
  match viewEntry.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2)
        s!"returnAggregate must have 2 leaves, got {leaves.size}"
      expect (leafIsInt == #[false, false])
        "returnAggregate leafIsInt must be #[false, false]"
  | _ =>
      throw <| IO.userError "ArrayRet getArr body must be .returnAggregate"
  let output ← liftResult "materialize ArrayRet" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "ArrayRet.yul") |
    throw <| IO.userError "ArrayRet: missing ArrayRet.yul"
  let yul := yulFile.contents
  expect (yul.contains "mstore(0, ") "ArrayRet Yul must mstore leaf 0"
  expect (yul.contains "mstore(32, ") "ArrayRet Yul must mstore leaf 1"
  expect (yul.contains "return(0, 64)") "ArrayRet Yul must return 64 bytes"
  let some abiFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "ArrayRet.abi.json") |
    throw <| IO.userError "ArrayRet: missing ArrayRet.abi.json"
  let abi := abiFile.contents
  expect (abi.contains "(uint64,uint64)")
    s!"ArrayRet ABI must declare tuple (uint64,uint64), got: {abi}"
  expect (abi.contains "components")
    "ArrayRet ABI must have components for tuple"

/-- BL-18: anonymous `Option UInt64` entry/view return is tag+payload
(2 leaves). Covers construct of none/some and returnAggregate ABI. -/
private unsafe def testAnonymousOptionUInt64Return : IO Unit := do
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptionRet where\n" ++
    "  state flag : UInt64\n" ++
    "  init(f : UInt64) do\n" ++
    "    flag := f\n" ++
    "  view getNone() : Option UInt64 do\n" ++
    "    return Option.none()\n" ++
    "  view getSome(x : UInt64) : Option UInt64 do\n" ++
    "    return Option.some(x)\n" ++
    "  view getFlagOpt() : Option UInt64 do\n" ++
    "    if flag == 0 then\n" ++
    "      return Option.none()\n" ++
    "    else\n" ++
    "      return Option.some(flag)\n"
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load OptionRet" (← session.selectProgramV1
    sourceText "<evm-option-ret>" "Tests.EvmOptionRet" none)
  let compiled ← liftResult "compile OptionRet" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan OptionRet" <| planEvm compiled
  expect (plan.entries.size == 3) "OptionRet must have three entries"
  for e in plan.entries do
    match e.resultKind with
    | .aggregate leaves =>
        expect (leaves.size == 2)
          s!"{e.name} Option return must have 2 leaves, got {leaves.size}"
        expect (!leaves[0]!.isInt && !leaves[1]!.isInt)
          s!"{e.name} Option leaves must be uint64"
    | _ =>
        throw <| IO.userError
          s!"{e.name} resultKind must be .aggregate, got {repr e.resultKind}"
  -- getNone body: returnAggregate (0, 0)
  let noneEntry := plan.entries[0]!
  expect (noneEntry.name == "getNone") "getNone name"
  match noneEntry.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2 && leafIsInt == #[false, false])
        "getNone returnAggregate shape"
      expect (leaves[0]! == .literal 0 && leaves[1]! == .literal 0)
        "getNone must return tag=0 payload=0"
  | _ =>
      throw <| IO.userError "getNone body must be .returnAggregate"
  -- getSome body: returnAggregate (1, param 0)
  let someEntry := plan.entries[1]!
  expect (someEntry.name == "getSome") "getSome name"
  match someEntry.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2 && leafIsInt == #[false, false])
        "getSome returnAggregate shape"
      expect (leaves[0]! == .literal 1)
        "getSome must return tag=1"
      expect (leaves[1]! == .param 0)
        "getSome payload must be the param"
  | _ =>
      throw <| IO.userError "getSome body must be .returnAggregate"
  let output ← liftResult "materialize OptionRet" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "OptionRet.yul") |
    throw <| IO.userError "OptionRet: missing OptionRet.yul"
  let yul := yulFile.contents
  expect (yul.contains "mstore(0, ") "OptionRet Yul must mstore tag leaf"
  expect (yul.contains "mstore(32, ") "OptionRet Yul must mstore payload leaf"
  expect (yul.contains "return(0, 64)") "OptionRet Yul must return 64 bytes"
  let some abiFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "OptionRet.abi.json") |
    throw <| IO.userError "OptionRet: missing OptionRet.abi.json"
  let abi := abiFile.contents
  expect (abi.contains "(uint64,uint64)")
    s!"OptionRet ABI must declare tuple (uint64,uint64), got: {abi}"

/-- BL-18: Bytes / Map / Array UInt64 9 / nested Array stay fail-closed. -/
private unsafe def testAnonymousReturnFailClosedBoundaries : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- Bytes N return (UInt8 leaf width class).
  let bytesSrc :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BytesRet where\n" ++
    "  state blob : Bytes 2\n" ++
    "  init() do\n" ++
    "    blob[0] := 0\n" ++
    "    blob[1] := 0\n" ++
    "  view getBytes() : Bytes 2 do\n" ++
    "    return blob\n"
  let bSrc ← match ← session.selectProgramV1
      bytesSrc "<evm-bytes-ret>" "Tests.EvmBytesRet" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"BytesRet select: {e.render}"
  match Compiler.compileValidatedSourceV1 bSrc with
  | .error _ => pure ()
  | .ok compiled =>
      match planEvm compiled with
      | .error e =>
          expect (e.render.contains "Bytes" || e.render.contains "fail" ||
              e.render.contains "aggregate" || e.render.contains "UInt8")
            s!"Bytes return FC must cite Bytes/UInt8/aggregate, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "EVM Bytes return must fail closed, not produce a plan"
  -- Map return (runtime key order).
  let mapSrc :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapRet where\n" ++
    "  state m : Map UInt64 UInt64\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "  view getMap() : Map UInt64 UInt64 do\n" ++
    "    return m\n"
  let mSrc ← match ← session.selectProgramV1
      mapSrc "<evm-map-ret>" "Tests.EvmMapRet" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapRet select: {e.render}"
  match Compiler.compileValidatedSourceV1 mSrc with
  | .error _ => pure ()
  | .ok compiled =>
      match planEvm compiled with
      | .error e =>
          expect (e.render.contains "Map" || e.render.contains "aggregate" ||
              e.render.contains "key")
            s!"Map return FC must cite Map/key/aggregate, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "EVM Map return must fail closed, not produce a plan"
  -- Array UInt64 9 exceeds cap-8.
  let arr9Src :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Arr9Ret where\n" ++
    "  state slots : Array UInt64 9\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n" ++
    "    slots[2] := 0\n" ++
    "    slots[3] := 0\n" ++
    "    slots[4] := 0\n" ++
    "    slots[5] := 0\n" ++
    "    slots[6] := 0\n" ++
    "    slots[7] := 0\n" ++
    "    slots[8] := 0\n" ++
    "  view getArr() : Array UInt64 9 do\n" ++
    "    return slots\n"
  let a9Src ← match ← session.selectProgramV1
      arr9Src "<evm-arr9-ret>" "Tests.EvmArr9Ret" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"Arr9Ret select: {e.render}"
  match Compiler.compileValidatedSourceV1 a9Src with
  | .error _ => pure ()
  | .ok compiled =>
      match planEvm compiled with
      | .error e =>
          expect (e.render.contains "8" || e.render.contains "leaf")
            s!"Array UInt64 9 leaf-cap error must cite cap/leaf, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "EVM Array UInt64 9 return must fail closed (cap-8), not produce a plan"
  -- Nested anonymous container: Option of Array (non-UInt64 payload) FC.
  -- Syntax is space-prefix (`Option Array UInt64 2`), not parenthesized.
  let nestSrc :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program NestRet where\n" ++
    "  state pad : UInt64\n" ++
    "  init(p : UInt64) do\n" ++
    "    pad := p\n" ++
    "  view getNested() : Option Array UInt64 2 do\n" ++
    "    return Option.none()\n"
  let nSrc ← match ← session.selectProgramV1
      nestSrc "<evm-nest-ret>" "Tests.EvmNestRet" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"NestRet select: {e.render}"
  match Compiler.compileValidatedSourceV1 nSrc with
  | .error _ => pure ()  -- Normalize may reject nested container result first.
  | .ok compiled =>
      match planEvm compiled with
      | .error e =>
          expect (e.render.contains "Option" || e.render.contains "Array" ||
              e.render.contains "UInt64" || e.render.contains "aggregate" ||
              e.render.contains "payload")
            s!"nested Option Array return FC must cite Option/Array/payload, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "EVM nested Option Array return must fail closed, not produce a plan"

/-- B-RET-ABI: leaf count exceeding cap-8 stays fail-closed. A Struct with
9 UInt64 fields exceeds the B-RET-ABI cap. -/
private unsafe def testAggregateLeafCapFailClosed : IO Unit := do
  let mut fields := ""
  for i in [0:9] do
    fields := fields ++ s!"    f{i} : UInt64\n"
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program WideBox where\n" ++
    "  struct Wide where\n" ++
    fields ++
    "  state w : Wide\n" ++
    "  init() do\n" ++
    "    w := Wide.new(0, 0, 0, 0, 0, 0, 0, 0, 0)\n" ++
    "  view getWide() : Wide do\n" ++
    "    return w\n"
  let session ← Tests.Language.ParserSession.shared
  let source ← match ← session.selectProgramV1
    sourceText "<evm-wide-ret>" "Tests.EvmWideRet" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"WideBox select: {e.render}"
  match Compiler.compileValidatedSourceV1 source with
  | .error _ => pure ()
  | .ok compiled =>
      match planEvm compiled with
      | .error e =>
        expect (e.render.contains "8" || e.render.contains "leaf")
          s!"WideBox leaf-cap error must cite cap/leaf, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "EVM 9-leaf aggregate return must fail closed (cap-8), not produce a plan"

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
  testMatchStringLiterals
  testMatchStringNonStringPatternRejected
  testEarlyReturnJoin
  testInitEarlyBareReturnClosed
  testEmitRevertFlow
  testFnLocalCall
  testArithOps
  testShiftBitwiseLogical
  testForLoop
  testRegionValidationNegatives
  testComparisonNegatives
  testPrincipalStateStorage
  testExternalCallGate
  testBodyMultiWidthUInt
  testBodyUInt8OverflowPlan
  testBodyMultiWidthShift
  testAbiMultiWidthStateParam
  testWideUintProduct
  testNarrowIntBodyAndAbi
  testNarrowResultAdmitted
  testUInt128ResultAdmitted
  testVoidEntryRejected
  testMultipleEvents
  testZeroArgRevert
  testBoolResultPureFn
  testOmittedTypeLet
  testAssertElseRejected
  testFieldBn254Lane
  testArrayStateIndexOps
  testMapPutIntoEmptyAtomicStore
  testTokenDualStoreBatchSeparation
  testBytesStateIndexOps
  testContextReadFailClosedBoundary
  testAggregateStructReturn
  testAnonymousArrayUInt64Return
  testAnonymousOptionUInt64Return
  testAnonymousReturnFailClosedBoundaries
  testAggregateLeafCapFailClosed
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
