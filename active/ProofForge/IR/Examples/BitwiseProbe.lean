import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.BitwiseProbe

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

def bitwiseMix : Entrypoint := {
  name := "bitwise_mix"
  returns := .u64
  body := #[
    .letMutBind "felt_bits" .u64 (felt 20),
    .assign (.local "felt_bits") (.bitOr (.local "felt_bits") (felt 8)),
    .assertEq (.local "felt_bits") (felt 28) "Felt bitwise or lowers to Psy",
    .assign (.local "felt_bits") (.bitAnd (.local "felt_bits") (felt 10)),
    .assertEq (.local "felt_bits") (felt 8) "Felt bitwise and lowers to Psy",
    .assign (.local "felt_bits") (.bitXor (.local "felt_bits") (felt 3)),
    .assertEq (.local "felt_bits") (felt 11) "Felt bitwise xor lowers to Psy",
    .assign (.local "felt_bits") (.shiftLeft (.local "felt_bits") (felt 1)),
    .assertEq (.local "felt_bits") (felt 22) "Felt shift-left lowers to Psy",
    .assign (.local "felt_bits") (.shiftRight (.local "felt_bits") (felt 1)),
    .assertEq (.local "felt_bits") (felt 11) "Felt shift-right lowers to Psy",
    .letMutBind "word" .u32 (u32 12),
    .assign (.local "word") (.bitAnd (.local "word") (u32 10)),
    .assertEq (.local "word") (u32 8) "u32 bitwise and follows upstream opcode_test",
    .assign (.local "word") (.bitOr (.local "word") (u32 1)),
    .assertEq (.local "word") (u32 9) "u32 bitwise or follows upstream opcode_test",
    .assign (.local "word") (.bitXor (.local "word") (u32 3)),
    .assertEq (.local "word") (u32 10) "u32 bitwise xor follows upstream opcode_test",
    .assign (.local "word") (.shiftLeft (.local "word") (u32 1)),
    .assertEq (.local "word") (u32 20) "u32 shift-left follows upstream opcode_test",
    .assign (.local "word") (.shiftRight (.local "word") (u32 2)),
    .assertEq (.local "word") (u32 5) "u32 shift-right follows upstream opcode_test",
    .letMutBind "compound_felt" .u64 (felt 20),
    .assignOp (.local "compound_felt") .bitOr (felt 8),
    .assignOp (.local "compound_felt") .bitAnd (felt 10),
    .assignOp (.local "compound_felt") .bitXor (felt 3),
    .assignOp (.local "compound_felt") .shiftLeft (felt 1),
    .assignOp (.local "compound_felt") .shiftRight (felt 1),
    .assertEq (.local "compound_felt") (felt 11) "Felt compound bitwise and shifts lower to Psy assignment operators",
    .letMutBind "compound_word" .u32 (u32 20),
    .assignOp (.local "compound_word") .bitOr (u32 8),
    .assignOp (.local "compound_word") .bitAnd (u32 10),
    .assignOp (.local "compound_word") .bitXor (u32 3),
    .assignOp (.local "compound_word") .shiftLeft (u32 1),
    .assignOp (.local "compound_word") .shiftRight (u32 1),
    .assertEq (.local "compound_word") (u32 11) "u32 compound bitwise and shifts lower to Psy assignment operators",
    .return (.add (.local "felt_bits") (.cast (.local "word") .u64))
  ]
}

def module : Module := {
  name := "BitwiseProbe"
  state := #[stateMarker]
  entrypoints := #[bitwiseMix]
}

end ProofForge.IR.Examples.BitwiseProbe
