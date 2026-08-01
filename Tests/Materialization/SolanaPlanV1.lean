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
      .store { accountIndex := 0, byteOffset := 8, value := .param 8 },
      .returnNone])
    "initializer Plan body must stay a single param store with the bare-return marker"
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

/-- If/else multi-block program for the Solana region lanes. -/
private def ifFlowSourceText : String := wrapProgram "IfFlow" <|
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    if count > 0 then\n" ++
  "      count := count + delta\n" ++
  "    else\n" ++
  "      count := delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

/-- Multi-block Plan/IR/emitter conformance: branch diamond + regions. -/
private unsafe def testIfFlowRegions
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session ifFlowSourceText
    "Examples.IfFlow" "<solana-if-flow>"
  let plan ← liftResult <| planSolana compiled
  let bump ← findHandler plan "bump"
  expect (bump.mode == .mutate && bump.resultKind == .u64)
    "bump must remain a UInt64 mutate entry"
  expect (bump.body == #[
      .ifThenElse (.compare .gt (.stateLoad 0 8) (.literal 0))
        #[.store {
          accountIndex := 0
          byteOffset := 8
          value := .checkedAdd (.stateLoad 0 8) (.param 8)
        }]
        #[.store { accountIndex := 0, byteOffset := 8, value := .param 8 }],
      .returnValue (.stateLoad 0 8)])
    "IfFlow bump must lower the branch diamond then join return"
  let ir ← liftResult <| irSolana compiled
  let bumpIR ← findHandlerIR ir "bump"
  let regionOps := bumpIR.operations.filter fun op =>
    match op with | .ifRegion .. => true | _ => false
  expect (regionOps.size == 1)
    s!"IfFlow IR must contain exactly one if-region, got {regionOps.size}"
  match bumpIR.operations[3]? with
  | some (Operation.ifRegion cond thenOps elseOps) =>
      expect (cond == 2 && thenOps.size == 4 && elseOps.size == 2)
        s!"IfFlow region: cond temp 2, then 4 ops, else 2 ops; got {cond}/{thenOps.size}/{elseOps.size}"
  | some other =>
      throw <| IO.userError s!"IfFlow: op[3] must be the if-region, got {repr other}"
  | none =>
      throw <| IO.userError "IfFlow: missing if-region op"
  liftResult <| validateIR ir
  let ir2 ← liftResult <| irSolana compiled
  expect (ir == ir2) "IfFlow IR rebuild must be structure-identical"
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "IfFlow.sbpf-plan"
  expect (planText.contains "if %2 {" &&
      planText.contains "} else {" &&
      planText.contains "checked_add_u64" &&
      planText.contains "store_u64_le")
    "sbpf-plan must render the branch if/else with stores in both arms"

/-- No-else if: the absent else falls into the join without an else region. -/
private unsafe def testIfNoElseRegion
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "IfNoElse" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    if count > 0 then\n" ++
    "      count := count + delta\n" ++
    "    return count\n"
  let compiled ← compileSource session text
    "Examples.IfNoElse" "<solana-if-noelse>"
  let plan ← liftResult <| planSolana compiled
  let bump ← findHandler plan "bump"
  expect (bump.body == #[
      .ifThenElse (.compare .gt (.stateLoad 0 8) (.literal 0))
        #[.store {
          accountIndex := 0
          byteOffset := 8
          value := .checkedAdd (.stateLoad 0 8) (.param 8)
        }]
        #[],
      .returnValue (.stateLoad 0 8)])
    "IfNoElse must lower an empty else body and keep the join"
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "IfNoElse.sbpf-plan"
  expect (planText.contains "if %2 {" && planText.contains "} else {")
    "IfNoElse must render the branch if with an empty else"

/-- Both branches return: the if is the final region (no join statement). -/
private unsafe def testIfBothReturnRegion
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "IfBoth" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry pick(delta : UInt64) : UInt64 do\n" ++
    "    if count > 0 then\n" ++
    "      return count\n" ++
    "    else\n" ++
    "      return delta\n"
  let compiled ← compileSource session text
    "Examples.IfBoth" "<solana-if-both>"
  let plan ← liftResult <| planSolana compiled
  let pick ← findHandler plan "pick"
  expect (pick.body == #[
      .ifThenElse (.compare .gt (.stateLoad 0 8) (.literal 0))
        #[.returnValue (.stateLoad 0 8)]
        #[.returnValue (.param 8)]])
    "IfBoth must lower both-returning branches without a join statement"
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir

/-- Nested if: inner diamond inside the then branch. -/
private unsafe def testNestedIfRegions
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "NestedIf" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    if count > 0 then\n" ++
    "      if delta > 0 then\n" ++
    "        count := count + delta\n" ++
    "      else\n" ++
    "        count := 1\n" ++
    "    else\n" ++
    "      count := 2\n" ++
    "    return count\n"
  let compiled ← compileSource session text
    "Examples.NestedIf" "<solana-nested-if>"
  let plan ← liftResult <| planSolana compiled
  let bump ← findHandler plan "bump"
  expect (bump.body == #[
      .ifThenElse (.compare .gt (.stateLoad 0 8) (.literal 0))
        #[.ifThenElse (.compare .gt (.param 8) (.literal 0))
          #[.store {
            accountIndex := 0
            byteOffset := 8
            value := .checkedAdd (.stateLoad 0 8) (.param 8)
          }]
          #[.store { accountIndex := 0, byteOffset := 8, value := .literal 1 }]]
        #[.store { accountIndex := 0, byteOffset := 8, value := .literal 2 }],
      .returnValue (.stateLoad 0 8)])
    "NestedIf must nest the inner diamond inside the then branch"
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "NestedIf.sbpf-plan"
  expect ((planText.splitOn "if %").length == 3)
    s!"NestedIf must render the outer and inner branch ifs, got {(planText.splitOn "if %").length}"

