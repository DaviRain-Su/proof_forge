import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Solana
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaPlanV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana

/-- Guarded counter: public UInt64 state with assert `count >= delta` before checked-sub. -/
private def guardedCounterSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program GuardedCounter where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(i : UInt64) do\n" ++
  "    count := i\n\n" ++
  "  entry decrement(delta : UInt64) : UInt64 do\n" ++
  "    assert count >= delta\n" ++
  "    count := count - delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

private def guardedCounterModuleNameV1 : String := "Examples.GuardedCounter"

/-- Same ABI as GuardedCounter but without the assert (for IDL identity). -/
private def unguardedCounterSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program GuardedCounter where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(i : UInt64) do\n" ++
  "    count := i\n\n" ++
  "  entry decrement(delta : UInt64) : UInt64 do\n" ++
  "    count := count - delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

/-- All six comparison operators as assert conditions, with required Solana state/init. -/
private def allComparesSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program AllCompares where\n" ++
  "  state seed : UInt64\n\n" ++
  "  init(x : UInt64) do\n" ++
  "    seed := x\n\n" ++
  "  entry check(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    assert a == b\n" ++
  "    assert a != b\n" ++
  "    assert a < b\n" ++
  "    assert a <= b\n" ++
  "    assert a > b\n" ++
  "    assert a >= b\n" ++
  "    return a\n\n" ++
  "  view current() : UInt64 do\n" ++
  "    return seed\n\n" ++
  "end ProofForgeV2.Examples\n"

private def allComparesModuleNameV1 : String := "Examples.AllCompares"

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def expectPlanError (label : String) (result : CompileResult α) : IO Unit :=
  match result with
  | .error (.planInvariant .solana _) => pure ()
  | .error e => throw <| IO.userError s!"{label}: expected solana planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError s!"{label}: expected failure, got ok"

private def expectCompileFailure (label : String) (result : CompileResult α) : IO Unit :=
  match result with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError s!"{label}: expected compile failure"

private unsafe def compileSource (session : Language.Loader.ParserSession)
    (source moduleName path : String) : IO CompiledSemanticV1 := do
  let validated ← liftResult (← session.selectProgramV1 source path moduleName none)
  liftResult <| Compiler.compileValidatedSourceV1 validated

private def solanaCapability (compiled : CompiledSemanticV1) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.solana none
  Targets.resolveEngineeringRequirementsV1 selection compiled

private def planSolana (compiled : CompiledSemanticV1) : CompileResult Plan := do
  let capability ← solanaCapability compiled
  planFromCapability capability

private def irSolana (compiled : CompiledSemanticV1) : CompileResult IR := do
  let capability ← solanaCapability compiled
  irFromCapability capability

private def filesSolana (compiled : CompiledSemanticV1) : CompileResult (Array OutputFile) := do
  let capability ← solanaCapability compiled
  buildFromCapability capability

private def findFile (files : Array OutputFile) (path : String) : IO String :=
  match files.find? (·.path == path) with
  | some file => pure file.contents
  | none => throw <| IO.userError s!"missing output file '{path}'"

private def findHandler (plan : Plan) (name : String) : IO Handler :=
  if plan.initializer.name == name then
    pure plan.initializer
  else
    match plan.entries.find? (·.name == name) with
    | some handler => pure handler
    | none => throw <| IO.userError s!"missing handler '{name}'"

private def findHandlerIR (ir : IR) (name : String) : IO HandlerIR :=
  match ir.handlers.find? (·.name == name) with
  | some handler => pure handler
  | none => throw <| IO.userError s!"missing IR handler '{name}'"

private def wrapProgram (name body : String) : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  s!"program {name} where\n" ++ body ++
  "\nend ProofForgeV2.Examples\n"

