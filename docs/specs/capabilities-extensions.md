---
id: SPEC-CAP-001
title: Requirements、Capabilities 与 Extensions
status: proposed
owner: architecture
updated: 2026-07-16
normative: true
---

# Requirements、Capabilities 与 Extensions

## 身份与 schema

```lean
structure RequirementId where value : String

structure RequirementKey where
  id      : RequirementId
  version : SemVer
  digest  : Digest

inductive SupportPredicate
  | uintAtLeast  (name : String) (value : UInt64)
  | uintAtMost   (name : String) (value : UInt64)
  | boolEquals   (name : String) (value : Bool)
  | enumContains (name : String) (values : NonEmptyArray String)
  | digestEquals (name : String) (value : Digest)

inductive SupportEvidenceGrade
  | specified | artifactValidated | localRuntime | networkOrProofValidated

structure RequirementRef where
  id      : RequirementId
  version : SemVer
  digest  : Digest
  predicates : Array SupportPredicate

-- Static target-level declaration carried by the descriptor for one exact
-- TargetSemanticIdentity. It never carries profile evidence.
structure SupportClaim where
  requirement : RequirementKey -- id + exact version + digest
  predicates  : Array SupportPredicate

structure CandidateIdentity where
  commit        : GitObjectId
  treeObjectId  : GitObjectId
  archiveDigest : Digest
  digest         : Digest

structure FinalizationId where value : String

structure EvidenceRef where
  id     : EvidenceId
  digest : Digest

structure FinalizationRef where
  schema : SchemaId
  id     : FinalizationId
  digest : Digest

structure SupportBindingRef where
  evidence     : EvidenceRef
  finalization : FinalizationRef
  requirement  : RequirementKey
  claimDigest  : Digest
  digest       : Digest

-- Profile-specific index, keyed by the selected exact build identity.
structure ProfileSupportBindings where
  build       : BuildIdentity
  requirement : RequirementKey
  claimDigest : Digest
  bindings    : Array SupportBindingRef

structure ProfileSupportIndex where
  schema    : SchemaId
  candidate : CandidateIdentity
  records   : Array ProfileSupportBindings

structure SupportEvidenceBinding where
  schema                 : SchemaId
  evidence               : EvidenceRef
  finalization           : FinalizationRef
  candidate              : CandidateIdentity
  build                  : BuildIdentity
  requirement            : RequirementKey
  claimDigest            : Digest
  achieved               : SupportEvidenceGrade
  finalizedAt            : UtcInstant
  expiresAt              : UtcInstant
  revocationLedgerDigest : Digest

structure ResolvedSupportDecision where
  request     : RequirementRef
  claim       : SupportClaim
  claimDigest : Digest
  build       : BuildIdentity
  achieved    : SupportEvidenceGrade
  bindings    : Array SupportBindingRef

structure SupportDecisionSet where
  schema    : SchemaId
  candidate : CandidateIdentity
  build     : BuildIdentity
  minimum   : SupportEvidenceGrade
  decisions : Array ResolvedSupportDecision
```

`GitObjectId`、raw evidence object 与 revocation ledger 的语法/内容 authority 是
[`TRACE-EV-001`](../traceability/evidence-schema.md)；`TargetSemanticIdentity`、`BuildIdentity`、
CodegenProfile digest 和 registry digest 的 authority 是 [`SPEC-REG-001`](target-registry.md)。
本规格只消费这些 exact identity，禁止从 target/profile 字符串或当前 default 重算替代值。

`RequirementId` 使用 1..127-byte lowercase dotted ASCII；每个 segment 使用
`[a-z][a-z0-9]*(?:-[a-z0-9]+)*`，至少两个 segment。`RequirementKey` wire object 恰为
`id,version,digest`，canonical key 是 `(id UTF-8,完整 SemVer UTF-8,digest raw bytes)`；其 digest
必须 exact resolve 到静态 requirement-semantics registry 的同一 ID/version payload，unknown、
same-version/different-digest 或 payload mismatch 均 fail closed。

`SupportPredicate` 使用带 tag 的 exact wire union，variant rank 与字段固定为：

| Rank | Wire object | Claim implication |
|---:|---|---|
| 0 | `{kind:"uint-at-least",name,value}` | requested value 必须 `>=` claim value |
| 1 | `{kind:"uint-at-most",name,value}` | requested value 必须 `<=` claim value |
| 2 | `{kind:"bool-equals",name,value}` | requested value 必须 exact 相等 |
| 3 | `{kind:"enum-contains",name,values}` | requested set 必须是 claim set 的子集 |
| 4 | `{kind:"digest-equals",name,value}` | requested digest 必须 exact 相等 |

