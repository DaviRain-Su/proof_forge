import ProofForgeV2.Core.SemanticIR

namespace ProofForgeV2

inductive ArtifactEncoding where
  | evmYul
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
  codegenProfile : String
  supportedRequirements : Array ProgramRequirement
  deriving BEq, Inhabited, Repr

structure ResolvedProgram (target : TargetId) where
  source : SemanticProgram
  descriptor : TargetDescriptor
  targetMatches : descriptor.targetId = target

structure OutputFile where
  path : String
  mediaType : String
  contents : String
  deriving BEq, Inhabited, Repr

structure OutputManifest where
  schemaVersion : String := "proof-forge-output/v2alpha1"
  target : TargetId
  codegenProfile : String
  sourceHash : String
  semanticHash : String
  deployable : Bool
  files : Array String
  deriving BEq, Inhabited, Repr

structure OutputSet where
  manifest : OutputManifest
  files : Array OutputFile
  deriving BEq, Inhabited, Repr

class Materializer (target : TargetId) where
  Plan : Type
  TargetIR : Type
  makePlan : ResolvedProgram target → CompileResult Plan
  lower : Plan → CompileResult TargetIR
  emit : TargetIR → CompileResult (Array OutputFile)

end ProofForgeV2
