import ProofForge.Backend.Refinement.Core
import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.Solana.Syscalls

namespace ProofForge.Backend.Solana.SbpfInterpreter

open ProofForge.IR
open ProofForge.Backend.Refinement
open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.Manifest
open ProofForge.Backend.Solana.SbpfAsm
open ProofForge.Backend.Solana.StateLayout
open ProofForge.Backend.Solana.Syscalls

abbrev Memory := Array (Nat × Nat)

def Memory.read (memory : Memory) (addr : Nat) : Nat :=
  match memory.find? (fun entry => entry.fst == addr) with
  | some entry => entry.snd
  | none => 0

def Memory.read? (memory : Memory) (addr : Nat) : Option Nat :=
  memory.find? (fun entry => entry.fst == addr) |>.map fun entry => entry.snd

def Memory.write (memory : Memory) (addr value : Nat) : Memory :=
  (memory.filter (fun entry => entry.fst != addr)).push (addr, value)

theorem Memory.find?_write (memory : Memory) (addr value : Nat) :
    ((memory.filter (fun entry => entry.fst != addr)).push (addr, value)).find?
        (fun entry => entry.fst == addr) = some (addr, value) := by
  simp

theorem Memory.read_write (memory : Memory) (addr value : Nat) :
    (memory.write addr value).read addr = value := by
  unfold Memory.read Memory.write
  simp [Memory.find?_write memory addr value]

def registerCount : Nat := 11
def stackBase : Nat := 1000000
def inputBase : Nat := 0
def defaultFuel : Nat := 2000

def emptyRegs : Array Nat := Array.replicate registerCount 0

def regGet (regs : Array Nat) (reg : Reg) : Nat :=
  regs.getD reg.idx 0

def regSet (regs : Array Nat) (reg : Reg) (value : Nat) : Array Nat :=
  regs.set! reg.idx value

structure SbpfProgram where
  instructions : Array Inst
  labels : Array (String × Nat)
  symbols : Array (String × Nat)
  deriving Repr, Inhabited

structure SbpfState where
  regs : Array Nat := emptyRegs
  stack : Array Nat := #[]
  memory : Memory := #[]
  entryR0 : Nat := 0
  returnData : Option Nat := none
  pc : Nat := 0
  halted : Bool := false
  deriving Repr, Inhabited

def lookupNat? (name : String) (bindings : Array (String × Nat)) : Option Nat :=
  match bindings.find? (fun binding => binding.fst == name) with
  | some binding => some binding.snd
  | none => none

def SbpfProgram.label? (program : SbpfProgram) (name : String) : Option Nat :=
  lookupNat? name program.labels

def SbpfProgram.symbol? (program : SbpfProgram) (name : String) : Option Nat :=
  lookupNat? name program.symbols

def collectProgram (nodes : Array AstNode) : SbpfProgram := Id.run do
  let mut instructions := #[]
  let mut labels := #[]
  let mut symbols := #[]
  for node in nodes do
    match node with
    | .label name =>
        labels := labels.push (name, instructions.size)
    | .instruction inst =>
        instructions := instructions.push inst
    | .equDecl name value =>
        symbols := symbols.push (name, value)
    | _ =>
        pure ()
  return { instructions, labels, symbols }

def resolveImm (program : SbpfProgram) : Imm → Except String Nat
  | .num value => .ok value
  | .sym name =>
      match program.symbol? name with
      | some value => .ok value
      | none => .error s!"unknown sBPF symbol `{name}`"

def resolveOff (program : SbpfProgram) : MemOff → Except String Nat
  | .num value => .ok value
  | .sym name =>
      match program.symbol? name with
      | some value => .ok value
      | none =>
          match program.label? name with
          | some value => .ok value
          | none => .error s!"unknown sBPF label/symbol `{name}`"

def resolveJumpTarget (program : SbpfProgram) (off : Option MemOff) : Except String Nat := do
  match off with
  | some (.sym name) =>
      match program.label? name with
      | some pc => .ok pc
      | none => .error s!"unknown sBPF jump label `{name}`"
  | some (.num pc) => .ok pc
  | none => .error "sBPF jump missing target"

def dstReg (inst : Inst) : Except String Reg :=
  match inst.dst with
  | some reg => .ok reg
  | none => .error s!"sBPF `{inst.opcode.render}` missing destination register"

def srcReg (inst : Inst) : Except String Reg :=
  match inst.src with
  | some reg => .ok reg
  | none => .error s!"sBPF `{inst.opcode.render}` missing source register"

def operandValue (program : SbpfProgram) (state : SbpfState) (inst : Inst) :
    Except String Nat :=
  match inst.imm with
  | some imm => resolveImm program imm
  | none =>
      match inst.src with
      | some reg => .ok (regGet state.regs reg)
      | none => .error s!"sBPF `{inst.opcode.render}` missing operand"

