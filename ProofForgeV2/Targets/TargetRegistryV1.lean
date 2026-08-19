/-
  ProofForgeV2.Targets.TargetRegistryV1 — D3 engineering registry kernel (repair B)

  **Sole** opaque static membership authority for the closed thirteen-target set
  (13 implemented + 0 design-only). Product selection (`BuildSelectionV1`)
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
  | noirCircuit | openvmGuest | aleoVm | psyDpn | quintModel | tvm | xrplWasm
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
  | xrplChain
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
  | .xrplWasm => "xrpl-wasm"
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
  | .xrplChain => "xrpl-chain"
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

private def containsString : List String → String → Bool
  | [], _ => false
  | value :: rest, wanted => value == wanted || containsString rest wanted

private def findDuplicateStringLoop : List String → List String → Option String
  | [], _ => none
  | value :: rest, seen =>
      if containsString seen value then
        some value
      else
        findDuplicateStringLoop rest (value :: seen)

private def findDuplicateString (values : Array String) : Option String :=
  findDuplicateStringLoop values.toList []

private def isStrictlyAscendingAsciiList : List String → Bool
  | [] | [_] => true
  | left :: right :: rest =>
      left < right && isStrictlyAscendingAsciiList (right :: rest)

private def isStrictlyAscendingAscii (values : Array String) : Bool :=
  isStrictlyAscendingAsciiList values.toList

private def containsProfileList : List CodegenProfileId → CodegenProfileId → Bool
  | [], _ => false
  | profile :: rest, wanted => profile == wanted || containsProfileList rest wanted

private def containsProfile (profiles : Array CodegenProfileId) (p : CodegenProfileId) : Bool :=
  containsProfileList profiles.toList p

/-- Closed kind → exact product implemented flag (sole membership policy). -/
def expectedImplementedOfKindV1 : TargetKind → Bool
  | .evm | .solana | .near | .noir | .aleo | .psy | .quint | .cosmwasm | .ton
  | .soroban | .icp | .openvm | .xrpl => true

/-- Closed kind → exact list/describe maturity label. -/
def expectedMaturityLabelOfKindV1 : TargetKind → String
  | .evm => "runtime-validated-alpha"
  | .solana => "runtime-validated-alpha"
  | .near => "wasm-validated-alpha"
  | .noir => "source-only"
  | .aleo => "instructions-only"
  | .psy => "dpn-only"
  | .quint => "source-only"
  | .cosmwasm => "wasm-validated-alpha"
  | .ton => "source-only"
  | .soroban => "source-only"
  | .icp => "source-only"
  | .openvm => "source-only"
  | .xrpl => "source-only"

/-- Closed kind → exact acceptance profile id string. -/
def expectedAcceptanceProfileIdOfKindV1 : TargetKind → String
  | .evm => "phase1.evm-u64.v1"
  | .solana => "phase1.solana-u64.v1"
  | .near => "phase1.near-u64.v1"
  | .noir => "phase1.noir-u64-private-sum.v1"
  | .aleo => "phase1.aleo-u64.v1"
  | .cosmwasm => "phase1.cosmwasm-u64.v1"
  | .ton => "phase1.ton-u64.v1"
  | .soroban => "phase1.soroban-u64.v1"
  | .icp => "phase1.icp-u64.v1"
  | .openvm => "research.openvm.v1"
  | .psy => "phase1.psy-u64.v1"
  | .quint => "research.quint.v1"
  | .xrpl => "research.xrpl.v1"

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
  | .xrpl => "XRPL"

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

/-- Validate the closed target identity joins for one registration. This is the
    first phase of the sole production registration validator. -/
def validateRegistrationIdentityV1
    (reg : TargetRegistrationDataV1) : CompileResult Unit := do
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

/-- Validate the exact kind-indexed policy fields for one registration. -/
def validateRegistrationClosedPolicyV1
    (reg : TargetRegistrationDataV1) : CompileResult Unit := do
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

/-- Validate display and acceptance metadata using the existing production
    Unicode/profile-id validators. -/
def validateRegistrationMetadataV1
    (reg : TargetRegistrationDataV1) : CompileResult Unit := do
  validateDisplayNameV1 reg.displayName
  validateAcceptanceProfileIdStr reg.acceptanceProfileId

/-- Validate the registration-to-semantics target join. -/
def validateRegistrationSemanticsV1
    (reg : TargetRegistrationDataV1) : CompileResult Unit := do
  unless reg.semantics.targetId == reg.targetId do
    throw <| .registryInvalid
      s!"semantics.targetId must equal registration target '{reg.targetId}'"

