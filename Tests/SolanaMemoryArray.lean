/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Memory Array Lowering Test

Validates that heap-backed memory array operations (`memoryArrayNew`,
`memoryArrayLength`, `memoryArrayGet`, `memoryArraySet`) and `release`
lower to `sol_alloc_free_` based code in the `solana-sbpf-asm` backend.
-/

import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.IR.Contract

namespace ProofForge.Tests.SolanaMemoryArray

open ProofForge.IR
open ProofForge.Backend.Solana

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
    .letBind "arr" (.array .u64) (.memoryArrayNew .u64 (.literal (.u64 3))),
    .effect (.memoryArraySet (.local "arr") (.literal (.u64 0)) (.literal (.u64 7))),
    .effect (.memoryArraySet (.local "arr") (.literal (.u64 1)) (.literal (.u64 11))),
    .effect (.memoryArraySet (.local "arr") (.literal (.u64 2)) (.literal (.u64 13))),
    .letBind "len" .u64 (.memoryArrayLength (.local "arr")),
    .letBind "a" .u64 (.memoryArrayGet (.local "arr") (.literal (.u64 0))),
    .letBind "b" .u64 (.memoryArrayGet (.local "arr") (.literal (.u64 1))),
    .letBind "c" .u64 (.memoryArrayGet (.local "arr") (.literal (.u64 2))),
    .release "arr",
    .letBind "sum" .u64 (.add (.add (.add (.local "a") (.local "b")) (.local "c")) (.local "len")),
    .effect (.storageScalarWrite "total" (.local "sum"))
  ]
}

def module : Module := {
  name := "MemoryArrayTest"
  state := #[stateTotal]
  entrypoints := #[testEntrypoint]
}

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def main : IO UInt32 := do
  match SbpfAsm.renderModule module with
  | .error err =>
      IO.eprintln s!"SolanaMemoryArray: FAILED: {err.render}"
      pure 1
  | .ok asm =>
      require (asm.contains "memory.array.new: allocate heap array") "missing array new comment"
      require (asm.contains "memory.array.length: load length from header") "missing array length comment"
      require (asm.contains "memory.array.get") "missing array get comment"
      require (asm.contains "memory.array.set") "missing array set comment"
      require (asm.contains "memory.release arr: free heap array") "missing release comment"
      require (asm.contains "sol_alloc_free_") "missing sol_alloc_free_ syscall"
      require (asm.contains "add64 r2, 8") "missing data pointer adjustment"
      require (asm.contains "sub64 r2, 8") "missing header pointer adjustment"
      IO.println "SolanaMemoryArray: ok"
      pure 0

end ProofForge.Tests.SolanaMemoryArray

def main : IO UInt32 :=
  ProofForge.Tests.SolanaMemoryArray.main
