import ProofForgeV2.Targets.Near.LowerSemanticV1

/-!
# NEAR bounded MethodWATV1

A typed representation of the bounded WAT instruction subset used by NEAR
target refinement. The production NEAR renderer consumes this representation
directly; it is therefore not a parallel renderer or a second business
semantics. The historical public names retain the `ReadOnlyWAT` prefix while
the canonical `MethodWAT` aliases below expose the same single syntax as the
subset grows beyond the first view slice.

The retained `KeyRegion` on `storageRead` is a proof-relevant annotation for
the module data segment whose WAT operands are its offset and length. A later
module gives this bounded instruction subset execution semantics. This module
only owns typed syntax and its sole text renderer.
-/

namespace ProofForgeV2.Targets.Near

/-- Typed i64 expressions needed by the nullary UInt64 view WAT recipe. -/
inductive ReadOnlyWATI64ExprV1 where
  | i64Const (value : Nat)
  | localGet (index : Nat)
  | i64Load (offset : Nat)
  | i64Add (left right : ReadOnlyWATI64ExprV1)
  | registerLen (register : Nat)
  | storageRead (field : KeyRegion) (register : Nat)
  /-- Exact 8-byte `storage_write` expression. It returns 1 when the key was
      present and fills `register` with the old value, or returns 0 when absent. -/
  | storageWrite (field : KeyRegion) (byteLen offset register : Nat)
  deriving BEq, Inhabited, Repr

/-- Typed WAT instructions needed by the nullary UInt64 view recipe. Invalid
    host-call arities cannot be represented by this syntax. -/
inductive ReadOnlyWATInstructionV1 where
  | input (register : Nat)
  /-- `attached_deposit` writes two little-endian UInt64 limbs at `offset`. -/
  | attachedDeposit (offset : Nat)
  | trapIfI64Ne (left right : ReadOnlyWATI64ExprV1)
  | trapIfI64LtU (left right : ReadOnlyWATI64ExprV1)
  | readRegister (register offset : Nat)
  | localSet (index : Nat) (value : ReadOnlyWATI64ExprV1)
  | i64Store (offset : Nat) (value : ReadOnlyWATI64ExprV1)
  | valueReturn (byteLen offset : Nat)
  deriving BEq, Inhabited, Repr

/-- Canonical names for the one bounded method-WAT syntax. These are aliases,
    not a second representation. -/
abbrev MethodWATI64ExprV1 := ReadOnlyWATI64ExprV1
abbrev MethodWATInstructionV1 := ReadOnlyWATInstructionV1

/-- Source-order concatenation shared by complete typed method recipes and the
    production operation lowering. Keeping recipes as lists of operation-sized
    arrays avoids a second instruction sequence or renderer. -/
def concatMethodWATRecipesV1 :
    List (Array MethodWATInstructionV1) → Array MethodWATInstructionV1
  | [] => #[]
  | recipe :: remaining => recipe ++ concatMethodWATRecipesV1 remaining

/-- Typed WAT for the production `checkInputLen 0` operation. -/
def checkEmptyInputWATV1 (registers : RegisterLayout) :
    Array ReadOnlyWATInstructionV1 := #[
  .input registers.input,
  .trapIfI64Ne (.registerLen registers.input) (.i64Const 0)
]

/-- Typed WAT for the production exact 8-byte UInt64 input operation. -/
def checkUInt64InputWATV1
    (registers : RegisterLayout)
    (memory : MemoryLayout) : Array MethodWATInstructionV1 := #[
  .input registers.input,
  .trapIfI64Ne (.registerLen registers.input) (.i64Const 8),
  .readRegister registers.input memory.inputOffset
]

/-- Typed WAT for the production layout-marker guard. -/
def requireLayoutWATV1
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker : KeyRegion)
    (value : UInt64) : Array ReadOnlyWATInstructionV1 := #[
  .trapIfI64Ne (.storageRead marker registers.storage) (.i64Const 1),
  .trapIfI64Ne (.registerLen registers.storage) (.i64Const 8),
  .readRegister registers.storage memory.valueOffset,
  .trapIfI64Ne (.i64Load memory.valueOffset) (.i64Const value.toNat)
]

/-- Typed WAT for one 8-byte state read into an i64 local. -/
def loadUInt64StateWATV1
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (destination : Nat)
    (field : KeyRegion) : Array ReadOnlyWATInstructionV1 := #[
  .trapIfI64Ne (.storageRead field registers.storage) (.i64Const 1),
  .trapIfI64Ne (.registerLen registers.storage) (.i64Const 8),
  .readRegister registers.storage memory.valueOffset,
  .localSet destination (.i64Load memory.valueOffset)
]