/-- Validate within-registration profile uniqueness before global profile
    membership is accumulated. -/
def validateRegistrationProfileUniquenessV1
    (reg : TargetRegistrationDataV1) : CompileResult Unit := do
  let profileIds := reg.profiles.map (·.toString)
  if let some dup := findDuplicateString profileIds then
    throw <| .registryDuplicate
      s!"duplicate codegen profile '{dup}' within target '{reg.targetId}'"

/-- Validate canonical ASCII ordering of one registration's profile list. -/
def validateRegistrationProfileOrderV1
    (reg : TargetRegistrationDataV1) : CompileResult Unit := do
  let profileIds := reg.profiles.map (·.toString)
  unless isStrictlyAscendingAscii profileIds do
    throw <| .registryInvalid
      s!"codegen profiles for target '{reg.targetId}' must be strictly ASCII-ascending"

/-- Validate the complete within-registration profile-list shape. -/
def validateRegistrationProfileShapeV1
    (reg : TargetRegistrationDataV1) : CompileResult Unit := do
  validateRegistrationProfileUniquenessV1 reg
  validateRegistrationProfileOrderV1 reg

/-- Compose the two ordered profile-list shape checks. -/
theorem validateRegistrationProfileShapeV1_eq_ok_of_stages
    (reg : TargetRegistrationDataV1)
    (hunique : validateRegistrationProfileUniquenessV1 reg = .ok ())
    (horder : validateRegistrationProfileOrderV1 reg = .ok ()) :
    validateRegistrationProfileShapeV1 reg = .ok () := by
  simp only [validateRegistrationProfileShapeV1, hunique, horder, Bind.bind,
    Except.bind]

