import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.AssignmentProbe

open ProofForge.IR

def reassignment : Entrypoint := {
  name := "reassignment"
  selector? := some "91a3e2ac"
  params := #[("seed", .u64)]
  returns := .u64
  body := #[
    .letMutBind "total" .u64 (.local "seed"),
    .assign (.local "total") (.add (.local "total") (.literal (.u64 7))),
    .letMutBind "matched" .bool (.literal (.bool false)),
    .assign (.local "matched") (.eq (.local "total") (.literal (.u64 12))),
    .assert (.local "matched") "local assignment updates the bool guard",
    .return (.local "total")
  ]
}

def module : Module := {
  name := "AssignmentProbe"
  state := #[]
  entrypoints := #[reassignment]
}

end ProofForge.IR.Examples.AssignmentProbe
