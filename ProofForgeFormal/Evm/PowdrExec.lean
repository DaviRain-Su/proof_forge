import ProofForgeFormal.Evm.PowdrAdapter

/-! Contract-agnostic symbolic execution helpers for powdr EVM.

This module is deliberately free of contract-specific names.  It factors the
repeated top-level `stepFE` branches (running state, precompile dispatch,
stack-cap check, and base-gas check) into reusable opcode dispatch lemmas.
Contract refinements should compose these lemmas instead of hand-deriving
`runBytecode` one bytecode instruction at a time.
-/

namespace ProofForge.Backend.Evm.PowdrExec

set_option linter.unusedSimpArgs false

abbrev State := ProofForge.Backend.Evm.PowdrAdapter.State
abbrev ObservableStep := ProofForge.Backend.Evm.PowdrAdapter.ObservableStep
abbrev StepFEPath := ProofForge.Backend.Evm.PowdrAdapter.StepFEPath
abbrev UInt256 := EvmSemantics.UInt256
abbrev Operation := EvmSemantics.Operation

def CodePcAt (code : ByteArray) (pc : Nat) (state : State) : Prop :=
  state.executionEnv.code = code ∧
    state.pc = EvmSemantics.UInt256.ofNat pc

structure DecodedOpcodeAt
    (code : ByteArray) (pc : Nat)
    (op : Operation) (argOpt : Option (EvmSemantics.UInt256 × Nat))
    (state : State) : Prop where
  codePc : CodePcAt code pc state
  pcNat : (EvmSemantics.UInt256.ofNat pc).toNat = pc
  decodedAt : EvmSemantics.EVM.Decode.decodeAt code pc = some (op, argOpt)
  available : op.availableInFork state.executionEnv.fork = true

def runSteps : State → Nat → Except String (State × Array ObservableStep) :=
  ProofForge.Backend.Evm.PowdrAdapter.runBytecode

theorem runSteps_zero (state : State) :
    runSteps state 0 = .ok (state, #[]) := rfl

theorem decoded_of_code_pc
    {state : State} {code : ByteArray} {pc : Nat}
    {op : Operation} {argOpt : Option (EvmSemantics.UInt256 × Nat)}
    (hcode : state.executionEnv.code = code)
    (hpc : state.pc = EvmSemantics.UInt256.ofNat pc)
    (hpcNat : (EvmSemantics.UInt256.ofNat pc).toNat = pc)
    (hdecode : EvmSemantics.EVM.Decode.decodeAt code pc = some (op, argOpt))
    (havailable : op.availableInFork state.executionEnv.fork = true) :
    state.decoded = some (op, argOpt) := by
  unfold EvmSemantics.EVM.State.decoded
  rw [hcode, hpc, hpcNat, hdecode]
  change (if op.availableInFork state.executionEnv.fork then some (op, argOpt)
    else none) = some (op, argOpt)
  simp [havailable]

theorem decoded_of_codePcAt
    {state : State} {code : ByteArray} {pc : Nat}
    {op : Operation} {argOpt : Option (EvmSemantics.UInt256 × Nat)}
    (hat : CodePcAt code pc state)
    (hpcNat : (EvmSemantics.UInt256.ofNat pc).toNat = pc)
    (hdecode : EvmSemantics.EVM.Decode.decodeAt code pc = some (op, argOpt))
    (havailable : op.availableInFork state.executionEnv.fork = true) :
    state.decoded = some (op, argOpt) := by
  exact decoded_of_code_pc hat.1 hat.2 hpcNat hdecode havailable

theorem DecodedOpcodeAt.decoded
    {state : State} {code : ByteArray} {pc : Nat}
    {op : Operation} {argOpt : Option (EvmSemantics.UInt256 × Nat)}
    (hat : DecodedOpcodeAt code pc op argOpt state) :
    state.decoded = some (op, argOpt) := by
  exact decoded_of_codePcAt hat.codePc hat.pcNat hat.decodedAt hat.available

theorem validJumpDest_of_code_eq
    {state : State} {code : ByteArray} {dest : Nat}
    (hcode : state.executionEnv.code = code)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest code dest = true) :
    EvmSemantics.EVM.Decode.isValidJumpDest state.executionEnv.code dest = true := by
  rw [hcode]
  exact hvalid

theorem runSteps_stepFE_succ
    {state nextState finalState : State}
    {observations : Array ObservableStep} {fuel : Nat}
    (hrunning : state.halt = .Running)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState)
    (hrun : runSteps nextState fuel = .ok (finalState, observations)) :
    runSteps state (fuel + 1) = .ok (finalState, observations) := by
  exact ProofForge.Backend.Evm.PowdrAdapter.runBytecode_stepFE_succ
    hrunning hstep hrun

theorem stepFE_ok_state_eq {state expected actual : State}
    (hexpected : EvmSemantics.EVM.stepFE state = .ok expected)
    (hactual : EvmSemantics.EVM.stepFE state = .ok actual) :
    actual = expected := by
  rw [hactual] at hexpected
  cases hexpected
  rfl

theorem stepFE_ok_stack_eq {state expected actual : State}
    (hexpected : EvmSemantics.EVM.stepFE state = .ok expected)
    (hactual : EvmSemantics.EVM.stepFE state = .ok actual) :
    actual.stack = expected.stack := by
  rw [stepFE_ok_state_eq hexpected hactual]

theorem stepFE_ok_callStack_eq {state expected actual : State}
    (hexpected : EvmSemantics.EVM.stepFE state = .ok expected)
    (hactual : EvmSemantics.EVM.stepFE state = .ok actual) :
    actual.callStack = expected.callStack := by
  rw [stepFE_ok_state_eq hexpected hactual]

theorem stepFE_ok_pc_eq {state expected actual : State}
    (hexpected : EvmSemantics.EVM.stepFE state = .ok expected)
    (hactual : EvmSemantics.EVM.stepFE state = .ok actual) :
    actual.pc = expected.pc := by
  rw [stepFE_ok_state_eq hexpected hactual]

theorem stepFE_ok_halt_eq {state expected actual : State}
    (hexpected : EvmSemantics.EVM.stepFE state = .ok expected)
    (hactual : EvmSemantics.EVM.stepFE state = .ok actual) :
    actual.halt = expected.halt := by
  rw [stepFE_ok_state_eq hexpected hactual]

theorem stepFE_ok_executionEnv_eq {state expected actual : State}
    (hexpected : EvmSemantics.EVM.stepFE state = .ok expected)
    (hactual : EvmSemantics.EVM.stepFE state = .ok actual) :
    actual.executionEnv = expected.executionEnv := by
  rw [stepFE_ok_state_eq hexpected hactual]

theorem stepFE_ok_accountMap_eq {state expected actual : State}
    (hexpected : EvmSemantics.EVM.stepFE state = .ok expected)
    (hactual : EvmSemantics.EVM.stepFE state = .ok actual) :
    actual.accountMap = expected.accountMap := by
  rw [stepFE_ok_state_eq hexpected hactual]

theorem stepFE_ok_memory_eq {state expected actual : State}
    (hexpected : EvmSemantics.EVM.stepFE state = .ok expected)
    (hactual : EvmSemantics.EVM.stepFE state = .ok actual) :
    actual.memory = expected.memory := by
  rw [stepFE_ok_state_eq hexpected hactual]

