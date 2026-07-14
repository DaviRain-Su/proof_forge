import ProofForgeFormal.Evm.PowdrExec

/-!
Small non-Counter reuse smoke for `PowdrExec`.

This file deliberately avoids importing `CounterRefinement`.  It models the
bytecode skeleton of a tiny two-slot reader entrypoint (`PUSH1 slot; SLOAD;
STOP`) and proves the three-step path only by composing the generic powdr
execution lemmas.
-/

namespace ProofForge.Backend.Evm.PowdrExecSmoke

abbrev State := ProofForge.Backend.Evm.PowdrExec.State
abbrev StepFEReady := ProofForge.Backend.Evm.PowdrExec.StepFEReady
abbrev StepFEPath := ProofForge.Backend.Evm.PowdrExec.StepFEPath
abbrev StepFEReduction := ProofForge.Backend.Evm.PowdrExec.StepFEReduction
abbrev StepFEReductionChain :=
  ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain
abbrev ReadyOpcodeAt := ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
abbrev SLoadGasSufficient :=
  ProofForge.Backend.Evm.PowdrExec.SLoadGasSufficient
abbrev MemoryExpansionSufficientAfterBase :=
  ProofForge.Backend.Evm.PowdrExec.MemoryExpansionSufficientAfterBase
abbrev ExecutionSegment :=
  ProofForge.Backend.Evm.PowdrExec.ExecutionSegment
abbrev SegmentProvider :=
  ProofForge.Backend.Evm.PowdrExec.SegmentProvider
abbrev ReductionChainProvider :=
  ProofForge.Backend.Evm.PowdrExec.ReductionChainProvider
abbrev UInt256 := EvmSemantics.UInt256
abbrev Operation := EvmSemantics.Operation

def twoSlotReaderPush1Op : EvmSemantics.Operation.PushOp :=
  { width := ⟨1, by decide⟩ }

def twoSlotReaderBalanceSlot : UInt256 :=
  EvmSemantics.UInt256.ofNat 1

def twoSlotReaderCode : ByteArray :=
  ByteArray.mk #[0x60, 0x01, 0x54, 0x00]

theorem twoSlotReaderCode_decode_push_balance :
    EvmSemantics.EVM.Decode.decodeAt twoSlotReaderCode 0 =
      some (.Push twoSlotReaderPush1Op,
        some (twoSlotReaderBalanceSlot, 1)) := by
  native_decide

theorem twoSlotReaderCode_decode_sload :
    EvmSemantics.EVM.Decode.decodeAt twoSlotReaderCode 2 =
      some (.StackMemFlow
        (.SLOAD : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem twoSlotReaderCode_decode_stop :
    EvmSemantics.EVM.Decode.decodeAt twoSlotReaderCode 3 =
      some (.StopArith (.STOP : EvmSemantics.Operation.StopArithOps), none) := by
  native_decide

def mstoreWordCode : ByteArray :=
  ByteArray.mk #[0x52]

theorem mstoreWordCode_decode_mstore :
    EvmSemantics.EVM.Decode.decodeAt mstoreWordCode 0 =
      some (.StackMemFlow
        (.MSTORE : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

def pushBalanceSlotPost (state : State)
    (hready : StepFEReady state (.Push twoSlotReaderPush1Op)) : State :=
  (state.consumeGas
    (EvmSemantics.EVM.Gas.baseCost state.fork
      (.Push twoSlotReaderPush1Op : Operation)) hready.gas).replaceStackAndIncrPC
    (twoSlotReaderBalanceSlot :: state.stack) (pcΔ := 2)

def sloadBalanceSlotPost (state : State)
    (hgas : SLoadGasSufficient state twoSlotReaderBalanceSlot) : State :=
  ({ (state.consumeGas
      (EvmSemantics.EVM.Gas.sloadTotal state twoSlotReaderBalanceSlot)
      hgas) with
      substate := state.substate.addAccessedStorageKey
        (state.executionEnv.address, twoSlotReaderBalanceSlot) }.replaceStackAndIncrPC
    ((state.accountMap state.executionEnv.address).storage
      twoSlotReaderBalanceSlot :: state.stack.tail))

def stopPost (state : State) : State :=
  { state with halt := .Success, hReturn := .empty }

def twoSlotReaderGetBalancePre (s0 : State) : Prop :=
  ∃ (hpushAt :
      ReadyOpcodeAt twoSlotReaderCode 0 (.Push twoSlotReaderPush1Op)
        (some (twoSlotReaderBalanceSlot, 1)) s0)
    (_hsloadAt :
      ReadyOpcodeAt twoSlotReaderCode 2
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps))
        none (pushBalanceSlotPost s0 hpushAt.ready))
    (hsloadGas :
      SLoadGasSufficient
        (pushBalanceSlotPost s0 hpushAt.ready) twoSlotReaderBalanceSlot)
    (_hstopAt :
      ReadyOpcodeAt twoSlotReaderCode 3
        (.StopArith (.STOP : EvmSemantics.Operation.StopArithOps))
        none
        (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready)
          hsloadGas)),
    True

def twoSlotReaderGetBalancePost (s0 finalState : State) : Prop :=
  ∃ (hpushAt :
      ReadyOpcodeAt twoSlotReaderCode 0 (.Push twoSlotReaderPush1Op)
        (some (twoSlotReaderBalanceSlot, 1)) s0)
    (_hsloadAt :
      ReadyOpcodeAt twoSlotReaderCode 2
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps))
        none (pushBalanceSlotPost s0 hpushAt.ready))
    (hsloadGas :
      SLoadGasSufficient
        (pushBalanceSlotPost s0 hpushAt.ready) twoSlotReaderBalanceSlot)
    (_hstopAt :
      ReadyOpcodeAt twoSlotReaderCode 3
        (.StopArith (.STOP : EvmSemantics.Operation.StopArithOps))
        none
        (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready)
          hsloadGas)),
    finalState =
      stopPost
        (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready) hsloadGas)

