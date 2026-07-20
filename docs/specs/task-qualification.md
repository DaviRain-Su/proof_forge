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
本规格所有 string 禁 NUL/Cc，单项最多 4096 UTF-8 bytes；argv/env value 例外上限 65536 bytes；
`TaskQualificationContentMemberV1.bytesHex` 是 §8.2 唯一大字符串例外，使用该节独立 pre-decode bound。
array 的 count 在第一次 entry decode/hash/curve work 前检查；标为集合的 array 按所述 ASCII key
严格升序且唯一，producer 不得替 consumer 排序。除 §8 的 inline-hex
`TaskQualificationContentBundleV1` 有明确 260 MiB 例外外，root canonical bytes 上限 4 MiB；array 通用上限
4096；本规格更小 bound 优先。所有 digest 形式均为
`SHA-256(ASCII(domain) || NUL || PF-JCS(value))`，除明确写 `raw bytes` 者外。

本 accepted amendment 的 authorization 是 Architecture + Quality + Security。production verification
与protected acceptance的registry **只能**是current activated `BootstrapAuthorityPolicyV1` exact bytes及其
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
    id: "task-qualification-production-profile-v1", version: "1.0.0",
    kind: "production", namespace, expectedAuthorityPolicy: ContentRefV1,
    adapter: VerifierIdentityV1, signatures: [ApprovalSignatureV1] }
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
除下文production profile内只能由protected adapter从外部pin解析的adapter refs外，每个ContentRef
必须resolve到恰好一个member，按其typed authority重算schema/id/version/digest；禁止untyped optional bag、
selector、未引用member、跨role bytes alias。

下表是operation的exact role set；`evidence/<EV-id>`、`review-report/<reviewerId>/<64hex-report-digest>`、
`dependency/<TASK-id>`、`dependency-archive/<TASK-id>`、`dependency-commit-object/<TASK-id>`、
`ancestry-commit/<40hex>`、`revocation-record/<record-id>`为suffix与decoded object exact join的bounded family。
qualification/approval 的 evidence/review 均 nonempty；receipt operations只验证signed prior subject/ref、
C→D closeout、policy/signatures，evidence/review/dependency/ancestry families恰为零且出现即拒绝，不递归重放
prior qualification/approval closure。qualification/approval dependency三件套exact等于direct dependencies
（可空）；revocation family exact等于snapshot records；除对应行及family count外不得增减。

| operation | required singleton roles | family cardinality |
|---|---|---|
| task-qualification | `phase-4-source`, `phase-5-source`, `freeze-package-source`, `candidate-archive`, `candidate-commit-object`, `authority-policy`, `revocation-snapshot`, `allowed-closeout-patch` | gate-keyed controls and evidence below nonempty; review nonempty; dependency exact row; ancestry exact §8.3; revocation exact snapshot |
| task-completion | `pre-close-archive`, `closeout-archive`, `pre-close-commit-object`, `closeout-commit-object`, `qualification`, `allowed-closeout-patch`, `closeout-file-set`, `authority-policy`, `revocation-snapshot` | evidence/review/dependency/ancestry zero; revocation exact snapshot |
| d0-10-bootstrap-approval | `phase-4-source`, `phase-5-source`, `ruling-source`, `freeze-package-source`, `candidate-archive`, `candidate-commit-object`, `authority-policy`, `revocation-snapshot`, `d0-07-governance-completion`, `d0-07-completion-archive`, `d0-07-completion-commit-object`, `allowed-closeout-patch` | one gate; evidence/review nonempty; dependency is exact D0-07; ancestry/revocation exact |
| d0-10-bootstrap-receipt | `pre-close-archive`, `closeout-archive`, `pre-close-commit-object`, `closeout-commit-object`, `bootstrap-approval`, `allowed-closeout-patch`, `closeout-file-set`, `authority-policy`, `revocation-snapshot` | evidence/review/dependency/ancestry zero; revocation exact snapshot |

