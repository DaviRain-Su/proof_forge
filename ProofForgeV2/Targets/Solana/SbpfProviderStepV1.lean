import SbpfSemantics.Api

/-!
# Solana SbpfProviderStepV1

Small proof helpers for certificates over the pinned `SbpfSemantics` provider.
They only expose projections and reductions of the provider's existing
`Machine`, `execInstr`, `Step`, `Steps`, and `runFuel` definitions. No target
instruction semantics or ProofForge business transition is defined here.
-/

namespace ProofForgeV2.Targets.Solana.ProviderStepV1

open SbpfSemantics

@[simp] theorem entry_halted (input rodata : Array UInt8) (maxDepth : Nat) :
    (Machine.entry input rodata maxDepth).halted = none := by rfl

@[simp] theorem entry_pc (input rodata : Array UInt8) (maxDepth : Nat) :
    (Machine.entry input rodata maxDepth).pc = 0 := by rfl

@[simp] theorem entry_mem (input rodata : Array UInt8) (maxDepth : Nat) :
    (Machine.entry input rodata maxDepth).mem =
      Memory.initial input rodata maxDepth := by
  rfl

@[simp] theorem entry_frames (input rodata : Array UInt8) (maxDepth : Nat) :
    (Machine.entry input rodata maxDepth).frames = [] := by rfl

@[simp] theorem entry_maxDepth (input rodata : Array UInt8)
    (maxDepth : Nat) :
    (Machine.entry input rodata maxDepth).maxDepth = maxDepth := by rfl

@[simp] theorem entry_returnData (input rodata : Array UInt8)
    (maxDepth : Nat) :
    (Machine.entry input rodata maxDepth).returnData = #[] := by rfl

@[simp] theorem entry_getReg_one (input rodata : Array UInt8)
    (maxDepth : Nat) :
    (Machine.entry input rodata maxDepth).getReg 1 = inputStart := by
  rfl

@[simp] theorem entry_getReg_ten (input rodata : Array UInt8)
    (maxDepth : Nat) :
    (Machine.entry input rodata maxDepth).getReg 10 =
      (Memory.initial input rodata maxDepth).initialFp := by
  rfl

@[simp] theorem advancePc_halted (m : Machine) :
    m.advancePc.halted = m.halted := by rfl

@[simp] theorem advancePc_pc (m : Machine) :
    m.advancePc.pc = m.pc + 1 := by rfl

@[simp] theorem advancePc_mem (m : Machine) :
    m.advancePc.mem = m.mem := by rfl

@[simp] theorem advancePc_getReg (m : Machine) (r : Reg) :
    m.advancePc.getReg r = m.getReg r := by rfl

@[simp] theorem advancePc_frames (m : Machine) :
    m.advancePc.frames = m.frames := by rfl

@[simp] theorem advancePc_maxDepth (m : Machine) :
    m.advancePc.maxDepth = m.maxDepth := by rfl

@[simp] theorem advancePc_returnData (m : Machine) :
    m.advancePc.returnData = m.returnData := by rfl

@[simp] theorem setPc_halted (m : Machine) (pc : Nat) :
    (m.setPc pc).halted = m.halted := by rfl

@[simp] theorem setPc_pc (m : Machine) (pc : Nat) :
    (m.setPc pc).pc = pc := by rfl

@[simp] theorem setPc_mem (m : Machine) (pc : Nat) :
    (m.setPc pc).mem = m.mem := by rfl

@[simp] theorem setPc_getReg (m : Machine) (pc : Nat) (r : Reg) :
    (m.setPc pc).getReg r = m.getReg r := by rfl

@[simp] theorem setPc_frames (m : Machine) (pc : Nat) :
    (m.setPc pc).frames = m.frames := by rfl

@[simp] theorem setPc_maxDepth (m : Machine) (pc : Nat) :
    (m.setPc pc).maxDepth = m.maxDepth := by rfl

@[simp] theorem setPc_returnData (m : Machine) (pc : Nat) :
    (m.setPc pc).returnData = m.returnData := by rfl

