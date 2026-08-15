import ProofForgeV2.Examples.OptionState
import ProofForgeV2.Targets.Solana.ProductionCompositionV1
import ProofForgeV2.Targets.Solana.ProductionMethodV1
import ProofForgeV2.Targets.Solana.SbpfHandlerJoinV1

/-!
# Solana OptionState production subjects

This module is the second real consumer of the contract-independent Solana
production chain. It reconstructs OptionState from the actual exported Source
AST, executes `peek` and `getOpt` with the sole Reference machine, executes
their production HandlerIR, and runs the identity-bound production assembly
with the shared provider resolver.

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

/-- Fuel retained for the production `getOpt(Some 77)` aggregate-return
    scenario. The same pinned artifact halts before this bound. -/
def optionStateGetOptProviderFuelV1 : Nat := 80

/-- Shared source-derived OptionState production state. Method selection and
    execution are deliberately absent: `peek`, `getOpt`, and later methods must
    all consume the same compiler/Plan/account representation authority. -/
structure ResolvedOptionStateProductionStateV1 where
  private mk ::
  preparation : CertifiedSolanaProductionPreparationV1
    OptionState.Source.subjectV1 OptionState.bytes
      optionStateProductionSbpfSha256V1
  binding : OptionUInt64StateAccountBindingV1
  referencePre : LogicalStateV1
  accountData : ByteArray
  accountRelation : OptionUInt64LogicalStateAccountRelV1 preparation.data
    preparation.productionPlan binding referencePre accountData (some 77)

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

/-- Reconstruct the shared `Some 77` logical/account state only through actual
    production stages. No method is required to establish this authority. -/
def resolveOptionStateProductionStateV1 :
    Except String ResolvedOptionStateProductionStateV1 := do
  unless OptionState.schema == Language.ProgramExport.programExportSchemaV2 do
    throw "OptionState program export schema is not proof-forge.program-export.v2"
  let preparation ← resolveCertifiedSolanaProductionPreparationV1
    OptionState.Source.subjectV1 OptionState.bytes
      optionStateProductionSbpfSha256V1
  let data := preparation.data
  let plan := preparation.productionPlan
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
    pure <| ResolvedOptionStateProductionStateV1.mk preparation binding
      referencePre accountData accountRelation
  else
    throw "production OptionState logical/account encoding relation failed"

/-- Canonical Loader V3 invocation for any nullary OptionState production
    method over the retained account. The method discriminator is supplied by
    the generic production method resolver. -/
def optionStateNullaryLoaderInvocationV1
    (accountData : ByteArray)
    (discriminator : UInt64) : LoaderV3SingleAccountInvocationV1 :=
  let programId := Array.replicate 32 (0x42 : UInt8)
  {
    accountKey := Array.replicate 32 (0x24 : UInt8)
    owner := programId
    programId
    accountData := accountData.data
    instructionData :=
      SbpfSemantics.wordToLE (BitVec.ofNat 64 discriminator.toNat)
  }

/-- Reconstruct `peek(Some 77)` only through actual production stages. Missing
    source identity, Option layout, switch HandlerIR, or artifact identity is
    rejected rather than replaced by a fixture value. -/
def resolveOptionStatePeekProductionSubjectV1 :
    Except String ResolvedOptionStatePeekProductionSubjectV1 := do
  let shared ← resolveOptionStateProductionStateV1
  let preparation := shared.preparation
  let method ← resolveCertifiedSolanaProductionMethodV1 preparation
    .view (some "peek") "peek"
  unless isSupportedNullaryUInt64SwitchViewHandlerIRV1 method.handler do
    throw "production OptionState.peek is not a supported switch-view HandlerIR"
  let referenceExecution :=
    executeCertifiedSolanaProductionMethodReferenceV1 method shared.referencePre
      #[] #[] #[] {}
  let discriminator ← compileResultV1 <|
    discriminatorToLeU64V1 method.handler.discriminator
  let handlerInvocation :=
    nullaryUInt64ViewInvocationV1 shared.accountData discriminator
  let loaderInvocation :=
    optionStateNullaryLoaderInvocationV1 shared.accountData discriminator
  pure <| ResolvedOptionStatePeekProductionSubjectV1.mk preparation method
    shared.binding shared.referencePre shared.accountData shared.accountRelation
    referenceExecution handlerInvocation loaderInvocation (encodeU64le 77)

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

