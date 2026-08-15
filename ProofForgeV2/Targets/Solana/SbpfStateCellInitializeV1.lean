import ProofForgeV2.Targets.Solana.ProductionProviderV1
import ProofForgeV2.Targets.Solana.SbpfStateCellGetV1

/-!
# Solana StateCell `initialize` provider certificate

Kernel-checkable certificate for the exact 55-step production StateCell
`initialize` path. The executable gate binds the complete sparse fetch manifest
and concrete Loader reads to the identity-bound production artifact, then
requires the pinned provider to remain live after 54 steps and halt successfully
after step 55 with the exact initialized account window.

The soundness theorem recovers an exact `Steps` derivation through the existing
`runFuel` adequacy theorem. This module defines neither another sBPF evaluator
nor another ProofForge business transition.
-/

namespace ProofForgeV2.Targets.Solana

open SbpfSemantics

/-- Exact entrypoint and initialize-dispatch fetches. -/
def StateCellInitializeDispatchLookupsV1 (p : Program) : Prop :=
  p[0]? = some (.binReg .Mov64Reg 6 1) ∧
  p[1]? = some (.loadMem .Ldxdw 1 6 0) ∧
  p[2]? = some (.jumpImm .JneImm 1 1 5) ∧
  p[3]? = some (.loadMem .Ldxb 1 6 8) ∧
  p[4]? = some (.jumpImm .JneImm 1 255 3) ∧
  p[5]? = some (.loadMem .Ldxdw 1 6 10360) ∧
  p[6]? = some (.jumpImm .JltImm 1 8 1) ∧
  p[7]? = some (.ja 2) ∧
  p[10]? = some (.loadMem .Ldxdw 1 6 10368) ∧
  p[11]? = some (.lddw 2 7217115878876727646) ∧
  p[12]? = some (.jumpReg .JneReg 1 2 2) ∧
  p[13]? = some (.callRel 11)

instance (p : Program) : Decidable (StateCellInitializeDispatchLookupsV1 p) := by
  unfold StateCellInitializeDispatchLookupsV1
  infer_instance

/-- Exact Loader, authority, flag, and uninitialized-marker validation
    fetches within the initialize body. -/
def StateCellInitializeValidationLookupsV1 (p : Program) : Prop :=
  p[25]? = some (.loadMem .Ldxdw 1 6 0) ∧
  p[26]? = some (.jumpImm .JneImm 1 1 30) ∧
  p[27]? = some (.loadMem .Ldxb 1 6 8) ∧
  p[28]? = some (.jumpImm .JneImm 1 255 28) ∧
  p[29]? = some (.loadMem .Ldxdw 1 6 10360) ∧
  p[30]? = some (.jumpImm .JneImm 1 16 26) ∧
  p[31]? = some (.loadMem .Ldxdw 1 6 10360) ∧
  p[32]? = some (.binReg .Mov64Reg 2 6) ∧
  p[33]? = some (.binImm .Add64Imm 2 10368) ∧
  p[34]? = some (.binReg .Add64Reg 2 1) ∧
  p[35]? = some (.loadMem .Ldxdw 1 6 48) ∧
  p[36]? = some (.loadMem .Ldxdw 3 2 0) ∧
  p[37]? = some (.jumpReg .JneReg 1 3 19) ∧
  p[38]? = some (.loadMem .Ldxdw 1 6 56) ∧
  p[39]? = some (.loadMem .Ldxdw 3 2 8) ∧
  p[40]? = some (.jumpReg .JneReg 1 3 16) ∧
  p[41]? = some (.loadMem .Ldxdw 1 6 64) ∧
  p[42]? = some (.loadMem .Ldxdw 3 2 16) ∧
  p[43]? = some (.jumpReg .JneReg 1 3 13) ∧
  p[44]? = some (.loadMem .Ldxdw 1 6 72) ∧
  p[45]? = some (.loadMem .Ldxdw 3 2 24) ∧
  p[46]? = some (.jumpReg .JneReg 1 3 10) ∧
  p[47]? = some (.loadMem .Ldxdw 1 6 88) ∧
  p[48]? = some (.jumpImm .JneImm 1 16 8) ∧
  p[49]? = some (.loadMem .Ldxb 1 6 9) ∧
  p[50]? = some (.jumpImm .JeqImm 1 0 6) ∧
  p[51]? = some (.loadMem .Ldxb 1 6 10) ∧
  p[52]? = some (.jumpImm .JeqImm 1 0 4) ∧
  p[53]? = some (.loadMem .Ldxdw 1 6 96) ∧
  p[54]? = some (.lddw 2 0) ∧
  p[55]? = some (.jumpReg .JneReg 1 2 1) ∧
  p[56]? = some (.ja 2)

