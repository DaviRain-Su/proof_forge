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
  expect (leo.contains "constructor() {}")
    "Leo 4 requires a closed empty constructor before mappings"
  expect (leo.contains "return final {")
    "Final functions must use return final { ... }; form"
  expect (leo.contains "    };\n")
    "return final block must end with a trailing semicolon"
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
  expect (!leo.contains "boolean")
    "Leo 4 keyword is bool, not boolean"
  expect (!leo.contains "return ();")
    "Leo 4 rejects return () unit tuples"

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
    "  fn dbl(a : UInt64) : UInt64 do\n" ++
    "    return a + a\n" ++
    "  entry scaled(x : UInt64) : UInt64 do\n" ++
    "    return dbl(x)\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-bitlogic>" "Tests.AleoBitLogic" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["mask", "both", "flip", "dbl", "scaled"])
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
  expect (leo.contains "fn both(public p0: u64, public p1: u64) -> bool {")
    "Bool-returning entry must render a bool result"
  expect (leo.contains " && ")
    "strict logical and must render"
  expect (leo.contains "fn flip(public p0: u64) -> u64 {")
    "flip must be a plain function"
  expect (leo.contains "(!")
    "bitNot must render as Leo type-directed !"
  -- pureFn is a Leo 4 helper outside `program` (no input modes).
  expect (leo.contains "fn dbl(p0: u64) -> u64 {")
    "pure fn must materialize as a file-level helper without public modes"
  expect (leo.contains "scaled(public p0: u64) -> u64")
    "scaled must materialize as a plain entry function"
  expect (leo.contains " as u8)")
    "shift count must cast to u8 for Leo 4.0.2"

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
    stateFieldIsInt := #[false]
    stateFieldIsU8 := #[false]
    stateFieldIsField := #[false]
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
    stateFieldIsInt := #[false]
    stateFieldIsU8 := #[false]
    stateFieldIsField := #[false]
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
    "  entry subtract(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return a - b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-diff>" "Tests.AleoDiff" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["subtract"])
    "Diff Aleo plan must carry the pure subtract entry"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "diff.aleo") |
    throw <| IO.userError "aleo: missing diff.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn subtract(public p0: u64, public p1: u64) -> u64 {")
    "subtract must be a plain u64-returning function"
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
  expect (leo.contains "fn cmp(public p0: u64, public p1: u64) -> bool {")
    "Bool-returning entry must render a bool result"
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
  expect (leo.contains "fn both(public p0: u64, public p1: u64) -> bool {")
    "both must be a plain bool-returning function"
  expect (leo.contains " || ")
    "logical or must render as Leo ||"
  -- boolNot binds `let pf_eN: bool = (!operand);`
  expect (leo.contains "let pf_")
    "boolNot must bind an intermediate bool"
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

/-- L1 / N-ASSERT-ELSE: `assert cond else ParamErr` where ParamErr declares a
    field is rejected by the shared-core TypeCheck arity gate (source
    `assert Expr else Ident` carries no args). Product path fails closed with
    PF-SRC-INVALID before any Aleo plan is produced. (Aleo's lowerer would
    silently drop a zero-arg errorId; pinning the parameterized case at the
    shared core avoids that drop and keeps assert-else fail closed.) -/
unsafe def testAssertElseFailClosedLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program GuardElse where\n" ++
    "  state count : UInt64\n" ++
    "  error Guard(limit : UInt64)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    assert x > 0 else Guard\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-guard-else>" "Tests.AleoGuardElse" none)
  -- Product path: shared-core TypeCheck arity gate rejects assert-else on a
  -- parameterized error (source `assert Expr else Ident` carries no args)
  -- before any Aleo plan is produced → PF-SRC-INVALID.
  match Compiler.compileValidatedSourceV1 parsed with
  | .error e =>
      expect (e.code == "PF-SRC-INVALID" && e.render.contains "arguments")
        s!"assert-else must fail closed at shared core with arguments mismatch, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError "assert-else (parameterized error) must fail closed at shared core, got compile ok"

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
    "  fn plus(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return a + b\n" ++
    "  fn above(a : UInt64, b : UInt64) : Bool do\n" ++
    "    return a > b\n" ++
    "  entry go(x : UInt64) : Bool do\n" ++
    "    return above(plus(x, 1), x)\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-helpers>" "Tests.AleoHelpers" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["plus", "above", "go"])
    "Helpers Aleo plan must carry plus + above + go in source order"
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
  expect (leo.contains "fn plus(p0: u64, p1: u64) -> u64 {")
    "UInt64 pureFn must render as a file-level helper without public"
  expect (leo.contains "fn above(p0: u64, p1: u64) -> bool {")
    "multi-param Bool pureFn must render as a file-level helper"
  expect (leo.contains "fn go(public p0: u64) -> bool {")
    "Bool entry must render a bool result"
  expect (leo.contains "plus(")
    "entry must call the plus helper"
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

/-- Aleo Field research pin (2026-08-01 AleoCoverage): catalog bn254_fr fails
    closed at type-closure. Native Aleo `field` is BLS12-377 Fr (Edwards BLS
    scalar), not bn254 Fr — wording must cite BLS12-377 / bn254 so no silent
    wrong-field mapping can land later. -/
unsafe def testFieldBn254FailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program FieldPin where\n" ++
    "  state acc : Field bn254_fr\n" ++
    "  init(initial : Field bn254_fr) do\n" ++
    "    acc := initial\n" ++
    "  entry bump(delta : Field bn254_fr) : Field bn254_fr do\n" ++
    "    acc := acc + delta\n" ++
    "    return acc\n" ++
    "  view get() : Field bn254_fr do\n" ++
    "    return acc\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-field-pin>" "Tests.FieldPinAleo" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planAleo compiled with
  | .ok _ =>
      throw <| IO.userError
        "Field bn254_fr must fail closed at Aleo type-closure (BLS12-377 Fr ≠ bn254 Fr)"
  | .error e =>
      let msg := e.render
      expect (msg.contains "Field" || msg.contains "unsupported" ||
          msg.contains "BLS12" || msg.contains "bn254")
        s!"Aleo Field decline must cite Field/BLS12/bn254 boundary, got: {msg}"
      expect (msg.contains "BLS12-377" || msg.contains "BLS12" ||
          msg.contains "bn254 Fr" || msg.contains "Edwards")
        s!"Aleo Field decline must cite BLS12-377 Fr vs bn254 Fr, got: {msg}"
      expect (msg.contains "Aleo" || msg.contains "aleo")
        s!"Aleo Field decline must label Aleo, got: {msg}"

