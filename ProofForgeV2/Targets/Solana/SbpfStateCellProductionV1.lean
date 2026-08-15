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

`get` and `initialize` retain dedicated 55-step certified joins. Successful and
overflowing `increment` use the generic executed HandlerIR/provider join; their
sparse certificates are later slices.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2.Compiler
open ProofForgeV2.Examples
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
  let handler ← match ir.handlers.find? (·.name == "initialize") with
    | some value => pure value
    | none => throw "production StateCell IR has no initialize handler"
  let discriminator ← compileResultV1 <|
    discriminatorToLeU64V1 handler.discriminator
  let argument : UInt64 := 7
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
  pure <| ResolvedStateCellInitializeProductionSubjectV1.mk sourceBinding ir
    assembly boundArtifact handler handlerInvocation loaderInvocation argument

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

/-- Concrete values consumed by the generic StateCell `increment` success
    HandlerIR/provider join. The selected scenario starts at `41` and adds
    `1`; a sparse increment certificate remains a separate later slice. -/
structure ResolvedStateCellIncrementProductionSubjectV1 where
  private mk ::
  sourceBinding : CanonicalSourceBindingV1
    StateCell.Source.subjectV1 StateCell.bytes
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
  let handler ← match ir.handlers.find? (·.name == "increment") with
    | some value => pure value
    | none => throw "production StateCell IR has no increment handler"
  let discriminator ← compileResultV1 <|
    discriminatorToLeU64V1 handler.discriminator
  let before : UInt64 := 41
  let argument : UInt64 := 1
  let accountData :=
    (SbpfSemantics.wordToLE
      (BitVec.ofNat 64 ir.stateAccount.initializedMarker.toNat)).append
      (SbpfSemantics.wordToLE (BitVec.ofNat 64 before.toNat))
  let programId := Array.replicate 32 (0x42 : UInt8)
  let loaderInvocation : LoaderV3SingleAccountInvocationV1 := {
    accountKey := Array.replicate 32 (0x24 : UInt8)
    owner := programId
    programId
    accountData
    instructionData :=
      (SbpfSemantics.wordToLE (BitVec.ofNat 64 discriminator.toNat)).append
        (SbpfSemantics.wordToLE (BitVec.ofNat 64 argument.toNat))
    isWritable := true
  }
  let handlerInvocation :=
    unaryUInt64InvocationV1 ⟨accountData⟩ discriminator argument false true
  pure <| ResolvedStateCellIncrementProductionSubjectV1.mk sourceBinding ir
    assembly boundArtifact handler handlerInvocation loaderInvocation before
    argument

/-- Fail-closed executable agreement for the pinned increment-success subject. -/
def checkStateCellIncrementProductionSubjectV1 : Bool :=
  checkExceptV1 resolveStateCellIncrementProductionSubjectV1 fun subject =>
    checkStateCellExecutedHandlerSbpfJoinV1
      subject.boundArtifact subject.handler subject.handlerInvocation
      subject.loaderInvocation

/-- Successful increment checking recovers the exact production subject and a
    carrier whose equations run both existing evaluators. It is not a sparse
    provider trace certificate. -/
theorem checkStateCellIncrementProductionSubjectV1_sound
    (checked : checkStateCellIncrementProductionSubjectV1 = true) :
    ∃ subject,
      resolveStateCellIncrementProductionSubjectV1 = .ok subject ∧
      Nonempty (StateCellExecutedHandlerSbpfJoinV1
        subject.boundArtifact subject.handler subject.handlerInvocation
        subject.loaderInvocation defaultSbpfExecutionFuelV1) := by
  rcases checkExceptV1_sound resolveStateCellIncrementProductionSubjectV1
      (fun subject =>
        checkStateCellExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation)
      checked with ⟨subject, hsubject, hchecked⟩
  refine ⟨subject, hsubject, ?_⟩
  exact checkStateCellExecutedHandlerSbpfJoinV1_sound
    subject.boundArtifact subject.handler subject.handlerInvocation
    subject.loaderInvocation defaultSbpfExecutionFuelV1 hchecked

