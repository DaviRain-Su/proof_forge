import ProofForge.Backend.Solana.SbpfInterpreter

/-!
Contract-agnostic symbolic execution helpers for the in-Lean sBPF interpreter.

This module factors the repeated `stepInst`/`run` branches into reusable
per-instruction lemmas over the pure `exec*` transition helpers in
`SbpfInterpreter.lean`. Contract refinements should compose these lemmas instead
of hand-deriving interpreter execution one instruction at a time.

Active Solana C-proof development surface: extend here (branches, ALU, syscalls).
Contract-specific files such as `CounterSbpfExec` / `CounterSbpfRefinement` are
regression smokes only — checked by `just solana-counter-sbpf-regression`, not
expanded in generic-layer PRs.
-/

namespace ProofForge.Backend.Solana.SbpfExec

open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.Syscalls
open ProofForge.Backend.Solana.SbpfInterpreter

set_option linter.unusedSimpArgs false

abbrev State := SbpfState
abbrev Program := SbpfProgram

def runSteps := run

def currentInst? (program : Program) (state : State) : Option Inst :=
  program.instructions[state.pc]?

structure StepReady (program : Program) (state : State) : Prop where
  running : ¬ state.halted
  decoded : ∃ inst, currentInst? program state = some inst

theorem runSteps_zero (program : Program) (state : State) :
    runSteps program 0 state =
      if state.halted then .ok state else .error "sBPF interpreter fuel exhausted" := by
  rfl

theorem runSteps_succ
    {program : Program} {state next final : State} {fuel : Nat}
    (hrunning : ¬ state.halted)
    (hstep : step program state = .ok next)
    (hrun : runSteps program fuel next = .ok final) :
    runSteps program (fuel + 1) state = .ok final := by
  unfold runSteps
  exact run_succ (halted_false_of_not hrunning) hstep hrun

theorem runSteps_of_halted (program : Program) (state : State) (fuel : Nat)
    (hhalted : state.halted) :
    runSteps program fuel state = .ok state := by
  induction fuel with
  | zero =>
      unfold runSteps run
      simp [hhalted]
  | succ fuel ih =>
      unfold runSteps run
      simp [hhalted]

inductive StepPath (program : Program) : State → Nat → State → Prop where
  | nil (state : State) (hhalted : state.halted) : StepPath program state 0 state
  | cons {state mid final : State} {fuel : Nat}
      (hready : StepReady program state)
      (hstep : step program state = .ok mid)
      (tail : StepPath program mid fuel final) :
      StepPath program state (fuel + 1) final

theorem runSteps_of_stepPath_done {program : Program} {fuel : Nat}
    {state final : State} (path : StepPath program state fuel final) :
    runSteps program fuel state = .ok final := by
  induction path with
  | nil state hhalted =>
      unfold runSteps run
      simp [hhalted]
  | cons hready hstep tail ih =>
      rcases hready with ⟨hrunning, _⟩
      unfold runSteps
      exact run_succ (halted_false_of_not hrunning) hstep ih

/-! ### PC-anchored readiness (PowdrExec `ReadyOpcodeAt` analogue) -/

def ProgramPcAt (_program : Program) (pc : Nat) (state : State) : Prop :=
  state.pc = pc

structure DecodedInstAt (program : Program) (pc : Nat) (inst : Inst) (state : State) : Prop where
  pcAt : ProgramPcAt program pc state
  decodedAt : program.instructions[pc]? = some inst

theorem DecodedInstAt.currentInst?
    {program : Program} {pc : Nat} {inst : Inst} {state : State}
    (hat : DecodedInstAt program pc inst state) :
    currentInst? program state = some inst := by
  rcases hat with ⟨hpc, hdec⟩
  subst hpc
  exact hdec

/-- Instruction at `program`/`pc` is decoded and the machine is running. -/
structure ReadyOpcodeAt (program : Program) (pc : Nat) (inst : Inst) (state : State) : Prop where
  decoded : DecodedInstAt program pc inst state
  running : ¬ state.halted

theorem ReadyOpcodeAt.currentInst?
    {program : Program} {pc : Nat} {inst : Inst} {state : State}
    (hat : ReadyOpcodeAt program pc inst state) :
    currentInst? program state = some inst :=
  hat.decoded.currentInst?

theorem ReadyOpcodeAt.stepReady
    {program : Program} {pc : Nat} {inst : Inst} {state : State}
    (hat : ReadyOpcodeAt program pc inst state) :
    StepReady program state :=
  ⟨hat.running, ⟨inst, hat.currentInst?⟩⟩

/-! ### Reduction chains (PowdrExec `StepFEReductionChain` analogue) -/

structure StepReduction (program : Program) (state nextState : State) : Prop where
  running : ¬ state.halted
  hstep : SbpfInterpreter.step program state = .ok nextState

theorem StepReduction.of_step
    {program : Program} {state nextState : State}
    (hrunning : ¬ state.halted)
    (hstep : SbpfInterpreter.step program state = .ok nextState) :
    StepReduction program state nextState :=
  { running := hrunning
    hstep := hstep }

theorem StepReduction.of_readyOpcodeAt
    {program : Program} {pc : Nat} {inst : Inst} {state nextState : State}
    (hat : ReadyOpcodeAt program pc inst state)
    (hstep : SbpfInterpreter.step program state = .ok nextState) :
    StepReduction program state nextState :=
  StepReduction.of_step hat.running hstep

inductive StepReductionChain (program : Program) : State → Nat → State → Prop where
  | nil (state : State) : StepReductionChain program state 0 state
  | cons {state nextState finalState : State} {fuel : Nat}
      (head : StepReduction program state nextState)
      (tail : StepReductionChain program nextState fuel finalState) :
      StepReductionChain program state (fuel + 1) finalState

theorem StepReductionChain.single
    {program : Program} {state nextState : State}
    (reduction : StepReduction program state nextState) :
    StepReductionChain program state 1 nextState := by
  simpa using
    StepReductionChain.cons reduction
      (StepReductionChain.nil nextState)

theorem StepReductionChain.append
    {program : Program} {state midState finalState : State}
    {prefixFuel suffixFuel : Nat}
    (leftChain : StepReductionChain program state prefixFuel midState)
    (suffix : StepReductionChain program midState suffixFuel finalState) :
    StepReductionChain program state (prefixFuel + suffixFuel) finalState := by
  induction leftChain with
  | nil =>
      simpa using suffix
  | cons head tail ih =>
      have htail := ih suffix
      simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
        StepReductionChain.cons head htail

theorem runSteps_of_reductionChain
    {program : Program} {fuel : Nat} {state finalState : State}
    (chain : StepReductionChain program state fuel finalState)
    (hhalted : finalState.halted) :
    runSteps program fuel state = .ok finalState := by
  suffices ∀ {s f n},
      StepReductionChain program s n f → f.halted → runSteps program n s = .ok f
    from this chain hhalted
  intro s f n chain hhalt
  induction chain with
  | nil s =>
      unfold runSteps run
      simp [hhalt]
  | cons head tail ih =>
    unfold runSteps
    exact run_succ (halted_false_of_not head.running) head.hstep (ih hhalt)

structure ExecutionSegment (program : Program)
    (fuel : Nat) (post : State → State → Prop)
    (state finalState : State) : Prop where
  chain : StepReductionChain program state fuel finalState
  postcondition : post state finalState

theorem runSteps_of_executionSegment
    {program : Program} {fuel : Nat} {post : State → State → Prop}
    {state finalState : State}
    (segment : ExecutionSegment program fuel post state finalState)
    (hhalted : finalState.halted) :
    runSteps program fuel state = .ok finalState :=
  runSteps_of_reductionChain segment.chain hhalted

theorem executionSegment_of_reductionChain
    {program : Program} {fuel : Nat} {post : State → State → Prop}
    {state finalState : State}
    (chain : StepReductionChain program state fuel finalState)
    (hpost : post state finalState) :
    ExecutionSegment program fuel post state finalState :=
  { chain := chain
    postcondition := hpost }

theorem executionSegment_single
    {program : Program} {post : State → State → Prop} {state nextState : State}
    (reduction : StepReduction program state nextState)
    (hpost : post state nextState) :
    ExecutionSegment program 1 post state nextState :=
  executionSegment_of_reductionChain (StepReductionChain.single reduction) hpost

theorem executionSegment_append
    {program : Program} {prefixFuel suffixFuel : Nat}
    {prefixPost suffixPost combinedPost : State → State → Prop}
    {state midState finalState : State}
    (combine :
      prefixPost state midState → suffixPost midState finalState →
        combinedPost state finalState)
    (leftSegment : ExecutionSegment program prefixFuel prefixPost state midState)
    (rightSegment :
      ExecutionSegment program suffixFuel suffixPost midState finalState) :
    ExecutionSegment program (prefixFuel + suffixFuel) combinedPost state finalState :=
  { chain :=
      StepReductionChain.append leftSegment.chain rightSegment.chain
    postcondition :=
      combine leftSegment.postcondition rightSegment.postcondition }

structure ReductionChainProvider (program : Program)
    (pre : State → Prop) (fuel : Nat)
    (post : State → State → Prop) : Prop where
  chain :
    ∀ {state}, pre state →
      ∃ finalState,
        StepReductionChain program state fuel finalState ∧
          post state finalState

theorem reductionChainProvider_single
    {program : Program} {pre : State → Prop} {post : State → State → Prop}
    (nextState : ∀ state, pre state → State)
    (reduction :
      ∀ {state} (hpre : pre state),
        StepReduction program state (nextState state hpre))
    (postcondition :
      ∀ {state} (hpre : pre state),
        post state (nextState state hpre)) :
    ReductionChainProvider program pre 1 post where
  chain := by
    intro state hpre
    exact ⟨nextState state hpre,
      StepReductionChain.single (reduction hpre),
      postcondition hpre⟩

theorem reductionChainProvider_single_of_exists
    {program : Program} {pre : State → Prop} {post : State → State → Prop}
    (step :
      ∀ {state}, pre state →
        ∃ nextState,
          StepReduction program state nextState ∧
            post state nextState) :
    ReductionChainProvider program pre 1 post where
  chain := by
    intro state hpre
    obtain ⟨nextState, reduction, hpost⟩ := step hpre
    exact ⟨nextState, StepReductionChain.single reduction, hpost⟩

theorem reductionChainProvider_append
    {program : Program}
    {leftPre rightPre : State → Prop}
    {leftFuel rightFuel : Nat}
    {leftPost rightPost combinedPost : State → State → Prop}
    (leftProvider :
      ReductionChainProvider program leftPre leftFuel leftPost)
    (rightProvider :
      ReductionChainProvider program rightPre rightFuel rightPost)
    (rightPre_of_leftPost :
      ∀ {state midState},
        leftPre state → leftPost state midState → rightPre midState)
    (combine :
      ∀ {state midState finalState},
        leftPre state →
        leftPost state midState →
        rightPost midState finalState →
        combinedPost state finalState) :
    ReductionChainProvider program leftPre (leftFuel + rightFuel) combinedPost where
  chain := by
    intro state hleftPre
    obtain ⟨midState, leftChain, hleftPost⟩ :=
      leftProvider.chain hleftPre
    obtain ⟨finalState, rightChain, hrightPost⟩ :=
      rightProvider.chain
        (rightPre_of_leftPost hleftPre hleftPost)
    exact ⟨finalState,
      StepReductionChain.append leftChain rightChain,
      combine hleftPre hleftPost hrightPost⟩

structure SegmentProvider (program : Program)
    (pre : State → Prop) (fuel : Nat)
    (post : State → State → Prop) : Prop where
  segment :
    ∀ {state}, pre state →
      ∃ finalState, ExecutionSegment program fuel post state finalState