/-- Assert inside a branch: error op inside the region body. -/
private unsafe def testAssertInBranchRegion
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "BranchAssert" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry withdraw(delta : UInt64) : UInt64 do\n" ++
    "    if delta > 0 then\n" ++
    "      assert count >= delta\n" ++
    "      count := count - delta\n" ++
    "    else\n" ++
    "      count := 0\n" ++
    "    return count\n"
  let compiled ← compileSource session text
    "Examples.BranchAssert" "<solana-branch-assert>"
  let plan ← liftResult <| planSolana compiled
  let withdraw ← findHandler plan "withdraw"
  expect (withdraw.body == #[
      .ifThenElse (.compare .gt (.param 8) (.literal 0))
        #[.assert (.compare .ge (.stateLoad 0 8) (.param 8)),
          .store {
            accountIndex := 0
            byteOffset := 8
            value := .checkedSub (.stateLoad 0 8) (.param 8)
          }]
        #[.store { accountIndex := 0, byteOffset := 8, value := .literal 0 }],
      .returnValue (.stateLoad 0 8)])
    "BranchAssert must keep assert-then-store order inside the taken branch"
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "BranchAssert.sbpf-plan"
  expect (planText.contains "assert %" && planText.contains "else program_error 0x1002")
    "sbpf-plan must render the assert error inside the branch"

/-- Match on UInt64 literals: switchRegion with two cases and a wildcard. -/
private unsafe def testMatchUIntLiteralRegions
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "MatchUint" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry apply(delta : UInt64) : UInt64 do\n" ++
    "    match delta with\n" ++
    "    | 0 => do\n" ++
    "      return count\n" ++
    "    | 1 => do\n" ++
    "      count := count + 1\n" ++
    "    | _ => do\n" ++
    "      count := delta\n" ++
    "    return count\n"
  let compiled ← compileSource session text
    "Examples.MatchUint" "<solana-match-uint>"
  let plan ← liftResult <| planSolana compiled
  let apply ← findHandler plan "apply"
  expect (apply.body == #[
      .switchOn (.param 8)
        #[(0, #[.returnValue (.stateLoad 0 8)]),
          (1, #[.store {
            accountIndex := 0
            byteOffset := 8
            value := .checkedAdd (.stateLoad 0 8) (.literal 1)
          }])]
        #[.store { accountIndex := 0, byteOffset := 8, value := .param 8 }],
      .returnValue (.stateLoad 0 8)])
    "MatchUint must lower literal cases to switchOn with a default store"
  let ir ← liftResult <| irSolana compiled
  let applyIR ← findHandlerIR ir "apply"
  let switchOps := applyIR.operations.filter fun op =>
    match op with | .switchRegion .. => true | _ => false
  expect (switchOps.size == 1)
    s!"MatchUint IR must contain exactly one switch-region, got {switchOps.size}"
  liftResult <| validateIR ir
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "MatchUint.sbpf-plan"
  expect (planText.contains "switch %" &&
      planText.contains "case 0 {" &&
      planText.contains "case 1 {" &&
      planText.contains "default {")
    "sbpf-plan must render switch cases and the default region"

/-- Match-bind arm: the binder aliases the scrutinee in the arm body. -/
private unsafe def testMatchBindArmRegion
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "MatchBind" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry apply(delta : UInt64) : UInt64 do\n" ++
    "    match delta with\n" ++
    "    | rest => do\n" ++
    "      count := count + rest\n" ++
    "    return count\n"
  let compiled ← compileSource session text
    "Examples.MatchBind" "<solana-match-bind>"
  let plan ← liftResult <| planSolana compiled
  let apply ← findHandler plan "apply"
  -- Catch-all-only match is straight-line: binder aliases the scrutinee param.
  expect (apply.body == #[
      .store {
        accountIndex := 0
        byteOffset := 8
        value := .checkedAdd (.stateLoad 0 8) (.param 8)
      },
      .returnValue (.stateLoad 0 8)])
    "MatchBind must alias the binder to the scrutinee value without a switch"
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir

/-- Early valued return in the then arm with a trailing join (the mirror
    guard-clause shape): the trailing join folds after the region, and the
    closed arm gains a hard exit after set_return_data. -/
private unsafe def testEarlyReturnJoinRegion
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "EarlyReturn" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry cap(limit : UInt64) : UInt64 do\n" ++
    "    if count > limit then\n" ++
    "      return limit\n" ++
    "    else\n" ++
    "      count := count + 1\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session text
    "Examples.EarlyReturn" "<solana-early-return>"
  let plan ← liftResult <| planSolana compiled
  let cap ← findHandler plan "cap"
  expect (cap.body == #[
      .ifThenElse (.compare .gt (.stateLoad 0 8) (.param 8))
        #[.returnValue (.param 8)]
        #[.store {
          accountIndex := 0
          byteOffset := 8
          value := .checkedAdd (.stateLoad 0 8) (.literal 1)
        }],
      .returnValue (.stateLoad 0 8)])
    "EarlyReturn cap must fold the trailing join return after the region"
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir
  let capIR ← findHandlerIR ir "cap"
  let some region := capIR.operations.find? (fun op => match op with
    | .ifRegion .. => true | _ => false) |
    throw <| IO.userError "EarlyReturn cap IR must contain the if-region"
  match region with
  | .ifRegion _ thenOps _ =>
      expect (thenOps.back? == some .returnNone)
        "EarlyReturn closed arm must gain a hard exit after set_return_data"
  | _ => throw <| IO.userError "EarlyReturn cap IR must contain the if-region"
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "EarlyReturn.sbpf-plan"
  expect (planText.contains "exit")
    "sbpf-plan must render the hard exit for the early-return arm"

/-- An early bare return inside an initializer branch arm fails closed: the
    header-marking epilogue must run on every path. Normalize currently
    rejects explicit bare `return` at the source boundary; the Plan validator
    independently rejects an in-arm bare-return marker. -/
private unsafe def testInitEarlyBareReturnClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "InitEarlyReturn" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    if initial > 0 then\n" ++
    "      return\n" ++
    "    else\n" ++
    "      count := initial\n" ++
    "    count := 0\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  match ← session.selectProgramV1 text "<solana-init-early-return>"
      "Examples.InitEarlyReturn" none with
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
  -- Validator level: an in-arm bare-return marker in the initializer body is
  -- rejected even though a final top-level marker is the canonical shape.
  let compiled ← compileSource session guardedCounterSourceText
    guardedCounterModuleNameV1 "<solana-early-return-plan>"
  let plan ← liftResult <| planSolana compiled
  let initHandler ← findHandler plan "initialize"
  let earlyArm := {
    initHandler with
    body := #[
      .ifThenElse (.compare .ge (.param 8) (.literal 0))
        #[.returnNone]
        #[],
      .store { accountIndex := 0, byteOffset := 8, value := .param 8 },
      .returnNone
    ]
  }
  match validatePlan { plan with initializer := earlyArm } with
  | .error (.planInvariant .solana message) =>
      expect (message.contains "early bare return")
        s!"validatePlan must reject the in-arm bare return, got {message}"
  | .error e =>
      throw <| IO.userError s!"validatePlan must fail with planInvariant, got {e.render}"
  | .ok () => throw <| IO.userError "validatePlan must reject an in-arm bare return"

/-- Declared event/error: emit lowers to an emit_event plan op and revert to
    program_error at the declared-error base, in Plan, typed IR, and the
    sbpf-plan text. -/
private unsafe def testEmitRevertFlow
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "EventFlow" <|
    "  state count : UInt64\n\n" ++
    "  event Moved(src : UInt64, dst : UInt64)\n" ++
    "  error Cap(limit : UInt64)\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    emit Moved(count, delta)\n" ++
    "    if count > delta then\n" ++
    "      revert Cap(delta)\n" ++
    "    else\n" ++
    "      count := count + delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session text
    "Examples.EventFlow" "<solana-event-flow>"
  let plan ← liftResult <| planSolana compiled
  expect (plan.events.map (·.name) == #["Moved"] &&
      plan.events[0]!.fieldCount == 2 &&
      plan.errors.map (·.name) == #["Cap"] &&
      plan.errors[0]!.fieldCount == 1)
    "EventFlow must carry the declared event/error bindings"
  let bump ← findHandler plan "bump"
  expect (bump.body == #[
      .emitEvent 0 #[.stateLoad 0 8, .param 8],
      .ifThenElse (.compare .gt (.stateLoad 0 8) (.param 8))
        #[.revertError 0 #[.param 8]]
        #[.store {
          accountIndex := 0
          byteOffset := 8
          value := .checkedAdd (.stateLoad 0 8) (.param 8)
        }],
      .returnValue (.stateLoad 0 8)])
    "EventFlow bump must lower emit, branch revert, join return"
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir
  let bumpIR ← findHandlerIR ir "bump"
  let emitOps := bumpIR.operations.filter fun op =>
    match op with | .emitEvent .. => true | _ => false
  expect (emitOps.size == 1 && emitOps[0]! == .emitEvent 0 #[0, 1])
    "EventFlow IR must emit event 0 with [load count, param delta]"
  let some region := bumpIR.operations.find? (fun op => match op with
    | .ifRegion .. => true | _ => false) |
    throw <| IO.userError "EventFlow bump IR must contain the if-region"
  match region with
  | .ifRegion _ thenOps _ =>
      expect (thenOps.any (fun op => match op with
        | .revertError 0 _ => true | _ => false))
        "EventFlow then arm must carry the declared revert op"
  | _ => throw <| IO.userError "EventFlow bump IR must contain the if-region"
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "EventFlow.sbpf-plan"
  expect (planText.contains "emit_event Moved")
    "sbpf-plan must render the named event emission"
  expect (planText.contains s!"program_error 0x{Nat.toDigits 16 (Targets.Solana.declaredErrorBase + 0) |> String.ofList}")
    "sbpf-plan must render the declared-error program_error code"
  let idl ← findFile files "EventFlow.idl.json"
  expect (idl.contains "\"events\": [{\"name\":\"Moved\"" &&
      idl.contains "\"errors\": [{\"name\":\"Cap\"")
    "EventFlow IDL must declare the Moved event and Cap error"

/-- validatePlan/validateIR negatives for the new region constructors. -/
private unsafe def testRegionValidationNegatives
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session ifFlowSourceText
    "Examples.IfFlow" "<solana-neg-region>"
  let base ← liftResult <| planSolana compiled
  match validatePlan base with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"base region plan must validate: {e.render}"
  -- Store inside a view branch is rejected.
  let viewStore := { base with entries := base.entries.map fun e =>
    if e.name == "bump" then
      { e with
          mode := .view
          body := #[
            .ifThenElse (.compare .gt (.stateLoad 0 8) (.literal 0))
              #[.store { accountIndex := 0, byteOffset := 8, value := .literal 1 }]
              #[],
            .returnValue (.stateLoad 0 8)] }
    else e }
  match validatePlan viewStore with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject a store inside a view branch"
  -- Statement after a both-returning branch at the same level.
  let afterReturn := { base with entries := base.entries.map fun e =>
    if e.name == "bump" then
      { e with body := #[
          .ifThenElse (.compare .gt (.stateLoad 0 8) (.literal 0))
            #[.returnValue (.stateLoad 0 8)] #[.returnValue (.literal 0)],
          .store { accountIndex := 0, byteOffset := 8, value := .literal 1 }] }
    else e }
  match validatePlan afterReturn with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject a statement after a both-returning branch"

