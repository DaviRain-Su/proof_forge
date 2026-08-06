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


private def expectUnsupportedRequirement (label requirementId : String)
    (result : CompileResult α) : IO Unit :=
  match result with
  | .error error =>
      expect (error.code == "PF-REQ-UNSUPPORTED" &&
          error.message.contains requirementId)
        s!"{label}: expected PF-REQ-UNSUPPORTED for {requirementId}, got {error.render}"
  | .ok _ =>
      throw <| IO.userError s!"{label}: expected unsupported requirement {requirementId}"


private def expectCompileFailure (label : String) (result : CompileResult α) : IO Unit :=
  match result with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError s!"{label}: expected compile failure"

private unsafe def compileSource (session : Language.Loader.ParserSession)
    (source moduleName path : String) : IO CompiledSemanticV1 := do
  let validated ← liftResult (← session.selectProgramV1 source path moduleName none)
  liftResult <| Compiler.compileValidatedSourceV1 validated

private def solanaCapability (compiled : CompiledSemanticV1)
    (profile? : Option CodegenProfileId := none) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.solana profile?
  Targets.resolveEngineeringRequirementsV1 selection compiled

/-- Legacy-only helper: unwraps `planFromCapability` `.legacy` carrier.
    Fails the CompileResult if the CPI branch is returned (test theater guard). -/
private def planSolana (compiled : CompiledSemanticV1) : CompileResult Plan := do
  let capability ← solanaCapability compiled
  match ← planFromCapability capability with
  | .legacy plan => pure plan
  | .cpi _ =>
      throw <| .planInvariant .solana
        "test helper planSolana: expected .legacy Plan, got .cpi"

/-- Legacy-only helper: unwraps `irFromCapability` `.legacy` carrier. -/
private def irSolana (compiled : CompiledSemanticV1) : CompileResult IR := do
  let capability ← solanaCapability compiled
  match ← irFromCapability capability with
  | .legacy ir => pure ir
  | .cpi _ =>
      throw <| .planInvariant .solana
        "test helper irSolana: expected .legacy IR, got .cpi"

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
      .loadState 0 0 8,
      .loadParam 1 8,
      .checkedSub 2 0 1 overflow,
      .storeState 0 8 2,
      .loadState 0 0 8,
      .setReturnData 8 0])
    "decrement IR must lower compare/assert then checked-sub store with recycled temps"
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
  -- (4 ops; 3 temps: a, b, compare-result). Temps are recycled after each
  -- consuming assert, so every segment reuses temps 0/1/2.
  for i in [:6] do
    let opBase := i * 4
    expect (checkIR.operations[opBase]? == some (.loadParam 0 8))
      s!"IR [{opBase}] load param a → %0"
    expect (checkIR.operations[opBase + 1]? == some (.loadParam 1 16))
      s!"IR [{opBase}+1] load param b → %1"
    expect (checkIR.operations[opBase + 2]? ==
        some (.compare 2 0 1 expectedOps[i]!))
      s!"IR [{opBase}+2] compare {repr (expectedOps[i]!)} → %2"
    expect (checkIR.operations[opBase + 3]? == some (.assert 2 assertErr))
      s!"IR [{opBase}+3] assert %2"
  expect (checkIR.operations[24]? == some (.loadParam 0 8) &&
      checkIR.operations[25]? == some (.setReturnData 8 0))
    "after six assert segments, return must reload param a into %0 (recycled)"
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
  let planCapSum ← liftResult <| planFromCapability capability
  let planCap ← match planCapSum with
    | .legacy p => pure p
    | .cpi _ =>
        throw <| IO.userError
          "bool-predicate: planFromCapability must return .legacy for default profile"
  expect (plan == planCap) "planFromCapability .legacy must match planSolana helper"
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
  let irSum ← liftResult <| irFromCapability capability
  let ir ← match irSum with
    | .legacy i => pure i
    | .cpi _ =>
        throw <| IO.userError
          "bool-predicate: irFromCapability must return .legacy for default profile"
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
    | .setReturnData _ _ => sawU64Return := true
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

/-- `assert … else Ident` (zero-arg declared error): L1 lowers it through the
    shared core to `Op.Assert cond (some eid) #[]`; the Solana target-owned
    Plan keeps fail-closed on `errorId=some` (it only materializes bare asserts
    with `errorId=none`). Confirm the product path still fails closed at the
    Solana plan boundary and produces no artifacts. -/
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
  -- Shared core (Normalize/TypeCheck) now lowers zero-arg assert-else.
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 validated
  -- Solana plan keeps fail-closed on errorId=some (target-owned behavior).
  expectPlanError "assert-else" (planSolana compiled)

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
      .setReturnData 8 2])
    "double IR: load x twice, checkedAdd, setReturnData (rendered as ret)"
  expect (ir.fns[1]!.operations == #[
      .loadParam 0 8,
      .callFn 0 1 #[0],
      .callFn 0 2 #[1],
      .setReturnData 8 2])
    "quadruple IR: two callFn double with dense destinations"
  let bumpIR ← findHandlerIR ir "bump"
  expect (bumpIR.operations == #[
      .loadState 0 0 8,
      .loadParam 1 8,
      .callFn 0 2 #[1],
      .checkedAdd 3 0 2 overflow,
      .storeState 0 8 3,
      .loadState 0 0 8,
      .callFn 1 1 #[0],
      .setReturnData 8 1])
    "bump IR must call double then quadruple with recycled temps"
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
  -- IR recycled temps for scale: the store and return are independent
  -- statements; after the store consumes its Expr-tree temps, the return
  -- recycles back to temp 0.
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
      .loadState 0 0 8,
      .setReturnData 8 0])
    "scale IR must lower mul/div/mod/add with recycled temp numbering"
  let bitsIR ← findHandlerIR ir "bits"
  expect (bitsIR.operations == #[
      .loadParam 0 8,
      .bitNot 1 0,
      .setReturnData 8 1])
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
  -- Recycled temps: load x, lit 2, shl, lit 15, bitAnd, load x, lit 1, shr,
  -- lit 3, bitXor, bitOr, store, load count, set_return_data. After the
  -- store consumes its Expr-tree temps, the return recycles to temp 0.
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
      .loadState 0 0 8,
      .setReturnData 8 0])
    "shiftMask IR must lower shifts/bitwise with recycled temps and dual shift guards"
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
      .setReturnData 8 4])
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

/-- #125 call/schedule matrix:
    * legacy profiles (default plan / elf) still PF-REQ-UNSUPPORTED for both keys
    * exact CPI profile admits sync at ordinary resolve; unknown Oracle QN fails
      product Plan with PF-PLAN-INVARIANT; schedule still PF-REQ-UNSUPPORTED
    Principal remains fail-closed for address mapping. Defense-in-depth: forged
    legacy Plan/IR/SBPF call nodes still fail closed. -/
