import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.AssertProbe

open ProofForge.IR

def stateMarker : StateDecl := {
  id := "_proof_forge_marker"
  kind := .scalar
  type := .u64
}

def checkedSum : Entrypoint := {
  name := "checked_sum"
  selector? := some "fe24a759"
  params := #[
    ("a", .u64),
    ("b", .u64)
  ]
  returns := .u64
  body := #[
    .letBind "total" .u64 (.add (.local "a") (.local "b")),
    .letBind "ok" .bool (.literal (.bool true)),
    .assert (.local "ok") "explicit boolean assertion passes",
    .assertEq (.local "total") (.literal (.u64 12)) "checked sum matches expected value",
    .return (.local "total")
  ]
}

def module : Module := {
  name := "AssertProbe"
  state := #[stateMarker]
  entrypoints := #[checkedSum]
}

end ProofForge.IR.Examples.AssertProbe
