import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmErrorsProbe

open ProofForge.IR

/-- Errors probe: tests Statement.revert and Statement.revertWithError.
    Entry points:
    - revertPlain: unconditionally reverts with no message
    - revertWithMessage: reverts with a string message
    - revertWithErrorRef: reverts with a structured ErrorRef
    - guardedRevert: reverts if a condition is met (uses assert)
    - conditionalRevert: uses ifElse + revert inside the branch
    - normalPath: reads storage and returns (non-reverting path) -/

def stateCounter : StateDecl := {
  id := "counter"
  kind := .scalar
  type := .u64
}

def entryRevertPlain : Entrypoint := {
  name := "revertPlain"
  selector? := some "e6023528"
  params := #[]
  returns := .unit
  body := #[
    .revert ""
  ]
}

def entryRevertWithMessage : Entrypoint := {
  name := "revertWithMessage"
  selector? := some "185c38a4"
  params := #[]
  returns := .unit
  body := #[
    .revert "Plain revert message"
  ]
}

def entryRevertWithErrorRef : Entrypoint := {
  name := "revertWithErrorRef"
  selector? := some "b34aafd2"
  params := #[]
  returns := .unit
  body := #[
    .revertWithError { assertionId := 42, userCode? := some "E42" }
  ]
}

def entryGuardedRevert : Entrypoint := {
  name := "guardedRevert"
  selector? := some "0ff6ea62"
  params := #[("condition", .bool)]
  returns := .unit
  body := #[
    .assert (Expr.local "condition") "condition must be true"
      (some { assertionId := 1, userCode? := some "E1" })
  ]
}

def entryConditionalRevert : Entrypoint := {
  name := "conditionalRevert"
  selector? := some "194fd609"
  params := #[("flag", .bool)]
  returns := .unit
  body := #[
    .ifElse (Expr.local "flag")
      #[.revert "flag is true, reverting"]
      #[]
  ]
}

def entryNormalPath : Entrypoint := {
  name := "normalPath"
  selector? := some "a3f05111"
  params := #[]
  returns := .u64
  body := #[
    .return (Expr.effect (.storageScalarRead "counter"))
  ]
}

def module : Module := {
  name := "EvmErrorsProbe"
  state := #[stateCounter]
  entrypoints := #[
    entryRevertPlain,
    entryRevertWithMessage,
    entryRevertWithErrorRef,
    entryGuardedRevert,
    entryConditionalRevert,
    entryNormalPath
  ]
}

end ProofForge.IR.Examples.EvmErrorsProbe