import ProofForgeV2.Examples.OptionState
import ProofForgeV2.Targets.Solana.ProductionCompositionV1
import ProofForgeV2.Targets.Solana.ProductionMethodV1
import ProofForgeV2.Targets.Solana.SbpfHandlerJoinV1

/-!
# Solana OptionState `peek` production subject

This module is the second real consumer of the contract-independent Solana
production chain. It reconstructs OptionState from the actual exported Source
AST, executes `peek` with the sole Reference machine, executes its production
switch-shaped HandlerIR, and runs the identity-bound production assembly with
the shared provider resolver.

The Option-specific content is limited to the selected business scenario and
its representation relation. No Option evaluator, copied HandlerIR, provider
trace, or alternate lowering is defined here.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2.Compiler
open ProofForgeV2.Examples
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-- SHA-256 of the exact production OptionState sBPF assembly emitted by the
    pinned compiler/profile path. -/
def optionStateProductionSbpfSha256V1 : String :=
  "5245f26a8b6912aeab1e538b840dbed2b67833a6efdb6921ea734f0dfaa067b4"

/-- Fuel retained by the generic provider resolution for the production
    `peek(Some 77)` scenario. The real program halts before this bound. -/
def optionStatePeekProviderFuelV1 : Nat := 80

/-- Exact values recovered from the exported OptionState source and consumed
    by the generic Reference/HandlerIR/provider composition. -/
structure ResolvedOptionStatePeekProductionSubjectV1 where
  private mk ::
  preparation : CertifiedSolanaProductionPreparationV1
    OptionState.Source.subjectV1 OptionState.bytes
      optionStateProductionSbpfSha256V1
  method : CertifiedSolanaProductionMethodV1 preparation .view (some "peek")
    "peek"
  binding : OptionUInt64StateAccountBindingV1
  referencePre : LogicalStateV1
  accountData : ByteArray
  accountRelation : OptionUInt64LogicalStateAccountRelV1 preparation.data
    preparation.productionPlan binding referencePre accountData (some 77)
  referenceExecution : CertifiedSolanaProductionMethodReferenceV1 method
    referencePre #[] #[] #[] {}
  handlerInvocation : InvocationObservationV1
  loaderInvocation : LoaderV3SingleAccountInvocationV1
  returnBytes : ByteArray

namespace ResolvedOptionStatePeekProductionSubjectV1

def sourceBinding (subject : ResolvedOptionStatePeekProductionSubjectV1) :=
  subject.preparation.sourceBinding

def referenceProgram (subject : ResolvedOptionStatePeekProductionSubjectV1) :=
  subject.preparation.referenceProgram

def data (subject : ResolvedOptionStatePeekProductionSubjectV1) :=
  subject.preparation.data

def admitted (subject : ResolvedOptionStatePeekProductionSubjectV1) :=
  subject.preparation.admitted

def plan (subject : ResolvedOptionStatePeekProductionSubjectV1) :=
  subject.preparation.productionPlan

def ir (subject : ResolvedOptionStatePeekProductionSubjectV1) :=
  subject.preparation.productionIR

def assembly (subject : ResolvedOptionStatePeekProductionSubjectV1) :=
  subject.preparation.productionAssembly

def boundArtifact (subject : ResolvedOptionStatePeekProductionSubjectV1) :=
  subject.preparation.boundArtifact

def handler (subject : ResolvedOptionStatePeekProductionSubjectV1) :=
  subject.method.handler

def referenceOutcome (subject : ResolvedOptionStatePeekProductionSubjectV1) :=
  subject.referenceExecution.outcome

def returnTypeId (subject : ResolvedOptionStatePeekProductionSubjectV1) :=
  subject.method.callable.result.typeId

end ResolvedOptionStatePeekProductionSubjectV1

private def compileResultV1 (result : CompileResult α) : Except String α :=
  match result with
  | .ok value => .ok value
  | .error error => .error error.render

/-- Reconstruct `peek(Some 77)` only through actual production stages. Missing
    source identity, Option layout, switch HandlerIR, or artifact identity is
    rejected rather than replaced by a fixture value. -/
