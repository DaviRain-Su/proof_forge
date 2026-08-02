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
  -- Checked u64 add guard: field-wrap (sum >= lhs). 2^64 is not a legal
  -- Goldilocks Felt literal (p = 2^64−2^32+1); dargo rejects it.
  expect (!psy.contains "18446744073709551616")
    "checked add must not emit the illegal 2^64 Felt bound"
  expect (psy.contains "u64 add overflow")
    "checked add must emit the overflow assert message"
  expect (psy.contains ">=" || psy.contains "≥")
    "checked add must use a field-wrap (>= lhs) guard"
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
    "checked mul must emit the field-wrap inverse overflow guard"
  expect (!psy.contains "18446744073709551616")
    "checked mul must not emit the illegal 2^64 Felt bound"
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

/-- UInt64 bitNot (~) lowers to Plan `checkedBitNot` and emits exact-semantics
    with a Felt representability guard:
      bitNot x = (2^64−1) − x  is a legal Felt iff x ≥ 2^32−1 (result < p).
    Emission: `assert x >= 4294967295` then wrapping Felt sub
    `(4294967294) − x` where 4294967294 = 2^32−2 ≡ (2^64−1) (mod p).
    Boundary coverage (runtime / math):
      x=0         → trap (result = 2^64−1 ≥ p)
      x=2^32−2    → trap (result = p)
      x=2^32−1    → p−1 (representable)
      x=UInt64.max→ math result 0, but UInt64.max ∉ Felt domain [0,p); not a
                    runtime input on this surface (Felt values are already < p).
    Forbidden: silent mod-p bitNot / illegal 2^64−1 Felt literal. -/
unsafe def testUInt64BitNotLowered : IO Unit := do
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
  let plan ← liftResult <| planPsy compiled
  let some flip := plan.functions.find? (·.name == "flip") |
    throw <| IO.userError s!"flip: missing flip, got {plan.functions.map (·.name)}"
  expect (flip.body == #[.returnValue (.checkedBitNot (.param 0))])
    s!"UInt64 bitNot must lower to Plan checkedBitNot(param0), got {repr flip.body}"
  expect (!flip.params.any (·.isU32))
    "flip: UInt64 param must not be tagged isU32"
  expect (!flip.resultIsU32)
    "flip: UInt64 result must not be tagged resultIsU32"
  liftResult <| Targets.Psy.validatePlan plan
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Flip.psy") |
    throw <| IO.userError "psy: missing Flip.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub fn flip(p0: Felt) -> Felt")
    "UInt64 bitNot fn must render Felt param and result"
  -- Representability guard: x >= 2^32−1 (exact UInt64 bitNot result < p)
  expect (psy.contains "4294967295")
    "UInt64 bitNot must emit the 2^32−1 representability threshold"
  expect (psy.contains "u64 bitNot result not representable in Felt")
    "UInt64 bitNot must emit the representability assert message"
  -- Reduced mask 2^32−2 used as wrapping Felt sub (≡ 2^64−1 mod p)
  expect (psy.contains "4294967294")
    "UInt64 bitNot must emit the reduced mask 2^32−2 for field sub"
  expect (psy.contains " - ")
    "UInt64 bitNot must emit Felt subtraction of the reduced mask"
  -- Never emit the illegal full UInt64 all-ones mask as a Felt literal
  expect (!psy.contains "18446744073709551615")
    "UInt64 bitNot must not emit the illegal 2^64−1 Felt literal"
  -- Must not reuse the u32 XOR surface
  expect (!psy.contains "4294967295u32")
    "UInt64 bitNot must not emit the u32 XOR mask form"

/-- Fail closed: Int64 bitNot has no Psy surface (checkedBitNot is UInt64-only). -/
unsafe def testFailClosedInt64BitNot : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program FlipI64 where\n" ++
    "  entry flip(x : Int64) : Int64 do\n" ++
    "    return ~x\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-flip-i64>" "Tests.PsyFlipI64" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planPsy compiled with
  | .error (.planInvariant .psy msg) =>
      expect (msg.contains "bitNot" || msg.contains "Int64")
        s!"Int64 bitNot planInvariant must mention bitNot/Int64, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .psy, got {e.render}"
  | .ok _ => throw <| IO.userError "Int64 bitNot must fail closed at Psy plan"

/-- bitNot (~) on UInt32 lowers to `x ^ 4294967295u32` (XOR mask, verified
    faithful on the real dargo VM). UInt64 bitNot uses checkedBitNot separately. -/