private unsafe def testExternalCallFailClosed
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
  -- Legacy profiles still reject both keys before capability mint.
  for profile? in #[none, some CodegenProfileId.solanaSbpfElfV1] do
    let callSelection ← liftResult <|
      resolveBuildSelectionV1 TargetId.solana profile?
    expectUnsupportedRequirement s!"call legacy profile={callSelection.codegenProfile}"
      "effect.synchronous-call"
      (Targets.resolveEngineeringRequirementsV1 callSelection callCompiled)
    let scheduleSelection ← liftResult <|
      resolveBuildSelectionV1 TargetId.solana profile?
    expectUnsupportedRequirement s!"schedule legacy profile={scheduleSelection.codegenProfile}"
      "effect.asynchronous-workflow"
      (Targets.resolveEngineeringRequirementsV1 scheduleSelection scheduleCompiled)
  -- Exact CPI profile: ordinary resolve admits sync. Unknown Oracle without
  -- extension fails product Plan (extension required). With exact extension,
  -- non-approved Oracle QN fails product Plan with PF-PLAN-INVARIANT.
  let cpiCallSel ← liftResult <|
    resolveBuildSelectionV1 TargetId.solana (some CodegenProfileId.solanaSbpfCpiElfV1)
  let cpiCallCap ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 cpiCallSel callCompiled
  match planFromCapability cpiCallCap with
  | .ok (.cpi _) =>
      throw <| IO.userError
        "cpi unknown Oracle.feed must not mint product Plan"
  | .ok (.legacy _) =>
      throw <| IO.userError
        "cpi profile must not enter legacy Plan for sync call program"
  | .error e =>
      expect (e.code == "PF-PLAN-INVARIANT" || e.code == "PF-REQ-UNSUPPORTED")
        s!"cpi unknown call product Plan must fail closed, got {e.render}"
  -- Same unknown QN with exact extension → ordinary resolve + PF-PLAN-INVARIANT.
  let cpiCallExtText :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CallGateExt where\n" ++
    "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
    "    digest \"sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020\"\n" ++
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    call Oracle.feed(count)\n" ++
    "    count := count + delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let cpiCallExtCompiled ← compileSource session cpiCallExtText
    "Examples.CallGateExt" "<solana-call-gate-ext>"
  let cpiCallExtCap ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 cpiCallSel cpiCallExtCompiled
  match planFromCapability cpiCallExtCap with
  | .ok (.cpi _) =>
      throw <| IO.userError
        "cpi Oracle.feed with extension must not mint product Plan"
  | .ok (.legacy _) =>
      throw <| IO.userError
        "cpi profile must not enter legacy Plan for Oracle.feed"
  | .error e =>
      expect (e.code == "PF-PLAN-INVARIANT")
        s!"cpi non-approved API product Plan must PF-PLAN-INVARIANT, got {e.render}"
  -- Exact CPI profile: schedule (async) still unsupported at ordinary resolve.
  let cpiSchedSel ← liftResult <|
    resolveBuildSelectionV1 TargetId.solana (some CodegenProfileId.solanaSbpfCpiElfV1)
  expectUnsupportedRequirement "schedule cpi profile"
    "effect.asynchronous-workflow"
    (Targets.resolveEngineeringRequirementsV1 cpiSchedSel scheduleCompiled)

  -- Defense in depth: legacy public Plan nodes cannot pass validation.
  let baselineCompiled ← compileSource session guardedCounterSourceText
    guardedCounterModuleNameV1 "<solana-call-defensive-baseline>"
  let baselinePlan ← liftResult <| planSolana baselineCompiled
  let baseEntry := baselinePlan.entries[0]!
  let forgedCallPlan := {
    baselinePlan with entries := baselinePlan.entries.set! 0 {
      baseEntry with body := #[.externalCall #["Oracle", "feed"] #[]]
    }
  }
  let forgedSchedulePlan := {
    baselinePlan with entries := baselinePlan.entries.set! 0 {
      baseEntry with body := #[.schedule #["Ledger", "daily"] #[]]
    }
  }
  expectPlanError "forged legacy call Plan" (validatePlan forgedCallPlan)
  expectPlanError "forged legacy schedule Plan" (validatePlan forgedSchedulePlan)

  -- Defense in depth continues at typed IR and the public SBPF emitter.
  -- Main IR externalCall carries resultDest Option; forge void form with none.
  let baselineIr ← liftResult <| irSolana baselineCompiled
  let baseHandler := baselineIr.handlers[1]!
  let zeroProgramId := String.ofList (List.replicate 64 '0')
  let forgedCallIr := withHandlers baselineIr <|
    baselineIr.handlers.set! 1 {
      baseHandler with operations :=
        #[.externalCall #["Oracle", "feed"] zeroProgramId #[] none]
    }
  let forgedScheduleIr := withHandlers baselineIr <|
    baselineIr.handlers.set! 1 {
      baseHandler with operations :=
        #[.schedule #["Ledger", "daily"] zeroProgramId #[]]
    }
  expectPlanError "forged legacy call IR" (validateIR forgedCallIr)
  expectPlanError "forged legacy schedule IR" (validateIR forgedScheduleIr)
  expectPlanError "forged legacy call SBPF" (emitSbpfAsmV1 forgedCallIr)
  expectPlanError "forged legacy schedule SBPF" (emitSbpfAsmV1 forgedScheduleIr)

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


