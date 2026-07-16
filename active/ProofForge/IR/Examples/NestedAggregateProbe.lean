import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.NestedAggregateProbe

open ProofForge.IR

def memberStruct : StructDecl := {
  name := "Member"
  fields := #[
    { id := "age", type := .u64 },
    { id := "score", type := .u64 }
  ]
}

def familyStruct : StructDecl := {
  name := "Family"
  fields := #[
    { id := "base", type := .u64 },
    { id := "children", type := .fixedArray (.structType "Member") 2 }
  ]
}

def stateMarker : StateDecl := {
  id := "_proof_forge_marker"
  kind := .scalar
  type := .u64
}

def felt (value : Nat) : Expr :=
  .literal (.u64 value)

def ix (value : Nat) : Expr :=
  .literal (.u64 value)

def member (age score : Nat) : Expr :=
  .structLit "Member" #[
    ("age", felt age),
    ("score", felt score)
  ]

def family (base : Nat) (child0 child1 : Expr) : Expr :=
  .structLit "Family" #[
    ("base", felt base),
    ("children", .arrayLit (.structType "Member") #[child0, child1])
  ]

def familiesType : ValueType :=
  .fixedArray (.structType "Family") 2

def familiesLiteral : Expr :=
  .arrayLit (.structType "Family") #[
    family 1 (member 10 11) (member 12 20),
    family 2 (member 30 31) (member 32 33)
  ]

def updatedChildAge : Expr :=
  .field
    (.arrayGet
      (.field
        (.arrayGet (.local "families") (ix 1))
        "children")
      (ix 0))
    "age"

def firstFamilySecondScore : Expr :=
  .field
    (.arrayGet
      (.field
        (.arrayGet (.local "families") (ix 0))
        "children")
      (ix 1))
    "score"

def nestedUpdateSum : Entrypoint := {
  name := "nested_update_sum"
  returns := .u64
  body := #[
    .letMutBind "families" familiesType familiesLiteral,
    .assign updatedChildAge (felt 31),
    .return (.add updatedChildAge firstFamilySecondScore)
  ]
}

def module : Module := {
  name := "NestedAggregateProbe"
  structs := #[memberStruct, familyStruct]
  state := #[stateMarker]
  entrypoints := #[nestedUpdateSum]
}

end ProofForge.IR.Examples.NestedAggregateProbe
