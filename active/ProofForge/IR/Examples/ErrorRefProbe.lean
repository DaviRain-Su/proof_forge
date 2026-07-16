import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.ErrorRefProbe

open ProofForge.IR

def stateCount : StateDecl := {
  id := "count"
  kind := .scalar
  type := .u64
}

def initializeEntrypoint : Entrypoint := {
  name := "initialize"
  selector? := some "8129fc1c"
  returns := .unit
  body := #[
    .effect (.storageScalarWrite "count" (.literal (.u64 0)))
  ]
}

def guardedIncrement : Entrypoint := {
  name := "guarded_increment"
  selector? := some "ceb899b0"
  returns := .unit
  body := #[
    .letBind "n" .u64 (.effect (.storageScalarRead "count")),
    .assert (.lt (.local "n") (.literal (.u64 5)))
      "count must be under five"
      (some { assertionId := 1, userCode? := some "Counter::Overflow" }),
    .effect (.storageScalarWrite "count" (.add (.local "n") (.literal (.u64 1))))
  ]
}

def exactIncrement : Entrypoint := {
  name := "exact_increment"
  selector? := some "b71aba02"
  returns := .unit
  body := #[
    .letBind "n" .u64 (.effect (.storageScalarRead "count")),
    .assertEq (.local "n") (.literal (.u64 7))
      "count must equal seven"
      (some { assertionId := 2, userCode? := some "Counter::ExactMatch" }),
    .effect (.storageScalarWrite "count" (.add (.local "n") (.literal (.u64 1))))
  ]
}

def module : Module := {
  name := "ErrorRefProbe"
  state := #[stateCount]
  entrypoints := #[initializeEntrypoint, guardedIncrement, exactIncrement]
}

end ProofForge.IR.Examples.ErrorRefProbe