/-- T14 catalog v2 (BLS12-377): Field bls12_377_fr state/param/body lowers to
    native Leo `field`. State is a `field` mapping value; add lowers to native
    Leo field arithmetic (exact mod BLS12-377 Fr; no checked-overflow guard).
    Engineering slice — not formal D2/D4. -/
unsafe def testBls12377FieldStateArith : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BlsFieldBox where\n" ++
    "  state acc : Field bls12_377_fr\n" ++
    "  init(initial : Field bls12_377_fr) do\n" ++
    "    acc := initial\n" ++
    "  entry bump(delta : Field bls12_377_fr) : Field bls12_377_fr do\n" ++
    "    acc := acc + delta\n" ++
    "    return acc\n" ++
    "  view get() : Field bls12_377_fr do\n" ++
    "    return acc\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-bls-field>" "Tests.BlsFieldBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.stateFieldNames == #["acc"])
    s!"BLS12-377 plan must carry the acc field state leaf, got {plan.stateFieldNames}"
  expect (plan.stateFieldIsField == #[true])
    "BLS12-377 acc state leaf must be flagged as field"
  let some bump := plan.functions.find? (·.name == "bump") |
    throw <| IO.userError
      s!"BLS12-377 plan must carry the bump entry, got {plan.functions.map (·.name)}"
  expect (bump.resultIsField)
    "BLS12-377 bump entry result must be flagged as field"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "blsfieldbox.aleo") |
    throw <| IO.userError "aleo: missing blsfieldbox.aleo"
  let leo := leoFile.contents
  expect (leo.contains "mapping pf_state_0: u8 => field;")
    s!"Aleo BLS12-377 source must declare the acc field mapping, got:\n{leo}"
  expect (leo.contains "public p0: field")
    s!"Aleo BLS12-377 bump param must be `public p0: field`, got:\n{leo}"
  -- Native Leo field add (no checked-overflow guard; exact mod BLS12-377 Fr).
  expect (leo.contains " + p0")
    s!"Aleo BLS12-377 add must lower to native field + p0, got:\n{leo}"
  expect (!leo.contains "add overflow")
    "Aleo BLS12-377 field add must NOT emit a u64 overflow guard"

/-- H3 PsyAleoAggregate: named Struct flattens to two u64 mappings (p_x/p_y).
    Field assign + bare field view lower to leaf stateLoad/store. -/
unsafe def testNamedAggregateLowered : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2
" ++
    "open ProofForgeV2.Language
" ++
    "program PointBox where
" ++
    "  struct Point where
" ++
    "    x : UInt64
" ++
    "    y : UInt64
" ++
    "  state p : Point
" ++
    "  init() do
" ++
    "    p := Point.new(0, 0)
" ++
    "  entry setX(v : UInt64) : UInt64 do
" ++
    "    p.x := v
" ++
    "    return p.x
" ++
    "  view getX() : UInt64 do
" ++
    "    return p.x
"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-point>" "Tests.PointBoxAleo" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.stateFieldNames == #["p_x", "p_y"])
    s!"Aleo named Struct must flatten to p_x/p_y leaves, got {plan.stateFieldNames}"
  expect (plan.functions.map (·.name) == #["initialize", "setX"])
    s!"Aleo Point must carry initialize+setX, got {plan.functions.map (·.name)}"
  expect (plan.views.map (·.name) == #["getX"])
    "Aleo getX must materialize as bare leaf view"
  expect (plan.views[0]!.stateFieldIndex == 0)
    "Aleo getX bare view must bind p_x (leaf 0)"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "pointbox.aleo") |
    throw <| IO.userError "aleo: missing pointbox.aleo"
  let leo := leoFile.contents
  expect (leo.contains "mapping pf_state_0: u8 => u64;")
    "Aleo Point must emit pf_state_0 for p_x"
  expect (leo.contains "mapping pf_state_1: u8 => u64;")
    "Aleo Point must emit pf_state_1 for p_y"
  expect (leo.contains "pf_state_0.set(0u8,")
    "setX must write the x leaf mapping"
  expect (leo.contains "program pointbox.aleo {")
    "Leo program id must not contain the substring aleo"

/-- H3: fixed Array UInt64 2 flattens to slots_0/slots_1 mappings. -/
unsafe def testArrayStateLowered : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2
" ++
    "open ProofForgeV2.Language
" ++
    "program ArrBox where
" ++
    "  state slots : Array UInt64 2
" ++
    "  init() do
" ++
    "    slots[0] := 0
" ++
    "    slots[1] := 0
" ++
    "  entry set0(v : UInt64) : UInt64 do
" ++
    "    slots[0] := v
" ++
    "    return slots[0]
"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-arr>" "Tests.ArrBoxAleo" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.stateFieldNames == #["slots_0", "slots_1"])
    s!"Aleo Array must flatten to slots_0/slots_1, got {plan.stateFieldNames}"
  expect (plan.functions.any (·.name == "set0"))
    "Aleo Array plan must carry set0"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "arrbox.aleo") |
    throw <| IO.userError "aleo: missing arrbox.aleo"
  let leo := leoFile.contents
  expect (leo.contains "mapping pf_state_0: u8 => u64;")
    "Aleo Array must emit pf_state_0 for slots_0"
  expect (leo.contains "mapping pf_state_1: u8 => u64;")
    "Aleo Array must emit pf_state_1 for slots_1"

/-- N5 Commit identity: label-only passthrough into commitment state. -/
unsafe def testCommitIdentityLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CommitSeal where\n" ++
    "  state commitment sealed : UInt64\n" ++
    "  init() do\n" ++
    "    sealed := 0\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    sealed := commit(x)\n" ++
    "    return x\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-commit>" "Tests.AleoCommitSeal" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["initialize", "run"])
    "CommitSeal must carry initialize + run"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "commitseal.aleo") |
    throw <| IO.userError "aleo: missing commitseal.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn run(public p0: u64) -> Final {")
    "commit identity entry must materialize as Final"
  expect (leo.contains "pf_state_0.set(0u8,")
    "commit identity must store the passthrough operand into the mapping"
  expect (leo.contains "p0")
    "commit identity must still evaluate the sealed operand (param p0)"