`name` 使用 RequirementId segment grammar、长度 1..127 bytes；enum value 是 1..127-byte NFC
string，按 UTF-8 唯一升序。predicate array 按 `(name UTF-8,variant rank,JCS(predicate))` 唯一
升序；同一 `(name,variant)` 的重复为 `PF-REQ-CONFLICT`。同名 `uint-at-least + uint-at-most`
仅在 lower `<=` upper 时构成 closed interval，其他跨 variant 同名组合不可比较并返回
`PF-REQ-CONFLICT`。`SupportEvidenceGrade` 的唯一 wire enum 与全序是
`specified < artifact_validated < local_runtime < network_or_proof_validated`；unknown spelling
拒绝，且不得与 TargetMaturity 或 evidence-ledger qualification 比较。

claim implication 的 lookup 也是 closed：request 与 claim 的 `(name,variant rank)` key 集必须 exact
相等，再对每个 key 按上表比较 value。missing/extra/variant substitution 一律
`PF-REQ-PRECONDITION`；empty claim 只可匹配 empty request，不能隐式表示 wildcard/unbounded support。
Requirement-semantics registry 的 exact payload 决定某个参数使用 at-least、at-most 或二者组成 closed
interval；resolver 不重命名 variant，也不从数值猜另一种表示。

`RequirementRef` wire object 恰为 `id,version,digest,predicates`；predicates 是程序实际
推导并按上表归并/排序后的 requested payload。source origin 不属于 requirement 语义，也不进入
`RequirementRef` 或 `semanticHash`；D2 必须把 canonical requirement index 的 nonempty origins 写入
`SPEC-SEM-WIRE-001` 的 `SemanticProvenanceV1.originMap`。`SupportClaim` wire object 恰为
`requirement,predicates`，predicates 是 target 对 request
施加的 accepted-range preconditions，同样按上表排序。所有本节 object/variant 都拒绝 unknown 或
缺失字段；empty predicate array 合法。

完整 claim 的 content digest 唯一为：

```text
claimDigest = SHA-256("pf.support-claim.v1" || NUL || JCS(SupportClaim))
```

任何 profile binding/evidence 不能只绑定 RequirementKey；它还必须绑定 exact `claimDigest`，否则
同一 requirement version 下不同 accepted bounds 会错误复用证据。

`SupportClaim` 只声明 `TargetDescriptor` 所引用的 exact target semantic identity 对
requirement/predicate 的静态支持，不带 evidence grade 或 EV 引用，也不伪装成
`TargetSemanticsV1` payload 字段。`ProfileSupportIndex` 是 release 随 candidate 发布的
独立、content-addressed evidence-set
成员，不嵌入会被它验证的 compiler/TargetDescriptor，也不从 cwd 或网络发现；resolver context 必须由
已验证的 candidate evidence-set 注入。`ProfileSupportBindings` 属于 selected `BuildIdentity`；同一
`(BuildIdentity, RequirementKey, claimDigest)` 最多一项，且同一 build/requirement 不得出现第二个
claim digest，不能把 profile A 或旧 registry claim 的 binding 用于 profile B/新 claim。
`bindings=[]` 只支持 `specified`；更高等级必须有 nonempty formal binding。binding refs 按
`(evidence.id,evidence.digest,finalization.schema,finalization.id,finalization.digest,requirement,claimDigest,digest)` 的 canonical
key 唯一升序。文档中的 EV 文字、development ledger 行或 target-level claim 不会被 resolver
自动信任。

`ProfileSupportIndex.schema` 固定为 `proof-forge.profile-support-index.v1`，wire object 恰为
`schema,candidate,records`；每个 record 恰为 `build,requirement,claimDigest,bindings`。records 按
`(BuildIdentity,RequirementKey,claimDigest)` 唯一升序，bindings 按上述 key 唯一升序。index digest
唯一为
`SHA-256("pf.profile-support-index.v1" || NUL || JCS(ProfileSupportIndex))`；resolver 必须
从 evidence-set manifest 获得并重算该 digest，不得接受没有 schema/digest binding 的内存 map。

```lean
def EvidenceResolver.resolveSupport
  (candidate : CandidateIdentity)
  (build : BuildIdentity)
  (index : ProfileSupportIndex)
  (staticClaims : Array SupportClaim)
  (request : RequirementRef)
  (minimum : SupportEvidenceGrade)
  : Except Diagnostic ResolvedSupportDecision
```

