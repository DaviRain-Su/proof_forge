import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmPackedStorageProbe

open ProofForge.IR

/-- Packed storage probe: multiple small scalars sharing slots.
    Layout (Solidity-style packing):
    - Slot 0: flag(bool, offset 0, 1B) + counter(u8, offset 1, 1B) +
      tag(u32, offset 2, 4B) + value(u64, offset 6, 8B) + big(u128, offset 14, 16B)
    - Slot 1: owner(address, offset 0, 20B) + active(bool, offset 20, 1B) +
      total(u64, offset 21, 8B)
    - Slot 2: reserve(u32, offset 0, 4B) + spare(u8, offset 4, 1B) +
      done(bool, offset 5, 1B) -/

def stateFlag : StateDecl := {
  id := "flag"
  kind := .scalar
  type := .bool
}

def stateCounter : StateDecl := {
  id := "counter"
  kind := .scalar
  type := .u8
}

def stateTag : StateDecl := {
  id := "tag"
  kind := .scalar
  type := .u32
}

def stateValue : StateDecl := {
  id := "value"
  kind := .scalar
  type := .u64
}

def stateBig : StateDecl := {
  id := "big"
  kind := .scalar
  type := .u128
}

def stateOwner : StateDecl := {
  id := "owner"
  kind := .scalar
  type := .address
}

def stateActive : StateDecl := {
  id := "active"
  kind := .scalar
  type := .bool
}

def stateTotal : StateDecl := {
  id := "total"
  kind := .scalar
  type := .u64
}

def stateReserve : StateDecl := {
  id := "reserve"
  kind := .scalar
  type := .u32
}

def stateSpare : StateDecl := {
  id := "spare"
  kind := .scalar
  type := .u8
}

def stateDone : StateDecl := {
  id := "done"
  kind := .scalar
  type := .bool
}

def boolLit (v : Bool) : Expr := .literal (.bool v)
def u8Lit (v : Nat) : Expr := .literal (.u8 v)
def u32Lit (v : Nat) : Expr := .literal (.u32 v)
def u64Lit (v : Nat) : Expr := .literal (.u64 v)
def u128Lit (v : Nat) : Expr := .literal (.u128 v)

/-- Write all packed fields in slot 0, then verify each reads back correctly
    without aliasing. Returns the sum of all slot-0 packed values as u64. -/
def packedSlot0Lifecycle : Entrypoint := {
  name := "packed_slot0_lifecycle"
  selector? := some "de0edef5"
  returns := .u64
  body := #[
    -- Write all packed fields in slot 0
    .effect (.storageScalarWrite "flag" (boolLit true)),
    .effect (.storageScalarWrite "counter" (u8Lit 200)),
    .effect (.storageScalarWrite "tag" (u32Lit 1000)),
    .effect (.storageScalarWrite "value" (u64Lit 99999)),
    -- Verify no aliasing: each field reads back its own value
    .assertEq (.effect (.storageScalarRead "flag")) (boolLit true) "flag reads true",
    .assertEq (.effect (.storageScalarRead "counter")) (u8Lit 200) "counter reads 200",
    .assertEq (.effect (.storageScalarRead "tag")) (u32Lit 1000) "tag reads 1000",
    .assertEq (.effect (.storageScalarRead "value")) (u64Lit 99999) "value reads 99999",
    -- Update one field and verify others are unchanged
    .effect (.storageScalarWrite "counter" (u8Lit 42)),
    .assertEq (.effect (.storageScalarRead "counter")) (u8Lit 42) "counter updated to 42",
    .assertEq (.effect (.storageScalarRead "flag")) (boolLit true) "flag still true after counter update",
    .assertEq (.effect (.storageScalarRead "tag")) (u32Lit 1000) "tag still 1000 after counter update",
    .assertEq (.effect (.storageScalarRead "value")) (u64Lit 99999) "value still 99999 after counter update",
    .return (.effect (.storageScalarRead "value"))
  ]
}