@[simp] theorem put64_halted (m : Machine) (r : Reg) (v : Word) :
    (put64 m r v).halted = m.halted := by rfl

@[simp] theorem put64_pc (m : Machine) (r : Reg) (v : Word) :
    (put64 m r v).pc = m.pc + 1 := by rfl

@[simp] theorem put64_mem (m : Machine) (r : Reg) (v : Word) :
    (put64 m r v).mem = m.mem := by rfl

@[simp] theorem put64_frames (m : Machine) (r : Reg) (v : Word) :
    (put64 m r v).frames = m.frames := by rfl

@[simp] theorem put64_maxDepth (m : Machine) (r : Reg) (v : Word) :
    (put64 m r v).maxDepth = m.maxDepth := by rfl

@[simp] theorem put64_returnData (m : Machine) (r : Reg) (v : Word) :
    (put64 m r v).returnData = m.returnData := by rfl

@[simp] theorem put64_getReg_same (m : Machine) (r : Reg) (v : Word) :
    (put64 m r v).getReg r = v := by
  simp [put64, Machine.setReg, Machine.advancePc, Machine.getReg]

@[simp] theorem put64_getReg_ne (m : Machine) (r s : Reg) (v : Word)
    (h : s ≠ r) :
    (put64 m r v).getReg s = m.getReg s := by
  have hv : s.val ≠ r.val := fun heq => h (Fin.ext heq)
  simp [put64, Machine.setReg, Machine.advancePc, Machine.getReg,
    Ne.symm hv]

@[simp] theorem execInstrMov64Reg (D : ExecDialect) (m : Machine)
    (dst src : Reg) (hhalt : m.halted = none) :
    execInstr D m (.binReg .Mov64Reg dst src) =
      some (put64 m dst (m.getReg src)) := by
  simp [execInstr, Instr.binReg, Opcode.opClass, execBin64Reg, hhalt,
    put64]
  rfl

@[simp] theorem execInstrLddw (D : ExecDialect) (m : Machine)
    (dst : Reg) (imm : Word) (hhalt : m.halted = none) :
    execInstr D m (.lddw dst imm) = some (put64 m dst imm) := by
  simp [execInstr, Instr.lddw, Opcode.opClass, hhalt, put64]
  rfl

@[simp] theorem execInstrLdxdw (D : ExecDialect) (m : Machine)
    (dst src : Reg) (off : Off16) (value : Word)
    (hhalt : m.halted = none)
    (hread : m.mem.readU64 (calcAddr (m.getReg src) off) = some value) :
    execInstr D m (.loadMem .Ldxdw dst src off) =
      some (put64 m dst value) := by
  simp [execInstr, Instr.loadMem, Opcode.opClass, hhalt, put64]
  change (m.mem.readU64 (calcAddr (m.getReg src) off)).bind
    (fun v => some (put64 m dst v)) = some (put64 m dst value)
  rw [hread]
  rfl

@[simp] theorem execInstrLdxb (D : ExecDialect) (m : Machine)
    (dst src : Reg) (off : Off16) (value : Word)
    (hhalt : m.halted = none)
    (hread : m.mem.readU8 (calcAddr (m.getReg src) off) = some value) :
    execInstr D m (.loadMem .Ldxb dst src off) =
      some (put64 m dst value) := by
  simp [execInstr, Instr.loadMem, Opcode.opClass, hhalt, put64]
  change (m.mem.readU8 (calcAddr (m.getReg src) off)).bind
    (fun v => some (put64 m dst v)) = some (put64 m dst value)
  rw [hread]
  rfl

@[simp] theorem execInstrJneImm (D : ExecDialect) (m : Machine)
    (dst : Reg) (imm : Word) (off : Off16)
    (hhalt : m.halted = none) :
    execInstr D m (.jumpImm .JneImm dst imm off) =
      some (condJump m (m.getReg dst != imm) off) := by
  simp [execInstr, Instr.jumpImm, Opcode.opClass, execJumpImm, hhalt]
  rfl