/-- N5 ContextRead fails closed (no host clock ABI). -/
unsafe def testContextReadFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CtxTime where\n" ++
    "  state public pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry now() : UInt64 do\n" ++
    "    return context.unixTimeSeconds\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-ctx>" "Tests.AleoCtxTime" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planAleo compiled with
  | .ok _ =>
      throw <| IO.userError "ContextRead must fail closed on Aleo"
  | .error e =>
      let msg := e.render
      expect (msg.contains "ContextRead" || msg.contains "context" ||
          msg.contains "unix-time" || msg.contains "unsupported" ||
          msg.contains "pilot")
        s!"Aleo ContextRead decline must cite context boundary, got: {msg}"

/-- Int64 state/params: checked signed arithmetic lowers to Leo i64 with
    i64 mappings and i64 dropped returns. -/
unsafe def testInt64StateArithLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Temp where\n" ++
    "  state acc : Int64\n" ++
    "  init(seed : Int64) do\n" ++
    "    acc := seed\n" ++
    "  entry bump(delta : Int64) : Int64 do\n" ++
    "    acc := acc + delta\n" ++
    "    return acc\n" ++
    "  entry scale(a : Int64, b : Int64) : Int64 do\n" ++
    "    return a * b\n" ++
    "  entry diff(a : Int64, b : Int64) : Int64 do\n" ++
    "    return a - b\n" ++
    "  entry quot(a : Int64, b : Int64) : Int64 do\n" ++
    "    return a / b\n" ++
    "  entry remainder(a : Int64, b : Int64) : Int64 do\n" ++
    "    return a % b\n" ++
    "  view get() : Int64 do\n" ++
    "    return acc\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-i64-arith>" "Tests.AleoI64Arith" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.stateFieldNames == #["acc"])
    "Int64 plan must carry the acc state field"
  expect (plan.stateFieldIsInt == #[true])
    "Int64 state leaf must be marked signed"
  let bump := plan.functions.find? (·.name == "bump")
  match bump with
  | some fn =>
      expect (fn.resultIsInt && fn.resultDropped && fn.touchesState)
        "Int64 state-touching entry must drop an i64 result"
      expect (fn.params.all (·.isInt))
        "Int64 entry params must be marked signed"
  | none => throw <| IO.userError "missing bump"
  let scale := plan.functions.find? (·.name == "scale")
  match scale with
  | some fn =>
      expect (fn.resultIsInt && !fn.touchesState)
        "pure Int64 entry must keep an i64 result"
  | none => throw <| IO.userError "missing scale"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "temp.aleo") |
    throw <| IO.userError "aleo: missing temp.aleo"
  let leo := leoFile.contents
  expect (leo.contains "mapping pf_state_0: u8 => i64;")
    "Int64 state must render an i64 mapping"
  expect (leo.contains "fn initialize(public p0: i64) -> Final {")
    "init must take an i64 public param"
  expect (leo.contains "pf_state_0.get_or_use(0u8, 0i64)")
    "Int64 stateLoad must default to 0i64"
  expect (leo.contains "let pf_e")
    "signed add must bind an intermediate"
  expect (leo.contains ": i64 = ")
    "signed arithmetic must bind i64 lets"
  expect (leo.contains "let pf_return: i64 =")
    "dropped Int64 return must bind an i64 pf_return"
  expect (leo.contains "fn scale(public p0: i64, public p1: i64) -> i64 {")
    "pure Int64 entry must return i64"
  expect (leo.contains " / ")
    "signed div must render Leo /"
  expect (leo.contains " % ")
    "signed mod must render Leo %"
  expect (leo.contains "assert((p1 != 0i64));")
    "signed div/mod must guard the i64 divisor against zero"
  -- The bare Int64 view materializes as an off-chain query (Plan view), so
  -- no view function appears inside the Leo program.
  expect (!leo.contains "fn get(")
    "bare Int64 view must not materialize as an on-chain Leo function"

/-- Int64 six comparisons render with Leo native signed i64 operators. -/
unsafe def testInt64ComparisonsLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CmpI where\n" ++
    "  entry cmp(a : Int64, b : Int64) : Bool do\n" ++
    "    return a == b || a != b || a < b || a <= b || a > b || a >= b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-cmpi>" "Tests.AleoCmpI" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  let cmp := plan.functions.find? (·.name == "cmp")
  match cmp with
  | some fn =>
      expect (fn.resultIsBool && fn.params.all (·.isInt))
        "Int64 comparison entry must be Bool-returning with signed params"
  | none => throw <| IO.userError "missing cmp"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "cmpi.aleo") |
    throw <| IO.userError "aleo: missing cmpi.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn cmp(public p0: i64, public p1: i64) -> bool {")
    "Int64 comparison entry must render i64 params and bool result"
  for op in #["==", "!=", "<", "<=", ">", ">="] do
    expect (leo.contains s!" {op} ")
      s!"Int64 comparison operator {op} must render"

/-- Int64 unary neg, bitwise not, bitwise ops, shifts (count u8 cast;
    UInt32 params stay fail-closed — shift counts enter as literals). -/
unsafe def testInt64NegBitwiseShiftsLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BitI where\n" ++
    "  entry negate(a : Int64) : Int64 do\n" ++
    "    return -a\n" ++
    "  entry bw(a : Int64, b : Int64) : Int64 do\n" ++
    "    return (a & b) | (a ^ b)\n" ++
    "  entry flip(a : Int64) : Int64 do\n" ++
    "    return ~a\n" ++
    "  entry shift(a : Int64) : Int64 do\n" ++
    "    return (a << 2) >> 2\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-biti>" "Tests.AleoBitI" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "biti.aleo") |
    throw <| IO.userError "aleo: missing biti.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn negate(public p0: i64) -> i64 {")
    "neg entry must render i64"
  expect (leo.contains "(-p0)")
    "unary neg must render Leo -"
  expect (leo.contains ": i64 = (!")
    "Int64 bitwise not must bind an i64 !"
  expect (leo.contains " & ")
    "Int64 bitwise and must render"
  expect (leo.contains " | ")
    "Int64 bitwise or must render"
  expect (leo.contains " ^ ")
    "Int64 bitwise xor must render"
  expect (leo.contains " as u8)")
    "Int64 shifts must cast the count to u8"
  expect (leo.contains " << ")
    "Int64 left shift must render"
  expect (leo.contains " >> ")
    "Int64 right shift must render (arithmetic on Leo i64)"

