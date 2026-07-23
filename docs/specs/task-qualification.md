---
id: SPEC-TASKQUAL-001
title: TaskQualificationV1 任务作用域 formal qualification
status: in_review
owner: quality
updated: 2026-07-23
normative: true
---

# SPEC-TASKQUAL-001：TaskQualificationV1

## 1. Authority、范围与公共 wire 规则

本规格是 task qualification、其 closeout receipt 及 D0-10 一次性 bridge 的完整对象 authority；
实现不得从 `ADR-0018` 或 `SPEC-EVFINAL-001` 导入对象、默认值或 verifier 行为（ADR-0018 是
accepted decision、后者是 proposed technical spec，但均不是本协议的 object-schema authority）。
本规格不增加 EV `qualification`/Ledger grade，不修改 `RequiredTestSetV1`，也不
满足 `TASK-D8-04`/`TST-ISO-003` 的 release aggregate。

全部 protocol JSON object（含 nested object）恰含所列字段，`additionalProperties=false`；字段声明
顺序即下列顺序。protocol object 输入必须是 UTF-8、无 BOM/NUL/trailing LF 的 canonical PF-JCS
bytes，拒绝 duplicate key、unknown field、alternate spelling 与 noncanonical bytes。PHASE-4/5
Markdown、freeze-package repository JSON、review report 与 closeout diff 是明确的 raw-source carrier：
consumer 对 candidate archive 中的 exact bytes 做 bounded safe-read，再按本规格对应 parser 投影；
不得要求这些 source carrier 自身是 PF-JCS，也不得由 caller 提供已解析 object。PF-JCS、`Digest`（wire 为
`sha256:<64 lowercase hex>`）、`ContentRef`、SemVer 和 safe profile ID grammar 采用
`SPEC-COMMON-001` 已冻结规则在本规格内的下列必要子集：schema 是 1..127-byte lowercase dotted
ASCII；id 是 1..127-byte `[a-z][a-z0-9]*(?:[-.][a-z0-9]+)*`；version 是 canonical SemVer；
`TASK-*` 为 `TASK-[A-Z0-9]+(?:-[A-Z0-9]+)*`，`TST-*` 同形；Git commit/tree 为 40 lowercase hex。
本规格所有 string 禁 NUL/Cc，单项最多 4096 UTF-8 bytes；argv/env value 例外上限 65536 bytes；
`TaskQualificationContentMemberV1.bytesHex` 是 §8.2 唯一大字符串例外，使用该节独立 pre-decode bound。
array 的 count 在第一次 entry decode/hash/curve work 前检查；标为集合的 array 按所述 ASCII key
严格升序且唯一，producer 不得替 consumer 排序。除 §8 的 inline-hex
`TaskQualificationContentBundleV1` 有明确 260 MiB 例外外，root canonical bytes 上限 4 MiB；array 通用上限
4096；本规格更小 bound 优先。所有 digest 形式均为
`SHA-256(ASCII(domain) || NUL || PF-JCS(value))`，除明确写 `raw bytes` 者外。

本 amendment 只有在ADR-0021、SPEC-TASKQUAL-001与PHASE-5经metadata-only commit共同恢复`accepted`且
记录Architecture + Quality + Security authorization后才生效。届时production verification与protected
acceptance的registry **只能**是current activated `BootstrapAuthorityPolicyV1` exact bytes及其
外部 expected `ContentRef`；fixture只允许§8.2独立FixturePolicyV1且永不authoritative。production仅复用
Bootstrap policy的principal/key/role registry；不得修改、扩展或用 D0-10 查询其恰含 D0-01..06 的
`taskRules`。本协议的固定 `TaskQualificationAuthorityRuleV1` 为
`requiredRoles=["architecture","quality","security"]`、`minimumDistinctSigners=3`；每个 role
必须由有效签名命中的 distinct principal 覆盖，distinctness 按 `principalId`，且 current/non-revoked。

## 2. 精确共用值对象

```text
CandidateIdentityV1 {
  commit, treeObjectId, archiveSha256: Digest
}
ContentRefV1 { schema, id, version, digest: Digest }
NormativeDocumentRefV1 {
  id, status: "accepted", contentDigest: Digest, reviewCommit
}
FixtureNormativeDocumentRefV1 {
  id, status: "accepted", contentDigest: Digest, reviewCommit
}
QualificationNormativeDocumentRefV1 = profile-discriminated
  NormativeDocumentRefV1 | FixtureNormativeDocumentRefV1
RawDocumentRefV1 { path, digest: Digest }
EvidenceRefV1 { id, digest: Digest }
ApprovalSignatureV1 { keyId, algorithm: "ed25519", signature }
IndependentReviewRefV1 {
  reviewerId, reviewerKind: "human" | "independent-ai",
  invocationId, reportDigest: Digest, reviewCommit, reviewLink,
  decision: "approved", findings: []
}
VerifierIdentityV1 {
  id, executable: ContentRefV1, closure: ContentRefV1,
  sourceDigest: Digest, buildPolicy: ContentRefV1
}
```

`CandidateIdentityV1.archiveSha256` 是 `sha256:` Digest，不是裸 hex；candidate digest domain 为
`pf.taskqual.candidate.v1`。Evidence ID 是真实日期的 `EV-[0-9]{8}-[0-9]{4}`；EvidenceRef digest
是 `SHA-256(raw canonical EV bytes)`（唯一 raw-byte exception）。signature 是 64-byte Ed25519 的
128 lowercase hex；algorithm 仅 `ed25519`。签名 key 必须 exact 命中 policy principal。reviewerId/
invocationId/keyId 使用 safe id；reviewLink 为 `https://`；reviewCommit 必须等于被审 pre-close
candidate commit；review report 是 opaque `1..1048576` bytes，reportDigest 为
`SHA-256("pf.taskqual.review-report.v1" || NUL || raw bytes)`。reviews 按 `(reviewerId,reportDigest raw)`
升序，count `1..256`；每项必须来自与实现会话不同的 bounded invocation，`invocationId` 唯一，
reviewerId 不得是 authorization signer principalId。`independent-ai` 按 accepted
`GOV-MAINTAINERS-001` 的 AI 复审条款认证：immutable report bytes、provider invocation ID 与
thread/tool reviewLink 由 authorization signatures 一并绑定；它不冒充第二位人类或第二个 authority
principal。findings 必须为空，任何 P0/P1（含 unresolved token）拒绝。VerifierIdentity digest domain 为
`pf.taskqual.verifier-identity.v1`。

## 3. Task row、freeze 与 command gate

```text
TaskQualificationTaskRowV1 {
  taskId, output, dependencies: [taskId],
  prerequisites: ["<document-id>@accepted"], tests: [testId],
  evidenceIds: [evidenceId], status: "in_progress"
}
TaskFreezePackageV1 {
  schemaVersion: 1, taskId, frozenAt, freezeCommit, output,
  dependencies: [taskId], prerequisites: [string], tests: [testId],
  inScope: [string], outOfScope: [string], doneWhen: [string],
  overflowPolicy, maxCalendarDays, maxCommits, notes
}
TaskFreezePackageRefV1 { taskId, digest: Digest }
TaskCommandPolicyV1 {
  schema: "proof-forge.task-command-policy.v1", id, version: "1.0.0",
  taskId, testIds: [testId], argv: [string],
  environment: [{name,value}], tool: ContentRefV1,
  probe: ContentRefV1, sandboxPolicy: ContentRefV1,
  verifier: VerifierIdentityV1
}
TaskQualificationGateV1 {
  gateId, taskId, testIds: [testId], evidence: [EvidenceRefV1],
  commandPolicy: ContentRefV1, eligibleStage0Handoff: ContentRefV1,
  sessionContainment: ContentRefV1, freshness: ContentRefV1,
  privateScan: ContentRefV1, revocationSnapshot: ContentRefV1
}
```

Task row 由同一次 accepted PHASE-4 raw snapshot 的 canonical task table 逐字投影；output 不 trim，
各 ID list 的唯一 delimiter 是 `, `，`—` 只表示 empty。tests 非空。freeze 的 frozenAt 是真实
`YYYY-MM-DD`；freezeCommit 是 candidate 的 ancestor；in/out scope 各 `3..12`，
doneWhen `1..32`，limits 为 `1..365`/`1..10000` safe integer。
freeze 的全部字段从 candidate archive 内 complete closed repository JSON package 投影，不允许只
hash row axes；`notes` 也是签名完成面的一部分。package ref digest 是
`SHA-256("pf.task-freeze-package-source.v1" || NUL || raw repository bytes)`；taskId 与 package exact。
row 与 package 的
taskId/output/dependencies/prerequisites/tests 必须 exact equality。

command argv count `1..256`，argv[0] 是absolute canonical policy path；EV没有argv→tool identity字段，
因此executable identity只由§8.3 selected tools entry的hash join证明，不从该path推导；environment count
`0..256`，name 匹配 `[A-Za-z_][A-Za-z0-9_]{0,254}` 并按 name
升序；它是完整 `env-i` environment，不继承 ambient 值。tool/probe/sandboxPolicy/verifier 均须
resolve、safe-read并重算。command policy digest domain `pf.task-command-policy.v1`。gateId safe-id；
gate 按 gateId 排序，evidence 按 id 排序。每个 raw EV 必须 canonical、passed、
`qualification="formal"`，candidate/task/gate command identity exact join；全部 gate testIds 无交叠，
其升序 union exact 等于 row.tests。handoff 必须 eligible direct handoff；containment、freshness、scan、
revocation refs 必须由 policy-pinned producer签名且在签发与 receipt 验证时 current/non-revoked。

## 4. Dependency completion（closed discriminated union）

```text
BootstrapTaskReceiptDependencyV1 {
  kind: "bootstrap-task-receipt", taskId,
  completionCommit, authorityPolicy: ContentRefV1,
  objectDigest: Digest, objectBytesHex, signatures: [ApprovalSignatureV1]
}
GovernanceBootstrapReceiptDependencyV1 {
  kind: "governance-bootstrap-receipt", taskId,
  ruling: QualificationNormativeDocumentRefV1,
  completionCommit, authorityPolicy: ContentRefV1,
  objectDigest: Digest, objectBytesHex, sourceClosureBytesHex,
  signatures: [ApprovalSignatureV1]
}
TaskQualificationDependencyV1 {
  kind: "task-qualification", taskId, completionCommit,
  authorityPolicy: ContentRefV1, receipt: TaskCompletionReceiptRefV1,
  objectDigest: Digest, objectBytesHex, signatures: [ApprovalSignatureV1]
}
DependencyCompletionRefV1 = one of the three objects above, discriminated by kind
```

`bootstrap-task-receipt` 只允许 exact D0-01..06，按该历史 receipt schema/signature domain 验证完整
object bytes；`governance-bootstrap-receipt` 只允许 `(TASK-D0-07,GOV-D0CLOSE-001)` 或
`(TASK-D0-10,GOV-TASKQUAL-BOOTSTRAP-001)`；`task-qualification` 只允许 D1..D8 并验证本规格
TaskCompletionReceiptV1。objectBytesHex 与 `sourceClosureBytesHex` 均是 nonempty lowercase even hex，分别
使用 §8.2 单 member 的 64 MiB pre-decode bound；objectBytesHex 解码后必须 canonical，
`objectDigest=SHA-256("pf.taskqual.dependency-object.v1" || NUL || raw bytes)`；typed task、policy、
ruling、签名与 raw object逐字段 exact join；wrapper.ruling与decoded completion.ruling必须是同一
profile-discriminant且逐字段exact equality，不制造Normative ContentRef/schema。`sourceClosureBytesHex`
解码 bytes 的 plain SHA-256 与 decoded completion.sourceClosure.digest exact，且 safe-read path 与
decoded completion.sourceClosure.path exact：D0-07 必须等于 candidate-external authenticated archive 中
历史 attest 的 bytes；D0-10 必须等于 candidate-external exact D0_10BootstrapReceiptV1 bytes。wrapper
因此能够在不信任 objectBytesHex 内声明的情况下验证 source closure，且两种 bytes 禁止 alias。
dependencies 按 taskId升序且exact等于row direct
dependencies（不接受 transitive substitute）。completionCommit 必须是 consuming pre-close candidate
commit 的严格 ancestor，不要求也不得等于 consuming candidate。consumer 通过 authenticated commit
graph及 revocation authority验证 current record；non-ancestor、same-candidate、superseded、revoked、
wrong task/ruling/policy/schema/signature 一律拒绝。

