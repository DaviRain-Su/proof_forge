/-
  Tests.Semantic.InvariantABI — engineering suite for the D2-07 public
  invariant ABI (`ProofForgeV2.Semantic.InvariantABI`).

  Engineering only (not formal TST-SEM / TASK-D2-07). Pins:
    * `defaultValueV1` for every TypeShapeV1
    * `initialLogicalStateV1` declaration-order slots + initialized flag
    * `stateConformsBoolV1` true-state only
    * `decodeLogicalStateValuesV1` / `encodeLogicalStateValuesV1` roundtrip
    * representative decode/encode negatives (missing slot, short length,
      trailing, noncanonical Bool/Option/Field)
    * public evalInvariantV1 ordinal/state/closure/result/fail-closed behavior
    * exact definitional InvariantTheoremV1 proposition shape
    * deterministic repeat

  Hand fixtures always pass through `encodeSemanticProgramDataV1` then
  `decodeSemanticProgramV1` (structure-gated carrier; no bypass).
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.WireV1

namespace Tests.Semantic.InvariantABI

set_option maxRecDepth 4096

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-! The public theorem ABI is deliberately pinned as a definitional alias,
not merely as a logically equivalent proposition assembled by this suite. -/
example (program : SemanticProgramV1) (ordinal : InvariantOrdinalV1) :
    InvariantTheoremV1 program ordinal ↔
      (ordinal.toNat < program.invariants.size ∧
        ∀ state : LogicalStateV1, StateConformsV1 program state →
          evalInvariantV1 program ordinal state = .returnedTrue) := Iff.rfl

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectOk {α} (label : String) (r : Except SemanticWireErrorV1 α) : IO α :=
  match r with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{label}: unexpected error {repr e}"

private def expectErr (label : String) (want : SemanticWireErrorV1)
    (r : Except SemanticWireErrorV1 α) : IO Unit :=
  match r with
  | .error e =>
    unless e == want do
      throw <| IO.userError s!"{label}: expected {repr want}, got {repr e}"
  | .ok _ => throw <| IO.userError s!"{label}: expected error {repr want}"

private def bytesEqual (a b : ByteArray) : Bool := a == b

private def u32le (n : Nat) : ByteArray :=
  encodeU32le (UInt32.ofNat n)

