/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Assembly AST and Printer

Structured representation of blueshift-gg/sbpf assembly, plus a text printer.
This is the assembly construction layer: other modules build `AstNode` arrays
and this file turns them into `.s` text.

See `docs/targets/solana-sbpf-asm.md` (D-026).
-/

namespace ProofForge.Backend.Solana.Asm

-- ============================================================================
-- Registers
-- ============================================================================

inductive Reg where
  | r0 | r1 | r2 | r3 | r4 | r5 | r6 | r7 | r8 | r9 | r10
  deriving BEq, DecidableEq, Repr, Inhabited

def Reg.idx : Reg → Nat
  | .r0 => 0  | .r1 => 1  | .r2 => 2  | .r3 => 3  | .r4 => 4
  | .r5 => 5  | .r6 => 6  | .r7 => 7  | .r8 => 8  | .r9 => 9
  | .r10 => 10

def Reg.render (r : Reg) : String := s!"r{r.idx}"

-- ============================================================================
-- Immediates / offsets
-- ============================================================================

inductive Imm where
  | num (n : Nat)
  | sym (name : String)
  deriving BEq, Repr, Inhabited

inductive MemOff where
  | num (n : Nat)
  | sym (name : String)
  deriving BEq, Repr, Inhabited

-- ============================================================================
-- Opcodes
-- ============================================================================

inductive Opcode where
  -- 64-bit ALU
  | lddw | ldxb | ldxh | ldxw | ldxdw
  | stb  | sth  | stw  | stdw
  | stxb | stxh | stxw | stxdw
  | add64 | sub64 | mul64 | div64 | mod64 | or64 | and64
  | lsh64 | rsh64 | xor64 | mov64 | arsh64 | neg64
  -- 32-bit ALU
  | add32 | sub32 | mul32 | div32 | mod32 | or32 | and32
  | lsh32 | rsh32 | xor32 | mov32 | arsh32 | neg32
  -- endianness
  | le16 | le32 | le64 | be16 | be32 | be64
  -- control flow
  | ja | jeq | jne | jgt | jge | jlt | jle
  | jsgt | jsge | jslt | jsle | jset
  | call | callx | exit
  deriving BEq, Repr, Inhabited

def Opcode.render : Opcode → String
  | .lddw => "lddw"     | .ldxb => "ldxb"     | .ldxh => "ldxh"     | .ldxw => "ldxw"     | .ldxdw => "ldxdw"
  | .stb  => "stb"      | .sth  => "sth"      | .stw  => "stw"      | .stdw => "stdw"
  | .stxb => "stxb"     | .stxh => "stxh"     | .stxw => "stxw"     | .stxdw => "stxdw"
  | .add64 => "add64"   | .sub64 => "sub64"   | .mul64 => "mul64"   | .div64 => "div64"
  | .mod64 => "mod64"   | .or64  => "or64"    | .and64 => "and64"   | .lsh64 => "lsh64"
  | .rsh64 => "rsh64"   | .xor64 => "xor64"   | .mov64 => "mov64"   | .arsh64 => "arsh64" | .neg64 => "neg64"
  | .add32 => "add32"   | .sub32 => "sub32"   | .mul32 => "mul32"   | .div32 => "div32"
  | .mod32 => "mod32"   | .or32  => "or32"    | .and32 => "and32"   | .lsh32 => "lsh32"
  | .rsh32 => "rsh32"   | .xor32 => "xor32"   | .mov32 => "mov32"   | .arsh32 => "arsh32" | .neg32 => "neg32"
  | .le16 => "le16"     | .le32 => "le32"     | .le64 => "le64"
  | .be16 => "be16"     | .be32 => "be32"     | .be64 => "be64"
  | .ja   => "ja"       | .jeq  => "jeq"      | .jne  => "jne"      | .jgt  => "jgt"
  | .jge  => "jge"      | .jlt  => "jlt"      | .jle  => "jle"      | .jsgt => "jsgt"
  | .jsge => "jsge"     | .jslt => "jslt"     | .jsle => "jsle"     | .jset => "jset"
  | .call => "call"     | .callx => "callx"   | .exit => "exit"

def Opcode.isCondJump : Opcode → Bool
  | .jeq | .jne | .jgt | .jge | .jlt | .jle
  | .jsgt | .jsge | .jslt | .jsle | .jset => true
  | _ => false

/-- ALU opcodes whose second operand may be a register. -/
def Opcode.isRegOp : Opcode → Bool
  | .add64 | .sub64 | .mul64 | .div64 | .mod64 | .or64 | .and64
  | .lsh64 | .rsh64 | .xor64 | .arsh64
  | .add32 | .sub32 | .mul32 | .div32 | .mod32 | .or32 | .and32
  | .lsh32 | .rsh32 | .xor32 | .arsh32 => true
  | _ => false

/-- Load opcodes (register-relative). -/
def Opcode.isLoad : Opcode → Bool
  | .ldxb | .ldxh | .ldxw | .ldxdw => true
  | _ => false

/-- Store-with-immediate opcodes. -/
def Opcode.isStore : Opcode → Bool
  | .stb | .sth | .stw | .stdw => true
  | _ => false

/-- Store-from-register opcodes. -/
def Opcode.isStoreReg : Opcode → Bool
  | .stxb | .stxh | .stxw | .stxdw => true
  | _ => false

/-- Endian-conversion opcodes. -/
def Opcode.isEndian : Opcode → Bool
  | .le16 | .le32 | .le64 | .be16 | .be32 | .be64 => true
  | _ => false

-- ============================================================================
-- Instructions
-- ============================================================================

structure Inst where
  opcode : Opcode
  dst  : Option Reg := none
  src  : Option Reg := none
  off  : Option MemOff := none
  imm  : Option Imm := none
  deriving Repr, Inhabited

