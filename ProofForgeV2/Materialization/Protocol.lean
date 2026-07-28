import ProofForgeV2.Core.SemanticIR
import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2

inductive ArtifactEncoding where
  | evmYul
  | sbpfPlanText
  | sbpfAssembly
  | wasmText
  | noirSource
  | researchOnly
  deriving BEq, Inhabited, Repr

inductive ExecutionHost where
  | evm
  | solanaRuntime
  | nearRuntime
  | cosmwasmRuntime
  | sorobanHost
  | icpActor
  | circuit
  | zkvm
  | zkApplicationChain
  deriving BEq, Inhabited, Repr

inductive CommitModel where
  | transactionAtomic
  | instructionAtomic
  | receiptLocal
  | messageLocal
  | externalStateTransition
  deriving BEq, Inhabited, Repr

inductive StateBinding where
  | contractStorage
  | explicitAccounts
  | hostKeyValue
  | actorMemory
  | proofInputs
  | recordsAndMappings
  deriving BEq, Inhabited, Repr

inductive CallModel where
  | synchronous
  | cpi
  | asynchronousReceipt
  | actorMessage
  | none
  deriving BEq, Inhabited, Repr

inductive ProofModel where
  | none
  | circuitProof
  | vmProof
  | applicationProof
  deriving BEq, Inhabited, Repr

inductive SettlementModel where
  | ethereum
  | solana
  | near
  | cosmos
  | stellar
  | internetComputer
  | externalVerifier
  | aleo
  | psy
  deriving BEq, Inhabited, Repr

structure TargetDescriptor where
  targetId : TargetId
  artifactEncoding : ArtifactEncoding
  executionHost : ExecutionHost
  commitModel : CommitModel
  stateBinding : StateBinding
  callModel : CallModel
  proofModel : ProofModel
  settlementModel : SettlementModel
  codegenProfile : CodegenProfileId
  /-- Residual alpha backend defense / characterization list. Product support
      authority is the engineering exact requirement resolver
      (`RequirementResolverV1` static index + `resolveEngineeringRequirementsV1`),
      not this field. Public residual target routes that read this list still
      exist (next deletion gate: S6); formal SupportClaim still pending. -/
  supportedRequirements : Array ProgramRequirement
  -- No Inhabited: TargetId/CodegenProfileId have no default identity.
  deriving BEq, Repr

/-- Target-owned resolved program indexed by internal TargetKind. -/
structure ResolvedProgram (kind : TargetKind) where
  source : SemanticProgram
  descriptor : TargetDescriptor

structure OutputFile where
  path : String
  mediaType : String
  contents : String
  deriving BEq, Inhabited, Repr

structure OutputManifest where
  schemaVersion : String := "proof-forge-output/v2alpha1"
  target : TargetId
  codegenProfile : CodegenProfileId
  sourceHash : String
  semanticHash : String
  deployable : Bool
  files : Array String
  -- No Inhabited: carries opaque TargetId/CodegenProfileId.
  deriving BEq, Repr

structure OutputSet where
  manifest : OutputManifest
  files : Array OutputFile
  -- No Inhabited: via OutputManifest identity fields.
  deriving BEq, Repr

class Materializer (kind : TargetKind) where
  Plan : Type
  TargetIR : Type
  makePlan : ResolvedProgram kind → CompileResult Plan
  lower : Plan → CompileResult TargetIR
  emit : TargetIR → CompileResult (Array OutputFile)

end ProofForgeV2