/-- Source-derived production subject for the real multiword `getOpt` return.
    The shared state owns compiler/Plan/account identity; this carrier only
    adds generic method selection and actual Reference/target observations. -/
structure ResolvedOptionStateGetOptProductionSubjectV1 where
  private mk ::
  shared : ResolvedOptionStateProductionStateV1
  method : CertifiedSolanaProductionMethodV1 shared.preparation .view
    (some "getOpt") "getOpt"
  referenceExecution : CertifiedSolanaProductionMethodReferenceV1 method
    shared.referencePre #[] #[] #[] {}
  targetShape : NullaryTwoLeafAggregateViewHandlerIRShapeV1
  targetAlignment : NullaryTwoLeafAggregateViewStaticAlignmentV1
    shared.preparation.productionPlan shared.binding.tagByteOffset
      shared.binding.payloadByteOffset false false method.handler.name
      method.handler.discriminator method.handler
  discriminatorValue : UInt64
  discriminatorEquation :
    discriminatorToLeU64V1 method.handler.discriminator = .ok discriminatorValue
  handlerInvocation : InvocationObservationV1
  handlerInvocationExact : handlerInvocation =
    nullaryUInt64ViewInvocationV1 shared.accountData discriminatorValue
  loaderInvocation : LoaderV3SingleAccountInvocationV1
  referenceValueBytes : ByteArray
  targetReturnBytes : ByteArray
  targetReturnBytesExact : targetReturnBytes =
    optionUInt64AggregateReturnDataV1 (some 77)

namespace ResolvedOptionStateGetOptProductionSubjectV1

def preparation (subject : ResolvedOptionStateGetOptProductionSubjectV1) :=
  subject.shared.preparation

def data (subject : ResolvedOptionStateGetOptProductionSubjectV1) :=
  subject.preparation.data

def plan (subject : ResolvedOptionStateGetOptProductionSubjectV1) :=
  subject.preparation.productionPlan

def binding (subject : ResolvedOptionStateGetOptProductionSubjectV1) :=
  subject.shared.binding

def referencePre (subject : ResolvedOptionStateGetOptProductionSubjectV1) :=
  subject.shared.referencePre

def accountData (subject : ResolvedOptionStateGetOptProductionSubjectV1) :=
  subject.shared.accountData

def boundArtifact (subject : ResolvedOptionStateGetOptProductionSubjectV1) :=
  subject.preparation.boundArtifact

def handler (subject : ResolvedOptionStateGetOptProductionSubjectV1) :=
  subject.method.handler

def referenceOutcome (subject : ResolvedOptionStateGetOptProductionSubjectV1) :=
  subject.referenceExecution.outcome

def returnTypeId (subject : ResolvedOptionStateGetOptProductionSubjectV1) :=
  subject.method.callable.result.typeId

end ResolvedOptionStateGetOptProductionSubjectV1

/-- Resolve the real `getOpt(Some 77)` method from the same source-derived
    OptionState production state used by `peek`. The aggregate recognizer is
    structural and does not inspect the contract or method name. -/