instance (p : Program) :
    Decidable (StateCellInitializeValidationLookupsV1 p) := by
  unfold StateCellInitializeValidationLookupsV1
  infer_instance

/-- Exact state writes and two-level return fetches. -/
def StateCellInitializeCommitLookupsV1 (p : Program) : Prop :=
  p[59]? = some (.lddw 1 0) ∧
  p[60]? = some (.storeReg .Stxdw 6 1 104) ∧
  p[61]? = some (.loadMem .Ldxdw 1 6 10376) ∧
  p[62]? = some (.storeReg .Stxdw 10 1 (BitVec.ofInt 16 (-8))) ∧
  p[63]? = some (.loadMem .Ldxdw 1 10 (BitVec.ofInt 16 (-8))) ∧
  p[64]? = some (.storeReg .Stxdw 6 1 104) ∧
  p[65]? = some (.lddw 1 846264958600013564) ∧
  p[66]? = some (.storeReg .Stxdw 6 1 96) ∧
  p[67]? = some (.lddw 0 0) ∧
  p[68]? = some .exit ∧
  p[14]? = some .exit

instance (p : Program) : Decidable (StateCellInitializeCommitLookupsV1 p) := by
  unfold StateCellInitializeCommitLookupsV1
  infer_instance

/-- The exact 55 fetched instructions on the successful production
    `initialize` path. This aggregates sparse lookup predicates over the
    resolved production program; it is not a copied executable program. -/
structure StateCellInitializeProgramLookupsV1 (p : Program) : Prop where
  dispatch : StateCellInitializeDispatchLookupsV1 p
  validation : StateCellInitializeValidationLookupsV1 p
  commit : StateCellInitializeCommitLookupsV1 p

instance (p : Program) : Decidable (StateCellInitializeProgramLookupsV1 p) := by
  let checks : Prop :=
    StateCellInitializeDispatchLookupsV1 p ∧
    StateCellInitializeValidationLookupsV1 p ∧
    StateCellInitializeCommitLookupsV1 p
  apply decidable_of_iff checks
  constructor
  · rintro ⟨dispatch, validation, commit⟩
    exact ⟨dispatch, validation, commit⟩
  · intro h
    exact ⟨h.dispatch, h.validation, h.commit⟩

/-- Executable identity and sparse-fetch gate for the production artifact. -/
def checkStateCellInitializeArtifactV1
    (bound : BoundResolvedSbpfArtifactV1) : Bool :=
  let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
  decide (artifact.sourceSha256 = stateCellProductionSbpfSha256V1) &&
    decide (StateCellInitializeProgramLookupsV1 artifact.program)

theorem checkStateCellInitializeArtifactV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (checked : checkStateCellInitializeArtifactV1 bound = true) :
    let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
    artifact.sourceSha256 = stateCellProductionSbpfSha256V1 ∧
      StateCellInitializeProgramLookupsV1 artifact.program := by
  simpa [checkStateCellInitializeArtifactV1] using checked

/-- Concrete Loader reads consumed by the successful `initialize` path. Owner
    equality is kept as four present equal reads; no program-id value is
    invented by this certificate. -/