/-- Wave E: pureFn + localCall → Plan.fns / Expr.callFn / Operation.callFn. -/
private unsafe def testFnLocalCall
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "FnCall" <|
    "  state count : UInt64\n\n" ++
    "  fn double(x : UInt64) : UInt64 do\n" ++
    "    return x + x\n\n" ++
    "  fn quadruple(x : UInt64) : UInt64 do\n" ++
    "    return double(double(x))\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := double(i)\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    count := count + double(delta)\n" ++
    "    return quadruple(count)\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return double(count)\n"
  let compiled ← compileSource session text
    "Examples.FnCall" "<solana-fn-local-call>"
  let plan ← liftResult <| planSolana compiled
  expect (plan.fns.size == 2)
    s!"FnCall must carry two pureFns, got {plan.fns.size}"
  expect (plan.fns[0]!.name == "double" && plan.fns[0]!.params.size == 1 &&
      !plan.fns[0]!.resultIsBool &&
      plan.fns[0]!.body == #[
        .returnValue (.checkedAdd (.param 8) (.param 8))])
    "double fn Plan: name/params/UInt64 result + return x+x"
  expect (plan.fns[1]!.name == "quadruple" && plan.fns[1]!.params.size == 1 &&
      !plan.fns[1]!.resultIsBool &&
      plan.fns[1]!.body == #[
        .returnValue (.callFn 0 #[.callFn 0 #[.param 8]])])
    "quadruple fn Plan: nested callFn double(double(x))"
  let initHandler ← findHandler plan "initialize"
  expect (initHandler.body == #[
      .store {
        accountIndex := 0
        byteOffset := 8
        value := .callFn 0 #[.param 8]
      },
      .returnNone])
    "init must store double(i)"
  let bump ← findHandler plan "bump"
  expect (bump.body == #[
      .store {
        accountIndex := 0
        byteOffset := 8
        value := .checkedAdd (.stateLoad 0 8) (.callFn 0 #[.param 8])
      },
      .returnValue (.callFn 1 #[.stateLoad 0 8])])
    "bump must store count+double(delta) and return quadruple(count)"
  let getHandler ← findHandler plan "get"
  expect (getHandler.body == #[.returnValue (.callFn 0 #[.stateLoad 0 8])])
    "get must return double(count)"
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir
  expect (ir.fns.size == 2 && ir.fns[0]!.name == "double" && ir.fns[1]!.name == "quadruple")
    "IR must lower both pureFn bodies"
  let overflow := plan.arithmeticOverflowError
  expect (ir.fns[0]!.operations == #[
      .loadParam 0 8,
      .loadParam 1 8,
      .checkedAdd 2 0 1 overflow,
      .setReturnData 2])
    "double IR: load x twice, checkedAdd, setReturnData (rendered as ret)"
  expect (ir.fns[1]!.operations == #[
      .loadParam 0 8,
      .callFn 0 1 #[0],
      .callFn 0 2 #[1],
      .setReturnData 2])
    "quadruple IR: two callFn double with dense destinations"
  let bumpIR ← findHandlerIR ir "bump"
  expect (bumpIR.operations == #[
      .loadState 0 0 8,
      .loadParam 1 8,
      .callFn 0 2 #[1],
      .checkedAdd 3 0 2 overflow,
      .storeState 0 8 3,
      .loadState 4 0 8,
      .callFn 1 5 #[4],
      .setReturnData 5])
    "bump IR must call double then quadruple with dense temps"
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "FnCall.sbpf-plan"
  expect (planText.contains ".fn 0 double (-> u64)" &&
      planText.contains ".fn 1 quadruple (-> u64)" &&
      planText.contains "ret %2" &&
      planText.contains "call double" &&
      planText.contains "call quadruple")
    "sbpf-plan must render .fn sections, ret, and call sites"
  expect (planText.contains "%5 = call quadruple %4" ||
      planText.contains "call quadruple")
    "sbpf-plan must render the quadruple call site"
  let idl ← findFile files "FnCall.idl.json"
  expect (idl.contains "\"fns\": [" &&
      idl.contains "\"name\":\"double\"" &&
      idl.contains "\"name\":\"quadruple\"" &&
      idl.contains "\"argCount\":1" &&
      idl.contains "\"result\":\"u64\"")
    "IDL must declare the fns array with name/argCount/result"
  -- Hand-crafted negative: callFn with out-of-range fnIndex fails validatePlan.
  let badBump := {
    bump with
    body := #[
      .returnValue (.callFn 99 #[.param 8])
    ]
  }
  expectPlanError "callFn fnIndex out of range" <|
    validatePlan { plan with entries := plan.entries.map fun e =>
      if e.name == "bump" then badBump else e }
  -- Hand-crafted IR negative: callFn with out-of-range index fails validateIR.
  let badOps := bumpIR.operations.map fun op =>
    match op with
    | .callFn _ dest args => .callFn 99 dest args
    | other => other
  expectPlanError "IR callFn fnIndex out of range" <|
    validateIR (withHandlers ir (ir.handlers.map fun h =>
      if h.name == "bump" then { h with operations := badOps } else h))
  let ir2 ← liftResult <| irSolana compiled
  expect (ir == ir2) "FnCall IR rebuild must be structure-identical"

/-- Wave F: mul/div/mod + unary bitNot/boolNot Plan/IR/render pins. -/
private unsafe def testArithOps
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "ArithOps" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry scale(factor : UInt64, divisor : UInt64) : UInt64 do\n" ++
    "    count := count * factor / divisor + count % divisor\n" ++
    "    return count\n\n" ++
    "  entry bits(x : UInt64) : UInt64 do\n" ++
    "    return ~x\n\n" ++
    "  entry neg5(x : UInt64) : Bool do\n" ++
    "    return !(x > 5)\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session source "Examples.ArithOps" "<solana-arith-ops>"
  let plan ← liftResult <| planSolana compiled
  let overflow := plan.arithmeticOverflowError
  -- Plan exprs: scale store is ((count * factor) / divisor) + (count % divisor).
  let scale ← findHandler plan "scale"
  expect (scale.body == #[
      .store {
        accountIndex := 0
        byteOffset := 8
        value := .checkedAdd
          (.checkedDiv
            (.checkedMul (.stateLoad 0 8) (.param 8))
            (.param 16))
          (.checkedMod (.stateLoad 0 8) (.param 16))
      },
      .returnValue (.stateLoad 0 8)])
    "scale Plan body must lower mul/div/mod into checked expr tree + return load"
  let bits ← findHandler plan "bits"
  expect (bits.body == #[.returnValue (.bitNot (.param 8))])
    "bits Plan body must be return bitNot(param)"
  let neg5 ← findHandler plan "neg5"
  expect (neg5.resultKind == .bool &&
      neg5.body == #[.returnValue (.boolNot (.compare .gt (.param 8) (.literal 5)))])
    "neg5 Plan body must be return boolNot(gt(param, 5))"
  -- IR dense temps for scale.
  let ir ← liftResult <| irSolana compiled
  let scaleIR ← findHandlerIR ir "scale"
  expect (scaleIR.operations == #[
      .loadState 0 0 8,
      .loadParam 1 8,
      .checkedMul 2 0 1 overflow,
      .loadParam 3 16,
      .checkedDiv 4 2 3 overflow,
      .loadState 5 0 8,
      .loadParam 6 16,
      .checkedMod 7 5 6 overflow,
      .checkedAdd 8 4 7 overflow,
      .storeState 0 8 8,
      .loadState 9 0 8,
      .setReturnData 9])
    "scale IR must lower mul/div/mod/add with dense temp numbering"
  let bitsIR ← findHandlerIR ir "bits"
  expect (bitsIR.operations == #[
      .loadParam 0 8,
      .bitNot 1 0,
      .setReturnData 1])
    "bits IR must lower bitNot with dense temps"
  let neg5IR ← findHandlerIR ir "neg5"
  expect (neg5IR.operations == #[
      .loadParam 0 8,
      .literal 1 5,
      .compare 2 0 1 .gt,
      .boolNot 3 2,
      .setReturnDataBool 3])
    "neg5 IR must lower compare then boolNot into Bool return"
  liftResult <| validateIR ir
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "ArithOps.sbpf-plan"
  for fragment in #["checked_mul_u64", "checked_div_u64", "checked_rem_u64",
      "bitnot_u64", "bool_not"] do
    expect (planText.contains fragment)
      s!"sbpf-plan must contain '{fragment}'"
  let ir2 ← liftResult <| irSolana compiled
  expect (ir == ir2) "ArithOps IR rebuild must be structure-identical"