def memOffset (program : SbpfProgram) (inst : Inst) : Except String Nat :=
  match inst.off with
  | some off => resolveOff program off
  | none => .ok 0

def memoryAddress (state : SbpfState) (base : Reg) (off : Nat) : Nat :=
  let baseValue := regGet state.regs base
  if base == .r10 then baseValue - off else baseValue + off

def setReg (state : SbpfState) (reg : Reg) (value : Nat) : SbpfState :=
  { state with regs := regSet state.regs reg value }

def nextPc (state : SbpfState) : SbpfState :=
  { state with pc := state.pc + 1 }

def alu64 (opcode : Opcode) (lhs rhs : Nat) : Except String Nat :=
  match opcode with
  | .add64 => .ok (lhs + rhs)
  | .sub64 => .ok (lhs - rhs)
  | .mul64 => .ok (lhs * rhs)
  | .div64 =>
      if rhs == 0 then .error "sBPF div64 by zero" else .ok (lhs / rhs)
  | .mod64 =>
      if rhs == 0 then .error "sBPF mod64 by zero" else .ok (lhs % rhs)
  | .or64 => .ok (Nat.lor lhs rhs)
  | .and64 => .ok (Nat.land lhs rhs)
  | .lsh64 => .ok (Nat.shiftLeft lhs rhs)
  | .rsh64 => .ok (Nat.shiftRight lhs rhs)
  | .xor64 => .ok (Nat.xor lhs rhs)
  | _ => .error s!"unsupported sBPF ALU opcode `{opcode.render}`"

def jumpCondition (opcode : Opcode) (lhs rhs : Nat) : Except String Bool :=
  match opcode with
  | .jeq => .ok (lhs == rhs)
  | .jne => .ok ((lhs == rhs) == false)
  | .jgt => .ok (lhs > rhs)
  | .jge => .ok (lhs >= rhs)
  | .jlt => .ok (lhs < rhs)
  | .jle => .ok (lhs <= rhs)
  | .jset => .ok (Nat.land lhs rhs != 0)
  | _ => .error s!"unsupported sBPF conditional jump `{opcode.render}`"

theorem jumpCondition_jeq_true {lhs : Nat} :
    jumpCondition .jeq lhs lhs = .ok true := by
  unfold jumpCondition
  simp [Nat.beq_refl]

theorem jumpCondition_jeq_false {lhs rhs : Nat} (h : lhs ≠ rhs) :
    jumpCondition .jeq lhs rhs = .ok false := by
  unfold jumpCondition
  simp [beq_false_of_ne h]

theorem jumpCondition_jne_true {lhs rhs : Nat} (h : lhs ≠ rhs) :
    jumpCondition .jne lhs rhs = .ok true := by
  unfold jumpCondition
  simp [beq_false_of_ne h]

theorem jumpCondition_jne_false {lhs : Nat} :
    jumpCondition .jne lhs lhs = .ok false := by
  unfold jumpCondition
  simp [Nat.beq_refl]

theorem jumpCondition_jeq_reg_eq
    {state : SbpfState} {dst : Reg} {lhs rhs : Nat}
    (hlhs : regGet state.regs dst = lhs) (h : lhs = rhs) :
    jumpCondition .jeq (regGet state.regs dst) rhs = .ok true := by
  rw [hlhs, h, jumpCondition_jeq_true]

theorem jumpCondition_jeq_reg_ne
    {state : SbpfState} {dst : Reg} {lhs rhs : Nat}
    (hlhs : regGet state.regs dst = lhs) (h : lhs ≠ rhs) :
    jumpCondition .jeq (regGet state.regs dst) rhs = .ok false := by
  rw [hlhs, jumpCondition_jeq_false h]

theorem jumpCondition_jne_reg_ne
    {state : SbpfState} {dst : Reg} {lhs rhs : Nat}
    (hlhs : regGet state.regs dst = lhs) (h : lhs ≠ rhs) :
    jumpCondition .jne (regGet state.regs dst) rhs = .ok true := by
  rw [hlhs, jumpCondition_jne_true h]

theorem jumpCondition_jne_reg_eq
    {state : SbpfState} {dst : Reg} {lhs rhs : Nat}
    (hlhs : regGet state.regs dst = lhs) (h : lhs = rhs) :
    jumpCondition .jne (regGet state.regs dst) rhs = .ok false := by
  rw [hlhs, h, jumpCondition_jne_false]

