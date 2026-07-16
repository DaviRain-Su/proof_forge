/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Register Allocation

A simple register pool for the 11 sBPF registers. The convention is:

- r0: return value / syscall result
- r1: syscall arg 1 / entrypoint input pointer (preserved)
- r2–r5: syscall args 2–5 / scratch
- r6–r8: callee-saved scratch (can hold longer-lived temps)
- r9: entrypoint instruction-data pointer, preserved across internal helpers
- r10: frame pointer (stack, grows downward)

This module tracks which registers are free. Stack spill slots are assigned by
the lowering context because they must share the same frame allocator as locals
and scratch slots. It is intentionally simple for Phase 1; a real allocator can
replace it later without changing callers.

See `docs/targets/solana-sbpf-asm.md` (D-026).
-/

import ProofForge.Backend.Solana.Asm

namespace ProofForge.Backend.Solana.Register

open ProofForge.Backend.Solana.Asm

/-- Result of allocating a value location. Either a register or a stack slot. -/
inductive Loc where
  | reg (r : Reg)
  | spill (off : Nat)
  deriving Repr, Inhabited

def Loc.isReg : Loc → Bool
  | .reg _ => true
  | .spill _ => false

def Loc.reg? : Loc → Option Reg
  | .reg r => some r
  | .spill _ => none

def Loc.render : Loc → String
  | .reg r => r.render
  | .spill off => s!"[r10-{off}]"

/-- Registers available for general allocation. r0, r1, r2, r9, r10 are reserved:
r0 is the return/syscall-result register, r1 is the input pointer, r2 is the
current expression-result register, r9 is the instruction-data pointer, and r10
is the frame pointer. -/
def allocatableRegs : Array Reg := #[.r4, .r5, .r6, .r7, .r8]

structure Allocator where
  inUse : Array Reg
  deriving Repr, Inhabited

def Allocator.new : Allocator := { inUse := #[] }

/-- Allocate a register if one is available. Stack fallback belongs to
`LowerCtx`, where stack offsets can be kept disjoint from locals and scratch
temporaries. -/
def Allocator.allocReg? (a : Allocator) : Option Reg × Allocator :=
  match allocatableRegs.find? (fun r => !a.inUse.contains r) with
  | some r => (some r, { a with inUse := a.inUse.push r })
  | none   => (none, a)

/-- Mark a location as free again. -/
def Allocator.free (a : Allocator) (loc : Loc) : Allocator :=
  match loc with
  | .reg r => { a with inUse := a.inUse.filter (· != r) }
  | .spill _ => a

end ProofForge.Backend.Solana.Register
