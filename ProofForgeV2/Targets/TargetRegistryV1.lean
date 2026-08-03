/-
  ProofForgeV2.Targets.TargetRegistryV1 — D3 engineering registry kernel (repair B)

  **Sole** opaque static membership authority for the closed twelve-target set
  (9 implemented + 3 design-only). Product selection (`BuildSelectionV1`)
  consumes this seed; there is no second static index.

  **Not** formal TASK-D3-02:
  * no formal registry root domain string / root digest field on the carrier
  * no full formal descriptor / codegenProfiles / acceptanceProfile wire
  * no SupportClaim / NetworkProfile / OutputSetV1
  * engineering semantics digests (if any) are inspection-only under
    engineering* domains and never enter product selection / capability /
    artifacts

  Future formal expansion must grow **this** module in place — do not add a
  parallel formal registry type or adapter layer.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Core.Unicode

namespace ProofForgeV2.Targets.TargetRegistryV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode

/-- Reserved future profiles must never register. -/
def reservedFutureProfiles : Array String :=
  #["noir-acir-proof-v1"]

-- ---------------------------------------------------------------------------
-- SPEC-REG-001 closed axis enums (wire via exact render only; no String parse)
-- ---------------------------------------------------------------------------

inductive ExecutionHostV1 where
  | evm | svm | nearWasm | cosmWasm | sorobanWasm | icpCanister
  | noirCircuit | openvmGuest | aleoVm | psyDpn | quintModel | tvm
  deriving BEq, DecidableEq, Repr

inductive CommitModelV1 where
  | transactionAtomic | instructionAtomic | receiptLocal | transactionSavepoints
  | awaitSegmented | relationExternal | guestExternal | proofFinalDual
  | recursiveNetwork
  deriving BEq, DecidableEq, Repr

inductive StateBindingV1 where
  | contractStorage | explicitAccounts | contractKeyValue | instanceKeyValue
  | ttlScopedStorage | canisterHeapStable | externalPublicPrePost
  | guestMemoryIo | recordsMappings | userPartitioned | cellHashmap
  deriving BEq, DecidableEq, Repr

inductive CallModelV1 where
  | synchronousMessage | synchronousCpi | promiseDag | cosmosSubmessageReply
  | synchronousAuthTree | asynchronousActor | noNativeCall | guestInternal
  | programProofFinal | recursiveProofPipeline
  deriving BEq, DecidableEq, Repr

inductive ProofModelV1 where
  | noProof | externalCircuit | zkvmExecution | applicationChainProof
  | recursiveAggregation
  deriving BEq, DecidableEq, Repr

inductive SettlementModelV1 where
  | evmChain | solanaChain | nearChain | cosmosChain | stellarChain
  | icpSubnet | externalVerifier | aleoChain | psyNetwork | noSettlement | tonChain
  deriving BEq, DecidableEq, Repr

namespace ExecutionHostV1
def toWire : ExecutionHostV1 → String
  | .evm => "evm"
  | .svm => "svm"
  | .nearWasm => "near-wasm"
  | .cosmWasm => "cosmwasm"
  | .sorobanWasm => "soroban-wasm"
  | .icpCanister => "icp-canister"
  | .noirCircuit => "noir-circuit"
  | .openvmGuest => "openvm-guest"
  | .aleoVm => "aleo-vm"
  | .psyDpn => "psy-dpn"
  | .quintModel => "quint-model"
  | .tvm => "tvm"
instance : ToString ExecutionHostV1 := ⟨toWire⟩
end ExecutionHostV1

namespace CommitModelV1
def toWire : CommitModelV1 → String
  | .transactionAtomic => "transaction-atomic"
  | .instructionAtomic => "instruction-atomic"
  | .receiptLocal => "receipt-local"
  | .transactionSavepoints => "transaction-savepoints"
  | .awaitSegmented => "await-segmented"
  | .relationExternal => "relation-external"
  | .guestExternal => "guest-external"
  | .proofFinalDual => "proof-final-dual"
  | .recursiveNetwork => "recursive-network"
instance : ToString CommitModelV1 := ⟨toWire⟩
end CommitModelV1

