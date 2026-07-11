/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Requirement-level standard manifests and artifact-bound compliance evidence.
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic

namespace ProofForge.Contract.Compliance

inductive RequirementKind where
  | interface
  | behavior
  | security
  deriving BEq, DecidableEq, Repr

def RequirementKind.id : RequirementKind → String
  | .interface => "interface"
  | .behavior => "behavior"
  | .security => "security"

inductive ComplianceLevel where
  | exact
  | scoped
  | experimental
  deriving BEq, DecidableEq, Repr

def ComplianceLevel.id : ComplianceLevel → String
  | .exact => "exact"
  | .scoped => "scoped"
  | .experimental => "experimental"

inductive RequirementStatus where
  | passed
  | failed
  | skipped
  deriving BEq, DecidableEq, Repr

def RequirementStatus.id : RequirementStatus → String
  | .passed => "passed"
  | .failed => "failed"
  | .skipped => "skipped"

structure StandardRef where
  id : String
  revision : String
  source : String
  deriving BEq, DecidableEq, Repr

structure Requirement where
  id : String
  kind : RequirementKind
  summary : String
  deriving BEq, DecidableEq, Repr

structure StandardManifest where
  standard : StandardRef
  requirements : Array Requirement
  deriving BEq, Repr

def StandardManifest.requirementIds (manifest : StandardManifest) : Array String :=
  manifest.requirements.map (·.id)

structure AdapterRef where
  id : String
  version : String
  deriving BEq, DecidableEq, Repr

structure ToolchainRef where
  id : String
  version : String
  environmentDigest? : Option String := none
  deriving BEq, DecidableEq, Repr

structure RequirementEvidence where
  requirementId : String
  adapter : AdapterRef
  artifactDigest : String
  oracleId : String
  oracleVersion : String
  command : String
  toolchains : Array ToolchainRef
  status : RequirementStatus
  runResultDigest : String
  deriving BEq, Repr

inductive ClaimScope where
  | full
  | subset (requirementIds : Array String)
  deriving BEq, Repr

/-- Raw evidence bundle offered by an adapter for one emitted artifact. It is
not trusted until `EvidenceClaim.verify` succeeds. -/
structure EvidenceClaim where
  manifest : StandardManifest
  adapter : AdapterRef
  artifactDigest : String
  scope : ClaimScope
  evidence : Array RequirementEvidence
  deriving BEq, Repr

structure ComplianceReport where
  level : ComplianceLevel
  manifest : StandardRef
  adapter : AdapterRef
  artifactDigest : String
  applicableRequirementIds : Array String
  satisfiedRequirementIds : Array String
  evidence : Array RequirementEvidence
  deriving BEq, Repr

structure ComplianceError where
  message : String
  deriving BEq, Repr

private def duplicateStrings (values : Array String) : Bool :=
  values.any fun value =>
    (values.filter fun other => other == value).size != 1

def validateManifest (manifest : StandardManifest) : Except ComplianceError Unit := do
  if manifest.standard.id.isEmpty then
    .error { message := "compliance manifest has an empty standard id" }
  if manifest.standard.revision.isEmpty then
    .error { message := s!"compliance manifest `{manifest.standard.id}` has an empty revision" }
  if manifest.standard.source.isEmpty then
    .error { message := s!"compliance manifest `{manifest.standard.id}` has an empty source" }
  if manifest.requirements.isEmpty then
    .error { message := s!"compliance manifest `{manifest.standard.id}` has no requirements" }
  let ids := manifest.requirementIds
  if duplicateStrings ids then
    .error { message := s!"compliance manifest `{manifest.standard.id}` has duplicate requirement ids" }
  for requirement in manifest.requirements do
    if requirement.id.isEmpty then
      .error { message := s!"compliance manifest `{manifest.standard.id}` has an empty requirement id" }
    if requirement.summary.isEmpty then
      .error {
        message :=
          s!"compliance requirement `{requirement.id}` in `{manifest.standard.id}` has an empty summary"
      }

def validateCatalog (manifests : Array StandardManifest) : Except ComplianceError Unit := do
  if manifests.isEmpty then
    .error { message := "compliance catalog is empty" }
  let standardIds := manifests.map (·.standard.id)
  if duplicateStrings standardIds then
    .error { message := "compliance catalog has duplicate standard ids" }
  for item in manifests do
    validateManifest item

