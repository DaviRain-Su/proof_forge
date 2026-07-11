/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana Core Plan

Decoupling-layer skeleton that maps a portable `CoreModule` (Task 1) to a
Solana-specific core plan. This is intentionally lightweight: it records the
account model, state layout, and entrypoint signatures while leaving assembly
lowering as a downstream concern.

See `.superpowers/sdd/task-6-brief.md`.
-/

import ProofForge.IR.Legacy.Core
import ProofForge.Backend.Solana.Asm

namespace ProofForge.Backend.Solana.CorePlan

open ProofForge.IR.Core

structure AccountPlan where
  name : String
  isMutable : Bool
  deriving Repr

structure EntrypointPlan where
  name : String
  params : List (String × CoreType)
  body : List Asm.AstNode
  deriving Repr

structure SolanaCorePlan where
  moduleName : String
  accounts : List AccountPlan
  stateLayout : List (String × Nat)
  entrypoints : List EntrypointPlan
  deriving Repr

def buildSolanaCorePlan (m : CoreModule) : SolanaCorePlan :=
  { moduleName := m.name
  , accounts := [ { name := "data", isMutable := true } ]
  , stateLayout := m.state.mapIdx fun i s => (s.name, i * 8)
  , entrypoints := m.entrypoints.map fun e =>
      { name := e.name, params := e.params, body := [] }
  }

end ProofForge.Backend.Solana.CorePlan