unsafe def testUInt32BitNotLowered : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Flip32 where\n" ++
    "  entry flip(x : UInt32) : UInt32 do\n" ++
    "    return ~x\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-flip32>" "Tests.PsyFlip32" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  let some flip := plan.functions.find? (·.name == "flip") |
    throw <| IO.userError s!"flip32: missing flip, got {plan.functions.map (·.name)}"
  expect (flip.body == #[.returnValue (.bitNot (.param 0))])
    s!"UInt32 bitNot must lower to Plan bitNot(param0), got {repr flip.body}"
  expect (flip.params.any (·.isU32))
    "flip32: UInt32 param must be tagged isU32 in the Plan"
  expect (flip.resultIsU32)
    "flip32: UInt32 result must be tagged resultIsU32 in the Plan"
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Flip32.psy") |
    throw <| IO.userError "psy: missing Flip32.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub fn flip(p0: u32) -> u32")
    "UInt32 bitNot fn must render u32 param and result"
  expect (psy.contains "4294967295u32")
    "UInt32 bitNot must emit the 2^32−1 mask with the u32 suffix"
  expect (psy.contains " ^ ")
    "UInt32 bitNot must emit XOR with the mask"
  expect (!psy.contains "18446744073709551615")
    "UInt32 bitNot must not emit the illegal 2^64−1 mask"

/-- Fail closed: UInt32 arithmetic/bitwise/shift on u32 operands. The real
    dargo VM u32 ops are not faithful to Reference (overflow/underflow are
    internal panics — even `a - a = 0` panics "u32 sub value too low" — and
    shifts wrap), so only u32 comparisons + bitNot are admitted. -/
unsafe def testUInt32ArithFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Add32 where\n" ++
    "  entry add(a : UInt32, b : UInt32) : UInt32 do\n" ++
    "    return a + b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-add32>" "Tests.PsyAdd32" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planPsy compiled with
  | .error (.planInvariant .psy msg) =>
      expect (msg.contains "UInt32" && msg.contains "slice")
        s!"u32 add must fail closed citing the u32 slice, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .psy, got {e.render}"
  | .ok _ => throw <| IO.userError "u32 add must fail closed at Psy plan"

/-- UInt32 comparisons are admitted (native unsigned == Reference unsigned). -/
unsafe def testUInt32CompareLowered : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Cmp32 where\n" ++
    "  entry cmp(a : UInt32, b : UInt32) : Bool do\n" ++
    "    return a < b || a == b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-cmp32>" "Tests.PsyCmp32" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Cmp32.psy") |
    throw <| IO.userError "psy: missing Cmp32.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub fn cmp(p0: u32, p1: u32) -> bool")
    "u32 comparison fn must render u32 params and bool result"
  expect (psy.contains " < ")
    "u32 lt must render"
  expect (psy.contains " == ")
    "u32 eq must render"

/-- Fail closed: narrow Int (Int8/16/32). The Psy toolchain has no native
    narrow integer types, no u8 storage impl, and the u32/Felt building blocks
    for faithful sign-extended narrow arithmetic are absent or VM-buggy
    (u32 sub panics on `a - a`; u32 shifts wrap; Felt ops are modular). -/
unsafe def testNarrowIntFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program I8 where\n" ++
    "  entry cmp(a : Int8, b : Int8) : Bool do\n" ++
    "    return a < b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-i8>" "Tests.PsyI8" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planPsy compiled with
  | .error (.planInvariant .psy msg) =>
      expect (msg.contains "Int" || msg.contains "width")
        s!"narrow Int must fail closed at Psy type-closure, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .psy, got {e.render}"
  | .ok _ => throw <| IO.userError "narrow Int must fail closed at Psy plan"

/-- Fail closed: Bytes state. Psy has no u8 native type / storage impl, and
    Bytes element ops return UInt8 which is outside the Psy pilot closure. -/
unsafe def testBytesStateFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Buf where\n" ++
    "  state buf : Bytes 4\n" ++
    "  init() do\n" ++
    "    buf[0] := 0\n" ++
    "  entry get() : UInt8 do\n" ++
    "    return buf[0]\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-bytes>" "Tests.PsyBytes" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planPsy compiled with
  | .error (.planInvariant .psy msg) =>
      expect (msg.contains "Bytes" || msg.contains "UInt8" ||
          msg.contains "container" || msg.contains "Array-only")
        s!"Bytes state must fail closed citing Bytes/UInt8/container boundary, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .psy, got {e.render}"
  | .ok _ => throw <| IO.userError "Bytes state must fail closed at Psy plan"

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
  -- For endpoints must be typed expressions (bare integer literals have no
  -- expected-type context at for-start; match NEAR/Noir product for style).
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Loop where\n" ++
    "  state total : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    total := initial\n" ++
    "  entry run(n : UInt64) : UInt64 do\n" ++
    "    let limit : UInt64 := n + 8\n" ++
    "    for i in n ..< limit bounded 8 do\n" ++
    "      total := total + 1\n" ++
    "    return total\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-loop>" "Tests.PsyLoop" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Loop.psy") |
    throw <| IO.userError "psy: missing Loop.psy"
  let psy := psyFile.contents
  expect (psy.contains "for pf_c0 in " || psy.contains "for ")
    "bounded for must render a Psy range loop"
  expect (psy.contains "boundExceeded")
    "the end-start <= N guard must be emitted"
  expect (psy.contains "pf_i0")
    "the induction variable must materialize"

