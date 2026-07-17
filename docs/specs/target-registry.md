---
id: SPEC-REG-001
title: Target 与 Profile 注册表
status: proposed
owner: targets
updated: 2026-07-17
normative: true
---

# Target 与 Profile 注册表

## 三种身份

- `TargetId`：执行、状态、调用、证明和结算语义；小写 ASCII `[a-z][a-z0-9-]{0,31}`。
- `CodegenProfileId`：target 的 ABI、lowering、artifact encoding、工具适配策略。
- `NetworkProfileId`：RPC/chain ID/deploy policy，只用于显式 deploy/verify。

三者不能拼接成隐式复合字符串，不能从 network 反推 codegen，也不能让 network 改变
semantic/plan hash。

## Schema authority

`SPEC-REG-001` 是 `TargetSemanticsV1`、`TargetDescriptor`、`CodegenProfileV1`、
`NetworkProfileV1`、`AcceptanceProfileV1`、`MaturitySnapshot` 及其本文件声明 nested type 的唯一
normative schema authority。primitive、`ContentRef`、`DocumentStatus`、
`ArtifactDeployability` 由 [`SPEC-COMMON-001`](common-types.md) 拥有；`RequirementKey`、
`SupportClaim`、`SupportEvidenceGrade`、`CandidateIdentity` 与 `FinalizationRef` 由
[`SPEC-CAP-001`](capabilities-extensions.md) 拥有。Architecture、target dossier 和其他规格只能
引用这些类型，不得重新声明同名 structure 或改变 ownership。

## Target semantics 与静态 descriptor

`TargetMaturity` 的 canonical wire enum 与全序唯一为：

```text
research < specified < prototype < artifact_validated < local_runtime
  < network_or_proof_validated
```

它描述整个 target acceptance profile 的端到端成熟度，不得与 `SupportEvidenceGrade` 或 evidence
ledger grade 比较，也不参与 build/deploy 授权。

```lean
structure SemanticRuleRef where
  id      : String
  version : SemVer
  digest  : Digest

inductive ExecutionHost
  | evm | svm | nearWasm | cosmWasm | sorobanWasm | icpCanister
  | noirCircuit | openvmGuest | aleoVm | psyDpn

inductive CommitModel
  | transactionAtomic | instructionAtomic | receiptLocal | transactionSavepoints
  | awaitSegmented | relationExternal | guestExternal | proofFinalDual
  | recursiveNetwork

inductive StateBinding
  | contractStorage | explicitAccounts | contractKeyValue | instanceKeyValue
  | ttlScopedStorage | canisterHeapStable | externalPublicPrePost
  | guestMemoryIo | recordsMappings | userPartitioned

inductive CallModel
  | synchronousMessage | synchronousCpi | promiseDag | cosmosSubmessageReply
  | synchronousAuthTree | asynchronousActor | noNativeCall | guestInternal
  | programProofFinal | recursiveProofPipeline

inductive ProofModel
  | noProof | externalCircuit | zkvmExecution | applicationChainProof
  | recursiveAggregation

inductive SettlementModel
  | evmChain | solanaChain | nearChain | cosmosChain | stellarChain
  | icpSubnet | externalVerifier | aleoChain | psyNetwork

structure TargetSemanticsV1 where
  schema             : SchemaId
  targetId           : TargetId
  semanticsVersion   : SemVer
  executionHost      : ExecutionHost
  commitModel        : CommitModel
  stateBinding       : StateBinding
  callModel          : CallModel
  proofModel         : ProofModel
  settlementModel    : SettlementModel
  abiSemantics       : SemanticRuleRef
  protocolRules      : Array SemanticRuleRef
  forkRules          : Array SemanticRuleRef
  resourceRules      : NonEmptyArray SemanticRuleRef
  failureRules       : NonEmptyArray SemanticRuleRef
  extensionRules     : Array SemanticRuleRef

structure TargetSemanticIdentity where
  targetId         : TargetId
  semanticsVersion : SemVer
  semanticsDigest  : Digest

structure AcceptanceProfileRef where
  id      : AcceptanceProfileId
  version : SemVer
  digest  : Digest

structure TargetDescriptor where
  semantics         : TargetSemanticsV1
  displayName       : String
  acceptanceProfile : AcceptanceProfileRef
  supportClaims     : Array SupportClaim
  codegenProfiles   : Array CodegenProfileId
  defaultCodegen    : Option CodegenProfileId
```

