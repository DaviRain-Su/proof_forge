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

private partial def nestedAddExpr : Nat → Targets.Evm.Expr
  | 0 => .literal 0
  | level + 1 => .checkedAdd (nestedAddExpr level) (.literal 0)

private def nestedCompareExpr (level : Nat) : Targets.Evm.Expr :=
  .compare .eq (nestedAddExpr (level - 1)) (.literal 0)

private partial def fullAddExpr : Nat → Targets.Evm.Expr
  | 0 => .literal 0
  | level + 1 =>
      let child := fullAddExpr level
      .checkedAdd child child

private def fullCompareExpr (level : Nat) : Targets.Evm.Expr :=
  .compare .eq (fullAddExpr level) (.literal 0)

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

private unsafe def testTerminalIfSemanticPlan : IO Unit := do
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Choose where\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry choose() : UInt64 do\n" ++
    "    if true then\n" ++
    "      assert count == 0\n" ++
    "      count := 7\n" ++
    "      return count\n" ++
    "    else\n" ++
    "      count := 9\n" ++
    "      assert count == 9\n" ++
    "      return count\n"
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load terminal if" (← session.selectProgramV1
    sourceText "<evm-terminal-if>" "Tests.EvmTerminalIf" none)
  let compiled ← liftResult "compile terminal if" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan terminal if" <| planEvm compiled
  expect (plan.entries.size == 1 && plan.entries[0]!.params.isEmpty)
    "terminal-if EVM slice must retain a parameterless entry"
  expect (plan.entries[0]!.body == #[.conditional (.literal 1)
      #[.assert (.compare .eq (.storageLoad 0) (.literal 0)),
        .store { slot := 0, value := .literal 7 },
        .returnValue (.storageLoad 0)]
      #[.store { slot := 0, value := .literal 9 },
        .assert (.compare .eq (.storageLoad 0) (.literal 9)),
        .returnValue (.storageLoad 0)]])
    "terminal-if lowering must accept global ValueIds and preserve ordered arm effects"
  let output ← liftResult "materialize terminal if" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "Choose.yul") |
    throw <| IO.userError "terminal if: missing Choose.yul"
  expect (yulFile.contents.contains "switch expr0" &&
      yulFile.contents.contains "case 0 {" &&
      yulFile.contents.contains "default {")
    "terminal-if Yul must render deterministic false/true arms"