private def resolveScope (manifest : StandardManifest) (scope : ClaimScope) :
    Except ComplianceError (Array String) := do
  let allIds := manifest.requirementIds
  match scope with
  | .full => pure allIds
  | .subset ids =>
      if ids.isEmpty then
        .error { message := s!"compliance scope for `{manifest.standard.id}` is empty" }
      if duplicateStrings ids then
        .error { message := s!"compliance scope for `{manifest.standard.id}` has duplicate ids" }
      for id in ids do
        if !allIds.contains id then
          .error {
            message := s!"compliance scope for `{manifest.standard.id}` contains unknown requirement `{id}`"
          }
      pure ids

private def validateAdapter (adapter : AdapterRef) : Except ComplianceError Unit := do
  if adapter.id.isEmpty then
    .error { message := "compliance adapter id is empty" }
  if adapter.version.isEmpty then
    .error { message := s!"compliance adapter `{adapter.id}` has an empty version" }

private def validateEvidence (scopeIds : Array String) (adapter : AdapterRef)
    (artifactDigest : String) (evidence : RequirementEvidence) :
    Except ComplianceError Unit := do
  if !scopeIds.contains evidence.requirementId then
    .error {
      message := s!"evidence references requirement `{evidence.requirementId}` outside the selected scope"
    }
  if evidence.adapter != adapter then
    .error {
      message :=
        s!"evidence for `{evidence.requirementId}` does not match adapter `{adapter.id}@{adapter.version}`"
    }
  if evidence.artifactDigest != artifactDigest then
    .error {
      message := s!"evidence for `{evidence.requirementId}` has a mismatched artifact digest"
    }
  if evidence.oracleId.isEmpty || evidence.oracleVersion.isEmpty then
    .error { message := s!"evidence for `{evidence.requirementId}` is missing oracle identity" }
  if evidence.command.isEmpty then
    .error { message := s!"evidence for `{evidence.requirementId}` is missing its command" }
  if evidence.toolchains.isEmpty then
    .error { message := s!"evidence for `{evidence.requirementId}` has no toolchain provenance" }
  for toolchain in evidence.toolchains do
    if toolchain.id.isEmpty || toolchain.version.isEmpty then
      .error { message := s!"evidence for `{evidence.requirementId}` has incomplete toolchain provenance" }
  if evidence.runResultDigest.isEmpty then
    .error { message := s!"evidence for `{evidence.requirementId}` has no result digest" }

def verify (manifest : StandardManifest) (adapter : AdapterRef)
    (artifactDigest : String) (scope : ClaimScope)
    (evidence : Array RequirementEvidence) : Except ComplianceError ComplianceReport := do
  validateManifest manifest
  validateAdapter adapter
  if artifactDigest.isEmpty then
    .error { message := s!"compliance report for `{manifest.standard.id}` has an empty artifact digest" }
  let scopeIds ← resolveScope manifest scope
  for item in evidence do
    validateEvidence scopeIds adapter artifactDigest item
  let satisfied := scopeIds.filter fun requirementId =>
    evidence.any fun item =>
      item.requirementId == requirementId && item.status == .passed
  let complete := satisfied.size == scopeIds.size
  let level :=
    if complete then
      match scope with
      | .full => ComplianceLevel.exact
      | .subset _ => ComplianceLevel.scoped
    else
      ComplianceLevel.experimental
  pure {
    level := level
    manifest := manifest.standard
    adapter := adapter
    artifactDigest := artifactDigest
    applicableRequirementIds := scopeIds
    satisfiedRequirementIds := satisfied
    evidence := evidence
  }

def EvidenceClaim.verify (claim : EvidenceClaim) : Except ComplianceError ComplianceReport :=
  ProofForge.Contract.Compliance.verify claim.manifest claim.adapter claim.artifactDigest
    claim.scope claim.evidence

/-- A support claim can promote only when all requirements of the expected
standard pass for the exact adapter id/version and artifact digest carried by
the evidence bundle. -/
def EvidenceClaim.isExactFor (claim : EvidenceClaim) (manifest : StandardManifest)
    (adapter : AdapterRef) : Bool :=
  if claim.manifest != manifest || claim.adapter != adapter ||
      claim.scope != .full then
    false
  else
    match claim.verify with
    | .error _ => false
    | .ok report =>
        report.level == .exact &&
          report.satisfiedRequirementIds == report.applicableRequirementIds

private def requirement (id : String) (kind : RequirementKind) (summary : String) : Requirement :=
  { id := id, kind := kind, summary := summary }

private def manifest (id revision source : String)
    (requirements : Array Requirement) : StandardManifest := {
  standard := { id := id, revision := revision, source := source }
  requirements := requirements
}

