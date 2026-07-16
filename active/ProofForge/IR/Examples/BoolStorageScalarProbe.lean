import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.BoolStorageScalarProbe

open ProofForge.IR

def stateFlag : StateDecl := {
  id := "flag"
  kind := .scalar
  type := .bool
}

def boolLit (value : Bool) : Expr :=
  .literal (.bool value)

def readFlag : Expr :=
  .effect (.storageScalarRead "flag")

def storageLifecycle : Entrypoint := {
  name := "storage_lifecycle"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "flag" (boolLit true)),
    .letBind "first" .bool readFlag,
    .assertEq (.local "first") (boolLit true) "bool scalar storage reads true",
    .effect (.storageScalarWrite "flag" (boolLit false)),
    .letBind "second" .bool readFlag,
    .assertEq (.local "second") (boolLit false) "bool scalar storage reads false",
    .effect (.storageScalarWrite "flag" (.local "first")),
    .return (.cast readFlag .u64)
  ]
}

def module : Module := {
  name := "BoolStorageScalarProbe"
  state := #[stateFlag]
  entrypoints := #[storageLifecycle]
}

end ProofForge.IR.Examples.BoolStorageScalarProbe