private def zeroBytes (n : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity n
  for _ in [:n] do
    out := out.push 0
  pure out

private def stateSlot (valueBytes : ByteArray) : ByteArray :=
  (encodeU32le (UInt32.ofNat valueBytes.size)).append valueBytes

private def appendSlots (slots : Array ByteArray) : ByteArray := Id.run do
  let mut out := ByteArray.empty
  for s in slots do
    out := out.append (stateSlot s)
  pure out

private def emptyData (name : String) : IO SemanticProgramDataV1 := do
  let qn ← match parseQualifiedName #["Tests", name] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  pure {
    qualifiedName := qn
    types := #[]
    constants := #[]
    logicalState := #[]
    events := #[]
    errors := #[]
    callables := #[]
    invariants := #[]
    requirements := { items := #[] }
  }

/-- Minimal `.entry` satisfying the SPEC §6 aggregate entry/view presence gate. -/
private def entryGate (id : CallableIdV1) (resultTypeId : TypeIdV1) : CallableV1 :=
  {
    id
    kind := .entry
    name := some "entry_gate"
    params := #[]
    result := { typeId := resultTypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{ id := 0, params := #[], instructions := #[],
                  terminator := .return_ none }]
    loopBounds := #[]
    invariantSteps := none
  }

private def mkInit
    (id : CallableIdV1) (unitTypeId : TypeIdV1) : CallableV1 :=
  {
    id
    kind := .initializer
    name := none
    params := #[]
    result := { typeId := unitTypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{ id := 0, params := #[], instructions := #[],
                  terminator := .return_ none }]
    loopBounds := #[]
    invariantSteps := none
  }

private def valueDef (id : Nat) (typeId : TypeIdV1) : ValueDefV1 :=
  { valueId := UInt32.ofNat id, typeId }

private def instruction (result : Option ValueDefV1) (op : SemanticOpV1) : InstructionV1 :=
  { result, op }

private def invariantCallable (id : CallableIdV1) (name : String)
    (instructions : Array InstructionV1) (terminator : TerminatorV1)
    (steps : Nat) : CallableV1 := {
  id
  kind := .invariant
  name := some name
  params := #[]
  result := { typeId := 0, visibility := .public_ }
  entryBlock := 0
  blocks := #[{ id := 0, params := #[], instructions, terminator }]
  loopBounds := #[]
  invariantSteps := some (UInt64.ofNat steps)
}

private def boolLiteral (id : Nat) (value : Bool) : InstructionV1 :=
  instruction (some (valueDef id 0))
    (.literal 0 (ByteArray.mk #[if value then 1 else 0]))

private def evalState : LogicalStateV1 :=
  { initialized := true, canonicalValues := ByteArray.empty }

/--
  Named Struct/Enum occupy types[0..1); anonymous leaves/containers follow
  without duplicate anonymous shapes. TypeId layout:

    0  named Struct Pair { a:Bool, b:UInt8 }
    1  named Enum Tag { V0(UInt8), V1() }
    2  Bool
    3  UInt8
    4  Int8
    5  Principal
    6  Unit
    7  Bytes 3
    8  Array Bool × 2
    9  Map Bool → UInt8
    10 Option Bool
    11 Field bn254-fr
-/
private def allShapeTypes : Array TypeDeclV1 := #[
  {
    id := 0
    name := some "Pair"
    shape := .struct #[
      { name := "a", typeId := 2 },
      { name := "b", typeId := 3 }
    ]
  },
  {
    id := 1
    name := some "Tag"
    shape := .enum #[
      { name := "V0", payloadTypes := #[3] },
      { name := "V1", payloadTypes := #[] }
    ]
  },
  { id := 2, name := none, shape := .bool },
  { id := 3, name := none, shape := .uint 8 },
  { id := 4, name := none, shape := .int 8 },
  { id := 5, name := none, shape := .principal },
  { id := 6, name := none, shape := .unit },
  { id := 7, name := none, shape := .bytes 3 },
  { id := 8, name := none, shape := .array 2 2 },
  { id := 9, name := none, shape := .map 2 3 },
  { id := 10, name := none, shape := .option 2 },
  { id := 11, name := none, shape := .field bn254FrFieldSpecV1 }
]

/-- State declaration order covers a representative multi-slot mix. -/
private def multiStateDecls : Array StateDeclV1 := #[
  { id := 0, name := "sBool", typeId := 2, visibility := .public_ },
  { id := 1, name := "sU8", typeId := 3, visibility := .public_ },
  { id := 2, name := "sOpt", typeId := 10, visibility := .public_ },
  { id := 3, name := "sPair", typeId := 0, visibility := .public_ },
  { id := 4, name := "sMap", typeId := 9, visibility := .public_ }
]

private def encodeCarrier (label : String) (data : SemanticProgramDataV1) :
    IO SemanticProgramV1 := do
  let bytes ← match encodeSemanticProgramDataV1 data with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"{label}: encode failed: {repr e}"
  match decodeSemanticProgramV1 bytes with
  | .ok c => pure c
  | .error e => throw <| IO.userError s!"{label}: carrier decode failed: {repr e}"

/-- No-initializer program: multi-state defaults, initialized=true. -/
private def programNoInit (name : String) : IO SemanticProgramV1 := do
  let base ← emptyData name
  let data : SemanticProgramDataV1 := {
    base with
    types := allShapeTypes
    logicalState := multiStateDecls
    -- entry result Unit (typeId 6); return_ none is not result-type-checked.
    callables := #[entryGate 0 6]
  }
  encodeCarrier name data

/-- With-initializer program: same tables; initialized=false on initial state. -/
private def programWithInit (name : String) : IO SemanticProgramV1 := do
  let base ← emptyData name
  let data : SemanticProgramDataV1 := {
    base with
    types := allShapeTypes
    logicalState := multiStateDecls
    callables := #[mkInit 0 6, entryGate 1 6]
  }
  encodeCarrier name data

/-- Expected type-driven defaults for `allShapeTypes` (SPEC-SEM-CORE). -/
private def expectedDefaults : Array (TypeIdV1 × ByteArray) := #[
  -- 0 Struct Pair = Bool false || UInt8 0
  (0, ByteArray.mk #[0, 0]),
  -- 1 Enum Tag variant0 + UInt8 payload default
  (1, (u32le 0).append (ByteArray.mk #[0])),
  -- 2 Bool false
  (2, ByteArray.mk #[0]),
  -- 3 UInt8 zero
  (3, ByteArray.mk #[0]),
  -- 4 Int8 zero
  (4, ByteArray.mk #[0]),
  -- 5 Principal payload `00` with u32 length
  (5, (u32le 1).append (ByteArray.mk #[0])),
  -- 6 Unit empty
  (6, ByteArray.empty),
  -- 7 Bytes 3 zeros
  (7, zeroBytes 3),
  -- 8 Array Bool×2 = false,false
  (8, ByteArray.mk #[0, 0]),
  -- 9 Map empty
  (9, u32le 0),
  -- 10 Option none
  (10, ByteArray.mk #[0]),
  -- 11 Field zero (32 LE bytes for bn254 Fr)
  (11, zeroBytes 32)
]

private def expectedMultiStateDefaults : Array ByteArray := #[
  ByteArray.mk #[0],           -- Bool
  ByteArray.mk #[0],           -- UInt8
  ByteArray.mk #[0],           -- Option none
  ByteArray.mk #[0, 0],        -- Pair
  u32le 0                      -- Map empty
]

/-! ### defaultValueV1 — all TypeShape families -/

private def testDefaultValueAllShapes : IO Unit := do
  let carrier ← programNoInit "DefaultShapes"
  for pair in expectedDefaults do
    let typeId := pair.1
    let want := pair.2
    let got ← expectOk s!"defaultValue typeId={typeId}"
      (defaultValueV1 carrier typeId)
    expect (bytesEqual got want)
      s!"defaultValue typeId={typeId}: bytes mismatch (got size {got.size}, want {want.size})"
    -- Output must re-validate under the public valueBytes gate.
    let data ← expectOk "validate carrier" (validateSemanticProgramV1 carrier)
    expectOk s!"validateValueBytes typeId={typeId}"
      (validateValueBytesV1 data.types typeId got)
  -- Bad typeId fails closed.
  expectErr "defaultValue OOR typeId" .badReference
    (defaultValueV1 carrier 99)

/-! ### initialLogicalStateV1 — order + initialized flag -/

private def testInitialLogicalState : IO Unit := do
  -- No initializer ⇒ initialized=true, slots = defaults in state order.
  let noInit ← programNoInit "InitNoInit"
  let stNo ← expectOk "initial no-init" (initialLogicalStateV1 noInit)
  expect (stNo.initialized == true)
    "no initializer: initialized=true"
  let wantCanon := appendSlots expectedMultiStateDefaults
  expect (bytesEqual stNo.canonicalValues wantCanon)
    "no initializer: canonicalValues = u32len||default per state order"
  -- With initializer ⇒ initialized=false, same default bytes.
  let withInit ← programWithInit "InitWithInit"
  let stYes ← expectOk "initial with-init" (initialLogicalStateV1 withInit)
  expect (stYes.initialized == false)
    "with initializer: initialized=false"
  expect (bytesEqual stYes.canonicalValues wantCanon)
    "with initializer: same default slot encoding"
  -- Empty logicalState still succeeds (initialized depends on init presence).
  let base ← emptyData "EmptyState"
  let emptyNoInit : SemanticProgramDataV1 := {
    base with
    types := #[{ id := 0, name := none, shape := .unit }]
    logicalState := #[]
    callables := #[entryGate 0 0]
  }
  let emptyCarrier ← encodeCarrier "EmptyState" emptyNoInit
  let stEmpty ← expectOk "initial empty state" (initialLogicalStateV1 emptyCarrier)
  expect (stEmpty.initialized == true) "empty state no-init: initialized=true"
  expect (stEmpty.canonicalValues.isEmpty) "empty state: empty canonicalValues"
  let base2 ← emptyData "EmptyStateInit"
  let emptyWithInit : SemanticProgramDataV1 := {
    base2 with
    types := #[{ id := 0, name := none, shape := .unit }]
    logicalState := #[]
    callables := #[mkInit 0 0, entryGate 1 0]
  }
  let emptyInitCarrier ← encodeCarrier "EmptyStateInit" emptyWithInit
  let stEmptyInit ← expectOk "initial empty+init"
    (initialLogicalStateV1 emptyInitCarrier)
  expect (stEmptyInit.initialized == false)
    "empty state with-init: initialized=false"

/-! ### stateConformsBoolV1 -/

private def testStateConforms : IO Unit := do
  let carrier ← programNoInit "Conforms"
  let initial ← expectOk "initial" (initialLogicalStateV1 carrier)
  -- No-init initial is already initialized=true and default-canonical ⇒ conforms.
  expect (stateConformsBoolV1 carrier initial == true)
    "true-state defaults must conform"
  -- False init does not conform even with valid default bytes.
  let falseInit : LogicalStateV1 :=
    { initialized := false, canonicalValues := initial.canonicalValues }
  expect (stateConformsBoolV1 carrier falseInit == false)
    "initialized=false must not conform"
  -- True reconstruction of a conforming state still conforms.
  let trueCopy : LogicalStateV1 :=
    { initialized := true
      canonicalValues := initial.canonicalValues.extract 0 initial.canonicalValues.size }
  expect (stateConformsBoolV1 carrier trueCopy == true)
    "true copy of conforming state must conform"
  -- With-init initial (false) does not conform; flipping initialized does.
  let withInit ← programWithInit "ConformsInit"
  let stFalse ← expectOk "initial with-init" (initialLogicalStateV1 withInit)
  expect (stateConformsBoolV1 withInit stFalse == false)
    "with-init pre-state (initialized=false) does not conform"
  let stTrue : LogicalStateV1 :=
    { initialized := true, canonicalValues := stFalse.canonicalValues }
  expect (stateConformsBoolV1 withInit stTrue == true)
    "same defaults with initialized=true conform"
  -- Corrupted bytes do not conform.
  let bad : LogicalStateV1 :=
    { initialized := true, canonicalValues := ByteArray.mk #[0] }
  expect (stateConformsBoolV1 carrier bad == false)
    "truncated/malformed canonicalValues must not conform"

/-! ### decode / encode roundtrip -/

private def testDecodeEncodeRoundtrip : IO Unit := do
  let carrier ← programNoInit "Roundtrip"
  let data ← expectOk "validate" (validateSemanticProgramV1 carrier)
  let initial ← expectOk "initial" (initialLogicalStateV1 carrier)
  let slots ← expectOk "decode initial"
    (decodeLogicalStateValuesV1 data initial)
  expect (slots.size == expectedMultiStateDefaults.size)
    "decode slot count == logicalState size"
  for i in [:slots.size] do
    let got := slots[i]!
    let want := expectedMultiStateDefaults[i]!
    expect (bytesEqual got want)
      s!"decode slot {i}: default mismatch"
  -- encode → decode identity (initialized preserved).
  let re ← expectOk "encode from slots"
    (encodeLogicalStateValuesV1 data true slots)
  expect (re.initialized == true) "encode preserves initialized=true"
  expect (bytesEqual re.canonicalValues initial.canonicalValues)
    "encode(decode(initial)) canonical identity"
  let slots2 ← expectOk "decode re-encoded"
    (decodeLogicalStateValuesV1 data re)
  expect (slots2.size == slots.size) "re-decode slot count"
  for i in [:slots.size] do
    expect (bytesEqual slots2[i]! slots[i]!)
      s!"roundtrip slot {i}"
  -- Non-default but still canonical valueBytes (Bool true) roundtrips.
  let custom : Array ByteArray := #[
    ByteArray.mk #[1],           -- Bool true
    ByteArray.mk #[0x2a],        -- UInt8 42
    ByteArray.mk #[0],           -- Option none
    ByteArray.mk #[1, 7],        -- Pair (true, 7)
    u32le 0                      -- Map empty
  ]
  let customSt ← expectOk "encode custom"
    (encodeLogicalStateValuesV1 data true custom)
  expect (stateConformsBoolV1 carrier customSt == true)
    "custom canonical true-state conforms"
  let customSlots ← expectOk "decode custom"
    (decodeLogicalStateValuesV1 data customSt)
  for i in [:custom.size] do
    expect (bytesEqual customSlots[i]! custom[i]!)
      s!"custom roundtrip slot {i}"

/-! ### representative negatives -/

private def testDecodeEncodeNegatives : IO Unit := do
  let carrier ← programNoInit "Negatives"
  let data ← expectOk "validate" (validateSemanticProgramV1 carrier)
  let defaults := expectedMultiStateDefaults
  -- Missing slot (arity too small).
  expectErr "encode missing slot" .nonCanonical
    (encodeLogicalStateValuesV1 data true defaults.pop)
  -- Extra slot (arity too large).
  expectErr "encode extra slot" .nonCanonical
    (encodeLogicalStateValuesV1 data true (defaults.push (ByteArray.mk #[0])))
  -- Noncanonical Bool (marker 2) in slot 0.
  let badBool := defaults.set! 0 (ByteArray.mk #[2])
  expectErr "encode noncanonical Bool" .nonCanonical
    (encodeLogicalStateValuesV1 data true badBool)
  -- Noncanonical Option marker 2 in slot 2 (sOpt).
  let badOpt := defaults.set! 2 (ByteArray.mk #[2])
  expectErr "encode noncanonical Option" .nonCanonical
    (encodeLogicalStateValuesV1 data true badOpt)
  -- Noncanonical Field ≥ p via a single-state field program.
  let baseF ← emptyData "NegField"
  let fieldData : SemanticProgramDataV1 := {
    baseF with
    types := #[{ id := 0, name := none, shape := .field bn254FrFieldSpecV1 },
               { id := 1, name := none, shape := .unit }]
    logicalState := #[{ id := 0, name := "f", typeId := 0, visibility := .public_ }]
    callables := #[entryGate 0 1]
  }
  let fieldCarrier ← encodeCarrier "NegField" fieldData
  let fieldProgData ← expectOk "field validate"
    (validateSemanticProgramV1 fieldCarrier)
  -- p as LE 32-byte value is ≥ modulus ⇒ nonCanonical.
  let pBytes := bn254FrModulusBEV1
  -- modulus is BE; convert to LE equal-width by reversing for p itself (same
  -- numerical p when read LE from reverse of BE modulus bytes... actually
  -- WireV1 tests use leBytesFromNat (beBytesToNat modulus) 32).
  let beToNat (bytes : ByteArray) : Nat := Id.run do
    let mut n : Nat := 0
    for i in [:bytes.size] do
      n := n * 256 + (bytes.get! i).toNat
    pure n
  let leFromNat (n : Nat) (len : Nat) : ByteArray := Id.run do
    let mut out := ByteArray.emptyWithCapacity len
    let mut v := n
    for _ in [:len] do
      out := out.push (UInt8.ofNat (v % 256))
      v := v / 256
    pure out
  let fieldGeP := leFromNat (beToNat pBytes) 32
  expectErr "encode Field ≥ p" .nonCanonical
    (encodeLogicalStateValuesV1 fieldProgData true #[fieldGeP])
  -- Decode: short length (u32 claims more bytes than available).
  let short : LogicalStateV1 :=
    { initialized := true
      -- length=4 but only 1 payload byte follows for first slot (Bool).
      canonicalValues := (u32le 4).append (ByteArray.mk #[0]) }
  expectErr "decode short length" .truncated
    (decodeLogicalStateValuesV1 data short)
  -- Decode: missing length prefix entirely.
  let missing : LogicalStateV1 :=
    { initialized := true, canonicalValues := ByteArray.empty }
  expectErr "decode missing slot" .truncated
    (decodeLogicalStateValuesV1 data missing)
  -- Decode: valid first slot then trailing garbage.
  let oneOkThenTrail :=
    (stateSlot (ByteArray.mk #[0])).append (ByteArray.mk #[0xde, 0xad])
  let trailing : LogicalStateV1 :=
    { initialized := true, canonicalValues := oneOkThenTrail }
  -- After first slot, remaining bytes are not a valid second-slot length+value
  -- sequence covering all remaining states; fails truncated (or trailing when
  -- only one state). With multi-state, short remaining ⇒ truncated.
  expectErr "decode truncated multi after one" .truncated
    (decodeLogicalStateValuesV1 data trailing)
  -- Single-state trailing-bytes case.
  let base1 ← emptyData "NegTrail"
  let oneState : SemanticProgramDataV1 := {
    base1 with
    types := #[{ id := 0, name := none, shape := .bool },
               { id := 1, name := none, shape := .unit }]
    logicalState := #[{ id := 0, name := "b", typeId := 0, visibility := .public_ }]
    callables := #[entryGate 0 1]
  }
  let oneCarrier ← encodeCarrier "NegTrail" oneState
  let oneData ← expectOk "one validate" (validateSemanticProgramV1 oneCarrier)
  let trailBytes :=
    (stateSlot (ByteArray.mk #[0])).append (ByteArray.mk #[0xff])
  let trailSt : LogicalStateV1 :=
    { initialized := true, canonicalValues := trailBytes }
  expectErr "decode trailing bytes" .trailingBytes
    (decodeLogicalStateValuesV1 oneData trailSt)
  -- Decode noncanonical Bool inside a well-framed slot.
  let badBoolFramed : LogicalStateV1 :=
    { initialized := true
      canonicalValues := appendSlots #[
        ByteArray.mk #[2], ByteArray.mk #[0], ByteArray.mk #[0],
        ByteArray.mk #[0, 0], u32le 0
      ] }
  expectErr "decode noncanonical Bool" .nonCanonical
    (decodeLogicalStateValuesV1 data badBoolFramed)
  -- stateConformsBoolV1 maps all decode failures to false (total).
  expect (stateConformsBoolV1 carrier short == false)
    "conforms: short → false"
  expect (stateConformsBoolV1 carrier missing == false)
    "conforms: missing → false"
  expect (stateConformsBoolV1 oneCarrier trailSt == false)
    "conforms: trailing → false"
  expect (stateConformsBoolV1 carrier badBoolFramed == false)
    "conforms: noncanonical → false"

/-! ### public evalInvariantV1 ABI -/

namespace CanonicalInvariantFixtureV1

/-- Closed qualified name for the public invariant ABI proof fixture. -/
def qualifiedName : QualifiedName :=
  { components := ⟨"Tests", #["PublicInvariantABI"]⟩ }

/-- The exact type table exercised by the selected invariant. The unrelated
    Principal declaration pins selected-closure rather than whole-program
    admission. -/
def types : Array TypeDeclV1 := #[
  { id := 0, name := none, shape := .bool },
  { id := 1, name := none, shape := .principal },
  { id := 2, name := none, shape := .unit }
]

def gate : CallableV1 := entryGate 0 2

def leaf : CallableV1 := {
  id := 1
  kind := .pureFn
  name := some "truthLeaf"
  params := #[]
  result := { typeId := 0, visibility := .public_ }
  entryBlock := 0
  blocks := #[{
    id := 0
    params := #[]
    instructions := #[boolLiteral 0 true]
    terminator := .return_ (some 0)
  }]
  loopBounds := #[]
  invariantSteps := some 3
}

/-- Selected invariant root. Its exact cost is
    root(1 + PureCall + return) + leaf(3) = 6. -/
def truth : CallableV1 :=
  invariantCallable 2 "truth"
    #[instruction (some (valueDef 0 0)) (.pureCall 1 #[])]
    (.return_ (some 0)) 6

def falsehood : CallableV1 :=
  invariantCallable 3 "falsehood" #[boolLiteral 0 false]
    (.return_ (some 0)) 3

/-- Closed semantic data used by both the runtime ABI suite and the kernel
    carrier proof. This is data only; carrier bytes remain under the sole
    production encoder/decoder authorities. -/
def data : SemanticProgramDataV1 := {
  qualifiedName
  types
  constants := #[]
  logicalState := #[
    { id := 0, name := "flag", typeId := 0, visibility := .public_ }
  ]
  events := #[]
  errors := #[]
  callables := #[gate, leaf, truth, falsehood]
  invariants := #[
    { id := 0, name := "truth", callableId := 2 },
    { id := 1, name := "falsehood", callableId := 3 }
  ]
  requirements := { items := #[] }
}

def selectedState : LogicalStateV1 := {
  initialized := true
  canonicalValues := stateSlot (ByteArray.mk #[0])
}

/-- Exact 1235-byte production encoding of `data`. This explicit golden is
    intentionally independent of encoder computation, so later decoder proofs
    have a closed byte spine rather than a self-derived carrier. -/
def canonicalBytes : ByteArray := ByteArray.mk #[
  112, 102, 46, 115, 101, 109, 97, 110, 116, 105, 99, 46, 118, 49, 0, 20, 0, 0, 0,
  83, 101, 109, 97, 110, 116, 105, 99, 80, 114, 111, 103, 114, 97, 109, 46, 68,
  97, 116, 97, 9, 0, 2, 0, 0, 0, 5, 0, 0, 0, 84, 101, 115, 116, 115, 18, 0, 0,
  0, 80, 117, 98, 108, 105, 99, 73, 110, 118, 97, 114, 105, 97, 110, 116, 65,
  66, 73, 3, 0, 0, 0, 8, 0, 0, 0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0,
  0, 0, 0, 0, 0, 9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0,
  8, 0, 0, 0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0, 1, 0, 0, 0, 0, 14,
  0, 0, 0, 84, 121, 112, 101, 46, 80, 114, 105, 110, 99, 105, 112, 97, 108, 0,
  0, 8, 0, 0, 0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0, 2, 0, 0, 0, 0, 9,
  0, 0, 0, 84, 121, 112, 101, 46, 85, 110, 105, 116, 0, 0, 0, 0, 0, 0, 1, 0,
  0, 0, 9, 0, 0, 0, 83, 116, 97, 116, 101, 68, 101, 99, 108, 4, 0, 0, 0, 0, 0,
  4, 0, 0, 0, 102, 108, 97, 103, 0, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105,
  98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 4, 0, 0, 0, 8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9,
  0, 0, 0, 0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 46, 69, 110,
  116, 114, 121, 0, 0, 1, 10, 0, 0, 0, 101, 110, 116, 114, 121, 95, 103, 97, 116,
  101, 0, 0, 0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 82, 101,
  115, 117, 108, 116, 2, 0, 2, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98, 105,
  108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0, 1, 0, 0,
  0, 5, 0, 0, 0, 66, 108, 111, 99, 107, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 11, 0, 0, 0, 84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110, 1, 0,
  0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9, 0, 1,
  0, 0, 0, 15, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 46, 80, 117, 114,
  101, 70, 110, 0, 0, 1, 9, 0, 0, 0, 116, 114, 117, 116, 104, 76, 101, 97, 102,
  0, 0, 0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115,
  117, 108, 116, 2, 0, 0, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98, 105,
  108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0, 1, 0, 0,
  0, 5, 0, 0, 0, 66, 108, 111, 99, 107, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0,
  0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0,
  1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 10, 0, 0, 0, 79, 112, 46, 76, 105, 116, 101, 114, 97, 108, 2, 0, 0, 0,
  0, 0, 1, 0, 0, 0, 1, 11, 0, 0, 0, 84, 101, 114, 109, 46, 82, 101, 116, 117,
  114, 110, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 0, 0, 0, 0, 0, 0, 0, 8,
  0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9, 0, 2, 0, 0, 0, 18, 0, 0, 0,
  67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114, 105, 97, 110,
  116, 0, 0, 1, 5, 0, 0, 0, 116, 114, 117, 116, 104, 0, 0, 0, 0, 14, 0, 0, 0,
  67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116, 2, 0, 0, 0, 0,
  0, 17, 0, 0, 0, 86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117,
  98, 108, 105, 99, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 5, 0, 0, 0, 66, 108, 111,
  99, 107, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 11, 0, 0, 0, 73, 110,
  115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108,
  117, 101, 68, 101, 102, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11, 0, 0, 0, 79, 112,
  46, 80, 117, 114, 101, 67, 97, 108, 108, 2, 0, 1, 0, 0, 0, 0, 0, 0, 0, 11, 0,
  0, 0, 84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110, 1, 0, 1, 0, 0, 0, 0, 0,
  0, 0, 0, 1, 6, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 67, 97, 108, 108, 97, 98,
  108, 101, 9, 0, 3, 0, 0, 0, 18, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101,
  46, 73, 110, 118, 97, 114, 105, 97, 110, 116, 0, 0, 1, 9, 0, 0, 0, 102, 97, 108,
  115, 101, 104, 111, 111, 100, 0, 0, 0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97,
  98, 108, 101, 82, 101, 115, 117, 108, 116, 2, 0, 0, 0, 0, 0, 17, 0, 0, 0, 86,
  105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0,
  0, 0, 0, 0, 1, 0, 0, 0, 5, 0, 0, 0, 66, 108, 111, 99, 107, 4, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 1, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116,
  105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 79, 112, 46, 76, 105, 116, 101, 114, 97,
  108, 2, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 11, 0, 0, 0, 84, 101, 114, 109, 46, 82,
  101, 116, 117, 114, 110, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 0, 0, 0, 0, 0,
  0, 0, 2, 0, 0, 0, 13, 0, 0, 0, 73, 110, 118, 97, 114, 105, 97, 110, 116, 68,
  101, 99, 108, 3, 0, 0, 0, 0, 0, 5, 0, 0, 0, 116, 114, 117, 116, 104, 2, 0, 0, 0,
  13, 0, 0, 0, 73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108, 3, 0, 1,
  0, 0, 0, 9, 0, 0, 0, 102, 97, 108, 115, 101, 104, 111, 111, 100, 3, 0, 0, 0, 19,
  0, 0, 0, 80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114, 101, 109,
  101, 110, 116, 115, 1, 0, 0, 0, 0, 0
]

end CanonicalInvariantFixtureV1

private def testEvalInvariantABI : IO Unit := do
  let encoded ← expectOk "public-invariant-abi golden encode"
    (encodeSemanticProgramDataV1 CanonicalInvariantFixtureV1.data)
  expect (CanonicalInvariantFixtureV1.canonicalBytes.size == 1235)
    "public invariant ABI golden must remain exactly 1235 bytes"
  expect (bytesEqual encoded CanonicalInvariantFixtureV1.canonicalBytes)
    "public invariant ABI production encoding must match the exact 1235-byte golden"
  let carrier ← encodeCarrier "public-invariant-abi" CanonicalInvariantFixtureV1.data
  let selectedState := CanonicalInvariantFixtureV1.selectedState
  expect (evalInvariantV1 carrier 0 selectedState == .returnedTrue)
    "ordinal 0: selected invariant returns true through PureCall closure"
  expect (evalInvariantV1 carrier 1 selectedState == .returnedFalse)
    "ordinal 1: selected invariant returns false"
  expect (evalInvariantV1 carrier 2 selectedState == .trapped)
    "out-of-range invariant ordinal maps to trapped"
  match admitReferenceProgramSliceV1 carrier with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError (
      "unrelated Principal declaration must remain outside whole-program engineering admission")

  let runTerminal (label name : String) (root : CallableV1)
      (want : InvariantEvalResultV1) : IO Unit := do
    let terminalBase ← emptyData name
    let terminalCarrier ← encodeCarrier label {
      terminalBase with
      types := #[{ id := 0, name := none, shape := .bool },
                 { id := 1, name := none, shape := .unit }]
      callables := #[entryGate 0 1, root]
      invariants := #[{ id := 0, name, callableId := 1 }]
    }
    expect (evalInvariantV1 terminalCarrier 0 evalState == want)
      s!"{label}: terminal result mapping"
  runTerminal "checked-failure" "checkedFailure"
    (invariantCallable 1 "checkedFailure"
      #[boolLiteral 0 false, instruction none (.assert_ 0 none #[])]
      (.return_ (some 0)) 4) .reverted
  runTerminal "explicit-trap" "explicitTrap"
    (invariantCallable 1 "explicitTrap" #[] (.trap .unreachable) 2) .trapped

  let uninitialized : LogicalStateV1 := { selectedState with initialized := false }
  let malformed : LogicalStateV1 :=
    { initialized := true, canonicalValues := ByteArray.mk #[0] }
  let trailingBytes := selectedState.canonicalValues.append (ByteArray.mk #[0xff])
  let trailing : LogicalStateV1 :=
    { initialized := true, canonicalValues := trailingBytes }
  let noncanonicalBytes := (u32le 1).append (ByteArray.mk #[2])
  let noncanonical : LogicalStateV1 :=
    { initialized := true, canonicalValues := noncanonicalBytes }
  let badStates : Array (String × LogicalStateV1) := #[
    ("uninitialized", uninitialized), ("malformed", malformed),
    ("trailing", trailing), ("noncanonical", noncanonical)]
  for pair in badStates do
    expect (evalInvariantV1 carrier 0 pair.2 == .trapped)
      s!"{pair.1} state maps to trapped"

  -- The carrier representation is public, but validation remains fail closed.
  let malformedProgram : SemanticProgramV1 := ⟨ByteArray.empty⟩
  let noncanonicalProgram : SemanticProgramV1 :=
    ⟨carrier.canonicalBytes.append (ByteArray.mk #[0])⟩
  expect (evalInvariantV1 malformedProgram 0 selectedState == .trapped)
    "malformed program carrier maps to trapped"
  expect (evalInvariantV1 noncanonicalProgram 0 selectedState == .trapped)
    "trailing/noncanonical program carrier maps to trapped"

  let first := evalInvariantV1 carrier 0 selectedState
  for _ in [:8] do
    expect (evalInvariantV1 carrier 0 selectedState == first)
      "public invariant evaluator deterministic repeat"

/-! ### deterministic repeat -/

private def testDeterministicRepeat : IO Unit := do
  let carrier ← programWithInit "Determinism"
  let a ← expectOk "initial a" (initialLogicalStateV1 carrier)
  let b ← expectOk "initial b" (initialLogicalStateV1 carrier)
  expect (a.initialized == b.initialized) "deterministic initialized"
  expect (bytesEqual a.canonicalValues b.canonicalValues)
    "deterministic canonicalValues"
  for pair in expectedDefaults do
    let typeId := pair.1
    let d1 ← expectOk s!"def1 {typeId}" (defaultValueV1 carrier typeId)
    let d2 ← expectOk s!"def2 {typeId}" (defaultValueV1 carrier typeId)
    expect (bytesEqual d1 d2) s!"deterministic defaultValue typeId={typeId}"
    expect (bytesEqual d1 pair.2) s!"stable expected default typeId={typeId}"
  let data ← expectOk "validate" (validateSemanticProgramV1 carrier)
  let slots ← expectOk "decode" (decodeLogicalStateValuesV1 data a)
  let e1 ← expectOk "enc1" (encodeLogicalStateValuesV1 data false slots)
  let e2 ← expectOk "enc2" (encodeLogicalStateValuesV1 data false slots)
  expect (e1.initialized == e2.initialized) "deterministic encode flag"
  expect (bytesEqual e1.canonicalValues e2.canonicalValues)
    "deterministic encode bytes"
  expect (stateConformsBoolV1 carrier a == stateConformsBoolV1 carrier b)
    "deterministic conforms on repeated initial"

/-- Suite entry (engineering only — not formal TST-SEM). -/
def run : IO Unit := do
  testDefaultValueAllShapes
  testInitialLogicalState
  testStateConforms
  testDecodeEncodeRoundtrip
  testDecodeEncodeNegatives
  testEvalInvariantABI
  testDeterministicRepeat
  IO.println "Tests.Semantic.InvariantABI: engineering suite finished"

end Tests.Semantic.InvariantABI