theorem runSteps_of_stepFEPath_done {fuel : Nat} {state finalState : State}
    (path : StepFEPath state fuel finalState) :
    runSteps state fuel = .ok (finalState, (#[] : Array ObservableStep)) := by
  exact ProofForge.Backend.Evm.PowdrAdapter.runBytecode_of_stepFEPath_done path

structure ExecutionSegment
    (fuel : Nat) (post : State → State → Prop)
    (state finalState : State) : Prop where
  path : StepFEPath state fuel finalState
  postcondition : post state finalState

theorem runSteps_of_executionSegment
    {fuel : Nat} {post : State → State → Prop} {state finalState : State}
    (segment : ExecutionSegment fuel post state finalState) :
    runSteps state fuel =
      .ok (finalState, (#[] : Array ObservableStep)) := by
  exact runSteps_of_stepFEPath_done segment.path

theorem executionSegment_of_stepFEPath
    {fuel : Nat} {post : State → State → Prop} {state finalState : State}
    (path : StepFEPath state fuel finalState)
    (hpost : post state finalState) :
    ExecutionSegment fuel post state finalState :=
  { path := path
    postcondition := hpost }

theorem executionSegment_single
    {post : State → State → Prop} {state nextState : State}
    (hrunning : state.halt = .Running)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState)
    (hpost : post state nextState) :
    ExecutionSegment 1 post state nextState :=
  { path :=
      ProofForge.Backend.Evm.PowdrAdapter.StepFEPath.cons
        hrunning hstep
        (ProofForge.Backend.Evm.PowdrAdapter.StepFEPath.nil nextState)
    postcondition := hpost }

theorem executionSegment_append
    {prefixFuel suffixFuel : Nat}
    {prefixPost suffixPost combinedPost : State → State → Prop}
    {state midState finalState : State}
    (combine :
      prefixPost state midState → suffixPost midState finalState →
        combinedPost state finalState)
    (leftSegment :
      ExecutionSegment prefixFuel prefixPost state midState)
    (rightSegment :
      ExecutionSegment suffixFuel suffixPost midState finalState) :
    ExecutionSegment (prefixFuel + suffixFuel) combinedPost state finalState :=
  { path :=
      ProofForge.Backend.Evm.PowdrAdapter.stepFEPath_append
        leftSegment.path rightSegment.path
    postcondition :=
      combine leftSegment.postcondition rightSegment.postcondition }

structure SegmentProvider
    (pre : State → Prop) (fuel : Nat)
    (post : State → State → Prop) : Prop where
  segment :
    ∀ {state}, pre state →
      ∃ finalState, ExecutionSegment fuel post state finalState

theorem runSteps_post_of_segmentProvider
    {pre : State → Prop} {fuel : Nat}
    {post : State → State → Prop} {state : State}
    (provider : SegmentProvider pre fuel post) (hpre : pre state) :
    ∃ finalState,
      runSteps state fuel =
        .ok (finalState, (#[] : Array ObservableStep)) ∧
      post state finalState := by
  obtain ⟨finalState, segment⟩ := provider.segment hpre
  exact ⟨finalState, runSteps_of_executionSegment segment,
    segment.postcondition⟩

theorem stepFEPath_single {state nextState : State}
    (hrunning : state.halt = .Running)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    StepFEPath state 1 nextState := by
  exact ProofForge.Backend.Evm.PowdrAdapter.StepFEPath.cons
    hrunning hstep
    (ProofForge.Backend.Evm.PowdrAdapter.StepFEPath.nil nextState)

theorem stepFEPath_append {state midState finalState : State}
    {prefixFuel suffixFuel : Nat}
    (prefixPath : StepFEPath state prefixFuel midState)
    (suffixPath : StepFEPath midState suffixFuel finalState) :
    StepFEPath state (prefixFuel + suffixFuel) finalState := by
  exact ProofForge.Backend.Evm.PowdrAdapter.stepFEPath_append
    prefixPath suffixPath

structure StepFEReduction (state nextState : State) : Prop where
  running : state.halt = .Running
  step : EvmSemantics.EVM.stepFE state = .ok nextState

theorem StepFEReduction.of_step
    {state nextState : State}
    (hrunning : state.halt = .Running)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    StepFEReduction state nextState :=
  { running := hrunning
    step := hstep }

theorem StepFEReduction.path
    {state nextState : State}
    (reduction : StepFEReduction state nextState) :
    StepFEPath state 1 nextState := by
  exact stepFEPath_single reduction.running reduction.step

theorem StepFEReduction.executionSegment
    {post : State → State → Prop} {state nextState : State}
    (reduction : StepFEReduction state nextState)
    (hpost : post state nextState) :
    ExecutionSegment 1 post state nextState := by
  exact executionSegment_single reduction.running reduction.step hpost

inductive StepFEReductionChain : State → Nat → State → Prop where
  | nil (state : State) : StepFEReductionChain state 0 state
  | cons {state nextState finalState : State} {fuel : Nat}
      (head : StepFEReduction state nextState)
      (tail : StepFEReductionChain nextState fuel finalState) :
      StepFEReductionChain state (fuel + 1) finalState

theorem StepFEReductionChain.path
    {state finalState : State} {fuel : Nat}
    (chain : StepFEReductionChain state fuel finalState) :
    StepFEPath state fuel finalState := by
  induction chain with
  | nil state =>
      exact .nil state
  | cons head tail ih =>
      exact .cons head.running head.step ih

theorem StepFEReductionChain.of_stepFEPath
    {state finalState : State} {fuel : Nat}
    (path : StepFEPath state fuel finalState) :
    StepFEReductionChain state fuel finalState := by
  induction path with
  | nil state =>
      exact .nil state
  | cons hrunning hstep tail ih =>
      exact .cons (StepFEReduction.of_step hrunning hstep) ih

theorem StepFEReductionChain.append
    {state midState finalState : State} {prefixFuel suffixFuel : Nat}
    (leftChain : StepFEReductionChain state prefixFuel midState)
    (suffix : StepFEReductionChain midState suffixFuel finalState) :
    StepFEReductionChain state (prefixFuel + suffixFuel) finalState := by
  induction leftChain with
  | nil state =>
      simpa using suffix
  | cons head tail ih =>
      have htail := ih suffix
      simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
        StepFEReductionChain.cons head htail

theorem StepFEReductionChain.single
    {state nextState : State}
    (reduction : StepFEReduction state nextState) :
    StepFEReductionChain state 1 nextState := by
  simpa using
    StepFEReductionChain.cons reduction
      (StepFEReductionChain.nil nextState)

theorem runSteps_of_reductionChain
    {fuel : Nat} {state finalState : State}
    (chain : StepFEReductionChain state fuel finalState) :
    runSteps state fuel = .ok (finalState, (#[] : Array ObservableStep)) := by
  exact runSteps_of_stepFEPath_done chain.path

theorem executionSegment_of_reductionChain
    {fuel : Nat} {post : State → State → Prop} {state finalState : State}
    (chain : StepFEReductionChain state fuel finalState)
    (hpost : post state finalState) :
    ExecutionSegment fuel post state finalState := by
  exact executionSegment_of_stepFEPath chain.path hpost

structure ReductionChainProvider
    (pre : State → Prop) (fuel : Nat)
    (post : State → State → Prop) : Prop where
  chain :
    ∀ {state}, pre state →
      ∃ finalState,
        StepFEReductionChain state fuel finalState ∧
          post state finalState

theorem reductionChainProvider_single
    {pre : State → Prop} {post : State → State → Prop}
    (nextState : ∀ state, pre state → State)
    (reduction :
      ∀ {state} (hpre : pre state),
        StepFEReduction state (nextState state hpre))
    (postcondition :
      ∀ {state} (hpre : pre state),
        post state (nextState state hpre)) :
    ReductionChainProvider pre 1 post where
  chain := by
    intro state hpre
    exact ⟨nextState state hpre,
      StepFEReductionChain.single (reduction hpre),
      postcondition hpre⟩

theorem reductionChainProvider_single_of_exists
    {pre : State → Prop} {post : State → State → Prop}
    (step :
      ∀ {state}, pre state →
        ∃ nextState,
          StepFEReduction state nextState ∧
            post state nextState) :
    ReductionChainProvider pre 1 post where
  chain := by
    intro state hpre
    obtain ⟨nextState, reduction, hpost⟩ := step hpre
    exact ⟨nextState, StepFEReductionChain.single reduction, hpost⟩

theorem reductionChainProvider_append
    {leftPre rightPre : State → Prop}
    {leftFuel rightFuel : Nat}
    {leftPost rightPost combinedPost : State → State → Prop}
    (leftProvider :
      ReductionChainProvider leftPre leftFuel leftPost)
    (rightProvider :
      ReductionChainProvider rightPre rightFuel rightPost)
    (rightPre_of_leftPost :
      ∀ {state midState},
        leftPre state → leftPost state midState → rightPre midState)
    (combine :
      ∀ {state midState finalState},
        leftPre state →
        leftPost state midState →
        rightPost midState finalState →
        combinedPost state finalState) :
    ReductionChainProvider leftPre (leftFuel + rightFuel) combinedPost where
  chain := by
    intro state hleftPre
    obtain ⟨midState, leftChain, hleftPost⟩ :=
      leftProvider.chain hleftPre
    obtain ⟨finalState, rightChain, hrightPost⟩ :=
      rightProvider.chain
        (rightPre_of_leftPost hleftPre hleftPost)
    exact ⟨finalState,
      StepFEReductionChain.append leftChain rightChain,
      combine hleftPre hleftPost hrightPost⟩

theorem segmentProvider_of_reductionChainProvider
    {pre : State → Prop} {fuel : Nat}
    {post : State → State → Prop}
    (provider : ReductionChainProvider pre fuel post) :
    SegmentProvider pre fuel post where
  segment := by
    intro state hpre
    obtain ⟨finalState, chain, hpost⟩ := provider.chain hpre
    exact ⟨finalState,
      executionSegment_of_reductionChain chain hpost⟩

theorem runSteps_post_of_reductionChainProvider
    {pre : State → Prop} {fuel : Nat}
    {post : State → State → Prop} {state : State}
    (provider : ReductionChainProvider pre fuel post) (hpre : pre state) :
    ∃ finalState,
      runSteps state fuel =
        .ok (finalState, (#[] : Array ObservableStep)) ∧
      post state finalState := by
  obtain ⟨finalState, chain, hpost⟩ := provider.chain hpre
  exact ⟨finalState, runSteps_of_reductionChain chain, hpost⟩

theorem stepFEPath_two {s0 s1 s2 : State}
    (hr0 : s0.halt = .Running)
    (h0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hr1 : s1.halt = .Running)
    (h1 : EvmSemantics.EVM.stepFE s1 = .ok s2) :
    StepFEPath s0 2 s2 := by
  exact .cons hr0 h0 (.cons hr1 h1 (.nil s2))

theorem stepFEPath_three {s0 s1 s2 s3 : State}
    (hr0 : s0.halt = .Running)
    (h0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hr1 : s1.halt = .Running)
    (h1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hr2 : s2.halt = .Running)
    (h2 : EvmSemantics.EVM.stepFE s2 = .ok s3) :
    StepFEPath s0 3 s3 := by
  exact .cons hr0 h0 (.cons hr1 h1 (.cons hr2 h2 (.nil s3)))

theorem stepFEPath_four {s0 s1 s2 s3 s4 : State}
    (hr0 : s0.halt = .Running)
    (h0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hr1 : s1.halt = .Running)
    (h1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hr2 : s2.halt = .Running)
    (h2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hr3 : s3.halt = .Running)
    (h3 : EvmSemantics.EVM.stepFE s3 = .ok s4) :
    StepFEPath s0 4 s4 := by
  exact .cons hr0 h0
    (.cons hr1 h1 (.cons hr2 h2 (.cons hr3 h3 (.nil s4))))

theorem stepFEPath_five {s0 s1 s2 s3 s4 s5 : State}
    (hr0 : s0.halt = .Running)
    (h0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hr1 : s1.halt = .Running)
    (h1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hr2 : s2.halt = .Running)
    (h2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hr3 : s3.halt = .Running)
    (h3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hr4 : s4.halt = .Running)
    (h4 : EvmSemantics.EVM.stepFE s4 = .ok s5) :
    StepFEPath s0 5 s5 := by
  exact .cons hr0 h0
    (.cons hr1 h1
      (.cons hr2 h2 (.cons hr3 h3 (.cons hr4 h4 (.nil s5)))))

theorem stepFEPath_six {s0 s1 s2 s3 s4 s5 s6 : State}
    (hr0 : s0.halt = .Running)
    (h0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hr1 : s1.halt = .Running)
    (h1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hr2 : s2.halt = .Running)
    (h2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hr3 : s3.halt = .Running)
    (h3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hr4 : s4.halt = .Running)
    (h4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hr5 : s5.halt = .Running)
    (h5 : EvmSemantics.EVM.stepFE s5 = .ok s6) :
    StepFEPath s0 6 s6 := by
  exact .cons hr0 h0
    (.cons hr1 h1
      (.cons hr2 h2
        (.cons hr3 h3 (.cons hr4 h4 (.cons hr5 h5 (.nil s6))))))

theorem stepFEPath_twelve
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 : State}
    (hr0 : s0.halt = .Running)
    (h0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hr1 : s1.halt = .Running)
    (h1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hr2 : s2.halt = .Running)
    (h2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hr3 : s3.halt = .Running)
    (h3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hr4 : s4.halt = .Running)
    (h4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hr5 : s5.halt = .Running)
    (h5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hr6 : s6.halt = .Running)
    (h6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hr7 : s7.halt = .Running)
    (h7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hr8 : s8.halt = .Running)
    (h8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hr9 : s9.halt = .Running)
    (h9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hr10 : s10.halt = .Running)
    (h10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hr11 : s11.halt = .Running)
    (h11 : EvmSemantics.EVM.stepFE s11 = .ok s12) :
    StepFEPath s0 12 s12 := by
  have hfirst : StepFEPath s0 6 s6 :=
    stepFEPath_six hr0 h0 hr1 h1 hr2 h2 hr3 h3 hr4 h4 hr5 h5
  have hsecond : StepFEPath s6 6 s12 :=
    stepFEPath_six hr6 h6 hr7 h7 hr8 h8 hr9 h9 hr10 h10 hr11 h11
  simpa using stepFEPath_append hfirst hsecond

theorem stepFEReductionChain_two {s0 s1 s2 : State}
    (r0 : StepFEReduction s0 s1)
    (r1 : StepFEReduction s1 s2) :
    StepFEReductionChain s0 2 s2 := by
  exact .cons r0 (.cons r1 (.nil s2))

theorem stepFEReductionChain_three {s0 s1 s2 s3 : State}
    (r0 : StepFEReduction s0 s1)
    (r1 : StepFEReduction s1 s2)
    (r2 : StepFEReduction s2 s3) :
    StepFEReductionChain s0 3 s3 := by
  exact .cons r0 (.cons r1 (.cons r2 (.nil s3)))

theorem stepFEReductionChain_four {s0 s1 s2 s3 s4 : State}
    (r0 : StepFEReduction s0 s1)
    (r1 : StepFEReduction s1 s2)
    (r2 : StepFEReduction s2 s3)
    (r3 : StepFEReduction s3 s4) :
    StepFEReductionChain s0 4 s4 := by
  exact .cons r0 (.cons r1 (.cons r2 (.cons r3 (.nil s4))))

theorem stepFEReductionChain_five {s0 s1 s2 s3 s4 s5 : State}
    (r0 : StepFEReduction s0 s1)
    (r1 : StepFEReduction s1 s2)
    (r2 : StepFEReduction s2 s3)
    (r3 : StepFEReduction s3 s4)
    (r4 : StepFEReduction s4 s5) :
    StepFEReductionChain s0 5 s5 := by
  exact .cons r0 (.cons r1 (.cons r2 (.cons r3 (.cons r4 (.nil s5)))))

theorem stepFEReductionChain_six {s0 s1 s2 s3 s4 s5 s6 : State}
    (r0 : StepFEReduction s0 s1)
    (r1 : StepFEReduction s1 s2)
    (r2 : StepFEReduction s2 s3)
    (r3 : StepFEReduction s3 s4)
    (r4 : StepFEReduction s4 s5)
    (r5 : StepFEReduction s5 s6) :
    StepFEReductionChain s0 6 s6 := by
  exact .cons r0
    (.cons r1 (.cons r2 (.cons r3 (.cons r4 (.cons r5 (.nil s6))))))

theorem stepFEReductionChain_twelve
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 : State}
    (r0 : StepFEReduction s0 s1)
    (r1 : StepFEReduction s1 s2)
    (r2 : StepFEReduction s2 s3)
    (r3 : StepFEReduction s3 s4)
    (r4 : StepFEReduction s4 s5)
    (r5 : StepFEReduction s5 s6)
    (r6 : StepFEReduction s6 s7)
    (r7 : StepFEReduction s7 s8)
    (r8 : StepFEReduction s8 s9)
    (r9 : StepFEReduction s9 s10)
    (r10 : StepFEReduction s10 s11)
    (r11 : StepFEReduction s11 s12) :
    StepFEReductionChain s0 12 s12 := by
  have hfirst : StepFEReductionChain s0 6 s6 :=
    stepFEReductionChain_six r0 r1 r2 r3 r4 r5
  have hsecond : StepFEReductionChain s6 6 s12 :=
    stepFEReductionChain_six r6 r7 r8 r9 r10 r11
  simpa using StepFEReductionChain.append hfirst hsecond

theorem executionSegment_two_reductions
    {post : State → State → Prop} {s0 s1 s2 : State}
    (r0 : StepFEReduction s0 s1)
    (r1 : StepFEReduction s1 s2)
    (hpost : post s0 s2) :
    ExecutionSegment 2 post s0 s2 := by
  exact executionSegment_of_stepFEPath
    (stepFEPath_two r0.running r0.step r1.running r1.step)
    hpost

theorem executionSegment_three_reductions
    {post : State → State → Prop} {s0 s1 s2 s3 : State}
    (r0 : StepFEReduction s0 s1)
    (r1 : StepFEReduction s1 s2)
    (r2 : StepFEReduction s2 s3)
    (hpost : post s0 s3) :
    ExecutionSegment 3 post s0 s3 := by
  exact executionSegment_of_stepFEPath
    (stepFEPath_three r0.running r0.step r1.running r1.step
      r2.running r2.step)
    hpost

theorem executionSegment_four_reductions
    {post : State → State → Prop} {s0 s1 s2 s3 s4 : State}
    (r0 : StepFEReduction s0 s1)
    (r1 : StepFEReduction s1 s2)
    (r2 : StepFEReduction s2 s3)
    (r3 : StepFEReduction s3 s4)
    (hpost : post s0 s4) :
    ExecutionSegment 4 post s0 s4 := by
  exact executionSegment_of_stepFEPath
    (stepFEPath_four r0.running r0.step r1.running r1.step
      r2.running r2.step r3.running r3.step)
    hpost

@[simp] def BaseGasSufficient (state : State) (op : Operation) : Prop :=
  EvmSemantics.EVM.Gas.baseCost state.fork op ≤ state.gasAvailable

def SLoadGasSufficient (state : State) (key : UInt256) : Prop :=
  EvmSemantics.EVM.Gas.sloadTotal state key ≤ state.gasAvailable

def MemoryExpansionSufficientAfterBase
    (state : State) (op : Operation)
    (hbase : BaseGasSufficient state op)
    (offset size : Nat) : Prop :=
  (state.consumeGas
    (EvmSemantics.EVM.Gas.baseCost state.fork op) hbase).canExpandMemory
      offset size

def SStoreBaseGasSufficient (state : State) : Prop :=
  BaseGasSufficient state
    (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps))

def SStoreSentryAllows
    (state : State) (hbase : SStoreBaseGasSufficient state) : Prop :=
  EvmSemantics.EVM.Gas.sstoreSentry state.fork
    (state.consumeGas
      (EvmSemantics.EVM.Gas.baseCost state.fork
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
          Operation)) hbase).gasAvailable = false

def SStoreDynamicGasSufficient
    (state : State) (key value : UInt256)
    (hbase : SStoreBaseGasSufficient state) : Prop :=
  (let addr := state.executionEnv.address
   let acc := state.accountMap addr
   let current := acc.storage key
   let original := state.substate.originalStorage addr key
   EvmSemantics.EVM.Gas.sstoreCost state.fork original current value +
     EvmSemantics.EVM.Gas.sstoreColdSurcharge state key) ≤
    (state.consumeGas
      (EvmSemantics.EVM.Gas.baseCost state.fork
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
          Operation)) hbase).gasAvailable

structure StepFEReady (state : State) (op : Operation) : Prop where
  running : state.halt = .Running
  notPrecompile :
    EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
      state.executionEnv.codeAddr = false
  stackOk :
    ¬ state.stack.length + op.pushArity > 1024 + op.popArity
  gas :
    EvmSemantics.EVM.Gas.baseCost state.fork op ≤ state.gasAvailable

structure ReadyOpcodeAt
    (code : ByteArray) (pc : Nat)
    (op : Operation) (argOpt : Option (EvmSemantics.UInt256 × Nat))
    (state : State) : Prop where
  decoded : DecodedOpcodeAt code pc op argOpt state
  ready : StepFEReady state op

theorem ReadyOpcodeAt.state_decoded
    {state : State} {code : ByteArray} {pc : Nat}
    {op : Operation} {argOpt : Option (EvmSemantics.UInt256 × Nat)}
    (hat : ReadyOpcodeAt code pc op argOpt state) :
    state.decoded = some (op, argOpt) := by
  exact hat.decoded.decoded

theorem StepFEReduction.of_readyOpcodeAt
    {state nextState : State} {code : ByteArray} {pc : Nat}
    {op : Operation} {argOpt : Option (EvmSemantics.UInt256 × Nat)}
    (hat : ReadyOpcodeAt code pc op argOpt state)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    StepFEReduction state nextState :=
  StepFEReduction.of_step hat.ready.running hstep

theorem stepFE_push_dispatch
    {state : State} {op : EvmSemantics.Operation.PushOp}
    {argOpt : Option (UInt256 × Nat)}
    (hready : StepFEReady state (.Push op))
    (hdecoded : state.decoded = some (.Push op, argOpt)) :
    EvmSemantics.EVM.stepFE state =
      EvmSemantics.EVM.stepF.push state
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Push op : Operation)) hready.gas)
        op argOpt := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  unfold EvmSemantics.EVM.stepFE
  simp only [Id.run]
  split
  · split
    · rename_i hprecompileActual
      rw [hprecompile] at hprecompileActual
      contradiction
    · simp [hdecoded, hstackOk, hgas]
  · rename_i hnotRunning
    rw [hrunning] at hnotRunning
    contradiction

theorem stepFE_dup_dispatch
    {state : State} {op : EvmSemantics.Operation.DupOp}
    (hready : StepFEReady state (.Dup op))
    (hdecoded : state.decoded = some (.Dup op, none)) :
    EvmSemantics.EVM.stepFE state =
      EvmSemantics.EVM.stepF.dup state
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Dup op : Operation)) hready.gas)
        op := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  unfold EvmSemantics.EVM.stepFE
  simp only [Id.run]
  split
  · split
    · rename_i hprecompileActual
      rw [hprecompile] at hprecompileActual
      contradiction
    · simp [hdecoded, hstackOk, hgas]
  · rename_i hnotRunning
    rw [hrunning] at hnotRunning
    contradiction

