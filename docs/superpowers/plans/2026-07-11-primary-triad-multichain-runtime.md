# Primary-Triad Multichain Contract Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `subagent-driven-development` (recommended) or `executing-plans` to implement
> this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Active

**Recorded on:** `feat/batch-a-p0-cleanup` at `bbc4fb9d` (2026-07-11)

**Goal:** A developer maintains business intent once, selects only
`--target evm | solana-sbpf-asm | wasm-near`, and receives an honest runnable
contract/program or protocol transaction bundle, matching client, deployment
plan, and verification evidence without authoring chain-specific storage,
accounts, ABI, CPI, Promise, or token-standard details.

**Architecture:** Elaborate a product source once, classify its typed business
intent, look up the selected target profile, then let `ProductRouter` select an
array of versioned component recipes. Each generated component enters the
existing `ContractSpec -> capability resolve -> target plan` pipeline; protocol
and host components enter their own typed materializers. The final
pre-build `ProductRoutePlan` records all per-component capabilities,
qualification references, and semantics that cannot be erased; a separate
post-build `ProductBuildReport` binds artifacts and current run evidence. The
design must not introduce a second target registry or merge the three backends
into a generic code generator.

**Tech stack:** Lean 4.31, Lake, `proof-forge`, Yul/EVM bytecode, direct sBPF
assembly/ELF, WAT/Wasm with NEAR host imports, Foundry/Anvil, Pinocchio/Surfpool,
NEAR sandbox, TypeScript clients, Rust testkit, Quint, and Lean refinement
surfaces.

## Global Constraints

1. The primary product scope is `evm`, `solana-sbpf-asm`, and `wasm-near`.
2. Automatic routing happens at compile/materialization time after an explicit
   `--target`. This plan does not build a cross-chain bridge or one bytecode
   artifact that discovers its chain at runtime.
3. Authors express business semantics. They do not select ERC, NEP, SPL,
   Token-2022, Metaplex, ABI codecs, account metas, or Promise indices.
4. Target-specific semantics may be hidden from the author but must remain
   explicit in the resolved plan, artifact metadata, generated client, and
   diagnostics.
5. Unsupported or non-equivalent behavior must fail closed. A Promise id is
   never a synchronous return value; a plan is never reported as deployed
   code; a feature name is never reported as `full` without executable proof.
6. Existing `TargetProfile`, `TargetBackend`, `BackendRegistry`,
   `CapabilityPlan`, `Materialize`, `ProtocolMaterialize`, and per-target
   `ModulePlan` types remain the extension seams. `ProductRouter` sits above
   per-generated-component backend resolution; it does not make
   `BackendRegistry` select ecosystem standards.
7. Official SDKs and reference contracts are behavioral oracles. ProofForge
   emits its own target artifacts; it does not copy OpenZeppelin,
   `near-contract-standards`, Anchor, or Metaplex source into generated output.
8. Each implementation slice starts with a failing regression, ends with an
   independently testable artifact, and lands as one coherent commit.
9. Standard compliance requires every applicable MUST-level interface and
   behavior, canonical ABI/schema evidence, and native runtime tests. A selector
   string or golden source file is not compliance.
10. Formal claims remain scoped to the proved fragment and trust boundary.
    Calls into deployed system/protocol programs carry an explicit external
    program-id/version assumption.
11. Do not stage, rewrite, or absorb pre-existing working-tree changes while
    executing this plan.

---

## 1. Branch Snapshot And Ownership Boundary

At plan creation, the branch already contains committed work at `bbc4fb9d`:

- EVM runtime custom-error expression arguments (initial slice later completed by E-P0-04).
- NEAR TokenSpec source auto-detection.
- A one-yocto guard for one NEAR storage-withdraw path.

It also contains unrelated, uncommitted work owned by another implementation
slice:

- `ProofForge/Backend/Solana/SbpfAsm/Stmt.lean`
- `ProofForge/Target/Registry.lean`
- `justfile`
- `Tests/Backend/Solana/SolanaWhileRevert.lean`

The uncommitted `justfile` diff contains the same
`Tests/Backend/Solana/SolanaWhileRevert.lean` invocation twice. The owner of
that slice must resolve it separately. Agents executing this roadmap must stage
only their declared paths.

### Truth sources

Do not use one source category to answer a different question:

1. Current code, native runtime output, and generated artifacts define what
   ProofForge actually implements.
2. Official chain standards define normative compliance. Official SDK and
   reference implementations are differential oracles where the specification
   leaves operational details.
3. Required CI gates, `justfile`, and `AGENTS.md` define repository acceptance.
4. This plan and the current gap audit define work ordering, not implementation
   or compliance truth.
5. Older roadmaps and status prose are historical context only.

The older `docs/sdk-ecosystem-gaps-2026-07.md` uses `Covered` too broadly for
several standard subsets. Task T-00 replaces that status vocabulary with
machine-backed compliance levels.

---

## 2. Product Boundary: What Is Unified

### 2.1 Author-visible intent

The default product surface is limited to:

- State and business invariants.
- Entrypoints and queries.
- Fungible, non-fungible, and multi-asset business features.
- Access, pause, reentrancy, upgrade, and lifecycle policies.
- Structured events and typed errors.
- External protocol intent such as transfer, balance query, or vault deposit.
- Call completion requirements: atomic result or asynchronous callback.
- Qualitative resource policy such as bounded execution or required storage
  funding. Optional numeric budgets live in target deployment configuration
  with an explicit denomination; there is no universal gas number in business
  logic.

### 2.2 Compiler-owned resolution

The router owns:

- Native standard selection.
- Generated-code versus deployed-protocol composition.
- Storage slots, host keys, Solana account graphs, PDA/ATA derivation, and rent.
- EVM ABI, NEAR JSON/Borsh, and Solana instruction layouts.
- CALL/CPI/Promise lowering and callback/compensation requirements.
- Event encoding, deployment lifecycle, client transaction construction, and
  artifact packaging.

### 2.3 Four materialization modes

Every resolved component must use one of these honest modes:

| Mode | Meaning | Example |
|---|---|---|
| `generatedProgram` | ProofForge generates the deployed code | EVM ERC-20 body, NEAR NEP-141 Wasm |
| `protocolBundle` | ProofForge calls an already-deployed standard program | Solana SPL Token mint and ATA transaction bundle |
| `hostPrimitive` | A target host/runtime action implements the effect | NEAR storage host functions, EVM logs |
| `hybrid` | Generated code composes with a deployed protocol | Solana Token-2022 mint plus generated transfer-hook ELF |

This distinction is user-transparent during authoring but visible in
`ProductRoutePlan`, artifact metadata, and deployment receipts.

---

## 3. Official SDK And Standard Inventory

Research snapshot: 2026-07-11. Links below are primary project or standards
sources and must be rechecked when a task begins.

### 3.1 EVM ecosystem

The reference component catalog is
[OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts), including
token implementations, access control, governance, proxy/upgrade utilities,
finance, meta-transactions, and account abstraction helpers. ProofForge should
match standards behavior, not duplicate the full catalog indiscriminately.

