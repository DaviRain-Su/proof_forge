import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.StructArrayProbe

open ProofForge.IR

def personStruct : StructDecl := {
  name := "Person"
  deriveStorage := true
  fields := #[
    { id := "age", type := .u64 },
    { id := "score", type := .u64 }
  ]
}

def statePeople : StateDecl := {
  id := "people"
  kind := .array 2
  type := .structType "Person"
}

def felt (value : Nat) : Expr :=
  .literal (.u64 value)

def ix (value : Nat) : Expr :=
  .literal (.u64 value)

def person (age score : Nat) : Expr :=
  .structLit "Person" #[
    ("age", felt age),
    ("score", felt score)
  ]

def localStructArraySum : Entrypoint := {
  name := "local_struct_array_sum"
  returns := .u64
  body := #[
    .letBind "people" (.fixedArray (.structType "Person") 2)
      (.arrayLit (.structType "Person") #[person 10 80, person 20 90]),
    .return (.add
      (.field (.arrayGet (.local "people") (ix 0)) "age")
      (.field (.arrayGet (.local "people") (ix 1)) "score"))
  ]
}

def storageStructArrayLifecycle : Entrypoint := {
  name := "storage_struct_array_lifecycle"
  returns := .u64
  body := #[
    .effect (.storageArrayWrite "people" (ix 0) (person 10 80)),
    .effect (.storageArrayWrite "people" (ix 1) (person 20 90)),
    .effect (.storageArrayStructFieldWrite "people" (ix 1) "score" (felt 92)),
    .return (.add
      (.effect (.storageArrayStructFieldRead "people" (ix 0) "age"))
      (.effect (.storageArrayStructFieldRead "people" (ix 1) "score"))
    )
  ]
}

def module : Module := {
  name := "StructArrayProbe"
  structs := #[personStruct]
  state := #[statePeople]
  entrypoints := #[localStructArraySum, storageStructArrayLifecycle]
}

end ProofForge.IR.Examples.StructArrayProbe
