/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# sBPF binary encoder (mathlib-free seam)

Encodes `ProofForge.Backend.Solana.Asm.Inst` into a flat little-endian byte
list matching the sBPF instruction layout that `solanalib.SBPF.Decoder`
(`findInstr`) and the Solana VM consume.

This module is intentionally **mathlib-free** and lives on the default
`ProofForge` build path (same isolation pattern as
`ProofForge.Backend.Evm.EvmBytecodeSemantics`). The opt-in
`ProofForgeFormalSolana` Lake target reinterprets the resulting bytes as
`Solanalib.SBPF.BpfBin` and lifts decoded instructions into
`Solanalib.SBPF.BpfInstruction` for `verifyInstr` / `bpfInterp`.

## Encoding layout (one 8-byte slot)

```
offset 0: opcode (u8)
offset 1: src_reg << 4 | dst_reg  (u8; each nibble 0..10)
offset 2: offset (i16 LE)         — jump target relative to next PC, or mem off
offset 4: imm (i32 LE)            — immediate / syscall id
```

`lddw` occupies **two** slots (16 bytes): opcode `0x18` with imm_lo, then a
zero-opcode pad with imm_hi (standard eBPF `LD_DW_IMM` form). Relative jump
offsets and label PCs are counted in **bytecode slots** (so `lddw` advances the
PC by 2), matching `solanalib.SBPF.findInstr`.

## Label / stack conventions

- Jump targets in `Asm.Inst` use absolute label symbols (`MemOff.sym`). The
  encoder resolves them to signed relative slot offsets
  `targetSlot - (pcSlot + 1)`.
- Stack-relative memory ops (`base = r10`) store a positive distance in the
  AST; the text printer emits `[r10-off]`. Binary encoding uses the signed
  i16 field `-off`, matching the Solana VM.

See `docs/solana-sbpf-solanalib-bridge.md`.
-/

import ProofForge.Backend.Solana.Asm
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.Solana.SbpfInterpreter
import ProofForge.Backend.Solana.Syscalls
import ProofForge.IR.Contract

namespace ProofForge.Backend.Solana.BpfEncode

open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.SbpfInterpreter
open ProofForge.Backend.Solana.Syscalls
open ProofForge.IR

/-- Flat little-endian bytecode (one byte per `Nat` in `0..255`). Mirrors
`Solanalib.SBPF.BpfBin` without importing mathlib/`BitVec`. -/
abbrev BpfBinBytes := Array Nat

/-- A fully numeric instruction ready for binary encoding. -/
structure ResolvedInst where
  opcode : Opcode
  dst : Nat := 0
  src : Nat := 0
  /-- Signed 16-bit offset field as a `Nat` bit-pattern (`0..65535`). -/
  offBits : Nat := 0
  /-- Immediate bit-pattern. For `lddw` this is the full 64-bit value; for
  other ops it is the low 32-bit field (`0..2^32-1`). -/
  immBits : Nat := 0
  /-- `true` for the implicit second slot of an `lddw` pair. -/
  isLddwPad : Bool := false
  /-- `true` when the second operand is a register (BPF reg-class opcode).
  Distinguishes e.g. `mov64 r0, r0` from `mov64 r0, 0`. -/
  usesRegSrc : Bool := false
  deriving Repr, Inhabited

/-- Encode error for the binary seam. -/
inductive EncodeError where
  | missingDst (op : String)
  | missingSrc (op : String)
  | missingImm (op : String)
  | missingOff (op : String)
  | unknownLabel (name : String)
  | unknownSymbol (name : String)
  | unknownSyscall (name : String)
  | unsupportedOpcode (op : String)
  | offsetOutOfRange (value : Int)
  | immOutOfRange (value : Int)
  | regOutOfRange (idx : Nat)
  deriving Repr