/-- A singleton profile list is unique and canonically ordered by construction. -/
theorem validateRegistrationProfileShapeV1_eq_ok_of_singleton
    (reg : TargetRegistrationDataV1)
    (profile : CodegenProfileId)
    (hprofiles : reg.profiles = #[profile]) :
    validateRegistrationProfileShapeV1 reg = .ok () := by
  simp [validateRegistrationProfileShapeV1,
    validateRegistrationProfileUniquenessV1, validateRegistrationProfileOrderV1,
    hprofiles, findDuplicateString, findDuplicateStringLoop, containsString,
    isStrictlyAscendingAscii, isStrictlyAscendingAsciiList, Bind.bind,
    Except.bind, Pure.pure, Except.pure]

/-- Validate one profile in the source order used by the production registry
    constructor and retain the global profile-name accumulator. -/
def validateRegistrationProfileV1
    (allProfiles : List String)
    (p : CodegenProfileId) : CompileResult (List String) := do
  match CodegenProfileId.parse? p.toString with
  | none =>
      throw <| .registryInvalid
        s!"codegen profile '{p}' fails CodegenProfileId grammar"
  | some parsed =>
      unless parsed == p do
        throw <| .registryInvalid
          s!"codegen profile '{p}' is not a canonical CodegenProfileId parse"
  if containsString reservedFutureProfiles.toList p.toString then
    throw <| .registryInvalid
      s!"reserved future profile '{p}' cannot be registered"
  if containsString allProfiles p.toString then
    throw <| .registryDuplicate
      s!"duplicate codegen profile '{p}' across targets"
  pure (p.toString :: allProfiles)

/-- Total structural driver for the production per-profile validation loop. -/
def validateRegistrationProfilesV1 :
    List CodegenProfileId → List String → CompileResult (List String)
  | [], allProfiles => .ok allProfiles
  | p :: rest, allProfiles => do
      let next ← validateRegistrationProfileV1 allProfiles p
      validateRegistrationProfilesV1 rest next

/-- Validate default-profile canonicality and implemented/design-only policy
    after all profile rows have entered the global accumulator. -/
def validateRegistrationDefaultV1
    (reg : TargetRegistrationDataV1) : CompileResult Unit := do
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

/-- Validate one registration in exactly the phase order used by the production
    registry constructor. The returned accumulator is consumed by the next
    source-order registration. -/
def validateRegistrationV1
    (allProfiles : List String)
    (reg : TargetRegistrationDataV1) : CompileResult (List String) := do
  validateRegistrationIdentityV1 reg
  validateRegistrationClosedPolicyV1 reg
  validateRegistrationMetadataV1 reg
  validateRegistrationSemanticsV1 reg
  validateRegistrationProfileShapeV1 reg
  let allProfiles ←
    validateRegistrationProfilesV1 reg.profiles.toList allProfiles
  validateRegistrationDefaultV1 reg
  pure allProfiles

/-- Replay all phases of the sole production registration validator. -/
theorem validateRegistrationV1_eq_ok_of_stages
    (allProfiles nextProfiles : List String)
    (reg : TargetRegistrationDataV1)
    (hidentity : validateRegistrationIdentityV1 reg = .ok ())
    (hpolicy : validateRegistrationClosedPolicyV1 reg = .ok ())
    (hmetadata : validateRegistrationMetadataV1 reg = .ok ())
    (hsemantics : validateRegistrationSemanticsV1 reg = .ok ())
    (hshape : validateRegistrationProfileShapeV1 reg = .ok ())
    (hprofiles : validateRegistrationProfilesV1 reg.profiles.toList allProfiles =
      .ok nextProfiles)
    (hdefault : validateRegistrationDefaultV1 reg = .ok ()) :
    validateRegistrationV1 allProfiles reg = .ok nextProfiles := by
  simp only [validateRegistrationV1, hidentity, hpolicy, hmetadata, hsemantics,
    hshape, hprofiles, hdefault, Bind.bind, Pure.pure, Except.bind, Except.pure]

/-- Total structural driver for the production registration validation loop. -/
def validateRegistrationsV1 :
    List TargetRegistrationDataV1 → List String → CompileResult (List String)
  | [], allProfiles => .ok allProfiles
  | reg :: rest, allProfiles => do
      let next ← validateRegistrationV1 allProfiles reg
      validateRegistrationsV1 rest next

/-- Production root checks that precede per-registration validation. -/
def validateRegistrationSetV1
    (regs : Array TargetRegistrationDataV1) : CompileResult Unit := do
  if regs.isEmpty then
    throw <| .registryInvalid "target registry must be non-empty"
  let targetIds := regs.map (·.targetId.toString)
  if let some dup := findDuplicateString targetIds then
    throw <| .registryDuplicate s!"duplicate target id '{dup}'"

@[reducible] private def asciiStringLtListV1 : List Char → List Char → Bool
  | [], [] => false
  | [], _ :: _ => true
  | _ :: _, [] => false
  | a :: as, b :: bs =>
      if a.val == b.val then asciiStringLtListV1 as bs
      else decide (a.val < b.val)

@[reducible] private def asciiStringLtV1 (a b : String) : Bool :=
  asciiStringLtListV1 a.toList b.toList

@[reducible] private def targetRegistrationLtV1
    (a b : TargetRegistrationDataV1) : Bool :=
  asciiStringLtV1 a.targetId.toString b.targetId.toString

@[reducible] private def insertRegistrationV1
    (reg : TargetRegistrationDataV1) :
    List TargetRegistrationDataV1 → List TargetRegistrationDataV1
  | [] => [reg]
  | current :: rest =>
      if targetRegistrationLtV1 reg current then
        reg :: current :: rest
      else
        current :: insertRegistrationV1 reg rest

@[reducible] private def sortRegistrationListV1 :
    List TargetRegistrationDataV1 → List TargetRegistrationDataV1
  | [] => []
  | reg :: rest => insertRegistrationV1 reg (sortRegistrationListV1 rest)

@[reducible] private def sortRegistrationsV1
    (regs : Array TargetRegistrationDataV1) : Array TargetRegistrationDataV1 :=
  (sortRegistrationListV1 regs.toList).toArray

/-- Validate and construct a TargetRegistryV1.
    Canonical storage: TargetId ASCII ascending. Profiles must already be
    strictly ascending (fail closed — no silent reorder of profile lists). -/
def createTargetRegistryV1 (regs : Array TargetRegistrationDataV1) :
    CompileResult TargetRegistryV1 := do
  validateRegistrationSetV1 regs
  let _ ← validateRegistrationsV1 regs.toList []
  let sorted := sortRegistrationsV1 regs
  return TargetRegistryV1.mk sorted

/-- Compose the existing production registry phases into the private registry
    mint. This theorem does not replace registration validation or sorting. -/
theorem createTargetRegistryV1_eq_ok_of_stages
    (regs : Array TargetRegistrationDataV1)
    (allProfiles : List String)
    (hset : validateRegistrationSetV1 regs = .ok ())
    (hregistrations : validateRegistrationsV1 regs.toList [] =
      .ok allProfiles) :
    createTargetRegistryV1 regs =
      .ok (TargetRegistryV1.mk (sortRegistrationsV1 regs)) := by
  simp only [createTargetRegistryV1, hset, hregistrations, Bind.bind, Pure.pure,
    Except.bind, Except.pure]

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
-- Frozen seed: sole 13-target membership table
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
  | .xrpl =>
      axes TargetId.xrpl .xrplWasm .transactionAtomic .contractKeyValue
        .synchronousMessage .noProof .xrplChain

@[reducible] def registrationRowV1
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

@[reducible] def evmRegistrationRowV1 : TargetRegistrationDataV1 :=
  registrationRowV1 .evm (semanticsAxesOfKindV1 .evm)
    -- Strictly ASCII-ascending: cancun-v1 < v1. Default = v1 (hashed Map).
    #[CodegenProfileId.evmYulSolc0834CancunV1, CodegenProfileId.evmYulSolc0834V1]
    (some CodegenProfileId.evmYulSolc0834V1)

/-- Frozen Solana product row. This is registration data, not a selection or
    materialization capability; the registry constructor remains the sole mint. -/
@[reducible] def solanaRegistrationRowV1 : TargetRegistrationDataV1 :=
  registrationRowV1 .solana (semanticsAxesOfKindV1 .solana)
    -- ADR-0032 U1: sole product rail only. plan-v1 / elf-v1 shims removed
    -- (no longer registry members; resolve/build reject them).
    #[CodegenProfileId.solanaSbpfCpiElfV1]
    (some CodegenProfileId.solanaSbpfCpiElfV1)

@[simp] theorem solanaRegistrationRowV1_implemented :
    solanaRegistrationRowV1.implemented = true := by
  rfl

@[simp] theorem solanaRegistrationRowV1_kind :
    solanaRegistrationRowV1.kind = .solana := by
  rfl

@[simp] theorem solanaRegistrationRowV1_profiles :
    solanaRegistrationRowV1.profiles =
      #[CodegenProfileId.solanaSbpfCpiElfV1] := by
  rfl

@[reducible] def nearRegistrationRowV1 : TargetRegistrationDataV1 :=
  registrationRowV1 .near (semanticsAxesOfKindV1 .near)
    #[CodegenProfileId.nearWasmRawU64V1]
    (some CodegenProfileId.nearWasmRawU64V1)

-- Noir dual profiles (ASCII ascending: nargo-acir < source-relations);
-- default remains zero-tool source. Same Plan / `.nr` base surface; the
-- explicit nargo ACIR profile dual-writes path-normalized ProgramArtifact
-- extras during Finalize (NOIR-IR-6; deployable=false; no prove/VK).
@[reducible] def noirRegistrationRowV1 : TargetRegistrationDataV1 :=
  registrationRowV1 .noir (semanticsAxesOfKindV1 .noir)
    #[CodegenProfileId.noirNargoAcirV1, CodegenProfileId.noirSourceU64RelationsV1]
    (some CodegenProfileId.noirSourceU64RelationsV1)

@[reducible] def cosmwasmRegistrationRowV1 : TargetRegistrationDataV1 :=
  registrationRowV1 .cosmwasm (semanticsAxesOfKindV1 .cosmwasm)
    #[CodegenProfileId.cosmwasmWasmU64V1]
    (some CodegenProfileId.cosmwasmWasmU64V1)

@[reducible] def sorobanRegistrationRowV1 : TargetRegistrationDataV1 :=
  registrationRowV1 .soroban (semanticsAxesOfKindV1 .soroban)
    #[CodegenProfileId.sorobanSourceU64V1]
    (some CodegenProfileId.sorobanSourceU64V1)

@[reducible] def icpRegistrationRowV1 : TargetRegistrationDataV1 :=
  registrationRowV1 .icp (semanticsAxesOfKindV1 .icp)
    #[CodegenProfileId.icpWasmCandidU64V1]
    (some CodegenProfileId.icpWasmCandidU64V1)

-- Explicit elf profile shares the Plan/guest emission; Finalize resolves
-- locked cargo-openvm 2.0.1 to build+transpile ELF/VmExe extras
-- (ADR-0046 O1; deployable=false; no keygen/execute/prove/verify).
@[reducible] def openvmRegistrationRowV1 : TargetRegistrationDataV1 :=
  registrationRowV1 .openvm (semanticsAxesOfKindV1 .openvm)
    #[CodegenProfileId.openvmGuestElfV1, CodegenProfileId.openvmGuestSourceV1]
    (some CodegenProfileId.openvmGuestSourceV1)

@[reducible] def aleoRegistrationRowV1 : TargetRegistrationDataV1 :=
  registrationRowV1 .aleo (semanticsAxesOfKindV1 .aleo)
    #[CodegenProfileId.aleoInstructionsV1]
    (some CodegenProfileId.aleoInstructionsV1)

@[reducible] def psyRegistrationRowV1 : TargetRegistrationDataV1 :=
  registrationRowV1 .psy (semanticsAxesOfKindV1 .psy)
    #[CodegenProfileId.psyDpnV1]
    (some CodegenProfileId.psyDpnV1)

@[reducible] def quintRegistrationRowV1 : TargetRegistrationDataV1 :=
  registrationRowV1 .quint (semanticsAxesOfKindV1 .quint)
    #[CodegenProfileId.quintSourceU64ModelV1]
    (some CodegenProfileId.quintSourceU64ModelV1)

@[reducible] def tonRegistrationRowV1 : TargetRegistrationDataV1 :=
  registrationRowV1 .ton (semanticsAxesOfKindV1 .ton)
    #[CodegenProfileId.tonTolkBocV1]
    (some CodegenProfileId.tonTolkBocV1)

-- XRPL dual profiles (ASCII ascending: source-u64 < wasm-u64);
-- default remains zero-tool source. Same Plan / `.rs` base surface; the
-- explicit WASM profile builds a `wasm32-unknown-unknown` extra during
-- Finalize (ADR-0050 Q1; deployable=false; no AlphaNet/mainnet).
@[reducible] def xrplRegistrationRowV1 : TargetRegistrationDataV1 :=
  registrationRowV1 .xrpl (semanticsAxesOfKindV1 .xrpl)
    #[CodegenProfileId.xrplBedrockSourceU64V1,
      CodegenProfileId.xrplBedrockWasmU64V1]
    (some CodegenProfileId.xrplBedrockSourceU64V1)

