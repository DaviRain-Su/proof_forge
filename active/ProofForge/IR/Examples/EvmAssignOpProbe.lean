import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmAssignOpProbe

open ProofForge.IR

def stateTotal : StateDecl := {
  id := "total"
  kind := .scalar
  type := .u64
}

def compoundAssignment : Entrypoint := {
  name := "compound_assignment"
  selector? := some "72250d96"
  params := #[("seed", .u64)]
  returns := .u64
  body := #[
    .letMutBind "total" .u64 (.local "seed"),
    .assignOp (.local "total") .add (.literal (.u64 7)),
    .assignOp (.local "total") .sub (.literal (.u64 2)),
    .assignOp (.local "total") .mul (.literal (.u64 3)),
    .assignOp (.local "total") .div (.literal (.u64 5)),
    .assignOp (.local "total") .mod (.literal (.u64 11)),
    .assignOp (.local "total") .bitOr (.literal (.u64 8)),
    .assignOp (.local "total") .bitAnd (.literal (.u64 14)),
    .assignOp (.local "total") .bitXor (.literal (.u64 3)),
    .assignOp (.local "total") .shiftLeft (.literal (.u64 1)),
    .assignOp (.local "total") .shiftRight (.literal (.u64 1)),
    .effect (.storageScalarWrite "total" (.local "total")),
    .effect (.storageScalarAssignOp "total" .add (.literal (.u64 5))),
    .effect (.storageScalarAssignOp "total" .sub (.literal (.u64 1))),
    .effect (.storageScalarAssignOp "total" .mul (.literal (.u64 2))),
    .effect (.storageScalarAssignOp "total" .div (.literal (.u64 3))),
    .effect (.storageScalarAssignOp "total" .mod (.literal (.u64 13))),
    .effect (.storageScalarAssignOp "total" .bitOr (.literal (.u64 16))),
    .effect (.storageScalarAssignOp "total" .bitAnd (.literal (.u64 31))),
    .effect (.storageScalarAssignOp "total" .bitXor (.literal (.u64 7))),
    .effect (.storageScalarAssignOp "total" .shiftLeft (.literal (.u64 2))),
    .effect (.storageScalarAssignOp "total" .shiftRight (.literal (.u64 1))),
    .return (.effect (.storageScalarRead "total"))
  ]
}

def compoundU32 : Entrypoint := {
  name := "compound_u32"
  selector? := some "1508c8ff"
  params := #[("seed", .u32)]
  returns := .u32
  body := #[
    .letMutBind "word" .u32 (.local "seed"),
    .assignOp (.local "word") .add (.literal (.u32 3)),
    .assignOp (.local "word") .sub (.literal (.u32 1)),
    .assignOp (.local "word") .mul (.literal (.u32 2)),
    .assignOp (.local "word") .div (.literal (.u32 11)),
    .assignOp (.local "word") .mod (.literal (.u32 3)),
    .assignOp (.local "word") .bitOr (.literal (.u32 8)),
    .assignOp (.local "word") .bitAnd (.literal (.u32 10)),
    .assignOp (.local "word") .bitXor (.literal (.u32 3)),
    .assignOp (.local "word") .shiftLeft (.literal (.u32 1)),
    .assignOp (.local "word") .shiftRight (.literal (.u32 1)),
    .return (.local "word")
  ]
}

def module : Module := {
  name := "EvmAssignOpProbe"
  state := #[stateTotal]
  entrypoints := #[compoundAssignment, compoundU32]
}

end ProofForge.IR.Examples.EvmAssignOpProbe