receipt rows have family cardinality zero except `revocation-record/*`, which is exact snapshot. For each gateId in
qualification/approval, and no other gateId, exact singletons are `command-policy/<gateId>`,
`resolved-tool/<gateId>`, `resolved-probe/<gateId>`, `sandbox-policy/<gateId>`,
`verifier-executable/<gateId>`, `verifier-closure/<gateId>`, `verifier-build-policy/<gateId>`,
`eligible-stage0-handoff/<gateId>`, `session-containment/<gateId>`, `freshness/<gateId>`,
`private-scan/<gateId>` plus nonempty `evidence/<EV-id>` exact gate partition. Pure bundle不承载额外adapter
bytes；adapter refs只由production profile的external pin解析。Missing, extra, duplicate or wrong suffix is
`members` rejection.

subjectBytes按operation只能是signed qualification、completion receipt、D0-10 approval、D0-10 receipt；
不得在members重复。command refs逐一exact join resolved tool/probe/sandbox/verifier executable/closure/build
policy；所有raw source/control/EV/dependency/review只能从member bytes投影。

role authority 是closed且逐项如下（family继承其prefix行）；raw/archive/git/review不携带也不推导
schema/id/version：

| role/prefix | member kind | parser/schema authority及ID/version | digest/domain | projected ref |
|---|---|---|---|---|
| `phase-4-source`,`phase-5-source`,`ruling-source` | raw-source | 本规格§8.3 accepted Markdown projection；path固定 | plain SHA-256 raw | RawDocumentRefV1/NormativeDocumentRefV1 |
| `freeze-package-source` | raw-source | 本规格§3 TaskFreezePackageV1；repository path固定 | `pf.task-freeze-package-source.v1` raw | TaskFreezePackageRefV1 |
| `evidence/*` | raw-source | local registry下表 RawEvidenceProjectionV1；ID来自row | plain SHA-256 canonical raw | EvidenceRefV1 |
| `review-report/*` | review | local ReviewProjectionV1；reviewerId/digest来自subject ref | `pf.taskqual.review-report.v1` raw | IndependentReviewRefV1 |
| `candidate-archive`,`pre-close-archive`,`closeout-archive`,`dependency-archive/*`,`d0-07-completion-archive` | archive | §8.3 archive map；无schema/id/version | plain SHA-256 archive | CandidateIdentityV1.archiveSha256 |
| `candidate-commit-object`,`pre-close-commit-object`,`closeout-commit-object`,`dependency-commit-object/*`,`d0-07-completion-commit-object`,`ancestry-commit/*` | git-object | §8.3 raw commit；objectId来自Git hash | Git SHA-1 object domain | CandidateIdentityV1.commit/ancestry edge |
| `authority-policy` | typed-content | profile-discriminated：production=`BootstrapAuthorityPolicyV1`；fixture=本节FixturePolicyV1 | production `pf.bootstrap-authority-policy.v1`；fixture `pf.taskqual.fixture-policy.v1` | ContentRefV1 |
| `production-profile` | typed-content | 本节ProductionVerificationProfileV1 | `pf.taskqual.production-profile.v1` | ContentRefV1 |
| `command-policy/*` | typed-content | §3 TaskCommandPolicyV1 | `pf.task-command-policy.v1` | gate.commandPolicy |
| gate control roles、`revocation-snapshot`,`revocation-record/*` | typed-content | local registry下表对应closed type | type表固定domain | gate ContentRefV1 |
| resolved/verifier/protected-adapter roles | typed-content | §2 ContentRefV1/VerifierIdentityV1 joins | declared ContentRef digest / `pf.taskqual.verifier-identity.v1` | command/verifier refs |
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
bundle内嵌`verificationProfile`的canonical PF-JCS bytes必须逐字等于`production-profile` member decoded
bytes；按固定schema/id/version与`pf.taskqual.production-profile.v1`重算的ContentRef必须exact等于
external pin.profile，禁止两份语义等价但bytes不同的profile。