/-- Shipped initial registration rows (any order; create canonicalizes TargetId). -/
@[reducible] def initialRegistrationRowsV1 : Array TargetRegistrationDataV1 :=
  #[evmRegistrationRowV1, solanaRegistrationRowV1, nearRegistrationRowV1,
    noirRegistrationRowV1, cosmwasmRegistrationRowV1, sorobanRegistrationRowV1,
    icpRegistrationRowV1, openvmRegistrationRowV1, aleoRegistrationRowV1,
    psyRegistrationRowV1, quintRegistrationRowV1, tonRegistrationRowV1,
    xrplRegistrationRowV1]

/-- Frozen registrations in the canonical TargetId order produced by the sole
    registry constructor. These are source rows, not selections/capabilities. -/
@[reducible] def initialCanonicalRegistrationRowsV1 :
    Array TargetRegistrationDataV1 :=
  #[aleoRegistrationRowV1, cosmwasmRegistrationRowV1, evmRegistrationRowV1,
    icpRegistrationRowV1, nearRegistrationRowV1, noirRegistrationRowV1,
    openvmRegistrationRowV1, psyRegistrationRowV1, quintRegistrationRowV1,
    solanaRegistrationRowV1, sorobanRegistrationRowV1, tonRegistrationRowV1,
    xrplRegistrationRowV1]