/-- T9c-2: Int8 state + Int16 param + Int8 result admitted on Solana plan. -/
private unsafe def testNarrowIntAbi : IO Unit := do
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
  let source ← liftResult (← session.selectProgramV1
    sourceText "<solana-narrow-int>" "Tests.SolanaNarrowInt" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let plan ← liftResult <| planSolana compiled
  expect (plan.stateAccount.fields.map (·.byteWidth) == #[1])
    "T9c-2: Int8 state byteWidth 1"
  expect (plan.stateAccount.fields[0]!.isInt)
    "T9c-2: Int8 state isInt"
  let bump ← findHandler plan "bump"
  expect (bump.resultKind == .i8)
    "T9c-2: bump resultKind i8"
  expect (bump.params.size == 1 && bump.params[0]!.isInt &&
      bump.params[0]!.byteWidth == 2)
    "T9c-2: bump Int16 param"
  -- Int128 fail closed
  let wideText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program WideInt where\n" ++
    "  entry run(x : Int128) : Int128 do\n" ++
    "    return x\n"
  let wideSrc ← liftResult (← session.selectProgramV1
    wideText "<solana-wide-int>" "Tests.SolanaWideInt" none)
  match Compiler.compileValidatedSourceV1 wideSrc with
  | .error _ => pure ()
  | .ok compiledW =>
      match planSolana compiledW with
      | .error _ => pure ()
      | .ok _ => throw <| IO.userError "Solana plan must reject Int128"

/-- B-MAP-STRUCT-PIN: recursive Plan walk — count 24-leaf `storeAggregate` and
    any scalar `.store` (sequential leaf writes). -/
private partial def countPlanAggregates (stmts : Array Statement) : Nat × Nat :=
  stmts.foldl (fun (agg24, seq) stmt =>
    match stmt with
    | .storeAggregate leaves =>
        (agg24 + (if leaves.size == 24 then 1 else 0), seq)
    | .store _ =>
        (agg24, seq + 1)
    | .ifThenElse _ t e =>
        let (a1, s1) := countPlanAggregates t
        let (a2, s2) := countPlanAggregates e
        (agg24 + a1 + a2, seq + s1 + s2)
    | .switchOn _ cases d =>
        let (ad, sd) := countPlanAggregates d
        let (ac, sc) := cases.foldl (fun (a, s) (_, b) =>
          let (ab, sb) := countPlanAggregates b
          (a + ab, s + sb)) (0, 0)
        (agg24 + ad + ac, seq + sd + sc)
    | .forLoop _ _ _ _ _ b =>
        let (ab, sb) := countPlanAggregates b
        (agg24 + ab, seq + sb)
    | _ => (agg24, seq)) (0, 0)

/-- B-MAP-STRUCT-PIN: recursive IR walk — count `storeStateMulti` (24-leaf) and
    scalar `storeState`/`narrowStoreState`. -/
private partial def countIrMultiStores (ops : Array Operation) : Nat × Nat :=
  ops.foldl (fun (multi24, scalar) op =>
    match op with
    | .storeStateMulti entries =>
        (multi24 + (if entries.size == 24 then 1 else 0), scalar)
    | .storeState .. | .narrowStoreState .. =>
        (multi24, scalar + 1)
    | .ifRegion _ t e =>
        let (m1, s1) := countIrMultiStores t
        let (m2, s2) := countIrMultiStores e
        (multi24 + m1 + m2, scalar + s1 + s2)
    | .switchRegion _ cases d =>
        let (md, sd) := countIrMultiStores d
        let (mc, sc) := cases.foldl (fun (m, s) (_, b) =>
          let (mb, sb) := countIrMultiStores b
          (m + mb, s + sb)) (0, 0)
        (multi24 + md + mc, scalar + sd + sc)
    | .forRegion _ _ _ _ condOps _ bodyOps boundOps _ updateOps _ =>
        let (m1, s1) := countIrMultiStores condOps
        let (m2, s2) := countIrMultiStores bodyOps
        let (m3, s3) := countIrMultiStores boundOps
        let (m4, s4) := countIrMultiStores updateOps
        (multi24 + m1 + m2 + m3 + m4, scalar + s1 + s2 + s3 + s4)
    | _ => (multi24, scalar)) (0, 0)

/-- Every `storeStateMulti` batch: leaf-eval ops first (at least one loadState),
    no scalar storeState interleaved in that eval window, 24 distinct u64
    offsets. Nested regions are walked recursively. -/
private partial def assertIrAtomicBatches (ops : Array Operation) (label : String) :
    IO Unit := do
  let mut i := 0
  while i < ops.size do
    match ops[i]? with
    | some (.storeStateMulti entries) =>
        expect (entries.size == 24)
          s!"{label}: storeStateMulti must write 24 Map leaves, got {entries.size}"
        -- Walk backward until a prior consuming boundary; collect eval window.
        let mut j := i
        let mut sawLoad := false
        let mut sawScalarStore := false
        let mut done := false
        while j > 0 && !done do
          j := j - 1
          match ops[j]? with
          | some (.storeStateMulti ..) | some (.setReturnData ..)
          | some (.setReturnDataBool ..) | some (.assert ..)
          | some (.ifRegion ..) | some (.switchRegion ..)
          | some (.forRegion ..) | some (.returnNone)
          | some (.emitEvent ..) | some (.revertError ..)
          | some (.externalCall ..) | some (.schedule ..) =>
              done := true
          | some (.storeState ..) | some (.narrowStoreState ..) =>
              sawScalarStore := true
          | some (.loadState ..) | some (.narrowLoadState ..) =>
              sawLoad := true
          | _ => pure ()
        expect sawLoad
          s!"{label}: storeStateMulti at op {i} must be preceded by leaf loadState temps (pre-store snapshot)"
        expect (!sawScalarStore)
          s!"{label}: storeStateMulti at op {i} must not interleave scalar storeState in its eval batch"
        let mut seen : Array Nat := #[]
        for (acct, off, bw, _) in entries do
          expect (acct == 0 && bw == 8)
            s!"{label}: storeStateMulti entry must be account0/u64, got acct={acct} bw={bw}"
          expect (!seen.contains off)
            s!"{label}: storeStateMulti must not repeat byteOffset {off}"
          seen := seen.push off
        expect (seen.size == 24)
          s!"{label}: storeStateMulti must cover 24 distinct offsets"
    | some (.ifRegion _ t e) =>
        assertIrAtomicBatches t s!"{label}.then"
        assertIrAtomicBatches e s!"{label}.else"
    | some (.switchRegion _ cases d) =>
        for (_, body) in cases do
          assertIrAtomicBatches body s!"{label}.case"
        assertIrAtomicBatches d s!"{label}.default"
    | some (.forRegion _ _ _ _ condOps _ bodyOps boundOps _ updateOps _) =>
        assertIrAtomicBatches condOps s!"{label}.for.cond"
        assertIrAtomicBatches bodyOps s!"{label}.for.body"
        assertIrAtomicBatches boundOps s!"{label}.for.bound"
        assertIrAtomicBatches updateOps s!"{label}.for.update"
    | _ => pure ()
    i := i + 1

/-- Dense Map empty upsert (MapMini put): production Plan carries one 24-leaf
    `storeAggregate`; IR evaluates all leaf temps then one `storeStateMulti`
    (not 24 live-read/live-write scalar stores). Frame budget remains ≤4096. -/
private unsafe def testMapMiniEmptyUpsertStructure
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "MapMini" <|
    "  state m : Map UInt64 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    m[k] := v\n" ++
    "    return v\n\n" ++
    "  view get(k : UInt64) : UInt64 do\n" ++
    "    match m[k] with\n" ++
    "    | Option.some(v) => do\n" ++
    "      return v\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let compiled ← compileSource session source "Examples.MapMini"
    "<solana-map-mini-struct>"
  let plan ← liftResult <| planSolana compiled
  expect (plan.stateAccount.fields.size == 24)
    s!"MapMini: dense Map must flatten to 24 leaves, got {plan.stateAccount.fields.size}"
  let put ← findHandler plan "put"
  let (agg24, seqStores) := countPlanAggregates put.body
  expect (agg24 == 1)
    s!"MapMini put Plan must have exactly one 24-leaf storeAggregate, got {agg24}"
  expect (seqStores == 0)
    s!"MapMini put Plan must not emit sequential scalar .store (store-then-read hazard), got {seqStores}"
  match put.body[0]? with
  | none =>
      throw <| IO.userError "MapMini put body empty"
  | some stmt =>
      match stmt with
      | .storeAggregate leaves =>
          expect (leaves.size == 24)
            s!"MapMini put body[0] storeAggregate leaves={leaves.size}"
          for i in [0:leaves.size] do
            let leaf := leaves[i]!
            expect (leaf.accountIndex == 0 && leaf.byteWidth == 8)
              s!"MapMini put leaf {i} must be account0/u64"
            -- Dense layout: field i at header(8) + i*8.
            expect (leaf.byteOffset == 8 + i * 8)
              s!"MapMini put leaf {i} byteOffset must be {8 + i * 8}, got {leaf.byteOffset}"
      | .store _ =>
          throw <| IO.userError
            "MapMini put body[0] must be storeAggregate, not scalar store"
      | _ =>
          throw <| IO.userError "MapMini put body[0] must be storeAggregate"
  liftResult <| validatePlan plan
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir
  let putIR ← findHandlerIR ir "put"
  let (multi24, scalarStores) := countIrMultiStores putIR.operations
  expect (multi24 == 1)
    s!"MapMini put IR must have exactly one storeStateMulti(24), got {multi24}"
  expect (scalarStores == 0)
    s!"MapMini put IR must not emit scalar storeState for Map leaves, got {scalarStores}"
  assertIrAtomicBatches putIR.operations "MapMini.put"
  -- sbpf-plan text + 4096B frame via asm emitter (throws on overflow).
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "MapMini.sbpf-plan"
  expect (planText.contains "store_multi_le [24]")
    "MapMini sbpf-plan must render store_multi_le [24] for the atomic aggregate"
  expect (!planText.contains "store_multi_le [23]" &&
      !planText.contains "store_multi_le [25]")
    "MapMini sbpf-plan must not render a non-24 multi-store for put"
  let asm ← liftResult <| emitSbpfAsmV1 ir
  expect (asm.contains "put:") "MapMini asm must contain put handler"
  expect (asm.contains "store_multi_le [24]")
    "MapMini asm must comment/emit store_multi_le [24]"
  -- Frame pin: asm emitter already fails closed above 4096; also pin the
  -- temps=N annotation stays within budget ((N+1)*8 ≤ 4096 ⇒ N ≤ 511).
  expect (asm.contains "handler put (temps=")
    "MapMini asm must annotate put temp count"
  let marker := "handler put (temps="
  let rec indexOf (hay needle : List Char) (i : Nat) : Option Nat :=
    match hay with
    | [] => none
    | _ :: rest =>
        if needle.isPrefixOf hay then some i else indexOf rest needle (i + 1)
  let some at_ := indexOf asm.toList marker.toList 0 |
    throw <| IO.userError "MapMini: put temps marker not found"
  let after := (asm.toList.drop (at_ + marker.length))
  let digits := after.takeWhile (fun c => c.isDigit)
  let tempStr := String.ofList digits
  let some temps := tempStr.toNat? |
    throw <| IO.userError s!"MapMini: could not parse put temps from '{tempStr}'"
  let frameBytes := (temps + 1) * 8
  expect (frameBytes ≤ maxSbpfStackBytesV1)
    s!"MapMini put frame must stay ≤ {maxSbpfStackBytesV1}B, got temps={temps} frame={frameBytes}"
  -- Historical CSE peak ~177 temps / 1424B; pin well under the hard budget.
  expect (temps ≤ 400)
    s!"MapMini put temps must stay CSE-bounded (≤400), got {temps}"
  IO.println "  MapMini empty-upsert Plan/IR/frame pin ok"

/-- B-MAP-STRUCT-PIN: Token transfer dual Map StateStores must stay two
    separate 24-leaf batches (not merged). Second batch IR re-loads state
    after the first `storeStateMulti` so cross-batch writes remain visible. -/
private unsafe def testTokenDualStoreBatchSeparation
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "Token" <|
    "  state balances : Map UInt64 UInt64\n" ++
    "  state supply : UInt64\n\n" ++
    "  init() do\n" ++
    "    balances := Map.empty()\n" ++
    "    supply := 0\n\n" ++
    "  entry mint(to : UInt64, amount : UInt64) : UInt64 do\n" ++
    "    match balances[to] with\n" ++
    "    | Option.some(v) => do\n" ++
    "      balances[to] := v + amount\n" ++
    "      supply := supply + amount\n" ++
    "      return supply\n" ++
    "    | _ => do\n" ++
    "      balances[to] := amount\n" ++
    "      supply := supply + amount\n" ++
    "      return supply\n\n" ++
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
    "      return false\n\n" ++
    "  view balanceOf(who : UInt64) : UInt64 do\n" ++
    "    match balances[who] with\n" ++
    "    | Option.some(v) => do\n" ++
    "      return v\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let compiled ← compileSource session source "Examples.Token"
    "<solana-token-dual-batch>"
  let plan ← liftResult <| planSolana compiled
  -- 24 Map leaves + supply scalar.
  expect (plan.stateAccount.fields.size == 25)
    s!"Token: Map+supply layout must be 25 fields, got {plan.stateAccount.fields.size}"
  let transfer ← findHandler plan "transfer"
  let (agg24, _) := countPlanAggregates transfer.body
  -- Both successful dual-write arms each emit two storeAggregate(24):
  -- some/some and some/none ⇒ ≥4 aggregate statements total (not merged).
  expect (agg24 >= 4)
    s!"Token transfer Plan must keep ≥4 separate 24-leaf storeAggregate (dual StateStores × arms), got {agg24}"
  liftResult <| validatePlan plan
  let ir ← liftResult <| irSolana compiled
  liftResult <| validateIR ir
  let xferIR ← findHandlerIR ir "transfer"
  let (multi24, _) := countIrMultiStores xferIR.operations
  expect (multi24 >= 4)
    s!"Token transfer IR must keep ≥4 storeStateMulti(24) batches, got {multi24}"
  assertIrAtomicBatches xferIR.operations "Token.transfer"
  -- Cross-batch visibility pin: after the first storeStateMulti in a dual-write
  -- arm, the next storeStateMulti's eval phase must re-loadState (not share a
  -- single merged batch). Walk nested regions for consecutive multi pairs.
  let rec hasCrossBatchReload (ops : Array Operation) : Bool :=
    Id.run do
      let mut lastMulti : Option Nat := none
      let mut found := false
      for i in [0:ops.size] do
        match ops[i]? with
        | some (.storeStateMulti _) =>
            match lastMulti with
            | none => lastMulti := some i
            | some prev =>
                -- Between prev+1 and i there must be a loadState (second batch
                -- re-reads account after first write).
                let mut j := prev + 1
                let mut sawLoad := false
                while j < i do
                  match ops[j]? with
                  | some (.loadState ..) | some (.narrowLoadState ..) =>
                      sawLoad := true
                  | _ => pure ()
                  j := j + 1
                if sawLoad then found := true
                lastMulti := some i
        | some (.ifRegion _ t e) =>
            if hasCrossBatchReload t || hasCrossBatchReload e then found := true
        | some (.switchRegion _ cases d) =>
            if hasCrossBatchReload d then found := true
            for (_, body) in cases do
              if hasCrossBatchReload body then found := true
        | _ => pure ()
      pure found
  expect (hasCrossBatchReload xferIR.operations)
    "Token transfer dual storeStateMulti must re-loadState between batches (cross-batch visibility)"
  let files ← liftResult <| filesSolana compiled
  let planText ← findFile files "Token.sbpf-plan"
  -- Count store_multi_le [24] markers in plan text (≥4).
  let rec countSubstr (hay needle : List Char) (acc : Nat) : Nat :=
    match hay with
    | [] => acc
    | _ :: rest =>
        if needle.isPrefixOf hay then countSubstr rest needle (acc + 1)
        else countSubstr rest needle acc
  let multiCount := countSubstr planText.toList "store_multi_le [24]".toList 0
  expect (multiCount >= 4)
    s!"Token sbpf-plan must render ≥4 store_multi_le [24], got {multiCount}"
  -- mint: Map storeAggregate + scalar supply store stay separate batches.
  let mint ← findHandler plan "mint"
  let (mintAgg, mintSeq) := countPlanAggregates mint.body
  expect (mintAgg >= 2)
    s!"Token mint Plan must have ≥2 Map storeAggregate (two match arms), got {mintAgg}"
  expect (mintSeq >= 2)
    s!"Token mint Plan must keep scalar supply .store separate from Map aggregate, got seq={mintSeq}"
  IO.println "  Token dual StateStore batch separation pin ok"

/-- Count any-size `storeAggregate` / scalar `.store` (unlike Map-only 24-leaf pin). -/
private partial def countAnyPlanAggregates (stmts : Array Statement) : Nat × Nat :=
  stmts.foldl (fun (agg, seq) stmt =>
    match stmt with
    | .storeAggregate _ => (agg + 1, seq)
    | .store _ => (agg, seq + 1)
    | .ifThenElse _ t e =>
        let (a1, s1) := countAnyPlanAggregates t
        let (a2, s2) := countAnyPlanAggregates e
        (agg + a1 + a2, seq + s1 + s2)
    | .switchOn _ cases d =>
        let (ad, sd) := countAnyPlanAggregates d
        let (ac, sc) := cases.foldl (fun (a, s) (_, b) =>
          let (ab, sb) := countAnyPlanAggregates b
          (a + ab, s + sb)) (0, 0)
        (agg + ad + ac, seq + sd + sc)
    | .forLoop _ _ _ _ _ b =>
        let (ab, sb) := countAnyPlanAggregates b
        (agg + ab, seq + sb)
    | _ => (agg, seq)) (0, 0)

/-- Count any-size `storeStateMulti` / scalar storeState. -/
private partial def countAnyIrMultiStores (ops : Array Operation) : Nat × Nat :=
  ops.foldl (fun (multi, scalar) op =>
    match op with
    | .storeStateMulti _ => (multi + 1, scalar)
    | .storeState .. | .narrowStoreState .. => (multi, scalar + 1)
    | .ifRegion _ t e =>
        let (m1, s1) := countAnyIrMultiStores t
        let (m2, s2) := countAnyIrMultiStores e
        (multi + m1 + m2, scalar + s1 + s2)
    | .switchRegion _ cases d =>
        let (md, sd) := countAnyIrMultiStores d
        let (mc, sc) := cases.foldl (fun (m, s) (_, b) =>
          let (mb, sb) := countAnyIrMultiStores b
          (m + mb, s + sb)) (0, 0)
        (multi + md + mc, scalar + sd + sc)
    | .forRegion _ _ _ _ condOps _ bodyOps boundOps _ updateOps _ =>
        let (m1, s1) := countAnyIrMultiStores condOps
        let (m2, s2) := countAnyIrMultiStores bodyOps
        let (m3, s3) := countAnyIrMultiStores boundOps
        let (m4, s4) := countAnyIrMultiStores updateOps
        (multi + m1 + m2 + m3 + m4, scalar + s1 + s2 + s3 + s4)
    | _ => (multi, scalar)) (0, 0)

/-- Named Struct state: flatten to UInt64 leaves; construct/fieldGet/fieldSet
    + atomic storeAggregate; scalar field return still covered (aggregate return
    is pinned separately in `testNamedStructReturn`). -/
private unsafe def testNamedStructState
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "PointBox" <|
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  state p : Point\n\n" ++
    "  init() do\n" ++
    "    p := Point.new(0, 0)\n\n" ++
    "  entry setX(v : UInt64) : UInt64 do\n" ++
    "    p.x := v\n" ++
    "    return p.x\n\n" ++
    "  view getY() : UInt64 do\n" ++
    "    return p.y\n"
  let compiled ← compileSource session source "Examples.PointBox"
    "<solana-point-box>"
  let plan ← liftResult (planSolana compiled)
  expect (plan.stateAccount.fields.size == 2)
    s!"PointBox: Point must flatten to 2 leaves, got {plan.stateAccount.fields.size}"
  expect (plan.stateAccount.fields.any fun f => f.name == "p_x" && f.byteWidth == 8)
    "PointBox p_x must be 8-byte leaf"
  expect (plan.stateAccount.fields.any fun f => f.name == "p_y" && f.byteWidth == 8)
    "PointBox p_y must be 8-byte leaf"
  let initializer := plan.initializer
  let (agg, seq) := countAnyPlanAggregates initializer.body
  expect (agg == 1)
    s!"PointBox init must have one storeAggregate for Point, got {agg}"
  expect (seq == 0)
    s!"PointBox init must not scalar-store Point leaves, got {seq}"
  let setX ← findHandler plan "setX"
  let (setAgg, setSeq) := countAnyPlanAggregates setX.body
  expect (setAgg == 1)
    s!"PointBox setX must rewrite Point via storeAggregate, got {setAgg}"
  expect (setSeq == 0)
    s!"PointBox setX must not scalar-store Point leaves, got {setSeq}"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"PointBox plan must validate: {e.render}"
  let ir ← liftResult (irSolana compiled)
  let (multi, scalar) := countAnyIrMultiStores (← findHandlerIR ir "setX").operations
  expect (multi == 1)
    s!"PointBox setX IR must have one storeStateMulti, got {multi}"
  expect (scalar == 0)
    s!"PointBox setX IR must not scalar storeState Point leaves, got {scalar}"
  -- Plan profile emits plan+IDL only; asm is additive via emitSbpfAsmV1.
  let asm ← liftResult (emitSbpfAsmV1 ir)
  expect (asm.contains "setX:") "PointBox asm must contain setX"
  -- Frame pin: 2-leaf struct rewrite stays well under 4096B (asm fails closed).
  expect (asm.contains "temps=")
    "PointBox asm must annotate temps"
  let files ← liftResult (filesSolana compiled)
  let _ ← findFile files "PointBox.sbpf-plan"
  IO.println "  PointBox named Struct Plan/IR pin ok"

/-- Named Enum state: tag + max-payload leaves; construct + atomic store. -/
private unsafe def testNamedEnumState
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "FlagBox" <|
    "  enum Flag where\n" ++
    "    | Off\n" ++
    "    | On\n" ++
    "  state f : Flag\n\n" ++
    "  init() do\n" ++
    "    f := Flag.Off()\n\n" ++
    "  entry setOn() : UInt64 do\n" ++
    "    f := Flag.On()\n" ++
    "    return 1\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return 0\n"
  let compiled ← compileSource session source "Examples.FlagBox"
    "<solana-flag-box>"
  let plan ← liftResult (planSolana compiled)
  -- Tag-only enum flattens to 1 leaf (tag); zero max payload.
  expect (plan.stateAccount.fields.size == 1)
    s!"FlagBox: tag-only Flag must flatten to 1 leaf, got {plan.stateAccount.fields.size}"
  expect (plan.stateAccount.fields.any fun f => f.name == "f_tag")
    "FlagBox leaf must be named f_tag"
  let (agg, seq) := countAnyPlanAggregates plan.initializer.body
  expect (agg == 1)
    s!"FlagBox init must storeAggregate the enum, got {agg}"
  expect (seq == 0)
    s!"FlagBox init must not scalar-store enum tag, got {seq}"
  let setOn ← findHandler plan "setOn"
  let (setAgg, _) := countAnyPlanAggregates setOn.body
  expect (setAgg == 1)
    s!"FlagBox setOn must storeAggregate On, got {setAgg}"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"FlagBox plan must validate: {e.render}"
  -- Payload enum: tag + 1 UInt64 payload → 2 leaves.
  let payloadSource := wrapProgram "MaybeBox" <|
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  state m : Maybe\n\n" ++
    "  init() do\n" ++
    "    m := Maybe.None()\n\n" ++
    "  entry put(v : UInt64) : UInt64 do\n" ++
    "    m := Maybe.Some(v)\n" ++
    "    return v\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return 0\n"
  let payloadCompiled ← compileSource session payloadSource "Examples.MaybeBox"
    "<solana-maybe-box>"
  let payloadPlan ← liftResult (planSolana payloadCompiled)
  expect (payloadPlan.stateAccount.fields.size == 2)
    s!"MaybeBox: Maybe must flatten to tag+payload (2), got {payloadPlan.stateAccount.fields.size}"
  expect (payloadPlan.stateAccount.fields.any fun f => f.name == "m_tag")
    "MaybeBox must have m_tag"
  expect (payloadPlan.stateAccount.fields.any fun f => f.name == "m_p0")
    "MaybeBox must have m_p0 payload leaf"
  match validatePlan payloadPlan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"MaybeBox plan must validate: {e.render}"
  IO.println "  FlagBox/MaybeBox named Enum Plan pin ok"

/-- Bytes N state: N×UInt8 leaves (byteWidth 1, pitch 8); IndexGet/IndexSet. -/
private unsafe def testBytesStateIndexOps
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "ByteBox" <|
    "  state data : Bytes 2\n\n" ++
    "  init() do\n" ++
    "    data[0] := 0\n" ++
    "    data[1] := 0\n\n" ++
    "  entry set0(v : UInt8) : UInt8 do\n" ++
    "    data[0] := v\n" ++
    "    return data[0]\n\n" ++
    "  view get1() : UInt8 do\n" ++
    "    return data[1]\n"
  let compiled ← compileSource session source "Examples.ByteBox"
    "<solana-byte-box>"
  let plan ← liftResult (planSolana compiled)
  expect (plan.stateAccount.fields.size == 2)
    s!"ByteBox: Bytes 2 must flatten to 2 leaves, got {plan.stateAccount.fields.size}"
  expect (plan.stateAccount.fields.any fun f =>
      f.name == "data_0" && f.byteWidth == 1)
    "ByteBox data_0 must be 1-byte leaf"
  expect (plan.stateAccount.fields.any fun f =>
      f.name == "data_1" && f.byteWidth == 1)
    "ByteBox data_1 must be 1-byte leaf"
  -- Pitch 8: second leaf at header+8.
  let some f0 := plan.stateAccount.fields.find? (·.name == "data_0") |
    throw <| IO.userError "ByteBox missing data_0"
  let some f1 := plan.stateAccount.fields.find? (·.name == "data_1") |
    throw <| IO.userError "ByteBox missing data_1"
  expect (f1.byteOffset == f0.byteOffset + 8)
    s!"ByteBox Bytes leaves must use 8-byte pitch, offsets {f0.byteOffset}/{f1.byteOffset}"
  let set0 ← findHandler plan "set0"
  let (agg, seq) := countAnyPlanAggregates set0.body
  expect (agg == 1)
    s!"ByteBox set0 must storeAggregate both Bytes leaves, got {agg}"
  expect (seq == 0)
    s!"ByteBox set0 must not scalar-store Bytes leaves, got {seq}"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ByteBox plan must validate: {e.render}"
  let ir ← liftResult (irSolana compiled)
  let set0IR ← findHandlerIR ir "set0"
  let (multi, scalar) := countAnyIrMultiStores set0IR.operations
  expect (multi == 1)
    s!"ByteBox set0 IR must have one storeStateMulti, got {multi}"
  expect (scalar == 0)
    s!"ByteBox set0 IR must not scalar storeState, got {scalar}"
  -- Multi-store entries must carry byteWidth 1.
  let checkMulti (ops : Array Operation) : Bool :=
    ops.any fun op =>
      match op with
      | .storeStateMulti entries =>
          entries.size == 2 && entries.all fun (_, _, bw, _) => bw == 1
      | _ => false
  expect (checkMulti set0IR.operations)
    "ByteBox set0 storeStateMulti must write 2× byteWidth-1 entries"
  let asm ← liftResult (emitSbpfAsmV1 ir)
  expect (asm.contains "set0:") "ByteBox asm must contain set0"
  expect (asm.contains "temps=")
    "ByteBox asm must annotate temps"
  let files ← liftResult (filesSolana compiled)
  let _ ← findFile files "ByteBox.sbpf-plan"
  -- Map remains admitted after Bytes path (orthogonal pilot).
  let mapSource := wrapProgram "MapStillOpen" <|
    "  state m : Map UInt64 UInt64\n" ++
    "  state d : UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "    d := 0\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return d\n"
  let mapCompiled ← compileSource session mapSource "Examples.MapStillOpen"
    "<solana-map-still>"
  match planSolana mapCompiled with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError s!"Solana must still accept Map after Bytes, got {e.render}"
  IO.println "  ByteBox Bytes state Plan/IR pin ok"

/-- B-RET-ABI: named Struct view return flattens to 2×UInt64 leaves via
`returnAggregate` / `setReturnDataMulti` / `sol_set_return_data` (16B). -/
private unsafe def testNamedStructReturn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "PairRet" <|
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  state p : Pair\n\n" ++
    "  init(x : UInt64, y : UInt64) do\n" ++
    "    p := Pair.new(x, y)\n\n" ++
    "  view getPair() : Pair do\n" ++
    "    return p\n"
  let compiled ← compileSource session source "Examples.PairRet"
    "<solana-pair-ret>"
  let plan ← liftResult (planSolana compiled)
  let getPair ← findHandler plan "getPair"
  match getPair.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"PairRet aggregate return must have 2 leaves, got {leaves.size}"
      expect (!leaves[0]!.isInt && !leaves[1]!.isInt)
        "PairRet leaves must be u64 (not Int)"
      expect (leaves.all (·.byteWidth == 8))
        "PairRet leaves must be 8-byte words"
  | other =>
      throw <| IO.userError
        s!"PairRet getPair resultKind must be .aggregate, got {repr other}"
  expect (getPair.body.size == 1) "PairRet getPair body must be one return"
  match getPair.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2)
        s!"returnAggregate must have 2 leaves, got {leaves.size}"
      expect (leafIsInt == #[false, false])
        "returnAggregate leafIsInt must be #[false, false]"
      -- Preorder: p_a then p_b → two stateLoad of the two fields.
      match leaves[0]!, leaves[1]! with
      | .stateLoad 0 off0, .stateLoad 0 off1 =>
          expect (off0 + 8 == off1)
            s!"PairRet leaf order must be consecutive field offsets, got {off0}/{off1}"
      | _, _ =>
          throw <| IO.userError
            "PairRet returnAggregate leaves must be stateLoad of p fields"
  | _ =>
      throw <| IO.userError "PairRet getPair body must be .returnAggregate"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"PairRet plan must validate: {e.render}"
  let ir ← liftResult (irSolana compiled)
  let getPairIR ← findHandlerIR ir "getPair"
  expect (getPairIR.resultKind == getPair.resultKind)
    "PairRet IR resultKind must match Plan"
  let mut sawMulti := false
  for op in getPairIR.operations do
    match op with
    | .setReturnDataMulti temps =>
        expect (temps.size == 2)
          s!"setReturnDataMulti must have 2 temps, got {temps.size}"
        sawMulti := true
    | .setReturnData .. | .setReturnDataBool _ =>
        throw <| IO.userError "PairRet must not emit scalar setReturnData*"
    | _ => pure ()
  expect sawMulti "PairRet IR must emit setReturnDataMulti"
  let asm ← liftResult (emitSbpfAsmV1 ir)
  expect (asm.contains "sol_set_return_data")
    "PairRet asm must call sol_set_return_data"
  expect (asm.contains "set_return_data_multi" || asm.contains "lddw r2, 16")
    "PairRet asm must pack 16-byte multi return (len=16)"
  expect (asm.contains "temps=")
    "PairRet asm must annotate temps (frame budget path)"
  -- Frame pin: 2-leaf return stays well under 4096B.
  expect (!asm.contains "frame budget exceeded")
    "PairRet must not exceed SBPF frame budget"
  let files ← liftResult (filesSolana compiled)
  let idl ← findFile files "PairRet.idl.json"
  expect (idl.contains "\"returns\":[\"u64-le\",\"u64-le\"]")
    s!"PairRet IDL must declare leaf tuple [\"u64-le\",\"u64-le\"], got: {idl}"
  let _ ← findFile files "PairRet.sbpf-plan"
  IO.println "  PairRet named Struct return Plan/IR/SBPF/IDL pin ok"

/-- B-RET-ABI: named Enum return = tag + max-payload slots (Maybe = 2 leaves). -/
private unsafe def testNamedEnumReturn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "MaybeRet" <|
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  state m : Maybe\n\n" ++
    "  init() do\n" ++
    "    m := Maybe.None()\n\n" ++
    "  entry put(v : UInt64) : Maybe do\n" ++
    "    m := Maybe.Some(v)\n" ++
    "    return m\n\n" ++
    "  view peek() : Maybe do\n" ++
    "    return m\n"
  let compiled ← compileSource session source "Examples.MaybeRet"
    "<solana-maybe-ret>"
  let plan ← liftResult (planSolana compiled)
  let peek ← findHandler plan "peek"
  match peek.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"MaybeRet Enum return must be tag+payload (2), got {leaves.size}"
  | other =>
      throw <| IO.userError
        s!"MaybeRet peek resultKind must be .aggregate, got {repr other}"
  match peek.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2 && leafIsInt.size == 2)
        "MaybeRet returnAggregate must have 2 leaves"
  | _ =>
      throw <| IO.userError "MaybeRet peek body must be .returnAggregate"
  let put ← findHandler plan "put"
  match put.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2) "MaybeRet put must also return 2-leaf Maybe"
  | _ =>
      throw <| IO.userError "MaybeRet put resultKind must be .aggregate"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"MaybeRet plan must validate: {e.render}"
  let ir ← liftResult (irSolana compiled)
  let peekIR ← findHandlerIR ir "peek"
  expect (peekIR.operations.any fun
      | .setReturnDataMulti t => t.size == 2
      | _ => false)
    "MaybeRet peek IR must emit setReturnDataMulti [2]"
  let asm ← liftResult (emitSbpfAsmV1 ir)
  expect (asm.contains "sol_set_return_data")
    "MaybeRet asm must call sol_set_return_data"
  let files ← liftResult (filesSolana compiled)
  let idl ← findFile files "MaybeRet.idl.json"
  expect (idl.contains "\"returns\":[\"u64-le\",\"u64-le\"]")
    s!"MaybeRet IDL must declare [\"u64-le\",\"u64-le\"], got: {idl}"
  IO.println "  MaybeRet named Enum return Plan/IR pin ok"