上述六个轴的唯一 wire enum 如下；表内次序也是各自 canonical rank，unknown value 一律拒绝：

| Type | Canonical wire values（从低 rank 到高 rank） |
|---|---|
| `ExecutionHost` | `evm`, `svm`, `near-wasm`, `cosmwasm`, `soroban-wasm`, `icp-canister`, `noir-circuit`, `openvm-guest`, `aleo-vm`, `psy-dpn` |
| `CommitModel` | `transaction-atomic`, `instruction-atomic`, `receipt-local`, `transaction-savepoints`, `await-segmented`, `relation-external`, `guest-external`, `proof-final-dual`, `recursive-network` |
| `StateBinding` | `contract-storage`, `explicit-accounts`, `contract-key-value`, `instance-key-value`, `ttl-scoped-storage`, `canister-heap-stable`, `external-public-pre-post`, `guest-memory-io`, `records-mappings`, `user-partitioned` |
| `CallModel` | `synchronous-message`, `synchronous-cpi`, `promise-dag`, `cosmos-submessage-reply`, `synchronous-auth-tree`, `asynchronous-actor`, `no-native-call`, `guest-internal`, `program-proof-final`, `recursive-proof-pipeline` |
| `ProofModel` | `no-proof`, `external-circuit`, `zkvm-execution`, `application-chain-proof`, `recursive-aggregation` |
| `SettlementModel` | `evm-chain`, `solana-chain`, `near-chain`, `cosmos-chain`, `stellar-chain`, `icp-subnet`, `external-verifier`, `aleo-chain`, `psy-network` |

这些值只是 digest 内的正交轴，不是 materializer dispatch family；完整 fork/host/commit/failure
语义仍由 target-owned rule closure 固定，尤其不能从任一 `*-wasm` 或 proof 值选择共享 Plan。

`TargetSemanticsV1` wire object 必须恰好包含上述十五个字段；`schema` 固定为
`proof-forge.target-semantics.v1`。五个 rule array 均按 `(id,version,digest)` canonical
key 升序并拒绝 duplicate；`SemanticRuleRef.id` 使用 1..127-byte lowercase dotted
ASCII，每个 segment 遵循 SPEC-COMMON-001 的 SchemaId segment grammar。`SemanticRuleRef` wire
object 恰为 `id,version,digest`，canonical key 是 `(id UTF-8,完整 SemVer UTF-8,digest raw bytes)`。
每个 `SemanticRuleRef` 必须 exact resolve 到 compiler 内静态
rule registry 中的 canonical payload 及其 domain-separated digest，unknown 或 digest mismatch 为
`PF-REGISTRY-INVALID`。
Target semantics digest 因而递归承诺这些 rule payload 的 exact content-addressed closure，
而不是对一组未校验 label 做 hash。

```text
semanticsDigest = SHA-256(
  "proof-forge.target-semantics.v1" || 0x00 || JCS(TargetSemanticsV1)
)
```

`TargetSemanticIdentity` 只能由 payload 的 `targetId`、`semanticsVersion` 和上式 digest
派生，不接受调用者自报 digest。fork/precompile/host protocol、resource/gas/
compute schedule、failure/commit 以及可观察 ABI 意义都在该 payload 内唯一拥有。
`displayName`、support/evidence、codegen 列表、maturity、toolchain 和 artifact encoding 不得
进入 semantics digest。
`TargetDescriptor` wire object 恰好为
`semantics,displayName,acceptanceProfile,supportClaims,codegenProfiles,defaultCodegen`；
claims 按 requirement key，profile ID 按 ASCII bytes 排序并拒绝 duplicate。它不存在
`maturity` 或 `maturitySnapshot` 字段。