candidate-external pin对象固定为：
```text
ProductionVerificationProfilePinV1 {
  schema: "proof-forge.task-qualification-production-profile-pin.v1",
  id: "task-qualification-production-profile-v1", version: "1.0.0",
  authorityPolicy: ContentRefV1,
  namespace: "task-qualification-production-v1",
  profile: ContentRefV1,
  signatures: [ApprovalSignatureV1]
}
```
unsigned/signature/full domains依次为`pf.taskqual.production-profile-pin-statement.v1`、
`pf.taskqual.production-profile-pin-signature.v1`、`pf.taskqual.production-profile-pin.v1`，按§1 fixed
rule验证。protected adapter不得让bundle选择pin：它从candidate外authority store以exact
`(authorityPolicy,namespace)`唯一current/non-revoked lookup取得expected pin ref/bytes，先验证pin，再要求
bundle `production-profile` bytes/ref exact等于pin.profile。docs-check只接受protected acceptance中同一
profile digest与pin ref并重验签名；candidate内自带但没有external expected ref的profile只可能得到pure
content result，不能成为authority。

fixture只允许`TST-DOC-001/task-qualification-v1`：namespace固定
`task-qualification-fixture-v1`，policy id前缀`task-qualification-fixture-policy-`，candidate commit/tree
首byte分别固定hex `f1`/`f2`，invocation/run前缀`task-qualification-fixture-run-`，keys只能使用RFC8032
§7.1 public test vectors #1–#3。该tuple必须与已提交production policy/ref/namespace/candidate/run静态不相交；
冲突在curve前拒绝。不存在env/CLI/global test-mode switch；fixture永远返回
`fixture-non-authoritative`，不能产生Ledger bootstrap/formal、GovernanceBootstrapCompletion、docs acceptance
或task closeout。steady-state fixture使用synthetic `TASK-D1-FIXTURE`；D0-10 fixture只测one-time
approval/receipt并消费fixture D0-07 GovernanceBootstrapCompletion，二者均不能关闭task。

fixturePolicy使用本规格独立closed schema `proof-forge.task-qualification-fixture-policy.v1`，不冒充
BootstrapAuthorityPolicyV1：恰含`{schema,id,version,namespace,principals,rule,verifierKey}`。principals
恰为RFC8032 §7.1 vectors #1/#2/#3 public keys，依次映射
`(fixture-principal-architecture,fixture-key-architecture,[architecture])`、
`(fixture-principal-quality,fixture-key-quality,[quality])`、
`(fixture-principal-security,fixture-key-security,[security])`；verifierKey固定为RFC8032 vector #4，
不得计入principal/quorum。rule恰为§1三role、minimumDistinctSigners=3，namespace固定fixture值。
fixture control objects使用本地fixture parser/projection与同一rule，不查询production taskRules。
由这些exact bytes以domain `pf.taskqual.fixture-policy.v1`重算的
fixturePolicy必须同时等于profile.fixturePolicy、bundle.expectedAuthorityPolicy、authority member及全部
embedded refs。任何tuple与production policy/ref/namespace/candidate/run碰撞必须在curve前拒绝。
fixture archive中特别允许synthetic PHASE-4/5 rows、freeze、ruling bytes，固定IDs
`PHASE-4-FIXTURE`/`PHASE-5-FIXTURE`/`GOV-TASKQUAL-FIXTURE-001`及paths
`fixtures/task-qualification/{04-task-breakdown.md,05-test-spec.md,freeze.json,ruling.md}`；它们只由本节
local raw projection解析，不是accepted normative documents且不得投影为NormativeDocumentRefV1。
fixture subject内需要NormativeDocumentRefV1 wire位置时，允许投影结构相同但typed为
`FixtureNormativeDocumentRefV1{id,status:"accepted",contentDigest,reviewCommit}`；pure verifier只在fixture
profile接受并投影fixture authority class，production parser与docs-check必须拒绝该type。