/-- Typed WAT for one canonical 8-byte UInt64 return. -/
def returnUInt64WATV1
    (memory : MemoryLayout)
    (source : Nat) : Array ReadOnlyWATInstructionV1 := #[
  .i64Store memory.valueOffset (.localGet source),
  .valueReturn 8 memory.valueOffset
]

/-- Complete typed WAT instruction sequence for the production nullary UInt64
    view recipe. -/
def nullaryUInt64ViewWATV1
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker : KeyRegion)
    (markerValue : UInt64)
    (field : KeyRegion) : Array ReadOnlyWATInstructionV1 :=
  concatMethodWATRecipesV1 [
    checkEmptyInputWATV1 registers,
    requireLayoutWATV1 registers memory marker markerValue,
    loadUInt64StateWATV1 registers memory 0 field,
    returnUInt64WATV1 memory 0
  ]

/-- Typed WAT for the production zero-attached-deposit gate. -/
def requireZeroAttachedDepositWATV1
    (memory : MemoryLayout) : Array MethodWATInstructionV1 := #[
  .attachedDeposit memory.depositOffset,
  .trapIfI64Ne (.i64Load memory.depositOffset) (.i64Const 0),
  .trapIfI64Ne (.i64Load (memory.depositOffset + 8)) (.i64Const 0)
]

/-- Typed WAT for the production absent-layout guard. -/
def requireLayoutAbsentWATV1
    (registers : RegisterLayout)
    (marker : KeyRegion) : Array MethodWATInstructionV1 := #[
  .trapIfI64Ne (.storageRead marker registers.storage) (.i64Const 0)
]

/-- Typed WAT for one initializer zero write to a previously absent UInt64
    state field. -/
def zeroUInt64StateWATV1
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (field : KeyRegion) : Array MethodWATInstructionV1 := #[
  .i64Store memory.valueOffset (.i64Const 0),
  .trapIfI64Ne
    (.storageWrite field 8 memory.valueOffset registers.evicted)
    (.i64Const 0)
]

/-- Typed WAT for one UInt64 local literal. -/
def uint64LiteralWATV1
    (destination : Nat) (value : UInt64) : Array MethodWATInstructionV1 := #[
  .localSet destination (.i64Const value.toNat)
]

/-- Typed WAT for loading one exact 8-byte ABI parameter. -/
def loadUInt64ParamWATV1
    (memory : MemoryLayout)
    (destination inputOffset : Nat) : Array MethodWATInstructionV1 := #[
  .localSet destination (.i64Load (memory.inputOffset + inputOffset))
]

/-- Typed WAT for checked UInt64 addition. Wasm addition wraps first; the
    unsigned result-less-than-left guard traps exactly on carry. -/
def checkedAddUInt64WATV1
    (destination lhs rhs : Nat) : Array MethodWATInstructionV1 := #[
  .localSet destination (.i64Add (.localGet lhs) (.localGet rhs)),
  .trapIfI64LtU (.localGet destination) (.localGet lhs)
]

/-- Typed WAT for overwriting one existing UInt64 state field from a local. -/
def storeUInt64StateWATV1
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (field : KeyRegion)
    (source : Nat) : Array MethodWATInstructionV1 := #[
  .i64Store memory.valueOffset (.localGet source),
  .trapIfI64Ne
    (.storageWrite field 8 memory.valueOffset registers.evicted)
    (.i64Const 1),
  .trapIfI64Ne (.registerLen registers.evicted) (.i64Const 8)
]

/-- Typed WAT for publishing the layout marker after initializer state writes. -/
def setLayoutWATV1
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker : KeyRegion)
    (markerValue : UInt64) : Array MethodWATInstructionV1 := #[
  .i64Store memory.valueOffset (.i64Const markerValue.toNat),
  .trapIfI64Ne
    (.storageWrite marker 8 memory.valueOffset registers.evicted)
    (.i64Const 0)
]

/-- Complete typed WAT sequence for the production nullary initializer that
    writes canonical zero to two UInt64 fields and then publishes the marker. -/
