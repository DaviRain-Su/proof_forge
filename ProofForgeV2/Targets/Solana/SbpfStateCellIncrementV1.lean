import ProofForgeV2.Targets.Solana.ProductionProviderV1
import ProofForgeV2.Targets.Solana.SbpfStateCellGetV1

/-!
# Solana StateCell `increment` provider certificate

Kernel-checkable certificate for the exact 70-step successful production
StateCell `increment` path. The executable gate binds the complete sparse fetch
manifest and concrete Loader reads to the identity-bound production artifact,
then requires the pinned provider to remain live after 69 steps and halt
successfully after step 70 with the exact updated account and return bytes.

The soundness theorem recovers an exact `Steps` derivation through the existing
`runFuel` adequacy theorem. This module defines neither another sBPF evaluator
nor another ProofForge business transition.
-/

namespace ProofForgeV2.Targets.Solana

open SbpfSemantics

/-- Exact entrypoint and increment-dispatch fetches. -/
def StateCellIncrementDispatchLookupsV1 (p : Program) : Prop :=
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
  p[15]? = some (.lddw 2 2467651336600536989) ∧
  p[16]? = some (.jumpReg .JneReg 1 2 2) ∧
  p[17]? = some (.callRel 51)

instance (p : Program) : Decidable (StateCellIncrementDispatchLookupsV1 p) := by
  unfold StateCellIncrementDispatchLookupsV1
  infer_instance

/-- Exact Loader, authority, writable, and initialized-marker validation
    fetches within the increment body. -/
def StateCellIncrementValidationLookupsV1 (p : Program) : Prop :=
  p[69]? = some (.loadMem .Ldxdw 1 6 0) ∧
  p[70]? = some (.jumpImm .JneImm 1 1 28) ∧
  p[71]? = some (.loadMem .Ldxb 1 6 8) ∧
  p[72]? = some (.jumpImm .JneImm 1 255 26) ∧
  p[73]? = some (.loadMem .Ldxdw 1 6 10360) ∧
  p[74]? = some (.jumpImm .JneImm 1 16 24) ∧
  p[75]? = some (.loadMem .Ldxdw 1 6 10360) ∧
  p[76]? = some (.binReg .Mov64Reg 2 6) ∧
  p[77]? = some (.binImm .Add64Imm 2 10368) ∧
  p[78]? = some (.binReg .Add64Reg 2 1) ∧
  p[79]? = some (.loadMem .Ldxdw 1 6 48) ∧
  p[80]? = some (.loadMem .Ldxdw 3 2 0) ∧
  p[81]? = some (.jumpReg .JneReg 1 3 17) ∧
  p[82]? = some (.loadMem .Ldxdw 1 6 56) ∧
  p[83]? = some (.loadMem .Ldxdw 3 2 8) ∧
  p[84]? = some (.jumpReg .JneReg 1 3 14) ∧
  p[85]? = some (.loadMem .Ldxdw 1 6 64) ∧
  p[86]? = some (.loadMem .Ldxdw 3 2 16) ∧
  p[87]? = some (.jumpReg .JneReg 1 3 11) ∧
  p[88]? = some (.loadMem .Ldxdw 1 6 72) ∧
  p[89]? = some (.loadMem .Ldxdw 3 2 24) ∧
  p[90]? = some (.jumpReg .JneReg 1 3 8) ∧
  p[91]? = some (.loadMem .Ldxdw 1 6 88) ∧
  p[92]? = some (.jumpImm .JneImm 1 16 6) ∧
  p[93]? = some (.loadMem .Ldxb 1 6 10) ∧
  p[94]? = some (.jumpImm .JeqImm 1 0 4) ∧
  p[95]? = some (.loadMem .Ldxdw 1 6 96) ∧
  p[96]? = some (.lddw 2 846264958600013564) ∧
  p[97]? = some (.jumpReg .JneReg 1 2 1) ∧
  p[98]? = some (.ja 2)

instance (p : Program) :
    Decidable (StateCellIncrementValidationLookupsV1 p) := by
  unfold StateCellIncrementValidationLookupsV1
  infer_instance

/-- Exact state/argument loads, checked-add guard, and successful arithmetic
    fetches. -/