def erc20Manifest : StandardManifest :=
  manifest "erc-20" "EIP-20" "https://eips.ethereum.org/EIPS/eip-20" #[
    requirement "erc20.interface.core" .interface
      "Expose totalSupply, balanceOf, transfer, transferFrom, approve, and allowance with canonical ABI types",
    requirement "erc20.interface.events" .interface
      "Expose canonical Transfer and Approval events",
    requirement "erc20.behavior.transfer" .behavior
      "Transfer updates balances, returns bool, and emits Transfer including zero-value transfers",
    requirement "erc20.behavior.allowance" .behavior
      "approve and transferFrom update and consume allowance and emit the required events",
    requirement "erc20.security.balance" .security
      "Insufficient balance or allowance cannot create or move tokens",
    requirement "erc20.security.width" .security
      "Canonical uint256 values are not narrowed or silently truncated"
  ]

def erc20ProductProfileManifest : StandardManifest :=
  manifest "proof-forge-erc20-product" "2026-07-11"
    "https://docs.openzeppelin.com/contracts/5.x/api/token/erc20" #[
    requirement "pf-erc20-product.interface.metadata" .interface
      "Expose selected optional name, symbol, and decimals product metadata",
    requirement "pf-erc20-product.behavior.features" .behavior
      "Configured mint, burn, cap, and pause features materialize in executable behavior",
    requirement "pf-erc20-product.security.authority" .security
      "Mint, pause, and administration operations have explicit non-public authority",
    requirement "pf-erc20-product.security.init" .security
      "Initialization is atomic and cannot be replayed"
  ]

def erc165Manifest : StandardManifest :=
  manifest "erc-165" "EIP-165" "https://eips.ethereum.org/EIPS/eip-165" #[
    requirement "erc165.interface.supports" .interface
      "Expose supportsInterface(bytes4) returning bool with the canonical selector",
    requirement "erc165.behavior.self" .behavior
      "Return true for ERC-165 and every implemented interface id",
    requirement "erc165.behavior.unknown" .behavior
      "Return false for unknown interfaces and the forbidden 0xffffffff id within the gas bound",
    requirement "erc165.security.immutable" .security
      "Untrusted runtime callers cannot forge or mutate the advertised interface set"
  ]

def erc721Manifest : StandardManifest :=
  manifest "erc-721" "EIP-721" "https://eips.ethereum.org/EIPS/eip-721" #[
    requirement "erc721.interface.core" .interface
      "Expose balanceOf, ownerOf, approve, getApproved, setApprovalForAll, isApprovedForAll, transferFrom, and both safeTransferFrom forms",
    requirement "erc721.interface.discovery" .interface
      "Expose ERC-165 support for the mandatory ERC-721 interface",
    requirement "erc721.behavior.events" .behavior
      "Emit canonical Transfer, Approval, and ApprovalForAll events",
    requirement "erc721.behavior.receiver" .behavior
      "Safe transfers to contracts require the ERC721Receiver acceptance value",
    requirement "erc721.security.authorization" .security
      "Only owner, approved account, or approved operator can transfer a token",
    requirement "erc721.security.addresses" .security
      "Owner and receiver values use canonical address ABI and forbidden zero-address cases reject"
  ]

def erc1155Manifest : StandardManifest :=
  manifest "erc-1155" "EIP-1155" "https://eips.ethereum.org/EIPS/eip-1155" #[
    requirement "erc1155.interface.core" .interface
      "Expose canonical balance, operator approval, single transfer, and dynamic batch transfer functions",
    requirement "erc1155.interface.discovery" .interface
      "Expose ERC-165 support for ERC-1155 and its receiver interfaces",
    requirement "erc1155.behavior.events" .behavior
      "Emit TransferSingle, TransferBatch, ApprovalForAll, and URI events as applicable",
    requirement "erc1155.behavior.receiver" .behavior
      "Safe single and batch transfers enforce receiver acceptance callbacks with bytes data",
    requirement "erc1155.security.authorization" .security
      "Only owner or approved operator can move balances",
    requirement "erc1155.security.batch-shape" .security
      "Batch ids and values have equal dynamic length and cannot be silently truncated"
  ]

def erc2612Manifest : StandardManifest :=
  manifest "erc-2612" "EIP-2612" "https://eips.ethereum.org/EIPS/eip-2612" #[
    requirement "erc2612.interface.core" .interface
      "Expose permit(owner,spender,value,deadline,v,r,s), nonces, and DOMAIN_SEPARATOR",
    requirement "erc2612.behavior.approval" .behavior
      "A valid permit atomically sets allowance, increments nonce, and emits Approval",
    requirement "erc2612.behavior.deadline" .behavior
      "Expired signatures reject without state changes",
    requirement "erc2612.security.replay" .security
      "Nonce and domain separation prevent replay across accounts, contracts, and chains",
    requirement "erc2612.security.signature" .security
      "Signature recovery validates signer, v, and canonical low-s form without public staging"
  ]