/-- Frozen product registry seed. Sole membership authority.
    Failure surfaces `PF-REGISTRY-INVALID` — never panic / empty success. -/
def initialTargetRegistryV1Result : CompileResult TargetRegistryV1 :=
  createTargetRegistryV1 initialRegistrationRowsV1

/-- The frozen registration set passes the production root checks. -/
theorem initialRegistrationSetV1_eq_ok :
    validateRegistrationSetV1 initialRegistrationRowsV1 = .ok () := by
  simp [validateRegistrationSetV1, initialRegistrationRowsV1, registrationRowV1,
    evmRegistrationRowV1, solanaRegistrationRowV1, nearRegistrationRowV1,
    noirRegistrationRowV1, cosmwasmRegistrationRowV1, sorobanRegistrationRowV1,
    icpRegistrationRowV1, openvmRegistrationRowV1, aleoRegistrationRowV1,
    psyRegistrationRowV1, quintRegistrationRowV1, tonRegistrationRowV1,
    xrplRegistrationRowV1, TargetId.ofKind, TargetId.toString, TargetId.evm,
    TargetId.solana, TargetId.near, TargetId.noir, TargetId.cosmwasm,
    TargetId.soroban, TargetId.icp, TargetId.openvm, TargetId.aleo, TargetId.psy,
    TargetId.quint, TargetId.ton, TargetId.xrpl, findDuplicateString,
    findDuplicateStringLoop, containsString, Bind.bind, Except.bind, Pure.pure,
    Except.pure]