def StateCellInitializeInputReadChecksV1
    (input : Array UInt8) (argument : Word) : Prop :=
  let memory := (Machine.entry input).mem
  memory.readU64 (inputStart + 0#64) = some 1 ∧
  memory.readU8 (inputStart + 8#64) = some 255 ∧
  memory.readU64 (inputStart + 10360#64) = some 16 ∧
  memory.readU64 (inputStart + 10368#64) =
    some 7217115878876727646 ∧
  memory.readU64 (inputStart + 48#64) =
    memory.readU64 (inputStart + 10384#64) ∧
  memory.readU64 (inputStart + 48#64) ≠ none ∧
  memory.readU64 (inputStart + 56#64) =
    memory.readU64 (inputStart + 10392#64) ∧
  memory.readU64 (inputStart + 56#64) ≠ none ∧
  memory.readU64 (inputStart + 64#64) =
    memory.readU64 (inputStart + 10400#64) ∧
  memory.readU64 (inputStart + 64#64) ≠ none ∧
  memory.readU64 (inputStart + 72#64) =
    memory.readU64 (inputStart + 10408#64) ∧
  memory.readU64 (inputStart + 72#64) ≠ none ∧
  memory.readU64 (inputStart + 88#64) = some 16 ∧
  memory.readU8 (inputStart + 9#64) = some 1 ∧
  memory.readU8 (inputStart + 10#64) = some 1 ∧
  memory.readU64 (inputStart + 96#64) = some 0 ∧
  memory.readU64 (inputStart + 10376#64) = some argument

instance (input : Array UInt8) (argument : Word) :
    Decidable (StateCellInitializeInputReadChecksV1 input argument) := by
  unfold StateCellInitializeInputReadChecksV1
  infer_instance

def checkStateCellInitializeInputReadsV1
    (input : Array UInt8) (argument : Word) : Bool :=
  decide (StateCellInitializeInputReadChecksV1 input argument)

theorem checkStateCellInitializeInputReadsV1_sound
    (input : Array UInt8) (argument : Word)
    (checked : checkStateCellInitializeInputReadsV1 input argument = true) :
    StateCellInitializeInputReadChecksV1 input argument := by
  exact of_decide_eq_true (by
    simpa [checkStateCellInitializeInputReadsV1] using checked)

/-- Exact account bytes produced by the production initialize body. -/
def stateCellInitializeFinalAccountDataV1 (argument : Word) : Array UInt8 :=
  (wordToLE (BitVec.ofNat 64 846264958600013564)).append
    (wordToLE argument)

/-- Final provider facts retained by the initialize certificate. -/
structure StateCellInitializeReturnedV1
    (input : Array UInt8) (argument : Word) (machine : Machine) : Prop where
  pc : machine.pc = 14
  halted : machine.halted = some 0
  frames : machine.frames = []
  returnData : machine.returnData = #[]
  result : machine.getReg 0 = 0
  framePointer : machine.getReg 10 = (Machine.entry input).getReg 10
  finalAccountData :
    machine.mem.readBytes (inputStart + BitVec.ofNat 64 accountDataOffsetV1) 16 =
      some (stateCellInitializeFinalAccountDataV1 argument)

instance (input : Array UInt8) (argument : Word) (machine : Machine) :
    Decidable (StateCellInitializeReturnedV1 input argument machine) := by
  let checks : Prop :=
    machine.pc = 14 ∧
    machine.halted = some 0 ∧
    machine.frames = [] ∧
    machine.returnData = #[] ∧
    machine.getReg 0 = 0 ∧
    machine.getReg 10 = (Machine.entry input).getReg 10 ∧
    machine.mem.readBytes
      (inputStart + BitVec.ofNat 64 accountDataOffsetV1) 16 =
        some (stateCellInitializeFinalAccountDataV1 argument)
  apply decidable_of_iff checks
  constructor
  · rintro ⟨hpc, hhalted, hframes, hreturn, hresult, hfp, hdata⟩
    exact ⟨hpc, hhalted, hframes, hreturn, hresult, hfp, hdata⟩
  · intro h
    exact ⟨h.pc, h.halted, h.frames, h.returnData, h.result,
      h.framePointer, h.finalAccountData⟩

/-- Provider result checks that make the exact step count observable: fuel 54
    is exhausted while the machine is live, and fuel 55 halts successfully. -/
def StateCellInitializeTraceResultChecksV1
    (p : Program) (input : Array UInt8) (argument : Word) : Prop :=
  let before := runFuel asmDefaultHost p 54 (Machine.entry input)
  let final := runFuel asmDefaultHost p 55 (Machine.entry input)
  before.2 = .outOfFuel ∧
  final.2 = .halted 0 ∧
  StateCellInitializeReturnedV1 input argument final.1

instance (p : Program) (input : Array UInt8) (argument : Word) :
    Decidable (StateCellInitializeTraceResultChecksV1 p input argument) := by
  unfold StateCellInitializeTraceResultChecksV1
  infer_instance

/-- One executable gate for the identity, sparse fetches, concrete input reads,
    exact 55-step boundary, and final account observation. -/
def checkStateCellInitializeTraceV1
    (bound : BoundResolvedSbpfArtifactV1)
    (input : Array UInt8) (argument : Word) : Bool :=
  let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
  checkStateCellInitializeArtifactV1 bound &&
    (checkSingleAccountExecutionWindowV1 bound accountDataOffsetV1 16 &&
      (decide (input.size ≤ maxSbpfInputImageBytesV1) &&
        (checkStateCellInitializeInputReadsV1 input argument &&
          decide (StateCellInitializeTraceResultChecksV1 artifact.program input
            argument))))

private theorem checkStateCellInitializeTraceV1_parts
    (bound : BoundResolvedSbpfArtifactV1)
    (input : Array UInt8) (argument : Word)
    (checked : checkStateCellInitializeTraceV1 bound input argument = true) :
    checkStateCellInitializeArtifactV1 bound = true ∧
    checkSingleAccountExecutionWindowV1 bound accountDataOffsetV1 16 = true ∧
    input.size ≤ maxSbpfInputImageBytesV1 ∧
    checkStateCellInitializeInputReadsV1 input argument = true ∧
    let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
    StateCellInitializeTraceResultChecksV1 artifact.program input argument := by
  simpa only [checkStateCellInitializeTraceV1, Bool.and_eq_true,
    decide_eq_true_eq] using checked

/-- The 54/55 fuel boundary and provider adequacy imply exactly 55 relational
    provider steps, rather than merely a run of at most 55 steps. -/
private theorem stateCellInitialize_exactStepsV1
    (p : Program) (input : Array UInt8) (machine : Machine)
    (prefixOutcome :
      (runFuel asmDefaultHost p 54 (Machine.entry input)).2 = .outOfFuel)
    (providerRun :
      runFuel asmDefaultHost p 55 (Machine.entry input) =
        (machine, .halted 0)) :
    Steps asmDefaultHost p 55 (Machine.entry input) machine := by
  rcases runFuel_halted_steps asmDefaultHost p 55 (Machine.entry input)
      machine 0 providerRun with ⟨steps, hbounded, hsteps, hhalted⟩
  have hnotShort : ¬ steps ≤ 54 := by
    intro hshort
    have hshortRun := steps_runFuel_halted asmDefaultHost p steps 54
      (Machine.entry input) machine 0 hsteps hhalted hshort
    have houtcome := congrArg Prod.snd hshortRun
    rw [prefixOutcome] at houtcome
    cases houtcome
  have hexact : steps = 55 := by omega
  simpa [hexact] using hsteps

/-- Proof-bearing provider certificate for the exact production initialize
    execution. Sparse lookups and reads remain available for audit, while the
    `Steps` field is derived from the provider's own interpreter. -/
structure StateCellInitializeProviderCertificateV1
    (bound : BoundResolvedSbpfArtifactV1)
    (input : Array UInt8) (argument : Word) where
  machine : Machine
  sourceIdentity :
    (BoundResolvedSbpfArtifactV1.resolvedOf bound).sourceSha256 =
      stateCellProductionSbpfSha256V1
  programLookups :
    StateCellInitializeProgramLookupsV1
      (BoundResolvedSbpfArtifactV1.resolvedOf bound).program
  inputReads : StateCellInitializeInputReadChecksV1 input argument
  providerRun :
    runFuel asmDefaultHost
      (BoundResolvedSbpfArtifactV1.resolvedOf bound).program 55
      (Machine.entry input) = (machine, .halted 0)
  providerSteps :
    Steps asmDefaultHost
      (BoundResolvedSbpfArtifactV1.resolvedOf bound).program 55
      (Machine.entry input) machine
  returned : StateCellInitializeReturnedV1 input argument machine

/-- Soundness of the complete trace gate. -/
theorem checkStateCellInitializeTraceV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (input : Array UInt8) (argument : Word)
    (checked : checkStateCellInitializeTraceV1 bound input argument = true) :
    Nonempty (StateCellInitializeProviderCertificateV1 bound input argument) := by
  have hparts :=
    checkStateCellInitializeTraceV1_parts bound input argument checked
  have hartifact :=
    checkStateCellInitializeArtifactV1_sound bound hparts.1
  have hreads :=
    checkStateCellInitializeInputReadsV1_sound input argument hparts.2.2.2.1
  let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
  let final := runFuel asmDefaultHost artifact.program 55 (Machine.entry input)
  have htrace :
      StateCellInitializeTraceResultChecksV1 artifact.program input argument :=
    hparts.2.2.2.2
  have hrun :
      runFuel asmDefaultHost artifact.program 55 (Machine.entry input) =
        (final.1, .halted 0) := by
    apply Prod.ext
    · rfl
    · exact htrace.2.1
  have hsteps := stateCellInitialize_exactStepsV1 artifact.program input final.1
    htrace.1 hrun
  exact ⟨{
    machine := final.1
    sourceIdentity := hartifact.1
    programLookups := hartifact.2
    inputReads := hreads
    providerRun := hrun
    providerSteps := hsteps
    returned := htrace.2.2
  }⟩

/-- End-to-end gate from the real Loader encoder into the certified trace. -/
def checkStateCellInitializeExecutionV1
    (bound : BoundResolvedSbpfArtifactV1)
    (invocation : LoaderV3SingleAccountInvocationV1)
    (argument : Word) : Bool :=
  match encodeLoaderV3SingleAccountInputV1 bound invocation with
  | .error _ => false
  | .ok input => checkStateCellInitializeTraceV1 bound input argument

/-- Encoder and provider-execution equations retained alongside the sparse
    trace certificate. -/
structure CertifiedStateCellInitializeExecutionV1
    (bound : BoundResolvedSbpfArtifactV1)
    (invocation : LoaderV3SingleAccountInvocationV1)
    (argument : Word) where
  input : Array UInt8
  certificate : StateCellInitializeProviderCertificateV1 bound input argument
  execution : CertifiedSolanaProductionProviderExecutionV1 bound invocation
    55 0 accountDataOffsetV1 16 input certificate.machine

namespace CertifiedStateCellInitializeExecutionV1

def encodedInput (certified :
    CertifiedStateCellInitializeExecutionV1 bound invocation argument) :=
  certified.execution.encodedInput

def providerExecution (certified :
    CertifiedStateCellInitializeExecutionV1 bound invocation argument) :=
  certified.execution.providerExecution

end CertifiedStateCellInitializeExecutionV1

/-- Soundness of the end-to-end initialize execution gate. -/
theorem checkStateCellInitializeExecutionV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (invocation : LoaderV3SingleAccountInvocationV1)
    (argument : Word)
    (checked :
      checkStateCellInitializeExecutionV1 bound invocation argument = true) :
    Nonempty (CertifiedStateCellInitializeExecutionV1 bound invocation
      argument) := by
  unfold checkStateCellInitializeExecutionV1 at checked
  cases hencode : encodeLoaderV3SingleAccountInputV1 bound invocation with
  | error error => simp [hencode] at checked
  | ok input =>
      rw [hencode] at checked
      rcases checkStateCellInitializeTraceV1_sound bound input argument checked
        with ⟨certificate⟩
      have hwindow := checkSingleAccountExecutionWindowV1_sound bound
        accountDataOffsetV1 16
        (checkStateCellInitializeTraceV1_parts bound input argument checked).2.1
      have hraw := runBoundSbpfArtifactV1_eq_ok_of_runFuel bound input 55
        accountDataOffsetV1 16 certificate.machine (.halted 0) hwindow
        (by decide) (by decide)
        (checkStateCellInitializeTraceV1_parts bound input argument checked).2.2.1
        certificate.providerRun
      exact ⟨{
        input
        certificate
        execution := {
          encodedInput := hencode
          providerExecution :=
            executeLoaderV3SingleAccountV1_eq_ok bound invocation 55 input _
              hencode hraw
        }
      }⟩

end ProofForgeV2.Targets.Solana