/-- Zero-arg error revert lowers to assert(false) (halt = atomic revert).
    ProgramV1 has no bare `revert` without an error name; zero-arg `error Halt()`
    + `revert Halt` is the product surface that Psy admits. -/
unsafe def testBareRevert : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Stop where\n" ++
    "  state count : UInt64\n" ++
    "  error Halt()\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    if x == 0 then\n" ++
    "      revert Halt\n" ++
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
    "zero-arg revert must lower to assert(false)"

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
  expect (psy.contains "!") "Bool negation must render"

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
    "    assert x > 0 else Guard\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-guard>" "Tests.PsyGuard" none)
  match Compiler.compileValidatedSourceV1 parsed with
  | .error err =>
      expect (err.render.contains "assert" || err.render.contains "PF-SRC-INVALID")
        s!"assert-else must fail closed at product compile, got: {err.render}"
  | .ok compiled =>
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
    "  event Moved(src : UInt64, dst : UInt64)\n" ++
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

/-- Void entry (no return) fails closed at product compile today: Normalize
    requires an explicit return for entry/view (init-only implicit returnNone).
    Psy lowerer/emitter support for Unit entries exists but is currently
    unreachable from `entry name(...) do` without a return. -/
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
  match Compiler.compileValidatedSourceV1 parsed with
  | .error err =>
      expect (err.render.contains "explicit return" ||
          err.render.contains "PF-SRC-INVALID")
        s!"void entry must fail closed at product compile, got {err.render}"
  | .ok compiled =>
      -- If Normalize admits Unit entries, Psy must still materialize them.
      let files ← liftResult <| buildPsy compiled
      let some psyFile := files.find? (·.path == "Void.psy") |
        throw <| IO.userError "psy: missing Void.psy"
      let psy := psyFile.contents
      expect (psy.contains "pub fn bump(p0: Felt)")
        "void entry must render without a result arrow"
      expect (psy.contains "c.count = ")
        "void entry must still write storage"

/-- PsyFelt research pin (2026-08-01): Field bn254_fr fails closed at Psy
    type-closure. Native Felt is Goldilocks (p = 2^64−2^32+1), not bn254 Fr;
    wording must cite Goldilocks / modulus mismatch so no silent wrong-field
    mapping can land later. -/
unsafe def testFieldBn254FailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PsyFieldPin where\n" ++
    "  state acc : Field bn254_fr\n" ++
    "  init(initial : Field bn254_fr) do\n" ++
    "    acc := initial\n" ++
    "  entry bump(delta : Field bn254_fr) : Field bn254_fr do\n" ++
    "    acc := acc + delta\n" ++
    "    return acc\n" ++
    "  view get() : Field bn254_fr do\n" ++
    "    return acc\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-field-pin>" "Tests.PsyFieldPin" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planPsy compiled with
  | .ok _ =>
      throw <| IO.userError
        "Field bn254_fr must fail closed at Psy type-closure (Felt is Goldilocks, not bn254 Fr)"
  | .error e =>
      let msg := e.render
      expect (msg.contains "Field" || msg.contains "unsupported" ||
          msg.contains "Goldilocks" || msg.contains "bn254")
        s!"Psy Field decline must cite Field/Goldilocks/bn254 boundary, got: {msg}"
      expect (msg.contains "Goldilocks" || msg.contains "0xFFFFFFFF00000001" ||
          msg.contains "2^64-2^32+1" || msg.contains "bn254 Fr")
        s!"Psy Field decline must cite Goldilocks modulus vs bn254 Fr, got: {msg}"
      expect (msg.contains "Psy" || msg.contains "psy")
        s!"Psy Field decline must label Psy, got: {msg}"

/-- T14 catalog v2 (Goldilocks): Field goldilocks state/param/body lowers to
    native Psy Felt. State is a Felt storage field; add lowers to native Felt
    arithmetic (no checked-overflow guard; exact mod Goldilocks). -/