/-- The frozen source-order registration rows pass the production validator. -/
theorem initialRegistrationsV1_eq_ok :
    ∃ allProfiles,
      validateRegistrationsV1 initialRegistrationRowsV1.toList [] =
        .ok allProfiles := by
  have hevm :
      "evm-yul-solc-0.8.34-cancun-v1" < "evm-yul-solc-0.8.34-v1" := by
    decide
  have hnoir :
      "noir-nargo-1.0.0-beta.26-acir-v1" < "noir-source-u64-relations-v1" := by
    decide
  have hopenvm :
      "openvm-guest-elf-v1" < "openvm-guest-source-v1" := by
    decide
  have hxrpl :
      "xrpl-bedrock-source-u64-v1" < "xrpl-bedrock-wasm-u64-v1" := by
    decide
  let pEvm : List String :=
    [CodegenProfileId.evmYulSolc0834V1.toString,
      CodegenProfileId.evmYulSolc0834CancunV1.toString]
  let pSolana := CodegenProfileId.solanaSbpfCpiElfV1.toString :: pEvm
  let pNear := CodegenProfileId.nearWasmRawU64V1.toString :: pSolana
  let pNoir := CodegenProfileId.noirSourceU64RelationsV1.toString ::
    CodegenProfileId.noirNargoAcirV1.toString :: pNear
  let pCosmwasm := CodegenProfileId.cosmwasmWasmU64V1.toString :: pNoir
  let pSoroban := CodegenProfileId.sorobanSourceU64V1.toString :: pCosmwasm
  let pIcp := CodegenProfileId.icpWasmCandidU64V1.toString :: pSoroban
  let pOpenvm := CodegenProfileId.openvmGuestSourceV1.toString ::
    CodegenProfileId.openvmGuestElfV1.toString :: pIcp
  let pAleo := CodegenProfileId.aleoInstructionsV1.toString :: pOpenvm
  let pPsy := CodegenProfileId.psyDpnV1.toString :: pAleo
  let pQuint := CodegenProfileId.quintSourceU64ModelV1.toString :: pPsy
  let pTon := CodegenProfileId.tonTolkBocV1.toString :: pQuint
  let pXrpl := CodegenProfileId.xrplBedrockWasmU64V1.toString ::
    CodegenProfileId.xrplBedrockSourceU64V1.toString :: pTon
  have hEvmShape :
      validateRegistrationProfileShapeV1 evmRegistrationRowV1 = .ok () := by
    simp [validateRegistrationProfileShapeV1,
      validateRegistrationProfileUniquenessV1, validateRegistrationProfileOrderV1,
      evmRegistrationRowV1, registrationRowV1, findDuplicateString, findDuplicateStringLoop,
      containsString, isStrictlyAscendingAscii, isStrictlyAscendingAsciiList,
      CodegenProfileId.toString, CodegenProfileId.evmYulSolc0834CancunV1,
      CodegenProfileId.evmYulSolc0834V1, hevm, Bind.bind, Except.bind,
      Pure.pure, Except.pure]
  have hNoirShape :
      validateRegistrationProfileShapeV1 noirRegistrationRowV1 = .ok () := by
    simp [validateRegistrationProfileShapeV1,
      validateRegistrationProfileUniquenessV1, validateRegistrationProfileOrderV1,
      noirRegistrationRowV1, registrationRowV1, findDuplicateString, findDuplicateStringLoop,
      containsString, isStrictlyAscendingAscii, isStrictlyAscendingAsciiList,
      CodegenProfileId.toString, CodegenProfileId.noirNargoAcirV1,
      CodegenProfileId.noirSourceU64RelationsV1, hnoir, Bind.bind, Except.bind,
      Pure.pure, Except.pure]
  have hOpenvmShape :
      validateRegistrationProfileShapeV1 openvmRegistrationRowV1 = .ok () := by
    simp [validateRegistrationProfileShapeV1,
      validateRegistrationProfileUniquenessV1, validateRegistrationProfileOrderV1,
      openvmRegistrationRowV1, registrationRowV1, findDuplicateString, findDuplicateStringLoop,
      containsString, isStrictlyAscendingAscii, isStrictlyAscendingAsciiList,
      CodegenProfileId.toString, CodegenProfileId.openvmGuestElfV1,
      CodegenProfileId.openvmGuestSourceV1, hopenvm, Bind.bind, Except.bind,
      Pure.pure, Except.pure]
  have hXrplShape :
      validateRegistrationProfileShapeV1 xrplRegistrationRowV1 = .ok () := by
    simp [validateRegistrationProfileShapeV1,
      validateRegistrationProfileUniquenessV1, validateRegistrationProfileOrderV1,
      xrplRegistrationRowV1, registrationRowV1, findDuplicateString, findDuplicateStringLoop,
      containsString, isStrictlyAscendingAscii, isStrictlyAscendingAsciiList,
      CodegenProfileId.toString, CodegenProfileId.xrplBedrockSourceU64V1,
      CodegenProfileId.xrplBedrockWasmU64V1, hxrpl, Bind.bind, Except.bind,
      Pure.pure, Except.pure]
  have hSolanaShape :
      validateRegistrationProfileShapeV1 solanaRegistrationRowV1 = .ok () := by
    apply validateRegistrationProfileShapeV1_eq_ok_of_singleton _
      CodegenProfileId.solanaSbpfCpiElfV1
    rfl
  have hNearShape :
      validateRegistrationProfileShapeV1 nearRegistrationRowV1 = .ok () := by
    apply validateRegistrationProfileShapeV1_eq_ok_of_singleton _
      CodegenProfileId.nearWasmRawU64V1
    rfl
  have hCosmwasmShape :
      validateRegistrationProfileShapeV1 cosmwasmRegistrationRowV1 = .ok () := by
    apply validateRegistrationProfileShapeV1_eq_ok_of_singleton _
      CodegenProfileId.cosmwasmWasmU64V1
    rfl
  have hSorobanShape :
      validateRegistrationProfileShapeV1 sorobanRegistrationRowV1 = .ok () := by
    apply validateRegistrationProfileShapeV1_eq_ok_of_singleton _
      CodegenProfileId.sorobanSourceU64V1
    rfl
  have hIcpShape :
      validateRegistrationProfileShapeV1 icpRegistrationRowV1 = .ok () := by
    apply validateRegistrationProfileShapeV1_eq_ok_of_singleton _
      CodegenProfileId.icpWasmCandidU64V1
    rfl
  have hAleoShape :
      validateRegistrationProfileShapeV1 aleoRegistrationRowV1 = .ok () := by
    apply validateRegistrationProfileShapeV1_eq_ok_of_singleton _
      CodegenProfileId.aleoInstructionsV1
    rfl
  have hPsyShape :
      validateRegistrationProfileShapeV1 psyRegistrationRowV1 = .ok () := by
    apply validateRegistrationProfileShapeV1_eq_ok_of_singleton _
      CodegenProfileId.psyDpnV1
    rfl
  have hQuintShape :
      validateRegistrationProfileShapeV1 quintRegistrationRowV1 = .ok () := by
    apply validateRegistrationProfileShapeV1_eq_ok_of_singleton _
      CodegenProfileId.quintSourceU64ModelV1
    rfl
  have hTonShape :
      validateRegistrationProfileShapeV1 tonRegistrationRowV1 = .ok () := by
    apply validateRegistrationProfileShapeV1_eq_ok_of_singleton _
      CodegenProfileId.tonTolkBocV1
    rfl
  have hEvm : validateRegistrationV1 [] evmRegistrationRowV1 = .ok pEvm := by
    apply validateRegistrationV1_eq_ok_of_stages
    all_goals first | exact hEvmShape | rfl
  have hSolana :
      validateRegistrationV1 pEvm solanaRegistrationRowV1 = .ok pSolana := by
    apply validateRegistrationV1_eq_ok_of_stages
    all_goals first | exact hSolanaShape | rfl
  have hNear : validateRegistrationV1 pSolana nearRegistrationRowV1 = .ok pNear := by
    apply validateRegistrationV1_eq_ok_of_stages
    all_goals first | exact hNearShape | rfl
  have hNoir : validateRegistrationV1 pNear noirRegistrationRowV1 = .ok pNoir := by
    apply validateRegistrationV1_eq_ok_of_stages
    all_goals first | exact hNoirShape | rfl
  have hCosmwasm :
      validateRegistrationV1 pNoir cosmwasmRegistrationRowV1 = .ok pCosmwasm := by
    apply validateRegistrationV1_eq_ok_of_stages
    all_goals first | exact hCosmwasmShape | rfl
  have hSoroban :
      validateRegistrationV1 pCosmwasm sorobanRegistrationRowV1 = .ok pSoroban := by
    apply validateRegistrationV1_eq_ok_of_stages
    all_goals first | exact hSorobanShape | rfl
  have hIcp : validateRegistrationV1 pSoroban icpRegistrationRowV1 = .ok pIcp := by
    apply validateRegistrationV1_eq_ok_of_stages
    all_goals first | exact hIcpShape | rfl
  have hOpenvm :
      validateRegistrationV1 pIcp openvmRegistrationRowV1 = .ok pOpenvm := by
    apply validateRegistrationV1_eq_ok_of_stages
    all_goals first | exact hOpenvmShape | rfl
  have hAleo : validateRegistrationV1 pOpenvm aleoRegistrationRowV1 = .ok pAleo := by
    apply validateRegistrationV1_eq_ok_of_stages
    all_goals first | exact hAleoShape | rfl
  have hPsy : validateRegistrationV1 pAleo psyRegistrationRowV1 = .ok pPsy := by
    apply validateRegistrationV1_eq_ok_of_stages
    all_goals first | exact hPsyShape | rfl
  have hQuint : validateRegistrationV1 pPsy quintRegistrationRowV1 = .ok pQuint := by
    apply validateRegistrationV1_eq_ok_of_stages
    all_goals first | exact hQuintShape | rfl
  have hTon : validateRegistrationV1 pQuint tonRegistrationRowV1 = .ok pTon := by
    apply validateRegistrationV1_eq_ok_of_stages
    all_goals first | exact hTonShape | rfl
  have hXrpl : validateRegistrationV1 pTon xrplRegistrationRowV1 = .ok pXrpl := by
    apply validateRegistrationV1_eq_ok_of_stages
    all_goals first | exact hXrplShape | rfl
  refine ⟨pXrpl, ?_⟩
  simp only [initialRegistrationRowsV1, validateRegistrationsV1, hEvm, hSolana,
    hNear, hNoir, hCosmwasm, hSoroban, hIcp, hOpenvm, hAleo, hPsy, hQuint,
    hTon, hXrpl, Bind.bind, Except.bind]

