import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.Solana.EmitIRV1
import ProofForgeV2.Targets.Solana.EmitSbpfAsmV1
import ProofForgeV2.Targets.Solana.ProductionCompositionV1
import ProofForgeV2.Targets.Solana.ProductionMethodV1
import ProofForgeV2.Targets.Solana.SbpfHandlerJoinV1

/-!
# Solana StateCell production subject

Pure, fail-closed reconstruction of the concrete StateCell certification
subjects from the exact Source AST captured by the actual `program StateCell`
declaration. The captured fields re-enter the production source validator and
must canonically encode to the declaration's actual export bytes. The resolvers
then follow the existing compiler, Solana capability, full-body HandlerIR,
assembly emitter, strict artifact parser, and identity-bound provider path.
They contain no copied IR/program and introduce no alternate lowering or
business semantics.

`get` and `initialize` retain dedicated 55-step certified joins. Successful
`increment` retains its dedicated 70-step certified join, and overflowing
`increment` retains its dedicated 56-step certified join.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2.Compiler
open ProofForgeV2.Examples
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Targets.BuildSelectionV1

-- Kernel-checked ownership of the exact source AST and export bytes produced
-- by the real `program StateCell` declaration. This discharges the first
-- production preparation stage without a copied AST, runtime-only assertion,
-- or contract-specific source validator.
set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellCanonicalSourceBindingV1 :
    ∃ binding,
      bindElaboratedSourceToCanonicalBytesV1
        StateCell.Source.subjectV1 StateCell.bytes = .ok binding := by
  have checked :
      (match bindElaboratedSourceToCanonicalBytesV1
          StateCell.Source.subjectV1 StateCell.bytes with
        | .ok _ => true
        | .error _ => false) = true := by
    decide
  cases hbinding : bindElaboratedSourceToCanonicalBytesV1
      StateCell.Source.subjectV1 StateCell.bytes with
  | error _ =>
      rw [hbinding] at checked
      contradiction
  | ok binding => exact ⟨binding, rfl⟩

/-- The concrete values consumed by the existing certified StateCell `get`
    HandlerIR/provider join. The private constructor prevents callers from
    presenting a hand-built tuple as the production subject; the sole resolver
    below reconstructs every field from the exported production source. -/
structure ResolvedStateCellGetProductionSubjectV1 where
  private mk ::
  preparation : CertifiedSolanaProductionPreparationV1
    StateCell.Source.subjectV1 StateCell.bytes stateCellProductionSbpfSha256V1
  method : CertifiedSolanaProductionMethodV1 preparation .view (some "get") "get"
  referencePre : LogicalStateV1
  referenceExecution : CertifiedSolanaProductionMethodReferenceV1 method
    referencePre #[] #[] #[] {}
  handlerInvocation : InvocationObservationV1
  loaderInvocation : LoaderV3SingleAccountInvocationV1
  returnBytes : Array UInt8
  value : SbpfSemantics.Word

namespace ResolvedStateCellGetProductionSubjectV1