def erc4626Manifest : StandardManifest :=
  manifest "erc-4626" "EIP-4626" "https://eips.ethereum.org/EIPS/eip-4626" #[
    requirement "erc4626.interface.share-token" .interface
      "Implement the ERC-20 share token including required metadata and allowance behavior",
    requirement "erc4626.interface.views" .interface
      "Expose asset, totalAssets, conversions, maximums, and preview functions with canonical uint256/address ABI",
    requirement "erc4626.interface.actions" .interface
      "Expose deposit, mint, withdraw, and redeem plus canonical Deposit and Withdraw events",
    requirement "erc4626.behavior.rounding" .behavior
      "Conversions and previews follow the standard caller-independence, fee, slippage, and rounding rules",
    requirement "erc4626.behavior.limits" .behavior
      "Maximum functions reflect global and receiver/owner limits without overstating accepted amounts",
    requirement "erc4626.behavior.actions" .behavior
      "Actions move the full requested assets/shares, return canonical amounts, and emit canonical events",
    requirement "erc4626.security.delegation" .security
      "Third-party withdraw and redeem enforce share allowance and owner authorization",
    requirement "erc4626.security.accounting" .security
      "totalAssets and full-precision math cannot silently ignore managed assets, overflow, or narrow values"
  ]

def erc173Manifest : StandardManifest :=
  manifest "erc-173" "EIP-173" "https://eips.ethereum.org/EIPS/eip-173" #[
    requirement "erc173.interface.owner" .interface
      "Expose owner() returning address and transferOwnership(address)",
    requirement "erc173.interface.event" .interface
      "Expose OwnershipTransferred(previousOwner,newOwner) with indexed addresses",
    requirement "erc173.behavior.transfer" .behavior
      "Authorized transfer and zero-address renounce update owner and emit the event",
    requirement "erc173.security.authorization" .security
      "Only the current owner can transfer or renounce ownership",
    requirement "erc173.security.init" .security
      "Initial ownership is set atomically and cannot be replayed"
  ]

def roleAccessProfileManifest : StandardManifest :=
  manifest "proof-forge-role-access" "2026-07-11"
    "https://docs.openzeppelin.com/contracts/5.x/api/access" #[
    requirement "pf-role.interface.core" .interface
      "Expose role query, grant, revoke, renounce, and role-admin operations with canonical role identity",
    requirement "pf-role.interface.events" .interface
      "Expose role grant, revoke, and admin-change events",
    requirement "pf-role.behavior.admin" .behavior
      "Grant and revoke enforce the configured role-admin relationship",
    requirement "pf-role.security.escalation" .security
      "Public callers cannot initialize, forge, or self-escalate privileged roles",
    requirement "pf-role.security.renounce" .security
      "Renounce only removes the caller's own role"
  ]

def nep141Manifest : StandardManifest :=
  manifest "nep-141" "NEP-141"
    "https://github.com/near/NEPs/blob/master/neps/nep-0141.md" #[
    requirement "nep141.interface.core" .interface
      "Expose NEP-141 JSON entrypoints using AccountId and decimal-string U128 values",
    requirement "nep141.interface.transfer-call" .interface
      "Expose ft_transfer_call and the resolver callback contract",
    requirement "nep141.behavior.one-yocto" .behavior
      "Transfer entrypoints require exactly one yoctoNEAR and preserve memo/msg semantics",
    requirement "nep141.behavior.resolve" .behavior
      "Transfer-call resolution refunds only the bounded unused amount",
    requirement "nep141.security.callback" .security
      "Resolver callbacks are private and cannot be invoked directly by an attacker",
    requirement "nep141.security.concurrency" .security
      "Concurrent transfer-call receipts cannot overwrite each other's pending state"
  ]

def nep145Manifest : StandardManifest :=
  manifest "nep-145" "NEP-145"
    "https://github.com/near/NEPs/blob/master/neps/nep-0145.md" #[
    requirement "nep145.interface.core" .interface
      "Expose storage_deposit, storage_withdraw, storage_unregister, storage_balance_bounds, and storage_balance_of",
    requirement "nep145.interface.json" .interface
      "Use canonical StorageBalance and StorageBalanceBounds JSON objects with decimal-string U128 values",
    requirement "nep145.behavior.deposit" .behavior
      "Registration charges the required storage balance and refunds excess attached deposit",
    requirement "nep145.behavior.withdraw" .behavior
      "Withdraw and unregister update storage balance and transfer the correct refund",
    requirement "nep145.security.deposit" .security
      "Withdraw and unregister enforce the one-yocto and caller/registration rules",
    requirement "nep145.security.accounting" .security
      "Cross-account calls, underflow, and storage-cost changes cannot steal or fabricate storage balance"
  ]