## Codegen、Build 与 Network identity

Target 拥有 ABI 的可观察语义；Codegen 只拥有实现该语义的具体 byte encoding/emitter。

```lean
structure AbiEncodingProfileV1 where
  implements    : SemanticRuleRef
  encodingRules : NonEmptyArray SemanticRuleRef

structure ToolchainIdentity where
  id         : String
  version    : SemVer
  lockDigest : Digest
  digest     : Digest

structure ArtifactRoleSpecV1 where
  role          : String
  mediaType     : String
  deployability : ArtifactDeployability

structure ArtifactPrimaryGroupV1 where
  members : NonEmptyArray ArtifactRoleSpecV1

structure ArtifactEncoding where
  schema        : SchemaId
  encodingRules : NonEmptyArray SemanticRuleRef
  primaryGroups : NonEmptyArray ArtifactPrimaryGroupV1
  auxiliary     : Array ArtifactRoleSpecV1

structure CodegenProfileV1 where
  schema              : SchemaId
  id                  : CodegenProfileId
  targetSemantics     : TargetSemanticIdentity
  compilerToolchain   : ToolchainIdentity
  loweringVersion     : SemVer
  abiEncoding         : AbiEncodingProfileV1
  artifactEncoding    : ArtifactEncoding
  securityContract    : Option ContentRef
  minimumEvidence     : SupportEvidenceGrade

structure BuildIdentity where
  targetSemantics      : TargetSemanticIdentity
  codegenProfileId     : CodegenProfileId
  codegenProfileDigest : Digest

structure ChainIdentity where
  namespace : String
  reference : String

inductive EndpointTransport
  | http | https | ws | wss

structure Endpoint where
  priority  : UInt32
  transport : EndpointTransport
  authority : String
  path      : String

inductive FeePolicyKind
  | metered | fixed | sponsored | none

structure FeePolicy where
  kind  : FeePolicyKind
  rules : Array SemanticRuleRef

inductive DeploymentEnvironment
  | local | publicTestnet | production

inductive UpgradeModel
  | immutable | signerAuthority | governance | controller | external

structure DeployPolicy where
  environment      : DeploymentEnvironment
  upgradeModel     : UpgradeModel
  confirmationRule : SemanticRuleRef
  policyRules      : Array SemanticRuleRef

structure NetworkProfileV1 where
  schema           : SchemaId
  id               : NetworkProfileId
  chainIdentity    : ChainIdentity
  genesisDigest    : Digest
  endpoints        : NonEmptyArray Endpoint
  feePolicy        : FeePolicy
  deployPolicy     : DeployPolicy
  compatibleBuilds : NonEmptyArray BuildIdentity

structure NetworkProfileIdentity where
  id     : NetworkProfileId
  digest : Digest
```

`ToolchainIdentity` wire object 恰为 `id,version,lockDigest,digest`。`id` 使用 profile ID grammar；
`lockDigest` 必须精确等于 [`SPEC-TOOL-001`](toolchains.md) 对已验证完整 Tool Lock v2 payload
产生的唯一 `ToolLockV2Digest`：

```text
lockDigest = SPEC-TOOL-001.ToolLockV2Digest
digest = SHA-256("proof-forge.toolchain-identity.v1" || 0x00 ||
  JCS({id,version,lockDigest}))
```

`id/version` 必须 exact resolve 到该 lock 的一个 compiler/tool closure；不能用 version probe、PATH
命中或 manifest 自报值代替 lock resolution。这样 CodegenProfile 与 OutputSet consumer 都能从
同一 lock payload 独立重算完整 identity。raw `toolchainLockSha256` 不能填入 `lockDigest`；本规格只
拥有 `ToolchainIdentity.digest`，不得重新定义 Tool Lock payload 的摘要 authority。