### 8.3 projections、trusted time与safe-open语义

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
immutable raw bytes，reviewCommit=C，digest重算，invocationId与implementationInvocationId及其他review
invocation不同。exact P0/P1 parser识别ASCII case-sensitive line `Severity: P0|P1`及`P0:`/`P1:`；任何命中、
UTF-8失败、case-insensitive whole-word `unresolved`或object findings非空均拒绝，不信summary。

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
| evidence | canonical PF-JCS decode → `scripts/evidence_v1_core.py::validate_evidence` → exact canonical re-encode / accepted TRACE-EV-001 | `RawEvidenceProjectionV1{id,gate:{id,taskId,testIds,qualification},repository:{commit,treeObjectId,archive},command,result}`；command按TaskCommandPolicy exact argv/env/tool identity比较 | plain SHA-256 canonical raw |
| authority-policy | profile-discriminated：production=`scripts/bootstrap_task_objects.py::parse_bootstrap_authority_policy`；fixture=本节closed FixturePolicyV1 parser | production complete BootstrapAuthorityPolicyV1；fixture complete FixturePolicyV1；均投影对应ContentRefV1且不得跨profile解析 | production `pf.bootstrap-authority-policy.v1`；fixture `pf.taskqual.fixture-policy.v1` |
| eligible handoff | `scripts/bootstrap_task_objects.py::_preflight_eligible_stage0_handoff` / accepted ADR-0018 consumer pin | complete `EligibleStage0HandoffV1{runId,nonce,candidate,authorityPolicy,authorityStoreService,hostObservation,hostProfile,eligible,tcb,environment,channels,pathnameReopen,fallback}` | `pf.eligible-stage0-handoff.v1` |
| containment | `scripts/formal_evidence.py::parse_session_containment_receipt` / accepted ADR-0018 consumer pin | complete `SessionContainmentReceiptV1{candidate,stage0Handoff,supervisorDigest,rootSessionId,descendants,escapeProbes,startedAt,finishedAt,result,signatures}` | `pf.session-containment-receipt.v1` |
| freshness | `scripts/formal_evidence.py::parse_freshness_authority_snapshot` / accepted ADR-0018 consumer pin | complete `FreshnessAuthoritySnapshotV1{authorityPolicy,observedAt,maximumAgeSeconds,clockSourceDigest,signatures}`；expiry只按ADR-0018公式派生 | `pf.freshness-authority-snapshot.v1` |
| private scan | `scripts/formal_evidence.py::parse_private_scan_receipt` / accepted ADR-0018 consumer pin | complete `PrivateScanReceiptV1{candidate,evidenceCoreDigest,scannerDigest,policy,scannedEvidenceRefs,scannedMembers,findings,result,signatures}` | `pf.private-scan-receipt.v1` |
| revocation snapshot/records | `scripts/formal_evidence.py::parse_revocation_ledger_snapshot` + `scripts/revocation_ledger.py::parse_revocation_record` / accepted ADR-0018 consumer pin | complete snapshot `{authorityPolicy,records,head,recordsDigest,signatures}` 与 record `{id,evidence,revokedUtc,reasonCode,reason,authorityRef,replacement,previousRecordSha256}`；record无自签名/status字段 | `pf.revocation-ledger-snapshot.v1` / `pf.evidence-revocation.v1` |
| governance completion | local §7 parser | complete GovernanceBootstrapCompletionV1 | §7 full domain |
| reviews | local parser | `ReviewProjectionV1{reviewerId,invocationId,reviewCommit,reviewLink,decision,findings,reportDigest}` from raw report + subject ref | `pf.taskqual.review-report.v1` raw |

