import ProofForgeV2.Targets.Near.LowerSemanticV1

/-!
# NEAR ReadOnlyWATV1

A typed representation of the exact WAT instruction subset used by the first
read-only target refinement slice. The production NEAR renderer consumes this
representation directly; it is therefore not a parallel renderer or a second
business semantics.

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
  | registerLen (register : Nat)
  | storageRead (field : KeyRegion) (register : Nat)
  deriving BEq, Inhabited, Repr

/-- Typed WAT instructions needed by the nullary UInt64 view recipe. Invalid
    host-call arities cannot be represented by this syntax. -/
inductive ReadOnlyWATInstructionV1 where
  | input (register : Nat)
  | trapIfI64Ne (left right : ReadOnlyWATI64ExprV1)
  | readRegister (register offset : Nat)
  | localSet (index : Nat) (value : ReadOnlyWATI64ExprV1)
  | i64Store (offset : Nat) (value : ReadOnlyWATI64ExprV1)
  | valueReturn (byteLen offset : Nat)
  deriving BEq, Inhabited, Repr

/-- Typed WAT for the production `checkInputLen 0` operation. -/
def checkEmptyInputWATV1 (registers : RegisterLayout) :
    Array ReadOnlyWATInstructionV1 := #[
  .input registers.input,
  .trapIfI64Ne (.registerLen registers.input) (.i64Const 0)
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
  checkEmptyInputWATV1 registers ++
    requireLayoutWATV1 registers memory marker markerValue ++
    loadUInt64StateWATV1 registers memory 0 field ++
    returnUInt64WATV1 memory 0

/-- Sole text renderer for the bounded typed i64 expression syntax. -/
def renderReadOnlyWATI64ExprV1 : ReadOnlyWATI64ExprV1 → String
  | .i64Const value => s!"(i64.const {value})"
  | .localGet index => s!"(local.get $t{index})"
  | .i64Load offset => s!"(i64.load (i32.const {offset}))"
  | .registerLen register =>
      s!"(call $pf_register_len (i64.const {register}))"
  | .storageRead field register =>
      s!"(call $pf_storage_read (i64.const {field.length}) " ++
        s!"(i64.const {field.offset}) (i64.const {register}))"

/-- Sole text renderer for one bounded typed WAT instruction. -/
def renderReadOnlyWATInstructionV1
    (indent : String) : ReadOnlyWATInstructionV1 → String
  | .input register =>
      s!"{indent}(call $pf_input (i64.const {register}))\n"
  | .trapIfI64Ne left right =>
      s!"{indent}(if (i64.ne {renderReadOnlyWATI64ExprV1 left} " ++
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

end ProofForgeV2.Targets.Near