def twoSlotReaderGetBalancePrefixPost (s0 s2 : State) : Prop :=
  ∃ (hpushAt :
      ReadyOpcodeAt twoSlotReaderCode 0 (.Push twoSlotReaderPush1Op)
        (some (twoSlotReaderBalanceSlot, 1)) s0)
    (_hsloadAt :
      ReadyOpcodeAt twoSlotReaderCode 2
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps))
        none (pushBalanceSlotPost s0 hpushAt.ready))
    (hsloadGas :
      SLoadGasSufficient
        (pushBalanceSlotPost s0 hpushAt.ready) twoSlotReaderBalanceSlot)
    (_hstopAt :
      ReadyOpcodeAt twoSlotReaderCode 3
        (.StopArith (.STOP : EvmSemantics.Operation.StopArithOps))
        none
        (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready)
          hsloadGas)),
    s2 =
      sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready) hsloadGas

def twoSlotReaderStopPre (s2 : State) : Prop :=
  ∃ s0, twoSlotReaderGetBalancePrefixPost s0 s2

def twoSlotReaderStopPost (s2 finalState : State) : Prop :=
  ∀ {s0 : State}
    (hpushAt :
      ReadyOpcodeAt twoSlotReaderCode 0 (.Push twoSlotReaderPush1Op)
        (some (twoSlotReaderBalanceSlot, 1)) s0)
    (_hsloadAt :
      ReadyOpcodeAt twoSlotReaderCode 2
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps))
        none (pushBalanceSlotPost s0 hpushAt.ready))
    (hsloadGas :
      SLoadGasSufficient
        (pushBalanceSlotPost s0 hpushAt.ready) twoSlotReaderBalanceSlot)
    (_hstopAt :
      ReadyOpcodeAt twoSlotReaderCode 3
        (.StopArith (.STOP : EvmSemantics.Operation.StopArithOps))
        none
        (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready)
          hsloadGas)),
    s2 =
      sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready) hsloadGas →
    finalState =
      stopPost
        (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready) hsloadGas)