## 5. Qualification、签名与 refs

```text
AllowedCloseoutPatchV1 {
  schema: "proof-forge.allowed-closeout-patch.v1", id, version: "1.0.0",
  taskId, preCloseCandidate: CandidateIdentityV1,
  allowedPaths: [project-relative path], semanticFileSetDigest: Digest,
  resultingTaskRowDigest: Digest
}
SemanticCloseoutFileSetV1 {
  schema: "proof-forge.semantic-closeout-file-set.v1", id, version: "1.0.0",
  taskId, preCloseCandidate: CandidateIdentityV1,
  changes: [{path,beforeDigest: Digest|null,afterDigest: Digest|null}]
}
TaskQualificationV1 {
  schema: "proof-forge.task-qualification.v1", id, version: "1.0.0",
  taskId, preCloseCandidate: CandidateIdentityV1,
  taskRow: TaskQualificationTaskRowV1,
  freezePackage: TaskFreezePackageRefV1,
  gates: [TaskQualificationGateV1],
  dependencies: [DependencyCompletionRefV1],
  verifier: VerifierIdentityV1,
  authorityPolicy: ContentRefV1,
  allowedCloseoutPatch: ContentRefV1,
  independentReviews: [IndependentReviewRefV1],
  signatures: [ApprovalSignatureV1]
}
TaskQualificationRefV1 { taskId, id, digest: Digest }
D0_10BootstrapApprovalRefV1 { id, digest: Digest }
D0_10BootstrapReceiptRefV1 { id, digest: Digest }
```

qualification id 固定 `task-qualification-<lowercase task suffix>`。Allowed patch allowedPaths 按 UTF-8
升序，count `1..16`，只能包含 task table、Evidence ledger、checkpoint、trace/review/log 的 task-owned
closeout locations及固定 qualification/bootstrap-approval path；禁止 verifier/protocol/product/test/
freeze package。`SemanticCloseoutFileSetV1.changes` 使用 §6 file-set 同一 path/digest/null 规则，但
排除固定 Q/approval file 且不含尚未存在的 closeoutCandidate；它在签 Q/approval 前由 C archive 与
计划写入的 exact after bytes 唯一构造。`semanticFileSetDigest =
SHA-256("pf.semantic-closeout-file-set.v1" || NUL || PF-JCS(semanticFileSet))`。Q/approval 不进入该
pre-sign digest，完整 D file set（含 Q/approval）只由 post-D receipt 的 `closeoutDiffDigest` 绑定。
semantic id 固定 `semantic-closeout-<lowercase task suffix>`；完整 AllowedCloseoutPatch object domain
`pf.allowed-closeout-patch.v1`。qualification unsigned statement 是移除 `signatures` 的 closed
object：

```text
S = SHA-256("pf.task-qualification-statement.v1" || NUL || PF-JCS(unsigned))
message = ASCII("pf.task-qualification-signature.v1") || NUL || raw32(S)
Q = SHA-256("pf.task-qualification.v1" || NUL || PF-JCS(signed object))
```

所有 signatures 按 keyId 升序，count `3..256`，全部验签，禁止忽略 extra；按 §1 固定 rule 验证。
ref 的 taskId/id/digest exact 等于 signed object；缺 taskId 的旧 `{schema,id,digest}` ref 非法，防止
跨任务 substitution。qualification 必须在 C 仍为 in_progress 后签发，且不写入 C。

## 6. Acyclic steady-state closeout 与 completion receipt

```text
TaskCompletionReceiptV1 {
  schema: "proof-forge.task-completion-receipt.v1", id, version: "1.0.0",
  taskId, preCloseCandidate: CandidateIdentityV1,
  closeoutCandidate: CandidateIdentityV1,
  qualification: TaskQualificationRefV1,
  allowedCloseoutPatch: ContentRefV1, closeoutDiffDigest: Digest,
  authorityPolicy: ContentRefV1, revocationSnapshot: ContentRefV1,
  issuedAt, signatures: [ApprovalSignatureV1]
}
TaskCompletionReceiptRefV1 { taskId, id, digest: Digest }
CloseoutFileSetV1 {
  schema: "proof-forge.closeout-file-set.v1", id, version: "1.0.0",
  taskId, preCloseCandidate: CandidateIdentityV1,
  closeoutCandidate: CandidateIdentityV1,
  changes: [{path,beforeDigest: Digest|null,afterDigest: Digest|null}]
}
```

协议固定：先有 in_progress candidate **C**；C 外签发绑定 C 与 allowed patch 的 Q；创建唯一 child
**D**，`parent(D)=C`，`diff(C,D)` paths/resulting row 与 AllowedCloseoutPatchV1 exact，且 D 只做
closeout。从完整 CloseoutFileSetV1 排除固定 Q file 并移除 closeoutCandidate 后，必须与 signed
SemanticCloseoutFileSetV1 exact 且命中 `semanticFileSetDigest`；完整 file set 必须命中 R 的
`closeoutDiffDigest`。通常D可由docs-check验证文档一致性；D0-10是唯一protected exception：D只能做
structural check，因R尚未存在而不得判authority-complete或repository done。Q/receipt 的 protected verifier
验证发生在candidate外。D 后才签发 receipt R，R 绑定 C、D、Q、patch、policy、current revocation；
**R 不在 D**。
receipt unsigned/domain/message分别为 `pf.task-completion-receipt-statement.v1`、
`pf.task-completion-receipt-signature.v1`、完整 digest `pf.task-completion-receipt.v1`，签名 rule 同 §1。
issuedAt 是 RFC3339 UTC 秒，必须晚于 D observed commit。id 固定
`task-completion-<lowercase task suffix>`，ref 三字段 exact join。

full diff 不使用实现相关 unified-diff 文本。`CloseoutFileSetV1.changes` 是 C/D candidate archive
逐 path 比较得到的 exact changed-file set，按 path UTF-8 byte严格升序，count `1..16`；before/after
digest 对对应 archive member raw bytes计算 plain SHA-256 Digest，文件不存在时为 null，二者不得同时
null或相等；id 固定 `closeout-<lowercase task suffix>`。
`closeoutDiffDigest = SHA-256("pf.closeout-file-set.v1" || NUL || PF-JCS(fileSet))`。
protected consumer 必须 safe-read C/D exact archive bytes并重算 candidate archiveSha256、完整 path map
和 file set；再从 raw closeout git commit object按 `SHA-1("commit "||decimal(size)||NUL||bytes)` 重算
D.commit、解析唯一 first parent=C.commit 与 tree=D.treeObjectId。extra parent、unlisted archive change、
Q/approval fixed path bytes不等于 signed object、candidate/ref不等均拒绝。

从 full fileSet 重构 semanticFileSet 的算法固定为：验证 full schema/id/version/task/C/D 后，删除
fixed Q/approval path 的唯一 change；把 schema 替换为 `proof-forge.semantic-closeout-file-set.v1`、id
替换为上述固定 semantic id、version 保持 `1.0.0`；保留 taskId/preCloseCandidate 与其余 changes；
删除 closeoutCandidate。无 fixed-path change、出现多个、其 after bytes 不等于已验证 Q/approval，
或转换结果不等于签名前 canonical semantic object均拒绝。receipt API 因而只需 full fileSet bytes即可
确定性重算 semanticFileSetDigest，无 caller selector。

若 repo 持久化 R，只能在第三 publication commit **P** 加入 receipt/ref/ledger publication locations；
P 必须 descend from D，且 diff 不得修改 product、protocol、tests、freeze semantics 或 D 的 closeout。
未来 dependency consumer 对 raw R 重验签、撤销和 `D ancestor-of consuming C`，而不是要求同 candidate。

## 7. D0-10 一次性 bootstrap objects

```text
GovernanceBootstrapCompletionV1 {
  schema: "proof-forge.governance-bootstrap-completion.v1", id, version: "1.0.0",
  taskId: "TASK-D0-07" | "TASK-D0-10",
  rulingId: "GOV-D0CLOSE-001" | "GOV-TASKQUAL-BOOTSTRAP-001",
  purpose: "d0-07-historical-bootstrap-closeout" | "d0-10-taskqual-one-time-bridge",
  completionCandidate: CandidateIdentityV1,
  ruling: QualificationNormativeDocumentRefV1,
  sourceClosure: RawDocumentRefV1,
  authorityPolicy: ContentRefV1,
  independentReviews: [IndependentReviewRefV1],
  signatures: [ApprovalSignatureV1]
}
D0_10BootstrapApprovalV1 {
  schema: "proof-forge.d0-10-bootstrap-approval.v1", id, version: "1.0.0",
  taskId: "TASK-D0-10", ruling: QualificationNormativeDocumentRefV1,
  preCloseCandidate: CandidateIdentityV1,
  taskRow: TaskQualificationTaskRowV1, freezePackage: TaskFreezePackageRefV1,
  verifier: VerifierIdentityV1, protectedConsumer: VerifierIdentityV1,
  verifierClosureDigest: Digest, consumerClosureDigest: Digest,
  ledgerEvidenceId,
  tstDocSubprofile: "TST-DOC-001/task-qualification-v1",
  bootstrapGate: D0_10BootstrapGateV1,
  d0_07Bridge: GovernanceBootstrapReceiptDependencyV1,
  allowedCloseoutPatch: ContentRefV1,
  independentReviews: [IndependentReviewRefV1],
  authorityPolicy: ContentRefV1, signatures: [ApprovalSignatureV1]
}
D0_10BootstrapReceiptV1 {
  schema: "proof-forge.d0-10-bootstrap-receipt.v1", id, version: "1.0.0",
  taskId: "TASK-D0-10", ruling: QualificationNormativeDocumentRefV1,
  preCloseCandidate: CandidateIdentityV1, closeoutCandidate: CandidateIdentityV1,
  approvalDigest: Digest, allowedCloseoutPatch: ContentRefV1,
  closeoutDiffDigest: Digest,
  ledgerEvidenceId,
  authorityPolicy: ContentRefV1, revocationSnapshot: ContentRefV1,
  ledgerGrade: "bootstrap", purpose: "d0-10-taskqual-one-time-bridge",
  issuedAt, signatures: [ApprovalSignatureV1]
}
D0_10ReceiptLedgerProjectionV1 {
  schema: "proof-forge.d0-10-receipt-ledger-projection.v1",
  id, version: "1.0.0", evidenceId, taskId: "TASK-D0-10",
  testId: "TST-DOC-001", grade: "bootstrap", result: "passed",
  approvalRef: D0_10BootstrapApprovalRefV1,
  receiptRef: D0_10BootstrapReceiptRefV1,
  rulingRef: QualificationNormativeDocumentRefV1
}
D0_10BootstrapGateV1 {
  gateId, taskId: "TASK-D0-10", testIds: ["TST-DOC-001"],
  evidence: [EvidenceRefV1], commandPolicy: ContentRefV1,
  eligibleStage0Handoff: ContentRefV1,
  sessionContainment: ContentRefV1, freshness: ContentRefV1,
  privateScan: ContentRefV1, revocationSnapshot: ContentRefV1
}
```

