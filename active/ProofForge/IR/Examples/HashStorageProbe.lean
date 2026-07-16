import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.HashStorageProbe

open ProofForge.IR

def stateRoot : StateDecl := {
  id := "root"
  kind := .scalar
  type := .hash
}

def stateRoots : StateDecl := {
  id := "roots"
  kind := .array 2
  type := .hash
}

def hashLit (a b c d : Nat) : Expr :=
  .literal (.hash4 a b c d)

def ix (value : Nat) : Expr :=
  .literal (.u64 value)

def rootPath (index : Nat) : Array StoragePathSegment :=
  #[.index (ix index)]

def scalarInitial : Expr :=
  hashLit 1 2 3 4

def scalarUpdated : Expr :=
  hashLit 5 6 7 8

def arrayFirst : Expr :=
  hashLit 11 22 33 44

def arraySecond : Expr :=
  hashLit 55 66 77 88

def scalarLifecycle : Entrypoint := {
  name := "scalar_lifecycle"
  returns := .hash
  body := #[
    .letBind "first" .hash scalarInitial,
    .letBind "second" .hash scalarUpdated,
    .effect (.storageScalarWrite "root" (.local "first")),
    .assertEq (.effect (.storageScalarRead "root")) (.local "first") "hash scalar reads first value",
    .effect (.storageScalarWrite "root" (.local "second")),
    .return (.effect (.storageScalarRead "root"))
  ]
}

def arrayLifecycle : Entrypoint := {
  name := "array_lifecycle"
  returns := .hash
  body := #[
    .letBind "first" .hash arrayFirst,
    .letBind "second" .hash arraySecond,
    .effect (.storageArrayWrite "roots" (ix 0) (.local "first")),
    .effect (.storagePathWrite "roots" (rootPath 1) (.local "second")),
    .assertEq (.effect (.storageArrayRead "roots" (ix 0))) (.local "first") "hash array reads first value",
    .return (.effect (.storagePathRead "roots" (rootPath 1)))
  ]
}

def module : Module := {
  name := "HashStorageProbe"
  state := #[stateRoot, stateRoots]
  entrypoints := #[scalarLifecycle, arrayLifecycle]
}

end ProofForge.IR.Examples.HashStorageProbe