namespace StateBindingV1
def toWire : StateBindingV1 → String
  | .contractStorage => "contract-storage"
  | .explicitAccounts => "explicit-accounts"
  | .contractKeyValue => "contract-key-value"
  | .instanceKeyValue => "instance-key-value"
  | .ttlScopedStorage => "ttl-scoped-storage"
  | .canisterHeapStable => "canister-heap-stable"
  | .externalPublicPrePost => "external-public-pre-post"
  | .guestMemoryIo => "guest-memory-io"
  | .recordsMappings => "records-mappings"
  | .userPartitioned => "user-partitioned"
  | .cellHashmap => "cell-hashmap"
instance : ToString StateBindingV1 := ⟨toWire⟩
end StateBindingV1

namespace CallModelV1
def toWire : CallModelV1 → String
  | .synchronousMessage => "synchronous-message"
  | .synchronousCpi => "synchronous-cpi"
  | .promiseDag => "promise-dag"
  | .cosmosSubmessageReply => "cosmos-submessage-reply"
  | .synchronousAuthTree => "synchronous-auth-tree"
  | .asynchronousActor => "asynchronous-actor"
  | .noNativeCall => "no-native-call"
  | .guestInternal => "guest-internal"
  | .programProofFinal => "program-proof-final"
  | .recursiveProofPipeline => "recursive-proof-pipeline"
instance : ToString CallModelV1 := ⟨toWire⟩
end CallModelV1

namespace ProofModelV1
def toWire : ProofModelV1 → String
  | .noProof => "no-proof"
  | .externalCircuit => "external-circuit"
  | .zkvmExecution => "zkvm-execution"
  | .applicationChainProof => "application-chain-proof"
  | .recursiveAggregation => "recursive-aggregation"
instance : ToString ProofModelV1 := ⟨toWire⟩
end ProofModelV1

namespace SettlementModelV1
def toWire : SettlementModelV1 → String
  | .evmChain => "evm-chain"
  | .solanaChain => "solana-chain"
  | .nearChain => "near-chain"
  | .cosmosChain => "cosmos-chain"
  | .stellarChain => "stellar-chain"
  | .icpSubnet => "icp-subnet"
  | .externalVerifier => "external-verifier"
  | .aleoChain => "aleo-chain"
  | .psyNetwork => "psy-network"
  | .noSettlement => "no-settlement"
  | .tonChain => "ton-chain"
instance : ToString SettlementModelV1 := ⟨toWire⟩
end SettlementModelV1

/-- Engineering axes payload (closed enums). Not formal TargetSemanticsV1. -/
structure TargetSemanticsAxesV1 where
  targetId : TargetId
  executionHost : ExecutionHostV1
  commitModel : CommitModelV1
  stateBinding : StateBindingV1
  callModel : CallModelV1
  proofModel : ProofModelV1
  settlementModel : SettlementModelV1
  deriving BEq, Repr

/-- Domain for **inspection-only** engineering semantics digests.
    Never a formal registry root; never product-selection authority. -/
def engineeringSemanticsDigestDomainV1 : String :=
  "proof-forge.target-semantics.engineering.v1"

/-- Inspection-only PF-JCS of axes (engineering domain). Not product-bound. -/
def renderEngineeringSemanticsAxesJcsV1 (s : TargetSemanticsAxesV1) :
    Except String String :=
  renderPfJcs (.object #[
    ("callModel", .string s.callModel.toWire),
    ("commitModel", .string s.commitModel.toWire),
    ("executionHost", .string s.executionHost.toWire),
    ("proofModel", .string s.proofModel.toWire),
    ("settlementModel", .string s.settlementModel.toWire),
    ("stateBinding", .string s.stateBinding.toWire),
    ("targetId", .string s.targetId.toString)
  ])

/-- Inspection-only engineering semantics digest. **Not** product selection,
    capability, artifacts, or formal registry root digest. -/
def engineeringSemanticsDigestV1 (s : TargetSemanticsAxesV1) :
    Except String Digest := do
  let jcs ← renderEngineeringSemanticsAxesJcsV1 s
  domainSeparatedSha256 engineeringSemanticsDigestDomainV1 jcs.toUTF8

/-- One static registration row (engineering membership carrier). -/
structure TargetRegistrationDataV1 where
  targetId : TargetId
  kind : TargetKind
  implemented : Bool
  displayName : String
  acceptanceProfileId : String
  /-- Inspection/list label only — not a formal maturity snapshot field. -/
  maturityLabel : String
  semantics : TargetSemanticsAxesV1
  profiles : Array CodegenProfileId
  defaultProfile : Option CodegenProfileId
  deriving BEq, Repr