GovernanceBootstrapCompletion pairs 必须按 enum positional exact 对应，禁止交叉组合或新增 task；
D0-07 的 `sourceClosure` path 固定为
`docs/governance/bootstrap-closure/TASK-D0-07.attest.json`，D0-10 的 path 固定为
`docs/governance/task-completions/TASK-D0-10/bootstrap-receipt.json`；digest 对 candidate-external raw bytes
计算 plain SHA-256 Digest。D0-10 completionCandidate **exact 为 D**，sourceClosure 是 D 外签发的 exact
D0_10BootstrapReceiptV1 bytes；R 或 GBC 均不得存入其自身所命名的 D，且任何 hash 输入都不包含其自身。
protected producer 必须先从 authority-owned bytes 验证 R 的签名、D/Q/policy/revocation joins，才可签 GBC。
dependency consumer 从 authenticated external source 或可选 P safe-read，并按 §4 wrapper bytes 重算。
其 unsigned/signature/full domains 依次为
`pf.governance-bootstrap-completion-statement.v1`、
`pf.governance-bootstrap-completion-signature.v1`、
`pf.governance-bootstrap-completion.v1`；完整构造固定为
`S=SHA-256("pf.governance-bootstrap-completion-statement.v1"||NUL||PF-JCS(unsigned))`、
`message=ASCII("pf.governance-bootstrap-completion-signature.v1")||NUL||raw32(S)`，full digest 使用
`pf.governance-bootstrap-completion.v1`。签名按 §1 fixed rule；id 固定为
`governance-bootstrap-completion-<lowercase task suffix>`；wrapper `completionCommit` exact 等于 decoded
`completionCandidate.commit`。因此 dependency wrapper 的 signatures
必须与 decoded signed object 内 signatures exact 相等，不能用 wrapper 自行给 unsigned attest 补票。
D0-10 approval 的 row 必须 exact pending→in_progress activation 后的 `in_progress` row，freeze 必须是
届时完整 closed package；本 baseline 不创建它们。ruling ref 必须重算本 accepted ruling。
bootstrapGate 与 command policy/receipts 按 §3 同型验证，但 raw EV qualification 固定为 development。
EV 必须 passed、candidate/task/testId exact，且 TaskCommandPolicyV1.id 固定为协议合法 ID
`tst-doc-001.task-qualification-v1`，映射 human-facing `TST-DOC-001/task-qualification-v1`；raw EV schema 不新增
`subprofile` 字段。它们保持
development；它们不被改称formal。approval 与 receipt 的 `ledgerEvidenceId` 必须逐字相等且是一个 exact
真实 `EV-[0-9]{8}-[0-9]{4}` ID，但 raw gate EV 保持其原 development ID，禁止重命名或冒充该 ID。
protected receipt acceptance 后唯一构造上述 closed Ledger projection：`evidenceId=ledgerEvidenceId`，id 固定
`d0-10-receipt-ledger-projection`；approvalRef/receiptRef分别用各signed full-object domain重算，rulingRef
逐字段等于已验证approval.ruling；其完整 digest domain 为
`pf.d0-10.receipt-ledger-projection.v1`。该 projection 是 docs Evidence Ledger 中同 ID 行的 exact bootstrap
投影 authority：canonical row七列固定为该evidenceId、`TASK-D0-10`、`TST-DOC-001`、`bootstrap`、
`protected receipt <receiptRef.digest>`、`passed`、`GOV-TASKQUAL-BOOTSTRAP-001 one-time receipt projection`；
parser重算projection refs/digest后才接受该row，不向Evidence Ledger增加隐藏列。它不是新的raw gate EV。D0-07 bridge
必须是 authenticated、current、non-revoked GOV-D0CLOSE-001 historical receipt且其 completion commit
为 C ancestor。reviews 必须 P0/P1=0；signatures 使用 §1 exact Architecture+Quality+Security rule。

approval unsigned/signature/full domains依次为 `pf.d0-10-bootstrap-approval-statement.v1`、
`pf.d0-10-bootstrap-approval-signature.v1`、`pf.d0-10-bootstrap-approval.v1`；receipt 对应替换
`approval` 为 `receipt`。checker authority 仅允许 policy-pinned D0-10 bootstrap checker exact
VerifierIdentity 执行本节，不得将它注册为 reusable bootstrap task checker、不得增加 policy
taskRules、不得进入 six-item activation。D0-10 使用与 §6 相同 C→signed approval→single child D→
external receipt R→signed GBC→optional P 协议；D diff 只能 exact allowed patch/template。external authority
可在无 P 时完成关闭；P 是 non-authoritative mirror，可持久化 R、GBC 和/或 Ledger projection，但不能改变
任何对象的 candidate identity、authority 或完成语义。GBC 以 external
D0_10BootstrapReceiptV1 为 sourceClosure；未来
`governance-bootstrap-receipt` dependency object只接受该 GovernanceBootstrapCompletionV1，不直接
接受 D0_10BootstrapReceiptV1。

## 8. Pure content verifier、protected adapter、publication 与错误

### 8.1 exact pure API、结果与顺序

四个 verifier 均为 pure consumer；唯一 positional API（禁止 kwargs、default、overload、path、env、
typed shortcut）为：

```text
verify_task_qualification_v1(contentBundleBytes, subjectBytes)
  -> VerifiedTaskQualificationV1 | RejectedV1
verify_task_completion_receipt_v1(contentBundleBytes, subjectBytes)
  -> VerifiedTaskCompletionV1 | RejectedV1
verify_d0_10_bootstrap_v1(contentBundleBytes, subjectBytes)
  -> VerifiedD0_10BootstrapApprovalV1 | RejectedV1
verify_d0_10_bootstrap_receipt_v1(contentBundleBytes, subjectBytes)
  -> VerifiedD0_10BootstrapCompletionV1 | RejectedV1

RejectedV1 { code: "PF-TASK-QUALIFICATION-UNVERIFIED", stage: RejectionStageV1 }
VerifiedTaskQualificationV1 { taskId: TaskId, preCloseCandidate: CandidateIdentityV1,
  qualification: TaskQualificationV1, allowedCloseoutPatch: AllowedCloseoutPatchV1,
  authorityPolicy: ContentRefV1, verificationInstant: Rfc3339UtcSecond,
  authorityClass: PureAuthorityClassV1 }
VerifiedTaskCompletionV1 { taskId: TaskId, preCloseCandidate: CandidateIdentityV1,
  closeoutCandidate: CandidateIdentityV1, qualification: TaskQualificationV1,
  receipt: TaskCompletionReceiptV1, closeoutDiffDigest: Digest,
  authorityPolicy: ContentRefV1, verificationInstant: Rfc3339UtcSecond,
  authorityClass: PureAuthorityClassV1 }
VerifiedD0_10BootstrapApprovalV1 { taskId: "TASK-D0-10",
  preCloseCandidate: CandidateIdentityV1, approvalDigest: Digest,
  allowedCloseoutPatch: AllowedCloseoutPatchV1, authorityPolicy: ContentRefV1,
  verificationInstant: Rfc3339UtcSecond, authorityClass: PureAuthorityClassV1 }
VerifiedD0_10BootstrapCompletionV1 { taskId: "TASK-D0-10",
  preCloseCandidate: CandidateIdentityV1, closeoutCandidate: CandidateIdentityV1,
  approvalDigest: Digest, receiptDigest: Digest, closeoutDiffDigest: Digest,
  authorityPolicy: ContentRefV1, verificationInstant: Rfc3339UtcSecond,
  authorityClass: PureAuthorityClassV1 }
PureAuthorityClassV1 = "production-content-verified" | "fixture-non-authoritative"
```

Verified 是字段/顺序如上的 immutable frozen record；每一字段只能来自已验证 subject（qualification/
receipt/approval及其nested candidate/ref/digest）、bundle verificationInstant 或重算 policy/member projection，
不得由 caller selector/default 合成。任何失败**返回** exact RejectedV1，不得向
public API抛任意 exception。stage只允许且固定顺序为 `bounds`、`bundle`、`profile`、`members`、
`documents`、`candidate`、`policy`、`command`、`evidence`、`dependencies`、`reviews`、`controls`、
`patch`、`signatures`、`projection`；前一阶段失败不得进入后续 hash/curve work。只有外层CLI可把它映射
为 exit 1及单行code。

### 8.2 closed bundle、profile 与 exact roles

```text
TaskQualificationContentBundleV1 {
  schema: "proof-forge.task-qualification-content-bundle.v1", id,
  version: "1.0.0",
  operation: "task-qualification" | "task-completion" |
    "d0-10-bootstrap-approval" | "d0-10-bootstrap-receipt",
  verificationProfile: TaskQualificationVerificationProfileV1,
  expectedAuthorityPolicy: ContentRefV1,
  verificationInstant, implementationInvocationId,
  members: [TaskQualificationContentMemberV1]
}
TaskQualificationVerificationProfileV1 =
  ProductionVerificationProfileV1 {
    schema: "proof-forge.task-qualification-production-profile.v1",
    id, version: "1.0.0", kind: "production", namespace,
    taskId, operation, gateSetDigest: Digest,
    expectedAuthorityPolicy: ContentRefV1,
    adapter: VerifierIdentityV1, snapshotParser: VerifierIdentityV1,
    artifacts: [{role,artifact:ContentRefV1,payloadSha256:Digest}],
    signatures: [ApprovalSignatureV1] }
| { kind: "fixture", namespace, fixturePolicy: ContentRefV1,
    keySet: "rfc8032-test-vectors" }
TaskQualificationContentMemberV1 = TypedContentMemberV1 | RawContentMemberV1 |
  ArchiveMemberV1 | GitObjectMemberV1 | ReviewMemberV1
TypedContentMemberV1 { role, kind: "typed-content", content: ContentRefV1, bytesHex }
RawContentMemberV1 { role, kind: "raw-source", raw: RawDocumentRefV1, bytesHex }
ArchiveMemberV1 { role, kind: "archive", archiveSha256: Digest, bytesHex }
GitObjectMemberV1 { role, kind: "git-object", objectId, objectType: "commit", bytesHex }
ReviewMemberV1 { role, kind: "review", reviewerId, reportDigest: Digest, bytesHex }
```

id固定为`task-qualification-content-<operation>`；verificationInstant是RFC3339 UTC秒且为全部
freshness/currentness计算的唯一instant；implementationInvocationId为safe id。members按role ASCII严格
升序且唯一；`bytesHex`为nonempty lowercase even hex，单member解码`<=64 MiB`，count `1..4096`，
decoded aggregate `<=128 MiB`，bundle canonical bytes`<=260 MiB`（`2*128 MiB + 4 MiB` fixed JSON
metadata allowance），subjectBytes `1..4 MiB`。archive decoded bytes另限`<=64 MiB`、最多100000 paths、
展开总计`<=128 MiB`、path最多4096 bytes；单archive上限同member为`64 MiB`。consumer必须仅扫描 canonical token/hex length，在任何 hex
decode、entry allocation/hash/curve 前同时检查 subject、bundle、member、aggregate与archive bounds。
除下文production profile内只能由protected adapter从外部pin解析的adapter、snapshotParser及artifacts
mapping refs外，每个ContentRef
必须resolve到恰好一个member，按其typed authority重算schema/id/version/digest；禁止untyped optional bag、
selector、未引用member、跨role bytes alias。

下表是operation的exact role set；`evidence/<EV-id>`、`review-report/<reviewerId>/<64hex-report-digest>`、
`dependency/<TASK-id>`、`dependency-archive/<TASK-id>`、`dependency-commit-object/<TASK-id>`、
`ancestry-commit/<40hex>`、`revocation-record/<record-id>`为suffix与decoded object exact join的bounded family。
qualification/approval 的 evidence/review 均 nonempty；receipt operations只验证signed prior subject/ref、
C→D closeout、policy/signatures，evidence/review/dependency/ancestry families恰为零且出现即拒绝。receipt
replay只需重验其引用的完整signed prior qualification/approval（含签名及digest/ref equality），不递归重放
该prior object的evidence/control/dependency closure。qualification/approval dependency三件套exact等于direct dependencies
（可空）；revocation family exact等于snapshot records；除对应行及family count外不得增减。

| operation | required singleton logical roles | family cardinality |
|---|---|---|
| task-qualification | `phase-4-source`, `phase-5-source`, `freeze-package-source`, `candidate-archive`, `candidate-commit-object`, `authority-policy`, `revocation-snapshot`, `allowed-closeout-patch` | gate-keyed controls and evidence below nonempty; review nonempty; dependency exact row; ancestry exact §8.3; revocation exact snapshot |
| task-completion | `pre-close-archive`, `closeout-archive`, `pre-close-commit-object`, `closeout-commit-object`, `qualification`, `allowed-closeout-patch`, `closeout-file-set`, `authority-policy`, `revocation-snapshot` | evidence/review/dependency/ancestry zero; revocation exact snapshot |
| d0-10-bootstrap-approval | `phase-4-source`, `phase-5-source`, `ruling-source`, `d0-07-ruling-source`, `freeze-package-source`, `candidate-archive`, `candidate-commit-object`, `authority-policy`, `revocation-snapshot`, `d0-07-governance-completion`, `d0-07-completion-archive`, `d0-07-completion-commit-object`, `allowed-closeout-patch`, `bootstrap-verifier-executable`, `bootstrap-verifier-closure`, `bootstrap-verifier-build-policy`, `protected-consumer-executable`, `protected-consumer-closure`, `protected-consumer-build-policy` | one gate; evidence/review nonempty; dependency is exact D0-07; ancestry/revocation exact |
| d0-10-bootstrap-receipt | `pre-close-archive`, `closeout-archive`, `pre-close-commit-object`, `closeout-commit-object`, `bootstrap-approval`, `allowed-closeout-patch`, `closeout-file-set`, `authority-policy`, `revocation-snapshot` | evidence/review/dependency/ancestry zero; revocation exact snapshot |