def resolveOptionStatePeekProductionSubjectV1 :
    Except String ResolvedOptionStatePeekProductionSubjectV1 := do
  unless OptionState.schema == Language.ProgramExport.programExportSchemaV2 do
    throw "OptionState program export schema is not proof-forge.program-export.v2"
  let preparation ← resolveCertifiedSolanaProductionPreparationV1
    OptionState.Source.subjectV1 OptionState.bytes
      optionStateProductionSbpfSha256V1
  let data := preparation.data
  let plan := preparation.productionPlan
  let method ← resolveCertifiedSolanaProductionMethodV1 preparation
    .view (some "peek") "peek"
  unless isSupportedNullaryUInt64SwitchViewHandlerIRV1 method.handler do
    throw "production OptionState.peek is not a supported switch-view HandlerIR"
  let stateRow ← match data.logicalState[0]? with
    | some value => pure value
    | none => throw "production OptionState Semantic program has no state row 0"
  let elementTypeId ← match data.types[stateRow.typeId.toNat]? with
    | some { shape := .option elementTypeId, .. } => pure elementTypeId
    | _ => throw "production OptionState state row 0 is not Option"
  let tagField ← match plan.stateAccount.fields[0]? with
    | some value => pure value
    | none => throw "production OptionState Plan has no tag field 0"
  let payloadField ← match plan.stateAccount.fields[1]? with
    | some value => pure value
    | none => throw "production OptionState Plan has no payload field 1"
  let binding : OptionUInt64StateAccountBindingV1 := {
    semanticStateId := stateRow.id
    optionTypeId := stateRow.typeId
    elementTypeId
    stateName := stateRow.name
    tagPhysicalFieldIndex := 0
    payloadPhysicalFieldIndex := 1
    accountIndex := tagField.accountIndex
    tagByteOffset := tagField.byteOffset
    payloadByteOffset := payloadField.byteOffset
  }
  let logicalValue : Option UInt64 := some 77
  let referencePre ← match encodeLogicalStateValuesV1 data true
      #[encodeOptionUInt64ValueV1 logicalValue] with
    | .ok value => pure value
    | .error error =>
        throw s!"OptionState peek pre-state encoding failed: {repr error}"
  let accountData := optionUInt64AccountDataV1
    plan.stateAccount.initializedMarker logicalValue
  if haccount : checkOptionUInt64LogicalStateAccountRelV1 data plan binding
      referencePre accountData logicalValue = true then
    let accountRelation :=
      (checkOptionUInt64LogicalStateAccountRelV1_eq_true_iff data plan binding
        referencePre accountData logicalValue).mp haccount
    let referenceExecution :=
      executeCertifiedSolanaProductionMethodReferenceV1 method referencePre
        #[] #[] #[] {}
    let discriminator ← compileResultV1 <|
      discriminatorToLeU64V1 method.handler.discriminator
    let handlerInvocation :=
      nullaryUInt64ViewInvocationV1 accountData discriminator
    let programId := Array.replicate 32 (0x42 : UInt8)
    let loaderInvocation : LoaderV3SingleAccountInvocationV1 := {
      accountKey := Array.replicate 32 (0x24 : UInt8)
      owner := programId
      programId
      accountData := accountData.data
      instructionData :=
        SbpfSemantics.wordToLE (BitVec.ofNat 64 discriminator.toNat)
    }
    pure <| ResolvedOptionStatePeekProductionSubjectV1.mk preparation method
      binding referencePre accountData accountRelation referenceExecution
      handlerInvocation loaderInvocation (encodeU64le 77)
  else
    throw "production OptionState logical/account encoding relation failed"

/-- Fail-closed production HandlerIR/provider gate for the exact exported
    OptionState subject. -/
def checkOptionStatePeekProductionSubjectV1 : Bool :=
  checkCertifiedSolanaProductionSubjectV1
    resolveOptionStatePeekProductionSubjectV1 fun subject =>
    checkCertifiedExecutedHandlerSbpfJoinV1 subject.boundArtifact
      subject.handler subject.handlerInvocation subject.loaderInvocation
      optionStatePeekProviderFuelV1 0 optionStateProductionSbpfSha256V1

/-- A successful production gate recovers the exact source-derived subject and
    the generic executed HandlerIR/provider certificate. -/