/-- Bounded for-loops: pre-header/header/body/exit CFG recovered as Plan
    `forLoop` with induction temp, init/cond/update/maxIterations, and body
    stores. Zero-trip and over-bound entries lower; plan-text pins
    `loop_u64` plus back-edge counter/bound-check (`0x1003`). -/
private unsafe def testForLoop
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "ForLoop" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry addUp(n : UInt64) : UInt64 do\n" ++
    "    let limit : UInt64 := n + 4\n" ++
    "    for i in n ..< limit bounded 8 do\n" ++
    "      count := count + i\n" ++
    "    return count\n\n" ++
    "  entry scan(n : UInt64) : UInt64 do\n" ++
    "    for i in n ..< n bounded 2 do\n" ++
    "      count := count + 1\n" ++
    "    return count\n\n" ++
    "  entry addUpTight(n : UInt64) : UInt64 do\n" ++
    "    for i in n ..< n + 4 bounded 3 do\n" ++
    "      count := count + i\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session source "Examples.ForLoop" "<solana-for-loop>"
  let plan ← liftResult <| planSolana compiled
  expect (plan.loopBoundExceededError == loopBoundExceededError)
    "Plan must carry the canonical loopBoundExceededError policy code"
  let addUp ← findHandler plan "addUp"
  -- Plan body: forLoop(varTemp=1, init=param n, cond=i<limit, update=i+1,
  -- max=8, body=store count+i) then return count.
  expect (addUp.body == #[
      .forLoop 1
        (.param 8)
        (.compare .lt (.temp 1) (.checkedAdd (.param 8) (.literal 4)))
        (.checkedAdd (.temp 1) (.literal 1))
        8
        #[.store {
          accountIndex := 0
          byteOffset := 8
          value := .checkedAdd (.stateLoad 0 8) (.temp 1)
        }],
      .returnValue (.stateLoad 0 8)])
    "addUp Plan body must recover forLoop with init/cond/update/max and body store"
  let scan ← findHandler plan "scan"
  -- Zero-trip still lowers: cond is i < n with i seeded from n.
  expect (scan.body == #[
      .forLoop 1
        (.param 8)
        (.compare .lt (.temp 1) (.param 8))
        (.checkedAdd (.temp 1) (.literal 1))
        2
        #[.store {
          accountIndex := 0
          byteOffset := 8
          value := .checkedAdd (.stateLoad 0 8) (.literal 1)
        }],
      .returnValue (.stateLoad 0 8)])
    "scan Plan body must lower zero-trip forLoop (n ..< n)"
  let addUpTight ← findHandler plan "addUpTight"
  -- Over-bound: range length 4 with bound 3 — still lowers; runtime must
  -- hit loopBoundExceededError after the 4th body at the back edge.
  expect (addUpTight.body == #[
      .forLoop 1
        (.param 8)
        (.compare .lt (.temp 1) (.checkedAdd (.param 8) (.literal 4)))
        (.checkedAdd (.temp 1) (.literal 1))
        3
        #[.store {
          accountIndex := 0
          byteOffset := 8
          value := .checkedAdd (.stateLoad 0 8) (.temp 1)
        }],
      .returnValue (.stateLoad 0 8)])
    "addUpTight Plan body must pin maxIterations=3 for the over-bound entry"
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir
  let addUpIR ← findHandlerIR ir "addUp"
  let loopOps := addUpIR.operations.filter fun op =>
    match op with | .forRegion .. => true | _ => false
  expect (loopOps.size == 1)
    s!"addUp IR must contain exactly one for-region, got {loopOps.size}"
  match loopOps[0]? with
  | some (Operation.forRegion _ _ _ maxIt _ _ _ boundOps _ _ _) =>
      expect (maxIt == 8)
        s!"addUp for-region maxIterations must be 8, got {maxIt}"
      expect (boundOps.size == 6)
        s!"addUp boundOps must be the 6-op back-edge check, got {boundOps.size}"
  | some other =>
      throw <| IO.userError s!"addUp: expected forRegion, got {repr other}"
  | none => throw <| IO.userError "addUp: missing for-region"
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "ForLoop.sbpf-plan"
  for fragment in #["loop_u64", "counter=%", "max=8", "max=3", "cond {",
      "body {", "bound {", "update {", "cmp_lt_u64", "cmp_eq_u64",
      "checked_add_u64", "program_error 0x1003"] do
    expect (planText.contains fragment)
      s!"sbpf-plan must contain '{fragment}'"
  let ir2 ← liftResult <| irSolana compiled
  expect (ir == ir2) "ForLoop IR rebuild must be structure-identical"

