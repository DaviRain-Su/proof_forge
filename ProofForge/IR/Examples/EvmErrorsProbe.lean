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

/-- PF-P2-02: Solidity custom-error selector for `CustomError()` (cast sig 0x09caebf3).
    Entrypoint selector is `revertCustomError()` (cast sig 0xc5159795). -/
def entryRevertCustomError : Entrypoint := {
  name := "revertCustomError"
  selector? := some "c5159795"
  params := #[]
  returns := .unit
  body := #[
    .revertWithError {
      assertionId := 0
      userCode? := some "CustomError"
      soliditySelector? := some "09caebf3"
    }
  ]
}

/-- E1.1: Solidity custom error with ABI static args —
    `error InsufficientBalance(uint64,uint64)` → selector `0x9432a7ee`.
    Entrypoint selector is `revertCustomErrorArgs()` (cast sig below). -/
def entryRevertCustomErrorArgs : Entrypoint := {
  name := "revertCustomErrorArgs"
  selector? := some "1cff28dd"  -- cast sig revertCustomErrorArgs()
  params := #[]
  returns := .unit
  body := #[
    .revertWithError {
      assertionId := 7
      userCode? := some "InsufficientBalance"
      soliditySelector? := some "9432a7ee"
      solidityArgWords := #[9007199254740993, 3]  -- above JS Number.MAX_SAFE_INTEGER
      solidityArgTypes := #["uint64", "uint64"]
    }
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
    entryRevertCustomError,
    entryRevertCustomErrorArgs,
    entryGuardedRevert,
    entryConditionalRevert,
    entryNormalPath
  ]
}

end ProofForge.IR.Examples.EvmErrorsProbe
