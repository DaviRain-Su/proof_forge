/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Storage Array-of-Struct Lowering Test

Validates that `storageArrayStructFieldRead` and
`storageArrayStructFieldWrite` lower to indexed account-data loads/stores
with struct-field offsets in the `solana-sbpf-asm` backend.
-/

import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.IR.Contract

namespace ProofForge.Tests.SolanaStorageArrayStruct

open ProofForge.IR
open ProofForge.Backend.Solana

def structPerson : StructDecl := {
  name := "Person"
  fields := #[
    { id := "age", type := .u64 },
    { id := "score", type := .u64 }
  ]
}

def statePeople : StateDecl := {
  id := "people"
  kind := .array 2
  type := .fixedArray (.structType "Person") 2
}

def stateTotal : StateDecl := {
  id := "total"
  kind := .scalar
  type := .u64
}

def testEntrypoint : Entrypoint := {
  name := "test"
  selector? := some "00000000"
  returns := .unit
  params := #[]
  body := #[
    .effect (.storageArrayStructFieldWrite "people" (.literal (.u64 0)) "age" (.literal (.u64 21))),
    .effect (.storageArrayStructFieldWrite "people" (.literal (.u64 0)) "score" (.literal (.u64 100))),
    .letBind "s" .u64 (.effect (.storageArrayStructFieldRead "people" (.literal (.u64 0)) "score")),
    .effect (.storageScalarWrite "total" (.local "s"))
  ]
}

def module : Module := {
  name := "StorageArrayStructTest"
  structs := #[structPerson]
  state := #[statePeople, stateTotal]
  entrypoints := #[testEntrypoint]
}

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def main : IO UInt32 := do
  match SbpfAsm.renderModule module with
  | .error err =>
      IO.eprintln s!"SolanaStorageArrayStruct: FAILED: {err.render}"
      pure 1
  | .ok asm =>
      require (asm.contains "solana.storage.array_struct_field_read people.score") "missing array_struct_field_read comment"
      require (asm.contains "solana.storage.array_struct_field_write people.age") "missing array_struct_field_write age comment"
      require (asm.contains "solana.storage.array_struct_field_write people.score") "missing array_struct_field_write score comment"
      require (asm.contains "error_array_bounds") "missing array struct bounds guard"
      require (asm.contains "error_array_bounds:") "missing array bounds error handler"
      require (asm.contains "mul64 r2, r3") "missing index scaling"
      require (asm.contains "add64 r2, r1") "missing base pointer add"
      require (asm.contains "add64 r2, 8") "missing score field offset" -- score offset = 8
      require (asm.contains "ldxdw r2, [r2+0]") "missing array struct field load"
      require (asm.contains "stxdw [r2+0], r3") "missing array struct field store"
      IO.println "SolanaStorageArrayStruct: ok"
      pure 0

end ProofForge.Tests.SolanaStorageArrayStruct

def main : IO UInt32 :=
  ProofForge.Tests.SolanaStorageArrayStruct.main
