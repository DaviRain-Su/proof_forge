import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.U32StorageScalarProbe

open ProofForge.IR

def stateValue : StateDecl := {
  id := "value"
  kind := .scalar
  type := .u32
}

def u32 (value : Nat) : Expr :=
  .literal (.u32 value)

def readValue : Expr :=
  .effect (.storageScalarRead "value")

def storageLifecycle : Entrypoint := {
  name := "storage_lifecycle"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "value" (u32 7)),
    .letBind "n" .u32 readValue,
    .effect (.storageScalarWrite "value" (.local "n")),
    .effect (.storageScalarAssignOp "value" .add (u32 5)),
    .letBind "result" .u32 readValue,
    .assertEq (.local "result") (u32 12) "u32 scalar storage read/write preserves u32 values",
    .return (.cast (.local "result") .u64)
  ]
}

def module : Module := {
  name := "U32StorageScalarProbe"
  state := #[stateValue]
  entrypoints := #[storageLifecycle]
}

end ProofForge.IR.Examples.U32StorageScalarProbe