def EncodeError.render : EncodeError → String
  | .missingDst op => s!"sBPF encode: `{op}` missing destination register"
  | .missingSrc op => s!"sBPF encode: `{op}` missing source register"
  | .missingImm op => s!"sBPF encode: `{op}` missing immediate"
  | .missingOff op => s!"sBPF encode: `{op}` missing offset"
  | .unknownLabel name => s!"sBPF encode: unknown jump label `{name}`"
  | .unknownSymbol name => s!"sBPF encode: unknown symbol `{name}`"
  | .unknownSyscall name => s!"sBPF encode: unknown syscall `{name}`"
  | .unsupportedOpcode op => s!"sBPF encode: unsupported opcode `{op}`"
  | .offsetOutOfRange v => s!"sBPF encode: offset {v} out of i16 range"
  | .immOutOfRange v => s!"sBPF encode: imm {v} out of i32 range"
  | .regOutOfRange idx => s!"sBPF encode: register index {idx} out of range"

def maskBits (n width : Nat) : Nat :=
  n % (2 ^ width)

/-- Encode a signed `Int` as an unsigned `width`-bit two's-complement pattern. -/
def toTwosComplement (value : Int) (width : Nat) : Except EncodeError Nat :=
  let bound : Int := Int.ofNat (2 ^ (width - 1))
  let modulus : Int := Int.ofNat (2 ^ width)
  if value < -bound || value >= bound then
    if width == 16 then .error (.offsetOutOfRange value)
    else .error (.immOutOfRange value)
  else
    let raw := if value < 0 then value + modulus else value
    .ok (Int.toNat raw)

def toUnsignedBits (value : Nat) (width : Nat) : Except EncodeError Nat :=
  if value >= 2 ^ width then
    if width == 16 then .error (.offsetOutOfRange (Int.ofNat value))
    else .error (.immOutOfRange (Int.ofNat value))
  else
    .ok value

def requireRegIdx (r : Reg) : Except EncodeError Nat :=
  let idx := r.idx
  if idx > 10 then .error (.regOutOfRange idx) else .ok idx

/-- Solana syscall ids used by the covered Counter / ValueVault fragment.
Values are the murmur3-32 hashes the Solana runtime binds to each symbol. -/
def syscallId? : String → Option Nat
  | "sol_log_" => some 0x207559bd
  | "sol_log_64_" => some 0x5c2a3178
  | "sol_log_pubkey" => some 0x7ef088ca
  | "sol_log_compute_units_" => some 0x52ba5096
  | "sol_memcpy_" => some 0x717cc4a3
  | "sol_memmove_" => some 0x5fdcde31
  | "sol_memset_" => some 0x3770fb22
  | "sol_memcmp_" => some 0x5f3bcf19
  | "sol_create_program_address" => some 0x937da264
  | "sol_try_find_program_address" => some 0x48504a38
  | "sol_invoke_signed_c" => some 0xa22b9c85
  | "sol_invoke_signed_rust" => some 0xd7449092
  | "sol_set_return_data" => some 0xa226d3eb
  | "sol_get_return_data" => some 0x5d224ccf
  | "sol_get_clock_sysvar" => some 0xb7e96933
  | "sol_get_rent_sysvar" => some 0xbf7188f2
  | "sol_get_epoch_schedule_sysvar" => some 0xc974c918
  | "sol_sha256" => some 0x11f49d86
  | "sol_keccak256" => some 0xd56b5fe9
  | "sol_blake3" => some 0x174c5122
  | "sol_panic_" => some 0x686093bb
  | "abort" => some 0x6cb2c653
  | _ => none

/-- How many bytecode slots an `Inst` occupies (`lddw` = 2, else 1). -/
def slotCount (inst : Inst) : Nat :=
  if inst.opcode == .lddw then 2 else 1

