import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.AbiAggregateProbe

open ProofForge.IR

def pairStruct : StructDecl := {
  name := "Pair"
  fields := #[
    { id := "left", type := .u64 },
    { id := "right", type := .u64 }
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

def pair (left right : Expr) : Expr :=
  .structLit "Pair" #[
    ("left", left),
    ("right", right)
  ]

def sumPair : Entrypoint := {
  name := "sum_pair"
  params := #[
    ("pair", .structType "Pair")
  ]
  returns := .u64
  body := #[
    .return (.add
      (.field (.local "pair") "left")
      (.field (.local "pair") "right"))
  ]
}

def sumArray : Entrypoint := {
  name := "sum_array"
  params := #[
    ("xs", .fixedArray .u64 3)
  ]
  returns := .u64
  body := #[
    .return (.add
      (.add
        (.arrayGet (.local "xs") (ix 0))
        (.arrayGet (.local "xs") (ix 1)))
      (.arrayGet (.local "xs") (ix 2)))
  ]
}

def makePair : Entrypoint := {
  name := "make_pair"
  params := #[
    ("left", .u64),
    ("right", .u64)
  ]
  returns := .structType "Pair"
  body := #[
    .return (pair (.local "left") (.local "right"))
  ]
}

def module : Module := {
  name := "AbiAggregateProbe"
  structs := #[pairStruct]
  state := #[stateMarker]
  entrypoints := #[sumPair, sumArray, makePair]
}

end ProofForge.IR.Examples.AbiAggregateProbe