def nullaryZeroTwoUInt64InitializerWATV1
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64) : Array MethodWATInstructionV1 :=
  concatMethodWATRecipesV1 [
    checkEmptyInputWATV1 registers,
    requireZeroAttachedDepositWATV1 memory,
    requireLayoutAbsentWATV1 registers marker,
    zeroUInt64StateWATV1 registers memory field0,
    zeroUInt64StateWATV1 registers memory field1,
    uint64LiteralWATV1 0 0,
    storeUInt64StateWATV1 registers memory field0 0,
    uint64LiteralWATV1 1 0,
    storeUInt64StateWATV1 registers memory field1 1,
    setLayoutWATV1 registers memory marker markerValue
  ]

/-- Complete typed WAT sequence for the selected unary deposit entry. It
    requires zero attached deposit, checked-adds the same input parameter into
    both UInt64 fields, and returns the second updated field. -/
def unaryAddTwoUInt64DepositWATV1
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64) : Array MethodWATInstructionV1 :=
  concatMethodWATRecipesV1 [
    checkUInt64InputWATV1 registers memory,
    requireZeroAttachedDepositWATV1 memory,
    requireLayoutWATV1 registers memory marker markerValue,
    loadUInt64StateWATV1 registers memory 0 field0,
    loadUInt64ParamWATV1 memory 1 0,
    checkedAddUInt64WATV1 2 0 1,
    storeUInt64StateWATV1 registers memory field0 2,
    loadUInt64StateWATV1 registers memory 3 field1,
    loadUInt64ParamWATV1 memory 4 0,
    checkedAddUInt64WATV1 5 3 4,
    storeUInt64StateWATV1 registers memory field1 5,
    loadUInt64StateWATV1 registers memory 6 field1,
    returnUInt64WATV1 memory 6
  ]

/-- Fail-closed static errors for the bounded typed-WAT subset. This validates
    renderability and the local/key/memory envelope owned by this syntax; it is
    not a validator for arbitrary textual WAT or Wasm modules. -/
inductive ReadOnlyWATValidationErrorV1 where
  | i64ConstantOutOfRange
  | localOutOfBounds
  | keyRegionNotBound
  | memoryOutOfBounds
  | unsupportedStorageWidth
  | unsupportedReturnWidth
  deriving BEq, Repr

abbrev MethodWATValidationErrorV1 := ReadOnlyWATValidationErrorV1

private def validateReadOnlyWATMemoryAccessV1
    (memory : MemoryLayout)
    (offset : Nat) : Except ReadOnlyWATValidationErrorV1 Unit :=
  if offset + 8 ≤ memory.minPages * wasmPageBytes then .ok ()
  else .error .memoryOutOfBounds

/-- Exact fieldwise equality for proof-relevant production data regions. -/
def readOnlyWATKeyRegionEqV1 (left right : KeyRegion) : Bool :=
  left.key == right.key && left.offset == right.offset &&
    left.length == right.length

/-- An exact production key-table lookup is sufficient for the bounded
    validator's region-membership check. -/
theorem readOnlyWATKeyRegionBoundV1_of_getElem?_eq_some
    (keys : Array KeyRegion)
    (index : Nat)
    (region : KeyRegion)
    (hlookup : keys[index]? = some region) :
    keys.any (fun candidate => readOnlyWATKeyRegionEqV1 candidate region) =
      true := by
  rw [Array.getElem?_eq_some_iff] at hlookup
  obtain ⟨hindex, hregion⟩ := hlookup
  rw [Array.any_eq_true]
  refine ⟨index, hindex, ?_⟩
  rw [hregion]
  simp [readOnlyWATKeyRegionEqV1]

/-- Validate one typed i64 expression against the selected method locals,
    production key table, and bounded memory layout. -/
def validateReadOnlyWATI64ExprV1
    (keys : Array KeyRegion)
    (memory : MemoryLayout)
    (localCount : Nat) :
    ReadOnlyWATI64ExprV1 → Except ReadOnlyWATValidationErrorV1 Unit
  | .i64Const value =>
      if value < UInt64.size then .ok ()
      else .error .i64ConstantOutOfRange
  | .localGet index =>
      if index < localCount then .ok ()
      else .error .localOutOfBounds
  | .i64Load offset => validateReadOnlyWATMemoryAccessV1 memory offset
  | .i64Add left right => do
      validateReadOnlyWATI64ExprV1 keys memory localCount left
      validateReadOnlyWATI64ExprV1 keys memory localCount right
  | .registerLen _ => .ok ()
  | .storageRead field _ =>
      if keys.any fun candidate => readOnlyWATKeyRegionEqV1 candidate field then
        .ok ()
      else .error .keyRegionNotBound
  | .storageWrite field byteLen offset _ => do
      if byteLen = 8 then pure ()
      else throw .unsupportedStorageWidth
      if keys.any fun candidate => readOnlyWATKeyRegionEqV1 candidate field then
        pure ()
      else throw .keyRegionNotBound
      validateReadOnlyWATMemoryAccessV1 memory offset

