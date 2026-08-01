/-
  Aleo target leaf tests: capability-gated Plan/IR/emitter over the retained
  SemanticProgramV1 envelope. Covers the Counter shape (init guard + Final
  mutate + droppedReturn + bare view query), pure fns with shifts/bitwise/
  strict logical, bounded for, and the honest fail-closed decisions (emit,
  revert payloads, computed state-reading views).
-/
import ProofForgeV2
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline

namespace Tests.Materialization.Aleo

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def planAleo (compiled : CompiledSemanticV1) : CompileResult Targets.Aleo.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.aleo none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Aleo.planFromCapability capability

private def irAleo (compiled : CompiledSemanticV1) : CompileResult Targets.Aleo.IR := do
  let selection ← resolveBuildSelectionV1 TargetId.aleo none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Aleo.irFromCapability capability

private def materializeAleo (compiled : CompiledSemanticV1) :
    CompileResult MaterializedArtifactsV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.aleo none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.materializeResult capability

/-- Counter: init guard + state-touching entry (dropped return) + bare view. -/
unsafe def testCounterPlanAndLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Counter where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-counter>" "Tests.AleoCounter" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["initialize", "increment"])
    "Counter Aleo plan must carry initialize + increment in source order"
  let initFn := plan.functions[0]!
  expect (initFn.kind == .initialize && !initFn.resultDropped)
    "initialize must be the guarded Final function"
  let inc := plan.functions[1]!
  expect (inc.kind == .mutate && inc.touchesState && inc.resultDropped)
    "increment must touch state and drop its non-Unit result"
  expect (plan.views.map (·.name) == #["get"] && plan.views[0]!.stateFieldIndex == 0)
    "get must materialize as a bare state-read view query"
  liftResult <| Targets.Aleo.validatePlan plan
  let ir ← liftResult <| irAleo compiled
  expect (ir.program.programId == "counter")
    "Counter Leo program id must be the lowercased artifact name"
  liftResult <| Targets.Aleo.validateIR ir
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "counter.aleo") |
    throw <| IO.userError "aleo: missing counter.aleo"
  let leo := leoFile.contents
  expect (leo.contains "program counter.aleo {")
    "Leo source must declare the program"
  expect (leo.contains "mapping pf_state_0: u8 => u64;")
    "Leo source must declare the state mapping"
  expect (leo.contains "mapping initialized: u8 => bool;")
    "Leo source must declare the one-shot init guard mapping"
  expect (leo.contains "fn initialize(public p0: u64) -> Final {")
    "init must materialize as a Final function"
  expect (leo.contains "initialized.get_or_use(0u8, false)")
    "init guard must read the initialized mapping"
  expect (leo.contains "assert((!pf_seen));")
    "init guard must reject double initialization"
  expect (leo.contains "fn increment(public p0: u64) -> Final {")
    "increment must materialize as a Final function"
  expect (leo.contains "pf_state_0.get_or_use(0u8, 0u64)")
    "increment must read the state mapping in final context"
  expect (leo.contains "pf_state_0.set(0u8,")
    "increment must write the state mapping"
  expect (leo.contains "let pf_return: u64 =")
    "dropped return must still be evaluated in the final block"