/-- BL-19 / N-ANON-RESULT Solana ABI: anonymous Array UInt64 2 entry/view return
    flattens to 2×UInt64 leaves via returnAggregate / setReturnDataMulti. -/
private unsafe def testAnonymousArrayReturn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "ArrayRet" <|
    "  state slots : Array UInt64 2\n\n" ++
    "  init(x : UInt64, y : UInt64) do\n" ++
    "    slots[0] := x\n" ++
    "    slots[1] := y\n\n" ++
    "  entry setArr(x : UInt64, y : UInt64) : Array UInt64 2 do\n" ++
    "    slots[0] := x\n" ++
    "    slots[1] := y\n" ++
    "    return slots\n\n" ++
    "  view getArr() : Array UInt64 2 do\n" ++
    "    return slots\n"
  let compiled ← compileSource session source "Examples.ArrayRet"
    "<solana-array-ret>"
  let plan ← liftResult (planSolana compiled)
  let getArr ← findHandler plan "getArr"
  match getArr.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"ArrayRet aggregate return must have 2 leaves, got {leaves.size}"
      expect (!leaves[0]!.isInt && !leaves[1]!.isInt)
        "ArrayRet leaves must be u64"
      expect (leaves.all (·.byteWidth == 8))
        "ArrayRet leaves must be 8-byte words"
  | other =>
      throw <| IO.userError
        s!"ArrayRet getArr resultKind must be .aggregate, got {repr other}"
  match getArr.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2 && leafIsInt == #[false, false])
        "ArrayRet returnAggregate must have 2 u64 leaves"
      match leaves[0]!, leaves[1]! with
      | .stateLoad 0 off0, .stateLoad 0 off1 =>
          expect (off0 + 8 == off1)
            s!"ArrayRet leaf order must be consecutive slots, got {off0}/{off1}"
      | _, _ =>
          throw <| IO.userError
            "ArrayRet returnAggregate leaves must be stateLoad of slots"
  | _ =>
      throw <| IO.userError "ArrayRet getArr body must be .returnAggregate"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ArrayRet plan must validate: {e.render}"
  let ir ← liftResult (irSolana compiled)
  let getArrIR ← findHandlerIR ir "getArr"
  expect (getArrIR.operations.any fun
      | .setReturnDataMulti t => t.size == 2
      | _ => false)
    "ArrayRet getArr IR must emit setReturnDataMulti [2]"
  let asm ← liftResult (emitSbpfAsmV1 ir)
  expect (asm.contains "sol_set_return_data")
    "ArrayRet asm must call sol_set_return_data"
  expect (asm.contains "set_return_data_multi" || asm.contains "lddw r2, 16")
    "ArrayRet asm must pack 16-byte multi return"
  let files ← liftResult (filesSolana compiled)
  let idl ← findFile files "ArrayRet.idl.json"
  expect (idl.contains "\"returns\":[\"u64-le\",\"u64-le\"]")
    s!"ArrayRet IDL must declare [\"u64-le\",\"u64-le\"], got: {idl}"
  IO.println "  ArrayRet anonymous Array return Plan/IR/SBPF/IDL pin ok"