/-- Validated static registry. Private constructor — use `createTargetRegistryV1`.
    **No** root digest field (wire is not formal registry payload). -/
structure TargetRegistryV1 where
  private mk ::
  registrations : Array TargetRegistrationDataV1
  deriving Repr

namespace TargetRegistryV1

def registrationsOf (r : TargetRegistryV1) : Array TargetRegistrationDataV1 :=
  r.registrations

def toArray (r : TargetRegistryV1) : Array TargetRegistrationDataV1 :=
  r.registrations

end TargetRegistryV1

/-- Inspection projection (no materialize capability). -/
structure RegistryTargetInspectionV1 where
  targetId : TargetId
  kind : TargetKind
  implemented : Bool
  displayName : String
  acceptanceProfileId : String
  maturityLabel : String
  profiles : Array CodegenProfileId
  defaultProfile : Option CodegenProfileId
  /-- Inspection-only; never product-bound. -/
  engineeringSemanticsDigest : Digest
  deriving Repr

private def findDuplicateString (values : Array String) : Option String :=
  Id.run do
    let mut seen : Array String := #[]
    for v in values do
      if seen.contains v then
        return some v
      seen := seen.push v
    return none

private def isStrictlyAscendingAscii (values : Array String) : Bool :=
  Id.run do
    let mut i : Nat := 0
    while i + 1 < values.size do
      let a := values[i]!
      let b := values[i + 1]!
      unless a < b do
        return false
      i := i + 1
    return true

private def containsProfile (profiles : Array CodegenProfileId) (p : CodegenProfileId) : Bool :=
  profiles.any (· == p)

/-- Closed kind → exact product implemented flag (sole membership policy). -/
def expectedImplementedOfKindV1 : TargetKind → Bool
  | .evm | .solana | .near | .noir | .aleo | .psy | .quint | .cosmwasm | .ton => true
  | .soroban | .icp | .openvm => false

/-- Closed kind → exact list/describe maturity label. -/
def expectedMaturityLabelOfKindV1 : TargetKind → String
  | .evm => "runtime-validated-alpha"
  | .solana => "plan-only"
  | .near => "wasm-validated-alpha"
  | .noir => "source-only"
  | .aleo => "source-only"
  | .psy => "source-only"
  | .quint => "source-only"
  | .cosmwasm => "wasm-validated-alpha"
  | .ton => "source-only"
  | .soroban | .icp | .openvm => "research-only"

/-- Closed kind → exact acceptance profile id string. -/
def expectedAcceptanceProfileIdOfKindV1 : TargetKind → String
  | .evm => "phase1.evm-u64.v1"
  | .solana => "phase1.solana-u64.v1"
  | .near => "phase1.near-u64.v1"
  | .noir => "phase1.noir-u64-private-sum.v1"
  | .aleo => "phase1.aleo-u64.v1"
  | .cosmwasm => "phase1.cosmwasm-u64.v1"
  | .ton => "phase1.ton-u64.v1"
  | .soroban => "research.soroban.v1"
  | .icp => "research.icp.v1"
  | .openvm => "research.openvm.v1"
  | .psy => "phase1.psy-u64.v1"
  | .quint => "research.quint.v1"

/-- Closed kind → exact displayName. -/
def expectedDisplayNameOfKindV1 : TargetKind → String
  | .evm => "EVM"
  | .solana => "Solana"
  | .near => "NEAR"
  | .noir => "Noir"
  | .cosmwasm => "CosmWasm"
  | .soroban => "Soroban"
  | .icp => "ICP"
  | .openvm => "OpenVM"
  | .aleo => "Aleo"
  | .psy => "Psy"
  | .quint => "Quint"
  | .ton => "TON"

private def validateDisplayNameV1 (name : String) : CompileResult Unit := do
  let n := name.utf8ByteSize
  if n == 0 || n > 127 then
    throw <| .registryInvalid "displayName must be 1..127 UTF-8 bytes"
  match requireNfc name with
  | .ok () => pure ()
  | .error e => throw <| .registryInvalid s!"displayName: {e}"

private def validateAcceptanceProfileIdStr (id : String) : CompileResult Unit :=
  match validateProfileIdValue id with
  | .ok () => pure ()
  | .error e => throw <| .registryInvalid s!"acceptanceProfileId: {e}"