/-- The frozen production seed succeeds through the sole registry constructor.
    The resulting registration order is still minted by that constructor's
    canonical TargetId sort rather than duplicated in this certificate. -/
theorem initialTargetRegistryV1Result_eq_ok :
    initialTargetRegistryV1Result =
      .ok (TargetRegistryV1.mk (sortRegistrationsV1 initialRegistrationRowsV1)) := by
  rcases initialRegistrationsV1_eq_ok with ⟨allProfiles, hregistrations⟩
  exact createTargetRegistryV1_eq_ok_of_stages initialRegistrationRowsV1
    allProfiles initialRegistrationSetV1_eq_ok hregistrations

/-- Exact canonical order of the frozen source rows. -/
theorem sortInitialRegistrationRowsV1_eq_canonical :
    sortRegistrationsV1 initialRegistrationRowsV1 =
      initialCanonicalRegistrationRowsV1 := by
  rfl

/-- The frozen registry equation with its canonical rows exposed as source
    data, so downstream certificates need not replay the sort. -/
theorem initialTargetRegistryV1Result_eq_canonical :
    initialTargetRegistryV1Result =
      .ok (TargetRegistryV1.mk initialCanonicalRegistrationRowsV1) := by
  rw [initialTargetRegistryV1Result_eq_ok,
    sortInitialRegistrationRowsV1_eq_canonical]