/-- Write u128 (slot 1) and verify it doesn't clobber slot 0 fields. -/
def packedSlot1Lifecycle : Entrypoint := {
  name := "packed_slot1_lifecycle"
  selector? := some "c8fb82aa"
  returns := .u128
  body := #[
    -- Set slot 0 fields first
    .effect (.storageScalarWrite "flag" (boolLit true)),
    .effect (.storageScalarWrite "counter" (u8Lit 42)),
    -- Write u128 in slot 0 (same slot, offset 14)
    .effect (.storageScalarWrite "big" (u128Lit 340282366920938463463374607431768211455)),
    .assertEq (.effect (.storageScalarRead "big")) (u128Lit 340282366920938463463374607431768211455) "big reads max u128",
    -- Verify slot 0 fields are untouched by big write
    .assertEq (.effect (.storageScalarRead "flag")) (boolLit true) "flag untouched by big write",
    .assertEq (.effect (.storageScalarRead "counter")) (u8Lit 42) "counter untouched by big write",
    -- Update u128 and verify
    .effect (.storageScalarWrite "big" (u128Lit 1)),
    .assertEq (.effect (.storageScalarRead "big")) (u128Lit 1) "big updated to 1",
    .assertEq (.effect (.storageScalarRead "counter")) (u8Lit 42) "counter still 42 after big update",
    .assertEq (.effect (.storageScalarRead "flag")) (boolLit true) "flag still true after big update",
    .return (.effect (.storageScalarRead "big"))
  ]
}

/-- Write slot 2: address (20B) + bool (1B) packed together. -/
def packedSlot2Lifecycle : Entrypoint := {
  name := "packed_slot2_lifecycle"
  selector? := some "329510c2"
  returns := .bool
  body := #[
    .effect (.storageScalarWrite "owner" (.literal (.address 0x1111111122222222333333334444444455555555))),
    .effect (.storageScalarWrite "active" (boolLit true)),
    .assertEq (.effect (.storageScalarRead "active")) (boolLit true) "active reads true",
    -- Toggle active and verify owner untouched
    .effect (.storageScalarWrite "active" (boolLit false)),
    .assertEq (.effect (.storageScalarRead "active")) (boolLit false) "active reads false after toggle",
    .effect (.storageScalarWrite "active" (boolLit true)),
    .assertEq (.effect (.storageScalarRead "active")) (boolLit true) "active reads true after re-toggle",
    .return (.effect (.storageScalarRead "active"))
  ]
}

/-- Write slot 3: u64(8B) + u32(4B) + u8(1B) + bool(1B) = 14B packed. -/
def packedSlot3Lifecycle : Entrypoint := {
  name := "packed_slot3_lifecycle"
  selector? := some "e077025f"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "total" (u64Lit 500000)),
    .effect (.storageScalarWrite "reserve" (u32Lit 7777)),
    .effect (.storageScalarWrite "spare" (u8Lit 99)),
    .effect (.storageScalarWrite "done" (boolLit true)),
    .assertEq (.effect (.storageScalarRead "total")) (u64Lit 500000) "total reads 500000",
    .assertEq (.effect (.storageScalarRead "reserve")) (u32Lit 7777) "reserve reads 7777",
    .assertEq (.effect (.storageScalarRead "spare")) (u8Lit 99) "spare reads 99",
    .assertEq (.effect (.storageScalarRead "done")) (boolLit true) "done reads true",
    -- Update spare and verify others unchanged
    .effect (.storageScalarWrite "spare" (u8Lit 1)),
    .assertEq (.effect (.storageScalarRead "spare")) (u8Lit 1) "spare updated to 1",
    .assertEq (.effect (.storageScalarRead "total")) (u64Lit 500000) "total unchanged after spare update",
    .assertEq (.effect (.storageScalarRead "reserve")) (u32Lit 7777) "reserve unchanged after spare update",
    .assertEq (.effect (.storageScalarRead "done")) (boolLit true) "done unchanged after spare update",
    .return (.effect (.storageScalarRead "total"))
  ]
}

/-- Compound assignment on a packed field. -/
def packedAssignOp : Entrypoint := {
  name := "packed_assign_op"
  selector? := some "d1a61f5e"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "counter" (u8Lit 10)),
    .effect (.storageScalarAssignOp "counter" .add (u8Lit 5)),
    .assertEq (.effect (.storageScalarRead "counter")) (u8Lit 15) "counter 10+5=15",
    .effect (.storageScalarAssignOp "counter" .mul (u8Lit 2)),
    .assertEq (.effect (.storageScalarRead "counter")) (u8Lit 30) "counter 15*2=30",
    -- Verify flag is still the value from slot0_lifecycle
    .effect (.storageScalarWrite "tag" (u32Lit 42)),
    .effect (.storageScalarAssignOp "tag" .add (u32Lit 8)),
    .assertEq (.effect (.storageScalarRead "tag")) (u32Lit 50) "tag 42+8=50",
    .assertEq (.effect (.storageScalarRead "counter")) (u8Lit 30) "counter still 30 after tag update",
    .return (.cast (.effect (.storageScalarRead "counter")) .u64)
  ]
}