private unsafe def testTerminalSwitchSemanticPlan : IO Unit := do
  let sourceText := "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program MatchSeven where\n  state n : UInt64\n  init() do\n    n := 7\n" ++
    "  view choose() : UInt64 do\n    match n with\n    | 7 => do\n      return 3\n" ++
    "    | _ => do\n      return 4\n"
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load terminal switch" (← session.selectProgramV1 sourceText
    "<evm-terminal-switch>" "Tests.EvmTerminalSwitch" none)
  let compiled ← liftResult "compile terminal switch" <| Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan terminal switch" <| planEvm compiled
  let choose := plan.entries[0]!
  expect (choose.body == #[.conditional (.compare .eq (.storageLoad 0) (.literal 7))
    #[.returnValue (.literal 3)] #[.returnValue (.literal 4)]])
    "EVM switch must lower to exact UInt64 equality with case/default arms"
  let output ← liftResult "materialize terminal switch" <| materializeSelected TargetId.evm compiled
  let yul := ((MaterializedArtifactsV1.filesOf output).find? (·.path == "MatchSeven.yul")).get!.contents
  expect (yul.contains "eq(" && yul.contains "let expr0 := 3" && yul.contains "let expr0 := 4")
    "EVM switch Yul must render equality and both returns"

private unsafe def testTerminalBoolSemanticPlans : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let ifText := "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program BoolIf where\n  state n : UInt64\n  init() do\n    n := 1\n" ++
    "  view choose() : Bool do\n    if true then\n" ++
    "      return n == 1\n    else\n      return n == 2\n"
  let ifSource ← liftResult "load terminal Bool if" (← session.selectProgramV1 ifText
    "<evm-terminal-bool-if>" "Tests.EvmTerminalBoolIf" none)
  let ifCompiled ← liftResult "compile terminal Bool if" <|
    Compiler.compileValidatedSourceV1 ifSource
  let ifPlan ← liftResult "plan terminal Bool if" <| planEvm ifCompiled
  expect (ifPlan.entries[0]!.resultKind == .bool && ifPlan.entries[0]!.body == #[
      .conditional (.literal 1)
        #[.returnValue (.compare .eq (.storageLoad 0) (.literal 1))]
        #[.returnValue (.compare .eq (.storageLoad 0) (.literal 2))]])
    "terminal Bool if must retain Bool arm returns in the EVM Plan"
  let ifOutput ← liftResult "materialize terminal Bool if" <|
    materializeSelected TargetId.evm ifCompiled
  let ifYul := ((MaterializedArtifactsV1.filesOf ifOutput).find?
    (·.path == "BoolIf.yul")).get!.contents
  expect (ifYul.contains "switch expr0" && ifYul.contains "sload(0)" &&
      (ifYul.splitOn "eq(").length >= 3)
    "terminal Bool if must render both Bool returns"

  let matchText := "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program BoolMatch where\n  state n : UInt64\n  init() do\n    n := 7\n" ++
    "  view choose() : Bool do\n    match n with\n    | 7 => do\n      return n == 7\n" ++
    "    | _ => do\n      return n == 0\n"
  let matchSource ← liftResult "load terminal Bool match" (← session.selectProgramV1 matchText
    "<evm-terminal-bool-match>" "Tests.EvmTerminalBoolMatch" none)
  let matchCompiled ← liftResult "compile terminal Bool match" <|
    Compiler.compileValidatedSourceV1 matchSource
  let matchPlan ← liftResult "plan terminal Bool match" <| planEvm matchCompiled
  expect (matchPlan.entries[0]!.resultKind == .bool && matchPlan.entries[0]!.body == #[
      .conditional (.compare .eq (.storageLoad 0) (.literal 7))
        #[.returnValue (.compare .eq (.storageLoad 0) (.literal 7))]
        #[.returnValue (.compare .eq (.storageLoad 0) (.literal 0))]])
    "one-case UInt64 match must retain Bool arm returns in the EVM Plan"
  let matchOutput ← liftResult "materialize terminal Bool match" <|
    materializeSelected TargetId.evm matchCompiled
  let matchYul := ((MaterializedArtifactsV1.filesOf matchOutput).find?
    (·.path == "BoolMatch.yul")).get!.contents
  expect (matchYul.contains "eq(" && matchYul.contains "case 0 {" &&
      matchYul.contains "default {")
    "one-case UInt64 match returning Bool must render its comparison and arms"

private unsafe def testJoinContinuationSemanticPlan : IO Unit := do
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program JoinChoice where\n" ++
    "  view choose() : UInt64 do\n" ++
    "    let selected : UInt64 := 0\n" ++
    "    if true then\n" ++
    "      selected := 7\n" ++
    "    else\n" ++
    "      selected := 9\n" ++
    "    return selected + 1\n"
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load join continuation" (← session.selectProgramV1
    sourceText "<evm-join-continuation>" "Tests.EvmJoinContinuation" none)
  let compiled ← liftResult "compile join continuation" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan join continuation" <| planEvm compiled
  let some choose := plan.entries.find? (·.name == "choose") |
    throw <| IO.userError "join continuation EVM Plan is missing choose"
  expect (choose.body == #[.conditional (.literal 1)
      #[.returnValue (.checkedAdd (.literal 7) (.literal 1))]
      #[.returnValue (.checkedAdd (.literal 9) (.literal 1))]])
    "phi lowering must substitute each pure arm value into a duplicated continuation"
  let output ← liftResult "materialize join continuation" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "JoinChoice.yul") |
    throw <| IO.userError "join continuation: missing JoinChoice.yul"
  expect (yulFile.contents.contains "switch expr0" &&
      yulFile.contents.contains "let expr0 := 7" &&
      yulFile.contents.contains "let expr0 := 9" &&
      yulFile.contents.contains "let expr2 := add(expr0, expr1)" &&
      !yulFile.contents.contains "sload(")
    "phi Yul must render complete continuation arithmetic independently in both arms"

private unsafe def testStateMediatedJoinContinuationSemanticPlan : IO Unit := do
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program StateJoinChoice where\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry choose() : UInt64 do\n" ++
    "    if true then\n" ++
    "      count := 7\n" ++
    "    else\n" ++
    "      count := 9\n" ++
    "    return count + 1\n"
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load state-mediated join" (← session.selectProgramV1
    sourceText "<evm-state-join-continuation>" "Tests.EvmStateJoinContinuation" none)
  let compiled ← liftResult "compile state-mediated join" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan state-mediated join" <| planEvm compiled
  let some choose := plan.entries.find? (·.name == "choose") |
    throw <| IO.userError "state-mediated join EVM Plan is missing choose"
  expect (choose.body == #[.conditional (.literal 1)
      #[.store { slot := 0, value := .literal 7 }]
      #[.store { slot := 0, value := .literal 9 }],
    .returnValue (.checkedAdd (.storageLoad 0) (.literal 1))])
    "zero-param join must preserve arm stores followed by one shared continuation"
  let output ← liftResult "materialize state-mediated join" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "StateJoinChoice.yul") |
    throw <| IO.userError "state-mediated join: missing StateJoinChoice.yul"
  expect (yulFile.contents.contains "switch expr0" &&
      yulFile.contents.contains "sstore(0, expr0)" &&
      yulFile.contents.contains "let expr1 := sload(0)" &&
      yulFile.contents.contains "let expr3 := add(expr1, expr2)")
    "zero-param join Yul must render branch state effects before the shared continuation"

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
  -- Structured terminal branches preserve ordered effects in both arms.
  let branchPlan := { basePlan with entries := #[{
    basePlan.entries[0]! with
      mutability := .nonpayable
      body := #[.conditional (.compare .eq (.literal 1) (.literal 1))
        #[.assert (.literal 1), .store { slot := 0, value := .literal 7 },
          .returnValue (.storageLoad 0)]
        #[.store { slot := 0, value := .literal 9 }, .assert (.literal 1),
          .returnValue (.storageLoad 0)]]
  }] }
  match Targets.Evm.validatePlan branchPlan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"structured branch plan must accept: {e.render}"
  let parameterizedBranch := { branchPlan with entries := #[{
    branchPlan.entries[0]! with
      selector := Targets.Evm.Keccak.selector "get" #["uint64"]
      params := #[{ sourceId := 0, name := "x", wordIndex := 0 }]
  }] }
  match Targets.Evm.validatePlan parameterizedBranch with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "parameterized singleton conditional must reject"
  let prefixedBranch := { branchPlan with entries := #[{
    branchPlan.entries[0]! with body := #[.assert (.literal 1), branchPlan.entries[0]!.body[0]!]
  }] }
  match Targets.Evm.validatePlan prefixedBranch with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "prefix plus conditional must reject"
  let nestedBranch := { branchPlan with entries := #[{
    branchPlan.entries[0]! with body := #[.conditional (.literal 1)
      #[.conditional (.literal 1) #[.returnValue (.literal 1)] #[.returnValue (.literal 2)]]
      #[.returnValue (.literal 3)]]
  }] }
  match Targets.Evm.validatePlan nestedBranch with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "nested conditional must reject"
  let secondConditional := { branchPlan with entries := #[{
    branchPlan.entries[0]! with body := #[
      .conditional (.literal 1) #[.assert (.literal 1)] #[.assert (.literal 1)],
      .conditional (.literal 1) #[.returnValue (.literal 1)] #[.returnValue (.literal 2)]]
  }] }
  match Targets.Evm.validatePlan secondConditional with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "additional continuation conditional must reject"
  let branchAfterReturn := { branchPlan with entries := #[{
    branchPlan.entries[0]! with body := #[.conditional (.literal 1)
      #[.returnValue (.literal 1), .assert (.literal 1)]
      #[.returnValue (.literal 2)]]
  }] }
  match Targets.Evm.validatePlan branchAfterReturn with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "branch arm statement after return must reject"
  let viewBranchStore := { branchPlan with entries := #[{
    branchPlan.entries[0]! with mutability := .view
  }] }
  match Targets.Evm.validatePlan viewBranchStore with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "view storage write inside branch arm must reject"
  let danglingBranchCondition := { branchPlan with entries := #[{
    branchPlan.entries[0]! with body := #[.conditional (.storageLoad 99)
      #[.returnValue (.literal 1)] #[.returnValue (.literal 2)]]
  }] }
  match Targets.Evm.validatePlan danglingBranchCondition with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "dangling structured branch condition must reject"
  let wrongCondition := { branchPlan with entries := #[{
    branchPlan.entries[0]! with body := #[.conditional (.storageLoad 0)
      #[.returnValue (.literal 1)] #[.returnValue (.literal 2)]]
  }] }
  let wrongArmAssert := { branchPlan with entries := #[{
    branchPlan.entries[0]! with body := #[.conditional (.literal 1)
      #[.assert (.literal 7), .returnValue (.literal 1)] #[.returnValue (.literal 2)]]
  }] }
  let boolArmReturn := { branchPlan with entries := #[{
    branchPlan.entries[0]! with body := #[.conditional (.literal 1)
      #[.returnValue (.compare .eq (.literal 0) (.literal 0))] #[.returnValue (.literal 2)]]
  }] }
  let boolArmStore := { branchPlan with entries := #[{
    branchPlan.entries[0]! with body := #[.conditional (.literal 1)
      #[.store { slot := 0, value := .compare .eq (.literal 0) (.literal 0) },
        .returnValue (.literal 1)] #[.returnValue (.literal 2)]]
  }] }
  for bad in #[wrongCondition, wrongArmAssert, boolArmReturn, boolArmStore] do
    match Targets.Evm.validatePlan bad with
    | .error (.planInvariant .evm _) => pure ()
    | _ => throw <| IO.userError "contextually mistyped terminal-if Plan must reject"

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

unsafe def run : IO Unit := do
  testSemanticPlanSourceAuthority
  testRichUInt64SemanticPlan
  testGuardedCounterSemanticPlan
  testInitWithAssert
  testTerminalIfSemanticPlan
  testTerminalSwitchSemanticPlan
  testTerminalBoolSemanticPlans
  testJoinContinuationSemanticPlan
  testStateMediatedJoinContinuationSemanticPlan
  testCompareAssertPlanMutations
  testBoolResultPositive
  testBoolPredicateEndToEnd
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