/-- Validate and construct a TargetRegistryV1.
    Canonical storage: TargetId ASCII ascending. Profiles must already be
    strictly ascending (fail closed — no silent reorder of profile lists). -/
def createTargetRegistryV1 (regs : Array TargetRegistrationDataV1) :
    CompileResult TargetRegistryV1 := do
  if regs.isEmpty then
    throw <| .registryInvalid "target registry must be non-empty"
  let targetIds := regs.map (·.targetId.toString)
  if let some dup := findDuplicateString targetIds then
    throw <| .registryDuplicate s!"duplicate target id '{dup}'"
  let mut allProfiles : Array String := #[]
  for reg in regs do
    match TargetId.parse? reg.targetId.toString with
    | none =>
        throw <| .registryInvalid
          s!"target id '{reg.targetId}' fails TargetId grammar"
    | some parsed =>
        unless parsed == reg.targetId do
          throw <| .registryInvalid
            s!"target id '{reg.targetId}' is not a canonical TargetId parse"
    unless reg.kind.toString == reg.targetId.toString do
      throw <| .registryInvalid
        s!"target id '{reg.targetId}' does not match kind '{reg.kind}'"
    unless reg.targetId == TargetId.ofKind reg.kind do
      throw <| .registryInvalid
        s!"target id '{reg.targetId}' does not match TargetId.ofKind for '{reg.kind}'"
    -- Closed policy: implemented / maturity / display / acceptance must match kind.
    unless reg.implemented == expectedImplementedOfKindV1 reg.kind do
      throw <| .registryInvalid
        s!"implemented flag for '{reg.targetId}' must match closed kind policy"
    unless reg.maturityLabel == expectedMaturityLabelOfKindV1 reg.kind do
      throw <| .registryInvalid
        s!"maturityLabel for '{reg.targetId}' must match closed kind policy"
    unless reg.displayName == expectedDisplayNameOfKindV1 reg.kind do
      throw <| .registryInvalid
        s!"displayName for '{reg.targetId}' must match closed kind policy"
    unless reg.acceptanceProfileId == expectedAcceptanceProfileIdOfKindV1 reg.kind do
      throw <| .registryInvalid
        s!"acceptanceProfileId for '{reg.targetId}' must match closed kind policy"
    validateDisplayNameV1 reg.displayName
    validateAcceptanceProfileIdStr reg.acceptanceProfileId
    unless reg.semantics.targetId == reg.targetId do
      throw <| .registryInvalid
        s!"semantics.targetId must equal registration target '{reg.targetId}'"
    let profileIds := reg.profiles.map (·.toString)
    if let some dup := findDuplicateString profileIds then
      throw <| .registryDuplicate
        s!"duplicate codegen profile '{dup}' within target '{reg.targetId}'"
    unless isStrictlyAscendingAscii profileIds do
      throw <| .registryInvalid
        s!"codegen profiles for target '{reg.targetId}' must be strictly ASCII-ascending"
    for p in reg.profiles do
      match CodegenProfileId.parse? p.toString with
      | none =>
          throw <| .registryInvalid
            s!"codegen profile '{p}' fails CodegenProfileId grammar"
      | some parsed =>
          unless parsed == p do
            throw <| .registryInvalid
              s!"codegen profile '{p}' is not a canonical CodegenProfileId parse"
      if reservedFutureProfiles.contains p.toString then
        throw <| .registryInvalid
          s!"reserved future profile '{p}' cannot be registered"
      if allProfiles.contains p.toString then
        throw <| .registryDuplicate
          s!"duplicate codegen profile '{p}' across targets"
      allProfiles := allProfiles.push p.toString
    if let some defP := reg.defaultProfile then
      match CodegenProfileId.parse? defP.toString with
      | none =>
          throw <| .registryInvalid
            s!"default profile '{defP}' fails CodegenProfileId grammar"
      | some parsed =>
          unless parsed == defP do
            throw <| .registryInvalid
              s!"default profile '{defP}' is not a canonical CodegenProfileId parse"
    match reg.implemented, reg.defaultProfile with
    | true, some defP =>
        if reg.profiles.isEmpty then
          throw <| .registryInvalid
            s!"implemented target '{reg.targetId}' must declare at least one profile"
        unless containsProfile reg.profiles defP do
          throw <| .registryInvalid
            s!"default profile '{defP}' is not a member of target '{reg.targetId}'"
    | true, none =>
        throw <| .registryInvalid
          s!"implemented target '{reg.targetId}' must declare an explicit default profile"
    | false, none =>
        unless reg.profiles.isEmpty do
          throw <| .registryInvalid
            s!"design-only target '{reg.targetId}' must have empty profiles"
    | false, some defP =>
        throw <| .registryInvalid
          s!"design-only target '{reg.targetId}' must not declare default '{defP}'"
  let sorted :=
    regs.qsort (fun a b => a.targetId.toString < b.targetId.toString)
  return TargetRegistryV1.mk sorted

