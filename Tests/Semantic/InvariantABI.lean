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

  N5b: invariant fixtures remain free of `Op.ContextRead` / `Op.Commit`
  (Wire structure forbids them on roots and reachable pureFn closure).
  Product ContextRead/Commit step traces live in `Tests.Semantic.ReferenceV1`.

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

def boolType : TypeDeclV1 := { id := 0, name := none, shape := .bool }

/-- The unrelated Principal declaration pins selected-closure rather than
    whole-program admission. -/
def principalType : TypeDeclV1 := { id := 1, name := none, shape := .principal }

def unitType : TypeDeclV1 := { id := 2, name := none, shape := .unit }

/-- The exact type table exercised by the selected invariant. -/
def types : Array TypeDeclV1 := #[boolType, principalType, unitType]

def logicalStateDecl : StateDeclV1 :=
  { id := 0, name := "flag", typeId := 0, visibility := .public_ }

def gateBlock : BlockV1 :=
  { id := 0, params := #[], instructions := #[], terminator := .return_ none }

def gate : CallableV1 := entryGate 0 2

def leafInstruction : InstructionV1 := boolLiteral 0 true

def leafBlock : BlockV1 := {
  id := 0
  params := #[]
  instructions := #[leafInstruction]
  terminator := .return_ (some 0)
}

def leaf : CallableV1 := {
  id := 1
  kind := .pureFn
  name := some "truthLeaf"
  params := #[]
  result := { typeId := 0, visibility := .public_ }
  entryBlock := 0
  blocks := #[leafBlock]
  loopBounds := #[]
  invariantSteps := some 3
}

/-- Selected invariant root. Its exact cost is
    root(1 + PureCall + return) + leaf(3) = 6. -/
def truthInstruction : InstructionV1 :=
  instruction (some (valueDef 0 0)) (.pureCall 1 #[])

def truthBlock : BlockV1 := {
  id := 0
  params := #[]
  instructions := #[truthInstruction]
  terminator := .return_ (some 0)
}

def truth : CallableV1 :=
  invariantCallable 2 "truth"
    #[truthInstruction] (.return_ (some 0)) 6

def falsehoodInstruction : InstructionV1 := boolLiteral 0 false

def falsehoodBlock : BlockV1 := {
  id := 0
  params := #[]
  instructions := #[falsehoodInstruction]
  terminator := .return_ (some 0)
}

def falsehood : CallableV1 :=
  invariantCallable 3 "falsehood" #[falsehoodInstruction]
    (.return_ (some 0)) 3

def truthDecl : InvariantDeclV1 := { id := 0, name := "truth", callableId := 2 }

def falsehoodDecl : InvariantDeclV1 :=
  { id := 1, name := "falsehood", callableId := 3 }

def invariants : Array InvariantDeclV1 := #[truthDecl, falsehoodDecl]

/-- Closed semantic data used by both the runtime ABI suite and the kernel
    carrier proof. This is data only; carrier bytes remain under the sole
    production encoder/decoder authorities. -/
def data : SemanticProgramDataV1 := {
  qualifiedName
  types
  constants := #[]
  logicalState := #[logicalStateDecl]
  events := #[]
  errors := #[]
  callables := #[gate, leaf, truth, falsehood]
  invariants
  requirements := { items := #[] }
}

/-- The concrete fixture closes the sole production structure prelude: root
    shape, contiguous table IDs, and shallow declaration references. This is
    intentionally not a claim that the later type/value/CFG/requirement gates
    have completed. -/
theorem structurePrelude_data :
    validateSemanticProgramStructurePreludeV1 data = .ok () := by
  have hQualifiedName : 2 ≤ qualifiedName.components.toArray.size := by decide
  simp [validateSemanticProgramStructurePreludeV1, checkTableIdsV1,
    validateProgramQualifiedNameShapeV1, hQualifiedName, data, types, boolType,
    principalType, unitType, logicalStateDecl, gate, entryGate, leaf, truth,
    invariantCallable, falsehood, invariants, truthDecl, falsehoodDecl,
    checkTypeShapeRefs, checkTypeIdInRange, checkCallableIdInRange,
    checkIdEqualsIndex, Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- The concrete primitive type table passes the next sole production phase:
    each declaration obeys the named rule and its exact shape/catalog gate. -/
theorem typesStructure_data :
    validateTypesStructureV1 data.types = .ok () := by
  simp [validateTypesStructureV1, validateTypeDeclShapeV1,
    validateTypeDeclNamedRuleV1, data, types, boolType, principalType, unitType,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- All three fixture declarations are anonymous, so the first production
    TypeKey subphase closes without any named declaration appearing after the
    anonymous suffix has begun. -/
theorem typeKeyNamedPrefix_data :
    validateNamedPrefixRankV1 data.types = .ok () := by
  simp [validateNamedPrefixRankV1, data, types, boolType, principalType,
    unitType, Pure.pure, Except.pure, Bind.bind, Except.bind]

private def boolTypeShapeBytes : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0]

private def principalTypeShapeBytes : ByteArray :=
  ByteArray.mk #[14, 0, 0, 0, 84, 121, 112, 101, 46, 80, 114, 105, 110, 99,
    105, 112, 97, 108, 0, 0]

private def unitTypeShapeBytes : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 85, 110, 105, 116, 0, 0]

private theorem encodeTypeShape_bool_fixture :
    encodeTypeShapeV1 (.bool : TypeShapeV1) = .ok boolTypeShapeBytes := by
  change encodeNullary "Type.Bool" = .ok boolTypeShapeBytes
  rw [encodeNullary_eq_okV1 "Type.Bool" (by decide) (by decide) (by decide)]
  congr 1

private theorem encodeTypeShape_principal_fixture :
    encodeTypeShapeV1 (.principal : TypeShapeV1) = .ok principalTypeShapeBytes := by
  change encodeNullary "Type.Principal" = .ok principalTypeShapeBytes
  rw [encodeNullary_eq_okV1 "Type.Principal" (by decide) (by decide) (by decide)]
  congr 1

private theorem encodeTypeShape_unit_fixture :
    encodeTypeShapeV1 (.unit : TypeShapeV1) = .ok unitTypeShapeBytes := by
  change encodeNullary "Type.Unit" = .ok unitTypeShapeBytes
  rw [encodeNullary_eq_okV1 "Type.Unit" (by decide) (by decide) (by decide)]
  congr 1

private theorem compare_bool_principal_fixture :
    compareByteArrayLex boolTypeShapeBytes principalTypeShapeBytes = .lt := by
  rw [compareByteArrayLex]
  apply compareByteArrayLexLoopV1_eq_lt
  · decide
  · decide

private theorem compare_principal_unit_fixture :
    compareByteArrayLex principalTypeShapeBytes unitTypeShapeBytes = .gt := by
  rw [compareByteArrayLex]
  apply compareByteArrayLexLoopV1_eq_gt
  · decide
  · decide

private theorem compare_bool_unit_fixture :
    compareByteArrayLex boolTypeShapeBytes unitTypeShapeBytes = .lt := by
  rw [compareByteArrayLex]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 0 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 1 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 2 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 3 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 4 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 5 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 6 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 7 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 8 (by decide) (by decide)]
  apply compareByteArrayLexLoopV1_eq_lt
  · decide
  · decide

/-- The three distinct primitive declarations pass the exact production
    TypeShape encoding and bounded byte-comparison uniqueness path. -/
theorem typeKeyPrimitiveLeaf_data :
    validatePrimitiveAnonymousTypeKeyUniquenessV1 data.types = .ok () := by
  simp [validatePrimitiveAnonymousTypeKeyUniquenessV1, data, types, boolType,
    principalType, unitType, encodeTypeShape_bool_fixture,
    encodeTypeShape_principal_fixture, encodeTypeShape_unit_fixture,
    compare_bool_principal_fixture, compare_bool_unit_fixture,
    compare_principal_unit_fixture, Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- No fixture declaration is an anonymous Array/Map/Option container, so the
    production recursive structural-class subphase has an empty domain. -/
theorem typeKeyRecursiveAnonymous_data :
    validateRecursiveAnonymousTypeKeyUniquenessV1 data.types = .ok () := by
  simp [validateRecursiveAnonymousTypeKeyUniquenessV1, data, types, boolType,
    principalType, unitType, Pure.pure, Except.pure]

/-- Primitive-only fixture declarations contribute no edge source to the
    production Option-removed TypeId graph. -/
theorem typeKeyNamedBodyCycle_data :
    validateNamedBodyOptionCycleLegalityV1 data.types = .ok () := by
  simp [validateNamedBodyOptionCycleLegalityV1, data, types, boolType,
    principalType, unitType, Pure.pure, Except.pure]

/-- All four exact production TypeKey subphases now compose successfully for
    the canonical fixture. -/
theorem typeKeyPhases_data :
    validateTypeKeyPhasesV1 data.types = .ok () := by
  apply validateTypeKeyPhasesV1_eq_ok_of_phases
  · exact typeKeyNamedPrefix_data
  · exact typeKeyPrimitiveLeaf_data
  · exact typeKeyRecursiveAnonymous_data
  · exact typeKeyNamedBodyCycle_data

/-- The fixture has no named Struct/Enum declarations, so the exact production
    named-TypeDecl uniqueness phase checks an empty name array. -/
theorem namedTypeNames_data :
    validateNamedTypeNameUniquenessV1 data.types = .ok () := by
  simp [validateNamedTypeNameUniquenessV1, checkUniqueDeclarationNamesV1,
    data, types, boolType, principalType, unitType, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

/-- The fixture's empty constants table preserves the full production
    canonical-value work budget. -/
theorem constantsValueBytes_data :
    validateConstantsValueBytesV1 data.types data.constants
      maxCanonicalProgramBytes = .ok maxCanonicalProgramBytes := by
  simp [validateConstantsValueBytesV1, data, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

/-- The production callable traversal encounters exactly the truth-leaf and
    falsehood Bool literals, consuming two work units for each in source order. -/
theorem callablesValueBytes_data :
    validateCallablesValueBytesV1 data.types data.callables
      maxCanonicalProgramBytes = .ok (maxCanonicalProgramBytes - 4) := by
  have htrue :
      validateOpValueBytesV1 types
        (.literal 0 (ByteArray.mk #[1])) maxCanonicalProgramBytes =
        .ok (maxCanonicalProgramBytes - 2) := by
    apply validateOpValueBytesV1_literal_bool_eq_ok types 0 boolType 1
    · rfl
    · rfl
    · exact Or.inr rfl
    · decide
  have hfalse :
      validateOpValueBytesV1 types
        (.literal 0 (ByteArray.mk #[0])) (maxCanonicalProgramBytes - 2) =
        .ok ((maxCanonicalProgramBytes - 2) - 2) := by
    apply validateOpValueBytesV1_literal_bool_eq_ok types 0 boolType 0
    · rfl
    · rfl
    · exact Or.inl rfl
    · decide
  have hpure (budget : Nat) :
      validateOpValueBytesV1 types (.pureCall 1 #[]) budget = .ok budget := by
    rfl
  simp [validateCallablesValueBytesV1, data, gate, entryGate, leaf,
    leafBlock, leafInstruction, truth, invariantCallable, truthInstruction,
    instruction, valueDef, falsehood, falsehoodInstruction, boolLiteral,
    validateTerminatorValueBytesV1, htrue, hfalse, hpure, Pure.pure,
    Except.pure, Bind.bind, Except.bind]
  omega

/-- Empty constants expose no duplicate declaration-name candidate. -/
theorem constantNames_data :
    validateConstantNameUniquenessV1 data.constants = .ok () := by
  simp [validateConstantNameUniquenessV1, checkUniqueDeclarationNamesV1, data,
    Pure.pure, Except.pure]

/-- The fixture's singleton logical-state table takes the production
    empty/singleton exact-name success path. -/
theorem logicalStateNames_data :
    validateLogicalStateNameUniquenessV1 data.logicalState = .ok () := by
  simp [validateLogicalStateNameUniquenessV1, checkUniqueDeclarationNamesV1,
    data, logicalStateDecl, Pure.pure, Except.pure]

/-- Empty event and error tables expose no duplicate declaration names. -/
theorem eventNames_data :
    validateEventNameUniquenessV1 data.events = .ok () := by
  simp [validateEventNameUniquenessV1, checkUniqueDeclarationNamesV1, data,
    Pure.pure, Except.pure]

theorem errorNames_data :
    validateErrorNameUniquenessV1 data.errors = .ok () := by
  simp [validateErrorNameUniquenessV1, checkUniqueDeclarationNamesV1, data,
    Pure.pure, Except.pure]

/-- With no event/error declarations, the production per-declaration
    interface-field uniqueness walker performs no checks. -/
theorem interfaceFieldNames_data :
    validateInterfaceFieldNameUniquenessV1 data.events data.errors = .ok () := by
  simp [validateInterfaceFieldNameUniquenessV1, data, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

def selectedState : LogicalStateV1 := {
  initialized := true
  canonicalValues := stateSlot (ByteArray.mk #[0])
}

/-- Exact magic segment of the concrete canonical carrier. -/
def canonicalMagicSpine : TransparentByteSpineV1 :=
  [112, 102, 46, 115, 101, 109, 97, 110, 116, 105, 99, 46, 118, 49, 0]

/-- Exact root tagged-header segment: u32 tag length, ASCII tag, u16 count. -/
def canonicalRootHeaderSpine : TransparentByteSpineV1 :=
  [20, 0, 0, 0, 83, 101, 109, 97, 110, 116, 105, 99, 80, 114, 111, 103,
    114, 97, 109, 46, 68, 97, 116, 97, 9, 0]

/-- Exact two-component QualifiedName field at root offset 41. -/
def canonicalQualifiedNameSpine : TransparentByteSpineV1 := [
  2, 0, 0, 0, 5, 0, 0, 0, 84, 101, 115, 116, 115, 18, 0, 0,
  0, 80, 117, 98, 108, 105, 99, 73, 110, 118, 97, 114, 105, 97, 110, 116, 65,
  66, 73
]

/-- Exact three-element TypeDecl array at root offset 76. -/
def canonicalTypesSpine : TransparentByteSpineV1 := [
  3, 0, 0, 0, 8, 0, 0, 0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0,
  0, 0, 0, 0, 0, 9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0,
  8, 0, 0, 0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0, 1, 0, 0, 0, 0, 14,
  0, 0, 0, 84, 121, 112, 101, 46, 80, 114, 105, 110, 99, 105, 112, 97, 108, 0,
  0, 8, 0, 0, 0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0, 2, 0, 0, 0, 0, 9,
  0, 0, 0, 84, 121, 112, 101, 46, 85, 110, 105, 116, 0, 0
]

/-- Exact empty constants table at root offset 187. -/
def canonicalConstantsSpine : TransparentByteSpineV1 := [0, 0, 0, 0]

/-- Exact singleton StateDecl array at root offset 191. -/
def canonicalLogicalStateSpine : TransparentByteSpineV1 := [
  1, 0, 0, 0, 9, 0, 0, 0, 83, 116, 97, 116, 101, 68, 101, 99, 108, 4, 0,
  0, 0, 0, 0, 4, 0, 0, 0, 102, 108, 97, 103, 0, 0, 0, 0, 17, 0, 0, 0,
  86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99,
  0, 0
]

/-- Exact empty events and errors tables at root offsets 249 and 253. -/
def canonicalEmptyInterfacesSpine : TransparentByteSpineV1 :=
  [0, 0, 0, 0, 0, 0, 0, 0]

/-- Exact four-element callables count at root offset 257. -/
def canonicalCallablesHeaderSpine : TransparentByteSpineV1 := [4, 0, 0, 0]

/-- Exact first callable (`entry_gate`) at root offset 261. -/
def canonicalEntryGateSpine : TransparentByteSpineV1 := [
  8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9, 0, 0, 0, 0, 0,
  14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 46, 69, 110, 116, 114, 121,
  0, 0, 1, 10, 0, 0, 0, 101, 110, 116, 114, 121, 95, 103, 97, 116, 101, 0,
  0, 0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115,
  117, 108, 116, 2, 0, 2, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98,
  105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0,
  1, 0, 0, 0, 5, 0, 0, 0, 66, 108, 111, 99, 107, 4, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 11, 0, 0, 0, 84, 101, 114, 109, 46,
  82, 101, 116, 117, 114, 110, 1, 0, 0, 0, 0, 0, 0, 0
]

/-- Exact second callable (`truthLeaf`) at root offset 419. -/
def canonicalTruthLeafSpine : TransparentByteSpineV1 := [
  8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9, 0, 1, 0, 0, 0,
  15, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 46, 80, 117, 114, 101, 70,
  110, 0, 0, 1, 9, 0, 0, 0, 116, 114, 117, 116, 104, 76, 101, 97, 102, 0,
  0, 0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115,
  117, 108, 116, 2, 0, 0, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98,
  105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0,
  1, 0, 0, 0, 5, 0, 0, 0, 66, 108, 111, 99, 107, 4, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 1, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114,
  117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101,
  68, 101, 102, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 79,
  112, 46, 76, 105, 116, 101, 114, 97, 108, 2, 0, 0, 0, 0, 0, 1, 0, 0,
  0, 1, 11, 0, 0, 0, 84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110, 1,
  0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 0, 0, 0, 0, 0, 0,
  0
]

/-- Exact third callable (`truth`) at root offset 654. -/
def canonicalTruthSpine : TransparentByteSpineV1 := [
  8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9, 0, 2, 0, 0, 0,
  18, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114,
  105, 97, 110, 116, 0, 0, 1, 5, 0, 0, 0, 116, 114, 117, 116, 104, 0, 0,
  0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117,
  108, 116, 2, 0, 0, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98, 105,
  108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0, 1,
  0, 0, 0, 5, 0, 0, 0, 66, 108, 111, 99, 107, 4, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 1, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117,
  99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68,
  101, 102, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11, 0, 0, 0, 79, 112,
  46, 80, 117, 114, 101, 67, 97, 108, 108, 2, 0, 1, 0, 0, 0, 0, 0, 0,
  0, 11, 0, 0, 0, 84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110, 1, 0,
  1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 6, 0, 0, 0, 0, 0, 0, 0
]

/-- Exact fourth callable (`falsehood`) at root offset 888. -/
def canonicalFalsehoodSpine : TransparentByteSpineV1 := [
  8, 0, 0, 0, 67, 97, 108, 108, 97, 98,
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
  0, 0
]

/-- Exact two-element InvariantDecl array at root offset 1126. -/
def canonicalInvariantsSpine : TransparentByteSpineV1 := [
  2, 0, 0, 0, 13, 0, 0, 0, 73, 110, 118, 97, 114, 105, 97, 110, 116, 68,
  101, 99, 108, 3, 0, 0, 0, 0, 0, 5, 0, 0, 0, 116, 114, 117, 116, 104, 2, 0, 0, 0,
  13, 0, 0, 0, 73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108, 3, 0, 1,
  0, 0, 0, 9, 0, 0, 0, 102, 97, 108, 115, 101, 104, 111, 111, 100, 3, 0, 0, 0
]

/-- Exact empty ProgramRequirements record at root offset 1206. -/
def canonicalRequirementsSpine : TransparentByteSpineV1 := [
  19,
  0, 0, 0, 80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114, 101, 109,
  101, 110, 116, 115, 1, 0, 0, 0, 0, 0
]

/-- Exact 1235-byte production encoding of `data` as the transparent proof
    spine. This explicit segmented golden is independent of encoder
    computation and is not a second runtime decoder. -/
def canonicalSpine : TransparentByteSpineV1 :=
  canonicalMagicSpine ++ canonicalRootHeaderSpine ++ canonicalQualifiedNameSpine ++
    canonicalTypesSpine ++ canonicalConstantsSpine ++ canonicalLogicalStateSpine ++
    canonicalEmptyInterfacesSpine ++ canonicalCallablesHeaderSpine ++ canonicalEntryGateSpine ++
    canonicalTruthLeafSpine ++ canonicalTruthSpine ++ canonicalFalsehoodSpine ++
    canonicalInvariantsSpine ++ canonicalRequirementsSpine

def canonicalBytes : ByteArray := ByteArray.mk canonicalSpine.toArray

theorem canonicalSpine_length : canonicalSpine.length = 1235 := by
  rfl

theorem consumeMagic_canonicalBytes :
    consumeMagic semanticProgramMagicV1 (start canonicalBytes) =
      .ok ((), ⟨canonicalBytes, 15, 0⟩) := by
  apply consumeMagic_eq_of_bytesV1
  change consumeMagicBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 0
      (ByteArray.mk canonicalMagicSpine.toArray) = .ok 15
  rw [consumeMagicBytesAtV1_refinesSpine]
  unfold consumeMagicSpineBytesV1 takeSpineBytesV1 spineRemainingV1
  rw [canonicalSpine_length]
  rfl

theorem expectRootTag_canonicalBytes :
    expectTag "SemanticProgram.Data" 9 ⟨canonicalBytes, 15, 1⟩ =
      .ok ((), ⟨canonicalBytes, 41, 1⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 15
      (ByteArray.mk [83, 101, 109, 97, 110, 116, 105, 99, 80, 114, 111, 103,
        114, 97, 109, 46, 68, 97, 116, 97].toArray) 9 = .ok 41
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

theorem readQualifiedNameCount_canonicalBytes :
    readArrayCountAtV1 canonicalBytes 41 256 = .ok (2, 45) := by
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 41 256 = .ok (2, 45)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

theorem readQualifiedNameTestsBytes_canonicalBytes :
    readSizedBytesAtV1 canonicalBytes 45 maxStringBytes =
      .ok (ByteArray.mk [84, 101, 115, 116, 115].toArray, 54) := by
  change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 45 maxStringBytes =
    .ok (ByteArray.mk [84, 101, 115, 116, 115].toArray, 54)
  apply readSizedBytesAtV1_eq_of_spine
  apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [84, 101, 115, 116, 115]
      45 maxStringBytes 5 49
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]
    rfl

theorem readQualifiedNamePublicInvariantABIBytes_canonicalBytes :
    readSizedBytesAtV1 canonicalBytes 54 maxStringBytes =
      .ok (ByteArray.mk
        [80, 117, 98, 108, 105, 99, 73, 110, 118, 97, 114, 105, 97, 110, 116,
          65, 66, 73].toArray, 76) := by
  change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 54 maxStringBytes =
    .ok (ByteArray.mk
      [80, 117, 98, 108, 105, 99, 73, 110, 118, 97, 114, 105, 97, 110, 116,
        65, 66, 73].toArray, 76)
  apply readSizedBytesAtV1_eq_of_spine
  apply readSizedSpineBytesV1_eq_of_parts canonicalSpine
      [80, 117, 98, 108, 105, 99, 73, 110, 118, 97, 114, 105, 97, 110, 116,
        65, 66, 73] 54 maxStringBytes 18 58
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]
    rfl

private theorem decodeTestsV1_of_read (bytes : ByteArray)
    (hread : readSizedBytesAtV1 bytes 45 maxStringBytes =
      .ok (ByteArray.mk [84, 101, 115, 116, 115].toArray, 54)) :
    decodeString ⟨bytes, 45, 1⟩ = .ok ("Tests", ⟨bytes, 54, 1⟩) := by
  apply decodeString_eq_of_valueV1 _ _ _ _ hread
  · rfl
  · apply ProofForgeV2.Core.Unicode.requireNfc_eq_ok_of_isAscii
    rfl

private theorem decodePublicInvariantABIV1_of_read (bytes : ByteArray)
    (hread : readSizedBytesAtV1 bytes 54 maxStringBytes =
      .ok (ByteArray.mk
        [80, 117, 98, 108, 105, 99, 73, 110, 118, 97, 114, 105, 97, 110, 116,
          65, 66, 73].toArray, 76)) :
    decodeString ⟨bytes, 54, 1⟩ =
      .ok ("PublicInvariantABI", ⟨bytes, 76, 1⟩) := by
  apply decodeString_eq_of_valueV1 _ _ _ _ hread
  · rfl
  · apply ProofForgeV2.Core.Unicode.requireNfc_eq_ok_of_isAscii
    rfl

theorem decodeQualifiedName_canonicalBytes :
    decodeQualifiedName ⟨canonicalBytes, 41, 1⟩ =
      .ok (qualifiedName, ⟨canonicalBytes, 76, 1⟩) := by
  apply decodeQualifiedName_eq_of_arrayV1
  · apply decodeArray_twoV1
    · exact readQualifiedNameCount_canonicalBytes
    · exact decodeTestsV1_of_read canonicalBytes readQualifiedNameTestsBytes_canonicalBytes
    · exact decodePublicInvariantABIV1_of_read canonicalBytes
        readQualifiedNamePublicInvariantABIBytes_canonicalBytes
  · rfl

theorem readTypesCount_canonicalBytes :
    readArrayCountAtV1 canonicalBytes 76 maxTableElements = .ok (3, 80) := by
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 76 maxTableElements =
    .ok (3, 80)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

private theorem expectTypeDeclV1_canonicalBytes (offset after : Nat)
    (hspine : expectTaggedHeaderSpineV1 canonicalSpine offset
      [84, 121, 112, 101, 68, 101, 99, 108] 3 = .ok after) :
    expectTag "TypeDecl" 3 ⟨canonicalBytes, offset, 2⟩ =
      .ok ((), ⟨canonicalBytes, after, 2⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) offset
      (ByteArray.mk [84, 121, 112, 101, 68, 101, 99, 108].toArray) 3 = .ok after
  rw [expectTaggedHeaderBytesAtV1_refinesSpine, hspine]

theorem expectTypeDecl0_canonicalBytes :
    expectTag "TypeDecl" 3 ⟨canonicalBytes, 80, 2⟩ =
      .ok ((), ⟨canonicalBytes, 94, 2⟩) := by
  apply expectTypeDeclV1_canonicalBytes
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

theorem expectTypeDecl1_canonicalBytes :
    expectTag "TypeDecl" 3 ⟨canonicalBytes, 114, 2⟩ =
      .ok ((), ⟨canonicalBytes, 128, 2⟩) := by
  apply expectTypeDeclV1_canonicalBytes
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

theorem expectTypeDecl2_canonicalBytes :
    expectTag "TypeDecl" 3 ⟨canonicalBytes, 153, 2⟩ =
      .ok ((), ⟨canonicalBytes, 167, 2⟩) := by
  apply expectTypeDeclV1_canonicalBytes
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeTypeIdV1_canonicalBytes (offset after id : Nat)
    (hspine : readSpineU32leV1 canonicalSpine offset = .ok (UInt32.ofNat id, after)) :
    decodeU32le ⟨canonicalBytes, offset, 2⟩ =
      .ok (UInt32.ofNat id, ⟨canonicalBytes, after, 2⟩) := by
  apply decodeU32le_eq_of_readV1
  change readU32leAtV1 (ByteArray.mk canonicalSpine.toArray) offset =
    .ok (UInt32.ofNat id, after)
  rw [readU32leAtV1_refinesSpine, hspine]

theorem decodeTypeId0_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 94, 2⟩ = .ok (0, ⟨canonicalBytes, 98, 2⟩) := by
  apply decodeTypeIdV1_canonicalBytes
  rfl

theorem decodeTypeId1_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 128, 2⟩ = .ok (1, ⟨canonicalBytes, 132, 2⟩) := by
  apply decodeTypeIdV1_canonicalBytes
  rfl

theorem decodeTypeId2_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 167, 2⟩ = .ok (2, ⟨canonicalBytes, 171, 2⟩) := by
  apply decodeTypeIdV1_canonicalBytes
  rfl

private theorem decodeNoTypeNameV1_canonicalBytes (offset : Nat)
    (hspine : readSpineByteV1 canonicalSpine offset = .ok 0) :
    decodeOption decodeString ⟨canonicalBytes, offset, 2⟩ =
      .ok (none, ⟨canonicalBytes, offset + 1, 2⟩) := by
  apply decodeOption_noneV1
  apply decodeU8_eq_of_readV1
  change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) offset = .ok 0
  rw [readByteAtV1_refinesSpine, hspine]

theorem decodeNoTypeName0_canonicalBytes :
    decodeOption decodeString ⟨canonicalBytes, 98, 2⟩ =
      .ok (none, ⟨canonicalBytes, 99, 2⟩) := by
  simpa using decodeNoTypeNameV1_canonicalBytes 98 (by rfl)

theorem decodeNoTypeName1_canonicalBytes :
    decodeOption decodeString ⟨canonicalBytes, 132, 2⟩ =
      .ok (none, ⟨canonicalBytes, 133, 2⟩) := by
  simpa using decodeNoTypeNameV1_canonicalBytes 132 (by rfl)

theorem decodeNoTypeName2_canonicalBytes :
    decodeOption decodeString ⟨canonicalBytes, 171, 2⟩ =
      .ok (none, ⟨canonicalBytes, 172, 2⟩) := by
  simpa using decodeNoTypeNameV1_canonicalBytes 171 (by rfl)

private theorem decodeTypeShapeTagV1_canonicalBytes (offset after : Nat)
    (raw : TransparentByteSpineV1) (value : String)
    (hspine : readTagSpineBytesV1 canonicalSpine offset = .ok (raw, after))
    (hutf8 : String.fromUTF8? (ByteArray.mk raw.toArray) = some value)
    (hascii : isAsciiTagV1 value = true) :
    decodeTag ⟨canonicalBytes, offset, 3⟩ =
      .ok (value, ⟨canonicalBytes, after, 3⟩) := by
  apply decodeTag_eq_of_valueV1 _ _ _ _ _ hutf8 hascii
  change readTagBytesAtV1 (ByteArray.mk canonicalSpine.toArray) offset =
    .ok (ByteArray.mk raw.toArray, after)
  exact readTagBytesAtV1_eq_of_spine canonicalSpine raw offset after hspine

private theorem decodeZeroFieldCountV1_canonicalBytes (offset after : Nat)
    (hspine : readSpineU16leV1 canonicalSpine offset = .ok (0, after)) :
    decodeFieldCount 0 ⟨canonicalBytes, offset, 3⟩ =
      .ok ((), ⟨canonicalBytes, after, 3⟩) := by
  have hread : readU16leAtV1 canonicalBytes offset = .ok (0, after) := by
    change readU16leAtV1 (ByteArray.mk canonicalSpine.toArray) offset = .ok (0, after)
    rw [readU16leAtV1_refinesSpine, hspine]
  have hresult := decodeFieldCount_eq_of_readU16leV1 0
    ⟨canonicalBytes, offset, 3⟩ 0 after hread
  simpa using hresult

theorem decodeTypeShapeBool_canonicalBytes :
    decodeTypeShapeV1 ⟨canonicalBytes, 99, 2⟩ =
      .ok (.bool, ⟨canonicalBytes, 114, 2⟩) := by
  refine decodeTypeShapeV1_eq_of_bodyV1 ⟨canonicalBytes, 99, 2⟩ .bool
    ⟨canonicalBytes, 114, 3⟩ ?_ ?_
  · decide
  · apply decodeTypeShapeBodyV1_bool
    · apply decodeTypeShapeTagV1_canonicalBytes 99 112
        [84, 121, 112, 101, 46, 66, 111, 111, 108] "Type.Bool"
      · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
        rw [canonicalSpine_length]
        rfl
      · rfl
      · rfl
    · apply decodeZeroFieldCountV1_canonicalBytes
      rfl

theorem decodeTypeShapePrincipal_canonicalBytes :
    decodeTypeShapeV1 ⟨canonicalBytes, 133, 2⟩ =
      .ok (.principal, ⟨canonicalBytes, 153, 2⟩) := by
  refine decodeTypeShapeV1_eq_of_bodyV1 ⟨canonicalBytes, 133, 2⟩ .principal
    ⟨canonicalBytes, 153, 3⟩ ?_ ?_
  · decide
  · apply decodeTypeShapeBodyV1_principal
    · apply decodeTypeShapeTagV1_canonicalBytes 133 151
        [84, 121, 112, 101, 46, 80, 114, 105, 110, 99, 105, 112, 97, 108]
        "Type.Principal"
      · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
        rw [canonicalSpine_length]
        rfl
      · rfl
      · rfl
    · apply decodeZeroFieldCountV1_canonicalBytes
      rfl

theorem decodeTypeShapeUnit_canonicalBytes :
    decodeTypeShapeV1 ⟨canonicalBytes, 172, 2⟩ =
      .ok (.unit, ⟨canonicalBytes, 187, 2⟩) := by
  refine decodeTypeShapeV1_eq_of_bodyV1 ⟨canonicalBytes, 172, 2⟩ .unit
    ⟨canonicalBytes, 187, 3⟩ ?_ ?_
  · decide
  · apply decodeTypeShapeBodyV1_unit
    · apply decodeTypeShapeTagV1_canonicalBytes 172 185
        [84, 121, 112, 101, 46, 85, 110, 105, 116] "Type.Unit"
      · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
        rw [canonicalSpine_length]
        rfl
      · rfl
      · rfl
    · apply decodeZeroFieldCountV1_canonicalBytes
      rfl

theorem decodeTypeDecl0_canonicalBytes :
    decodeTypeDeclV1 ⟨canonicalBytes, 80, 1⟩ =
      .ok (boolType, ⟨canonicalBytes, 114, 1⟩) := by
  refine decodeTypeDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 80, 1⟩ boolType
    ⟨canonicalBytes, 114, 2⟩ (by decide) ?_
  apply decodeTypeDeclBodyV1_eq_of_fields
  · exact expectTypeDecl0_canonicalBytes
  · exact decodeTypeId0_canonicalBytes
  · exact decodeNoTypeName0_canonicalBytes
  · exact decodeTypeShapeBool_canonicalBytes

theorem decodeTypeDecl1_canonicalBytes :
    decodeTypeDeclV1 ⟨canonicalBytes, 114, 1⟩ =
      .ok (principalType, ⟨canonicalBytes, 153, 1⟩) := by
  refine decodeTypeDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 114, 1⟩ principalType
    ⟨canonicalBytes, 153, 2⟩ (by decide) ?_
  apply decodeTypeDeclBodyV1_eq_of_fields
  · exact expectTypeDecl1_canonicalBytes
  · exact decodeTypeId1_canonicalBytes
  · exact decodeNoTypeName1_canonicalBytes
  · exact decodeTypeShapePrincipal_canonicalBytes

theorem decodeTypeDecl2_canonicalBytes :
    decodeTypeDeclV1 ⟨canonicalBytes, 153, 1⟩ =
      .ok (unitType, ⟨canonicalBytes, 187, 1⟩) := by
  refine decodeTypeDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 153, 1⟩ unitType
    ⟨canonicalBytes, 187, 2⟩ (by decide) ?_
  apply decodeTypeDeclBodyV1_eq_of_fields
  · exact expectTypeDecl2_canonicalBytes
  · exact decodeTypeId2_canonicalBytes
  · exact decodeNoTypeName2_canonicalBytes
  · exact decodeTypeShapeUnit_canonicalBytes

theorem decodeTypes_canonicalBytes :
    decodeArray maxTableElements decodeTypeDeclV1 ⟨canonicalBytes, 76, 1⟩ =
      .ok (types, ⟨canonicalBytes, 187, 1⟩) := by
  have h := decodeArray_threeV1 maxTableElements decodeTypeDeclV1
    ⟨canonicalBytes, 76, 1⟩ 80 boolType principalType unitType
    ⟨canonicalBytes, 114, 1⟩ ⟨canonicalBytes, 153, 1⟩ ⟨canonicalBytes, 187, 1⟩
    readTypesCount_canonicalBytes decodeTypeDecl0_canonicalBytes
    decodeTypeDecl1_canonicalBytes decodeTypeDecl2_canonicalBytes
  simpa [types] using h

theorem decodeConstants_canonicalBytes :
    decodeArray maxTableElements decodeConstantV1 ⟨canonicalBytes, 187, 1⟩ =
      .ok (#[], ⟨canonicalBytes, 191, 1⟩) := by
  apply decodeArray_zeroV1
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 187 maxTableElements =
    .ok (0, 191)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

theorem readLogicalStateCount_canonicalBytes :
    readArrayCountAtV1 canonicalBytes 191 maxTableElements = .ok (1, 195) := by
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 191 maxTableElements =
    .ok (1, 195)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

theorem expectStateDecl_canonicalBytes :
    expectTag "StateDecl" 4 ⟨canonicalBytes, 195, 2⟩ =
      .ok ((), ⟨canonicalBytes, 210, 2⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 195
      (ByteArray.mk [83, 116, 97, 116, 101, 68, 101, 99, 108].toArray) 4 = .ok 210
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

theorem decodeStateId_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 210, 2⟩ =
      .ok (0, ⟨canonicalBytes, 214, 2⟩) := by
  apply decodeTypeIdV1_canonicalBytes
  rfl

theorem readStateNameBytes_canonicalBytes :
    readSizedBytesAtV1 canonicalBytes 214 maxStringBytes =
      .ok (ByteArray.mk [102, 108, 97, 103].toArray, 222) := by
  change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 214 maxStringBytes =
    .ok (ByteArray.mk [102, 108, 97, 103].toArray, 222)
  apply readSizedBytesAtV1_eq_of_spine
  apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [102, 108, 97, 103]
      214 maxStringBytes 4 218
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]
    rfl

private theorem decodeFlagV1_of_read (bytes : ByteArray)
    (hread : readSizedBytesAtV1 bytes 214 maxStringBytes =
      .ok (ByteArray.mk [102, 108, 97, 103].toArray, 222)) :
    decodeString ⟨bytes, 214, 2⟩ = .ok ("flag", ⟨bytes, 222, 2⟩) := by
  apply decodeString_eq_of_valueV1 _ _ _ _ hread
  · rfl
  · apply ProofForgeV2.Core.Unicode.requireNfc_eq_ok_of_isAscii
    rfl

theorem decodeStateName_canonicalBytes :
    decodeString ⟨canonicalBytes, 214, 2⟩ =
      .ok ("flag", ⟨canonicalBytes, 222, 2⟩) := by
  exact decodeFlagV1_of_read canonicalBytes readStateNameBytes_canonicalBytes

theorem decodeStateTypeId_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 222, 2⟩ =
      .ok (0, ⟨canonicalBytes, 226, 2⟩) := by
  apply decodeTypeIdV1_canonicalBytes
  rfl

theorem decodeStateVisibility_canonicalBytes :
    decodeVisibilityV1 ⟨canonicalBytes, 226, 2⟩ =
      .ok (.public_, ⟨canonicalBytes, 249, 2⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 226, 2⟩ .public_
    ⟨canonicalBytes, 249, 3⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · apply decodeTypeShapeTagV1_canonicalBytes 226 247
      [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105,
        99] "Visibility.Public"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeZeroFieldCountV1_canonicalBytes
    rfl

theorem decodeStateDecl_canonicalBytes :
    decodeStateDeclV1 ⟨canonicalBytes, 195, 1⟩ =
      .ok (logicalStateDecl, ⟨canonicalBytes, 249, 1⟩) := by
  refine decodeStateDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 195, 1⟩ logicalStateDecl
    ⟨canonicalBytes, 249, 2⟩ (by decide) ?_
  apply decodeStateDeclBodyV1_eq_of_fields
  · exact expectStateDecl_canonicalBytes
  · exact decodeStateId_canonicalBytes
  · exact decodeStateName_canonicalBytes
  · exact decodeStateTypeId_canonicalBytes
  · exact decodeStateVisibility_canonicalBytes

theorem decodeLogicalState_canonicalBytes :
    decodeArray maxTableElements decodeStateDeclV1 ⟨canonicalBytes, 191, 1⟩ =
      .ok (#[logicalStateDecl], ⟨canonicalBytes, 249, 1⟩) := by
  exact decodeArray_oneV1 maxTableElements decodeStateDeclV1
    ⟨canonicalBytes, 191, 1⟩ 195 logicalStateDecl ⟨canonicalBytes, 249, 1⟩
    readLogicalStateCount_canonicalBytes decodeStateDecl_canonicalBytes

theorem decodeEvents_canonicalBytes :
    decodeArray maxTableElements decodeEventDeclV1 ⟨canonicalBytes, 249, 1⟩ =
      .ok (#[], ⟨canonicalBytes, 253, 1⟩) := by
  apply decodeArray_zeroV1
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 249 maxTableElements =
    .ok (0, 253)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

theorem decodeErrors_canonicalBytes :
    decodeArray maxTableElements decodeErrorDeclV1 ⟨canonicalBytes, 253, 1⟩ =
      .ok (#[], ⟨canonicalBytes, 257, 1⟩) := by
  apply decodeArray_zeroV1
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 253 maxTableElements =
    .ok (0, 257)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

private theorem decodeCanonicalTagV1 (offset after nesting : Nat)
    (raw : TransparentByteSpineV1) (value : String)
    (hspine : readTagSpineBytesV1 canonicalSpine offset = .ok (raw, after))
    (hutf8 : String.fromUTF8? (ByteArray.mk raw.toArray) = some value)
    (hascii : isAsciiTagV1 value = true) :
    decodeTag ⟨canonicalBytes, offset, nesting⟩ =
      .ok (value, ⟨canonicalBytes, after, nesting⟩) := by
  apply decodeTag_eq_of_valueV1 _ _ _ _ _ hutf8 hascii
  change readTagBytesAtV1 (ByteArray.mk canonicalSpine.toArray) offset =
    .ok (ByteArray.mk raw.toArray, after)
  exact readTagBytesAtV1_eq_of_spine canonicalSpine raw offset after hspine

private theorem decodeCanonicalZeroFieldsV1 (offset after nesting : Nat)
    (hspine : readSpineU16leV1 canonicalSpine offset = .ok (0, after)) :
    decodeFieldCount 0 ⟨canonicalBytes, offset, nesting⟩ =
      .ok ((), ⟨canonicalBytes, after, nesting⟩) := by
  have hread : readU16leAtV1 canonicalBytes offset = .ok (0, after) := by
    change readU16leAtV1 (ByteArray.mk canonicalSpine.toArray) offset = .ok (0, after)
    rw [readU16leAtV1_refinesSpine, hspine]
  simpa using decodeFieldCount_eq_of_readU16leV1 0
    ⟨canonicalBytes, offset, nesting⟩ 0 after hread

private theorem decodeCanonicalU32V1 (offset after nesting value : Nat)
    (hspine : readSpineU32leV1 canonicalSpine offset =
      .ok (UInt32.ofNat value, after)) :
    decodeU32le ⟨canonicalBytes, offset, nesting⟩ =
      .ok (UInt32.ofNat value, ⟨canonicalBytes, after, nesting⟩) := by
  apply decodeU32le_eq_of_readV1
  change readU32leAtV1 (ByteArray.mk canonicalSpine.toArray) offset =
    .ok (UInt32.ofNat value, after)
  rw [readU32leAtV1_refinesSpine, hspine]

theorem readCallablesCount_canonicalBytes :
    readArrayCountAtV1 canonicalBytes 257 maxTableElements = .ok (4, 261) := by
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 257 maxTableElements =
    .ok (4, 261)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

theorem expectGateCallable_canonicalBytes :
    expectTag "Callable" 9 ⟨canonicalBytes, 261, 2⟩ =
      .ok ((), ⟨canonicalBytes, 275, 2⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 261
      (ByteArray.mk [67, 97, 108, 108, 97, 98, 108, 101].toArray) 9 = .ok 275
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

theorem decodeGateId_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 275, 2⟩ =
      .ok (0, ⟨canonicalBytes, 279, 2⟩) := by
  apply decodeCanonicalU32V1
  rfl

theorem decodeGateKind_canonicalBytes :
    decodeCallableKindV1 ⟨canonicalBytes, 279, 2⟩ =
      .ok (.entry, ⟨canonicalBytes, 299, 2⟩) := by
  refine decodeCallableKindV1_eq_of_bodyV1 ⟨canonicalBytes, 279, 2⟩ .entry
    ⟨canonicalBytes, 299, 3⟩ (by decide) ?_
  apply decodeCallableKindBodyV1_entry
  · apply decodeCanonicalTagV1 279 297 3
      [67, 97, 108, 108, 97, 98, 108, 101, 46, 69, 110, 116, 114, 121]
      "Callable.Entry"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeCanonicalZeroFieldsV1
    rfl

theorem readGateNameBytes_canonicalBytes :
    readSizedBytesAtV1 canonicalBytes 300 maxStringBytes =
      .ok (ByteArray.mk [101, 110, 116, 114, 121, 95, 103, 97, 116, 101].toArray,
        314) := by
  change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 300 maxStringBytes =
    .ok (ByteArray.mk [101, 110, 116, 114, 121, 95, 103, 97, 116, 101].toArray, 314)
  apply readSizedBytesAtV1_eq_of_spine
  apply readSizedSpineBytesV1_eq_of_parts canonicalSpine
      [101, 110, 116, 114, 121, 95, 103, 97, 116, 101] 300 maxStringBytes 10 304
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]
    rfl

private theorem decodeEntryGateNameV1_of_read (bytes : ByteArray)
    (hread : readSizedBytesAtV1 bytes 300 maxStringBytes =
      .ok (ByteArray.mk [101, 110, 116, 114, 121, 95, 103, 97, 116, 101].toArray,
        314)) :
    decodeString ⟨bytes, 300, 2⟩ = .ok ("entry_gate", ⟨bytes, 314, 2⟩) := by
  apply decodeString_eq_of_valueV1 _ _ _ _ hread
  · rfl
  · apply ProofForgeV2.Core.Unicode.requireNfc_eq_ok_of_isAscii
    rfl

theorem decodeGateName_canonicalBytes :
    decodeOption decodeString ⟨canonicalBytes, 299, 2⟩ =
      .ok (some "entry_gate", ⟨canonicalBytes, 314, 2⟩) := by
  apply decodeOption_someV1 decodeString ⟨canonicalBytes, 299, 2⟩
    ⟨canonicalBytes, 300, 2⟩ ⟨canonicalBytes, 314, 2⟩ "entry_gate"
  · apply decodeU8_eq_of_readV1
    change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) 299 = .ok 1
    rw [readByteAtV1_refinesSpine]
    rfl
  · exact decodeEntryGateNameV1_of_read canonicalBytes readGateNameBytes_canonicalBytes

theorem expectGateResult_canonicalBytes :
    expectTag "CallableResult" 2 ⟨canonicalBytes, 318, 3⟩ =
      .ok ((), ⟨canonicalBytes, 338, 3⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 318
      (ByteArray.mk [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108,
        116].toArray) 2 = .ok 338
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

theorem decodeGateResultVisibility_canonicalBytes :
    decodeVisibilityV1 ⟨canonicalBytes, 342, 3⟩ =
      .ok (.public_, ⟨canonicalBytes, 365, 3⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 342, 3⟩ .public_
    ⟨canonicalBytes, 365, 4⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · apply decodeCanonicalTagV1 342 363 4
      [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105,
        99] "Visibility.Public"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeCanonicalZeroFieldsV1
    rfl

theorem decodeGateResult_canonicalBytes :
    decodeCallableResultV1 ⟨canonicalBytes, 318, 2⟩ =
      .ok ({ typeId := 2, visibility := .public_ }, ⟨canonicalBytes, 365, 2⟩) := by
  refine decodeCallableResultV1_eq_of_bodyV1 ⟨canonicalBytes, 318, 2⟩
    { typeId := 2, visibility := .public_ } ⟨canonicalBytes, 365, 3⟩ (by decide) ?_
  apply decodeCallableResultBodyV1_eq_of_fields
  · exact expectGateResult_canonicalBytes
  · apply decodeCanonicalU32V1
    rfl
  · exact decodeGateResultVisibility_canonicalBytes

theorem expectGateBlock_canonicalBytes :
    expectTag "Block" 4 ⟨canonicalBytes, 373, 3⟩ =
      .ok ((), ⟨canonicalBytes, 384, 3⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 373
      (ByteArray.mk [66, 108, 111, 99, 107].toArray) 4 = .ok 384
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

theorem decodeGateReturn_canonicalBytes :
    decodeTerminatorV1 ⟨canonicalBytes, 396, 3⟩ =
      .ok (.return_ none, ⟨canonicalBytes, 414, 3⟩) := by
  apply decodeTerminatorV1_return ⟨canonicalBytes, 396, 3⟩
    ⟨canonicalBytes, 411, 4⟩ ⟨canonicalBytes, 413, 4⟩
    ⟨canonicalBytes, 414, 4⟩ none (by decide)
  · apply decodeCanonicalTagV1 396 411 4
      [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] "Term.Return"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · have hread : readU16leAtV1 canonicalBytes 411 = .ok (1, 413) := by
      change readU16leAtV1 (ByteArray.mk canonicalSpine.toArray) 411 = .ok (1, 413)
      rw [readU16leAtV1_refinesSpine]
      rfl
    have hresult := decodeFieldCount_eq_of_readU16leV1 1
      ⟨canonicalBytes, 411, 4⟩ 1 413 hread
    simpa using hresult
  · apply decodeOption_noneV1
    apply decodeU8_eq_of_readV1
    change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) 413 = .ok 0
    rw [readByteAtV1_refinesSpine]
    rfl

theorem decodeGateBlock_canonicalBytes :
    decodeBlockV1 ⟨canonicalBytes, 373, 2⟩ =
      .ok (gateBlock, ⟨canonicalBytes, 414, 2⟩) := by
  apply decodeBlockV1_emptyV1 ⟨canonicalBytes, 373, 2⟩
    ⟨canonicalBytes, 384, 3⟩ ⟨canonicalBytes, 388, 3⟩
    ⟨canonicalBytes, 414, 3⟩ 392 396 0 (.return_ none) (by decide)
  · exact expectGateBlock_canonicalBytes
  · apply decodeCanonicalU32V1
    rfl
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 388
      maxArrayElements = .ok (0, 392)
    rw [readArrayCountAtV1_refinesSpine]
    rfl
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 392
      maxArrayElements = .ok (0, 396)
    rw [readArrayCountAtV1_refinesSpine]
    rfl
  · exact decodeGateReturn_canonicalBytes

theorem decodeGate_canonicalBytes :
    decodeCallableV1 ⟨canonicalBytes, 261, 1⟩ =
      .ok (gate, ⟨canonicalBytes, 419, 1⟩) := by
  have h := decodeCallableV1_singleBlockV1
    ⟨canonicalBytes, 261, 1⟩ ⟨canonicalBytes, 275, 2⟩
    ⟨canonicalBytes, 279, 2⟩ ⟨canonicalBytes, 299, 2⟩
    ⟨canonicalBytes, 314, 2⟩ ⟨canonicalBytes, 365, 2⟩
    ⟨canonicalBytes, 369, 2⟩ ⟨canonicalBytes, 414, 2⟩
    ⟨canonicalBytes, 419, 2⟩ 318 373 418 0 0 .entry (some "entry_gate")
    { typeId := 2, visibility := .public_ } gateBlock none (by decide)
    expectGateCallable_canonicalBytes decodeGateId_canonicalBytes decodeGateKind_canonicalBytes
    decodeGateName_canonicalBytes (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 314
        maxArrayElements = .ok (0, 318)
      rw [readArrayCountAtV1_refinesSpine]
      rfl)
    decodeGateResult_canonicalBytes (decodeCanonicalU32V1 365 369 2 0 (by rfl))
    (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 369
        maxArrayElements = .ok (1, 373)
      rw [readArrayCountAtV1_refinesSpine]
      rfl)
    decodeGateBlock_canonicalBytes (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 414
        maxArrayElements = .ok (0, 418)
      rw [readArrayCountAtV1_refinesSpine]
      rfl)
    (by
      apply decodeOption_noneV1
      apply decodeU8_eq_of_readV1
      change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) 418 = .ok 0
      rw [readByteAtV1_refinesSpine]
      rfl)
  simpa [gate, entryGate, gateBlock] using h

private theorem decodeCanonicalU64V1 (offset after nesting value : Nat)
    (hspine : readSpineU64leV1 canonicalSpine offset =
      .ok (UInt64.ofNat value, after)) :
    decodeU64le ⟨canonicalBytes, offset, nesting⟩ =
      .ok (UInt64.ofNat value, ⟨canonicalBytes, after, nesting⟩) := by
  apply decodeU64le_eq_of_readV1
  change readU64leAtV1 (ByteArray.mk canonicalSpine.toArray) offset =
    .ok (UInt64.ofNat value, after)
  rw [readU64leAtV1_refinesSpine, hspine]

theorem expectLeafCallable_canonicalBytes :
    expectTag "Callable" 9 ⟨canonicalBytes, 419, 2⟩ =
      .ok ((), ⟨canonicalBytes, 433, 2⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 419
      (ByteArray.mk [67, 97, 108, 108, 97, 98, 108, 101].toArray) 9 = .ok 433
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

theorem decodeLeafKind_canonicalBytes :
    decodeCallableKindV1 ⟨canonicalBytes, 437, 2⟩ =
      .ok (.pureFn, ⟨canonicalBytes, 458, 2⟩) := by
  refine decodeCallableKindV1_eq_of_bodyV1 ⟨canonicalBytes, 437, 2⟩ .pureFn
    ⟨canonicalBytes, 458, 3⟩ (by decide) ?_
  apply decodeCallableKindBodyV1_pureFn
  · apply decodeCanonicalTagV1 437 456 3
      [67, 97, 108, 108, 97, 98, 108, 101, 46, 80, 117, 114, 101, 70, 110]
      "Callable.PureFn"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeCanonicalZeroFieldsV1
    rfl

theorem readLeafNameBytes_canonicalBytes :
    readSizedBytesAtV1 canonicalBytes 459 maxStringBytes =
      .ok (ByteArray.mk [116, 114, 117, 116, 104, 76, 101, 97, 102].toArray, 472) := by
  change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 459 maxStringBytes =
    .ok (ByteArray.mk [116, 114, 117, 116, 104, 76, 101, 97, 102].toArray, 472)
  apply readSizedBytesAtV1_eq_of_spine
  apply readSizedSpineBytesV1_eq_of_parts canonicalSpine
      [116, 114, 117, 116, 104, 76, 101, 97, 102] 459 maxStringBytes 9 463
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]
    rfl

private theorem decodeTruthLeafNameV1_of_read (bytes : ByteArray)
    (hread : readSizedBytesAtV1 bytes 459 maxStringBytes =
      .ok (ByteArray.mk [116, 114, 117, 116, 104, 76, 101, 97, 102].toArray, 472)) :
    decodeString ⟨bytes, 459, 2⟩ = .ok ("truthLeaf", ⟨bytes, 472, 2⟩) := by
  apply decodeString_eq_of_valueV1 _ _ _ _ hread
  · rfl
  · apply ProofForgeV2.Core.Unicode.requireNfc_eq_ok_of_isAscii
    rfl

theorem decodeLeafName_canonicalBytes :
    decodeOption decodeString ⟨canonicalBytes, 458, 2⟩ =
      .ok (some "truthLeaf", ⟨canonicalBytes, 472, 2⟩) := by
  apply decodeOption_someV1 decodeString ⟨canonicalBytes, 458, 2⟩
    ⟨canonicalBytes, 459, 2⟩ ⟨canonicalBytes, 472, 2⟩ "truthLeaf"
  · apply decodeU8_eq_of_readV1
    change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) 458 = .ok 1
    rw [readByteAtV1_refinesSpine]
    rfl
  · exact decodeTruthLeafNameV1_of_read canonicalBytes readLeafNameBytes_canonicalBytes

theorem expectLeafResult_canonicalBytes :
    expectTag "CallableResult" 2 ⟨canonicalBytes, 476, 3⟩ =
      .ok ((), ⟨canonicalBytes, 496, 3⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 476
      (ByteArray.mk [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108,
        116].toArray) 2 = .ok 496
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

theorem decodeLeafResultVisibility_canonicalBytes :
    decodeVisibilityV1 ⟨canonicalBytes, 500, 3⟩ =
      .ok (.public_, ⟨canonicalBytes, 523, 3⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 500, 3⟩ .public_
    ⟨canonicalBytes, 523, 4⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · apply decodeCanonicalTagV1 500 521 4
      [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105,
        99] "Visibility.Public"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeCanonicalZeroFieldsV1
    rfl

theorem decodeLeafResult_canonicalBytes :
    decodeCallableResultV1 ⟨canonicalBytes, 476, 2⟩ =
      .ok ({ typeId := 0, visibility := .public_ }, ⟨canonicalBytes, 523, 2⟩) := by
  refine decodeCallableResultV1_eq_of_bodyV1 ⟨canonicalBytes, 476, 2⟩
    { typeId := 0, visibility := .public_ } ⟨canonicalBytes, 523, 3⟩ (by decide) ?_
  apply decodeCallableResultBodyV1_eq_of_fields
  · exact expectLeafResult_canonicalBytes
  · apply decodeCanonicalU32V1
    rfl
  · exact decodeLeafResultVisibility_canonicalBytes

theorem expectLeafBlock_canonicalBytes :
    expectTag "Block" 4 ⟨canonicalBytes, 531, 3⟩ =
      .ok ((), ⟨canonicalBytes, 542, 3⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 531
      (ByteArray.mk [66, 108, 111, 99, 107].toArray) 4 = .ok 542
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

theorem expectLeafInstruction_canonicalBytes :
    expectTag "Instruction" 2 ⟨canonicalBytes, 554, 4⟩ =
      .ok ((), ⟨canonicalBytes, 571, 4⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 554
      (ByteArray.mk [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110].toArray) 2 =
    .ok 571
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

theorem expectLeafValueDef_canonicalBytes :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 572, 5⟩ =
      .ok ((), ⟨canonicalBytes, 586, 5⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 572
      (ByteArray.mk [86, 97, 108, 117, 101, 68, 101, 102].toArray) 2 = .ok 586
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

theorem decodeLeafValueDef_canonicalBytes :
    decodeValueDefV1 ⟨canonicalBytes, 572, 4⟩ =
      .ok ({ valueId := 0, typeId := 0 }, ⟨canonicalBytes, 594, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 572, 4⟩
    ⟨canonicalBytes, 586, 5⟩ ⟨canonicalBytes, 590, 5⟩
    ⟨canonicalBytes, 594, 5⟩ 0 0 (by decide)
  · exact expectLeafValueDef_canonicalBytes
  · apply decodeCanonicalU32V1
    rfl
  · apply decodeCanonicalU32V1
    rfl

theorem decodeLeafResultDef_canonicalBytes :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 571, 4⟩ =
      .ok (some { valueId := 0, typeId := 0 }, ⟨canonicalBytes, 594, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 571, 4⟩
    ⟨canonicalBytes, 572, 4⟩ ⟨canonicalBytes, 594, 4⟩
    { valueId := 0, typeId := 0 }
  · apply decodeU8_eq_of_readV1
    change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) 571 = .ok 1
    rw [readByteAtV1_refinesSpine]
    rfl
  · exact decodeLeafValueDef_canonicalBytes

theorem decodeLeafLiteralBytes_canonicalBytes :
    decodeByteArray maxCanonicalProgramBytes ⟨canonicalBytes, 614, 5⟩ =
      .ok (ByteArray.mk #[1], ⟨canonicalBytes, 619, 5⟩) := by
  have hread : readSizedBytesAtV1 canonicalBytes 614 maxCanonicalProgramBytes =
      .ok (ByteArray.mk #[1], 619) := by
    change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 614
      maxCanonicalProgramBytes = .ok (ByteArray.mk [1].toArray, 619)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [1] 614
      maxCanonicalProgramBytes 1 618
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
  simp only [decodeByteArray, hread, Bind.bind, Pure.pure, Except.bind, Except.pure]

theorem decodeLeafLiteral_canonicalBytes :
    decodeSemanticOpV1 ⟨canonicalBytes, 594, 4⟩ =
      .ok (.literal 0 (ByteArray.mk #[1]), ⟨canonicalBytes, 619, 4⟩) := by
  apply decodeSemanticOpV1_literal ⟨canonicalBytes, 594, 4⟩
    ⟨canonicalBytes, 608, 5⟩ ⟨canonicalBytes, 610, 5⟩
    ⟨canonicalBytes, 614, 5⟩ ⟨canonicalBytes, 619, 5⟩ 0 (ByteArray.mk #[1])
    (by decide)
  · apply decodeCanonicalTagV1 594 608 5
      [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] "Op.Literal"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · have hread : readU16leAtV1 canonicalBytes 608 = .ok (2, 610) := by
      change readU16leAtV1 (ByteArray.mk canonicalSpine.toArray) 608 = .ok (2, 610)
      rw [readU16leAtV1_refinesSpine]
      rfl
    have hresult := decodeFieldCount_eq_of_readU16leV1 2
      ⟨canonicalBytes, 608, 5⟩ 2 610 hread
    simpa using hresult
  · apply decodeCanonicalU32V1
    rfl
  · exact decodeLeafLiteralBytes_canonicalBytes

theorem decodeLeafInstruction_canonicalBytes :
    decodeInstructionV1 ⟨canonicalBytes, 554, 3⟩ =
      .ok (leafInstruction, ⟨canonicalBytes, 619, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 554, 3⟩
    ⟨canonicalBytes, 571, 4⟩ ⟨canonicalBytes, 594, 4⟩
    ⟨canonicalBytes, 619, 4⟩ (some { valueId := 0, typeId := 0 })
    (.literal 0 (ByteArray.mk #[1])) (by decide) expectLeafInstruction_canonicalBytes
    decodeLeafResultDef_canonicalBytes decodeLeafLiteral_canonicalBytes
  simpa [leafInstruction, boolLiteral, instruction, valueDef] using h

theorem decodeLeafReturn_canonicalBytes :
    decodeTerminatorV1 ⟨canonicalBytes, 619, 3⟩ =
      .ok (.return_ (some 0), ⟨canonicalBytes, 641, 3⟩) := by
  apply decodeTerminatorV1_return ⟨canonicalBytes, 619, 3⟩
    ⟨canonicalBytes, 634, 4⟩ ⟨canonicalBytes, 636, 4⟩
    ⟨canonicalBytes, 641, 4⟩ (some 0) (by decide)
  · apply decodeCanonicalTagV1 619 634 4
      [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] "Term.Return"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · have hread : readU16leAtV1 canonicalBytes 634 = .ok (1, 636) := by
      change readU16leAtV1 (ByteArray.mk canonicalSpine.toArray) 634 = .ok (1, 636)
      rw [readU16leAtV1_refinesSpine]
      rfl
    have hresult := decodeFieldCount_eq_of_readU16leV1 1
      ⟨canonicalBytes, 634, 4⟩ 1 636 hread
    simpa using hresult
  · apply decodeOption_someV1 decodeU32le ⟨canonicalBytes, 636, 4⟩
      ⟨canonicalBytes, 637, 4⟩ ⟨canonicalBytes, 641, 4⟩ 0
    · apply decodeU8_eq_of_readV1
      change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) 636 = .ok 1
      rw [readByteAtV1_refinesSpine]
      rfl
    · apply decodeCanonicalU32V1
      rfl

theorem decodeLeafBlock_canonicalBytes :
    decodeBlockV1 ⟨canonicalBytes, 531, 2⟩ =
      .ok (leafBlock, ⟨canonicalBytes, 641, 2⟩) := by
  apply decodeBlockV1_oneInstructionV1 ⟨canonicalBytes, 531, 2⟩
    ⟨canonicalBytes, 542, 3⟩ ⟨canonicalBytes, 546, 3⟩
    ⟨canonicalBytes, 619, 3⟩ ⟨canonicalBytes, 641, 3⟩
    550 554 0 leafInstruction (.return_ (some 0)) (by decide)
  · exact expectLeafBlock_canonicalBytes
  · apply decodeCanonicalU32V1
    rfl
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 546
      maxArrayElements = .ok (0, 550)
    rw [readArrayCountAtV1_refinesSpine]
    rfl
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 550
      maxArrayElements = .ok (1, 554)
    rw [readArrayCountAtV1_refinesSpine]
    rfl
  · exact decodeLeafInstruction_canonicalBytes
  · exact decodeLeafReturn_canonicalBytes

theorem decodeLeafSteps_canonicalBytes :
    decodeOption decodeU64le ⟨canonicalBytes, 645, 2⟩ =
      .ok (some 3, ⟨canonicalBytes, 654, 2⟩) := by
  apply decodeOption_someV1 decodeU64le ⟨canonicalBytes, 645, 2⟩
    ⟨canonicalBytes, 646, 2⟩ ⟨canonicalBytes, 654, 2⟩ 3
  · apply decodeU8_eq_of_readV1
    change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) 645 = .ok 1
    rw [readByteAtV1_refinesSpine]
    rfl
  · apply decodeCanonicalU64V1
    rfl

theorem decodeLeaf_canonicalBytes :
    decodeCallableV1 ⟨canonicalBytes, 419, 1⟩ =
      .ok (leaf, ⟨canonicalBytes, 654, 1⟩) := by
  have h := decodeCallableV1_singleBlockV1
    ⟨canonicalBytes, 419, 1⟩ ⟨canonicalBytes, 433, 2⟩
    ⟨canonicalBytes, 437, 2⟩ ⟨canonicalBytes, 458, 2⟩
    ⟨canonicalBytes, 472, 2⟩ ⟨canonicalBytes, 523, 2⟩
    ⟨canonicalBytes, 527, 2⟩ ⟨canonicalBytes, 641, 2⟩
    ⟨canonicalBytes, 654, 2⟩ 476 531 645 1 0 .pureFn (some "truthLeaf")
    { typeId := 0, visibility := .public_ } leafBlock (some 3) (by decide)
    expectLeafCallable_canonicalBytes (decodeCanonicalU32V1 433 437 2 1 (by rfl))
    decodeLeafKind_canonicalBytes decodeLeafName_canonicalBytes (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 472
        maxArrayElements = .ok (0, 476)
      rw [readArrayCountAtV1_refinesSpine]
      rfl)
    decodeLeafResult_canonicalBytes (decodeCanonicalU32V1 523 527 2 0 (by rfl))
    (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 527
        maxArrayElements = .ok (1, 531)
      rw [readArrayCountAtV1_refinesSpine]
      rfl)
    decodeLeafBlock_canonicalBytes (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 641
        maxArrayElements = .ok (0, 645)
      rw [readArrayCountAtV1_refinesSpine]
      rfl)
    decodeLeafSteps_canonicalBytes
  simpa [leaf] using h

theorem decodeTruthKind_canonicalBytes :
    decodeCallableKindV1 ⟨canonicalBytes, 672, 2⟩ =
      .ok (.invariant, ⟨canonicalBytes, 696, 2⟩) := by
  refine decodeCallableKindV1_eq_of_bodyV1 ⟨canonicalBytes, 672, 2⟩ .invariant
    ⟨canonicalBytes, 696, 3⟩ (by decide) ?_
  apply decodeCallableKindBodyV1_invariant
  · apply decodeCanonicalTagV1 672 694 3
      [67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114, 105, 97,
        110, 116] "Callable.Invariant"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeCanonicalZeroFieldsV1
    rfl

theorem readTruthNameBytes_canonicalBytes :
    readSizedBytesAtV1 canonicalBytes 697 maxStringBytes =
      .ok (ByteArray.mk [116, 114, 117, 116, 104].toArray, 706) := by
  change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 697 maxStringBytes =
    .ok (ByteArray.mk [116, 114, 117, 116, 104].toArray, 706)
  apply readSizedBytesAtV1_eq_of_spine
  apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [116, 114, 117, 116, 104]
      697 maxStringBytes 5 701
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]
    rfl

private theorem decodeTruthNameV1_of_read (bytes : ByteArray)
    (hread : readSizedBytesAtV1 bytes 697 maxStringBytes =
      .ok (ByteArray.mk [116, 114, 117, 116, 104].toArray, 706)) :
    decodeString ⟨bytes, 697, 2⟩ = .ok ("truth", ⟨bytes, 706, 2⟩) := by
  apply decodeString_eq_of_valueV1 _ _ _ _ hread
  · rfl
  · apply ProofForgeV2.Core.Unicode.requireNfc_eq_ok_of_isAscii
    rfl

theorem decodeTruthName_canonicalBytes :
    decodeOption decodeString ⟨canonicalBytes, 696, 2⟩ =
      .ok (some "truth", ⟨canonicalBytes, 706, 2⟩) := by
  apply decodeOption_someV1 decodeString ⟨canonicalBytes, 696, 2⟩
    ⟨canonicalBytes, 697, 2⟩ ⟨canonicalBytes, 706, 2⟩ "truth"
  · apply decodeU8_eq_of_readV1
    change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) 696 = .ok 1
    rw [readByteAtV1_refinesSpine]
    rfl
  · exact decodeTruthNameV1_of_read canonicalBytes readTruthNameBytes_canonicalBytes

theorem decodeTruthResult_canonicalBytes :
    decodeCallableResultV1 ⟨canonicalBytes, 710, 2⟩ =
      .ok ({ typeId := 0, visibility := .public_ }, ⟨canonicalBytes, 757, 2⟩) := by
  refine decodeCallableResultV1_eq_of_bodyV1 ⟨canonicalBytes, 710, 2⟩
    { typeId := 0, visibility := .public_ } ⟨canonicalBytes, 757, 3⟩ (by decide) ?_
  apply decodeCallableResultBodyV1_eq_of_fields
  · apply expectTag_eq_of_headerV1
    change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 710
        (ByteArray.mk [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108,
          116].toArray) 2 = .ok 730
    rw [expectTaggedHeaderBytesAtV1_refinesSpine]
    unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
      spineRemainingV1 readSpineU16leV1
    rw [canonicalSpine_length]
    rfl
  · apply decodeCanonicalU32V1
    rfl
  · refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 734, 3⟩ .public_
      ⟨canonicalBytes, 757, 4⟩ (by decide) ?_
    apply decodeVisibilityBodyV1_public
    · apply decodeCanonicalTagV1 734 755 4
        [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108,
          105, 99] "Visibility.Public"
      · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
        rw [canonicalSpine_length]
        rfl
      · rfl
      · rfl
    · apply decodeCanonicalZeroFieldsV1
      rfl

theorem decodeTruthValueDef_canonicalBytes :
    decodeValueDefV1 ⟨canonicalBytes, 806, 4⟩ =
      .ok ({ valueId := 0, typeId := 0 }, ⟨canonicalBytes, 828, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 806, 4⟩
    ⟨canonicalBytes, 820, 5⟩ ⟨canonicalBytes, 824, 5⟩
    ⟨canonicalBytes, 828, 5⟩ 0 0 (by decide)
  · apply expectTag_eq_of_headerV1
    change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 806
        (ByteArray.mk [86, 97, 108, 117, 101, 68, 101, 102].toArray) 2 = .ok 820
    rw [expectTaggedHeaderBytesAtV1_refinesSpine]
    unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
      spineRemainingV1 readSpineU16leV1
    rw [canonicalSpine_length]
    rfl
  · apply decodeCanonicalU32V1
    rfl
  · apply decodeCanonicalU32V1
    rfl

theorem decodeTruthPureCall_canonicalBytes :
    decodeSemanticOpV1 ⟨canonicalBytes, 828, 4⟩ =
      .ok (.pureCall 1 #[], ⟨canonicalBytes, 853, 4⟩) := by
  apply decodeSemanticOpV1_pureCall ⟨canonicalBytes, 828, 4⟩
    ⟨canonicalBytes, 843, 5⟩ ⟨canonicalBytes, 845, 5⟩
    ⟨canonicalBytes, 849, 5⟩ ⟨canonicalBytes, 853, 5⟩ 1 #[] (by decide)
  · apply decodeCanonicalTagV1 828 843 5
      [79, 112, 46, 80, 117, 114, 101, 67, 97, 108, 108] "Op.PureCall"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · have hread : readU16leAtV1 canonicalBytes 843 = .ok (2, 845) := by
      change readU16leAtV1 (ByteArray.mk canonicalSpine.toArray) 843 = .ok (2, 845)
      rw [readU16leAtV1_refinesSpine]
      rfl
    have hresult := decodeFieldCount_eq_of_readU16leV1 2
      ⟨canonicalBytes, 843, 5⟩ 2 845 hread
    simpa using hresult
  · apply decodeCanonicalU32V1
    rfl
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 849
      maxArrayElements = .ok (0, 853)
    rw [readArrayCountAtV1_refinesSpine]
    rfl

theorem decodeTruthInstruction_canonicalBytes :
    decodeInstructionV1 ⟨canonicalBytes, 788, 3⟩ =
      .ok (truthInstruction, ⟨canonicalBytes, 853, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 788, 3⟩
    ⟨canonicalBytes, 805, 4⟩ ⟨canonicalBytes, 828, 4⟩
    ⟨canonicalBytes, 853, 4⟩ (some { valueId := 0, typeId := 0 })
    (.pureCall 1 #[]) (by decide) (by
      apply expectTag_eq_of_headerV1
      change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 788
          (ByteArray.mk [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110].toArray)
          2 = .ok 805
      rw [expectTaggedHeaderBytesAtV1_refinesSpine]
      unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
        spineRemainingV1 readSpineU16leV1
      rw [canonicalSpine_length]
      rfl)
    (by
      apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 805, 4⟩
        ⟨canonicalBytes, 806, 4⟩ ⟨canonicalBytes, 828, 4⟩
        { valueId := 0, typeId := 0 }
      · apply decodeU8_eq_of_readV1
        change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) 805 = .ok 1
        rw [readByteAtV1_refinesSpine]
        rfl
      · exact decodeTruthValueDef_canonicalBytes)
    decodeTruthPureCall_canonicalBytes
  simpa [truthInstruction, instruction, valueDef] using h

theorem decodeTruthReturn_canonicalBytes :
    decodeTerminatorV1 ⟨canonicalBytes, 853, 3⟩ =
      .ok (.return_ (some 0), ⟨canonicalBytes, 875, 3⟩) := by
  apply decodeTerminatorV1_return ⟨canonicalBytes, 853, 3⟩
    ⟨canonicalBytes, 868, 4⟩ ⟨canonicalBytes, 870, 4⟩
    ⟨canonicalBytes, 875, 4⟩ (some 0) (by decide)
  · apply decodeCanonicalTagV1 853 868 4
      [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] "Term.Return"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · have hread : readU16leAtV1 canonicalBytes 868 = .ok (1, 870) := by
      change readU16leAtV1 (ByteArray.mk canonicalSpine.toArray) 868 = .ok (1, 870)
      rw [readU16leAtV1_refinesSpine]
      rfl
    have hresult := decodeFieldCount_eq_of_readU16leV1 1
      ⟨canonicalBytes, 868, 4⟩ 1 870 hread
    simpa using hresult
  · apply decodeOption_someV1 decodeU32le ⟨canonicalBytes, 870, 4⟩
      ⟨canonicalBytes, 871, 4⟩ ⟨canonicalBytes, 875, 4⟩ 0
    · apply decodeU8_eq_of_readV1
      change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) 870 = .ok 1
      rw [readByteAtV1_refinesSpine]
      rfl
    · apply decodeCanonicalU32V1
      rfl

theorem decodeTruthBlock_canonicalBytes :
    decodeBlockV1 ⟨canonicalBytes, 765, 2⟩ =
      .ok (truthBlock, ⟨canonicalBytes, 875, 2⟩) := by
  apply decodeBlockV1_oneInstructionV1 ⟨canonicalBytes, 765, 2⟩
    ⟨canonicalBytes, 776, 3⟩ ⟨canonicalBytes, 780, 3⟩
    ⟨canonicalBytes, 853, 3⟩ ⟨canonicalBytes, 875, 3⟩
    784 788 0 truthInstruction (.return_ (some 0)) (by decide)
  · apply expectTag_eq_of_headerV1
    change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 765
        (ByteArray.mk [66, 108, 111, 99, 107].toArray) 4 = .ok 776
    rw [expectTaggedHeaderBytesAtV1_refinesSpine]
    unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
      spineRemainingV1 readSpineU16leV1
    rw [canonicalSpine_length]
    rfl
  · apply decodeCanonicalU32V1
    rfl
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 780
      maxArrayElements = .ok (0, 784)
    rw [readArrayCountAtV1_refinesSpine]
    rfl
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 784
      maxArrayElements = .ok (1, 788)
    rw [readArrayCountAtV1_refinesSpine]
    rfl
  · exact decodeTruthInstruction_canonicalBytes
  · exact decodeTruthReturn_canonicalBytes

theorem decodeTruth_canonicalBytes :
    decodeCallableV1 ⟨canonicalBytes, 654, 1⟩ =
      .ok (truth, ⟨canonicalBytes, 888, 1⟩) := by
  have h := decodeCallableV1_singleBlockV1
    ⟨canonicalBytes, 654, 1⟩ ⟨canonicalBytes, 668, 2⟩
    ⟨canonicalBytes, 672, 2⟩ ⟨canonicalBytes, 696, 2⟩
    ⟨canonicalBytes, 706, 2⟩ ⟨canonicalBytes, 757, 2⟩
    ⟨canonicalBytes, 761, 2⟩ ⟨canonicalBytes, 875, 2⟩
    ⟨canonicalBytes, 888, 2⟩ 710 765 879 2 0 .invariant (some "truth")
    { typeId := 0, visibility := .public_ } truthBlock (some 6) (by decide)
    (by
      apply expectTag_eq_of_headerV1
      change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 654
          (ByteArray.mk [67, 97, 108, 108, 97, 98, 108, 101].toArray) 9 = .ok 668
      rw [expectTaggedHeaderBytesAtV1_refinesSpine]
      unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
        spineRemainingV1 readSpineU16leV1
      rw [canonicalSpine_length]
      rfl)
    (decodeCanonicalU32V1 668 672 2 2 (by rfl)) decodeTruthKind_canonicalBytes
    decodeTruthName_canonicalBytes (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 706
        maxArrayElements = .ok (0, 710)
      rw [readArrayCountAtV1_refinesSpine]
      rfl)
    decodeTruthResult_canonicalBytes (decodeCanonicalU32V1 757 761 2 0 (by rfl))
    (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 761
        maxArrayElements = .ok (1, 765)
      rw [readArrayCountAtV1_refinesSpine]
      rfl)
    decodeTruthBlock_canonicalBytes (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 875
        maxArrayElements = .ok (0, 879)
      rw [readArrayCountAtV1_refinesSpine]
      rfl)
    (by
      apply decodeOption_someV1 decodeU64le ⟨canonicalBytes, 879, 2⟩
        ⟨canonicalBytes, 880, 2⟩ ⟨canonicalBytes, 888, 2⟩ 6
      · apply decodeU8_eq_of_readV1
        change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) 879 = .ok 1
        rw [readByteAtV1_refinesSpine]
        rfl
      · apply decodeCanonicalU64V1
        rfl)
  simpa [truth, invariantCallable, truthBlock] using h

theorem decodeFalsehoodKind_canonicalBytes :
    decodeCallableKindV1 ⟨canonicalBytes, 906, 2⟩ =
      .ok (.invariant, ⟨canonicalBytes, 930, 2⟩) := by
  refine decodeCallableKindV1_eq_of_bodyV1 ⟨canonicalBytes, 906, 2⟩ .invariant
    ⟨canonicalBytes, 930, 3⟩ (by decide) ?_
  apply decodeCallableKindBodyV1_invariant
  · apply decodeCanonicalTagV1 906 928 3
      [67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114, 105, 97,
        110, 116] "Callable.Invariant"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeCanonicalZeroFieldsV1
    rfl

theorem readFalsehoodNameBytes_canonicalBytes :
    readSizedBytesAtV1 canonicalBytes 931 maxStringBytes =
      .ok (ByteArray.mk [102, 97, 108, 115, 101, 104, 111, 111, 100].toArray, 944) := by
  change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 931 maxStringBytes =
    .ok (ByteArray.mk [102, 97, 108, 115, 101, 104, 111, 111, 100].toArray, 944)
  apply readSizedBytesAtV1_eq_of_spine
  apply readSizedSpineBytesV1_eq_of_parts canonicalSpine
      [102, 97, 108, 115, 101, 104, 111, 111, 100] 931 maxStringBytes 9 935
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]
    rfl

private theorem decodeFalsehoodNameV1_of_read (bytes : ByteArray)
    (hread : readSizedBytesAtV1 bytes 931 maxStringBytes =
      .ok (ByteArray.mk [102, 97, 108, 115, 101, 104, 111, 111, 100].toArray, 944)) :
    decodeString ⟨bytes, 931, 2⟩ = .ok ("falsehood", ⟨bytes, 944, 2⟩) := by
  apply decodeString_eq_of_valueV1 _ _ _ _ hread
  · rfl
  · apply ProofForgeV2.Core.Unicode.requireNfc_eq_ok_of_isAscii
    rfl

theorem decodeFalsehoodName_canonicalBytes :
    decodeOption decodeString ⟨canonicalBytes, 930, 2⟩ =
      .ok (some "falsehood", ⟨canonicalBytes, 944, 2⟩) := by
  apply decodeOption_someV1 decodeString ⟨canonicalBytes, 930, 2⟩
    ⟨canonicalBytes, 931, 2⟩ ⟨canonicalBytes, 944, 2⟩ "falsehood"
  · apply decodeU8_eq_of_readV1
    change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) 930 = .ok 1
    rw [readByteAtV1_refinesSpine]
    rfl
  · exact decodeFalsehoodNameV1_of_read canonicalBytes readFalsehoodNameBytes_canonicalBytes

theorem decodeFalsehoodResult_canonicalBytes :
    decodeCallableResultV1 ⟨canonicalBytes, 948, 2⟩ =
      .ok ({ typeId := 0, visibility := .public_ }, ⟨canonicalBytes, 995, 2⟩) := by
  refine decodeCallableResultV1_eq_of_bodyV1 ⟨canonicalBytes, 948, 2⟩
    { typeId := 0, visibility := .public_ } ⟨canonicalBytes, 995, 3⟩ (by decide) ?_
  apply decodeCallableResultBodyV1_eq_of_fields
  · apply expectTag_eq_of_headerV1
    change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 948
        (ByteArray.mk [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108,
          116].toArray) 2 = .ok 968
    rw [expectTaggedHeaderBytesAtV1_refinesSpine]
    unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
      spineRemainingV1 readSpineU16leV1
    rw [canonicalSpine_length]
    rfl
  · apply decodeCanonicalU32V1
    rfl
  · refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 972, 3⟩ .public_
      ⟨canonicalBytes, 995, 4⟩ (by decide) ?_
    apply decodeVisibilityBodyV1_public
    · apply decodeCanonicalTagV1 972 993 4
        [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108,
          105, 99] "Visibility.Public"
      · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
        rw [canonicalSpine_length]
        rfl
      · rfl
      · rfl
    · apply decodeCanonicalZeroFieldsV1
      rfl

theorem decodeFalsehoodValueDef_canonicalBytes :
    decodeValueDefV1 ⟨canonicalBytes, 1044, 4⟩ =
      .ok ({ valueId := 0, typeId := 0 }, ⟨canonicalBytes, 1066, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1044, 4⟩
    ⟨canonicalBytes, 1058, 5⟩ ⟨canonicalBytes, 1062, 5⟩
    ⟨canonicalBytes, 1066, 5⟩ 0 0 (by decide)
  · apply expectTag_eq_of_headerV1
    change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1044
        (ByteArray.mk [86, 97, 108, 117, 101, 68, 101, 102].toArray) 2 = .ok 1058
    rw [expectTaggedHeaderBytesAtV1_refinesSpine]
    unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
      spineRemainingV1 readSpineU16leV1
    rw [canonicalSpine_length]
    rfl
  · apply decodeCanonicalU32V1
    rfl
  · apply decodeCanonicalU32V1
    rfl

theorem decodeFalsehoodLiteral_canonicalBytes :
    decodeSemanticOpV1 ⟨canonicalBytes, 1066, 4⟩ =
      .ok (.literal 0 (ByteArray.mk #[0]), ⟨canonicalBytes, 1091, 4⟩) := by
  apply decodeSemanticOpV1_literal ⟨canonicalBytes, 1066, 4⟩
    ⟨canonicalBytes, 1080, 5⟩ ⟨canonicalBytes, 1082, 5⟩
    ⟨canonicalBytes, 1086, 5⟩ ⟨canonicalBytes, 1091, 5⟩ 0 (ByteArray.mk #[0])
    (by decide)
  · apply decodeCanonicalTagV1 1066 1080 5
      [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] "Op.Literal"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · have hread : readU16leAtV1 canonicalBytes 1080 = .ok (2, 1082) := by
      change readU16leAtV1 (ByteArray.mk canonicalSpine.toArray) 1080 = .ok (2, 1082)
      rw [readU16leAtV1_refinesSpine]
      rfl
    have hresult := decodeFieldCount_eq_of_readU16leV1 2
      ⟨canonicalBytes, 1080, 5⟩ 2 1082 hread
    simpa using hresult
  · apply decodeCanonicalU32V1
    rfl
  · have hread : readSizedBytesAtV1 canonicalBytes 1086 maxCanonicalProgramBytes =
        .ok (ByteArray.mk #[0], 1091) := by
      change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1086
        maxCanonicalProgramBytes = .ok (ByteArray.mk [0].toArray, 1091)
      apply readSizedBytesAtV1_eq_of_spine
      apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [0] 1086
        maxCanonicalProgramBytes 1 1090
      · rfl
      · decide
      · decide
      · unfold takeSpineBytesV1 spineRemainingV1
        rw [canonicalSpine_length]
        rfl
    simp only [decodeByteArray, hread, Bind.bind, Pure.pure, Except.bind, Except.pure]

theorem decodeFalsehoodInstruction_canonicalBytes :
    decodeInstructionV1 ⟨canonicalBytes, 1026, 3⟩ =
      .ok (falsehoodInstruction, ⟨canonicalBytes, 1091, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1026, 3⟩
    ⟨canonicalBytes, 1043, 4⟩ ⟨canonicalBytes, 1066, 4⟩
    ⟨canonicalBytes, 1091, 4⟩ (some { valueId := 0, typeId := 0 })
    (.literal 0 (ByteArray.mk #[0])) (by decide) (by
      apply expectTag_eq_of_headerV1
      change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1026
          (ByteArray.mk [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110].toArray)
          2 = .ok 1043
      rw [expectTaggedHeaderBytesAtV1_refinesSpine]
      unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
        spineRemainingV1 readSpineU16leV1
      rw [canonicalSpine_length]
      rfl)
    (by
      apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1043, 4⟩
        ⟨canonicalBytes, 1044, 4⟩ ⟨canonicalBytes, 1066, 4⟩
        { valueId := 0, typeId := 0 }
      · apply decodeU8_eq_of_readV1
        change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) 1043 = .ok 1
        rw [readByteAtV1_refinesSpine]
        rfl
      · exact decodeFalsehoodValueDef_canonicalBytes)
    decodeFalsehoodLiteral_canonicalBytes
  simpa [falsehoodInstruction, boolLiteral, instruction, valueDef] using h

theorem decodeFalsehoodReturn_canonicalBytes :
    decodeTerminatorV1 ⟨canonicalBytes, 1091, 3⟩ =
      .ok (.return_ (some 0), ⟨canonicalBytes, 1113, 3⟩) := by
  apply decodeTerminatorV1_return ⟨canonicalBytes, 1091, 3⟩
    ⟨canonicalBytes, 1106, 4⟩ ⟨canonicalBytes, 1108, 4⟩
    ⟨canonicalBytes, 1113, 4⟩ (some 0) (by decide)
  · apply decodeCanonicalTagV1 1091 1106 4
      [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] "Term.Return"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · have hread : readU16leAtV1 canonicalBytes 1106 = .ok (1, 1108) := by
      change readU16leAtV1 (ByteArray.mk canonicalSpine.toArray) 1106 = .ok (1, 1108)
      rw [readU16leAtV1_refinesSpine]
      rfl
    have hresult := decodeFieldCount_eq_of_readU16leV1 1
      ⟨canonicalBytes, 1106, 4⟩ 1 1108 hread
    simpa using hresult
  · apply decodeOption_someV1 decodeU32le ⟨canonicalBytes, 1108, 4⟩
      ⟨canonicalBytes, 1109, 4⟩ ⟨canonicalBytes, 1113, 4⟩ 0
    · apply decodeU8_eq_of_readV1
      change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) 1108 = .ok 1
      rw [readByteAtV1_refinesSpine]
      rfl
    · apply decodeCanonicalU32V1
      rfl

theorem decodeFalsehoodBlock_canonicalBytes :
    decodeBlockV1 ⟨canonicalBytes, 1003, 2⟩ =
      .ok (falsehoodBlock, ⟨canonicalBytes, 1113, 2⟩) := by
  apply decodeBlockV1_oneInstructionV1 ⟨canonicalBytes, 1003, 2⟩
    ⟨canonicalBytes, 1014, 3⟩ ⟨canonicalBytes, 1018, 3⟩
    ⟨canonicalBytes, 1091, 3⟩ ⟨canonicalBytes, 1113, 3⟩
    1022 1026 0 falsehoodInstruction (.return_ (some 0)) (by decide)
  · apply expectTag_eq_of_headerV1
    change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1003
        (ByteArray.mk [66, 108, 111, 99, 107].toArray) 4 = .ok 1014
    rw [expectTaggedHeaderBytesAtV1_refinesSpine]
    unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
      spineRemainingV1 readSpineU16leV1
    rw [canonicalSpine_length]
    rfl
  · apply decodeCanonicalU32V1
    rfl
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1018
      maxArrayElements = .ok (0, 1022)
    rw [readArrayCountAtV1_refinesSpine]
    rfl
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1022
      maxArrayElements = .ok (1, 1026)
    rw [readArrayCountAtV1_refinesSpine]
    rfl
  · exact decodeFalsehoodInstruction_canonicalBytes
  · exact decodeFalsehoodReturn_canonicalBytes

theorem decodeFalsehood_canonicalBytes :
    decodeCallableV1 ⟨canonicalBytes, 888, 1⟩ =
      .ok (falsehood, ⟨canonicalBytes, 1126, 1⟩) := by
  have h := decodeCallableV1_singleBlockV1
    ⟨canonicalBytes, 888, 1⟩ ⟨canonicalBytes, 902, 2⟩
    ⟨canonicalBytes, 906, 2⟩ ⟨canonicalBytes, 930, 2⟩
    ⟨canonicalBytes, 944, 2⟩ ⟨canonicalBytes, 995, 2⟩
    ⟨canonicalBytes, 999, 2⟩ ⟨canonicalBytes, 1113, 2⟩
    ⟨canonicalBytes, 1126, 2⟩ 948 1003 1117 3 0 .invariant (some "falsehood")
    { typeId := 0, visibility := .public_ } falsehoodBlock (some 3) (by decide)
    (by
      apply expectTag_eq_of_headerV1
      change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 888
          (ByteArray.mk [67, 97, 108, 108, 97, 98, 108, 101].toArray) 9 = .ok 902
      rw [expectTaggedHeaderBytesAtV1_refinesSpine]
      unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
        spineRemainingV1 readSpineU16leV1
      rw [canonicalSpine_length]
      rfl)
    (decodeCanonicalU32V1 902 906 2 3 (by rfl)) decodeFalsehoodKind_canonicalBytes
    decodeFalsehoodName_canonicalBytes (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 944
        maxArrayElements = .ok (0, 948)
      rw [readArrayCountAtV1_refinesSpine]
      rfl)
    decodeFalsehoodResult_canonicalBytes (decodeCanonicalU32V1 995 999 2 0 (by rfl))
    (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 999
        maxArrayElements = .ok (1, 1003)
      rw [readArrayCountAtV1_refinesSpine]
      rfl)
    decodeFalsehoodBlock_canonicalBytes (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1113
        maxArrayElements = .ok (0, 1117)
      rw [readArrayCountAtV1_refinesSpine]
      rfl)
    (by
      apply decodeOption_someV1 decodeU64le ⟨canonicalBytes, 1117, 2⟩
        ⟨canonicalBytes, 1118, 2⟩ ⟨canonicalBytes, 1126, 2⟩ 3
      · apply decodeU8_eq_of_readV1
        change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) 1117 = .ok 1
        rw [readByteAtV1_refinesSpine]
        rfl
      · apply decodeCanonicalU64V1
        rfl)
  simpa [falsehood, invariantCallable, falsehoodBlock] using h

theorem decodeCallables_canonicalBytes :
    decodeArray maxTableElements decodeCallableV1 ⟨canonicalBytes, 257, 1⟩ =
      .ok (#[gate, leaf, truth, falsehood], ⟨canonicalBytes, 1126, 1⟩) := by
  exact decodeCallableArrayV1_four ⟨canonicalBytes, 257, 1⟩ 261
    gate leaf truth falsehood ⟨canonicalBytes, 419, 1⟩ ⟨canonicalBytes, 654, 1⟩
    ⟨canonicalBytes, 888, 1⟩ ⟨canonicalBytes, 1126, 1⟩
    readCallablesCount_canonicalBytes decodeGate_canonicalBytes decodeLeaf_canonicalBytes
    decodeTruth_canonicalBytes decodeFalsehood_canonicalBytes

private theorem decodeCanonicalAsciiStringV1 (bytes : ByteArray) (offset after nesting : Nat)
    (raw : ByteArray) (value : String)
    (hread : readSizedBytesAtV1 bytes offset maxStringBytes = .ok (raw, after))
    (hutf8 : String.fromUTF8? raw = some value)
    (hascii : ProofForgeV2.Core.Unicode.isAscii value = true) :
    decodeString ⟨bytes, offset, nesting⟩ = .ok (value, ⟨bytes, after, nesting⟩) := by
  apply decodeString_eq_of_valueV1 _ _ _ _ hread hutf8
  exact ProofForgeV2.Core.Unicode.requireNfc_eq_ok_of_isAscii value hascii

theorem decodeTruthDecl_canonicalBytes :
    decodeInvariantDeclV1 ⟨canonicalBytes, 1130, 1⟩ =
      .ok (truthDecl, ⟨canonicalBytes, 1166, 1⟩) := by
  refine decodeInvariantDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 1130, 1⟩ truthDecl
    ⟨canonicalBytes, 1166, 2⟩ (by decide) ?_
  apply decodeInvariantDeclBodyV1_eq_of_fields
  · apply expectTag_eq_of_headerV1
    change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1130
        (ByteArray.mk [73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108].toArray)
        3 = .ok 1149
    rw [expectTaggedHeaderBytesAtV1_refinesSpine]
    unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
      spineRemainingV1 readSpineU16leV1
    rw [canonicalSpine_length]
    rfl
  · apply decodeCanonicalU32V1
    rfl
  · apply decodeCanonicalAsciiStringV1 canonicalBytes 1153 1162 2
      (ByteArray.mk [116, 114, 117, 116, 104].toArray) "truth"
    · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1153 maxStringBytes =
        .ok (ByteArray.mk [116, 114, 117, 116, 104].toArray, 1162)
      apply readSizedBytesAtV1_eq_of_spine
      apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [116, 114, 117, 116, 104]
        1153 maxStringBytes 5 1157
      · rfl
      · decide
      · decide
      · unfold takeSpineBytesV1 spineRemainingV1
        rw [canonicalSpine_length]
        rfl
    · rfl
    · rfl
  · apply decodeCanonicalU32V1
    rfl

theorem decodeFalsehoodDecl_canonicalBytes :
    decodeInvariantDeclV1 ⟨canonicalBytes, 1166, 1⟩ =
      .ok (falsehoodDecl, ⟨canonicalBytes, 1206, 1⟩) := by
  refine decodeInvariantDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 1166, 1⟩ falsehoodDecl
    ⟨canonicalBytes, 1206, 2⟩ (by decide) ?_
  apply decodeInvariantDeclBodyV1_eq_of_fields
  · apply expectTag_eq_of_headerV1
    change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1166
        (ByteArray.mk [73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108].toArray)
        3 = .ok 1185
    rw [expectTaggedHeaderBytesAtV1_refinesSpine]
    unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
      spineRemainingV1 readSpineU16leV1
    rw [canonicalSpine_length]
    rfl
  · apply decodeCanonicalU32V1
    rfl
  · apply decodeCanonicalAsciiStringV1 canonicalBytes 1189 1202 2
      (ByteArray.mk [102, 97, 108, 115, 101, 104, 111, 111, 100].toArray) "falsehood"
    · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1189 maxStringBytes =
        .ok (ByteArray.mk [102, 97, 108, 115, 101, 104, 111, 111, 100].toArray, 1202)
      apply readSizedBytesAtV1_eq_of_spine
      apply readSizedSpineBytesV1_eq_of_parts canonicalSpine
        [102, 97, 108, 115, 101, 104, 111, 111, 100] 1189 maxStringBytes 9 1193
      · rfl
      · decide
      · decide
      · unfold takeSpineBytesV1 spineRemainingV1
        rw [canonicalSpine_length]
        rfl
    · rfl
    · rfl
  · apply decodeCanonicalU32V1
    rfl

theorem decodeInvariants_canonicalBytes :
    decodeArray maxTableElements decodeInvariantDeclV1 ⟨canonicalBytes, 1126, 1⟩ =
      .ok (invariants, ⟨canonicalBytes, 1206, 1⟩) := by
  have h := decodeArray_twoV1 maxTableElements decodeInvariantDeclV1
    ⟨canonicalBytes, 1126, 1⟩ 1130 truthDecl falsehoodDecl
    ⟨canonicalBytes, 1166, 1⟩ ⟨canonicalBytes, 1206, 1⟩ (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1126
        maxTableElements = .ok (2, 1130)
      rw [readArrayCountAtV1_refinesSpine]
      rfl)
    decodeTruthDecl_canonicalBytes decodeFalsehoodDecl_canonicalBytes
  simpa [invariants] using h

theorem decodeRequirements_canonicalBytes :
    decodeProgramRequirementsV1 ⟨canonicalBytes, 1206, 1⟩ =
      .ok ({ items := #[] }, ⟨canonicalBytes, 1235, 1⟩) := by
  refine decodeProgramRequirementsV1_eq_of_bodyV1 ⟨canonicalBytes, 1206, 1⟩
    { items := #[] } ⟨canonicalBytes, 1235, 2⟩ (by decide) ?_
  apply decodeProgramRequirementsBodyV1_eq_of_fields
  · apply expectTag_eq_of_headerV1
    change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1206
        (ByteArray.mk [80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114,
          101, 109, 101, 110, 116, 115].toArray) 1 = .ok 1231
    rw [expectTaggedHeaderBytesAtV1_refinesSpine]
    unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
      spineRemainingV1 readSpineU16leV1
    rw [canonicalSpine_length]
    rfl
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1231
      maxArrayElements = .ok (0, 1235)
    rw [readArrayCountAtV1_refinesSpine]
    rfl

theorem decodeTaggedData_canonicalBytes :
    decodeSemanticProgramDataTaggedV1 ⟨canonicalBytes, 15, 0⟩ =
      .ok (data, ⟨canonicalBytes, 1235, 0⟩) := by
  have h := decodeSemanticProgramDataTaggedV1_eq_of_fields
    ⟨canonicalBytes, 15, 0⟩ ⟨canonicalBytes, 41, 1⟩
    ⟨canonicalBytes, 76, 1⟩ ⟨canonicalBytes, 187, 1⟩
    ⟨canonicalBytes, 191, 1⟩ ⟨canonicalBytes, 249, 1⟩
    ⟨canonicalBytes, 253, 1⟩ ⟨canonicalBytes, 257, 1⟩
    ⟨canonicalBytes, 1126, 1⟩ ⟨canonicalBytes, 1206, 1⟩
    ⟨canonicalBytes, 1235, 1⟩ qualifiedName types #[] #[logicalStateDecl] #[] #[]
    #[gate, leaf, truth, falsehood] invariants { items := #[] } (by decide)
    expectRootTag_canonicalBytes decodeQualifiedName_canonicalBytes decodeTypes_canonicalBytes
    decodeConstants_canonicalBytes decodeLogicalState_canonicalBytes decodeEvents_canonicalBytes
    decodeErrors_canonicalBytes decodeCallables_canonicalBytes decodeInvariants_canonicalBytes
    decodeRequirements_canonicalBytes
  simpa [data] using h

theorem decodeData_canonicalBytes :
    decodeSemanticProgramDataV1 canonicalBytes = .ok data := by
  apply decodeSemanticProgramDataV1_eq_of_framing canonicalBytes
    ⟨canonicalBytes, 15, 0⟩ ⟨canonicalBytes, 1235, 0⟩ data
  · change canonicalSpine.length ≤ maxCanonicalProgramBytes
    rw [canonicalSpine_length]
    decide
  · exact consumeMagic_canonicalBytes
  · exact decodeTaggedData_canonicalBytes
  · apply finish_eq_ok_of_offset_sizeV1
    change 1235 = canonicalSpine.length
    exact canonicalSpine_length.symm

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
