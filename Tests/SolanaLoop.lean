/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Bounded Loop Lowering Test

Validates that `IR.Statement.boundedFor` lowers to a counted loop in the
`solana-sbpf-asm` backend.
-/

import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.IR.Contract

namespace ProofForge.Tests.SolanaLoop

open ProofForge.IR
open ProofForge.Backend.Solana

def stateCount : StateDecl := {
  id := "count"
  kind := .scalar
  type := .u64
}

def sumEntrypoint : Entrypoint := {
  name := "sum"
  selector? := some "00000000"
  returns := .unit
  params := #[]
  body := #[
    .letBind "total" .u64 (.literal (.u64 0)),
    .boundedFor "i" 0 10 #[
      .assignOp (.local "total") .add (.local "i")
    ],
    .effect (.storageScalarWrite "count" (.local "total"))
  ]
}

def module : Module := {
  name := "LoopTest"
  state := #[stateCount]
  entrypoints := #[sumEntrypoint]
}

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def main : IO UInt32 := do
  match SbpfAsm.renderModule module with
  | .error err =>
      IO.eprintln s!"SolanaLoop: FAILED: {err.render}"
      pure 1
  | .ok asm =>
      require (asm.contains "sol_lbl_0:") "missing loop start label"
      require (asm.contains "sol_lbl_1:") "missing loop end label"
      require (asm.contains "add64 r2, 1") "missing index increment"
      require (asm.contains "jge r2, r3, sol_lbl_1") "missing loop bound check"
      IO.println "SolanaLoop: ok"
      pure 0

end ProofForge.Tests.SolanaLoop

def main : IO UInt32 :=
  ProofForge.Tests.SolanaLoop.main