theorem jumpCondition_jeq_regs_eq
    {state : SbpfState} {dst src : Reg} {lhs rhs : Nat}
    (hlhs : regGet state.regs dst = lhs) (hrhs : regGet state.regs src = rhs) (h : lhs = rhs) :
    jumpCondition .jeq (regGet state.regs dst) (regGet state.regs src) = .ok true := by
  rw [hlhs, hrhs, h, jumpCondition_jeq_true]

theorem jumpCondition_jeq_regs_ne
    {state : SbpfState} {dst src : Reg} {lhs rhs : Nat}
    (hlhs : regGet state.regs dst = lhs) (hrhs : regGet state.regs src = rhs) (h : lhs ≠ rhs) :
    jumpCondition .jeq (regGet state.regs dst) (regGet state.regs src) = .ok false := by
  rw [hlhs, hrhs, jumpCondition_jeq_false h]

theorem jumpCondition_jne_regs_ne
    {state : SbpfState} {dst src : Reg} {lhs rhs : Nat}
    (hlhs : regGet state.regs dst = lhs) (hrhs : regGet state.regs src = rhs) (h : lhs ≠ rhs) :
    jumpCondition .jne (regGet state.regs dst) (regGet state.regs src) = .ok true := by
  rw [hlhs, hrhs, jumpCondition_jne_true h]

theorem jumpCondition_jne_regs_eq
    {state : SbpfState} {dst src : Reg} {lhs rhs : Nat}
    (hlhs : regGet state.regs dst = lhs) (hrhs : regGet state.regs src = rhs) (h : lhs = rhs) :
    jumpCondition .jne (regGet state.regs dst) (regGet state.regs src) = .ok false := by
  rw [hlhs, hrhs, h, jumpCondition_jne_false]

def execMov64 (state : SbpfState) (dst : Reg) (value : Nat) : SbpfState :=
  nextPc (setReg state dst value)

def execAlu64 (state : SbpfState) (dst : Reg) (opcode : Opcode) (lhs rhs : Nat) :
    Except String SbpfState :=
  match alu64 opcode lhs rhs with
  | .error msg => .error msg
  | .ok value => .ok (nextPc (setReg state dst value))

def execLddw (state : SbpfState) (dst : Reg) (value : Nat) : SbpfState :=
  nextPc (setReg state dst value)

def execLoad (state : SbpfState) (dst : Reg) (addr value : Nat) : SbpfState :=
  nextPc (setReg state dst value)

def execStore (state : SbpfState) (addr value : Nat) : SbpfState :=
  nextPc { state with memory := state.memory.write addr value }

def execJump (state : SbpfState) (target : Nat) : SbpfState :=
  { state with pc := target }

def execExit (state : SbpfState) (r0 : Nat) : SbpfState :=
  { state with entryR0 := r0, halted := true, pc := state.pc + 1 }

def execSetReturnData (state : SbpfState) (value : Nat) : SbpfState :=
  nextPc (setReg { state with returnData := some value } .r0 0)

def execGetClockSysvar (state : SbpfState) (ptr : Nat) : SbpfState :=
  nextPc (setReg { state with memory := state.memory.write ptr 0 } .r0 0)

def execLog64 (state : SbpfState) : SbpfState :=
  nextPc (setReg state .r0 0)

def readLoad (program : SbpfProgram) (state : SbpfState) (inst : Inst) :
    Except String SbpfState :=
  match dstReg inst with
  | .error msg => .error msg
  | .ok dst =>
      match srcReg inst with
      | .error msg => .error msg
      | .ok base =>
          match memOffset program inst with
          | .error msg => .error msg
          | .ok off =>
              let addr := memoryAddress state base off
              .ok (execLoad state dst addr (state.memory.read addr))

def writeStoreReg (program : SbpfProgram) (state : SbpfState) (inst : Inst) :
    Except String SbpfState :=
  match dstReg inst with
  | .error msg => .error msg
  | .ok base =>
      match srcReg inst with
      | .error msg => .error msg
      | .ok src =>
          match memOffset program inst with
          | .error msg => .error msg
          | .ok off =>
              let addr := memoryAddress state base off
              .ok (execStore state addr (regGet state.regs src))

def writeStoreImm (program : SbpfProgram) (state : SbpfState) (inst : Inst) :
    Except String SbpfState := do
  let base ← dstReg inst
  let off ← memOffset program inst
  let value ←
    match inst.imm with
    | some imm => resolveImm program imm
    | none => .error s!"sBPF `{inst.opcode.render}` missing store immediate"
  let addr := memoryAddress state base off
  .ok (nextPc { state with memory := state.memory.write addr value })