receipt operations have zero artifact mappings and zero families except `revocation-record/*`, which remains an
ordinary typed member exact to the snapshot. For each gateId in qualification/approval, and no other gateId, bundle
controls are mechanically **exactly five** ordinary typed roles: `command-policy/<gateId>`,
`eligible-stage0-handoff/<gateId>`, `session-containment/<gateId>`, `freshness/<gateId>`,
`private-scan/<gateId>`. External artifact logical roles are mechanically **exactly twelve**:
`resolved-tool/<gateId>`, `resolved-tool-closure/<gateId>`, `resolved-probe/<gateId>`, `sandbox-policy/<gateId>`,
`verifier-executable/<gateId>`, `verifier-closure/<gateId>`, `verifier-build-policy/<gateId>`,
`private-scan-policy/<gateId>`, `private-scan-scanner/<gateId>`, `authority-store-service/<gateId>`,
`host-observation/<gateId>`, `host-profile/<gateId>`. D0 approval adds exactly six top-level verifier/consumer
artifact roles listed in its row. Production snapshot-parser refs are profile-pin external exceptions, not operation
roles or bundle members. `authority-policy`,
`revocation-snapshot` and `revocation-record/*` are ordinary typed members, never artifacts. Additionally, nonempty
`evidence/<EV-id>` exact gate partition. Non-artifact logical roles始终是bundle members；artifact logical roles
在fixture中各由一个FixtureResolvedBlobV1 member实现，在production中各由profile `artifacts` mapping实现且
不是bundle members。因而cardinality检查不得递归要求production mapping再resolve为nested member。Pure
bundle不承载额外adapter bytes；adapter refs只由production profile的external pin解析。按profile投影后的
logical role set missing/extra/duplicate/wrong suffix，或实际bundle member set不exact，均为`members` rejection。

subjectBytes按operation只能是signed qualification、completion receipt、D0-10 approval、D0-10 receipt；
不得在members重复。command refs逐一exact join resolved tool/probe/sandbox/verifier executable/closure/build
policy；所有raw source/control/EV/dependency/review只能从member bytes投影。

role authority 是closed且逐项如下（family继承其prefix行）；raw/archive/git/review不携带也不推导
schema/id/version：

| role/prefix | member kind | parser/schema authority及ID/version | digest/domain | projected ref |
|---|---|---|---|---|
| `phase-4-source`,`phase-5-source`,`ruling-source`,`d0-07-ruling-source` | raw-source | 本规格§8.3 profile-discriminated Markdown projection；path固定 | PHASE raw ref用plain SHA-256；normative ref用production/fixture各自domain | RawDocumentRefV1/QualificationNormativeDocumentRefV1 |
| `freeze-package-source` | raw-source | 本规格§3 TaskFreezePackageV1；repository path固定 | `pf.task-freeze-package-source.v1` raw | TaskFreezePackageRefV1 |
| `evidence/*` | raw-source | local registry下表 RawEvidenceProjectionV1；ID来自row | plain SHA-256 canonical raw | EvidenceRefV1 |
| `review-report/*` | review | local ReviewProjectionV1；reviewerId/digest来自subject ref | `pf.taskqual.review-report.v1` raw | IndependentReviewRefV1 |
| `candidate-archive`,`pre-close-archive`,`closeout-archive`,`dependency-archive/*`,`d0-07-completion-archive` | archive | §8.3 archive map；无schema/id/version | plain SHA-256 archive | CandidateIdentityV1.archiveSha256 |
| `candidate-commit-object`,`pre-close-commit-object`,`closeout-commit-object`,`dependency-commit-object/*`,`d0-07-completion-commit-object`,`ancestry-commit/*` | git-object | §8.3 raw commit；objectId来自Git hash | Git SHA-1 object domain | CandidateIdentityV1.commit/ancestry edge |
| `authority-policy` | typed-content | profile-discriminated：production=`BootstrapAuthorityPolicyV1`；fixture=本节FixturePolicyV1 | production `pf.bootstrap-authority-policy.v1`；fixture `pf.taskqual.fixture-policy.v1` | ContentRefV1 |
| `production-profile` | typed-content | 本节ProductionVerificationProfileV1 | `pf.taskqual.production-profile.v1` | ContentRefV1 |
| `command-policy/*` | typed-content | §3 TaskCommandPolicyV1 | `pf.task-command-policy.v1` | gate.commandPolicy |
| `eligible-stage0-handoff/*`,`session-containment/*`,`freshness/*`,`private-scan/*`,`revocation-snapshot`,`revocation-record/*` | typed-content | local registry下表对应closed type | type表固定domain | gate ContentRefV1 |
| fixture artifact logical roles及六个top-level verifier/consumer roles | typed-content bundle member | 本节FixtureResolvedBlobV1 | `pf.taskqual.fixture-resolved-blob.v1` | command/control/identity refs |
| production artifact logical roles及六个top-level verifier/consumer roles | **无bundle member**；profile signed `artifacts` mapping | original accepted ContentRef schema；mapping携带exact ref+payloadSha256 | original ref domain；payload plain SHA-256 | command/control/identity refs |
| dependency、qualification/approval/patch/file-set/D0-07 completion | typed-content | 本规格§4–§7 exact type |各节固定domain | subject中的exact typed ref |

ProductionVerificationProfileV1 是candidate-external accepted mapping；namespace固定为policy管理的
`task-qualification-production-v1`，expectedAuthorityPolicy必须等于bundle字段、authority-policy member及
所有embedded authority refs，adapter是该namespace唯一VerifierIdentityV1。profile unsigned PF-JCS以
`pf.taskqual.production-profile-statement.v1`摘要，签名message domain
`pf.taskqual.production-profile-signature.v1`，full digest domain `pf.taskqual.production-profile.v1`，并按
§1 Architecture+Quality+Security固定rule验签。production docs-check在curve前要求exact mapping。
每个production operation另要求singleton typed member `production-profile`；fixture禁止该role。profile内
adapter executable/closure/buildPolicy refs是本条“每个ContentRef须bundle resolve”的唯一例外：pure
verifier只验profile签名与self-consistency，不从candidate bundle解析adapter bytes；protected adapter
必须从外部profile pin解析并逐字验证这些refs。
`taskId`与subject、`operation`与bundle逐字相等。令`R`为该invocation按上表机械展开后、按ASCII严格
升序唯一的artifact logical role字符串集合（只含gateId及适用的六个D0 top-level role）；
`gateSetDigest=SHA-256("pf.taskqual.gate-set.v1"||NUL||PF-JCS(entries))`，其中entry是closed union
`{scope:"gate",gateId,roles:[role]}`或`{scope:"top-level",roles:[role]}`，先按scope再按gateId ASCII升序
且唯一，每个roles是该gate的exact logical artifact role set；D0 approval恰有一个top-level entry及六role，
其他operation禁止top-level entry，receipt使用canonical空array。operation code固定映射
`task-qualification→tq`、`task-completion→tc`、`d0-10-bootstrap-approval→d0a`、
`d0-10-bootstrap-receipt→d0r`。profile id唯一为
`tq-profile-<lowercase-task-suffix>-<operation-code>-<gateSetDigest raw前48 lowercase hex>`；完整
gateSetDigest仍作为字段逐字验证，192-bit前缀只用于有界ID，任何同前缀不同full digest碰撞均拒绝且不得
另分配alias。因此profile不是一个跨operation immutable ID且所有合法ID均小于127 bytes。
profile `artifacts`按role ASCII严格升序且唯一，exact覆盖当前operation全部production artifact logical
roles（qualification/approval每 gate exact 12；D0 approval再加六个top-level；receipt operation exact zero），
不得包含raw/archive/git/review/control wrapper roles。每项保留original accepted `artifact` ContentRef identity，
绝不生成wrapper identity或bundle member；这是与adapter refs同类的external-resolution exception。pure
verifier只重验signed profile并把subject/control中的ref exact join到mapping.artifact；protected adapter才
从candidate外safe-open该original ref的payload、按accepted schema/domain重算ref并要求plain SHA-256
等于mapping.payloadSha256。mapping缺失、extra、重复或role/ref不等均拒绝。
bundle内嵌`verificationProfile`的canonical PF-JCS bytes必须逐字等于`production-profile` member decoded
bytes；按固定schema/id/version与`pf.taskqual.production-profile.v1`重算的ContentRef必须exact等于
external pin.profile，禁止两份语义等价但bytes不同的profile。

candidate-external pin对象固定为：
```text
ProductionVerificationProfilePinV1 {
  schema: "proof-forge.task-qualification-production-profile-pin.v1",
  id, version: "1.0.0", taskId, operation, gateSetDigest: Digest,
  authorityPolicy: ContentRefV1,
  namespace: "task-qualification-production-v1",
  profile: ContentRefV1, expectedSnapshotParser: VerifierIdentityV1,
  signatures: [ApprovalSignatureV1]
}
```
pin的taskId/operation/gateSetDigest与profile逐字段exact，id唯一为
`tq-pin-<lowercase-task-suffix>-<operation-code>-<gateSetDigest raw前48 lowercase hex>`；
`profile.id`及pin.profile必须命中上式派生的同一invocation profile。不存在固定全局profile/pin ID。
unsigned/signature/full domains依次为`pf.taskqual.production-profile-pin-statement.v1`、
`pf.taskqual.production-profile-pin-signature.v1`、`pf.taskqual.production-profile-pin.v1`，按§1 fixed
rule验证。protected adapter不得让bundle选择pin：它按§8.4 signed handoff中的
`(taskId,operation,gateSetDigest)`从candidate外唯一current/non-revoked lookup取得expected pin ref/bytes，先验证pin，再要求
bundle `production-profile` bytes/ref exact等于pin.profile，且profile.snapshotParser逐字段exact等于
pin.expectedSnapshotParser。docs-check只接受protected acceptance中同一
profile digest与pin ref并重验签名；candidate内自带但没有external expected ref的profile只可能得到pure
content result，不能成为authority。

fixture只允许`TST-DOC-001/task-qualification-v1`：namespace固定
`task-qualification-fixture-v1`，policy id前缀`task-qualification-fixture-policy-`，candidate commit/tree
首byte分别固定hex `f1`/`f2`，invocation/run前缀`task-qualification-fixture-run-`，principal signing keys
只能使用RFC8032 §7.1 public test vectors #1–#3，non-quorum verifier key只能使用vector #4。该tuple必须与
已提交production policy/ref/namespace/candidate/run静态不相交；
冲突在curve前拒绝。不存在env/CLI/global test-mode switch；fixture永远返回
`fixture-non-authoritative`，不能产生Ledger bootstrap/formal、GovernanceBootstrapCompletion、docs acceptance
或task closeout。steady-state fixture使用synthetic `TASK-D1-FIXTURE`；D0-10 fixture只测one-time
approval/receipt并消费fixture D0-07 GovernanceBootstrapCompletion，二者均不能关闭task。

fixturePolicy使用本规格独立closed schema `proof-forge.task-qualification-fixture-policy.v1`，不冒充
BootstrapAuthorityPolicyV1，其完整closed wire及record field order固定为：
```text
FixtureAuthorityPrincipalV1 {
  principalId, keyId, publicKey, roles: [ApprovalRoleV1]
}
FixtureVerifierKeyV1 {
  keyId: "fixture-verifier-key", algorithm: "ed25519", publicKey
}
FixturePolicyV1 {
  schema: "proof-forge.task-qualification-fixture-policy.v1",
  id, version: "1.0.0", namespace: "task-qualification-fixture-v1",
  principals: [FixtureAuthorityPrincipalV1],
  rule: ApprovalRuleV1, verifierKey: FixtureVerifierKeyV1
}
```
每个object只允许所列字段；`FixtureAuthorityPrincipalV1`与`ApprovalRuleV1`逐字段复用§1 production
closed value wire，不导入production policy parser或taskRules。principals按`keyId` ASCII严格升序且恰为：