| Domain | Official baseline | ProofForge status at snapshot | Required closure |
|---|---|---|---|
| Fungible token | [ERC-20](https://eips.ethereum.org/EIPS/eip-20) | Core transfer/allowance/event shape exists, but amounts are commonly narrowed below `uint256` | Close every ERC-20 MUST-level ABI/behavior requirement with a full-width amount policy |
| Fungible product profile | ERC-20 optional metadata plus [OZ ERC20](https://docs.openzeppelin.com/contracts/5.x/api/token/erc20) interoperability | Metadata and authority policies are incomplete | Separately require optional name/symbol/decimals, mint authority, cap/pause policy, and SafeERC20 behavior; do not call these ERC-20 MUSTs |
| Permit | [ERC-2612](https://eips.ethereum.org/EIPS/eip-2612), [EIP-712](https://eips.ethereum.org/EIPS/eip-712) | Canonical seven-argument atomic route now exists with replay/deadline/domain/low-s/v attacks; compliance evidence is not yet bound | Bind exact adapter/artifact/runtime evidence before promotion from `experimental` |
| NFT | [ERC-721](https://eips.ethereum.org/EIPS/eip-721) | Transfer subset only | Add mandatory balance/approval/operator/ERC-165 behavior and canonical address ABI |
| Multi-token | [ERC-1155](https://eips.ethereum.org/EIPS/eip-1155) | Single-transfer subset plus a custom fixed-size-two batch | Dynamic batch ABI, `TransferBatch`, `balanceOfBatch`, standard receiver data and ERC-165 |
| Interface discovery | [ERC-165](https://eips.ethereum.org/EIPS/eip-165) | Immutable/generated identity set now rejects `0xffffffff`; evidence remains `experimental` | Bind the exact adapter/artifact/runtime result to the compliance manifest |
| Ownership | [ERC-173](https://eips.ethereum.org/EIPS/eip-173) | Canonical EVM ABI/event and one-shot initialization now coexist with a portable u64 carrier | Bind the exact adapter/artifact/runtime result to the compliance manifest |
| Role access | [OZ Access](https://docs.openzeppelin.com/contracts/5.x/api/access) | EVM bytes32 role/admin/event surface is separate from the portable u64 role profile | Finish behavioral equivalence and evidence binding; never report the portable profile as exact OZ AccessControl |
| Vault | [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) | Substantial runtime body with security hardening, but not a complete tokenized vault | Share allowance, delegated exits, total-assets policy, full-precision math, atomic initialization |
| Upgrade | [ERC-1967](https://eips.ethereum.org/EIPS/eip-1967), [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822) | Transport spike exists | `proxiableUUID`, only-proxy boundary, initializer calldata, authority binding, layout/migration checks |
| Governance | [OZ Governance](https://docs.openzeppelin.com/contracts/5.x/api/governance), [ERC-5805](https://eips.ethereum.org/EIPS/eip-5805), [ERC-6372](https://eips.ethereum.org/EIPS/eip-6372) | No reusable Governor/Votes/Timelock SDK | Add only after token/access compliance closes |
| Meta-tx/accounts | [ERC-2771](https://eips.ethereum.org/EIPS/eip-2771), [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337) | Missing | P2 after standard asset and lifecycle closure |

Additional ecosystem candidates include ERC-1271 signatures, ERC-1363 token
callbacks, ERC-2981 royalties, ERC-4906 metadata updates, ERC-3156 flash loans,
Ownable2Step, AccessManager, VestingWallet, and TimelockController. They enter
the SDK only through a scheduled component task with product demand.

### 3.2 NEAR ecosystem

The official SDK surface consists of
[near-sdk-rs](https://github.com/near/near-sdk-rs),
[`near-contract-standards`](https://docs.rs/near-contract-standards/latest/near_contract_standards/),
[near-sdk-contract-tools](https://github.com/near/near-sdk-contract-tools),
NEAR sandbox/workspaces, `near-api-js`, `near-cli-rs`, and `cargo-near`.
ProofForge directly emits Wasm, but these packages define the expected ABI,
contract behavior, reusable component boundaries, and differential oracle.

| Domain | Official baseline | ProofForge status at snapshot | Required closure |
|---|---|---|---|
| Fungible token | [NEP-141](https://github.com/near/NEPs/blob/master/neps/nep-0141.md) | `NearFungibleToken` is a Borsh/Hash/U64-shaped lite body, not an interoperable NEP-141 contract | JSON AccountId/U128, exact one yocto, registration, memo/msg, safe resolver and standard callbacks |
| Storage | [NEP-145](https://github.com/near/NEPs/blob/master/neps/nep-0145.md) | U64 ledger projection only | StorageBalance/Bounds objects, storage usage/cost, refund, withdraw, unregister and attack tests |
| FT metadata | [NEP-148](https://github.com/near/NEPs/blob/master/neps/nep-0148.md) | `ft_metadata` returns decimals only | Full metadata object and version string |
| Events | [NEP-297](https://github.com/near/NEPs/blob/master/neps/nep-0297.md) | Generic JSON log shape | Exact `EVENT_JSON` standard/version/event/data envelope |
| NFT | [NEP-171](https://github.com/near/NEPs/blob/master/neps/nep-0171.md), [NEP-177](https://github.com/near/NEPs/blob/master/neps/nep-0177.md), [NEP-178](https://github.com/near/NEPs/blob/master/neps/nep-0178.md), [NEP-181](https://github.com/near/NEPs/blob/master/neps/nep-0181.md) | Missing | Core, metadata, approval, enumeration, callbacks and storage funding |
| Multi-token | [NEP-245](https://github.com/near/NEPs/blob/master/neps/nep-0245.md) | Missing; older docs incorrectly mention NEP-448 | Implement only after NFT and dynamic ABI closure |
| Promise/cross-call | [NEAR cross-contract calls](https://docs.near.org/smart-contracts/anatomy/crosscontract) | create/then slice exists; portable sync assumptions remain | Typed async result/error, private callback, join/batch/return, gas/deposit and compensation |
| Serialization | [NEAR serialization](https://docs.near.org/smart-contracts/anatomy/serialization-interface) | Generated client sends JSON while generated Wasm entrypoints currently decode raw Borsh | Per-entrypoint codec plan shared by contract and client |
| Storage collections | [NEAR collections](https://docs.near.org/smart-contracts/anatomy/collections) | Scalar/map host-key lowering exists | Prefix/schema/version and migration discipline |
| Deployment/upgrade | [NEAR upgrade](https://docs.near.org/smart-contracts/release/upgrade), [Global Contracts](https://docs.near.org/smart-contracts/global-contracts) | Policy metadata only | Deploy-code, authority/lock, initialization, migration and receipt verification |

Official reusable contracts and examples include FT/NFT reference contracts,
factories, lockups, and global contracts. They are conformance inputs, not
proof that the current lite stdlib is standard-compatible.

### 3.3 Solana ecosystem

The native SDK surface includes direct Rust/Pinocchio or Anchor program APIs,
the System Program, SPL Token, Token-2022, Associated Token Accounts, Memo,
Metaplex programs, client transaction builders, and loader/deployment tooling.
Solana programs execute as
[sBPF ELF](https://solana.com/docs/core/programs/program-execution) with an
explicit account list.

| Domain | Official baseline | ProofForge status at snapshot | Required closure |
|---|---|---|---|
| Generic program | [Accounts](https://solana.com/docs/core/accounts), [PDA](https://solana.com/docs/core/pda), [CPI](https://solana.com/docs/core/cpi) | Portable sources can produce ELF; account/PDA/CPI support is broad | Duplicate-aware input parsing, per-entrypoint account graph, canonical bump, tighter permission validation |
| Fungible token | [Token Program CPI](https://solana.com/docs/tokens/advanced/cpi) | Broad classic SPL CPI support | Product transaction bundle, client, deploy/broadcast and receipt; live coverage for every claimed operation |
| Token extensions | [Token extensions](https://solana.com/docs/tokens/extensions) | Several operations and a plan catalog exist | Typed extension schema, space/order/account requirements, compatibility matrix, executable feature honesty |
| NFT/metadata | [Metaplex Token Metadata](https://developers.metaplex.com/token-metadata/token-standard), [Metaplex Core](https://developers.metaplex.com/core), [Token-2022 metadata](https://solana.com/docs/tokens/extensions/metadata) | No product adapter | Feature-derived route among Token Metadata, Core, and Token-2022 metadata paths |
| ATA/account lifecycle | Official ATA/System/Token programs | ATA/PDA/realloc/close slices exist | Complete initialization, alias, realloc, close, rent, signer and owner plan with runtime tests |
| Program lifecycle | [Solana deployment](https://solana.com/docs/programs/deploying) | Generic deploy is missing; upgrade authority is metadata | ProgramDeploymentPlan, loader/ProgramData, authority transfer, immutable mode and receipt |
| Formal/runtime evidence | Native runtime, Pinocchio/Surfpool | Counter refinement and selected live smokes | Account/CPI/PDA/Token traces and differential evidence for the claimed fragment |

For Solana, a standard token normally does not require a new per-token ELF.
The honest final artifact is a transaction bundle targeting a known Token
Program. Custom transfer logic may produce a hybrid Token-2022 plus transfer
hook ELF.

---

## 4. Confirmed Critical Gaps

### 4.1 Cross-target product gaps

| ID | Finding | Consequence |
|---|---|---|
| X-P0-01 | `TokenSpec` feature matrices historically validated plan labels rather than final behavior | Fail-closed routing is enforced for cap, pause, permit, confidential transfer and storage unregister; promotion from `experimental` to `full` now requires a verified full-scope claim for the canonical manifest, exact adapter/version and emitted artifact digest |
| X-P0-02 | There is no typed product route plan above target module plans | CLI, client, metadata, deploy and lowerers can independently infer different standard choices |
| X-P0-03 | Artifact kind does not fully model generated code versus protocol transaction bundles versus hybrid output | Solana TokenSpec is either under-claimed as a plan or over-claimed as a program |
| X-P0-04 | Portable call intent does not distinguish atomic return from scheduled callback | NEAR Promise identifiers can be mistaken for business return values |
| X-P0-05 | Standard compliance is prose-driven | Partial ERC/NEP/SPL components are reported as covered without MUST-level evidence |
| X-P0-06 | Generated client and target ABI are not guaranteed to consume the same codec/account plan | A successful build can still produce an unusable client |
| X-P0-07 | Portable numeric semantics stop below EVM U256 and principal values still admit Nat/U64 projections | Standard ABI values and full chain identities can truncate or collide |
| X-P0-08 | Product source detection retries another source kind after broad frontend failure | Real elaboration errors can be hidden and an ambiguous source can be misclassified |

### 4.2 EVM P0 findings

- ERC-721 lacks mandatory balance, approval/operator, event, and ERC-165
  surfaces; `ownerOf` metadata is not canonical address ABI.
- ERC-1155 single transfer omits the standard bytes argument, and the fixed
  two-item batch is not the standard dynamic batch or `TransferBatch` event.
- ERC-2612 staging/front-run, replay, deadline, domain, high-s, and invalid-v
  attacks are covered by the atomic Foundry gate. The feature router now accepts
  only exact canonical-manifest, adapter/version, artifact and passing-result
  evidence; ordinary builds remain `experimental` until they supply that claim.
- ERC-165 public mutation and forbidden-ID claims are closed; requirement-bound
  evidence promotion remains open.
- Ownable canonical ABI/events and one-shot initialization are closed. The EVM
  AccessControl adapter now has bytes32 roles/admin/events/renounce, while the
  portable role profile remains explicitly separate; full OZ behavioral
  equivalence and evidence promotion remain open.
- ERC-4626 lacks full share-token allowance/delegated exit behavior, a defined
  live `totalAssets` policy, full-precision math, and atomic initialization.
- Runtime custom-error expressions now enforce inferred type/range checks,
  static/runtime mutual exclusion, structural equality, selector/schema parity,
  and exact native revert payload tests.
- Entrypoint mutability cannot express payable/nonpayable/pure accurately.

### 4.3 NEAR P0 findings

- Closed by N-P0-01: one per-entrypoint Borsh plan now drives generated Wasm
  input validation and TypeScript client encoding/decoding; unsupported dynamic
  schemas fail client/build generation.
- Closed by N-P0-02: `NearFungibleToken` now has one-shot init, bound mint
  authority, private keyed resolver state, out-of-order callback isolation and
  refunds bounded by peer-unused, original amount and receiver balance.
- Closed by N-P0-03: hash-valued U64/Hash-keyed map results allocate stable
  copies, and affected entrypoints reset the hash bump allocator.
- TokenSpec name, decimals, and initial supply still need complete runtime
  parameterization. Cap, pause, and permit now reject before NEAR planning.
- External FT portable calls use zero deposit and synchronous assumptions that
  conflict with NEP-141 and Promise semantics.
- Predecessor/current/signer identities are hashed and truncated to U64,
  creating a collision boundary for access control.
- Native deposit and token amounts are narrowed instead of preserving U128.
- Upgrade classification has no executable deployment/migration path.

### 4.4 Solana P0 findings

- The sBPF input parser uses fixed offsets for every logical role, but the
  runtime uses compact duplicate-account markers. Account aliases can shift all
  later account/instruction offsets.
- Every entrypoint is forced to carry the module-wide account set, expanding
  locks and writable permissions.
- Token feature routing now rejects cap, pause, permit, and confidential
  transfer, and burn is capability-gated. Evidence-bound promotion from
  `experimental` remains open.
- Token-2022 extension initialization uses an untyped common account/parameter
  shape even though extension scope, space, ordering, and accounts differ.
- `SolanaModulePlan` remains a flat MVP while lowerer extensions, IDL, client,
  and manifest still reconstruct decisions.
- Product TokenSpec Solana coverage is outside the required `just product`
  aggregate and has no transaction client/broadcast/receipt closure.
- NFT/metadata routing and generic program deployment are missing.

---

## 5. Semantics That Must Not Be Erased

| Intent | EVM | NEAR | Solana | Router rule |
|---|---|---|---|---|
| Principal | 20-byte address | variable-length AccountId | 32-byte Pubkey/PDA | Portable principal must become opaque; target codec preserves full identity and no U64 projection is allowed |
| Amount | standard ABI commonly uint256 | JSON decimal string backed by U128 | u64 Token amount | `AmountPolicy` records bounds; narrower target must reject values outside the declared portable range |
| State | contract storage slots | host key/value plus storage staking | owned data accounts plus rent | Business state unifies; `StoragePlan` remains target-specific |
| Caller/auth | `msg.sender`, allowance, signature | predecessor/signer, account registration | signer/writable/authority/delegate | Access intent maps explicitly; non-equivalent authorization is rejected |
| External call | synchronous CALL/static/delegate | asynchronous receipts and callbacks | synchronous atomic CPI with account metas | Each operation declares local return, transaction receipt, fire-and-forget, or callback; an on-chain NEAR Promise cannot be a local return |
| Failure | transaction revert | receipt/callback failure with earlier receipts possibly committed | instruction/transaction error and atomic rollback | Cross-target scenario compares declared outcome and compensation, not raw trace equality |
| Event | topics/data | NEP-297 JSON log | program log/return data/indexer schema | Event meaning unifies; indexability is a target capability |
| Token implementation | generated contract | generated contract | deployed Token Program composition | Materialization mode is explicit in the route plan |
| NFT implementation | generated ERC-721 | generated NEP-171 | Metaplex/Token-2022 protocol composition | Target adapter selects from business features and records policy version |
| Upgrade | proxy/delegatecall | account code replacement plus migration/lock | loader ProgramData and authority | Only `UpgradeIntent` unifies; lifecycle actions remain target plans |
| Resources | gas/value | gas, attached deposit, storage balance | compute units, account locks, rent, transaction size | No universal numeric gas field; resource constraints are typed target requirements |

---

## 6. Selected Routing Design

### 6.1 Alternatives considered

1. **Continue adding target branches directly to `Token.lean` and CLI.**
   Fast for one feature, but standard selection, artifact type, client schema,
   and deployment behavior keep drifting. Rejected as the long-term model.
2. **Create one universal chain plan containing slots, accounts, PDAs, Promise
   indices, selectors, and codecs.** This makes target details leak into the
   portable layer and falsely equates incompatible semantics. Rejected.
3. **Add a typed product route plan above existing target plans.** Business
   components resolve to target-native recipes; target plans retain all chain
   semantics. Selected.

### 6.2 New route interfaces

Task R-01 creates `ProofForge/Target/ProductRoute.lean` with these stable
interfaces. The code below fixes ownership and serialization boundaries; exact
field types may reuse existing repository identifiers where available.

```lean
namespace ProofForge.Target

structure AdapterRef where
  id : String
  version : String
  deriving BEq, DecidableEq, Repr

structure StandardRef where
  id : String
  revision : String
  externalProgramId? : Option String := none
  externalProgramVersion? : Option String := none
  deriving BEq, DecidableEq, Repr

inductive MaterializationMode where
  | generatedProgram
  | protocolBundle
  | hostPrimitive
  | hybrid
  deriving BEq, DecidableEq, Repr

inductive InvocationModel where
  | generatedEntrypoint
  | protocolInstruction
  | hostAction
  deriving BEq, DecidableEq, Repr

inductive CompletionModel where
  | localReturn
  | transactionReceipt
  | fireAndForget
  | callback
  deriving BEq, DecidableEq, Repr

inductive ComplianceLevel where
  | exact
  | scoped
  | experimental
  deriving BEq, DecidableEq, Repr

inductive ArtifactRole where
  | programCode
  | protocolTransactions
  | client
  | deploymentPlan
  | receipt
  | complianceReport
  deriving BEq, DecidableEq, Repr

inductive RequiredConfigKind where
  | principal
  | signer
  | rpcEndpoint
  | externalProgram
  | targetBudget
  deriving BEq, DecidableEq, Repr

structure RequiredConfig where
  key : String
  kind : RequiredConfigKind
  denomination? : Option String := none
  secret : Bool := false
  deriving Repr

inductive AssumptionSubject where
  | standard (ref : StandardRef)
  | hostRuntime (id version : String)
  | oracle (id version : String)
  | formalTrustBoundary (id : String)
  deriving BEq, DecidableEq, Repr

structure ExternalAssumption where
  id : String
  subject : AssumptionSubject
  statement : String
  deriving Repr

structure ComplianceManifestRef where
  id : String
  revision : String
  deriving BEq, DecidableEq, Repr

structure AdapterQualificationRef where
  adapter : AdapterRef
  manifest : ComplianceManifestRef
  eligibleLevel : ComplianceLevel
  verifiedReportDigest : String
  deriving Repr

inductive RequirementStatus where
  | passed
  | failed
  | skipped
  deriving BEq, DecidableEq, Repr

structure ToolchainRef where
  id : String
  version : String
  environmentDigest? : Option String := none
  deriving Repr

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
  deriving Repr

structure ComplianceReport where
  level : ComplianceLevel
  manifest : ComplianceManifestRef
  adapter : AdapterRef
  artifactDigest : String
  applicableRequirementIds : Array String
  satisfiedRequirementIds : Array String
  evidence : Array RequirementEvidence
  deriving Repr

structure OperationRoute where
  operationId : String
  invocation : InvocationModel
  completion : CompletionModel
  deriving Repr

structure GeneratedRecipe where
  spec : ProofForge.Contract.ContractSpec
  deriving Repr

structure ProtocolRecipe where
  protocolId : String
  transactionSchemaId : String
  deriving Repr

structure HostRecipe where
  hostActionId : String
  deriving Repr

inductive ComponentRecipe where
  | generated (modules : Array GeneratedRecipe)
  | protocol (plans : Array ProtocolRecipe)
  | host (actions : Array HostRecipe)
  | hybrid (modules : Array GeneratedRecipe) (plans : Array ProtocolRecipe)
  deriving Repr

structure ComponentRouteDraft where
  intentId : String
  adapter : AdapterRef
  standards : Array StandardRef
  materialization : MaterializationMode
  operations : Array OperationRoute
  recipe : ComponentRecipe
  qualification : AdapterQualificationRef
  assumptions : Array ExternalAssumption := #[]
  deriving Repr

structure ProductRouteDraft where
  schemaVersion : Nat
  targetId : String
  targetRegistryRevision : String
  components : Array ComponentRouteDraft
  requiredConfig : Array RequiredConfig := #[]
  warnings : Array Diagnostic := #[]
  deriving Repr

structure GeneratedResolution where
  spec : ProofForge.Contract.ContractSpec
  capabilities : CapabilityPlan
  deriving Repr

structure ProtocolResolution where
  protocolId : String
  transactionSchemaId : String
  deriving Repr

structure HostResolution where
  hostActionId : String
  deriving Repr

inductive RoutedPayload where
  | generated (modules : Array GeneratedResolution)
  | protocol (plans : Array ProtocolResolution)
  | host (actions : Array HostResolution)
  | hybrid (modules : Array GeneratedResolution)
      (plans : Array ProtocolResolution)
  deriving Repr

structure RoutedComponentPlan where
  intentId : String
  adapter : AdapterRef
  standards : Array StandardRef
  materialization : MaterializationMode
  operations : Array OperationRoute
  payload : RoutedPayload
  qualification : AdapterQualificationRef
  assumptions : Array ExternalAssumption := #[]
  deriving Repr

structure ProductRoutePlan where
  schemaVersion : Nat
  targetId : String
  targetRegistryRevision : String
  components : Array RoutedComponentPlan
  artifactRoles : Array ArtifactRole
  requiredConfig : Array RequiredConfig := #[]
  warnings : Array Diagnostic := #[]
  deriving Repr

structure ArtifactResult where
  role : ArtifactRole
  digest : String
  deriving Repr

structure ReceiptResult where
  id : String
  digest : String
  deriving Repr

inductive TargetPlanKind where
  | generatedModule
  | protocolTransaction
  | hostAction
  deriving BEq, DecidableEq, Repr

structure TargetPlanResult where
  componentId : String
  planKind : TargetPlanKind
  digest : String
  deriving Repr

structure ProductBuildReport where
  schemaVersion : Nat
  routePlanDigest : String
  targetPlans : Array TargetPlanResult
  artifacts : Array ArtifactResult
  compliance : Array ComplianceReport
  receipts : Array ReceiptResult := #[]
  warnings : Array Diagnostic := #[]
  deriving Repr

end ProofForge.Target
```

`ProductRouter` owns standard and adapter selection. The existing
`BackendRegistry` does not select ERC/NEP/SPL policy; it resolves each generated
`ContractSpec` in a routed payload to its own `CapabilityPlan`. A
`protocolBundle` therefore needs no fake `ContractSpec`, while a `hybrid` may
contain multiple generated modules and protocol plans.

The three phases are deliberately separate:

1. `ProductRouter` returns `Except Diagnostic ProductRouteDraft` with a
   pre-build adapter qualification reference.
2. Per-component capability/protocol resolution returns
   `Except Diagnostic ProductRoutePlan`. This immutable pre-build plan is the
   only input to target planners, lowerers, clients, and packagers.
3. Emission and native execution return
   `Except Diagnostic ProductBuildReport`, which binds current target-plan and
   artifact digests, receipts, and per-requirement run evidence. The route plan
   is never mutated with post-build results.

`ComplianceReport` is constructed only by `Compliance.verify`, never directly
from source labels. `exact` requires every applicable requirement ID to have a
`passed` evidence row; `scoped` exposes the precise satisfied subset;
`experimental` cannot be presented as ecosystem-compatible. `failed` and
`skipped` never satisfy a requirement. `AdapterQualificationRef` is accepted
only after its referenced report digest is loaded and verified; its cached
level cannot come from adapter prose. Only non-fatal warnings live in a
successful draft, plan, or report.

### 6.3 Product input and component graph

Task R-02 creates `ProofForge/Contract/ProductIntent.lean` without replacing
`ContractSpec` or `TokenSpec`:

```lean
namespace ProofForge.Contract

inductive ProductIntent where
  | contract (spec : ContractSpec)
  | fungibleAsset (spec : Token.TokenSpec)
  | nonFungibleAsset (spec : NftSpec)
  | multiAsset (spec : MultiAssetSpec)

end ProofForge.Contract
```

`NftSpec` and `MultiAssetSpec` contain business fields and features only. The
Solana author never writes `Metaplex`, and the EVM author never writes
`ERC721`. An external-asset operation stays a `ProtocolIntent` in the existing
protocol materialization layer and is distinct from deploying an asset.

The loader elaborates a source exactly once and classifies typed exported
declarations. It preserves the original frontend diagnostic and rejects
ambiguous or missing product exports. Catching every `ContractSpec` error and
retrying TokenSpec is explicitly forbidden.

### 6.4 Adapter selection policy

- Fungible asset:
  - EVM: generated ERC-20 family contract.
  - NEAR: generated NEP-141/145/148 Wasm contract.
  - Solana: SPL Token bundle for core features; Token-2022 bundle when required;
    hybrid bundle plus generated hook ELF for custom transfer logic.
- Non-fungible asset:
  - EVM: generated ERC-721 family contract.
  - NEAR: generated NEP-171 plus selected extensions.
  - Solana MVP: Metaplex Token Metadata for the portable core. Metaplex Core is
    selected only by a business feature requiring its plugin model. Token-2022
    metadata is not the default NFT route.
- Multi-asset:
  - EVM: ERC-1155 after dynamic ABI closure.
  - NEAR: NEP-245 after NFT closure.
  - Solana: a separately reviewed Metaplex/Token-2022 policy; no route is
    advertised until an executable adapter exists.

Every choice records an `adapterId` and version in the route plan so policy
changes cannot silently alter repeat builds.

### 6.5 Authoritative pipeline

```text
Product source
  -> one frontend elaboration + typed product export
  -> ProductIntent + target-profile lookup
  -> ProductRouter -> Array ComponentRouteDraft
  -> route resolution:
       generated recipe -> existing BackendRegistry.resolve(spec) -> CapabilityPlan
       protocol recipe -> validated protocol/schema resolution
       host recipe -> validated host-action resolution
  -> immutable ProductRoutePlan with per-component capability and
     pre-build qualification references
  -> target planning/materialization:
       generated resolution -> target ModulePlan -> typed AST/program code
       protocol resolution -> ProtocolMaterialize -> transaction bundle
       host resolution -> target host-action plan
  -> ArtifactBundle + ComplianceManifest + Client + DeploymentPlan
  -> native validation + receipt
  -> ProductBuildReport with plan/artifact digests and requirement evidence
```

The resolved route plan is immutable input to target planners, lowerers,
clients, metadata, packaging, deployment, and refinement. No downstream stage
may rediscover a standard or feature from source strings. Adapter selection
must finish before the existing per-module capability resolver is invoked.

---

## 7. Execution Ledger

Allowed states are `pending`, `in_progress: evidence`, `blocked: condition`, and
`done: verified@SHA; commands`. Keep IDs stable.

### Wave T - Truth and immediate safety

| ID | Deliverable | Primary files | Acceptance | Depends | State |
|---|---|---|---|---|---|
| T-00 | Requirement-level standards manifests and evidence model; replace broad `Covered` claims | `docs/sdk-ecosystem-gaps-2026-07.md`, new `ProofForge/Contract/Compliance.lean`, `Tests/StandardCompliance.lean` | Stable requirement IDs cover interface, behavior and security obligations; status binds adapter version, artifact digest, oracle version and actual run result | none | done: verified@528a0148; `just standard-compliance`, `just docs-check`, `just product` |
| E-P0-01 | Canonical selector/schema derivation and fail-closed mismatch checks | `ProofForge/Cli/EvmAbi.lean`, `Contract/Spec.lean`, EVM validators | Tests reject a selector whose actual params differ; ABI JSON matches dispatcher | T-00 | done: verified@fac64949; `just evm-abi-schema`, `just portable-counter-multi-target`, `just evm-foundry` |
| E-P0-02 | Replace staged permit with atomic ERC-2612 or reject permit routing until complete | `Stdlib/ERC20Permit.lean`, `Token/EvmSpec.lean`, Foundry smoke | canonical seven-arg permit, nonce/domain/deadline/low-s/v tests, front-run regression | E-P0-01 | done: verified@86cc0f89; `just product-erc20-permit`, `just evm-foundry`, `just evm-anvil-deploy`, `just product` |
| E-P0-03 | Fix immutable standard identity/access surfaces | `Stdlib/ERC165.lean`, `Ownable.lean`, `AccessControl.lean` | Separate ERC-165, ERC-173 and access-profile conformance plus attacker re-init tests | T-00 | done: verified@6dac65f6; `just evm-standard-identity`, `just portable-auth-materialize`, `just contract-client`, `just evm-foundry`, `just product`, `just docs-check`, `just build` |
| E-P0-04 | Finish runtime custom-error expression safety from `bbc4fb9d` | EVM validation/lowering, `ErrorRef`, error smokes | inferred type/range, mutual exclusion, equality, exact Foundry payload | T-00 | done: verified@876e2ad9; `just evm-diagnostics`, `just evm-smoke errors`, `just evm-abi-schema`, `just contract-spec-json`, `just contract-client`, `just product`, `just docs-check`, `just build` |
| N-P0-01 | One authoritative per-entrypoint NEAR codec plan; stop emitting incompatible clients | `WasmHost/NearModulePlan.lean`, `Params.lean`, `Return.lean`, `Contract/Client.lean` | generated TS client calls nonzero-arg sandbox contract and decodes result; codec mismatch fails build | T-00 | done: verified@ab461417; `just near-abi-plan`, `just near-abi-client`, `just near-abi-client-sandbox`, `just near-plan-smoke`, `just near-target-first`, `just value-vault-wasm-refinement-smoke`, `just product`, `just docs-check`, `just build` |
| N-P0-02 | One-shot init, authorized mint, private/concurrent-safe resolver | `Stdlib/NearFungibleToken.lean`, NEAR sandbox tests | repeat-init, attacker mint, direct callback, concurrent transfer-call, and refund-bound attacks fail | N-P0-01 | done: verified@92ace75b; `just near-ft-security`, `just wasm-near-ft-transfer-call`, `just wasm-near-ft-transfer-call-e2e`, `just near-ft-security-sandbox`, `just contract-client`, `just product`, `just docs-check`, `just build` |
| N-P0-03 | Stable non-aliasing `Map<U64, Hash>` read results | `WasmHost/Map.lean`, allocator/plan/refinement tests | two retained hash reads survive later map operations and compare/store correctly in interpreter and sandbox | N-P0-01 | done: verified@4f4ccb5f; `just near-map-hash-alias`, `just near-map-hash-alias-sandbox`, `just wasm-near-plan`, `just near-plan-smoke`, `just near-target-first`, `just wasm-near-ft-transfer-call-e2e`, `just value-vault-wasm-refinement-smoke`, `just near-ft-security-sandbox`, `just product`, `just docs-check`, `just build` |
| S-P0-01 | Duplicate-aware Solana account input decoder and alias policy | `Backend/Solana/StateLayout.lean`, `SbpfAsm/Common.lean`, plan/tests | duplicate logical roles followed by another account decode correctly in ELF and pinned live runtime | T-00 | done: verified@ab23a012; `just solana-duplicate-accounts`, `just solana-bpf-encode-smoke`, `just solana-duplicate-accounts-live`, `just solana-light`, `just product`, `just docs-check` |
| S-P0-02 | Per-entrypoint account graph and least privilege | `Backend/Solana/Plan.lean`, `Manifest.lean`, `Idl.lean`, `Client.lean`, lowerer | unused accounts absent; signer/writable escalation tests fail closed | S-P0-01 | done: verified@315f3acd; `just solana-account-graph`, `just solana-pinocchio-reference-equivalence`, `just solana-light`, `just product`, `just docs-check`, `git diff --check`; manifest/IDL/client/plan/lowerer share entrypoint graphs, runtime counts are exact, and CPI/PDA/syscall helpers use entrypoint-local bindings |
| X-P0-01 | Feature support derives from executable adapter evidence | `Contract/Token.lean`, `TokenAuth.lean`, feature matrix tests | cap/pause/permit/confidential/unregister cannot report full without a verified requirement result for the exact adapter/artifact | T-00 | done: verified@0f9ce05f; `just token-feature-matrix`, `just standard-compliance`, `just product-erc20-permit`, `just product-token-near`, `just product-token-solana`, `just token-intent-smoke`, `just product`, `just docs-check`, `just build` |
| T-99 | Wave-T fail-closed gate | all Wave-T tests and product matrices | Every earlier Wave-T row is green or the corresponding route is rejected; evidence report records commands and digests | all earlier Wave-T rows | pending |

### Wave F - Portable numeric and principal foundations

| ID | Deliverable | Primary files | Acceptance | Depends | State |
|---|---|---|---|---|---|
| F-01 | `NumericDomain` and `AmountPolicy` with real wide-value semantics | portable IR types/semantics/validation and target codecs | U256 EVM, U128 NEAR and u64 Solana boundaries are represented without truncation; unsupported ranges reject; arithmetic and serialization tests cover boundaries | T-00 | pending |
| F-02 | Opaque `Principal` plus target `IdentityCodec` | portable IR values/semantics, EVM/NEAR/Solana ABI plans | 20-byte address, full NEAR AccountId and 32-byte Pubkey round-trip and compare/store without hash-to-U64 projection | T-00 | pending |

### Wave R - Unified product routing

| ID | Deliverable | Primary files | Acceptance | Depends | State |
|---|---|---|---|---|---|
| R-01 | Versioned route draft/plan/build-report phases and per-component payload/invocation/compliance types | new `Target/ProductRoute.lean`, `Target.lean`, tests | deterministic schema-versioned JSON/repr; no post-build evidence mutates the pre-build plan | T-00, X-P0-01 | pending |
| R-02 | `ProductIntent` loader unifies contract/token/NFT input detection | new `Contract/ProductIntent.lean`, CLI source loader | elaborate once; classify typed exports; preserve original errors; reject ambiguous/missing exports; no exception fallback or `--token` | R-01 | pending |
| R-03 | `ProductRouter` selects evidence-backed adapters; generated payloads dispatch through existing `BackendRegistry` | new `Target/ProductRouter.lean`, `BackendRegistry.lean`, `Materialize.lean` | versioned three-target adapter refs and modes; ineligible adapter rejects with intent/target/feature/evidence reason | R-01, R-02, T-99, F-01, F-02 | pending |
| R-04 | Protocol intent distinguishes deploy-own-asset from call-existing-asset | `Contract/Protocol.lean`, `Target/ProtocolMaterialize.lean` | external transfer maps to IERC20/SPL/NEP-141 with correct auth/deposit/completion or rejects | R-03 | pending |
| R-05 | Per-operation invocation/completion and async call plan | IR call/effect modules, `CrosscallMaterialize.lean`, NEAR plan | local return, transaction receipt, fire-and-forget and callback are distinct; synchronous query cannot consume a Promise id | R-04, N-P0-01 | pending |
| R-06 | Artifact bundle and `ProductBuildReport` model code, protocol bundle, hybrid, client, deployment, evidence and receipt | `Target/ArtifactBundle.lean`, `Target/ProductRoute.lean`, CLI build/deploy/check | EVM/NEAR token produce code; Solana token produces transaction bundle; hybrid carries both; report binds route/artifact/evidence digests | R-03, R-04, R-05 | pending |
| R-07 | `proof-forge plan --target` route explanation | CLI command/help/tests | stable JSON lists adapter, standard, mode, assumptions, required config and rejection reason | R-03, R-06 | pending |

### Wave E - EVM standard and SDK closure

| ID | Deliverable | Acceptance | Depends | State |
|---|---|---|---|---|
| E-01 | Full-width amount and ABI policy (`u256` standard boundary; checked portable bound) | ERC-20/721/1155/4626 canonical ABI plus boundary/rejection tests | E-P0-01, F-01, F-02 | pending |
| E-02 | ERC-20 route: metadata, authority-bound mint, cap and pause actually materialize | standard manifest, Foundry behavior, TokenPlan-to-module bidirectional check | E-01, X-P0-01, R-03 | pending |
| E-03 | Mandatory ERC-721 core plus metadata/royalty follow-up | balance/approval/operator/safe receiver/ERC-165 tests; exact ABI | E-01, E-P0-03 | pending |
| E-04 | Standard dynamic ERC-1155 core | dynamic batch/data ABI, `TransferBatch`, batch balances, receiver and ERC-165 tests | E-01 | pending |
| E-05 | Production ERC-4626 semantics | allowance/delegated exits, total-assets policy, fee-on-transfer/rebase decision, mulDiv and atomic init attacks | E-01, E-02 | pending |
| E-06 | UUPS lifecycle closure | proxiable UUID, only-proxy/not-delegated, upgrade-and-call, keyRef binding, layout/migration manifest | R-06 | pending |
| E-07 | Payable/pure ABI and client behavior | callvalue guard, payable artifact metadata, TS static/mutating/payable calls | E-P0-01 | pending |
| E-08 | Safe external token protocol adapter | empty-return/true/false policy, dynamic returndata, allowance and revert tests | R-04 | pending |
| E-09 | Selective catalog expansion: Votes/Timelock, royalties, vesting, ERC-1271/2771 | one component per reviewed task with standard manifest and runtime evidence | E-02, E-03, E-04, E-05, E-06, E-07, E-08 | pending |

### Wave N - NEAR standard, async, and lifecycle closure

| ID | Deliverable | Acceptance | Depends | State |
|---|---|---|---|---|
| N-01 | Full NEAR `u128`, AccountId, string/bytes, aggregate JSON and Borsh codecs | round-trip unit tests and sandbox calls; no identity truncation | N-P0-01, F-01, F-02 | pending |
| N-02 | Parameterized TokenSpec runtime | name/symbol/decimals/initial supply/features affect Wasm; unsupported features reject | N-01, X-P0-01, R-03 | pending |
| N-03 | Interoperable NEP-141 core | reference differential: transfer, transfer-call, resolver, one yocto, registration, memo/msg | N-P0-02, N-01, N-02 | pending |
| N-04 | NEP-145/148/297 closure | storage refunds/unregister, full metadata, exact event envelopes and storage attacks | N-03 | pending |
| N-05 | Typed Promise graph | create/then/and/batch/return, private callback, result/error, gas/deposit and compensation tests | R-05, N-01 | pending |
| N-06 | External FT protocol adapter | one-yocto transfer, async result, balance-query rejection/callback design | N-03, N-05, R-04 | pending |
| N-07 | NEP-171/177/178/181 NFT route | core/metadata/approval/enumeration conformance and sandbox runtime | N-01, R-03 | pending |
| N-08 | NEP-245 multi-token route | standard batch/event/client tests | N-01, N-07 | pending |
| N-09 | Deploy, lock, global-contract, upgrade and migration plan | sandbox deploy/init/migrate/lock and receipt; immutable policy verified | R-06, N-01 | pending |

### Wave S - Solana account, token, NFT, and lifecycle closure

| ID | Deliverable | Acceptance | Depends | State |
|---|---|---|---|---|
| S-01 | Authoritative `SolanaModulePlan` | storage/account/instruction/CPI/PDA/syscall/manifest plans are the only inputs to ELF, IDL, client, metadata | S-P0-01, S-P0-02, F-02 | pending |
| S-02 | Type-safe Token-2022 extension registry | typed scope/space/init/account/config/compatibility per claimed extension | X-P0-01, S-01 | pending |
| S-03 | TokenSpec transaction bundle and client | create mint/ATA, initialize, mint/transfer/burn/authority operations; unsigned bundle deterministic | R-06, S-02 | pending |
| S-04 | Broadcast and receipt | pinned Surfpool/validator transaction verifies program IDs, signatures, balances and extension state; devnet is supplementary evidence | S-03 | pending |
| S-05 | Product token coverage becomes required | add `product-token-solana` to `just product`; every claimed feature has negative/positive evidence | S-03 | pending |
| S-06 | Metaplex Token Metadata NFT MVP | mint, metadata, master edition, ownership transfer, client and receipt | R-03, R-06, S-01 | pending |
| S-07 | Metaplex Core adapter | business plugin feature triggers Core route; asset/plugin lifecycle tests | S-06 | pending |
| S-08 | Generic program deploy/upgrade lifecycle | loader/ProgramData, authority transfer, immutable mode and receipt | R-06, S-01 | pending |
| S-09 | Dynamic account/resource depth | canonical bump, realloc/close, extra metas, transaction/account limits and ALT decision | S-01, S-02 | pending |

### Wave P - Cross-target product proof

| ID | Deliverable | Acceptance | Depends | State |
|---|---|---|---|---|
| P-05 | Semantic scenario schema | compare typed states/events/outcomes/receipts instead of raw chain traces | R-06 | pending |
| P-01 | Portable fungible asset scenario | same source deploys/runs as ERC-20, NEP-141, SPL/Token-2022; supply/balance/auth/failure invariants match | P-05, E-02, N-04, S-05 | pending |
| P-02 | Portable NFT scenario | same NftSpec routes to ERC-721, NEP-171, Metaplex Token Metadata; ownership/approval/metadata invariants match | P-05, E-03, N-07, S-06 | pending |
| P-03 | External token protocol scenario | vault/escrow calls IERC20/SPL/NEP-141 with explicit atomic/async outcomes | P-05, E-08, N-06, S-03, R-05 | pending |
| P-04 | Unified client/deploy UX | generated TS client and deploy command execute all three scenarios using route-plan config only | P-01, P-02, P-03, R-06 | pending |
| P-06 | Formal/trust-boundary growth | generated paths refine supported IR; protocol bundles prove encoding/accounts and record external program assumptions | P-01, P-02, P-03, P-05 | pending |
| P-07 | Release evidence and documentation | product tutorial, target pages, compliance tables, artifact examples and Chinese mirrors agree | P-04, P-06, R-07 | pending |

---

## 8. Detailed First Execution Batch

The first batch closes false-success and safety issues before adapter selection.
EVM, NEAR, Solana, and portable-foundation tasks may use separate worktrees
after current branch changes are safely committed.

### 8.1 Dependency schedule

| Order | Tasks | Parallel rule | Exit condition |
|---|---|---|---|
| 1 | T-00 | Run alone because every later status consumes its evidence schema | Requirement manifests and verified-result model are green |
| 2 | X-P0-01, E-P0-01, E-P0-03, E-P0-04, N-P0-01, S-P0-01, F-01, F-02 | May run in owned worktrees after T-00 | False claims reject; base ABI/account/numeric/identity work has tests |
| 3 | E-P0-02, N-P0-02, S-P0-02, then R-01/R-02 | Safety tasks wait for their explicit predecessor; R-01 waits for X-P0-01 and R-02 waits for R-01, but they may run beside unrelated chain tasks | Safety closures plus route types and one-pass loader are green |
| 4 | T-99 | Run after every earlier Wave-T row; F/R work may continue independently | One evidence report proves all routes either pass or fail closed |
| 5 | R-03 | Requires T-99, F-01, F-02, R-01 and R-02 | Only evidence-eligible adapters can be selected |

### Task 1: T-00 Requirement-Level Compliance Truth

**Files:** Create `ProofForge/Contract/Compliance.lean` and
`Tests/StandardCompliance.lean`; modify
`docs/sdk-ecosystem-gaps-2026-07.md` and add `standard-compliance` to `justfile`.

- [x] Define stable standard revision and requirement IDs for interface,
      behavior, and security obligations. Split ERC-20 MUSTs from the optional
      product profile, and split ERC-173 from the access-role profile.
- [x] Define run evidence that binds requirement ID, adapter ID/version,
      artifact digest, oracle ID/version, command, status, and result digest.
- [x] Add failing assertions proving current ERC-721, ERC-1155, ERC-2612,
      NEP-141, and Solana Token claims are not `exact`.
- [x] Derive `exact` only when every applicable requirement has passing bound
      evidence; derive `scoped` from an explicit subset; never trust a status
      string supplied by an adapter.
- [x] Run `just standard-compliance`, `just docs-check`, translation sync, and
      commit only compliance/test/doc paths.

### Task 2: X-P0-01 Executable Feature Honesty

**Files:** Modify `ProofForge/Contract/Token.lean`,
`ProofForge/Contract/TokenAuth.lean`, `Tests/TokenFeatureMatrix.lean`, and target
token artifact tests.

- [x] Add negative cases for EVM cap/pause, NEAR cap/pause/permit/unregister,
      and Solana cap/pause/permit/confidential/unconditional burn.
- [x] Change every unmaterialized combination to a stable fail-closed
      diagnostic before adding any new feature implementation.
- [x] Replace named-gate strings with verified evidence references for the
      exact adapter version and emitted artifact/bundle digest.
- [x] Run `just token-feature-matrix`, affected target token smokes,
      `just product`, and commit.

### Task 3: E-P0-01 Canonical EVM ABI And Selector Schema

**Files:** Modify `ProofForge/Cli/EvmAbi.lean`, the contract ABI/spec schema,
EVM validators, and focused ABI/dispatcher tests.

- [x] Add a regression where an advertised selector and actual parameter schema
      disagree and prove the current path accepts or misreports it.
- [x] Derive selectors from the same canonical function schema consumed by the
      dispatcher and client; reject manual overrides that disagree.
- [x] Compare emitted ABI JSON, dispatcher decode widths/types, and runtime call
      behavior for static and dynamic arguments.
- [x] Run the focused ABI tests, `just product`, `just evm-foundry`, and commit.

### Task 4: E-P0-02 Atomic ERC-2612

**Files:** Modify `ProofForge/Contract/Stdlib/ERC20Permit.lean`,
`ProofForge/Contract/Token/EvmSpec.lean`, EVM ABI/client metadata, and Foundry
smokes. This task cannot start before E-P0-01.

- [x] Add attacks for signature overwrite/front-run, replay, expired deadline,
      bad domain, high-s, and invalid v.
- [x] Remove the public signature-staging entrypoint and use one canonical
      seven-parameter permit call.
- [x] Verify nonce/domain/signature rules and Approval emission atomically.
- [x] Run targeted Lean tests, `just product-erc20-permit`,
      `just evm-foundry`, `just evm-anvil-deploy`, `just product`, and commit.

### Task 5: E-P0-03 And E-P0-04 EVM Safety Closure

Execute as two commits with disjoint ownership where possible.

- [x] E-P0-03: make the ERC-165 set immutable/generated, force `0xffffffff`
      false, implement ERC-173 ABI/event behavior, separate role-profile
      requirements, and reject repeat initialization.
- [x] E-P0-04: add runtime custom-error inferred-type/range validation,
      static/runtime mutual exclusion, complete equality, and exact Foundry
      payload assertions.
- [ ] Run their focused tests, `just evm-foundry`, `just product`, and commit
      each slice independently.

### Task 6: N-P0-01 And N-P0-02 NEAR ABI And FT Safety

**Files:** `ProofForge/Backend/WasmHost/NearModulePlan.lean`, `Params.lean`,
`Return.lean`, `ProofForge/Contract/Client.lean`,
`Stdlib/NearFungibleToken.lean`, and nearest plan/sandbox tests.

- [x] N-P0-01: reproduce the generated-client JSON versus generated-Wasm Borsh
      mismatch with a nonzero argument and non-unit result.
- [x] Add a per-entrypoint `NearAbiPlan`; make Wasm and client consume it and
      validate input length/schema.
- [ ] N-P0-02: add repeat-init, attacker-mint, direct-callback, concurrent
      transfer-call, and refund-bound attack tests; implement one-shot init,
      authority, private callback, per-transfer state, and bounded refund.
- [ ] Run `just near-plan-smoke`, `just near-target-first`, pinned sandbox
      client/security smokes, `just product`, and commit each task separately.

### Task 7: S-P0-01 And S-P0-02 Solana Account Safety

**Files:** `ProofForge/Backend/Solana/StateLayout.lean`, `SbpfAsm/Common.lean`,
`Plan.lean`, `Manifest.lean`, `Idl.lean`, `Client.lean`, focused Lean tests, and
a pinned Pinocchio/Surfpool fixture.

- [x] S-P0-01: reproduce two logical roles sharing one pubkey followed by a
      distinct account; implement compact duplicate-marker walking before any
      state or instruction offset is consumed.
- [x] Define allowed and forbidden alias policies and verify the later account
      plus instruction data in ELF and the pinned runtime.
- [x] S-P0-02: carry an `AccountGraph` per entrypoint through plan, validator,
      IDL, client, manifest, and lowerer; reject signer/writable escalation.
- [x] Run focused Lean/ELF tests, `just solana-light`, the pinned live gate,
      `just product`, and commit each task separately.

S-P0-01 evidence (`ab23a012`): the interpreter regression executes the emitted
scanner against `[unique account 0, duplicate-of-0, unique account 2]`, checks
all three pointer-table slots and the final instruction-data cursor, and rejects
self/forward duplicate indices with target error 13. The generated live fixture
declares three logical roles and submitted `[payer, payer, system_program]` to a
deployed ELF on Surfpool; dispatch succeeded with the distinct third role after
the compact duplicate record. The verified ELF SHA-256 was
`d007d77353344f797eb94031e158f7fda120a06911b60702b7a79458de1202fb`.
The pinned local runner was Darwin 25.4.0 arm64 with Lean 4.31.0, sbpf 0.2.2,
Surfpool 0.10.8, Solana CLI 3.1.12, and Cargo 1.94.1. The optional GitHub
`solana-pinocchio-live` job runs the same live gate after its pinned toolchain
installer.

### Task 8: F-01 And F-02 Portable Value Foundations

Treat both as shared-IR migrations with broad blast radius and separate commits.

- [ ] F-01: choose and document a real wide-integer representation; implement
      arithmetic/serialization/validation for U256, U128, and u64 target
      boundaries. A target either preserves the value or rejects it; it never
      truncates. `exact` EVM token compliance remains impossible until U256 is
      executable end to end.
- [ ] F-02: introduce an opaque principal value and target codecs; round-trip,
      compare, store, and authorize EVM addresses, NEAR AccountIds, and Solana
      Pubkeys without hashing them into U64.
- [ ] Run focused semantics/codec tests, `just product`, `just check`, and
      request cross-backend review before each commit.

### Task 9: T-99 Safety Gate

- [ ] Run every Wave-T focused gate plus `just product` and
      `just standard-compliance` on one integrated commit.
- [ ] Emit a machine-readable evidence report with command/tool versions,
      adapter versions, artifact digests, oracle versions, and results.
- [ ] Assert that each incomplete feature/standard route rejects before
      materialization; skips and missing tools cannot count as passes.
- [ ] Mark T-99 done only after independent review. R-01/R-02 type and loader
      work may proceed under their dependencies, but R-03 adapter selection
      remains blocked until T-99, F-01, and F-02 are done.

---

## 9. Required Gates

| Boundary | Required evidence |
|---|---|
| Product intent/routing | `just product`, `just portable-default`, route-plan tests, negative unsupported routes |
| Compliance | requirement manifest, adapter/version, artifact digest, oracle/version, actual run result and `just standard-compliance` |
| EVM standard/runtime | canonical ABI manifest, targeted Lean test, pinned Foundry/Anvil version, `just evm-foundry`, `just evm-all` |
| NEAR standard/runtime | `just near-plan-smoke`, `just near-target-first`, pinned sandbox/runtime client-reference differential, NEAR honesty gates |
| Solana account/codegen | targeted Lean/ELF test, `just solana-light`, pinned local Pinocchio/Surfpool runner when affected |
| Solana token protocol | transaction bundle golden, pinned official-program execution, receipt/state verification, `just product-token-solana`; devnet evidence is supplementary |
| Cross-target scenario | `just testkit` plus source-backed EVM/Solana/NEAR runtime scenario |
| Formal boundary | affected refinement smoke, covered-fragment tests, explicit protocol assumptions |
| Documentation | `just docs-check`, `scripts/i18n/check-sync.sh`, `git diff --check` |

Before a task is marked done, run the narrow gates above and the broad gates
required by its blast radius. Before a wave closes, run:

```sh
just product
just check
scripts/i18n/check-sync.sh
git diff --check
```

Required live evidence must record the release runner image or environment,
toolchain versions, command, artifact digest, and result. Deterministic local
Anvil, NEAR sandbox, and Solana validator/Surfpool runs are release gates;
public devnet runs are supplementary because network state is not deterministic.
Unavailable chain tools may be recorded as an external blocker, but their
absence cannot promote compliance or turn a skip into a pass.

---

## 10. Global Definition Of Done

The primary-triad multichain runtime milestone is complete only when:

1. A single portable fungible source runs as ERC-20, NEP-141, and SPL or
   Token-2022 with native clients and deployment receipts.
2. A single portable NFT source runs as ERC-721, NEP-171, and the selected
   Metaplex route.
3. A portable external-token business contract routes IERC20, SPL Token, and
   NEP-141 calls without hand-written selectors, account metas, or Promise
   indices.
4. `proof-forge plan --target` explains every standard/materialization choice
   and every non-equivalent semantic assumption.
5. Generated code, protocol bundles, hybrid artifacts, clients, deployment
   plans, and receipts are distinct and truthfully typed.
6. No feature is accepted without materialization, and no standard is `exact`
   without its conformance manifest and native runtime gate.
7. NEAR async behavior is modeled as async; Solana accounts remain explicit in
   the target plan; EVM ABI and payable behavior match runtime dispatch.
8. Cross-target testkit compares declared business invariants across native
   execution, including failure and asynchronous completion.
9. Formal claims state the generated-code fragment and external protocol trust
   assumptions.
10. `just product`, `just check`, required live gates, docs/i18n sync, and diff
    checks pass on one final commit.

This definition does not require every OpenZeppelin, NEAR contract-tools,
Token-2022, or Metaplex component. It requires a truthful extension model and
complete primary product paths for the scheduled FT, NFT, protocol-call, and
lifecycle scenarios.

---

## 11. Long-Running Agent Execution Protocol

1. Start with `git status --short`, current branch, and the ledger above.
2. Preserve unrelated work; claim exact paths for one task.
3. Recheck current code and official standards before trusting this snapshot.
4. Select the earliest eligible pending task whose dependencies are done.
5. Write and run the failing regression before implementation.
6. Implement one vertical slice through plan, artifact, client, and runtime
   evidence where the task crosses those boundaries.
7. Inspect generated artifacts and receipts, not only command exit status.
8. Request independent review for standard compliance, false capability claims,
   privilege expansion, ABI drift, and missing negative tests.
9. Run narrow gates, then the required broad gates.
10. Stage owned paths explicitly, run cached diff checks, and commit one slice.
11. Update the ledger to `done: verified@SHA; commands` only after fresh
    post-commit evidence.
12. Continue to the next eligible task. A progress summary is not completion.

If blocked by an unavailable native tool, finish independent code/static/doc
work, record the exact command/error and unblock condition, then proceed to an
independent task. Never replace a required live test with a fabricated pass.

---

## 12. Long-Running Agent Prompt

Use this as the single continuation instruction for an implementation agent:

```text
Work in the current ProofForge checkout and execute
docs/superpowers/plans/2026-07-11-primary-triad-multichain-runtime.md as the
source-of-truth task ledger.

Objective: make one business source run honestly on EVM, NEAR, and Solana by
selecting only --target. Preserve target-native semantics behind a typed
ProductRoutePlan; do not build a runtime bridge, a second target registry, or a
universal plan that erases ABI, async, account, storage, authorization, or
lifecycle differences.

Keep stages acyclic: ProductRouter emits ProductRouteDraft; per-component
resolution emits the immutable pre-build ProductRoutePlan; emission and native
execution emit ProductBuildReport with artifact-bound requirement evidence.
Never mutate the route plan with post-build results, and never make the existing
BackendRegistry choose ERC/NEP/SPL policy.

At the start of every cycle:
1. Read AGENTS.md, git status, the current branch, recent commits, and the full
   plan. Treat current code/runtime as implementation truth and official
   standards as compliance truth.
2. Preserve every unrelated working-tree change. Claim exact paths for one
   task and never stage files outside that ownership set.
3. Select the earliest pending task whose dependencies are done. Use separate
   worktrees or agents for independent EVM, NEAR, and Solana tasks.
4. Revalidate the documented gap against current code and official sources.
   If it is stale, update the ledger with evidence before choosing another
   task.
5. Write a failing regression, implement one vertical slice, inspect generated
   artifacts/clients/receipts, and run the task's narrow and broad gates.
6. Request an independent review of standards compliance, capability honesty,
   privilege expansion, ABI drift, async behavior, and negative tests.
7. Commit only the owned slice. Then update its ledger state to
   done: verified@SHA; commands in a separate evidence commit if necessary.
8. Continue automatically with the next eligible task. Do not stop at a plan,
   partial implementation, skipped live test, or progress summary.

Fail closed whenever a target cannot preserve the requested behavior. A plan
is not deployed code, a Promise id is not a synchronous return value, and a
feature is not full/exact without executable native evidence. If a required
tool is unavailable, record the exact command, error, and unblock condition,
finish independent work, and continue with another eligible task.

Before closing a wave, run just product, just check,
scripts/i18n/check-sync.sh, and git diff --check, plus every live gate required
by the affected chain. The overall job ends only when Section 10's global
definition of done is satisfied or a concrete external blocker leaves no
eligible task.
```