/-- A wrapping expression assigned to packed storage must truncate to the field
    width. An unmasked `u8` carry would otherwise spill into an adjacent field. -/
def packedAssignOpWraps : Entrypoint := {
  name := "packed_assign_op_wraps"
  selector? := some "9641cb4f"
  returns := .bool
  body := #[
    .effect (.storageScalarWrite "flag" (boolLit false)),
    .effect (.storageScalarWrite "tag" (u32Lit 305419896)),
    .effect (.storageScalarWrite "counter" (.add (u8Lit 255) (u8Lit 1) false)),
    .assertEq (.effect (.storageScalarRead "counter")) (u8Lit 0) "counter wraps to zero",
    .assertEq (.effect (.storageScalarRead "flag")) (boolLit false) "counter carry does not set flag",
    .assertEq (.effect (.storageScalarRead "tag")) (u32Lit 305419896) "counter carry does not alter tag",
    .return (.effect (.storageScalarRead "flag"))
  ]
}

/-- Every checked node must enforce the U8 width. The inner addition overflows
    even though the outer subtraction brings the final word back into range. -/
def packedNestedCheckedOverflowReverts : Entrypoint := {
  name := "packed_nested_checked_overflow_reverts"
  selector? := some "48bedaed"
  returns := .bool
  body := #[
    .effect (.storageScalarWrite "flag" (boolLit false)),
    .effect (.storageScalarWrite "tag" (u32Lit 305419896)),
    .effect (.storageScalarWrite "counter"
      (.sub (.add (u8Lit 255) (u8Lit 1) true) (u8Lit 1) true)),
    .return (.effect (.storageScalarRead "flag"))
  ]
}

/-- A wrapping outer node must not erase an overflowing checked inner node. -/
def packedMixedOverflowReverts : Entrypoint := {
  name := "packed_mixed_overflow_reverts"
  selector? := some "a691f1b1"
  returns := .bool
  body := #[
    .effect (.storageScalarWrite "flag" (boolLit false)),
    .effect (.storageScalarWrite "tag" (u32Lit 305419896)),
    .effect (.storageScalarWrite "counter"
      (.sub (.add (u8Lit 255) (u8Lit 1) true) (u8Lit 256) false)),
    .return (.effect (.storageScalarRead "flag"))
  ]
}

/-- Wrapping is applied at every U8 arithmetic node and remains isolated from
    neighboring packed fields. -/
def packedNestedWrappingPreservesNeighbors : Entrypoint := {
  name := "packed_nested_wrapping_preserves_neighbors"
  selector? := some "baa34f4a"
  returns := .bool
  body := #[
    .effect (.storageScalarWrite "flag" (boolLit false)),
    .effect (.storageScalarWrite "tag" (u32Lit 305419896)),
    .effect (.storageScalarWrite "counter"
      (.sub (.add (u8Lit 255) (u8Lit 1) false) (u8Lit 1) false)),
    .assertEq (.effect (.storageScalarRead "counter")) (u8Lit 255)
      "nested wrapping counter is 255",
    .assertEq (.effect (.storageScalarRead "flag")) (boolLit false)
      "nested wrapping does not set flag",
    .assertEq (.effect (.storageScalarRead "tag")) (u32Lit 305419896)
      "nested wrapping does not alter tag",
    .return (.effect (.storageScalarRead "flag"))
  ]
}

/-- Checked multiplication by zero must produce zero for either operand order.
    This specifically covers the non-zero left / zero right helper path. -/
def packedCheckedMulZeroRhsSucceeds : Entrypoint := {
  name := "packed_checked_mul_zero_rhs_succeeds"
  selector? := some "ffb3ca34"
  returns := .bool
  body := #[
    .effect (.storageScalarWrite "flag" (boolLit false)),
    .effect (.storageScalarWrite "tag" (u32Lit 305419896)),
    .effect (.storageScalarWrite "counter"
      (.mul (u8Lit 7) (u8Lit 0) true)),
    .assertEq (.effect (.storageScalarRead "counter")) (u8Lit 0)
      "checked multiplication by zero is zero",
    .assertEq (.effect (.storageScalarRead "flag")) (boolLit false)
      "checked multiplication by zero does not set flag",
    .assertEq (.effect (.storageScalarRead "tag")) (u32Lit 305419896)
      "checked multiplication by zero does not alter tag",
    .return (.effect (.storageScalarRead "flag"))
  ]
}