/-- The pinned arithmetic-overflow invocation over the exact increment
    production subject. Reusing that private subject guarantees the same source,
    HandlerIR, assembly, and identity-bound provider artifact. -/
structure ResolvedStateCellIncrementOverflowProductionSubjectV1 where
  private mk ::
  production : ResolvedStateCellIncrementProductionSubjectV1
  handlerInvocation : InvocationObservationV1
  loaderInvocation : LoaderV3SingleAccountInvocationV1
  before : UInt64
  argument : UInt64

/-- Reconstruct `UInt64.max + 1` without another compiler or artifact path.
    The existing HandlerIR evaluator must trap before its write and the provider
    join must observe status `0x1001` with the exact pre-account snapshot. -/
def resolveStateCellIncrementOverflowProductionSubjectV1 :
    Except String ResolvedStateCellIncrementOverflowProductionSubjectV1 := do
  let production ← resolveStateCellIncrementProductionSubjectV1
  let discriminator ← compileResultV1 <|
    discriminatorToLeU64V1 production.handler.discriminator
  let before : UInt64 := 0xffffffffffffffff
  let argument : UInt64 := 1
  let accountData :=
    (SbpfSemantics.wordToLE
      (BitVec.ofNat 64 production.ir.stateAccount.initializedMarker.toNat)).append
      (SbpfSemantics.wordToLE (BitVec.ofNat 64 before.toNat))
  let programId := Array.replicate 32 (0x42 : UInt8)
  let loaderInvocation : LoaderV3SingleAccountInvocationV1 := {
    accountKey := Array.replicate 32 (0x24 : UInt8)
    owner := programId
    programId
    accountData
    instructionData :=
      (SbpfSemantics.wordToLE (BitVec.ofNat 64 discriminator.toNat)).append
        (SbpfSemantics.wordToLE (BitVec.ofNat 64 argument.toNat))
    isWritable := true
  }
  let handlerInvocation :=
    unaryUInt64InvocationV1 ⟨accountData⟩ discriminator argument false true
  pure <| ResolvedStateCellIncrementOverflowProductionSubjectV1.mk production
    handlerInvocation loaderInvocation before argument

/-- Fail-closed executable agreement for the pinned increment-overflow subject. -/
def checkStateCellIncrementOverflowProductionSubjectV1 : Bool :=
  checkExceptV1 resolveStateCellIncrementOverflowProductionSubjectV1 fun subject =>
    checkStateCellExecutedHandlerSbpfJoinV1
      subject.production.boundArtifact subject.production.handler
      subject.handlerInvocation subject.loaderInvocation

/-- Successful checking recovers an executed carrier that binds the actual
    Handler arithmetic trap to the identity-bound provider observation. -/
theorem checkStateCellIncrementOverflowProductionSubjectV1_sound
    (checked : checkStateCellIncrementOverflowProductionSubjectV1 = true) :
    ∃ subject,
      resolveStateCellIncrementOverflowProductionSubjectV1 = .ok subject ∧
      Nonempty (StateCellExecutedHandlerSbpfJoinV1
        subject.production.boundArtifact subject.production.handler
        subject.handlerInvocation subject.loaderInvocation
        defaultSbpfExecutionFuelV1) := by
  rcases checkExceptV1_sound
      resolveStateCellIncrementOverflowProductionSubjectV1
      (fun subject =>
        checkStateCellExecutedHandlerSbpfJoinV1
          subject.production.boundArtifact subject.production.handler
          subject.handlerInvocation subject.loaderInvocation)
      checked with ⟨subject, hsubject, hchecked⟩
  refine ⟨subject, hsubject, ?_⟩
  exact checkStateCellExecutedHandlerSbpfJoinV1_sound
    subject.production.boundArtifact subject.production.handler
    subject.handlerInvocation subject.loaderInvocation
    defaultSbpfExecutionFuelV1 hchecked

end ProofForgeV2.Targets.Solana