theorem stepFE_swap_dispatch
    {state : State} {op : EvmSemantics.Operation.SwapOp}
    (hready : StepFEReady state (.Swap op))
    (hdecoded : state.decoded = some (.Swap op, none)) :
    EvmSemantics.EVM.stepFE state =
      EvmSemantics.EVM.stepF.swap state
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Swap op : Operation)) hready.gas)
        op := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  unfold EvmSemantics.EVM.stepFE
  simp only [Id.run]
  split
  · split
    · rename_i hprecompileActual
      rw [hprecompile] at hprecompileActual
      contradiction
    · simp [hdecoded, hstackOk, hgas]
  · rename_i hnotRunning
    rw [hrunning] at hnotRunning
    contradiction

theorem stepFE_stopArith_dispatch
    {state : State} {op : EvmSemantics.Operation.StopArithOps}
    (hready : StepFEReady state (.StopArith op))
    (hdecoded : state.decoded = some (.StopArith op, none)) :
    EvmSemantics.EVM.stepFE state =
      EvmSemantics.EVM.stepF.stopArith state
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StopArith op : Operation)) hready.gas)
        op := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  unfold EvmSemantics.EVM.stepFE
  simp only [Id.run]
  split
  · split
    · rename_i hprecompileActual
      rw [hprecompile] at hprecompileActual
      contradiction
    · simp [hdecoded, hstackOk, hgas]
  · rename_i hnotRunning
    rw [hrunning] at hnotRunning
    contradiction

