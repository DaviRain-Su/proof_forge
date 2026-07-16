import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmHashProbe

open ProofForge.IR

def rootState : StateDecl := {
  id := "root"
  kind := .scalar
  type := .hash
}

def hashLit (a b c d : Nat) : Expr :=
  .literal (.hash4 a b c d)

def hashLiteral : Entrypoint := {
  name := "hash_literal"
  selector? := some "1214538f"
  returns := .hash
  body := #[
    .letBind "data" .hash (hashLit 1 2 3 4),
    .return (.hash (.local "data"))
  ]
}

def hashPair : Entrypoint := {
  name := "hash_pair"
  selector? := some "6b28555d"
  returns := .hash
  body := #[
    .letBind "left" .hash (hashLit 1 2 3 4),
    .letBind "right" .hash (hashLit 5 6 7 8),
    .return (.hashTwoToOne (.local "left") (.local "right"))
  ]
}

def packHash : Entrypoint := {
  name := "pack_hash"
  selector? := some "5d6d411d"
  params := #[
    ("a", .u64),
    ("b", .u64),
    ("c", .u64),
    ("d", .u64)
  ]
  returns := .hash
  body := #[
    .return (.hashValue (.local "a") (.local "b") (.local "c") (.local "d"))
  ]
}

def hashParam : Entrypoint := {
  name := "hash_param"
  selector? := some "3db89466"
  params := #[("input", .hash)]
  returns := .hash
  body := #[
    .return (.hash (.local "input"))
  ]
}

def storeHash : Entrypoint := {
  name := "store_hash"
  selector? := some "a9a07fbf"
  params := #[("input", .hash)]
  returns := .hash
  body := #[
    .effect (.storageScalarWrite "root" (.local "input")),
    .return (.effect (.storageScalarRead "root"))
  ]
}

def readRoot : Entrypoint := {
  name := "read_root"
  selector? := some "e3dfebc3"
  returns := .hash
  body := #[
    .return (.effect (.storageScalarRead "root"))
  ]
}

def module : Module := {
  name := "EvmHashProbe"
  state := #[rootState]
  entrypoints := #[hashLiteral, hashPair, packHash, hashParam, storeHash, readRoot]
}

end ProofForge.IR.Examples.EvmHashProbe
