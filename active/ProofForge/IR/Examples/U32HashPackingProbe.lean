import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.U32HashPackingProbe

open ProofForge.IR

def two32 : Nat := 4294967296

def stateMarker : StateDecl := {
  id := "_proof_forge_marker"
  kind := .scalar
  type := .u64
}

def felt (value : Nat) : Expr :=
  .literal (.u64 value)

def u32 (value : Nat) : Expr :=
  .literal (.u32 value)

def localLimb (name : String) (index : Nat) : Expr :=
  .arrayGet (.local name) (felt index)

def packPair (lo hi : Expr) : Expr :=
  .add (.cast lo .u64) (.mul (.cast hi .u64) (felt two32))

def packLocalPair (name : String) (lo hi : Nat) : Expr :=
  packPair (localLimb name lo) (localLimb name hi)

def packParamPair (lo hi : String) : Expr :=
  packPair (.local lo) (.local hi)

def packedLiteralHash : Expr :=
  .hashValue
    (packLocalPair "limbs" 0 1)
    (packLocalPair "limbs" 2 3)
    (packLocalPair "limbs" 4 5)
    (packLocalPair "limbs" 6 7)

def packedParamHash : Expr :=
  .hashValue
    (packParamPair "a0" "a1")
    (packParamPair "a2" "a3")
    (packParamPair "a4" "a5")
    (packParamPair "a6" "a7")

def packLiteral : Entrypoint := {
  name := "pack_literal"
  returns := .hash
  body := #[
    .letBind "limbs" (.fixedArray .u32 8) (.arrayLit .u32 #[
      u32 1, u32 2, u32 3, u32 4, u32 5, u32 6, u32 7, u32 8
    ]),
    .return packedLiteralHash
  ]
}

def packParams : Entrypoint := {
  name := "pack_params"
  params := #[
    ("a0", .u32),
    ("a1", .u32),
    ("a2", .u32),
    ("a3", .u32),
    ("a4", .u32),
    ("a5", .u32),
    ("a6", .u32),
    ("a7", .u32)
  ]
  returns := .hash
  body := #[
    .return packedParamHash
  ]
}

def module : Module := {
  name := "U32HashPackingProbe"
  state := #[stateMarker]
  entrypoints := #[packLiteral, packParams]
}

end ProofForge.IR.Examples.U32HashPackingProbe