| principalId | keyId | publicKey lowercase hex | roles |
|---|---|---|---|
| `fixture-principal-architecture` | `fixture-key-architecture` | `d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a` | `["architecture"]` |
| `fixture-principal-quality` | `fixture-key-quality` | `3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c` | `["quality"]` |
| `fixture-principal-security` | `fixture-key-security` | `fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025` | `["security"]` |

`verifierKey.publicKey`固定为RFC8032 §7.1 vector #4 lowercase hex
`278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e`；该key不得出现在principals、
signatures或quorum计算。rule恰为`requiredRoles=["architecture","quality","security"]`及
`minimumDistinctSigners=3`，roles保持上述ASCII顺序，namespace固定fixture值。
fixture control objects使用本地fixture parser/projection与同一rule，不查询production taskRules。
由这些exact bytes以domain `pf.taskqual.fixture-policy.v1`重算的
fixturePolicy必须同时等于profile.fixturePolicy、bundle.expectedAuthorityPolicy、authority member及全部
embedded refs。任何tuple与production policy/ref/namespace/candidate/run碰撞必须在curve前拒绝。
fixture archive中特别允许synthetic PHASE-4/5 rows、freeze、ruling bytes，固定IDs
`PHASE-4-FIXTURE`/`PHASE-5-FIXTURE`/`GOV-TASKQUAL-FIXTURE-001`及paths
`fixtures/task-qualification/{04-task-breakdown.md,05-test-spec.md,freeze.json,ruling.md}`；D0-10 fixture
另允许且只允许D0-07 ruling ID `GOV-D0CLOSE-FIXTURE-001`及path
`fixtures/task-qualification/d0-07-ruling.md`。它们只由本节
local raw projection解析，不是accepted normative documents且不得投影为NormativeDocumentRefV1。
fixture subject的QualificationNormativeDocumentRefV1位置使用
`FixtureNormativeDocumentRefV1{id,status:"accepted",contentDigest,reviewCommit}`；pure verifier只在fixture
profile接受并投影fixture authority class，production parser与docs-check必须拒绝该type。

fixture control wire**逐字段复用**下表production type的closed schema、field order、id/version grammar与
digest/signature domains，不发明fixture schema或alternate field；差异仅为authority verification：所有
`authorityPolicy` ref exact等于FixturePolicyV1 ref，所有signatures按原type signature statement/message
domain对FixturePolicyV1三principal及本节fixed rule验签，而不是调用production taskRules/named-rule lookup。
无own signatures的EligibleStage0HandoffV1与RevocationRecord仍由其ContentRef、enclosing signed
qualification/approval及signed snapshot绑定。fixture handoff的authorityStoreService/hostObservation/
hostProfile、private scan的policy，以及command的tool/probe/sandbox/verifier raw refs必须分别解析到上述
gate-keyed exact role，禁止bare digest或unresolved ref。

fixture resolved raw bytes使用唯一wrapper：
```text
FixtureResolvedBlobV1 {
  schema: "proof-forge.task-qualification-fixture-resolved-blob.v1",
  id, version: "1.0.0", role, payloadSha256: Digest
}
```
对每个枚举member role `<role-prefix>/<gateId>`，`role-prefix`只能是
`resolved-tool|resolved-tool-closure|resolved-probe|sandbox-policy|verifier-executable|verifier-closure|verifier-build-policy|private-scan-policy|private-scan-scanner|authority-store-service|host-observation|host-profile`，id固定为
`fixture-resolved-<gateId>-<role-prefix>`；role exact等于完整member role，payloadSha256对该测试拥有的
deterministic payload raw bytes计算plain SHA-256；wrapper full digest domain固定
`pf.taskqual.fixture-resolved-blob.v1`。member bytes是canonical wrapper，ContentRef由wrapper重算；它只在
fixture profile合法。VerifierIdentityV1按§2原domain并使executable/closure/buildPolicy分别resolve到
对应FixtureResolvedBlobV1。production profile禁止FixtureResolvedBlobV1 schema。

production `snapshotParser` 是 taskqualification-owned parser identity，不得使用 D0-01..07 historical parser。
唯一 API 是 `parse_taskqualification_snapshot_v1(phase4Bytes, phase5Bytes, taskId) ->
{row:TaskQualificationTaskRowV1,tests:[testId]} | RejectedV1`：三个 positional inputs，禁止 path/kwargs/default；
exact-consume两份 raw bytes，tests须exact等于row.tests并验证PHASE-5 task-qualification subprofile。identity
按§2 domain，由signed profile及candidate-external pin exact；其executable/closure/buildPolicy与adapter refs
同属external pin exception，由protected adapter safe-open/recompute，不进入operation roles、profile.artifacts
或candidate bundle。fixture保持本节local parser且不构造snapshot-parser identity/wrapper。

wrapper不携带也不引用bundle外payload。fixture virtual identity token的exact bytes是
`ASCII("pf.taskqual.fixture-resolved-payload.v1") || NUL || UTF8(role)`，其`payloadSha256`唯一合法值是
该exact bytes的plain SHA-256 Digest；因此
verifier从已验证role直接重算，禁止caller bytes、archive path或未承载payload。六个top-level role不带
`/<gateId>`，恰为`bootstrap-verifier-{executable,closure,build-policy}`与
`protected-consumer-{executable,closure,build-policy}`；其wrapper id固定为`fixture-resolved-<完整role>`、
wrapper role exact等于member role，并采用同一payload公式。这六个role只是D0-10 approval singleton，
不得出现在其他operation或gate-keyed family。该token仅供nonauthoritative fixture确定性join，绝不声称
executable、closure、scanner或其他payload provenance。production禁止FixtureResolvedBlobV1，并只使用
上述profile signed mapping，不定义任何production resolved wrapper type。

### 8.3 projections、trusted time与safe-open语义

#### 8.3.1 closed join projections（2026-07-20 accepted contract repair）

本节只闭合前述对象已有字段间的验证join，不增加EV wire、测试、task完成条件或production authority。

**Task row与closeout。** `TaskCloseoutTaskRowV1`是closed object，字段顺序固定为：

```text
TaskCloseoutTaskRowV1 {
  taskId, output, dependencies: [taskId],
  prerequisites: ["<document-id>@accepted"], tests: [testId],
  evidenceIds: [evidenceId], status: "done"
}
```

从C的`TaskQualificationTaskRowV1`构造D projection时逐字段复制前六项，只把status
`in_progress→done`；steady-state不得增删、重排或替换evidenceIds。D0-10是唯一例外：D evidenceIds在
C的development IDs后按ASCII位置加入approval.ledgerEvidenceId恰一次，且该reserved ID不得等于任何gate
raw EV ID；在R前它只是由signed approval预留的external projection ID，不冒充已存在EV。steady-state的
formal EV已在C发布并由Q验证，D只发布Q及task-owned closeout文档；D0-10 raw IDs保持development，bootstrap
authority只由外部R及其Ledger projection提供。由D的raw PHASE-4 source
按下述grammar重新投影后必须exact等于该对象；
`resultingTaskRowDigest = SHA-256("pf.taskqual.closeout-task-row.v1" || NUL ||
PF-JCS(TaskCloseoutTaskRowV1))`。这与§6 receipt在D后签发、R不在D完全一致。
所有gate的EvidenceRef IDs取sorted union（按ID ASCII升序，跨gate重复非法）后还必须exact等于
taskRow.evidenceIds；不得只比较gate局部集合或允许row遗留ID。

**Raw EV。** local closed projection扩为（nested值均是`validate_evidence`已验证对象的逐字段deep copy，
不是新wire）：

```text
RawEvidenceProjectionV1 {
  id,
  gate: {id,taskId,testIds,qualification},
  repository: {commit,treeObjectId,archive:{format,sha256,size}},
  command: {argv,cwdRelative,startedUtc,endedUtc,durationMs,attempts},
  environment: {os,arch,environmentSha256,sourceDateEpoch,cleanRoom,buildCache,assetCache},
  sandboxPolicies, tools, inputs, artifacts, logs,
  result
}
```

字段及array entry closed shape、顺序、bounds完全来自pinned `validate_evidence`；projection删除其他root字段，
但不得过滤array。每个gate的所有EV必须满足：`command.argv == commandPolicy.argv`；handoff.environment固定
四值mapping投影成按name ASCII升序的完整env数组
`[{name:"HOME",value:"/var/empty"},{name:"LC_ALL",value:"C"},
{name:"PATH",value:"/usr/bin:/bin"},{name:"TZ",value:"UTC"}]`，且与commandPolicy.environment exact；
因此这里只比较signed policy与EligibleStage0Handoff，EV不携带process environment且不得从
`environment` host metadata推导。按`(id,version)`筛选后必须恰有一个tools entry，其
`executableSha256 == plain-SHA256(resolved-tool payload)`且`closureSha256 ==
plain-SHA256(resolved-tool-closure payload)`；其id/version分别exact等于commandPolicy.tool.id/version，
commandPolicy.tool ref仍按role member的schema/domain重算。`sandboxPolicies`必须恰含一个entry，其
`id == commandPolicy.sandboxPolicy.id`、`renderedSha256 == plain-SHA256(sandbox-policy payload)`；该entry
的probes必须恰含一个entry，其`id == commandPolicy.probe.id`且status=`passed`；EV `inputs`中必须恰有
一个role=`sandbox-probe-wrapper`的actual wrapper input claim，其sha256 exact等于resolved-probe payload的
plain SHA-256。invocation receipt不参与这个identity join。commandPolicy.verifier三ref分别exact resolve gate-keyed
verifier roles；tool与verifier executable是不同role/ref且不得alias。EV tools/inputs/artifacts/logs不得充当
ContentRef carrier；以上plain hashes只是它们到已解析signed policy/control及bundle member的join。

fixture的“payload”按§8.2公式由role确定，所以上述plain hash对该确定性payload计算；production由protected
adapter safe-open的真实payload计算。任一EV间argv/environment/tool/sandbox/probe/verifier结果不一致拒绝。

**Task qualification private scan coverage。** 本协议不调用、不重解释production
`PrivateScanReceiptV1`。gate.privateScan只接受closed：

```text
TaskQualificationPrivateScanReceiptV1 {
  schema: "proof-forge.task-qualification-private-scan-receipt.v1",
  id, version: "1.0.0", candidate: CandidateIdentityV1,
  evidenceCoreDigest: Digest, scannerDigest: Digest, policy: ContentRefV1,
  scannedEvidenceRefs: [EvidenceRefV1], scannedMembers,
  findings: [], result: "clean", signatures: [ApprovalSignatureV1]
}
```

id固定`task-qualification-private-scan-<gateId>`；unsigned statement、signature message、full domains
依次为`pf.taskqual.private-scan-statement.v1`、`pf.taskqual.private-scan-signature.v1`、
`pf.taskqual.private-scan.v1`，按profile authority rule验签。对gate内按EvidenceRef
`(id,digest raw32)`升序的每个raw EV，先令
`E={id,digest}`（digest是raw canonical EV bytes的plain SHA-256 Digest）。`scannedEvidenceRefs`必须exact
等于全部E。再从该EV未经筛选的三个array生成：每个`inputs` entry生成
`{evidence:E,role:entry.role,path:entry.path,size:entry.size,digest:"sha256:"+entry.sha256}`；每个
`artifacts` entry生成同形对象，role固定为
`artifact.<target>.<role>`；每个`logs` entry生成同形对象，role固定`log`。按
`(evidence.id,evidence.digest raw32,path UTF-8)`严格升序后的完整union必须exact等于
`scannedMembers`；由于EV已拒绝inputs/artifacts/logs跨集合path复用，不存在同key歧义。零项允许，但不得
省略任一存在项或加入bundle control/archive/review member；`evidenceCoreDigest`固定为
`SHA-256("pf.taskqual.private-scan-core.v1" || NUL || PF-JCS({candidate,scannedEvidenceRefs,
scannedMembers}))`。receipt.policy exact resolve`private-scan-policy/<gateId>`；scannerDigest等于
`private-scan-scanner/<gateId>` payload plain SHA-256；
findings=`[]`、result=`clean`。candidate及全部refs/members共同进入上述taskqual core digest，禁止接受
production formal scan receipt、其`result:passed`语义或其pinned domain。