def runSyscall (state : SbpfState) (name : String) : Except String SbpfState :=
  if name == sol_set_return_data then
    let ptr := regGet state.regs .r1
    let value := state.memory.read ptr
    let state := setReg { state with returnData := some value } .r0 0
    .ok (nextPc state)
  else if name == sol_get_clock_sysvar then
    let ptr := regGet state.regs .r1
    let state := setReg { state with memory := state.memory.write ptr 0 } .r0 0
    .ok (nextPc state)
  else if name == sol_log_64_ then
    .ok (nextPc (setReg state .r0 0))
  else
    .error s!"unsupported sBPF syscall `{name}`"

def stepInstExit (state : SbpfState) : Except String SbpfState :=
  .ok (execExit state (regGet state.regs .r0))

def stepInstCall (state : SbpfState) (inst : Inst) : Except String SbpfState :=
  match inst.imm with
  | some (.sym name) =>
      if name == sol_set_return_data then
        let ptr := regGet state.regs .r1
        .ok (execSetReturnData state (state.memory.read ptr))
      else if name == sol_get_clock_sysvar then
        .ok (execGetClockSysvar state (regGet state.regs .r1))
      else if name == sol_log_64_ then
        .ok (execLog64 state)
      else
        .error s!"unsupported sBPF syscall `{name}`"
  | _ => .error "sBPF call missing syscall symbol"

def stepInstLddw (program : SbpfProgram) (state : SbpfState) (inst : Inst) :
    Except String SbpfState :=
  match inst.imm with
  | none => .error "sBPF lddw missing immediate"
  | some imm =>
      match dstReg inst with
      | .error msg => .error msg
      | .ok dst =>
          match resolveImm program imm with
          | .error msg => .error msg
          | .ok value => .ok (execLddw state dst value)

def stepInstJa (program : SbpfProgram) (state : SbpfState) (inst : Inst) :
    Except String SbpfState :=
  match resolveJumpTarget program inst.off with
  | .error msg => .error msg
  | .ok target => .ok (execJump state target)

def stepInstCondJumpCore (program : SbpfProgram) (state : SbpfState) (inst : Inst)
    (cond : Bool) : Except String SbpfState :=
  if cond then
    match resolveJumpTarget program inst.off with
    | .error msg => .error msg
    | .ok target => .ok (execJump state target)
  else
    .ok (nextPc state)

theorem stepInstCondJumpCore_taken
    (program : SbpfProgram) (state : SbpfState) (inst : Inst) (target : Nat)
    (htarget : resolveJumpTarget program inst.off = .ok target) :
    stepInstCondJumpCore program state inst true = .ok (execJump state target) := by
  simp [stepInstCondJumpCore, htarget, ↓reduceIte]

theorem stepInstCondJumpCore_fallthrough
    (program : SbpfProgram) (state : SbpfState) (inst : Inst) :
    stepInstCondJumpCore program state inst false = .ok (nextPc state) := by
  simp [stepInstCondJumpCore, ↓reduceIte]

theorem inst_opcode (opcode : Opcode) (dst src : Option Reg) (off : Option MemOff) (imm : Option Imm) :
    (inst opcode dst src off imm).opcode = opcode := rfl

theorem inst_off (opcode : Opcode) (dst src : Option Reg) (off : Option MemOff) (imm : Option Imm) :
    (inst opcode dst src off imm).off = off := rfl

theorem dstReg_inst_some (opcode : Opcode) (dst : Reg) (src : Option Reg)
    (off : Option MemOff) (imm : Option Imm) :
    dstReg (inst opcode (some dst) src off imm) = .ok dst := by
  simp [dstReg, inst]

theorem operandValue_inst_imm (program : SbpfProgram) (state : SbpfState) (opcode : Opcode)
    (dst src : Option Reg) (off : Option MemOff) (imm : Imm) :
    operandValue program state (inst opcode dst src off (some imm)) = resolveImm program imm := by
  simp [operandValue, inst]

theorem operandValue_inst_reg (program : SbpfProgram) (state : SbpfState) (opcode : Opcode)
    (dst : Option Reg) (src : Reg) (off : Option MemOff) :
    operandValue program state (inst opcode dst (some src) off none) = .ok (regGet state.regs src) := by
  simp [operandValue, inst, regGet]

def stepInstCondJump (program : SbpfProgram) (state : SbpfState) (inst : Inst) :
    Except String SbpfState :=
  match dstReg inst with
  | .error msg => .error msg
  | .ok dst =>
      match operandValue program state inst with
      | .error msg => .error msg
      | .ok rhs =>
          match jumpCondition inst.opcode (regGet state.regs dst) rhs with
          | .error msg => .error msg
          | .ok cond => stepInstCondJumpCore program state inst cond

