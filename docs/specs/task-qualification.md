---
id: SPEC-TASKQUAL-001
title: TaskQualificationV1 任务作用域 formal qualification
status: accepted
owner: quality
updated: 2026-07-20
normative: true
approvers: architecture-owner, davirain, quality-owner, security-owner
approvedAt: 2026-07-20
reviewCommit: db4cf6b883196548e46e0e9c7d630ae6b397ee4e
reviewLink: https://ampcode.com/threads/T-019f7dea-e600-77ea-8884-9f35f81f747d
openFindings: none
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
本规格所有 string 禁 NUL/Cc，单项最多 4096 UTF-8 bytes；argv/env value 例外上限 65536 bytes。
array 的 count 在第一次 entry decode/hash/curve work 前检查；标为集合的 array 按所述 ASCII key
严格升序且唯一，producer 不得替 consumer 排序。root canonical bytes 上限 4 MiB，array 通用上限
4096；本规格更小 bound 优先。所有 digest 形式均为
`SHA-256(ASCII(domain) || NUL || PF-JCS(value))`，除明确写 `raw bytes` 者外。

本 accepted amendment 的 authorization 是 Architecture + Quality + Security，registry **只能**是
current activated `BootstrapAuthorityPolicyV1` exact bytes及其外部 expected `ContentRef`。它仅复用
该 policy 的 principal/key/role registry；不得修改、扩展或用 D0-10 查询其恰含 D0-01..06 的
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