def resolveOptionStateGetOptProductionSubjectV1 :
    Except String ResolvedOptionStateGetOptProductionSubjectV1 := do
  let shared ← resolveOptionStateProductionStateV1
  let method ← resolveCertifiedSolanaProductionMethodV1 shared.preparation
    .view (some "getOpt") "getOpt"
  let recognized ← match
      certifyNullaryTwoLeafAggregateViewHandlerIRV1 method.handler with
    | some certified => pure certified
    | none =>
        throw "production OptionState.getOpt is not an exact two-leaf aggregate HandlerIR"
  let targetShape := recognized.shape
  let plan := shared.preparation.productionPlan
  if hshape : checkNullaryTwoLeafAggregateViewHandlerIRShapeRelV1 plan
      shared.binding.tagByteOffset shared.binding.payloadByteOffset false false
      method.handler.name method.handler.discriminator targetShape = true then
    have hshapeRel :=
      (checkNullaryTwoLeafAggregateViewHandlerIRShapeRelV1_eq_true_iff plan
        shared.binding.tagByteOffset shared.binding.payloadByteOffset false false
        method.handler.name method.handler.discriminator targetShape).mp hshape
    have howner : plan.stateAccount.ownerPolicy = .currentProgram := by
      cases plan.stateAccount.ownerPolicy
      rfl
    let targetAlignment :=
      nullaryTwoLeafAggregateViewStaticAlignmentV1_of_recognized plan
        shared.binding.tagByteOffset shared.binding.payloadByteOffset false false
        method.handler.name method.handler.discriminator method.handler
        targetShape recognized.recognition howner hshapeRel
    let referenceExecution :=
      executeCertifiedSolanaProductionMethodReferenceV1 method shared.referencePre
        #[] #[] #[] {}
    match hdiscriminator :
        discriminatorToLeU64V1 method.handler.discriminator with
    | .error error => throw error.render
    | .ok discriminatorValue =>
      let handlerInvocation :=
        nullaryUInt64ViewInvocationV1 shared.accountData discriminatorValue
      let loaderInvocation :=
        optionStateNullaryLoaderInvocationV1 shared.accountData discriminatorValue
      let logicalValue : Option UInt64 := some 77
      pure <| ResolvedOptionStateGetOptProductionSubjectV1.mk shared method
        referenceExecution targetShape targetAlignment discriminatorValue
        hdiscriminator handlerInvocation rfl loaderInvocation
        (encodeOptionUInt64ValueV1 logicalValue)
        (optionUInt64AggregateReturnDataV1 logicalValue) rfl
  else
    throw "production OptionState.getOpt HandlerIR does not align with its Plan"

/-- Every resolved production getOpt subject carries a kernel proof of its
    exact target return and read-only account stutter. Source/compiler/artifact
    reduction is confined to subject resolution; this theorem consumes the
    retained target certificate. -/
theorem resolvedOptionStateGetOptProductionSubjectV1_handlerObservation
    (subject : ResolvedOptionStateGetOptProductionSubjectV1) :
    observeHandlerIRV1 subject.handler subject.handlerInvocation = {
      invocation := subject.handlerInvocation
      outcome := .returned (some subject.targetReturnBytes)
      postAccounts := subject.handlerInvocation.accounts
    } := by
  rcases subject.shared.accountRelation with
    ⟨_, _, _, hdataLength, hheader, htag, hpayload⟩
  rw [subject.handlerInvocationExact, subject.targetReturnBytesExact]
  exact observeHandlerIRV1_of_nullaryTwoLeafAggregateViewStaticAlignment
    subject.plan subject.binding.tagByteOffset subject.binding.payloadByteOffset
    false false subject.handler.name subject.handler.discriminator
    subject.handler subject.accountData subject.discriminatorValue
    (optionUInt64TagV1 (some 77)) (optionUInt64PayloadV1 (some 77))
    subject.targetAlignment subject.discriminatorEquation hdataLength hheader
    htag hpayload

/-- Fail-closed production HandlerIR/provider gate for the real aggregate
    OptionState method. -/
def checkOptionStateGetOptProductionSubjectV1 : Bool :=
  checkCertifiedSolanaProductionSubjectV1
    resolveOptionStateGetOptProductionSubjectV1 fun subject =>
    checkCertifiedExecutedHandlerSbpfJoinV1 subject.boundArtifact
      subject.handler subject.handlerInvocation subject.loaderInvocation
      optionStateGetOptProviderFuelV1 0 optionStateProductionSbpfSha256V1

