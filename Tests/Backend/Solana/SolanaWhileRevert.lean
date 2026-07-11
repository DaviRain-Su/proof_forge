/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF While-Loop and Revert Lowering Test

Validates that `IR.Statement.whileLoop` lowers to a conditional backward jump
and that `revert` / `revertWithError` lower to `exit` with the correct codes.
-/

import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.IR.Contract

namespace ProofForge.tests.SolanaWhileRevert

open ProofForge.IR
open ProofForge.Backend.Solana

def stateAccum : StateDecl := {
  id := "accum"
  kind := .scalar
  type := .u64
}

/-- Entrypoint with an unbounded while-loop: decrement a counter until it hits
zero, accumulating into storage. -/
def whileLoopEntrypoint : Entrypoint := {
  name := "drain"
  selector? := some "00000000"
  returns := .unit
  params := #[("remaining", .u64)]
  body := #[
    .letMutBind "n" .u64 (.local "remaining"),
    .whileLoop (.gt (.local "n") (.literal (.u64 0))) #[
      .assignOp (.local "n") .sub (.literal (.u64 1))
    ],
    .effect (.storageScalarWrite "accum" (.local "n"))
  ]
}

def revertEntrypoint : Entrypoint := {
  name := "revertAlways"
  selector? := some "00000000"
  returns := .unit
  params := #[]
  body := #[.revert "always rolls back"]
}

def revertWithErrorEntrypoint : Entrypoint := {
  name := "revertWithErr"
  selector? := some "00000000"
  returns := .unit
  params := #[]
  body := #[.revertWithError { assertionId := 42 }]
}

def module : Module := {
  name := "WhileRevertTest"
  state := #[stateAccum]
  entrypoints := #[whileLoopEntrypoint, revertEntrypoint, revertWithErrorEntrypoint]
}

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def main : IO UInt32 := do
  match SbpfAsm.renderModule module with
  | .error err =>
      IO.eprintln s!"SolanaWhileRevert: FAILED: {err.render}"
      pure 1
  | .ok asm =>
      -- whileLoop: should have a loop start label, condition check, backward jump
      require (asm.contains "control.whileLoop") "missing whileLoop comment"
      require (asm.contains "jeq r2, 0,") "missing whileLoop condition check"
      require (asm.contains "ja sol_lbl_") "missing whileLoop backward jump"
      -- revert: should have exit with code 7
      require (asm.contains "control.revert") "missing revert comment"
      require (asm.contains "mov64 r0, 7") "missing revert exit code 7"
      require (asm.contains "exit") "missing exit after revert"
      -- revertWithError: should have exit with custom error code 4294967338 (4294967296 + 42)
      require (asm.contains "control.revertWithError error=42") "missing revertWithError comment"
      require (asm.contains "mov64 r0, 4294967338") "missing revertWithError custom error code"
      IO.println "SolanaWhileRevert: ok"
      pure 0

end ProofForge.tests.SolanaWhileRevert

def main : IO UInt32 :=
  ProofForge.tests.SolanaWhileRevert.main