| object | pure snapshot test at bundle verificationInstant | protected currentness |
|---|---|---|
| EV/review/governance completion | candidate/commit/ref/signature joins；这些wire无通用expiry，不臆造time字段 | immutable source provenance/current policy |
| handoff | candidate/policy/eligible/pathnameReopen/fallback/channel/tcb joins；无通用expiry | live FD/session/peer重新认证 |
| containment | candidate/handoff/result/descendant/probe joins且`startedAt<=finishedAt<=verificationInstant` | live session/peer重新认证 |
| private scan | candidate/evidence/member exact coverage、findings empty、result passed；无通用expiry | protected scanner/source provenance |
| freshness | `observedAt<=instant<expiresAt=observedAt+maximumAgeSeconds` | trusted clock observation |
| revocation snapshot/records | pure count/order/head/aggregate/signature与record chain；当前subject refs不得命中record.evidence；snapshot本身无time字段 | protected authority-store在trusted instant返回同一current head；不得由snapshot自证store currentness |

只有表中实际存在的time字段参与比较；future containment times及freshness equal-expiry拒绝，不给其他类型
添加issuedAt/expiresAt隐式default。

pure verifier只证明caller-supplied instant处content/digest/signature/join；不声称instant可信、FD/session仍
live、source path/safe-open、真实Git graph、external policy currentness或authority-store provenance。

### 8.4 protected production adapter

policy-pinned adapter在candidate控制外取得exact current production policy ref/store snapshot与revocation
records、trusted verification instant、live eligible handoff/FD/session/peer provenance、safe-open C/D archive
及authenticated Git objects、immutable review reports、resolved command/tool/probe/sandbox/verifier/build-policy
bytes；按§8.2 exact projection构造canonical production bundle，调用同一pure verifier，再额外证明上述
provenance/currentness。任一步失败不得返回Verified。它可复用accepted ADR-0018/GOV-D0CLOSE-001 D0-07
protected consumer实现/对象，但只按本节projection纳入raw members，不声称重定义其schema。adapter
executable/closure/buildPolicy须与expectedAdapter逐字段相等（D0-10 roles显式承载；steady-state由外层
policy-pinned protected invocation同样绑定）。production docs-check只消费adapter immutable projection并
重算subject/ref/candidate equality，fixture在curve前拒绝。

```text
ProtectedTaskQualificationAcceptanceV1 {
  schema: "proof-forge.protected-task-qualification-acceptance.v1",
  id, version: "1.0.0", authorityClass: "production-candidate-bound",
  operation, pureProjectionDigest: Digest, bundleDigest: Digest,
  subjectDigest: Digest, preCloseCandidate: CandidateIdentityV1,
  closeoutCandidate: CandidateIdentityV1|null, trustedVerificationInstant,
  adapter: VerifierIdentityV1, productionProfileDigest: Digest,
  productionProfilePin: ContentRefV1,
  provenanceRefs: [ContentRefV1], signatures: [ApprovalSignatureV1]
}
```

pureProjectionDigest=`SHA-256("pf.taskqual.pure-projection.v1"||NUL||PF-JCS(pure Verified))`；bundleDigest和
subjectDigest分别是plain SHA-256 exact input bytes；id固定为
`protected-task-qualification-<operation>-<lowercase-task-suffix>`。provenanceRefs按
`(schema,id,version,digest)` ASCII升序、非空且exact覆盖clock/store/safe-open Git/archive/review/live-session
attestations。unsigned statement、signature message、full object domains依次为
`pf.taskqual.protected-acceptance-statement.v1`、`pf.taskqual.protected-acceptance-signature.v1`、
`pf.taskqual.protected-acceptance.v1`，使用§1 fixed rule。只有该protected type可称
`production-candidate-bound`并被docs-check接受；production pure projection仅为
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
`bootstrap-approval.json`）；该路径必须出现在 AllowedCloseoutPatchV1.allowedPaths，且 docs-check
只从这个 candidate-owned fixed path重算 Q/approval。外部 receipt R 若持久化，只能由 optional P
加入 `docs/governance/task-completions/<taskId>/receipt.json`；未来 dependency consumer 只认该固定
路径的 canonical bytes。临时 build publication 不能代替 candidate-owned Q/approval 或 P 中的 R。

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