/-- Imm-form opcode byte (v1 class table, matching `Solanalib.SBPF.decode`). -/
def opcodeByteImm : Opcode → Except EncodeError Nat
  | .lddw => .ok 0x18
  | .ldxb => .ok 0x71
  | .ldxh => .ok 0x69
  | .ldxw => .ok 0x61
  | .ldxdw => .ok 0x79
  | .stb => .ok 0x72
  | .sth => .ok 0x6a
  | .stw => .ok 0x62
  | .stdw => .ok 0x7a
  | .stxb => .ok 0x73
  | .stxh => .ok 0x6b
  | .stxw => .ok 0x63
  | .stxdw => .ok 0x7b
  | .add64 => .ok 0x07
  | .sub64 => .ok 0x17
  | .mul64 => .ok 0x27
  | .div64 => .ok 0x37
  | .or64 => .ok 0x47
  | .and64 => .ok 0x57
  | .lsh64 => .ok 0x67
  | .rsh64 => .ok 0x77
  | .neg64 => .ok 0x87
  | .mod64 => .ok 0x97
  | .xor64 => .ok 0xa7
  | .mov64 => .ok 0xb7
  | .arsh64 => .ok 0xc7
  | .add32 => .ok 0x04
  | .sub32 => .ok 0x14
  | .mul32 => .ok 0x24
  | .div32 => .ok 0x34
  | .or32 => .ok 0x44
  | .and32 => .ok 0x54
  | .lsh32 => .ok 0x64
  | .rsh32 => .ok 0x74
  | .neg32 => .ok 0x84
  | .mod32 => .ok 0x94
  | .xor32 => .ok 0xa4
  | .mov32 => .ok 0xb4
  | .arsh32 => .ok 0xc4
  | .le16 | .le32 | .le64 => .ok 0xd4
  | .be16 | .be32 | .be64 => .ok 0xdc
  | .ja => .ok 0x05
  | .jeq => .ok 0x15
  | .jgt => .ok 0x25
  | .jge => .ok 0x35
  | .jset => .ok 0x45
  | .jne => .ok 0x55
  | .jsgt => .ok 0x65
  | .jsge => .ok 0x75
  | .jlt => .ok 0xa5
  | .jle => .ok 0xb5
  | .jslt => .ok 0xc5
  | .jsle => .ok 0xd5
  | .call => .ok 0x85
  | .callx => .ok 0x8d
  | .exit => .ok 0x95

/-- Reg-source form: set the 0x08 bit that distinguishes imm vs reg. -/
def opcodeByteReg (op : Opcode) : Except EncodeError Nat := do
  let imm ← opcodeByteImm op
  .ok (imm ||| 0x08)

def isAlu : Opcode → Bool
  | .add64 | .sub64 | .mul64 | .div64 | .mod64 | .or64 | .and64
  | .lsh64 | .rsh64 | .xor64 | .mov64 | .arsh64
  | .add32 | .sub32 | .mul32 | .div32 | .mod32 | .or32 | .and32
  | .lsh32 | .rsh32 | .xor32 | .mov32 | .arsh32 => true
  | _ => false

def isCondJump : Opcode → Bool
  | .jeq | .jne | .jgt | .jge | .jlt | .jle
  | .jsgt | .jsge | .jslt | .jsle | .jset => true
  | _ => false

def endianImm : Opcode → Nat
  | .le16 | .be16 => 16
  | .le32 | .be32 => 32
  | .le64 | .be64 => 64
  | _ => 0

def pushLe (acc : BpfBinBytes) (n width : Nat) : BpfBinBytes :=
  Id.run do
    let mut a := acc
    let mut x := n
    for _ in [0:width] do
      a := a.push (x % 256)
      x := x / 256
    a