/-- Shift / bitwise / strict logical binaries: UInt64 masks, guarded shifts
    (count ≥ 64 → 0x1004 invalidShift; shl overflow → 0x1001), Bool
    `bool_and`/`bool_or` with both sides always evaluated, and computed UInt32
    shift counts (e.g. `x >> (32 + 32)` — the only way invalidShift is reachable
    at runtime because CheckV1 rejects literal counts ≥ 64). -/
private unsafe def testShiftBitwiseLogical
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "BitLogic" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry shiftMask(x : UInt64) : UInt64 do\n" ++
    "    count := (x << 2) & 15 | (x >> 1) ^ 3\n" ++
    "    return count\n\n" ++
    "  entry both(a : UInt64, b : UInt64) : Bool do\n" ++
    "    return a > 0 && b > 0\n\n" ++
    "  entry strictOr(a : UInt64, b : UInt64) : Bool do\n" ++
    "    let one : UInt64 := 1\n" ++
    "    return a > 0 || (one / b) == one\n\n" ++
    "  entry bigShift(x : UInt64) : UInt64 do\n" ++
    "    return x >> (32 + 32)\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session source "Examples.BitLogic" "<solana-bit-logic>"
  let plan ← liftResult <| planSolana compiled
  expect (plan.invalidShiftError == invalidShiftError)
    "Plan must carry the canonical invalidShiftError policy code"
  let shiftMask ← findHandler plan "shiftMask"
  -- Precedence: & > ^ > | so
  --   ((x << 2) & 15) | ((x >> 1) ^ 3)
  expect (shiftMask.body == #[
      .store {
        accountIndex := 0
        byteOffset := 8
        value := .bitOr
          (.bitAnd
            (.shl (.param 8) (.literal 2))
            (.literal 15))
          (.bitXor
            (.shr (.param 8) (.literal 1))
            (.literal 3))
      },
      .returnValue (.stateLoad 0 8)])
    "shiftMask Plan body must nest shl/bitAnd | shr/bitXor with store + return"
  let both ← findHandler plan "both"
  expect (both.resultKind == .bool &&
      both.body == #[
        .returnValue (.boolAnd
          (.compare .gt (.param 8) (.literal 0))
          (.compare .gt (.param 16) (.literal 0)))])
    "both Plan body must be return boolAnd(gt(a,0), gt(b,0))"
  let strictOr ← findHandler plan "strictOr"
  -- Strict: both sides evaluate; rhs is eq(div(1,b), 1).
  expect (strictOr.resultKind == .bool &&
      strictOr.body == #[
        .returnValue (.boolOr
          (.compare .gt (.param 8) (.literal 0))
          (.compare .eq
            (.checkedDiv (.literal 1) (.param 16))
            (.literal 1)))])
    "strictOr Plan body must be return boolOr(gt(a,0), eq(div(1,b), 1))"
  let bigShift ← findHandler plan "bigShift"
  -- Computed UInt32 count: (32 + 32) lowers as narrowCheckedAdd 32 (T8a body
  -- multi-width); UInt64 shr constructor is unchanged.
  expect (bigShift.body == #[
      .returnValue (.shr (.param 8)
        (.narrowCheckedAdd 32 (.literal 32) (.literal 32)))])
    "bigShift Plan body must be return shr(param, narrowCheckedAdd 32 (32, 32))"
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir
  let shiftMaskIR ← findHandlerIR ir "shiftMask"
  let overflow := plan.arithmeticOverflowError
  let shiftErr := plan.invalidShiftError
  -- Dense temps: load x, lit 2, shl, lit 15, bitAnd, load x, lit 1, shr,
  -- lit 3, bitXor, bitOr, store, load count, set_return_data.
  expect (shiftMaskIR.operations == #[
      .loadParam 0 8,
      .literal 1 2,
      .checkedShl 2 0 1 shiftErr overflow,
      .literal 3 15,
      .bitAnd 4 2 3,
      .loadParam 5 8,
      .literal 6 1,
      .checkedShr 7 5 6 shiftErr,
      .literal 8 3,
      .bitXor 9 7 8,
      .bitOr 10 4 9,
      .storeState 0 8 10,
      .loadState 11 0 8,
      .setReturnData 11])
    "shiftMask IR must lower shifts/bitwise with dense temps and dual shift guards"
  let strictOrIR ← findHandlerIR ir "strictOr"
  expect (strictOrIR.operations == #[
      .loadParam 0 8,
      .literal 1 0,
      .compare 2 0 1 .gt,
      .literal 3 1,
      .loadParam 4 16,
      .checkedDiv 5 3 4 overflow,
      .literal 6 1,
      .compare 7 5 6 .eq,
      .boolOr 8 2 7,
      .setReturnDataBool 8])
    "strictOr IR must evaluate both sides then boolOr into Bool return"
  let bigShiftIR ← findHandlerIR ir "bigShift"
  expect (bigShiftIR.operations == #[
      .loadParam 0 8,
      .literal 1 32,
      .literal 2 32,
      .narrowCheckedAdd 32 3 1 2 overflow,
      .checkedShr 4 0 3 shiftErr,
      .setReturnData 4])
    "bigShift IR must lower UInt32 count narrowCheckedAdd then checkedShr with invalidShift"
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "BitLogic.sbpf-plan"
  for fragment in #["bitand_u64", "bitor_u64", "bitxor_u64",
      "shl_u64", "shr_u64", "bool_and", "bool_or",
      "program_error 0x1004", "program_error 0x1001",
      "checked_add_u32"] do
    expect (planText.contains fragment)
      s!"sbpf-plan must contain '{fragment}'"
  -- Dual-else form for shl: invalidShift then arithmeticOverflow.
  expect (planText.contains
      "shl_u64 %0, %1 else program_error 0x1004 else program_error 0x1001")
    "sbpf-plan must render shl with dual program_error guards"
  expect (planText.contains "shr_u64 %5, %6 else program_error 0x1004")
    "sbpf-plan must render shr with invalidShift guard"
  -- Computed-count shift: UInt32 add then u64 shr; count ≥ 64 → 0x1004.
  expect (planText.contains "shr_u64 %0, %3 else program_error 0x1004")
    "sbpf-plan bigShift must render shr with invalidShift on the computed count"
  let ir2 ← liftResult <| irSolana compiled
  expect (ir == ir2) "BitLogic IR rebuild must be structure-identical"