/-- Pure fns and entries: shifts, bitwise, strict logical, Bool results. -/
unsafe def testPureOpsAndShifts : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BitLogic where\n" ++
    "  entry mask(x : UInt64) : UInt64 do\n" ++
    "    return (x << 2) & 15 | (x >> 1) ^ 3\n" ++
    "  entry both(a : UInt64, b : UInt64) : Bool do\n" ++
    "    return a > 0 && b > 0\n" ++
    "  entry flip(x : UInt64) : UInt64 do\n" ++
    "    return ~x\n" ++
    "  fn double(a : UInt64) : UInt64 do\n" ++
    "    return a + a\n" ++
    "  entry scaled(x : UInt64) : UInt64 do\n" ++
    "    return double(x)\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-bitlogic>" "Tests.AleoBitLogic" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["mask", "both", "flip", "double", "scaled"])
    "BitLogic Aleo plan must carry five callables in source order"
  expect (plan.functions.all fun fn => !fn.touchesState && !fn.resultDropped)
    "pure entries and fns must not touch state and must keep their results"
  liftResult <| Targets.Aleo.validatePlan plan
  let ir ← liftResult <| irAleo compiled
  let leoFns := ir.program.functions
  expect (leoFns.all fun fn => !fn.isFinal)
    "BitLogic must materialize entirely as plain (non-Final) functions"
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "bitlogic.aleo") |
    throw <| IO.userError "aleo: missing bitlogic.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn mask(public p0: u64) -> u64 {")
    "mask must be a plain u64-returning function"
  expect (leo.contains " << ")
    "Leo source must render the shift operator"
  expect (leo.contains "assert((")
    "shift count guard must be emitted"
  expect (leo.contains "fn both(public p0: u64, public p1: u64) -> boolean {")
    "Bool-returning entry must render a boolean result"
  expect (leo.contains " && ")
    "strict logical and must render"
  expect (leo.contains "fn flip(public p0: u64) -> u64 {")
    "flip must be a plain function"
  expect (leo.contains "(!")
    "bitNot must render as Leo type-directed !"
  expect (leo.contains "fn double(public p0: u64) -> u64 {")
    "pure fn must materialize as a plain function"
  expect (leo.contains "scaled(public p0: u64) -> u64")
    "scaled must materialize as a plain function"

/-- Bounded for: constant-bound loop with the boundExceeded guard. -/
unsafe def testBoundedForLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program LoopSum where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry sumUp(n : UInt64) : UInt64 do\n" ++
    "    let zero : UInt64 := 0\n" ++
    "    for i in zero ..< n bounded 8 do\n" ++
    "      count := count + i\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-loop>" "Tests.AleoLoop" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["initialize", "sumUp"])
    "LoopSum must carry initialize + sumUp in source order"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "loopsum.aleo") |
    throw <| IO.userError "aleo: missing loopsum.aleo"
  let leo := leoFile.contents
  expect (leo.contains "for pf_c0 in 0u64..8u64 {")
    "bounded for must render as a constant-bound Leo for"
  expect (leo.contains "if (pf_c0 < (pf_end0 - pf_start0)) {")
    "runtime loop guard must gate the body"
  expect (leo.contains "if (pf_start0 < pf_end0) {")
    "boundExceeded guard must be conditional on the loop actually starting"

