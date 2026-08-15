import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.ReferenceV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.Solana.EmitIRV1
import ProofForgeV2.Targets.Solana.EmitSbpfAsmV1
import ProofForgeV2.Targets.Solana.SbpfArtifactV1

/-!
# Contract-independent Solana production preparation certificate

This module decomposes the production Source → Reference/HandlerIR → assembly
artifact preparation gate into proof-producing stages. Every retained value is
accompanied by an equality showing that the existing production function
returned it. No source AST, lowering, business semantics, or provider program
is copied here.

Contract modules supply only their elaborated source, canonical export bytes,
and expected production artifact SHA-256. Method-specific Reference and
provider certificates remain outside this contract-independent boundary.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Targets.BuildSelectionV1

/-- One successful production stage together with its exact result equation.
    This carrier does not evaluate or replace the stage. -/
structure ProductionStageSuccessV1 {ε α : Type} (result : Except ε α) where
  value : α
  success : result = .ok value

/-- Run one existing production stage and retain its success equation. -/
def certifyProductionStageV1 {ε α : Type}
    (renderError : ε → String) (result : Except ε α) :
    Except String (ProductionStageSuccessV1 result) :=
  match result with
  | .ok value => .ok ⟨value, rfl⟩
  | .error error => .error (renderError error)

/-- Replay one retained stage certificate through the existing fail-closed
    certifier. This is the completeness direction paired with the certificate's
    `success` equation; it does not evaluate or replace the production stage. -/
theorem certifyProductionStageV1_eq_ok {ε α : Type}
    (renderError : ε → String) (result : Except ε α)
    (certified : ProductionStageSuccessV1 result) :
    certifyProductionStageV1 renderError result = .ok certified := by
  rcases certified with ⟨value, success⟩
  subst result
  simp [certifyProductionStageV1]

/-- Contract-independent proof decomposition of the production Solana sBPF
    preparation pipeline. Its indices bind the exact source/export/artifact
    identity while every field retains the real production function result. -/
structure CertifiedSolanaProductionPreparationV1
    (elaborated : ElaboratedSourceV1)
    (canonicalBytes : ByteArray)
    (expectedArtifactSha256 : String) where
  source : ProductionStageSuccessV1
    (bindElaboratedSourceToCanonicalBytesV1 elaborated canonicalBytes)
  compiled : ProductionStageSuccessV1
    (compileValidatedSourceV1 source.value.validated)
  semanticData : ProductionStageSuccessV1
    (validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled.value))
  referenceAdmission : ProductionStageSuccessV1
    (admitReferenceProgramSliceV1
      (CompiledSemanticV1.semanticV1Of compiled.value))
  selection : ProductionStageSuccessV1
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1))
  capability : ProductionStageSuccessV1
    (resolveEngineeringRequirementsV1 selection.value compiled.value)
  plan : ProductionStageSuccessV1
    (materializeFullBodyPlanForProductV1 capability.value false)
  ir : ProductionStageSuccessV1
    (fullBodyIrFromProductCapabilityV1 capability.value false)
  assembly : ProductionStageSuccessV1 (emitSbpfAsmV1 ir.value)
  artifact : BoundResolvedSbpfArtifactV1
  artifactSuccess :
    resolveBoundSbpfArtifactV1 assembly.value expectedArtifactSha256 = .ok artifact

namespace CertifiedSolanaProductionPreparationV1

def sourceBinding (prepared :
    CertifiedSolanaProductionPreparationV1 elaborated canonicalBytes expectedSha) :
    CanonicalSourceBindingV1 elaborated canonicalBytes :=
  prepared.source.value

def compiledSemantic (prepared :
    CertifiedSolanaProductionPreparationV1 elaborated canonicalBytes expectedSha) :
    CompiledSemanticV1 :=
  prepared.compiled.value

def referenceProgram (prepared :
    CertifiedSolanaProductionPreparationV1 elaborated canonicalBytes expectedSha) :
    SemanticProgramV1 :=
  CompiledSemanticV1.semanticV1Of prepared.compiled.value

def data (prepared :
    CertifiedSolanaProductionPreparationV1 elaborated canonicalBytes expectedSha) :
    SemanticProgramDataV1 :=
  prepared.semanticData.value

def admitted (prepared :
    CertifiedSolanaProductionPreparationV1 elaborated canonicalBytes expectedSha) :
    AdmittedReferenceSliceV1 :=
  prepared.referenceAdmission.value

def productionPlan (prepared :
    CertifiedSolanaProductionPreparationV1 elaborated canonicalBytes expectedSha) :
    Plan :=
  prepared.plan.value

def productionIR (prepared :
    CertifiedSolanaProductionPreparationV1 elaborated canonicalBytes expectedSha) :
    IR :=
  prepared.ir.value

def productionAssembly (prepared :
    CertifiedSolanaProductionPreparationV1 elaborated canonicalBytes expectedSha) :
    String :=
  prepared.assembly.value

def boundArtifact (prepared :
    CertifiedSolanaProductionPreparationV1 elaborated canonicalBytes expectedSha) :
    BoundResolvedSbpfArtifactV1 :=
  prepared.artifact

/-- Generic compilation equation exposed for downstream kernel composition. -/
theorem compilation_success (prepared :
    CertifiedSolanaProductionPreparationV1 elaborated canonicalBytes expectedSha) :
    compileValidatedSourceV1 prepared.sourceBinding.validated =
      .ok prepared.compiledSemantic :=
  prepared.compiled.success

