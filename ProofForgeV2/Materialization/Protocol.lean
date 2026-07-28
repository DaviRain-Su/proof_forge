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
  /-- Residual alpha characterization / describe-target list only.
      Product support authority is the engineering exact requirement resolver
      (`RequirementResolverV1` static index + `resolveEngineeringRequirementsV1`),
      not this field. S6 closed public residual routes that treated this list as
      acceptance authority (residual Common resolve / validateResolved /
      supportedRequirements membership checks). Formal SupportClaim still pending. -/
  supportedRequirements : Array ProgramRequirement
  -- No Inhabited: TargetId/CodegenProfileId have no default identity.
  deriving BEq, Repr

/-- S6 deleted dead public residual `ResolvedProgram` carrier.
    Product Plan/materialize inputs are only `ResolvedEngineeringBuildV1`
    via target `planFromCapability` / `buildFromCapability`. Formal
    ResolvedProgram/SupportClaim still pending as a future design object. -/

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

/-- Associated Plan/TargetIR type witnesses only.
    S6: capability-gated target entries own plan/lower/emit
    (`planFromCapability` / `buildFromCapability`). No public
    SemanticProgram→Plan, Plan→TargetIR, or TargetIR→OutputFile product
    chains. -/
class Materializer (kind : TargetKind) where
  Plan : Type
  TargetIR : Type

end ProofForgeV2