def encodeSlot (opc dst src offBits immBits : Nat) : BpfBinBytes :=
  let regByte := (maskBits src 4) * 16 + maskBits dst 4
  let acc := (#[] : BpfBinBytes).push (maskBits opc 8) |>.push (maskBits regByte 8)
  let acc := pushLe acc (maskBits offBits 16) 2
  pushLe acc (maskBits immBits 32) 4

def encodeLddw (dst imm64 : Nat) : BpfBinBytes :=
  let lo := maskBits imm64 32
  let hi := imm64 / (2 ^ 32)
  encodeSlot 0x18 dst 0 0 lo ++ encodeSlot 0 0 0 0 hi

/-- Map ProofForge instruction index → bytecode slot index (lddw costs 2). -/
def buildSlotIndexMap (instructions : Array Inst) : Array Nat :=
  Id.run do
    let mut slots : Array Nat := #[]
    let mut slot : Nat := 0
    for inst in instructions do
      slots := slots.push slot
      slot := slot + slotCount inst
    slots

/-- Label name → bytecode slot, rebuilt from instruction-index labels. -/
def buildSlotLabels (program : SbpfProgram) (slotOf : Array Nat) : Array (String × Nat) :=
  Id.run do
    let mut out : Array (String × Nat) := #[]
    for binding in program.labels do
      let name := binding.fst
      let pfPc := binding.snd
      let slot := slotOf.getD pfPc 0
      out := out.push (name, slot)
    out

def lookupLabel (labels : Array (String × Nat)) (name : String) : Option Nat :=
  match labels.find? (fun b => b.fst == name) with
  | some b => some b.snd
  | none => none

def resolveImmValue (program : SbpfProgram) : Imm → Except EncodeError Nat
  | .num n => .ok n
  | .sym name =>
      match program.symbol? name with
      | some n => .ok n
      | none => .error (.unknownSymbol name)

def resolveJumpSlot (labels : Array (String × Nat)) : Option MemOff → Except EncodeError Nat
  | some (.sym name) =>
      match lookupLabel labels name with
      | some slot => .ok slot
      | none => .error (.unknownLabel name)
  | some (.num slot) => .ok slot
  | none => .error (.missingOff "jump")

/-- Memory offset bits: negative i16 when `base` is `r10` (stack). -/
def resolveMemOffBits (program : SbpfProgram) (base : Reg) (off : Option MemOff) :
    Except EncodeError Nat := do
  let raw : Nat ← match off with
    | none => pure 0
    | some (.num n) => pure n
    | some (.sym name) =>
        match program.symbol? name with
        | some n => pure n
        | none => .error (.unknownSymbol name)
  if base == .r10 then
    toTwosComplement (-(Int.ofNat raw)) 16
  else
    toUnsignedBits raw 16

/-- Resolve + encode a whole `SbpfProgram`. -/
def resolveProgram (program : SbpfProgram) :
    Except EncodeError (Array ResolvedInst × BpfBinBytes) := do
  let slotOf := buildSlotIndexMap program.instructions
  let slotLabels := buildSlotLabels program slotOf
  let mut resolved : Array ResolvedInst := #[]
  let mut bytes : BpfBinBytes := #[]
  let mut pfPc : Nat := 0
  for inst in program.instructions do
    let pcSlot := slotOf.getD pfPc 0
    let op := inst.opcode
    if op == .lddw then
      let dst ← match inst.dst with
        | some r => requireRegIdx r
        | none => .error (.missingDst "lddw")
      let value ← match inst.imm with
        | some imm => resolveImmValue program imm
        | none => .error (.missingImm "lddw")
      resolved := resolved.push {
        opcode := .lddw, dst, immBits := value
      }
      resolved := resolved.push {
        opcode := .lddw, immBits := value / (2 ^ 32), isLddwPad := true
      }
      bytes := bytes ++ encodeLddw dst value
    else if op == .exit then
      resolved := resolved.push { opcode := .exit }
      bytes := bytes ++ encodeSlot 0x95 0 0 0 0
    else if op == .call then
      let (src, id) ← match inst.imm with
        | some (.sym name) =>
            match lookupLabel slotLabels name with
            | some target =>
                let rel := (Int.ofNat target) - (Int.ofNat (pcSlot + 1))
                pure (1, ← toTwosComplement rel 32)
            | none =>
                match syscallId? name with
                | some id => pure (0, id)
                | none => .error (.unknownSyscall name)
        | some (.num n) => pure (0, n)
        | none => .error (.missingImm "call")
      resolved := resolved.push { opcode := .call, src, immBits := id }
      bytes := bytes ++ encodeSlot 0x85 0 src 0 id
    else if op == .callx then
      let src ← match inst.dst with
        | some r => requireRegIdx r
        | none => .error (.missingDst "callx")
      resolved := resolved.push { opcode := .callx, src }
      bytes := bytes ++ encodeSlot 0x8d 0 src 0 0
    else if op == .ja then
      let target ← resolveJumpSlot slotLabels inst.off
      let rel := (Int.ofNat target) - (Int.ofNat (pcSlot + 1))
      let offBits ← toTwosComplement rel 16
      resolved := resolved.push { opcode := .ja, offBits }
      bytes := bytes ++ encodeSlot 0x05 0 0 offBits 0
    else if isCondJump op then
      let dst ← match inst.dst with
        | some r => requireRegIdx r
        | none => .error (.missingDst op.render)
      let target ← resolveJumpSlot slotLabels inst.off
      let rel := (Int.ofNat target) - (Int.ofNat (pcSlot + 1))
      let offBits ← toTwosComplement rel 16
      match inst.imm with
      | some imm =>
          let immV ← resolveImmValue program imm
          let immBits ← toUnsignedBits (maskBits immV 32) 32
          let opc ← opcodeByteImm op
          resolved := resolved.push {
            opcode := op, dst, offBits, immBits
          }
          bytes := bytes ++ encodeSlot opc dst 0 offBits immBits
      | none =>
          let src ← match inst.src with
            | some r => requireRegIdx r
            | none => .error (.missingSrc op.render)
          let opc ← opcodeByteReg op
          resolved := resolved.push {
            opcode := op, dst, src, offBits, usesRegSrc := true
          }
          bytes := bytes ++ encodeSlot opc dst src offBits 0
    else if op.isLoad then
      let dst ← match inst.dst with
        | some r => requireRegIdx r
        | none => .error (.missingDst op.render)
      let srcReg ← match inst.src with
        | some r => pure r
        | none => .error (.missingSrc op.render)
      let src ← requireRegIdx srcReg
      let offBits ← resolveMemOffBits program srcReg inst.off
      let opc ← opcodeByteImm op
      resolved := resolved.push { opcode := op, dst, src, offBits }
      bytes := bytes ++ encodeSlot opc dst src offBits 0
    else if op.isStore then
      let dstReg ← match inst.dst with
        | some r => pure r
        | none => .error (.missingDst op.render)
      let dst ← requireRegIdx dstReg
      let offBits ← resolveMemOffBits program dstReg inst.off
      let immV ← match inst.imm with
        | some imm => resolveImmValue program imm
        | none => .error (.missingImm op.render)
      let immBits ← toUnsignedBits (maskBits immV 32) 32
      let opc ← opcodeByteImm op
      resolved := resolved.push { opcode := op, dst, offBits, immBits }
      bytes := bytes ++ encodeSlot opc dst 0 offBits immBits
    else if op.isStoreReg then
      let dstReg ← match inst.dst with
        | some r => pure r
        | none => .error (.missingDst op.render)
      let dst ← requireRegIdx dstReg
      let src ← match inst.src with
        | some r => requireRegIdx r
        | none => .error (.missingSrc op.render)
      let offBits ← resolveMemOffBits program dstReg inst.off
      let opc ← opcodeByteImm op
      resolved := resolved.push { opcode := op, dst, src, offBits }
      bytes := bytes ++ encodeSlot opc dst src offBits 0
    else if op.isEndian then
      let dst ← match inst.dst with
        | some r => requireRegIdx r
        | none => .error (.missingDst op.render)
      let immBits := endianImm op
      let opc ← opcodeByteImm op
      resolved := resolved.push { opcode := op, dst, immBits }
      bytes := bytes ++ encodeSlot opc dst 0 0 immBits
    else if op == .neg64 || op == .neg32 then
      let dst ← match inst.dst with
        | some r => requireRegIdx r
        | none => .error (.missingDst op.render)
      let opc ← opcodeByteImm op
      resolved := resolved.push { opcode := op, dst }
      bytes := bytes ++ encodeSlot opc dst 0 0 0
    else if isAlu op then
      let dst ← match inst.dst with
        | some r => requireRegIdx r
        | none => .error (.missingDst op.render)
      match inst.imm with
      | some imm =>
          let immV ← resolveImmValue program imm
          let immBits ← toUnsignedBits (maskBits immV 32) 32
          let opc ← opcodeByteImm op
          resolved := resolved.push { opcode := op, dst, immBits }
          bytes := bytes ++ encodeSlot opc dst 0 0 immBits
      | none =>
          let src ← match inst.src with
            | some r => requireRegIdx r
            | none => .error (.missingSrc op.render)
          let opc ← opcodeByteReg op
          resolved := resolved.push { opcode := op, dst, src, usesRegSrc := true }
          bytes := bytes ++ encodeSlot opc dst src 0 0
    else
      throw (.unsupportedOpcode op.render)
    pfPc := pfPc + 1
  pure (resolved, bytes)

/-- Encode a structured AST program to bytecode. -/
def toBpfBin (nodes : Array AstNode) : Except EncodeError BpfBinBytes := do
  let (_, bytes) ← resolveProgram (collectProgram nodes)
  .ok bytes

/-- Encode and also return the resolved instruction list (for verify/adapter). -/
def toBpfBinWithResolved (nodes : Array AstNode) :
    Except EncodeError (Array ResolvedInst × BpfBinBytes) :=
  resolveProgram (collectProgram nodes)

/-- Lower an IR module and encode the resulting sBPF AST to bytecode. -/
def lowerModuleToBpfBin (module : Module) : Except String BpfBinBytes :=
  match ProofForge.Backend.Solana.SbpfAsm.lowerModule module with
  | .error e => .error e.render
  | .ok nodes =>
      match toBpfBin nodes with
      | .error e => .error e.render
      | .ok bytes => .ok bytes

/-- Structural sanity: every byte is in `0..255` and the length is a multiple
of 8 (instruction slots). -/
def bpfBinWellFormed (bytes : BpfBinBytes) : Bool :=
  bytes.size % 8 == 0 &&
    bytes.all (fun b => b < 256)

/-- Smoke predicate used by default-path tests (no solanalib). -/
def moduleEncodesOk (module : Module) : Bool :=
  match lowerModuleToBpfBin module with
  | .error _ => false
  | .ok bytes => bpfBinWellFormed bytes && bytes.size > 0

/-- Unit-level encode of a single resolved non-lddw instruction (tests). -/
def encodeResolved (ri : ResolvedInst) : Except EncodeError BpfBinBytes := do
  if ri.isLddwPad then
    .ok (encodeSlot 0 0 0 0 ri.immBits)
  else if ri.opcode == .lddw then
    .ok (encodeLddw ri.dst ri.immBits)
  else if ri.opcode == .exit then
    .ok (encodeSlot 0x95 0 0 0 0)
  else if (isAlu ri.opcode || isCondJump ri.opcode) && ri.usesRegSrc then
    let opc ← opcodeByteReg ri.opcode
    .ok (encodeSlot opc ri.dst ri.src ri.offBits ri.immBits)
  else
    let opc ← opcodeByteImm ri.opcode
    .ok (encodeSlot opc ri.dst ri.src ri.offBits ri.immBits)

end ProofForge.Backend.Solana.BpfEncode