/-- Pin guarded-counter Plan body: ge compare + assert + checked-sub store + return. -/
private unsafe def testGuardedCounterPlan
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session guardedCounterSourceText
    guardedCounterModuleNameV1 "<solana-guarded-counter>"
  let plan ← liftResult <| planSolana compiled
  expect (plan.assertionFailedError == assertionFailedError)
    "plan must carry the canonical assertion-failed error code"
  expect (plan.arithmeticOverflowError == arithmeticOverflowError)
    "plan must retain the canonical arithmetic overflow error code"
  let decrement ← findHandler plan "decrement"
  expect (decrement.mode == .mutate && decrement.params.size == 1 &&
      decrement.params[0]!.name == "delta" && decrement.params[0]!.dataOffset == 8)
    "decrement ABI must remain single UInt64 delta at dataOffset 8"
  expect (decrement.body == #[
      .assert (.compare .ge (.stateLoad 0 8) (.param 8)),
      .store {
        accountIndex := 0
        byteOffset := 8
        value := .checkedSub (.stateLoad 0 8) (.param 8)
      },
      .returnValue (.stateLoad 0 8)])
    "decrement Plan body must be assert(ge(load,param)) → store(checkedSub) → return load"
  let initHandler ← findHandler plan "initialize"
  expect (initHandler.body == #[
      .store { accountIndex := 0, byteOffset := 8, value := .param 8 }])
    "initializer Plan body must stay a single param store"
  let getHandler ← findHandler plan "get"
  expect (getHandler.mode == .view && getHandler.body == #[.returnValue (.stateLoad 0 8)])
    "view Plan body must stay a single state load return"

/-- Pin IR op order/destinations for compare + assert + checked-sub. -/
private unsafe def testGuardedCounterIR
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session guardedCounterSourceText
    guardedCounterModuleNameV1 "<solana-guarded-counter-ir>"
  let plan ← liftResult <| planSolana compiled
  let ir ← liftResult <| irSolana compiled
  let decrement ← findHandlerIR ir "decrement"
  let overflow := plan.arithmeticOverflowError
  let assertErr := plan.assertionFailedError
  expect (decrement.operations == #[
      .loadState 0 0 8,
      .loadParam 1 8,
      .compare 2 0 1 .ge,
      .assert 2 assertErr,
      .loadState 3 0 8,
      .loadParam 4 8,
      .checkedSub 5 3 4 overflow,
      .storeState 0 8 5,
      .loadState 6 0 8,
      .setReturnData 6])
    "decrement IR must lower compare/assert then checked-sub store with dense temps"
  liftResult <| validateIR ir
  -- Deterministic rebuild identity.
  let ir2 ← liftResult <| irSolana compiled
  expect (ir == ir2) "Solana IR rebuild must be byte-identical / structure-identical"

/-- sbpf-plan substrings for compare/assert; IDL ABI-identical to unguarded twin. -/
private unsafe def testGuardedCounterArtifacts
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session guardedCounterSourceText
    guardedCounterModuleNameV1 "<solana-guarded-artifacts>"
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "GuardedCounter.sbpf-plan"
  expect (planText.contains "cmp_ge_u64")
    "sbpf-plan must render cmp_ge_u64 for the assert condition"
  expect (planText.contains "assert %2 else program_error 0x1002")
    "sbpf-plan must render assert with the canonical 0x1002 program error"
  expect (planText.contains "checked_sub_u64")
    "sbpf-plan must retain checked_sub_u64 after the assert"
  expect (!planText.contains "cmp_eq_u64" && !planText.contains "cmp_lt_u64")
    "guarded counter only uses ge; other cmp renderers must not appear spuriously"
  let idl ← findFile files "GuardedCounter.idl.json"
  expect (idl.contains "\"name\":\"decrement\"" && idl.contains "\"name\":\"delta\"" &&
      idl.contains "\"type\":\"u64\"" && idl.contains "\"returns\":\"u64-le\"")
    "IDL must describe decrement(delta:u64)→u64 without assert surface"
  expect (!idl.contains "assert" && !idl.contains "cmp_")
    "IDL must not surface assert/compare operations"
  -- Same program name/ABI without assert → identical IDL bytes.
  let unguarded ← compileSource session unguardedCounterSourceText
    guardedCounterModuleNameV1 "<solana-unguarded-artifacts>"
  let unguardedFiles ← liftResult <| filesSolana unguarded
  let unguardedIdl ← findFile unguardedFiles "GuardedCounter.idl.json"
  expect (idl == unguardedIdl)
    "assert must not change the Solana IDL relative to the unguarded twin"
  let files2 ← liftResult <| filesSolana compiled
  let planText2 ← findFile files2 "GuardedCounter.sbpf-plan"
  expect (planText == planText2) "sbpf-plan rebuild must be byte-identical"

