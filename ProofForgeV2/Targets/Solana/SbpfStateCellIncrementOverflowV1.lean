import ProofForgeV2.Targets.Solana.ProductionProviderV1
import ProofForgeV2.Targets.Solana.SbpfStateCellIncrementV1

/-!
# Solana StateCell `increment` overflow provider certificate

Kernel-checkable certificate for the exact 56-step production StateCell
`increment` arithmetic-overflow path. The executable gate reuses the successful
path's shared dispatch, validation, and concrete Loader-read contracts, binds
the overflow suffix to the identity-bound production artifact, and requires the
pinned provider to remain live after 55 steps before halting with status
`0x1001` at step 56 without changing the account or publishing return data.

The soundness theorem recovers an exact `Steps` derivation through the existing
`runFuel` adequacy theorem. This module defines neither another sBPF evaluator
nor another ProofForge business transition.
-/

namespace ProofForgeV2.Targets.Solana

open SbpfSemantics

/-- Exact checked-add overflow branch and two-level exit fetches. -/
def StateCellIncrementOverflowLookupsV1 (p : Program) : Prop :=
  p[101]? = some (.loadMem .Ldxdw 1 6 104) ∧
  p[102]? = some (.storeReg .Stxdw 10 1 (BitVec.ofInt 16 (-8))) ∧
  p[103]? = some (.loadMem .Ldxdw 1 6 10376) ∧
  p[104]? = some (.storeReg .Stxdw 10 1 (BitVec.ofInt 16 (-16))) ∧
  p[105]? = some (.loadMem .Ldxdw 1 10 (BitVec.ofInt 16 (-8))) ∧
  p[106]? = some (.loadMem .Ldxdw 2 10 (BitVec.ofInt 16 (-16))) ∧
  p[107]? = some (.lddw 3 18446744073709551615) ∧
  p[108]? = some (.binReg .Sub64Reg 3 2) ∧
  p[109]? = some (.jumpReg .JgtReg 1 3 4) ∧
  p[114]? = some (.lddw 0 4097) ∧
  p[115]? = some .exit ∧
  p[18]? = some .exit

instance (p : Program) : Decidable (StateCellIncrementOverflowLookupsV1 p) := by
  unfold StateCellIncrementOverflowLookupsV1
  infer_instance

/-- The exact 56 fetched instructions on the production increment-overflow
    path. Shared dispatch and validation predicates come from the successful
    increment certificate; no executable program is copied here. -/
structure StateCellIncrementOverflowProgramLookupsV1 (p : Program) : Prop where
  dispatch : StateCellIncrementDispatchLookupsV1 p
  validation : StateCellIncrementValidationLookupsV1 p
  overflow : StateCellIncrementOverflowLookupsV1 p

instance (p : Program) :
    Decidable (StateCellIncrementOverflowProgramLookupsV1 p) := by
  let checks : Prop :=
    StateCellIncrementDispatchLookupsV1 p ∧
    StateCellIncrementValidationLookupsV1 p ∧
    StateCellIncrementOverflowLookupsV1 p
  apply decidable_of_iff checks
  constructor
  · rintro ⟨dispatch, validation, overflow⟩
    exact ⟨dispatch, validation, overflow⟩
  · intro h
    exact ⟨h.dispatch, h.validation, h.overflow⟩

/-- Executable identity and sparse-fetch gate for the production artifact. -/
def checkStateCellIncrementOverflowArtifactV1
    (bound : BoundResolvedSbpfArtifactV1) : Bool :=
  let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
  decide (artifact.sourceSha256 = stateCellProductionSbpfSha256V1) &&
    decide (StateCellIncrementOverflowProgramLookupsV1 artifact.program)

theorem checkStateCellIncrementOverflowArtifactV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (checked : checkStateCellIncrementOverflowArtifactV1 bound = true) :
    let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
    artifact.sourceSha256 = stateCellProductionSbpfSha256V1 ∧
      StateCellIncrementOverflowProgramLookupsV1 artifact.program := by
  simpa [checkStateCellIncrementOverflowArtifactV1] using checked

/-- The overflow path consumes the same concrete Loader reads as increment
    success before the arithmetic branch diverges. -/