def StateCellIncrementArithmeticLookupsV1 (p : Program) : Prop :=
  p[101]? = some (.loadMem .Ldxdw 1 6 104) ∧
  p[102]? = some (.storeReg .Stxdw 10 1 (BitVec.ofInt 16 (-8))) ∧
  p[103]? = some (.loadMem .Ldxdw 1 6 10376) ∧
  p[104]? = some (.storeReg .Stxdw 10 1 (BitVec.ofInt 16 (-16))) ∧
  p[105]? = some (.loadMem .Ldxdw 1 10 (BitVec.ofInt 16 (-8))) ∧
  p[106]? = some (.loadMem .Ldxdw 2 10 (BitVec.ofInt 16 (-16))) ∧
  p[107]? = some (.lddw 3 18446744073709551615) ∧
  p[108]? = some (.binReg .Sub64Reg 3 2) ∧
  p[109]? = some (.jumpReg .JgtReg 1 3 4) ∧
  p[110]? = some (.binReg .Mov64Reg 4 1) ∧
  p[111]? = some (.binReg .Add64Reg 4 2) ∧
  p[112]? = some (.storeReg .Stxdw 10 4 (BitVec.ofInt 16 (-24))) ∧
  p[113]? = some (.ja 2)

instance (p : Program) :
    Decidable (StateCellIncrementArithmeticLookupsV1 p) := by
  unfold StateCellIncrementArithmeticLookupsV1
  infer_instance

/-- Exact account write, return-data publication, and two-level exit fetches. -/
def StateCellIncrementCommitLookupsV1 (p : Program) : Prop :=
  p[116]? = some (.loadMem .Ldxdw 1 10 (BitVec.ofInt 16 (-24))) ∧
  p[117]? = some (.storeReg .Stxdw 6 1 104) ∧
  p[118]? = some (.loadMem .Ldxdw 1 6 104) ∧
  p[119]? = some (.storeReg .Stxdw 10 1 (BitVec.ofInt 16 (-8))) ∧
  p[120]? = some (.loadMem .Ldxdw 1 10 (BitVec.ofInt 16 (-8))) ∧
  p[121]? = some (.storeReg .Stxdw 10 1 (BitVec.ofInt 16 (-32))) ∧
  p[122]? = some (.binReg .Mov64Reg 1 10) ∧
  p[123]? = some (.binImm .Add64Imm 1 (BitVec.ofInt 64 (-32))) ∧
  p[124]? = some (.lddw 2 8) ∧
  p[125]? = some (.callSyscall "sol_set_return_data") ∧
  p[126]? = some (.lddw 0 0) ∧
  p[127]? = some .exit ∧
  p[18]? = some .exit

instance (p : Program) : Decidable (StateCellIncrementCommitLookupsV1 p) := by
  unfold StateCellIncrementCommitLookupsV1
  infer_instance

/-- The exact 70 fetched instructions on the successful production increment
    path. This aggregates sparse lookup predicates over the resolved production
    program; it is not a copied executable program. -/
structure StateCellIncrementProgramLookupsV1 (p : Program) : Prop where
  dispatch : StateCellIncrementDispatchLookupsV1 p
  validation : StateCellIncrementValidationLookupsV1 p
  arithmetic : StateCellIncrementArithmeticLookupsV1 p
  commit : StateCellIncrementCommitLookupsV1 p

instance (p : Program) : Decidable (StateCellIncrementProgramLookupsV1 p) := by
  let checks : Prop :=
    StateCellIncrementDispatchLookupsV1 p ∧
    StateCellIncrementValidationLookupsV1 p ∧
    StateCellIncrementArithmeticLookupsV1 p ∧
    StateCellIncrementCommitLookupsV1 p
  apply decidable_of_iff checks
  constructor
  · rintro ⟨dispatch, validation, arithmetic, commit⟩
    exact ⟨dispatch, validation, arithmetic, commit⟩
  · intro h
    exact ⟨h.dispatch, h.validation, h.arithmetic, h.commit⟩

/-- Executable identity and sparse-fetch gate for the production artifact. -/
def checkStateCellIncrementArtifactV1
    (bound : BoundResolvedSbpfArtifactV1) : Bool :=
  let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
  decide (artifact.sourceSha256 = stateCellProductionSbpfSha256V1) &&
    decide (StateCellIncrementProgramLookupsV1 artifact.program)

