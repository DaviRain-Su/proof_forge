import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.BoolStorageArrayProbe

open ProofForge.IR

def stateFlags : StateDecl := {
  id := "flags"
  kind := .array 3
  type := .bool
}

def boolLit (value : Bool) : Expr :=
  .literal (.bool value)

def ix (value : Nat) : Expr :=
  .literal (.u64 value)

def flagPath (index : Nat) : Array StoragePathSegment :=
  #[.index (ix index)]

def readFlag (index : Nat) : Expr :=
  .effect (.storageArrayRead "flags" (ix index))

def readFlagPath (index : Nat) : Expr :=
  .effect (.storagePathRead "flags" (flagPath index))

def localFlagsSum : Entrypoint := {
  name := "local_flags_sum"
  returns := .u64
  body := #[
    .letBind "flags" (.fixedArray .bool 3) (.arrayLit .bool #[
      boolLit true,
      boolLit false,
      boolLit true
    ]),
    .return (.add
      (.add
        (.cast (.arrayGet (.local "flags") (ix 0)) .u64)
        (.cast (.arrayGet (.local "flags") (ix 1)) .u64))
      (.cast (.arrayGet (.local "flags") (ix 2)) .u64))
  ]
}

def storageLifecycle : Entrypoint := {
  name := "storage_lifecycle"
  returns := .u64
  body := #[
    .effect (.storageArrayWrite "flags" (ix 0) (boolLit true)),
    .effect (.storageArrayWrite "flags" (ix 1) (boolLit false)),
    .effect (.storagePathWrite "flags" (flagPath 2) (boolLit true)),
    .letBind "first" .bool (readFlag 0),
    .letBind "second" .bool (readFlag 1),
    .letBind "third" .bool (readFlagPath 2),
    .assertEq (.local "first") (boolLit true) "bool storage array reads true",
    .assertEq (.local "second") (boolLit false) "bool storage array reads false",
    .assertEq (.local "third") (boolLit true) "bool storage path reads true",
    .return (.add
      (.add
        (.cast (.local "first") .u64)
        (.cast (.local "second") .u64))
      (.cast (.local "third") .u64))
  ]
}

def module : Module := {
  name := "BoolStorageArrayProbe"
  state := #[stateFlags]
  entrypoints := #[localFlagsSum, storageLifecycle]
}

end ProofForge.IR.Examples.BoolStorageArrayProbe
