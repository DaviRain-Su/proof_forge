/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Labeled sBPF intermediate (Scheme 2 Phase A, mathlib-free)

A **register-machine labeled assembly** view of EmitSBPF output, sitting
between the structured text AST (`Asm.AstNode`) and the binary seam
(`BpfEncode.BpfBinBytes`). This is the ProofForge analogue of yul-compiler's
labeled assembly — adapted to sBPF's 11-register model rather than a stack.

## Why this exists (Portable IR stays the source)

```
Lean Contract Intent
        │
        ▼
Portable IR  +  IR.Semantics          ← multi-chain source of truth
        │
        ├── EVM / NEAR / Sui / …      (other backends unchanged)
        │
        └── Solana EmitSBPF
              IR.Module
                 │ SbpfAsm.lowerModule
                 ▼
              Array AstNode           ← product text path (.s → sbpf → ELF)
                 │ LabeledSbpf.fromNodes
                 ▼
              LabeledProgram          ← this module (symbolic + resolved)
                 │ BpfEncode
                 ▼
              BpfBinBytes
                 │ (opt-in ProofForgeFormalSolana)
                 ▼
              solanalib BpfInstruction / bpfInterp
```

**Non-goal:** replace Portable IR with dennj-style "Lean → sBPF" direct
cross-compilation. Hybrid "simple contracts skip IR" is explicitly out of
scope. Every Solana proof obligation still starts from `IR.Semantics`.

## What is machine-checkable today

- Building a `LabeledProgram` from Counter/ValueVault lowering succeeds
  (`labeledProgramOk`).
- Every instruction is either a resolved numeric slot or a labeled
  pseudo-op that `BpfEncode` already knows how to materialise.
- The labeled view's bytecode equals `BpfEncode.toBpfBin` (same encoder).

Scheme 2 Phase B (lift `ResolvedInst` → `Solanalib.SBPF.BpfInstruction`
without a byte round-trip) lives in the opt-in `ProofForgeFormalSolana` target.
-/

import ProofForge.Backend.Solana.Asm
import ProofForge.Backend.Solana.BpfEncode
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.Solana.SbpfInterpreter
import ProofForge.IR.Contract
import ProofForge.IR.Examples.Counter

namespace ProofForge.Backend.Solana.LabeledSbpf

open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.BpfEncode
open ProofForge.Backend.Solana.SbpfInterpreter
open ProofForge.IR

/-- One labeled-assembly item: either a label anchor or a resolved instruction
slot (post label/equ resolution, pre binary packing). -/
inductive LabeledItem where
  | label (name : String) (slot : Nat)
  | inst (ri : ResolvedInst)
  deriving Repr, Inhabited

/-- A labeled sBPF program: ordered items + the flat bytecode they encode to. -/
structure LabeledProgram where
  /-- Source IR module name (for diagnostics / fragment checks). -/
  moduleName : String := ""
  /-- Label → bytecode slot (post-lddw expansion). -/
  labels : Array (String × Nat) := #[]
  /-- Resolved instruction slots (including `lddw` pads). -/
  slots : Array ResolvedInst := #[]
  /-- Binary encoding of `slots` (same bytes as `BpfEncode.toBpfBin`). -/
  bytes : BpfBinBytes := #[]
  deriving Repr, Inhabited

def LabeledProgram.itemCount (p : LabeledProgram) : Nat :=
  p.labels.size + p.slots.size

/-- Build a labeled program from a collected `SbpfProgram` (labels already at
ProofForge instruction indices; encoder remaps to slots). -/
def fromSbpfProgram (program : SbpfProgram) (moduleName : String := "") :
    Except EncodeError LabeledProgram := do
  let (slots, bytes) ← resolveProgram program
  let slotOf := buildSlotIndexMap program.instructions
  let labels := buildSlotLabels program slotOf
  .ok { moduleName, labels, slots, bytes }

/-- Build from the structured EmitSBPF AST. -/
def fromNodes (nodes : Array AstNode) (moduleName : String := "") :
    Except EncodeError LabeledProgram :=
  fromSbpfProgram (collectProgram nodes) moduleName

/-- Lower an IR module to labeled sBPF (EmitSBPF + resolve). -/
def fromModule (module : Module) : Except String LabeledProgram :=
  match ProofForge.Backend.Solana.SbpfAsm.lowerModule module with
  | .error e => .error e.render
  | .ok nodes =>
      match fromNodes nodes module.name with
      | .error e => .error e.render
      | .ok p => .ok p

/-- Well-formed labeled program: non-empty slots, well-formed bytes, and
byte length matches 8 × slot count (`lddw` pads already expanded). -/
def labeledProgramOk (p : LabeledProgram) : Bool :=
  p.slots.size > 0 &&
    bpfBinWellFormed p.bytes &&
    p.bytes.size == p.slots.size * 8

/-- Module-level smoke predicate (default path, no solanalib). -/
def moduleLabeledOk (module : Module) : Bool :=
  match fromModule module with
  | .error _ => false
  | .ok p => labeledProgramOk p

/-- Round-trip honesty: labeled bytecode equals the direct encode seam. -/
def labeledMatchesEncode (module : Module) : Bool :=
  match fromModule module, lowerModuleToBpfBin module with
  | .ok p, .ok bytes => p.bytes == bytes
  | _, _ => false

theorem counter_labeled_ok :
    moduleLabeledOk ProofForge.IR.Examples.Counter.module = true := by
  native_decide

theorem counter_labeled_matches_encode :
    labeledMatchesEncode ProofForge.IR.Examples.Counter.module = true := by
  native_decide

end ProofForge.Backend.Solana.LabeledSbpf