def splTokenManifest : StandardManifest :=
  manifest "spl-token" "Token Program"
    "https://solana.com/docs/tokens" #[
    requirement "spl-token.interface.instructions" .interface
      "Transaction plans use canonical Token Program instructions and account order",
    requirement "spl-token.interface.accounts" .interface
      "Mint and token-account schemas preserve owner program, authority, and amount fields",
    requirement "spl-token.behavior.lifecycle" .behavior
      "Create, initialize, mint, transfer, burn, approve, revoke, close, and authority changes execute as claimed",
    requirement "spl-token.behavior.receipt" .behavior
      "Broadcast reports signatures and verifies resulting mint/account state",
    requirement "spl-token.security.authority" .security
      "Signer, writable, owner, mint, delegate, and authority checks cannot be escalated",
    requirement "spl-token.security.program" .security
      "The resolved external Token Program id and version are recorded and verified"
  ]

def splToken2022Manifest : StandardManifest :=
  manifest "spl-token-2022" "Token-2022"
    "https://solana.com/docs/tokens/extensions" #[
    requirement "token2022.interface.extensions" .interface
      "Each advertised extension has a versioned instruction and account schema",
    requirement "token2022.interface.space" .interface
      "Mint/account extension scope and required allocation are explicit",
    requirement "token2022.behavior.init-order" .behavior
      "Extension initialization order and configuration match the deployed Token-2022 program",
    requirement "token2022.behavior.compatibility" .behavior
      "Only compatible extension combinations materialize and execute",
    requirement "token2022.security.accounts" .security
      "Extension-specific authority, signer, owner, and extra-account-meta requirements are enforced",
    requirement "token2022.security.program" .security
      "The resolved external Token-2022 program id and version are recorded and verified"
  ]

def knownManifests : Array StandardManifest := #[
  erc20Manifest,
  erc20ProductProfileManifest,
  erc165Manifest,
  erc721Manifest,
  erc1155Manifest,
  erc2612Manifest,
  erc4626Manifest,
  erc173Manifest,
  roleAccessProfileManifest,
  nep141Manifest,
  nep145Manifest,
  splTokenManifest,
  splToken2022Manifest
]

private def unboundAdapter (id : String) : AdapterRef := {
  id := id
  version := "unverified-snapshot-2026-07-11"
}

private def unboundReport (manifest : StandardManifest) (adapterId : String) :
    Except ComplianceError ComplianceReport :=
  verify manifest (unboundAdapter adapterId) "unbound:no-artifact-evidence" .full #[]

/-- Recorded audit claims that must remain non-exact until runtime evidence is
bound to each requirement and concrete artifact. -/
def currentAtRiskReports : Except ComplianceError (Array ComplianceReport) := do
  let erc20 ← unboundReport erc20Manifest "evm-erc20-stdlib"
  let erc20Product ← unboundReport erc20ProductProfileManifest "evm-token-product"
  let erc165 ← unboundReport erc165Manifest "evm-erc165-stdlib"
  let erc721 ← unboundReport erc721Manifest "evm-erc721-stdlib"
  let erc1155 ← unboundReport erc1155Manifest "evm-erc1155-stdlib"
  let erc2612 ← unboundReport erc2612Manifest "evm-erc2612-stdlib"
  let erc4626 ← unboundReport erc4626Manifest "evm-erc4626-stdlib"
  let erc173 ← unboundReport erc173Manifest "evm-ownable-stdlib"
  let roleAccess ← unboundReport roleAccessProfileManifest "portable-role-access"
  let nep141 ← unboundReport nep141Manifest "near-nep141-stdlib"
  let nep145 ← unboundReport nep145Manifest "near-nep145-storage"
  let spl ← unboundReport splTokenManifest "solana-spl-token-plan"
  let token2022 ← unboundReport splToken2022Manifest "solana-token-2022-plan"
  pure #[erc20, erc20Product, erc165, erc721, erc1155, erc2612, erc4626,
    erc173, roleAccess, nep141, nep145, spl, token2022]

def renderSummary (reports : Array ComplianceReport) : String :=
  let rows := reports.toList.map fun report =>
    s!"{report.manifest.id}={report.level.id}"
  "standard-compliance: " ++ String.intercalate " · " rows

end ProofForge.Contract.Compliance
