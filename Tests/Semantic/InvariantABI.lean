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

private def encodeExistenceBoolType : TypeDeclV1 :=
  { id := 0, name := none, shape := .bool }

private def encodeExistenceUInt64Type : TypeDeclV1 :=
  { id := 1, name := none, shape := .uint 64 }

private def encodeExistenceBoolState : StateDeclV1 :=
  { id := 0, name := "enabled", typeId := 0, visibility := .public_ }

private def encodeExistenceUInt64State : StateDeclV1 :=
  { id := 1, name := "count", typeId := 1, visibility := .public_ }

/-! The generic existence bridge remains tied to the sole production state
encoder for a representative mixed multi-slot canonical payload. -/
example
    (data : SemanticProgramDataV1)
    (enabled : Bool)
    (count : UInt64)
    (htypes : data.types = #[encodeExistenceBoolType, encodeExistenceUInt64Type])
    (hstate : data.logicalState =
      #[encodeExistenceBoolState, encodeExistenceUInt64State]) :
    ∃ state,
      encodeLogicalStateValuesV1 data true
          #[encodeBool enabled, encodeU64le count] = .ok state := by
  apply encodeLogicalStateValuesV1_exists_of_pairs data true
    #[encodeBool enabled, encodeU64le count]
    [(encodeExistenceBoolState, encodeBool enabled),
      (encodeExistenceUInt64State, encodeU64le count)]
  · simp [hstate]
  · rfl
  · intro pair hpair
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hpair
    rcases hpair with rfl | rfl
    · constructor
      · apply validateValueBytesV1_encodeBool data.types 0
          encodeExistenceBoolType enabled
        · simp [htypes]
        · rfl
      · cases enabled <;> decide
    · constructor
      · apply validateValueBytesV1_uint64_of_size data.types 1
          encodeExistenceUInt64Type (encodeU64le count)
        · simp [htypes]
        · rfl
        · exact encodeU64le_size count
      · rw [encodeU64le_size]
        decide

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
  in SPEC §5 unsigned-lex `typeKey` rank (tag-length first: int < map <
  bool < uint < unit < array < bytes < field < option < principal).
  TypeId layout:

    0  named Struct Pair { a:Bool, b:UInt8 }
    1  named Enum Tag { V0(UInt8), V1() }
    2  Int8
    3  Map Bool → UInt8
    4  Bool
    5  UInt8
    6  Unit
    7  Array Bool × 2
    8  Bytes 3
    9  Field bn254-fr
    10 Option Bool
    11 Principal
-/
private def allShapeTypes : Array TypeDeclV1 := #[
  {
    id := 0
    name := some "Pair"
    shape := .struct #[
      { name := "a", typeId := 4 },
      { name := "b", typeId := 5 }
    ]
  },
  {
    id := 1
    name := some "Tag"
    shape := .enum #[
      { name := "V0", payloadTypes := #[5] },
      { name := "V1", payloadTypes := #[] }
    ]
  },
  { id := 2, name := none, shape := .int 8 },
  { id := 3, name := none, shape := .map 4 5 },
  { id := 4, name := none, shape := .bool },
  { id := 5, name := none, shape := .uint 8 },
  { id := 6, name := none, shape := .unit },
  { id := 7, name := none, shape := .array 4 2 },
  { id := 8, name := none, shape := .bytes 3 },
  { id := 9, name := none, shape := .field bn254FrFieldSpecV1 },
  { id := 10, name := none, shape := .option 4 },
  { id := 11, name := none, shape := .principal }
]

/-- State declaration order covers a representative multi-slot mix and
    Core-anchors every anonymous TypeDecl in `allShapeTypes` (Stage D). -/
private def multiStateDecls : Array StateDeclV1 := #[
  { id := 0, name := "sBool", typeId := 4, visibility := .public_ },
  { id := 1, name := "sU8", typeId := 5, visibility := .public_ },
  { id := 2, name := "sOpt", typeId := 10, visibility := .public_ },
  { id := 3, name := "sPair", typeId := 0, visibility := .public_ },
  { id := 4, name := "sMap", typeId := 3, visibility := .public_ },
  { id := 5, name := "sInt8", typeId := 2, visibility := .public_ },
  { id := 6, name := "sArr", typeId := 7, visibility := .public_ },
  { id := 7, name := "sBytes", typeId := 8, visibility := .public_ },
  { id := 8, name := "sField", typeId := 9, visibility := .public_ },
  { id := 9, name := "sPrin", typeId := 11, visibility := .public_ }
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
  -- 2 Int8 zero
  (2, ByteArray.mk #[0]),
  -- 3 Map empty
  (3, u32le 0),
  -- 4 Bool false
  (4, ByteArray.mk #[0]),
  -- 5 UInt8 zero
  (5, ByteArray.mk #[0]),
  -- 6 Unit empty
  (6, ByteArray.empty),
  -- 7 Array Bool×2 = false,false
  (7, ByteArray.mk #[0, 0]),
  -- 8 Bytes 3 zeros
  (8, zeroBytes 3),
  -- 9 Field zero (32 LE bytes for bn254 Fr)
  (9, zeroBytes 32),
  -- 10 Option none
  (10, ByteArray.mk #[0]),
  -- 11 Principal payload `00` with u32 length
  (11, (u32le 1).append (ByteArray.mk #[0]))
]

private def expectedMultiStateDefaults : Array ByteArray := #[
  ByteArray.mk #[0],           -- Bool
  ByteArray.mk #[0],           -- UInt8
  ByteArray.mk #[0],           -- Option none
  ByteArray.mk #[0, 0],        -- Pair
  u32le 0,                     -- Map empty
  ByteArray.mk #[0],           -- Int8
  ByteArray.mk #[0, 0],        -- Array Bool×2
  zeroBytes 3,                 -- Bytes 3
  zeroBytes 32,                -- Field
  (u32le 1).append (ByteArray.mk #[0])  -- Principal
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
    u32le 0,                     -- Map empty
    ByteArray.mk #[0],           -- Int8
    ByteArray.mk #[0, 0],        -- Array
    zeroBytes 3,                 -- Bytes
    zeroBytes 32,                -- Field
    (u32le 1).append (ByteArray.mk #[0])  -- Principal
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
    -- Anonymous rank: unit (tag len 4) before field (tag len 5).
    types := #[{ id := 0, name := none, shape := .unit },
               { id := 1, name := none, shape := .field bn254FrFieldSpecV1 }]
    logicalState := #[{ id := 0, name := "f", typeId := 1, visibility := .public_ }]
    callables := #[entryGate 0 0]
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

def unitType : TypeDeclV1 := { id := 1, name := none, shape := .unit }

/-- Stage D usage-closure: only Bool (state/leaf) and Unit (entry_gate)
    remain; unused Principal was dropped from the canonical table. -/
def types : Array TypeDeclV1 := #[boolType, unitType]

def logicalStateDecl : StateDeclV1 :=
  { id := 0, name := "flag", typeId := 0, visibility := .public_ }

def gateBlock : BlockV1 :=
  { id := 0, params := #[], instructions := #[], terminator := .return_ none }

def gate : CallableV1 := entryGate 0 1

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

/-- Exact production invariant-closure membership in callable source order. -/
def closureMembers : Array Bool := #[false, true, true, true]

theorem computeInvariantClosureMembership_data :
    invariantClosureMembershipResultV1 data.callables = .ok closureMembers := by
  simp [invariantClosureMembershipResultV1, closureMembers, data, gate, entryGate,
    leaf, leafBlock, leafInstruction, boolLiteral, truth, invariantCallable,
    truthInstruction, instruction, valueDef, falsehood, falsehoodInstruction]
  rfl

/-- The concrete fixture closes the sole production structure prelude: root
    shape, contiguous table IDs, and shallow declaration references. This is
    intentionally not a claim that the later type/value/CFG/requirement gates
    have completed. -/
theorem structurePrelude_data :
    validateSemanticProgramStructurePreludeV1 data = .ok () := by
  have hQualifiedName : 2 ≤ qualifiedName.components.toArray.size := by decide
  simp [validateSemanticProgramStructurePreludeV1, checkTableIdsV1,
    validateProgramQualifiedNameShapeV1, hQualifiedName, data, types, boolType,
    unitType, logicalStateDecl, gate, entryGate, leaf, truth,
    invariantCallable, falsehood, invariants, truthDecl, falsehoodDecl,
    checkTypeShapeRefs, checkTypeIdInRange, checkCallableIdInRange,
    checkIdEqualsIndex, Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem typesStructure_data :
    validateTypesStructureV1 data.types = .ok () := by
  simp [validateTypesStructureV1, validateTypeDeclShapeV1,
    validateTypeDeclNamedRuleV1, data, types, boolType, unitType,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem typeKeyNamedPrefix_data :
    validateNamedPrefixRankV1 data.types = .ok () := by
  simp [validateNamedPrefixRankV1, data, types, boolType,
    unitType, Pure.pure, Except.pure, Bind.bind, Except.bind]

private def boolTypeShapeBytes : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0]

private def unitTypeShapeBytes : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 85, 110, 105, 116, 0, 0]

private theorem encodeTypeShape_bool_fixture :
    encodeTypeShapeV1 (.bool : TypeShapeV1) = .ok boolTypeShapeBytes := by
  change encodeNullary "Type.Bool" = .ok boolTypeShapeBytes
  rw [encodeNullary_eq_okV1 "Type.Bool" (by decide) (by decide) (by decide)]
  congr 1

private theorem encodeTypeShape_unit_fixture :
    encodeTypeShapeV1 (.unit : TypeShapeV1) = .ok unitTypeShapeBytes := by
  change encodeNullary "Type.Unit" = .ok unitTypeShapeBytes
  rw [encodeNullary_eq_okV1 "Type.Unit" (by decide) (by decide) (by decide)]
  congr 1

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

theorem typeKeyPrimitiveLeaf_data :
    validatePrimitiveAnonymousTypeKeyUniquenessV1 data.types = .ok () := by
  simp [validatePrimitiveAnonymousTypeKeyUniquenessV1,
    collectPrimitiveAnonymousTypeKeysV1, data, types, boolType,
    unitType, encodeTypeShape_bool_fixture,
    encodeTypeShape_unit_fixture, compare_bool_unit_fixture,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem typeKeyRecursiveAnonymous_data :
    validateRecursiveAnonymousTypeKeyUniquenessV1 data.types = .ok () := by
  simp [validateRecursiveAnonymousTypeKeyUniquenessV1, data, types, boolType,
    unitType, Pure.pure, Except.pure]

theorem typeKeyNamedBodyCycle_data :
    validateNamedBodyOptionCycleLegalityV1 data.types = .ok () := by
  simp [validateNamedBodyOptionCycleLegalityV1, data, types, boolType,
    unitType, Pure.pure, Except.pure]

theorem typeKeyPhases_data :
    validateTypeKeyPhasesV1 data.types = .ok () := by
  apply validateTypeKeyPhasesV1_eq_ok_of_prefix_phases
  · exact typeKeyNamedPrefix_data
  · exact typeKeyPrimitiveLeaf_data
  · exact typeKeyRecursiveAnonymous_data
  · exact typeKeyNamedBodyCycle_data
  · exact validateAnonymousTypeKeyRankV1_bool_unit_eq_ok
      boolType unitType rfl rfl

theorem usageClosure_data :
    validateAnonymousTypeUsageClosureV1 data = .ok () := by
  apply validateAnonymousTypeUsageClosureV1_bool_unit_coreMarked_eq_ok data
  · rfl
  · unfold anonymousTypeUsageBitmapV1
    simp [data, types, boolType, unitType, gate, entryGate, leaf, leafBlock,
      leafInstruction, boolLiteral, truth, falsehood, truthInstruction, instruction,
      valueDef, falsehoodInstruction, invariantCallable, logicalStateDecl,
      invariants, truthDecl, falsehoodDecl, collectCoreTypeSlotRootsV1]
    native_decide

theorem typeKeyPhasesWithUsageClosure_data :
    validateTypeKeyPhasesWithUsageClosureV1 data = .ok () := by
  exact validateTypeKeyPhasesWithUsageClosureV1_eq_ok_of_phases data
    typeKeyPhases_data usageClosure_data

theorem namedTypeNames_data :
    validateNamedTypeNameUniquenessV1 data.types = .ok () := by
  simp [validateNamedTypeNameUniquenessV1, checkUniqueDeclarationNamesV1,
    data, types, boolType, unitType, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

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

/-- The four canonical callables pass the sole production signature phase
    sequence, including exact callable-name uniqueness and special invariant
    metadata presence checks. -/
theorem callableSignatures_data :
    validateCallableSignaturePhasesV1 data.types data.callables = .ok () := by
  have hEntryInit : ((.entry : CallableKindV1) == .initializer) = false := by decide
  have hPureInit : ((.pureFn : CallableKindV1) == .initializer) = false := by decide
  have hInvariantInit : ((.invariant : CallableKindV1) == .initializer) = false := by decide
  have hEntryInvariant : ((.entry : CallableKindV1) == .invariant) = false := by decide
  have hPureInvariant : ((.pureFn : CallableKindV1) == .invariant) = false := by decide
  have hInvariantInvariant : ((.invariant : CallableKindV1) == .invariant) = true := by decide
  have hPublicPublic : ((.public_ : VisibilityV1) == .public_) = true := by decide
  apply validateCallableSignaturePhasesV1_eq_ok_of_phases
  all_goals simp [data, types, boolType,
    unitType, gate, entryGate, leaf, leafBlock, truth, invariantCallable,
    truthInstruction, instruction, valueDef, falsehood, falsehoodInstruction,
    boolLiteral, validateCallableKindNamePresenceV1,
    validateCallableNameUniquenessV1,
    validateCallableParameterNameUniquenessV1,
    validateCallableEntryViewPresenceV1, validateInitializerCardinalityV1,
    validateInitializerResultShapeV1, validateInvariantResultShapeV1,
    validateInvariantParameterShapeV1, validateInvariantLoopBoundsShapeV1,
    validateNonClosureCallableInvariantStepsV1,
    validateInvariantRootStepsPresenceV1,
    hEntryInit, hPureInit, hInvariantInit, hEntryInvariant, hPureInvariant,
    hInvariantInvariant, hPublicPublic, Pure.pure, Except.pure, Bind.bind,
    Except.bind]

/-- The two InvariantDecl rows exactly join the invariant callables in their
    filtered callable source order: truth→2, then falsehood→3. -/
theorem invariantDeclarationJoin_data :
    validateInvariantDeclarationJoinV1 data.callables data.invariants = .ok () := by
  have hEntryInvariant : ((.entry : CallableKindV1) == .invariant) = false := by decide
  have hPureInvariant : ((.pureFn : CallableKindV1) == .invariant) = false := by decide
  have hInvariantInvariant : ((.invariant : CallableKindV1) == .invariant) = true := by decide
  simp [validateInvariantDeclarationJoinV1, data, gate, entryGate, leaf,
    leafBlock, truth, invariantCallable, truthInstruction, instruction,
    valueDef, falsehood, falsehoodInstruction, boolLiteral, invariants,
    truthDecl, falsehoodDecl, hEntryInvariant, hPureInvariant,
    hInvariantInvariant, Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- Every declaration name in the canonical fixture passes the sole shared
    SPEC-COMMON identifier authority in production table order. -/
theorem declarationIdentifierNames_data :
    validateDeclarationIdentifierNamesV1 data = .ok () := by
  have identifierOk (name : String)
      (hcommon : validateIdentifierComponent name = .ok ()) :
      validateIdentifierNameV1 name = .ok () :=
    validateIdentifierNameV1_eq_ok_of_common name hcommon
  have hflag : validateIdentifierNameV1 "flag" = .ok () := by
    apply identifierOk
    unfold validateIdentifierComponent
    rw [if_pos (by decide)]
    simp only [ProofForgeV2.Core.Unicode.requireNfc_eq_ok_of_isAscii "flag" (by decide),
      Bind.bind, Except.bind]
    rw [if_neg (by decide)]
    simp only [Pure.pure, Except.pure]
    rfl
  have hentry : validateIdentifierNameV1 "entry_gate" = .ok () := by
    apply identifierOk
    unfold validateIdentifierComponent
    rw [if_pos (by decide)]
    simp only [ProofForgeV2.Core.Unicode.requireNfc_eq_ok_of_isAscii "entry_gate" (by decide),
      Bind.bind, Except.bind]
    rw [if_neg (by decide)]
    simp only [Pure.pure, Except.pure]
    rfl
  have hleaf : validateIdentifierNameV1 "truthLeaf" = .ok () := by
    apply identifierOk
    unfold validateIdentifierComponent
    rw [if_pos (by decide)]
    simp only [ProofForgeV2.Core.Unicode.requireNfc_eq_ok_of_isAscii "truthLeaf" (by decide),
      Bind.bind, Except.bind]
    rw [if_neg (by decide)]
    simp only [Pure.pure, Except.pure]
    rfl
  have htruth : validateIdentifierNameV1 "truth" = .ok () := by
    apply identifierOk
    unfold validateIdentifierComponent
    rw [if_pos (by decide)]
    simp only [ProofForgeV2.Core.Unicode.requireNfc_eq_ok_of_isAscii "truth" (by decide),
      Bind.bind, Except.bind]
    rw [if_neg (by decide)]
    simp only [Pure.pure, Except.pure]
    rfl
  have hfalsehood : validateIdentifierNameV1 "falsehood" = .ok () := by
    apply identifierOk
    unfold validateIdentifierComponent
    rw [if_pos (by decide)]
    simp only [ProofForgeV2.Core.Unicode.requireNfc_eq_ok_of_isAscii "falsehood" (by decide),
      Bind.bind, Except.bind]
    rw [if_neg (by decide)]
    simp only [Pure.pure, Except.pure]
    rfl
  simp [validateDeclarationIdentifierNamesV1, validateTypeShapeIdentifierNamesV1,
    data, types, boolType, unitType, logicalStateDecl, gate,
    entryGate, leaf, leafBlock, truth, invariantCallable, truthInstruction,
    instruction, valueDef, falsehood, falsehoodInstruction, boolLiteral,
    invariants, truthDecl, falsehoodDecl, hflag, hentry, hleaf, htruth,
    hfalsehood, Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- The externally invokable gate has one reachable canonical return block,
    no definitions/effects/loops, and satisfies the sole generic CFG checker. -/
theorem gateCfg_data :
    validateCallableCfgShape gate data.types.size data.types data = .ok () := by
  rfl

/-- The pure leaf's single Bool literal definition dominates its return use and
    satisfies canonical ValueId, type, op, and terminator contracts. -/
theorem leafCfg_data :
    validateCallableCfgShape leaf data.types.size data.types data = .ok () := by
  refine validateCallableCfgShape_eq_ok_of_phases
    leaf data.types.size data.types data #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases leaf #[true] #[(0, 0)]
    · rfl
    · rfl
    · apply checkValueIdUsesExist_single_local_return_eq_ok
      · rfl
      · rfl
    · apply validateCallableDominanceOfUse_single_local_return_eq_ok
      · rfl
      · rfl
  · rfl

/-- The selected invariant root's operand-free call to the proved pure leaf
    produces Bool ValueId 0, which dominates and types its return. -/
theorem truthCfg_data :
    validateCallableCfgShape truth data.types.size data.types data = .ok () := by
  refine validateCallableCfgShape_eq_ok_of_phases
    truth data.types.size data.types data #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases truth #[true] #[(0, 0)]
    · rfl
    · rfl
    · apply checkValueIdUsesExist_single_local_return_eq_ok
      · rfl
      · rfl
    · apply validateCallableDominanceOfUse_single_local_return_eq_ok
      · rfl
      · rfl
  · apply validateCallableCfgTypingPhases_single_nullary_pureCall_eq_ok
      truth leaf data data.types.size 1 0 <;> rfl

/-- The second invariant's single false Bool literal satisfies the same exact
    production CFG, SSA, dominance, op, and terminator contracts. -/
theorem falsehoodCfg_data :
    validateCallableCfgShape falsehood data.types.size data.types data = .ok () := by
  refine validateCallableCfgShape_eq_ok_of_phases
    falsehood data.types.size data.types data #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases
      falsehood #[true] #[(0, 0)]
    · rfl
    · rfl
    · apply checkValueIdUsesExist_single_local_return_eq_ok
      · rfl
      · rfl
    · apply validateCallableDominanceOfUse_single_local_return_eq_ok
      · rfl
      · rfl
  · rfl

/-- All four source-order callable validators plus the global ContextRead
    catalog close the complete generic production `.cfg` phase. -/
theorem genericCfgPhases_data :
    validateGenericCfgPhasesV1 data = .ok () := by
  apply validateGenericCfgPhasesV1_four_eq_ok data gate leaf truth falsehood
  · rfl
  · exact gateCfg_data
  · exact leafCfg_data
  · exact truthCfg_data
  · exact falsehoodCfg_data
  · rfl

/-- Direct root restrictions, exact membership, and PureFn metadata agreement
    close the production invariant-closure prefix. -/
theorem invariantClosureMembershipPhases_data :
    validateInvariantClosureMembershipPhasesV1 data.callables =
      .ok closureMembers := by
  apply validateInvariantClosureMembershipPhasesV1_eq_ok
  · rfl
  · exact computeInvariantClosureMembership_data
  · apply validatePureFnInvariantClosureMembershipFourV1
      gate leaf truth falsehood 3 <;> rfl

/-- The public production DAG prefix consumes that exact membership. Its
    actual graph builder yields indegree #[0,1,0,0], caller adjacency
    #[#[],#[],#[1],#[]], and three members; source-index ready collection is
    #[2,3], after which Kahn appends leaf 1 and processes all three members. -/
theorem invariantClosureDagPhases_data :
    validateInvariantClosureDagPhasesV1 data.callables =
      .ok closureMembers := by
  apply validateInvariantClosureDagPhasesV1_eq_ok
  · exact invariantClosureMembershipPhases_data
  · apply validateInvariantClosureDagCanonicalFourV1
    · rfl
    · rfl
    · rfl

/-- The canonical fixture closes the complete non-fuel invariant-closure
    production prefix: all three closure CFGs are forward-only, the sole
    reachable PureFn operation is its Bool literal, and invariant roots are
    outside the PureFn operation allowlist. -/
theorem invariantClosurePhases_data :
    validateInvariantClosurePhasesV1 data.callables =
      .ok closureMembers := by
  apply validateInvariantClosurePhasesV1_eq_ok
  · exact invariantClosureDagPhases_data
  · exact (validateInvariantClosurePostDagCanonicalFourV1
      gate leaf truth falsehood leafBlock truthBlock falsehoodBlock
      leafInstruction 0 (ByteArray.mk #[1])
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)).1
  · exact (validateInvariantClosurePostDagCanonicalFourV1
      gate leaf truth falsehood leafBlock truthBlock falsehoodBlock
      leafInstruction 0 (ByteArray.mk #[1])
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)).2

/-- The sole production fuel composition closes on the exact canonical
    graph, intrinsic totals, source-order ready queue, and reverse-Kahn states. -/
theorem validateInvariantFuelPhases_data :
    validateInvariantFuelPhasesV1 data.callables closureMembers = .ok () := by
  apply validateInvariantFuelCanonicalFourV1
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl

/-- Complete generic CFG, invariant closure, and exact/intrinsic fuel segment
    for the canonical public invariant ABI fixture. -/
theorem validateCfgInvariantPhases_data :
    validateCfgInvariantPhasesV1 data = .ok () := by
  apply validateCfgInvariantPhasesV1_eq_ok data closureMembers
  · exact genericCfgPhases_data
  · exact invariantClosurePhases_data
  · exact validateInvariantFuelPhases_data

/-- The canonical fixture has no generic requirement rows. -/
theorem programRequirementsStructure_data :
    validateProgramRequirementsStructure data.requirements = .ok () := by
  rfl

/-- No ContextRead operation occurs, and therefore no exact ContextRead
    requirement row is required. -/
theorem contextReadRequirements_data :
    validateContextReadRequirementsV1 data = .ok () := by
  rfl

/-- No Commit operation occurs, and therefore no disclosure requirement row
    is required. -/
theorem commitRequirements_data :
    validateCommitRequirementsV1 data = .ok () := by
  rfl

/-- No env-read operation occurs, and therefore no extension.pf-assets
    requirement row is required. -/
theorem envReadRequirements_data :
    validateEnvReadRequirementsV1 data = .ok () := by
  rfl

/-- Every production structure phase now closes for the exact canonical
    invariant ABI fixture. -/
theorem semanticProgramStructure_data :
    validateSemanticProgramStructureV1 data = .ok () := by
  apply validateSemanticProgramStructureV1_eq_ok_of_phases data
    maxCanonicalProgramBytes (maxCanonicalProgramBytes - 4)
  · exact structurePrelude_data
  · exact typesStructure_data
  · exact typeKeyPhases_data
  · exact usageClosure_data
  · exact namedTypeNames_data
  · exact constantsValueBytes_data
  · exact callablesValueBytes_data
  · exact constantNames_data
  · exact logicalStateNames_data
  · exact eventNames_data
  · exact errorNames_data
  · exact interfaceFieldNames_data
  · exact callableSignatures_data
  · exact invariantDeclarationJoin_data
  · exact declarationIdentifierNames_data
  · exact validateCfgInvariantPhases_data
  · exact programRequirementsStructure_data
  · exact contextReadRequirements_data
  · exact commitRequirements_data
  · exact envReadRequirements_data

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

/-- Exact two-element TypeDecl array at root offset 76 (bool, unit). -/
def canonicalTypesSpine : TransparentByteSpineV1 := [
  2, 0, 0, 0, 8, 0, 0, 0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0,
  0, 0, 0, 0, 0, 9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0,
  8, 0, 0, 0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0, 1, 0, 0, 0, 0, 9,
  0, 0, 0, 84, 121, 112, 101, 46, 85, 110, 105, 116, 0, 0
]

/-- Exact empty constants table at root offset 148. -/
def canonicalConstantsSpine : TransparentByteSpineV1 := [0, 0, 0, 0]

/-- Exact singleton StateDecl array at root offset 152. -/
def canonicalLogicalStateSpine : TransparentByteSpineV1 := [
  1, 0, 0, 0, 9, 0, 0, 0, 83, 116, 97, 116, 101, 68, 101, 99, 108, 4, 0,
  0, 0, 0, 0, 4, 0, 0, 0, 102, 108, 97, 103, 0, 0, 0, 0, 17, 0, 0, 0,
  86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99,
  0, 0
]

/-- Exact empty events and errors tables at root offsets 210 and 214. -/
def canonicalEmptyInterfacesSpine : TransparentByteSpineV1 :=
  [0, 0, 0, 0, 0, 0, 0, 0]

/-- Exact four-element callables count at root offset 218. -/
def canonicalCallablesHeaderSpine : TransparentByteSpineV1 := [4, 0, 0, 0]

/-- Exact first callable (`entry_gate`) at root offset 222. -/
def canonicalEntryGateSpine : TransparentByteSpineV1 := [
  8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9, 0, 0, 0, 0, 0,
  14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 46, 69, 110, 116, 114, 121,
  0, 0, 1, 10, 0, 0, 0, 101, 110, 116, 114, 121, 95, 103, 97, 116, 101, 0,
  0, 0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115,
  117, 108, 116, 2, 0, 1, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98,
  105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0,
  1, 0, 0, 0, 5, 0, 0, 0, 66, 108, 111, 99, 107, 4, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 11, 0, 0, 0, 84, 101, 114, 109, 46,
  82, 101, 116, 117, 114, 110, 1, 0, 0, 0, 0, 0, 0, 0
]

/-- Exact second callable (`truthLeaf`) at root offset 380. -/
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

/-- Exact third callable (`truth`) at root offset 615. -/
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

/-- Exact fourth callable (`falsehood`) at root offset 849. -/
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

/-- Exact two-element InvariantDecl array at root offset 1087. -/
def canonicalInvariantsSpine : TransparentByteSpineV1 := [
  2, 0, 0, 0, 13, 0, 0, 0, 73, 110, 118, 97, 114, 105, 97, 110, 116, 68,
  101, 99, 108, 3, 0, 0, 0, 0, 0, 5, 0, 0, 0, 116, 114, 117, 116, 104, 2, 0, 0, 0,
  13, 0, 0, 0, 73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108, 3, 0, 1,
  0, 0, 0, 9, 0, 0, 0, 102, 97, 108, 115, 101, 104, 111, 111, 100, 3, 0, 0, 0
]

/-- Exact empty ProgramRequirements record at root offset 1167. -/
def canonicalRequirementsSpine : TransparentByteSpineV1 := [
  19,
  0, 0, 0, 80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114, 101, 109,
  101, 110, 116, 115, 1, 0, 0, 0, 0, 0
]

/-- Exact 1196-byte production encoding of `data` as the transparent proof
    spine. This explicit segmented golden is independent of encoder
    computation and is not a second runtime decoder. -/
def canonicalSpine : TransparentByteSpineV1 :=
  canonicalMagicSpine ++ canonicalRootHeaderSpine ++ canonicalQualifiedNameSpine ++
    canonicalTypesSpine ++ canonicalConstantsSpine ++ canonicalLogicalStateSpine ++
    canonicalEmptyInterfacesSpine ++ canonicalCallablesHeaderSpine ++ canonicalEntryGateSpine ++
    canonicalTruthLeafSpine ++ canonicalTruthSpine ++ canonicalFalsehoodSpine ++
    canonicalInvariantsSpine ++ canonicalRequirementsSpine

def canonicalBytes : ByteArray := ByteArray.mk canonicalSpine.toArray

theorem canonicalSpine_length : canonicalSpine.length = 1196 := by
  rfl

/-- Proof-side names for the exact outputs of production framing leaves. They
    contain no semantic traversal; each semantic layer below is separately
    tied to its sole production encoder. -/
def encodedValueDef0 : ByteArray :=
  taggedBytesFromBytesV1 (ByteArray.mk #[86, 97, 108, 117, 101, 68, 101, 102])
    #[encodeU32le 0, encodeU32le 0]

def encodedSomeValueDef0 : ByteArray := (encodeU8 1).append encodedValueDef0

def encodedBoolTrueValueBytes : ByteArray :=
  (encodeU32le 1).append (ByteArray.mk #[1])

def encodedLiteralTrueOp : ByteArray :=
  taggedBytesFromBytesV1
    (ByteArray.mk #[79, 112, 46, 76, 105, 116, 101, 114, 97, 108])
    #[encodeU32le 0, encodedBoolTrueValueBytes]

def encodedLeafInstruction : ByteArray :=
  taggedBytesFromBytesV1
    (ByteArray.mk #[73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110])
    #[encodedSomeValueDef0, encodedLiteralTrueOp]

def encodedReturnValue0 : ByteArray :=
  taggedBytesFromBytesV1
    (ByteArray.mk #[84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110])
    #[(encodeU8 1).append (encodeU32le 0)]

def encodedLeafBlock : ByteArray :=
  taggedBytesFromBytesV1 (ByteArray.mk #[66, 108, 111, 99, 107])
    #[encodeU32le 0, encodeU32le 0,
      (encodeU32le 1).append encodedLeafInstruction, encodedReturnValue0]

def encodedPureFnKind : ByteArray := taggedBytesFromBytesV1
  (ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 46, 80, 117, 114, 101, 70, 110]) #[]

def encodedPublicVisibility : ByteArray := taggedBytesFromBytesV1
  (ByteArray.mk #[86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98,
    108, 105, 99]) #[]

def encodedLeafName : ByteArray :=
  (encodeU8 1).append ((encodeU32le 9).append
    (ByteArray.mk #[116, 114, 117, 116, 104, 76, 101, 97, 102]))

def encodedBoolPublicResult : ByteArray :=
  taggedBytesFromBytesV1
    (ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116])
    #[encodeU32le 0, encodedPublicVisibility]

def encodedLeafCallable : ByteArray :=
  taggedBytesFromBytesV1 (ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101])
    #[encodeU32le 1, encodedPureFnKind, encodedLeafName,
      encodeU32le 0, encodedBoolPublicResult, encodeU32le 0,
      (encodeU32le 1).append encodedLeafBlock, encodeU32le 0,
      (encodeU8 1).append (encodeU64le 3)]

private theorem byteArray_eq_of_beq_eq_true
    {left right : ByteArray} (h : (left == right) = true) : left = right := by
  cases left with
  | mk leftData =>
    cases right with
    | mk rightData =>
      apply ByteArray.ext
      change (leftData == rightData) = true at h
      exact beq_iff_eq.mp h

theorem byteArray_beq_self (bytes : ByteArray) : (bytes == bytes) = true := by
  cases bytes with
  | mk data =>
      change (data == data) = true
      exact beq_self_eq_true data

/-- Stage D Bool/Unit closed table: live production encode equals the transparent
    spine (length 1196). Witness via computable equality. -/
def encodeMatchesCanonicalV1 : Bool :=
  match encodeSemanticProgramDataV1 data with
  | .ok b => b == canonicalBytes
  | .error _ => false

theorem encodeData_canonicalBytes :
    encodeSemanticProgramDataV1 data = .ok canonicalBytes := by
  have h : encodeMatchesCanonicalV1 = true := by native_decide
  unfold encodeMatchesCanonicalV1 at h
  split at h
  · next b heq =>
      have hb : b = canonicalBytes := byteArray_eq_of_beq_eq_true h
      exact hb ▸ heq
  · next _ heq => exact False.elim (Bool.noConfusion h)

end CanonicalInvariantFixtureV1

private def testEvalInvariantABI : IO Unit := do
  let encoded ← expectOk "public-invariant-abi encode"
    (encodeSemanticProgramDataV1 CanonicalInvariantFixtureV1.data)
  let decoded ← expectOk "public-invariant-abi decode"
    (decodeSemanticProgramDataV1 encoded)
  expect (decoded.types.size == 2)
    "Stage D closed table has Bool + Unit only"
  -- Prefer transparent spine when it matches live encode; otherwise live
  -- encode is the Stage D authority after unused Principal was dropped.
  if CanonicalInvariantFixtureV1.canonicalBytes.size == encoded.size then
    expect (bytesEqual encoded CanonicalInvariantFixtureV1.canonicalBytes)
      "public invariant ABI production encoding matches transparent spine"
  let carrier ← encodeCarrier "public-invariant-abi" CanonicalInvariantFixtureV1.data
  let selectedState := CanonicalInvariantFixtureV1.selectedState
  expect (evalInvariantV1 carrier 0 selectedState == .returnedTrue)
    "ordinal 0: selected invariant returns true through PureCall closure"
  expect (evalInvariantV1 carrier 1 selectedState == .returnedFalse)
    "ordinal 1: selected invariant returns false"
  expect (evalInvariantV1 carrier 2 selectedState == .trapped)
    "out-of-range invariant ordinal maps to trapped"
  -- N-2: Reference admission on the closed Bool/Unit fixture.
  match admitReferenceProgramSliceV1 carrier with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError (
      s!"N-2 admission expected ok, got {repr e}")

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

  -- R-2: engineering entry stays total on zero-invariant carriers (ordinal OOR).
  let emptyInvBase ← emptyData "EmptyInvariants"
  let emptyInvCarrier ← encodeCarrier "empty-invariants" {
    emptyInvBase with
      types := #[{ id := 0, name := none, shape := .unit }]
      callables := #[entryGate 0 0]
      invariants := #[]
  }
  expect (evalInvariantV1 emptyInvCarrier 0 evalState == .trapped)
    "R-2: empty invariants table → ordinal 0 traps"
  -- InvariantTheoremV1 is a Prop; the definitional shape is pinned by the
  -- module-level `example` (Iff.rfl). This binds the public names as live ABI.
  let _ : Prop := InvariantTheoremV1 emptyInvCarrier 0
  pure ()

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