**Markdown carrier grammar。** production source不在本amendment复制或收窄repository Markdown grammar：
必须exact委托当前profile pin指定的accepted snapshot parser及其既有PHASE-4、PHASE-5、normative-document
authority docs；尤其不得硬编码四位approver，也不得额外要求H1 exact equality。parser输出的row/document ref
仍须与subject逐字段exact join，且actual D0-07 production ruling必须保持accepted。

fixture parser独立且closed：UTF-8、LF-only、exact一个trailing LF、无BOM/NUL/CR；frontmatter从byte 0
开始，opening/closing均exact `---`，中间恰有以下**11 fields/lines**且顺序固定：`id`、`title`、
`status`、`owner`、`updated`、`normative`、`approvers`、`approvedAt`、`reviewCommit`、`reviewLink`、
`openFindings`。形式分别为`id: <枚举id>`、`title: <nonempty>`、`status: accepted`、
`owner: <safe-id>`、`updated: YYYY-MM-DD`、`normative: true`、
`approvers: <safe-id>(, <safe-id>)*`、`approvedAt: YYYY-MM-DD`、`reviewCommit: <40hex>`、
`reviewLink: https://<nonempty>`、`openFindings: none`；approvers非空、唯一并按safe-id ASCII严格升序。
closing后恰一空行。body首个ATX-H1必须以exact `# <frontmatter.id>`开始，且ID后立即是EOL，或是
ASCII colon `:` / fullwidth colon `：`后跟任意非NUL/Cc text再EOL。

fixture PHASE-4只接受一个table：header exact
`| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |`、delimiter exact
`|---|---|---|---|---|---|---|`，随后仅允许§8.2枚举的row；每row exact七个single-line cell，首尾`|`，
cell delimiter exact ` | `，ID/list/status按§3投影，禁止第二block或同ID重复。fixture PHASE-5只接受一个
table：header exact `| ID | 测试对象 |`、delimiter exact `|---|---|`，随后仅允许唯一row
`| TST-DOC-001 | task-qualification-v1 |`，禁止其他row/block。这些fixture grammar不反向约束production。

production paths固定为§8.3既有三path，`ruling-source`固定
`docs/governance/task-qualification-bootstrap-ruling.md`，`d0-07-ruling-source`固定
`docs/governance/d0-07-closure-ruling.md`。production `NormativeDocumentRefV1.contentDigest`固定为
`SHA-256("pf.normative-document.v1" || NUL || UTF8(id) || NUL || raw document bytes)`，不得使用raw
plain hash；reviewCommit及其他字段由pinned accepted parser/profile产生。Q/approval中的PHASE/ruling ref
必须exact等于projection。fixture使用上述独立grammar，frontmatter
id限§8.2枚举；全部fixture PHASE-4/PHASE-5/ruling frontmatter及其typed refs的reviewCommit固定为
candidate-external review pin
`f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0`，不得等于或由fixture C/D commit推导。该pin首byte
`f0`，与fixture C commit首byte`f1`、tree首byte`f2`静态不相交；它只证明test-owned fixture grammar，
不是Git ancestry、production review或docs acceptance。synthetic
PHASE-4只允许`TASK-D1-FIXTURE` steady row，或D0-10 operation的`TASK-D0-10` row及其唯一direct dependency
`TASK-D0-07`。synthetic PHASE-5只允许`TST-DOC-001` row。fixture ruling body H1必须对应其枚举ID；
`FixtureNormativeDocumentRefV1.contentDigest = SHA-256("pf.taskqual.fixture-normative-document.v1" || NUL ||
UTF8(id) || NUL || raw document bytes)`，reviewCommit exact等于上述fixed pin，且不得转型
为production NormativeDocumentRefV1。

**Legacy candidate normalization。** 每个pinned legacy control candidate必须先由
`parse_candidate_identity`验证closed
`{commit,treeObjectId,archiveDigest,digest}`及
`digest=SHA-256("pf.candidate-identity.v1"||NUL||PF-JCS({commit,treeObjectId,archiveDigest}))`；随后唯一
投影为taskqual`{commit,treeObjectId,archiveSha256:archiveDigest}`。taskqual candidate digest不是wire字段；
需要比较派生identity时使用
`SHA-256("pf.taskqual.candidate.v1"||NUL||PF-JCS(taskqual CandidateIdentityV1))`。raw EV repository的
`archive.sha256`先加`sha256:`后作archiveDigest，再经同一legacy验证/投影；所有handoff、containment、scan、
qualification/approval及archive member candidate必须投影后exact相等。禁止直接忽略legacy digest或把它
误当taskqual candidate digest。

**Fixture D0-07 bridge与ruling。** §7所称fixture D0-07 completion是只供
`d0-10-bootstrap-approval` pure fixture消费的non-authoritative signed shape；允许
`taskId=TASK-D0-07`、`rulingId=GOV-D0CLOSE-FIXTURE-001`、purpose保持
`d0-07-historical-bootstrap-closeout`，其ruling typed为FixtureNormativeDocumentRefV1。它可通过local fixture
parser得到fixture authority class，但public API不得返回或发布GovernanceBootstrapCompletion、不得进入
Ledger/docs acceptance。production仍只接受`GOV-D0CLOSE-001`及production NormativeDocumentRefV1。
`d0_07Bridge.ruling`不是第二份自由ref：它必须直接等于`d0-07-ruling-source`投影所得
QualificationNormativeDocumentRefV1，并与decoded completion.ruling保持同一profile discriminant及逐字段
exact equality；禁止制造normative ContentRef/schema/version。production projection使用上述pinned domain，
fixture使用其own domain；该role禁止与D0-10 `ruling-source` alias。fixture D0-07 completion仅在fixture
profile可验证为nonauthoritative；production仍验证并接受仓库actual D0-07 accepted ruling。

**D0-10 top-level identities。** approval.verifier与protectedConsumer必须不同id且逐字段resolve六个新增
singleton role；每个identity的executable/closure/buildPolicy依次只可指向其同prefix role，禁止跨identity、
gate verifier或production adapter bytes alias。`verifierClosureDigest =
SHA-256("pf.d0-10.bootstrap-verifier-closure.v1"||NUL||PF-JCS(verifier))`，
`consumerClosureDigest = SHA-256("pf.d0-10.protected-consumer-closure.v1"||NUL||
PF-JCS(protectedConsumer))`。gate commandPolicy.verifier只解析gate-keyed三role且与top-level verifier不同；
它证明测试命令身份。top-level verifier是执行§7 checker的identity；protectedConsumer必须在production
等于§8.4 protected acceptance.adapter，fixture只验证结构并保持non-authoritative。fixture六role由wrapper
members承载；production六role逐一exact join profile artifact mappings的original refs，closure digest公式
绑定完整identity，protected adapter再safe-open并hash。approval verifier、protectedConsumer、gate verifier
及tool保持不同identity/ref，所有跨role alias拒绝。由此role表、
gate family及FixtureResolvedBlob prefix对四个operation均total：未列role一律extra-member拒绝。

archive只接受POSIX.1-1988 ustar（512-byte header、octal size/checksum）或`git archive --format=tar`
产生的同一ustar子集；全archive只能选一种。每项必须在唯一root prefix `<taskId-lower>/` 下，prefix剥离后
形成按UTF-8 path排序的完整path map；只接受regular file与relative NFC POSIX path，拒绝empty/
`.`/`..` component、absolute、backslash、NUL、symlink/hardlink/device、PAX/GNU extension、sparse、
duplicate/casefold collision。uname/gname、uid/gid、mtime必须为零或全忽略且不参与tree；typeflag只允许
`0`/NUL；mode仅低9位且只能`0644`或`0755`，分别确定Git mode `100644`/`100755`，其他metadata拒绝。
archiveSha256是exact archive bytes的plain SHA-256 Digest；treeObjectId按Git blob/tree object规则从完整map
自底向上重算：blob=`SHA-1("blob "||decimal(size)||NUL||bytes)`；tree payload按Git bytewise name order编码
`ASCII(mode)||SP||name||NUL||raw20(objectId)`（目录mode `40000`），tree同样加`tree <size>\0`后SHA-1。
commit member是raw commit payload；commit按
`SHA-1("commit "||decimal(size)||NUL||payload)`重算，解析唯一tree与first parent；C tree必须等于archive
tree，D必须唯一parent=C且禁止extra parent。§6 full/semantic path-map算法逐字适用。

PHASE-4/5固定来自`docs/04-task-breakdown.md`/`docs/05-test-spec.md`；freeze/ruling使用§3/§7固定path。
从raw bytes解析accepted frontmatter与唯一authority table/row。review report必须是protected review service的
immutable opaque raw bytes；它不承载、也不解析review metadata。`ReviewProjectionV1`的
`reviewerId,reviewerKind,invocationId,reviewCommit,reviewLink,decision,findings`逐字段exact复制已解码subject中的
`IndependentReviewRefV1`，`reportDigest`则由raw bytes按本节domain重算后必须exact等于subject ref及
`ReviewMemberV1.reportDigest`；member role必须exact为
`review-report/<reviewerId>/<reportDigest的64 lowercase hex，不含sha256:前缀>`，member reviewerId也必须
exact等于该subject ref。由此
reviewCommit=C，invocationId与implementationInvocationId及其他review invocation不同。raw bytes只做以下
bounded内容扫描：先按§2检查`1..1048576` bytes并strict UTF-8 decode；把每个exact CRLF替换为LF，若仍有
bare CR则拒绝，只按literal LF切line，不把其他Unicode line separator当换行。任一line exact等于
`Severity: P0`/`Severity: P1`，或以ASCII case-sensitive `P0:`/`P1:`从byte 0开始即拒绝。另在原始UTF-8
bytes上仅把ASCII `A..Z`映射为`a..z`后搜索`unresolved`；其前后若存在相邻byte，均不得属于
`[A-Za-z0-9_]`，由此定义唯一ASCII whole-word boundary。UTF-8失败、任何上述命中或subject object
findings非空均拒绝，不信summary，也不得从report文本标题、frontmatter、JSON或其他自述字段覆盖subject
metadata。

ancestry graph恰为consuming C到freezeCommit以及C到每个direct dependency completionCommit的所有父边
闭包路径并集：每个目标至少一条路径、沿途每个commit的全部parents都须递归表示；member按commit id
keyed/dedup，根目标之后不展开，任何缺parent、不可达或不在该并集的extra commit拒绝。merge保留全部
parent并确定性展开，不采用first-parent shortcut；receipt operations按§8.2不承载此图。
commit bytes按objectId建立唯一map且role precedence固定：consuming C只来自`candidate-commit-object`，
dependency target只来自`dependency-commit-object/<TASK>`，D0-07 target只来自其固定singleton；这些target
不得重复为`ancestry-commit/*`。`ancestry-commit/*`只承载其余closure node；同一objectId跨role出现、
同bytes alias或extra node均拒绝。

本协议所需raw parser registry固定如下。`module::api`名称及schema/domain是accepted接口pin；所列local
projection是完整closed字段，不导入SPEC-EVFINAL-001，也不复制其generalized framework：

