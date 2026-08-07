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
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def psyU32leBytes (value : Nat) : ByteArray :=
  ByteArray.mk #[
    UInt8.ofNat (value % 256),
    UInt8.ofNat ((value / 256) % 256),
    UInt8.ofNat ((value / 65536) % 256),
    UInt8.ofNat ((value / 16777216) % 256)
  ]

private def psyU128Bytes (limbs : Array Nat) : ByteArray :=
  limbs.foldl (fun out limb => out.append (psyU32leBytes limb)) ByteArray.empty

private def psyU128RefValue
    (typeId : TypeIdV1) (limbs : Array Nat) : ReferenceValueV1 :=
  { typeId, valueBytes := psyU128Bytes limbs }

private def psyU128LogicalState (limbs : Array Nat) : LogicalStateV1 :=
  { initialized := true
    canonicalValues :=
      (ByteArray.mk #[16, 0, 0, 0]).append (psyU128Bytes limbs) }

private def psyU256Bytes (limbs : Array Nat) : ByteArray :=
  psyU128Bytes limbs

private def psyU256RefValue
    (typeId : TypeIdV1) (limbs : Array Nat) : ReferenceValueV1 :=
  { typeId, valueBytes := psyU256Bytes limbs }

private def psyU256LogicalState (limbs : Array Nat) : LogicalStateV1 :=
  { initialized := true
    canonicalValues :=
      (ByteArray.mk #[32, 0, 0, 0]).append (psyU256Bytes limbs) }

private def expectPsyReferenceReturned
    (label : String) (outcome : OutcomeV1) (post : LogicalStateV1)
    (value : Option ReferenceValueV1) : IO Unit := do
  match outcome with
  | .returned actualPost actualValue effects =>
      expect (actualPost == post) s!"{label}: Reference post-state mismatch"
      expect (actualValue == value) s!"{label}: Reference return mismatch"
      expect effects.isEmpty s!"{label}: Reference must not invent effects"
  | .reverted reason _ =>
      throw <| IO.userError s!"{label}: expected return, got revert {repr reason}"
  | .trapped fault _ =>
      throw <| IO.userError s!"{label}: expected return, got trap {repr fault}"

private def expectPsyReferenceStandardRevert
    (label : String) (outcome : OutcomeV1) (code : StandardRevertCodeV1)
    (pre : LogicalStateV1) : IO Unit := do
  match outcome with
  | .reverted (.standard actual) unchanged =>
      expect (actual == code) s!"{label}: Reference revert code mismatch"
      expect (unchanged == pre) s!"{label}: Reference revert must preserve pre-state"
  | .reverted reason _ =>
      throw <| IO.userError s!"{label}: expected {repr code}, got {repr reason}"
  | .returned _ _ _ =>
      throw <| IO.userError s!"{label}: expected revert, got return"
  | .trapped fault _ =>
      throw <| IO.userError s!"{label}: expected revert, got trap {repr fault}"

private def resolvePsyCapabilityWithProfile
    (compiled : CompiledSemanticV1) (profile? : Option CodegenProfileId) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.psy profile?
  Targets.resolveEngineeringRequirementsV1 selection compiled

private def resolvePsyCapability (compiled : CompiledSemanticV1) :
    CompileResult Targets.ResolvedEngineeringBuildV1 :=
  resolvePsyCapabilityWithProfile compiled none

private def resolvePsyVmCapability (compiled : CompiledSemanticV1) :
    CompileResult Targets.ResolvedEngineeringBuildV1 :=
  resolvePsyCapabilityWithProfile compiled (some CodegenProfileId.psyDargo010VmV1)

private def planPsy (compiled : CompiledSemanticV1) : CompileResult Targets.Psy.Plan := do
  let capability ← resolvePsyCapability compiled
  Targets.Psy.planFromCapability capability

private def buildPsy (compiled : CompiledSemanticV1) :
    CompileResult (Array OutputFile) := do
  let capability ← resolvePsyCapability compiled
  Targets.Psy.buildFromCapability capability

private def planPsyVm (compiled : CompiledSemanticV1) : CompileResult Targets.Psy.Plan := do
  let capability ← resolvePsyVmCapability compiled
  Targets.Psy.planFromCapability capability

private def buildPsyVm (compiled : CompiledSemanticV1) :
    CompileResult (Array OutputFile) := do
  let capability ← resolvePsyVmCapability compiled
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

/-- N-CONST-REF Psy leaf: exactly representable scalar constants reuse the
    literal lowering path. This pins narrow-UInt metadata (UInt32 arithmetic),
    Bool, the UInt64 `p-1` boundary, and nonnegative Int64 without adding a
    target constant declaration or a new emitter expression form. -/
unsafe def testScalarConstantsLowered : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ScalarConsts where\n" ++
    "  const U8 : UInt8 := 7\n" ++
    "  const U16 : UInt16 := 300\n" ++
    "  const U32 : UInt32 := 4000000000\n" ++
    "  const U64 : UInt64 := 18446744069414584320\n" ++
    "  const POS : Int64 := 7\n" ++
    "  const MAXI : Int64 := 9223372036854775807\n" ++
    "  const FLAG : Bool := true\n" ++
    "  entry get8() : UInt8 do\n" ++
    "    return U8\n" ++
    "  entry get16() : UInt16 do\n" ++
    "    return U16\n" ++
    "  entry add32() : UInt32 do\n" ++
    "    return U32 + 1\n" ++
    "  entry get64() : UInt64 do\n" ++
    "    return U64\n" ++
    "  entry getPos() : Int64 do\n" ++
    "    return POS\n" ++
    "  entry getMax() : Int64 do\n" ++
    "    return MAXI\n" ++
    "  entry getFlag() : Bool do\n" ++
    "    return FLAG\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-const>" "Tests.PsyScalarConsts" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  let bodyOf (name : String) : IO (Array Targets.Psy.Statement) := do
    let some fn := plan.functions.find? (·.name == name) |
      throw <| IO.userError s!"psy const: missing function '{name}'"
    pure fn.body
  expect ((← bodyOf "get8") == #[.returnValue (.literal 7)])
    "UInt8 constant must lower to the existing scalar literal Plan form"
  expect ((← bodyOf "get16") == #[.returnValue (.literal 300)])
    "UInt16 constant must lower to the existing scalar literal Plan form"
  expect ((← bodyOf "add32") == #[
      .returnValue (.narrowCheckedAdd 32 (.literal 4000000000) (.literal 1))])
    "UInt32 constant must retain narrow-width metadata through arithmetic"
  expect ((← bodyOf "get64") == #[
      .returnValue (.literal 18446744069414584320)])
    "UInt64 p-1 constant must remain exact on the Goldilocks Felt surface"
  expect ((← bodyOf "getPos") == #[.returnValue (.literal 7)])
    "nonnegative Int64 constant must lower to the existing scalar literal Plan form"
  expect ((← bodyOf "getMax") == #[
      .returnValue (.literal 9223372036854775807)])
    "Int64.max constant must remain exactly representable as a Felt literal"
  expect ((← bodyOf "getFlag") == #[.returnValue (.boolLiteral true)])
    "Bool constant must lower to the existing Bool literal Plan form"
  liftResult <| Targets.Psy.validatePlan plan
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "ScalarConsts.psy") |
    throw <| IO.userError "psy const: missing ScalarConsts.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub fn get8() -> Felt" &&
      psy.contains "pub fn get16() -> Felt" &&
      psy.contains "pub fn add32() -> Felt" &&
      psy.contains "pub fn get64() -> Felt" &&
      psy.contains "pub fn getPos() -> Felt" &&
      psy.contains "pub fn getMax() -> Felt")
    "integer constants must remain on the existing Felt ABI surface"
  expect (psy.contains "u32 add overflow")
    "UInt32 constant arithmetic must emit the existing width guard"
  expect (psy.contains "pub fn getFlag() -> bool" && psy.contains "return true;")
    "Bool constant must emit on the existing bool surface"

/-- Constants that cannot be represented by the existing Psy Felt scalar
    convention must fail closed instead of being silently reduced modulo p. -/
unsafe def testScalarConstantsRepresentabilityFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  for (name, value) in #[
      ("NegOne", "-1"),
      ("NegSeven", "-7"),
      ("NegMin", "-9223372036854775808")] do
    let source :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      s!"program {name} where\n" ++
      s!"  const BAD : Int64 := {value}\n" ++
      "  entry get() : Int64 do\n" ++
      "    return BAD\n"
    let parsed ← liftResult (← session.selectProgramV1
      source s!"<psy-const-{name}>" s!"Tests.Psy{name}" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
    match planPsy compiled with
    | .error (.planInvariant .psy message) =>
        expect (message.contains "negative Int64 constants")
          s!"{name}: negative Int64 constant must cite the exact Psy boundary, got {message}"
    | .error error =>
        throw <| IO.userError s!"{name}: expected Psy plan invariant, got {error.render}"
    | .ok _ =>
        throw <| IO.userError s!"{name}: negative Int64 constant must fail closed"
  let overSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ConstAtModulus where\n" ++
    "  const BAD : UInt64 := 18446744069414584321\n" ++
    "  entry get() : UInt64 do\n" ++
    "    return BAD\n"
  let overParsed ← liftResult (← session.selectProgramV1
    overSource "<psy-const-at-modulus>" "Tests.PsyConstAtModulus" none)
  let overCompiled ← liftResult <| Compiler.compileValidatedSourceV1 overParsed
  match planPsy overCompiled with
  | .error (.planInvariant .psy message) =>
      expect (message.contains "below the Goldilocks modulus")
        s!"UInt64 p constant must cite the Felt representability boundary, got {message}"
  | .error error =>
      throw <| IO.userError s!"UInt64 p constant: expected Psy plan invariant, got {error.render}"
  | .ok _ =>
      throw <| IO.userError "UInt64 constant equal to Goldilocks p must fail closed"

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

/-- T8: bitNot (~) on UInt32 lowers to Felt-carried `narrowBitNot 32` =
    `x ^ 4294967295` (Felt mask, not native u32). UInt64 uses checkedBitNot. -/
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
  expect (flip.body == #[.returnValue (.narrowBitNot 32 (.param 0))])
    s!"UInt32 bitNot must lower to Plan narrowBitNot 32 (param0), got {repr flip.body}"
  expect (flip.params.any (·.isU32))
    "flip32: UInt32 param must be tagged uintWidth=32 in the Plan"
  expect (flip.resultIsU32)
    "flip32: UInt32 result must be tagged resultUintWidth=32 in the Plan"
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Flip32.psy") |
    throw <| IO.userError "psy: missing Flip32.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub fn flip(p0: Felt) -> Felt")
    "UInt32 bitNot fn must render Felt param and result (Felt-carried narrow)"
  expect (psy.contains "u32 param out of range")
    "UInt32 param must get an entry range assert"
  expect (psy.contains "4294967295")
    "UInt32 bitNot must emit the 2^32−1 Felt mask"
  expect (psy.contains " ^ ")
    "UInt32 bitNot must emit XOR with the mask"
  expect (!psy.contains "4294967295u32")
    "UInt32 bitNot must not emit the native-u32 mask suffix"
  expect (!psy.contains "18446744073709551615")
    "UInt32 bitNot must not emit the illegal 2^64−1 mask"

/-- T8 multi-width: UInt32 add is Felt-carried with an explicit width guard
    (`result < 2^32`). Native dargo u32 ops stay unused (unfaithful to
    Reference); width bound alone is enough because (2^32−1)^2 < Goldilocks p. -/
unsafe def testUInt32ArithWidthGuard : IO Unit := do
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
  let plan ← liftResult <| planPsy compiled
  let some add := plan.functions.find? (·.name == "add") |
    throw <| IO.userError "add32: missing add"
  expect (add.body == #[.returnValue (.narrowCheckedAdd 32 (.param 0) (.param 1))])
    s!"UInt32 add must lower to narrowCheckedAdd 32, got {repr add.body}"
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "Add32.psy") |
    throw <| IO.userError "psy: missing Add32.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub fn add(p0: Felt, p1: Felt) -> Felt")
    "UInt32 add must render Felt params/result"
  expect (psy.contains "4294967296")
    "UInt32 add must emit 2^32 width bound"
  expect (psy.contains "u32 add overflow")
    "UInt32 add must emit the width-overflow assert message"
  expect (psy.contains "u32 param out of range")
    "UInt32 params must be range-checked at entry"

/-- T8 multi-width: UInt8 state/param/body with width guards + bitNot mask. -/
unsafe def testUInt8CounterMultiWidth : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program U8Ctr where\n" ++
    "  state count : UInt8\n" ++
    "  init(seed : UInt8) do\n" ++
    "    count := seed\n" ++
    "  entry increment(delta : UInt8) : UInt8 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  entry flip() : UInt8 do\n" ++
    "    return ~count\n" ++
    "  entry shift(v : UInt8) : UInt8 do\n" ++
    "    return v << 1\n" ++
    "  view get() : UInt8 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-u8ctr>" "Tests.PsyU8Ctr" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  expect (plan.stateFieldNames == #["count"])
    "U8Ctr must carry count state"
  let some inc := plan.functions.find? (·.name == "increment") |
    throw <| IO.userError "U8Ctr: missing increment"
  expect (inc.params.any (fun p => p.uintWidth == 8))
    "increment delta must be uintWidth=8"
  expect (inc.resultUintWidth == 8)
    "increment result must be uintWidth=8"
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "U8Ctr.psy") |
    throw <| IO.userError "psy: missing U8Ctr.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub count: Felt,")
    "UInt8 state must render as Felt storage"
  expect (psy.contains "u8 add overflow")
    "UInt8 add must emit width overflow guard"
  expect (psy.contains "256")
    "UInt8 width bound must be 2^8=256"
  expect (psy.contains "255")
    "UInt8 bitNot must emit the 2^8−1 mask"
  expect (psy.contains "u8 param out of range")
    "UInt8 params must be range-checked"
  expect (psy.contains "invalidShift: count >= 8")
    "UInt8 shift must guard count < 8"
  expect (psy.contains "pub fn increment(p0: Felt) -> Felt")
    "UInt8 entry must render Felt ABI"
  expect (psy.contains "pub fn get() -> Felt")
    "UInt8 view must render Felt result"

/-- Fail closed: UInt128 stays outside the Psy multi-width pilot. -/
unsafe def testUInt128FailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program W128 where\n" ++
    "  entry add(a : UInt128, b : UInt128) : UInt128 do\n" ++
    "    return a + b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-u128>" "Tests.PsyU128" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planPsy compiled with
  | .error (.planInvariant .psy msg) =>
      expect (msg.contains "width" || msg.contains "UInt" || msg.contains "128")
        s!"UInt128 must fail closed at Psy type-closure, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .psy, got {e.render}"
  | .ok _ => throw <| IO.userError "UInt128 must fail closed at Psy plan"

/-- Explicit locked-dargo VM profile: UInt128 is four little-endian UInt32
    Felt limbs across state, params, checked add/sub/mul/div/mod, bitwise,
    shift (UInt32 count), comparisons, and entry/view returns. The historical
    default profile remains fail closed. -/
unsafe def testUInt128VmProfileLowered : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program WideCounter where\n" ++
    "  state total : UInt128\n" ++
    "  init(initial : UInt128) do\n" ++
    "    total := initial\n" ++
    "  entry add(delta : UInt128) : UInt128 do\n" ++
    "    total := total + delta\n" ++
    "    return total\n" ++
    "  entry subtract(delta : UInt128) : UInt128 do\n" ++
    "    total := total - delta\n" ++
    "    return total\n" ++
    "  entry multiply(factor : UInt128) : UInt128 do\n" ++
    "    total := total * factor\n" ++
    "    return total\n" ++
    "  entry divide(divisor : UInt128) : UInt128 do\n" ++
    "    total := total / divisor\n" ++
    "    return total\n" ++
    "  entry remainder(divisor : UInt128) : UInt128 do\n" ++
    "    total := total % divisor\n" ++
    "    return total\n" ++
    "  entry bitand(mask : UInt128) : UInt128 do\n" ++
    "    total := total & mask\n" ++
    "    return total\n" ++
    "  entry bitor(mask : UInt128) : UInt128 do\n" ++
    "    total := total | mask\n" ++
    "    return total\n" ++
    "  entry bitxor(mask : UInt128) : UInt128 do\n" ++
    "    total := total ^ mask\n" ++
    "    return total\n" ++
    "  entry shiftLeft(count : UInt32) : UInt128 do\n" ++
    "    total := total << count\n" ++
    "    return total\n" ++
    "  entry shiftRight(count : UInt32) : UInt128 do\n" ++
    "    total := total >> count\n" ++
    "    return total\n" ++
    "  view leq(bound : UInt128) : Bool do\n" ++
    "    return total <= bound\n" ++
    "  view get() : UInt128 do\n" ++
    "    return total\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-u128-vm>" "Tests.PsyU128Vm" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed

  -- Cross-layer differential pin: the exact retained SemanticProgramV1 used by
  -- the Psy Plan must produce the same logical UInt128 carry/borrow/compare and
  -- rollback observations in the target-neutral Reference machine. The Psy ABI
  -- below is four UInt32 limbs; Reference remains one canonical 16-byte value.
  let carrier := CompiledSemanticV1.semanticV1Of compiled
  let data ← match validateSemanticProgramV1 carrier with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"UInt128 VM Reference validate failed: {repr error}"
  let admitted ← match admitReferenceProgramSliceV1 carrier with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"UInt128 VM Reference admission failed: {repr error}"
  let some u128TypeId := data.types.findSome? (fun decl =>
      match decl.name, decl.shape with
      | none, .uint 128 => some decl.id
      | _, _ => none) |
    throw <| IO.userError "UInt128 VM semantic is missing anonymous UInt128"
  let some boolTypeId := data.types.findSome? (fun decl =>
      match decl.name, decl.shape with
      | none, .bool => some decl.id
      | _, _ => none) |
    throw <| IO.userError "UInt128 VM semantic is missing anonymous Bool"
  let some initId := data.callables.findSome? (fun callable =>
      if callable.kind == .initializer then some callable.id else none) |
    throw <| IO.userError "UInt128 VM semantic is missing initializer"
  let callableNamed (name : String) : Option CallableIdV1 :=
    data.callables.findSome? fun callable =>
      if callable.name == some name then some callable.id else none
  let some addId := callableNamed "add" |
    throw <| IO.userError "UInt128 VM semantic is missing add"
  let some subtractId := callableNamed "subtract" |
    throw <| IO.userError "UInt128 VM semantic is missing subtract"
  let some multiplyId := callableNamed "multiply" |
    throw <| IO.userError "UInt128 VM semantic is missing multiply"
  let some divideId := callableNamed "divide" |
    throw <| IO.userError "UInt128 VM semantic is missing divide"
  let some remainderId := callableNamed "remainder" |
    throw <| IO.userError "UInt128 VM semantic is missing remainder"
  let some bitandId := callableNamed "bitand" |
    throw <| IO.userError "UInt128 VM semantic is missing bitand"
  let some bitorId := callableNamed "bitor" |
    throw <| IO.userError "UInt128 VM semantic is missing bitor"
  let some bitxorId := callableNamed "bitxor" |
    throw <| IO.userError "UInt128 VM semantic is missing bitxor"
  let some shiftLeftId := callableNamed "shiftLeft" |
    throw <| IO.userError "UInt128 VM semantic is missing shiftLeft"
  let some shiftRightId := callableNamed "shiftRight" |
    throw <| IO.userError "UInt128 VM semantic is missing shiftRight"
  let some leqId := callableNamed "leq" |
    throw <| IO.userError "UInt128 VM semantic is missing leq"
  let some getId := callableNamed "get" |
    throw <| IO.userError "UInt128 VM semantic is missing get"
  let invoke (callableId : CallableIdV1) (args : Array ReferenceValueV1) : InvocationV1 :=
    { callableId, args, context := #[] }
  let noResponses : ExternalResponsesV1 := #[]
  let zeroLimbs : Array Nat := #[0, 0, 0, 0]
  let oneLimbs : Array Nat := #[1, 0, 0, 0]
  let twoLimbs : Array Nat := #[2, 0, 0, 0]
  let lowMaxLimbs : Array Nat := #[4294967295, 0, 0, 0]
  let carriedLimbs : Array Nat := #[0, 1, 0, 0]
  let squaredLowMaxLimbs : Array Nat := #[1, 4294967294, 0, 0]
  let maxLimbs : Array Nat :=
    #[4294967295, 4294967295, 4294967295, 4294967295]
  let divDividendLimbs : Array Nat :=
    #[2309737967, 19088743, 1985229328, 4275878552]
  let divDivisorLimbs : Array Nat :=
    #[4275878553, 1, 305419896, 0]
  let divQuotientLimbs : Array Nat := #[119, 14, 0, 0]
  let divRemainderLimbs : Array Nat := #[286331088, 286330908, 44, 0]
  -- 0x0000000100000000 & 0x00000000ffffffff = 0
  -- 0x0000000100000000 | 0x00000000ffffffff = 0x00000001ffffffff
  -- 0x0000000100000000 ^ 0x00000000ffffffff = 0x00000001ffffffff
  -- 0x00000000ffffffff << 1 = 0x00000001fffffffe
  -- 0x0000000100000000 >> 1 = 0x0000000080000000
  let maskLimbs : Array Nat := #[4294967295, 0, 0, 0]
  let orXorLimbs : Array Nat := #[4294967295, 1, 0, 0]
  let shlOneLimbs : Array Nat := #[4294967294, 1, 0, 0]
  let shrOneLimbs : Array Nat := #[2147483648, 0, 0, 0]
  let initial ← match initialLogicalStateV1 carrier with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"UInt128 VM initial state failed: {repr error}"
  let lowMaxValue := psyU128RefValue u128TypeId lowMaxLimbs
  let oneValue := psyU128RefValue u128TypeId oneLimbs
  let twoValue := psyU128RefValue u128TypeId twoLimbs
  let carriedValue := psyU128RefValue u128TypeId carriedLimbs
  let squaredLowMaxValue := psyU128RefValue u128TypeId squaredLowMaxLimbs
  let divDivisorValue := psyU128RefValue u128TypeId divDivisorLimbs
  let zeroValue := psyU128RefValue u128TypeId zeroLimbs
  let divQuotientValue := psyU128RefValue u128TypeId divQuotientLimbs
  let divRemainderValue := psyU128RefValue u128TypeId divRemainderLimbs
  let maskValue := psyU128RefValue u128TypeId maskLimbs
  let orXorValue := psyU128RefValue u128TypeId orXorLimbs
  let shlOneValue := psyU128RefValue u128TypeId shlOneLimbs
  let shrOneValue := psyU128RefValue u128TypeId shrOneLimbs
  let some u32TypeId := data.types.findSome? (fun decl =>
      match decl.name, decl.shape with
      | none, .uint 32 => some decl.id
      | _, _ => none) |
    throw <| IO.userError "UInt128 VM semantic is missing anonymous UInt32"
  let countOneValue : ReferenceValueV1 :=
    { typeId := u32TypeId, valueBytes := ByteArray.mk #[1, 0, 0, 0] }
  let lowMaxState := psyU128LogicalState lowMaxLimbs
  let carriedState := psyU128LogicalState carriedLimbs
  let squaredLowMaxState := psyU128LogicalState squaredLowMaxLimbs
  let divDividendState := psyU128LogicalState divDividendLimbs
  let divQuotientState := psyU128LogicalState divQuotientLimbs
  let divRemainderState := psyU128LogicalState divRemainderLimbs
  let orXorState := psyU128LogicalState orXorLimbs
  let shlOneState := psyU128LogicalState shlOneLimbs
  let shrOneState := psyU128LogicalState shrOneLimbs
  expectPsyReferenceReturned "psy-u128-ref-init"
    (stepReferenceSliceV1 admitted initial (invoke initId #[lowMaxValue]) noResponses)
    lowMaxState none
  expectPsyReferenceReturned "psy-u128-ref-carry"
    (stepReferenceSliceV1 admitted lowMaxState (invoke addId #[oneValue]) noResponses)
    carriedState (some carriedValue)
  expectPsyReferenceReturned "psy-u128-ref-leq"
    (stepReferenceSliceV1 admitted carriedState (invoke leqId #[carriedValue]) noResponses)
    carriedState (some { typeId := boolTypeId, valueBytes := ByteArray.mk #[1] })
  expectPsyReferenceReturned "psy-u128-ref-get"
    (stepReferenceSliceV1 admitted carriedState (invoke getId #[]) noResponses)
    carriedState (some carriedValue)
  expectPsyReferenceReturned "psy-u128-ref-borrow"
    (stepReferenceSliceV1 admitted carriedState (invoke subtractId #[oneValue]) noResponses)
    lowMaxState (some lowMaxValue)
  expectPsyReferenceReturned "psy-u128-ref-mul-lowmax"
    (stepReferenceSliceV1 admitted lowMaxState
      (invoke multiplyId #[lowMaxValue]) noResponses)
    squaredLowMaxState (some squaredLowMaxValue)
  expectPsyReferenceReturned "psy-u128-ref-div-mixed"
    (stepReferenceSliceV1 admitted divDividendState
      (invoke divideId #[divDivisorValue]) noResponses)
    divQuotientState (some divQuotientValue)
  expectPsyReferenceReturned "psy-u128-ref-mod-mixed"
    (stepReferenceSliceV1 admitted divDividendState
      (invoke remainderId #[divDivisorValue]) noResponses)
    divRemainderState (some divRemainderValue)
  expectPsyReferenceStandardRevert "psy-u128-ref-div-zero"
    (stepReferenceSliceV1 admitted divDividendState
      (invoke divideId #[zeroValue]) noResponses)
    .divisionByZero divDividendState
  expectPsyReferenceStandardRevert "psy-u128-ref-mod-zero"
    (stepReferenceSliceV1 admitted divDividendState
      (invoke remainderId #[zeroValue]) noResponses)
    .divisionByZero divDividendState
  expectPsyReferenceReturned "psy-u128-ref-bitand"
    (stepReferenceSliceV1 admitted carriedState
      (invoke bitandId #[maskValue]) noResponses)
    (psyU128LogicalState zeroLimbs) (some zeroValue)
  expectPsyReferenceReturned "psy-u128-ref-bitor"
    (stepReferenceSliceV1 admitted carriedState
      (invoke bitorId #[maskValue]) noResponses)
    orXorState (some orXorValue)
  expectPsyReferenceReturned "psy-u128-ref-bitxor"
    (stepReferenceSliceV1 admitted carriedState
      (invoke bitxorId #[maskValue]) noResponses)
    orXorState (some orXorValue)
  expectPsyReferenceReturned "psy-u128-ref-shl1"
    (stepReferenceSliceV1 admitted lowMaxState
      (invoke shiftLeftId #[countOneValue]) noResponses)
    shlOneState (some shlOneValue)
  expectPsyReferenceReturned "psy-u128-ref-shr1"
    (stepReferenceSliceV1 admitted carriedState
      (invoke shiftRightId #[countOneValue]) noResponses)
    shrOneState (some shrOneValue)
  let maxState := psyU128LogicalState maxLimbs
  expectPsyReferenceStandardRevert "psy-u128-ref-add-overflow"
    (stepReferenceSliceV1 admitted maxState (invoke addId #[oneValue]) noResponses)
    .arithmeticOverflow maxState
  expectPsyReferenceStandardRevert "psy-u128-ref-mul-overflow"
    (stepReferenceSliceV1 admitted maxState (invoke multiplyId #[twoValue]) noResponses)
    .arithmeticOverflow maxState
  expectPsyReferenceStandardRevert "psy-u128-ref-shl-overflow"
    (stepReferenceSliceV1 admitted maxState
      (invoke shiftLeftId #[countOneValue]) noResponses)
    .arithmeticOverflow maxState
  let zeroState := psyU128LogicalState zeroLimbs
  expectPsyReferenceStandardRevert "psy-u128-ref-underflow"
    (stepReferenceSliceV1 admitted zeroState (invoke subtractId #[oneValue]) noResponses)
    .arithmeticUnderflow zeroState

  let plan ← liftResult <| planPsyVm compiled
  expect (plan.profileMode == .dargo010Vm)
    "UInt128 plan must retain the explicit dargo 0.1.0 VM profile"
  expect (plan.stateFieldNames ==
      #["total_0", "total_1", "total_2", "total_3"])
    "UInt128 state must flatten to four little-endian UInt32 Felt limbs"
  let functionNamed (name : String) := plan.functions.find? (·.name == name)
  let some initFn := functionNamed "initialize" |
    throw <| IO.userError "UInt128 VM plan is missing initialize"
  let some add := functionNamed "add" |
    throw <| IO.userError "UInt128 VM plan is missing add"
  let some subtract := functionNamed "subtract" |
    throw <| IO.userError "UInt128 VM plan is missing subtract"
  let some multiply := functionNamed "multiply" |
    throw <| IO.userError "UInt128 VM plan is missing multiply"
  let some divide := functionNamed "divide" |
    throw <| IO.userError "UInt128 VM plan is missing divide"
  let some remainder := functionNamed "remainder" |
    throw <| IO.userError "UInt128 VM plan is missing remainder"
  let some bitand := functionNamed "bitand" |
    throw <| IO.userError "UInt128 VM plan is missing bitand"
  let some bitor := functionNamed "bitor" |
    throw <| IO.userError "UInt128 VM plan is missing bitor"
  let some bitxor := functionNamed "bitxor" |
    throw <| IO.userError "UInt128 VM plan is missing bitxor"
  let some shiftLeft := functionNamed "shiftLeft" |
    throw <| IO.userError "UInt128 VM plan is missing shiftLeft"
  let some shiftRight := functionNamed "shiftRight" |
    throw <| IO.userError "UInt128 VM plan is missing shiftRight"
  let some leq := functionNamed "leq" |
    throw <| IO.userError "UInt128 VM plan is missing leq"
  let some get := functionNamed "get" |
    throw <| IO.userError "UInt128 VM plan is missing get"
  for fn in #[initFn, add, subtract, multiply, divide, remainder, bitand, bitor, bitxor, leq] do
    expect (fn.params.size == 4 && fn.params.all (·.uintWidth == 32))
      s!"{fn.name}: each logical UInt128 parameter must expand to four range-checked UInt32 limbs"
  for fn in #[shiftLeft, shiftRight] do
    expect (fn.params.size == 1 && fn.params[0]!.uintWidth == 32)
      s!"{fn.name}: UInt128 shift count must be one physical UInt32 limb"
  let expectWideResult (fn : Targets.Psy.PlanFunction) : IO Unit :=
    match fn.resultKind with
    | .aggregate leaves =>
        expect (fn.resultUintWidth == 128 && leaves.size == 4 &&
            leaves.all (fun leaf => !leaf.isInt && leaf.byteWidth == 4))
          s!"{fn.name}: UInt128 result must be four unsigned 4-byte limbs"
    | other =>
        throw <| IO.userError s!"{fn.name}: expected UInt128 aggregate result, got {repr other}"
  expectWideResult add
  expectWideResult subtract
  expectWideResult multiply
  expectWideResult divide
  expectWideResult remainder
  expectWideResult bitand
  expectWideResult bitor
  expectWideResult bitxor
  expectWideResult shiftLeft
  expectWideResult shiftRight
  expectWideResult get
  expect (leq.resultIsBool && leq.resultKind == .bool)
    "UInt128 comparison must produce the existing scalar Bool result"
  expect (add.body.any fun
      | .assertWithMessage _ message => message == "u128 add overflow"
      | _ => false)
    "UInt128 add must carry a stable final-carry overflow guard"
  expect (subtract.body.any fun
      | .assertWithMessage _ message => message == "u128 sub underflow"
      | _ => false)
    "UInt128 sub must carry a stable final-borrow underflow guard"
  expect (multiply.body.any fun
      | .bindWideUintMul 128 _ lhs rhs => lhs.size == 4 && rhs.size == 4
      | _ => false)
    "UInt128 mul must bind one exact 8×UInt16 schoolbook multiplication"
  expect (divide.body.any fun
      | .bindWideUintDivMod .quotient 128 _ lhs rhs => lhs.size == 4 && rhs.size == 4
      | _ => false)
    "UInt128 div must bind one exact quotient-producing restoring divider"
  expect (remainder.body.any fun
      | .bindWideUintDivMod .remainder 128 _ lhs rhs => lhs.size == 4 && rhs.size == 4
      | _ => false)
    "UInt128 mod must bind one exact remainder-producing restoring divider"
  expect (shiftLeft.body.any fun
      | .bindWideUintShift .shl 128 _ value _ => value.size == 4
      | _ => false)
    "UInt128 shl must bind one exact fixed-step shift binding"
  expect (shiftRight.body.any fun
      | .bindWideUintShift .shr 128 _ value _ => value.size == 4
      | _ => false)
    "UInt128 shr must bind one exact fixed-step shift binding"
  expect (add.body.any fun
      | .storeAggregate fields values => fields.size == 4 && values.size == 4
      | _ => false)
    "UInt128 add must use one atomic four-limb state update"
  expect (add.body.any fun
      | .returnAggregate leaves _ => leaves.size == 4
      | _ => false)
    "UInt128 add must return all four limbs"
  expect (leq.body.any fun
      | .returnValue _ => true
      | _ => false)
    "UInt128 comparison must return a scalar Bool expression"
  liftResult <| Targets.Psy.validatePlan plan
  let noMulBindingBody := multiply.body.filter fun
    | .bindWideUintMul .. => false
    | _ => true
  let badMultiply := { multiply with body := noMulBindingBody }
  let badPlan := { plan with
    functions := plan.functions.set! multiply.index badMultiply }
  match Targets.Psy.validatePlan badPlan with
  | .error (.planInvariant .psy message) =>
      expect (message.contains "used before its binding")
        s!"UInt128 mul result without its binding must fail closed, got: {message}"
  | .error error =>
      throw <| IO.userError s!"expected Psy planInvariant for missing wide mul binding, got {error.render}"
  | .ok _ =>
      throw <| IO.userError "UInt128 mul result without its binding must fail plan validation"
  let noDivBindingBody := divide.body.filter fun
    | .bindWideUintDivMod .. => false
    | _ => true
  let badDivide := { divide with body := noDivBindingBody }
  let badDivPlan := { plan with
    functions := plan.functions.set! divide.index badDivide }
  match Targets.Psy.validatePlan badDivPlan with
  | .error (.planInvariant .psy message) =>
      expect (message.contains "used before its binding" || message.contains "mismatched")
        s!"UInt128 div result without its binding must fail closed, got: {message}"
  | .error error =>
      throw <| IO.userError s!"expected Psy planInvariant for missing wide div binding, got {error.render}"
  | .ok _ =>
      throw <| IO.userError "UInt128 div result without its binding must fail plan validation"
  let files ← liftResult <| buildPsyVm compiled
  let some psyFile := files.find? (·.path == "WideCounter.psy") |
    throw <| IO.userError "psy: missing WideCounter.psy"
  let psy := psyFile.contents
  expect (psy.contains "dargo-v0.1.0-vm")
    "VM profile source header must identify the locked dargo lane"
  expect (psy.contains "pub total_0: Felt," &&
      psy.contains "pub total_1: Felt," &&
      psy.contains "pub total_2: Felt," &&
      psy.contains "pub total_3: Felt,")
    "UInt128 state must render as four Felt storage fields"
  expect (psy.contains
      "pub fn add(p0: Felt, p1: Felt, p2: Felt, p3: Felt) -> [Felt; 4]")
    "UInt128 entry ABI must expand one parameter and return four Felt limbs"
  expect (psy.contains "u32 param out of range")
    "every physical UInt128 input limb must use the UInt32 range guard"
  expect (psy.contains "u128 add overflow" &&
      psy.contains "u128 sub underflow" &&
      psy.contains "u128 mul overflow" &&
      psy.contains "u128 div by zero" &&
      psy.contains "u128 mod by zero" &&
      psy.contains "u128 shl overflow" &&
      psy.contains "invalidShift: count >= 128")
    "UInt128 checked arithmetic/shift messages must reach emitted Psy source"
  expect (psy.contains "0u32..32u32" &&
      psy.contains "u128 div internal high borrow" &&
      psy.contains "u128 div internal remainder high" &&
      psy.contains "u128 div internal quotient overflow")
    "UInt128 div/mod must emit the fixed restoring loops and internal guards"
  expect (psy.contains "0u32..128u32")
    "UInt128 shift must emit the fixed 128-step bit walk"
  expect (psy.contains " & 65535" && psy.contains " >> 16")
    "UInt128 mul must split and normalize with integer bit operations"
  expect (!psy.contains "/ 65536" && !psy.contains "% 65536")
    "UInt128 mul must not use Felt field division/modulo for integer splitting"
  expect (psy.contains "return [")
    "UInt128 return must use the honest fixed-length Felt array ABI"
  expect (psy.contains "if ")
    "UInt128 carry/borrow materialization must use Psy expression-form select"

/-- The explicit VM profile lowers exact UInt128 div/mod through one
    target-bound four-loop restoring divider per Semantic operation. -/
unsafe def testUInt128VmDivModLowered : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program WideDivMod where\n" ++
    "  entry div(a : UInt128, b : UInt128) : UInt128 do\n" ++
    "    return a / b\n" ++
    "  entry rem(a : UInt128, b : UInt128) : UInt128 do\n" ++
    "    return a % b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-u128-divmod>" "Tests.PsyU128DivMod" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsyVm compiled
  let some divFn := plan.functions.find? (·.name == "div") |
    throw <| IO.userError "UInt128 div/mod plan is missing div"
  let some remFn := plan.functions.find? (·.name == "rem") |
    throw <| IO.userError "UInt128 div/mod plan is missing rem"
  expect (divFn.body.any fun
      | .bindWideUintDivMod .quotient 128 _ lhs rhs => lhs.size == 4 && rhs.size == 4
      | _ => false)
    "UInt128 div must bind one exact quotient-producing restoring divider"
  expect (remFn.body.any fun
      | .bindWideUintDivMod .remainder 128 _ lhs rhs => lhs.size == 4 && rhs.size == 4
      | _ => false)
    "UInt128 mod must bind one exact remainder-producing restoring divider"
  liftResult <| Targets.Psy.validatePlan plan
  let files ← liftResult <| buildPsyVm compiled
  let some psyFile := files.find? (·.path == "WideDivMod.psy") |
    throw <| IO.userError "psy: missing WideDivMod.psy"
  let psy := psyFile.contents
  expect (psy.contains "0u32..32u32")
    "UInt128 div/mod must emit fixed 32-step Psy loops"
  expect (psy.contains "u128 div by zero" && psy.contains "u128 mod by zero")
    "UInt128 div/mod must emit operation-specific zero-divisor messages"
  expect (psy.contains "u128 div internal high borrow" &&
      psy.contains "u128 div internal remainder high" &&
      psy.contains "u128 div internal quotient overflow")
    "UInt128 div/mod must retain target-internal restoring invariants"
  expect (!psy.contains " / " && !psy.contains " % ")
    "UInt128 div/mod must not use Psy Felt field division or remainder"

/-- The first restoring-divider profile caps one div/mod binding per function;
    larger compositions remain explicitly fail closed until measured. -/
unsafe def testUInt128VmDivModResourceFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program WideDivBudget where\n" ++
    "  entry twice(a : UInt128, b : UInt128, c : UInt128) : UInt128 do\n" ++
    "    let q : UInt128 := a / b\n" ++
    "    return q % c\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-u128-div-budget>" "Tests.PsyU128DivBudget" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planPsyVm compiled with
  | .error (.planInvariant .psy message) =>
      expect (message.contains "div/mod binding limit" && message.contains "1")
        s!"UInt128 div/mod resource denial must cite the exact cap, got: {message}"
  | .error error =>
      throw <| IO.userError s!"expected Psy planInvariant for UInt128 div/mod budget, got {error.render}"
  | .ok _ =>
      throw <| IO.userError "two UInt128 div/mod bindings in one function must remain fail closed"

/-- Explicit VM profile: UInt256 is eight little-endian UInt32 Felt limbs. -/
unsafe def testUInt256VmProfileLowered : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Wide256 where\n" ++
    "  state total : UInt256\n" ++
    "  init(initial : UInt256) do\n" ++
    "    total := initial\n" ++
    "  entry add(delta : UInt256) : UInt256 do\n" ++
    "    total := total + delta\n" ++
    "    return total\n" ++
    "  entry subtract(delta : UInt256) : UInt256 do\n" ++
    "    total := total - delta\n" ++
    "    return total\n" ++
    "  entry multiply(factor : UInt256) : UInt256 do\n" ++
    "    total := total * factor\n" ++
    "    return total\n" ++
    "  entry bitand(mask : UInt256) : UInt256 do\n" ++
    "    total := total & mask\n" ++
    "    return total\n" ++
    "  entry shiftLeft(count : UInt32) : UInt256 do\n" ++
    "    total := total << count\n" ++
    "    return total\n" ++
    "  view get() : UInt256 do\n" ++
    "    return total\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-u256-vm>" "Tests.PsyU256Vm" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let carrier := CompiledSemanticV1.semanticV1Of compiled
  let data ← match validateSemanticProgramV1 carrier with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"UInt256 VM Reference validate failed: {repr error}"
  let admitted ← match admitReferenceProgramSliceV1 carrier with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"UInt256 VM Reference admission failed: {repr error}"
  let some u256TypeId := data.types.findSome? (fun decl =>
      match decl.name, decl.shape with
      | none, .uint 256 => some decl.id
      | _, _ => none) |
    throw <| IO.userError "UInt256 VM semantic is missing anonymous UInt256"
  let some u32TypeId := data.types.findSome? (fun decl =>
      match decl.name, decl.shape with
      | none, .uint 32 => some decl.id
      | _, _ => none) |
    throw <| IO.userError "UInt256 VM semantic is missing anonymous UInt32"
  let callableNamed (name : String) : Option CallableIdV1 :=
    data.callables.findSome? fun callable =>
      if callable.name == some name then some callable.id else none
  let some initId := data.callables.findSome? (fun c =>
      if c.kind == .initializer then some c.id else none) |
    throw <| IO.userError "UInt256 VM semantic is missing initializer"
  let some addId := callableNamed "add" |
    throw <| IO.userError "UInt256 VM semantic is missing add"
  let some multiplyId := callableNamed "multiply" |
    throw <| IO.userError "UInt256 VM semantic is missing multiply"
  let some bitandId := callableNamed "bitand" |
    throw <| IO.userError "UInt256 VM semantic is missing bitand"
  let some shiftLeftId := callableNamed "shiftLeft" |
    throw <| IO.userError "UInt256 VM semantic is missing shiftLeft"
  let invoke (callableId : CallableIdV1) (args : Array ReferenceValueV1) : InvocationV1 :=
    { callableId, args, context := #[] }
  let noResponses : ExternalResponsesV1 := #[]
  let zeroLimbs : Array Nat := #[0, 0, 0, 0, 0, 0, 0, 0]
  let oneLimbs : Array Nat := #[1, 0, 0, 0, 0, 0, 0, 0]
  let lowMaxLimbs : Array Nat := #[4294967295, 0, 0, 0, 0, 0, 0, 0]
  let carriedLimbs : Array Nat := #[0, 1, 0, 0, 0, 0, 0, 0]
  let squaredLowMaxLimbs : Array Nat := #[1, 4294967294, 0, 0, 0, 0, 0, 0]
  let maskLimbs : Array Nat := #[4294967295, 0, 0, 0, 0, 0, 0, 0]
  let shlOneLimbs : Array Nat := #[4294967294, 1, 0, 0, 0, 0, 0, 0]
  let initial ← match initialLogicalStateV1 carrier with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"UInt256 VM initial state failed: {repr error}"
  let lowMaxValue := psyU256RefValue u256TypeId lowMaxLimbs
  let oneValue := psyU256RefValue u256TypeId oneLimbs
  let carriedValue := psyU256RefValue u256TypeId carriedLimbs
  let squaredLowMaxValue := psyU256RefValue u256TypeId squaredLowMaxLimbs
  let maskValue := psyU256RefValue u256TypeId maskLimbs
  let shlOneValue := psyU256RefValue u256TypeId shlOneLimbs
  let zeroValue := psyU256RefValue u256TypeId zeroLimbs
  let countOneValue : ReferenceValueV1 :=
    { typeId := u32TypeId, valueBytes := ByteArray.mk #[1, 0, 0, 0] }
  let lowMaxState := psyU256LogicalState lowMaxLimbs
  let carriedState := psyU256LogicalState carriedLimbs
  let squaredLowMaxState := psyU256LogicalState squaredLowMaxLimbs
  let shlOneState := psyU256LogicalState shlOneLimbs
  expectPsyReferenceReturned "psy-u256-ref-init"
    (stepReferenceSliceV1 admitted initial (invoke initId #[lowMaxValue]) noResponses)
    lowMaxState none
  expectPsyReferenceReturned "psy-u256-ref-carry"
    (stepReferenceSliceV1 admitted lowMaxState (invoke addId #[oneValue]) noResponses)
    carriedState (some carriedValue)
  expectPsyReferenceReturned "psy-u256-ref-mul-lowmax"
    (stepReferenceSliceV1 admitted lowMaxState
      (invoke multiplyId #[lowMaxValue]) noResponses)
    squaredLowMaxState (some squaredLowMaxValue)
  expectPsyReferenceReturned "psy-u256-ref-bitand"
    (stepReferenceSliceV1 admitted carriedState
      (invoke bitandId #[maskValue]) noResponses)
    (psyU256LogicalState zeroLimbs) (some zeroValue)
  expectPsyReferenceReturned "psy-u256-ref-shl1"
    (stepReferenceSliceV1 admitted lowMaxState
      (invoke shiftLeftId #[countOneValue]) noResponses)
    shlOneState (some shlOneValue)

  let plan ← liftResult <| planPsyVm compiled
  expect (plan.stateFieldNames ==
      #["total_0", "total_1", "total_2", "total_3",
        "total_4", "total_5", "total_6", "total_7"])
    "UInt256 state must flatten to eight little-endian UInt32 Felt limbs"
  let functionNamed (name : String) := plan.functions.find? (·.name == name)
  let some add := functionNamed "add" |
    throw <| IO.userError "UInt256 VM plan is missing add"
  let some multiply := functionNamed "multiply" |
    throw <| IO.userError "UInt256 VM plan is missing multiply"
  let some shiftLeft := functionNamed "shiftLeft" |
    throw <| IO.userError "UInt256 VM plan is missing shiftLeft"
  expect (add.params.size == 8 && add.params.all (·.uintWidth == 32))
    "UInt256 logical parameter must expand to eight UInt32 limbs"
  expect (shiftLeft.params.size == 1 && shiftLeft.params[0]!.uintWidth == 32)
    "UInt256 shift count must be one physical UInt32 limb"
  match add.resultKind with
  | .aggregate leaves =>
      expect (add.resultUintWidth == 256 && leaves.size == 8 &&
          leaves.all (fun leaf => !leaf.isInt && leaf.byteWidth == 4))
        "UInt256 result must be eight unsigned 4-byte limbs"
  | other =>
      throw <| IO.userError s!"UInt256 add expected aggregate result, got {repr other}"
  expect (add.body.any fun
      | .assertWithMessage _ message => message == "u256 add overflow"
      | _ => false)
    "UInt256 add must carry a stable final-carry overflow guard"
  expect (multiply.body.any fun
      | .bindWideUintMul 256 _ lhs rhs => lhs.size == 8 && rhs.size == 8
      | _ => false)
    "UInt256 mul must bind one exact schoolbook multiplication over eight limbs"
  expect (shiftLeft.body.any fun
      | .bindWideUintShift .shl 256 _ value _ => value.size == 8
      | _ => false)
    "UInt256 shl must bind one exact fixed-step shift binding"
  liftResult <| Targets.Psy.validatePlan plan
  let files ← liftResult <| buildPsyVm compiled
  let some psyFile := files.find? (·.path == "Wide256.psy") |
    throw <| IO.userError "psy: missing Wide256.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub total_7: Felt,")
    "UInt256 state must render eight Felt storage fields"
  expect (psy.contains
      "pub fn add(p0: Felt, p1: Felt, p2: Felt, p3: Felt, p4: Felt, p5: Felt, p6: Felt, p7: Felt) -> [Felt; 8]")
    "UInt256 entry ABI must expand to eight Felt limbs"
  expect (psy.contains "u256 add overflow" && psy.contains "u256 mul overflow" &&
      psy.contains "invalidShift: count >= 256")
    "UInt256 checked messages must reach emitted Psy source"
  expect (psy.contains "0u32..256u32")
    "UInt256 shift must emit the fixed 256-step bit walk"

/-- Default profile keeps UInt256 fail closed. -/
unsafe def testUInt256DefaultProfileFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Wide256Default where\n" ++
    "  state total : UInt256\n" ++
    "  entry add(delta : UInt256) : UInt256 do\n" ++
    "    total := total + delta\n" ++
    "    return total\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-u256-default>" "Tests.PsyU256Default" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planPsy compiled with
  | .error (.planInvariant .psy message) =>
      expect (message.contains "UInt" || message.contains "width" ||
          message.contains "unsupported")
        s!"default-profile UInt256 must fail closed, got: {message}"
  | .error error =>
      throw <| IO.userError s!"expected Psy planInvariant for default UInt256, got {error.render}"
  | .ok _ =>
      throw <| IO.userError "default profile UInt256 must remain fail closed"

/-- UInt32 comparisons are Felt-carried (unsigned order for values < 2^32 < p). -/
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
  expect (psy.contains "pub fn cmp(p0: Felt, p1: Felt) -> bool")
    "u32 comparison fn must render Felt params and bool result"
  expect (psy.contains "u32 param out of range")
    "u32 comparison params must be range-checked"
  expect (psy.contains " < ")
    "u32 lt must render"
  expect (psy.contains " == ")
    "u32 eq must render"

/-- Fail closed: Int128 remains outside the Psy pilot (no honest 128-bit
    two's-complement Felt carrier; narrow Int stops at Int32). -/
unsafe def testNarrowIntFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program I128 where\n" ++
    "  entry cmp(a : Int128, b : Int128) : Bool do\n" ++
    "    return a < b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-i128>" "Tests.PsyI128" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planPsy compiled with
  | .error (.planInvariant .psy msg) =>
      expect (msg.contains "Int" || msg.contains "width" || msg.contains "unsupported")
        s!"Int128 must fail closed at Psy type-closure, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .psy, got {e.render}"
  | .ok _ => throw <| IO.userError "Int128 must fail closed at Psy plan"

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

/-- B-RET-ABI: named Struct view return flattens to 2×UInt64 leaves via
    `returnAggregate` and emits honest Psy `-> [Felt; 2]` + `return [..];`. -/
unsafe def testNamedStructReturn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PairRet where\n" ++
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  state p : Pair\n" ++
    "  init(x : UInt64, y : UInt64) do\n" ++
    "    p := Pair.new(x, y)\n" ++
    "  view getPair() : Pair do\n" ++
    "    return p\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-pair-ret>" "Tests.PairRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  let some getPair := plan.functions.find? (·.name == "getPair") |
    throw <| IO.userError "PairRet plan must carry getPair"
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
  expect (!getPair.resultIsBool && !getPair.resultIsUnit && !getPair.resultIsU32)
    "PairRet aggregate must not set scalar result flags"
  expect (getPair.body.size == 1) "PairRet getPair body must be one return"
  match getPair.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2)
        s!"returnAggregate must have 2 leaves, got {leaves.size}"
      expect (leafIsInt == #[false, false])
        "returnAggregate leafIsInt must be #[false, false]"
      match leaves[0]!, leaves[1]! with
      | .stateLoad 0, .stateLoad 1 => pure ()
      | _, _ =>
          throw <| IO.userError
            "PairRet returnAggregate leaves must be stateLoad of p_a/p_b"
  | _ =>
      throw <| IO.userError "PairRet getPair body must be .returnAggregate"
  liftResult <| Targets.Psy.validatePlan plan
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "PairRet.psy") |
    throw <| IO.userError "psy: missing PairRet.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub fn getPair() -> [Felt; 2]")
    s!"PairRet source must declare -> [Felt; 2], got:\n{psy}"
  expect (psy.contains "return [c.p_a.get(), c.p_b.get()];" ||
      (psy.contains "return [" && psy.contains "p_a" && psy.contains "p_b"))
    s!"PairRet source must return [p_a, p_b] leaf array, got:\n{psy}"
  expect (!psy.contains "return of aggregate")
    "PairRet must not re-emit the old fail-closed message"

/-- B-RET-ABI: named Enum return = tag + max-payload slots (Maybe = 2 leaves). -/
unsafe def testNamedEnumReturn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MaybeRet where\n" ++
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  state m : Maybe\n" ++
    "  init() do\n" ++
    "    m := Maybe.None()\n" ++
    "  entry put(v : UInt64) : Maybe do\n" ++
    "    m := Maybe.Some(v)\n" ++
    "    return m\n" ++
    "  view peek() : Maybe do\n" ++
    "    return m\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-maybe-ret>" "Tests.MaybeRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  let some peek := plan.functions.find? (·.name == "peek") |
    throw <| IO.userError "MaybeRet plan must carry peek"
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
  let some put := plan.functions.find? (·.name == "put") |
    throw <| IO.userError "MaybeRet plan must carry put"
  match put.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2) "MaybeRet put must also return 2-leaf Maybe"
  | _ =>
      throw <| IO.userError "MaybeRet put resultKind must be .aggregate"
  liftResult <| Targets.Psy.validatePlan plan
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "MaybeRet.psy") |
    throw <| IO.userError "psy: missing MaybeRet.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub fn peek() -> [Felt; 2]")
    s!"MaybeRet peek must declare -> [Felt; 2], got:\n{psy}"
  expect (psy.contains "pub fn put(p0: Felt) -> [Felt; 2]")
    s!"MaybeRet put must declare -> [Felt; 2], got:\n{psy}"
  expect (psy.contains "return [")
    "MaybeRet source must emit array-literal return"

/-- N-ANON-RESULT: anonymous Array UInt64 2 view return → `[Felt; 2]`. -/
unsafe def testAnonymousArrayReturn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrayRet where\n" ++
    "  state slots : Array UInt64 2\n" ++
    "  init(a : UInt64, b : UInt64) do\n" ++
    "    slots[0] := a\n" ++
    "    slots[1] := b\n" ++
    "  entry setArr(a : UInt64, b : UInt64) : Array UInt64 2 do\n" ++
    "    slots[0] := a\n" ++
    "    slots[1] := b\n" ++
    "    return slots\n" ++
    "  view getArr() : Array UInt64 2 do\n" ++
    "    return slots\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-array-ret>" "Tests.ArrayRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  let some getArr := plan.functions.find? (·.name == "getArr") |
    throw <| IO.userError "ArrayRet plan must carry getArr"
  match getArr.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"ArrayRet aggregate return must have 2 leaves, got {leaves.size}"
      expect (leaves.all (fun l => !l.isInt && l.byteWidth == 8))
        "ArrayRet leaves must be 8-byte u64"
  | other =>
      throw <| IO.userError
        s!"ArrayRet getArr resultKind must be .aggregate, got {repr other}"
  match getArr.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2 && leafIsInt == #[false, false])
        "ArrayRet returnAggregate must have 2 u64 leaves"
      match leaves[0]!, leaves[1]! with
      | .stateLoad 0, .stateLoad 1 => pure ()
      | _, _ =>
          throw <| IO.userError
            "ArrayRet returnAggregate leaves must be stateLoad of slots_0/slots_1"
  | _ =>
      throw <| IO.userError "ArrayRet getArr body must be .returnAggregate"
  let some setArr := plan.functions.find? (·.name == "setArr") |
    throw <| IO.userError "ArrayRet plan must carry setArr"
  match setArr.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2) "ArrayRet setArr must also return 2-leaf Array"
  | _ =>
      throw <| IO.userError "ArrayRet setArr resultKind must be .aggregate"
  liftResult <| Targets.Psy.validatePlan plan
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "ArrayRet.psy") |
    throw <| IO.userError "psy: missing ArrayRet.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub fn getArr() -> [Felt; 2]")
    s!"ArrayRet getArr must declare -> [Felt; 2], got:\n{psy}"
  expect (psy.contains "pub fn setArr(p0: Felt, p1: Felt) -> [Felt; 2]")
    s!"ArrayRet setArr must declare -> [Felt; 2], got:\n{psy}"
  expect (psy.contains "return [")
    "ArrayRet source must emit array-literal return"

/-- N-ANON-RESULT: anonymous Option UInt64 entry/view → `[Felt; 2]` tag+payload. -/
unsafe def testAnonymousOptionReturn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptionRet where\n" ++
    "  state seed : UInt64\n" ++
    "  init(x : UInt64) do\n" ++
    "    seed := x\n" ++
    "  entry asSome(v : UInt64) : Option UInt64 do\n" ++
    "    return Option.some(v)\n" ++
    "  view asNone() : Option UInt64 do\n" ++
    "    return Option.none()\n" ++
    "  view asSomeOfSeed() : Option UInt64 do\n" ++
    "    return Option.some(seed)\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-option-ret>" "Tests.OptionRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  let some asNone := plan.functions.find? (·.name == "asNone") |
    throw <| IO.userError "OptionRet plan must carry asNone"
  match asNone.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"OptionRet asNone must be tag+payload (2), got {leaves.size}"
  | other =>
      throw <| IO.userError
        s!"OptionRet asNone resultKind must be .aggregate, got {repr other}"
  match asNone.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2 && leafIsInt == #[false, false])
        "OptionRet asNone returnAggregate must have 2 u64 leaves"
      match leaves[0]!, leaves[1]! with
      | .literal 0, .literal 0 => pure ()
      | _, _ =>
          throw <| IO.userError
            "OptionRet asNone leaves must be literal 0,0 (none)"
  | _ =>
      throw <| IO.userError "OptionRet asNone body must be .returnAggregate"
  let some asSome := plan.functions.find? (·.name == "asSome") |
    throw <| IO.userError "OptionRet plan must carry asSome"
  match asSome.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2) "OptionRet asSome must return 2-leaf Option"
  | _ =>
      throw <| IO.userError "OptionRet asSome resultKind must be .aggregate"
  match asSome.body[0]! with
  | .returnAggregate leaves _ =>
      match leaves[0]!, leaves[1]! with
      | .literal 1, .param 0 => pure ()
      | _, _ =>
          throw <| IO.userError
            "OptionRet asSome leaves must be literal 1 + param 0"
  | _ =>
      throw <| IO.userError "OptionRet asSome body must be .returnAggregate"
  liftResult <| Targets.Psy.validatePlan plan
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "OptionRet.psy") |
    throw <| IO.userError "psy: missing OptionRet.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub fn asNone() -> [Felt; 2]")
    s!"OptionRet asNone must declare -> [Felt; 2], got:\n{psy}"
  expect (psy.contains "pub fn asSome(p0: Felt) -> [Felt; 2]")
    s!"OptionRet asSome must declare -> [Felt; 2], got:\n{psy}"
  expect (psy.contains "return [")
    "OptionRet source must emit array-literal return"

/-- BL-36 / B-OPT-STATE: Option UInt64 state = Enum-shaped 2-leaf Felt layout
    (`slot_tag` + `slot_p0`); construct none zeroes payload; match read via
    VariantTag/VariantPayload; multi-leaf store on assign. -/
unsafe def testOptionState : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptionState where\n" ++
    "  state slot : Option UInt64\n" ++
    "  init() do\n" ++
    "    slot := Option.none()\n" ++
    -- entry name must not be `set` (Psy Storage derive owns `set`/`get` members).
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    slot := Option.some(v)\n" ++
    "    return v\n" ++
    "  entry clear() : UInt64 do\n" ++
    "    slot := Option.none()\n" ++
    "    return 0\n" ++
    "  view peek() : UInt64 do\n" ++
    "    match slot with\n" ++
    "    | Option.some(x) => do\n" ++
    "      return x\n" ++
    "    | _ => do\n" ++
    "      return 0\n" ++
    "  view getOpt() : Option UInt64 do\n" ++
    "    return slot\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-option-state>" "Tests.OptionState" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planPsy compiled
  expect (plan.stateFieldNames == #["slot_tag", "slot_p0"])
    s!"OptionState: Option UInt64 must flatten to slot_tag/slot_p0, got {plan.stateFieldNames}"
  -- Init none → one atomic tag+payload store, both literal zero.
  let some initFn := plan.functions.find? (·.name == "initialize") |
    throw <| IO.userError "OptionState plan must carry initialize"
  expect (initFn.body.any fun
      | .storeAggregate fields values =>
          fields == #[0, 1] && values == #[.literal 0, .literal 0]
      | _ => false)
    "OptionState init must atomically store tag=0 and zero payload"
  -- setSome → one atomic tag=1 + payload=param store.
  let some setFn := plan.functions.find? (·.name == "setSome") |
    throw <| IO.userError "OptionState plan must carry setSome"
  expect (setFn.body.any fun
      | .storeAggregate fields values =>
          fields == #[0, 1] && values == #[.literal 1, .param 0]
      | _ => false)
    "OptionState setSome must atomically store tag=1 and payload=param0"
  -- clear none-reset → atomic zero tag/payload (stale payload must not survive).
  let some clearFn := plan.functions.find? (·.name == "clear") |
    throw <| IO.userError "OptionState plan must carry clear"
  expect (clearFn.body.any fun
      | .storeAggregate fields values =>
          fields == #[0, 1] && values == #[.literal 0, .literal 0]
      | _ => false)
    "OptionState clear must atomically zero tag and stale payload"
  -- peek match → reads state leaves (VariantTag/VariantPayload path).
  let some peekFn := plan.functions.find? (·.name == "peek") |
    throw <| IO.userError "OptionState plan must carry peek"
  expect (!peekFn.resultIsBool && !peekFn.resultIsUnit)
    "OptionState peek must return scalar UInt64"
  expect (peekFn.body.any fun
      | .ifThenElse .. => true
      | .switchOn .. => true
      | _ => false)
    "OptionState peek must lower match to if/switch on VariantTag"
  -- Pin: match on Option.some uses tag leaf stateLoad 0 and payload leaf 1.
  expect (peekFn.body.any fun
      | .switchOn (.stateLoad 0) cases _ =>
          cases.any fun (tag, arm) =>
            tag == 1 && arm.any fun
              | .returnValue (.stateLoad 1) => true
              | _ => false
      | _ => false)
    "OptionState peek must switch on tag leaf and return payload leaf for some"
  -- getOpt return of stored Option → 2-leaf aggregate from state.
  let some getOpt := plan.functions.find? (·.name == "getOpt") |
    throw <| IO.userError "OptionState plan must carry getOpt"
  match getOpt.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"OptionState getOpt must return 2-leaf Option, got {leaves.size}"
  | other =>
      throw <| IO.userError
        s!"OptionState getOpt resultKind must be .aggregate, got {repr other}"
  match getOpt.body[getOpt.body.size - 1]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2 && leafIsInt == #[false, false])
        "OptionState getOpt returnAggregate must have 2 u64 leaves"
      match leaves[0]!, leaves[1]! with
      | .stateLoad 0, .stateLoad 1 => pure ()
      | a, b =>
          throw <| IO.userError
            s!"OptionState getOpt leaves must be stateLoad 0/1, got {repr a}/{repr b}"
  | _ =>
      throw <| IO.userError "OptionState getOpt must end with .returnAggregate"
  liftResult <| Targets.Psy.validatePlan plan
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "OptionState.psy") |
    throw <| IO.userError "psy: missing OptionState.psy"
  let psy := psyFile.contents
  expect (psy.contains "pub slot_tag: Felt," && psy.contains "pub slot_p0: Felt,")
    s!"OptionState source must declare slot_tag/slot_p0 Felt fields, got:\n{psy}"
  expect (psy.contains "pub fn getOpt() -> [Felt; 2]")
    s!"OptionState getOpt must declare -> [Felt; 2], got:\n{psy}"
  expect (psy.contains "slot_tag" && psy.contains "slot_p0")
    "OptionState emitted source must reference both Option leaves"
  IO.println "  OptionState Option UInt64 state Plan/emitter pin ok"

/-- Fail-closed matrix: Map/Bytes returns, >8 leaves, pureFn aggregate,
    non-UInt64 Array element, N>8 Array, Option non-UInt64 state, Option params. -/
unsafe def testAggregateReturnFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- B-OPT-STATE: Option of non-UInt64 state stays fail closed.
  let optBadSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptBadEl where\n" ++
    "  state o : Option UInt8\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  view get() : UInt64 do\n" ++
    "    return 0\n"
  match ← (do
      try
        let parsed ← liftResult (← session.selectProgramV1
          optBadSource "<psy-opt-bad>" "Tests.OptBadEl" none)
        let c ← liftResult <| Compiler.compileValidatedSourceV1 parsed
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planPsy c with
      | .error e =>
          expect (e.render.contains "Option" || e.render.contains "UInt64" ||
              e.render.contains "payload" || e.render.contains "element")
            s!"OptBadEl must cite Option/UInt64/payload, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "Psy Option UInt8 state must fail closed (UInt64 payload only)"
  -- Option param stays fail closed (state-only; mirrors Enum params).
  let optParamSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptParam where\n" ++
    "  state pad : UInt64\n" ++
    "  init(i : UInt64) do\n" ++
    "    pad := i\n" ++
    "  entry take(o : Option UInt64) : UInt64 do\n" ++
    "    return pad\n"
  match ← (do
      try
        let parsed ← liftResult (← session.selectProgramV1
          optParamSource "<psy-opt-param>" "Tests.OptParam" none)
        let c ← liftResult <| Compiler.compileValidatedSourceV1 parsed
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planPsy c with
      | .error e =>
          expect (e.render.contains "Option" || e.render.contains "parameter" ||
              e.render.contains "param")
            s!"OptParam must cite Option/parameter, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "Psy Option parameter must fail closed (state-only)"
  -- Anonymous Map return stays fail-closed.
  let mapSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapRet where\n" ++
    "  state seed : UInt64\n" ++
    "  init() do\n" ++
    "    seed := 0\n" ++
    "  view getMap() : Map UInt64 UInt64 do\n" ++
    "    return Map.empty()\n"
  match ← (do
      try
        let parsed ← liftResult (← session.selectProgramV1
          mapSource "<psy-map-ret>" "Tests.MapRet" none)
        let c ← liftResult <| Compiler.compileValidatedSourceV1 parsed
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planPsy c with
      | .error e =>
          expect (e.render.contains "Map" || e.render.contains "aggregate" ||
              e.render.contains "B-RET" || e.render.contains "container")
            s!"MapRet error must cite Map/aggregate, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "Psy anonymous Map return must fail closed (N-ANON-RESULT)"
  -- Anonymous Bytes return stays fail-closed.
  let bytesSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BytesRet where\n" ++
    "  state seed : UInt64\n" ++
    "  init() do\n" ++
    "    seed := 0\n" ++
    "  view getBytes() : Bytes 4 do\n" ++
    "    return 0x00000000\n"
  match ← (do
      try
        let parsed ← liftResult (← session.selectProgramV1
          bytesSource "<psy-bytes-ret>" "Tests.BytesRet" none)
        let c ← liftResult <| Compiler.compileValidatedSourceV1 parsed
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planPsy c with
      | .error e =>
          expect (e.render.contains "Bytes" || e.render.contains "aggregate" ||
              e.render.contains "B-RET" || e.render.contains "container")
            s!"BytesRet error must cite Bytes/aggregate, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "Psy anonymous Bytes return must fail closed (N-ANON-RESULT)"
  -- Array UInt64 9 exceeds B-RET-ABI leaf cap.
  let arr9Source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Arr9Ret where\n" ++
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
    "  view getArr() : Array UInt64 9 do\n" ++
    "    return slots\n"
  match ← (do
      try
        let parsed ← liftResult (← session.selectProgramV1
          arr9Source "<psy-arr9-ret>" "Tests.Arr9Ret" none)
        let c ← liftResult <| Compiler.compileValidatedSourceV1 parsed
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planPsy c with
      | .error e =>
          expect (e.render.contains "8" || e.render.contains "leaf" ||
              e.render.contains "aggregate")
            s!"Arr9Ret leaf-cap error must cite cap/leaf/aggregate, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "Psy Array UInt64 9 return must fail closed (cap-8)"
  -- Cap-8: Struct with 9 UInt64 fields exceeds B-RET-ABI leaf cap.
  let mut fields := ""
  let mut args := ""
  for i in [0:9] do
    fields := fields ++ s!"    f{i} : UInt64\n"
    args := args ++ (if i == 0 then "0" else ", 0")
  let wideSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program WideRet where\n" ++
    "  struct Wide where\n" ++
    fields ++
    "  state w : Wide\n" ++
    "  init() do\n" ++
    s!"    w := Wide.new({args})\n" ++
    "  view getWide() : Wide do\n" ++
    "    return w\n"
  match ← (do
      try
        let parsed ← liftResult (← session.selectProgramV1
          wideSource "<psy-wide-ret>" "Tests.WideRet" none)
        let c ← liftResult <| Compiler.compileValidatedSourceV1 parsed
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planPsy c with
      | .error e =>
          expect (e.render.contains "8" || e.render.contains "leaf" ||
              e.render.contains "aggregate")
            s!"WideRet leaf-cap error must cite cap/leaf/aggregate, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "Psy 9-leaf aggregate return must fail closed (cap-8)"
  -- pureFn aggregate return stays fail closed.
  let pureSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PureAgg where\n" ++
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  state p : Pair\n" ++
    "  init() do\n" ++
    "    p := Pair.new(0, 0)\n" ++
    "  fn make(x : UInt64, y : UInt64) : Pair do\n" ++
    "    return Pair.new(x, y)\n" ++
    "  entry run(x : UInt64, y : UInt64) : UInt64 do\n" ++
    "    let q := make(x, y)\n" ++
    "    return q.a\n"
  match ← (do
      try
        let parsed ← liftResult (← session.selectProgramV1
          pureSource "<psy-pure-agg>" "Tests.PureAgg" none)
        let c ← liftResult <| Compiler.compileValidatedSourceV1 parsed
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planPsy c with
      | .error e =>
          expect (e.render.contains "pureFn" || e.render.contains "aggregate" ||
              e.render.contains "B-RET")
            s!"PureAgg error must cite pureFn/aggregate, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "Psy pureFn aggregate return must fail closed"

/-- PSY-INT-NARROW: Int8/16/32 two's-complement bit patterns on Felt. -/
unsafe def testNarrowIntVmLowered : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program NarrowInt where\n" ++
    "  state acc : Int32\n" ++
    "  init(initial : Int32) do\n" ++
    "    acc := initial\n" ++
    "  entry add(delta : Int32) : Int32 do\n" ++
    "    acc := acc + delta\n" ++
    "    return acc\n" ++
    "  entry subtract(delta : Int32) : Int32 do\n" ++
    "    acc := acc - delta\n" ++
    "    return acc\n" ++
    "  entry multiply(factor : Int32) : Int32 do\n" ++
    "    acc := acc * factor\n" ++
    "    return acc\n" ++
    "  entry negate() : Int32 do\n" ++
    "    acc := -acc\n" ++
    "    return acc\n" ++
    "  view leq(bound : Int32) : Bool do\n" ++
    "    return acc <= bound\n" ++
    "  view get() : Int32 do\n" ++
    "    return acc\n" ++
    "  entry add8(a : Int8, b : Int8) : Int8 do\n" ++
    "    return a + b\n" ++
    "  entry add16(a : Int16, b : Int16) : Int16 do\n" ++
    "    return a + b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<psy-int-narrow>" "Tests.PsyIntNarrow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let carrier := CompiledSemanticV1.semanticV1Of compiled
  let data ← match validateSemanticProgramV1 carrier with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"narrow Int Reference validate failed: {repr error}"
  let admitted ← match admitReferenceProgramSliceV1 carrier with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"narrow Int Reference admission failed: {repr error}"
  let some i32TypeId := data.types.findSome? (fun decl =>
      match decl.name, decl.shape with
      | none, .int 32 => some decl.id
      | _, _ => none) |
    throw <| IO.userError "narrow Int semantic is missing anonymous Int32"
  let some boolTypeId := data.types.findSome? (fun decl =>
      match decl.name, decl.shape with
      | none, .bool => some decl.id
      | _, _ => none) |
    throw <| IO.userError "narrow Int semantic is missing anonymous Bool"
  let callableNamed (name : String) : Option CallableIdV1 :=
    data.callables.findSome? fun callable =>
      if callable.name == some name then some callable.id else none
  let some initId := data.callables.findSome? (fun c =>
      if c.kind == .initializer then some c.id else none) |
    throw <| IO.userError "narrow Int semantic is missing initializer"
  let some addId := callableNamed "add" |
    throw <| IO.userError "narrow Int semantic is missing add"
  let some leqId := callableNamed "leq" |
    throw <| IO.userError "narrow Int semantic is missing leq"
  let some negateId := callableNamed "negate" |
    throw <| IO.userError "narrow Int semantic is missing negate"
  let invoke (callableId : CallableIdV1) (args : Array ReferenceValueV1) : InvocationV1 :=
    { callableId, args, context := #[] }
  let noResponses : ExternalResponsesV1 := #[]
  -- Int32 -1 is LE bytes ff ff ff ff
  let minusOneBytes := ByteArray.mk #[255, 255, 255, 255]
  let zeroBytes := ByteArray.mk #[0, 0, 0, 0]
  let oneBytes := ByteArray.mk #[1, 0, 0, 0]
  let twoBytes := ByteArray.mk #[2, 0, 0, 0]
  let minusOne : ReferenceValueV1 := { typeId := i32TypeId, valueBytes := minusOneBytes }
  let zero : ReferenceValueV1 := { typeId := i32TypeId, valueBytes := zeroBytes }
  let one : ReferenceValueV1 := { typeId := i32TypeId, valueBytes := oneBytes }
  let two : ReferenceValueV1 := { typeId := i32TypeId, valueBytes := twoBytes }
  let zeroState : LogicalStateV1 :=
    { initialized := true
      canonicalValues := (ByteArray.mk #[4, 0, 0, 0]).append zeroBytes }
  let oneState : LogicalStateV1 :=
    { initialized := true
      canonicalValues := (ByteArray.mk #[4, 0, 0, 0]).append oneBytes }
  let minusOneState : LogicalStateV1 :=
    { initialized := true
      canonicalValues := (ByteArray.mk #[4, 0, 0, 0]).append minusOneBytes }
  let initial ← match initialLogicalStateV1 carrier with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"narrow Int initial state failed: {repr error}"
  expectPsyReferenceReturned "psy-i32-ref-init"
    (stepReferenceSliceV1 admitted initial (invoke initId #[zero]) noResponses)
    zeroState none
  expectPsyReferenceReturned "psy-i32-ref-add"
    (stepReferenceSliceV1 admitted zeroState (invoke addId #[one]) noResponses)
    oneState (some one)
  expectPsyReferenceReturned "psy-i32-ref-leq"
    (stepReferenceSliceV1 admitted oneState (invoke leqId #[two]) noResponses)
    oneState (some { typeId := boolTypeId, valueBytes := ByteArray.mk #[1] })
  expectPsyReferenceReturned "psy-i32-ref-neg"
    (stepReferenceSliceV1 admitted oneState (invoke negateId #[]) noResponses)
    minusOneState (some minusOne)
  expectPsyReferenceStandardRevert "psy-i32-ref-add-overflow"
    (stepReferenceSliceV1 admitted
      { initialized := true
        canonicalValues :=
          (ByteArray.mk #[4, 0, 0, 0]).append (ByteArray.mk #[255, 255, 255, 127]) }
      (invoke addId #[one]) noResponses)
    .arithmeticOverflow
    { initialized := true
      canonicalValues :=
        (ByteArray.mk #[4, 0, 0, 0]).append (ByteArray.mk #[255, 255, 255, 127]) }

  let plan ← liftResult <| planPsy compiled
  let functionNamed (name : String) := plan.functions.find? (·.name == name)
  let some add := functionNamed "add" |
    throw <| IO.userError "narrow Int plan is missing add"
  let some add8 := functionNamed "add8" |
    throw <| IO.userError "narrow Int plan is missing add8"
  expect (add.body.any fun
      | .returnValue (.narrowSignedCheckedAdd 32 _ _) => true
      | .store _ (.narrowSignedCheckedAdd 32 _ _) => true
      | .storeAggregate _ values =>
          values.any fun
            | .narrowSignedCheckedAdd 32 _ _ => true
            | _ => false
      | _ => false)
    "Int32 add must lower to narrowSignedCheckedAdd"
  expect (add8.body.any fun
      | .returnValue (.narrowSignedCheckedAdd 8 _ _) => true
      | _ => false)
    "Int8 add must lower to narrowSignedCheckedAdd"
  liftResult <| Targets.Psy.validatePlan plan
  let files ← liftResult <| buildPsy compiled
  let some psyFile := files.find? (·.path == "NarrowInt.psy") |
    throw <| IO.userError "psy: missing NarrowInt.psy"
  let psy := psyFile.contents
  expect (psy.contains "i32 add overflow" && psy.contains "i8 add overflow")
    "narrow Int overflow messages must reach emitted Psy source"
  expect (psy.contains "i32 neg overflow (intMin)")
    "Int32 negation intMin guard must be emitted"

unsafe def run : IO Unit := do
  testCounterPsySource
  testCheckedArithGuards
  testBitwiseAndShifts
  testEmitAndPureFn
  testScalarConstantsLowered
  testScalarConstantsRepresentabilityFailClosed
  testUInt64BitNotLowered
  testFailClosedInt64BitNot
  testUInt32BitNotLowered
  testUInt32ArithWidthGuard
  testUInt8CounterMultiWidth
  testUInt128FailClosed
  testUInt128VmProfileLowered
  testUInt128VmDivModLowered
  testUInt128VmDivModResourceFailClosed
  testUInt256VmProfileLowered
  testUInt256DefaultProfileFailClosed
  testNarrowIntVmLowered
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
  testNamedStructReturn
  testNamedEnumReturn
  testAnonymousArrayReturn
  testAnonymousOptionReturn
  testOptionState
  testAggregateReturnFailClosed
  IO.println "Tests.Materialization.PsySourceV1: ok"

end Tests.Materialization.PsySourceV1
