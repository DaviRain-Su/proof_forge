/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Scheme 2 Phase B — lift labeled slots → solanalib.BpfInstruction

Direct structural lift from mathlib-free `ResolvedInst` to
`Solanalib.SBPF.BpfInstruction`, **without** a byte round-trip. The product
still emits text via EmitSBPF; this path exists so CompileCorrect can talk
about instruction lists that solanalib's `verifyInstr` / `step` understand.

Portable IR remains the sole multi-chain source. This module only handles the
Solana target leg:

```
IR.Semantics  (shared)
     │
     ▼
EmitSBPF AstNode → LabeledSbpf → ResolvedInst
                                      │ liftResolved
                                      ▼
                              BpfInstruction
                                      │ verifyInstr / step_ne_err
                                      ▼
                              solanalib safety
```

Differential honesty: for Counter, `liftProgram` and `decodeAll ∘ encode`
produce the same instruction list (`counter_lift_matches_decode`).
-/

import ProofForge.Backend.Solana.BpfEncode
import ProofForge.Backend.Solana.LabeledSbpf
import ProofForge.IR.Examples.Counter
import ProofForgeFormal.Solana.SolanalibAdapter
import Solanalib.SBPF.CommType
import Solanalib.SBPF.Syntax
import Solanalib.SBPF.Memory
import Solanalib.SBPF.Decoder
import Solanalib.SBPF.Verifier

namespace ProofForge.Backend.Solana.LabeledToSolanalib

open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.BpfEncode
open ProofForge.Backend.Solana.LabeledSbpf
open ProofForge.Backend.Solana.SolanalibAdapter
open Solanalib.SBPF

def u4OfNat (n : Nat) : U4 := BitVec.ofNat 4 n
def u16OfNat (n : Nat) : U16 := BitVec.ofNat 16 n
def u32OfNat (n : Nat) : U32 := BitVec.ofNat 32 n

def regOfNat? (n : Nat) : Option BpfIReg :=
  BpfIReg.ofU4 (u4OfNat n)

def requireReg (n : Nat) : Except String BpfIReg :=
  match regOfNat? n with
  | some r => .ok r
  | none => .error s!"solanalib lift: bad register index {n}"

def binopOfAlu64 : Opcode → Option Binop
  | .add64 => some .add
  | .sub64 => some .sub
  | .mul64 => some .mul
  | .div64 => some .div
  | .or64 => some .or
  | .and64 => some .and
  | .lsh64 => some .lsh
  | .rsh64 => some .rsh
  | .mod64 => some .mod
  | .xor64 => some .xor
  | .mov64 => some .mov
  | .arsh64 => some .arsh
  | _ => none

def binopOfAlu32 : Opcode → Option Binop
  | .add32 => some .add
  | .sub32 => some .sub
  | .mul32 => some .mul
  | .div32 => some .div
  | .or32 => some .or
  | .and32 => some .and
  | .lsh32 => some .lsh
  | .rsh32 => some .rsh
  | .mod32 => some .mod
  | .xor32 => some .xor
  | .mov32 => some .mov
  | .arsh32 => some .arsh
  | _ => none

def condOfJump : Opcode → Option Condition
  | .jeq => some .eq
  | .jgt => some .gt
  | .jge => some .ge
  | .jlt => some .lt
  | .jle => some .le
  | .jset => some .sEt
  | .jne => some .ne
  | .jsgt => some .sGt
  | .jsge => some .sGe
  | .jslt => some .sLt
  | .jsle => some .sLe
  | _ => none

def loadChunk : Opcode → Option MemoryChunk
  | .ldxb => some .m8
  | .ldxh => some .m16
  | .ldxw => some .m32
  | .ldxdw => some .m64
  | _ => none

def storeChunkImm : Opcode → Option MemoryChunk
  | .stb => some .m8
  | .sth => some .m16
  | .stw => some .m32
  | .stdw => some .m64
  | _ => none

def storeChunkReg : Opcode → Option MemoryChunk
  | .stxb => some .m8
  | .stxh => some .m16
  | .stxw => some .m32
  | .stxdw => some .m64
  | _ => none