theorem segmentProvider_of_reductionChainProvider
    {program : Program} {pre : State → Prop} {fuel : Nat}
    {post : State → State → Prop}
    (provider : ReductionChainProvider program pre fuel post) :
    SegmentProvider program pre fuel post where
  segment := by
    intro state hpre
    obtain ⟨finalState, chain, hpost⟩ := provider.chain hpre
    exact ⟨finalState, executionSegment_of_reductionChain chain hpost⟩

theorem runSteps_post_of_reductionChainProvider
    {program : Program} {pre : State → Prop} {fuel : Nat}
    {post : State → State → Prop} {state : State}
    (provider : ReductionChainProvider program pre fuel post) (hpre : pre state)
    (hhaltedPost : ∀ {s f}, post s f → f.halted) :
    ∃ finalState,
      runSteps program fuel state = .ok finalState ∧
      post state finalState := by
  obtain ⟨finalState, chain, hpost⟩ := provider.chain hpre
  exact ⟨finalState,
    runSteps_of_reductionChain chain (hhaltedPost hpost), hpost⟩

theorem runSteps_post_of_segmentProvider
    {program : Program} {pre : State → Prop} {fuel : Nat}
    {post : State → State → Prop} {state : State}
    (provider : SegmentProvider program pre fuel post) (hpre : pre state)
    (hhaltedPost : ∀ {s f}, post s f → f.halted) :
    ∃ finalState,
      runSteps program fuel state = .ok finalState ∧
      post state finalState := by
  obtain ⟨finalState, segment⟩ := provider.segment hpre
  exact ⟨finalState,
    runSteps_of_executionSegment segment (hhaltedPost segment.postcondition),
    segment.postcondition⟩

theorem step_of_stepInst_ok
    {program : Program} {state next : State} {instr : Inst}
    (hready : StepReady program state)
    (hdecoded : currentInst? program state = some instr)
    (hstep : stepInst program state instr = .ok next) :
    step program state = .ok next := by
  rcases hready with ⟨hrunning, _⟩
  unfold step currentInst? at *
  simp [hrunning, hdecoded, hstep]

theorem stepInst_mov64_imm_ok
    (program : Program) (state : State) (dst : Reg) (value : Nat)
    (instr : Inst)
    (hinst : instr = inst .mov64 (some dst) none none (some (.num value))) :
    stepInst program state instr = .ok (execMov64 state dst value) := by
  subst hinst
  rfl

theorem stepInst_mov64_reg_ok
    (program : Program) (state : State) (dst src : Reg) (value : Nat)
    (instr : Inst)
    (hinst : instr = inst .mov64 (some dst) (some src) none none)
    (hvalue : regGet state.regs src = value) :
    stepInst program state instr = .ok (execMov64 state dst value) := by
  subst hinst
  rw [← hvalue]
  rfl

theorem stepInst_mov32_imm_ok
    (program : Program) (state : State) (dst : Reg) (value : Nat)
    (instr : Inst)
    (hinst : instr = inst .mov32 (some dst) none none (some (.num value))) :
    stepInst program state instr = .ok (execMov64 state dst value) := by
  subst hinst
  rfl