/-- Wave I: Solana declines external call and workflow schedule at the S2
    requirement resolver (no address-bearing type for CPI program ids in the
    UInt64 envelope). Compile succeeds; build selection succeeds; capability
    resolve fails closed with PF-REQ-UNSUPPORTED before any Solana lowering.
    Defensive planInvariant arms in `lowerBlockInstructionsV1` cover hand-built
    Semantic carriers, but the product path never reaches them for these ops. -/
private unsafe def testExternalCallGate
    (session : Language.Loader.ParserSession) : IO Unit := do
  let callText := wrapProgram "CallGate" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    call Oracle.feed(count)\n" ++
    "    count := count + delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let callCompiled ← compileSource session callText
    "Examples.CallGate" "<solana-call-gate>"
  let callSelection ← liftResult <| resolveBuildSelectionV1 TargetId.solana none
  match Targets.resolveEngineeringRequirementsV1 callSelection callCompiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"call gate: expected PF-REQ-UNSUPPORTED, got {e.render}"
      expect (e.render.startsWith "PF-REQ-UNSUPPORTED:")
        s!"call gate: PF-REQ-UNSUPPORTED rendering must be code-prefixed, got {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "call gate: Solana must reject effect.synchronous-call at resolveEngineeringRequirementsV1"

  let scheduleText := wrapProgram "ScheduleGate" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry later(delta : UInt64) : UInt64 do\n" ++
    "    schedule Ledger.daily(count)\n" ++
    "    count := count + delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let scheduleCompiled ← compileSource session scheduleText
    "Examples.ScheduleGate" "<solana-schedule-gate>"
  let scheduleSelection ← liftResult <| resolveBuildSelectionV1 TargetId.solana none
  match Targets.resolveEngineeringRequirementsV1 scheduleSelection scheduleCompiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"schedule gate: expected PF-REQ-UNSUPPORTED, got {e.render}"
      expect (e.render.startsWith "PF-REQ-UNSUPPORTED:")
        s!"schedule gate: PF-REQ-UNSUPPORTED rendering must be code-prefixed, got {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "schedule gate: Solana must reject effect.asynchronous-workflow at resolveEngineeringRequirementsV1"

/-- Unit/void entry (`entry run() do`) fails closed at makeEntryV1. -/
private unsafe def testVoidEntryRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "VoidEntry" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry run() do\n" ++
    "    count := count + 1\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  match ← session.selectProgramV1 text "<solana-void-entry>" "Examples.VoidEntry" none with
  | .error e => throw <| IO.userError s!"void entry load: {e.render}"
  | .ok source =>
      match Compiler.compileValidatedSourceV1 source with
      | .error e =>
          expect (e.render.contains "return" || e.render.contains "Unit" ||
              e.render.contains "unsupported" || e.render.contains "PF-SRC-INVALID")
            s!"void entry compile failure must mention return/Unit/unsupported, got {e.render}"
      | .ok compiled =>
          match planSolana compiled with
          | .error (.planInvariant .solana msg) =>
              expect (msg.contains "run" &&
                  msg.contains "does not return public UInt64 or Bool")
                s!"void entry planInvariant must match makeEntryV1, got: {msg}"
          | .error e =>
              throw <| IO.userError
                s!"void entry must fail with planInvariant .solana, got {e.render}"
          | .ok _ =>
              throw <| IO.userError "void entry must not produce a Solana plan"

/-- Two declared events emitted in one entry: pin emit_event plan/IDL. -/
private unsafe def testMultipleEvents
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "MultiEvent" <|
    "  state count : UInt64\n\n" ++
    "  event A(x : UInt64)\n" ++
    "  event B(x : UInt64, y : UInt64)\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry go(x : UInt64) : UInt64 do\n" ++
    "    emit A(x)\n" ++
    "    emit B(count, x)\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session text
    "Examples.MultiEvent" "<solana-multi-event>"
  let plan ← liftResult <| planSolana compiled
  expect (plan.events.map (·.name) == #["A", "B"] &&
      plan.events[0]!.fieldCount == 1 &&
      plan.events[1]!.fieldCount == 2)
    "MultiEvent must carry A(1 field) then B(2 fields)"
  let go ← findHandler plan "go"
  expect (go.body == #[
      .emitEvent 0 #[.param 8],
      .emitEvent 1 #[.stateLoad 0 8, .param 8],
      .returnValue (.stateLoad 0 8)])
    "MultiEvent go must emit A then B then return count"
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir
  let goIR ← findHandlerIR ir "go"
  let emitOps := goIR.operations.filter fun op =>
    match op with | .emitEvent .. => true | _ => false
  expect (emitOps.size == 2)
    s!"MultiEvent IR must emit both events, got {emitOps.size}"
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "MultiEvent.sbpf-plan"
  expect (planText.contains "emit_event A" && planText.contains "emit_event B")
    "sbpf-plan must render both named event emissions"
  let headA := (planText.splitOn "emit_event A").head?.getD ""
  let headB := (planText.splitOn "emit_event B").head?.getD ""
  expect (headA.length < headB.length)
    "sbpf-plan must emit event A before event B"
  let idl ← findFile files "MultiEvent.idl.json"
  expect (idl.contains "\"name\":\"A\"" && idl.contains "\"name\":\"B\"" &&
      idl.contains "\"events\":")
    "MultiEvent IDL must declare both events"