/-- Honest fail-closed decisions: emit, revert payloads, computed views. -/
unsafe def testFailClosedNegatives : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- The honest per-target support row rejects `effect.event` at the resolver
  -- (PF-REQ-UNSUPPORTED); other unsupported shapes reach the plan and fail
  -- with planInvariant. Both are fail-closed.
  let expectPlanError (label : String) (sourceText : String) : IO Unit := do
    let moduleName := s!"Tests.AleoNeg{(label.replace "-" "")}"
    let parsed ← liftResult (← session.selectProgramV1
      sourceText s!"<aleo-neg-{label}>" moduleName none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
    match planAleo compiled with
    | .error (.planInvariant .aleo _) => pure ()
    | .error (.unsupportedRequirementV1 _) => pure ()
    | .error e => throw <| IO.userError s!"{label}: expected fail-closed, got {e.render}"
    | .ok _ => throw <| IO.userError s!"{label}: must fail closed"
  -- emit has no Leo on-chain analogue.
  expectPlanError "emit"
    ("import ProofForgeV2\n" ++
     "open ProofForgeV2.Language\n" ++
     "program Emitter where\n" ++
     "  event Ticked(value : UInt64)\n" ++
     "  entry tick(x : UInt64) : UInt64 do\n" ++
     "    emit Ticked(x)\n" ++
     "    return x\n")
  -- revert payloads cannot be represented in Leo.
  expectPlanError "revert-args"
    ("import ProofForgeV2\n" ++
     "open ProofForgeV2.Language\n" ++
     "program Reverter where\n" ++
     "  error Bad(why : UInt64)\n" ++
     "  entry fail(x : UInt64) : UInt64 do\n" ++
     "    revert Bad(x)\n")
  -- computed views that read state have no on-chain or query materialization.
  expectPlanError "computed-view"
    ("import ProofForgeV2\n" ++
     "open ProofForgeV2.Language\n" ++
     "program Viewy where\n" ++
     "  state count : UInt64\n" ++
     "  init(initial : UInt64) do\n" ++
     "    count := initial\n" ++
     "  view doubled() : UInt64 do\n" ++
     "    return count * 2\n")

unsafe def testPlanValidation : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Tiny where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump() : UInt64 do\n" ++
    "    count := count + 1\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-tiny>" "Tests.AleoTiny" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  liftResult <| Targets.Aleo.validatePlan plan
  -- Hand-built malformed: a droppedReturn on a pure function must be rejected.
  let pureFn : Targets.Aleo.PlanFunction := {
    index := 0
    name := "pureish"
    kind := .mutate
    params := #[]
    body := #[.returnValue (.literal 1)]
    touchesState := false
    resultIsBool := false
    resultDropped := true
  }
  let badPlan : Targets.Aleo.Plan := {
    programName := "Tiny"
    stateFieldNames := #["count"]
    functions := #[pureFn]
    views := #[]
    sourceHash := plan.sourceHash
    semanticHash := plan.semanticHash
  }
  match Targets.Aleo.validatePlan badPlan with
  | .error (.planInvariant .aleo _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject resultDropped on a pure function"
  -- Reserved Leo word as a function name must be rejected.
  let reservedFn : Targets.Aleo.PlanFunction := {
    index := 0
    name := "final"
    kind := .mutate
    params := #[]
    body := #[.returnValue (.literal 1)]
    touchesState := false
    resultIsBool := false
    resultDropped := false
  }
  let badPlan2 : Targets.Aleo.Plan := {
    programName := "Tiny"
    stateFieldNames := #["count"]
    functions := #[reservedFn]
    views := #[]
    sourceHash := plan.sourceHash
    semanticHash := plan.semanticHash
  }
  match Targets.Aleo.validatePlan badPlan2 with
  | .error (.planInvariant .aleo _) => pure ()
  | _ => throw <| IO.userError "validatePlan must reject reserved Leo words"

/-- if/else with state writes renders as Leo if/else in the Final block. -/
unsafe def testIfElseLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Branch where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry pick() : UInt64 do\n" ++
    "    if count > 10 then\n" ++
    "      count := count - 1\n" ++
    "    else\n" ++
    "      count := count + 1\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-branch>" "Tests.AleoBranch" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["initialize", "pick"])
    "Branch Aleo plan must carry initialize + pick"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "branch.aleo") |
    throw <| IO.userError "aleo: missing branch.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn pick() -> Final {")
    "pick must materialize as a Final function"
  expect (leo.contains "if ")
    "if/else must render the Leo if keyword"
  expect (leo.contains "} else {")
    "if/else must render the else branch"
  expect (leo.contains "pf_state_0.set(0u8,")
    "both arms must write the state mapping"

/-- match with two literal arms + catch-all lowers via switchOn to a nested
    if/else chain comparing the scrutinee. -/
unsafe def testMatchLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Pick where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry apply(delta : UInt64) : UInt64 do\n" ++
    "    match delta with\n" ++
    "    | 0 => do\n" ++
    "      count := 0\n" ++
    "    | 1 => do\n" ++
    "      count := count + 1\n" ++
    "    | _ => do\n" ++
    "      count := delta\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-pick>" "Tests.AleoPick" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["initialize", "apply"])
    "Pick Aleo plan must carry initialize + apply"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "pick.aleo") |
    throw <| IO.userError "aleo: missing pick.aleo"
  let leo := leoFile.contents
  -- switchOn emission folds cases into a right-nested if/else chain whose
  -- conditions are `(scrutinee == <literal>)`.
  expect (leo.contains " == 0u64)")
    "match arm 0 must compare the scrutinee to 0u64"
  expect (leo.contains " == 1u64)")
    "match arm 1 must compare the scrutinee to 1u64"
  expect (leo.contains "if ")
    "switchOn must lower to Leo if"
  expect (leo.contains "} else {")
    "switchOn must lower to a nested if/else chain"
  expect (leo.contains "pf_state_0.set(0u8,")
    "match arms must write the state mapping"