def checkStateCellIncrementOverflowInputReadsV1
    (input : Array UInt8) (before argument : Word) : Bool :=
  checkStateCellIncrementInputReadsV1 input before argument

theorem checkStateCellIncrementOverflowInputReadsV1_sound
    (input : Array UInt8) (before argument : Word)
    (checked : checkStateCellIncrementOverflowInputReadsV1 input before
      argument = true) :
    StateCellIncrementInputReadChecksV1 input before argument := by
  exact checkStateCellIncrementInputReadsV1_sound input before argument checked

/-- Emitted arithmetic-overflow status. -/
def stateCellIncrementOverflowStatusV1 : Word := BitVec.ofNat 64 0x1001

/-- Exact unchanged account bytes retained by the overflow path. -/
def stateCellIncrementOverflowAccountDataV1 (before : Word) : Array UInt8 :=
  (wordToLE (BitVec.ofNat 64 846264958600013564)).append
    (wordToLE before)

/-- Final provider facts retained by the increment-overflow certificate. -/
structure StateCellIncrementOverflowReturnedV1
    (input : Array UInt8) (before : Word) (machine : Machine) : Prop where
  pc : machine.pc = 18
  halted : machine.halted = some stateCellIncrementOverflowStatusV1
  frames : machine.frames = []
  returnData : machine.returnData = #[]
  result : machine.getReg 0 = stateCellIncrementOverflowStatusV1
  framePointer : machine.getReg 10 = (Machine.entry input).getReg 10
  unchangedAccountData :
    machine.mem.readBytes (inputStart + BitVec.ofNat 64 accountDataOffsetV1) 16 =
      some (stateCellIncrementOverflowAccountDataV1 before)

instance (input : Array UInt8) (before : Word) (machine : Machine) :
    Decidable (StateCellIncrementOverflowReturnedV1 input before machine) := by
  let checks : Prop :=
    machine.pc = 18 ∧
    machine.halted = some stateCellIncrementOverflowStatusV1 ∧
    machine.frames = [] ∧
    machine.returnData = #[] ∧
    machine.getReg 0 = stateCellIncrementOverflowStatusV1 ∧
    machine.getReg 10 = (Machine.entry input).getReg 10 ∧
    machine.mem.readBytes
      (inputStart + BitVec.ofNat 64 accountDataOffsetV1) 16 =
        some (stateCellIncrementOverflowAccountDataV1 before)
  apply decidable_of_iff checks
  constructor
  · rintro ⟨hpc, hhalted, hframes, hreturn, hresult, hfp, hdata⟩
    exact ⟨hpc, hhalted, hframes, hreturn, hresult, hfp, hdata⟩
  · intro h
    exact ⟨h.pc, h.halted, h.frames, h.returnData, h.result,
      h.framePointer, h.unchangedAccountData⟩

/-- Provider result checks that make the exact step count observable: fuel 55
    is exhausted while the machine is live, and fuel 56 halts with `0x1001`. -/
def StateCellIncrementOverflowTraceResultChecksV1
    (p : Program) (input : Array UInt8) (before : Word) : Prop :=
  let beforeRun := runFuel asmDefaultHost p 55 (Machine.entry input)
  let final := runFuel asmDefaultHost p 56 (Machine.entry input)
  beforeRun.2 = .outOfFuel ∧
  final.2 = .halted stateCellIncrementOverflowStatusV1 ∧
  StateCellIncrementOverflowReturnedV1 input before final.1

instance (p : Program) (input : Array UInt8) (before : Word) :
    Decidable
      (StateCellIncrementOverflowTraceResultChecksV1 p input before) := by
  unfold StateCellIncrementOverflowTraceResultChecksV1
  infer_instance

/-- One executable gate for identity, sparse fetches, concrete input reads,
    exact 56-step boundary, overflow status, and unchanged account bytes. -/
def checkStateCellIncrementOverflowTraceV1
    (bound : BoundResolvedSbpfArtifactV1)
    (input : Array UInt8) (before argument : Word) : Bool :=
  let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
  checkStateCellIncrementOverflowArtifactV1 bound &&
    (checkSingleAccountExecutionWindowV1 bound accountDataOffsetV1 16 &&
      (decide (input.size ≤ maxSbpfInputImageBytesV1) &&
        (checkStateCellIncrementOverflowInputReadsV1 input before argument &&
          decide (StateCellIncrementOverflowTraceResultChecksV1 artifact.program
            input before))))

