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
open ProofForgeV2.Targets.DescriptorDataV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def planAleo
    (compiled : CompiledSemanticV1)
    (profile? : Option CodegenProfileId := none) :
    CompileResult Targets.Aleo.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.aleo profile?
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Aleo.planFromCapability capability

private def irAleo
    (compiled : CompiledSemanticV1)
    (profile? : Option CodegenProfileId := none) :
    CompileResult Targets.Aleo.IR := do
  let selection ← resolveBuildSelectionV1 TargetId.aleo profile?
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Aleo.irFromCapability capability

private def materializeAleo
    (compiled : CompiledSemanticV1)
    (profile? : Option CodegenProfileId := none)
    (emitLeoDebug : Bool := false) :
    CompileResult MaterializedArtifactsV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.aleo profile?
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.materializeResult capability (emitLeoDebug := emitLeoDebug)

/-- ALEO-IR-6: Leo 4 surface pins read dual-written `{id}.leo` under
    `emitLeoDebug := true` (product primary `{id}.aleo` is Instructions when
    lower succeeds; residual shapes keep Leo as `.aleo` but still dual-write
    `.leo` when debug is on). -/
private def materializeLeoSource
    (compiled : CompiledSemanticV1)
    (programId : String)
    (profile? : Option CodegenProfileId := none) : IO String := do
  let output ← liftResult <| materializeAleo compiled profile? (emitLeoDebug := true)
  let files := MaterializedArtifactsV1.filesOf output
  match files.find? (·.path == s!"{programId}.leo") with
  | some f => pure f.contents
  | none =>
      throw <| IO.userError
        s!"aleo: missing {programId}.leo under emitLeoDebug; got {files.map (·.path)}"

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
  let files := MaterializedArtifactsV1.filesOf output
  expect (files.map (·.path) ==
      #["counter.aleo", "counter.aleo-query-contract.json"])
    s!"Counter materialize must emit Instructions + query-contract base files in order, got {files.map (·.path)}"
  expect (files[0]!.mediaType == "text/plain" &&
      files[1]!.mediaType == "application/json")
    "Counter base mediaTypes must be text/plain then application/json"
  let some instFile := files.find? (·.path == "counter.aleo") |
    throw <| IO.userError "aleo: missing counter.aleo"
  let inst := instFile.contents
  -- ALEO-IR-6: product primary is Aleo Instructions (not Leo 4 brace source).
  expect (inst.contains "program counter.aleo;")
    "Instructions primary must declare the program with semicolon header"
  expect (!inst.contains "program counter.aleo {")
    "Instructions primary must not be Leo brace source"
  expect (inst.contains "mapping pf_state_0:")
    "Instructions must declare the state mapping"
  expect (inst.contains "mapping initialized:")
    "Instructions must declare the one-shot init guard mapping"
  expect (inst.contains "function initialize:")
    "init must materialize as an Instructions function"
  expect (inst.contains "finalize initialize:")
    "init must carry a finalize block"
  expect (inst.contains "get.or_use initialized[0u8] false into")
    "init guard must read the initialized mapping"
  expect (inst.contains "assert.eq")
    "init guard must assert via assert.eq"
  expect (inst.contains "function increment:")
    "increment must materialize as an Instructions function"
  expect (inst.contains "finalize increment:")
    "increment must carry a finalize block"
  expect (inst.contains "get.or_use pf_state_0[0u8]")
    "increment must read the state mapping in finalize"
  expect (inst.contains "set ")
    "increment must write mappings via set"
  expect (inst.contains "constructor:")
    "Instructions requires a constructor item"
  -- Debug dual-write: Leo 4 source on explicit flag only.
  let filesDbg ← liftResult <| materializeAleo compiled none (emitLeoDebug := true)
  let dbgPaths := (MaterializedArtifactsV1.filesOf filesDbg).map (·.path)
  expect (dbgPaths ==
      #["counter.aleo", "counter.aleo-query-contract.json", "counter.leo"])
    s!"debug dual-write must add counter.leo last, got {dbgPaths}"
  let some leoFile := (MaterializedArtifactsV1.filesOf filesDbg).find?
      (·.path == "counter.leo") |
    throw <| IO.userError "aleo: missing counter.leo under emitLeoDebug"
  let leo := leoFile.contents
  expect (leo.contains "program counter.aleo {")
    "debug Leo source must declare the program"
  expect (leo.contains "mapping pf_state_0: u8 => u64;")
    "debug Leo source must declare the state mapping"
  expect (leo.contains "fn initialize(public p0: u64) -> Final {")
    "debug Leo init must materialize as a Final function"
  expect (leo.contains "return final {")
    "debug Leo Final functions must use return final { ... }; form"
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
  let leo ← materializeLeoSource compiled "bitlogic"
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
  let leo ← materializeLeoSource compiled "loopsum"
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
    stateFieldUintWidth := #[0]
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
    stateFieldUintWidth := #[0]
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
  let leo ← materializeLeoSource compiled "branch"
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
  let leo ← materializeLeoSource compiled "pick"
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
  let leo ← materializeLeoSource compiled "arith"
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
  let leo ← materializeLeoSource compiled "diff"
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
  let leo ← materializeLeoSource compiled "cmp"
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
  let leo ← materializeLeoSource compiled "log"
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
  let leo ← materializeLeoSource compiled "guard"
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
  let leo ← materializeLeoSource compiled "stop"
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
  let leo ← materializeLeoSource compiled "dual"
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
  let leo ← materializeLeoSource compiled "helpers"
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
  let leo ← materializeLeoSource compiled "blsfieldbox"
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
  let leo ← materializeLeoSource compiled "pointbox"
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
  let leo ← materializeLeoSource compiled "arrbox"
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
  let leo ← materializeLeoSource compiled "commitseal"
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
  let leo ← materializeLeoSource compiled "temp"
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
  let leo ← materializeLeoSource compiled "cmpi"
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
  let leo ← materializeLeoSource compiled "biti"
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
  let leo ← materializeLeoSource compiled "helperi"
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
  let leo ← materializeLeoSource compiled "neglit"
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
  let leo ← materializeLeoSource compiled "token"
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
  let leo ← materializeLeoSource compiled "mapmini"
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

/-- Fixed Bytes N: N×`u8 => u8` mappings, u8 params/results, native u8
    checked arithmetic (Leo trap-on-overflow; T8 multi-width). -/
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
  expect (plan.stateFieldUintWidth == #[8, 8])
    "Bytes leaves must be width-8"
  let set0 := plan.functions.find? (·.name == "set0")
  match set0 with
  | some fn =>
      expect (fn.resultUintWidth == 8 && fn.params.all (·.uintWidth == 8))
        "Bytes entry must take and return UInt8"
  | none => throw <| IO.userError "missing set0"
  liftResult <| Targets.Aleo.validatePlan plan
  let leo ← materializeLeoSource compiled "bytesbox"
  expect (leo.contains "mapping pf_state_0: u8 => u8;")
    "Bytes leaves must render u8 => u8 mappings"
  expect (leo.contains "fn set0(public p0: u8) -> Final {")
    "Bytes entry must render a u8 public param"
  expect (leo.contains "let pf_return: u8 =")
    "Bytes dropped return must bind u8"
  -- T8: native u8 arithmetic (no widen→u64→narrow cast dance).
  expect (leo.contains ": u8 = (")
    "u8 arithmetic must bind native u8 results"
  expect (!leo.contains " as u64)")
    "native u8 path must not widen operands to u64"
  expect (leo.contains ": u8 = (!")
    "Bytes bitwise not must bind a u8 !"

/-- T8 multi-width: scalar UInt8/16/32 state + params + body native Leo ops. -/
unsafe def testNarrowUintStateLeo : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program NarrowBox where\n" ++
    "  state a : UInt8\n" ++
    "  state b : UInt16\n" ++
    "  state c : UInt32\n" ++
    "  init(seed8 : UInt8, seed16 : UInt16, seed32 : UInt32) do\n" ++
    "    a := seed8\n" ++
    "    b := seed16\n" ++
    "    c := seed32\n" ++
    "  entry bump8(d : UInt8) : UInt8 do\n" ++
    "    a := a + d\n" ++
    "    return a\n" ++
    "  entry bump16(d : UInt16) : UInt16 do\n" ++
    "    b := b + d\n" ++
    "    return b\n" ++
    "  entry bump32(d : UInt32) : UInt32 do\n" ++
    "    c := c + d\n" ++
    "    return c\n" ++
    "  entry flip8() : UInt8 do\n" ++
    "    return ~a\n" ++
    "  entry shift8(v : UInt8) : UInt8 do\n" ++
    "    return v << 1\n" ++
    "  view get8() : UInt8 do\n" ++
    "    return a\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-narrow>" "Tests.AleoNarrow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  expect (plan.stateFieldUintWidth == #[8, 16, 32])
    s!"narrow state widths must be 8/16/32, got {plan.stateFieldUintWidth}"
  let bump8 := plan.functions.find? (·.name == "bump8")
  match bump8 with
  | some fn =>
      expect (fn.resultUintWidth == 8 && fn.params.all (·.uintWidth == 8))
        "bump8 must take/return UInt8"
  | none => throw <| IO.userError "missing bump8"
  let bump16 := plan.functions.find? (·.name == "bump16")
  match bump16 with
  | some fn =>
      expect (fn.resultUintWidth == 16 && fn.params.all (·.uintWidth == 16))
        "bump16 must take/return UInt16"
  | none => throw <| IO.userError "missing bump16"
  let bump32 := plan.functions.find? (·.name == "bump32")
  match bump32 with
  | some fn =>
      expect (fn.resultUintWidth == 32 && fn.params.all (·.uintWidth == 32))
        "bump32 must take/return UInt32"
  | none => throw <| IO.userError "missing bump32"
  liftResult <| Targets.Aleo.validatePlan plan
  let leo ← materializeLeoSource compiled "narrowbox"
  expect (leo.contains "mapping pf_state_0: u8 => u8;")
    "UInt8 state must render u8 => u8 mapping"
  expect (leo.contains "mapping pf_state_1: u8 => u16;")
    "UInt16 state must render u8 => u16 mapping"
  expect (leo.contains "mapping pf_state_2: u8 => u32;")
    "UInt32 state must render u8 => u32 mapping"
  expect (leo.contains "fn bump8(public p0: u8) -> Final {")
    "bump8 must take a public u8 param"
  expect (leo.contains "fn bump16(public p0: u16) -> Final {")
    "bump16 must take a public u16 param"
  expect (leo.contains "fn bump32(public p0: u32) -> Final {")
    "bump32 must take a public u32 param"
  expect (leo.contains ": u8 = (")
    "UInt8 body ops must bind native u8"
  expect (leo.contains ": u16 = (")
    "UInt16 body ops must bind native u16"
  expect (leo.contains ": u32 = (")
    "UInt32 body ops must bind native u32"
  expect (leo.contains ": u8 = (!")
    "UInt8 bitNot must bind u8 !"
  expect (leo.contains " as u8)")
    "narrow shifts must cast the count to u8"

/-- T8 fail-closed: UInt128 / narrow Int stay outside the Aleo envelope. -/
unsafe def testNarrowUintFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let u128Source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Wide where\n" ++
    "  state x : UInt128\n" ++
    "  init(seed : UInt128) do\n" ++
    "    x := seed\n" ++
    "  entry get() : UInt128 do\n" ++
    "    return x\n"
  let parsed ← liftResult (← session.selectProgramV1
    u128Source "<aleo-u128>" "Tests.AleoU128" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planAleo compiled with
  | .error (.planInvariant .aleo msg) =>
      expect (msg.contains "UInt" || msg.contains "width" || msg.contains "128")
        s!"UInt128 decline must cite the width boundary, got: {msg}"
  | .error e => throw <| IO.userError s!"UInt128: expected decline, got {e.render}"
  | .ok _ => throw <| IO.userError "UInt128 state must fail closed at Aleo plan"
  let i8Source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program NarrowInt where\n" ++
    "  state x : Int8\n" ++
    "  init(seed : Int8) do\n" ++
    "    x := seed\n" ++
    "  entry get() : Int8 do\n" ++
    "    return x\n"
  let parsedI ← liftResult (← session.selectProgramV1
    i8Source "<aleo-i8>" "Tests.AleoI8" none)
  let compiledI ← liftResult <| Compiler.compileValidatedSourceV1 parsedI
  match planAleo compiledI with
  | .error (.planInvariant .aleo msg) =>
      expect (msg.contains "Int" || msg.contains "width" || msg.contains "8")
        s!"Int8 decline must cite the width boundary, got: {msg}"
  | .error e => throw <| IO.userError s!"Int8: expected decline, got {e.render}"
  | .ok _ => throw <| IO.userError "Int8 state must fail closed at Aleo plan"

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
  | .aggregate leaves form =>
      expect (leaves.size == 2) "PairRet resultKind.aggregate must have 2 leaves"
      expect (form == .named) "PairRet form must be .named"
  | other =>
      throw <| IO.userError
        s!"PairRet resultKind must be .aggregate, got {repr other}"
  expect (makePair.resultAggregateForm == .named)
    "PairRet resultAggregateForm must be .named"
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
  let leo ← materializeLeoSource compiled "pairret"
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
  let leo ← materializeLeoSource compiled "mayberet"
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
  let leo ← materializeLeoSource compiled "pairstore"
  expect (leo.contains "fn setPair(public p0: u64, public p1: u64) -> Final {")
    s!"PairStore setPair must be Final, got:\n{leo}"
  expect (leo.contains "let pf_return_0: u64 =")
    s!"PairStore Final must evaluate leaf 0, got:\n{leo}"
  expect (leo.contains "let pf_return_1: u64 =")
    s!"PairStore Final must evaluate leaf 1, got:\n{leo}"
  IO.println "  PairStore Final aggregate drop pin ok"

/-- N-ANON-RESULT: anonymous `Array UInt64 2` entry return via state load
    (source has no Array value constructor — only state IndexSet/StateLoad
    produce Array values). Final path evaluates leaves and drops; Plan form
    is `.array` so a non-Final surface would be Leo `[u64; N]`. -/
unsafe def testAnonymousArrayReturn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrayRet where\n" ++
    "  state slots : Array UInt64 2\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n" ++
    "  entry setArr(a : UInt64, b : UInt64) : Array UInt64 2 do\n" ++
    "    slots[0] := a\n" ++
    "    slots[1] := b\n" ++
    "    return slots\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-array-ret>" "Tests.AleoArrayRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  let some setArr := plan.functions.find? (·.name == "setArr") |
    throw <| IO.userError "ArrayRet: missing setArr"
  match setArr.resultAggregateLeaves with
  | some leaves =>
      expect (leaves.size == 2)
        s!"ArrayRet aggregate return must have 2 leaves, got {leaves.size}"
      expect (leaves.all (fun l => !l.isInt && l.byteWidth == 8))
        "ArrayRet leaves must be unsigned 8-byte words"
  | none =>
      throw <| IO.userError "ArrayRet setArr must set resultAggregateLeaves"
  expect (setArr.resultAggregateForm == .array)
    "ArrayRet form must be .array"
  match setArr.resultKind with
  | .aggregate leaves form =>
      expect (leaves.size == 2 && form == .array)
        "ArrayRet resultKind must be .aggregate form=.array"
  | other =>
      throw <| IO.userError
        s!"ArrayRet resultKind must be .aggregate, got {repr other}"
  expect (setArr.touchesState && setArr.resultDropped)
    "ArrayRet setArr must be Final (state-touching) and drop the aggregate"
  match setArr.body.back? with
  | some (.returnAggregate leaves leafIsInt) =>
      expect (leaves.size == 2 && leafIsInt == #[false, false])
        "ArrayRet returnAggregate must be 2 unsigned leaves"
  | _ =>
      throw <| IO.userError "ArrayRet setArr must end in .returnAggregate"
  liftResult <| Targets.Aleo.validatePlan plan
  let ir ← liftResult <| irAleo compiled
  let some leoFn := ir.program.functions.find? (·.name == "setArr") |
    throw <| IO.userError "ArrayRet IR missing setArr"
  expect (leoFn.resultAggregateForm == .array)
    "ArrayRet Leo IR form must be .array"
  let leo ← materializeLeoSource compiled "arrayret"
  expect (leo.contains "fn setArr(public p0: u64, public p1: u64) -> Final {")
    s!"ArrayRet setArr must be Final, got:\n{leo}"
  expect (leo.contains "let pf_return_0: u64 =")
    s!"ArrayRet Final must evaluate leaf 0, got:\n{leo}"
  expect (leo.contains "let pf_return_1: u64 =")
    s!"ArrayRet Final must evaluate leaf 1, got:\n{leo}"
  IO.println "  ArrayRet anonymous Array return Plan/IR/Leo pin ok"

/-- N-ANON-RESULT: anonymous `Option UInt64` non-state entry returns → 2
    leaves, form `.option`, Leo surface `(bool, u64)`. -/
unsafe def testAnonymousOptionReturn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptionRet where\n" ++
    "  entry put(v : UInt64) : Option UInt64 do\n" ++
    "    return Option.some(v)\n" ++
    "  entry clear() : Option UInt64 do\n" ++
    "    return Option.none()\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-option-ret>" "Tests.AleoOptionRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  let some put := plan.functions.find? (·.name == "put") |
    throw <| IO.userError "OptionRet: missing put"
  match put.resultAggregateLeaves with
  | some leaves =>
      expect (leaves.size == 2)
        s!"OptionRet Option return must be tag+payload (2), got {leaves.size}"
      expect (leaves.all (fun l => !l.isInt && l.byteWidth == 8))
        "OptionRet leaves must be unsigned 8-byte words"
  | none =>
      throw <| IO.userError "OptionRet put must set resultAggregateLeaves"
  expect (put.resultAggregateForm == .option)
    "OptionRet form must be .option"
  match put.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2 && leafIsInt.size == 2)
        "OptionRet put returnAggregate must have 2 leaves"
      -- some(v) → tag=1, payload=param0
      match leaves[0]!, leaves[1]! with
      | .literal 1, .param 0 => pure ()
      | _, _ =>
          throw <| IO.userError
            s!"OptionRet put leaves must be literal 1 / param 0, got {repr leaves}"
  | _ =>
      throw <| IO.userError "OptionRet put body must be .returnAggregate"
  let some clear := plan.functions.find? (·.name == "clear") |
    throw <| IO.userError "OptionRet: missing clear"
  expect (clear.resultAggregateForm == .option)
    "OptionRet clear form must be .option"
  match clear.body[0]! with
  | .returnAggregate leaves _ =>
      match leaves[0]!, leaves[1]! with
      | .literal 0, .literal 0 => pure ()
      | _, _ =>
          throw <| IO.userError
            s!"OptionRet clear leaves must be (0,0), got {repr leaves}"
  | _ =>
      throw <| IO.userError "OptionRet clear body must be .returnAggregate"
  liftResult <| Targets.Aleo.validatePlan plan
  let leo ← materializeLeoSource compiled "optionret"
  expect (leo.contains "fn put(public p0: u64) -> (bool, u64) {")
    s!"OptionRet put must emit Leo (bool, u64) return, got:\n{leo}"
  expect (leo.contains "fn clear() -> (bool, u64) {")
    s!"OptionRet clear must emit Leo (bool, u64) return, got:\n{leo}"
  expect (leo.contains "return (true,")
    s!"OptionRet put must emit true tag, got:\n{leo}"
  expect (leo.contains "return (false,")
    s!"OptionRet clear must emit false tag, got:\n{leo}"
  IO.println "  OptionRet anonymous Option return Plan/IR/Leo pin ok"

/-- Multi-leaf view-over-state stays fail closed (BL-6 caveat). -/
unsafe def testMultiLeafViewOverStateFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrView where\n" ++
    "  state slots : Array UInt64 2\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n" ++
    "  view getArr() : Array UInt64 2 do\n" ++
    "    return slots\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-arr-view>" "Tests.AleoArrView" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planAleo compiled with
  | .error e =>
      expect ((e.render).contains "view" ||
          (e.render).contains "state" ||
          (e.render).contains "query")
        s!"ArrView: FC must cite view/state boundary, got {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "ArrView: Aleo multi-leaf view-over-state must fail closed"

/-- B-RET-ABI / N-ANON-RESULT fail-closed matrix: Map/Bytes/narrow/nested/
    cap-9/Struct-param/pureFn aggregate. -/
unsafe def testAggregateReturnFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- Anonymous Map entry return stays fail-closed (state load → return).
  let mapSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapRet where\n" ++
    "  state table : Map UInt64 UInt64\n" ++
    "  init() do\n" ++
    "    table[0] := 0\n" ++
    "  entry getMap() : Map UInt64 UInt64 do\n" ++
    "    return table\n"
  match ← (do
      try
        let parsed ← liftResult (← session.selectProgramV1
          mapSource "<aleo-map-ret>" "Tests.AleoMapRet" none)
        let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
        pure (some compiled)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planAleo c with
      | .error e =>
          expect ((e.render).contains "Map" ||
              (e.render).contains "return" ||
              (e.render).contains "B-RET" ||
              (e.render).contains "unsupported" ||
              (e.render).contains "aggregate")
            s!"MapRet: FC must cite Map/return boundary, got {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "MapRet: Aleo must fail closed on anonymous Map entry return"
  -- Anonymous Bytes return stays fail-closed (state load → return).
  let bytesSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BytesRet where\n" ++
    "  state payload : Bytes 2\n" ++
    "  init() do\n" ++
    "    payload[0] := 1\n" ++
    "    payload[1] := 2\n" ++
    "  entry getBytes() : Bytes 2 do\n" ++
    "    return payload\n"
  match ← (do
      try
        let parsed ← liftResult (← session.selectProgramV1
          bytesSource "<aleo-bytes-ret>" "Tests.AleoBytesRet" none)
        let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
        pure (some compiled)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planAleo c with
      | .error e =>
          expect ((e.render).contains "Bytes" ||
              (e.render).contains "return" ||
              (e.render).contains "B-RET" ||
              (e.render).contains "unsupported" ||
              (e.render).contains "UInt8" ||
              (e.render).contains "leaf")
            s!"BytesRet: FC must cite Bytes/return boundary, got {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "BytesRet: Aleo must fail closed on anonymous Bytes entry return"
  -- Narrow element Array stays fail-closed (state load → return).
  let narrowSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program NarrowArr where\n" ++
    "  state slots : Array UInt8 2\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n" ++
    "  entry getArr() : Array UInt8 2 do\n" ++
    "    return slots\n"
  match ← (do
      try
        let parsed ← liftResult (← session.selectProgramV1
          narrowSource "<aleo-narrow-arr>" "Tests.AleoNarrowArr" none)
        let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
        pure (some compiled)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planAleo c with
      | .error e =>
          expect ((e.render).contains "UInt" ||
              (e.render).contains "Array" ||
              (e.render).contains "element" ||
              (e.render).contains "unsupported" ||
              (e.render).contains "envelope")
            s!"NarrowArr: FC must cite element/width boundary, got {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "NarrowArr: Aleo must fail closed on Array UInt8 return"
  -- Cap-8: Array UInt64 9 exceeds leaf cap (state load → return).
  let wideArrSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program WideArr where\n" ++
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
    "  entry getArr() : Array UInt64 9 do\n" ++
    "    return slots\n"
  match ← (do
      try
        let parsed ← liftResult (← session.selectProgramV1
          wideArrSource "<aleo-wide-arr>" "Tests.AleoWideArr" none)
        let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
        pure (some compiled)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planAleo c with
      | .error e =>
          expect (e.render.contains "8" || e.render.contains "leaf" ||
              e.render.contains "cap" || e.render.contains "aggregate" ||
              e.render.contains "Array")
            s!"WideArr leaf-cap error must cite cap/leaf/Array, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "WideArr: Aleo Array UInt64 9 return must fail closed (cap-8)"
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

/-- B-OPT-STATE / BL-35: `state slot : Option UInt64` is 2 mapping leaves
    (`slot_tag` + `slot_p0`), Enum-identical layout. Pins:
    * none default / none-assign zeroes payload via storeAggregate (0,0)
    * some writes tag=1 + payload via storeAggregate
    * match read via VariantTag/VariantPayload (entry; computed views FC)
    * FC: Option of non-UInt64, nested Option, Option params -/
unsafe def testOptionState : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptionState where\n" ++
    "  state slot : Option UInt64\n" ++
    "  init() do\n" ++
    "    slot := Option.none()\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    slot := Option.some(v)\n" ++
    "    return v\n" ++
    "  entry clear() : UInt64 do\n" ++
    "    slot := Option.none()\n" ++
    "    return 0\n" ++
    "  entry peek() : UInt64 do\n" ++
    "    match slot with\n" ++
    "    | Option.some(x) => do\n" ++
    "      return x\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-option-state>" "Tests.AleoOptionState" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  -- Layout: Enum-shaped 2-leaf names.
  expect (plan.stateFieldNames == #["slot_tag", "slot_p0"])
    s!"OptionState must flatten to slot_tag/slot_p0, got {plan.stateFieldNames}"
  expect (plan.stateFieldIsInt == #[false, false])
    "OptionState leaves must be unsigned u64"
  expect (plan.stateFieldUintWidth == #[0, 0])
    "OptionState leaves must be full u64 width"
  -- Helper: walk storeAggregate of size 2 with expected leaf values.
  let rec findStoreAgg2 (stmts : Array Targets.Aleo.Statement) :
      Option (Array Targets.Aleo.Store) :=
    stmts.findSome? fun stmt =>
      match stmt with
      | .storeAggregate leaves =>
          if leaves.size == 2 then some leaves else none
      | .ifThenElse _ t e =>
          match findStoreAgg2 t with
          | some v => some v
          | none => findStoreAgg2 e
      | .switchOn _ cases d =>
          match findStoreAgg2 d with
          | some v => some v
          | none =>
              cases.findSome? fun (_, b) => findStoreAgg2 b
      | .forLoop _ _ _ b => findStoreAgg2 b
      | _ => none
  -- Init none → storeAggregate (tag=0, payload=0).
  let some initFn := plan.functions.find? (·.name == "initialize") |
    throw <| IO.userError "OptionState: missing initialize"
  match findStoreAgg2 initFn.body with
  | some leaves =>
      expect (leaves[0]!.fieldIndex == 0 && leaves[1]!.fieldIndex == 1)
        "Option.none storeAggregate must target leaves 0/1"
      expect (leaves[0]!.value == .literal 0 && leaves[1]!.value == .literal 0)
        "Option.none must zero tag and payload (stale-payload pin)"
  | none =>
      throw <| IO.userError
        "OptionState init must emit 2-leaf storeAggregate for Option.none"
  -- setSome → storeAggregate (1, param 0).
  let some setSome := plan.functions.find? (·.name == "setSome") |
    throw <| IO.userError "OptionState: missing setSome"
  match findStoreAgg2 setSome.body with
  | some leaves =>
      expect (leaves[0]!.value == .literal 1)
        "setSome tag leaf must be literal 1"
      expect (leaves[1]!.value == .param 0)
        "setSome payload leaf must be the UInt64 param"
  | none =>
      throw <| IO.userError
        "OptionState setSome must emit 2-leaf storeAggregate for Option.some"
  -- clear none-reset zeros both leaves.
  let some clear := plan.functions.find? (·.name == "clear") |
    throw <| IO.userError "OptionState: missing clear"
  match findStoreAgg2 clear.body with
  | some leaves =>
      expect (leaves[0]!.value == .literal 0 && leaves[1]!.value == .literal 0)
        "clear Option.none must zero tag and payload"
  | none =>
      throw <| IO.userError
        "OptionState clear must emit 2-leaf storeAggregate for Option.none"
  -- peek match → reads both state leaves (VariantTag/VariantPayload path).
  let some peek := plan.functions.find? (·.name == "peek") |
    throw <| IO.userError "OptionState: missing peek"
  let peekRepr := toString (repr peek.body)
  expect (peekRepr.contains "stateLoad 0")
    s!"peek match must load Option tag leaf, body={peekRepr}"
  expect (peekRepr.contains "stateLoad 1")
    s!"peek match must load Option payload leaf, body={peekRepr}"
  expect (peekRepr.contains "ifThenElse" || peekRepr.contains "switchOn")
    s!"peek match must lower to ifThenElse/switchOn, body={peekRepr}"
  liftResult <| Targets.Aleo.validatePlan plan
  let leo ← materializeLeoSource compiled "optionstate"
  expect (leo.contains "mapping pf_state_0: u8 => u64;")
    "OptionState must emit pf_state_0 for tag"
  expect (leo.contains "mapping pf_state_1: u8 => u64;")
    "OptionState must emit pf_state_1 for payload"
  expect (leo.contains "pf_state_0.set(0u8,")
    "OptionState must write the tag mapping"
  expect (leo.contains "pf_state_1.set(0u8,")
    "OptionState must write the payload mapping (none zeroes payload)"
  expect (leo.contains "if (")
    "OptionState peek match must render a Leo if on the tag"
  IO.println "  OptionState Option UInt64 state Plan/IR/Leo pin ok"

  -- FC: Option of non-UInt64 (Bool payload).
  let badBool :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptBool where\n" ++
    "  state o : Option Bool\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  entry set() : UInt64 do\n" ++
    "    o := Option.some(true)\n" ++
    "    return 1\n"
  let badBoolSrc ← liftResult (← session.selectProgramV1
    badBool "<aleo-opt-bool>" "Tests.AleoOptBool" none)
  let badBoolCompiled ← liftResult <|
    Compiler.compileValidatedSourceV1 badBoolSrc
  match planAleo badBoolCompiled with
  | .ok _ =>
      throw <| IO.userError "Aleo Option Bool state must fail closed"
  | .error e =>
      expect (e.render.contains "Option" || e.render.contains "UInt64" ||
          e.render.contains "payload" || e.render.contains "shape")
        s!"Option Bool FC must cite Option/UInt64/payload, got: {e.render}"

  -- FC: nested Option (Option of Option UInt64).
  let badNested :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptNested where\n" ++
    "  state o : Option Option UInt64\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  entry set(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(Option.some(v))\n" ++
    "    return v\n"
  let badNestedSrc ← liftResult (← session.selectProgramV1
    badNested "<aleo-opt-nested>" "Tests.AleoOptNested" none)
  let badNestedCompiled ← liftResult <|
    Compiler.compileValidatedSourceV1 badNestedSrc
  match planAleo badNestedCompiled with
  | .ok _ =>
      throw <| IO.userError "Aleo nested Option state must fail closed"
  | .error e =>
      expect (e.render.contains "Option" || e.render.contains "UInt64" ||
          e.render.contains "payload" || e.render.contains "shape")
        s!"nested Option FC must cite Option/UInt64/payload, got: {e.render}"

  -- FC: Option params (state-only admission).
  let badParam :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptParam where\n" ++
    "  state x : UInt64\n" ++
    "  init() do\n" ++
    "    x := 0\n" ++
    "  entry take(o : Option UInt64) : UInt64 do\n" ++
    "    match o with\n" ++
    "    | Option.some(v) => do\n" ++
    "      return v\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let badParamSrc ← liftResult (← session.selectProgramV1
    badParam "<aleo-opt-param>" "Tests.AleoOptParam" none)
  let badParamCompiled ← liftResult <|
    Compiler.compileValidatedSourceV1 badParamSrc
  match planAleo badParamCompiled with
  | .ok _ =>
      throw <| IO.userError "Aleo Option params must fail closed"
  | .error e =>
      expect (e.render.contains "Option" || e.render.contains "parameter" ||
          e.render.contains "param" || e.render.contains "state-only")
        s!"Option param FC must cite parameter/Option boundary, got: {e.render}"
  IO.println "  OptionState fail-closed matrix ok"

/-- ALEO-I2: Counter query-contract sidecar binds schema, mapping, bare view,
    and honest resultDropped observation (never Final return). -/
unsafe def testQueryContractCounter : IO Unit := do
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
    source "<aleo-qc-counter>" "Tests.AleoQcCounter" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planAleo compiled
  let output ← liftResult <| materializeAleo compiled
  let files := MaterializedArtifactsV1.filesOf output
  expect (files.map (·.path) ==
      #["counter.aleo", "counter.aleo-query-contract.json"])
    s!"query-contract Counter paths, got {files.map (·.path)}"
  let some contractFile := files.find?
      (·.path == "counter.aleo-query-contract.json") |
    throw <| IO.userError "missing counter.aleo-query-contract.json"
  expect (contractFile.mediaType == "application/json")
    "query-contract mediaType must be application/json"
  let c := contractFile.contents
  expect (c.endsWith "\n") "query-contract must end with a trailing newline"
  expect (c.contains "\"schema\": \"proof-forge-aleo-query-contract/v1\"")
    "query-contract schema must be exact proof-forge-aleo-query-contract/v1"
  expect (c.contains "\"program\": \"Counter\"")
    "query-contract program must bind artifact name"
  expect (c.contains "\"programFile\": \"counter.aleo\"")
    "query-contract programFile must bind primary .aleo base path"
  expect (c.contains "\"codegenProfile\": \"aleo-leo-4.0.2-u64-v1\"")
    "query-contract must bind current Aleo profile"
  expect (c.contains "\"leo\": \"4.0.2\"")
    "query-contract must bind Leo 4.0.2"
  expect (c.contains s!"\"sourceHash\": \"{plan.sourceHash}\"")
    "query-contract sourceHash must match plan"
  expect (c.contains s!"\"semanticHash\": \"{plan.semanticHash}\"")
    "query-contract semanticHash must match plan"
  expect (c.contains "\"mappingKey\": \"0u8\"")
    "query-contract mappingKey must be 0u8"
  expect (c.contains "\"executionModel\": \"network-state-descriptor\"")
    "query-contract executionModel must be network-state-descriptor"
  -- Root key order via successive first-occurrence splits (fixed order).
  let afterSchema := (c.splitOn "\"schema\"")[1]!
  expect ((afterSchema.splitOn "\"program\"").length > 1) "schema precedes program"
  let afterProgram := (afterSchema.splitOn "\"program\"")[1]!
  expect ((afterProgram.splitOn "\"programFile\"").length > 1)
    "program precedes programFile"
  let afterProgramFile := (afterProgram.splitOn "\"programFile\"")[1]!
  expect ((afterProgramFile.splitOn "\"codegenProfile\"").length > 1)
    "programFile precedes codegenProfile"
  let afterProfile := (afterProgramFile.splitOn "\"codegenProfile\"")[1]!
  expect ((afterProfile.splitOn "\"leo\"").length > 1) "codegenProfile precedes leo"
  let afterLeo := (afterProfile.splitOn "\"leo\"")[1]!
  expect ((afterLeo.splitOn "\"sourceHash\"").length > 1) "leo precedes sourceHash"
  let afterSource := (afterLeo.splitOn "\"sourceHash\"")[1]!
  expect ((afterSource.splitOn "\"semanticHash\"").length > 1)
    "sourceHash precedes semanticHash"
  let afterSemantic := (afterSource.splitOn "\"semanticHash\"")[1]!
  expect ((afterSemantic.splitOn "\"mappingKey\"").length > 1)
    "semanticHash precedes mappingKey"
  let afterKey := (afterSemantic.splitOn "\"mappingKey\"")[1]!
  expect ((afterKey.splitOn "\"executionModel\"").length > 1)
    "mappingKey precedes executionModel"
  let afterModel := (afterKey.splitOn "\"executionModel\"")[1]!
  expect ((afterModel.splitOn "\"mappings\"").length > 1)
    "executionModel precedes mappings"
  let afterMappings := (afterModel.splitOn "\"mappings\"")[1]!
  expect ((afterMappings.splitOn "\"views\"").length > 1) "mappings precedes views"
  let afterViews := (afterMappings.splitOn "\"views\"")[1]!
  expect ((afterViews.splitOn "\"resultDropped\"").length > 1)
    "views precedes resultDropped"
  -- mappings: state leaf only (not initialized guard).
  expect (c.contains
      "{\"name\":\"pf_state_0\",\"dslName\":\"count\",\"type\":\"u64\",\"default\":\"0u64\"}")
    "query-contract mappings must bind pf_state_0/count/u64/0u64"
  expect (!c.contains "\"initialized\"")
    "query-contract must not list the initialized guard mapping"
  expect (!c.contains "fn get(")
    "query-contract file is JSON, not Leo"
  -- views: bare PlanView mapping get.
  expect (c.contains
      "{\"index\":0,\"name\":\"get\",\"mapping\":\"pf_state_0\",\"key\":\"0u8\",\"type\":\"u64\",\"default\":\"0u64\"}")
    "query-contract views must bind get → pf_state_0"
  -- Primary Instructions (and residual Leo) must omit the bare view
  -- (descriptor / query-contract only).
  let some primaryFile := files.find? (·.path == "counter.aleo") |
    throw <| IO.userError "missing counter.aleo"
  expect (!primaryFile.contents.contains "fn get(")
    "bare view must never emit into primary .aleo"
  expect (!primaryFile.contents.contains "function get:")
    "bare view must never emit into Instructions function table"
  -- resultDropped: only flag=true (increment); honest observation label.
  expect (c.contains
      "{\"name\":\"increment\",\"observation\":\"post-transaction-mapping-query\"}")
    "resultDropped must mark increment as post-transaction-mapping-query"
  expect (!c.contains "\"initialize\"")
    "resultDropped must not list Unit initialize"
  expect (!c.contains "Final return")
    "resultDropped must not claim Final return"
  expect (!c.contains "\"finalReturn\"")
    "resultDropped must not invent a Final return claim"

/-- ALEO-I2: dual bare views bind distinct mapping leaves. -/
unsafe def testQueryContractDualViews : IO Unit := do
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
    source "<aleo-qc-dual>" "Tests.AleoQcDual" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let output ← liftResult <| materializeAleo compiled
  let files := MaterializedArtifactsV1.filesOf output
  expect (files.map (·.path) ==
      #["dual.aleo", "dual.aleo-query-contract.json"])
    s!"dual query-contract paths, got {files.map (·.path)}"
  let some cFile := files.find? (·.path == "dual.aleo-query-contract.json") |
    throw <| IO.userError "missing dual.aleo-query-contract.json"
  let c := cFile.contents
  expect (c.contains
      "{\"name\":\"pf_state_0\",\"dslName\":\"count\",\"type\":\"u64\",\"default\":\"0u64\"}")
    "dual mappings leaf 0"
  expect (c.contains
      "{\"name\":\"pf_state_1\",\"dslName\":\"balance\",\"type\":\"u64\",\"default\":\"0u64\"}")
    "dual mappings leaf 1"
  expect (c.contains
      "{\"index\":0,\"name\":\"getCount\",\"mapping\":\"pf_state_0\",\"key\":\"0u8\",\"type\":\"u64\",\"default\":\"0u64\"}")
    "getCount view binding"
  expect (c.contains
      "{\"index\":1,\"name\":\"getBalance\",\"mapping\":\"pf_state_1\",\"key\":\"0u8\",\"type\":\"u64\",\"default\":\"0u64\"}")
    "getBalance view binding"
  expect (c.contains
      "{\"name\":\"go\",\"observation\":\"post-transaction-mapping-query\"}")
    "go is resultDropped"
  let some primaryFile := files.find? (·.path == "dual.aleo") |
    throw <| IO.userError "missing dual.aleo"
  expect (!primaryFile.contents.contains "fn getCount(")
    "getCount must not appear in primary .aleo"
  expect (!primaryFile.contents.contains "fn getBalance(")
    "getBalance must not appear in primary .aleo"
  expect (!primaryFile.contents.contains "function getCount:")
    "getCount must not appear in Instructions function table"
  expect (!primaryFile.contents.contains "function getBalance:")
    "getBalance must not appear in Instructions function table"

/-- ALEO-I2: no-state pure program → empty mappings/views/resultDropped arrays. -/
unsafe def testQueryContractNoStateEmpty : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BitLogic where\n" ++
    "  entry mask(x : UInt64) : UInt64 do\n" ++
    "    return (x << 2) & 15 | (x >> 1) ^ 3\n" ++
    "  entry both(a : UInt64, b : UInt64) : Bool do\n" ++
    "    return a > 0 && b > 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-qc-empty>" "Tests.AleoQcEmpty" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let output ← liftResult <| materializeAleo compiled
  let files := MaterializedArtifactsV1.filesOf output
  expect (files.map (·.path) ==
      #["bitlogic.aleo", "bitlogic.aleo-query-contract.json"])
    s!"empty-state query-contract paths, got {files.map (·.path)}"
  let some cFile := files.find? (·.path == "bitlogic.aleo-query-contract.json") |
    throw <| IO.userError "missing bitlogic.aleo-query-contract.json"
  let c := cFile.contents
  expect (c.contains "\"mappings\": []")
    "no-state mappings must be empty array"
  expect (c.contains "\"views\": []")
    "no-state views must be empty array (legal)"
  expect (c.contains "\"resultDropped\": []")
    "pure entries must leave resultDropped empty"
  expect (c.contains "\"schema\": \"proof-forge-aleo-query-contract/v1\"")
    "empty-state still binds schema"
  expect (c.contains "\"executionModel\": \"network-state-descriptor\"")
    "empty-state still binds executionModel"

/-- ALEO-I2: double materialize is exact-byte deterministic for both base files. -/
unsafe def testQueryContractDeterminism : IO Unit := do
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
    source "<aleo-qc-det>" "Tests.AleoQcDet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let out1 ← liftResult <| materializeAleo compiled
  let out2 ← liftResult <| materializeAleo compiled
  let f1 := MaterializedArtifactsV1.filesOf out1
  let f2 := MaterializedArtifactsV1.filesOf out2
  expect (f1.size == 2 && f2.size == 2) "determinism: two base files"
  expect (f1[0]!.path == f2[0]!.path && f1[0]!.contents == f2[0]!.contents)
    "determinism: Leo source exact-byte equal"
  expect (f1[1]!.path == f2[1]!.path && f1[1]!.contents == f2[1]!.contents)
    "determinism: query-contract exact-byte equal"
  expect (f1[1]!.contents == f2[1]!.contents)
    "determinism: query-contract replay identity"

/-- Dual Aleo profiles: same Plan body / planDigest; query-contract profile is
    selection-honest; supportClaim/BuildIdentity diverge. -/
unsafe def testDualProfilePlanAndQueryContract : IO Unit := do
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
    source "<aleo-dual-profile>" "Tests.AleoDualProfile" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let planSrc ← liftResult <| planAleo compiled none
  let planCmp ← liftResult <|
    planAleo compiled (some CodegenProfileId.aleoLeoU64CompileV1)
  expect (planSrc == planCmp)
    "dual profiles must produce BEq-equal retained Plans"
  let digSrc ← match Targets.Aleo.engineeringAleoPlanDigestV1 planSrc with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"source plan digest: {e}"
  let digCmp ← match Targets.Aleo.engineeringAleoPlanDigestV1 planCmp with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"compile plan digest: {e}"
  expect (digSrc.algorithm == digCmp.algorithm && digSrc.bytes == digCmp.bytes)
    "dual profiles must share planDigest"
  let irSrc ← liftResult <| irAleo compiled none
  let irCmp ← liftResult <|
    irAleo compiled (some CodegenProfileId.aleoLeoU64CompileV1)
  expect (irSrc.codegenProfile == CodegenProfileId.aleoLeoU64V1)
    "source IR binds default source profile"
  expect (irCmp.codegenProfile == CodegenProfileId.aleoLeoU64CompileV1)
    "compile IR binds compile profile"
  let outSrc ← liftResult <| materializeAleo compiled none
  let outCmp ← liftResult <|
    materializeAleo compiled (some CodegenProfileId.aleoLeoU64CompileV1)
  expect (MaterializedArtifactsV1.codegenProfileIdOf outSrc ==
      CodegenProfileId.aleoLeoU64V1)
    "source materialize binds source profile"
  expect (MaterializedArtifactsV1.codegenProfileIdOf outCmp ==
      CodegenProfileId.aleoLeoU64CompileV1)
    "compile materialize binds compile profile"
  let filesSrc := MaterializedArtifactsV1.filesOf outSrc
  let filesCmp := MaterializedArtifactsV1.filesOf outCmp
  expect (filesSrc.map (·.path) ==
      #["counter.aleo", "counter.aleo-query-contract.json"])
    s!"source profile base paths (Instructions+query), got {filesSrc.map (·.path)}"
  expect (filesCmp.map (·.path) ==
      #["counter.aleo", "counter.aleo-query-contract.json", "counter.leo"])
    s!"compile profile dual-writes Leo for compare, got {filesCmp.map (·.path)}"
  let some primarySrc := filesSrc.find? (·.path == "counter.aleo") |
    throw <| IO.userError "dual: missing source counter.aleo"
  let some primaryCmp := filesCmp.find? (·.path == "counter.aleo") |
    throw <| IO.userError "dual: missing compile counter.aleo"
  expect (primarySrc.contents == primaryCmp.contents)
    "dual profiles must emit exact-byte-equal Instructions primary"
  expect (primarySrc.contents.contains "program counter.aleo;")
    "dual profile primary must be Instructions text"
  let some leoCmp := filesCmp.find? (·.path == "counter.leo") |
    throw <| IO.userError "dual: missing compile counter.leo"
  expect (leoCmp.contents.contains "program counter.aleo {")
    "compile dual-write must be Leo 4 brace source"
  let some qcSrc := filesSrc.find? (·.path == "counter.aleo-query-contract.json") |
    throw <| IO.userError "dual: missing source query-contract"
  let some qcCmp := filesCmp.find? (·.path == "counter.aleo-query-contract.json") |
    throw <| IO.userError "dual: missing compile query-contract"
  expect (qcSrc.contents.contains "\"codegenProfile\": \"aleo-leo-4.0.2-u64-v1\"")
    "source sidecar must honestly bind source profile"
  expect (qcCmp.contents.contains
      "\"codegenProfile\": \"aleo-leo-4.0.2-u64-compile-v1\"")
    "compile sidecar must honestly bind compile profile"
  expect (qcSrc.contents != qcCmp.contents)
    "dual profile sidecars must differ (profile field)"
  -- Descriptor residual stays source; compile is accepted without second table.
  expect (Targets.Aleo.descriptor.codegenProfile == CodegenProfileId.aleoLeoU64V1)
    "residual Aleo descriptor remains source default"
  expect (DescriptorDataV1.acceptsCodegenProfile Targets.Aleo.descriptor
      CodegenProfileId.aleoLeoU64V1)
    "descriptor accepts source profile"
  expect (DescriptorDataV1.acceptsCodegenProfile Targets.Aleo.descriptor
      CodegenProfileId.aleoLeoU64CompileV1)
    "descriptor accepts compile profile"
  expect (!DescriptorDataV1.acceptsCodegenProfile Targets.Aleo.descriptor
      CodegenProfileId.evmYulSolc0834V1)
    "descriptor rejects foreign EVM profile"

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
  testNarrowUintStateLeo
  testNarrowUintFailClosed
  testNamedStructReturn
  testNamedEnumReturn
  testNamedStructReturnFinalDropped
  testAnonymousArrayReturn
  testAnonymousOptionReturn
  testMultiLeafViewOverStateFailClosed
  testAggregateReturnFailClosed
  testOptionState
  testQueryContractCounter
  testQueryContractDualViews
  testQueryContractNoStateEmpty
  testQueryContractDeterminism
  testDualProfilePlanAndQueryContract
  IO.println "Tests.Materialization.Aleo: ok"

end Tests.Materialization.Aleo