def findRegistrationV1 (registry : TargetRegistryV1) (target : TargetId) :
    Option TargetRegistrationDataV1 :=
  registry.registrations.find? (·.targetId == target)

def implementedRegistrationsV1 (registry : TargetRegistryV1) :
    Array TargetRegistrationDataV1 :=
  registry.registrations.filter (·.implemented)

def designOnlyRegistrationsV1 (registry : TargetRegistryV1) :
    Array TargetRegistrationDataV1 :=
  registry.registrations.filter (fun r => !r.implemented)

def inspectTargetV1 (registry : TargetRegistryV1) (target : TargetId) :
    CompileResult RegistryTargetInspectionV1 := do
  let reg ← match findRegistrationV1 registry target with
    | some r => pure r
    | none => throw <| .unknownTarget target.toString
  let engDig ← match engineeringSemanticsDigestV1 reg.semantics with
    | .ok d => pure d
    | .error e => throw <| .registryInvalid e
  return {
    targetId := reg.targetId
    kind := reg.kind
    implemented := reg.implemented
    displayName := reg.displayName
    acceptanceProfileId := reg.acceptanceProfileId
    maturityLabel := reg.maturityLabel
    profiles := reg.profiles
    defaultProfile := reg.defaultProfile
    engineeringSemanticsDigest := engDig
  }

def listTargetInspectionsV1 (registry : TargetRegistryV1) :
    CompileResult (Array RegistryTargetInspectionV1) :=
  registry.registrations.mapM fun reg =>
    inspectTargetV1 registry reg.targetId

-- ---------------------------------------------------------------------------
-- Frozen seed: sole 12-target membership table
-- ---------------------------------------------------------------------------

private def axes
    (targetId : TargetId)
    (executionHost : ExecutionHostV1) (commitModel : CommitModelV1)
    (stateBinding : StateBindingV1) (callModel : CallModelV1)
    (proofModel : ProofModelV1) (settlementModel : SettlementModelV1) :
    TargetSemanticsAxesV1 :=
  { targetId, executionHost, commitModel, stateBinding, callModel, proofModel,
    settlementModel }

/-- Sole closed TargetKind → engineering semantics-axis mapping.
    Registry rows and implemented TargetDescriptors both project from this
    function; no target-local or Protocol-owned second axis seed is allowed. -/
def semanticsAxesOfKindV1 : TargetKind → TargetSemanticsAxesV1
  | .evm =>
      axes TargetId.evm .evm .transactionAtomic .contractStorage
        .synchronousMessage .noProof .evmChain
  | .solana =>
      axes TargetId.solana .svm .instructionAtomic .explicitAccounts
        .synchronousCpi .noProof .solanaChain
  | .near =>
      axes TargetId.near .nearWasm .receiptLocal .contractKeyValue
        .promiseDag .noProof .nearChain
  | .noir =>
      axes TargetId.noir .noirCircuit .relationExternal .externalPublicPrePost
        .noNativeCall .externalCircuit .externalVerifier
  | .cosmwasm =>
      axes TargetId.cosmwasm .cosmWasm .transactionSavepoints .contractKeyValue
        .cosmosSubmessageReply .noProof .cosmosChain
  | .soroban =>
      axes TargetId.soroban .sorobanWasm .transactionAtomic .ttlScopedStorage
        .synchronousAuthTree .noProof .stellarChain
  | .icp =>
      axes TargetId.icp .icpCanister .awaitSegmented .canisterHeapStable
        .asynchronousActor .noProof .icpSubnet
  | .openvm =>
      axes TargetId.openvm .openvmGuest .guestExternal .guestMemoryIo
        .guestInternal .zkvmExecution .externalVerifier
  | .aleo =>
      axes TargetId.aleo .aleoVm .proofFinalDual .recordsMappings
        .programProofFinal .applicationChainProof .aleoChain
  | .psy =>
      axes TargetId.psy .psyDpn .recursiveNetwork .userPartitioned
        .recursiveProofPipeline .recursiveAggregation .psyNetwork
  | .quint =>
      axes TargetId.quint .quintModel .relationExternal .externalPublicPrePost
        .noNativeCall .noProof .noSettlement
  | .ton =>
      axes TargetId.ton .tvm .transactionAtomic .cellHashmap
        .asynchronousActor .noProof .tonChain