private theorem checkStateCellIncrementOverflowTraceV1_parts
    (bound : BoundResolvedSbpfArtifactV1)
    (input : Array UInt8) (before argument : Word)
    (checked : checkStateCellIncrementOverflowTraceV1 bound input before
      argument = true) :
    checkStateCellIncrementOverflowArtifactV1 bound = true ∧
    checkSingleAccountExecutionWindowV1 bound accountDataOffsetV1 16 = true ∧
    input.size ≤ maxSbpfInputImageBytesV1 ∧
    checkStateCellIncrementOverflowInputReadsV1 input before argument = true ∧
    let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
    StateCellIncrementOverflowTraceResultChecksV1 artifact.program input
      before := by
  simpa only [checkStateCellIncrementOverflowTraceV1, Bool.and_eq_true,
    decide_eq_true_eq] using checked

/-- The 55/56 fuel boundary and provider adequacy imply exactly 56 relational
    provider steps. -/
private theorem stateCellIncrementOverflow_exactStepsV1
    (p : Program) (input : Array UInt8) (machine : Machine)
    (prefixOutcome :
      (runFuel asmDefaultHost p 55 (Machine.entry input)).2 = .outOfFuel)
    (providerRun :
      runFuel asmDefaultHost p 56 (Machine.entry input) =
        (machine, .halted stateCellIncrementOverflowStatusV1)) :
    Steps asmDefaultHost p 56 (Machine.entry input) machine := by
  rcases runFuel_halted_steps asmDefaultHost p 56 (Machine.entry input)
      machine stateCellIncrementOverflowStatusV1 providerRun with
    ⟨steps, hbounded, hsteps, hhalted⟩
  have hnotShort : ¬ steps ≤ 55 := by
    intro hshort
    have hshortRun := steps_runFuel_halted asmDefaultHost p steps 55
      (Machine.entry input) machine stateCellIncrementOverflowStatusV1 hsteps
      hhalted hshort
    have houtcome := congrArg Prod.snd hshortRun
    rw [prefixOutcome] at houtcome
    cases houtcome
  have hexact : steps = 56 := by omega
  simpa [hexact] using hsteps

/-- Proof-bearing provider certificate for the exact production overflow
    execution. -/
structure StateCellIncrementOverflowProviderCertificateV1
    (bound : BoundResolvedSbpfArtifactV1)
    (input : Array UInt8) (before argument : Word) where
  machine : Machine
  sourceIdentity :
    (BoundResolvedSbpfArtifactV1.resolvedOf bound).sourceSha256 =
      stateCellProductionSbpfSha256V1
  programLookups :
    StateCellIncrementOverflowProgramLookupsV1
      (BoundResolvedSbpfArtifactV1.resolvedOf bound).program
  inputReads : StateCellIncrementInputReadChecksV1 input before argument
  providerRun :
    runFuel asmDefaultHost
      (BoundResolvedSbpfArtifactV1.resolvedOf bound).program 56
      (Machine.entry input) =
        (machine, .halted stateCellIncrementOverflowStatusV1)
  providerSteps :
    Steps asmDefaultHost
      (BoundResolvedSbpfArtifactV1.resolvedOf bound).program 56
      (Machine.entry input) machine
  returned : StateCellIncrementOverflowReturnedV1 input before machine