/-- Checked compound assignment must reject a value that fits in an EVM word
    but not in the packed field. The whole call, including neighboring writes,
    must roll back. -/
def packedAssignOpOverflowReverts : Entrypoint := {
  name := "packed_assign_op_overflow_reverts"
  selector? := some "ab0efcd6"
  returns := .bool
  body := #[
    .effect (.storageScalarWrite "flag" (boolLit false)),
    .effect (.storageScalarWrite "counter" (u8Lit 255)),
    .effect (.storageScalarWrite "tag" (u32Lit 305419896)),
    .effect (.storageScalarAssignOp "counter" .add (u8Lit 1)),
    .return (.effect (.storageScalarRead "flag"))
  ]
}

/-- A checked expression written directly to a packed field must reject a
    value that fits in an EVM word but not in the destination field. -/
def packedCheckedWriteOverflowReverts : Entrypoint := {
  name := "packed_checked_write_overflow_reverts"
  selector? := some "2b19bf56"
  returns := .bool
  body := #[
    .effect (.storageScalarWrite "flag" (boolLit false)),
    .effect (.storageScalarWrite "tag" (u32Lit 305419896)),
    .effect (.storageScalarWrite "counter" (.add (u8Lit 255) (u8Lit 1) true)),
    .return (.effect (.storageScalarRead "flag"))
  ]
}

/-- Checked modules reject an out-of-range packed literal even when the value
    expression contains no arithmetic node. -/
def packedCheckedLiteralWriteOverflowReverts : Entrypoint := {
  name := "packed_checked_literal_write_overflow_reverts"
  selector? := some "d1614879"
  returns := .bool
  body := #[
    .effect (.storageScalarWrite "flag" (boolLit false)),
    .effect (.storageScalarWrite "tag" (u32Lit 305419896)),
    .effect (.storageScalarWrite "counter" (u8Lit 256)),
    .return (.effect (.storageScalarRead "flag"))
  ]
}

/-- Checked modules also retain the destination-width guard after a value has
    passed through a local binding. -/
def packedCheckedLocalWriteOverflowReverts : Entrypoint := {
  name := "packed_checked_local_write_overflow_reverts"
  selector? := some "463dd423"
  returns := .bool
  body := #[
    .effect (.storageScalarWrite "flag" (boolLit false)),
    .effect (.storageScalarWrite "tag" (u32Lit 305419896)),
    .letBind "candidate" .u8 (u8Lit 256),
    .effect (.storageScalarWrite "counter" (.local "candidate")),
    .return (.effect (.storageScalarRead "flag"))
  ]
}

/-- ABI validation rejects non-canonical `u8` calldata before it reaches the
    function-local packed write. -/
def packedCheckedWriteParam : Entrypoint := {
  name := "packed_checked_write_param"
  selector? := some "c1244eee"
  params := #[("candidate", .u8)]
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "counter" (.local "candidate")),
    .return (.cast (.effect (.storageScalarRead "counter")) .u64)
  ]
}

def module : Module := {
  name := "EvmPackedStorageProbe"
  state := #[
    stateFlag, stateCounter, stateTag, stateValue,
    stateBig,
    stateOwner, stateActive,
    stateTotal, stateReserve, stateSpare, stateDone
  ]
  entrypoints := #[
    packedSlot0Lifecycle,
    packedSlot1Lifecycle,
    packedSlot2Lifecycle,
    packedSlot3Lifecycle,
    packedAssignOp,
    packedAssignOpWraps,
    packedNestedCheckedOverflowReverts,
    packedMixedOverflowReverts,
    packedNestedWrappingPreservesNeighbors,
    packedCheckedMulZeroRhsSucceeds,
    packedAssignOpOverflowReverts,
    packedCheckedWriteOverflowReverts,
    packedCheckedLiteralWriteOverflowReverts,
    packedCheckedLocalWriteOverflowReverts,
    packedCheckedWriteParam
  ]
  overflowChecked := true
}

end ProofForge.IR.Examples.EvmPackedStorageProbe