theorem twoSlotReader_getBalance_reductionChain
    {s0 : State}
    (hpushAt :
      ReadyOpcodeAt twoSlotReaderCode 0 (.Push twoSlotReaderPush1Op)
        (some (twoSlotReaderBalanceSlot, 1)) s0)
    (hsloadAt :
      ReadyOpcodeAt twoSlotReaderCode 2
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps))
        none (pushBalanceSlotPost s0 hpushAt.ready))
    (hsloadGas :
      SLoadGasSufficient
        (pushBalanceSlotPost s0 hpushAt.ready) twoSlotReaderBalanceSlot)
    (hstopAt :
      ReadyOpcodeAt twoSlotReaderCode 3
        (.StopArith (.STOP : EvmSemantics.Operation.StopArithOps))
        none
        (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready)
          hsloadGas)) :
    StepFEReductionChain s0 3
      (stopPost
        (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready) hsloadGas)) := by
  let s1 := pushBalanceSlotPost s0 hpushAt.ready
  let s2 := sloadBalanceSlotPost s1 hsloadGas
  let s3 := stopPost s2
  have pushReduction : StepFEReduction s0 s1 :=
    ProofForge.Backend.Evm.PowdrExec.reduction_push_data_at_ok
      (op := twoSlotReaderPush1Op) (value := twoSlotReaderBalanceSlot)
      (argBytes := 1) (widthPred := 0) hpushAt (by rfl)
  have sloadReduction : StepFEReduction s1 s2 :=
    ProofForge.Backend.Evm.PowdrExec.reduction_sload_at_ok
      (rest := s0.stack) hsloadAt
      (by
        simp [pushBalanceSlotPost,
          EvmSemantics.EVM.State.replaceStackAndIncrPC])
      hsloadGas
  have stopReduction : StepFEReduction s2 s3 :=
    ProofForge.Backend.Evm.PowdrExec.reduction_stop_at_ok hstopAt
  exact ProofForge.Backend.Evm.PowdrExec.stepFEReductionChain_three
    pushReduction sloadReduction stopReduction

theorem twoSlotReader_getBalance_executionSegment
    {s0 : State}
    (hpushAt :
      ReadyOpcodeAt twoSlotReaderCode 0 (.Push twoSlotReaderPush1Op)
        (some (twoSlotReaderBalanceSlot, 1)) s0)
    (hsloadAt :
      ReadyOpcodeAt twoSlotReaderCode 2
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps))
        none (pushBalanceSlotPost s0 hpushAt.ready))
    (hsloadGas :
      SLoadGasSufficient
        (pushBalanceSlotPost s0 hpushAt.ready) twoSlotReaderBalanceSlot)
    (hstopAt :
      ReadyOpcodeAt twoSlotReaderCode 3
        (.StopArith (.STOP : EvmSemantics.Operation.StopArithOps))
        none
        (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready)
          hsloadGas)) :
    ExecutionSegment 3 twoSlotReaderGetBalancePost s0
      (stopPost
        (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready) hsloadGas)) := by
  exact ProofForge.Backend.Evm.PowdrExec.executionSegment_of_reductionChain
    (twoSlotReader_getBalance_reductionChain hpushAt hsloadAt hsloadGas hstopAt)
    (by
      exact
        ⟨hpushAt, hsloadAt, hsloadGas, hstopAt, rfl⟩)

theorem twoSlotReader_getBalance_stepFEPath
    {s0 : State}
    (hpushAt :
      ReadyOpcodeAt twoSlotReaderCode 0 (.Push twoSlotReaderPush1Op)
        (some (twoSlotReaderBalanceSlot, 1)) s0)
    (hsloadAt :
      ReadyOpcodeAt twoSlotReaderCode 2
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps))
        none (pushBalanceSlotPost s0 hpushAt.ready))
    (hsloadGas :
      SLoadGasSufficient
        (pushBalanceSlotPost s0 hpushAt.ready) twoSlotReaderBalanceSlot)
    (hstopAt :
      ReadyOpcodeAt twoSlotReaderCode 3
        (.StopArith (.STOP : EvmSemantics.Operation.StopArithOps))
        none
        (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready)
          hsloadGas)) :
    StepFEPath s0 3
      (stopPost
        (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready) hsloadGas)) :=
  (twoSlotReader_getBalance_executionSegment hpushAt
    hsloadAt hsloadGas hstopAt).path

def twoSlotReaderGetBalancePrefixReductionChainProvider :
    ReductionChainProvider twoSlotReaderGetBalancePre 2
      twoSlotReaderGetBalancePrefixPost where
  chain := by
    intro s0 hpre
    rcases hpre with
      ⟨hpushAt, hsloadAt, hsloadGas, hstopAt, _⟩
    let s1 := pushBalanceSlotPost s0 hpushAt.ready
    let s2 := sloadBalanceSlotPost s1 hsloadGas
    have pushReduction : StepFEReduction s0 s1 :=
      ProofForge.Backend.Evm.PowdrExec.reduction_push_data_at_ok
        (op := twoSlotReaderPush1Op) (value := twoSlotReaderBalanceSlot)
        (argBytes := 1) (widthPred := 0) hpushAt (by rfl)
    have sloadReduction : StepFEReduction s1 s2 :=
      ProofForge.Backend.Evm.PowdrExec.reduction_sload_at_ok
        (rest := s0.stack) hsloadAt
        (by
          simp [pushBalanceSlotPost,
            EvmSemantics.EVM.State.replaceStackAndIncrPC])
        hsloadGas
    have prefixChain : StepFEReductionChain s0 2 s2 :=
      ProofForge.Backend.Evm.PowdrExec.stepFEReductionChain_two
        pushReduction sloadReduction
    exact ⟨s2, prefixChain,
      ⟨hpushAt, hsloadAt, hsloadGas, hstopAt, rfl⟩⟩

