import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmAbiAggregateProbe

open ProofForge.IR

def pairStruct : StructDecl := {
  name := "Pair"
  fields := #[
    { id := "left", type := .u64 },
    { id := "right", type := .u64 }
  ]
}

def flagsStruct : StructDecl := {
  name := "Flags"
  fields := #[
    { id := "enabled", type := .bool },
    { id := "archived", type := .bool }
  ]
}

def hashPairStruct : StructDecl := {
  name := "HashPair"
  fields := #[
    { id := "left", type := .hash },
    { id := "right", type := .hash }
  ]
}

def u32 (value : Nat) : Expr :=
  .literal (.u32 value)

def u64 (value : Nat) : Expr :=
  .literal (.u64 value)

def pair (left right : Expr) : Expr :=
  .structLit "Pair" #[
    ("left", left),
    ("right", right)
  ]

def hashPair (left right : Expr) : Expr :=
  .structLit "HashPair" #[
    ("left", left),
    ("right", right)
  ]

def sumPair : Entrypoint := {
  name := "sum_pair"
  selector? := some "25508e13"
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
  selector? := some "eb353b80"
  params := #[
    ("xs", .fixedArray .u64 3)
  ]
  returns := .u64
  body := #[
    .return (.add
      (.add
        (.arrayGet (.local "xs") (u64 0))
        (.arrayGet (.local "xs") (u64 1)))
      (.arrayGet (.local "xs") (u64 2)))
  ]
}

def sumMatrix : Entrypoint := {
  name := "sum_matrix"
  selector? := some "da76e471"
  params := #[
    ("matrix", .fixedArray (.fixedArray .u64 2) 2)
  ]
  returns := .u64
  body := #[
    .return (.add
      (.add
        (.arrayGet (.arrayGet (.local "matrix") (u64 0)) (u64 0))
        (.arrayGet (.arrayGet (.local "matrix") (u64 0)) (u64 1)))
      (.add
        (.arrayGet (.arrayGet (.local "matrix") (u64 1)) (u64 0))
        (.arrayGet (.arrayGet (.local "matrix") (u64 1)) (u64 1))))
  ]
}

def sumPairArray : Entrypoint := {
  name := "sum_pair_array"
  selector? := some "10e4c1da"
  params := #[
    ("pairs", .fixedArray (.structType "Pair") 2)
  ]
  returns := .u64
  body := #[
    .return (.add
      (.add
        (.field (.arrayGet (.local "pairs") (u64 0)) "left")
        (.field (.arrayGet (.local "pairs") (u64 0)) "right"))
      (.add
        (.field (.arrayGet (.local "pairs") (u64 1)) "left")
        (.field (.arrayGet (.local "pairs") (u64 1)) "right"))
    )
  ]
}

def makePair : Entrypoint := {
  name := "make_pair"
  selector? := some "ef51ff62"
  params := #[
    ("left", .u64),
    ("right", .u64)
  ]
  returns := .structType "Pair"
  body := #[
    .return (pair (.local "left") (.local "right"))
  ]
}

def makePairArray : Entrypoint := {
  name := "make_pair_array"
  selector? := some "617df171"
  params := #[
    ("a", .u64),
    ("b", .u64),
    ("c", .u64),
    ("d", .u64)
  ]
  returns := .fixedArray (.structType "Pair") 2
  body := #[
    .letBind "pairs" (.fixedArray (.structType "Pair") 2) (.arrayLit (.structType "Pair") #[
      pair (.local "a") (.local "b"),
      pair (.local "c") (.local "d")
    ]),
    .return (.local "pairs")
  ]
}

def makeMatrix : Entrypoint := {
  name := "make_matrix"
  selector? := some "b61c11b8"
  params := #[
    ("a", .u64),
    ("b", .u64),
    ("c", .u64),
    ("d", .u64)
  ]
  returns := .fixedArray (.fixedArray .u64 2) 2
  body := #[
    .return (.arrayLit (.fixedArray .u64 2) #[
      .arrayLit .u64 #[.local "a", .local "b"],
      .arrayLit .u64 #[.local "c", .local "d"]
    ])
  ]
}

def makeArray : Entrypoint := {
  name := "make_array"
  selector? := some "ffac5c16"
  params := #[
    ("a", .u64),
    ("b", .u64),
    ("c", .u64)
  ]
  returns := .fixedArray .u64 3
  body := #[
    .letBind "xs" (.fixedArray .u64 3) (.arrayLit .u64 #[.local "a", .local "b", .local "c"]),
    .return (.local "xs")
  ]
}

def sumSmall : Entrypoint := {
  name := "sum_small"
  selector? := some "384e9976"
  params := #[
    ("xs", .fixedArray .u32 2)
  ]
  returns := .u32
  body := #[
    .return (.add
      (.arrayGet (.local "xs") (u32 0))
      (.arrayGet (.local "xs") (u32 1)))
  ]
}

def sumSmallMatrix : Entrypoint := {
  name := "sum_small_matrix"
  selector? := some "94f90bdd"
  params := #[
    ("xs", .fixedArray (.fixedArray .u32 2) 2)
  ]
  returns := .u32
  body := #[
    .return (.add
      (.add
        (.arrayGet (.arrayGet (.local "xs") (u64 0)) (u64 0))
        (.arrayGet (.arrayGet (.local "xs") (u64 0)) (u64 1)))
      (.add
        (.arrayGet (.arrayGet (.local "xs") (u64 1)) (u64 0))
        (.arrayGet (.arrayGet (.local "xs") (u64 1)) (u64 1))))
  ]
}

def andFlags : Entrypoint := {
  name := "and_flags"
  selector? := some "1df89823"
  params := #[
    ("flags", .structType "Flags")
  ]
  returns := .bool
  body := #[
    .return (.boolAnd
      (.field (.local "flags") "enabled")
      (.field (.local "flags") "archived"))
  ]
}

def echoHashPair : Entrypoint := {
  name := "echo_hash_pair"
  selector? := some "5e248cf3"
  params := #[
    ("pair", .structType "HashPair")
  ]
  returns := .hash
  body := #[
    .return (.field (.local "pair") "right")
  ]
}

def makeHashPair : Entrypoint := {
  name := "make_hash_pair"
  selector? := some "d3a9b1bd"
  params := #[
    ("left", .hash),
    ("right", .hash)
  ]
  returns := .structType "HashPair"
  body := #[
    .return (hashPair (.local "left") (.local "right"))
  ]
}

def pickHash : Entrypoint := {
  name := "pick_hash"
  selector? := some "44d9885a"
  params := #[
    ("roots", .fixedArray .hash 2)
  ]
  returns := .hash
  body := #[
    .return (.arrayGet (.local "roots") (u64 1))
  ]
}

def makeHashArray : Entrypoint := {
  name := "make_hash_array"
  selector? := some "3fcd733b"
  params := #[
    ("left", .hash),
    ("right", .hash)
  ]
  returns := .fixedArray .hash 2
  body := #[
    .return (.arrayLit .hash #[.local "left", .local "right"])
  ]
}

def module : Module := {
  name := "EvmAbiAggregateProbe"
  structs := #[pairStruct, flagsStruct, hashPairStruct]
  state := #[]
  entrypoints := #[
    sumPair,
    sumArray,
    sumMatrix,
    sumPairArray,
    makePair,
    makePairArray,
    makeMatrix,
    makeArray,
    sumSmall,
    sumSmallMatrix,
    andFlags,
    echoHashPair,
    makeHashPair,
    pickHash,
    makeHashArray
  ]
}

end ProofForge.IR.Examples.EvmAbiAggregateProbe