resolver 先以 `request.(id,version,digest)` 在 selected descriptor 的 canonical `staticClaims` 做唯一
exact lookup，重算 claimDigest，并先 exact 比较 predicate key 集，再逐项验证 claim predicates imply
request predicates；missing/
incomparable/out-of-range 按 Support Resolution 返回稳定错误。随后只用
`(build,request key,claimDigest)` exact lookup `ProfileSupportBindings`，再对每个 ref safe-read immutable
binding/evidence/finalization，验证 candidate、完整 BuildIdentity、exact requirement/claimDigest、
achieved grade、freshness 和 revocation。任一字段缺失、digest mismatch、跨 target/profile/
requirement/claim、过期或撤销都返回 `PF-EVIDENCE-BINDING`，不得取同 target 的其他 profile/EV 补足。
无 binding 时 achieved grade 恰为 `specified`；否则为全部 required binding/vector 的最低等级。
低于 `minimum` 返回 `PF-REQ-EVIDENCE`。`ResolvedSupportDecision` 保留 canonical request、exact claim/
claimDigest、selected BuildIdentity、achieved grade 与完整 `SupportBindingRef` 集合。

`CandidateIdentity.digest` 固定为：

```text
SHA-256("pf.candidate-identity.v1" || NUL ||
  JCS({commit, treeObjectId, archiveDigest}))
```

candidate wire object 恰为 `commit,treeObjectId,archiveDigest,digest`；consumer 必须先重算
digest 再构造 typed value。`FinalizationId` 只接受
`EVF-[0-9]{8}-[0-9]{4}` 且日期必须是真实 Gregorian UTC date。
`EvidenceRef` wire object 恰为 `id,digest`；`FinalizationRef` 恰为 `schema,id,digest`，
不允许用裸 ID 替代。support/acceptance binding 只接受
`schema="proof-forge.formal-evidence-finalization.v1"`；development ref 只可用于开发报告。
`SupportBindingRef` wire object 恰为 `evidence,finalization,requirement,claimDigest,digest`；
`ProfileSupportBindings` 恰为 `build,requirement,claimDigest,bindings`；
`ResolvedSupportDecision` 恰为 `request,claim,claimDigest,build,achieved,bindings`。所有这些 object
均拒绝 unknown/缺失字段。

`SupportEvidenceBinding` 的 wire object 固定为
`proof-forge.support-evidence-binding.v1`，字段恰为 `schema`、
`evidence{id,digest}`、`finalization{schema,id,digest}`、
`candidate{commit,treeObjectId,archiveDigest,digest}`、`build`、`requirement`、`claimDigest`、`achieved`、
`finalizedAt`、`expiresAt`、`revocationLedgerDigest`；typed 与 wire 字段一一对应。
`EvidenceRef.digest` 是 exact canonical EV bytes 的 SHA-256，`FinalizationRef.digest` 按
[`SPEC-EVFINAL-001`](gate-catalog-finalization.md) 的 finalization domain 计算；所有 `Digest` wire value
均使用 SPEC-COMMON-001 的 `sha256:<64 lowercase hex>`。`revocationLedgerDigest` 必须 exact 等于
resolved formal finalization record 的 typed `revocationLedger.digest`，不得由 binding caller 另选
ledger、schema 或裸 hash。

`SupportBindingRef.digest` 固定为：

```text
SHA-256("pf.support-evidence-binding.v1" || NUL ||
  JCS(SupportEvidenceBinding))
```

ref 中 evidence/finalization/requirement/claimDigest 必须与 binding body exact 相等；这样一份 EV 可为多个
requirement 生成不同 binding，而不会因只按 EV ID lookup 发生歧义。只有未来 formal gate-catalog
finalizer 可从 captured immutable evidence、formal finalization snapshot、freshness authority 和完整
revocation ledger 生成 binding。当前 development finalizer 必须拒绝该输出，普通 build、registry
JSON 或手写文档均不能生成可信 binding。

OutputSet 的 `support-decisions.json` wire object 固定为 `proof-forge.support-decisions.v1`，字段恰为
`schema`、`candidate`、`build`、`minimum`、`decisions`；每个 decision 字段恰为
`request,claim,claimDigest,build,achieved,bindings`。decisions 按 request RequirementKey 唯一升序，
所有 decision.build 必须等于 root build，binding refs 使用上文 canonical order；request/claim 的
predicates 也必须为 canonical order。决策集合必须与本次 canonical `ProgramRequirements` exact
相等，不得缺项、加项或重复；descriptor 中未被程序请求的 static claim 不进入 decisions。每个
decision.claim 必须是 selected descriptor 的 exact lookup，claimDigest 必须重算匹配，claim predicates
必须 imply request predicates。其 digest authority 属于本规格：

```text
SHA-256("pf.support-decisions.v1" || NUL || JCS(support-decisions.json))
```

manifest 只按 SPEC-OUT-001 复制该 digest/path，不能删减 decisions 或把未验证 binding 改写成更高
grade。

ID 为小写 dotted ASCII，如 `state.map`、`failure.atomic-revert`；version 使用完整 SemVer，
解析后 exact equality，不接受范围、latest 或通配符。digest 是
`sha256:<64 lowercase hex>`，覆盖规范化语义定义而非实现代码。

