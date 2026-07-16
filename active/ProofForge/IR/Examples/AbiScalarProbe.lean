import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.AbiScalarProbe

open ProofForge.IR

def u64 (value : Nat) : Expr :=
  .literal (.u64 value)

def mix : Entrypoint := {
  name := "mix"
  selector? := some "7f97495c"
  params := #[
    ("base", .u64),
    ("delta", .u32),
    ("flag", .bool)
  ]
  returns := .u64
  body := #[
    .return (.add
      (.add
        (.local "base")
        (.cast (.local "delta") .u64))
      (.cast (.local "flag") .u64))
  ]
}

def same : Entrypoint := {
  name := "same"
  selector? := some "c32c70b1"
  params := #[
    ("left", .u64),
    ("right", .u64)
  ]
  returns := .bool
  body := #[
    .return (.eq (.local "left") (.local "right"))
  ]
}

def module : Module := {
  name := "AbiScalarProbe"
  state := #[]
  entrypoints := #[mix, same]
}

end ProofForge.IR.Examples.AbiScalarProbe