unsafe def testGoldilocksFieldStateArith : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PsyGoldField where\n" ++
    "  state acc : Field goldilocks\n" ++
    "  init(initial : Field goldilocks) do\n" ++
    "    acc := initial\n" ++
    "  entry bump(delta : Field goldilocks) : Field goldilocks do\n" ++
    "    acc := acc + delta\n" ++
    "    return acc\n" ++
    "  view get() : Field goldilocks do\n" ++
    "    return acc\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-gold-field>" "Tests.PsyGoldField" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  expect (plan.stateFieldNames == #["acc"])
    s!"Goldilocks plan must carry the acc Felt state field, got {plan.stateFieldNames}"
  let bump := plan.functions.find? (·.name == "bump")
  expect bump.isSome "Goldilocks plan must carry the bump entry"
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (fun f => f.path == "PsyGoldField.psy") |
    throw <| IO.userError "psy: missing PsyGoldField.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub acc: Felt")
    s!"Psy Goldilocks source must declare the acc Felt storage field, got:\n{psy}"
  -- Native Felt add (no checked-overflow guard `>= p` line for Felt fields).
  expect (psy.contains " + p0")
    s!"Psy Goldilocks add must lower to native Felt +, got:\n{psy}"

/-- Omitted-type let: `let x := a + b` materializes through checked-add
    (same surface as an annotated UInt64 let). -/
unsafe def testOmittedTypeLet : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OmitLet where\n" ++
    "  entry sum(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    let x := a + b\n" ++
    "    return x\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-omit-let>" "Tests.PsyOmitLet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  let some sum := plan.functions.find? (·.name == "sum") |
    throw <| IO.userError
      s!"omit-let: missing sum function, got {plan.functions.map (·.name)}"
  expect (sum.body == #[
      .returnValue (.checkedAdd (.param 0) (.param 1))])
    "omit-let: sum must lower let x := a+b into return checkedAdd(a,b)"
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "OmitLet.psy") |
    throw <| IO.userError "psy: missing OmitLet.psy"
  let psy := psyFile.contents
  expect (psy.contains "u64 add overflow" || psy.contains " + ")
    "omit-let must render checked-add (overflow guard or +)"
  expect (psy.contains "return ")
    "omit-let sum must still return the bound value"


/-- H3 PsyAleoAggregate: named Struct flattens to Felt storage leaves p_x/p_y. -/
unsafe def testNamedAggregateLowered : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2
" ++
    "open ProofForgeV2.Language
" ++
    "program PsyPoint where
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
    source "<psy-point>" "Tests.PsyPoint" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  expect (plan.stateFieldNames == #["p_x", "p_y"])
    s!"Psy named Struct must flatten to p_x/p_y leaves, got {plan.stateFieldNames}"
  expect (plan.functions.any (·.name == "setX"))
    "Psy Point plan must carry setX"
  liftResult <| Targets.Psy.validatePlan plan
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "PsyPoint.psy") |
    throw <| IO.userError "psy: missing PsyPoint.psy"
  let psy := psyFile.contents
  expect (psy.contains "p_x" && psy.contains "p_y")
    "Psy Point source must declare p_x and p_y Felt fields"

/-- H3: fixed Array UInt64 2 flattens to slots_0/slots_1 Felt storage. -/
unsafe def testArrayStateLowered : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2
" ++
    "open ProofForgeV2.Language
" ++
    "program PsyArr where
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
    source "<psy-arr>" "Tests.PsyArr" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  expect (plan.stateFieldNames == #["slots_0", "slots_1"])
    s!"Psy Array must flatten to slots_0/slots_1, got {plan.stateFieldNames}"
  liftResult <| Targets.Psy.validatePlan plan
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "PsyArr.psy") |
    throw <| IO.userError "psy: missing PsyArr.psy"
  let psy := psyFile.contents
  expect (psy.contains "slots_0" && psy.contains "slots_1")
    "Psy Array source must declare slots_0 and slots_1"

unsafe def run : IO Unit := do
  testCounterPsySource
  testCheckedArithGuards
  testBitwiseAndShifts
  testEmitAndPureFn
  testUInt64BitNotLowered
  testFailClosedInt64BitNot
  testUInt32BitNotLowered
  testUInt32ArithFailClosed
  testUInt32CompareLowered
  testNarrowIntFailClosed
  testBytesStateFailClosed
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
  testFieldBn254FailClosed
  testGoldilocksFieldStateArith
  testOmittedTypeLet
  testNamedAggregateLowered
  testArrayStateLowered
  IO.println "Tests.Materialization.PsySourceV1: ok"

end Tests.Materialization.PsySourceV1