/-- Validate one instruction in the bounded typed-WAT subset. Host-call
    signatures are already fixed by the constructors; this checks their
    embedded expressions, local indices, 8-byte scratch accesses, key-region
    binding, and the execution subset's exact return width. -/
def validateReadOnlyWATInstructionV1
    (keys : Array KeyRegion)
    (memory : MemoryLayout)
    (localCount : Nat) :
    ReadOnlyWATInstructionV1 → Except ReadOnlyWATValidationErrorV1 Unit
  | .input _ => .ok ()
  | .attachedDeposit offset => do
      validateReadOnlyWATMemoryAccessV1 memory offset
      validateReadOnlyWATMemoryAccessV1 memory (offset + 8)
  | .trapIfI64Ne left right => do
      validateReadOnlyWATI64ExprV1 keys memory localCount left
      validateReadOnlyWATI64ExprV1 keys memory localCount right
  | .trapIfI64LtU left right => do
      validateReadOnlyWATI64ExprV1 keys memory localCount left
      validateReadOnlyWATI64ExprV1 keys memory localCount right
  | .readRegister _ offset => validateReadOnlyWATMemoryAccessV1 memory offset
  | .localSet index value => do
      if index < localCount then pure ()
      else throw .localOutOfBounds
      validateReadOnlyWATI64ExprV1 keys memory localCount value
  | .i64Store offset value => do
      validateReadOnlyWATMemoryAccessV1 memory offset
      validateReadOnlyWATI64ExprV1 keys memory localCount value
  | .valueReturn byteLen offset => do
      if byteLen = 8 then pure ()
      else throw .unsupportedReturnWidth
      validateReadOnlyWATMemoryAccessV1 memory offset

/-- Source-order validator for a bounded typed-WAT instruction list. -/
def validateReadOnlyWATInstructionsListV1
    (keys : Array KeyRegion)
    (memory : MemoryLayout)
    (localCount : Nat) :
    List ReadOnlyWATInstructionV1 → Except ReadOnlyWATValidationErrorV1 Unit
  | [] => .ok ()
  | instruction :: remaining => do
      validateReadOnlyWATInstructionV1 keys memory localCount instruction
      validateReadOnlyWATInstructionsListV1 keys memory localCount remaining

/-- Public validator for one method body represented by the bounded typed-WAT
    syntax. -/
def validateReadOnlyWATMethodV1
    (keys : Array KeyRegion)
    (memory : MemoryLayout)
    (localCount : Nat)
    (instructions : Array ReadOnlyWATInstructionV1) :
    Except ReadOnlyWATValidationErrorV1 Unit :=
  validateReadOnlyWATInstructionsListV1 keys memory localCount
    instructions.toList

/-- The exact nullary UInt64 view recipe validates whenever both data-segment
    regions are bound to the selected production key table and its single
    scratch block fits the declared memory. -/
theorem validateReadOnlyWATMethodV1_nullaryUInt64View
    (keys : Array KeyRegion)
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field : KeyRegion)
    (markerValue : UInt64)
    (hmarker :
      keys.any (fun candidate => readOnlyWATKeyRegionEqV1 candidate marker) =
        true)
    (hfield :
      keys.any (fun candidate => readOnlyWATKeyRegionEqV1 candidate field) =
        true)
    (hmemory :
      memory.valueOffset + 8 ≤ memory.minPages * wasmPageBytes) :
    validateReadOnlyWATMethodV1 keys memory 1
      (nullaryUInt64ViewWATV1 registers memory marker markerValue field) =
        .ok () := by
  have hone : (1 : Nat) < UInt64.size := by decide
  have height : (8 : Nat) < UInt64.size := by decide
  simp [validateReadOnlyWATMethodV1, nullaryUInt64ViewWATV1,
    concatMethodWATRecipesV1, checkEmptyInputWATV1, requireLayoutWATV1,
    loadUInt64StateWATV1,
    returnUInt64WATV1, validateReadOnlyWATInstructionsListV1,
    validateReadOnlyWATInstructionV1, validateReadOnlyWATI64ExprV1,
    validateReadOnlyWATMemoryAccessV1, hmarker, hfield, hmemory,
    markerValue.toNat_lt, hone, height, Bind.bind, Except.bind, Pure.pure,
    Except.pure]

