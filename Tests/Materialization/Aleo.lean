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
private unsafe def testCounterPlanAndLeo : IO Unit := do
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
private unsafe def testPureOpsAndShifts : IO Unit := do
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
private unsafe def testBoundedForLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program LoopSum where\n" ++
    "  entry sumUp(n : UInt64) : UInt64 do\n" ++
    "    let acc : UInt64 := 0\n" ++
    "    for i in 0 .. n bounded 8 do\n" ++
    "      acc := acc + i\n" ++
    "    return acc\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-loop>" "Tests.AleoLoop" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.size == 1 && plan.functions[0]!.name == "sumUp")
    "LoopSum must carry the single entry"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "loopsum.aleo") |
    throw <| IO.userError "aleo: missing loopsum.aleo"
  let leo := leoFile.contents
  expect (leo.contains "for pf_c0 in 0u64..8u64 {")
    "bounded for must render as a constant-bound Leo for"
  expect (leo.contains "if pf_c0 < (pf_end0 - pf_start0) {")
    "runtime loop guard must gate the body"
  expect (leo.contains "if pf_start0 < pf_end0 {")
    "boundExceeded guard must be conditional on the loop actually starting"

/-- Honest fail-closed decisions: emit, revert payloads, computed views. -/
private unsafe def testFailClosedNegatives : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let expectPlanError (label : String) (sourceText : String) : IO Unit := do
    let parsed ← liftResult (← session.selectProgramV1
      sourceText s!"<aleo-neg-{label}>" s!"Tests.AleoNeg{label}" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
    match planAleo compiled with
    | .error (.planInvariant .aleo _) => pure ()
    | .error e => throw <| IO.userError s!"{label}: expected planInvariant, got {e.render}"
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
     "    revert Bad(x)\n" ++
     "    return x\n")
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

private unsafe def testPlanValidation : IO Unit := do
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

unsafe def run : IO Unit := do
  testCounterPlanAndLeo
  testPureOpsAndShifts
  testBoundedForLeo
  testFailClosedNegatives
  testPlanValidation
  IO.println "Tests.Materialization.Aleo: ok"

end Tests.Materialization.Aleo