theorem stepInst_add64_reg_ok
    (program : Program) (state : State) (dst src : Reg) (lhs rhs : Nat)
    (instr : Inst)
    (hinst : instr = inst .add64 (some dst) (some src) none none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    stepInst program state instr = .ok (nextPc (setReg state dst (lhs + rhs))) := by
  subst hinst
  rw [← hlhs, ← hrhs]
  rfl

theorem stepInst_add64_imm_ok
    (program : Program) (state : State) (dst : Reg) (lhs rhs : Nat)
    (instr : Inst)
    (hinst : instr = inst .add64 (some dst) none none (some (.num rhs)))
    (hlhs : regGet state.regs dst = lhs) :
    stepInst program state instr = .ok (nextPc (setReg state dst (lhs + rhs))) := by
  subst hinst
  rw [← hlhs]
  rfl

theorem stepInst_sub64_reg_ok
    (program : Program) (state : State) (dst src : Reg) (lhs rhs : Nat)
    (instr : Inst)
    (hinst : instr = inst .sub64 (some dst) (some src) none none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    stepInst program state instr = .ok (nextPc (setReg state dst (lhs - rhs))) := by
  subst hinst
  rw [← hlhs, ← hrhs]
  rfl

theorem stepInst_sub64_imm_ok
    (program : Program) (state : State) (dst : Reg) (lhs rhs : Nat)
    (instr : Inst)
    (hinst : instr = inst .sub64 (some dst) none none (some (.num rhs)))
    (hlhs : regGet state.regs dst = lhs) :
    stepInst program state instr = .ok (nextPc (setReg state dst (lhs - rhs))) := by
  subst hinst
  rw [← hlhs]
  rfl

theorem stepInst_mul64_reg_ok
    (program : Program) (state : State) (dst src : Reg) (lhs rhs : Nat)
    (instr : Inst)
    (hinst : instr = inst .mul64 (some dst) (some src) none none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    stepInst program state instr = .ok (nextPc (setReg state dst (lhs * rhs))) := by
  subst hinst
  rw [← hlhs, ← hrhs]
  rfl

theorem stepInst_div64_reg_ok
    (program : Program) (state : State) (dst src : Reg) (lhs rhs : Nat)
    (instr : Inst)
    (hinst : instr = inst .div64 (some dst) (some src) none none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hrhs_nonzero : rhs ≠ 0) :
    stepInst program state instr = .ok (nextPc (setReg state dst (lhs / rhs))) := by
  subst hinst
  have hsrc_nonzero : regGet state.regs src ≠ 0 := by
    rw [hrhs]
    exact hrhs_nonzero
  rw [← hlhs, ← hrhs]
  simp [stepInst, stepInstAlu64, operandValue, execAlu64, alu64, inst, dstReg,
    hsrc_nonzero]

theorem stepInst_mod64_reg_ok
    (program : Program) (state : State) (dst src : Reg) (lhs rhs : Nat)
    (instr : Inst)
    (hinst : instr = inst .mod64 (some dst) (some src) none none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hrhs_nonzero : rhs ≠ 0) :
    stepInst program state instr = .ok (nextPc (setReg state dst (lhs % rhs))) := by
  subst hinst
  have hsrc_nonzero : regGet state.regs src ≠ 0 := by
    rw [hrhs]
    exact hrhs_nonzero
  rw [← hlhs, ← hrhs]
  simp [stepInst, stepInstAlu64, operandValue, execAlu64, alu64, inst, dstReg,
    hsrc_nonzero]

theorem stepInst_lsh64_reg_ok
    (program : Program) (state : State) (dst src : Reg) (lhs rhs : Nat)
    (instr : Inst)
    (hinst : instr = inst .lsh64 (some dst) (some src) none none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    stepInst program state instr =
      .ok (nextPc (setReg state dst (Nat.shiftLeft lhs rhs))) := by
  subst hinst
  rw [← hlhs, ← hrhs]
  rfl

theorem stepInst_rsh64_reg_ok
    (program : Program) (state : State) (dst src : Reg) (lhs rhs : Nat)
    (instr : Inst)
    (hinst : instr = inst .rsh64 (some dst) (some src) none none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    stepInst program state instr =
      .ok (nextPc (setReg state dst (Nat.shiftRight lhs rhs))) := by
  subst hinst
  rw [← hlhs, ← hrhs]
  rfl

theorem stepInst_and64_reg_ok
    (program : Program) (state : State) (dst src : Reg) (lhs rhs : Nat)
    (instr : Inst)
    (hinst : instr = inst .and64 (some dst) (some src) none none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    stepInst program state instr =
      .ok (nextPc (setReg state dst (Nat.land lhs rhs))) := by
  subst hinst
  rw [← hlhs, ← hrhs]
  rfl

theorem stepInst_and64_imm_ok
    (program : Program) (state : State) (dst : Reg) (lhs rhs : Nat)
    (instr : Inst)
    (hinst : instr = inst .and64 (some dst) none none (some (.num rhs)))
    (hlhs : regGet state.regs dst = lhs) :
    stepInst program state instr =
      .ok (nextPc (setReg state dst (Nat.land lhs rhs))) := by
  subst hinst
  rw [← hlhs]
  rfl

theorem stepInst_or64_reg_ok
    (program : Program) (state : State) (dst src : Reg) (lhs rhs : Nat)
    (instr : Inst)
    (hinst : instr = inst .or64 (some dst) (some src) none none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    stepInst program state instr =
      .ok (nextPc (setReg state dst (Nat.lor lhs rhs))) := by
  subst hinst
  rw [← hlhs, ← hrhs]
  rfl

theorem stepInst_or64_imm_ok
    (program : Program) (state : State) (dst : Reg) (lhs rhs : Nat)
    (instr : Inst)
    (hinst : instr = inst .or64 (some dst) none none (some (.num rhs)))
    (hlhs : regGet state.regs dst = lhs) :
    stepInst program state instr =
      .ok (nextPc (setReg state dst (Nat.lor lhs rhs))) := by
  subst hinst
  rw [← hlhs]
  rfl

theorem stepInst_xor64_reg_ok
    (program : Program) (state : State) (dst src : Reg) (lhs rhs : Nat)
    (instr : Inst)
    (hinst : instr = inst .xor64 (some dst) (some src) none none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    stepInst program state instr =
      .ok (nextPc (setReg state dst (Nat.xor lhs rhs))) := by
  subst hinst
  rw [← hlhs, ← hrhs]
  rfl

theorem stepInst_xor64_imm_ok
    (program : Program) (state : State) (dst : Reg) (lhs rhs : Nat)
    (instr : Inst)
    (hinst : instr = inst .xor64 (some dst) none none (some (.num rhs)))
    (hlhs : regGet state.regs dst = lhs) :
    stepInst program state instr =
      .ok (nextPc (setReg state dst (Nat.xor lhs rhs))) := by
  subst hinst
  rw [← hlhs]
  rfl

theorem stepInst_lddw_ok
    (program : Program) (state : State) (dst : Reg) (value : Nat)
    (instr : Inst)
    (hinst : instr = inst .lddw (some dst) none none (some (.num value))) :
    stepInst program state instr = .ok (execLddw state dst value) := by
  subst hinst
  rfl

theorem stepInst_ldxdw_ok
    (program : Program) (state : State) (dst base : Reg) (off addr value : Nat)
    (instr : Inst)
    (hinst : instr = inst .ldxdw (some dst) (some base) (some (.num off)) none)
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    stepInst program state instr = .ok (execLoad state dst addr value) := by
  subst hinst
  have hstep :
      stepInst program state (inst .ldxdw (some dst) (some base) (some (.num off)) none) =
        .ok (execLoad state dst (memoryAddress state base off)
          (state.memory.read (memoryAddress state base off))) := rfl
  rw [hstep, haddr, hvalue]

theorem stepInst_ldxb_ok
    (program : Program) (state : State) (dst base : Reg) (off addr value : Nat)
    (instr : Inst)
    (hinst : instr = inst .ldxb (some dst) (some base) (some (.num off)) none)
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    stepInst program state instr = .ok (execLoad state dst addr value) := by
  subst hinst
  have hstep :
      stepInst program state (inst .ldxb (some dst) (some base) (some (.num off)) none) =
        .ok (execLoad state dst (memoryAddress state base off)
          (state.memory.read (memoryAddress state base off))) := rfl
  rw [hstep, haddr, hvalue]

theorem stepInst_ldxh_ok
    (program : Program) (state : State) (dst base : Reg) (off addr value : Nat)
    (instr : Inst)
    (hinst : instr = inst .ldxh (some dst) (some base) (some (.num off)) none)
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    stepInst program state instr = .ok (execLoad state dst addr value) := by
  subst hinst
  have hstep :
      stepInst program state (inst .ldxh (some dst) (some base) (some (.num off)) none) =
        .ok (execLoad state dst (memoryAddress state base off)
          (state.memory.read (memoryAddress state base off))) := rfl
  rw [hstep, haddr, hvalue]

theorem stepInst_ldxw_ok
    (program : Program) (state : State) (dst base : Reg) (off addr value : Nat)
    (instr : Inst)
    (hinst : instr = inst .ldxw (some dst) (some base) (some (.num off)) none)
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    stepInst program state instr = .ok (execLoad state dst addr value) := by
  subst hinst
  have hstep :
      stepInst program state (inst .ldxw (some dst) (some base) (some (.num off)) none) =
        .ok (execLoad state dst (memoryAddress state base off)
          (state.memory.read (memoryAddress state base off))) := rfl
  rw [hstep, haddr, hvalue]

theorem stepInst_stxdw_ok
    (program : Program) (state : State) (base src : Reg) (off addr value : Nat)
    (instr : Inst)
    (hinst : instr = inst .stxdw (some base) (some src) (some (.num off)) none)
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    stepInst program state instr = .ok (execStore state addr value) := by
  subst hinst
  have hstep :
      stepInst program state (inst .stxdw (some base) (some src) (some (.num off)) none) =
        .ok (execStore state (memoryAddress state base off) (regGet state.regs src)) := rfl
  rw [hstep, haddr, hvalue]

theorem stepInst_stb_ok
    (program : Program) (state : State) (base : Reg) (off addr value : Nat)
    (instr : Inst)
    (hinst : instr = inst .stb (some base) none (some (.num off)) (some (.num value)))
    (haddr : memoryAddress state base off = addr) :
    stepInst program state instr = .ok (execStore state addr value) := by
  subst hinst
  have hstep :
      stepInst program state (inst .stb (some base) none (some (.num off)) (some (.num value))) =
        .ok (execStore state (memoryAddress state base off) value) := rfl
  rw [hstep, haddr]

theorem stepInst_sth_ok
    (program : Program) (state : State) (base : Reg) (off addr value : Nat)
    (instr : Inst)
    (hinst : instr = inst .sth (some base) none (some (.num off)) (some (.num value)))
    (haddr : memoryAddress state base off = addr) :
    stepInst program state instr = .ok (execStore state addr value) := by
  subst hinst
  have hstep :
      stepInst program state (inst .sth (some base) none (some (.num off)) (some (.num value))) =
        .ok (execStore state (memoryAddress state base off) value) := rfl
  rw [hstep, haddr]

theorem stepInst_stw_ok
    (program : Program) (state : State) (base : Reg) (off addr value : Nat)
    (instr : Inst)
    (hinst : instr = inst .stw (some base) none (some (.num off)) (some (.num value)))
    (haddr : memoryAddress state base off = addr) :
    stepInst program state instr = .ok (execStore state addr value) := by
  subst hinst
  have hstep :
      stepInst program state (inst .stw (some base) none (some (.num off)) (some (.num value))) =
        .ok (execStore state (memoryAddress state base off) value) := rfl
  rw [hstep, haddr]

theorem stepInst_stdw_ok
    (program : Program) (state : State) (base : Reg) (off addr value : Nat)
    (instr : Inst)
    (hinst : instr = inst .stdw (some base) none (some (.num off)) (some (.num value)))
    (haddr : memoryAddress state base off = addr) :
    stepInst program state instr = .ok (execStore state addr value) := by
  subst hinst
  have hstep :
      stepInst program state (inst .stdw (some base) none (some (.num off)) (some (.num value))) =
        .ok (execStore state (memoryAddress state base off) value) := rfl
  rw [hstep, haddr]

theorem stepInst_stxb_ok
    (program : Program) (state : State) (base src : Reg) (off addr value : Nat)
    (instr : Inst)
    (hinst : instr = inst .stxb (some base) (some src) (some (.num off)) none)
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    stepInst program state instr = .ok (execStore state addr value) := by
  subst hinst
  have hstep :
      stepInst program state (inst .stxb (some base) (some src) (some (.num off)) none) =
        .ok (execStore state (memoryAddress state base off) (regGet state.regs src)) := rfl
  rw [hstep, haddr, hvalue]

theorem stepInst_stxh_ok
    (program : Program) (state : State) (base src : Reg) (off addr value : Nat)
    (instr : Inst)
    (hinst : instr = inst .stxh (some base) (some src) (some (.num off)) none)
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    stepInst program state instr = .ok (execStore state addr value) := by
  subst hinst
  have hstep :
      stepInst program state (inst .stxh (some base) (some src) (some (.num off)) none) =
        .ok (execStore state (memoryAddress state base off) (regGet state.regs src)) := rfl
  rw [hstep, haddr, hvalue]

theorem stepInst_stxw_ok
    (program : Program) (state : State) (base src : Reg) (off addr value : Nat)
    (instr : Inst)
    (hinst : instr = inst .stxw (some base) (some src) (some (.num off)) none)
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    stepInst program state instr = .ok (execStore state addr value) := by
  subst hinst
  have hstep :
      stepInst program state (inst .stxw (some base) (some src) (some (.num off)) none) =
        .ok (execStore state (memoryAddress state base off) (regGet state.regs src)) := rfl
  rw [hstep, haddr, hvalue]

theorem stepInst_ja_imm_ok
    (program : Program) (state : State) (target : Nat)
    (instr : Inst)
    (hinst : instr = inst .ja none none (some (.num target)) none) :
    stepInst program state instr = .ok (execJump state target) := by
  subst hinst
  rfl

theorem stepInst_jeq_imm_taken_ok
    (program : Program) (state : State) (dst : Reg) (lhs rhs target : Nat)
    (instr : Inst)
    (hinst : instr = inst .jeq (some dst) none (some (.num target)) (some (.num rhs)))
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs = rhs) :
    stepInst program state instr = .ok (execJump state target) := by
  subst hinst
  exact stepInstCondJump_jeq_imm_taken program state dst lhs rhs target hlhs hcond

theorem stepInst_jeq_imm_fallthrough_ok
    (program : Program) (state : State) (dst : Reg) (lhs rhs target : Nat)
    (instr : Inst)
    (hinst : instr = inst .jeq (some dst) none (some (.num target)) (some (.num rhs)))
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs ≠ rhs) :
    stepInst program state instr = .ok (nextPc state) := by
  subst hinst
  exact stepInstCondJump_jeq_imm_fallthrough program state dst lhs rhs target hlhs hcond

theorem stepInst_jeq_reg_taken_ok
    (program : Program) (state : State) (dst src : Reg) (lhs rhs target : Nat)
    (instr : Inst)
    (hinst : instr = inst .jeq (some dst) (some src) (some (.num target)) none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs = rhs) :
    stepInst program state instr = .ok (execJump state target) := by
  subst hinst
  exact stepInstCondJump_jeq_reg_taken program state dst src lhs rhs target hlhs hrhs hcond

theorem stepInst_jeq_reg_fallthrough_ok
    (program : Program) (state : State) (dst src : Reg) (lhs rhs target : Nat)
    (instr : Inst)
    (hinst : instr = inst .jeq (some dst) (some src) (some (.num target)) none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs ≠ rhs) :
    stepInst program state instr = .ok (nextPc state) := by
  subst hinst
  exact stepInstCondJump_jeq_reg_fallthrough program state dst src lhs rhs target hlhs hrhs hcond

theorem stepInst_jne_imm_taken_ok
    (program : Program) (state : State) (dst : Reg) (lhs rhs target : Nat)
    (instr : Inst)
    (hinst : instr = inst .jne (some dst) none (some (.num target)) (some (.num rhs)))
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs ≠ rhs) :
    stepInst program state instr = .ok (execJump state target) := by
  subst hinst
  exact stepInstCondJump_jne_imm_taken program state dst lhs rhs target hlhs hcond

theorem stepInst_jne_imm_fallthrough_ok
    (program : Program) (state : State) (dst : Reg) (lhs rhs target : Nat)
    (instr : Inst)
    (hinst : instr = inst .jne (some dst) none (some (.num target)) (some (.num rhs)))
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs = rhs) :
    stepInst program state instr = .ok (nextPc state) := by
  subst hinst
  exact stepInstCondJump_jne_imm_fallthrough program state dst lhs rhs target hlhs hcond

theorem stepInst_jne_reg_taken_ok
    (program : Program) (state : State) (dst src : Reg) (lhs rhs target : Nat)
    (instr : Inst)
    (hinst : instr = inst .jne (some dst) (some src) (some (.num target)) none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs ≠ rhs) :
    stepInst program state instr = .ok (execJump state target) := by
  subst hinst
  exact stepInstCondJump_jne_reg_taken program state dst src lhs rhs target hlhs hrhs hcond

theorem stepInst_jne_reg_fallthrough_ok
    (program : Program) (state : State) (dst src : Reg) (lhs rhs target : Nat)
    (instr : Inst)
    (hinst : instr = inst .jne (some dst) (some src) (some (.num target)) none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs = rhs) :
    stepInst program state instr = .ok (nextPc state) := by
  subst hinst
  exact stepInstCondJump_jne_reg_fallthrough program state dst src lhs rhs target hlhs hrhs hcond

theorem stepInstCondJump_imm_taken_of_cond
    (program : Program) (state : State) (opcode : Opcode)
    (dst : Reg) (off : MemOff) (lhs rhs target : Nat)
    (hlhs : regGet state.regs dst = lhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition opcode lhs rhs = .ok true) :
    stepInstCondJump program state
      (inst opcode (some dst) none (some off) (some (.num rhs))) =
      .ok (execJump state target) := by
  simp only [stepInstCondJump, dstReg_inst_some, operandValue_inst_imm, resolveImm,
    inst_opcode]
  rw [hlhs, hcond]
  exact stepInstCondJumpCore_taken program state
    (inst opcode (some dst) none (some off) (some (.num rhs))) target htarget

theorem stepInstCondJump_imm_fallthrough_of_cond
    (program : Program) (state : State) (opcode : Opcode)
    (dst : Reg) (off : MemOff) (lhs rhs : Nat)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : jumpCondition opcode lhs rhs = .ok false) :
    stepInstCondJump program state
      (inst opcode (some dst) none (some off) (some (.num rhs))) =
      .ok (nextPc state) := by
  simp only [stepInstCondJump, dstReg_inst_some, operandValue_inst_imm, resolveImm,
    inst_opcode]
  rw [hlhs, hcond]
  exact stepInstCondJumpCore_fallthrough program state
    (inst opcode (some dst) none (some off) (some (.num rhs)))

theorem stepInstCondJump_reg_taken_of_cond
    (program : Program) (state : State) (opcode : Opcode)
    (dst src : Reg) (off : MemOff) (lhs rhs target : Nat)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition opcode lhs rhs = .ok true) :
    stepInstCondJump program state
      (inst opcode (some dst) (some src) (some off) none) =
      .ok (execJump state target) := by
  simp only [stepInstCondJump, dstReg_inst_some, operandValue_inst_reg, inst_opcode]
  rw [hlhs, hrhs, hcond]
  exact stepInstCondJumpCore_taken program state
    (inst opcode (some dst) (some src) (some off) none) target htarget

theorem stepInstCondJump_reg_fallthrough_of_cond
    (program : Program) (state : State) (opcode : Opcode)
    (dst src : Reg) (off : MemOff) (lhs rhs : Nat)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition opcode lhs rhs = .ok false) :
    stepInstCondJump program state
      (inst opcode (some dst) (some src) (some off) none) =
      .ok (nextPc state) := by
  simp only [stepInstCondJump, dstReg_inst_some, operandValue_inst_reg, inst_opcode]
  rw [hlhs, hrhs, hcond]
  exact stepInstCondJumpCore_fallthrough program state
    (inst opcode (some dst) (some src) (some off) none)

theorem stepInst_jge_imm_taken_ok
    (program : Program) (state : State) (dst : Reg) (off : MemOff)
    (lhs rhs target : Nat) (instr : Inst)
    (hinst : instr = inst .jge (some dst) none (some off) (some (.num rhs)))
    (hlhs : regGet state.regs dst = lhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jge lhs rhs = .ok true) :
    stepInst program state instr = .ok (execJump state target) := by
  subst hinst
  exact stepInstCondJump_imm_taken_of_cond program state .jge dst off lhs rhs target
    hlhs htarget hcond

theorem stepInst_jge_imm_fallthrough_ok
    (program : Program) (state : State) (dst : Reg) (off : MemOff)
    (lhs rhs : Nat) (instr : Inst)
    (hinst : instr = inst .jge (some dst) none (some off) (some (.num rhs)))
    (hlhs : regGet state.regs dst = lhs)
    (hcond : jumpCondition .jge lhs rhs = .ok false) :
    stepInst program state instr = .ok (nextPc state) := by
  subst hinst
  exact stepInstCondJump_imm_fallthrough_of_cond program state .jge dst off lhs rhs
    hlhs hcond

theorem stepInst_jge_reg_taken_ok
    (program : Program) (state : State) (dst src : Reg) (off : MemOff)
    (lhs rhs target : Nat) (instr : Inst)
    (hinst : instr = inst .jge (some dst) (some src) (some off) none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jge lhs rhs = .ok true) :
    stepInst program state instr = .ok (execJump state target) := by
  subst hinst
  exact stepInstCondJump_reg_taken_of_cond program state .jge dst src off lhs rhs target
    hlhs hrhs htarget hcond

theorem stepInst_jge_reg_fallthrough_ok
    (program : Program) (state : State) (dst src : Reg) (off : MemOff)
    (lhs rhs : Nat) (instr : Inst)
    (hinst : instr = inst .jge (some dst) (some src) (some off) none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jge lhs rhs = .ok false) :
    stepInst program state instr = .ok (nextPc state) := by
  subst hinst
  exact stepInstCondJump_reg_fallthrough_of_cond program state .jge dst src off lhs rhs
    hlhs hrhs hcond

theorem stepInst_jlt_imm_taken_ok
    (program : Program) (state : State) (dst : Reg) (off : MemOff)
    (lhs rhs target : Nat) (instr : Inst)
    (hinst : instr = inst .jlt (some dst) none (some off) (some (.num rhs)))
    (hlhs : regGet state.regs dst = lhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jlt lhs rhs = .ok true) :
    stepInst program state instr = .ok (execJump state target) := by
  subst hinst
  exact stepInstCondJump_imm_taken_of_cond program state .jlt dst off lhs rhs target
    hlhs htarget hcond

theorem stepInst_jlt_imm_fallthrough_ok
    (program : Program) (state : State) (dst : Reg) (off : MemOff)
    (lhs rhs : Nat) (instr : Inst)
    (hinst : instr = inst .jlt (some dst) none (some off) (some (.num rhs)))
    (hlhs : regGet state.regs dst = lhs)
    (hcond : jumpCondition .jlt lhs rhs = .ok false) :
    stepInst program state instr = .ok (nextPc state) := by
  subst hinst
  exact stepInstCondJump_imm_fallthrough_of_cond program state .jlt dst off lhs rhs
    hlhs hcond

theorem stepInst_jlt_reg_taken_ok
    (program : Program) (state : State) (dst src : Reg) (off : MemOff)
    (lhs rhs target : Nat) (instr : Inst)
    (hinst : instr = inst .jlt (some dst) (some src) (some off) none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jlt lhs rhs = .ok true) :
    stepInst program state instr = .ok (execJump state target) := by
  subst hinst
  exact stepInstCondJump_reg_taken_of_cond program state .jlt dst src off lhs rhs target
    hlhs hrhs htarget hcond

theorem stepInst_jlt_reg_fallthrough_ok
    (program : Program) (state : State) (dst src : Reg) (off : MemOff)
    (lhs rhs : Nat) (instr : Inst)
    (hinst : instr = inst .jlt (some dst) (some src) (some off) none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jlt lhs rhs = .ok false) :
    stepInst program state instr = .ok (nextPc state) := by
  subst hinst
  exact stepInstCondJump_reg_fallthrough_of_cond program state .jlt dst src off lhs rhs
    hlhs hrhs hcond

theorem stepInst_jgt_reg_taken_ok
    (program : Program) (state : State) (dst src : Reg) (off : MemOff)
    (lhs rhs target : Nat) (instr : Inst)
    (hinst : instr = inst .jgt (some dst) (some src) (some off) none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jgt lhs rhs = .ok true) :
    stepInst program state instr = .ok (execJump state target) := by
  subst hinst
  exact stepInstCondJump_reg_taken_of_cond program state .jgt dst src off lhs rhs target
    hlhs hrhs htarget hcond

theorem stepInst_jgt_reg_fallthrough_ok
    (program : Program) (state : State) (dst src : Reg) (off : MemOff)
    (lhs rhs : Nat) (instr : Inst)
    (hinst : instr = inst .jgt (some dst) (some src) (some off) none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jgt lhs rhs = .ok false) :
    stepInst program state instr = .ok (nextPc state) := by
  subst hinst
  exact stepInstCondJump_reg_fallthrough_of_cond program state .jgt dst src off lhs rhs
    hlhs hrhs hcond

theorem stepInst_jle_reg_taken_ok
    (program : Program) (state : State) (dst src : Reg) (off : MemOff)
    (lhs rhs target : Nat) (instr : Inst)
    (hinst : instr = inst .jle (some dst) (some src) (some off) none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jle lhs rhs = .ok true) :
    stepInst program state instr = .ok (execJump state target) := by
  subst hinst
  exact stepInstCondJump_reg_taken_of_cond program state .jle dst src off lhs rhs target
    hlhs hrhs htarget hcond

theorem stepInst_jle_reg_fallthrough_ok
    (program : Program) (state : State) (dst src : Reg) (off : MemOff)
    (lhs rhs : Nat) (instr : Inst)
    (hinst : instr = inst .jle (some dst) (some src) (some off) none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jle lhs rhs = .ok false) :
    stepInst program state instr = .ok (nextPc state) := by
  subst hinst
  exact stepInstCondJump_reg_fallthrough_of_cond program state .jle dst src off lhs rhs
    hlhs hrhs hcond

theorem stepInst_jset_imm_taken_ok
    (program : Program) (state : State) (dst : Reg) (off : MemOff)
    (lhs rhs target : Nat) (instr : Inst)
    (hinst : instr = inst .jset (some dst) none (some off) (some (.num rhs)))
    (hlhs : regGet state.regs dst = lhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jset lhs rhs = .ok true) :
    stepInst program state instr = .ok (execJump state target) := by
  subst hinst
  exact stepInstCondJump_imm_taken_of_cond program state .jset dst off lhs rhs target
    hlhs htarget hcond

theorem stepInst_jset_imm_fallthrough_ok
    (program : Program) (state : State) (dst : Reg) (off : MemOff)
    (lhs rhs : Nat) (instr : Inst)
    (hinst : instr = inst .jset (some dst) none (some off) (some (.num rhs)))
    (hlhs : regGet state.regs dst = lhs)
    (hcond : jumpCondition .jset lhs rhs = .ok false) :
    stepInst program state instr = .ok (nextPc state) := by
  subst hinst
  exact stepInstCondJump_imm_fallthrough_of_cond program state .jset dst off lhs rhs
    hlhs hcond

theorem stepInst_jset_reg_taken_ok
    (program : Program) (state : State) (dst src : Reg) (off : MemOff)
    (lhs rhs target : Nat) (instr : Inst)
    (hinst : instr = inst .jset (some dst) (some src) (some off) none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jset lhs rhs = .ok true) :
    stepInst program state instr = .ok (execJump state target) := by
  subst hinst
  exact stepInstCondJump_reg_taken_of_cond program state .jset dst src off lhs rhs target
    hlhs hrhs htarget hcond

theorem stepInst_jset_reg_fallthrough_ok
    (program : Program) (state : State) (dst src : Reg) (off : MemOff)
    (lhs rhs : Nat) (instr : Inst)
    (hinst : instr = inst .jset (some dst) (some src) (some off) none)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jset lhs rhs = .ok false) :
    stepInst program state instr = .ok (nextPc state) := by
  subst hinst
  exact stepInstCondJump_reg_fallthrough_of_cond program state .jset dst src off lhs rhs
    hlhs hrhs hcond