/-- Soundness of the complete overflow trace gate. -/
theorem checkStateCellIncrementOverflowTraceV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (input : Array UInt8) (before argument : Word)
    (checked : checkStateCellIncrementOverflowTraceV1 bound input before
      argument = true) :
    Nonempty (StateCellIncrementOverflowProviderCertificateV1 bound input
      before argument) := by
  have hparts := checkStateCellIncrementOverflowTraceV1_parts bound input before
    argument checked
  have hartifact :=
    checkStateCellIncrementOverflowArtifactV1_sound bound hparts.1
  have hreads := checkStateCellIncrementOverflowInputReadsV1_sound input before
    argument hparts.2.2.2.1
  let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
  let final := runFuel asmDefaultHost artifact.program 56 (Machine.entry input)
  have htrace :
      StateCellIncrementOverflowTraceResultChecksV1 artifact.program input
        before := hparts.2.2.2.2
  have hrun :
      runFuel asmDefaultHost artifact.program 56 (Machine.entry input) =
        (final.1, .halted stateCellIncrementOverflowStatusV1) := by
    apply Prod.ext
    · rfl
    · exact htrace.2.1
  have hsteps := stateCellIncrementOverflow_exactStepsV1 artifact.program input
    final.1 htrace.1 hrun
  exact ⟨{
    machine := final.1
    sourceIdentity := hartifact.1
    programLookups := hartifact.2
    inputReads := hreads
    providerRun := hrun
    providerSteps := hsteps
    returned := htrace.2.2
  }⟩

/-- End-to-end gate from the real Loader encoder into the certified overflow
    trace. -/
def checkStateCellIncrementOverflowExecutionV1
    (bound : BoundResolvedSbpfArtifactV1)
    (invocation : LoaderV3SingleAccountInvocationV1)
    (before argument : Word) : Bool :=
  match encodeLoaderV3SingleAccountInputV1 bound invocation with
  | .error _ => false
  | .ok input =>
      checkStateCellIncrementOverflowTraceV1 bound input before argument

/-- Encoder and provider-execution equations retained alongside the overflow
    trace certificate. -/
structure CertifiedStateCellIncrementOverflowExecutionV1
    (bound : BoundResolvedSbpfArtifactV1)
    (invocation : LoaderV3SingleAccountInvocationV1)
    (before argument : Word) where
  input : Array UInt8
  certificate :
    StateCellIncrementOverflowProviderCertificateV1 bound input before argument
  execution : CertifiedSolanaProductionProviderExecutionV1 bound invocation
    56 stateCellIncrementOverflowStatusV1 accountDataOffsetV1 16 input
      certificate.machine

namespace CertifiedStateCellIncrementOverflowExecutionV1

def encodedInput (certified : CertifiedStateCellIncrementOverflowExecutionV1
    bound invocation before argument) :=
  certified.execution.encodedInput

def providerExecution (certified :
    CertifiedStateCellIncrementOverflowExecutionV1 bound invocation before
      argument) :=
  certified.execution.providerExecution

end CertifiedStateCellIncrementOverflowExecutionV1

/-- Soundness of the end-to-end increment-overflow execution gate. -/
theorem checkStateCellIncrementOverflowExecutionV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (invocation : LoaderV3SingleAccountInvocationV1)
    (before argument : Word)
    (checked : checkStateCellIncrementOverflowExecutionV1 bound invocation
      before argument = true) :
    Nonempty (CertifiedStateCellIncrementOverflowExecutionV1 bound invocation
      before argument) := by
  unfold checkStateCellIncrementOverflowExecutionV1 at checked
  cases hencode : encodeLoaderV3SingleAccountInputV1 bound invocation with
  | error error => simp [hencode] at checked
  | ok input =>
      rw [hencode] at checked
      rcases checkStateCellIncrementOverflowTraceV1_sound bound input before
          argument checked with ⟨certificate⟩
      have hwindow := checkSingleAccountExecutionWindowV1_sound bound
        accountDataOffsetV1 16
        (checkStateCellIncrementOverflowTraceV1_parts bound input before
          argument checked).2.1
      have hraw := runBoundSbpfArtifactV1_eq_ok_of_runFuel bound input 56
        accountDataOffsetV1 16 certificate.machine
        (.halted stateCellIncrementOverflowStatusV1) hwindow
        (by decide) (by decide)
        (checkStateCellIncrementOverflowTraceV1_parts bound input before
          argument checked).2.2.1 certificate.providerRun
      exact ⟨{
        input
        certificate
        execution := {
          encodedInput := hencode
          providerExecution :=
            executeLoaderV3SingleAccountV1_eq_ok bound invocation 56 input _
              hencode hraw
        }
      }⟩

end ProofForgeV2.Targets.Solana