theorem checkStateCellIncrementArtifactV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (checked : checkStateCellIncrementArtifactV1 bound = true) :
    let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
    artifact.sourceSha256 = stateCellProductionSbpfSha256V1 ∧
      StateCellIncrementProgramLookupsV1 artifact.program := by
  simpa [checkStateCellIncrementArtifactV1] using checked

/-- Concrete Loader reads consumed by the successful increment path. Owner
    equality is kept as four present equal reads; no program-id value is
    invented by this certificate. -/
def StateCellIncrementInputReadChecksV1
    (input : Array UInt8) (before argument : Word) : Prop :=
  let memory := (Machine.entry input).mem
  memory.readU64 (inputStart + 0#64) = some 1 ∧
  memory.readU8 (inputStart + 8#64) = some 255 ∧
  memory.readU64 (inputStart + 10360#64) = some 16 ∧
  memory.readU64 (inputStart + 10368#64) =
    some 2467651336600536989 ∧
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
  memory.readU8 (inputStart + 10#64) = some 1 ∧
  memory.readU64 (inputStart + 96#64) = some 846264958600013564 ∧
  memory.readU64 (inputStart + 104#64) = some before ∧
  memory.readU64 (inputStart + 10376#64) = some argument

instance (input : Array UInt8) (before argument : Word) :
    Decidable (StateCellIncrementInputReadChecksV1 input before argument) := by
  unfold StateCellIncrementInputReadChecksV1
  infer_instance

def checkStateCellIncrementInputReadsV1
    (input : Array UInt8) (before argument : Word) : Bool :=
  decide (StateCellIncrementInputReadChecksV1 input before argument)

theorem checkStateCellIncrementInputReadsV1_sound
    (input : Array UInt8) (before argument : Word)
    (checked :
      checkStateCellIncrementInputReadsV1 input before argument = true) :
    StateCellIncrementInputReadChecksV1 input before argument := by
  exact of_decide_eq_true (by
    simpa [checkStateCellIncrementInputReadsV1] using checked)

/-- Exact account bytes produced by a successful production increment. -/
def stateCellIncrementFinalAccountDataV1
    (before argument : Word) : Array UInt8 :=
  (wordToLE (BitVec.ofNat 64 846264958600013564)).append
    (wordToLE (before + argument))

/-- Final provider facts retained by the increment-success certificate. -/
structure StateCellIncrementReturnedV1
    (input : Array UInt8) (before argument : Word) (machine : Machine) : Prop where
  pc : machine.pc = 18
  halted : machine.halted = some 0
  frames : machine.frames = []
  returnData : machine.returnData = wordToLE (before + argument)
  result : machine.getReg 0 = 0
  framePointer : machine.getReg 10 = (Machine.entry input).getReg 10
  finalAccountData :
    machine.mem.readBytes (inputStart + BitVec.ofNat 64 accountDataOffsetV1) 16 =
      some (stateCellIncrementFinalAccountDataV1 before argument)

instance (input : Array UInt8) (before argument : Word) (machine : Machine) :
    Decidable (StateCellIncrementReturnedV1 input before argument machine) := by
  let checks : Prop :=
    machine.pc = 18 ∧
    machine.halted = some 0 ∧
    machine.frames = [] ∧
    machine.returnData = wordToLE (before + argument) ∧
    machine.getReg 0 = 0 ∧
    machine.getReg 10 = (Machine.entry input).getReg 10 ∧
    machine.mem.readBytes
      (inputStart + BitVec.ofNat 64 accountDataOffsetV1) 16 =
        some (stateCellIncrementFinalAccountDataV1 before argument)
  apply decidable_of_iff checks
  constructor
  · rintro ⟨hpc, hhalted, hframes, hreturn, hresult, hfp, hdata⟩
    exact ⟨hpc, hhalted, hframes, hreturn, hresult, hfp, hdata⟩
  · intro h
    exact ⟨h.pc, h.halted, h.frames, h.returnData, h.result,
      h.framePointer, h.finalAccountData⟩

/-- Provider result checks that make the exact step count observable: fuel 69
    is exhausted while the machine is live, and fuel 70 halts successfully. -/
def StateCellIncrementTraceResultChecksV1
    (p : Program) (input : Array UInt8) (before argument : Word) : Prop :=
  let beforeRun := runFuel asmDefaultHost p 69 (Machine.entry input)
  let final := runFuel asmDefaultHost p 70 (Machine.entry input)
  beforeRun.2 = .outOfFuel ∧
  final.2 = .halted 0 ∧
  StateCellIncrementReturnedV1 input before argument final.1

instance (p : Program) (input : Array UInt8) (before argument : Word) :
    Decidable (StateCellIncrementTraceResultChecksV1 p input before argument) := by
  unfold StateCellIncrementTraceResultChecksV1
  infer_instance

/-- One executable gate for the identity, sparse fetches, concrete input reads,
    exact 70-step boundary, and final account/return observation. -/
def checkStateCellIncrementTraceV1
    (bound : BoundResolvedSbpfArtifactV1)
    (input : Array UInt8) (before argument : Word) : Bool :=
  let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
  checkStateCellIncrementArtifactV1 bound &&
    (checkSingleAccountExecutionWindowV1 bound accountDataOffsetV1 16 &&
      (decide (input.size ≤ maxSbpfInputImageBytesV1) &&
        (checkStateCellIncrementInputReadsV1 input before argument &&
          decide (StateCellIncrementTraceResultChecksV1 artifact.program input
            before argument))))

private theorem checkStateCellIncrementTraceV1_parts
    (bound : BoundResolvedSbpfArtifactV1)
    (input : Array UInt8) (before argument : Word)
    (checked :
      checkStateCellIncrementTraceV1 bound input before argument = true) :
    checkStateCellIncrementArtifactV1 bound = true ∧
    checkSingleAccountExecutionWindowV1 bound accountDataOffsetV1 16 = true ∧
    input.size ≤ maxSbpfInputImageBytesV1 ∧
    checkStateCellIncrementInputReadsV1 input before argument = true ∧
    let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
    StateCellIncrementTraceResultChecksV1 artifact.program input before
      argument := by
  simpa only [checkStateCellIncrementTraceV1, Bool.and_eq_true,
    decide_eq_true_eq] using checked

/-- The 69/70 fuel boundary and provider adequacy imply exactly 70 relational
    provider steps, rather than merely a run of at most 70 steps. -/
private theorem stateCellIncrement_exactStepsV1
    (p : Program) (input : Array UInt8) (machine : Machine)
    (prefixOutcome :
      (runFuel asmDefaultHost p 69 (Machine.entry input)).2 = .outOfFuel)
    (providerRun :
      runFuel asmDefaultHost p 70 (Machine.entry input) =
        (machine, .halted 0)) :
    Steps asmDefaultHost p 70 (Machine.entry input) machine := by
  rcases runFuel_halted_steps asmDefaultHost p 70 (Machine.entry input)
      machine 0 providerRun with ⟨steps, hbounded, hsteps, hhalted⟩
  have hnotShort : ¬ steps ≤ 69 := by
    intro hshort
    have hshortRun := steps_runFuel_halted asmDefaultHost p steps 69
      (Machine.entry input) machine 0 hsteps hhalted hshort
    have houtcome := congrArg Prod.snd hshortRun
    rw [prefixOutcome] at houtcome
    cases houtcome
  have hexact : steps = 70 := by omega
  simpa [hexact] using hsteps

/-- Proof-bearing provider certificate for the exact production increment
    execution. Sparse lookups and reads remain available for audit, while the
    `Steps` field is derived from the provider's own interpreter. -/
structure StateCellIncrementProviderCertificateV1
    (bound : BoundResolvedSbpfArtifactV1)
    (input : Array UInt8) (before argument : Word) where
  machine : Machine
  sourceIdentity :
    (BoundResolvedSbpfArtifactV1.resolvedOf bound).sourceSha256 =
      stateCellProductionSbpfSha256V1
  programLookups :
    StateCellIncrementProgramLookupsV1
      (BoundResolvedSbpfArtifactV1.resolvedOf bound).program
  inputReads : StateCellIncrementInputReadChecksV1 input before argument
  providerRun :
    runFuel asmDefaultHost
      (BoundResolvedSbpfArtifactV1.resolvedOf bound).program 70
      (Machine.entry input) = (machine, .halted 0)
  providerSteps :
    Steps asmDefaultHost
      (BoundResolvedSbpfArtifactV1.resolvedOf bound).program 70
      (Machine.entry input) machine
  returned : StateCellIncrementReturnedV1 input before argument machine

/-- Soundness of the complete trace gate. -/
theorem checkStateCellIncrementTraceV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (input : Array UInt8) (before argument : Word)
    (checked :
      checkStateCellIncrementTraceV1 bound input before argument = true) :
    Nonempty (StateCellIncrementProviderCertificateV1 bound input before
      argument) := by
  have hparts :=
    checkStateCellIncrementTraceV1_parts bound input before argument checked
  have hartifact :=
    checkStateCellIncrementArtifactV1_sound bound hparts.1
  have hreads :=
    checkStateCellIncrementInputReadsV1_sound input before argument
      hparts.2.2.2.1
  let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
  let final := runFuel asmDefaultHost artifact.program 70 (Machine.entry input)
  have htrace :
      StateCellIncrementTraceResultChecksV1 artifact.program input before
        argument := hparts.2.2.2.2
  have hrun :
      runFuel asmDefaultHost artifact.program 70 (Machine.entry input) =
        (final.1, .halted 0) := by
    apply Prod.ext
    · rfl
    · exact htrace.2.1
  have hsteps := stateCellIncrement_exactStepsV1 artifact.program input final.1
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
def checkStateCellIncrementExecutionV1
    (bound : BoundResolvedSbpfArtifactV1)
    (invocation : LoaderV3SingleAccountInvocationV1)
    (before argument : Word) : Bool :=
  match encodeLoaderV3SingleAccountInputV1 bound invocation with
  | .error _ => false
  | .ok input => checkStateCellIncrementTraceV1 bound input before argument

/-- Encoder and provider-execution equations retained alongside the sparse
    trace certificate. -/
structure CertifiedStateCellIncrementExecutionV1
    (bound : BoundResolvedSbpfArtifactV1)
    (invocation : LoaderV3SingleAccountInvocationV1)
    (before argument : Word) where
  input : Array UInt8
  certificate :
    StateCellIncrementProviderCertificateV1 bound input before argument
  execution : CertifiedSolanaProductionProviderExecutionV1 bound invocation
    70 0 accountDataOffsetV1 16 input certificate.machine

namespace CertifiedStateCellIncrementExecutionV1

def encodedInput (certified :
    CertifiedStateCellIncrementExecutionV1 bound invocation before argument) :=
  certified.execution.encodedInput

def providerExecution (certified :
    CertifiedStateCellIncrementExecutionV1 bound invocation before argument) :=
  certified.execution.providerExecution

end CertifiedStateCellIncrementExecutionV1

/-- Soundness of the end-to-end increment-success execution gate. -/
theorem checkStateCellIncrementExecutionV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (invocation : LoaderV3SingleAccountInvocationV1)
    (before argument : Word)
    (checked :
      checkStateCellIncrementExecutionV1 bound invocation before argument =
        true) :
    Nonempty (CertifiedStateCellIncrementExecutionV1 bound invocation before
      argument) := by
  unfold checkStateCellIncrementExecutionV1 at checked
  cases hencode : encodeLoaderV3SingleAccountInputV1 bound invocation with
  | error error => simp [hencode] at checked
  | ok input =>
      rw [hencode] at checked
      rcases checkStateCellIncrementTraceV1_sound bound input before argument
          checked with ⟨certificate⟩
      have hwindow := checkSingleAccountExecutionWindowV1_sound bound
        accountDataOffsetV1 16
        (checkStateCellIncrementTraceV1_parts bound input before argument
          checked).2.1
      have hraw := runBoundSbpfArtifactV1_eq_ok_of_runFuel bound input 70
        accountDataOffsetV1 16 certificate.machine (.halted 0) hwindow
        (by decide) (by decide)
        (checkStateCellIncrementTraceV1_parts bound input before argument
          checked).2.2.1
        certificate.providerRun
      exact ⟨{
        input
        certificate
        execution := {
          encodedInput := hencode
          providerExecution :=
            executeLoaderV3SingleAccountV1_eq_ok bound invocation 70 input _
              hencode hraw
        }
      }⟩

end ProofForgeV2.Targets.Solana