## Requirement 域

- `value.*`：width、checked overflow、Field、Bytes、Principal。
- `control.*`：loop bound、call depth、recursion、allocation。
- `state.*`：cell/map/vector、atomic commit、continuity。
- `effect.*`：event、sync call、async workflow、protocol call。
- `context.*`：caller、authorizers、time、randomness。
- `disclosure.*`：verifier visible、prover witness、commitment only。
- `authority.*`：caller/signer/auth tree/record owner。
- `state-custody.*`：program/account/user/record/external continuity。
- `failure.*`：revert/trap/external failure/commit boundary。
- `extension.*`：target/ecosystem-specific typed semantics。

## 推导

每个 typed operation 通过静态 table 贡献 requirements；复合节点取 key union，分别合并 semantic
predicate 与 provenance origin。参数化 requirement（width、bound、max bytes）使用 predicate payload，而不是动态
拼接 ID。相同 RequirementKey 先按 predicate name/variant 归并：`uint-at-least` 取最大 value、
`uint-at-most` 取最小 value、`enum-contains` 取 canonical union，`bool-equals`/`digest-equals` 只允许
exact 相等；随后验证同名 at-least/at-most 的 lower `<=` upper。其他跨 variant 同名组合或
bool/digest 不等均为 `PF-REQ-CONFLICT`。归并后每个 `(name,variant)` 只保留一项，再按本规格
canonical order 输出 `ProgramRequirementsV1`；同一过程把每个 canonical requirement index 的
origins 按 SPEC-COMMON-001 key 唯一升序写入 companion provenance。两份输出均与 source item/hash-map
顺序无关且幂等，但只有前者进入 `SemanticProgramV1` canonical bytes。

## Support Resolution

```text
for request in canonical ProgramRequirements:
  claim := exact lookup(selected descriptor, request.id, request.version, request.digest)
  if missing: reject PF-REQ-UNSUPPORTED
  claimDigest := recompute full SupportClaim
  if claim.predicates do not imply request.predicates: PF-REQ-PRECONDITION
  bindings := exact lookup(selected BuildIdentity, request key, claimDigest)
  achieved := verify candidate/profile bindings, freshness and revocation
  if achieved < requested minimum: PF-REQ-EVIDENCE
if any rejection: return sorted DiagnosticBundle
else: construct ResolvedProgram target with immutable decisions
```

禁止 alias、nearest version、目标 fallback、best effort 或 evidence 自动降级。

## Extensions

用户只可用顶层：

```lean
requires extension near.promise version "1.0.0"
  digest "sha256:..."
```

extension 注册 typed syntax/operation、type/effect/requirement rules 和 target support claims；
不能注入任意 elaborator callback、文件 I/O 或动态 native code。未声明 extension syntax 为
`PF-EXT-001`，版本/digest 不符为 `PF-EXTENSION-VERSION`。使用 extension 不改变 DSL
入口，只使不支持它的 targets 精确拒绝。

## SupportEvidenceGrade

wire form 与顺序由“身份与 schema”一节唯一冻结为
`specified < artifact_validated < local_runtime < network_or_proof_validated`。
target-level claim 本身只建立 `specified`；只有 selected BuildIdentity 的 verified formal bindings
可以提升 grade，文档/父项目实现不能提升 V2 evidence。build 的
默认 minimum 是 profile 声明值，CLI 可要求更高但不可降低 profile 的安全下限。
这个枚举只表示 target support claim 的行为证据成熟度，与 Evidence Ledger
用于 task closure 的 `development | bootstrap | formal` qualification 是两个不同命名空间。

## 版本与边界

语义改变必须新 version+digest；只增加或移动 source locator 不改变 key、ProgramRequirements 或
`semanticHash`，但必须改变 companion provenance digest。覆盖 duplicate key、
unknown ID、malformed SemVer/digest、same version different digest、predicate exact/equal/
just-over limit、incomparable predicate、origin merge/order、zero requirements、extension
未声明/重复/冲突、duplicate profile binding set、wrong candidate/build/requirement/ref digest、
development finalization、stale/revoked binding、evidence 不足、registry target 不存在、resolver
全部错误聚合。

## 安全与验收

registry 静态编译并有 canonical hash；不加载网络或动态插件。build pipeline 必须先 exact join
validated `SemanticProgramV1` 与 `SemanticProvenanceV1`，resolver diagnostic 再按 canonical
requirement index 带回每个 origin，且不得泄露 private literal；resolver 本身不得把 origin 当成
support 选择输入。关联 `FR-006/013`、`TST-REQ-001..003`、
`TST-XTARGET-002`；property test 证明 inference 与 source item/hash-map 顺序无关。
