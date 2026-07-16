/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Storage Array Lowering Test

Validates that `storageArrayRead` and `storageArrayWrite` lower to indexed
account-data loads/stores in the `solana-sbpf-asm` backend.
-/

import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.IR.Contract

namespace ProofForge.Tests.SolanaStorageArray

open ProofForge.IR
open ProofForge.Backend.Solana

def stateCount : StateDecl := {
  id := "count"
  kind := .scalar
  type := .u64
}

def stateValues : StateDecl := {
  id := "values"
  kind := .array 5
  type := .u64
}

def testEntrypoint : Entrypoint := {
  name := "test"
  selector? := some "00000000"
  returns := .unit
  params := #[]
  body := #[
    .letBind "x" .u64 (.effect (.storageArrayRead "values" (.literal (.u64 2)))),
    .effect (.storageArrayWrite "values" (.literal (.u64 2)) (.literal (.u64 42))),
    .effect (.storageScalarWrite "count" (.local "x"))
  ]
}

def module : Module := {
  name := "StorageArrayTest"
  state := #[stateCount, stateValues]
  entrypoints := #[testEntrypoint]
}

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def main : IO UInt32 := do
  match SbpfAsm.renderModule module with
  | .error err =>
      IO.eprintln s!"SolanaStorageArray: FAILED: {err.render}"
      pure 1
  | .ok asm =>
      require (asm.contains "solana.storage.array_read values") "missing array_read comment"
      require (asm.contains "solana.storage.array_write values") "missing array_write comment"
      require (asm.contains "error_array_bounds") "missing array bounds guard"
      require (asm.contains "error_array_bounds:") "missing array bounds error handler"
      require (asm.contains "mul64 r2, r3") "missing index scaling"
      require (asm.contains "add64 r2, r1") "missing base pointer add"
      require (asm.contains "ldxdw r2, [r2+0]") "missing array load"
      require (asm.contains "stxdw [r2+0], r3") "missing array store"
      IO.println "SolanaStorageArray: ok"
      pure 0

end ProofForge.Tests.SolanaStorageArray

def main : IO UInt32 :=
  ProofForge.Tests.SolanaStorageArray.main