theorem stepInstCondJump_jeq_imm_taken
    (program : SbpfProgram) (state : SbpfState) (dst : Reg) (lhs rhs target : Nat)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs = rhs) :
    stepInstCondJump program state
      (inst .jeq (some dst) none (some (.num target)) (some (.num rhs))) =
      .ok (execJump state target) := by
  subst hcond
  simp only [stepInstCondJump, dstReg_inst_some, operandValue_inst_imm, resolveImm, inst_opcode]
  rw [jumpCondition_jeq_reg_eq hlhs (Eq.refl lhs)]
  simp [resolveJumpTarget, inst_off, stepInstCondJumpCore, ↓reduceIte]

theorem stepInstCondJump_jeq_imm_fallthrough
    (program : SbpfProgram) (state : SbpfState) (dst : Reg) (lhs rhs target : Nat)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs ≠ rhs) :
    stepInstCondJump program state
      (inst .jeq (some dst) none (some (.num target)) (some (.num rhs))) =
      .ok (nextPc state) := by
  simp only [stepInstCondJump, dstReg_inst_some, operandValue_inst_imm, resolveImm, inst_opcode]
  rw [jumpCondition_jeq_reg_ne hlhs hcond]
  simp [stepInstCondJumpCore, ↓reduceIte]

theorem stepInstCondJump_jeq_reg_taken
    (program : SbpfProgram) (state : SbpfState) (dst src : Reg) (lhs rhs target : Nat)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs = rhs) :
    stepInstCondJump program state
      (inst .jeq (some dst) (some src) (some (.num target)) none) =
      .ok (execJump state target) := by
  subst hcond
  simp only [stepInstCondJump, dstReg_inst_some, operandValue_inst_reg, inst_opcode]
  rw [jumpCondition_jeq_regs_eq hlhs hrhs (Eq.refl lhs)]
  simp [resolveJumpTarget, inst_off, stepInstCondJumpCore, ↓reduceIte]

theorem stepInstCondJump_jeq_reg_fallthrough
    (program : SbpfProgram) (state : SbpfState) (dst src : Reg) (lhs rhs target : Nat)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs ≠ rhs) :
    stepInstCondJump program state
      (inst .jeq (some dst) (some src) (some (.num target)) none) =
      .ok (nextPc state) := by
  simp only [stepInstCondJump, dstReg_inst_some, operandValue_inst_reg, inst_opcode]
  rw [jumpCondition_jeq_regs_ne hlhs hrhs hcond]
  simp [stepInstCondJumpCore, ↓reduceIte]

theorem stepInstCondJump_jne_imm_taken
    (program : SbpfProgram) (state : SbpfState) (dst : Reg) (lhs rhs target : Nat)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs ≠ rhs) :
    stepInstCondJump program state
      (inst .jne (some dst) none (some (.num target)) (some (.num rhs))) =
      .ok (execJump state target) := by
  simp only [stepInstCondJump, dstReg_inst_some, operandValue_inst_imm, resolveImm, inst_opcode]
  rw [jumpCondition_jne_reg_ne hlhs hcond]
  simp [resolveJumpTarget, inst_off, stepInstCondJumpCore, ↓reduceIte]

theorem stepInstCondJump_jne_imm_fallthrough
    (program : SbpfProgram) (state : SbpfState) (dst : Reg) (lhs rhs target : Nat)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs = rhs) :
    stepInstCondJump program state
      (inst .jne (some dst) none (some (.num target)) (some (.num rhs))) =
      .ok (nextPc state) := by
  subst hcond
  simp only [stepInstCondJump, dstReg_inst_some, operandValue_inst_imm, resolveImm, inst_opcode]
  rw [jumpCondition_jne_reg_eq hlhs (Eq.refl lhs)]
  simp [stepInstCondJumpCore, ↓reduceIte]

theorem stepInstCondJump_jne_reg_taken
    (program : SbpfProgram) (state : SbpfState) (dst src : Reg) (lhs rhs target : Nat)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs ≠ rhs) :
    stepInstCondJump program state
      (inst .jne (some dst) (some src) (some (.num target)) none) =
      .ok (execJump state target) := by
  simp only [stepInstCondJump, dstReg_inst_some, operandValue_inst_reg, inst_opcode]
  rw [jumpCondition_jne_regs_ne hlhs hrhs hcond]
  simp [resolveJumpTarget, inst_off, stepInstCondJumpCore, ↓reduceIte]

theorem stepInstCondJump_jne_reg_fallthrough
    (program : SbpfProgram) (state : SbpfState) (dst src : Reg) (lhs rhs target : Nat)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs = rhs) :
    stepInstCondJump program state
      (inst .jne (some dst) (some src) (some (.num target)) none) =
      .ok (nextPc state) := by
  subst hcond
  simp only [stepInstCondJump, dstReg_inst_some, operandValue_inst_reg, inst_opcode]
  rw [jumpCondition_jne_regs_eq hlhs hrhs (Eq.refl lhs)]
  simp [stepInstCondJumpCore, ↓reduceIte]