theorem stepFE_compBit_dispatch
    {state : State} {op : EvmSemantics.Operation.CompareBitwiseOps}
    (hready : StepFEReady state (.CompBit op))
    (hdecoded : state.decoded = some (.CompBit op, none)) :
    EvmSemantics.EVM.stepFE state =
      EvmSemantics.EVM.stepF.compBit state
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit op : Operation)) hready.gas)
        op := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  unfold EvmSemantics.EVM.stepFE
  simp only [Id.run]
  split
  · split
    · rename_i hprecompileActual
      rw [hprecompile] at hprecompileActual
      contradiction
    · simp [hdecoded, hstackOk, hgas]
  · rename_i hnotRunning
    rw [hrunning] at hnotRunning
    contradiction

theorem stepFE_env_dispatch
    {state : State} {op : EvmSemantics.Operation.EnvOps}
    (hready : StepFEReady state (.Env op))
    (hdecoded : state.decoded = some (.Env op, none)) :
    EvmSemantics.EVM.stepFE state =
      EvmSemantics.EVM.stepF.env state
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Env op : Operation)) hready.gas)
        op := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  unfold EvmSemantics.EVM.stepFE
  simp only [Id.run]
  split
  · split
    · rename_i hprecompileActual
      rw [hprecompile] at hprecompileActual
      contradiction
    · simp [hdecoded, hstackOk, hgas]
  · rename_i hnotRunning
    rw [hrunning] at hnotRunning
    contradiction

theorem stepFE_stackMemFlow_dispatch
    {state : State} {op : EvmSemantics.Operation.StackMemFlowOps}
    (hready : StepFEReady state (.StackMemFlow op))
    (hdecoded : state.decoded = some (.StackMemFlow op, none)) :
    EvmSemantics.EVM.stepFE state =
      EvmSemantics.EVM.stepF.stackMemFlow state
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow op : Operation)) hready.gas)
        op := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  unfold EvmSemantics.EVM.stepFE
  simp only [Id.run]
  split
  · split
    · rename_i hprecompileActual
      rw [hprecompile] at hprecompileActual
      contradiction
    · simp [hdecoded, hstackOk, hgas]
  · rename_i hnotRunning
    rw [hrunning] at hnotRunning
    contradiction

theorem stepFE_system_dispatch
    {state : State} {op : EvmSemantics.Operation.SystemOps}
    (hready : StepFEReady state (.System op))
    (hdecoded : state.decoded = some (.System op, none)) :
    EvmSemantics.EVM.stepFE state =
      EvmSemantics.EVM.stepF.system state
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.System op : Operation)) hready.gas)
        op := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  unfold EvmSemantics.EVM.stepFE
  simp only [Id.run]
  split
  · split
    · rename_i hprecompileActual
      rw [hprecompile] at hprecompileActual
      contradiction
    · simp [hdecoded, hstackOk, hgas]
  · rename_i hnotRunning
    rw [hrunning] at hnotRunning
    contradiction

