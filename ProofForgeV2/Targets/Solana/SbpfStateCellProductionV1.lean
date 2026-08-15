import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.Solana.EmitIRV1
import ProofForgeV2.Targets.Solana.EmitSbpfAsmV1
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

/-- The concrete values consumed by the existing certified StateCell `get`
    HandlerIR/provider join. The private constructor prevents callers from
    presenting a hand-built tuple as the production subject; the sole resolver
    below reconstructs every field from the exported production source. -/
structure ResolvedStateCellGetProductionSubjectV1 where
  private mk ::
  sourceBinding : CanonicalSourceBindingV1
    StateCell.Source.subjectV1 StateCell.bytes
  ir : IR
  assembly : String
  boundArtifact : BoundResolvedSbpfArtifactV1
  handler : HandlerIR
  handlerInvocation : InvocationObservationV1
  loaderInvocation : LoaderV3SingleAccountInvocationV1
  returnBytes : Array UInt8
  value : SbpfSemantics.Word

private def compileResultV1 (result : CompileResult α) : Except String α :=
  match result with
  | .ok value => .ok value
  | .error error => .error error.render

private def artifactResultV1 (result : SbpfArtifactResultV1 α) : Except String α :=
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
  let sourceBinding ← bindElaboratedSourceToCanonicalBytesV1
    StateCell.Source.subjectV1 StateCell.bytes
  let source := sourceBinding.validated
  let compiled ← compileResultV1 <|
    compileValidatedSourceV1 source
  let selection ← compileResultV1 <|
    resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1)
  let capability ← compileResultV1 <|
    resolveEngineeringRequirementsV1 selection compiled
  let ir ← compileResultV1 <|
    fullBodyIrFromProductCapabilityV1 capability false
  let assembly ← compileResultV1 <| emitSbpfAsmV1 ir
  let boundArtifact ← artifactResultV1 <|
    resolveBoundSbpfArtifactV1 assembly stateCellProductionSbpfSha256V1
  let handler ← match ir.handlers.find? (·.name == "get") with
    | some value => pure value
    | none => throw "production StateCell IR has no get handler"
  let discriminator ← compileResultV1 <|
    discriminatorToLeU64V1 handler.discriminator
  let value := BitVec.ofNat 64 41
  let returnBytes := SbpfSemantics.wordToLE value
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
  pure <| ResolvedStateCellGetProductionSubjectV1.mk sourceBinding ir assembly
    boundArtifact handler handlerInvocation loaderInvocation returnBytes value

private def checkExceptV1 (result : Except String α)
    (checker : α → Bool) : Bool :=
  match result with
  | .error _ => false
  | .ok value => checker value

private theorem checkExceptV1_sound
    (result : Except String α) (checker : α → Bool)
    (checked : checkExceptV1 result checker = true) :
    ∃ value, result = .ok value ∧ checker value = true := by
  unfold checkExceptV1 at checked
  cases hresult : result with
  | error error => simp [hresult] at checked
  | ok value =>
      simp [hresult] at checked
      exact ⟨value, rfl, checked⟩

/-- Single fail-closed gate over the pure production subject and the existing
    certified HandlerIR/provider checker. Any source, compiler, profile,
    artifact, handler, or invocation failure returns `false`. -/
def checkStateCellGetProductionSubjectV1 : Bool :=
  checkExceptV1 resolveStateCellGetProductionSubjectV1 fun subject =>
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
  rcases checkExceptV1_sound resolveStateCellGetProductionSubjectV1
      (fun subject =>
        checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation subject.returnBytes subject.value)
      checked with ⟨subject, hsubject, hchecked⟩
  refine ⟨subject, hsubject, ?_⟩
  exact checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1_sound
    subject.boundArtifact subject.handler subject.handlerInvocation
    subject.loaderInvocation subject.returnBytes subject.value hchecked

/-- Concrete values consumed by the generic StateCell `initialize`
    HandlerIR/provider join. Same private-ctor discipline as `get`. -/