`ArtifactRoleSpecV1` wire object 恰为 `role,mediaType,deployability`；role 是 1..63-byte lowercase
kebab ASCII `[a-z][a-z0-9]*(?:-[a-z0-9]+)*`，media type 是 lowercase ASCII `type/subtype`，禁止
parameter、wildcard、空白和 alternate spelling。`ArtifactPrimaryGroupV1` 恰为 `members`；members
按 `(role,mediaType,ArtifactDeployability rank)` 唯一升序。`ArtifactEncoding.schema` 固定为
`proof-forge.artifact-encoding.v1`，wire object 恰为
`schema,encodingRules,primaryGroups,auxiliary`；rules 按 SemanticRuleRef key、auxiliary 按 role-spec
key、primary groups 按其完整 member-key vector 唯一升序。auxiliary 不得与任何 primary member
exact 重复；全部 object 拒绝 unknown/缺失字段。它不另带自引用 digest，而是完整嵌入并由
CodegenProfile digest 递归承诺。

一个 OutputSet 只有在至少完整满足一个 `primaryGroups` alternative（该组每个 role-spec 至少有一份
非空 artifact），且每份 artifact exact 匹配任一已声明 primary member 或 `auxiliary` 时才完整；
同时输出多个 alternative 的合法 primary member 允许。primary 表示 profile 输出完整性，不提升
`ArtifactDeployability`，因此 intermediate-only primary 仍不可部署。

`CodegenProfileV1.schema` 固定为 `proof-forge.codegen-profile.v1`，profile digest 为
`SHA-256("proof-forge.codegen-profile.v1" || 0x00 || JCS(profile))`。
profile wire object 恰好为
`schema,id,targetSemantics,compilerToolchain,loweringVersion,abiEncoding,artifactEncoding,`
`securityContract,minimumEvidence`；`securityContract` 字段始终存在，`none` wire 为 `null`，`some`
wire 为 SPEC-COMMON-001 exact `ContentRef`。
`abiEncoding` 恰好为 `implements,encodingRules`，encoding rules 按 SemanticRuleRef canonical key
排序并拒绝 duplicate。
`abiEncoding.implements` 必须与 target payload 的 `abiSemantics` exact 相等；
`encodingRules` 也必须 exact resolve。Codegen 可以改变非语义 optimization、emitter、toolchain
或 artifact bytes，但任何改变 fork/resource/failure/ABI 意义的参数必须先生成新
`TargetSemanticsV1` identity，不得由 CodegenProfile 覆盖。

不产生 circuit executable、witness、proof、verification key 或 verification result 的 profile，
其 `securityContract` 必须为 `null`；任何产生其中一类制品的 profile 必须为 `some`，并 exact resolve 到
[`SPEC-SEC-001`](security.md) 的 `ZkBackendSecurityProfileV1`。security payload 不能反向包含
CodegenProfile/Build digest；candidate-specific `ZkSecurityApprovalV1` 另行绑定完整
`CandidateIdentity + BuildIdentity + security-profile digest`，从而没有 hash cycle。缺失、wrong schema/
target/digest、未批准、过期或撤销均 fail closed。

`BuildIdentity` 的五个 wire 字段为
`targetId,targetSemanticsVersion,targetSemanticsDigest,codegenProfileId,codegenProfileDigest`。
`TargetSemanticIdentity` wire object 恰为 `targetId,semanticsVersion,semanticsDigest`，但嵌入
`BuildIdentity` 时必须 flatten 成上述前三个命名，禁止同时接受 nested alternate form。完整
BuildIdentity canonical key 按这五个字段各自 canonical bytes 比较。

`ChainIdentity` wire object 恰为 `namespace,reference`；namespace 使用 TargetId grammar，reference
是 1..128-byte ASCII `[A-Za-z0-9][A-Za-z0-9._-]*`，两者 exact、case-sensitive。`EndpointTransport`
wire enum/rank 为 `http < https < ws < wss`；`Endpoint` wire object 恰为
`priority,transport,authority,path`。authority 使用 lowercase DNS/IPv4/`localhost` 或 bracketed
RFC 5952 IPv6，可带非默认 decimal port；禁止 userinfo。path 必须是以 `/` 开头的 RFC 3986 ASCII
path，percent escape 使用 uppercase hex，禁止 query、fragment、NUL 和 secret placeholder。
formal public network 只允许 `https`/`wss`；`http`/`ws` 只允许 local loopback profile。