theorem stepInst_exit_ok
    (program : Program) (state : State) (r0 : Nat)
    (instr : Inst) (hinst : instr = inst .exit none none none none)
    (hr0 : regGet state.regs .r0 = r0) :
    stepInst program state instr = .ok (execExit state r0) := by
  subst hinst
  rw [← hr0]
  rfl

theorem stepInst_syscall_set_return_data_ok
    (program : Program) (state : State) (ptr value : Nat)
    (instr : Inst)
    (hinst : instr = inst .call none none none (some (.sym sol_set_return_data)))
    (hptr : regGet state.regs .r1 = ptr)
    (hvalue : state.memory.read ptr = value) :
    stepInst program state instr = .ok (execSetReturnData state value) := by
  subst hinst
  have hread : state.memory.read (regGet state.regs .r1) = value := by rw [hptr, hvalue]
  rw [← hread]
  rfl

theorem stepInst_syscall_get_clock_sysvar_ok
    (program : Program) (state : State) (ptr : Nat)
    (instr : Inst)
    (hinst : instr = inst .call none none none (some (.sym sol_get_clock_sysvar)))
    (hptr : regGet state.regs .r1 = ptr) :
    stepInst program state instr = .ok (execGetClockSysvar state ptr) := by
  subst hinst
  rw [← hptr]
  rfl

theorem stepInst_syscall_log64_ok
    (program : Program) (state : State)
    (instr : Inst)
    (hinst : instr = inst .call none none none (some (.sym sol_log_64_))) :
    stepInst program state instr = .ok (execLog64 state) := by
  subst hinst
  rfl

theorem step_mov64_imm_ok
    {program : Program} {state : State} {dst : Reg} {value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .mov64 (some dst) none none (some (.num value)))) :
    step program state = .ok (execMov64 state dst value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_mov64_imm_ok program state dst value _ rfl)

theorem step_mov64_reg_ok
    {program : Program} {state : State} {dst src : Reg} {value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .mov64 (some dst) (some src) none none))
    (hvalue : regGet state.regs src = value) :
    step program state = .ok (execMov64 state dst value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_mov64_reg_ok program state dst src value _ rfl hvalue)

theorem step_mov32_imm_ok
    {program : Program} {state : State} {dst : Reg} {value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .mov32 (some dst) none none (some (.num value)))) :
    step program state = .ok (execMov64 state dst value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_mov32_imm_ok program state dst value _ rfl)

theorem step_add64_reg_ok
    {program : Program} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .add64 (some dst) (some src) none none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (lhs + rhs))) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_add64_reg_ok program state dst src lhs rhs _ rfl hlhs hrhs)