/-- mul / div / mod: native * for mul; div/mod emit an explicit nonzero assert. -/
unsafe def testMulDivModLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Arith where\n" ++
    "  entry product(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return a * b\n" ++
    "  entry quotient(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return a / b\n" ++
    "  entry remainder(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return a % b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-arith>" "Tests.AleoArith" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["product", "quotient", "remainder"])
    "Arith Aleo plan must carry three pure entries"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "arith.aleo") |
    throw <| IO.userError "aleo: missing arith.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn product(public p0: u64, public p1: u64) -> u64 {")
    "product must be a plain u64-returning function"
  expect (leo.contains " * ")
    "mul must render as Leo *"
  expect (leo.contains "fn quotient(public p0: u64, public p1: u64) -> u64 {")
    "quotient must be a plain u64-returning function"
  -- EmitIRV1: div/mod emit `assert((rhs != 0u64));` then the op binding.
  expect (leo.contains "assert((p1 != 0u64));")
    "div/mod must emit the nonzero guard on the divisor"
  expect (leo.contains " / ")
    "div must render as Leo /"
  expect (leo.contains "fn remainder(public p0: u64, public p1: u64) -> u64 {")
    "remainder must be a plain u64-returning function"
  expect (leo.contains " % ")
    "mod must render as Leo %"

/-- checked sub renders as Leo `-` (underflow is Leo-native checked halt). -/
unsafe def testCheckedSubLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Diff where\n" ++
    "  entry sub(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return a - b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-diff>" "Tests.AleoDiff" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["sub"])
    "Diff Aleo plan must carry the pure sub entry"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "diff.aleo") |
    throw <| IO.userError "aleo: missing diff.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn sub(public p0: u64, public p1: u64) -> u64 {")
    "sub must be a plain u64-returning function"
  -- EmitIRV1 binds checkedSub as `let pf_eN: u64 = (lhs - rhs);` with no
  -- explicit underflow assert (Leo 4.0.2 native checked arithmetic).
  expect (leo.contains " - ")
    "checked sub must render as Leo -"
  expect (leo.contains "let pf_e0: u64 = (p0 - p1);")
    "checked sub must bind the subtraction result"

/-- All six comparisons in one Bool-returning entry. -/
unsafe def testComparisonsLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Cmp where\n" ++
    "  entry cmp(a : UInt64, b : UInt64) : Bool do\n" ++
    "    return a == b || a != b || a < b || a <= b || a > b || a >= b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-cmp>" "Tests.AleoCmp" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["cmp"])
    "Cmp Aleo plan must carry the pure cmp entry"
  expect (plan.functions[0]!.resultIsBool)
    "cmp must be marked Bool-returning"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "cmp.aleo") |
    throw <| IO.userError "aleo: missing cmp.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn cmp(public p0: u64, public p1: u64) -> boolean {")
    "Bool-returning entry must render a boolean result"
  for op in #["==", "!=", "<", "<=", ">", ">="] do
    expect (leo.contains s!" {op} ")
      s!"comparison operator {op} must render"

/-- Logical or and Bool negation render as Leo || / !. -/
unsafe def testLogicalLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Log where\n" ++
    "  entry both(a : UInt64, b : UInt64) : Bool do\n" ++
    "    return !(a == 0 || b == 0)\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-log>" "Tests.AleoLog" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["both"])
    "Log Aleo plan must carry the pure both entry"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "log.aleo") |
    throw <| IO.userError "aleo: missing log.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn both(public p0: u64, public p1: u64) -> boolean {")
    "both must be a plain boolean-returning function"
  expect (leo.contains " || ")
    "logical or must render as Leo ||"
  -- boolNot binds `let pf_eN: boolean = (!operand);`
  expect (leo.contains "let pf_")
    "boolNot must bind an intermediate boolean"
  expect (leo.contains "(!")
    "Bool negation must render as Leo type-directed !"

