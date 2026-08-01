import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2

inductive ArtifactEncoding where
  | evmYul
  | sbpfPlanText
  | sbpfAssembly
  | wasmText
  | noirSource
  | leoSource
  | psySource
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
  | userPartitionedState
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
  -- Requirement support is deliberately absent. The exact engineering resolver
  -- index is the sole current authority; formal SupportClaim remains pending.
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

/-- Associated Plan/TargetIR type witnesses only.
    S6: capability-gated target entries own plan/lower/emit
    (`planFromCapability` / `buildFromCapability`). No public
    SemanticProgram→Plan, Plan→TargetIR, or TargetIR→OutputFile product
    chains. S7a: public alpha `OutputSet` / `OutputManifest` deleted;
    aggregate files chain ends at private-ctor `MaterializedArtifactsV1`
    (capability-only mint). S7b: locked-tool finalization is
    `finalizeMaterializedArtifactsV1` → private-ctor `FinalizedArtifactsV1`
    (CLI publisher-only). Formal OutputSetV1 still pending. -/
class Materializer (kind : TargetKind) where
  Plan : Type
  TargetIR : Type

end ProofForgeV2