theorem step_add64_imm_ok
    {program : Program} {state : State} {dst : Reg} {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .add64 (some dst) none none (some (.num rhs))))
    (hlhs : regGet state.regs dst = lhs) :
    step program state = .ok (nextPc (setReg state dst (lhs + rhs))) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_add64_imm_ok program state dst lhs rhs _ rfl hlhs)

theorem step_sub64_reg_ok
    {program : Program} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .sub64 (some dst) (some src) none none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (lhs - rhs))) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_sub64_reg_ok program state dst src lhs rhs _ rfl hlhs hrhs)

theorem step_sub64_imm_ok
    {program : Program} {state : State} {dst : Reg} {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .sub64 (some dst) none none (some (.num rhs))))
    (hlhs : regGet state.regs dst = lhs) :
    step program state = .ok (nextPc (setReg state dst (lhs - rhs))) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_sub64_imm_ok program state dst lhs rhs _ rfl hlhs)

theorem step_mul64_reg_ok
    {program : Program} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .mul64 (some dst) (some src) none none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (lhs * rhs))) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_mul64_reg_ok program state dst src lhs rhs _ rfl hlhs hrhs)

theorem step_div64_reg_ok
    {program : Program} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .div64 (some dst) (some src) none none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hrhs_nonzero : rhs ≠ 0) :
    step program state = .ok (nextPc (setReg state dst (lhs / rhs))) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_div64_reg_ok program state dst src lhs rhs _ rfl hlhs hrhs hrhs_nonzero)

theorem step_mod64_reg_ok
    {program : Program} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .mod64 (some dst) (some src) none none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hrhs_nonzero : rhs ≠ 0) :
    step program state = .ok (nextPc (setReg state dst (lhs % rhs))) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_mod64_reg_ok program state dst src lhs rhs _ rfl hlhs hrhs hrhs_nonzero)

theorem step_lsh64_reg_ok
    {program : Program} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .lsh64 (some dst) (some src) none none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (Nat.shiftLeft lhs rhs))) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_lsh64_reg_ok program state dst src lhs rhs _ rfl hlhs hrhs)

theorem step_rsh64_reg_ok
    {program : Program} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .rsh64 (some dst) (some src) none none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (Nat.shiftRight lhs rhs))) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_rsh64_reg_ok program state dst src lhs rhs _ rfl hlhs hrhs)

theorem step_and64_reg_ok
    {program : Program} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .and64 (some dst) (some src) none none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (Nat.land lhs rhs))) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_and64_reg_ok program state dst src lhs rhs _ rfl hlhs hrhs)

theorem step_and64_imm_ok
    {program : Program} {state : State} {dst : Reg} {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .and64 (some dst) none none (some (.num rhs))))
    (hlhs : regGet state.regs dst = lhs) :
    step program state = .ok (nextPc (setReg state dst (Nat.land lhs rhs))) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_and64_imm_ok program state dst lhs rhs _ rfl hlhs)

theorem step_or64_reg_ok
    {program : Program} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .or64 (some dst) (some src) none none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (Nat.lor lhs rhs))) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_or64_reg_ok program state dst src lhs rhs _ rfl hlhs hrhs)

theorem step_or64_imm_ok
    {program : Program} {state : State} {dst : Reg} {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .or64 (some dst) none none (some (.num rhs))))
    (hlhs : regGet state.regs dst = lhs) :
    step program state = .ok (nextPc (setReg state dst (Nat.lor lhs rhs))) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_or64_imm_ok program state dst lhs rhs _ rfl hlhs)

theorem step_xor64_reg_ok
    {program : Program} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .xor64 (some dst) (some src) none none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (Nat.xor lhs rhs))) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_xor64_reg_ok program state dst src lhs rhs _ rfl hlhs hrhs)

theorem step_xor64_imm_ok
    {program : Program} {state : State} {dst : Reg} {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .xor64 (some dst) none none (some (.num rhs))))
    (hlhs : regGet state.regs dst = lhs) :
    step program state = .ok (nextPc (setReg state dst (Nat.xor lhs rhs))) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_xor64_imm_ok program state dst lhs rhs _ rfl hlhs)

theorem step_lddw_ok
    {program : Program} {state : State} {dst : Reg} {value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .lddw (some dst) none none (some (.num value)))) :
    step program state = .ok (execLddw state dst value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_lddw_ok program state dst value _ rfl)

theorem step_ldxdw_ok
    {program : Program} {state : State} {dst base : Reg} {off addr value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .ldxdw (some dst) (some base) (some (.num off)) none))
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    step program state = .ok (execLoad state dst addr value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_ldxdw_ok program state dst base off addr value _ rfl haddr hvalue)

theorem step_ldxb_ok
    {program : Program} {state : State} {dst base : Reg} {off addr value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .ldxb (some dst) (some base) (some (.num off)) none))
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    step program state = .ok (execLoad state dst addr value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_ldxb_ok program state dst base off addr value _ rfl haddr hvalue)

theorem step_ldxh_ok
    {program : Program} {state : State} {dst base : Reg} {off addr value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .ldxh (some dst) (some base) (some (.num off)) none))
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    step program state = .ok (execLoad state dst addr value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_ldxh_ok program state dst base off addr value _ rfl haddr hvalue)

theorem step_ldxw_ok
    {program : Program} {state : State} {dst base : Reg} {off addr value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .ldxw (some dst) (some base) (some (.num off)) none))
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    step program state = .ok (execLoad state dst addr value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_ldxw_ok program state dst base off addr value _ rfl haddr hvalue)

theorem step_stxdw_ok
    {program : Program} {state : State} {base src : Reg} {off addr value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .stxdw (some base) (some src) (some (.num off)) none))
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    step program state = .ok (execStore state addr value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_stxdw_ok program state base src off addr value _ rfl haddr hvalue)

theorem step_stb_ok
    {program : Program} {state : State} {base : Reg} {off addr value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .stb (some base) none (some (.num off)) (some (.num value))))
    (haddr : memoryAddress state base off = addr) :
    step program state = .ok (execStore state addr value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_stb_ok program state base off addr value _ rfl haddr)

theorem step_sth_ok
    {program : Program} {state : State} {base : Reg} {off addr value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .sth (some base) none (some (.num off)) (some (.num value))))
    (haddr : memoryAddress state base off = addr) :
    step program state = .ok (execStore state addr value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_sth_ok program state base off addr value _ rfl haddr)

theorem step_stw_ok
    {program : Program} {state : State} {base : Reg} {off addr value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .stw (some base) none (some (.num off)) (some (.num value))))
    (haddr : memoryAddress state base off = addr) :
    step program state = .ok (execStore state addr value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_stw_ok program state base off addr value _ rfl haddr)

theorem step_stdw_ok
    {program : Program} {state : State} {base : Reg} {off addr value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .stdw (some base) none (some (.num off)) (some (.num value))))
    (haddr : memoryAddress state base off = addr) :
    step program state = .ok (execStore state addr value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_stdw_ok program state base off addr value _ rfl haddr)

theorem step_stxb_ok
    {program : Program} {state : State} {base src : Reg} {off addr value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .stxb (some base) (some src) (some (.num off)) none))
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    step program state = .ok (execStore state addr value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_stxb_ok program state base src off addr value _ rfl haddr hvalue)

theorem step_stxh_ok
    {program : Program} {state : State} {base src : Reg} {off addr value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .stxh (some base) (some src) (some (.num off)) none))
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    step program state = .ok (execStore state addr value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_stxh_ok program state base src off addr value _ rfl haddr hvalue)

theorem step_stxw_ok
    {program : Program} {state : State} {base src : Reg} {off addr value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .stxw (some base) (some src) (some (.num off)) none))
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    step program state = .ok (execStore state addr value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_stxw_ok program state base src off addr value _ rfl haddr hvalue)

theorem step_ja_imm_ok
    {program : Program} {state : State} {target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .ja none none (some (.num target)) none)) :
    step program state = .ok (execJump state target) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_ja_imm_ok program state target _ rfl)

theorem step_jeq_imm_taken_ok
    {program : Program} {state : State} {dst : Reg} {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jeq (some dst) none (some (.num target)) (some (.num rhs))))
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs = rhs) :
    step program state = .ok (execJump state target) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jeq_imm_taken_ok program state dst lhs rhs target _ rfl hlhs hcond)

theorem step_jeq_imm_fallthrough_ok
    {program : Program} {state : State} {dst : Reg} {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jeq (some dst) none (some (.num target)) (some (.num rhs))))
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs ≠ rhs) :
    step program state = .ok (nextPc state) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jeq_imm_fallthrough_ok program state dst lhs rhs target _ rfl hlhs hcond)

theorem step_jeq_reg_taken_ok
    {program : Program} {state : State} {dst src : Reg} {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jeq (some dst) (some src) (some (.num target)) none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs = rhs) :
    step program state = .ok (execJump state target) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jeq_reg_taken_ok program state dst src lhs rhs target _ rfl hlhs hrhs hcond)

theorem step_jeq_reg_fallthrough_ok
    {program : Program} {state : State} {dst src : Reg} {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jeq (some dst) (some src) (some (.num target)) none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs ≠ rhs) :
    step program state = .ok (nextPc state) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jeq_reg_fallthrough_ok program state dst src lhs rhs target _ rfl hlhs hrhs hcond)

theorem step_jne_imm_taken_ok
    {program : Program} {state : State} {dst : Reg} {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jne (some dst) none (some (.num target)) (some (.num rhs))))
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs ≠ rhs) :
    step program state = .ok (execJump state target) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jne_imm_taken_ok program state dst lhs rhs target _ rfl hlhs hcond)

theorem step_jne_imm_fallthrough_ok
    {program : Program} {state : State} {dst : Reg} {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jne (some dst) none (some (.num target)) (some (.num rhs))))
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs = rhs) :
    step program state = .ok (nextPc state) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jne_imm_fallthrough_ok program state dst lhs rhs target _ rfl hlhs hcond)

theorem step_jne_reg_taken_ok
    {program : Program} {state : State} {dst src : Reg} {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jne (some dst) (some src) (some (.num target)) none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs ≠ rhs) :
    step program state = .ok (execJump state target) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jne_reg_taken_ok program state dst src lhs rhs target _ rfl hlhs hrhs hcond)

theorem step_jne_reg_fallthrough_ok
    {program : Program} {state : State} {dst src : Reg} {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jne (some dst) (some src) (some (.num target)) none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs = rhs) :
    step program state = .ok (nextPc state) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jne_reg_fallthrough_ok program state dst src lhs rhs target _ rfl hlhs hrhs hcond)

theorem step_jge_imm_taken_ok
    {program : Program} {state : State} {dst : Reg} {off : MemOff}
    {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jge (some dst) none (some off) (some (.num rhs))))
    (hlhs : regGet state.regs dst = lhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jge lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jge_imm_taken_ok program state dst off lhs rhs target _ rfl
      hlhs htarget hcond)

theorem step_jge_imm_fallthrough_ok
    {program : Program} {state : State} {dst : Reg} {off : MemOff}
    {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jge (some dst) none (some off) (some (.num rhs))))
    (hlhs : regGet state.regs dst = lhs)
    (hcond : jumpCondition .jge lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jge_imm_fallthrough_ok program state dst off lhs rhs _ rfl hlhs hcond)

theorem step_jge_reg_taken_ok
    {program : Program} {state : State} {dst src : Reg} {off : MemOff}
    {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jge (some dst) (some src) (some off) none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jge lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jge_reg_taken_ok program state dst src off lhs rhs target _ rfl
      hlhs hrhs htarget hcond)

theorem step_jge_reg_fallthrough_ok
    {program : Program} {state : State} {dst src : Reg} {off : MemOff}
    {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jge (some dst) (some src) (some off) none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jge lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jge_reg_fallthrough_ok program state dst src off lhs rhs _ rfl
      hlhs hrhs hcond)