theorem checkOptionStatePeekProductionSubjectV1_sound
    (checked : checkOptionStatePeekProductionSubjectV1 = true) :
    ∃ subject,
      resolveOptionStatePeekProductionSubjectV1 = .ok subject ∧
      Nonempty (CertifiedExecutedHandlerSbpfJoinV1 subject.boundArtifact
        subject.handler subject.handlerInvocation subject.loaderInvocation
        optionStatePeekProviderFuelV1 0 optionStateProductionSbpfSha256V1) := by
  rcases checkCertifiedSolanaProductionSubjectV1_sound
      resolveOptionStatePeekProductionSubjectV1
      (fun subject =>
        checkCertifiedExecutedHandlerSbpfJoinV1 subject.boundArtifact
          subject.handler subject.handlerInvocation subject.loaderInvocation
          optionStatePeekProviderFuelV1 0 optionStateProductionSbpfSha256V1)
      checked with ⟨subject, hsubject, hchecked⟩
  exact ⟨subject, hsubject,
    checkCertifiedExecutedHandlerSbpfJoinV1_sound subject.boundArtifact
      subject.handler subject.handlerInvocation subject.loaderInvocation
      optionStatePeekProviderFuelV1 0 optionStateProductionSbpfSha256V1
      hchecked⟩

/-- Source-derived Reference→HandlerIR→provider gate for
    `OptionState.peek(Some 77)`. -/
def checkOptionStatePeekReferenceProviderSubjectV1 : Bool :=
  checkCertifiedSolanaProductionCompositionV1
    resolveOptionStatePeekProductionSubjectV1
    (fun subject =>
      checkUInt64ReturnedHandlerObservationRelV1 subject.data
        subject.returnTypeId subject.referencePre subject.referenceOutcome
        subject.returnBytes
        (observeHandlerIRV1 subject.handler subject.handlerInvocation))
    (fun subject =>
      checkCertifiedExecutedHandlerSbpfJoinV1 subject.boundArtifact
        subject.handler subject.handlerInvocation subject.loaderInvocation
        optionStatePeekProviderFuelV1 0 optionStateProductionSbpfSha256V1)

/-- A successful composition gate recovers one shared source-derived subject,
    generic provider certificate, and UInt64 Reference/Handler/provider join.
    The subject additionally retains its `Option UInt64` account relation. -/
theorem checkOptionStatePeekReferenceProviderSubjectV1_sound
    (checked : checkOptionStatePeekReferenceProviderSubjectV1 = true) :
    ∃ subject,
      resolveOptionStatePeekProductionSubjectV1 = .ok subject ∧
      ∃ certified : CertifiedExecutedHandlerSbpfJoinV1 subject.boundArtifact
          subject.handler subject.handlerInvocation subject.loaderInvocation
          optionStatePeekProviderFuelV1 0 optionStateProductionSbpfSha256V1,
        UInt64ReferenceHandlerSbpfJoinV1 subject.data subject.returnTypeId
          subject.referencePre subject.referenceOutcome subject.returnBytes
          certified.executed.handlerObservation
          optionStateProductionSbpfSha256V1
          certified.executed.sbpfObservation := by
  exact checkCertifiedSolanaProductionCompositionV1_sound_of_witnesses
    resolveOptionStatePeekProductionSubjectV1
    (fun subject =>
      checkUInt64ReturnedHandlerObservationRelV1 subject.data
        subject.returnTypeId subject.referencePre subject.referenceOutcome
        subject.returnBytes
        (observeHandlerIRV1 subject.handler subject.handlerInvocation))
    (fun subject =>
      checkCertifiedExecutedHandlerSbpfJoinV1 subject.boundArtifact
        subject.handler subject.handlerInvocation subject.loaderInvocation
        optionStatePeekProviderFuelV1 0 optionStateProductionSbpfSha256V1)
    (fun subject hreference =>
      (checkUInt64ReturnedHandlerObservationRelV1_eq_true_iff subject.data
        subject.returnTypeId subject.referencePre subject.referenceOutcome
        subject.returnBytes
        (observeHandlerIRV1 subject.handler subject.handlerInvocation)).mp
          hreference)
    (fun subject hprovider =>
      checkCertifiedExecutedHandlerSbpfJoinV1_sound subject.boundArtifact
        subject.handler subject.handlerInvocation subject.loaderInvocation
        optionStatePeekProviderFuelV1 0 optionStateProductionSbpfSha256V1
        hprovider)
    (fun _ certified referenceHandler => {
      referenceHandler := by
        simpa [certified.executed.handlerExecution] using referenceHandler
      handlerSbpf := certified.executed.observationRel
    })
    checked

end ProofForgeV2.Targets.Solana
