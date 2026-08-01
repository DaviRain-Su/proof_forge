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

unsafe def run : IO Unit := do
  testCounterPsySource
  testCheckedArithGuards
  testBitwiseAndShifts
  testEmitAndPureFn
  testFailClosedBitNot
  IO.println "Tests.Materialization.PsySourceV1: ok"

end Tests.Materialization.PsySourceV1