theorem checkOptionStateGetOptProductionSubjectV1_sound
    (checked : checkOptionStateGetOptProductionSubjectV1 = true) :
    ∃ subject,
      resolveOptionStateGetOptProductionSubjectV1 = .ok subject ∧
      Nonempty (CertifiedExecutedHandlerSbpfJoinV1 subject.boundArtifact
        subject.handler subject.handlerInvocation subject.loaderInvocation
        optionStateGetOptProviderFuelV1 0 optionStateProductionSbpfSha256V1) := by
  rcases checkCertifiedSolanaProductionSubjectV1_sound
      resolveOptionStateGetOptProductionSubjectV1
      (fun subject =>
        checkCertifiedExecutedHandlerSbpfJoinV1 subject.boundArtifact
          subject.handler subject.handlerInvocation subject.loaderInvocation
          optionStateGetOptProviderFuelV1 0 optionStateProductionSbpfSha256V1)
      checked with ⟨subject, hsubject, hchecked⟩
  exact ⟨subject, hsubject,
    checkCertifiedExecutedHandlerSbpfJoinV1_sound subject.boundArtifact
      subject.handler subject.handlerInvocation subject.loaderInvocation
      optionStateGetOptProviderFuelV1 0 optionStateProductionSbpfSha256V1
      hchecked⟩

/-- Typed aggregate composition gate. Canonical Reference Option bytes and
    the two-word target ABI bytes are intentionally related, not equated. -/
def checkOptionStateGetOptReferenceProviderSubjectV1 : Bool :=
  checkCertifiedSolanaProductionCompositionV1
    resolveOptionStateGetOptProductionSubjectV1
    (fun subject =>
      checkTypedReturnedHandlerObservationRelV1 subject.data
        subject.returnTypeId subject.referencePre subject.referenceOutcome
        subject.referenceValueBytes subject.targetReturnBytes
        (observeHandlerIRV1 subject.handler subject.handlerInvocation))
    (fun subject =>
      checkCertifiedExecutedHandlerSbpfJoinV1 subject.boundArtifact
        subject.handler subject.handlerInvocation subject.loaderInvocation
        optionStateGetOptProviderFuelV1 0 optionStateProductionSbpfSha256V1)

/-- Soundness packages the generic typed Reference/Handler relation with the
    shared executed Handler/provider certificate. -/
theorem checkOptionStateGetOptReferenceProviderSubjectV1_sound
    (checked : checkOptionStateGetOptReferenceProviderSubjectV1 = true) :
    ∃ subject,
      resolveOptionStateGetOptProductionSubjectV1 = .ok subject ∧
      ∃ certified : CertifiedExecutedHandlerSbpfJoinV1 subject.boundArtifact
          subject.handler subject.handlerInvocation subject.loaderInvocation
          optionStateGetOptProviderFuelV1 0 optionStateProductionSbpfSha256V1,
        TypedReferenceHandlerSbpfJoinV1 subject.data subject.returnTypeId
          subject.referencePre subject.referenceOutcome
          subject.referenceValueBytes subject.targetReturnBytes
          certified.executed.handlerObservation
          optionStateProductionSbpfSha256V1
          certified.executed.sbpfObservation := by
  exact checkCertifiedSolanaProductionCompositionV1_sound_of_witnesses
    resolveOptionStateGetOptProductionSubjectV1
    (fun subject =>
      checkTypedReturnedHandlerObservationRelV1 subject.data
        subject.returnTypeId subject.referencePre subject.referenceOutcome
        subject.referenceValueBytes subject.targetReturnBytes
        (observeHandlerIRV1 subject.handler subject.handlerInvocation))
    (fun subject =>
      checkCertifiedExecutedHandlerSbpfJoinV1 subject.boundArtifact
        subject.handler subject.handlerInvocation subject.loaderInvocation
        optionStateGetOptProviderFuelV1 0 optionStateProductionSbpfSha256V1)
    (fun subject hreference =>
      (checkTypedReturnedHandlerObservationRelV1_eq_true_iff subject.data
        subject.returnTypeId subject.referencePre subject.referenceOutcome
        subject.referenceValueBytes subject.targetReturnBytes
        (observeHandlerIRV1 subject.handler subject.handlerInvocation)).mp
          hreference)
    (fun subject hprovider =>
      checkCertifiedExecutedHandlerSbpfJoinV1_sound subject.boundArtifact
        subject.handler subject.handlerInvocation subject.loaderInvocation
        optionStateGetOptProviderFuelV1 0 optionStateProductionSbpfSha256V1
        hprovider)
    (fun _ certified referenceHandler => {
      referenceHandler := by
        simpa [certified.executed.handlerExecution] using referenceHandler
      handlerSbpf := certified.executed.observationRel
    })
    checked

end ProofForgeV2.Targets.Solana
