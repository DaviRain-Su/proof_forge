/-
  Tests.Semantic.InvariantABI — engineering suite for D2-07 LogicalState /
  StateConforms foundation (`ProofForgeV2.Semantic.InvariantABI`).

  Engineering only (not formal TST-SEM / TASK-D2-07). Pins:
    * `defaultValueV1` for every TypeShapeV1
    * `initialLogicalStateV1` declaration-order slots + initialized flag
    * `stateConformsBoolV1` true-state only
    * `decodeLogicalStateValuesV1` / `encodeLogicalStateValuesV1` roundtrip
    * representative decode/encode negatives (missing slot, short length,
      trailing, noncanonical Bool/Option/Field)
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
open ProofForgeV2.Semantic.WireV1

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
  testDeterministicRepeat
  IO.println "Tests.Semantic.InvariantABI: engineering suite finished"

end Tests.Semantic.InvariantABI