structure ResolvedStateCellInitializeProductionSubjectV1 where
  private mk ::
  sourceBinding : CanonicalSourceBindingV1
    StateCell.Source.subjectV1 StateCell.bytes
  referenceProgram : ProofForgeV2.Semantic.WireV1.SemanticProgramV1
  data : SemanticProgramDataV1
  admitted : AdmittedReferenceSliceV1
  referencePre : LogicalStateV1
  referencePost : LogicalStateV1
  referenceOutcome : OutcomeV1
  plan : Plan
  binding : UInt64StateAccountBindingV1
  postData : ByteArray
  ir : IR
  assembly : String
  boundArtifact : BoundResolvedSbpfArtifactV1
  handler : HandlerIR
  handlerInvocation : InvocationObservationV1
  loaderInvocation : LoaderV3SingleAccountInvocationV1
  argument : UInt64

/-- Reconstruct the initialize production subject from the same exported
    StateCell source. Prestate is the uninitialized one-field account used by
    the existing executable observation; the argument is `7`. -/
def resolveStateCellInitializeProductionSubjectV1 :
    Except String ResolvedStateCellInitializeProductionSubjectV1 := do
  unless StateCell.schema == Language.ProgramExport.programExportSchemaV2 do
    throw "StateCell program export schema is not proof-forge.program-export.v2"
  let sourceBinding ← bindElaboratedSourceToCanonicalBytesV1
    StateCell.Source.subjectV1 StateCell.bytes
  let source := sourceBinding.validated
  let compiled ← compileResultV1 <|
    compileValidatedSourceV1 source
  let referenceProgram := CompiledSemanticV1.semanticV1Of compiled
  let data ← match validateSemanticProgramV1 referenceProgram with
    | .ok value => pure value
    | .error error => throw s!"StateCell semantic validation failed: {repr error}"
  let admitted ← match admitReferenceProgramSliceV1 referenceProgram with
    | .ok value => pure value
    | .error error => throw s!"StateCell Reference admission failed: {repr error}"
  let referencePre ← match initialLogicalStateV1 referenceProgram with
    | .ok value => pure value
    | .error error =>
        throw s!"StateCell initial logical state failed: {repr error}"
  let selection ← compileResultV1 <|
    resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1)
  let capability ← compileResultV1 <|
    resolveEngineeringRequirementsV1 selection compiled
  let plan ← compileResultV1 <|
    materializeFullBodyPlanForProductV1 capability false
  let ir ← compileResultV1 <|
    fullBodyIrFromProductCapabilityV1 capability false
  let assembly ← compileResultV1 <| emitSbpfAsmV1 ir
  let boundArtifact ← artifactResultV1 <|
    resolveBoundSbpfArtifactV1 assembly stateCellProductionSbpfSha256V1
  let handler ← match ir.handlers.find? (·.name == "initialize") with
    | some value => pure value
    | none => throw "production StateCell IR has no initialize handler"
  let discriminator ← compileResultV1 <|
    discriminatorToLeU64V1 handler.discriminator
  let argument : UInt64 := 7
  let initializer ← match data.callables.find? (·.kind == .initializer) with
    | some value => pure value
    | none => throw "production StateCell Semantic program has no initializer"
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
  let referenceOutcome := stepReferenceSliceV1 admitted referencePre {
    callableId := initializer.id
    args := #[{
      typeId := binding.semanticTypeId
      valueBytes := encodeU64le argument
    }]
    context := #[]
  } #[]
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
  pure <| ResolvedStateCellInitializeProductionSubjectV1.mk sourceBinding
    referenceProgram data admitted referencePre referencePost referenceOutcome
    plan binding postData ir assembly boundArtifact handler handlerInvocation
    loaderInvocation argument

