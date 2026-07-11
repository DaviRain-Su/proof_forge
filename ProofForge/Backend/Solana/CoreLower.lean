/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana Core Lower

Skeleton lowering from the Solana core plan (`SolanaCorePlan`) to sBPF
assembly AST nodes (`AstNode`). This is intentionally minimal: it emits the
.text section, a global declaration for the module, and one placeholder
instruction per entrypoint. Real instruction selection will be layered on top
in later tasks.

See `.superpowers/sdd/task-7-brief.md`.
-/

import ProofForge.Backend.Solana.CorePlan
import ProofForge.Backend.Solana.Asm

namespace ProofForge.Backend.Solana.CoreLower

open ProofForge.Backend.Solana.CorePlan
open ProofForge.Backend.Solana.Asm

/-- A no-op instruction used as a placeholder for unlowered entrypoints. -/
def nopInst : AstNode :=
  .instruction { opcode := .mov64, dst := some .r0, src := some .r0 }

def lowerSolanaCorePlan (p : SolanaCorePlan) : List AstNode :=
  [ .sectionDecl .text
  , .globalDecl p.moduleName
  ] ++ p.entrypoints.flatMap (fun _ => [ nopInst ])

end ProofForge.Backend.Solana.CoreLower