/-- Lift one resolved slot. Pads of `lddw` are skipped by the caller (the
`ldImm` constructor already carries both halves). -/
def liftResolved (ri : ResolvedInst) : Except String BpfInstruction := do
  if ri.isLddwPad then
    .error "solanalib lift: unexpected lddw pad (caller should skip)"
  else if ri.opcode == .lddw then
    let dst ← requireReg ri.dst
    let lo := u32OfNat (maskBits ri.immBits 32)
    let hi := u32OfNat (ri.immBits / (2 ^ 32))
    .ok (.ldImm dst lo hi)
  else if ri.opcode == .exit then
    .ok .exit
  else if ri.opcode == .call then
    -- callImm: solanalib stores src register (unused for helper calls) + imm
    .ok (.callImm .br0 (u32OfNat ri.immBits))
  else if ri.opcode == .callx then
    let src ← requireReg ri.src
    .ok (.callReg src 0)
  else if ri.opcode == .ja then
    .ok (.ja (u16OfNat ri.offBits))
  else if ri.opcode == .neg64 then
    let dst ← requireReg ri.dst
    .ok (.neg64Reg dst)
  else if ri.opcode == .neg32 then
    let dst ← requireReg ri.dst
    .ok (.neg32Reg dst)
  else if ri.opcode.isEndian then
    let dst ← requireReg ri.dst
    let imm := u32OfNat ri.immBits
    if ri.opcode == .le16 || ri.opcode == .le32 || ri.opcode == .le64 then
      .ok (.le dst imm)
    else
      .ok (.be dst imm)
  else if let some chk := loadChunk ri.opcode then
    let dst ← requireReg ri.dst
    let src ← requireReg ri.src
    .ok (.ldx chk dst src (u16OfNat ri.offBits))
  else if let some chk := storeChunkImm ri.opcode then
    let dst ← requireReg ri.dst
    .ok (.st chk dst (.imm (u32OfNat ri.immBits)) (u16OfNat ri.offBits))
  else if let some chk := storeChunkReg ri.opcode then
    let dst ← requireReg ri.dst
    let src ← requireReg ri.src
    .ok (.st chk dst (.reg src) (u16OfNat ri.offBits))
  else if let some bop := binopOfAlu64 ri.opcode then
    let dst ← requireReg ri.dst
    if ri.usesRegSrc then
      let src ← requireReg ri.src
      .ok (.alu64 bop dst (.reg src))
    else
      .ok (.alu64 bop dst (.imm (u32OfNat ri.immBits)))
  else if let some bop := binopOfAlu32 ri.opcode then
    let dst ← requireReg ri.dst
    if ri.usesRegSrc then
      let src ← requireReg ri.src
      .ok (.alu bop dst (.reg src))
    else
      .ok (.alu bop dst (.imm (u32OfNat ri.immBits)))
  else if let some cond := condOfJump ri.opcode then
    let dst ← requireReg ri.dst
    let off := u16OfNat ri.offBits
    if ri.usesRegSrc then
      let src ← requireReg ri.src
      .ok (.jump cond dst (.reg src) off)
    else
      .ok (.jump cond dst (.imm (u32OfNat ri.immBits)) off)
  else
    .error s!"solanalib lift: unsupported opcode `{ri.opcode.render}`"

/-- Lift a full resolved slot array, skipping `lddw` pads. -/
def liftSlots (slots : Array ResolvedInst) : Except String (List BpfInstruction) :=
  go slots.size 0 []
where
  go : Nat → Nat → List BpfInstruction → Except String (List BpfInstruction)
    | 0, _, acc => .ok acc.reverse
    | fuel + 1, i, acc =>
        if h : i < slots.size then
          let ri := slots[i]
          if ri.isLddwPad then
            go fuel (i + 1) acc
          else
            match liftResolved ri with
            | .error e => .error e
            | .ok ins => go fuel (i + 1) (ins :: acc)
        else
          .ok acc.reverse

def liftProgram (p : LabeledProgram) : Except String (List BpfInstruction) :=
  liftSlots p.slots

def liftModule (module : ProofForge.IR.Module) : Except String (List BpfInstruction) :=
  match fromModule module with
  | .error e => .error e
  | .ok p => liftProgram p

/-- Every lifted instruction verifies under sBPF v1. -/
def liftVerifyOk (module : ProofForge.IR.Module) : Bool :=
  match liftModule module with
  | .error _ => false
  | .ok insns => !insns.isEmpty && verifyAll insns .v1

/-- Differential: direct lift equals decode-after-encode for Counter. -/
def liftMatchesDecode (module : ProofForge.IR.Module) : Bool :=
  match liftModule module, SolanalibAdapter.lowerModuleToBpfBin module with
  | .ok lifted, .ok bin =>
      match decodeAll bin with
      | .ok decoded =>
          -- BpfInstruction has DecidableEq.
          lifted == decoded
      | .error _ => false
  | _, _ => false

theorem counter_lift_verify_ok :
    liftVerifyOk ProofForge.IR.Examples.Counter.module = true := by
  native_decide

theorem counter_lift_matches_decode :
    liftMatchesDecode ProofForge.IR.Examples.Counter.module = true := by
  native_decide

end ProofForge.Backend.Solana.LabeledToSolanalib