/-- Bare assert lowers to Leo `assert(...)`. -/
unsafe def testAssertLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Guard where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry take(delta : UInt64) : UInt64 do\n" ++
    "    assert count >= delta\n" ++
    "    count := count - delta\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-guard>" "Tests.AleoGuard" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["initialize", "take"])
    "Guard Aleo plan must carry initialize + take"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "guard.aleo") |
    throw <| IO.userError "aleo: missing guard.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn take(public p0: u64) -> Final {")
    "take must materialize as a Final function"
  -- Compare is bound, then asserted: `assert(pf_eN);`
  expect (leo.contains "assert(pf_")
    "bare assert must render as Leo assert(...)"
  expect (leo.contains " >= ")
    "assert condition must carry the >= comparison"

/-- assert-with-else is outside the envelope: S1 Normalize rejects it before
    the Aleo lowerer (which would also reject with planInvariant). Product
    path fails closed with PF-SRC-INVALID. -/
unsafe def testAssertElseFailClosedLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program GuardElse where\n" ++
    "  state count : UInt64\n" ++
    "  error Guard\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    assert x > 0 else Guard\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-guard-else>" "Tests.AleoGuardElse" none)
  -- Product path: Normalize rejects assert-else (sole authority). The Aleo
  -- lowerer independently fails closed with "Aleo assert-else is outside the
  -- envelope" if a residual carrier ever reached planFromCapability.
  match Compiler.compileValidatedSourceV1 parsed with
  | .error e =>
      expect (e.code == "PF-SRC-INVALID" && e.render.contains "assert-else")
        s!"assert-else must fail closed at Normalize with assert-else, got: {e.render}"
  | .ok compiled =>
      match planAleo compiled with
      | .error (.planInvariant .aleo msg) =>
          expect (msg.contains "assert-else")
            s!"assert-else planInvariant must mention assert-else, got: {msg}"
      | .error e =>
          throw <| IO.userError s!"assert-else: expected planInvariant .aleo, got {e.render}"
      | .ok _ => throw <| IO.userError "assert-else must fail closed at Aleo plan"

/-- Bare zero-arg `revert Err` lowers to Leo `assert(false)`. -/
unsafe def testBareRevertLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Stop where\n" ++
    "  state count : UInt64\n" ++
    "  error Cap\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    if x == 0 then\n" ++
    "      revert Cap\n" ++
    "    else\n" ++
    "      return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-stop>" "Tests.AleoStop" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["initialize", "run"])
    "Stop Aleo plan must carry initialize + run"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "stop.aleo") |
    throw <| IO.userError "aleo: missing stop.aleo"
  let leo := leoFile.contents
  expect (leo.contains "assert(false);")
    "bare zero-arg revert must lower to assert(false)"

/-- Two state fields materialize as distinct pf_state mappings. -/
unsafe def testMultiStateLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Dual where\n" ++
    "  state count : UInt64\n" ++
    "  state balance : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "    balance := initial\n" ++
    "  entry go(x : UInt64) : UInt64 do\n" ++
    "    count := count + x\n" ++
    "    balance := balance + x\n" ++
    "    return count\n" ++
    "  view getCount() : UInt64 do\n" ++
    "    return count\n" ++
    "  view getBalance() : UInt64 do\n" ++
    "    return balance\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-dual>" "Tests.AleoDual" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.stateFieldNames == #["count", "balance"])
    "Dual plan must carry both state fields in source order"
  expect (plan.views.map (·.name) == #["getCount", "getBalance"])
    "Dual plan must carry both bare views"
  expect (plan.views[0]!.stateFieldIndex == 0 && plan.views[1]!.stateFieldIndex == 1)
    "views must bind the matching state field indices"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "dual.aleo") |
    throw <| IO.userError "aleo: missing dual.aleo"
  let leo := leoFile.contents
  expect (leo.contains "mapping pf_state_0: u8 => u64;")
    "first state field must render as pf_state_0"
  expect (leo.contains "mapping pf_state_1: u8 => u64;")
    "second state field must render as pf_state_1"
  expect (leo.contains "pf_state_0.set(0u8,")
    "go must write pf_state_0"
  expect (leo.contains "pf_state_1.set(0u8,")
    "go must write pf_state_1"

/-- Unit-result entry without an explicit value return is rejected on the
    product path: S1 Normalize requires an explicit return for entry/view and
    rejects bare `return` (return none). Init is the only Unit callable that
    may omit a return (allowImplicitReturnNone). Pin the fail-closed surface;
    Leo Unit Final rendering is exercised by initialize in Counter. -/