/-- The exact two-UInt64 initializer recipe validates when its three key
    regions are production-bound and the deposit/value scratch regions fit. -/
theorem validateReadOnlyWATMethodV1_nullaryZeroTwoUInt64Initializer
    (keys : Array KeyRegion)
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64)
    (hmarker :
      keys.any (fun candidate => readOnlyWATKeyRegionEqV1 candidate marker) =
        true)
    (hfield0 :
      keys.any (fun candidate => readOnlyWATKeyRegionEqV1 candidate field0) =
        true)
    (hfield1 :
      keys.any (fun candidate => readOnlyWATKeyRegionEqV1 candidate field1) =
        true)
    (hdeposit :
      memory.depositOffset + 16 ≤ memory.minPages * wasmPageBytes)
    (hvalue :
      memory.valueOffset + 8 ≤ memory.minPages * wasmPageBytes) :
    validateReadOnlyWATMethodV1 keys memory 2
      (nullaryZeroTwoUInt64InitializerWATV1 registers memory marker field0
        field1 markerValue) = .ok () := by
  have hzero : (0 : Nat) < UInt64.size := by decide
  have hone : (1 : Nat) < UInt64.size := by decide
  have height : (8 : Nat) < UInt64.size := by decide
  have hdepositLow :
      memory.depositOffset + 8 ≤ memory.minPages * wasmPageBytes := by omega
  simp [validateReadOnlyWATMethodV1,
    nullaryZeroTwoUInt64InitializerWATV1, concatMethodWATRecipesV1,
    checkEmptyInputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutAbsentWATV1,
    zeroUInt64StateWATV1, uint64LiteralWATV1, storeUInt64StateWATV1,
    setLayoutWATV1, validateReadOnlyWATInstructionsListV1,
    validateReadOnlyWATInstructionV1, validateReadOnlyWATI64ExprV1,
    validateReadOnlyWATMemoryAccessV1, hmarker, hfield0, hfield1,
    hdeposit, hdepositLow, hvalue, markerValue.toNat_lt, hzero, hone,
    height, Bind.bind, Except.bind, Pure.pure, Except.pure]

/-- The selected unary deposit recipe validates when all canonical key regions
    are bound and its input/deposit/value scratch regions fit. -/
theorem validateMethodWATV1_unaryAddTwoUInt64Deposit
    (keys : Array KeyRegion)
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64)
    (hmarker :
      keys.any (fun candidate => readOnlyWATKeyRegionEqV1 candidate marker) =
        true)
    (hfield0 :
      keys.any (fun candidate => readOnlyWATKeyRegionEqV1 candidate field0) =
        true)
    (hfield1 :
      keys.any (fun candidate => readOnlyWATKeyRegionEqV1 candidate field1) =
        true)
    (hinput :
      memory.inputOffset + 8 ≤ memory.minPages * wasmPageBytes)
    (hdeposit :
      memory.depositOffset + 16 ≤ memory.minPages * wasmPageBytes)
    (hvalue :
      memory.valueOffset + 8 ≤ memory.minPages * wasmPageBytes) :
    validateReadOnlyWATMethodV1 keys memory 7
      (unaryAddTwoUInt64DepositWATV1 registers memory marker field0 field1
        markerValue) = .ok () := by
  have hzero : (0 : Nat) < UInt64.size := by decide
  have hone : (1 : Nat) < UInt64.size := by decide
  have height : (8 : Nat) < UInt64.size := by decide
  have hdepositLow :
      memory.depositOffset + 8 ≤ memory.minPages * wasmPageBytes := by omega
  simp [validateReadOnlyWATMethodV1, unaryAddTwoUInt64DepositWATV1,
    concatMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutWATV1,
    loadUInt64StateWATV1, loadUInt64ParamWATV1, checkedAddUInt64WATV1,
    storeUInt64StateWATV1, returnUInt64WATV1,
    validateReadOnlyWATInstructionsListV1,
    validateReadOnlyWATInstructionV1, validateReadOnlyWATI64ExprV1,
    validateReadOnlyWATMemoryAccessV1, hmarker, hfield0, hfield1,
    hinput, hdeposit, hdepositLow, hvalue, markerValue.toNat_lt,
    hzero, hone, height, Bind.bind, Except.bind, Pure.pure, Except.pure]