`FeePolicyKind` wire enum/rank 为 `metered < fixed < sponsored < none`；`FeePolicy` wire object 恰为
`kind,rules`。除 `none` 可为空外，rules 必须 nonempty。`DeploymentEnvironment` wire enum/rank 为
`local < public-testnet < production`；`UpgradeModel` 为
`immutable < signer-authority < governance < controller < external`。`DeployPolicy` wire object 恰为
`environment,upgradeModel,confirmationRule,policyRules`。fee/deploy rule arrays 均按
SemanticRuleRef key 唯一升序；这些 rule 必须 exact resolve，不能从 endpoint 或 chain label 推导。

`NetworkProfileV1.schema` 固定为 `proof-forge.network-profile.v1`，wire object 恰为
`schema,id,chainIdentity,genesisDigest,endpoints,feePolicy,deployPolicy,compatibleBuilds`。endpoints
必须按 priority `0..n-1` 连续排列，从而 failover 顺序既有语义又 canonical，并拒绝 duplicate；
compatible builds 按完整
BuildIdentity 唯一升序。network profile digest 唯一为
`SHA-256("proof-forge.network-profile.v1" || 0x00 || JCS(profile))`；
`NetworkProfileIdentity` wire object 恰为 `id,digest`，只能从 payload 的 ID 和该 digest 派生；
payload 不得包含自引用 digest，consumer 必须先 resolve/recompute profile 再构造 identity。

deploy/verify 先 exact resolve `NetworkProfileIdentity`，再以 manifest 中完整
`BuildIdentity` 做 `compatibleBuilds` membership join。部分匹配、只匹配 ID 或从 endpoint/default
推导任何字段均拒绝；deploy receipt 记录 network ID/digest 和 BuildIdentity。

## Acceptance profile 与动态 maturity

```lean
inductive AcceptanceRequirement
  | specification (documentId : String) (contentDigest : Digest) (requiredStatus : DocumentStatus)
  | formalGate (gateId : String) (catalogVersion : SemVer) (catalogDigest : Digest)
      (builds : NonEmptyArray BuildIdentity)

structure AcceptanceStageV1 where
  stage        : TargetMaturity
  requirements : Array AcceptanceRequirement

structure AcceptanceProfileV1 where
  schema          : SchemaId
  id              : AcceptanceProfileId
  version         : SemVer
  targetSemantics : TargetSemanticIdentity
  stages          : NonEmptyArray AcceptanceStageV1

structure MaturitySnapshot where
  schema            : SchemaId
  candidate         : CandidateIdentity
  targetSemantics   : TargetSemanticIdentity
  acceptanceProfile : AcceptanceProfileRef
  builds            : Array BuildIdentity
  stage             : TargetMaturity
  staticInputs      : Array Digest
  bindingRefs       : Array FinalizationRef
  evaluatedAt       : UtcInstant
  expiresAt         : UtcInstant
  revocationLedgerDigest : Digest
  evaluatorDigest   : Digest
```

`AcceptanceProfileV1.schema` 固定为 `proof-forge.acceptance-profile.v1`；profile digest 为
`SHA-256("proof-forge.acceptance-profile.v1" || 0x00 || JCS(profile))`。`stages` 必须恰好
按顺序包含六个 canonical `TargetMaturity` 值，不得重复、缺失或跳级；后一阶段的
求值累积前面全部 requirement。`research` 和 `specified` 只能由 exact content-digest-bound
research/decision-complete dossier requirement 支持；`prototype` 及以上的每一阶段至少有一个
`formalGate`。
该 wire object 恰好为 `schema,id,version,targetSemantics,stages`；`AcceptanceStageV1` 恰为
`stage,requirements`。`AcceptanceRequirement` 使用以下 exact tagged union，不接受省略 kind、别名或
额外字段：

```text
{kind:"specification",documentId,contentDigest,requiredStatus}
{kind:"formal-gate",gateId,catalogVersion,catalogDigest,builds}
```

