import ProofForge.IR.Semantics

/-! ## ExecResult three-valued classification smoke

The legacy IR interpreter returns `Except String α`, which conflates
contract-level reverts with interpreter-level failures. `ExecResult.ofExcept`
classifies the legacy error channel into `.ok`, `.reverted`, and `.error`.
This smoke verifies:

1. A passing entrypoint (no storage read) returns `.ok`.
2. A failing `Statement.assert` is classified as `.reverted` (not `.error`).
3. An explicit `Statement.revert` is classified as `.reverted`.
4. A `Statement.revertWithError` is classified as `.reverted`.
5. An unsupported-construct error string is classified as `.error`.

These are the prerequisites for FV-2/FV-5 revert-aware refinement. The legacy
`Except String` drivers (`runEntrypoint` etc.) continue to return the raw
error string for backward compatibility with `Refinement.lean` trace
obligations.
-/

namespace ProofForge.Tests.IRExecResult

open ProofForge.IR
open ProofForge.IR.Semantics

/-- A trivially-passing entrypoint that returns a constant and touches no
storage, so it succeeds against `State.empty`. -/
def passingEntrypoint : Entrypoint := {
  name := "pass"
  kind := .function
  params := #[]
  returns := .u64
  body := #[ .return (.literal (.u64 7)) ]
}

/-- A minimal entrypoint whose body is a failing assert. -/
def failingAssertEntrypoint : Entrypoint := {
  name := "fail"
  kind := .function
  params := #[]
  returns := .unit
  body := #[ .assert (.literal (.bool false)) "always fails" ]
}

/-- A minimal entrypoint whose body is an explicit revert. -/
def revertEntrypoint : Entrypoint := {
  name := "revert"
  kind := .function
  params := #[]
  returns := .unit
  body := #[ .revert "explicit rollback" ]
}

/-- A minimal entrypoint whose body is a structured revertWithError. -/
def revertWithErrorEntrypoint : Entrypoint := {
  name := "revertErr"
  kind := .function
  params := #[]
  returns := .unit
  body := #[ .revertWithError { assertionId := 42, userCode? := none } ]
}

/-- A minimal entrypoint that lowers an unsupported memoryArraySet effect. -/
def unsupportedEntrypoint : Entrypoint := {
  name := "unsupported"
  kind := .function
  params := #[]
  returns := .unit
  body := #[ .effect (.memoryArraySet (.local "arr") (.literal (.u64 0)) (.literal (.u64 1))) ]
}

/-- A passing entrypoint returns `.ok`. -/
theorem passing_entrypoint_is_ok :
    (match runEntrypointResult State.empty passingEntrypoint
     with | .ok _ => true | _ => false) = true := by
  native_decide

/-- A failing assert is `.reverted`, not `.error` and not `.ok`. -/
theorem failing_assert_is_reverted :
    (match runEntrypointResult State.empty failingAssertEntrypoint
     with | .reverted _ => true | _ => false) = true := by
  native_decide

/-- An explicit revert is `.reverted`. -/
theorem explicit_revert_is_reverted :
    (match runEntrypointResult State.empty revertEntrypoint
     with | .reverted _ => true | _ => false) = true := by
  native_decide

/-- A structured revertWithError is `.reverted`. -/
theorem revert_with_error_is_reverted :
    (match runEntrypointResult State.empty revertWithErrorEntrypoint
     with | .reverted _ => true | _ => false) = true := by
  native_decide

/-- An unsupported construct is `.error` (interpreter gap), not `.reverted`. -/
theorem unsupported_is_error :
    (match runEntrypointResult State.empty unsupportedEntrypoint
     with | .error _ => true | _ => false) = true := by
  native_decide

/-- The string classifier agrees: "assertion failed: ..." is a revert message. -/
theorem assertion_failed_string_is_revert :
    ExecResult.isRevertMessage "assertion failed: x" = true := by
  native_decide

/-- The string classifier agrees: "revert: msg" is a revert message. -/
theorem revert_string_is_revert :
    ExecResult.isRevertMessage "revert: msg" = true := by
  native_decide

/-- The string classifier agrees: unsupported-construct messages are not reverts. -/
theorem unsupported_string_is_not_revert :
    ExecResult.isRevertMessage "statement is not supported by the scalar semantics model" = false := by
  native_decide

end ProofForge.Tests.IRExecResult

def main : IO UInt32 := do
  IO.println "ir-exec-result-smoke: ExecResult three-valued classification (ok/reverted/error) for assert/revert/revertWithError/unsupported checked via native_decide"
  return 0