/-- BL-19: anonymous Option UInt64 entry/view return = tag + payload (2 leaves). -/
private unsafe def testAnonymousOptionReturn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "OptionRet" <|
    "  state pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry putSome(v : UInt64) : Option UInt64 do\n" ++
    "    pad := v\n" ++
    "    return Option.some(v)\n\n" ++
    "  entry putNone() : Option UInt64 do\n" ++
    "    pad := 0\n" ++
    "    return Option.none()\n\n" ++
    "  view peekSome() : Option UInt64 do\n" ++
    "    return Option.some(pad)\n\n" ++
    "  view peekNone() : Option UInt64 do\n" ++
    "    return Option.none()\n"
  let compiled ← compileSource session source "Examples.OptionRet"
    "<solana-option-ret>"
  let plan ← liftResult (planSolana compiled)
  let peekNone ← findHandler plan "peekNone"
  match peekNone.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"OptionRet Enum-like Option return must be tag+payload (2), got {leaves.size}"
  | other =>
      throw <| IO.userError
        s!"OptionRet peekNone resultKind must be .aggregate, got {repr other}"
  match peekNone.body[peekNone.body.size - 1]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2 && leafIsInt.size == 2)
        "OptionRet returnAggregate must have 2 leaves"
      -- none → (0, 0) literals
      match leaves[0]!, leaves[1]! with
      | .literal 0, .literal 0 => pure ()
      | a, b =>
          throw <| IO.userError
            s!"OptionRet peekNone leaves must be literal 0/0, got {repr a}/{repr b}"
  | _ =>
      throw <| IO.userError "OptionRet peekNone must end with .returnAggregate"
  let putSome ← findHandler plan "putSome"
  match putSome.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2) "OptionRet putSome must return 2-leaf Option"
  | _ =>
      throw <| IO.userError "OptionRet putSome resultKind must be .aggregate"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"OptionRet plan must validate: {e.render}"
  let ir ← liftResult (irSolana compiled)
  let peekNoneIR ← findHandlerIR ir "peekNone"
  expect (peekNoneIR.operations.any fun
      | .setReturnDataMulti t => t.size == 2
      | _ => false)
    "OptionRet peekNone IR must emit setReturnDataMulti [2]"
  let peekSomeIR ← findHandlerIR ir "peekSome"
  expect (peekSomeIR.operations.any fun
      | .setReturnDataMulti t => t.size == 2
      | _ => false)
    "OptionRet peekSome IR must emit setReturnDataMulti [2]"
  let asm ← liftResult (emitSbpfAsmV1 ir)
  expect (asm.contains "sol_set_return_data")
    "OptionRet asm must call sol_set_return_data"
  let files ← liftResult (filesSolana compiled)
  let idl ← findFile files "OptionRet.idl.json"
  expect (idl.contains "\"returns\":[\"u64-le\",\"u64-le\"]")
    s!"OptionRet IDL must declare [\"u64-le\",\"u64-le\"], got: {idl}"
  IO.println "  OptionRet anonymous Option return Plan/IR pin ok"

