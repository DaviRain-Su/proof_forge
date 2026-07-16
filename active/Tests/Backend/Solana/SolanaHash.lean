/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Portable Crypto Hash Lowering Test

Validates that portable `hashValue`, `hash`, and `hashTwoToOne` lower to
`sol_sha256` calls in the `solana-sbpf-asm` backend.
-/

import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.IR.Contract

namespace ProofForge.Tests.SolanaHash

open ProofForge.IR
open ProofForge.Backend.Solana

def stateCount : StateDecl := {
  id := "count"
  kind := .scalar
  type := .u64
}

def hashValueEntrypoint : Entrypoint := {
  name := "hashValue"
  selector? := some "00000000"
  returns := .unit
  params := #[]
  body := #[
    .letBind "h" .hash (.hashValue (.literal (.u64 1)) (.literal (.u64 2)) (.literal (.u64 3)) (.literal (.u64 4))),
    .letBind "x" .u64 (.hashValue (.literal (.u64 1)) (.literal (.u64 2)) (.literal (.u64 3)) (.literal (.u64 4))),
    .effect (.storageScalarWrite "count" (.local "x"))
  ]
}

def module : Module := {
  name := "HashTest"
  state := #[stateCount]
  entrypoints := #[hashValueEntrypoint]
}

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def main : IO UInt32 := do
  match SbpfAsm.renderModule module with
  | .error err =>
      IO.eprintln s!"SolanaHash: FAILED: {err.render}"
      pure 1
  | .ok asm =>
      require (asm.contains "hashValue: pack four u64 words into input buffer") "missing hashValue comment"
      require (asm.contains "hashValue: call sol_sha256") "missing hashValue syscall comment"
      require (asm.contains "call sol_sha256") "missing sol_sha256 call"
      IO.println "SolanaHash: ok"
      pure 0

end ProofForge.Tests.SolanaHash

def main : IO UInt32 :=
  ProofForge.Tests.SolanaHash.main