| role | parser API / authority | 本协议消费的exact typed projection | digest domain |
|---|---|---|---|
| evidence | canonical PF-JCS decode → `scripts/evidence_v1_core.py::validate_evidence` → exact canonical re-encode / accepted TRACE-EV-001 | §8.3.1完整`RawEvidenceProjectionV1`（含repository、command、environment、sandboxPolicies、tools、inputs、artifacts、logs、result），不得回退旧subset | plain SHA-256 canonical raw |
| authority-policy | profile-discriminated：production=`scripts/bootstrap_task_objects.py::parse_bootstrap_authority_policy`；fixture=本节closed FixturePolicyV1 parser | production complete BootstrapAuthorityPolicyV1；fixture complete FixturePolicyV1；均投影对应ContentRefV1且不得跨profile解析 | production `pf.bootstrap-authority-policy.v1`；fixture `pf.taskqual.fixture-policy.v1` |
| eligible handoff | `scripts/bootstrap_task_objects.py::_preflight_eligible_stage0_handoff` / accepted ADR-0018 consumer pin | complete `EligibleStage0HandoffV1{runId,nonce,candidate,authorityPolicy,authorityStoreService,hostObservation,hostProfile,eligible,tcb,environment,channels,pathnameReopen,fallback}` | `pf.eligible-stage0-handoff.v1` |
| containment | `scripts/formal_evidence.py::parse_session_containment_receipt` / accepted ADR-0018 consumer pin | complete `SessionContainmentReceiptV1{candidate,stage0Handoff,supervisorDigest,rootSessionId,descendants,escapeProbes,startedAt,finishedAt,result,signatures}` | `pf.session-containment-receipt.v1` |
| freshness | `scripts/formal_evidence.py::parse_freshness_authority_snapshot` / accepted ADR-0018 consumer pin | complete `FreshnessAuthoritySnapshotV1{authorityPolicy,observedAt,maximumAgeSeconds,clockSourceDigest,signatures}`；expiry只按ADR-0018公式派生 | `pf.freshness-authority-snapshot.v1` |
| task qualification private scan | 本规格§8.3.1 local closed parser | complete `TaskQualificationPrivateScanReceiptV1`；result only `clean` | `pf.taskqual.private-scan.v1` |
| revocation snapshot/records | `scripts/formal_evidence.py::parse_revocation_ledger_snapshot` + `scripts/revocation_ledger.py::parse_revocation_record` / accepted ADR-0018 consumer pin | complete snapshot `{authorityPolicy,records,head,recordsDigest,signatures}` 与 record `{id,evidence,revokedUtc,reasonCode,reason,authorityRef,replacement,previousRecordSha256}`；record无自签名/status字段 | `pf.revocation-ledger-snapshot.v1` / `pf.evidence-revocation.v1` |
| governance completion | local §7 parser | complete GovernanceBootstrapCompletionV1 | §7 full domain |
| reviews | local parser | `ReviewProjectionV1{reviewerId,reviewerKind,invocationId,reviewCommit,reviewLink,decision,findings,reportDigest}`；前七项exact复制subject ref，reportDigest由opaque raw重算并join subject/member；raw只做bounded findings文本扫描 | `pf.taskqual.review-report.v1` raw |

| object | pure snapshot test at bundle verificationInstant | protected currentness |
|---|---|---|
| EV/review/governance completion | candidate/commit/ref/signature joins；这些wire无通用expiry，不臆造time字段 | immutable source provenance/current policy |
| handoff | candidate/policy/eligible/pathnameReopen/fallback/channel/tcb joins；无通用expiry | live FD/session/peer重新认证 |
| containment | candidate/handoff/result/descendant/probe joins且`startedAt<=finishedAt<=verificationInstant` | live session/peer重新认证 |
| task qualification private scan | candidate/evidence/member exact coverage、findings empty、result clean；无通用expiry | protected scanner/source provenance |
| freshness | `observedAt<=instant<expiresAt=observedAt+maximumAgeSeconds` | trusted clock observation |
| revocation snapshot/records | pure count/order/head/aggregate/signature与record chain；当前subject refs不得命中record.evidence；snapshot本身无time字段 | protected authority-store在trusted instant返回同一current head；不得由snapshot自证store currentness |

只有表中实际存在的time字段参与比较；future containment times及freshness equal-expiry拒绝，不给其他类型
添加issuedAt/expiresAt隐式default。

pure verifier只证明caller-supplied instant处content/digest/signature/join；不声称instant可信、FD/session仍
live、source path/safe-open、真实Git graph、external policy currentness或authority-store provenance。

### 8.4 protected production adapter

root-only `docs_check` 永远只是 structural checker，任何运行方式都不构成 production-authority complete。
本节定义独立、taskqualification-owned protected authority；它**不修改、不复用、也不冒充**
`proof-forge.eligible-stage0-handoff.v1`、`BootstrapEvidenceRootManifestV1`或通用
`pf.authority-store.rpc.v1`，且其任何对象、service descriptor或executable pin均不得进入six-item
activation。名称相似、字段可投影或同一进程实现均不构成wire兼容。2026-07-23 C3 amendment经
`ADR-0021`把新production handoff从本节原taskqualification lookup-only v1迁移到exact v2 terminal signer；
旧v1只保留historical decoder，禁止production fallback、协商或dual reader。

唯一 protected positional API 固定为
`protect_taskqualification_v1(operationBytes, handoffBytes, authorityPolicyFd, authorityStoreFd,
candidateArchiveFd, provenanceBundleFd, trustedClockFd)`；七个参数均required positional，禁止
path/env/kwargs/default。operationBytes是四operation之一的exact ASCII。继承FD集合必须exact为
`0,1,2`加后五个FD，五者为非负、两两不同且逐一等于handoff.channels中的同名值；禁止reopen、dup后替换、
ambient FD或fallback。policy/archive/provenance/clock是只读regular file，从offset 0 stable exact-consume，
读取前后`fstat(dev,ino,mode,nlink,size)`相等、`nlink=1`、非symlink；store是唯一authenticated channel且
不按文件读取。historical v1为`SOCK_STREAM`；新production handoff只允许`ADR-0021`冻结的Linux
`AF_UNIX/SOCK_SEQPACKET` v2 socketpair endpoint。handoffBytes不在candidate archive/provenance中取得。

```text
TaskQualificationProtectedChannelsV1 {
  authorityPolicyFd, authorityStoreFd, candidateArchiveFd,
  provenanceBundleFd, trustedClockFd
}
TaskQualificationProtectedHandoffV1 {
  schema: "proof-forge.task-qualification-protected-handoff.v1",
  id, version: "1.0.0", taskId, operation, runId, nonce,
  candidate: CandidateIdentityV1, authorityPolicy: ContentRefV1,
  productionProfilePin: ContentRefV1, gateSetDigest: Digest,
  adapter: VerifierIdentityV1, snapshotParser: VerifierIdentityV1,
  authorityStoreService: ContentRefV1,
  trustedClockService: VerifierIdentityV1,
  revocationHead: {headSequence,headDigest:Digest}, trustedInstant,
  channels: TaskQualificationProtectedChannelsV1,
  signatures: [ApprovalSignatureV1]
}
```

id固定`task-qualification-protected-handoff-<runId>`；runId/nonce为safe-id且nonce一次性。unsigned、signature
message、full domains依次为`pf.taskqual.protected-handoff-statement.v1`、
`pf.taskqual.protected-handoff-signature.v1`、`pf.taskqual.protected-handoff.v1`。使用current activated
BootstrapAuthorityPolicyV1 principal/key registry与§1固定TaskQualificationAuthorityRule验签，但不读取或
扩展其taskRules。policy exact bytes/ref、handoff、profile pin、adapter/parser/store/clock service descriptor及
它们的executable/closure/buildPolicy payload pins均由candidate外ceremony提供并签入handoff；candidate、
subject、bundle或CLI不能选择。trustedInstant为RFC3339 UTC秒，并须exact等于trustedClockFd中signed
TaskQualificationTrustedClockObservationV1.observedAt；clock object还绑定taskId/operation/runId/nonce、
trustedClockService、clockSourceDigest并用同一fixed rule及§8.3既有clock domains验签。

provenanceBundleFd只接受candidate-external authenticated canonical closed：
```text
ProtectedTaskQualificationProvenanceBundleV1 {
  schema: "proof-forge.protected-task-qualification-provenance-bundle.v1",
  id, version: "1.0.0", taskId, operation, runId, nonce,
  subjectDigest: Digest, candidateArchiveSha256: Digest,
  entries: [{role, bytesHex}]
}
```
entries按role ASCII严格升序唯一，bytesHex使用§8.2相同single/aggregate/pre-decode bounds；roles exact等于
该operation pure bundle需要的subject、raw/archive/git/review/control source roles，外加`production-profile`、
`production-profile-pin`、
`live-handoff`、`live-session`、`trusted-clock-observation`、`current-revocation-snapshot`、
`authority-store-service-descriptor`、`authority-store-executable`、`authority-store-closure`、
`authority-store-build-policy`、
`adapter-executable`、`adapter-closure`、`adapter-build-policy`、`snapshot-parser-executable`、
`snapshot-parser-closure`、`snapshot-parser-build-policy`；v2新production handoff再恰加
`store-supervisor-executable`、`store-supervisor-closure`、`store-supervisor-build-policy`与
`store-isolation-policy`，historical v1禁止这四role。D0 receipt acceptance另加`bootstrap-receipt`、
`governance-bootstrap-completion`、`receipt-ledger-projection`。artifact payload roles由signed profile mapping
展开并在bundle各出现一次，bytes按mapping payloadSha256与original accepted ref重算。bundle不携带expected
policy/profile/revocation值且不签发authority；它是本协议自己的provenance channel，不是evidence root。
其task/operation/run/nonce、subject及archive digests须exact handoff/API/subject/channel bytes；六个
adapter/parser payload及v2四个supervisor/isolation payload逐字段匹配current pin/descriptor refs并重算。
authority-store descriptor bytes重算后exact等于handoff.authorityStoreService。historical v1 verifier三ref分别
绑定三个authority-store payload roles；v2还要求descriptor.supervisor三ref与isolationPolicy逐字段绑定新增
四role，并按`ADR-0021`验证static service、supervisor、socket endpoint lineage与live session identity。
trusted-clock-observation是closed
`{schema:"proof-forge.task-qualification-trusted-clock-observation.v1",id,version:"1.0.0",taskId,operation,
runId,nonce,trustedClockService,observedAt,clockSourceDigest,signatures}`，tuple/service exact handoff，
unsigned/signature/full domains依次为
`pf.taskqual.trusted-clock-observation-statement.v1`、
`pf.taskqual.trusted-clock-observation-signature.v1`、`pf.taskqual.trusted-clock-observation.v1`，按§1 fixed
rule验签，observedAt是本次唯一trusted instant。
current-revocation-snapshot及records须与authority-store同一headSequence/headDigest lookup结果exact。

以下`pf.taskqual.authority-store.rpc.v1` descriptor/frame/key是C3迁移后只读historical grammar，bytes、domain与
lookup-only语义保持不变；新protected production invocation必须在curve前拒绝它。historical service descriptor
及其ref固定为：
```text
TaskQualificationAuthorityStoreServiceV1 {
  schema: "proof-forge.task-qualification-authority-store-service.v1",
  id, version: "1.0.0", namespace: "task-qualification-production-v1",
  protocol: "pf.taskqual.authority-store.rpc.v1",
  servicePublicKey, verifier: VerifierIdentityV1,
  maximumFrameBytes: 1048576
}
TaskQualificationStoreClientHelloV1 {
  schema: "proof-forge.task-qualification-store-client-hello.v1",
  version: "1.0.0", taskId, operation, runId, nonce,
  service: ContentRefV1, headSequence, headDigest: Digest
}
TaskQualificationStoreServerHelloV1 {
  schema: "proof-forge.task-qualification-store-server-hello.v1",
  version: "1.0.0", taskId, operation, runId, nonce,
  service: ContentRefV1, headSequence, headDigest: Digest,
  status: "ready", signature
}
TaskQualificationStoreLookupRequestV1 {
  schema: "proof-forge.task-qualification-store-lookup-request.v1",
  version: "1.0.0", requestId, taskId, operation, runId, nonce,
  headSequence, headDigest: Digest, key: TaskQualificationStoreLookupKeyV1
}
TaskQualificationStoreLookupResponseV1 {
  schema: "proof-forge.task-qualification-store-lookup-response.v1",
  version: "1.0.0", requestId, taskId, operation, runId, nonce,
  headSequence, headDigest: Digest, status: "found",
  key: TaskQualificationStoreLookupKeyV1,
  object: ContentRefV1, objectBytesHex, signature
}
```
每个object只允许所列字段及顺序。servicePublicKey是32-byte Ed25519 lowercase hex；descriptor full digest
domain `pf.taskqual.authority-store-service.v1`并exact等于handoff.authorityStoreService。headSequence与
requestId均为PF-JCS safe integer `0..2^53-1`；requestId从0开始每次exact加1。signature是128-char
lowercase Ed25519 hex，不是ApprovalSignatureV1；server hello/lookup response分别对移除signature后的closed
object以message `ASCII("pf.taskqual.store-server-hello-signature.v1"或
"pf.taskqual.store-lookup-response-signature.v1") || NUL || PF-JCS(unsigned)`用descriptor.servicePublicKey
验签。四种full frame digest domains依次为`pf.taskqual.store-client-hello.v1`、
`pf.taskqual.store-server-hello.v1`、`pf.taskqual.store-lookup-request.v1`、
`pf.taskqual.store-lookup-response.v1`；digest均覆盖包含signature（若有）的完整PF-JCS object。

