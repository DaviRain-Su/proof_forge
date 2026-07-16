import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.U32ArithmeticProbe

open ProofForge.IR

def stateMarker : StateDecl := {
  id := "_proof_forge_marker"
  kind := .scalar
  type := .u64
}

def felt (value : Nat) : Expr :=
  .literal (.u64 value)

def u32 (value : Nat) : Expr :=
  .literal (.u32 value)

def u32Arithmetic : Entrypoint := {
  name := "u32_arithmetic"
  params := #[
    ("a", .u32),
    ("b", .u32)
  ]
  returns := .u64
  body := #[
    .letBind "k" .u32 (.sub
      (.mul
        (.mul (.add (.local "a") (u32 2)) (.mul (u32 2) (u32 2)))
        (.local "b"))
      (.mul (u32 3) (.add (.local "a") (.local "b")))),
    .letMutBind "z" .u32 (.add (.local "k") (.local "a")),
    .assertEq (.local "z") (u32 35) "u32 addition and subtraction compose",
    .assign (.local "z") (.div (.local "z") (.local "a")),
    .assertEq (.local "z") (u32 17) "u32 division lowers to Psy",
    .assign (.local "z") (.pow (.local "z") (.local "a")),
    .assertEq (.local "z") (u32 289) "u32 exponentiation lowers to Psy",
    .assign (.local "z") (.mod (.local "z") (u32 2)),
    .assertEq (.local "z") (u32 1) "u32 modulo lowers to Psy",
    .letMutBind "compound" .u32 (u32 20),
    .assignOp (.local "compound") .add (u32 3),
    .assignOp (.local "compound") .sub (u32 1),
    .assignOp (.local "compound") .mul (u32 2),
    .assignOp (.local "compound") .div (u32 11),
    .assignOp (.local "compound") .mod (u32 3),
    .assertEq (.local "compound") (u32 1) "u32 compound arithmetic lowers to Psy assignment operators",
    .letBind "bb" .bool (.cast (.local "z") .bool),
    .return (.cast (.local "bb") .u64)
  ]
}

def module : Module := {
  name := "U32ArithmeticProbe"
  state := #[stateMarker]
  entrypoints := #[u32Arithmetic]
}

end ProofForge.IR.Examples.U32ArithmeticProbe