/-- Zero-field error + bare `revert E` → program_error at declared base. -/
private unsafe def testZeroArgRevert
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "ZeroRev" <|
    "  state count : UInt64\n\n" ++
    "  error E()\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry go(x : UInt64) : UInt64 do\n" ++
    "    if x == 0 then\n" ++
    "      revert E\n" ++
    "    else\n" ++
    "      count := count + x\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session text
    "Examples.ZeroRev" "<solana-zero-rev>"
  let plan ← liftResult <| planSolana compiled
  expect (plan.errors.map (·.name) == #["E"] && plan.errors[0]!.fieldCount == 0)
    "ZeroRev must carry zero-field error E"
  let go ← findHandler plan "go"
  expect (go.body == #[
      .ifThenElse (.compare .eq (.param 8) (.literal 0))
        #[.revertError 0 #[]]
        #[.store {
          accountIndex := 0
          byteOffset := 8
          value := .checkedAdd (.stateLoad 0 8) (.param 8)
        }],
      .returnValue (.stateLoad 0 8)])
    "ZeroRev go must branch to bare revertError 0 with empty args"
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "ZeroRev.sbpf-plan"
  let errCode :=
    String.ofList (Nat.toDigits 16 (Targets.Solana.declaredErrorBase + 0))
  expect (planText.contains s!"program_error 0x{errCode}" &&
      planText.contains "E()")
    s!"sbpf-plan must render zero-arg program_error 0x{errCode} ; E()"
  let idl ← findFile files "ZeroRev.idl.json"
  expect (idl.contains "\"name\":\"E\"" && idl.contains "\"errors\":")
    "ZeroRev IDL must declare error E"

/-- Bool-result pureFn called from a Bool entry: pin resultIsBool + ret path. -/
private unsafe def testBoolResultPureFn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "BoolFn" <|
    "  state count : UInt64\n\n" ++
    "  fn flag(a : UInt64) : Bool do\n" ++
    "    return a > 0\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry check(x : UInt64) : Bool do\n" ++
    "    return flag(x)\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session text
    "Examples.BoolFn" "<solana-bool-fn>"
  let plan ← liftResult <| planSolana compiled
  expect (plan.fns.size == 1 && plan.fns[0]!.name == "flag" &&
      plan.fns[0]!.resultIsBool)
    "BoolFn must lower flag with resultIsBool"
  expect (plan.fns[0]!.body == #[
      .returnValue (.compare .gt (.param 8) (.literal 0))])
    "flag body must return a > 0"
  let check ← findHandler plan "check"
  expect (check.resultKind == .bool &&
      check.body == #[.returnValue (.callFn 0 #[.param 8])])
    "check must return flag(x) as Bool callFn"
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir
  expect (ir.fns.size == 1 && ir.fns[0]!.resultIsBool)
    "IR flag must carry resultIsBool"
  expect (ir.fns[0]!.operations.any fun op =>
      match op with | .setReturnDataBool _ => true | _ => false)
    "Bool pureFn IR must use setReturnDataBool"
  let checkIR ← findHandlerIR ir "check"
  expect (checkIR.operations.any fun op =>
      match op with | .setReturnDataBool _ => true | _ => false)
    "check handler IR must set_return_data_bool"
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "BoolFn.sbpf-plan"
  expect (planText.contains ".fn 0 flag (-> bool)" &&
      planText.contains "ret %" &&
      planText.contains "call flag" &&
      planText.contains "set_return_data_bool")
    "sbpf-plan must render Bool fn section, ret, call, and set_return_data_bool"
  let idl ← findFile files "BoolFn.idl.json"
  expect (idl.contains "\"name\":\"flag\"" &&
      idl.contains "\"result\":\"bool\"" &&
      idl.contains "\"name\":\"check\"" &&
      idl.contains "\"returns\":\"bool\"")
    "IDL must declare flag result bool and check returns bool"

/-- Omitted-type `let x := a + b` still lowers to checkedAdd. -/
private unsafe def testOmittedTypeLet
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "LetOmit" <|
    "  state seed : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    seed := i\n\n" ++
    "  entry sum(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    let x := a + b\n" ++
    "    return x\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return seed\n"
  let compiled ← compileSource session text
    "Examples.LetOmit" "<solana-let-omit>"
  let plan ← liftResult <| planSolana compiled
  let sum ← findHandler plan "sum"
  expect (sum.body == #[
      .returnValue (.checkedAdd (.param 8) (.param 16))])
    "omitted-type let must lower to checkedAdd of both params"
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "LetOmit.sbpf-plan"
  expect (planText.contains "checked_add_u64")
    "sbpf-plan must render checked_add_u64 for the omitted-type let"


/-- Isolated mod-by-zero: a dedicated `%` entry pins checked_rem_u64 with its
    error branch in the sbpf plan. -/
private unsafe def testIsolatedModZero
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text := wrapProgram "ModOnly" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry rem(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return a % b\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session text
    "Examples.ModOnly" "<solana-mod-only>"
  let plan ← liftResult <| planSolana compiled
  let rem ← findHandler plan "rem"
  let remMods := rem.body.filter fun s =>
    match s with | .returnValue (.checkedMod ..) => true | _ => false
  expect (remMods.size == 1)
    "mod-only: rem must return a checkedMod"
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "ModOnly.sbpf-plan"
  expect (planText.contains "checked_rem_u64")
    "sbpf-plan must emit checked_rem_u64 for the isolated mod"
  expect (planText.contains "else program_error")
    "checked_rem_u64 must carry the fail-closed error branch"

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
  testIfFlowRegions session
  testIfNoElseRegion session
  testIfBothReturnRegion session
  testNestedIfRegions session
  testAssertInBranchRegion session
  testMatchUIntLiteralRegions session
  testMatchBindArmRegion session
  testEarlyReturnJoinRegion session
  testInitEarlyBareReturnClosed session
  testEmitRevertFlow session
  testRegionValidationNegatives session
  testAssertElseRejected session
  testValidatePlanNegatives session
  testFnLocalCall session
  testArithOps session
  testForLoop session
  testShiftBitwiseLogical session
  testExternalCallGate session
  testVoidEntryRejected session
  testMultipleEvents session
  testIsolatedModZero session
  testZeroArgRevert session
  testBoolResultPureFn session
  testOmittedTypeLet session
  IO.println "Tests.Materialization.SolanaPlanV1: ok"

end Tests.Materialization.SolanaPlanV1