def twoSlotReaderStopReductionChainProvider :
    ReductionChainProvider twoSlotReaderStopPre 1
      twoSlotReaderStopPost :=
  ProofForge.Backend.Evm.PowdrExec.reductionChainProvider_single_of_exists
    (by
      intro s2 hpre
      rcases hpre with
        ⟨s0, hpushAt, _hsloadAt, hsloadGas, hstopAt, hs2⟩
      have stopReduction : StepFEReduction s2 (stopPost s2) := by
        subst s2
        exact ProofForge.Backend.Evm.PowdrExec.reduction_stop_at_ok hstopAt
      have hpost : twoSlotReaderStopPost s2 (stopPost s2) := by
        intro s0' hpushAt' hsloadAt' hsloadGas' hstopAt' hs2'
        exact congrArg stopPost hs2'
      exact ⟨stopPost s2, stopReduction, hpost⟩)

def twoSlotReaderGetBalanceReductionChainProviderFromAppend :
    ReductionChainProvider twoSlotReaderGetBalancePre 3
      twoSlotReaderGetBalancePost :=
  ProofForge.Backend.Evm.PowdrExec.reductionChainProvider_append
    twoSlotReaderGetBalancePrefixReductionChainProvider
    twoSlotReaderStopReductionChainProvider
    (by
      intro s0 s2 _hpre hprefix
      exact ⟨s0, hprefix⟩)
    (by
      intro _s0 _s2 _finalState _hpre hprefix hstopPost
      rcases hprefix with
        ⟨hpushAt, hsloadAt, hsloadGas, hstopAt, hs2⟩
      exact ⟨hpushAt, hsloadAt, hsloadGas, hstopAt,
        hstopPost hpushAt hsloadAt hsloadGas hstopAt hs2⟩)

def twoSlotReaderGetBalanceReductionChainProvider :
    ReductionChainProvider twoSlotReaderGetBalancePre 3
      twoSlotReaderGetBalancePost :=
  twoSlotReaderGetBalanceReductionChainProviderFromAppend

def twoSlotReaderGetBalanceSegmentProvider :
    SegmentProvider twoSlotReaderGetBalancePre 3
      twoSlotReaderGetBalancePost :=
  ProofForge.Backend.Evm.PowdrExec.segmentProvider_of_reductionChainProvider
    twoSlotReaderGetBalanceReductionChainProvider