/-- Every comparison op appears in plan/IR/sbpf-plan text. -/
private unsafe def testAllComparisonOps
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session allComparesSourceText
    allComparesModuleNameV1 "<solana-all-compares>"
  let plan ← liftResult <| planSolana compiled
  let check ← findHandler plan "check"
  let expectedOps : Array ComparisonOp := #[.eq, .ne, .lt, .le, .gt, .ge]
  expect (check.body.size == 7)
    s!"check body must be 6 asserts + return, got {check.body.size}"
  for i in [:6] do
    match check.body[i]! with
    | .assert (.compare op (.param 8) (.param 16)) =>
        expect (op == expectedOps[i]!)
          s!"assert {i} must use comparison op {repr (expectedOps[i]!)}, got {repr op}"
    | other =>
        throw <| IO.userError s!"assert {i}: unexpected statement {repr other}"
  expect (check.body[6]! == .returnValue (.param 8))
    "check must return the first parameter after asserts"
  let ir ← liftResult <| irSolana compiled
  let checkIR ← findHandlerIR ir "check"
  let assertErr := plan.assertionFailedError
  -- Each assert segment lowers as loadParam a / loadParam b / compare / assert
  -- (4 ops; 3 temps: a, b, compare-result). Temps are dense across statements.
  for i in [:6] do
    let opBase := i * 4
    let destA := i * 3
    let destB := destA + 1
    let destCmp := destA + 2
    expect (checkIR.operations[opBase]? == some (.loadParam destA 8))
      s!"IR [{opBase}] load param a → %{destA}"
    expect (checkIR.operations[opBase + 1]? == some (.loadParam destB 16))
      s!"IR [{opBase}+1] load param b → %{destB}"
    expect (checkIR.operations[opBase + 2]? ==
        some (.compare destCmp destA destB expectedOps[i]!))
      s!"IR [{opBase}+2] compare {repr (expectedOps[i]!)} → %{destCmp}"
    expect (checkIR.operations[opBase + 3]? == some (.assert destCmp assertErr))
      s!"IR [{opBase}+3] assert %{destCmp}"
  expect (checkIR.operations[24]? == some (.loadParam 18 8) &&
      checkIR.operations[25]? == some (.setReturnData 18))
    "after six assert segments, return must reload param a into %{18}"
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "AllCompares.sbpf-plan"
  for fragment in #["cmp_eq_u64", "cmp_ne_u64", "cmp_lt_u64", "cmp_le_u64",
      "cmp_gt_u64", "cmp_ge_u64", "assert %2 else program_error 0x1002"] do
    expect (planText.contains fragment)
      s!"sbpf-plan must contain '{fragment}'"

/-- Assert is legal in initialize/mutate/view modes. -/
private unsafe def testAssertInAllModes
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "AssertModes" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    assert i >= 0\n" ++
    "    count := i\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    assert delta >= 0\n" ++
    "    count := count + delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    assert count >= 0\n" ++
    "    return count\n"
  let compiled ← compileSource session source "Examples.AssertModes" "<solana-assert-modes>"
  let plan ← liftResult <| planSolana compiled
  let initHandler ← findHandler plan "initialize"
  expect (initHandler.body[0]? == some (.assert (.compare .ge (.param 8) (.literal 0))))
    "initializer may begin with assert"
  let bumpHandler ← findHandler plan "bump"
  expect (bumpHandler.body[0]? == some (.assert (.compare .ge (.param 8) (.literal 0))))
    "mutate entry may begin with assert"
  let getHandler ← findHandler plan "get"
  expect (getHandler.mode == .view &&
      getHandler.body[0]? == some (.assert (.compare .ge (.stateLoad 0 8) (.literal 0))))
    "view may assert without writing state"
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir

/-- Product-path envelopes that put Bool in state/param still fail closed.
    Bool entry/view results are now accepted (see testBoolResultPositive /
    testBoolPredicateEndToEnd). -/
private unsafe def testBoolEnvelopeRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let boolState := wrapProgram "BoolState" <|
    "  state flag : Bool\n\n" ++
    "  entry ping(x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  let boolParam := wrapProgram "BoolParam" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry ping(flag : Bool) : UInt64 do\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  for item in #[
      ("bool-state", boolState, "Examples.BoolState"),
      ("bool-param", boolParam, "Examples.BoolParam")] do
    let (label, source, moduleName) := item
    let validated ← liftResult (← session.selectProgramV1
      source s!"<solana-{label}>" moduleName none)
    expectCompileFailure label (Compiler.compileValidatedSourceV1 validated)
  -- Type-mismatched returns fail closed at typed/normalize (not Solana Plan).
  let boolReturnsU64 := wrapProgram "BoolReturnsU64" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  view positive() : Bool do\n" ++
    "    return count\n\n" ++
    "  entry bump(d : UInt64) : UInt64 do\n" ++
    "    return count\n"
  let u64ReturnsBool := wrapProgram "U64ReturnsBool" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count > 0\n\n" ++
    "  entry bump(d : UInt64) : UInt64 do\n" ++
    "    return count\n"
  for item in #[
      ("bool-handler-returns-u64", boolReturnsU64, "Examples.BoolReturnsU64"),
      ("u64-handler-returns-bool", u64ReturnsBool, "Examples.U64ReturnsBool")] do
    let (label, source, moduleName) := item
    let validated ← liftResult (← session.selectProgramV1
      source s!"<solana-{label}>" moduleName none)
    expectCompileFailure label (Compiler.compileValidatedSourceV1 validated)

/-- Wave-A Bool result negative flipped to positive: view returning Bool plans. -/
private unsafe def testBoolResultPositive
    (session : Language.Loader.ParserSession) : IO Unit := do
  let boolResult := wrapProgram "BoolResult" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  view positive() : Bool do\n" ++
    "    return count > 0\n"
  let compiled ← compileSource session boolResult
    "Examples.BoolResult" "<solana-bool-result>"
  let plan ← liftResult <| planSolana compiled
  let positive ← findHandler plan "positive"
  expect (positive.mode == .view && positive.resultKind == .bool)
    "positive view must carry Bool result kind"
  expect (positive.body == #[
      .returnValue (.compare .gt (.stateLoad 0 8) (.literal 0))])
    "positive Plan body must return gt(load, 0)"
  let ir ← liftResult <| irSolana compiled
  let positiveIR ← findHandlerIR ir "positive"
  expect (positiveIR.resultKind == .bool && positiveIR.operations == #[
      .loadState 0 0 8,
      .literal 1 0,
      .compare 2 0 1 .gt,
      .setReturnDataBool 2])
    "positive IR must lower compare then set_return_data_bool"
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "BoolResult.sbpf-plan"
  expect (planText.contains "set_return_data_bool %2")
    "sbpf-plan must render set_return_data_bool for Bool views"
  expect (planText.contains "cmp_gt_u64")
    "sbpf-plan must render cmp_gt_u64 for the comparison"
  expect (!planText.contains "set_return_data_u64_le %2")
    "Bool return must not reuse the UInt64 return-data renderer"
  let idl ← findFile files "BoolResult.idl.json"
  expect (idl.contains "\"name\":\"positive\"" && idl.contains "\"returns\":\"bool\"")
    "IDL must describe positive()→bool"
  expect (!idl.contains "\"returns\":\"u64-le\"")
    "BoolResult has no UInt64 entry/view return (init is null)"
  liftResult <| validateIR ir
  let ir2 ← liftResult <| irSolana compiled
  expect (ir == ir2) "BoolResult IR rebuild must be structure-identical"