/-- Convenience constructor for `Inst`. -/
def inst (opcode : Opcode) (dst : Option Reg := none) (src : Option Reg := none)
         (off : Option MemOff := none) (imm : Option Imm := none) : Inst :=
  { opcode, dst, src, off, imm }

-- ============================================================================
-- AST nodes
-- ============================================================================

/-- A data initializer for `.rodata`/`.data` sections. -/
inductive DataInit where
  | byte  (n : Nat)
  | short (n : Nat)
  | word  (n : Nat)
  | long  (n : Nat)
  | quad  (n : Nat)
  | ascii (s : String)
  deriving Repr, Inhabited

inductive Section where
  | text | data | rodata
  deriving BEq, Repr, Inhabited

def Section.render : Section → String
  | .text => ".text"
  | .data => ".data"
  | .rodata => ".rodata"

inductive AstNode where
  | sectionDecl (sec : Section)
  | globalDecl  (label : String)
  | equDecl     (name : String) (value : Nat)
  | label      (name : String)
  | instruction (inst : Inst)
  | data        (label : String) (inits : Array DataInit)
  | comment    (text : String)
  | blankLine
  deriving Repr, Inhabited

-- ============================================================================
-- Rendering
-- ============================================================================

/-- Decimal for small values; hex when the high bit would make a signed decimal
parser reject the token (sbpf parses some immediates as signed i64). Values
`≥ 2^63` must use `0x…` so AccessControl-style hash4 limb0 constants assemble. -/
def numStr (n : Nat) : String :=
  let signedMax : Nat := 9223372036854775807 -- 2^63 - 1
  if n ≤ signedMax then
    toString n
  else
    "0x" ++ String.ofList (Nat.toDigits 16 n)

def Imm.render : Imm → String
  | .num n => numStr n
  | .sym s => s

def MemOff.render : MemOff → String
  | .num n => numStr n
  | .sym s => s

def DataInit.render : DataInit → String
  | .byte n  => s!".byte {numStr n}"
  | .short n => s!".short {numStr n}"
  | .word n  => s!".word {numStr n}"
  | .long n  => s!".long {numStr n}"
  | .quad n  => s!".quad {numStr n}"
  | .ascii s => s!".ascii \"{s}\""

/-- Stack-relative accesses use negative offsets; all other bases use positive. -/
def memSign (base : Reg) : String := if base == .r10 then "-" else "+"

def Inst.render (i : Inst) : String :=
  let op := i.opcode.render
  let dstStr (r : Reg) : String := r.render
  let body :=
    if i.opcode == .exit then ""
    else if i.opcode == .call then
      match i.imm with | some (.sym n) => s!" {n}" | _ => ""
    else if i.opcode == .callx then
      match i.dst with | some r => s!" {dstStr r}" | none => ""
    else if i.opcode == .ja then
      match i.off with | some o => s!" {o.render}" | none => ""
    else if i.opcode == .lddw then
      s!" {dstStr (i.dst.getD .r0)}, {i.imm.getD (.num 0) |>.render}"
    else if i.opcode.isLoad then
      let base := dstStr (i.src.getD .r1)
      let off := i.off.getD (.num 0) |>.render
      s!" {dstStr (i.dst.getD .r0)}, [{base}{memSign (i.src.getD .r1)}{off}]"
    else if i.opcode.isStore then
      let base := dstStr (i.dst.getD .r1)
      let off := i.off.getD (.num 0) |>.render
      let val := i.imm.getD (.num 0) |>.render
      s!" [{base}{memSign (i.dst.getD .r1)}{off}], {val}"
    else if i.opcode.isStoreReg then
      let base := dstStr (i.dst.getD .r1)
      let off := i.off.getD (.num 0) |>.render
      let val := dstStr (i.src.getD .r0)
      s!" [{base}{memSign (i.dst.getD .r1)}{off}], {val}"
    else if i.opcode.isCondJump then
      let arg2 : String := match i.imm with | some imm => imm.render | none => dstStr (i.src.getD .r0)
      let target : String := match i.off with | some o => o.render | none => "?"
      s!" {dstStr (i.dst.getD .r0)}, {arg2}, {target}"
    else if i.opcode.isRegOp then
      let arg2 : String := match i.imm with | some imm => imm.render | none => dstStr (i.src.getD .r0)
      s!" {dstStr (i.dst.getD .r0)}, {arg2}"
    else if i.opcode.isEndian then
      s!" {dstStr (i.dst.getD .r0)}"
    else
      let arg : String := match i.imm with | some imm => imm.render | none => dstStr (i.src.getD .r0)
      s!" {dstStr (i.dst.getD .r0)}, {arg}"
  s!"  {op}{body}"

def AstNode.render (node : AstNode) : Array String :=
  match node with
  | .sectionDecl sec  => #[ sec.render ]
  | .globalDecl lbl   => #[ s!".globl {lbl}" ]
  | .equDecl name val => #[ s!".equ {name}, {numStr val}" ]
  | .label name       => #[ s!"{name}:" ]
  | .instruction i    => #[ i.render ]
  | .data lbl inits   =>
      if inits.isEmpty then #[ s!"{lbl}:" ]
      else #[ s!"{lbl}: " ++ String.intercalate ", " (inits.map DataInit.render).toList ]
  | .comment text     => #[ "  ; " ++ text ]
  | .blankLine        => #[""]

/-- Render a list of AST nodes to assembly text. -/
def renderNodes (nodes : Array AstNode) : String :=
  let lines := nodes.foldl (init := #[]) fun acc node => acc ++ node.render
  String.intercalate "\n" lines.toList ++ "\n"

end ProofForge.Backend.Solana.Asm