/-- Int64 pureFn helper: helper result i64 typing across a call site. -/
unsafe def testInt64PureHelperLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program HelperI where\n" ++
    "  fn twice(a : Int64) : Int64 do\n" ++
    "    return a + a\n" ++
    "  fn pos(a : Int64) : Bool do\n" ++
    "    return a > 0\n" ++
    "  entry go(x : Int64) : Bool do\n" ++
    "    return pos(twice(x))\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-helperi>" "Tests.AleoHelperI" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.map (·.name) == #["twice", "pos", "go"])
    "HelperI Aleo plan must carry twice + pos + go"
  let twice := plan.functions[0]!
  expect (twice.resultIsInt && twice.isPureHelper)
    "twice must be an Int64-returning pure helper"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "helperi.aleo") |
    throw <| IO.userError "aleo: missing helperi.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn twice(p0: i64) -> i64 {")
    "Int64 pureFn must render as a file-level i64 helper"
  expect (leo.contains "fn pos(p0: i64) -> bool {")
    "Bool pureFn with i64 param must render i64 param"
  expect (leo.contains "fn go(public p0: i64) -> bool {")
    "entry must render the i64 param"
  expect (leo.contains "twice(")
    "entry must call the twice helper"

/-- Mixed signedness and Int64-in-unsigned contexts fail closed at
    Normalize (product path) and again at the Aleo plan (defense in depth). -/
unsafe def testInt64MixedSignednessFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- UInt64/Int64 mixed binary: Normalize rejects the type mismatch before
  -- the plan; if a residual carrier ever reached the lowerer, the operand
  -- signedness check fails closed too.
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Mixed where\n" ++
    "  entry mix(a : UInt64, b : Int64) : UInt64 do\n" ++
    "    return a + b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-i64neg-mixed>" "Tests.AleoI64NegMixed" none)
  match Compiler.compileValidatedSourceV1 parsed with
  | .error e =>
      expect (e.code == "PF-SRC-INVALID")
        s!"mixed-signedness must fail closed at Normalize, got {e.render}"
  | .ok compiled =>
      match planAleo compiled with
      | .error (.planInvariant .aleo _) => pure ()
      | .error e => throw <| IO.userError s!"mixed: expected planInvariant, got {e.render}"
      | .ok _ => throw <| IO.userError "mixed-signedness must fail closed at Aleo plan"

/-- Negative Int64 literals: wire two's-complement decodes to i64 literals. -/
unsafe def testInt64Negatives : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program NegLit where\n" ++
    "  entry min() : Int64 do\n" ++
    "    return -9223372036854775808\n" ++
    "  entry negone() : Int64 do\n" ++
    "    return -1\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-neglit>" "Tests.AleoNegLit" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.functions.all (·.resultIsInt))
    "negative literal entries must be Int64-returning"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "neglit.aleo") |
    throw <| IO.userError "aleo: missing neglit.aleo"
  let leo := leoFile.contents
  expect (leo.contains "-9223372036854775808i64")
    "intMin must render as a negative i64 literal"
  expect (leo.contains "-1i64")
    "-1 must render as a negative i64 literal"

/-- End-to-end leo build of an Int64 Counter shape (skipped when leo absent;
    this is the resident source-shape test; the leo build itself lives in
    AleoAcceptance when leo is present). -/
unsafe def testInt64AcceptanceLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Temp where\n" ++
    "  state acc : Int64\n" ++
    "  init(seed : Int64) do\n" ++
    "    acc := seed\n" ++
    "  entry bump(delta : Int64) : Int64 do\n" ++
    "    acc := acc + delta\n" ++
    "    return acc\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-i64-accept>" "Tests.AleoI64Accept" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "temp.aleo") |
    throw <| IO.userError "aleo: missing temp.aleo"
  expect (leoFile.contents.contains "program temp.aleo {")
    "Int64 Counter must materialize a Leo program"

/-- First index of `needle` in `hay` as char list, or none. -/
private partial def indexOfChars (hay needle : List Char) (i : Nat) : Option Nat :=
  match hay with
  | [] => if needle.isEmpty then some i else none
  | _ :: rest =>
      if needle.isPrefixOf hay then some i else indexOfChars rest needle (i + 1)

/-- Collect every start index of `needle` in `hay` (non-overlapping scan). -/
private def allSubstrPositions (hay needle : String) : Array Nat := Id.run do
  let mut out : Array Nat := #[]
  let mut rest := hay.toList
  let n := needle.toList
  let mut base : Nat := 0
  while true do
    match indexOfChars rest n 0 with
    | none => break
    | some rel =>
        out := out.push (base + rel)
        rest := rest.drop (rel + n.length)
        base := base + rel + n.length
  pure out

/-- Dense Map UInt64 UInt64 (capacity-2 pilot): Map.empty + IndexGet
    (Option intermediate) + IndexSet upsert + match on the Option tag.
    Map StateStore lowers as one 6-leaf storeAggregate (not six sequential
    `.store`); Leo final two-phase keeps all batch get_or_use before first set. -/