/-- Canonical aliases for the one bounded method-WAT validator. -/
abbrev validateMethodWATI64ExprV1 := validateReadOnlyWATI64ExprV1
abbrev validateMethodWATInstructionV1 := validateReadOnlyWATInstructionV1
abbrev validateMethodWATInstructionsListV1 :=
  validateReadOnlyWATInstructionsListV1
abbrev validateMethodWATV1 := validateReadOnlyWATMethodV1

/-- Sole text renderer for the bounded typed i64 expression syntax. -/
def renderReadOnlyWATI64ExprV1 : ReadOnlyWATI64ExprV1 → String
  | .i64Const value => s!"(i64.const {value})"
  | .localGet index => s!"(local.get $t{index})"
  | .i64Load offset => s!"(i64.load (i32.const {offset}))"
  | .i64Add left right =>
      s!"(i64.add {renderReadOnlyWATI64ExprV1 left} " ++
        s!"{renderReadOnlyWATI64ExprV1 right})"
  | .registerLen register =>
      s!"(call $pf_register_len (i64.const {register}))"
  | .storageRead field register =>
      s!"(call $pf_storage_read (i64.const {field.length}) " ++
        s!"(i64.const {field.offset}) (i64.const {register}))"
  | .storageWrite field byteLen offset register =>
      s!"(call $pf_storage_write (i64.const {field.length}) " ++
        s!"(i64.const {field.offset}) (i64.const {byteLen}) " ++
        s!"(i64.const {offset}) (i64.const {register}))"

/-- Sole text renderer for one bounded typed WAT instruction. -/
def renderReadOnlyWATInstructionV1
    (indent : String) : ReadOnlyWATInstructionV1 → String
  | .input register =>
      s!"{indent}(call $pf_input (i64.const {register}))\n"
  | .attachedDeposit offset =>
      s!"{indent}(call $pf_attached_deposit (i64.const {offset}))\n"
  | .trapIfI64Ne left right =>
      s!"{indent}(if (i64.ne {renderReadOnlyWATI64ExprV1 left} " ++
        s!"{renderReadOnlyWATI64ExprV1 right}) (then unreachable))\n"
  | .trapIfI64LtU left right =>
      s!"{indent}(if (i64.lt_u {renderReadOnlyWATI64ExprV1 left} " ++
        s!"{renderReadOnlyWATI64ExprV1 right}) (then unreachable))\n"
  | .readRegister register offset =>
      s!"{indent}(call $pf_read_register (i64.const {register}) " ++
        s!"(i64.const {offset}))\n"
  | .localSet index value =>
      s!"{indent}(local.set $t{index} {renderReadOnlyWATI64ExprV1 value})\n"
  | .i64Store offset value =>
      s!"{indent}(i64.store (i32.const {offset}) " ++
        s!"{renderReadOnlyWATI64ExprV1 value})\n"
  | .valueReturn byteLen offset =>
      s!"{indent}(call $pf_value_return (i64.const {byteLen}) " ++
        s!"(i64.const {offset}))\n"

/-- Render a typed instruction array in source order. -/
def renderReadOnlyWATInstructionsV1
    (indent : String)
    (instructions : Array ReadOnlyWATInstructionV1) : String :=
  String.intercalate "" <|
    instructions.toList.map (renderReadOnlyWATInstructionV1 indent)

/-- Exact exported-function wrapper for a method wholly represented by the
    bounded typed WAT subset. -/
def renderReadOnlyWATMethodV1
    (name : String)
    (tempCount : Nat)
    (instructions : Array ReadOnlyWATInstructionV1) : String :=
  let locals := String.intercalate "" <|
    (Array.range tempCount).toList.map fun index => s!" (local $t{index} i64)"
  s!"  (func (export \"{name}\"){locals}\n" ++
    renderReadOnlyWATInstructionsV1 "    " instructions ++ "  )\n"

/-- Canonical aliases for the sole bounded method-WAT renderer. -/
abbrev renderMethodWATI64ExprV1 := renderReadOnlyWATI64ExprV1
abbrev renderMethodWATInstructionV1 := renderReadOnlyWATInstructionV1
abbrev renderMethodWATInstructionsV1 := renderReadOnlyWATInstructionsV1
abbrev renderMethodWATV1 := renderReadOnlyWATMethodV1

end ProofForgeV2.Targets.Near