/-- Generic Reference-admission equation exposed for downstream composition. -/
theorem referenceAdmission_success (prepared :
    CertifiedSolanaProductionPreparationV1 elaborated canonicalBytes expectedSha) :
    admitReferenceProgramSliceV1 prepared.referenceProgram =
      .ok prepared.admitted :=
  prepared.referenceAdmission.success

/-- Exact production emitter certificate retained by this preparation. It
    decomposes the existing assembly-stage equation; it does not invoke or
    model a second emitter. -/
theorem emission_certificate (prepared :
    CertifiedSolanaProductionPreparationV1 elaborated canonicalBytes expectedSha) :
    SbpfAsmEmissionCertificateV1 prepared.productionIR
      prepared.productionAssembly :=
  SbpfAsmEmissionCertificateV1.of_success prepared.assembly.success

/-- Generic final identity-bound artifact equation. -/
theorem artifact_success (prepared :
    CertifiedSolanaProductionPreparationV1 elaborated canonicalBytes expectedSha) :
    resolveBoundSbpfArtifactV1 prepared.productionAssembly expectedSha =
      .ok prepared.boundArtifact :=
  prepared.artifactSuccess

end CertifiedSolanaProductionPreparationV1

/-- Execute the existing production preparation stages and retain each exact
    success equation. Any unsupported source, compile failure, emission error,
    or missing/tampered artifact identity fails closed. -/
def resolveCertifiedSolanaProductionPreparationV1
    (elaborated : ElaboratedSourceV1)
    (canonicalBytes : ByteArray)
    (expectedArtifactSha256 : String) :
    Except String (CertifiedSolanaProductionPreparationV1
      elaborated canonicalBytes expectedArtifactSha256) := do
  let source ← certifyProductionStageV1 id <|
    bindElaboratedSourceToCanonicalBytesV1 elaborated canonicalBytes
  let compiled ← certifyProductionStageV1 (·.render) <|
    compileValidatedSourceV1 source.value.validated
  let semanticData ← certifyProductionStageV1
    (fun error => s!"semantic validation failed: {repr error}") <|
    validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled.value)
  let referenceAdmission ← certifyProductionStageV1
    (fun error => s!"Reference admission failed: {repr error}") <|
    admitReferenceProgramSliceV1
      (CompiledSemanticV1.semanticV1Of compiled.value)
  let selection ← certifyProductionStageV1 (·.render) <|
    resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1)
  let capability ← certifyProductionStageV1 (·.render) <|
    resolveEngineeringRequirementsV1 selection.value compiled.value
  let plan ← certifyProductionStageV1 (·.render) <|
    materializeFullBodyPlanForProductV1 capability.value false
  let ir ← certifyProductionStageV1 (·.render) <|
    fullBodyIrFromProductCapabilityV1 capability.value false
  let assembly ← certifyProductionStageV1 (·.render) <|
    emitSbpfAsmV1 ir.value
  let artifact ← certifyProductionStageV1 (·.render) <|
    resolveBoundSbpfArtifactV1 assembly.value expectedArtifactSha256
  pure {
    source
    compiled
    semanticData
    referenceAdmission
    selection
    capability
    plan
    ir
    assembly
    artifact := artifact.value
    artifactSuccess := artifact.success
  }

/-- Replay a complete preparation certificate through the real production
    resolver. The proof uses every retained stage equation, so a caller cannot
    bypass a missing, unsupported, or identity-mismatched stage. -/
theorem resolveCertifiedSolanaProductionPreparationV1_eq_ok
    (prepared : CertifiedSolanaProductionPreparationV1
      elaborated canonicalBytes expectedArtifactSha256) :
    resolveCertifiedSolanaProductionPreparationV1 elaborated canonicalBytes
      expectedArtifactSha256 = .ok prepared := by
  rcases prepared with ⟨source, compiled, semanticData, referenceAdmission,
    selection, capability, plan, ir, assembly, artifact, artifactSuccess⟩
  unfold resolveCertifiedSolanaProductionPreparationV1
  rw [certifyProductionStageV1_eq_ok id _ source]
  dsimp only [Bind.bind, Except.bind]
  rw [certifyProductionStageV1_eq_ok (·.render) _ compiled]
  dsimp only [Bind.bind, Except.bind]
  rw [certifyProductionStageV1_eq_ok
    (fun error => s!"semantic validation failed: {repr error}") _ semanticData]
  dsimp only [Bind.bind, Except.bind]
  rw [certifyProductionStageV1_eq_ok
    (fun error => s!"Reference admission failed: {repr error}") _
      referenceAdmission]
  dsimp only [Bind.bind, Except.bind]
  rw [certifyProductionStageV1_eq_ok (·.render) _ selection]
  dsimp only [Bind.bind, Except.bind]
  rw [certifyProductionStageV1_eq_ok (·.render) _ capability]
  dsimp only [Bind.bind, Except.bind]
  rw [certifyProductionStageV1_eq_ok (·.render) _ plan]
  dsimp only [Bind.bind, Except.bind]
  rw [certifyProductionStageV1_eq_ok (·.render) _ ir]
  dsimp only [Bind.bind, Except.bind]
  rw [certifyProductionStageV1_eq_ok (·.render) _ assembly]
  dsimp only [Bind.bind, Except.bind]
  rw [certifyProductionStageV1_eq_ok (·.render) _
    (⟨artifact, artifactSuccess⟩ : ProductionStageSuccessV1
      (resolveBoundSbpfArtifactV1 assembly.value expectedArtifactSha256))]
  rfl

end ProofForgeV2.Targets.Solana