variant rank 固定为 `specification=0`、`formal-gate=1`；`documentId` 必须 exact 匹配
[`TRACE-ID-001`](../traceability/id-schema.md) primary document ID（包括 `REL-<SemVer>` 特例），
`gateId` 是 1..127-byte lowercase kebab ASCII
`[a-z][a-z0-9]*(?:-[a-z0-9]+)*`。每个 stage 内 requirement 按
`(variant rank,documentId|gateId UTF-8,contentDigest|catalogDigest raw bytes,requiredStatus rank|`
`catalogVersion UTF-8,build vector)` 唯一升序，formal gate 的 builds 按完整 BuildIdentity 唯一
升序。`DocumentStatus` wire/authority 是 SPEC-COMMON-001/DOC-STATUS；所有 stage/object 均拒绝
duplicate、unknown 和缺失字段。

`AcceptanceProfileRef` wire object 恰为 `id,version,digest`，其 digest 必须由同 ID/version 的完整
AcceptanceProfileV1 payload 重算。`TargetDescriptor` 内的 ref、`MaturitySnapshot` 内的 ref 与
registration 嵌入 payload 必须 exact 相等，不能只比较 ID。

evaluator 从 `research` 开始顺序求值：specification requirement 必须匹配 exact 文档
digest/status；formal gate 必须由 gate-catalog finalizer 产生并完整绑定 current
candidate、target semantics、codegen ID/digest、gate catalog/version/digest、freshness 和 revocation。
任一 requirement 失败就停在前一连续阶段。development/alpha EV、手写 badge、文档中的
EV 字符串和跨 profile 证据都不是 formal binding。
`MaturitySnapshot.schema` 固定为 `proof-forge.maturity-snapshot.v1`，wire object 恰为
`schema,candidate,targetSemantics,acceptanceProfile,builds,stage,staticInputs,bindingRefs,`
`evaluatedAt,expiresAt,revocationLedgerDigest,evaluatorDigest`。builds 按 BuildIdentity、
static inputs 按 digest、binding refs 按 `(schema,id,digest)` 唯一升序；`candidate` 和
`FinalizationRef` 的 authority 为 SPEC-CAP-001。snapshot digest 唯一为
`SHA-256("proof-forge.maturity-snapshot.v1" || 0x00 || JCS(snapshot))`。
`prototype` 及以上 snapshot 的 `builds` 和 `bindingRefs` 必须 nonempty，并与实际满足的
累积 formal-gate binding exact 一致；`revocationLedgerDigest` 必须来自同一次评估的完整
snapshot，并 exact 等于所有 resolved formal finalization record 的同一 typed
`revocationLedger.digest`；不同 ref 指向不同 ledger 时聚合失败，不得留空或事后替换。

`evaluatedAt < expiresAt`；snapshot consumer 必须在受信 UTC clock 下检查 freshness。snapshot
不带 registry/profile 自报状态：staticInputs 必须包含本次实际读取的 registry、acceptance profile、
gate catalog、revocation ledger 等全部 canonical digest，且 evaluatorDigest 必须 resolve 到 exact
evaluator implementation payload。

`MaturitySnapshot` 是 evaluator 的带时效派生报告，不存入 `TargetDescriptor`、不进入静态
registry hash，也不参与 build/deploy 授权。是否允许 build 只由实现存在、exact
`SupportClaim` resolution 和 profile minimum evidence 决定。

`family/view label` 可从 semantics payload 生成文档视图，但不存在参与 dispatch 的单一
family 字段。Registry 是 compile-time static array，其 canonical payload 固定为：

```lean
structure TargetRegistration where
  descriptor        : TargetDescriptor
  codegenProfiles   : Array CodegenProfileV1
  acceptanceProfile : AcceptanceProfileV1

structure TargetRegistryV1 where
  schema        : SchemaId
  registrations : Array TargetRegistration
```