每帧为4-byte big-endian payload length（`1..1048576`）加canonical PF-JCS object；exact-read，EOF/extra
bytes/unknown frame拒绝。client hello、server hello逐字段绑定handoff service/head；随后request/response
exact echo task/operation/run/nonce/head/key/requestId。key是closed
`{namespace:"task-qualification-production-v1",taskId,operation,gateSetDigest,objectKind,objectId}`；允许的
`objectKind/object schema`仅为`authority-policy`/BootstrapAuthorityPolicyV1、`production-profile-pin`/
ProductionVerificationProfilePinV1、`production-profile`/ProductionVerificationProfileV1、
`adapter`/VerifierIdentityV1、`snapshot-parser`/VerifierIdentityV1、`authority-store-service`/
TaskQualificationAuthorityStoreServiceV1、`trusted-clock-service`/VerifierIdentityV1、`revocation-snapshot`/既有closed snapshot及
`revocation-record`/既有closed record。objectId必须来自signed handoff/pin/snapshot，不得由candidate提供；
decoded bytes重算object ref及schema/key exact。只允许lookup，禁止publish/mutation。

服务端必须原子消费(runId,nonce)：同nonce第二次hello、跨operation/task复用、旧head、head drift、重复或乱序
requestId、not-found/revoked/multiple、peer/service pin不符均fail closed并使nonce永久spent。每个response及
最终acceptance都必须保持handoff current head；验证结束前再lookup revocation head并exact相等。失败后不得
重试同nonce；新尝试必须由candidate-external authority签发新handoff。profile/pin lookup唯一按signed
handoff `(taskId,operation,gateSetDigest)`，绝不按candidate声明。以上段落同样只定义historical v1 replay；它
不得为新production acceptance提供签名或authority。

新production `authorityStoreFd`只讲`pf.taskqual.authority-store.rpc.v2`，其closed descriptor、六种frame、
PF-JCS field order、full/signature domains、4 MiB seqpacket framing、lookup key union与exact序列、unsigned
acceptance wire、terminal request/response、Linux U/P/A peer/custody profile、static service
supervisor→same-PID `execveat`、seedRoot/role-key custody、durable nonce/head transaction、bounds及negative
matrix只在ADR-0021、SPEC-TASKQUAL-001与PHASE-5共同恢复`accepted`后，才以该同一acceptance unit中的
`ADR-0021` §§2–8、§12为本规格exact normative内容。其中capability transition只能是ADR表列的ambient
bridge：pre/post-exec五组均`[CAP_SETPCAP,CAP_SYS_PTRACE]`，service在任何post-exec service读取已打开
seed FD、接收packet或检查peer前不可逆收敛为`B/I/A=[] P/E=[CAP_SYS_PTRACE]`，terminal signing前
五组全空；adapter必须在credential drop前以setup `CAP_SETPCAP`清空bounding set，且adapter与service都须在
mapped U内仍持有setup `CAP_SETGID`时先清空supplementary groups，再以`setresgid(g,g,g)`、
`setresuid(u,u,u)`清除全部real/effective/saved/fs credential alias并重验，filtered
stage禁止全部UID/GID/group mutation syscall。旧`custodyCapabilities=[19]`、file capability、U-root、helper
或host fallback均cross-reject。v2只允许
同一authenticated session完成全部lookup后恰一次`sign-acceptance`；adapter不得接收private key、seed、HSM
handle、signer callback或任意message/digest signer。v1/v2 schema、socket kind、frame、descriptor与object key
必须双向cross-reject，且新handoff.authorityStoreService必须exact指向v2 descriptor。

authority equality chain不可省略：RPC返回的policy ref/bytes exact等于handoff.authorityPolicy及
authorityPolicyFd bytes/ref；返回pin ref exact等于handoff.productionProfilePin，且pin.authorityPolicy exact
等于该policy；返回profile ref/bytes exact等于pin.profile，且profile.expectedAuthorityPolicy exact等于该
policy、profile task/operation/gateSet exact handoff；profile.adapter exact等于handoff.adapter；
pin.expectedSnapshotParser、profile.snapshotParser、handoff.snapshotParser逐字段exact；最终acceptance的
adapter/snapshotParser/profile pin与上述对象再次exact。任一相同id不同bytes/ref或链中断均拒绝。

时间equality同样不可省略：`production bundle.verificationInstant = pure result.verificationInstant =
handoff.trustedInstant = clock observation.observedAt = protected acceptance.trustedVerificationInstant`；所有
freshness/expiry/currentness只用这一值，禁止用较早bundle instant通过后报告较晚trusted instant。

policy-pinned adapter在candidate控制外取得exact current production policy ref/store snapshot与revocation
records、trusted verification instant、本协议handoff/FD/session/peer provenance、safe-open C/D archive
及authenticated Git objects、immutable review reports、resolved command/tool/probe/sandbox/verifier/build-policy
bytes；按§8.2 exact projection构造canonical production bundle，调用同一pure verifier，再额外证明上述
provenance/currentness。任一步失败不得返回Verified。既有EligibleStage0Handoff等对象只能作为待验证的
ordinary candidate evidence member，不能授权本API、提供FD或替代本节handoff/store protocol。adapter
executable/closure/buildPolicy须与handoff.adapter逐字段相等（D0-10 roles显式承载；steady-state由外层
policy-pinned protected invocation同样绑定）。protected entry 对 exact D archive运行structural docs_check，
并在外部验证R、GBC与Ledger projection（适用时）；只在protected receipt acceptance后发出acceptance，且不把
external对象写入D。v2 adapter只能把`ADR-0021` terminal response中的exact signed acceptance bytes作为
成功结果；它必须重验service signature、Architecture+Quality+Security fixed quorum、unsigned/signed byte
identity、statement/full digest、current head与durable accepted terminal state，不得自行签名、替换或重排。
docs-check只消费adapter immutable projection并重算subject/ref/candidate equality，fixture在curve前拒绝。

```text
ProtectedTaskQualificationAcceptanceV1 {
  schema: "proof-forge.protected-task-qualification-acceptance.v1",
  id, version: "1.0.0", authorityClass: "production-candidate-bound",
  operation, pureProjectionDigest: Digest, bundleDigest: Digest,
  subjectDigest: Digest, preCloseCandidate: CandidateIdentityV1,
  closeoutCandidate: CandidateIdentityV1|null, trustedVerificationInstant,
  adapter: VerifierIdentityV1, snapshotParser: VerifierIdentityV1,
  productionProfileDigest: Digest,
  productionProfilePin: ContentRefV1,
  ledgerProjectionDigest: Digest|null,
  governanceCompletionDigest: Digest|null,
  provenanceBundleDigest: Digest,
  provenanceRoles: [string], signatures: [ApprovalSignatureV1]
}
```

pureProjectionDigest=`SHA-256("pf.taskqual.pure-projection.v1"||NUL||PF-JCS(pure Verified))`；bundleDigest和
subjectDigest分别是plain SHA-256 exact input bytes；id固定为
`protected-task-qualification-<operation>-<lowercase-task-suffix>`。provenanceBundleDigest是
ProtectedTaskQualificationProvenanceBundleV1 exact canonical input bytes的plain SHA-256；provenanceRoles是
其entries.role按ASCII严格升序的exact nonempty projection。二者共同绑定无法投影为ContentRefV1的raw、
archive、Git object、review与live-session bytes，不为它们制造schema/id/version。ledgerProjectionDigest/
governanceCompletionDigest只在D0-10 receipt protected acceptance为
对应verified full-object digest，其他operation必须均为null。unsigned statement、signature message、full object domains依次为
`pf.taskqual.protected-acceptance-statement.v1`、`pf.taskqual.protected-acceptance-signature.v1`、
`pf.taskqual.protected-acceptance.v1`，使用§1 fixed rule。只有该protected type可称
`production-candidate-bound`并以approval的preCloseCandidate.commit或receipt的closeoutCandidate.commit为
不可替换key；production pure projection仅为
`production-content-verified`，fixture及任何pure projection均不得作为docs acceptance。

### 8.5 publication

producer 临时 publication 仅允许 caller 提供、预先不存在的
`build/task-qualification/<taskId>/qualification.json`、`completion-receipt.json` 或
`d0-10-bootstrap-{approval,receipt}.json`。先在同 parent 私有 `0700` staging，以 `O_EXCL|O_NOFOLLOW`
写 `0400` single-link file，fsync file+dir 后 no-replace rename、再 fsync parent；destination/ancestor
symlink、existing destination、race、fault 均同一 code，旧文件不变，失败时零新输出并只清理由本
writer 持有的 staging。consumer 默认只返回 bytes，不发布，也不得直接写 candidate tree。

closeout commit D 必须把已验证 Q（D0-10 时为 approval）的 exact canonical bytes加入固定路径
`docs/governance/task-qualifications/<taskId>/qualification.json`（D0-10 为
`bootstrap-approval.json`）；该路径必须出现在 AllowedCloseoutPatchV1.allowedPaths。D0-10 repository/external
状态机固定为：

| state | candidate-owned bytes | root structural checker | authority |
|---|---|---|---|
| D | fixed approval存在；row=`done`且IDs为C development IDs加唯一reserved ledgerEvidenceId；该ID尚无Ledger row | 重算approval/row/patch，且只对该signed reserved ID豁免unknown-EV与formal-grade检查；返回typed `StructuralTaskQualificationResultV1{taskId:"TASK-D0-10",candidate:D,reservedEvidenceId,status:"structural-only"}`，CLI固定输出`docs-check: structural-only TASK-D0-10 <EV-id>` | 无；不得称bootstrap/done authority-complete |
| external completion | D不变；authority-owned R、GBC、Ledger projection | 不读取external对象 | protected adapter验证并签发acceptance后可关闭；P不需要 |
| optional P object mirror | 可选路径分别为R=`docs/governance/task-completions/TASK-D0-10/bootstrap-receipt.json`、GBC=`docs/governance/task-completions/TASK-D0-10/receipt.json`、projection=`docs/governance/task-completions/TASK-D0-10/ledger-projection.json` | 对存在对象只做canonical/ref/digest/candidate structural replay | 无新增authority |
| optional P Ledger mirror | 上述三对象必须全部存在且exact，Evidence Ledger增加reserved ID canonical row | 重算projection及row；仍输出structural-only，不证明currentness | 无新增authority；只镜像external acceptance |

steady-state external receipt仍可由optional P加入既有fixed receipt path。P不authoritative、不改变D identity，
也不得导致对象自包含或self-hash。D0-10 optional P若没有Ledger row可镜像三对象任意subset；一旦有reserved
Ledger row则必须exact all-three，禁止orphan row。未来dependency consumer可从authenticated external source
或P取得canonical bytes并按§4重验。临时build publication不能代替candidate-ownedQ/approval或protected
external acceptance。

## 9. Amendment review 状态

本 authority baseline 经多轮 bounded independent review 修复 schema/authorization、bootstrap、
dependency bridge、closeout digest cycle、TST subprofile 与 approval-source findings；最终复审结论为
`COMMIT BASELINE`、P0/P1=0。该结论只批准本规范/任务图基线，不是 TASK-D0-10 实现复审，也不得据此
跳过 freeze→RED→GREEN、protected ceremony 或 closeout 前的独立实现复审。

2026-07-20 R2 amendment 将 oversized positional protected API 拆为 closed-bundle pure verifier 与
protected production adapter，并补齐 fixture/profile/provenance边界；不改变 TASK-D0-10 冻结的 Output、
Tests、Dependencies、Prerequisites或doneWhen。amendment 经多轮 bounded independent review 修复 size、
role/parser、fixture policy、time/revocation、Git ancestry 与 external profile pin 后，最终结论
`SAFE TO COMMIT AMENDMENT`、P0/P1=0；该结论仍不覆盖后续 RED/GREEN implementation。

2026-07-23 首次C3 terminal-signing amendment与`ADR-0021`、PHASE-5同一历史review/acceptance unit，修复
七参数API、lookup-only v1与最终acceptance role signatures之间的不可实现闭环。activation后真实Linux probe
又证明其capability checkpoint不可达；当前三份bytes因此共同转`in_review`，仅纠正同一v2 signer的exec
transition，不改变TASK-D0-10完成面。当前unit只在新的immutable proposed-body commit/HTTPS review取得
P0/P1=0，且metadata-only commit记录Architecture+Quality+Security批准后生效；此前TASK-D0-10保持blocked，
本文workspace草案不得作为implementation authority。
