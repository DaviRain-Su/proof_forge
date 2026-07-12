import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.U128StorageScalarProbe

open ProofForge.IR

def stateValue : StateDecl := {
  id := "value"
  kind := .scalar
  type := .u128
}

def u128 (value : Nat) : Expr :=
  .literal (.u128 value)

def readValue : Expr :=
  .effect (.storageScalarRead "value")

/-! U128 storage lifecycle: write u128(7), assignOp add 5 (-> 12), read back,
    and return it directly (no let-bind — two-word u128 locals are a separate
    gap). A correct lowering returns `0c000000000000000000000000000000`
    (= u128 12) via `__pf_return_u128`. Exercises 16-byte scalar write/read,
    the two-word (lo, hi) convention, and U128 scalar `assignOp`
    (read + `__pf_u128_add` + write). -/
def storageLifecycle : Entrypoint := {
  name := "storage_lifecycle"
  returns := .u128
  body := #[
    .effect (.storageScalarWrite "value" (u128 7)),
    .effect (.storageScalarAssignOp "value" .add (u128 5)),
    .return readValue
  ]
}

/-! Minimal U128 storage round-trip: write u128(7), read it back, return it. -/
def storageRoundTrip : Entrypoint := {
  name := "storage_roundtrip"
  returns := .u128
  body := #[
    .effect (.storageScalarWrite "value" (u128 7)),
    .letBind "result" .u128 readValue,
    .return (.local "result")
  ]
}

/-! U128 comparison check: write 7, assignOp add 5 (-> 12), return
    (read >= 10) as a bool. Validates the U128 `ge` lowering (`__pf_u128_lt` +
    i32.eqz) without let-binding a u128 (two-word locals are a separate gap).
    A correct lowering returns bool 1. -/
def storageGe : Entrypoint := {
  name := "storage_ge"
  returns := .bool
  body := #[
    .effect (.storageScalarWrite "value" (u128 7)),
    .effect (.storageScalarAssignOp "value" .add (u128 5)),
    .return (.ge readValue (u128 10))
  ]
}

def module : Module := {
  name := "U128StorageScalarProbe"
  state := #[stateValue]
  entrypoints := #[storageLifecycle, storageRoundTrip, storageGe]
}

end ProofForge.IR.Examples.U128StorageScalarProbe