theorem stepFE_push0_ok
    {state : State} {op : EvmSemantics.Operation.PushOp}
    {argOpt : Option (UInt256 × Nat)}
    (hwidth : op.width.val = 0)
    (hready : StepFEReady state (.Push op))
    (hdecoded : state.decoded = some (.Push op, argOpt)) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Push op : Operation)) hready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat 0 :: state.stack)) := by
  rw [stepFE_push_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.push
  simp [hwidth, EvmSemantics.UInt256.ofNat]

theorem stepFE_push_data_ok
    {state : State} {op : EvmSemantics.Operation.PushOp}
    {value : UInt256} {argBytes widthPred : Nat}
    (hwidth : op.width.val = widthPred + 1)
    (hready : StepFEReady state (.Push op))
    (hdecoded : state.decoded = some (.Push op, some (value, argBytes))) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Push op : Operation)) hready.gas).replaceStackAndIncrPC
        (value :: state.stack) (pcΔ := argBytes + 1)) := by
  rw [stepFE_push_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.push
  simp [hwidth]

theorem stepFE_dup_ok
    {state : State} {op : EvmSemantics.Operation.DupOp}
    {value : UInt256}
    (hready : StepFEReady state (.Dup op))
    (hdecoded : state.decoded = some (.Dup op, none))
    (hindex : state.stack[op.idx.val]? = some value) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Dup op : Operation)) hready.gas).replaceStackAndIncrPC
        (value :: state.stack)) := by
  rw [stepFE_dup_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.dup
  simp [hindex]

theorem stepFE_swap_ok
    {state : State} {op : EvmSemantics.Operation.SwapOp}
    {stack' : List UInt256}
    (hready : StepFEReady state (.Swap op))
    (hdecoded : state.decoded = some (.Swap op, none))
    (hexchange : state.stack.exchange 0 (op.idx.val + 1) = some stack') :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Swap op : Operation)) hready.gas).replaceStackAndIncrPC
        stack') := by
  rw [stepFE_swap_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.swap
  simp [hexchange]

theorem stepFE_calldataload_ok
    {state : State} {offset : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)))
    (hdecoded :
      state.decoded =
        some (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps), none))
    (hstack : state.stack = offset :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
              Operation)) hready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat
          (EvmSemantics.Data.Bytes.bytesToBigEndianNat
            (EvmSemantics.MachineState.readPadded
              state.executionEnv.calldata offset.toNat 32)) :: rest)) := by
  rw [stepFE_env_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.env
  simp [hstack]

theorem stepFE_eq_ok
    {state : State} {a b : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hdecoded :
      state.decoded =
        some (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = a :: b :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.eq a b :: rest)) := by
  rw [stepFE_compBit_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.compBit
  simp [hstack]

theorem stepFE_gt_ok
    {state : State} {a b : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.CompBit (.GT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hdecoded :
      state.decoded =
        some (.CompBit (.GT : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = a :: b :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.GT : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.gt a b :: rest)) := by
  rw [stepFE_compBit_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.compBit
  simp [hstack]

theorem stepFE_shl_ok
    {state : State} {shift value : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hdecoded :
      state.decoded =
        some (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = shift :: value :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.shiftLeft value shift :: rest)) := by
  rw [stepFE_compBit_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.compBit
  simp [hstack]

theorem stepFE_shr_ok
    {state : State} {shift value : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hdecoded :
      state.decoded =
        some (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = shift :: value :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.shiftRight value shift :: rest)) := by
  rw [stepFE_compBit_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.compBit
  simp [hstack]

theorem stepFE_not_ok
    {state : State} {value : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hdecoded :
      state.decoded =
        some (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = value :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.lnot value :: rest)) := by
  rw [stepFE_compBit_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.compBit
  simp [hstack]

theorem stepFE_and_ok
    {state : State} {a b : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hdecoded :
      state.decoded =
        some (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = a :: b :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.land a b :: rest)) := by
  rw [stepFE_compBit_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.compBit
  simp [hstack]

theorem stepFE_or_ok
    {state : State} {a b : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hdecoded :
      state.decoded =
        some (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = a :: b :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.lor a b :: rest)) := by
  rw [stepFE_compBit_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.compBit
  simp [hstack]

theorem stepFE_add_ok
    {state : State} {a b : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.StopArith (.ADD : EvmSemantics.Operation.StopArithOps)))
    (hdecoded :
      state.decoded =
        some (.StopArith (.ADD : EvmSemantics.Operation.StopArithOps), none))
    (hstack : state.stack = a :: b :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StopArith (.ADD : EvmSemantics.Operation.StopArithOps) :
              Operation)) hready.gas).replaceStackAndIncrPC
        ((a + b) :: rest)) := by
  rw [stepFE_stopArith_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.stopArith
  simp [hstack]

theorem stepFE_sub_ok
    {state : State} {a b : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hdecoded :
      state.decoded =
        some (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps), none))
    (hstack : state.stack = a :: b :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps) :
              Operation)) hready.gas).replaceStackAndIncrPC
        ((a - b) :: rest)) := by
  rw [stepFE_stopArith_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.stopArith
  simp [hstack]

theorem stepFE_stop_ok
    {state : State}
    (hready :
      StepFEReady state
        (.StopArith (.STOP : EvmSemantics.Operation.StopArithOps)))
    (hdecoded :
      state.decoded =
        some (.StopArith (.STOP : EvmSemantics.Operation.StopArithOps), none)) :
    EvmSemantics.EVM.stepFE state =
      .ok { state with halt := .Success, hReturn := .empty } := by
  rw [stepFE_stopArith_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.stopArith
  rfl

theorem stepFE_jumpdest_ok
    {state : State}
    (hready :
      StepFEReady state
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hdecoded :
      state.decoded =
        some (.StackMemFlow
          (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none)) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow
              (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hready.gas).incrPC) := by
  rw [stepFE_stackMemFlow_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.stackMemFlow
  rfl

theorem stepFE_jump_ok
    {state : State} {dest : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hdecoded :
      state.decoded =
        some (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = dest :: rest)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest state.executionEnv.code
        dest.toNat = true) :
    EvmSemantics.EVM.stepFE state =
      .ok { state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hready.gas with
        pc := dest
        stack := rest } := by
  rw [stepFE_stackMemFlow_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.stackMemFlow
  simp [hstack, hvalid]

theorem stepFE_jumpi_taken_ok
    {state : State} {dest cond : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hdecoded :
      state.decoded =
        some (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = dest :: cond :: rest)
    (hcond : cond.toNat ≠ 0)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest state.executionEnv.code
        dest.toNat = true) :
    EvmSemantics.EVM.stepFE state =
      .ok { state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hready.gas with
        pc := dest
        stack := rest } := by
  rw [stepFE_stackMemFlow_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.stackMemFlow
  simp [hstack, hcond, hvalid]

theorem stepFE_jumpi_not_taken_ok
    {state : State} {dest cond : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hdecoded :
      state.decoded =
        some (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = dest :: cond :: rest)
    (hcond : cond.toNat = 0) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hready.gas).replaceStackAndIncrPC rest) := by
  rw [stepFE_stackMemFlow_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.stackMemFlow
  simp [hstack, hcond]

theorem stepFE_sload_ok
    {state : State} {key : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hdecoded :
      state.decoded =
        some (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = key :: rest)
    (hgasTotal : EvmSemantics.EVM.Gas.sloadTotal state key ≤ state.gasAvailable) :
    EvmSemantics.EVM.stepFE state =
      .ok ({ (state.consumeGas (EvmSemantics.EVM.Gas.sloadTotal state key)
              hgasTotal) with
          substate := state.substate.addAccessedStorageKey
            (state.executionEnv.address, key) }.replaceStackAndIncrPC
        ((state.accountMap state.executionEnv.address).storage key :: rest)) := by
  rw [stepFE_stackMemFlow_dispatch hready hdecoded]
  unfold EvmSemantics.EVM.stepF.stackMemFlow
  simp [hstack, hgasTotal, EvmSemantics.EVM.State.consumeGas]

theorem stepFE_sload_success_stack_ok
    {state nextState : State} {key : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hdecoded :
      state.decoded =
        some (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = key :: rest)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.stack =
      (state.accountMap state.executionEnv.address).storage key :: rest := by
  rw [stepFE_stackMemFlow_dispatch hready hdecoded] at hstep
  unfold EvmSemantics.EVM.stepF.stackMemFlow at hstep
  simp [hstack] at hstep
  by_cases hgasTotal :
      EvmSemantics.EVM.Gas.sloadTotal state key ≤ state.gasAvailable
  · simp [hgasTotal, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC] at hstep
    cases hstep
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  · simp [hgasTotal] at hstep

theorem stepFE_sload_success_callStack_ok
    {state nextState : State} {key : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hdecoded :
      state.decoded =
        some (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = key :: rest)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  rw [stepFE_stackMemFlow_dispatch hready hdecoded] at hstep
  unfold EvmSemantics.EVM.stepF.stackMemFlow at hstep
  simp [hstack] at hstep
  by_cases hgasTotal :
      EvmSemantics.EVM.Gas.sloadTotal state key ≤ state.gasAvailable
  · simp [hgasTotal, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC] at hstep
    cases hstep
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  · simp [hgasTotal] at hstep

theorem stepF_mstore_ok
    {state gasState : State} {offset value : UInt256} {rest : List UInt256}
    (hstack : state.stack = offset :: value :: rest)
    (hmem : gasState.canExpandMemory offset.toNat 32) :
    EvmSemantics.EVM.stepF.stackMemFlow state gasState
        (.MSTORE : EvmSemantics.Operation.StackMemFlowOps) =
      .ok
        ({ gasState.consumeMemExp offset.toNat 32 hmem with
          toMachineState :=
            EvmSemantics.MachineState.mstore
              (gasState.consumeMemExp offset.toNat 32 hmem).toMachineState
              offset value }.replaceStackAndIncrPC rest) := by
  unfold EvmSemantics.EVM.stepF.stackMemFlow EvmSemantics.EVM.chargeMem
  simp [hstack, hmem]

theorem stepFE_mstore_ok
    {state : State} {offset value : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hdecoded :
      state.decoded =
        some (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = offset :: value :: rest)
    (hmem :
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps) :
            Operation)) hready.gas).canExpandMemory offset.toNat 32) :
    EvmSemantics.EVM.stepFE state =
      .ok
        ({ (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hready.gas).consumeMemExp offset.toNat 32 hmem with
          toMachineState :=
            EvmSemantics.MachineState.mstore
              ((state.consumeGas
                (EvmSemantics.EVM.Gas.baseCost state.fork
                  (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps) :
                    Operation)) hready.gas).consumeMemExp offset.toNat 32 hmem).toMachineState
              offset value }.replaceStackAndIncrPC rest) := by
  rw [stepFE_stackMemFlow_dispatch hready hdecoded]
  exact stepF_mstore_ok hstack hmem

theorem stepFE_sstore_dispatch_ok
    {state : State}
    (hready :
      StepFEReady state
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hdecoded :
      state.decoded =
        some (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps), none)) :
    EvmSemantics.EVM.stepFE state =
      EvmSemantics.EVM.stepF.stackMemFlow state
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hready.gas)
        (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) := by
  exact stepFE_stackMemFlow_dispatch hready hdecoded

theorem stepF_sstore_ok
    {state gasState : State} {key value : UInt256} {rest : List UInt256}
    (hmut : state.executionEnv.permitStateMutation = true)
    (hsentry :
      EvmSemantics.EVM.Gas.sstoreSentry state.fork gasState.gasAvailable = false)
    (hstack : state.stack = key :: value :: rest)
    (hcost :
      (let addr := state.executionEnv.address
       let acc := state.accountMap addr
       let current := acc.storage key
       let original := state.substate.originalStorage addr key
       EvmSemantics.EVM.Gas.sstoreCost state.fork original current value +
         EvmSemantics.EVM.Gas.sstoreColdSurcharge state key) ≤
        gasState.gasAvailable) :
    EvmSemantics.EVM.stepF.stackMemFlow state gasState
        (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) =
      .ok
        (let addr := state.executionEnv.address
         let acc := state.accountMap addr
         let current := acc.storage key
         let original := state.substate.originalStorage addr key
         let cost :=
           EvmSemantics.EVM.Gas.sstoreCost state.fork original current value +
             EvmSemantics.EVM.Gas.sstoreColdSurcharge state key
         let acc' := { acc with storage := acc.storage.set key value }
         let σ' := state.accountMap.set addr acc'
         let refDelta :=
           EvmSemantics.EVM.Gas.sstoreRefund state.fork original current value
         let rb : Int := (state.substate.refundBalance.toNat : Int) + refDelta
         let rb' : Nat := if rb < 0 then 0 else rb.toNat
         let sub' : EvmSemantics.Substate :=
           { state.substate.addAccessedStorageKey (addr, key) with
             refundBalance := EvmSemantics.UInt256.ofNat rb' }
         ({ (gasState.consumeGas cost hcost) with
             accountMap := σ'
             substate := sub' }.replaceStackAndIncrPC rest)) := by
  unfold EvmSemantics.EVM.stepF.stackMemFlow
  simp [hmut, hsentry, hstack, hcost]

theorem stepFE_sstore_ok
    {state : State} {key value : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hdecoded :
      state.decoded =
        some (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps), none))
    (hmut : state.executionEnv.permitStateMutation = true)
    (hsentry :
      EvmSemantics.EVM.Gas.sstoreSentry state.fork
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hready.gas).gasAvailable = false)
    (hstack : state.stack = key :: value :: rest)
    (hcost :
      (let addr := state.executionEnv.address
       let acc := state.accountMap addr
       let current := acc.storage key
       let original := state.substate.originalStorage addr key
       EvmSemantics.EVM.Gas.sstoreCost state.fork original current value +
         EvmSemantics.EVM.Gas.sstoreColdSurcharge state key) ≤
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hready.gas).gasAvailable) :
    EvmSemantics.EVM.stepFE state =
      .ok
        (let gasState := state.consumeGas
            (EvmSemantics.EVM.Gas.baseCost state.fork
              (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
                Operation)) hready.gas
         let addr := state.executionEnv.address
         let acc := state.accountMap addr
         let current := acc.storage key
         let original := state.substate.originalStorage addr key
         let cost :=
           EvmSemantics.EVM.Gas.sstoreCost state.fork original current value +
             EvmSemantics.EVM.Gas.sstoreColdSurcharge state key
         let acc' := { acc with storage := acc.storage.set key value }
         let σ' := state.accountMap.set addr acc'
         let refDelta :=
           EvmSemantics.EVM.Gas.sstoreRefund state.fork original current value
         let rb : Int := (state.substate.refundBalance.toNat : Int) + refDelta
         let rb' : Nat := if rb < 0 then 0 else rb.toNat
         let sub' : EvmSemantics.Substate :=
           { state.substate.addAccessedStorageKey (addr, key) with
             refundBalance := EvmSemantics.UInt256.ofNat rb' }
         ({ (gasState.consumeGas cost hcost) with
             accountMap := σ'
             substate := sub' }.replaceStackAndIncrPC rest)) := by
  rw [stepFE_sstore_dispatch_ok hready hdecoded]
  exact stepF_sstore_ok hmut hsentry hstack hcost

theorem stepFE_return_dispatch_ok
    {state : State}
    (hready :
      StepFEReady state
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hdecoded :
      state.decoded =
        some (.System (.RETURN : EvmSemantics.Operation.SystemOps), none)) :
    EvmSemantics.EVM.stepFE state =
      EvmSemantics.EVM.stepF.system state
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.System (.RETURN : EvmSemantics.Operation.SystemOps) :
              Operation)) hready.gas)
        (.RETURN : EvmSemantics.Operation.SystemOps) := by
  exact stepFE_system_dispatch hready hdecoded

theorem stepF_return_ok
    {state gasState : State} {offset size : UInt256} {rest : List UInt256}
    (hstack : state.stack = offset :: size :: rest)
    (hmem : gasState.canExpandMemory offset.toNat size.toNat) :
    EvmSemantics.EVM.stepF.system state gasState
        (.RETURN : EvmSemantics.Operation.SystemOps) =
      .ok { gasState.consumeMemExp offset.toNat size.toNat hmem with
        halt := .Returned
        hReturn := EvmSemantics.MachineState.readPadded state.memory
          offset.toNat size.toNat
        stack := rest } := by
  unfold EvmSemantics.EVM.stepF.system EvmSemantics.EVM.chargeMem
  simp [hstack, hmem]

theorem stepFE_return_ok
    {state : State} {offset size : UInt256} {rest : List UInt256}
    (hready :
      StepFEReady state
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hdecoded :
      state.decoded =
        some (.System (.RETURN : EvmSemantics.Operation.SystemOps), none))
    (hstack : state.stack = offset :: size :: rest)
    (hmem :
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.System (.RETURN : EvmSemantics.Operation.SystemOps) :
            Operation)) hready.gas).canExpandMemory offset.toNat size.toNat) :
    EvmSemantics.EVM.stepFE state =
      .ok { (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.System (.RETURN : EvmSemantics.Operation.SystemOps) :
              Operation)) hready.gas).consumeMemExp offset.toNat size.toNat hmem with
        halt := .Returned
        hReturn := EvmSemantics.MachineState.readPadded state.memory
          offset.toNat size.toNat
        stack := rest } := by
  rw [stepFE_return_dispatch_ok hready hdecoded]
  exact stepF_return_ok hstack hmem

theorem stepFE_push0_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {op : EvmSemantics.Operation.PushOp}
    {argOpt : Option (UInt256 × Nat)}
    (hat : ReadyOpcodeAt code pc (.Push op) argOpt state)
    (hwidth : op.width.val = 0) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Push op : Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat 0 :: state.stack)) := by
  exact stepFE_push0_ok hwidth hat.ready hat.state_decoded

