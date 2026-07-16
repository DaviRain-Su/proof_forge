/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Fixed Array and Struct Lowering Test

Validates that fixed-array locals, array indexing, struct locals, and field
access lower correctly in the `solana-sbpf-asm` backend.
-/

import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.IR.Contract

namespace ProofForge.Tests.SolanaFixedArrayStruct

open ProofForge.IR
open ProofForge.Backend.Solana

def stateCount : StateDecl := {
  id := "count"
  kind := .scalar
  type := .u64
}

def pointStruct : StructDecl := {
  name := "Point"
  fields := #[
    { id := "x", type := .u64 },
    { id := "y", type := .u64 }
  ]
}

def arrayEntrypoint : Entrypoint := {
  name := "array"
  selector? := some "00000000"
  returns := .unit
  params := #[]
  body := #[
    .letBind "arr" (.fixedArray .u64 3)
      (.arrayLit .u64 #[.literal (.u64 10), .literal (.u64 20), .literal (.u64 30)]),
    .letBind "x" .u64 (.arrayGet (.local "arr") (.literal (.u64 1))),
    .effect (.storageScalarWrite "count" (.local "x"))
  ]
}

def structEntrypoint : Entrypoint := {
  name := "struct"
  selector? := some "00000001"
  returns := .unit
  params := #[]
  body := #[
    .letBind "p" (.structType "Point")
      (.structLit "Point" #[("x", .literal (.u64 7)), ("y", .literal (.u64 8))]),
    .letBind "y" .u64 (.field (.local "p") "y"),
    .effect (.storageScalarWrite "count" (.local "y"))
  ]
}

def module : Module := {
  name := "FixedArrayStructTest"
  structs := #[pointStruct]
  state := #[stateCount]
  entrypoints := #[arrayEntrypoint, structEntrypoint]
}

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def main : IO UInt32 := do
  match SbpfAsm.renderModule module with
  | .error err =>
      IO.eprintln s!"SolanaFixedArrayStruct: FAILED: {err.render}"
      pure 1
  | .ok asm =>
      require (asm.contains "array literal: 3 x U64") "missing array literal comment"
      require (asm.contains "struct literal: Point") "missing struct literal comment"
      require (asm.contains "array.get: compute element address") "missing array.get comment"
      require (asm.contains "struct.field Point.y") "missing struct.field comment"
      require (asm.contains "stxdw [r3+0], r2") "missing array/struct element store"
      IO.println "SolanaFixedArrayStruct: ok"
      pure 0

end ProofForge.Tests.SolanaFixedArrayStruct

def main : IO UInt32 :=
  ProofForge.Tests.SolanaFixedArrayStruct.main