def checkStateCellInitializeProductionSubjectV1 : Bool :=
  checkExceptV1 resolveStateCellInitializeProductionSubjectV1 fun subject =>
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
  rcases checkExceptV1_sound resolveStateCellInitializeProductionSubjectV1
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
  checkExceptV1 resolveStateCellInitializeProductionSubjectV1 fun subject =>
    checkUInt64InitializerReturnedHandlerObservationRelV1 subject.data
      subject.plan subject.binding subject.referencePost subject.referenceOutcome
      subject.postData subject.argument
      (observeHandlerIRV1 subject.handler subject.handlerInvocation) &&
    checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
      subject.boundArtifact subject.handler subject.handlerInvocation
      subject.loaderInvocation (BitVec.ofNat 64 subject.argument.toNat)

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
  rcases checkExceptV1_sound resolveStateCellInitializeProductionSubjectV1
      (fun subject =>
        checkUInt64InitializerReturnedHandlerObservationRelV1 subject.data
          subject.plan subject.binding subject.referencePost
          subject.referenceOutcome subject.postData subject.argument
          (observeHandlerIRV1 subject.handler subject.handlerInvocation) &&
        checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.argument.toNat))
      checked with ⟨subject, hsubject, hchecked⟩
  simp only [Bool.and_eq_true] at hchecked
  rcases hchecked with ⟨hreference, hprovider⟩
  have referenceHandler :
      UInt64InitializerReturnedHandlerObservationRelV1 subject.data subject.plan
        subject.binding subject.referencePost subject.referenceOutcome
        subject.postData subject.argument
        (observeHandlerIRV1 subject.handler subject.handlerInvocation) :=
    (checkUInt64InitializerReturnedHandlerObservationRelV1_eq_true_iff
      subject.data subject.plan subject.binding subject.referencePost
      subject.referenceOutcome subject.postData subject.argument
      (observeHandlerIRV1 subject.handler subject.handlerInvocation)).mp hreference
  rcases checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1_sound
      subject.boundArtifact subject.handler subject.handlerInvocation
      subject.loaderInvocation (BitVec.ofNat 64 subject.argument.toNat)
      hprovider with ⟨certified⟩
  refine ⟨subject, hsubject, certified, ?_⟩
  exact certified.referenceJoin (by
    simpa [certified.executed.handlerExecution] using referenceHandler)

/-- Concrete values consumed by the certified StateCell `increment` success
    HandlerIR/provider join. The selected scenario starts at `41` and adds
    `1` along the exact 70-step provider path. -/
structure ResolvedStateCellIncrementProductionSubjectV1 where
  private mk ::
  sourceBinding : CanonicalSourceBindingV1
    StateCell.Source.subjectV1 StateCell.bytes
  referenceProgram : ProofForgeV2.Semantic.WireV1.SemanticProgramV1
  data : SemanticProgramDataV1
  admitted : AdmittedReferenceSliceV1
  referencePre : LogicalStateV1
  referencePost : LogicalStateV1
  referenceOutcome : OutcomeV1
  plan : Plan
  binding : UInt64StateAccountBindingV1
  postData : ByteArray
  ir : IR
  assembly : String
  boundArtifact : BoundResolvedSbpfArtifactV1
  handler : HandlerIR
  handlerInvocation : InvocationObservationV1
  loaderInvocation : LoaderV3SingleAccountInvocationV1
  before : UInt64
  argument : UInt64

/-- Reconstruct the increment-success subject from the same production source,
    compiler, assembly emitter, identity gate, and provider artifact as `get`
    and `initialize`. -/