def sourceBinding (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.preparation.sourceBinding

def referenceProgram (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.preparation.referenceProgram

def data (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.preparation.data

def admitted (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.preparation.admitted

def ir (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.preparation.productionIR

def assembly (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.preparation.productionAssembly

def boundArtifact (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.preparation.boundArtifact

def handler (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.method.handler

def referenceOutcome (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.referenceExecution.outcome

def returnTypeId (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.method.callable.result.typeId

end ResolvedStateCellGetProductionSubjectV1

private def compileResultV1 (result : CompileResult α) : Except String α :=
  match result with
  | .ok value => .ok value
  | .error error => .error error.render

/-- Reconstruct the exact production subject without IO or a parser session.

    Source authority is the AST captured by `program StateCell`, revalidated by
    the production source validator and checked against that declaration's
    canonical export bytes. The validated source then enters the same compiler/
    capability/lowering/emitter path used by product construction. The exact
    `.s` SHA-256 is checked before the strict parser may mint the provider
    artifact. -/
def resolveStateCellGetProductionSubjectV1 :
    Except String ResolvedStateCellGetProductionSubjectV1 := do
  unless StateCell.schema == Language.ProgramExport.programExportSchemaV2 do
    throw "StateCell program export schema is not proof-forge.program-export.v2"
  let preparation ← resolveCertifiedSolanaProductionPreparationV1
    StateCell.Source.subjectV1 StateCell.bytes stateCellProductionSbpfSha256V1
  let ir := preparation.productionIR
  let method ← resolveCertifiedSolanaProductionMethodV1 preparation
    .view (some "get") "get"
  let data := preparation.data
  let handler := method.handler
  let discriminator ← compileResultV1 <|
    discriminatorToLeU64V1 handler.discriminator
  let logicalValue : UInt64 := 41
  let referencePre ← match encodeLogicalStateValuesV1 data true
      #[encodeU64le logicalValue] with
    | .ok value => pure value
    | .error error =>
        throw s!"StateCell get pre-state encoding failed: {repr error}"
  let referenceExecution :=
    executeCertifiedSolanaProductionMethodReferenceV1 method referencePre
      #[] #[] #[] {}
  let value := BitVec.ofNat 64 logicalValue.toNat
  let returnBytes := (encodeU64le logicalValue).data
  let accountData :=
    (SbpfSemantics.wordToLE
      (BitVec.ofNat 64 ir.stateAccount.initializedMarker.toNat)).append
      returnBytes
  let programId := Array.replicate 32 (0x42 : UInt8)
  let loaderInvocation : LoaderV3SingleAccountInvocationV1 := {
    accountKey := Array.replicate 32 (0x24 : UInt8)
    owner := programId
    programId
    accountData
    instructionData :=
      SbpfSemantics.wordToLE (BitVec.ofNat 64 discriminator.toNat)
  }
  let handlerInvocation :=
    nullaryUInt64ViewInvocationV1 ⟨accountData⟩ discriminator
  pure <| ResolvedStateCellGetProductionSubjectV1.mk preparation method
    referencePre referenceExecution handlerInvocation loaderInvocation returnBytes
    value

/-- Single fail-closed gate over the pure production subject and the existing
    certified HandlerIR/provider checker. Any source, compiler, profile,
    artifact, handler, or invocation failure returns `false`. -/
def checkStateCellGetProductionSubjectV1 : Bool :=
  checkCertifiedSolanaProductionSubjectV1
    resolveStateCellGetProductionSubjectV1 fun subject =>
    checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1
      subject.boundArtifact subject.handler subject.handlerInvocation
      subject.loaderInvocation subject.returnBytes subject.value

/-- The pure production gate remains proof-producing rather than treating its
    executable result as a theorem. Once the Boolean is discharged, this
    theorem recovers both the exact resolved production subject and the
    existing certified 55-step HandlerIR/provider carrier. -/
theorem checkStateCellGetProductionSubjectV1_sound
    (checked : checkStateCellGetProductionSubjectV1 = true) :
    ∃ subject,
      resolveStateCellGetProductionSubjectV1 = .ok subject ∧
      Nonempty (CertifiedStateCellGetExecutedHandlerSbpfJoinV1
        subject.boundArtifact subject.handler subject.handlerInvocation
        subject.loaderInvocation subject.returnBytes subject.value) := by
  rcases checkCertifiedSolanaProductionSubjectV1_sound
      resolveStateCellGetProductionSubjectV1
      (fun subject =>
        checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation subject.returnBytes subject.value)
      checked with ⟨subject, hsubject, hchecked⟩
  refine ⟨subject, hsubject, ?_⟩
  exact checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1_sound
    subject.boundArtifact subject.handler subject.handlerInvocation
    subject.loaderInvocation subject.returnBytes subject.value hchecked

/-- D5 production gate for the read-only `get(41)` slice. It composes the
    source-derived sole Reference result with the dedicated 55-step provider
    certificate; the production account remains unchanged. -/
def checkStateCellGetReferenceProviderSubjectV1 : Bool :=
  checkCertifiedSolanaProductionCompositionV1
    resolveStateCellGetProductionSubjectV1
    (fun subject =>
      checkUInt64ReturnedHandlerObservationRelV1 subject.data
        subject.returnTypeId subject.referencePre subject.referenceOutcome
        ⟨subject.returnBytes⟩
        (observeHandlerIRV1 subject.handler subject.handlerInvocation))
    (fun subject =>
      checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1
        subject.boundArtifact subject.handler subject.handlerInvocation
        subject.loaderInvocation subject.returnBytes subject.value)

/-- A successful get D5 gate recovers one composed
    Reference→HandlerIR→provider carrier. The Boolean premise remains explicit;
    this does not cover ELF, linker, loader, or SVM runtime semantics. -/
theorem checkStateCellGetReferenceProviderSubjectV1_sound
    (checked : checkStateCellGetReferenceProviderSubjectV1 = true) :
    ∃ subject,
      resolveStateCellGetProductionSubjectV1 = .ok subject ∧
      ∃ certified : CertifiedStateCellGetExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation subject.returnBytes subject.value,
        UInt64ReferenceHandlerSbpfJoinV1 subject.data subject.returnTypeId
          subject.referencePre subject.referenceOutcome ⟨subject.returnBytes⟩
          certified.executed.handlerObservation
          stateCellProductionSbpfSha256V1
          certified.executed.sbpfObservation := by
  exact checkCertifiedSolanaProductionCompositionV1_sound_of_witnesses
      resolveStateCellGetProductionSubjectV1
      (fun subject =>
        checkUInt64ReturnedHandlerObservationRelV1 subject.data
          subject.returnTypeId subject.referencePre subject.referenceOutcome
          ⟨subject.returnBytes⟩
          (observeHandlerIRV1 subject.handler subject.handlerInvocation))
      (fun subject =>
        checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation subject.returnBytes subject.value)
      (fun subject hreference =>
        (checkUInt64ReturnedHandlerObservationRelV1_eq_true_iff subject.data
          subject.returnTypeId subject.referencePre subject.referenceOutcome
          ⟨subject.returnBytes⟩
          (observeHandlerIRV1 subject.handler subject.handlerInvocation)).mp
            hreference)
      (fun subject hprovider =>
        checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1_sound
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation subject.returnBytes subject.value hprovider)
      (fun _ certified referenceHandler =>
        certified.referenceJoin (by
          simpa [certified.executed.handlerExecution] using referenceHandler))
      checked

/-- Concrete values consumed by the generic StateCell `initialize`
    HandlerIR/provider join. Same private-ctor discipline as `get`. -/
structure ResolvedStateCellInitializeProductionSubjectV1 where
  private mk ::
  preparation : CertifiedSolanaProductionPreparationV1
    StateCell.Source.subjectV1 StateCell.bytes stateCellProductionSbpfSha256V1
  method : CertifiedSolanaProductionMethodV1 preparation .initializer none
    "initialize"
  referencePre : LogicalStateV1
  referencePost : LogicalStateV1
  binding : UInt64StateAccountBindingV1
  argument : UInt64
  referenceExecution : CertifiedSolanaProductionMethodReferenceV1 method
    referencePre #[{
      typeId := binding.semanticTypeId
      valueBytes := encodeU64le argument
    }] #[] #[] {}
  postData : ByteArray
  handlerInvocation : InvocationObservationV1
  loaderInvocation : LoaderV3SingleAccountInvocationV1

namespace ResolvedStateCellInitializeProductionSubjectV1

def sourceBinding (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.sourceBinding

def referenceProgram (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.referenceProgram

def data (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.data

def admitted (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.admitted

def plan (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.productionPlan

def ir (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.productionIR

def assembly (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.productionAssembly

def boundArtifact (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.boundArtifact

def handler (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.method.handler

def referenceOutcome
    (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.referenceExecution.outcome

end ResolvedStateCellInitializeProductionSubjectV1

/-- Reconstruct the initialize production subject from the same exported
    StateCell source. Prestate is the uninitialized one-field account used by
    the existing executable observation; the argument is `7`. -/
def resolveStateCellInitializeProductionSubjectV1 :
    Except String ResolvedStateCellInitializeProductionSubjectV1 := do
  unless StateCell.schema == Language.ProgramExport.programExportSchemaV2 do
    throw "StateCell program export schema is not proof-forge.program-export.v2"
  let preparation ← resolveCertifiedSolanaProductionPreparationV1
    StateCell.Source.subjectV1 StateCell.bytes stateCellProductionSbpfSha256V1
  let referenceProgram := preparation.referenceProgram
  let data := preparation.data
  let plan := preparation.productionPlan
  let method ← resolveCertifiedSolanaProductionMethodV1 preparation
    .initializer none "initialize"
  let handler := method.handler
  let referencePre ← match initialLogicalStateV1 referenceProgram with
    | .ok value => pure value
    | .error error =>
        throw s!"StateCell initial logical state failed: {repr error}"
  let discriminator ← compileResultV1 <|
    discriminatorToLeU64V1 handler.discriminator
  let argument : UInt64 := 7
  let stateRow ← match data.logicalState[0]? with
    | some value => pure value
    | none => throw "production StateCell Semantic program has no state row 0"
  let field ← match plan.stateAccount.fields[0]? with
    | some value => pure value
    | none => throw "production StateCell Plan has no state field 0"
  let binding : UInt64StateAccountBindingV1 := {
    semanticStateId := stateRow.id
    semanticTypeId := stateRow.typeId
    stateName := stateRow.name
    physicalFieldIndex := 0
    accountIndex := field.accountIndex
    byteOffset := field.byteOffset
  }
  let referencePost ← match encodeLogicalStateValuesV1 data true
      #[encodeU64le argument] with
    | .ok value => pure value
    | .error error =>
        throw s!"StateCell initialize post-state encoding failed: {repr error}"
  let referenceExecution :=
    executeCertifiedSolanaProductionMethodReferenceV1 method referencePre #[{
      typeId := binding.semanticTypeId
      valueBytes := encodeU64le argument
    }] #[] #[] {}
  let postData := oneFieldUInt64AccountDataV1
    plan.stateAccount.initializedMarker argument
  let staleValue : UInt64 := 999
  let accountData :=
    (SbpfSemantics.wordToLE (BitVec.ofNat 64 0)).append
      (SbpfSemantics.wordToLE (BitVec.ofNat 64 staleValue.toNat))
  let programId := Array.replicate 32 (0x42 : UInt8)
  let loaderInvocation : LoaderV3SingleAccountInvocationV1 := {
    accountKey := Array.replicate 32 (0x24 : UInt8)
    owner := programId
    programId
    accountData
    instructionData :=
      (SbpfSemantics.wordToLE (BitVec.ofNat 64 discriminator.toNat)).append
        (SbpfSemantics.wordToLE (BitVec.ofNat 64 argument.toNat))
    isSigner := true
    isWritable := true
  }
  let handlerInvocation :=
    unaryUInt64InvocationV1 ⟨accountData⟩ discriminator argument true true
  pure <| ResolvedStateCellInitializeProductionSubjectV1.mk preparation method
    referencePre referencePost binding argument referenceExecution postData
    handlerInvocation loaderInvocation

def checkStateCellInitializeProductionSubjectV1 : Bool :=
  checkCertifiedSolanaProductionSubjectV1
    resolveStateCellInitializeProductionSubjectV1 fun subject =>
    checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
      subject.boundArtifact subject.handler subject.handlerInvocation
      subject.loaderInvocation (BitVec.ofNat 64 subject.argument.toNat)

theorem checkStateCellInitializeProductionSubjectV1_sound
    (checked : checkStateCellInitializeProductionSubjectV1 = true) :
    ∃ subject,
      resolveStateCellInitializeProductionSubjectV1 = .ok subject ∧
      Nonempty (CertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
        subject.boundArtifact subject.handler subject.handlerInvocation
        subject.loaderInvocation
        (BitVec.ofNat 64 subject.argument.toNat)) := by
  rcases checkCertifiedSolanaProductionSubjectV1_sound
      resolveStateCellInitializeProductionSubjectV1
      (fun subject =>
        checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.argument.toNat))
      checked with ⟨subject, hsubject, hchecked⟩
  refine ⟨subject, hsubject, ?_⟩
  exact checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1_sound
    subject.boundArtifact subject.handler subject.handlerInvocation
    subject.loaderInvocation (BitVec.ofNat 64 subject.argument.toNat) hchecked

/-- D5 production gate: run the sole Reference machine on the source-derived
    `initialize(7)` subject and compose its exact observation relation with the
    dedicated 55-step provider certificate. The gate remains fail closed and
    proof-producing; it does not define another transition or lowering. -/
def checkStateCellInitializeReferenceProviderSubjectV1 : Bool :=
  checkCertifiedSolanaProductionCompositionV1
    resolveStateCellInitializeProductionSubjectV1
    (fun subject =>
      checkUInt64InitializerReturnedHandlerObservationRelV1 subject.data
        subject.plan subject.binding subject.referencePost
        subject.referenceOutcome subject.postData subject.argument
        (observeHandlerIRV1 subject.handler subject.handlerInvocation))
    (fun subject =>
      checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
        subject.boundArtifact subject.handler subject.handlerInvocation
        subject.loaderInvocation (BitVec.ofNat 64 subject.argument.toNat))

/-- A successful D5 gate recovers the exact source-derived subject, dedicated
    sparse provider certificate, and composed Reference→provider carrier. The
    Boolean premise is intentional: this theorem does not claim an
    unconditional ELF or SVM-runtime refinement. -/
theorem checkStateCellInitializeReferenceProviderSubjectV1_sound
    (checked : checkStateCellInitializeReferenceProviderSubjectV1 = true) :
    ∃ subject,
      resolveStateCellInitializeProductionSubjectV1 = .ok subject ∧
      ∃ certified : CertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation
          (BitVec.ofNat 64 subject.argument.toNat),
        UInt64InitializerReferenceHandlerSbpfJoinV1 subject.data subject.plan
          subject.binding subject.referencePost subject.referenceOutcome
          subject.postData subject.argument certified.executed.handlerObservation
          stateCellProductionSbpfSha256V1
          certified.executed.sbpfObservation := by
  exact checkCertifiedSolanaProductionCompositionV1_sound_of_witnesses
      resolveStateCellInitializeProductionSubjectV1
      (fun subject =>
        checkUInt64InitializerReturnedHandlerObservationRelV1 subject.data
          subject.plan subject.binding subject.referencePost
          subject.referenceOutcome subject.postData subject.argument
          (observeHandlerIRV1 subject.handler subject.handlerInvocation))
      (fun subject =>
        checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.argument.toNat))
      (fun subject hreference =>
        (checkUInt64InitializerReturnedHandlerObservationRelV1_eq_true_iff
          subject.data subject.plan subject.binding subject.referencePost
          subject.referenceOutcome subject.postData subject.argument
          (observeHandlerIRV1 subject.handler
            subject.handlerInvocation)).mp hreference)
      (fun subject hprovider =>
        checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1_sound
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.argument.toNat)
          hprovider)
      (fun _ certified referenceHandler =>
        certified.referenceJoin (by
          simpa [certified.executed.handlerExecution] using referenceHandler))
      checked

/-- Concrete values consumed by the certified StateCell `increment` success
    HandlerIR/provider join. The selected scenario starts at `41` and adds
    `1` along the exact 70-step provider path. -/
structure ResolvedStateCellIncrementProductionSubjectV1 where
  private mk ::
  preparation : CertifiedSolanaProductionPreparationV1
    StateCell.Source.subjectV1 StateCell.bytes stateCellProductionSbpfSha256V1
  method : CertifiedSolanaProductionMethodV1 preparation .entry
    (some "increment") "increment"
  referencePre : LogicalStateV1
  referencePost : LogicalStateV1
  binding : UInt64StateAccountBindingV1
  before : UInt64
  argument : UInt64
  referenceExecution : CertifiedSolanaProductionMethodReferenceV1 method
    referencePre #[{
      typeId := binding.semanticTypeId
      valueBytes := encodeU64le argument
    }] #[] #[] {}
  postData : ByteArray
  handlerInvocation : InvocationObservationV1
  loaderInvocation : LoaderV3SingleAccountInvocationV1

namespace ResolvedStateCellIncrementProductionSubjectV1

def sourceBinding (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.sourceBinding

def referenceProgram (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.referenceProgram

def data (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.data

def admitted (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.admitted

def plan (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.productionPlan

def ir (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.productionIR

def assembly (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.productionAssembly

def boundArtifact (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.boundArtifact

def handler (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.method.handler

def referenceOutcome
    (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.referenceExecution.outcome

end ResolvedStateCellIncrementProductionSubjectV1

/-- Reconstruct the increment-success subject from the same production source,
    compiler, assembly emitter, identity gate, and provider artifact as `get`
    and `initialize`. -/
def resolveStateCellIncrementProductionSubjectV1 :
    Except String ResolvedStateCellIncrementProductionSubjectV1 := do
  unless StateCell.schema == Language.ProgramExport.programExportSchemaV2 do
    throw "StateCell program export schema is not proof-forge.program-export.v2"
  let preparation ← resolveCertifiedSolanaProductionPreparationV1
    StateCell.Source.subjectV1 StateCell.bytes stateCellProductionSbpfSha256V1
  let data := preparation.data
  let plan := preparation.productionPlan
  let method ← resolveCertifiedSolanaProductionMethodV1 preparation
    .entry (some "increment") "increment"
  let handler := method.handler
  let discriminator ← compileResultV1 <|
    discriminatorToLeU64V1 handler.discriminator
  let before : UInt64 := 41
  let argument : UInt64 := 1
  let stateRow ← match data.logicalState[0]? with
    | some value => pure value
    | none => throw "production StateCell Semantic program has no state row 0"
  let field ← match plan.stateAccount.fields[0]? with
    | some value => pure value
    | none => throw "production StateCell Plan has no state field 0"
  let binding : UInt64StateAccountBindingV1 := {
    semanticStateId := stateRow.id
    semanticTypeId := stateRow.typeId
    stateName := stateRow.name
    physicalFieldIndex := 0
    accountIndex := field.accountIndex
    byteOffset := field.byteOffset
  }
  let referencePre ← match encodeLogicalStateValuesV1 data true
      #[encodeU64le before] with
    | .ok value => pure value
    | .error error =>
        throw s!"StateCell increment pre-state encoding failed: {repr error}"
  let referencePost ← match encodeLogicalStateValuesV1 data true
      #[encodeU64le (before + argument)] with
    | .ok value => pure value
    | .error error =>
        throw s!"StateCell increment post-state encoding failed: {repr error}"
  let referenceExecution :=
    executeCertifiedSolanaProductionMethodReferenceV1 method referencePre #[{
      typeId := binding.semanticTypeId
      valueBytes := encodeU64le argument
    }] #[] #[] {}
  let postData := oneFieldUInt64AccountDataV1
    plan.stateAccount.initializedMarker (before + argument)
  let accountData := oneFieldUInt64AccountDataV1
    plan.stateAccount.initializedMarker before
  let programId := Array.replicate 32 (0x42 : UInt8)
  let loaderInvocation : LoaderV3SingleAccountInvocationV1 := {
    accountKey := Array.replicate 32 (0x24 : UInt8)
    owner := programId
    programId
    accountData := accountData.data
    instructionData :=
      (SbpfSemantics.wordToLE (BitVec.ofNat 64 discriminator.toNat)).append
        (SbpfSemantics.wordToLE (BitVec.ofNat 64 argument.toNat))
    isWritable := true
  }
  let handlerInvocation :=
    unaryUInt64InvocationV1 accountData discriminator argument false true
  pure <| ResolvedStateCellIncrementProductionSubjectV1.mk preparation method
    referencePre referencePost binding before argument referenceExecution postData
    handlerInvocation loaderInvocation

/-- Fail-closed certified agreement for the pinned increment-success subject. -/
def checkStateCellIncrementProductionSubjectV1 : Bool :=
  checkCertifiedSolanaProductionSubjectV1
    resolveStateCellIncrementProductionSubjectV1 fun subject =>
    checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
      subject.boundArtifact subject.handler subject.handlerInvocation
      subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
      (BitVec.ofNat 64 subject.argument.toNat)

/-- Successful increment checking recovers the exact production subject and a
    carrier whose equations retain both existing evaluators and the exact
    70-step sparse provider certificate. -/
theorem checkStateCellIncrementProductionSubjectV1_sound
    (checked : checkStateCellIncrementProductionSubjectV1 = true) :
    ∃ subject,
      resolveStateCellIncrementProductionSubjectV1 = .ok subject ∧
      Nonempty (CertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
        subject.boundArtifact subject.handler subject.handlerInvocation
        subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
        (BitVec.ofNat 64 subject.argument.toNat)) := by
  rcases checkCertifiedSolanaProductionSubjectV1_sound
      resolveStateCellIncrementProductionSubjectV1
      (fun subject =>
        checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat))
      checked with ⟨subject, hsubject, hchecked⟩
  refine ⟨subject, hsubject, ?_⟩
  exact checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1_sound
    subject.boundArtifact subject.handler subject.handlerInvocation
    subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
    (BitVec.ofNat 64 subject.argument.toNat) hchecked

/-- D5 production gate for the successful `increment(41, 1)` slice. It
    composes the source-derived sole Reference outcome with the dedicated
    70-step provider certificate. -/
def checkStateCellIncrementReferenceProviderSubjectV1 : Bool :=
  checkCertifiedSolanaProductionCompositionV1
    resolveStateCellIncrementProductionSubjectV1
    (fun subject =>
      checkUInt64CheckedAddReturnedHandlerObservationRelV1 subject.data
        subject.plan subject.binding subject.referencePost
        subject.referenceOutcome subject.postData subject.before subject.argument
        (observeHandlerIRV1 subject.handler subject.handlerInvocation))
    (fun subject =>
      checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
        subject.boundArtifact subject.handler subject.handlerInvocation
        subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
        (BitVec.ofNat 64 subject.argument.toNat))

/-- A successful D5 increment gate returns one composed
    Reference→HandlerIR→provider carrier. Its Boolean premise is retained; this
    is not an unconditional ELF or SVM-runtime theorem. -/
theorem checkStateCellIncrementReferenceProviderSubjectV1_sound
    (checked : checkStateCellIncrementReferenceProviderSubjectV1 = true) :
    ∃ subject,
      resolveStateCellIncrementProductionSubjectV1 = .ok subject ∧
      ∃ certified : CertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat),
        UInt64CheckedAddReferenceHandlerSbpfJoinV1 subject.data subject.plan
          subject.binding subject.referencePost subject.referenceOutcome
          subject.postData subject.before subject.argument
          certified.executed.handlerObservation stateCellProductionSbpfSha256V1
          certified.executed.sbpfObservation := by
  exact checkCertifiedSolanaProductionCompositionV1_sound_of_witnesses
      resolveStateCellIncrementProductionSubjectV1
      (fun subject =>
        checkUInt64CheckedAddReturnedHandlerObservationRelV1 subject.data
          subject.plan subject.binding subject.referencePost
          subject.referenceOutcome subject.postData subject.before
          subject.argument
          (observeHandlerIRV1 subject.handler subject.handlerInvocation))
      (fun subject =>
        checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat))
      (fun subject hreference =>
        (checkUInt64CheckedAddReturnedHandlerObservationRelV1_eq_true_iff
          subject.data subject.plan subject.binding subject.referencePost
          subject.referenceOutcome subject.postData subject.before
          subject.argument
          (observeHandlerIRV1 subject.handler
            subject.handlerInvocation)).mp hreference)
      (fun subject hprovider =>
        checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1_sound
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat) hprovider)
      (fun _ certified referenceHandler =>
        certified.referenceJoin (by
          simpa [certified.executed.handlerExecution] using referenceHandler))
      checked

/-- The pinned arithmetic-overflow invocation over the exact increment
    production subject. Reusing that private subject guarantees the same source,
    HandlerIR, assembly, and identity-bound provider artifact. -/
structure ResolvedStateCellIncrementOverflowProductionSubjectV1 where
  private mk ::
  production : ResolvedStateCellIncrementProductionSubjectV1
  referencePre : LogicalStateV1
  before : UInt64
  argument : UInt64
  referenceExecution : CertifiedSolanaProductionMethodReferenceV1
    production.method referencePre #[{
      typeId := production.binding.semanticTypeId
      valueBytes := encodeU64le argument
    }] #[] #[] {}
  accountData : ByteArray
  handlerInvocation : InvocationObservationV1
  loaderInvocation : LoaderV3SingleAccountInvocationV1

namespace ResolvedStateCellIncrementOverflowProductionSubjectV1

def referenceOutcome
    (subject : ResolvedStateCellIncrementOverflowProductionSubjectV1) :=
  subject.referenceExecution.outcome

end ResolvedStateCellIncrementOverflowProductionSubjectV1

/-- Reconstruct `UInt64.max + 1` without another compiler or artifact path.
    The sole Reference machine and existing HandlerIR evaluator must both
    retain their exact pre-state snapshots; the provider join must observe
    status `0x1001` with the same production account bytes. -/
def resolveStateCellIncrementOverflowProductionSubjectV1 :
    Except String ResolvedStateCellIncrementOverflowProductionSubjectV1 := do
  let production ← resolveStateCellIncrementProductionSubjectV1
  let discriminator ← compileResultV1 <|
    discriminatorToLeU64V1 production.handler.discriminator
  let before : UInt64 := 0xffffffffffffffff
  let argument : UInt64 := 1
  let referencePre ← match encodeLogicalStateValuesV1 production.data true
      #[encodeU64le before] with
    | .ok value => pure value
    | .error error =>
        throw s!"StateCell increment overflow pre-state encoding failed: {repr error}"
  let referenceExecution :=
    executeCertifiedSolanaProductionMethodReferenceV1 production.method
      referencePre #[{
      typeId := production.binding.semanticTypeId
      valueBytes := encodeU64le argument
    }] #[] #[] {}
  let accountData := oneFieldUInt64AccountDataV1
    production.plan.stateAccount.initializedMarker before
  let programId := Array.replicate 32 (0x42 : UInt8)
  let loaderInvocation : LoaderV3SingleAccountInvocationV1 := {
    accountKey := Array.replicate 32 (0x24 : UInt8)
    owner := programId
    programId
    accountData := accountData.data
    instructionData :=
      (SbpfSemantics.wordToLE (BitVec.ofNat 64 discriminator.toNat)).append
        (SbpfSemantics.wordToLE (BitVec.ofNat 64 argument.toNat))
    isWritable := true
  }
  let handlerInvocation :=
    unaryUInt64InvocationV1 accountData discriminator argument false true
  pure <| ResolvedStateCellIncrementOverflowProductionSubjectV1.mk production
    referencePre before argument referenceExecution accountData handlerInvocation
    loaderInvocation

/-- Fail-closed certified agreement for the pinned increment-overflow subject. -/
def checkStateCellIncrementOverflowProductionSubjectV1 : Bool :=
  checkCertifiedSolanaProductionSubjectV1
    resolveStateCellIncrementOverflowProductionSubjectV1 fun subject =>
    checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
      subject.production.boundArtifact subject.production.handler
      subject.handlerInvocation subject.loaderInvocation
      (BitVec.ofNat 64 subject.before.toNat)
      (BitVec.ofNat 64 subject.argument.toNat)

/-- Successful checking recovers the exact 56-step provider certificate and an
    executed carrier binding the actual Handler arithmetic trap to it. -/
theorem checkStateCellIncrementOverflowProductionSubjectV1_sound
    (checked : checkStateCellIncrementOverflowProductionSubjectV1 = true) :
    ∃ subject,
      resolveStateCellIncrementOverflowProductionSubjectV1 = .ok subject ∧
      Nonempty (CertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
        subject.production.boundArtifact subject.production.handler
        subject.handlerInvocation subject.loaderInvocation
        (BitVec.ofNat 64 subject.before.toNat)
        (BitVec.ofNat 64 subject.argument.toNat)) := by
  rcases checkCertifiedSolanaProductionSubjectV1_sound
      resolveStateCellIncrementOverflowProductionSubjectV1
      (fun subject =>
        checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
          subject.production.boundArtifact subject.production.handler
          subject.handlerInvocation subject.loaderInvocation
          (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat))
      checked with ⟨subject, hsubject, hchecked⟩
  refine ⟨subject, hsubject, ?_⟩
  exact checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1_sound
    subject.production.boundArtifact subject.production.handler
    subject.handlerInvocation subject.loaderInvocation
    (BitVec.ofNat 64 subject.before.toNat)
    (BitVec.ofNat 64 subject.argument.toNat) hchecked

/-- D5 production gate for `increment(UInt64.max, 1)`. It composes the actual
    source-derived Reference overflow with the dedicated 56-step provider
    certificate and exact unchanged production account snapshot. -/
def checkStateCellIncrementOverflowReferenceProviderSubjectV1 : Bool :=
  checkCertifiedSolanaProductionCompositionV1
    resolveStateCellIncrementOverflowProductionSubjectV1
    (fun subject =>
      checkUInt64CheckedAddOverflowHandlerObservationRelV1
        subject.production.data subject.production.plan
        subject.production.binding subject.referencePre subject.referenceOutcome
        subject.accountData subject.before
        (observeHandlerIRV1 subject.production.handler
          subject.handlerInvocation))
    (fun subject =>
      checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
        subject.production.boundArtifact subject.production.handler
        subject.handlerInvocation subject.loaderInvocation
        (BitVec.ofNat 64 subject.before.toNat)
        (BitVec.ofNat 64 subject.argument.toNat))

/-- A successful overflow D5 gate recovers one composed
    Reference→HandlerIR→provider carrier. Its Boolean premise is retained; this
    is not an unconditional ELF, linker, loader, or SVM-runtime theorem. -/
theorem checkStateCellIncrementOverflowReferenceProviderSubjectV1_sound
    (checked :
      checkStateCellIncrementOverflowReferenceProviderSubjectV1 = true) :
    ∃ subject,
      resolveStateCellIncrementOverflowProductionSubjectV1 = .ok subject ∧
      ∃ certified : CertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
          subject.production.boundArtifact subject.production.handler
          subject.handlerInvocation subject.loaderInvocation
          (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat),
        UInt64CheckedAddOverflowReferenceHandlerSbpfJoinV1
          subject.production.data subject.production.plan
          subject.production.binding subject.referencePre
          subject.referenceOutcome subject.accountData subject.before
          certified.executed.handlerObservation
          stateCellProductionSbpfSha256V1
          certified.executed.sbpfObservation := by
  exact checkCertifiedSolanaProductionCompositionV1_sound_of_witnesses
      resolveStateCellIncrementOverflowProductionSubjectV1
      (fun subject =>
        checkUInt64CheckedAddOverflowHandlerObservationRelV1
          subject.production.data subject.production.plan
          subject.production.binding subject.referencePre
          subject.referenceOutcome subject.accountData subject.before
          (observeHandlerIRV1 subject.production.handler
            subject.handlerInvocation))
      (fun subject =>
        checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
          subject.production.boundArtifact subject.production.handler
          subject.handlerInvocation subject.loaderInvocation
          (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat))
      (fun subject hreference =>
        (checkUInt64CheckedAddOverflowHandlerObservationRelV1_eq_true_iff
          subject.production.data subject.production.plan
          subject.production.binding subject.referencePre
          subject.referenceOutcome subject.accountData subject.before
          (observeHandlerIRV1 subject.production.handler
            subject.handlerInvocation)).mp hreference)
      (fun subject hprovider =>
        checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1_sound
          subject.production.boundArtifact subject.production.handler
          subject.handlerInvocation subject.loaderInvocation
          (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat) hprovider)
      (fun _ certified referenceHandler =>
        certified.referenceJoin (by
          simpa [certified.executed.handlerExecution] using referenceHandler))
      checked

end ProofForgeV2.Targets.Solana
