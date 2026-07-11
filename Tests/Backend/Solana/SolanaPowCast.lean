/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Pow / Cast / Bitwise / Bytes / String Literal Lowering Test

Validates lowering of `Expr.pow`, `Expr.cast`, bitwise/shift ops, and
`Literal.bytes` / `Literal.string` in the `solana-sbpf-asm` backend.
-/

import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.IR.Contract

namespace ProofForge.tests.SolanaPowCast

open ProofForge.IR
open ProofForge.Backend.Solana

def stateResult : StateDecl := {
  id := "result"
  kind := .scalar
  type := .u64
}

/-- pow: 2^10 = 1024 -/
def powEntrypoint : Entrypoint := {
  name := "powTest"
  selector? := some "00000000"
  returns := .unit
  params := #[]
  body := #[
    .effect (.storageScalarWrite "result"
      (.pow (.literal (.u64 2)) (.literal (.u64 10))))
  ]
}

/-- cast: u64 → u8 (truncate to 0xFF) -/
def castEntrypoint : Entrypoint := {
  name := "castTest"
  selector? := some "00000000"
  returns := .unit
  params := #[]
  body := #[
    .effect (.storageScalarWrite "result"
      (.cast (.literal (.u64 256)) .u8))
  ]
}

/-- bitAnd: 0xFF & 0x0F = 0x0F -/
def bitAndEntrypoint : Entrypoint := {
  name := "bitAndTest"
  selector? := some "00000000"
  returns := .unit
  params := #[]
  body := #[
    .effect (.storageScalarWrite "result"
      (.bitAnd (.literal (.u64 255)) (.literal (.u64 15))))
  ]
}

/-- string literal: store a short string into storage as u64 handle -/
def stringLitEntrypoint : Entrypoint := {
  name := "stringLitTest"
  selector? := some "00000000"
  returns := .unit
  params := #[]
  body := #[
    .letBind "ptr" .u64 (.literal (.string "hello")),
    .effect (.storageScalarWrite "result" (.local "ptr"))
  ]
}

def module : Module := {
  name := "PowCastTest"
  state := #[stateResult]
  entrypoints := #[powEntrypoint, castEntrypoint, bitAndEntrypoint, stringLitEntrypoint]
}

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def main : IO UInt32 := do
  match SbpfAsm.renderModule module with
  | .error err =>
      IO.eprintln s!"SolanaPowCast: FAILED: {err.render}"
      pure 1
  | .ok asm =>
      -- pow: should have a loop with mul64
      require (asm.contains "solana.pow:") "missing pow comment"
      require (asm.contains "mul64 r2, r3") "missing pow multiply"
      -- cast: should have and64 with 255
      require (asm.contains "solana.cast: u64 → u8") "missing cast comment"
      require (asm.contains "and64 r2, 255") "missing cast mask"
      -- bitAnd: should have and64
      require (asm.contains "and64 r2, r3") "missing bitAnd"
      -- string literal: should have stb instructions
      require (asm.contains "string literal:") "missing string literal comment"
      require (asm.contains "stb") "missing stb for string literal"
      IO.println "SolanaPowCast: ok"
      pure 0

end ProofForge.tests.SolanaPowCast

def main : IO UInt32 :=
  ProofForge.tests.SolanaPowCast.main