def stepInstMov (program : SbpfProgram) (state : SbpfState) (inst : Inst) :
    Except String SbpfState :=
  match dstReg inst with
  | .error msg => .error msg
  | .ok dst =>
      match operandValue program state inst with
      | .error msg => .error msg
      | .ok value => .ok (execMov64 state dst value)

def stepInstAlu64 (program : SbpfProgram) (state : SbpfState) (inst : Inst) :
    Except String SbpfState :=
  match dstReg inst with
  | .error msg => .error msg
  | .ok dst =>
      let lhs := regGet state.regs dst
      match operandValue program state inst with
      | .error msg => .error msg
      | .ok rhs => execAlu64 state dst inst.opcode lhs rhs

/-- Execute one decoded instruction. Exposed for contract-agnostic step lemmas in
`SbpfExec.lean`. -/
def stepInst (program : SbpfProgram) (state : SbpfState) (inst : Inst) :
    Except String SbpfState :=
  match inst.opcode with
  | .exit => stepInstExit state
  | .call => stepInstCall state inst
  | .lddw => stepInstLddw program state inst
  | .ldxb | .ldxh | .ldxw | .ldxdw => readLoad program state inst
  | .stb | .sth | .stw | .stdw => writeStoreImm program state inst
  | .stxb | .stxh | .stxw | .stxdw => writeStoreReg program state inst
  | .ja => stepInstJa program state inst
  | .jeq | .jne | .jgt | .jge | .jlt | .jle | .jset =>
      stepInstCondJump program state inst
  | .mov64 | .mov32 => stepInstMov program state inst
  | .add64 | .sub64 | .mul64 | .div64 | .mod64 | .or64 | .and64
  | .lsh64 | .rsh64 | .xor64 => stepInstAlu64 program state inst
  | opcode => .error s!"unsupported sBPF opcode `{opcode.render}`"

def step (program : SbpfProgram) (state : SbpfState) : Except String SbpfState := do
  if state.halted then
    .ok state
  else
    match program.instructions[state.pc]? with
    | none => .error s!"sBPF pc {state.pc} out of bounds"
    | some inst => stepInst program state inst

def run (program : SbpfProgram) : Nat → SbpfState → Except String SbpfState
  | 0, state =>
      if state.halted then .ok state else .error "sBPF interpreter fuel exhausted"
  | fuel + 1, state => do
      if state.halted then
        .ok state
      else
        let next ← step program state
        run program fuel next

theorem halted_false_of_not {state : SbpfState} (h : ¬ state.halted) : state.halted = false := by
  cases hhalt : state.halted <;> simp_all

theorem run_succ {program : SbpfProgram} {state next final : SbpfState} {fuel : Nat}
    (hhalted : state.halted = false)
    (hstep : step program state = .ok next)
    (hrun : run program fuel next = .ok final) :
    run program (fuel + 1) state = .ok final := by
  simp only [run, hhalted, hstep]
  exact hrun

def entrypointIndex? (module : Module) (entrypointName : String) : Option Nat := Id.run do
  let mut idx := 0
  for entrypoint in module.entrypoints do
    if entrypoint.name == entrypointName then
      return some idx
    idx := idx + 1
  return none

def discriminatorBytes (module : Module) (entrypoint : Entrypoint) :
    Except String (Array Nat) :=
  match externalDiscriminatorBytes? entrypoint with
  | some bytes => .ok bytes
  | none =>
      match entrypointIndex? module entrypoint.name with
      | some idx => .ok #[idx]
      | none => .error s!"entrypoint `{entrypoint.name}` not found in module `{module.name}`"

def scalarArgNat (type : ValueType) (value : ProofForge.IR.Semantics.Value) :
    Except String Nat :=
  match type, value with
  | .u64, .u64 value => .ok value
  | .u32, .u32 value => .ok value
  | .bool, .bool value => .ok (if value then 1 else 0)
  | _, _ => .error s!"sBPF trace arg does not match parameter type `{type.name}`"

def writeCallArgs (memory : Memory) (instructionDataOff : Nat) (call : TraceCall) :
    Except String Memory := do
  let mut memory := memory
  let mut payloadOff := entrypointDiscriminatorSize call.entrypoint
  for param in call.entrypoint.params, idx in [0:call.entrypoint.params.size] do
    let (_, type) := param
    let value ←
      match call.args[idx]? with
      | some value => .ok value
      | none => .error s!"missing sBPF trace arg {idx} for `{call.entrypoint.name}`"
    let scalar ← scalarArgNat type value
    memory := memory.write (instructionDataOff + payloadOff) scalar
    payloadOff := payloadOff + (instructionParamByteSize? type).getD 0
  .ok memory

