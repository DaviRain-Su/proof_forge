/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Smoke test for `ProofForge.Backend.Solana.CoreLower`.
See `.superpowers/sdd/task-7-brief.md`.
-/

import ProofForge.IR.Legacy.Core
import ProofForge.Backend.Solana.CorePlan
import ProofForge.Backend.Solana.CoreLower

open ProofForge.IR.Legacy.Core
open ProofForge.Backend.Solana.CorePlan
open ProofForge.Backend.Solana.CoreLower

def main : IO UInt32 := do
  let m : CoreModule :=
    { name := "Counter"
    , structs := []
    , state := [ { name := "count", ty := .u64, initializer := .some (.literal (.u64Lit 0)) } ]
    , entrypoints := [ { name := "increment", params := [], retTy := .unit, body := [] } ]
    , events := []
    }
  let plan := buildSolanaCorePlan m
  let asm := lowerSolanaCorePlan plan
  if asm.length > 0 then
    IO.println "SolanaCoreSmoke OK"
    return 0
  else
    IO.println "SolanaCoreSmoke FAIL"
    return 1