theorem twoSlotReader_getBalance_runSteps_from_segmentProvider
    {s0 : State} (hpre : twoSlotReaderGetBalancePre s0) :
    ∃ finalState,
      ProofForge.Backend.Evm.PowdrExec.runSteps s0 3 =
        .ok
          (finalState,
            (#[] : Array ProofForge.Backend.Evm.PowdrExec.ObservableStep)) ∧
      twoSlotReaderGetBalancePost s0 finalState :=
  ProofForge.Backend.Evm.PowdrExec.runSteps_post_of_segmentProvider
    twoSlotReaderGetBalanceSegmentProvider hpre

theorem twoSlotReader_getBalance_runSteps_from_reductionChainProvider
    {s0 : State} (hpre : twoSlotReaderGetBalancePre s0) :
    ∃ finalState,
      ProofForge.Backend.Evm.PowdrExec.runSteps s0 3 =
        .ok
          (finalState,
            (#[] : Array ProofForge.Backend.Evm.PowdrExec.ObservableStep)) ∧
      twoSlotReaderGetBalancePost s0 finalState :=
  ProofForge.Backend.Evm.PowdrExec.runSteps_post_of_reductionChainProvider
    twoSlotReaderGetBalanceReductionChainProvider hpre

theorem twoSlotReader_getBalance_runSteps
    {s0 : State}
    (hpushAt :
      ReadyOpcodeAt twoSlotReaderCode 0 (.Push twoSlotReaderPush1Op)
        (some (twoSlotReaderBalanceSlot, 1)) s0)
    (hsloadAt :
      ReadyOpcodeAt twoSlotReaderCode 2
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps))
        none (pushBalanceSlotPost s0 hpushAt.ready))
    (hsloadGas :
      SLoadGasSufficient
        (pushBalanceSlotPost s0 hpushAt.ready) twoSlotReaderBalanceSlot)
    (hstopAt :
      ReadyOpcodeAt twoSlotReaderCode 3
        (.StopArith (.STOP : EvmSemantics.Operation.StopArithOps))
        none
        (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready)
          hsloadGas)) :
    ProofForge.Backend.Evm.PowdrExec.runSteps s0 3 =
      .ok
        (stopPost
          (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready) hsloadGas),
          (#[] : Array ProofForge.Backend.Evm.PowdrExec.ObservableStep)) :=
  ProofForge.Backend.Evm.PowdrExec.runSteps_of_executionSegment
    (twoSlotReader_getBalance_executionSegment hpushAt
      hsloadAt hsloadGas hstopAt)

theorem twoSlotReader_getBalance_runSteps_from_reductionChain
    {s0 : State}
    (hpushAt :
      ReadyOpcodeAt twoSlotReaderCode 0 (.Push twoSlotReaderPush1Op)
        (some (twoSlotReaderBalanceSlot, 1)) s0)
    (hsloadAt :
      ReadyOpcodeAt twoSlotReaderCode 2
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps))
        none (pushBalanceSlotPost s0 hpushAt.ready))
    (hsloadGas :
      SLoadGasSufficient
        (pushBalanceSlotPost s0 hpushAt.ready) twoSlotReaderBalanceSlot)
    (hstopAt :
      ReadyOpcodeAt twoSlotReaderCode 3
        (.StopArith (.STOP : EvmSemantics.Operation.StopArithOps))
        none
        (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready)
          hsloadGas)) :
    ProofForge.Backend.Evm.PowdrExec.runSteps s0 3 =
      .ok
        (stopPost
          (sloadBalanceSlotPost (pushBalanceSlotPost s0 hpushAt.ready) hsloadGas),
          (#[] : Array ProofForge.Backend.Evm.PowdrExec.ObservableStep)) := by
  exact ProofForge.Backend.Evm.PowdrExec.runSteps_of_reductionChain
    (twoSlotReader_getBalance_reductionChain hpushAt hsloadAt hsloadGas hstopAt)

theorem mstore_word_runSteps
    {s0 : State} {offset value : UInt256} {rest : List UInt256}
    (hat :
      ReadyOpcodeAt mstoreWordCode 0
        (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps))
        none s0)
    (hstack : s0.stack = offset :: value :: rest)
    (hmem :
      MemoryExpansionSufficientAfterBase s0
        (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps) :
          Operation)
        hat.ready.gas offset.toNat 32) :
    ProofForge.Backend.Evm.PowdrExec.runSteps s0 1 =
      .ok
        (({ (s0.consumeGas
          (EvmSemantics.EVM.Gas.baseCost s0.fork
            (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas).consumeMemExp offset.toNat 32 hmem with
          toMachineState :=
            EvmSemantics.MachineState.mstore
              ((s0.consumeGas
                (EvmSemantics.EVM.Gas.baseCost s0.fork
                  (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps) :
                    Operation)) hat.ready.gas).consumeMemExp offset.toNat 32 hmem).toMachineState
              offset value }.replaceStackAndIncrPC rest),
          (#[] : Array ProofForge.Backend.Evm.PowdrExec.ObservableStep)) := by
  have chain :
      StepFEReductionChain s0 1
        ({ (s0.consumeGas
          (EvmSemantics.EVM.Gas.baseCost s0.fork
            (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps) :
              Operation)) hat.ready.gas).consumeMemExp offset.toNat 32 hmem with
          toMachineState :=
            EvmSemantics.MachineState.mstore
              ((s0.consumeGas
                (EvmSemantics.EVM.Gas.baseCost s0.fork
                  (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps) :
                    Operation)) hat.ready.gas).consumeMemExp offset.toNat 32 hmem).toMachineState
              offset value }.replaceStackAndIncrPC rest) :=
    ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain.single
      (ProofForge.Backend.Evm.PowdrExec.reduction_mstore_at_ok
        (offset := offset) (value := value) (rest := rest) hat hstack hmem)
  exact ProofForge.Backend.Evm.PowdrExec.runSteps_of_reductionChain chain

end ProofForge.Backend.Evm.PowdrExecSmoke
