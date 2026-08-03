import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Targets.TargetRegistryV1

namespace ProofForgeV2

open ProofForgeV2.Targets.TargetRegistryV1

inductive ArtifactEncoding where
  | evmYul
  | sbpfPlanText
  | sbpfAssembly
  | wasmText
  | noirSource
  | leoSource
  | psySource
  | quintSource
  | tolkSource
  | researchOnly
  deriving BEq, Inhabited, Repr

/-- TargetDescriptor deliberately reuses the registry-owned closed V1 axes.
    ArtifactEncoding remains profile/materializer metadata, not a semantics axis. -/
structure TargetDescriptor where
  targetId : TargetId
  artifactEncoding : ArtifactEncoding
  executionHost : ExecutionHostV1
  commitModel : CommitModelV1
  stateBinding : StateBindingV1
  callModel : CallModelV1
  proofModel : ProofModelV1
  settlementModel : SettlementModelV1
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