`TargetRegistryV1.schema` 固定为 `proof-forge.target-registry.v1`；registrations 按
TargetId、codegen profiles 按 profile ID 唯一升序。创建时检查全部 target/profile/key
唯一，重算 target semantics、codegen 与 acceptance profile digest，并要求 descriptor
的 profile ID/ref 与嵌入 payload exact 一致。canonical `registryDigest` 唯一为
`SHA-256("proof-forge.target-registry.v1" || 0x00 || JCS(registry))`；dynamic maturity、
network profile、display-order view 和当前时间不进入该 digest。

`TargetRegistration` wire object 恰为 `descriptor,codegenProfiles,acceptanceProfile`；
`TargetRegistryV1` 恰为 `schema,registrations`。`TargetDescriptor.displayName` 是 1..127-byte NFC
display string；`defaultCodegen` 字段始终存在并按 SPEC-COMMON-001 编码为 profile ID 或 `null`。
descriptor/codegen/acceptance/registration/registry 全部拒绝 unknown 或缺失字段。任何 nested ref
不能作为 digest oracle：validator 必须先重算/resolve nested payload，再重算 enclosing profile 和
registry digest。

## Initial Registry

| TargetId | Default CodegenProfileId | AcceptanceProfileId | Phase 1 | Static dossier ceiling | Descriptor 摘要 |
|---|---|---|---|---|---|
| `evm` | `evm-yul-solc-0.8.34-v1` | `phase1.evm-u64.v1` | implement | `specified` | bytecode/EVM/storage/sync call/transaction commit/no proof/EVM settlement |
| `solana` | `solana-sbpf-plan-v1` | `phase1.solana-u64.v1` | implement | `specified` | non-executable plan/SVM/explicit accounts+CPI/transaction commit/Solana settlement |
| `near` | `near-wasm-raw-u64-v1` | `phase1.near-u64.v1` | implement | `specified` | Wasm/NEAR host/KV/receipt-local commit/Promise/NEAR settlement |
| `noir` | `noir-source-u64-relations-v1` | `phase1.noir-u64-private-sum.v1` | implement | `specified` | source relation/external state/no proof backend/external verifier |
| `cosmwasm` | — | `research.cosmwasm.v1` | design | `research` | Wasm/CosmWasm host/KV/submessage+reply/Cosmos settlement |
| `soroban` | — | `research.soroban.v1` | design | `research` | Wasm/Soroban host/TTL storage/auth tree/Stellar settlement |
| `icp` | — | `research.icp.v1` | design | `research` | Wasm/canister actor/stable memory/await commit/ICP settlement |
| `openvm` | — | `research.openvm.v1` | design | `research` | RV32IM guest/zkVM proof/external verifier |
| `aleo` | — | `research.aleo.v1` | design | `research` | Aleo Instructions/records+mappings/private+final/Aleo settlement |
| `psy` | — | `research.psy.v1` | design | `research` | DPN/user-partitioned state/recursive proof/Psy settlement |

初始/保留 profile 的 artifact completeness 与 ZK security contract 约束固定如下；每个 cell 表示
`ArtifactEncoding.primaryGroups` 的 alternative group，role 后是 exact media type：

| CodegenProfileId | Primary group alternatives | Group deployability | `securityContract` |
|---|---|---|---|
| `evm-yul-solc-0.8.34-v1` | `{deploy-bytecode: application/vnd.proof-forge.evm-bytecode}` **or** `{runtime-bytecode: application/vnd.proof-forge.evm-bytecode}` | `deployable` | `null` |
| `solana-sbpf-plan-v1` | `{sbpf-plan: application/vnd.proof-forge.sbpf-plan}` | `intermediate-only` | `null` |
| `near-wasm-raw-u64-v1` | `{contract-wasm: application/wasm}` | `deployable` | `null` |
| `noir-source-u64-relations-v1` | `{noir-source-package: application/vnd.proof-forge.noir-package}` | `intermediate-only` | `null` |
| reserved `solana-sbpf-elf-v1` | `{program-elf: application/vnd.proof-forge.solana-sbpf-elf}` | `deployable` | `null` |
| reserved `noir-acir-proof-v1` | `{circuit: application/vnd.proof-forge.noir-acir, verification-key: application/vnd.proof-forge.verification-key}` | `verifiable-workload` | required exact `ZkBackendSecurityProfileV1` ref |