def resolveStateCellIncrementProductionSubjectV1 :
    Except String ResolvedStateCellIncrementProductionSubjectV1 := do
  unless StateCell.schema == Language.ProgramExport.programExportSchemaV2 do
    throw "StateCell program export schema is not proof-forge.program-export.v2"
  let sourceBinding ← bindElaboratedSourceToCanonicalBytesV1
    StateCell.Source.subjectV1 StateCell.bytes
  let source := sourceBinding.validated
  let compiled ← compileResultV1 <|
    compileValidatedSourceV1 source
  let referenceProgram := CompiledSemanticV1.semanticV1Of compiled
  let data ← match validateSemanticProgramV1 referenceProgram with
    | .ok value => pure value
    | .error error => throw s!"StateCell semantic validation failed: {repr error}"
  let admitted ← match admitReferenceProgramSliceV1 referenceProgram with
    | .ok value => pure value
    | .error error => throw s!"StateCell Reference admission failed: {repr error}"
  let selection ← compileResultV1 <|
    resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1)
  let capability ← compileResultV1 <|
    resolveEngineeringRequirementsV1 selection compiled
  let plan ← compileResultV1 <|
    materializeFullBodyPlanForProductV1 capability false
  let ir ← compileResultV1 <|
    fullBodyIrFromProductCapabilityV1 capability false
  let assembly ← compileResultV1 <| emitSbpfAsmV1 ir
  let boundArtifact ← artifactResultV1 <|
    resolveBoundSbpfArtifactV1 assembly stateCellProductionSbpfSha256V1
  let handler ← match ir.handlers.find? (·.name == "increment") with
    | some value => pure value
    | none => throw "production StateCell IR has no increment handler"
  let discriminator ← compileResultV1 <|
    discriminatorToLeU64V1 handler.discriminator
  let before : UInt64 := 41
  let argument : UInt64 := 1
  let increment ← match data.callables.find? (fun callable =>
      callable.kind == .entry && callable.name == some "increment") with
    | some value => pure value
    | none => throw "production StateCell Semantic program has no increment entry"
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
  let referenceOutcome := stepReferenceSliceV1 admitted referencePre {
    callableId := increment.id
    args := #[{
      typeId := binding.semanticTypeId
      valueBytes := encodeU64le argument
    }]
    context := #[]
  } #[]
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
  pure <| ResolvedStateCellIncrementProductionSubjectV1.mk sourceBinding
    referenceProgram data admitted referencePre referencePost referenceOutcome
    plan binding postData ir assembly boundArtifact handler handlerInvocation
    loaderInvocation before argument

/-- Fail-closed certified agreement for the pinned increment-success subject. -/
def checkStateCellIncrementProductionSubjectV1 : Bool :=
  checkExceptV1 resolveStateCellIncrementProductionSubjectV1 fun subject =>
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
  rcases checkExceptV1_sound resolveStateCellIncrementProductionSubjectV1
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
  checkExceptV1 resolveStateCellIncrementProductionSubjectV1 fun subject =>
    checkUInt64CheckedAddReturnedHandlerObservationRelV1 subject.data
      subject.plan subject.binding subject.referencePost subject.referenceOutcome
      subject.postData subject.before subject.argument
      (observeHandlerIRV1 subject.handler subject.handlerInvocation) &&
    checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
      subject.boundArtifact subject.handler subject.handlerInvocation
      subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
      (BitVec.ofNat 64 subject.argument.toNat)

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
  rcases checkExceptV1_sound resolveStateCellIncrementProductionSubjectV1
      (fun subject =>
        checkUInt64CheckedAddReturnedHandlerObservationRelV1 subject.data
          subject.plan subject.binding subject.referencePost
          subject.referenceOutcome subject.postData subject.before
          subject.argument
          (observeHandlerIRV1 subject.handler subject.handlerInvocation) &&
        checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat))
      checked with ⟨subject, hsubject, hchecked⟩
  simp only [Bool.and_eq_true] at hchecked
  rcases hchecked with ⟨hreference, hprovider⟩
  have referenceHandler :
      UInt64CheckedAddReturnedHandlerObservationRelV1 subject.data subject.plan
        subject.binding subject.referencePost subject.referenceOutcome
        subject.postData subject.before subject.argument
        (observeHandlerIRV1 subject.handler subject.handlerInvocation) :=
    (checkUInt64CheckedAddReturnedHandlerObservationRelV1_eq_true_iff
      subject.data subject.plan subject.binding subject.referencePost
      subject.referenceOutcome subject.postData subject.before subject.argument
      (observeHandlerIRV1 subject.handler subject.handlerInvocation)).mp hreference
  rcases checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1_sound
      subject.boundArtifact subject.handler subject.handlerInvocation
      subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
      (BitVec.ofNat 64 subject.argument.toNat) hprovider with ⟨certified⟩
  refine ⟨subject, hsubject, certified, ?_⟩
  exact certified.referenceJoin (by
    simpa [certified.executed.handlerExecution] using referenceHandler)

/-- The pinned arithmetic-overflow invocation over the exact increment
    production subject. Reusing that private subject guarantees the same source,
    HandlerIR, assembly, and identity-bound provider artifact. -/