unsafe def testVoidEntryLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Void where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) do\n" ++
    "    count := count + delta\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-void>" "Tests.AleoVoid" none)
  match Compiler.compileValidatedSourceV1 parsed with
  | .error e =>
      expect (e.code == "PF-SRC-INVALID" &&
          (e.render.contains "explicit return" || e.render.contains "bare return"))
        s!"void entry must fail closed at Normalize, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "void Unit entry without value return must fail closed at product compile"

/-- Multi-param pure fn + Bool-returning helper called from an entry. -/
unsafe def testMultiParamFnLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Helpers where\n" ++
    "  fn add(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return a + b\n" ++
    "  fn above(a : UInt64, b : UInt64) : Bool do\n" ++
    "    return a > b\n" ++
    "  entry go(x : UInt64) : Bool do\n" ++
    "    return above(add(x, 1), x)\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-helpers>" "Tests.AleoHelpers" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["add", "above", "go"])
    "Helpers Aleo plan must carry add + above + go in source order"
  expect (plan.functions.all fun fn => !fn.touchesState && !fn.resultDropped)
    "pure helpers and entry must not touch state"
  expect (plan.functions[1]!.resultIsBool && plan.functions[2]!.resultIsBool)
    "above and go must be Bool-returning"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "helpers.aleo") |
    throw <| IO.userError "aleo: missing helpers.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn add(public p0: u64, public p1: u64) -> u64 {")
    "multi-param UInt64 fn must render both public params"
  expect (leo.contains "fn above(public p0: u64, public p1: u64) -> boolean {")
    "multi-param Bool fn must render a boolean result"
  expect (leo.contains "fn go(public p0: u64) -> boolean {")
    "Bool entry must render a boolean result"
  expect (leo.contains "add(")
    "entry must call the add helper"
  expect (leo.contains "above(")
    "entry must call the above helper"

/-- Product-path fail-closed: Aleo declines sync call and async schedule with
    PF-REQ-UNSUPPORTED at the capability resolver. -/
unsafe def testCallScheduleFailClosedLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let callSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CallPeer where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(x : UInt64) : UInt64 do\n" ++
    "    call Peer.go(x)\n" ++
    "    return count\n"
  let callParsed ← liftResult (← session.selectProgramV1
    callSource "<aleo-call>" "Tests.AleoCallPeer" none)
  let callCompiled ← liftResult <| Compiler.compileValidatedSourceV1 callParsed
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.aleo none
  match Targets.resolveEngineeringRequirementsV1 selection callCompiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"Aleo must reject effect.synchronous-call with PF-REQ-UNSUPPORTED, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "Aleo unexpectedly supports the sync-call key"
  let scheduleSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program LaterPeer where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry later(x : UInt64) : UInt64 do\n" ++
    "    schedule ledger.daily(x)\n" ++
    "    return count\n"
  let scheduleParsed ← liftResult (← session.selectProgramV1
    scheduleSource "<aleo-schedule>" "Tests.AleoLaterPeer" none)
  let scheduleCompiled ← liftResult <| Compiler.compileValidatedSourceV1 scheduleParsed
  match Targets.resolveEngineeringRequirementsV1 selection scheduleCompiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"Aleo must reject effect.asynchronous-workflow with PF-REQ-UNSUPPORTED, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "Aleo unexpectedly supports the async-workflow key"

unsafe def run : IO Unit := do
  testCounterPlanAndLeo
  testPureOpsAndShifts
  testBoundedForLeo
  testFailClosedNegatives
  testPlanValidation
  testIfElseLeo
  testMatchLeo
  testMulDivModLeo
  testCheckedSubLeo
  testComparisonsLeo
  testLogicalLeo
  testAssertLeo
  testAssertElseFailClosedLeo
  testBareRevertLeo
  testMultiStateLeo
  testVoidEntryLeo
  testMultiParamFnLeo
  testCallScheduleFailClosedLeo
  IO.println "Tests.Materialization.Aleo: ok"

end Tests.Materialization.Aleo