@[simp] theorem execInstrJltImm (D : ExecDialect) (m : Machine)
    (dst : Reg) (imm : Word) (off : Off16)
    (hhalt : m.halted = none) :
    execInstr D m (.jumpImm .JltImm dst imm off) =
      some (condJump m (m.getReg dst < imm) off) := by
  simp [execInstr, Instr.jumpImm, Opcode.opClass, execJumpImm, hhalt]
  rfl

@[simp] theorem execInstrJneReg (D : ExecDialect) (m : Machine)
    (dst src : Reg) (off : Off16) (hhalt : m.halted = none) :
    execInstr D m (.jumpReg .JneReg dst src off) =
      some (condJump m (m.getReg dst != m.getReg src) off) := by
  simp [execInstr, Instr.jumpReg, Opcode.opClass, execJumpReg, hhalt]
  rfl

@[simp] theorem execInstrJa (D : ExecDialect) (m : Machine)
    (off : Off16) (hhalt : m.halted = none) :
    execInstr D m (.ja off) = some (doJump m off) := by
  simp [execInstr, Instr.ja, Opcode.opClass, hhalt]
  rfl

@[simp] theorem execInstrCallRel (D : ExecDialect) (m : Machine)
    (off : Word) (hhalt : m.halted = none) :
    execInstr D m (.callRel off) = execCallRel m off := by
  simp [execInstr, Instr.callRel, Opcode.opClass, hhalt]

@[simp] theorem execInstrExit (D : ExecDialect) (m : Machine)
    (hhalt : m.halted = none) :
    execInstr D m .exit = execExit m := by
  simp [execInstr, Instr.exit, Opcode.opClass, hhalt]

@[simp] theorem execInstrAdd64Imm (D : ExecDialect) (m : Machine)
    (dst : Reg) (imm : Word) (hhalt : m.halted = none) :
    execInstr D m (.binImm .Add64Imm dst imm) =
      some (put64 m dst (m.getReg dst + imm)) := by
  simp [execInstr, Instr.binImm, Opcode.opClass, execBin64Imm, hhalt]
  rfl

@[simp] theorem execInstrAdd64Reg (D : ExecDialect) (m : Machine)
    (dst src : Reg) (hhalt : m.halted = none) :
    execInstr D m (.binReg .Add64Reg dst src) =
      some (put64 m dst (m.getReg dst + m.getReg src)) := by
  simp [execInstr, Instr.binReg, Opcode.opClass, execBin64Reg, hhalt]
  rfl

/-- Reduce a provider step to its fetched instruction and instruction
execution. -/
theorem step_of_fetch_exec {D : ExecDialect} {P : Program} {m m' : Machine}
    {i : Instr}
    (hhalt : m.halted = none)
    (hfetch : P[m.pc]? = some i)
    (hexec : execInstr D m i = some m') :
    Step D P m m' := by
  simp [Step, execStep, fetch, hhalt, hfetch, hexec]

/-- A provider step can only start from a non-halted machine. -/
theorem halted_eq_none_of_step {D : ExecDialect} {P : Program}
    {m m' : Machine} (hstep : Step D P m m') :
    m.halted = none := by
  unfold Step execStep fetch at hstep
  cases hhalt : m.halted with
  | none => rfl
  | some code => simp [hhalt] at hstep

/-- Exact successful steps consume exactly their count of fuel when the final
state is halted. -/
theorem runFuel_eq_halted_of_steps
    {D : ExecDialect} {P : Program} {n : Nat} {m m' : Machine}
    {code : Word}
    (hsteps : Steps D P n m m')
    (hhalt : m'.halted = some code) :
    runFuel D P n m = (m', .halted code) := by
  induction hsteps with
  | zero m => simp [runFuel, hhalt]
  | @succ n m m1 m2 hstep hrest ih =>
      have hm : m.halted = none := halted_eq_none_of_step hstep
      unfold Step at hstep
      simp [runFuel, hm, hstep, ih hhalt]

end ProofForgeV2.Targets.Solana.ProviderStepV1