unsafe def testMapStateLeo : IO Unit := do
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
    "      return supply\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-token-map>" "Tests.AleoTokenMap" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  -- capacity-2 × (occ,key,val) = 6 Map leaves + supply.
  expect (plan.stateFieldNames.size == 7)
    s!"Map plan must carry 6 Map leaves + supply, got {plan.stateFieldNames.size}"
  expect (plan.stateFieldNames.take 6 ==
      #["balances_0_occ", "balances_0_key", "balances_0_val",
        "balances_1_occ", "balances_1_key", "balances_1_val"])
    s!"Map leaves must be entry_i_occ/key/val, got {plan.stateFieldNames.take 6}"
  -- Token mint: each arm has one 6-leaf storeAggregate for balances (plus
  -- scalar supply store). Sequential six `.store` would be the snapshot bug.
  let some mintFn := plan.functions.find? (·.name == "mint") |
    throw <| IO.userError "Token plan missing mint"
  let rec countMapStores (stmts : Array Targets.Aleo.Statement) : Nat × Nat :=
    stmts.foldl (fun (agg6, seq) stmt =>
      match stmt with
      | .storeAggregate leaves =>
          (agg6 + (if leaves.size == 6 then 1 else 0), seq)
      | .store fi _ =>
          (agg6, seq + (if fi < 6 then 1 else 0))
      | .ifThenElse _ t e =>
          let (a1, s1) := countMapStores t
          let (a2, s2) := countMapStores e
          (agg6 + a1 + a2, seq + s1 + s2)
      | .switchOn _ cases d =>
          let (ad, sd) := countMapStores d
          let (ac, sc) := cases.foldl (fun (a, s) (_, b) =>
            let (ab, sb) := countMapStores b
            (a + ab, s + sb)) (0, 0)
          (agg6 + ad + ac, seq + sd + sc)
      | .forLoop _ _ _ b =>
          let (ab, sb) := countMapStores b
          (agg6 + ab, seq + sb)
      | _ => (agg6, seq)) (0, 0)
  let (aggregate6Count, sequentialMapStoreCount) := countMapStores mintFn.body
  expect (aggregate6Count >= 1)
    s!"Token mint must form ≥1 6-leaf storeAggregate for Map balances, got {aggregate6Count}"
  expect (sequentialMapStoreCount == 0)
    s!"Token mint must not sequential-store Map leaves (snapshot hazard), got {sequentialMapStoreCount}"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "token.aleo") |
    throw <| IO.userError "aleo: missing token.aleo"
  let leo := leoFile.contents
  expect (leo.contains "mapping pf_state_0: u8 => u64;")
    "Map must render occ/key/val u64 mappings"
  expect (leo.contains " ? ")
    "Map lookup/upsert must render typed Leo ternaries"
  expect (leo.contains "if (")
    "Option match must render a Leo if on the tag"
  expect (leo.contains "} else {")
    "Option match arms must render if/else"
  expect (leo.contains "1u64 : 0u64)")
    "Option tag must materialize as a u64 0/1 ternary"

/-- MapMini put: empty Map upsert must lower as one 6-leaf storeAggregate and
    emit all mapping get_or_use / value bindings before the first mapping set
    of that batch (store-then-read snapshot). Sequential per-leaf store
    polluted later leaves after writing occ' of the first-empty slot. -/
unsafe def testMapStoreAggregateSnapshot : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapMini where\n" ++
    "  state m : Map UInt64 UInt64\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    m[k] := v\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-mapmini>" "Tests.AleoMapMini" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.stateFieldNames.size == 6)
    s!"MapMini plan must carry 6 Map leaves, got {plan.stateFieldNames.size}"
  let some putFn := plan.functions.find? (·.name == "put") |
    throw <| IO.userError "MapMini plan missing put"
  let hasAgg6 := putFn.body.any fun stmt =>
    match stmt with
    | .storeAggregate leaves => leaves.size == 6
    | _ => false
  expect hasAgg6
    "MapMini put must lower Map StateStore as one storeAggregate of 6 leaves"
  let hasSeqStore := putFn.body.any fun stmt =>
    match stmt with | .store _ _ => true | _ => false
  expect (!hasSeqStore)
    "MapMini put must not emit sequential per-leaf .store for the Map upsert"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "mapmini.aleo") |
    throw <| IO.userError "aleo: missing mapmini.aleo"
  let leo := leoFile.contents
  -- Extract put's final block (between `return final {` after put header
  -- and the matching `};` close).
  let putMarker := "fn put(public p0: u64, public p1: u64) -> Final {"
  let leoCs := leo.toList
  let some putStart := indexOfChars leoCs putMarker.toList 0 |
    throw <| IO.userError s!"MapMini Leo missing put Final header, got:\n{leo}"
  let afterPutCs := leoCs.drop putStart
  let finalMarker := "return final {"
  let some finalRel := indexOfChars afterPutCs finalMarker.toList 0 |
    throw <| IO.userError "MapMini put missing return final block"
  let finalBodyStart := putStart + finalRel + finalMarker.length
  let restCs := leoCs.drop finalBodyStart
  -- Close of final is `    };` before the function close; take until first
  -- `    };\n` that ends the final block (Leo emitter uses 4-space indent).
  let some closeRel := indexOfChars restCs "    };\n".toList 0 |
    throw <| IO.userError "MapMini put final block missing close"
  let finalBody := String.ofList (restCs.take closeRel)
  -- Collect get_or_use / set positions for the six Map leaves.
  let mut getPoses : Array Nat := #[]
  let mut setPoses : Array Nat := #[]
  for i in [0:6] do
    getPoses := getPoses ++ allSubstrPositions finalBody s!"pf_state_{i}.get_or_use"
    setPoses := setPoses ++ allSubstrPositions finalBody s!"pf_state_{i}.set"
  expect (setPoses.size == 6)
    s!"MapMini put final must emit exactly 6 Map leaf sets, got {setPoses.size}"
  expect (getPoses.size > 0)
    "MapMini put final must emit Map leaf get_or_use for upsert snapshot"
  let some firstSet := setPoses.foldl (fun acc p =>
      match acc with | none => some p | some m => some (Nat.min m p)) none |
    throw <| IO.userError "MapMini put: empty setPoses"
  let some lastGet := getPoses.foldl (fun acc p =>
      match acc with | none => some p | some m => some (Nat.max m p)) none |
    throw <| IO.userError "MapMini put: empty getPoses"
  expect (lastGet < firstSet)
    s!"MapMini put store-then-read snapshot: all batch get_or_use (last={lastGet}) must precede first mapping set (first={firstSet})"

/-- Map-full insert and mixed-shape Map fail closed (Normalize first, then
    the Aleo type closure / plan as defense in depth). -/
unsafe def testMapUpsertFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- A non-UInt64→UInt64 Map is declined: Normalize rejects the Bool param
  -- first (PF-SRC-INVALID); the Aleo type closure would also decline the
  -- Map shape if a residual carrier ever reached it.
  let badMapSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BadMap where\n" ++
    "  state m : Map UInt64 Bool\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "  entry go(k : UInt64, v : Bool) : UInt64 do\n" ++
    "    m[k] := v\n" ++
    "    return 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    badMapSource "<aleo-badmap>" "Tests.AleoBadMap" none)
  match Compiler.compileValidatedSourceV1 parsed with
  | .error e =>
      -- Normalize rejects the Bool param (and would reject the Map shape);
      -- either is an honest fail-closed layer.
      expect (e.code == "PF-SRC-INVALID")
        s!"Map UInt64 Bool must fail closed at Normalize, got {e.render}"
  | .ok compiled =>
      match planAleo compiled with
      | .error (.planInvariant .aleo _) => pure ()
      | .error e => throw <| IO.userError s!"Map UInt64 Bool must fail closed, got {e.render}"
      | .ok _ => throw <| IO.userError "Map UInt64 Bool must fail closed at Aleo plan"