/-- The frozen target registry succeeds through its sole validator/private
    constructor. The witness is exposed only propositionally. -/
theorem initialTargetRegistryV1Result_exists :
    ∃ registry, initialTargetRegistryV1Result = .ok registry := by
  exact ⟨TargetRegistryV1.mk initialCanonicalRegistrationRowsV1,
    initialTargetRegistryV1Result_eq_canonical⟩

/-- Solana lookup in the certified frozen registry. The proof computes the
    constructor-owned canonical sort; it does not introduce another index. -/
theorem findRegistrationV1_initial_solana_eq_some :
    findRegistrationV1
        (TargetRegistryV1.mk
          (sortRegistrationsV1 initialRegistrationRowsV1))
        TargetId.solana =
      some solanaRegistrationRowV1 := by
  simp [findRegistrationV1, initialRegistrationRowsV1, sortRegistrationsV1,
    sortRegistrationListV1, insertRegistrationV1, targetRegistrationLtV1,
    asciiStringLtV1, asciiStringLtListV1,
    evmRegistrationRowV1, solanaRegistrationRowV1, nearRegistrationRowV1,
    noirRegistrationRowV1, cosmwasmRegistrationRowV1, sorobanRegistrationRowV1,
    icpRegistrationRowV1, openvmRegistrationRowV1, aleoRegistrationRowV1,
    psyRegistrationRowV1, quintRegistrationRowV1, tonRegistrationRowV1,
    xrplRegistrationRowV1, registrationRowV1, TargetId.ofKind, TargetId.toString, TargetId.evm,
    TargetId.solana, TargetId.near, TargetId.noir, TargetId.cosmwasm,
    TargetId.soroban, TargetId.icp, TargetId.openvm, TargetId.aleo, TargetId.psy,
    TargetId.quint, TargetId.ton, TargetId.xrpl, TargetId.beq_eq_toString]

end ProofForgeV2.Targets.TargetRegistryV1