表中 `or` 是两个 canonical single-member group；逗号分隔的 Noir successor 是一个必须整体满足的
two-member group。当前 Solana plan 与 Noir source package 因而可以产生 schema-valid、完整但诚实的
OutputSet；primary 只表示该 immutable profile 的主要交付物，绝不把它们提升为 ELF/circuit/proof。
future OpenVM/Aleo/Psy 等任何 proof-producing profile 同样必须 `securityContract=some`，不能凭 target
类别豁免。

上表是人类可读摘要，简写了 AcceptanceProfile ID；serialized descriptor 仍必须存储
exact `AcceptanceProfileRef(id,version,digest)`。该列只是静态 dossier 所允许的上限，不是
`MaturitySnapshot`；当前没有 candidate-bound evaluator output。Phase 1 四项的 `specified`
只表示 decision-complete dossier 输入；已有 development EV 不进入 authoritative evaluator，
因此未来 snapshot 在 formal binding 之前不得提升到 `prototype`、`artifact_validated`
或 `local_runtime`。

`solana-sbpf-plan-v1` 与 `noir-source-u64-relations-v1` 是 immutable alpha/intermediate
profiles；它们永远不得在原 ID/digest 下升级为 executable/proof profile。Phase 1 DoD
分别要求 `TASK-D5-04` 新建 `solana-sbpf-elf-v1`、`TASK-D7-04` 新建
`noir-acir-proof-v1`，锁定 exact toolchain closure/ABI encoding/minimum evidence 并生成新
profile digest。两个 ID 在相应任务前只是 reserved，不得放入 static registry 或用于
build。只有新 profile 的 formal artifact/proof gate 和 acceptance binding 通过后，新的
registry payload/version 才可将 default 切换到它；Phase 1 release 在两项切换前 fail closed。

Design-only entries可出现在 `list-targets --all`，但 `build` 必须返回
`PF-TARGET-NOT-IMPLEMENTED`；默认 `list-targets` 只列有实现且达到 profile 最低 evidence
的 entries。

## Lookup API

```lean
def TargetRegistry.create : Array TargetRegistration → Except RegistryError TargetRegistry
def TargetRegistry.resolveTarget : TargetId → Except Diagnostic TargetRegistration
def TargetRegistration.resolveCodegen : CodegenProfileId → Except Diagnostic CodegenProfileV1
def NetworkRegistry.resolve : NetworkProfileId →
  Except Diagnostic (NetworkProfileV1 × NetworkProfileIdentity)
```

lookup exact、case-sensitive，不接受 alias。默认 profile 只在用户未给 `--profile` 且
target registration 明确唯一 default 时使用；design-only target 的 profile array 为空且 default
为 none。`--network` 对 build 是 CLI 错误。Network compatibility 只接受 exact `BuildIdentity`；
unknown、missing、digest mismatch 或只匹配 TargetId 均拒绝。

## 错误、边界与安全

`PF-TARGET-UNKNOWN`、`PF-TARGET-NOT-IMPLEMENTED`、`PF-PROFILE-UNKNOWN`、
`PF-REGISTRY-DUPLICATE`、`PF-REGISTRY-INVALID`。覆盖空 registry、duplicate target/profile/
claim、大小写、Unicode、过长 ID、无 default/多 default、profile 属于另一 target、design-only
build、unknown network、network 用于 build、descriptor 缺轴、semantic rule/target semantics/codegen/
acceptance profile digest mismatch、ABI implements mismatch、network partial/exact compatibility、
forged/missing/stale/revoked/cross-target maturity EV、development EV promotion、snapshot 混入 registry hash、
support claim 排序、registry hash 决定性、恶意动态配置。Registry 不从 cwd、环境、网络或用户文件加载 executable
plugin；可选 JSON 只允许选择已编译 profile，不可新增代码。

## 验收

关联 `FR-005/008`、`TST-REG-001/002`。输出 target list 与 registry canonical hash；
重排源 registration 不改变 hash；所有 design-only target honest reject。
