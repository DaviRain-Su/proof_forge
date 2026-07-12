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

/-! Minimal u128 storage round-trip: write u128(7), read it back, return it.
    A correct end-to-end lowering must return the 16-byte little-endian Borsh
    encoding `0700000000000000 0000000000000000` (= u128 7) via `__pf_return_u128`.
    This exercises the legacy EmitWat u128 path (16-byte scalar storage,
    `__pf_u128` representation, and `returnU128Name`) that NEP-141 U128 amounts
    will rely on. -/
def storageLifecycle : Entrypoint := {
  name := "storage_lifecycle"
  returns := .u128
  body := #[
    .effect (.storageScalarWrite "value" (u128 7)),
    .letBind "result" .u128 readValue,
    .return (.local "result")
  ]
}

def module : Module := {
  name := "U128StorageScalarProbe"
  state := #[stateValue]
  entrypoints := #[storageLifecycle]
}

end ProofForge.IR.Examples.U128StorageScalarProbe