theorem reduction_push0_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {op : EvmSemantics.Operation.PushOp}
    {argOpt : Option (UInt256 × Nat)}
    (hat : ReadyOpcodeAt code pc (.Push op) argOpt state)
    (hwidth : op.width.val = 0) :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Push op : Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat 0 :: state.stack)) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_push0_at_ok hat hwidth)

theorem stepFE_push_data_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {op : EvmSemantics.Operation.PushOp}
    {value : UInt256} {argBytes widthPred : Nat}
    (hat : ReadyOpcodeAt code pc (.Push op) (some (value, argBytes)) state)
    (hwidth : op.width.val = widthPred + 1) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Push op : Operation)) hat.ready.gas).replaceStackAndIncrPC
        (value :: state.stack) (pcΔ := argBytes + 1)) := by
  exact stepFE_push_data_ok hwidth hat.ready hat.state_decoded

theorem reduction_push_data_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {op : EvmSemantics.Operation.PushOp}
    {value : UInt256} {argBytes widthPred : Nat}
    (hat : ReadyOpcodeAt code pc (.Push op) (some (value, argBytes)) state)
    (hwidth : op.width.val = widthPred + 1) :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Push op : Operation)) hat.ready.gas).replaceStackAndIncrPC
        (value :: state.stack) (pcΔ := argBytes + 1)) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_push_data_at_ok hat hwidth)