command argv count `1..256`，argv[0] 是 absolute canonical executable 并与 `tool` resolved bytes
identity 一致；environment count `0..256`，name 匹配 `[A-Za-z_][A-Za-z0-9_]{0,254}` 并按 name
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
  ruling: ContentRefV1, completionCommit, authorityPolicy: ContentRefV1,
  objectDigest: Digest, objectBytesHex, signatures: [ApprovalSignatureV1]
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
TaskCompletionReceiptV1。objectBytesHex 是 nonempty lowercase even hex，解码后必须 canonical，
`objectDigest=SHA-256("pf.taskqual.dependency-object.v1" || NUL || raw bytes)`；typed task、policy、
receipt、签名与 raw object逐字段 exact join。dependencies 按 taskId 升序且 exact 等于 row direct
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
`closeoutDiffDigest`。D 可由 docs-check 验证文档一致性；Q/receipt 的 protected verifier 验证发生在 candidate
外。D 后才签发 receipt R，R 绑定 C、D、Q、patch、policy、current revocation；**R 不在 D**。
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
  ruling: NormativeDocumentRefV1,
  sourceClosure: RawDocumentRefV1,
  authorityPolicy: ContentRefV1,
  independentReviews: [IndependentReviewRefV1],
  signatures: [ApprovalSignatureV1]
}
D0_10BootstrapApprovalV1 {
  schema: "proof-forge.d0-10-bootstrap-approval.v1", id, version: "1.0.0",
  taskId: "TASK-D0-10", ruling: NormativeDocumentRefV1,
  preCloseCandidate: CandidateIdentityV1,
  taskRow: TaskQualificationTaskRowV1, freezePackage: TaskFreezePackageRefV1,
  verifier: VerifierIdentityV1, protectedConsumer: VerifierIdentityV1,
  verifierClosureDigest: Digest, consumerClosureDigest: Digest,
  tstDocSubprofile: "TST-DOC-001/task-qualification-v1",
  bootstrapGate: D0_10BootstrapGateV1,
  d0_07Bridge: GovernanceBootstrapReceiptDependencyV1,
  allowedCloseoutPatch: ContentRefV1,
  independentReviews: [IndependentReviewRefV1],
  authorityPolicy: ContentRefV1, signatures: [ApprovalSignatureV1]
}
D0_10BootstrapReceiptV1 {
  schema: "proof-forge.d0-10-bootstrap-receipt.v1", id, version: "1.0.0",
  taskId: "TASK-D0-10", ruling: NormativeDocumentRefV1,
  preCloseCandidate: CandidateIdentityV1, closeoutCandidate: CandidateIdentityV1,
  approvalDigest: Digest, allowedCloseoutPatch: ContentRefV1,
  closeoutDiffDigest: Digest,
  authorityPolicy: ContentRefV1, revocationSnapshot: ContentRefV1,
  ledgerGrade: "bootstrap", purpose: "d0-10-taskqual-one-time-bridge",
  issuedAt, signatures: [ApprovalSignatureV1]
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
`docs/governance/task-completions/TASK-D0-10/receipt.json`；digest 对该路径 raw bytes 计算 plain
SHA-256 Digest，consumer 从绑定 candidate archive safe-read、重算并验证对应 closure/receipt。
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
development，只有最终 receipt 的 Ledger projection 获得 D0-10 一次性 bootstrap grade。D0-07 bridge
必须是 authenticated、current、non-revoked GOV-D0CLOSE-001 historical receipt且其 completion commit
为 C ancestor。reviews 必须 P0/P1=0；signatures 使用 §1 exact Architecture+Quality+Security rule。

approval unsigned/signature/full domains依次为 `pf.d0-10-bootstrap-approval-statement.v1`、
`pf.d0-10-bootstrap-approval-signature.v1`、`pf.d0-10-bootstrap-approval.v1`；receipt 对应替换
`approval` 为 `receipt`。checker authority 仅允许 policy-pinned D0-10 bootstrap checker exact
VerifierIdentity 执行本节，不得将它注册为 reusable bootstrap task checker、不得增加 policy
taskRules、不得进入 six-item activation。D0-10 使用与 §6 相同 C→signed approval→single child D→
external receipt→optional P 协议；D diff 只能 exact allowed patch/template。optional P 以
D0_10BootstrapReceiptV1 为 sourceClosure 再签发 GovernanceBootstrapCompletionV1；未来
`governance-bootstrap-receipt` dependency object只接受该 GovernanceBootstrapCompletionV1，不直接
接受 D0_10BootstrapReceiptV1。

## 8. Consumer API、顺序、publication 与错误

唯一 protected positional API（禁止 kwargs/path/env/typed shortcut）为：

```text
verify_task_qualification_v1(
  phase4Bytes, phase5Bytes, freezePackageBytes, commandPolicyBytes,
  evidenceBytes[], dependencyObjectBytes[], reviewReportBytes[],
  authorityPolicyBytes, handoffBytes, verifierClosureBytes,
  qualificationBytes, allowedCloseoutPatchBytes, revocationSnapshotBytes
) -> VerifiedTaskQualificationV1 | Rejected

verify_task_completion_receipt_v1(
  qualificationBytes, allowedCloseoutPatchBytes,
  preCloseArchiveBytes, closeoutArchiveBytes,
  closeoutCommitObjectBytes, closeoutFileSetBytes,
  receiptBytes, authorityPolicyBytes, revocationSnapshotBytes
) -> VerifiedTaskCompletionV1 | Rejected

verify_d0_10_bootstrap_v1(
  phase4Bytes, phase5Bytes, rulingBytes, freezePackageBytes,
  bootstrapCommandPolicyBytes, developmentEvidenceBytes[],
  handoffBytes, sessionContainmentBytes, freshnessBytes,
  privateScanBytes, revocationSnapshotBytes,
  d0_07GovernanceCompletionBytes,
  reviewReportBytes[], authorityPolicyBytes,
  verifierClosureBytes, protectedConsumerClosureBytes,
  approvalBytes, allowedCloseoutPatchBytes
) -> VerifiedD0_10BootstrapApprovalV1 | Rejected

verify_d0_10_bootstrap_receipt_v1(
  approvalBytes, allowedCloseoutPatchBytes,
  preCloseArchiveBytes, closeoutArchiveBytes,
  closeoutCommitObjectBytes, closeoutFileSetBytes,
  receiptBytes, authorityPolicyBytes, revocationSnapshotBytes
) -> VerifiedD0_10BootstrapCompletionV1 | Rejected
```

固定 verifier 顺序：全部 carrier count/type/byte bounds → PF-JCS/closed schema/grammar/order/unique →
raw PHASE-4/5/freeze/row joins → candidate/archive/commit DAG → policy/handoff/verifier closure → command/
raw EV exact partition → dependency raw bytes/DAG/currentness → review raw digest与 P0/P1 → freshness/scan/
revocation → allowed patch → authority signatures（qualification/receipt 最后）→ projection。前一阶段失败
不得进入后续 hash/curve/external lookup。任何失败统一 `PF-TASK-QUALIFICATION-UNVERIFIED`，exit 1，
stdout/stderr 除单行 code 外无对象输出。

producer 临时 publication 仅允许 caller 提供、预先不存在的
`build/task-qualification/<taskId>/qualification.json`、`completion-receipt.json` 或
`d0-10-bootstrap-{approval,receipt}.json`。先在同 parent 私有 `0700` staging，以 `O_EXCL|O_NOFOLLOW`
写 `0400` single-link file，fsync file+dir 后 no-replace rename、再 fsync parent；destination/ancestor
symlink、existing destination、race、fault 均同一 code，旧文件不变，失败时零新输出并只清理由本
writer 持有的 staging。consumer 默认只返回 bytes，不发布，也不得直接写 candidate tree。

closeout commit D 必须把已验证 Q（D0-10 时为 approval）的 exact canonical bytes加入固定路径
`docs/governance/task-qualifications/<taskId>/qualification.json`（D0-10 为
`bootstrap-approval.json`）；该路径必须出现在 AllowedCloseoutPatchV1.allowedPaths，且 docs-check
只从这个 candidate-owned fixed path重算 Q/approval。外部 receipt R 若持久化，只能由 optional P
加入 `docs/governance/task-completions/<taskId>/receipt.json`；未来 dependency consumer 只认该固定
路径的 canonical bytes。临时 build publication 不能代替 candidate-owned Q/approval 或 P 中的 R。

## 9. Amendment review 状态

本 authority baseline 经多轮 bounded independent review 修复 schema/authorization、bootstrap、
dependency bridge、closeout digest cycle、TST subprofile 与 approval-source findings；最终复审结论为
`COMMIT BASELINE`、P0/P1=0。该结论只批准本规范/任务图基线，不是 TASK-D0-10 实现复审，也不得据此
跳过 freeze→RED→GREEN、protected ceremony 或 closeout 前的独立实现复审。