theorem step_jlt_imm_taken_ok
    {program : Program} {state : State} {dst : Reg} {off : MemOff}
    {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jlt (some dst) none (some off) (some (.num rhs))))
    (hlhs : regGet state.regs dst = lhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jlt lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jlt_imm_taken_ok program state dst off lhs rhs target _ rfl
      hlhs htarget hcond)

theorem step_jlt_imm_fallthrough_ok
    {program : Program} {state : State} {dst : Reg} {off : MemOff}
    {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jlt (some dst) none (some off) (some (.num rhs))))
    (hlhs : regGet state.regs dst = lhs)
    (hcond : jumpCondition .jlt lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jlt_imm_fallthrough_ok program state dst off lhs rhs _ rfl hlhs hcond)

theorem step_jlt_reg_taken_ok
    {program : Program} {state : State} {dst src : Reg} {off : MemOff}
    {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jlt (some dst) (some src) (some off) none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jlt lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jlt_reg_taken_ok program state dst src off lhs rhs target _ rfl
      hlhs hrhs htarget hcond)

theorem step_jlt_reg_fallthrough_ok
    {program : Program} {state : State} {dst src : Reg} {off : MemOff}
    {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jlt (some dst) (some src) (some off) none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jlt lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jlt_reg_fallthrough_ok program state dst src off lhs rhs _ rfl
      hlhs hrhs hcond)

theorem step_jgt_reg_taken_ok
    {program : Program} {state : State} {dst src : Reg} {off : MemOff}
    {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jgt (some dst) (some src) (some off) none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jgt lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jgt_reg_taken_ok program state dst src off lhs rhs target _ rfl
      hlhs hrhs htarget hcond)

theorem step_jgt_reg_fallthrough_ok
    {program : Program} {state : State} {dst src : Reg} {off : MemOff}
    {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jgt (some dst) (some src) (some off) none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jgt lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jgt_reg_fallthrough_ok program state dst src off lhs rhs _ rfl
      hlhs hrhs hcond)

theorem step_jle_reg_taken_ok
    {program : Program} {state : State} {dst src : Reg} {off : MemOff}
    {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jle (some dst) (some src) (some off) none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jle lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jle_reg_taken_ok program state dst src off lhs rhs target _ rfl
      hlhs hrhs htarget hcond)

theorem step_jle_reg_fallthrough_ok
    {program : Program} {state : State} {dst src : Reg} {off : MemOff}
    {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jle (some dst) (some src) (some off) none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jle lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jle_reg_fallthrough_ok program state dst src off lhs rhs _ rfl
      hlhs hrhs hcond)

theorem step_jset_imm_taken_ok
    {program : Program} {state : State} {dst : Reg} {off : MemOff}
    {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jset (some dst) none (some off) (some (.num rhs))))
    (hlhs : regGet state.regs dst = lhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jset lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jset_imm_taken_ok program state dst off lhs rhs target _ rfl
      hlhs htarget hcond)

theorem step_jset_imm_fallthrough_ok
    {program : Program} {state : State} {dst : Reg} {off : MemOff}
    {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jset (some dst) none (some off) (some (.num rhs))))
    (hlhs : regGet state.regs dst = lhs)
    (hcond : jumpCondition .jset lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jset_imm_fallthrough_ok program state dst off lhs rhs _ rfl
      hlhs hcond)

theorem step_jset_reg_taken_ok
    {program : Program} {state : State} {dst src : Reg} {off : MemOff}
    {lhs rhs target : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jset (some dst) (some src) (some off) none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jset lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jset_reg_taken_ok program state dst src off lhs rhs target _ rfl
      hlhs hrhs htarget hcond)

theorem step_jset_reg_fallthrough_ok
    {program : Program} {state : State} {dst src : Reg} {off : MemOff}
    {lhs rhs : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .jset (some dst) (some src) (some off) none))
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jset lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_jset_reg_fallthrough_ok program state dst src off lhs rhs _ rfl
      hlhs hrhs hcond)

theorem step_exit_ok
    {program : Program} {state : State} {r0 : Nat}
    (hready : StepReady program state)
    (hdecoded : currentInst? program state = some (inst .exit none none none none))
    (hr0 : regGet state.regs .r0 = r0) :
    step program state = .ok (execExit state r0) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_exit_ok program state r0 _ rfl hr0)

theorem step_syscall_set_return_data_ok
    {program : Program} {state : State} {ptr value : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .call none none none (some (.sym sol_set_return_data))))
    (hptr : regGet state.regs .r1 = ptr)
    (hvalue : state.memory.read ptr = value) :
    step program state = .ok (execSetReturnData state value) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_syscall_set_return_data_ok program state ptr value _ rfl hptr hvalue)

theorem step_syscall_get_clock_sysvar_ok
    {program : Program} {state : State} {ptr : Nat}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .call none none none (some (.sym sol_get_clock_sysvar))))
    (hptr : regGet state.regs .r1 = ptr) :
    step program state = .ok (execGetClockSysvar state ptr) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_syscall_get_clock_sysvar_ok program state ptr _ rfl hptr)

theorem step_syscall_log64_ok
    {program : Program} {state : State}
    (hready : StepReady program state)
    (hdecoded :
      currentInst? program state =
        some (inst .call none none none (some (.sym sol_log_64_)))) :
    step program state = .ok (execLog64 state) :=
  step_of_stepInst_ok hready hdecoded
    (stepInst_syscall_log64_ok program state _ rfl)

/-! ### PC-anchored step and reduction lemmas -/

theorem step_mov64_imm_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .mov64 (some dst) none none (some (.num value))) state) :
    step program state = .ok (execMov64 state dst value) :=
  step_mov64_imm_ok hat.stepReady hat.currentInst?

theorem reduction_mov64_imm_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .mov64 (some dst) none none (some (.num value))) state) :
    StepReduction program state (execMov64 state dst value) :=
  StepReduction.of_readyOpcodeAt hat (step_mov64_imm_at_ok hat)

theorem step_lddw_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .lddw (some dst) none none (some (.num value))) state) :
    step program state = .ok (execLddw state dst value) :=
  step_lddw_ok hat.stepReady hat.currentInst?

theorem reduction_lddw_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .lddw (some dst) none none (some (.num value))) state) :
    StepReduction program state (execLddw state dst value) :=
  StepReduction.of_readyOpcodeAt hat (step_lddw_at_ok hat)

theorem step_ldxdw_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .ldxdw (some dst) (some base) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    step program state = .ok (execLoad state dst addr value) :=
  step_ldxdw_ok hat.stepReady hat.currentInst? haddr hvalue

theorem reduction_ldxdw_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .ldxdw (some dst) (some base) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    StepReduction program state (execLoad state dst addr value) :=
  StepReduction.of_readyOpcodeAt hat (step_ldxdw_at_ok hat haddr hvalue)

theorem step_syscall_set_return_data_at_ok
    {program : Program} {pc : Nat} {state : State} {ptr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .call none none none (some (.sym sol_set_return_data))) state)
    (hptr : regGet state.regs .r1 = ptr)
    (hvalue : state.memory.read ptr = value) :
    step program state = .ok (execSetReturnData state value) :=
  step_syscall_set_return_data_ok hat.stepReady hat.currentInst? hptr hvalue

theorem reduction_syscall_set_return_data_at_ok
    {program : Program} {pc : Nat} {state : State} {ptr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .call none none none (some (.sym sol_set_return_data))) state)
    (hptr : regGet state.regs .r1 = ptr)
    (hvalue : state.memory.read ptr = value) :
    StepReduction program state (execSetReturnData state value) :=
  StepReduction.of_readyOpcodeAt hat
    (step_syscall_set_return_data_at_ok hat hptr hvalue)

theorem step_syscall_get_clock_sysvar_at_ok
    {program : Program} {pc : Nat} {state : State} {ptr : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .call none none none (some (.sym sol_get_clock_sysvar))) state)
    (hptr : regGet state.regs .r1 = ptr) :
    step program state = .ok (execGetClockSysvar state ptr) :=
  step_syscall_get_clock_sysvar_ok hat.stepReady hat.currentInst? hptr

theorem reduction_syscall_get_clock_sysvar_at_ok
    {program : Program} {pc : Nat} {state : State} {ptr : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .call none none none (some (.sym sol_get_clock_sysvar))) state)
    (hptr : regGet state.regs .r1 = ptr) :
    StepReduction program state (execGetClockSysvar state ptr) :=
  StepReduction.of_readyOpcodeAt hat
    (step_syscall_get_clock_sysvar_at_ok hat hptr)

theorem step_syscall_log64_at_ok
    {program : Program} {pc : Nat} {state : State}
    (hat : ReadyOpcodeAt program pc
      (inst .call none none none (some (.sym sol_log_64_))) state) :
    step program state = .ok (execLog64 state) :=
  step_syscall_log64_ok hat.stepReady hat.currentInst?

theorem reduction_syscall_log64_at_ok
    {program : Program} {pc : Nat} {state : State}
    (hat : ReadyOpcodeAt program pc
      (inst .call none none none (some (.sym sol_log_64_))) state) :
    StepReduction program state (execLog64 state) :=
  StepReduction.of_readyOpcodeAt hat (step_syscall_log64_at_ok hat)

theorem step_exit_at_ok
    {program : Program} {pc : Nat} {state : State} {r0 : Nat}
    (hat : ReadyOpcodeAt program pc (inst .exit none none none none) state)
    (hr0 : regGet state.regs .r0 = r0) :
    step program state = .ok (execExit state r0) :=
  step_exit_ok hat.stepReady hat.currentInst? hr0

theorem reduction_exit_at_ok
    {program : Program} {pc : Nat} {state : State} {r0 : Nat}
    (hat : ReadyOpcodeAt program pc (inst .exit none none none none) state)
    (hr0 : regGet state.regs .r0 = r0) :
    StepReduction program state (execExit state r0) :=
  StepReduction.of_readyOpcodeAt hat (step_exit_at_ok hat hr0)

theorem step_add64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .add64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (lhs + rhs))) :=
  step_add64_reg_ok hat.stepReady hat.currentInst? hlhs hrhs

theorem reduction_add64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .add64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    StepReduction program state (nextPc (setReg state dst (lhs + rhs))) :=
  StepReduction.of_readyOpcodeAt hat (step_add64_reg_at_ok hat hlhs hrhs)

theorem step_stxdw_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base src : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .stxdw (some base) (some src) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    step program state = .ok (execStore state addr value) :=
  step_stxdw_ok hat.stepReady hat.currentInst? haddr hvalue

theorem reduction_stxdw_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base src : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .stxdw (some base) (some src) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    StepReduction program state (execStore state addr value) :=
  StepReduction.of_readyOpcodeAt hat (step_stxdw_at_ok hat haddr hvalue)

theorem step_and64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .and64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (Nat.land lhs rhs))) :=
  step_and64_reg_ok hat.stepReady hat.currentInst? hlhs hrhs

theorem reduction_and64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .and64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    StepReduction program state (nextPc (setReg state dst (Nat.land lhs rhs))) :=
  StepReduction.of_readyOpcodeAt hat (step_and64_reg_at_ok hat hlhs hrhs)

theorem step_or64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .or64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (Nat.lor lhs rhs))) :=
  step_or64_reg_ok hat.stepReady hat.currentInst? hlhs hrhs

theorem reduction_or64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .or64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    StepReduction program state (nextPc (setReg state dst (Nat.lor lhs rhs))) :=
  StepReduction.of_readyOpcodeAt hat (step_or64_reg_at_ok hat hlhs hrhs)