structure ResolvedStateCellIncrementOverflowProductionSubjectV1 where
  private mk ::
  production : ResolvedStateCellIncrementProductionSubjectV1
  referencePre : LogicalStateV1
  referenceOutcome : OutcomeV1
  accountData : ByteArray
  handlerInvocation : InvocationObservationV1
  loaderInvocation : LoaderV3SingleAccountInvocationV1
  before : UInt64
  argument : UInt64

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
  let increment ← match production.data.callables.find? (fun callable =>
      callable.kind == .entry && callable.name == some "increment") with
    | some value => pure value
    | none => throw "production StateCell Semantic program has no increment entry"
  let referencePre ← match encodeLogicalStateValuesV1 production.data true
      #[encodeU64le before] with
    | .ok value => pure value
    | .error error =>
        throw s!"StateCell increment overflow pre-state encoding failed: {repr error}"
  let referenceOutcome := stepReferenceSliceV1 production.admitted referencePre {
    callableId := increment.id
    args := #[{
      typeId := production.binding.semanticTypeId
      valueBytes := encodeU64le argument
    }]
    context := #[]
  } #[]
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
    referencePre referenceOutcome accountData handlerInvocation loaderInvocation
    before argument

/-- Fail-closed certified agreement for the pinned increment-overflow subject. -/
def checkStateCellIncrementOverflowProductionSubjectV1 : Bool :=
  checkExceptV1 resolveStateCellIncrementOverflowProductionSubjectV1 fun subject =>
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
  rcases checkExceptV1_sound
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
  checkExceptV1 resolveStateCellIncrementOverflowProductionSubjectV1 fun subject =>
    checkUInt64CheckedAddOverflowHandlerObservationRelV1
      subject.production.data subject.production.plan subject.production.binding
      subject.referencePre subject.referenceOutcome subject.accountData
      subject.before
      (observeHandlerIRV1 subject.production.handler
        subject.handlerInvocation) &&
    checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
      subject.production.boundArtifact subject.production.handler
      subject.handlerInvocation subject.loaderInvocation
      (BitVec.ofNat 64 subject.before.toNat)
      (BitVec.ofNat 64 subject.argument.toNat)

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
  rcases checkExceptV1_sound
      resolveStateCellIncrementOverflowProductionSubjectV1
      (fun subject =>
        checkUInt64CheckedAddOverflowHandlerObservationRelV1
          subject.production.data subject.production.plan
          subject.production.binding subject.referencePre
          subject.referenceOutcome subject.accountData subject.before
          (observeHandlerIRV1 subject.production.handler
            subject.handlerInvocation) &&
        checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
          subject.production.boundArtifact subject.production.handler
          subject.handlerInvocation subject.loaderInvocation
          (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat))
      checked with ⟨subject, hsubject, hchecked⟩
  simp only [Bool.and_eq_true] at hchecked
  rcases hchecked with ⟨hreference, hprovider⟩
  have referenceHandler :
      UInt64CheckedAddOverflowHandlerObservationRelV1
        subject.production.data subject.production.plan
        subject.production.binding subject.referencePre
        subject.referenceOutcome subject.accountData subject.before
        (observeHandlerIRV1 subject.production.handler
          subject.handlerInvocation) :=
    (checkUInt64CheckedAddOverflowHandlerObservationRelV1_eq_true_iff
      subject.production.data subject.production.plan
      subject.production.binding subject.referencePre
      subject.referenceOutcome subject.accountData subject.before
      (observeHandlerIRV1 subject.production.handler
        subject.handlerInvocation)).mp hreference
  rcases checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1_sound
      subject.production.boundArtifact subject.production.handler
      subject.handlerInvocation subject.loaderInvocation
      (BitVec.ofNat 64 subject.before.toNat)
      (BitVec.ofNat 64 subject.argument.toNat) hprovider with ⟨certified⟩
  refine ⟨subject, hsubject, certified, ?_⟩
  exact certified.referenceJoin (by
    simpa [certified.executed.handlerExecution] using referenceHandler)

end ProofForgeV2.Targets.Solana
