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
          .store { slot := 0, value := .param 0 }])
        "constructor body must interleave assert then store in source order"
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
  -- Bool as entry result fails closed.
  let boolResult :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BadBoolResult where\n" ++
    "  view isZero(x : UInt64) : Bool do\n" ++
    "    return x == 0\n"
  match ← session.selectProgramV1 boolResult "<evm-bool-result>" "Tests.EvmBoolResult" none with
  | .error _ => pure ()
  | .ok source =>
      match Compiler.compileValidatedSourceV1 source with
      | .error _ => pure ()
      | .ok compiled =>
          match planEvm compiled with
          | .error (.planInvariant .evm _) => pure ()
          | .error e => throw <| IO.userError s!"Bool result must fail closed, got {e.render}"
          | .ok _ => throw <| IO.userError "Bool result must not produce an EVM plan"
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

unsafe def run : IO Unit := do
  testSemanticPlanSourceAuthority
  testRichUInt64SemanticPlan
  testGuardedCounterSemanticPlan
  testInitWithAssert
  testCompareAssertPlanMutations
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
  expect (MaterializedArtifactsV1.sourceDigestOf output == sourceDigest &&
      MaterializedArtifactsV1.semanticDigestOf output == semanticDigest)
    "EVM smoke carrier must bind canonical source and semantic digests"
  -- plan is still capability-gated and used for layout assertions above
  let _ := plan
  IO.println "Tests.Materialization.EvmSmoke: ok"

end Tests.Materialization.EvmSmoke
