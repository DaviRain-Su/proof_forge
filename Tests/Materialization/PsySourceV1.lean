/-
  Psy target leaf tests: capability-gated Plan/IR/emitter over the retained
  SemanticProgramV1 envelope. Product path: resolveBuildSelectionV1 → capability
  mint → planFromCapability → buildFromCapability (psy is implemented in the
  registry with the psy-dargo-u64-v1 profile).
-/
import ProofForgeV2
import ProofForgeV2.Targets.Psy
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline

namespace Tests.Materialization.PsySourceV1

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

private def resolvePsyCapability (compiled : CompiledSemanticV1) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.psy none
  Targets.resolveEngineeringRequirementsV1 selection compiled

private def planPsy (compiled : CompiledSemanticV1) : CompileResult Targets.Psy.Plan := do
  let capability ← resolvePsyCapability compiled
  Targets.Psy.planFromCapability capability

private def buildPsy (compiled : CompiledSemanticV1) :
    CompileResult (Array OutputFile) := do
  let capability ← resolvePsyCapability compiled
  Targets.Psy.buildFromCapability capability

/-- Counter: contract struct + storage field + initialize/increment/get methods
    and checked-arithmetic guard lines for `+`. -/
unsafe def testCounterPsySource : IO Unit := do
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
    source "<psy-counter>" "Tests.PsyCounter" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  expect (plan.stateFieldNames == #["count"])
    "Counter Psy plan must carry the count state field"
  expect (plan.functions.map (·.name) == #["initialize", "increment", "get"])
    "Counter Psy plan must carry initialize + increment + get in source order"
  liftResult <| Targets.Psy.validatePlan plan
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (fun f => f.path == "Counter.psy") |
    throw <| IO.userError "psy: missing Counter.psy"
  let psy := psyFile.contents
  expect (psy.contains "#[contract]")
    "Psy source must declare a contract"
  expect (psy.contains "#[derive(Storage)]")
    "Psy source must derive Storage"
  expect (psy.contains "pub struct Counter ")
    "Psy source must declare the Counter contract struct"
  expect (psy.contains "pub count: Felt,")
    "Psy source must declare the count storage field as Felt"
  expect (psy.contains "impl CounterRef ")
    "Psy source must declare the CounterRef impl block"
  expect (psy.contains "pub fn initialize(p0: Felt)")
    "initialize must materialize as a contract method"
  expect (psy.contains "pub fn increment(p0: Felt) -> Felt")
    "increment must materialize as a Felt-returning method"
  expect (psy.contains "pub fn get() -> Felt")
    "get must materialize as a Felt-returning view method"
  expect (psy.contains "c.count = ")
    "initialize/increment must write storage via c.count ="
  expect (psy.contains "c.count.get()")
    "reads must use c.count.get()"
  -- Checked u64 add guard: product then assert against 2^64.
  expect (psy.contains "18446744073709551616")
    "checked add/mul must emit the 2^64 Felt bound"
  expect (psy.contains "u64 add overflow")
    "checked add must emit the overflow assert message"
  expect (psy.contains "CounterRef::new(ContractMetadata::current())")
    "each method must construct the contract ref"

/-- Checked sub/mul/div guards + bare assert. -/
unsafe def testCheckedArithGuards : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Arith where\n" ++
    "  entry mix(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    let s : UInt64 := a - b\n" ++
    "    let p : UInt64 := a * b\n" ++
    "    let q : UInt64 := a / b\n" ++
    "    assert s > 0\n" ++
    "    return p + q\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-arith>" "Tests.PsyArith" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Arith.psy") |
    throw <| IO.userError "psy: missing Arith.psy"
  let psy := psyFile.contents
  expect (psy.contains "u64 sub underflow")
    "checked sub must assert a >= b before subtraction"
  expect (psy.contains "u64 mul overflow")
    "checked mul must assert product < 2^64"
  expect (psy.contains "u64 div by zero")
    "checked div must assert divisor != 0"
  expect (psy.contains "assert(")
    "bare assert must render as Psy assert"

/-- Bitwise/shift/logical surface (Felt-native ops + shift count guard). -/
unsafe def testBitwiseAndShifts : IO Unit := do
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
    source "<psy-bitlogic>" "Tests.PsyBitLogic" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (fun f => f.path == "BitLogic.psy") |
    throw <| IO.userError "psy: missing BitLogic.psy"
  let psy := psyFile.contents
  expect (psy.contains " << " || psy.contains "<<")
    "shift-left must render"
  expect (psy.contains "invalidShift: count >= 64")
    "shift count guard must be emitted"
  expect (psy.contains " & " || psy.contains "&")
    "bitAnd must render"
  expect (psy.contains " && " || psy.contains "&&")
    "logical and must render"
  expect (psy.contains "-> bool")
    "Bool-returning entry must render bool result"

/-- emit + pureFn localCall forms. -/
unsafe def testEmitAndPureFn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Emitter where\n" ++
    "  event Ticked(value : UInt64)\n" ++
    "  fn double(a : UInt64) : UInt64 do\n" ++
    "    return a + a\n" ++
    "  entry tick(x : UInt64) : UInt64 do\n" ++
    "    emit Ticked(x)\n" ++
    "    return double(x)\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-emit>" "Tests.PsyEmitter" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  expect (plan.events.map (·.name) == #["Ticked"])
    "Emitter plan must carry the Ticked event"
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Emitter.psy") |
    throw <| IO.userError "psy: missing Emitter.psy"
  let psy := psyFile.contents
  expect (psy.contains "__emit([")
    "emit must lower to __emit([...])"
  expect (psy.contains "event `Ticked`")
    "emit comment must name the event"
  expect (psy.contains "fn double(p0: Felt) -> Felt")
    "pureFn must materialize as a free helper function"
  expect (psy.contains "double(")
    "localCall must invoke the helper"

/-- Fail closed: unary bitNot has no Psy surface. -/
unsafe def testFailClosedBitNot : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Flip where\n" ++
    "  entry flip(x : UInt64) : UInt64 do\n" ++
    "    return ~x\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-flip>" "Tests.PsyFlip" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planPsy compiled with
  | .error (.planInvariant .psy msg) =>
      expect (msg.contains "bitNot" || msg.contains "bitwise-not")
        s!"bitNot planInvariant must mention bitNot, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .psy, got {e.render}"
  | .ok _ => throw <| IO.userError "bitNot must fail closed at Psy plan"

/-- if/else multi-block control flow renders as a Psy if-else. -/
unsafe def testIfElseControlFlow : IO Unit := do
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
    source "<psy-branch>" "Tests.PsyBranch" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Branch.psy") |
    throw <| IO.userError "psy: missing Branch.psy"
  let psy := psyFile.contents
  expect (psy.contains "if ") "if must render"
  expect (psy.contains "} else {") "if-else must render the else branch"
  expect (psy.contains "c.count = ") "arms must write storage"

/-- match statement lowers to a nested if-else chain on the scrutinee. -/
unsafe def testMatchStatement : IO Unit := do
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
    source "<psy-pick>" "Tests.PsyPick" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Pick.psy") |
    throw <| IO.userError "psy: missing Pick.psy"
  let psy := psyFile.contents
  expect (psy.contains " == 0") "match arm 0 must compare the scrutinee to 0"
  expect (psy.contains " == 1") "match arm 1 must compare the scrutinee to 1"
  expect (psy.contains "} else {") "match must lower to nested if-else"
  expect (plan.functions.map (·.name) == #["initialize", "apply"])
    "Pick Psy plan must carry initialize + apply"

/-- Bounded for lowers to a Psy range loop with the boundExceeded guard. -/
unsafe def testBoundedFor : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Loop where\n" ++
    "  state total : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    total := initial\n" ++
    "  entry run() : UInt64 do\n" ++
    "    for i in 0 ..< 8 bounded 8 do\n" ++
    "      total := total + 1\n" ++
    "    return total\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-loop>" "Tests.PsyLoop" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Loop.psy") |
    throw <| IO.userError "psy: missing Loop.psy"
  let psy := psyFile.contents
  expect (psy.contains "for pf_c0 in 0u32..8u32")
    "bounded for must render the Psy range loop with the static bound"
  expect (psy.contains "boundExceeded")
    "the end-start <= N guard must be emitted"
  expect (psy.contains "pf_i0")
    "the induction variable must materialize"

/-- Bare revert lowers to assert(false) (halt = atomic revert). -/
unsafe def testBareRevert : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Stop where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    if x == 0 then\n" ++
    "      revert\n" ++
    "    else\n" ++
    "      return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-stop>" "Tests.PsyStop" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Stop.psy") |
    throw <| IO.userError "psy: missing Stop.psy"
  let psy := psyFile.contents
  expect (psy.contains "assert(false")
    "bare revert must lower to assert(false)"

/-- Revert with error arguments cannot be expressed on the Psy surface. -/
unsafe def testRevertWithArgsFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Cap where\n" ++
    "  state count : UInt64\n" ++
    "  error Cap(limit : UInt64)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    if x > 10 then\n" ++
    "      revert Cap(x)\n" ++
    "    else\n" ++
    "      return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-cap>" "Tests.PsyCap" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match buildPsy compiled with
  | .error (.planInvariant .psy msg) =>
      expect (msg.contains "revert" && msg.contains "error")
        s!"revert-with-args must fail closed, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .psy, got {e.render}"
  | .ok _ => throw <| IO.userError "revert with error args must fail closed at Psy"

/-- Sync external call renders as __invoke_sync#<Felt> with hashed components. -/
unsafe def testExternalCall : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Ext where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    call Peer.go(x)\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-ext>" "Tests.PsyExt" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Ext.psy") |
    throw <| IO.userError "psy: missing Ext.psy"
  let psy := psyFile.contents
  expect (psy.contains "__invoke_sync#<Felt>")
    "call must lower to __invoke_sync#<Felt>"
  expect (psy.contains "// call `Peer.go`")
    "the callee note must name the verbatim qualified callee"

/-- Schedule fails closed twice: the resolver declines effect.asynchronous-workflow
    (PF-REQ-UNSUPPORTED) and the emitter rejects the plan's schedule stmt. -/
unsafe def testScheduleFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Later where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    schedule ledger.daily(x)\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-later>" "Tests.PsyLater" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  -- Capability path: the resolver declines the async key first.
  match resolvePsyCapability compiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"schedule must be declined at the capability, got {e.code}"
  | .ok _ =>
      -- Non-product path: plan accepts, emitter fails closed.
      let _ ← liftResult <| planPsy compiled
      match buildPsy compiled with
      | .error (.planInvariant .psy msg) =>
          expect (msg.contains "deferred crosscall")
            s!"schedule must fail closed at the emitter, got: {msg}"
      | .error e => throw <| IO.userError s!"expected planInvariant .psy, got {e.render}"
      | .ok _ => throw <| IO.userError "schedule must fail closed at Psy"

/-- Full comparison family and mod render with their Psy operators. -/
unsafe def testComparisonsAndMod : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Cmp where\n" ++
    "  entry cmp(a : UInt64, b : UInt64) : Bool do\n" ++
    "    return a == b || a != b || a < b || a <= b || a > b || a >= b\n" ++
    "  entry rem(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    let t : UInt64 := a % b\n" ++
    "    return t\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-cmp>" "Tests.PsyCmp" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Cmp.psy") |
    throw <| IO.userError "psy: missing Cmp.psy"
  let psy := psyFile.contents
  for op in ["==", "!=", "<", "<=", ">", ">=", "%"] do
    expect (psy.contains op) s!"comparison/mod operator {op} must render"

/-- Logical-or and Bool negation render. -/
unsafe def testLogicalOrAndNot : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Log where\n" ++
    "  entry both(a : UInt64, b : UInt64) : Bool do\n" ++
    "    return !(a == 0 || b == 0)\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-log>" "Tests.PsyLog" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Log.psy") |
    throw <| IO.userError "psy: missing Log.psy"
  let psy := psyFile.contents
  expect (psy.contains "||") "logical or must render"
  expect (psy.contains "!(") "Bool negation must render"

/-- assert-else is outside the envelope and fails closed. -/
unsafe def testAssertElseFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Guard where\n" ++
    "  state count : UInt64\n" ++
    "  error Guard(limit : UInt64)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    assert x > 0 else Guard(0)\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-guard>" "Tests.PsyGuard" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planPsy compiled with
  | .error (.planInvariant .psy msg) =>
      expect (msg.contains "assert")
        s!"assert-else must fail closed at Psy plan, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .psy, got {e.render}"
  | .ok _ => throw <| IO.userError "assert-else must fail closed at Psy plan"

/-- Multi-state / multi-event / multi-param fn with Bool result. -/
unsafe def testMultiStateMultiEvent : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Rich where\n" ++
    "  state count : UInt64\n" ++
    "  state balance : UInt64\n" ++
    "  event Ticked(value : UInt64)\n" ++
    "  event Moved(from : UInt64, to : UInt64)\n" ++
    "  fn above(a : UInt64, b : UInt64) : Bool do\n" ++
    "    return a > b\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "    balance := initial\n" ++
    "  entry go(x : UInt64) : UInt64 do\n" ++
    "    emit Ticked(x)\n" ++
    "    emit Moved(count, balance)\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-rich>" "Tests.PsyRich" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  expect (plan.stateFieldNames == #["count", "balance"])
    "Rich plan must carry both state fields in source order"
  expect (plan.events.map (·.name) == #["Ticked", "Moved"])
    "Rich plan must carry both events in source order"
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Rich.psy") |
    throw <| IO.userError "psy: missing Rich.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub count: Felt," && psy.contains "pub balance: Felt,")
    "both storage fields must render"
  expect (psy.contains "event `Ticked`" && psy.contains "event `Moved`")
    "both event notes must render"
  expect (psy.contains "fn above(p0: Felt, p1: Felt) -> bool")
    "multi-param Bool fn must render as a helper"

/-- Void entry (no return) renders a method without a result type. -/
unsafe def testVoidEntry : IO Unit := do
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
    source "<psy-void>" "Tests.PsyVoid" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Void.psy") |
    throw <| IO.userError "psy: missing Void.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub fn bump(p0: Felt)")
    "void entry must render without a result arrow"
  expect (psy.contains "c.count = ")
    "void entry must still write storage"

unsafe def run : IO Unit := do
  testCounterPsySource
  testCheckedArithGuards
  testBitwiseAndShifts
  testEmitAndPureFn
  testFailClosedBitNot
  testIfElseControlFlow
  testMatchStatement
  testBoundedFor
  testBareRevert
  testRevertWithArgsFailClosed
  testExternalCall
  testScheduleFailClosed
  testComparisonsAndMod
  testLogicalOrAndNot
  testAssertElseFailClosed
  testMultiStateMultiEvent
  testVoidEntry
  IO.println "Tests.Materialization.PsySourceV1: ok"

end Tests.Materialization.PsySourceV1