/-- The Leo ECMP0376015 mapping-set budget is enforced at plan time: a
    state-touching function whose statically-summed sets exceed 32 fails
    closed before any Leo source is emitted. -/
unsafe def testMapSetBudgetFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- 3 state fields touched in every arm of a 12-arm match → 36 sets (each
  -- arm contributes 3; Leo sums statically across arms).
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Spendy where\n" ++
    "  state a : UInt64\n" ++
    "  state b : UInt64\n" ++
    "  state c : UInt64\n" ++
    "  init() do\n" ++
    "    a := 0\n" ++
    "    b := 0\n" ++
    "    c := 0\n" ++
    "  entry go(x : UInt64) : UInt64 do\n" ++
    "    match x with\n" ++
    "    | 0 => do\n" ++
    "      a := 1\n" ++
    "      b := 1\n" ++
    "      c := 1\n" ++
    "      return 0\n" ++
    "    | 1 => do\n" ++
    "      a := 1\n" ++
    "      b := 1\n" ++
    "      c := 1\n" ++
    "      return 0\n" ++
    "    | 2 => do\n" ++
    "      a := 1\n" ++
    "      b := 1\n" ++
    "      c := 1\n" ++
    "      return 0\n" ++
    "    | 3 => do\n" ++
    "      a := 1\n" ++
    "      b := 1\n" ++
    "      c := 1\n" ++
    "      return 0\n" ++
    "    | 4 => do\n" ++
    "      a := 1\n" ++
    "      b := 1\n" ++
    "      c := 1\n" ++
    "      return 0\n" ++
    "    | 5 => do\n" ++
    "      a := 1\n" ++
    "      b := 1\n" ++
    "      c := 1\n" ++
    "      return 0\n" ++
    "    | 6 => do\n" ++
    "      a := 1\n" ++
    "      b := 1\n" ++
    "      c := 1\n" ++
    "      return 0\n" ++
    "    | 7 => do\n" ++
    "      a := 1\n" ++
    "      b := 1\n" ++
    "      c := 1\n" ++
    "      return 0\n" ++
    "    | 8 => do\n" ++
    "      a := 1\n" ++
    "      b := 1\n" ++
    "      c := 1\n" ++
    "      return 0\n" ++
    "    | 9 => do\n" ++
    "      a := 1\n" ++
    "      b := 1\n" ++
    "      c := 1\n" ++
    "      return 0\n" ++
    "    | 10 => do\n" ++
    "      a := 1\n" ++
    "      b := 1\n" ++
    "      c := 1\n" ++
    "      return 0\n" ++
    "    | _ => do\n" ++
    "      a := 1\n" ++
    "      b := 1\n" ++
    "      c := 1\n" ++
    "      return 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-spendy>" "Tests.AleoSpendy" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planAleo compiled with
  | .error (.planInvariant .aleo msg) =>
      expect (msg.contains "mapping-set budget")
        s!"set-budget decline must cite the Leo budget, got: {msg}"
  | .error e => throw <| IO.userError s!"Spendy: expected set-budget decline, got {e.render}"
  | .ok _ => throw <| IO.userError "Spendy must fail closed at the Leo mapping-set budget"

/-- Fixed Bytes N: N×`u8 => u8` mappings, u8 params/results, checked u8
    arithmetic via widen → u64 op → checked `as u8` narrow. -/
unsafe def testBytesStateLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BytesBox where\n" ++
    "  state b : Bytes 2\n" ++
    "  init() do\n" ++
    "    b[0] := 0\n" ++
    "    b[1] := 0\n" ++
    "  entry set0(v : UInt8) : UInt8 do\n" ++
    "    b[0] := v\n" ++
    "    return b[0]\n" ++
    "  entry plus(v : UInt8) : UInt8 do\n" ++
    "    b[1] := b[1] + v\n" ++
    "    return b[1]\n" ++
    "  entry flip() : UInt8 do\n" ++
    "    return ~b[0]\n" ++
    "  view get0() : UInt8 do\n" ++
    "    return b[0]\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-bytes>" "Tests.AleoBytes" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.stateFieldNames == #["b_0", "b_1"])
    s!"Bytes must flatten to b_0/b_1 leaves, got {plan.stateFieldNames}"
  expect (plan.stateFieldIsU8 == #[true, true])
    "Bytes leaves must be marked u8"
  let set0 := plan.functions.find? (·.name == "set0")
  match set0 with
  | some fn =>
      expect (fn.resultIsU8 && fn.params.all (·.isU8))
        "Bytes entry must take and return UInt8"
  | none => throw <| IO.userError "missing set0"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "bytesbox.aleo") |
    throw <| IO.userError "aleo: missing bytesbox.aleo"
  let leo := leoFile.contents
  expect (leo.contains "mapping pf_state_0: u8 => u8;")
    "Bytes leaves must render u8 => u8 mappings"
  expect (leo.contains "fn set0(public p0: u8) -> Final {")
    "Bytes entry must render a u8 public param"
  expect (leo.contains "let pf_return: u8 =")
    "Bytes dropped return must bind u8"
  expect (leo.contains " as u64)")
    "u8 arithmetic must widen operands to u64"
  expect (leo.contains " as u8)")
    "u8 arithmetic must narrow the result with a checked cast"
  expect (leo.contains ": u8 = (!")
    "Bytes bitwise not must bind a u8 !"