def writeZeroPubkey (memory : Memory) (ptr : Nat) : Memory :=
  memory
    |>.write ptr 0
    |>.write (ptr + 8) 0
    |>.write (ptr + 16) 0
    |>.write (ptr + 24) 0

def initialMemory (module : Module) (baseMemory : Memory) (call : TraceCall) :
    Except String Memory := do
  let schema := buildModuleInputSchema module {}
  let accountLayout ←
    match schema.inputLayout.accounts[0]? with
    | some layout => .ok layout
    | none => .error "sBPF interpreter requires at least one Solana account layout"
  let dataSize := moduleDataSize module
  let discriminator ← discriminatorBytes module call.entrypoint
  let memory := baseMemory
    |>.write 0 schema.inputLayout.accounts.size
    |>.write accountLayout.dataLenOff dataSize
    |>.write accountLayout.writableOff 1
    |>.write schema.inputLayout.instructionDataLenOff (instructionDataMinLen call.entrypoint)
  let mut memory := memory
  for byte in discriminator, idx in [0:discriminator.size] do
    memory := memory.write (schema.inputLayout.instructionDataOff + idx) byte
  let memoryWithArgs ← writeCallArgs memory schema.inputLayout.instructionDataOff call
  let programIdPtr :=
    schema.inputLayout.instructionDataOff + instructionDataMinLen call.entrypoint
  .ok (writeZeroPubkey memoryWithArgs programIdPtr)

def initialState (program : SbpfProgram) (module : Module) (baseMemory : Memory)
    (call : TraceCall) : Except String SbpfState := do
  let pc ←
    match program.label? "entrypoint" with
    | some pc => .ok pc
    | none => .error "sBPF program missing `entrypoint` label"
  let memory ← initialMemory module baseMemory call
  let regs := regSet (regSet emptyRegs .r1 inputBase) .r10 stackBase
  .ok { regs, memory, pc }

def observeEntrypoint (entrypoint : Entrypoint) (state : SbpfState) :
    Except String ObservableReturn :=
  match entrypoint.returns with
  | .unit => .ok .none
  | .u64 =>
      match state.returnData with
      | some value => .ok (.u64 value)
      | none => .error s!"sBPF entrypoint `{entrypoint.name}` produced no return data"
  | other =>
      .error s!"sBPF executable trace only models Unit/U64 returns, got `{other.name}`"

def runEntrypointState (program : SbpfProgram) (module : Module) (memory : Memory)
    (call : TraceCall) : Except String (Memory × ObservableStep × SbpfState) := do
  let initial ← initialState program module memory call
  let final ← run program defaultFuel initial
  if final.entryR0 == 0 then
    let returnValue ← observeEntrypoint call.entrypoint final
    .ok (final.memory, {
      entrypointName := call.entrypoint.name
      returnValue
    }, final)
  else
    .error s!"sBPF entrypoint `{call.entrypoint.name}` exited with r0={final.entryR0}"

def runEntrypoint (program : SbpfProgram) (module : Module) (memory : Memory)
    (call : TraceCall) : Except String (Memory × ObservableStep) := do
  let (memory, step, _) ← runEntrypointState program module memory call
  .ok (memory, step)