/-- BoolPredicate: state + init + UInt64 entry + Bool view + Bool entry. -/
private unsafe def testBoolPredicateEndToEnd
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "BoolPredicate" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n\n" ++
    "  view positive() : Bool do\n" ++
    "    return count > 0\n\n" ++
    "  entry equalsCount(delta : UInt64) : Bool do\n" ++
    "    return count == delta\n"
  let compiled ← compileSource session source
    "Examples.BoolPredicate" "<solana-bool-predicate>"
  let plan ← liftResult <| planSolana compiled
  let capability ← liftResult <| solanaCapability compiled
  let planCap ← liftResult <| planFromCapability capability
  expect (plan == planCap) "planFromCapability must match planSolana helper"
  let bump ← findHandler plan "bump"
  expect (bump.mode == .mutate && bump.resultKind == .u64)
    "bump must remain a UInt64 mutate entry"
  let positive ← findHandler plan "positive"
  expect (positive.mode == .view && positive.resultKind == .bool &&
      positive.body == #[
        .returnValue (.compare .gt (.stateLoad 0 8) (.literal 0))])
    "positive must be Bool view returning gt(load,0)"
  let equalsCount ← findHandler plan "equalsCount"
  expect (equalsCount.mode == .mutate && equalsCount.resultKind == .bool &&
      equalsCount.params.size == 1 && equalsCount.params[0]!.name == "delta" &&
      equalsCount.body == #[
        .returnValue (.compare .eq (.stateLoad 0 8) (.param 8))])
    "equalsCount must be Bool entry returning eq(load,param)"
  let ir ← liftResult <| irFromCapability capability
  let positiveIR ← findHandlerIR ir "positive"
  expect (positiveIR.operations == #[
      .loadState 0 0 8,
      .literal 1 0,
      .compare 2 0 1 .gt,
      .setReturnDataBool 2])
    "positive IR ops: load/literal/compare/setReturnDataBool"
  let equalsIR ← findHandlerIR ir "equalsCount"
  expect (equalsIR.operations == #[
      .loadState 0 0 8,
      .loadParam 1 8,
      .compare 2 0 1 .eq,
      .setReturnDataBool 2])
    "equalsCount IR ops: load/param/compare/setReturnDataBool"
  let bumpIR ← findHandlerIR ir "bump"
  expect (bumpIR.resultKind == .u64) "bump IR result kind must be u64"
  let mut sawU64Return := false
  for op in bumpIR.operations do
    match op with
    | .setReturnData _ => sawU64Return := true
    | .setReturnDataBool _ =>
        throw <| IO.userError "bump must not emit setReturnDataBool"
    | _ => pure ()
  expect sawU64Return "bump must emit setReturnData (u64-le)"
  let files ← liftResult <| buildFromCapability capability
  let planText ← findFile files "BoolPredicate.sbpf-plan"
  expect (planText.contains "set_return_data_bool %2")
    "sbpf-plan must contain set_return_data_bool"
  expect (planText.contains "cmp_gt_u64" && planText.contains "cmp_eq_u64")
    "sbpf-plan must render both comparison ops"
  expect (planText.contains "set_return_data_u64_le")
    "UInt64 bump return must retain set_return_data_u64_le"
  let idl ← findFile files "BoolPredicate.idl.json"
  expect (idl.contains "\"name\":\"positive\"" && idl.contains "\"returns\":\"bool\"")
    "IDL positive returns bool"
  expect (idl.contains "\"name\":\"equalsCount\"" && idl.contains "\"name\":\"delta\"")
    "IDL equalsCount(delta) surface"
  expect (idl.contains "\"name\":\"bump\"" && idl.contains "\"returns\":\"u64-le\"")
    "IDL bump returns u64-le"
  -- Pin exact returns tokens: two bool + one u64-le (init null excluded from count).
  let boolReturns := (idl.splitOn "\"returns\":\"bool\"").length - 1
  let u64Returns := (idl.splitOn "\"returns\":\"u64-le\"").length - 1
  expect (boolReturns == 2 && u64Returns == 1)
    s!"IDL return kinds: expected 2 bool + 1 u64-le, got {boolReturns} bool / {u64Returns} u64"
  let files2 ← liftResult <| buildFromCapability capability
  let planText2 ← findFile files2 "BoolPredicate.sbpf-plan"
  let idl2 ← findFile files2 "BoolPredicate.idl.json"
  expect (planText == planText2 && idl == idl2)
    "BoolPredicate artifacts must rebuild byte-identically"
  liftResult <| validateIR ir