/-- Bytes fail-closed: mixed lane stores and UInt8 scalar state decline. -/
unsafe def testBytesFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- UInt8 scalar *state* stays fail-closed (only the Bytes element lane is
  -- open): Normalize admits UInt8 state, the Aleo type closure does not.
  let u8StateSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program U8State where\n" ++
    "  state x : UInt8\n" ++
    "  init(seed : UInt8) do\n" ++
    "    x := seed\n" ++
    "  entry get() : UInt8 do\n" ++
    "    return x\n"
  let parsed ← liftResult (← session.selectProgramV1
    u8StateSource "<aleo-u8state>" "Tests.AleoU8State" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planAleo compiled with
  | .error (.planInvariant .aleo msg) =>
      expect (msg.contains "UInt64" || msg.contains "width" || msg.contains "u8")
        s!"UInt8 state decline must cite the width boundary, got: {msg}"
  | .error e => throw <| IO.userError s!"UInt8 state: expected decline, got {e.render}"
  | .ok _ => throw <| IO.userError "UInt8 scalar state must fail closed at Aleo plan"

/-- B-RET-ABI: named Struct entry return flattens to 2 UInt64 leaves and
    emits a native Leo `(u64, u64)` tuple (non-Final, no state). -/
unsafe def testNamedStructReturn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PairRet where\n" ++
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  entry makePair(x : UInt64, y : UInt64) : Pair do\n" ++
    "    return Pair.new(x, y)\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-pair-ret>" "Tests.AleoPairRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  let some makePair := plan.functions.find? (·.name == "makePair") |
    throw <| IO.userError "PairRet: missing makePair"
  match makePair.resultAggregateLeaves with
  | some leaves =>
      expect (leaves.size == 2)
        s!"PairRet aggregate return must have 2 leaves, got {leaves.size}"
      expect (!leaves[0]!.isInt && !leaves[1]!.isInt)
        "PairRet leaves must be u64 (not Int)"
      expect (leaves.all (·.byteWidth == 8))
        "PairRet leaves must be 8-byte words"
  | none =>
      throw <| IO.userError "PairRet makePair must set resultAggregateLeaves"
  match makePair.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2) "PairRet resultKind.aggregate must have 2 leaves"
  | other =>
      throw <| IO.userError
        s!"PairRet resultKind must be .aggregate, got {repr other}"
  expect (!makePair.touchesState && !makePair.resultDropped)
    "PairRet makePair must be non-Final (no state) and keep its result"
  expect (makePair.body.size == 1) "PairRet makePair body must be one return"
  match makePair.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2)
        s!"returnAggregate must have 2 leaves, got {leaves.size}"
      expect (leafIsInt == #[false, false])
        "returnAggregate leafIsInt must be #[false, false]"
      match leaves[0]!, leaves[1]! with
      | .param 0, .param 1 => pure ()
      | _, _ =>
          throw <| IO.userError
            "PairRet returnAggregate leaves must be param 0 / param 1"
  | _ =>
      throw <| IO.userError "PairRet makePair body must be .returnAggregate"
  liftResult <| Targets.Aleo.validatePlan plan
  let ir ← liftResult <| irAleo compiled
  let some leoFn := ir.program.functions.find? (·.name == "makePair") |
    throw <| IO.userError "PairRet IR missing makePair"
  match leoFn.resultAggregateLeaves with
  | some leaves =>
      expect (leaves.size == 2) "PairRet Leo IR must carry 2 aggregate leaves"
  | none =>
      throw <| IO.userError "PairRet Leo IR must set resultAggregateLeaves"
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "pairret.aleo") |
    throw <| IO.userError "aleo: missing pairret.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn makePair(public p0: u64, public p1: u64) -> (u64, u64) {")
    s!"PairRet must emit Leo tuple return type, got:\n{leo}"
  expect (leo.contains "return (")
    s!"PairRet must emit Leo tuple return value, got:\n{leo}"
  expect (!leo.contains "return final")
    "PairRet non-state entry must not be Final"
  IO.println "  PairRet named Struct return Plan/IR/Leo pin ok"

/-- B-RET-ABI: named Enum return = tag + max-payload slots (Maybe = 2 leaves).
    Non-state entry constructs and returns the Enum as a Leo tuple. -/
unsafe def testNamedEnumReturn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MaybeRet where\n" ++
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  entry put(v : UInt64) : Maybe do\n" ++
    "    return Maybe.Some(v)\n" ++
    "  entry clear() : Maybe do\n" ++
    "    return Maybe.None()\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-maybe-ret>" "Tests.AleoMaybeRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  let some put := plan.functions.find? (·.name == "put") |
    throw <| IO.userError "MaybeRet: missing put"
  match put.resultAggregateLeaves with
  | some leaves =>
      expect (leaves.size == 2)
        s!"MaybeRet Enum return must be tag+payload (2), got {leaves.size}"
      expect (leaves.all (fun l => !l.isInt && l.byteWidth == 8))
        "MaybeRet leaves must be unsigned 8-byte words"
  | none =>
      throw <| IO.userError "MaybeRet put must set resultAggregateLeaves"
  match put.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2 && leafIsInt.size == 2)
        "MaybeRet returnAggregate must have 2 leaves"
  | _ =>
      throw <| IO.userError "MaybeRet put body must be .returnAggregate"
  let some clear := plan.functions.find? (·.name == "clear") |
    throw <| IO.userError "MaybeRet: missing clear"
  match clear.resultAggregateLeaves with
  | some leaves =>
      expect (leaves.size == 2) "MaybeRet clear must also return 2-leaf Maybe"
  | none =>
      throw <| IO.userError "MaybeRet clear must set resultAggregateLeaves"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "mayberet.aleo") |
    throw <| IO.userError "aleo: missing mayberet.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn put(public p0: u64) -> (u64, u64) {")
    s!"MaybeRet put must emit Leo tuple return, got:\n{leo}"
  expect (leo.contains "fn clear() -> (u64, u64) {")
    s!"MaybeRet clear must emit Leo tuple return, got:\n{leo}"
  IO.println "  MaybeRet named Enum return Plan/IR/Leo pin ok"

/-- B-RET-ABI: Final (state-touching) entry that returns a named Struct still
    evaluates leaves for failure semantics but drops them (`resultDropped`). -/