def runTraceList (program : SbpfProgram) (module : Module) :
    List TraceCall → Memory → Except String (Memory × Array ObservableStep)
  | [], memory => .ok (memory, #[])
  | call :: rest, memory => do
      let (memory, step) ← runEntrypoint program module memory call
      let (memory, steps) ← runTraceList program module rest memory
      .ok (memory, #[step] ++ steps)

def runTrace (nodes : Array AstNode) (obligation : TraceObligation) :
    Except String (Array ObservableStep) := do
  let program := collectProgram nodes
  let (_, steps) ← runTraceList program obligation.module obligation.calls.toList #[]
  .ok steps

def executableTraceOk (obligation : TraceObligation) : Bool :=
  match lowerModule obligation.module with
  | .error _ => false
  | .ok nodes =>
      match runTrace nodes obligation with
      | .ok actual => actual == obligation.expected
      | .error _ => false

/-! ### Counter-slice simulation relation

`R` is the first pointwise bridge between the IR state and the concrete sBPF
machine state: for a scalar `u64` field, the IR binding must equal the word at
the account-data offset computed by `StateLayout`.
-/

def stateFieldOffset? (module : Module) (stateId : String) : Option Nat :=
  let schema := buildModuleInputSchema module {}
  match schema.inputLayout.accounts[0]? with
  | none => none
  | some accountLayout =>
      let fields := buildStateOffsetsAtBase module accountLayout.dataStart
      fields.find? (fun field => field.id == stateId) |>.map fun field => field.absOff

def irU64State? (state : ProofForge.IR.Semantics.State) (stateId : String) : Option Nat :=
  match ProofForge.IR.Semantics.State.read state stateId with
  | some (.u64 value) => some value
  | _ => none

def R (module : Module) (stateId : String)
    (irState : ProofForge.IR.Semantics.State) (sbpfState : SbpfState) : Bool :=
  match irU64State? irState stateId, stateFieldOffset? module stateId with
  | some expected, some offset => sbpfState.memory.read offset == expected
  | _, _ => false

/-- Optional scalar-storage relation for trace-start states.

The strict `R` relation above is useful after a scalar has been written. For a
whole Counter trace, the initial IR state and target account data are both
missing the `count` cell before `initialize`; this optional relation treats
missing/missing as related and then compares concrete U64 words after writes. -/
def RMemoryOptional (module : Module) (stateId : String)
    (irState : ProofForge.IR.Semantics.State) (memory : Memory) : Bool :=
  match stateFieldOffset? module stateId with
  | some offset => memory.read? offset == irU64State? irState stateId
  | none => false

def ROptional (module : Module) (stateId : String)
    (irState : ProofForge.IR.Semantics.State) (sbpfState : SbpfState) : Bool :=
  RMemoryOptional module stateId irState sbpfState.memory

def runIrEntrypointState (state : ProofForge.IR.Semantics.State)
    (entrypoint : Entrypoint) : Except String ProofForge.IR.Semantics.State :=
  match ProofForge.IR.Semantics.runEntrypointWithArgsResult state entrypoint #[] with
  | .ok (nextState, _) => .ok nextState
  | .reverted message => .error s!"IR entrypoint `{entrypoint.name}` reverted: {message}"
  | .error message => .error message

def counterRAfterInitialize : Bool :=
  match lowerModule ProofForge.IR.Examples.Counter.module with
  | .error _ => false
  | .ok nodes =>
      let program := collectProgram nodes
      let initCall : TraceCall := {
        entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint
      }
      match runIrEntrypointState ProofForge.IR.Semantics.State.empty
          ProofForge.IR.Examples.Counter.initializeEntrypoint with
      | .error _ => false
      | .ok irState =>
          match runEntrypointState program ProofForge.IR.Examples.Counter.module #[] initCall with
          | .ok (_, _, sbpfState) =>
              R ProofForge.IR.Examples.Counter.module "count" irState sbpfState
          | .error _ => false

def counterRAfterIncrement : Bool :=
  match lowerModule ProofForge.IR.Examples.Counter.module with
  | .error _ => false
  | .ok nodes =>
      let program := collectProgram nodes
      let initCall : TraceCall := {
        entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint
      }
      let incrementCall : TraceCall := {
        entrypoint := ProofForge.IR.Examples.Counter.increment
      }
      match runIrEntrypointState ProofForge.IR.Semantics.State.empty
          ProofForge.IR.Examples.Counter.initializeEntrypoint with
      | .error _ => false
      | .ok irAfterInit =>
          match runIrEntrypointState irAfterInit ProofForge.IR.Examples.Counter.increment with
          | .error _ => false
          | .ok irAfterIncrement =>
              match runEntrypointState program ProofForge.IR.Examples.Counter.module #[] initCall with
              | .error _ => false
              | .ok (memory, _, _) =>
                  match runEntrypointState program ProofForge.IR.Examples.Counter.module memory incrementCall with
                  | .ok (_, _, sbpfState) =>
                      R ProofForge.IR.Examples.Counter.module "count" irAfterIncrement sbpfState
                  | .error _ => false

theorem counter_R_after_initialize_ok :
    counterRAfterInitialize = true := by
  native_decide

theorem counter_R_after_increment_ok :
    counterRAfterIncrement = true := by
  native_decide

def counterInterpreterSmoke : Bool :=
  match lowerModule ProofForge.IR.Examples.Counter.module with
  | .error _ => false
  | .ok nodes =>
      let program := collectProgram nodes
      let calls := traceCallsFromEntrypoints #[
        ProofForge.IR.Examples.Counter.initializeEntrypoint,
        ProofForge.IR.Examples.Counter.get,
        ProofForge.IR.Examples.Counter.increment,
        ProofForge.IR.Examples.Counter.get
      ]
      match runTraceList program ProofForge.IR.Examples.Counter.module calls.toList #[] with
      | .ok _ => true
      | .error _ => false

theorem counter_interpreter_smoke_ok :
    counterInterpreterSmoke = true := by
  native_decide

end ProofForge.Backend.Solana.SbpfInterpreter