theorem step_jeq_imm_taken_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jeq (some dst) none (some (.num target)) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs = rhs) :
    step program state = .ok (execJump state target) :=
  step_jeq_imm_taken_ok hat.stepReady hat.currentInst? hlhs hcond

theorem reduction_jeq_imm_taken_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jeq (some dst) none (some (.num target)) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs = rhs) :
    StepReduction program state (execJump state target) :=
  StepReduction.of_readyOpcodeAt hat (step_jeq_imm_taken_at_ok hat hlhs hcond)

theorem step_jeq_imm_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jeq (some dst) none (some (.num target)) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs ≠ rhs) :
    step program state = .ok (nextPc state) :=
  step_jeq_imm_fallthrough_ok hat.stepReady hat.currentInst? hlhs hcond

theorem reduction_jeq_imm_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jeq (some dst) none (some (.num target)) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs ≠ rhs) :
    StepReduction program state (nextPc state) :=
  StepReduction.of_readyOpcodeAt hat (step_jeq_imm_fallthrough_at_ok hat hlhs hcond)

theorem step_jeq_reg_taken_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jeq (some dst) (some src) (some (.num target)) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs = rhs) :
    step program state = .ok (execJump state target) :=
  step_jeq_reg_taken_ok hat.stepReady hat.currentInst? hlhs hrhs hcond

theorem reduction_jeq_reg_taken_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jeq (some dst) (some src) (some (.num target)) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs = rhs) :
    StepReduction program state (execJump state target) :=
  StepReduction.of_readyOpcodeAt hat (step_jeq_reg_taken_at_ok hat hlhs hrhs hcond)

theorem step_jeq_reg_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jeq (some dst) (some src) (some (.num target)) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs ≠ rhs) :
    step program state = .ok (nextPc state) :=
  step_jeq_reg_fallthrough_ok hat.stepReady hat.currentInst? hlhs hrhs hcond

theorem reduction_jeq_reg_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jeq (some dst) (some src) (some (.num target)) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs ≠ rhs) :
    StepReduction program state (nextPc state) :=
  StepReduction.of_readyOpcodeAt hat (step_jeq_reg_fallthrough_at_ok hat hlhs hrhs hcond)

theorem step_jne_imm_taken_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jne (some dst) none (some (.num target)) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs ≠ rhs) :
    step program state = .ok (execJump state target) :=
  step_jne_imm_taken_ok hat.stepReady hat.currentInst? hlhs hcond

theorem reduction_jne_imm_taken_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jne (some dst) none (some (.num target)) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs ≠ rhs) :
    StepReduction program state (execJump state target) :=
  StepReduction.of_readyOpcodeAt hat (step_jne_imm_taken_at_ok hat hlhs hcond)

theorem step_jne_imm_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jne (some dst) none (some (.num target)) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs = rhs) :
    step program state = .ok (nextPc state) :=
  step_jne_imm_fallthrough_ok hat.stepReady hat.currentInst? hlhs hcond

theorem reduction_jne_imm_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jne (some dst) none (some (.num target)) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : lhs = rhs) :
    StepReduction program state (nextPc state) :=
  StepReduction.of_readyOpcodeAt hat (step_jne_imm_fallthrough_at_ok hat hlhs hcond)

theorem step_jne_reg_taken_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jne (some dst) (some src) (some (.num target)) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs ≠ rhs) :
    step program state = .ok (execJump state target) :=
  step_jne_reg_taken_ok hat.stepReady hat.currentInst? hlhs hrhs hcond

theorem reduction_jne_reg_taken_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jne (some dst) (some src) (some (.num target)) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs ≠ rhs) :
    StepReduction program state (execJump state target) :=
  StepReduction.of_readyOpcodeAt hat (step_jne_reg_taken_at_ok hat hlhs hrhs hcond)

theorem step_jne_reg_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jne (some dst) (some src) (some (.num target)) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs = rhs) :
    step program state = .ok (nextPc state) :=
  step_jne_reg_fallthrough_ok hat.stepReady hat.currentInst? hlhs hrhs hcond

theorem reduction_jne_reg_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jne (some dst) (some src) (some (.num target)) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : lhs = rhs) :
    StepReduction program state (nextPc state) :=
  StepReduction.of_readyOpcodeAt hat (step_jne_reg_fallthrough_at_ok hat hlhs hrhs hcond)

/-! ### Lowered-opcode coverage wrappers -/

theorem step_mov32_imm_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .mov32 (some dst) none none (some (.num value))) state) :
    step program state = .ok (execMov64 state dst value) :=
  step_mov32_imm_ok hat.stepReady hat.currentInst?

theorem reduction_mov32_imm_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .mov32 (some dst) none none (some (.num value))) state) :
    StepReduction program state (execMov64 state dst value) :=
  StepReduction.of_readyOpcodeAt hat (step_mov32_imm_at_ok hat)

theorem step_add64_imm_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .add64 (some dst) none none (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs) :
    step program state = .ok (nextPc (setReg state dst (lhs + rhs))) :=
  step_add64_imm_ok hat.stepReady hat.currentInst? hlhs

theorem reduction_add64_imm_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .add64 (some dst) none none (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs) :
    StepReduction program state (nextPc (setReg state dst (lhs + rhs))) :=
  StepReduction.of_readyOpcodeAt hat (step_add64_imm_at_ok hat hlhs)

theorem step_sub64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .sub64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (lhs - rhs))) :=
  step_sub64_reg_ok hat.stepReady hat.currentInst? hlhs hrhs

theorem reduction_sub64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .sub64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    StepReduction program state (nextPc (setReg state dst (lhs - rhs))) :=
  StepReduction.of_readyOpcodeAt hat (step_sub64_reg_at_ok hat hlhs hrhs)

theorem step_sub64_imm_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .sub64 (some dst) none none (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs) :
    step program state = .ok (nextPc (setReg state dst (lhs - rhs))) :=
  step_sub64_imm_ok hat.stepReady hat.currentInst? hlhs

theorem reduction_sub64_imm_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .sub64 (some dst) none none (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs) :
    StepReduction program state (nextPc (setReg state dst (lhs - rhs))) :=
  StepReduction.of_readyOpcodeAt hat (step_sub64_imm_at_ok hat hlhs)

theorem step_mul64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .mul64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (lhs * rhs))) :=
  step_mul64_reg_ok hat.stepReady hat.currentInst? hlhs hrhs

theorem reduction_mul64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .mul64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    StepReduction program state (nextPc (setReg state dst (lhs * rhs))) :=
  StepReduction.of_readyOpcodeAt hat (step_mul64_reg_at_ok hat hlhs hrhs)

theorem step_div64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .div64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hrhs_nonzero : rhs ≠ 0) :
    step program state = .ok (nextPc (setReg state dst (lhs / rhs))) :=
  step_div64_reg_ok hat.stepReady hat.currentInst? hlhs hrhs hrhs_nonzero

theorem reduction_div64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .div64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hrhs_nonzero : rhs ≠ 0) :
    StepReduction program state (nextPc (setReg state dst (lhs / rhs))) :=
  StepReduction.of_readyOpcodeAt hat
    (step_div64_reg_at_ok hat hlhs hrhs hrhs_nonzero)

theorem step_mod64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .mod64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hrhs_nonzero : rhs ≠ 0) :
    step program state = .ok (nextPc (setReg state dst (lhs % rhs))) :=
  step_mod64_reg_ok hat.stepReady hat.currentInst? hlhs hrhs hrhs_nonzero

theorem reduction_mod64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .mod64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hrhs_nonzero : rhs ≠ 0) :
    StepReduction program state (nextPc (setReg state dst (lhs % rhs))) :=
  StepReduction.of_readyOpcodeAt hat
    (step_mod64_reg_at_ok hat hlhs hrhs hrhs_nonzero)

theorem step_lsh64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .lsh64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (Nat.shiftLeft lhs rhs))) :=
  step_lsh64_reg_ok hat.stepReady hat.currentInst? hlhs hrhs

theorem reduction_lsh64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .lsh64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    StepReduction program state (nextPc (setReg state dst (Nat.shiftLeft lhs rhs))) :=
  StepReduction.of_readyOpcodeAt hat (step_lsh64_reg_at_ok hat hlhs hrhs)

theorem step_rsh64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .rsh64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (Nat.shiftRight lhs rhs))) :=
  step_rsh64_reg_ok hat.stepReady hat.currentInst? hlhs hrhs

theorem reduction_rsh64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .rsh64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    StepReduction program state (nextPc (setReg state dst (Nat.shiftRight lhs rhs))) :=
  StepReduction.of_readyOpcodeAt hat (step_rsh64_reg_at_ok hat hlhs hrhs)

theorem step_xor64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .xor64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    step program state = .ok (nextPc (setReg state dst (Nat.xor lhs rhs))) :=
  step_xor64_reg_ok hat.stepReady hat.currentInst? hlhs hrhs

theorem reduction_xor64_reg_at_ok
    {program : Program} {pc : Nat} {state : State} {dst src : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .xor64 (some dst) (some src) none none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs) :
    StepReduction program state (nextPc (setReg state dst (Nat.xor lhs rhs))) :=
  StepReduction.of_readyOpcodeAt hat (step_xor64_reg_at_ok hat hlhs hrhs)

theorem step_xor64_imm_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .xor64 (some dst) none none (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs) :
    step program state = .ok (nextPc (setReg state dst (Nat.xor lhs rhs))) :=
  step_xor64_imm_ok hat.stepReady hat.currentInst? hlhs

theorem reduction_xor64_imm_at_ok
    {program : Program} {pc : Nat} {state : State} {dst : Reg} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .xor64 (some dst) none none (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs) :
    StepReduction program state (nextPc (setReg state dst (Nat.xor lhs rhs))) :=
  StepReduction.of_readyOpcodeAt hat (step_xor64_imm_at_ok hat hlhs)

theorem step_ldxb_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .ldxb (some dst) (some base) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    step program state = .ok (execLoad state dst addr value) :=
  step_ldxb_ok hat.stepReady hat.currentInst? haddr hvalue

theorem reduction_ldxb_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .ldxb (some dst) (some base) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    StepReduction program state (execLoad state dst addr value) :=
  StepReduction.of_readyOpcodeAt hat (step_ldxb_at_ok hat haddr hvalue)

theorem step_ldxh_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .ldxh (some dst) (some base) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    step program state = .ok (execLoad state dst addr value) :=
  step_ldxh_ok hat.stepReady hat.currentInst? haddr hvalue

theorem reduction_ldxh_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .ldxh (some dst) (some base) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    StepReduction program state (execLoad state dst addr value) :=
  StepReduction.of_readyOpcodeAt hat (step_ldxh_at_ok hat haddr hvalue)

theorem step_ldxw_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .ldxw (some dst) (some base) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    step program state = .ok (execLoad state dst addr value) :=
  step_ldxw_ok hat.stepReady hat.currentInst? haddr hvalue

theorem reduction_ldxw_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .ldxw (some dst) (some base) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : state.memory.read addr = value) :
    StepReduction program state (execLoad state dst addr value) :=
  StepReduction.of_readyOpcodeAt hat (step_ldxw_at_ok hat haddr hvalue)

theorem step_stdw_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .stdw (some base) none (some (.num off)) (some (.num value))) state)
    (haddr : memoryAddress state base off = addr) :
    step program state = .ok (execStore state addr value) :=
  step_stdw_ok hat.stepReady hat.currentInst? haddr

theorem reduction_stdw_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .stdw (some base) none (some (.num off)) (some (.num value))) state)
    (haddr : memoryAddress state base off = addr) :
    StepReduction program state (execStore state addr value) :=
  StepReduction.of_readyOpcodeAt hat (step_stdw_at_ok hat haddr)

