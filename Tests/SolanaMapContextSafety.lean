/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Map and Context Safety Test

Validates map lookup miss handling and account[0]-backed context reads in the
`solana-sbpf-asm` backend.
-/

import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.IR.Contract

namespace ProofForge.Tests.SolanaMapContextSafety

open ProofForge.IR
open ProofForge.Backend.Solana

def stateScores : StateDecl := {
  id := "scores"
  kind := .map .u64 4
  type := .u64
}

def stateLast : StateDecl := {
  id := "last"
  kind := .scalar
  type := .u64
}

def testEntrypoint : Entrypoint := {
  name := "test"
  selector? := some "00000000"
  returns := .unit
  params := #[]
  body := #[
    .letBind "score" .u64 (.effect (.storageMapGet "scores" (.literal (.u64 99)))),
    .letBind "caller" .u64 (.effect (.contextRead .userId)),
    .letBind "origin" .u64 (.effect (.contextRead .origin)),
    .effect (.storageScalarWrite "last" (.add (.add (.local "score") (.local "caller")) (.local "origin")))
  ]
}

def module : Module := {
  name := "MapContextSafetyTest"
  state := #[stateScores, stateLast]
  entrypoints := #[testEntrypoint]
}

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def main : IO UInt32 := do
  match SbpfAsm.renderModule module with
  | .error err =>
      IO.eprintln s!"SolanaMapContextSafety: FAILED: {err.render}"
      pure 1
  | .ok asm =>
      require (asm.contains "solana.storage.map_get scores: linear search 4 entries") "missing declared map capacity"
      require (asm.contains "mov64 r2, 0") "missing explicit map miss default"
      require (asm.contains "jge r3, r4") "missing map exhaustion branch"
      require (asm.contains "jne r6, r7") "missing map mismatch branch"
      require (asm.contains "solana.context.userId: read account[0] pubkey first 8 bytes as u64") "missing userId context lowering"
      require (asm.contains "solana.context.origin: read account[0] pubkey first 8 bytes as u64") "missing origin context lowering"
      require (asm.contains "ldxdw r2, [r1+16]") "missing account[0] pubkey load"
      IO.println "SolanaMapContextSafety: ok"
      pure 0

end ProofForge.Tests.SolanaMapContextSafety

def main : IO UInt32 :=
  ProofForge.Tests.SolanaMapContextSafety.main