theorem stepFE_dup_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {op : EvmSemantics.Operation.DupOp} {value : UInt256}
    (hat : ReadyOpcodeAt code pc (.Dup op) none state)
    (hindex : state.stack[op.idx.val]? = some value) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Dup op : Operation)) hat.ready.gas).replaceStackAndIncrPC
        (value :: state.stack)) := by
  exact stepFE_dup_ok hat.ready hat.state_decoded hindex

theorem reduction_dup_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {op : EvmSemantics.Operation.DupOp} {value : UInt256}
    (hat : ReadyOpcodeAt code pc (.Dup op) none state)
    (hindex : state.stack[op.idx.val]? = some value) :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Dup op : Operation)) hat.ready.gas).replaceStackAndIncrPC
        (value :: state.stack)) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_dup_at_ok hat hindex)

theorem stepFE_swap_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {op : EvmSemantics.Operation.SwapOp} {stack' : List UInt256}
    (hat : ReadyOpcodeAt code pc (.Swap op) none state)
    (hexchange : state.stack.exchange 0 (op.idx.val + 1) = some stack') :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Swap op : Operation)) hat.ready.gas).replaceStackAndIncrPC
        stack') := by
  exact stepFE_swap_ok hat.ready hat.state_decoded hexchange

theorem reduction_swap_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {op : EvmSemantics.Operation.SwapOp} {stack' : List UInt256}
    (hat : ReadyOpcodeAt code pc (.Swap op) none state)
    (hexchange : state.stack.exchange 0 (op.idx.val + 1) = some stack') :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Swap op : Operation)) hat.ready.gas).replaceStackAndIncrPC
        stack') := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_swap_at_ok hat hexchange)

theorem stepFE_calldataload_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {offset : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)) none state)
    (hstack : state.stack = offset :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat
          (EvmSemantics.Data.Bytes.bytesToBigEndianNat
            (EvmSemantics.MachineState.readPadded
              state.executionEnv.calldata offset.toNat 32)) :: rest)) := by
  exact stepFE_calldataload_ok hat.ready hat.state_decoded hstack

theorem reduction_calldataload_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {offset : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)) none state)
    (hstack : state.stack = offset :: rest) :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat
          (EvmSemantics.Data.Bytes.bytesToBigEndianNat
            (EvmSemantics.MachineState.readPadded
              state.executionEnv.calldata offset.toNat 32)) :: rest)) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_calldataload_at_ok hat hstack)

theorem stepFE_eq_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {a b : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)) none state)
    (hstack : state.stack = a :: b :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.eq a b :: rest)) := by
  exact stepFE_eq_ok hat.ready hat.state_decoded hstack

theorem reduction_eq_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {a b : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)) none state)
    (hstack : state.stack = a :: b :: rest) :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.eq a b :: rest)) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_eq_at_ok hat hstack)

theorem stepFE_gt_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {a b : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.CompBit (.GT : EvmSemantics.Operation.CompareBitwiseOps)) none state)
    (hstack : state.stack = a :: b :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.GT : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.gt a b :: rest)) := by
  exact stepFE_gt_ok hat.ready hat.state_decoded hstack

theorem reduction_gt_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {a b : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.CompBit (.GT : EvmSemantics.Operation.CompareBitwiseOps)) none state)
    (hstack : state.stack = a :: b :: rest) :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.GT : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.gt a b :: rest)) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_gt_at_ok hat hstack)

theorem stepFE_shl_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {shift value : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)) none state)
    (hstack : state.stack = shift :: value :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.shiftLeft value shift :: rest)) := by
  exact stepFE_shl_ok hat.ready hat.state_decoded hstack

theorem reduction_shl_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {shift value : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)) none state)
    (hstack : state.stack = shift :: value :: rest) :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.shiftLeft value shift :: rest)) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_shl_at_ok hat hstack)

theorem stepFE_shr_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {shift value : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)) none state)
    (hstack : state.stack = shift :: value :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.shiftRight value shift :: rest)) := by
  exact stepFE_shr_ok hat.ready hat.state_decoded hstack

theorem reduction_shr_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {shift value : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)) none state)
    (hstack : state.stack = shift :: value :: rest) :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.shiftRight value shift :: rest)) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_shr_at_ok hat hstack)

theorem stepFE_not_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {value : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)) none state)
    (hstack : state.stack = value :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.lnot value :: rest)) := by
  exact stepFE_not_ok hat.ready hat.state_decoded hstack

theorem reduction_not_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {value : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)) none state)
    (hstack : state.stack = value :: rest) :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.lnot value :: rest)) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_not_at_ok hat hstack)

theorem stepFE_and_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {a b : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)) none state)
    (hstack : state.stack = a :: b :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.land a b :: rest)) := by
  exact stepFE_and_ok hat.ready hat.state_decoded hstack

theorem reduction_and_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {a b : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)) none state)
    (hstack : state.stack = a :: b :: rest) :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.land a b :: rest)) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_and_at_ok hat hstack)

theorem stepFE_or_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {a b : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)) none state)
    (hstack : state.stack = a :: b :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.lor a b :: rest)) := by
  exact stepFE_or_ok hat.ready hat.state_decoded hstack

theorem reduction_or_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {a b : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)) none state)
    (hstack : state.stack = a :: b :: rest) :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.lor a b :: rest)) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_or_at_ok hat hstack)

theorem stepFE_add_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {a b : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StopArith (.ADD : EvmSemantics.Operation.StopArithOps)) none state)
    (hstack : state.stack = a :: b :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StopArith (.ADD : EvmSemantics.Operation.StopArithOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        ((a + b) :: rest)) := by
  exact stepFE_add_ok hat.ready hat.state_decoded hstack

theorem reduction_add_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {a b : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StopArith (.ADD : EvmSemantics.Operation.StopArithOps)) none state)
    (hstack : state.stack = a :: b :: rest) :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StopArith (.ADD : EvmSemantics.Operation.StopArithOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        ((a + b) :: rest)) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_add_at_ok hat hstack)

theorem stepFE_sub_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {a b : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)) none state)
    (hstack : state.stack = a :: b :: rest) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        ((a - b) :: rest)) := by
  exact stepFE_sub_ok hat.ready hat.state_decoded hstack

theorem reduction_sub_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {a b : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)) none state)
    (hstack : state.stack = a :: b :: rest) :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC
        ((a - b) :: rest)) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_sub_at_ok hat hstack)

theorem stepFE_stop_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    (hat :
      ReadyOpcodeAt code pc
        (.StopArith (.STOP : EvmSemantics.Operation.StopArithOps)) none state) :
    EvmSemantics.EVM.stepFE state =
      .ok { state with halt := .Success, hReturn := .empty } := by
  exact stepFE_stop_ok hat.ready hat.state_decoded

theorem reduction_stop_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    (hat :
      ReadyOpcodeAt code pc
        (.StopArith (.STOP : EvmSemantics.Operation.StopArithOps)) none state) :
    StepFEReduction state { state with halt := .Success, hReturn := .empty } := by
  exact StepFEReduction.of_readyOpcodeAt hat (stepFE_stop_at_ok hat)

theorem stepFE_jumpdest_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    (hat :
      ReadyOpcodeAt code pc
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps))
        none state) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow
              (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas).incrPC) := by
  exact stepFE_jumpdest_ok hat.ready hat.state_decoded

theorem reduction_jumpdest_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    (hat :
      ReadyOpcodeAt code pc
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps))
        none state) :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow
              (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas).incrPC) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_jumpdest_at_ok hat)

theorem stepFE_jump_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {dest : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps))
        none state)
    (hstack : state.stack = dest :: rest)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest code dest.toNat = true) :
    EvmSemantics.EVM.stepFE state =
      .ok { state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas with
        pc := dest
        stack := rest } := by
  exact stepFE_jump_ok hat.ready hat.state_decoded hstack
    (validJumpDest_of_code_eq hat.decoded.codePc.1 hvalid)

theorem reduction_jump_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {dest : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps))
        none state)
    (hstack : state.stack = dest :: rest)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest code dest.toNat = true) :
    StepFEReduction state
      { state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas with
        pc := dest
        stack := rest } := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_jump_at_ok hat hstack hvalid)

theorem stepFE_jumpi_taken_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {dest cond : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps))
        none state)
    (hstack : state.stack = dest :: cond :: rest)
    (hcond : cond.toNat ≠ 0)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest code dest.toNat = true) :
    EvmSemantics.EVM.stepFE state =
      .ok { state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas with
        pc := dest
        stack := rest } := by
  exact stepFE_jumpi_taken_ok hat.ready hat.state_decoded hstack hcond
    (validJumpDest_of_code_eq hat.decoded.codePc.1 hvalid)

theorem reduction_jumpi_taken_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {dest cond : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps))
        none state)
    (hstack : state.stack = dest :: cond :: rest)
    (hcond : cond.toNat ≠ 0)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest code dest.toNat = true) :
    StepFEReduction state
      { state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas with
        pc := dest
        stack := rest } := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_jumpi_taken_at_ok hat hstack hcond hvalid)