/-- `assert … else Ident` is outside the envelope (errorId/args non-empty path). -/
private unsafe def testAssertElseRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "AssertElse" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry f(x : UInt64) : UInt64 do\n" ++
    "    assert x > 0 else bad\n" ++
    "    return x\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "  error bad()\n"
  let validated ← liftResult (← session.selectProgramV1
    source "<solana-assert-else>" "Examples.AssertElse" none)
  expectCompileFailure "assert-else" (Compiler.compileValidatedSourceV1 validated)

/-- validatePlan rejects dangling assert operands and post-return assert. -/
private unsafe def testValidatePlanNegatives
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session guardedCounterSourceText
    guardedCounterModuleNameV1 "<solana-plan-negatives>"
  let plan ← liftResult <| planSolana compiled
  let decrement := (← findHandler plan "decrement")
  let danglingAssert := {
    decrement with
    body := #[
      .assert (.param 999),
      .returnValue (.stateLoad 0 8)
    ]
  }
  expectPlanError "dangling assert operand" <|
    validatePlan { plan with entries := plan.entries.set! 0 danglingAssert }
  let afterReturn := {
    decrement with
    body := #[
      .returnValue (.stateLoad 0 8),
      .assert (.compare .ge (.stateLoad 0 8) (.param 8))
    ]
  }
  expectPlanError "assert after return" <|
    validatePlan { plan with entries := plan.entries.set! 0 afterReturn }
  let badAssertError := { plan with assertionFailedError := 0 }
  expectPlanError "forged assertion error policy" <| validatePlan badAssertError
  -- validateIR: out-of-range assert condition / wrong error code.
  let ir ← liftResult <| irSolana compiled
  let decIR ← findHandlerIR ir "decrement"
  let badCondition := {
    decIR with
    operations := decIR.operations.map fun op =>
      match op with
      | .assert _ errorCode => .assert 99 errorCode
      | other => other
  }
  expectPlanError "IR assert condition out of range" <|
    validateIR (withHandlers ir (ir.handlers.set! 1 badCondition))
  let badError := {
    decIR with
    operations := decIR.operations.map fun op =>
      match op with
      | .assert condition _ => .assert condition 0
      | other => other
  }
  expectPlanError "IR assert wrong error code" <|
    validateIR (withHandlers ir (ir.handlers.set! 1 badError))

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testGuardedCounterPlan session
  testGuardedCounterIR session
  testGuardedCounterArtifacts session
  testAllComparisonOps session
  testAssertInAllModes session
  testBoolEnvelopeRejected session
  testBoolResultPositive session
  testBoolPredicateEndToEnd session
  testAssertElseRejected session
  testValidatePlanNegatives session
  IO.println "Tests.Materialization.SolanaPlanV1: ok"

end Tests.Materialization.SolanaPlanV1
