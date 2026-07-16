/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Storage Struct Field Lowering Test

Validates that `storageStructFieldRead` and `storageStructFieldWrite` lower
to account-data loads/stores with struct-field offsets in the
`solana-sbpf-asm` backend.
-/

import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.IR.Contract

namespace ProofForge.Tests.SolanaStorageStructField

open ProofForge.IR
open ProofForge.Backend.Solana

def structPoint : StructDecl := {
  name := "Point"
  fields := #[
    { id := "x", type := .u64 },
    { id := "y", type := .u64 }
  ]
}

def stateCurrent : StateDecl := {
  id := "current"
  kind := .scalar
  type := .structType "Point"
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
    .effect (.storageStructFieldWrite "current" "x" (.literal (.u64 7))),
    .effect (.storageStructFieldWrite "current" "y" (.literal (.u64 11))),
    .letBind "sx" .u64 (.effect (.storageStructFieldRead "current" "x")),
    .letBind "sy" .u64 (.effect (.storageStructFieldRead "current" "y")),
    .letBind "sum" .u64 (.add (.local "sx") (.local "sy")),
    .effect (.storageScalarWrite "total" (.local "sum"))
  ]
}

def module : Module := {
  name := "StorageStructFieldTest"
  structs := #[structPoint]
  state := #[stateCurrent, stateTotal]
  entrypoints := #[testEntrypoint]
}

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def main : IO UInt32 := do
  match SbpfAsm.renderModule module with
  | .error err =>
      IO.eprintln s!"SolanaStorageStructField: FAILED: {err.render}"
      pure 1
  | .ok asm =>
      require (asm.contains "solana.storage.struct_field_read current.x") "missing struct_field_read x comment"
      require (asm.contains "solana.storage.struct_field_read current.y") "missing struct_field_read y comment"
      require (asm.contains "solana.storage.struct_field_write current.x") "missing struct_field_write x comment"
      require (asm.contains "solana.storage.struct_field_write current.y") "missing struct_field_write y comment"
      require (asm.contains "add64 r3, 8") "missing y field offset" -- y offset = 8
      IO.println "SolanaStorageStructField: ok"
      pure 0

end ProofForge.Tests.SolanaStorageStructField

def main : IO UInt32 :=
  ProofForge.Tests.SolanaStorageStructField.main