unsafe def testNamedStructReturnFinalDropped : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PairStore where\n" ++
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  state p : Pair\n" ++
    "  init(x : UInt64, y : UInt64) do\n" ++
    "    p := Pair.new(x, y)\n" ++
    "  entry setPair(x : UInt64, y : UInt64) : Pair do\n" ++
    "    p := Pair.new(x, y)\n" ++
    "    return p\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-pair-store>" "Tests.AleoPairStore" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  let some setPair := plan.functions.find? (·.name == "setPair") |
    throw <| IO.userError "PairStore: missing setPair"
  match setPair.resultAggregateLeaves with
  | some leaves =>
      expect (leaves.size == 2) "PairStore setPair must return 2-leaf Pair"
  | none =>
      throw <| IO.userError "PairStore setPair must set resultAggregateLeaves"
  expect (setPair.touchesState && setPair.resultDropped)
    "PairStore setPair must be Final and drop the aggregate result"
  match setPair.body.back? with
  | some (.returnAggregate leaves _) =>
      expect (leaves.size == 2) "PairStore final return must be returnAggregate"
  | _ =>
      throw <| IO.userError "PairStore setPair must end in returnAggregate"
  liftResult <| Targets.Aleo.validatePlan plan
  let output ← liftResult <| materializeAleo compiled
  let some leoFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "pairstore.aleo") |
    throw <| IO.userError "aleo: missing pairstore.aleo"
  let leo := leoFile.contents
  expect (leo.contains "fn setPair(public p0: u64, public p1: u64) -> Final {")
    s!"PairStore setPair must be Final, got:\n{leo}"
  expect (leo.contains "let pf_return_0: u64 =")
    s!"PairStore Final must evaluate leaf 0, got:\n{leo}"
  expect (leo.contains "let pf_return_1: u64 =")
    s!"PairStore Final must evaluate leaf 1, got:\n{leo}"
  IO.println "  PairStore Final aggregate drop pin ok"

/-- B-RET-ABI fail-closed: anonymous Array return, 9-leaf Struct, named param. -/
unsafe def testAggregateReturnFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- Anonymous Array entry return stays fail-closed.
  let arrSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrayRet where\n" ++
    "  state slots : Array UInt64 2\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n" ++
    "  entry getArr() : Array UInt64 2 do\n" ++
    "    return slots\n"
  match ← (do
      try
        let parsed ← liftResult (← session.selectProgramV1
          arrSource "<aleo-array-ret>" "Tests.AleoArrayRet" none)
        let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
        pure (some compiled)
      catch _ => pure none) with
  | none => pure ()  -- may fail at Normalize/typed
  | some c =>
      match planAleo c with
      | .error e =>
          expect ((e.render).contains "return" ||
              (e.render).contains "Array" ||
              (e.render).contains "aggregate" ||
              (e.render).contains "container" ||
              (e.render).contains "B-RET" ||
              (e.render).contains "unsupported")
            s!"ArrayRet: FC message must cite return/container surface, got {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "ArrayRet: Aleo must fail closed on anonymous Array entry return"
  -- Cap-8: Struct with 9 UInt64 fields exceeds B-RET-ABI leaf cap.
  let mut fields := ""
  for i in [0:9] do
    fields := fields ++ s!"    f{i} : UInt64\n"
  let wideSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program WideRet where\n" ++
    "  struct Wide where\n" ++
    fields ++
    "  entry makeWide() : Wide do\n" ++
    "    return Wide.new(0, 0, 0, 0, 0, 0, 0, 0, 0)\n"
  match ← (do
      try
        let parsed ← liftResult (← session.selectProgramV1
          wideSource "<aleo-wide-ret>" "Tests.AleoWideRet" none)
        let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
        pure (some compiled)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planAleo c with
      | .error e =>
          expect (e.render.contains "8" || e.render.contains "leaf" ||
              e.render.contains "cap" || e.render.contains "aggregate")
            s!"WideRet leaf-cap error must cite cap/leaf/aggregate, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "WideRet: Aleo 9-leaf aggregate return must fail closed (cap-8)"
  -- Named Struct param stays fail closed.
  let paramSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program StructParam where\n" ++
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  entry take(p : Pair) : UInt64 do\n" ++
    "    return p.a\n"
  let paramParsed ← liftResult (← session.selectProgramV1
    paramSource "<aleo-struct-param>" "Tests.AleoStructParam" none)
  let paramCompiled ← liftResult <| Compiler.compileValidatedSourceV1 paramParsed
  match planAleo paramCompiled with
  | .error e =>
      expect ((e.render).contains "parameter" ||
          (e.render).contains "Pair" ||
          (e.render).contains "aggregate" ||
          (e.render).contains "envelope" ||
          (e.render).contains "unsupported")
        s!"StructParam: FC must cite parameter boundary, got {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "StructParam: Aleo must fail closed on named Struct params"
  -- pureFn aggregate return stays fail closed.
  let pureSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PurePair where\n" ++
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  fn mk(x : UInt64, y : UInt64) : Pair do\n" ++
    "    return Pair.new(x, y)\n" ++
    "  entry use(x : UInt64, y : UInt64) : UInt64 do\n" ++
    "    let p : Pair := mk(x, y)\n" ++
    "    return p.a\n"
  match ← (do
      try
        let parsed ← liftResult (← session.selectProgramV1
          pureSource "<aleo-pure-pair>" "Tests.AleoPurePair" none)
        let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
        pure (some compiled)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planAleo c with
      | .error e =>
          expect ((e.render).contains "pureFn" ||
              (e.render).contains "aggregate" ||
              (e.render).contains "helper" ||
              (e.render).contains "scalar" ||
              (e.render).contains "B-RET")
            s!"PurePair: FC must cite pureFn/aggregate, got {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "PurePair: Aleo pureFn aggregate return must fail closed"
  IO.println "  aggregate return fail-closed boundaries ok"

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
  testFieldBn254FailClosed
  testBls12377FieldStateArith
  testNamedAggregateLowered
  testArrayStateLowered
  testCommitIdentityLeo
  testContextReadFailClosed
  testInt64StateArithLeo
  testInt64ComparisonsLeo
  testInt64NegBitwiseShiftsLeo
  testInt64PureHelperLeo
  testInt64MixedSignednessFailClosed
  testInt64Negatives
  testInt64AcceptanceLeo
  testMapStateLeo
  testMapStoreAggregateSnapshot
  testMapUpsertFailClosed
  testMapSetBudgetFailClosed
  testBytesStateLeo
  testBytesFailClosed
  testNamedStructReturn
  testNamedEnumReturn
  testNamedStructReturnFinalDropped
  testAggregateReturnFailClosed
  IO.println "Tests.Materialization.Aleo: ok"

end Tests.Materialization.Aleo