theorem step_stb_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .stb (some base) none (some (.num off)) (some (.num value))) state)
    (haddr : memoryAddress state base off = addr) :
    step program state = .ok (execStore state addr value) :=
  step_stb_ok hat.stepReady hat.currentInst? haddr

theorem reduction_stb_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .stb (some base) none (some (.num off)) (some (.num value))) state)
    (haddr : memoryAddress state base off = addr) :
    StepReduction program state (execStore state addr value) :=
  StepReduction.of_readyOpcodeAt hat (step_stb_at_ok hat haddr)

theorem step_sth_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .sth (some base) none (some (.num off)) (some (.num value))) state)
    (haddr : memoryAddress state base off = addr) :
    step program state = .ok (execStore state addr value) :=
  step_sth_ok hat.stepReady hat.currentInst? haddr

theorem reduction_sth_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .sth (some base) none (some (.num off)) (some (.num value))) state)
    (haddr : memoryAddress state base off = addr) :
    StepReduction program state (execStore state addr value) :=
  StepReduction.of_readyOpcodeAt hat (step_sth_at_ok hat haddr)

theorem step_stw_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .stw (some base) none (some (.num off)) (some (.num value))) state)
    (haddr : memoryAddress state base off = addr) :
    step program state = .ok (execStore state addr value) :=
  step_stw_ok hat.stepReady hat.currentInst? haddr

theorem reduction_stw_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .stw (some base) none (some (.num off)) (some (.num value))) state)
    (haddr : memoryAddress state base off = addr) :
    StepReduction program state (execStore state addr value) :=
  StepReduction.of_readyOpcodeAt hat (step_stw_at_ok hat haddr)

theorem step_stxb_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base src : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .stxb (some base) (some src) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    step program state = .ok (execStore state addr value) :=
  step_stxb_ok hat.stepReady hat.currentInst? haddr hvalue

theorem reduction_stxb_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base src : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .stxb (some base) (some src) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    StepReduction program state (execStore state addr value) :=
  StepReduction.of_readyOpcodeAt hat (step_stxb_at_ok hat haddr hvalue)

theorem step_stxh_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base src : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .stxh (some base) (some src) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    step program state = .ok (execStore state addr value) :=
  step_stxh_ok hat.stepReady hat.currentInst? haddr hvalue

theorem reduction_stxh_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base src : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .stxh (some base) (some src) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    StepReduction program state (execStore state addr value) :=
  StepReduction.of_readyOpcodeAt hat (step_stxh_at_ok hat haddr hvalue)

theorem step_stxw_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base src : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .stxw (some base) (some src) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    step program state = .ok (execStore state addr value) :=
  step_stxw_ok hat.stepReady hat.currentInst? haddr hvalue

theorem reduction_stxw_at_ok
    {program : Program} {pc : Nat} {state : State}
    {base src : Reg} {off addr value : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .stxw (some base) (some src) (some (.num off)) none) state)
    (haddr : memoryAddress state base off = addr)
    (hvalue : regGet state.regs src = value) :
    StepReduction program state (execStore state addr value) :=
  StepReduction.of_readyOpcodeAt hat (step_stxw_at_ok hat haddr hvalue)

theorem step_jge_imm_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jge (some dst) none (some off) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jge lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_jge_imm_taken_ok hat.stepReady hat.currentInst? hlhs htarget hcond

theorem reduction_jge_imm_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jge (some dst) none (some off) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jge lhs rhs = .ok true) :
    StepReduction program state (execJump state target) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jge_imm_taken_at_ok hat hlhs htarget hcond)

theorem step_jge_imm_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jge (some dst) none (some off) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : jumpCondition .jge lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_jge_imm_fallthrough_ok hat.stepReady hat.currentInst? hlhs hcond

theorem reduction_jge_imm_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jge (some dst) none (some off) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : jumpCondition .jge lhs rhs = .ok false) :
    StepReduction program state (nextPc state) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jge_imm_fallthrough_at_ok hat hlhs hcond)

theorem step_jge_reg_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jge (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jge lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_jge_reg_taken_ok hat.stepReady hat.currentInst? hlhs hrhs htarget hcond

theorem reduction_jge_reg_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jge (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jge lhs rhs = .ok true) :
    StepReduction program state (execJump state target) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jge_reg_taken_at_ok hat hlhs hrhs htarget hcond)

theorem step_jge_reg_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jge (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jge lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_jge_reg_fallthrough_ok hat.stepReady hat.currentInst? hlhs hrhs hcond

theorem reduction_jge_reg_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jge (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jge lhs rhs = .ok false) :
    StepReduction program state (nextPc state) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jge_reg_fallthrough_at_ok hat hlhs hrhs hcond)

theorem step_jlt_imm_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jlt (some dst) none (some off) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jlt lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_jlt_imm_taken_ok hat.stepReady hat.currentInst? hlhs htarget hcond

theorem reduction_jlt_imm_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jlt (some dst) none (some off) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jlt lhs rhs = .ok true) :
    StepReduction program state (execJump state target) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jlt_imm_taken_at_ok hat hlhs htarget hcond)

theorem step_jlt_imm_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jlt (some dst) none (some off) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : jumpCondition .jlt lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_jlt_imm_fallthrough_ok hat.stepReady hat.currentInst? hlhs hcond

theorem reduction_jlt_imm_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jlt (some dst) none (some off) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : jumpCondition .jlt lhs rhs = .ok false) :
    StepReduction program state (nextPc state) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jlt_imm_fallthrough_at_ok hat hlhs hcond)

theorem step_jlt_reg_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jlt (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jlt lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_jlt_reg_taken_ok hat.stepReady hat.currentInst? hlhs hrhs htarget hcond

theorem reduction_jlt_reg_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jlt (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jlt lhs rhs = .ok true) :
    StepReduction program state (execJump state target) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jlt_reg_taken_at_ok hat hlhs hrhs htarget hcond)

theorem step_jlt_reg_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jlt (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jlt lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_jlt_reg_fallthrough_ok hat.stepReady hat.currentInst? hlhs hrhs hcond

theorem reduction_jlt_reg_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jlt (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jlt lhs rhs = .ok false) :
    StepReduction program state (nextPc state) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jlt_reg_fallthrough_at_ok hat hlhs hrhs hcond)

theorem step_jgt_reg_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jgt (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jgt lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_jgt_reg_taken_ok hat.stepReady hat.currentInst? hlhs hrhs htarget hcond

theorem reduction_jgt_reg_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jgt (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jgt lhs rhs = .ok true) :
    StepReduction program state (execJump state target) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jgt_reg_taken_at_ok hat hlhs hrhs htarget hcond)

theorem step_jgt_reg_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jgt (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jgt lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_jgt_reg_fallthrough_ok hat.stepReady hat.currentInst? hlhs hrhs hcond

theorem reduction_jgt_reg_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jgt (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jgt lhs rhs = .ok false) :
    StepReduction program state (nextPc state) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jgt_reg_fallthrough_at_ok hat hlhs hrhs hcond)

theorem step_jle_reg_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jle (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jle lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_jle_reg_taken_ok hat.stepReady hat.currentInst? hlhs hrhs htarget hcond

theorem reduction_jle_reg_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jle (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jle lhs rhs = .ok true) :
    StepReduction program state (execJump state target) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jle_reg_taken_at_ok hat hlhs hrhs htarget hcond)

theorem step_jle_reg_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jle (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jle lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_jle_reg_fallthrough_ok hat.stepReady hat.currentInst? hlhs hrhs hcond

theorem reduction_jle_reg_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jle (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jle lhs rhs = .ok false) :
    StepReduction program state (nextPc state) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jle_reg_fallthrough_at_ok hat hlhs hrhs hcond)

theorem step_jset_imm_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jset (some dst) none (some off) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jset lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_jset_imm_taken_ok hat.stepReady hat.currentInst? hlhs htarget hcond

theorem reduction_jset_imm_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jset (some dst) none (some off) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jset lhs rhs = .ok true) :
    StepReduction program state (execJump state target) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jset_imm_taken_at_ok hat hlhs htarget hcond)

theorem step_jset_imm_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jset (some dst) none (some off) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : jumpCondition .jset lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_jset_imm_fallthrough_ok hat.stepReady hat.currentInst? hlhs hcond

theorem reduction_jset_imm_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jset (some dst) none (some off) (some (.num rhs))) state)
    (hlhs : regGet state.regs dst = lhs)
    (hcond : jumpCondition .jset lhs rhs = .ok false) :
    StepReduction program state (nextPc state) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jset_imm_fallthrough_at_ok hat hlhs hcond)

theorem step_jset_reg_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jset (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jset lhs rhs = .ok true) :
    step program state = .ok (execJump state target) :=
  step_jset_reg_taken_ok hat.stepReady hat.currentInst? hlhs hrhs htarget hcond

theorem reduction_jset_reg_taken_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs target : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jset (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (htarget : resolveJumpTarget program (some off) = .ok target)
    (hcond : jumpCondition .jset lhs rhs = .ok true) :
    StepReduction program state (execJump state target) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jset_reg_taken_at_ok hat hlhs hrhs htarget hcond)

theorem step_jset_reg_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jset (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jset lhs rhs = .ok false) :
    step program state = .ok (nextPc state) :=
  step_jset_reg_fallthrough_ok hat.stepReady hat.currentInst? hlhs hrhs hcond

theorem reduction_jset_reg_fallthrough_at_ok
    {program : Program} {pc : Nat} {state : State}
    {dst src : Reg} {off : MemOff} {lhs rhs : Nat}
    (hat : ReadyOpcodeAt program pc
      (inst .jset (some dst) (some src) (some off) none) state)
    (hlhs : regGet state.regs dst = lhs)
    (hrhs : regGet state.regs src = rhs)
    (hcond : jumpCondition .jset lhs rhs = .ok false) :
    StepReduction program state (nextPc state) :=
  StepReduction.of_readyOpcodeAt hat
    (step_jset_reg_fallthrough_at_ok hat hlhs hrhs hcond)

/-! ### Lowerer opcode coverage gate

`loweredOpcodeSet` is the contract-agnostic opcode surface that
`SbpfAsm.lowerModule` and Solana extension helpers can currently emit through
static instructions, `assignOpcode`, scalar parameter loads, comparison
lowering, and byte/halfword packing. `call` here is opcode-level coverage;
syscall-name support remains a separate capability gate.
-/

def loweredOpcodeSet : List Opcode := [
  .mov64, .mov32,
  .lddw, .ldxb, .ldxh, .ldxw, .ldxdw,
  .stb, .sth, .stw, .stdw,
  .stxb, .stxh, .stxw, .stxdw,
  .add64, .sub64, .mul64, .div64, .mod64,
  .or64, .and64, .lsh64, .rsh64, .xor64,
  .ja, .jeq, .jne, .jgt, .jge, .jlt, .jle, .jset,
  .call, .exit
]

def loweredOpcodeCoveredBySbpfExec : Opcode → Bool
  | .mov64 | .mov32
  | .lddw | .ldxb | .ldxh | .ldxw | .ldxdw
  | .stb | .sth | .stw | .stdw
  | .stxb | .stxh | .stxw | .stxdw
  | .add64 | .sub64 | .mul64 | .div64 | .mod64
  | .or64 | .and64 | .lsh64 | .rsh64 | .xor64
  | .ja | .jeq | .jne | .jgt | .jge | .jlt | .jle | .jset
  | .call | .exit => true
  | _ => false

theorem loweredOpcodeSet_covered_by_sbpfExec :
    loweredOpcodeSet.all loweredOpcodeCoveredBySbpfExec = true := by
  native_decide

end ProofForge.Backend.Solana.SbpfExec