/-- Fail-closed: Bytes/Map/9-element Array return, nested, Option state, named param. -/
private unsafe def testAggregateFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Cap-8: Struct with 9 UInt64 fields exceeds B-RET-ABI leaf cap.
  let mut fields := ""
  for i in [0:9] do
    fields := fields ++ s!"    f{i} : UInt64\n"
  let wideSource := wrapProgram "WideRet" <|
    "  struct Wide where\n" ++
    fields ++
    "  state w : Wide\n\n" ++
    "  init() do\n" ++
    "    w := Wide.new(0, 0, 0, 0, 0, 0, 0, 0, 0)\n\n" ++
    "  view getWide() : Wide do\n" ++
    "    return w\n"
  match ← (do
      try
        let c ← compileSource session wideSource "Examples.WideRet" "<solana-wide-ret>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planSolana c with
      | .error e =>
          expect (e.render.contains "8" || e.render.contains "leaf" ||
              e.render.contains "aggregate")
            s!"WideRet leaf-cap error must cite cap/leaf/aggregate, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "Solana 9-leaf aggregate return must fail closed (cap-8)"
  -- Array UInt64 9 return exceeds cap-8.
  let arr9Source := wrapProgram "Array9Ret" <|
    "  state slots : Array UInt64 9\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n" ++
    "    slots[2] := 0\n" ++
    "    slots[3] := 0\n" ++
    "    slots[4] := 0\n" ++
    "    slots[5] := 0\n" ++
    "    slots[6] := 0\n" ++
    "    slots[7] := 0\n" ++
    "    slots[8] := 0\n\n" ++
    "  view getArr() : Array UInt64 9 do\n" ++
    "    return slots\n"
  match ← (do
      try
        let c ← compileSource session arr9Source "Examples.Array9Ret" "<solana-arr9>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planSolana c with
      | .error e =>
          expect (e.render.contains "8" || e.render.contains "leaf" ||
              e.render.contains "aggregate" || e.render.contains "9")
            s!"Array9Ret cap error must cite cap/leaf/aggregate/9, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "Solana Array UInt64 9 return must fail closed (cap-8)"
  -- Bytes N result stays fail-closed.
  let bytesSource := wrapProgram "BytesRet" <|
    "  state b : Bytes 2\n\n" ++
    "  init() do\n" ++
    "    b[0] := 0\n" ++
    "    b[1] := 0\n\n" ++
    "  view getB() : Bytes 2 do\n" ++
    "    return b\n"
  match ← (do
      try
        let c ← compileSource session bytesSource "Examples.BytesRet" "<solana-bytes-ret>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c => expectPlanError "BytesRet" (planSolana c)
  -- Map result stays fail-closed.
  let mapSource := wrapProgram "MapRet" <|
    "  state m : Map UInt64 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  view getM() : Map UInt64 UInt64 do\n" ++
    "    return m\n"
  match ← (do
      try
        let c ← compileSource session mapSource "Examples.MapRet" "<solana-map-ret>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c => expectPlanError "MapRet" (planSolana c)
  -- Nested anonymous Array element stays fail-closed (element must be UInt64).
  let nestSource := wrapProgram "NestArrRet" <|
    "  state pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  view getNest() : Array (Array UInt64 2) 1 do\n" ++
    "    return Array(Array(0, 0))\n"
  match ← (do
      try
        let c ← compileSource session nestSource "Examples.NestArrRet" "<solana-nest>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()  -- may fail at typed/Normalize
  | some c => expectPlanError "NestArrRet" (planSolana c)
  -- B-OPT-STATE: Option of non-UInt64 state stays fail closed.
  let optBadSource := wrapProgram "OptBadEl" <|
    "  state o : Option UInt8\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return 0\n"
  match ← (do
      try
        let c ← compileSource session optBadSource "Examples.OptBadEl" "<solana-opt-bad>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()  -- may fail at Normalize/typed
  | some c =>
      match planSolana c with
      | .error e =>
          expect (e.render.contains "Option" || e.render.contains "UInt64" ||
              e.render.contains "element")
            s!"OptBadEl must cite Option/UInt64/element, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "Solana Option UInt8 state must fail closed (UInt64 element only)"
  -- Option param stays fail closed (state-only; mirrors Enum params).
  let optParamSource := wrapProgram "OptParam" <|
    "  state pad : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    pad := i\n\n" ++
    "  entry take(o : Option UInt64) : UInt64 do\n" ++
    "    return pad\n"
  match ← (do
      try
        let c ← compileSource session optParamSource "Examples.OptParam" "<solana-opt-param>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c => expectPlanError "OptParam" (planSolana c)
  -- Named Struct param stays fail closed (state-only pilot).
  let paramSource := wrapProgram "StructParam" <|
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  state pad : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    pad := i\n\n" ++
    "  entry take(p : Pair) : UInt64 do\n" ++
    "    return p.a\n"
  let paramCompiled ← compileSource session paramSource "Examples.StructParam"
    "<solana-struct-param>"
  expectPlanError "StructParam" (planSolana paramCompiled)
  IO.println "  aggregate fail-closed boundaries ok"

/-- BL-29 / B-OPT-STATE: Option UInt64 state = Enum-shaped 2-leaf layout
    (`slot_tag` + `slot_p0`); construct none zeros payload; match read via
    VariantTag/VariantPayload; storeAggregate on assign. -/
private unsafe def testOptionState
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "OptionState" <|
    "  state slot : Option UInt64\n\n" ++
    "  init() do\n" ++
    "    slot := Option.none()\n\n" ++
    "  entry set(v : UInt64) : UInt64 do\n" ++
    "    slot := Option.some(v)\n" ++
    "    return v\n\n" ++
    "  entry clear() : UInt64 do\n" ++
    "    slot := Option.none()\n" ++
    "    return 0\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    match slot with\n" ++
    "    | Option.some(x) => do\n" ++
    "      return x\n" ++
    "    | _ => do\n" ++
    "      return 0\n\n" ++
    "  view getOpt() : Option UInt64 do\n" ++
    "    return slot\n"
  let compiled ← compileSource session source "Examples.OptionState"
    "<solana-option-state>"
  let plan ← liftResult (planSolana compiled)
  expect (plan.stateAccount.fields.size == 2)
    s!"OptionState: Option UInt64 must flatten to tag+payload (2), got {plan.stateAccount.fields.size}"
  expect (plan.stateAccount.fields.any fun f => f.name == "slot_tag")
    "OptionState must have slot_tag leaf"
  expect (plan.stateAccount.fields.any fun f => f.name == "slot_p0")
    "OptionState must have slot_p0 payload leaf"
  let some tagF := plan.stateAccount.fields.find? (·.name == "slot_tag") |
    throw <| IO.userError "OptionState missing slot_tag"
  let some payF := plan.stateAccount.fields.find? (·.name == "slot_p0") |
    throw <| IO.userError "OptionState missing slot_p0"
  expect (tagF.byteWidth == 8 && payF.byteWidth == 8)
    "OptionState leaves must be 8-byte UInt64 words"
  expect (payF.byteOffset == tagF.byteOffset + 8)
    s!"OptionState leaves must be consecutive, offsets {tagF.byteOffset}/{payF.byteOffset}"
  -- Init none → storeAggregate both leaves (payload zeroed).
  let (initAgg, initSeq) := countAnyPlanAggregates plan.initializer.body
  expect (initAgg == 1)
    s!"OptionState init must storeAggregate Option.none, got {initAgg}"
  expect (initSeq == 0)
    s!"OptionState init must not scalar-store Option leaves, got {initSeq}"
  -- set some → storeAggregate.
  let setH ← findHandler plan "set"
  let (setAgg, _) := countAnyPlanAggregates setH.body
  expect (setAgg == 1)
    s!"OptionState set must storeAggregate Option.some, got {setAgg}"
  -- clear none-reset → storeAggregate (stale payload must not survive).
  let clearH ← findHandler plan "clear"
  let (clearAgg, _) := countAnyPlanAggregates clearH.body
  expect (clearAgg == 1)
    s!"OptionState clear must storeAggregate Option.none, got {clearAgg}"
  -- peek match → body reads state leaves (VariantTag/VariantPayload path).
  let peekH ← findHandler plan "peek"
  expect (peekH.resultKind == .u64)
    "OptionState peek must return UInt64"
  -- getOpt return of stored Option → 2-leaf aggregate.
  let getOpt ← findHandler plan "getOpt"
  match getOpt.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"OptionState getOpt must return 2-leaf Option, got {leaves.size}"
  | other =>
      throw <| IO.userError
        s!"OptionState getOpt resultKind must be .aggregate, got {repr other}"
  match getOpt.body[getOpt.body.size - 1]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2 && leafIsInt.size == 2)
        "OptionState getOpt returnAggregate must have 2 leaves"
      match leaves[0]!, leaves[1]! with
      | .stateLoad 0 off0, .stateLoad 0 off1 =>
          expect (off0 + 8 == off1)
            s!"OptionState getOpt leaves must be consecutive stateLoads, got {off0}/{off1}"
      | a, b =>
          throw <| IO.userError
            s!"OptionState getOpt leaves must be stateLoads, got {repr a}/{repr b}"
  | _ =>
      throw <| IO.userError "OptionState getOpt must end with .returnAggregate"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"OptionState plan must validate: {e.render}"
  let ir ← liftResult (irSolana compiled)
  let setIR ← findHandlerIR ir "set"
  let (multi, scalar) := countAnyIrMultiStores setIR.operations
  expect (multi == 1)
    s!"OptionState set IR must have one storeStateMulti, got {multi}"
  expect (scalar == 0)
    s!"OptionState set IR must not scalar storeState, got {scalar}"
  let clearIR ← findHandlerIR ir "clear"
  let (clearMulti, _) := countAnyIrMultiStores clearIR.operations
  expect (clearMulti == 1)
    s!"OptionState clear IR must storeStateMulti none-reset, got {clearMulti}"
  -- none construct must materialize literal 0 payload (not leave stale).
  let initIR ← findHandlerIR ir "initialize"
  let (initMulti, _) := countAnyIrMultiStores initIR.operations
  expect (initMulti == 1)
    s!"OptionState init IR must storeStateMulti none, got {initMulti}"
  let getOptIR ← findHandlerIR ir "getOpt"
  expect (getOptIR.operations.any fun
      | .setReturnDataMulti t => t.size == 2
      | _ => false)
    "OptionState getOpt IR must emit setReturnDataMulti [2]"
  let asm ← liftResult (emitSbpfAsmV1 ir)
  expect (asm.contains "set:") "OptionState asm must contain set"
  expect (asm.contains "clear:") "OptionState asm must contain clear"
  expect (asm.contains "temps=")
    "OptionState asm must annotate temps"
  let files ← liftResult (filesSolana compiled)
  let _ ← findFile files "OptionState.sbpf-plan"
  let idl ← findFile files "OptionState.idl.json"
  expect (idl.contains "getOpt")
    s!"OptionState IDL must declare getOpt, got: {idl}"
  IO.println "  OptionState Option UInt64 state Plan/IR/SBPF pin ok"

/-- ADR-0031 S2: `context.blockHeight` lowers on ordinary Solana to
    `Clock.slot` via `sol_get_clock_sysvar` (physical ≈400ms slot, **not**
    logical block number). View-safe; Plan/IR/SBPF pin; wrong result type and
    still-deferred keys fail closed. -/
private unsafe def testContextReadBlockHeight
    (session : Language.Loader.ParserSession) : IO Unit := do
  let sourceText :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program HeightBox where\n" ++
    "  state h : UInt64\n\n" ++
    "  init() do\n" ++
    "    h := 0\n\n" ++
    "  entry stamp() : UInt64 do\n" ++
    "    h := context.blockHeight\n" ++
    "    return h\n\n" ++
    "  view height() : UInt64 do\n" ++
    "    return context.blockHeight\n\n" ++
    "end ProofForgeV2.Examples\n"
  let compiled ← compileSource session sourceText
    "Examples.HeightBox" "<solana-height-box>"
  let plan ← liftResult (planSolana compiled)
  let stamp ← findHandler plan "stamp"
  let hasSlot := stamp.body.any fun s =>
    match s with
    | .store op =>
        match op.value with
        | .clockSlot => true
        | _ => false
    | _ => false
  expect hasSlot "height-box: stamp must store clockSlot"
  let height ← findHandler plan "height"
  let viewHasSlot := height.body.any fun s =>
    match s with
    | .returnValue .clockSlot => true
    | _ => false
  expect viewHasSlot "height-box: view must return clockSlot (view-safe)"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"height-box plan must validate: {e.render}"
  let ir ← liftResult (irSolana compiled)
  let stampIR ← findHandlerIR ir "stamp"
  expect (stampIR.operations.any fun
      | .clockSlot _ => true
      | _ => false)
    "height-box: IR stamp must contain clockSlot op"
  let heightIR ← findHandlerIR ir "height"
  expect (heightIR.operations.any fun
      | .clockSlot _ => true
      | _ => false)
    "height-box: IR height view must contain clockSlot op"
  let asm ← liftResult (emitSbpfAsmV1 ir)
  expect (asm.contains "call sol_get_clock_sysvar")
    "height-box: SBPF must call sol_get_clock_sysvar"
  expect (asm.contains "clock_slot")
    "height-box: SBPF must annotate clock_slot"
  -- Wrong result type (Bool) fail closed at type-check or plan.
  let badDirect :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BadHeightType where\n" ++
    "  state s : UInt64\n\n" ++
    "  init() do\n" ++
    "    s := 0\n\n" ++
    "  view bad() : Bool do\n" ++
    "    let x : Bool := context.blockHeight\n" ++
    "    return x\n\n" ++
    "end ProofForgeV2.Examples\n"
  match ← session.selectProgramV1 badDirect
      "<solana-bad-height>" "Examples.BadHeightType" none with
  | .error _ => pure ()  -- type-check may reject at parse/select
  | .ok validated =>
      match Compiler.compileValidatedSourceV1 validated with
      | .error _ => pure ()
      | .ok compiledBad =>
          match planSolana compiledBad with
          | .error e =>
              expect
                (e.render.contains "blockHeight" ||
                  e.render.contains "UInt64" ||
                  e.render.contains "ContextRead" ||
                  e.render.contains "type" ||
                  e.render.contains "PF-")
                s!"height-box wrong type must FC, got {e.render}"
          | .ok _ =>
              throw <| IO.userError
                "height-box: Bool-typed context.blockHeight must fail closed"
  -- unixTimeSeconds still FC on ordinary Solana.
  let unixSrc :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program UnixBox where\n" ++
    "  state t : UInt64\n\n" ++
    "  init() do\n" ++
    "    t := 0\n\n" ++
    "  view now() : UInt64 do\n" ++
    "    return context.unixTimeSeconds\n\n" ++
    "end ProofForgeV2.Examples\n"
  let compiledUnix ← compileSource session unixSrc
    "Examples.UnixBox" "<solana-unix-box>"
  match planSolana compiledUnix with
  | .error e =>
      expect
        (e.render.contains "unixTimeSeconds" || e.render.contains "unix-time" ||
          e.render.contains "ContextRead" || e.render.contains "not admitted")
        s!"unixTimeSeconds must stay FC on ordinary Solana, got {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "unixTimeSeconds must fail closed on ordinary Solana pilot"
  -- caller still FC on ordinary (legacy) profiles.
  let callerSrc :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CallerBox where\n" ++
    "  state s : UInt64\n\n" ++
    "  init() do\n" ++
    "    s := 0\n\n" ++
    "  view who() : Principal do\n" ++
    "    return context.caller\n\n" ++
    "end ProofForgeV2.Examples\n"
  let compiledCaller ← compileSource session callerSrc
    "Examples.CallerBox" "<solana-caller-box>"
  match planSolana compiledCaller with
  | .error e =>
      expect
        (e.render.contains "caller" || e.render.contains "ContextRead" ||
          e.render.contains "CPI" || e.render.contains "not admitted" ||
          e.render.contains "Principal")
        s!"caller must stay FC on ordinary Solana, got {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "context.caller must fail closed on ordinary Solana (CPI-only)"
  IO.println "  ADR-0031 S2 context.blockHeight → Clock.slot Plan/IR/SBPF pin ok"

unsafe def run : IO Unit := do
  testNarrowIntAbi
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
  testExternalCallFailClosed session
  testVoidEntryRejected session
  testMultipleEvents session
  testIsolatedModZero session
  testZeroArgRevert session
  testBoolResultPureFn session
  testOmittedTypeLet session
  testMapMiniEmptyUpsertStructure session
  testTokenDualStoreBatchSeparation session
  testNamedStructState session
  testNamedEnumState session
  testBytesStateIndexOps session
  testNamedStructReturn session
  testNamedEnumReturn session
  testAnonymousArrayReturn session
  testAnonymousOptionReturn session
  testOptionState session
  testAggregateFailClosed session
  testContextReadBlockHeight session
  IO.println "Tests.Materialization.SolanaPlanV1: ok"

end Tests.Materialization.SolanaPlanV1