theorem stepFE_jumpi_not_taken_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {dest cond : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps))
        none state)
    (hstack : state.stack = dest :: cond :: rest)
    (hcond : cond.toNat = 0) :
    EvmSemantics.EVM.stepFE state =
      .ok ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC rest) := by
  exact stepFE_jumpi_not_taken_ok hat.ready hat.state_decoded hstack hcond

theorem reduction_jumpi_not_taken_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {dest cond : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps))
        none state)
    (hstack : state.stack = dest :: cond :: rest)
    (hcond : cond.toNat = 0) :
    StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas).replaceStackAndIncrPC rest) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_jumpi_not_taken_at_ok hat hstack hcond)

theorem stepFE_sload_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {key : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps))
        none state)
    (hstack : state.stack = key :: rest)
    (hgasTotal : EvmSemantics.EVM.Gas.sloadTotal state key ≤ state.gasAvailable) :
    EvmSemantics.EVM.stepFE state =
      .ok ({ (state.consumeGas (EvmSemantics.EVM.Gas.sloadTotal state key)
              hgasTotal) with
          substate := state.substate.addAccessedStorageKey
            (state.executionEnv.address, key) }.replaceStackAndIncrPC
        ((state.accountMap state.executionEnv.address).storage key :: rest)) := by
  exact stepFE_sload_ok hat.ready hat.state_decoded hstack hgasTotal

theorem reduction_sload_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {key : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps))
        none state)
    (hstack : state.stack = key :: rest)
    (hgasTotal : EvmSemantics.EVM.Gas.sloadTotal state key ≤ state.gasAvailable) :
    StepFEReduction state
      ({ (state.consumeGas (EvmSemantics.EVM.Gas.sloadTotal state key)
              hgasTotal) with
          substate := state.substate.addAccessedStorageKey
            (state.executionEnv.address, key) }.replaceStackAndIncrPC
        ((state.accountMap state.executionEnv.address).storage key :: rest)) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_sload_at_ok hat hstack hgasTotal)

theorem stepFE_mstore_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {offset value : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps))
        none state)
    (hstack : state.stack = offset :: value :: rest)
    (hmem :
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps) :
            Operation)) hat.ready.gas).canExpandMemory offset.toNat 32) :
    EvmSemantics.EVM.stepFE state =
      .ok
        ({ (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas).consumeMemExp offset.toNat 32 hmem with
          toMachineState :=
            EvmSemantics.MachineState.mstore
              ((state.consumeGas
                (EvmSemantics.EVM.Gas.baseCost state.fork
                  (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps) :
                    Operation)) hat.ready.gas).consumeMemExp offset.toNat 32 hmem).toMachineState
              offset value }.replaceStackAndIncrPC rest) := by
  exact stepFE_mstore_ok hat.ready hat.state_decoded hstack hmem

theorem reduction_mstore_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {offset value : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps))
        none state)
    (hstack : state.stack = offset :: value :: rest)
    (hmem :
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps) :
            Operation)) hat.ready.gas).canExpandMemory offset.toNat 32) :
    StepFEReduction state
      ({ (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas).consumeMemExp offset.toNat 32 hmem with
          toMachineState :=
            EvmSemantics.MachineState.mstore
              ((state.consumeGas
                (EvmSemantics.EVM.Gas.baseCost state.fork
                  (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps) :
                    Operation)) hat.ready.gas).consumeMemExp offset.toNat 32 hmem).toMachineState
              offset value }.replaceStackAndIncrPC rest) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_mstore_at_ok hat hstack hmem)

theorem stepFE_sstore_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {key value : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps))
        none state)
    (hmut : state.executionEnv.permitStateMutation = true)
    (hsentry :
      EvmSemantics.EVM.Gas.sstoreSentry state.fork
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas).gasAvailable = false)
    (hstack : state.stack = key :: value :: rest)
    (hcost :
      (let addr := state.executionEnv.address
       let acc := state.accountMap addr
       let current := acc.storage key
       let original := state.substate.originalStorage addr key
       EvmSemantics.EVM.Gas.sstoreCost state.fork original current value +
         EvmSemantics.EVM.Gas.sstoreColdSurcharge state key) ≤
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas).gasAvailable) :
    EvmSemantics.EVM.stepFE state =
      .ok
        (let gasState := state.consumeGas
            (EvmSemantics.EVM.Gas.baseCost state.fork
              (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
                Operation)) hat.ready.gas
         let addr := state.executionEnv.address
         let acc := state.accountMap addr
         let current := acc.storage key
         let original := state.substate.originalStorage addr key
         let cost :=
           EvmSemantics.EVM.Gas.sstoreCost state.fork original current value +
             EvmSemantics.EVM.Gas.sstoreColdSurcharge state key
         let acc' := { acc with storage := acc.storage.set key value }
         let σ' := state.accountMap.set addr acc'
         let refDelta :=
           EvmSemantics.EVM.Gas.sstoreRefund state.fork original current value
         let rb : Int := (state.substate.refundBalance.toNat : Int) + refDelta
         let rb' : Nat := if rb < 0 then 0 else rb.toNat
         let sub' : EvmSemantics.Substate :=
           { state.substate.addAccessedStorageKey (addr, key) with
             refundBalance := EvmSemantics.UInt256.ofNat rb' }
         ({ (gasState.consumeGas cost hcost) with
             accountMap := σ'
             substate := sub' }.replaceStackAndIncrPC rest)) := by
  exact stepFE_sstore_ok hat.ready hat.state_decoded hmut hsentry hstack hcost

theorem reduction_sstore_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {key value : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps))
        none state)
    (hmut : state.executionEnv.permitStateMutation = true)
    (hsentry :
      EvmSemantics.EVM.Gas.sstoreSentry state.fork
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas).gasAvailable = false)
    (hstack : state.stack = key :: value :: rest)
    (hcost :
      (let addr := state.executionEnv.address
       let acc := state.accountMap addr
       let current := acc.storage key
       let original := state.substate.originalStorage addr key
       EvmSemantics.EVM.Gas.sstoreCost state.fork original current value +
         EvmSemantics.EVM.Gas.sstoreColdSurcharge state key) ≤
        (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas).gasAvailable) :
    StepFEReduction state
      (let gasState := state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas
       let addr := state.executionEnv.address
       let acc := state.accountMap addr
       let current := acc.storage key
       let original := state.substate.originalStorage addr key
       let cost :=
         EvmSemantics.EVM.Gas.sstoreCost state.fork original current value +
           EvmSemantics.EVM.Gas.sstoreColdSurcharge state key
       let acc' := { acc with storage := acc.storage.set key value }
       let σ' := state.accountMap.set addr acc'
       let refDelta :=
         EvmSemantics.EVM.Gas.sstoreRefund state.fork original current value
       let rb : Int := (state.substate.refundBalance.toNat : Int) + refDelta
       let rb' : Nat := if rb < 0 then 0 else rb.toNat
       let sub' : EvmSemantics.Substate :=
         { state.substate.addAccessedStorageKey (addr, key) with
           refundBalance := EvmSemantics.UInt256.ofNat rb' }
       ({ (gasState.consumeGas cost hcost) with
           accountMap := σ'
           substate := sub' }.replaceStackAndIncrPC rest)) := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_sstore_at_ok hat hmut hsentry hstack hcost)

theorem stepFE_return_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {offset size : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)) none state)
    (hstack : state.stack = offset :: size :: rest)
    (hmem :
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.System (.RETURN : EvmSemantics.Operation.SystemOps) :
            Operation)) hat.ready.gas).canExpandMemory offset.toNat size.toNat) :
    EvmSemantics.EVM.stepFE state =
      .ok { (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.System (.RETURN : EvmSemantics.Operation.SystemOps) :
              Operation)) hat.ready.gas).consumeMemExp offset.toNat size.toNat hmem with
        halt := .Returned
        hReturn := EvmSemantics.MachineState.readPadded state.memory
          offset.toNat size.toNat
        stack := rest } := by
  exact stepFE_return_ok hat.ready hat.state_decoded hstack hmem

theorem reduction_return_at_ok
    {code : ByteArray} {pc : Nat} {state : State}
    {offset size : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt code pc
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)) none state)
    (hstack : state.stack = offset :: size :: rest)
    (hmem :
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.System (.RETURN : EvmSemantics.Operation.SystemOps) :
            Operation)) hat.ready.gas).canExpandMemory offset.toNat size.toNat) :
    StepFEReduction state
      { (state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.System (.RETURN : EvmSemantics.Operation.SystemOps) :
              Operation)) hat.ready.gas).consumeMemExp offset.toNat size.toNat hmem with
        halt := .Returned
        hReturn := EvmSemantics.MachineState.readPadded state.memory
          offset.toNat size.toNat
        stack := rest } := by
  exact StepFEReduction.of_readyOpcodeAt hat
    (stepFE_return_at_ok hat hstack hmem)

end ProofForge.Backend.Evm.PowdrExec