private def row
    (kind : TargetKind)
    (semantics : TargetSemanticsAxesV1)
    (profiles : Array CodegenProfileId)
    (defaultProfile : Option CodegenProfileId) : TargetRegistrationDataV1 :=
  {
    targetId := TargetId.ofKind kind
    kind
    implemented := expectedImplementedOfKindV1 kind
    displayName := expectedDisplayNameOfKindV1 kind
    acceptanceProfileId := expectedAcceptanceProfileIdOfKindV1 kind
    maturityLabel := expectedMaturityLabelOfKindV1 kind
    semantics
    profiles
    defaultProfile
  }

/-- Shipped initial registration rows (any order; create canonicalizes TargetId). -/
def initialRegistrationRowsV1 : Array TargetRegistrationDataV1 :=
  #[
    row .evm (semanticsAxesOfKindV1 .evm)
      -- Strictly ASCII-ascending: cancun-v1 < v1. Default stays legacy v1.
      #[CodegenProfileId.evmYulSolc0834CancunV1, CodegenProfileId.evmYulSolc0834V1]
      (some CodegenProfileId.evmYulSolc0834V1),
    row .solana (semanticsAxesOfKindV1 .solana)
      -- Strictly ASCII-ascending: elf-v1 < plan-v1. Default stays plan-v1.
      #[CodegenProfileId.solanaSbpfElfV1, CodegenProfileId.solanaSbpfPlanV1]
      -- Default plan: Map Token exceeds SBPF 4KiB frame budget under pure-expr
      -- dense lowering (ELF needs frame-friendly Map follow-on). ELF remains
      -- selectable via `--profile solana-sbpf-elf-v1` for non-Map programs.
      (some CodegenProfileId.solanaSbpfPlanV1),
    row .near (semanticsAxesOfKindV1 .near)
      #[CodegenProfileId.nearWasmRawU64V1]
      (some CodegenProfileId.nearWasmRawU64V1),
    row .noir (semanticsAxesOfKindV1 .noir)
      #[CodegenProfileId.noirSourceU64RelationsV1]
      (some CodegenProfileId.noirSourceU64RelationsV1),
    row .cosmwasm (semanticsAxesOfKindV1 .cosmwasm)
      #[CodegenProfileId.cosmwasmWasmU64V1]
      (some CodegenProfileId.cosmwasmWasmU64V1),
    row .soroban (semanticsAxesOfKindV1 .soroban) #[] none,
    row .icp (semanticsAxesOfKindV1 .icp) #[] none,
    row .openvm (semanticsAxesOfKindV1 .openvm) #[] none,
    row .aleo (semanticsAxesOfKindV1 .aleo)
      #[CodegenProfileId.aleoLeoU64V1]
      (some CodegenProfileId.aleoLeoU64V1),
    row .psy (semanticsAxesOfKindV1 .psy)
      #[CodegenProfileId.psyDargoU64V1]
      (some CodegenProfileId.psyDargoU64V1),
    row .quint (semanticsAxesOfKindV1 .quint)
      #[CodegenProfileId.quintSourceU64ModelV1]
      (some CodegenProfileId.quintSourceU64ModelV1),
    row .ton (semanticsAxesOfKindV1 .ton)
      #[CodegenProfileId.tonTolkBocV1]
      (some CodegenProfileId.tonTolkBocV1)
  ]

/-- Frozen product registry seed. Sole membership authority.
    Failure surfaces `PF-REGISTRY-INVALID` — never panic / empty success. -/
def initialTargetRegistryV1Result : CompileResult TargetRegistryV1 :=
  createTargetRegistryV1 initialRegistrationRowsV1

end ProofForgeV2.Targets.TargetRegistryV1
