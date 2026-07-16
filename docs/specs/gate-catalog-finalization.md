---
id: SPEC-EVFINAL-001
title: Gate Catalog 与 Development Finalization 规格
status: proposed
owner: quality
updated: 2026-07-16
normative: true
---

# Gate Catalog 与 Development Finalization

## 范围与非目标

本规格定义 `TASK-D0-03/H1e`：把 development gate 的 candidate、host observation、
rendered sandbox policy、launcher invocation、raw streams、tools、artifacts 与 required catalog
绑定为可独立复核的事实。H1e 只允许输出 `development-catalog-verified`，并必须同时输出
`formal-not-verified`。

H1e 不解决 eligible host、formal Stage-0 digest handoff、`setsid()` session containment、
freshness/clock authority、revocation lookup、业务 private-data scanner 或正式 evidence-set
publication。上述任一项未闭合时，所有 formal 输入必须在 preliminary evidence read 后、读取
catalog/claimed bundle members 或创建输出前以 `PF-EVIDENCE-FORMAL-UNVERIFIED` 拒绝。
H1e 也不得生成 `proof-forge.support-evidence-binding.v1`；该 binding 只能由下文所述、在
`TASK-D0-04` bootstrap activation 后由 `TASK-D0-07` 实现的 formal producer 生成。

## 分层协议

```text
sandbox launcher
  -> raw stdout/stderr + sandbox-invocation.v1 receipt
clean-room runner
  -> retained bundle + proof-forge.evidence.v1
gate-catalog.v1 + caller expected digests
  -> single safe-open bundle snapshot
  -> exact catalog evaluation
  -> evidence-finalization.v1 (development only)
```

Schema validation、bundle point-in-time integrity、catalog evaluation 与 formal policy decision
是四个不同结论；任何前层成功都不能改写成后层成功。

## Sandbox invocation receipt

完整 H1e runner 的每个 launcher invocation 必须发布第三个文件：

```text
policies/sandbox-<stage>-<invocation>.receipt.json
```

文件使用 restricted PF JCS canonical bytes，无 trailing newline，current-user `0400`、single
link。stdout/stderr 先发布，receipt JSON 最后发布并作为 complete-set commit marker；普通异常
在 marker 前尽力回滚 raw streams。进程崩溃可能留下没有 marker 的 partial raw files，后续
finalizer 必须拒绝，不能把多文件协议描述成物理原子 rename。Schema 固定为
`proof-forge.sandbox-invocation.v1`。canonical receipt 最大 1 MiB，root object 恰含：

同一 `(stage,invocation)` 在执行前必须以 `O_EXCL|O_NOFOLLOW` 获取 policies 目录内的
`.sandbox-<stage>-<invocation>.reservation`，保持其 fd 打开，并在 spawn 前、publication 前后
核对 token、inode、owner、mode 与 pathname identity。已有或 stale reservation 必须在 spawn
前失败。Launcher 在两份 raw receipt 发布并复核后释放自己的 reservation；release 成功后 raw
路径本身会阻止后来的 launcher 通过 no-clobber preflight，随后才允许发布最后的 metadata marker。
如果 reservation cleanup 失败，必须在 marker 前回滚 raw。只有已经持有 reservation 且证明三条
输出路径起初均不存在的 writer，才可在 publication failure 时清理这三个保留名；未取得
reservation 或在初始 no-clobber 检查前失败的 launcher 不得清理。Reservation 只提供 launcher
间的 single-writer ownership，不是对同 UID hostile actor 的锁，也不是 retained evidence。

```text
{
  schema,
  stage: "materialize" | "core" | "evm-runtime",
  invocation,
  runBindingSha256,
  invocationBindingSha256,
  policy: {path, sha256, size},
  runtimePort: null | integer 1..65535,
  engine: {path: "/usr/bin/sandbox-exec", observedSha256},
  observedLauncherSha256,
  command: {
    argv: [string, ...], argvSha256,
    observedExecutablePath, observedExecutableSha256
  },
  environment: {entries: [{name, value}, ...], sha256},
  durationMs,
  terminal: {exitCode, signal, timedOut},
  stdout: {path, sha256, size, truncated},
  stderr: {path, sha256, size, truncated}
}
```

约束：

- `invocation` 使用 launcher 已有的 lowercase-hyphen ID；receipt 不接受 gate/probe ID 自报。
  Catalog 以后只按 `(stage, invocation)` 映射 required probe。
- `runBindingSha256` 与 `invocationBindingSha256` 必须分别等于本节后述 base run context 与
  per-invocation context 的 domain-separated digest；它们阻止不同 context 之间 mix-and-match，
  但没有 freshness 或受保护 nonce registry，不能声称阻止一整套旧 context/receipt 被完整重放。
  两份 context 在 decode 后、Popen 紧前以及 child cleanup 后都必须再次 stable-read 并确认
  pathname identity；任何 pre-spawn mismatch 必须 no-spawn/no-marker。
- `policy.path` 固定为 `policies/<stage>.sb`；SHA-256/size 来自 launcher 已稳定读取的 exact
  bytes。`runtimePort` 字段始终存在：非 runtime stage 必须为 `null`，`evm-runtime` 必须为
  `1..65535`，并且已与 policy 的唯一 inbound/outbound `localhost:PORT` 规则一致。
- `command.argv` 是作为 sandbox engine argv tail 的 exact payload argv（argv[0] 已替换为验证
  后的 absolute canonical executable）；`environment.entries` 是传给 `Popen` 的完整 allowlisted
  environment，按 name 唯一升序。两者都保留 canonical 原值，不能只保留不可复核的 hash。
- `argvSha256 = SHA256("pf.sandbox.argv.v1" || NUL || canonical_pf_jcs(argv))`；environment 使用
  domain `pf.sandbox.environment.v1` 对 `entries` 计算。`observedExecutableSha256` 是 launcher
  在 spawn 前以 `O_NOFOLLOW` stable-read 得到的 observed pathname bytes，不得命名为
  “actual executed bytes”。launcher 必须在 child 结束后再次核对 pathname identity/metadata；
  由于当前 Python `Popen(pathname)` 仍存在同 UID replace-and-restore 的 TOCTOU 窗口，这只是
  development observation，formal 路径需 fd-based exec 或受保护 spawn handshake。
- `observedExecutablePath` 必须等于 `command.argv[0]`。payload executable 与 engine 在 spawn
  前后、launcher source 在 spawn 前及 child cleanup 后，都要 stable-read/check exact
  `(dev,inode,uid,nlink,mode,size,mtime_ns,ctime_ns)`，且 pathname 仍指向同 inode；receipt 字段
  因此都明确命名为 observed digest，不能声称实际 loaded/executed bytes。完整 Popen vector 可由
  固定 engine path、`-p`、exact captured policy text 和 `command.argv` 重构。
- terminal 三字段始终存在。已提交 receipt 必须 `timedOut=false`，且恰有一个 `exitCode` 或
  `signal` 非 null；普通 nonzero exit 仍应留 receipt。timeout、output-cap、spawn/cleanup failure
  是 launcher internal failure，必须在 marker 前回滚且不得留下 complete receipt。
- stdout/stderr path 固定为对应 raw receipt
  `policies/sandbox-<stage>-<invocation>.stdout.log` 与 `.stderr.log`；digest/size 对 launcher 已
  收集的 exact bytes 计算。当前输出无截断，`truncated=false`。
- `durationMs` 使用 `monotonic_ns()` 向下取整到毫秒：起点紧邻 `Popen` 前，终点在 terminal、
  PGID cleanup、stdout/stderr EOF 及全部 post-run stable checks 后、receipt publication 前；范围
  为 `0..86400000`，只表示 launcher observation，不提供 freshness。

所有 nested objects 同样 `additionalProperties=false`。SHA-256 是 64 位小写 hex；policy/stream
size 分别不超过 128 KiB/4 MiB；exitCode 为 `0..255`、signal 为 `1..255`。receipt path 是
bundle-root-relative normalized POSIX path。argv 非空，每项是无 NUL、最多 64 KiB UTF-8 的
string；environment name 匹配 `[A-Za-z_][A-Za-z0-9_]{0,254}`，value 无 NUL且最多 64 KiB，
entries 按 name 唯一升序。engine/launcher/payload executable 的 observed file 上限为 256 MiB，
超限在 spawn 前失败；该上限属于 catalog/launcher profile，改变时必须升 catalog version。
launcher 必须在 spawn 前以最大宽度 duration/terminal/stream fields
构造 canonical receipt preflight，确保最终一定小于 1 MiB；preflight 失败不得执行 payload。

### Clean-room run context

Runner 在第一次 invocation 前 canonical 发布一个不超过 1 MiB 的 base
`TEMP_ROOT/run-context.json`，schema 为 `proof-forge.clean-room-run-context.v1`，root 恰含：

```text
{
  schema, runId, runRoot,
  catalog: {schema, id, version, contentSha256, catalogDigest},
  gate: {id, taskId, testIds},
  candidate: {commit, treeObjectId, archiveSha256},
  host: {profileId, observationSha256},
  bindings: [{name, type: "string" | "integer" | "sha256", value}, ...]
}
```

`runId` 固定为 `RUN-` 加 32 位 lowercase hex，来自 128-bit CSPRNG；它提供 domain separation，
不提供 freshness 或全局 replay registry。`runRoot` 是 launcher 当时使用的 canonical normalized absolute root；它只
用于复核 argv，不作为可移植 artifact path。catalog ref 使用固定 schema、safe-id、exact SemVer
和两个 SHA-256；candidate 使用 Git object ID/SHA-256；host 使用 safe-id/SHA-256。gate identity
必须等于 selected catalog entry/EV，testIds 唯一升序。base bindings 只允许放第一次 invocation
前已冻结的值，并按 name 唯一升序；runtime port/LAN IP/chain ID 不得提前放入。Digest 固定为：

```text
runBindingSha256 = SHA256(
  ASCII("pf.clean-room-run-context.v1") || NUL || canonical_pf_jcs(context)
)
```

Evidence 必须把 context 作为唯一 `inputs[].role="clean-room-run-context"` 保留；所有 receipt 的
`runBindingSha256` 必须相同并等于该 snapshot 重算值。

因为 runtime port/LAN IP/chain ID 只能在较晚 stage 安全生成，runner 在每次 spawn 前另发布
不超过 1 MiB 的
`TEMP_ROOT/contexts/sandbox-<stage>-<invocation>.json`：

```text
{
  schema: "proof-forge.sandbox-invocation-context.v1",
  runBindingSha256, stage, invocation,
  bindings: [{name, type: "string" | "integer" | "sha256", value}, ...]
}
```

bindings 按 name 唯一升序，type/value 严格对应；dynamic port、adjacent port、LAN IPv4、chain
ID、asset cache 等值只能在需要它们的 invocation context 中出现。Digest 固定为
`SHA256("pf.sandbox.invocation-context.v1" || NUL || canonical_pf_jcs(context))`。同名 binding
在 selected gate 的多个 contexts 中出现时必须 type/value 相等。每个 context 作为唯一
`inputs[].role="sandbox-invocation-context"` retained，且 stage/invocation 必须与 receipt 相等。
Base 禁止 late dynamic names、跨 invocation 同名 binding 一致性与 catalog binding-name joins
需要 selected gate 全集，属于 H1e-b finalizer；H1e-a launcher 只验证当前两份 context，不猜测
业务 binding 名。

H1e-a 的 launcher CLI 使用一组 all-or-none opt-in 参数：

```text
sandbox_exec.py run ...
  --receipt-run-context TEMP_ROOT/run-context.json
  --receipt-invocation-context TEMP_ROOT/contexts/sandbox-<stage>-<invocation>.json
```

两项均省略时保留 H1c legacy two-stream 行为且不得声称 invocation-receipt；只给一项立即失败且
不得 spawn。两项齐全时 launcher 必须逐组件拒绝 symlink，要求 fixed canonical pathname、
current-user `0400` regular single-link、contexts parent `0700`，在 1 MiB 内用 launcher 内独立的
small restricted-PF-JCS codec 拒绝 duplicate/unknown/noncanonical JSON，stable-read 两份 bytes
并重算两个 digest。不得信任 caller 传入的裸 digest。launcher 不普通 sibling-import
`gate_evidence.py`；H1e-b 以共享 golden 验证两个独立 codec 的 canonical bytes/digest 一致。
在 spawn 前还必须 exact join：base `runRoot` 等于 canonical `--temp-root`，invocation context 的
`runBindingSha256` 等于重算的 base digest，context `stage`/`invocation` 等于 CLI values；任一
mismatch 都不得 spawn 或发布 metadata marker。

## Bootstrap authority 与 RequiredTestSetV1

Evidence Ledger 的 `Grade=bootstrap` 不是自证事实。它只能引用本节定义的、由 candidate 外部
authority root 授权并经 eligible Stage-0 直接 handoff 验证的单项 TaskApproval+task receipt；D0-04
还必须引用 six-item approval set+activation receipt。候选仓库内的
`passed` 文本、review prose、`host-bootstrap.lock`、catalog digest 或 verifier 自报 digest 均不能
单独成为该 root。

### 外部 authority policy 与签名 primitive

`BootstrapAuthorityPolicyV1` 是 candidate 外部、content-addressed 的治理根：

```text
ApprovalRoleV1 = "architecture" | "quality" | "security" | "release"

ApprovalSignatureV1 {
  keyId, algorithm: "ed25519", signature
}

ApprovalRuleV1 {
  requiredRoles: NonEmptyArray<ApprovalRoleV1>,
  minimumDistinctSigners: u32
}

BootstrapAuthorityPolicyV1 {
  schema, id, version,
  principals: [{principalId, keyId, publicKey, roles: NonEmptyArray<ApprovalRoleV1>}, ...],
  taskRules: [{taskId, rule: ApprovalRuleV1}, ...],
  requiredTestSetRule: ApprovalRuleV1,
  formalCatalogRule: ApprovalRuleV1,
  bootstrapSetRule: ApprovalRuleV1,
  sessionContainmentRule: ApprovalRuleV1,
  freshnessAuthorityRule: ApprovalRuleV1,
  privateScanRule: ApprovalRuleV1,
  privateScanPolicy: ContentRef,
  revocationSnapshotRule: ApprovalRuleV1,
  authorityStoreService: ContentRef,
  verifier: {id, executableDigest, receiptKeyId, receiptPublicKey}
}
```

wire field order 恰为 declaration order；所有 object `additionalProperties=false`；root `schema` 固定为
`proof-forge.bootstrap-authority-policy.v1`。root `id` 使用
ContentRef id grammar，`principalId`/`keyId`/verifier `id` 使用 safe-id；version 是 exact SemVer。
`publicKey` 是 32-byte Ed25519 key 的 64 位
lowercase hex，`signature` 是 64-byte signature 的 128 位 lowercase hex；receiptPublicKey 采用同一
encoding。principals 中 keyId 与 publicKey 分别全局唯一；同一 principal 的 key rotation 也必须使用
不同 publicKey。receiptKeyId 不得出现在 principals，receiptPublicKey 也不得等于任一 principal
publicKey。principals、taskRules、signatures 分别按 keyId、
taskId、keyId 唯一升序；roles/requiredRoles 按上列 enum 顺序唯一升序。同一 principalId 可轮换
多把 key，但 quorum、minimumDistinctSigners 和 independent review 独立性一律按 distinct
principalId 计算；每个 requiredRole 必须至少由一个拥有该 role 的 distinct principal 覆盖，不能用
同一人多 key 伪造 quorum。对每个 ApprovalRule，requiredRoles 的覆盖集合只能由已通过 Ed25519
验证的 signatures 各自 keyId exact 命中的 principal entry.roles 取并集；未出现在 signatures 的
同 principalId 其他 key roles 不得参与。minimumDistinctSigners 也只按这些有效 signatures 映射出的
distinct principalId 计数。
principals count 必须为 `1..256`。consumer 必须在任何逐 key curve/subgroup 运算前先检查该 count，
并先完成 keyId 顺序/唯一性与 publicKey lowercase-hex 解码/唯一性；重复 key material 不得触发重复的
昂贵曲线验证。每条 ApprovalRule 的 minimumDistinctSigners 不得超过 policy principals 中 distinct
principalId count；超过该 count 的当前不可满足 policy 必须在解析时拒绝，允许的 stronger threshold
仍受此上界约束。该 schema-specific bound 不能被 4 MiB/100k-node 通用 PF-JCS envelope 替代。
严格 Ed25519 验证使用 RFC 8032 pure mode、无 prehash/context；拒绝 non-canonical encoding、
invalid/small-order public key 和 invalid signature。

`taskRules` 必须恰含 `TASK-D0-01` 至 `TASK-D0-06` 六项。每项至少要求 `quality` 且至少两个不同
principal；D0-01/02/06 还必须要求 `architecture`，D0-03/04/05 还必须要求 `security`，D0-04 还必须要求
`release`。`requiredTestSetRule` 与 `formalCatalogRule` 至少要求 `quality+security` 和两个不同
principal；`bootstrapSetRule` 至少要求 `quality+security+release` 和三个不同 principal；
`sessionContainmentRule` 与 `privateScanRule` 至少要求 `quality+security` 和两个不同 principal；
`freshnessAuthorityRule` 至少要求 `quality+release` 和两个不同 principal；
`revocationSnapshotRule` 至少要求 `security+release` 和两个不同 principal。policy 可
增加 key/role/threshold，不能降低
这些 v1 hard minima。

policy content digest 为：

```text
bootstrapAuthorityPolicyDigest = SHA-256(
  "pf.bootstrap-authority-policy.v1" || NUL ||
  canonical_pf_jcs(BootstrapAuthorityPolicyV1)
)
```

它以 `ContentRef{schema="proof-forge.bootstrap-authority-policy.v1",id,version,digest}` 表示，其中
id/version exact 来自 policy 同名字段，digest 必须按上式重算；所有 authorityPolicy ref 必须与该
完整 ContentRef exact equality。
`authorityStoreService` 必须 resolve 到下节 exact service descriptor；handoff 中同名 ref 必须与
policy exact 相等，禁止 Stage-0/caller 临时替换 store namespace、service key 或 executable。
eligible Stage-0 caller 必须从 checkout/archive/candidate 之外的只读 external governance root
取得 expected ContentRef，并经预打开 fd 交给 verifier；不得从 source、catalog、environment、普通
CLI 字符串、仓库 lock 或失败后的 fallback 选择 policy。

authority receipt storage 不是 candidate 可写目录，也不是预先 hash 后再原地修改的 file tree。
Stage-0 必须启动 policy-pinned 的外部 append-only service，并把其已连接 authenticated channel
直接交给 verifier。service identity 的 closed descriptor 为：

```text
AuthorityStoreServiceDescriptorV1 {
  schema, id, version,
  protocol: "pf.authority-store.rpc.v1",
  serviceExecutableDigest: Digest,
  servicePublicKey,
  namespaceId,
  maximumFrameBytes: u32
}
```

schema 固定为 `proof-forge.authority-store-service.v1`；id/version 使用 ContentRef 规则，
servicePublicKey 是 32-byte Ed25519 public key 的 lowercase hex，namespaceId 使用 safe-id，
`maximumFrameBytes` 固定为 `4194304`。descriptor digest 固定为
`SHA-256("pf.authority-store-service.v1" || NUL || canonical_pf_jcs(descriptor))`，以 exact
ContentRef 表示；它绑定 immutable service executable/protocol/namespace identity，不绑定会随 append
变化的 store root、head、receipt set 或 pathname。

`EligibleStage0HandoffV1` 的 closed object 为：

```text
Stage0ChannelV1 {
  role: "authority-policy" | "authority-store" | "candidate-archive" | "evidence-root",
  fd: u32,
  transport: "regular-file" | "authenticated-stream",
  access: "read-only" | "request-response",
  bindingDigest: Digest
}

EligibleStage0HandoffV1 {
  schema, id, version, runId, nonce,
  candidate: CandidateIdentity,
  authorityPolicy: ContentRef,
  authorityStoreService: ContentRef,
  hostObservation: ContentRef,
  hostProfile: ContentRef,
  eligible: true,
  tcb: {
    stage0VerifierDigest, bootstrapVerifierDigest,
    continuationDigest, formalFinalizerDigest
  },
  environment: {
    mode: "env-i", home: "/var/empty", path: "/usr/bin:/bin",
    lcAll: "C", tz: "UTC", network: "deny-default"
  },
  channels: [Stage0ChannelV1; 4],
  pathnameReopen: false,
  fallback: "none"
}
```

schema 固定为 `proof-forge.eligible-stage0-handoff.v1`；root id 使用 ContentRef id grammar，version
使用 exact SemVer，runId 使用 safe-id，
nonce 是 32-byte unpredictable value 的 64 位 lowercase hex。tcb fields 是 Digest；channels 恰按
上述 role 顺序出现，fd 必须大于 2 且唯一。`authority-policy`、`candidate-archive`、`evidence-root`
必须是 `regular-file/read-only`，bindingDigest 分别绑定 policy exact bytes、candidate archive 和
evidence-root manifest；`authority-store` 必须是 `authenticated-stream/request-response`，其
bindingDigest exact 等于 resolved `authorityStoreService.digest`。host observation/profile 必须 safe-read、重算 ref 并
证明当前 host `eligible=true`；candidate archive 与 candidate identity exact join。handoff 只能由
external Stage-0 TCB 在净化环境中生成，通过预开只读 fd/继承的认证 channel 交付并由 consumer
立即对 regular file `fstat`/stable-read、对 service channel 校验 socket type、peer identity 与下述
signed hello；inherited fd set 必须恰为 `0,1,2` 加 channels 中四个 fd，stdin 为 EOF，
stdout/stderr 是 caller-captured write-only channel。禁止 pathname reopen、额外继承 fd、
environment/repository fallback。
policy verifier executableDigest 必须等于 tcb.bootstrapVerifierDigest；本次实际 Stage-0 verifier、
continuation、formal finalizer bytes 必须分别等于其余 tcb digest，禁止进程启动后替换。
Stage-0 启动的 authority-store service executable bytes 必须等于 resolved descriptor
`serviceExecutableDigest`，且 authenticated channel peer 必须是该 Stage-0 child；仅回报同一 public key
但 executable/peer 不一致仍拒绝。
handoff digest 为：

```text
eligibleStage0HandoffDigest = SHA-256(
  "pf.eligible-stage0-handoff.v1" || NUL || canonical_pf_jcs(EligibleStage0HandoffV1)
)
```

它以 exact ContentRef 表示。handoff 不绑定后生成的 approval set，避免
authority-policy → approval-set → handoff hash cycle。

authority-store RPC 使用 authenticated local byte-stream socket；每个 frame 是
`u32be(payload.size) || canonical_pf_jcs(payload)`，payload 不得超过 descriptor maximum。连接后
service 必须先返回 signed hello
`{schema:"proof-forge.authority-store-hello.v1",descriptor:AuthorityStoreServiceDescriptorV1,runId,nonce,signature}`；
consumer 先重算 descriptor ContentRef 并与 external policy、handoff 及 channel bindingDigest exact
比较，再用其中 servicePublicKey 对
`"pf.authority-store-hello.v1" || NUL || canonical_pf_jcs(unsignedHello)` 做 Ed25519 签名。
descriptor/runId/nonce 任一不等于 handoff 即关闭 channel并失败。hello/response 的 signature wire
均是 64-byte Ed25519 signature 的 128 位 lowercase hex，不是 ApprovalSignatureV1 object。

后续 request closed object 恰为
`{schema,requestId,runId,nonce,leaseId,operation,objectSchema,lookupKeyHex,objectBytesHex}`：schema 固定
`proof-forge.authority-store-request.v1`，requestId 为本连接从 0 开始、不得超过 `2^53-1` 的单调递增
UInt64；operation 只允许
`lookup|publish`。普通 request 的 leaseId 为 null；publish 的 leaseId 必须为 null且携带 canonical object raw bytes
的 lowercase even-length hex。`lookupKeyHex` 是对应 receipt schema 冻结的 canonical PF-JCS tuple
bytes 的 lowercase even-length hex，service strict decode/re-encode 后才查询且不接受 pathname。
response schema 固定为 `proof-forge.authority-store-response.v1`，closed object 恰为
`{schema,requestId,runId,nonce,leaseId,result,objects,headSequence,headDigest,signature}`；result 只允许
`stored|found|not-found|conflict|revoked|multiple`，objects 是 raw object bytes hex 的 canonical array，
headSequence 是从 0 开始且不超过 `2^53-1` 的 append-only UInt64，headDigest 是
SPEC-COMMON-001 Digest并绑定该 sequence 的 log head。response runId/nonce 必须与 handoff exact，
signature 使用 service key 对
`"pf.authority-store-response.v1" || NUL || canonical_pf_jcs(unsignedResponse)` 签名。

publish objectSchema 只允许以下 closed allowlist，并必须先 strict decode/re-encode、重算 lookup key/
content digest 与验证对应 authority，禁止 generic signed JSON：

| schema | publish authority |
|---|---|
| `proof-forge.required-test-set.v1` | policy `requiredTestSetRule` |
| `proof-forge.formal-gate-catalog-approval.v1` | policy `formalCatalogRule` |
| `proof-forge.bootstrap-task-approval.v1` | matching policy `taskRules[taskId]` |
| `proof-forge.bootstrap-task-verifier-receipt.v1` | policy verifier receipt key |
| `proof-forge.bootstrap-approval-set.v1` | policy `bootstrapSetRule` |
| `proof-forge.bootstrap-approval-verifier-receipt.v1` | policy verifier receipt key |

因此 quorum-signed BootstrapApprovalSet 在 task receipts 后有独立合法 publication path，activation
verifier 只能消费其 stored+readback exact bytes。key 不存在时 service 原子 no-clobber append object，
返回 `stored`、exact single object、non-null 32-byte random lowercase-hex leaseId 与 head pair；任何
既有 key 返回 `conflict` 且 leaseId=null。stored 后该 namespace 进入连接独占 readback window：
consumer 的下一 request 必须是相同 key/schema、携带该 leaseId 的 lookup；service 不接受其他
request/publisher，返回 `found`、exact single bytes、同 leaseId 和与 stored ack **完全相同** 的
headSequence/headDigest 后才释放 window。普通 lookup/所有其他 result 的 leaseId 必须为 null。
connection close、timeout、wrong next request 或 head change 都使本次 closure 失败；不得用“后继”
但无 consistency proof 的 head 代替 exact equality。lookup 的 zero/revoked/multiple 结果均 fail closed。
request/response ID、
runId/nonce、signature、frame boundary、ack 或 readback 任一错误都不得发布 task closure。service
process/executable 属于 Stage-0 TCB，candidate/verifier 只有该 request-response fd，没有 signer key、
store pathname、directory fd 或 root mutation capability。该协议使 receipt 在 handoff 后追加并回查，
同时不让 handoff digest 预承诺未来 store contents。

### TASK-D0-01 pure object consumer 与 protected integration 边界

`TASK-D0-01` 的首个实现切片是 deterministic、无 I/O 的 bootstrap task object consumer。其
process-local typed input 固定为以下 exact records；它们不是 wire schema，也不是 authority：

```text
BootstrapLedgerSubjectV1 {
  id, taskId, testIds, grade: "bootstrap", result: "passed"
}

BootstrapDocumentSnapshotV1 {id, path, bytes}

BootstrapTaskRowSubjectV1 {
  taskId,
  dependencies: Array<TaskId>,
  prerequisites: Array<{documentId, requiredStatus: "accepted"}>,
  testIds: NonEmptyArray<TestId>,
  evidenceIds: NonEmptyArray<EvidenceId>
}

BootstrapTaskSubjectV1 {
  candidate: CandidateIdentity,
  rootTaskId,
  taskRows: NonEmptyArray<BootstrapTaskRowSubjectV1>,
  evidenceRows: NonEmptyArray<BootstrapLedgerSubjectV1>,
  documents: NonEmptyArray<BootstrapDocumentSnapshotV1>
}

DependencyTaskObjectV1 {
  approvalBytes: bytes,
  receiptBytes: bytes,
  stage0HandoffBytes: bytes
}

BootstrapTaskObjectSetV1 {
  authorityPolicyBytes,
  stage0HandoffBytes,
  requiredTestSetBytes,
  taskApprovalBytes,
  taskReceiptBytes,
  dependencyObjects: Array<DependencyTaskObjectV1>,
  evidenceObjectBytes: NonEmptyArray<bytes>,
  reviewReports: NonEmptyArray<{digest, bytes}>
}

ObjectVerifiedV1 {
  taskId, candidate: CandidateIdentity,
  authorityPolicy: ContentRef,
  requiredTestSet: ContentRef,
  taskApproval: TaskApprovalRefV1,
  taskReceipt: BootstrapTaskVerifierReceiptRefV1,
  stage0Handoff: ContentRef,
  dependencyReceipts: Array<BootstrapTaskVerifierReceiptRefV1>,
  evidence: NonEmptyArray<EvidenceRef>
}
```

`subject.taskRows` 必须恰含 rootTaskId 与其 Task Breakdown DAG 的全部 transitive dependency rows，
按 taskId 唯一升序；每行 dependencies、prerequisites、testIds、evidenceIds 分别按 ID 唯一升序，
且不得引用 taskRows 外 dependency。evidenceRows 按 ID 唯一升序并 exact 等于全部 taskRows 的
evidenceIds；每行必须绑定对应 task，且每个 task 的 evidence testIds 并集 exact 等于该 task row
testIds。documents 的 exact set 是 `PHASE-4`、`PHASE-5` 与全部 taskRows prerequisites 中出现的
document ID，按 ID 唯一升序；path 必须是当前
candidate archive 中的 normalized project-relative path，bytes 必须是 UTF-8。pure consumer 只验证
path lexical normalization/全局唯一、frontmatter 与 document ID、raw bytes 的 normative digest 以及
ref 字段 exact equality；它不把 process-local bytes 自证为 archive member。archive membership、同一次
stable snapshot 与 `reviewCommit` 对 candidate commit 的 ancestor relation 必须由 protected adapter
对预开 candidate archive/commit graph 验证。`candidate` 在 pure API 中只用于 exact join；仅凭
process-local subject 不能证明 archive provenance。

object set 的五个 root bytes 各恰有一个。`dependencyObjects` count 固定为 `0..5`，按每项解析后的
TaskApproval taskId 唯一升序，并 exact 等于 Task Breakdown DAG 的全部 transitive dependency taskId。
每项三个字段都必须是 non-empty canonical PF-JCS bytes；consumer 必须使用该项自己的
`stage0HandoffBytes` 验证其 run-specific TaskApproval/receipt，禁止用 root handoff 或其他 dependency
handoff 代替。root 与全部 dependency 的 handoff ContentRef 以及 `(runId, nonce)` pair 必须分别唯一；
同一次 Stage-0 run 不得为两个 task 重签复用。consumer 从 receipt 中的 TaskApprovalRef 解析同项 approval，memoize 后拒绝 cycle、
missing、duplicate、reorder、extra object 或 bundle 内 task/ref/handoff mismatch。evidence objects 按解析后的
EvidenceRef.id 唯一升序，并 exact 等于 root 与 dependency TaskApproval 引用的全部 evidence refs；每个
task 的 refs 还必须 exact 等于 subject 中该 task 的 evidenceRows。reviewReports 按 digest raw bytes
唯一升序，并 exact 等于 root 与 dependency TaskApproval independentReviews 引用的全部集合。review
report digest 固定为
`SHA-256("pf.independent-review-report.v1" || NUL || bytes)`，wire 使用 SPEC-COMMON-001 Digest。
在 dynamic exact-set join 前，`evidenceObjectBytes` carrier count 固定为 `1..24576`（六项 task 各最多
4096），`reviewReports` 固定为 `1..1536`（六项 task 各最多 256）；over-bound 必须在任何 entry decode、
hash 或 signature work 前拒绝。这两个 coarse upper bound 不替代后续由已验证 approval refs 派生的
更小 dynamic exact count。

内部入口固定为
`verifyBootstrapTaskObjects(subject, objects) -> ObjectVerifiedV1 | Rejected(code)`。consumer 负责
restricted canonical PF-JCS decode/re-encode、closed schema、domain digest、ContentRef、RFC 8032
Ed25519、quorum/role/review independence、document bytes/ref、task row/test/evidence/dependency/
prerequisite exact join，以及 task receipt signature/verifier/result。任一 unknown、duplicate、
noncanonical、missing、extra、unused 或 mismatch 都返回
`Rejected(PF-DOC-EVIDENCE-BOOTSTRAP-UNVERIFIED)`。返回值必须完全由上列已重算 refs 投影，不含
caller 提供的 boolean/tag/opaque payload。`ObjectVerifiedV1.taskId` exact 等于 subject rootTaskId；
dependencyReceipts 是全部 transitive dependency receipts 的 taskId 升序 array；evidence 只投影 root
TaskApproval 的 evidence refs 并按 EvidenceRef.id 升序，dependency evidence 已由各 dependency receipt
的递归验证承诺，不重复并入 root projection。

`ObjectVerifiedV1` 只证明给定对象内容闭合，不证明 subject/candidate snapshot 的来源，也不证明实际
eligible host、handoff fd、authority-store peer/executable、signed hello、publish-readback 或
current/non-revoked lookup；因此不得单独关闭 ledger 或 task。真实 bootstrap closure 还必须由
candidate 外部的 eligible Stage-0 protected adapter 从预开 candidate archive/policy/evidence/store
channels 自行 stable-read 并派生同一 subject/object set，验证 transport 与 execution provenance 后再
调用 pure consumer。该 external adapter 是 D0-01 可独立消费的治理基础设施，不以 `TASK-D0-04`
完成为前置；`TASK-D0-04` 后续拥有仓库内 bootstrap foundation 与 aggregate activation 的实现验收，
不能反向成为 D0-01 的任务依赖。

protected integration 的 handoff 自身 carrier、candidate/evidence snapshot、peer credential、crypto
closure 与 invocation transcript 在冻结并实现前继续 fail closed；不得临时增加
`check(root, capability)`、Python type/tag、CLI/env/path/fd selector 或 repository fallback 来冒充该
边界。公开 `docs_check.py` CLI 仍只接受 `--root`，默认对 bootstrap closure 返回
`PF-DOC-EVIDENCE-BOOTSTRAP-UNVERIFIED`。`TST-DOC-001` 可以直接覆盖 pure object consumer 的 synthetic
positive/mutation matrix，但 `ObjectVerifiedV1` 永远不是 bootstrap evidence；production integration
positive 只能来自上述 candidate-external protected invocation。

### Normative document 与 review references

```text
NormativeDocumentRefV1 {
  id, contentDigest, status: "accepted",
  reviewCommit, reviewLink, approvedAt, approvers: NonEmptyArray<safe-id>
}

IndependentReviewRefV1 {
  keyId, role: ApprovalRoleV1, reviewCommit, reviewLink,
  reportDigest, decision: "approved"
}
```

`NormativeDocumentRefV1.contentDigest` 对 candidate 中 committed exact UTF-8 bytes 计算：

```text
SHA-256("pf.normative-document.v1" || NUL || ASCII(document-id) || NUL || raw-bytes)
```

ref 必须与该文件 accepted frontmatter 的 `id/reviewCommit/reviewLink/approvedAt/approvers` exact
一致；frontmatter 的 scalar `approvers` 必须先按 `DOC-STATUS` 的 exact `, ` 分隔规则解码为
ASCII safe-id array，禁止 trim、重排或接受其他 delimiter，所得 array 原样进入本 object。review
commit 必须是 candidate commit 的 ancestor，且 candidate 中该文档 bytes 仍等于
contentDigest。该 object 字段按 declaration order、`additionalProperties=false`；id 使用 safe-id，
contentDigest 使用 SPEC-COMMON-001 Digest，status exact 为 `accepted`，reviewCommit 恰为 40 位
lowercase hex，approvedAt 是真实 Gregorian `YYYY-MM-DD`。reviewLink 为 1..4096 UTF-8 bytes、无
Unicode General_Category=`Cc` code point 且 scheme 按 ASCII case-insensitive 比较为 `https://`；
approvers count 为 1..256。
approvers、independent reviews 分别按 ASCII ID、keyId 唯一升序。review ref 的
keyId/role 必须由 authority policy 授权，reviewCommit 必须等于正在批准的 candidate commit，
reportDigest 是对应 immutable review report 的 `Digest`；review key 经 policy 映射后只有不同
principalId 才算独立审阅者。

### RequiredTestSetV1 authority

```text
RequiredTestSetV1 {
  schema, id, version,
  phase5Document: NormativeDocumentRefV1,
  authorityPolicy: ContentRef,
  requiredTestIds: NonEmptyArray<TestId>,
  signatures: NonEmptyArray<ApprovalSignatureV1>
}
```

`schema` 固定为 `proof-forge.required-test-set.v1`；id/version 使用 ContentRef 规则。
`phase5Document.id` 必须是 `PHASE-5`。producer 从 accepted PHASE-5 exact bytes 中唯一标题
`## 完整 Test ID Catalog` 下、`### Phase 1 required-set 分母` 前的唯一 `ID | 测试对象` 表提取
TestId；只有冻结的 `TST-A0-001..020` 二十项 development IDs 可从分母排除，任何其他
`TST-A0-*` 形式均拒绝；其余行全部进入 `requiredTestIds`，按 ASCII ID 唯一升序。duplicate
heading/table/ID、malformed row、范围或通配符均拒绝。这样 statement 同时绑定 accepted
PHASE-5 raw content digest、reviewCommit 与 exact required ID denominator。
`requiredTestIds` count 必须为 1..4096；每项必须是 1..127-byte ASCII 且匹配
`TST-[A-Z0-9]+(?:-[A-Z0-9]+)*`，按 ASCII byte 唯一
升序，并禁止任何 `TST-A0-` prefix；development A0 IDs 只能存在于 PHASE-5 完整 catalog，不能进入
signed formal denominator。`signatures` count 必须为
`1..min(resolved BootstrapAuthorityPolicyV1.principals.count, 256)`；consumer 必须在任何
RequiredTestSet signature curve verification 前完成 signature
closed-field、requiredTestIds grammar/order/unique、keyId ASCII 升序唯一、algorithm exact `ed25519`、
signature 128 位 lowercase-hex 与 keyId policy membership 检查。所有 signatures 都必须验签通过；
禁止选择有效子集或忽略 extra/unknown signature。quorum 按有效 signatures 映射出的 distinct
principalId 计算，role coverage 只合并这些 signature exact key entry 的 roles。

signature statement 是移除 `signatures` 后的同序 object；其 digest 与 signature message 为：

```text
requiredTestSetStatementDigest = SHA-256(
  "pf.required-test-set-statement.v1" || NUL || canonical_pf_jcs(statement)
)
signatureMessage = "pf.required-test-set-signature.v1" || NUL ||
                   raw-32-byte(requiredTestSetStatementDigest)
```

signatures 必须按外部 policy 的 `requiredTestSetRule` 验证。完整 content digest 为：

```text
requiredTestSetDigest = SHA-256(
  "pf.required-test-set.v1" || NUL || canonical_pf_jcs(RequiredTestSetV1)
)
```

其 ContentRef exact 为
`{schema="proof-forge.required-test-set.v1",id=record.id,version=record.version,digest=requiredTestSetDigest}`；
statement digest 只用于签名，禁止代替完整 signed-object digest。pure public API 固定为
`parse_required_test_set(requiredBytes, authorityPolicyBytes) -> (RequiredTestSetV1, ContentRef)`；它必须
从 canonical authorityPolicyBytes 重新解析 policy 并重算 policy ContentRef，再与 record 中
authorityPolicy exact join，不接受 caller 提供的 typed policy/ref 或 selector。

该 API 的成功只表示 required-set canonical bytes、所给 policy 内容、签名、role/quorum 与自身
ContentRef 已验证，是后续 object consumer 的 typed intermediate；它不表示 PHASE-5 snapshot 或
candidate ancestry 已验证。consumer 仍须把 phase5Document 与同一 subject document bytes/frontmatter
以及 exact catalog denominator join；reviewCommit 对 candidate commit 的 ancestor relation仍只能由
protected adapter 的预开 commit graph 验证。完成这些 join 前不得把中间值写成 authority verified、
task complete 或 bootstrap closure。

上述 snapshot content parser 的 public API 与 process-local result 固定为：

```text
Phase5SnapshotContentV1 {
  document: NormativeDocumentRefV1,
  requiredTestIds: NonEmptyArray<TestId>
}

parse_phase5_snapshot_content(
  phase5Snapshot: BootstrapDocumentSnapshotV1
) -> Phase5SnapshotContentV1
```

该 API 不接受 caller 构造的 document ref、expected digest、catalog array、boolean 或 selector。
snapshot 必须是 exact `BootstrapDocumentSnapshotV1`（禁止 subclass/tag），id exact 为 `PHASE-5`，path exact 为
`docs/05-test-spec.md`，bytes 为 1..4 MiB、无 UTF-8 BOM/NUL/CR、以 LF 结尾的 strict UTF-8。raw bytes
digest 按 `pf.normative-document.v1` domain 重算。这里的 frontmatter grammar 是 formal PHASE-5
authority snapshot 的 canonical subset；普通 docs-check 接受更宽语法也不构成 formal consumer 接受。

frontmatter opening/closing delimiter 必须是 byte-exact `---\n` / 首个 `\n---\n`；其中每个非空行
必须在首个 byte-exact `: ` 处分成 key/value，key/value 均非空且无 leading/trailing whitespace，禁止
quote stripping、重复 key 与 unknown key；value 中后续 `:` 是普通内容，key declaration order 不影响
解析。字段集合必须 exact 为
`id/title/status/owner/updated/normative` 加五个 accepted 字段；
`id/status/normative/openFindings` 分别 exact 为 `PHASE-5`/`accepted`/`true`/`none`，两个日期均为真实
Gregorian `YYYY-MM-DD`，其余 approval scalar 按 `DOC-STATUS` 规则验证。解析出的
`id/reviewCommit/reviewLink/approvedAt/approvers` 和重算的 raw digest 构成返回的
`NormativeDocumentRefV1`；该单参 parser 自身不接收或比较 signed ref。

catalog 解析不实现 Markdown renderer，而对 frontmatter 后 body 做单次有界 raw-line scan。只有
byte-exact raw line 才识别为 heading/header/delimiter；parser 不维护 fence/comment/inline-code state，
因此位于多行 fence/comment 之间的 exact reserved line 仍会被识别并计数，禁止通过 renderer 差异隐藏
第二份 catalog。scanner 对全部 raw bytes（含 frontmatter）
要求每个 LF-terminated line 在去掉 LF 后为 0..65536 UTF-8 bytes，`rawBytes.count(0x0A)` 为
1..100000，且不得使用按每个 token 反向重扫 prefix 的算法。raw LF-split line 上 byte-exact、各恰
出现一次且顺序正确的
`## 完整 Test ID Catalog` 与 `### Phase 1 required-set 分母`，且后者必须是 catalog section 的首个
raw H3 heading。raw H3 grammar 固定为 line 从 byte 0 开始 `###`，其后立即为 line end、ASCII SP 或
ASCII HTAB；`####` 不是 H3，带 leading whitespace 的 line 也不作隐式 Markdown 修复。两者之间必须
只有一个 byte-exact
`| ID | 测试对象 |` header，下一行 exact 为 `|---|---|`；其后 non-empty contiguous rows 必须逐行是
exact two-cell `| <TestId> | <non-empty-description> |`，table 结束至分母标题前只允许空行。header 前
或 table 结束后出现任何首 byte 或尾 byte 为 `|` 的 raw line、额外 header/delimiter/table、空
description、额外 cell、malformed/range/wildcard
ID、重复 ID 全部拒绝；description 必须为 1..4096 UTF-8 bytes、无 `|` 或 Unicode `Cc` code point。
所有 catalog TestId 先按 1..127-byte ASCII exact grammar 验证；development
例外集合必须是 exact `TST-A0-001..020`，缺少其中任一项或出现其他 `TST-A0-*` 均拒绝。其余 ID
按 ASCII 排序后必须 non-empty、count 1..4096，总 catalog rows 必须为 21..4116。

可正向验收两项 exact compare 的纯组合入口固定为：

```text
parse_document_bound_required_test_set(
  requiredBytes,
  authorityPolicyBytes,
  phase5Snapshot: BootstrapDocumentSnapshotV1
) -> (RequiredTestSetV1, ContentRef)
```

该入口先调用 `parse_phase5_snapshot_content`，再调用 two-byte-input
`parse_required_test_set` 所共用的 internal structural preflight，在任何 RequiredTestSet signature
verification 前要求 `snapshotContent.document == preflight.phase5Document` 与
`snapshotContent.requiredTestIds == preflight.requiredTestIds`，然后才执行全部 signatures、role/quorum
与完整 ContentRef finalization；它不接受 expected ref/IDs 或 caller 构造的 typed intermediate。
two-byte-input public parser 同样使用该 internal preflight，但在无 snapshot join 的 intermediate 模式下
直接继续 signature finalization。禁止为了组合该 API 而先调用已经完成验签的 public parser，再做
事后 compare。`verifyBootstrapTaskObjects` 必须对同一 invocation 的 subject PHASE-5
snapshot 与 object bytes 调用该组合入口。snapshot type/size/UTF-8/frontmatter/heading/table/row/
duplicate/denominator 结构预检必须在任何 RequiredTestSet signature curve verification 前完成。
`Phase5SnapshotContentV1` 与组合入口成功都不是 archive
authority：snapshot 仍是 process-local bytes，candidate archive membership、single stable snapshot 与
reviewCommit ancestry 继续只能由 protected adapter 证明。

### FormalGateCatalogApprovalV1 authority

RequiredTestSet 只锁定测试 ID 分母，不能授权一份把全部 ID 绑定到 no-op/弱 command policy 的
catalog。formal catalog 必须另有单向签名 approval：

```text
GateCatalogRefV1 {schema, id, version, contentSha256, catalogDigest}

FormalGateCatalogApprovalV1 {
  schema, id, version,
  authorityPolicy: ContentRef,
  requiredTestSet: ContentRef,
  catalog: GateCatalogRefV1,
  signatures: NonEmptyArray<ApprovalSignatureV1>
}
```

schema 固定为 `proof-forge.formal-gate-catalog-approval.v1`；id/version 使用 ContentRef id grammar/
exact SemVer。catalog ref 必须指向后文 canonical
formal GateCatalog exact bytes/identity；`contentSha256` 与 `catalogDigest` 都使用 GateCatalog 已冻结的
64 位 lowercase hex SHA-256 wire form，禁止改名为 `contentDigest` 或换成 SPEC-COMMON Digest wire
form。requiredTestSet 必须 resolve 并通过前节全部 authority 验证。
signature statement 移除 `signatures`，exact derivation 为：

```text
formalCatalogApprovalStatementDigest = SHA-256(
  "pf.formal-gate-catalog-approval-statement.v1" || NUL || canonical_pf_jcs(statement))
formalCatalogApprovalSignatureMessage =
  "pf.formal-gate-catalog-approval-signature.v1" || NUL ||
  raw-32-byte(formalCatalogApprovalStatementDigest)
formalCatalogApprovalDigest = SHA-256(
  "pf.formal-gate-catalog-approval.v1" || NUL ||
  canonical_pf_jcs(FormalGateCatalogApprovalV1))
```

签名满足 policy `formalCatalogRule`。RequiredTestSet 不回指 catalog，catalog approval 才回指二者，
因此没有 digest cycle；caller 不能自行生成该 approval。

### TaskApprovalV1、单任务 receipt 与 BootstrapApprovalSetV1

```text
TaskApprovalRefV1 {taskId, digest}
BootstrapTaskVerifierReceiptRefV1 {taskId, id, digest}

TaskApprovalV1 {
  schema, taskId,
  candidate: CandidateIdentity,
  taskBreakdown: NormativeDocumentRefV1,
  requiredTestSet: ContentRef,
  testIds: NonEmptyArray<TestId>,
  evidence: NonEmptyArray<EvidenceRef>,
  dependencyCompletions: Array<BootstrapTaskVerifierReceiptRefV1>,
  prerequisiteDocuments: Array<NormativeDocumentRefV1>,
  authorityPolicy: ContentRef,
  stage0Handoff: ContentRef,
  independentReviews: NonEmptyArray<IndependentReviewRefV1>,
  signatures: NonEmptyArray<ApprovalSignatureV1>
}

BootstrapTaskVerifierReceiptV1 {
  schema, id, taskId,
  candidate: CandidateIdentity,
  authorityPolicy: ContentRef,
  requiredTestSet: ContentRef,
  taskApproval: TaskApprovalRefV1,
  stage0Handoff: ContentRef,
  dependencyCompletions: Array<BootstrapTaskVerifierReceiptRefV1>,
  verifierDigest: Digest,
  result: "task-approved",
  signature: ApprovalSignatureV1
}

BootstrapApprovalSetV1 {
  schema, id, version,
  candidate: CandidateIdentity,
  authorityPolicy: ContentRef,
  taskBreakdown: NormativeDocumentRefV1,
  requiredTestSet: ContentRef,
  stage0Handoff: ContentRef,
  taskApprovals: [TaskApprovalV1; 6],
  taskReceipts: [BootstrapTaskVerifierReceiptRefV1; 6],
  signatures: NonEmptyArray<ApprovalSignatureV1>
}
```

TaskApproval schema 固定为 `proof-forge.bootstrap-task-approval.v1`。taskId 只允许精确 D0-01..06；
`TaskApprovalRefV1` wire object 恰为 `{taskId,digest}`，digest 使用 SPEC-COMMON-001 Digest wire form。
taskBreakdown.id 必须是 `PHASE-4`。testIds、dependencyCompletions、prerequisiteDocuments 必须分别
exact 等于 accepted Task Breakdown 对应行的 Tests、Dependencies、Prerequisites，按 ID 唯一升序；
requiredTestSet 必须 resolve 到前节签名验证通过的 exact `RequiredTestSetV1`，其 authorityPolicy
与 TaskApproval exact 相等，且本 task 每个 testId 都必须是 requiredTestIds 成员。task verifier
必须在产生每个 task receipt 前重新验证 PHASE-5 document ref、statement digest、policy/signatures 与
membership，不能推迟到 D0-04 aggregate activation。
每个 dependency completion 必须 safe-read、认证并重算对应既有
`BootstrapTaskVerifierReceiptV1`，且 receipt taskId exact 等于 dependency ID、result 为
`task-approved`、未撤销；dependency receipt 的 candidate、authorityPolicy、requiredTestSet 必须与
当前 TaskApproval exact 相等，因此新 candidate 必须按依赖拓扑重验 completion，不能复用旧
candidate receipt。evidence
中的 canonical immutable `proof-forge.evidence.v1` 必须由 safe snapshot 重算 EvidenceRef digest，
其 candidate、gate.taskId、passed result 与 testIds exact；bootstrap 是控制面 approval grade，
因此 raw EV qualification 保持 `development`，不能伪造第三种 qualification。全部 evidence testIds
的并集必须 exact 覆盖 task testIds。

stage0Handoff schema 固定为 `proof-forge.eligible-stage0-handoff.v1`，必须由 candidate 外部 caller
直接产生并证明 eligible host、candidate identity、authority policy ref、pinned verifier digest 与
无 environment/repository fallback。每个 TaskApproval 绑定本次 task completion run 的 exact
handoff；该 run-specific binding 是有意的，每次重验都必须取得在线 distinct-principal quorum，旧
run approval 不得作为新 candidate 的 approval 复用。independentReviews 与 signatures 的
principalId 集合 exact 相等，并满足 policy 对该 task 的 rule。

TaskApproval 的 signature statement 是移除 `signatures` 后的同序 object：

```text
taskApprovalStatementDigest = SHA-256(
  "pf.bootstrap-task-approval-statement.v1" || NUL || canonical_pf_jcs(statement)
)
taskApprovalSignatureMessage =
  "pf.bootstrap-task-approval-signature.v1" || NUL ||
  raw-32-byte(taskApprovalStatementDigest)
taskApprovalDigest = SHA-256(
  "pf.bootstrap-task-approval.v1" || NUL || canonical_pf_jcs(TaskApprovalV1)
)
```

首个 signed-content consumer 的 public API 固定为：

```text
parse_task_approval(
  taskApprovalBytes,
  requiredTestSetBytes,
  authorityPolicyBytes,
  phase5Snapshot: BootstrapDocumentSnapshotV1
) -> (TaskApprovalV1, TaskApprovalRefV1)
```

四个参数均为 required positional input；API 不接受 caller 构造的 policy/required-set typed value、
ref、expected IDs/candidate、boolean 或 selector。`EvidenceRef`、`TaskApprovalRefV1`、
`BootstrapTaskVerifierReceiptRefV1`、`IndependentReviewRefV1` 与 `TaskApprovalV1` 都是 exact frozen typed
records，wire array 进入 typed tuple，不得保留 dict/opaque payload。

schema-specific bounds 固定为：`testIds` 与 `evidence` 各 `1..4096`，`dependencyCompletions` `0..5`，
`prerequisiteDocuments` `0..256`；reviews 为
`1..min(distinct policy principalId count,256)`，signatures 为
`1..min(policy principal-entry count,256)`。test/evidence/dependency/prerequisite/review/signature
分别按 TestId、EvidenceRef.id、taskId、document id、keyId、keyId 唯一 ASCII 升序；review
principalId 与 reportDigest 也必须分别唯一。EvidenceRef.id 与 BTV id 中的 `YYYYMMDD` 必须是真实
Gregorian date；BTV id exact grammar 为 `BTV-[0-9]{8}-[0-9]{4}`。任何 count/order/duplicate/closed-field/
scalar error 都必须在 TaskApproval signature curve work 前拒绝。

每个 independent review key 必须 exact 命中 policy principal entry，显式 role 必须属于该 exact key 的
roles，decision exact 为 `approved`，reviewCommit 使用 40/64 位 lowercase GitObjectId grammar 并 exact
等于 TaskApproval candidate.commit，reviewLink/reportDigest 按前述规则验证。reviews 中 principalId
必须唯一；review principalId set 与 signatures 映射出的 distinct principalId set exact 相等，因此
threshold 自动与 signatures 相同。显式 review role 只证明该 review key 对该角色获授权，不另行把
单值 review role 集合当作 task rule role coverage；task rule 的 requiredRoles 只由已验证 signatures
各自 exact key entry 的完整 roles 覆盖。rotation 可由 review key 与 signature key 映射到同一
principalId，不要求 keyId set 相等；同一 principal 的多 signature key 始终只计一次。所有 signatures
必须有效，禁止选择有效子集。

实现顺序固定为：先完成 TaskApproval canonical/closed-field/bounds/scalar/array/signature-syntax structural
preflight 与 PHASE-5 snapshot parse，再共用 RequiredTestSet internal preflight；随后 exact join snapshot
document/denominator、policy ref、required-set ref 和 task test membership，并解析 review/signature policy
membership/rule；完成全部上述结构检查后，先 finalize 全部 RequiredTestSet signatures，再 finalize 全部
TaskApproval signatures 和完整 approval digest。禁止先调用已完成验签的 public document-bound parser，
再解析 malformed TaskApproval。

该 API 成功只表示 policy + document-bound RequiredTestSet + signed TaskApproval 自身内容闭合；它不验证
PHASE-4 raw snapshot/task row、EV raw bytes/test union、dependency approval/receipt、review report bytes、
handoff bytes/provenance、archive membership、single snapshot、reviewCommit ancestry、revocation 或
protected execution，也不产生 task closure。上述对象只能由后续同一次 pure object consumer join。

单项 D0 `done` 的 authority 是 exact TaskApproval 加其 authenticated task receipt，而不是六项
aggregate set。Task receipt schema 固定为 `proof-forge.bootstrap-task-verifier-receipt.v1`，ID 使用
`BTV-YYYYMMDD-NNNN`。receipt 的 task/candidate/policy/approval/handoff/dependency refs 必须与
TaskApproval exact join，requiredTestSet 也必须与 TaskApproval 及 resolved signed record exact；
verifierDigest 与 policy/handoff pinned verifier exact；signature 使用 policy
verifier receipt key 与 Ed25519。signature statement 移除 `signature`，exact derivation 为：

```text
bootstrapTaskReceiptStatementDigest = SHA-256(
  "pf.bootstrap-task-verifier-receipt-statement.v1" || NUL ||
  canonical_pf_jcs(statement))
bootstrapTaskReceiptSignatureMessage =
  "pf.bootstrap-task-verifier-receipt-signature.v1" || NUL ||
  raw-32-byte(bootstrapTaskReceiptStatementDigest)
bootstrapTaskReceiptDigest = SHA-256(
  "pf.bootstrap-task-verifier-receipt.v1" || NUL ||
  canonical_pf_jcs(BootstrapTaskVerifierReceiptV1))
```

首个 receipt signed-content consumer 的 public API 固定为：

```text
parse_bootstrap_task_verifier_receipt(
  taskReceiptBytes,
  taskApprovalBytes,
  requiredTestSetBytes,
  authorityPolicyBytes,
  phase5Snapshot: BootstrapDocumentSnapshotV1,
  stage0HandoffBytes
) -> (BootstrapTaskVerifierReceiptV1, BootstrapTaskVerifierReceiptRefV1)
```

六个参数均为 required positional input。除既有 process-local `phase5Snapshot` 外，其余输入必须是
canonical raw bytes；API 不接受 caller 构造的 policy/approval/required-set/handoff typed value、ref、
expected candidate/digest、boolean 或 selector。`Stage0ChannelV1`、
`EligibleStage0TcbV1{stage0VerifierDigest,bootstrapVerifierDigest,continuationDigest,formalFinalizerDigest}`、
`EligibleStage0EnvironmentV1{mode,home,path,lcAll,tz,network}`、`EligibleStage0HandoffV1` 与
`BootstrapTaskVerifierReceiptV1` 都必须成为 exact frozen typed records，wire array 进入 typed tuple，不得
保留 dict/opaque payload。

handoff content preflight 必须按本节既有 `EligibleStage0HandoffV1` closed schema 验证 exact field set、
scalar 与四通道顺序/唯一性。content-level exact joins 固定为：handoff `candidate` 与 TaskApproval
candidate 相等；`authorityPolicy` 与 raw policy 重算 ContentRef 相等；`authorityStoreService` 与 policy
相等；`tcb.bootstrapVerifierDigest` 与 policy verifier `executableDigest` 相等；`authority-policy`、
`candidate-archive`、`authority-store` 三个 channel `bindingDigest` 分别等于 policy ContentRef digest、
candidate `archiveDigest` 与 authority-store ContentRef digest。`evidence-root` binding 只在本 API 做 Digest
syntax/content preservation，raw evidence-root manifest join 由后续 object graph 完成。handoff 完整
ContentRef digest 必须按本节 `pf.eligible-stage0-handoff.v1` domain 重算，并与 TaskApproval/receipt 的
`stage0Handoff` exact equality；不得从两个 ref 相等推断 raw bytes 已验证。

receipt `id` 必须匹配 `BTV-[0-9]{8}-[0-9]{4}` 且日期是真实 Gregorian date；
`dependencyCompletions` count 为 `0..5` 并按 taskId 唯一 ASCII 升序。receipt 的 schema、taskId、
candidate、authorityPolicy、requiredTestSet、stage0Handoff、dependencyCompletions、verifierDigest、result
与 singular signature 都是 closed/scalar preflight 的一部分；`result` exact 为 `task-approved`。
signature 必须使用 policy verifier 的 exact `receiptKeyId`、`receiptPublicKey` 与 pure Ed25519；它不参与
principal quorum，也不得命中普通 principal key。receipt 的 task/candidate/policy/required-set/handoff/
dependency refs 必须与已验证 TaskApproval exact，`verifierDigest` 必须同时等于 policy verifier 与
handoff `tcb.bootstrapVerifierDigest`。

实现顺序固定为：先完成 receipt canonical/closed-field/bounds/scalar/signature-syntax structural
preflight，再完成 TaskApproval structural preflight、PHASE-5 snapshot parse、RequiredTestSet/policy internal
preflight 与 raw handoff content preflight；在任何 approval-signature curve work 前完成所有不依赖最终
TaskApproval digest 的 exact joins、policy membership/rule 与 receipt-key selection；其中 receipt
`taskApproval.taskId` 必须与 receipt/approval `taskId` pre-curve exact，不能与 digest 一起延后。随后依次
finalize 全部 RequiredTestSet signatures、全部 TaskApproval signatures 与 TaskApproval digest；再只对
receipt `taskApproval.digest` 做 final exact join，验证 receipt signature，最后才计算 receipt 完整
digest/ref。malformed receipt
不得先触发 RequiredTestSet/TaskApproval curve work；wrong `taskApproval.digest` 必须在 TaskApproval finalize
后、receipt curve work 前拒绝；禁止调用已完成验签的 public TaskApproval parser 后才解析 malformed
receipt。

该 API 成功只证明 raw policy、PHASE-5 raw snapshot、signed RequiredTestSet、signed TaskApproval、raw
handoff content 与 signed receipt 六项输入的内容闭合。它不证明 Stage-0 carrier/fd/fstat/stable-read、
host eligibility 的真实性、
service peer/executable/signed hello、publish ack/exact readback/current/non-revoked lookup，也不验证 PHASE-4
raw row、EV bytes/test union、dependency approval/receipt raw bytes、review report bytes、archive membership、
single snapshot、reviewCommit ancestry，或 `authorityPolicyBytes` 的 external governance-root provenance 与
expected-ref selection；因此仍不产生 task closure 或 `ObjectVerifiedV1`。

protected service 的 task lookup key 固定为
`(authorityPolicy,requiredTestSet,taskId,candidate,taskApproval,stage0Handoff)`；verifier 必须通过
handoff 的预开 `authority-store` RPC 先 publish signed receipt、验证 stored ack，再 lookup 得到唯一、
当前、non-revoked exact bytes。caller 不能选择 path/store/root/service；read-only file/directory fd、
未签 response 或省略 publish-readback 都拒绝。
`BootstrapTaskVerifierReceiptRefV1` wire object 恰为 `{taskId,id,digest}`，digest 使用
SPEC-COMMON-001 Digest wire form；consumer 必须 safe-read 该 receipt 并重算全部三个字段；dependency
completion refs 递归执行同一验证，但按 Task Breakdown DAG memoize，禁止循环或遗漏。

BootstrapApprovalSet schema 固定为 `proof-forge.bootstrap-approval-set.v1`；`id` 使用
SPEC-COMMON-001 ContentRef id grammar，`version` 是 exact SemVer，必须恰含按 taskId 升序的六项
approval 和按 taskId 同序的六项 authenticated task receipt。aggregate activation 必须在
一个 final candidate/run 中按 Task Breakdown 依赖拓扑重新签发/验证六项 approval+receipt；每项
candidate/policy/task document/stage0Handoff 都与 set root exact 相等，receipt 必须 exact 引用并认证
同序 approval；每项 approval/receipt 的 requiredTestSet 必须与 set root exact 相等。历史上用于逐项
`done` 的旧 candidate receipt 可保留审计，但不能进入当前 set。
requiredTestSet 必须 resolve 到前节通过签名验证的 exact object；每个 task testId 都必须属于该 set。
set signature statement 同样移除 signatures，并满足 policy `bootstrapSetRule`。exact derivation 为：

```text
bootstrapApprovalSetStatementDigest = SHA-256(
  "pf.bootstrap-approval-set-statement.v1" || NUL || canonical_pf_jcs(statement))
bootstrapApprovalSetSignatureMessage =
  "pf.bootstrap-approval-set-signature.v1" || NUL ||
  raw-32-byte(bootstrapApprovalSetStatementDigest)
bootstrapApprovalSetDigest = SHA-256(
  "pf.bootstrap-approval-set.v1" || NUL ||
  canonical_pf_jcs(BootstrapApprovalSetV1)
)
```

set 的唯一 ContentRef 为
`{schema="proof-forge.bootstrap-approval-set.v1",id,version,digest=bootstrapApprovalSetDigest}`；
所有 set consumer 必须从 authenticated authority-store RPC 返回的 exact immutable bytes strict decode、
重算 digest 与六项 closure，不能从 ref、caller 或 manifest 自报字段构造 set。
该 schema 的唯一 authority-store lookup tuple 固定为单成员 array `[setContentRef]`，其中
`setContentRef` 必须是上式完整 closed object；`lookupKeyHex` 必须恰为
`lowercase_hex(canonical_pf_jcs([setContentRef]))`。publish ack、同 lease 的独占 readback 以及后续
普通 lookup 都必须使用完全相同的 `objectSchema` 与 key bytes，禁止按裸 id、digest、candidate 或
caller alias 建立第二索引。

关闭规则没有 aggregate 前置死锁：D0-01/02/03/05/06 各自只要求本 task approval+task receipt，且
dependencyCompletions 已认证既有依赖。D0-04 唯一 owned test 是 `TST-BOOTSTRAP-001`；它必须在
没有任何既有 aggregate activation 的输入空间中验收 foundation，不得读取、查询或要求本次即将
产生的 set/activation。该测试的 activation positive vector 只能使用与 production lookup tuple
不相交的 fixture candidate/policy/namespace，fixture receipt 永不满足当前 D0 closure。外部 verifier
在该 pre-activation evidence 通过后签发 D0-04 的 TaskApproval
与 task receipt，随后才构造六项 ApprovalSet，最后取得下节 aggregate activation receipt。只有
D0-04 的 `done` 额外要求该 set 与 activation receipt。该顺序固定为
`D0-04 TaskApproval → D0-04 task receipt → six-item set → set activation receipt`，set/receipt
不回填到任何 TaskApproval 或 task receipt statement。`TASK-D0-07` 不是 bootstrap-set member；
它依赖已关闭 D0-04 与 current、non-revoked activation，并在其后以 formal evidence 验收
`TST-ISO-002`/`TST-EVIDENCE-002`。

### Bootstrap verifier receipt 与 zero-trust ledger rule

外部 policy 锁定的 verifier 必须在 eligible Stage-0 handoff 的同一次 protected execution 中对
policy、PHASE-4/5 documents、required test set、六项 task approvals、EV bytes、review reports 与
六项 task receipts、签名做一次 safe-open snapshot，并输出 aggregate activation：

```text
BootstrapApprovalVerifierReceiptV1 {
  schema, id,
  candidate: CandidateIdentity,
  authorityPolicy: ContentRef,
  requiredTestSet: ContentRef,
  approvalSet: ContentRef,
  stage0Handoff: ContentRef,
  verifierDigest: Digest,
  taskApprovals: [TaskApprovalRefV1; 6],
  taskReceipts: [BootstrapTaskVerifierReceiptRefV1; 6],
  result: "bootstrap-approved",
  signature: ApprovalSignatureV1
}
```

schema 固定为 `proof-forge.bootstrap-approval-verifier-receipt.v1`；receipt ID 使用
`BAV-YYYYMMDD-NNNN`。字段与上游对象必须 exact join，task refs 按 ID 升序且 digest 重算相等，
taskReceipts 必须与 set 的六项 receipt exact 同序并逐项认证；verifierDigest 必须等于 external policy
与 stage0Handoff 锁定值。signature key/算法必须
等于 policy verifier 的 receiptKeyId/receiptPublicKey 与 Ed25519；signature statement 是移除
`signature` 后的同序 object，exact derivation 为：

```text
bootstrapVerifierReceiptStatementDigest = SHA-256(
  "pf.bootstrap-approval-verifier-receipt-statement.v1" || NUL ||
  canonical_pf_jcs(statement))
bootstrapVerifierReceiptSignatureMessage =
  "pf.bootstrap-approval-verifier-receipt-signature.v1" || NUL ||
  raw-32-byte(bootstrapVerifierReceiptStatementDigest)
bootstrapVerifierReceiptDigest = SHA-256(
  "pf.bootstrap-approval-verifier-receipt.v1" || NUL || canonical_pf_jcs(receipt))
```

protected approval service 的 lookup key 固定为
`(authorityPolicy,candidate,requiredTestSet,approvalSet,stage0Handoff)`，必须返回唯一、当前、
non-revoked receipt；zero/multiple/revoked result 一律失败。service descriptor/channel 只能来自
stage0Handoff 与 external policy exact 绑定的预开 `authority-store` RPC，caller 不得选择
pathname/root/service/旧 receipt。verifier 必须先 publish、验证 signed stored ack，再 exact lookup；
receipt 只是本次验证输出；
consumer 必须在同一 protected invocation 中验证 pinned verifier 的 exit/result、receipt signature
和 exact joins，不能只读取一份自报 verifierDigest 的旧文件。

`BootstrapApprovalVerifierReceiptRefV1` 的 wire object 恰为 `{id,digest}`，其中 `id` 必须等于
receipt ID，`digest` 使用 SPEC-COMMON-001 的 Digest wire form 并等于上式 receipt digest。consumer
必须从受保护 approval store safe-read immutable receipt bytes，拒绝 symlink/hardlink/replacement，
按 receipt schema 重算 digest，并把 receipt 的 candidate/policy/required-test-set/approval-set/
stage0-handoff/verifier/task-approval/task-receipt refs 与本次 protected invocation 的输入逐字段 exact join；仅比较 ref
中的自报 digest 不构成验证。

在 producer、external authority policy root、eligible handoff、signature verifier、protected
approval store 和 docs-check receipt consumer 全部实现前，任何 `Grade=bootstrap` 行以及任何 D0
`done` 转换都必须以 `PF-DOC-EVIDENCE-BOOTSTRAP-UNVERIFIED` zero-closure 拒绝。普通 ledger
`passed` 文本、完整 Tests 并集或人工 prose 均不能绕过。本仓库当前没有这些 producer/verifier，
所以 `TASK-D0-01` 仍只能保持 `in_progress`，其余 D0 状态不得提升。

## Gate catalog lock

Catalog 是独立、canonical、不可自包含 self-hash 的 policy lock；最大 4 MiB，root object
恰含：

```text
schema: "proof-forge.gate-catalog.v1"
id: safe-id
version: exact SemVer
qualification: "development" | "formal"
requiredTestSet: null | ContentRef
locks: {
  hostBootstrapSha256, hostProfileLockSha256, toolchainLockSha256,
  stage0LauncherSha256, stage0VerifierSha256,
  sandboxEngineSha256, sandboxRendererSha256, sandboxLauncherSha256,
  sandboxProbeWrapperSha256,
  evidenceValidatorSha256, finalizerSha256
}
gates: [GateRequirement, ...]  # non-empty
```

Catalog identity 是 `(schema,id,version,contentSha256,catalogDigest)`：

```text
contentSha256 = SHA256(canonical catalog bytes)
catalogDigest = SHA256("pf.gate-catalog.v1" || NUL || canonical catalog bytes)
```

同一次 finalizer 调用中 catalog bytes、caller expected identity、EV ref 或 retained catalog input
对同一 `(id,version)` 给出不同 `contentSha256` 或 `catalogDigest` 是 split-brain，必须失败；两个
hash 都必须从同一 canonical catalog bytes 重算，不能只核对其中一个。H1e 不承诺跨调用的 immutable
catalog registry；跨调用冲突检测属于未来受保护 catalog store。Catalog 不允许 version range、
`latest`、alias、wildcard、regex、script、plugin 或 best-effort。gate/test/tool/policy/probe/input/
artifact/log 均是 closed、sorted、unique exact sets；缺失和额外项同样失败。Catalog 内容改变必须
使用新的 exact version/digest，不得覆盖旧 lock。

development catalog 的 `requiredTestSet` 必须为显式 `null`，且只能得到 development 单-gate
结论。formal catalog 必须给出 `proof-forge.required-test-set.v1` ContentRef；finalizer 必须从
eligible Stage-0 handoff 取得 external `BootstrapAuthorityPolicyV1` expected ref，safe-read 并重算
RequiredTestSetV1 content/document/statement digest 与全部签名。catalog 所有 gates 的 `testIds`
必须形成 requiredTestIds 的 exact partition：每个 required ID 恰出现一次，且不存在 missing、extra
或 duplicate。只对 caller 自选 catalog 做内部 exact-set 比较不满足 formal 验收；caller expected
catalog digest 只能防 split-brain，不能代替 required-test-set authority。

formal finalizer 还必须从 handoff 的 authenticated authority-store service 按
`(policy,requiredTestSet,catalog identity)` 通过同一 authenticated RPC 唯一查得 non-revoked
`FormalGateCatalogApprovalV1` 并验证
policy `formalCatalogRule` signatures；caller/catalog 不能携带或选择 trusted approval/service/root。

Catalog 的 exact SemVer 只接受 `MAJOR.MINOR.PATCH`，三个分量无 leading zero；`gates` 必须
non-empty 并按 gate id 唯一升序。`locks` 恰含
`hostBootstrapSha256`、`hostProfileLockSha256`、`toolchainLockSha256`、
`stage0LauncherSha256`、`stage0VerifierSha256`、
`sandboxEngineSha256`、`sandboxRendererSha256`、`sandboxLauncherSha256`、
`sandboxProbeWrapperSha256`、
`evidenceValidatorSha256`、`finalizerSha256`，值均为 SHA-256。

Lock join 也是 closed contract，不能混淆不同 TCB：前三个 lock 值分别等于 EV host 的
bootstrap/profile/toolchain fields 及唯一 retained `host-bootstrap-lock`/`host-profile-lock`/
`toolchain-lock` input bytes；`stage0LauncherSha256` 与 `stage0VerifierSha256` 分别等于
EV host 的 `launcherSha256`（`verify_host_stage0.sh`）与 `verifierSha256`
（`toolchain_assets.py`）、对应 retained input bytes，并与 captured bootstrap lock 内容一致。
sandbox engine 值必须等于
每个 EV policy 的 `engineSha256` 与每个 receipt 的 `engine.observedSha256`；renderer 值必须等于唯一
`inputs[].role="sandbox-policy-renderer"` 的 captured bytes；sandbox launcher 值必须等于每个
receipt 的 `observedLauncherSha256` 及唯一 `sandbox-launcher` input bytes；probe wrapper 值必须等于唯一
`inputs[].role="sandbox-probe-wrapper"` 的 captured bytes及每个 denial receipt 的
`observedExecutableSha256`。evidence validator 与 finalizer 分别对其执行中的实现 bytes 做
stable-read；当前两者可由同一 `gate_evidence.py` 提供且 digest 相等，但身份/版本轴不能合并。
任一 lock 无 consumer 或出现第二个 consumer claim都失败。

`GateRequirement` 恰含以下字段；`testIds`、`requiredTools` 与 `policies` 必须 non-empty，
其余数组可为空，并按所示 key 唯一升序：

| Field | Closed contract / canonical key |
|---|---|
| `id`, `taskId`, `testIds` | safe-id、task ID、test ID 升序 set |
| `candidatePolicy` | `{subtree,anchorSource,dirty,unchangedDuringRun,archiveFormat:"git-tar"}` |
| `hostPolicy` | `{scope:"local-point-in-time",remoteAttestation:false,profileId,eligibleForHermetic,observationInput:{role,path}}` |
| `commandPolicy` | `{argv:[ValueMatcher,...],cwdRelative,environmentSha256:ValueMatcher,attempts:1,result:"passed"}` |
| `requiredTools` | `{id,version,source,assetSha256,executableSha256,closureSha256,usage,closureOf}`；key `id` |
| `policies` | 下述 `PolicyRequirement`；key `id` |
| `requiredInputs` | `{role,path}`；key `(role,path)`，hash/size 仍由 EV claim 与 bundle snapshot 约束 |
| `requiredArtifacts` | `{target,role,path,mediaType,retained}`；key `(target,role,path)`，hash/size 由 EV/bundle 约束 |
| `requiredObservations` | 完整 EV observation literal；保持执行顺序，逐项深度相等 |
| `requiredLogs` | `{path,truncated,privateDataScan}`；key `path`，hash/size 由 EV/bundle 约束 |

`ValueMatcher` 是 closed tagged union，所在字段决定期望 value type：

```text
{kind: "literal", value: string | integer}
{kind: "binding", name: safe-id}
{kind: "binding-decimal", name: safe-id}       # 只允许 integer -> canonical decimal string
{kind: "run-path", relative: relative-path}  # 只允许匹配 string argv
```

Gate command matcher 从 base context 解析 binding；probe matcher 先从其 invocation context、再从
base context 解析，若两处同名则 type/value 必须相等。`binding` 要求目标 type exact；
`binding-decimal` 只把 integer 按无 `+`、无 leading zero 的 base-10 ASCII 投影为 string，使同一
port/chain-id binding 能同时约束 numeric schema field 与 argv/env。`run-path` 精确解析为
`runRoot + "/" + relative`。不允许其他 coercion、substring、glob、regex 或 executable callback。

Catalog tool 的前六个字段必须与 EV tool record exact 相等；`usage` 是 `invoked` 或
`closure-only`。前者必须被至少一个 probe `ExecutableRef(kind="tool")` 消费；后者必须有
`closureOf=<invoked-tool-id>` 且不得作为 executable consumer。`closureOf` 对 invoked tool 必须
为 null。这样 required tool set 与实际 receipt executable observation 相连，而不是两个独立事实。

`ExecutableRef` 是 closed tagged union：

```text
{kind: "tool", id: required-tool-id}
{kind: "input", role, path}
{kind: "artifact", target, role, path}
```

Finalizer 必须令 receipt `command.observedExecutableSha256` 等于所选 tool/input/artifact claim 的
SHA-256；observed path 仍由同一 probe 的 argv[0] matcher 约束。Ref 必须命中唯一 selected-gate
claim，不能引用未 retained artifact。每个 probe 恰有一个 executable ref；禁止 literal digest。

`PolicyRequirement` 恰含
`{id,engine,engineSha256,defaultAction,network,networkPort,templateSha256,renderedPolicyInput,probes}`。
`networkPort` 必须是 `ValueMatcher` 或 null：仅 `exact-local-port` 使用 binding matcher，其他
network mode 必须 null。`renderedPolicyInput={role,path}`。每个 probe 恰含：

```text
{
  id, stage, invocation,
  outcome: "success" | "permission-denied",
  invocationContextInput: {role, path},
  receiptInput: {role, path}, stdoutLog, stderrLog,
  denial: null | {
    operation: "file-read" | "file-write" | "process-exec" | "tcp-connect" | "tcp-bind",
    allowedErrnos: ["EACCES", "EPERM"]
  },
  command: {
    executable: ExecutableRef,
    argv: [ValueMatcher, ...],
    environment: [{name, value: ValueMatcher}, ...]
  }
}
```

每个 policy 的 probes、每个 probe 的 command.argv 及 gate commandPolicy.argv 都必须 non-empty；
bindings/environment/requiredInputs/requiredArtifacts/requiredObservations/requiredLogs 可为空。
probe 按 `id` 唯一升序，environment 按 name 唯一升序；stage/invocation 必须在整个 selected
gate 内唯一。每项 policy 固定 engine/default/network/template digest、rendered policy input
和 required invocations。`exact-local-port` 必须令 evidence `networkPort`、invocation-context binding、
一次 safe-open 捕获的 rendered policy bytes，以及该 policy 下全部 invocation receipts 的
`runtimePort` 四方相等。

Evidence 的 effective input exact set 恰为 catalog、base run context、host observation、三份
host/toolchain locks、Stage-0 launcher/verifier、sandbox launcher/renderer/probe wrapper、每项
rendered policy、每个 invocation context、每个 invocation receipt，与 `requiredInputs` 的
不相交并集；structural role 不得在 `requiredInputs` 重复。
上述 singleton roles 精确为 `gate-catalog`、`clean-room-run-context`、`host-observation`、
`host-bootstrap-lock`、`host-profile-lock`、`toolchain-lock`、`host-stage0-launcher`、
`host-stage0-verifier`、`sandbox-launcher`、`sandbox-policy-renderer`、
`sandbox-probe-wrapper`；policy/context/receipt 使用各自已定义的 repeated role。
effective log exact set是每个 probe 的两条
stream 与 `requiredLogs` 的不相交并集；probe streams 固定 `truncated=false`、
`privateDataScan="not-run"`，sha256/size 必须与 receipt 相等。Artifacts 必须与
`requiredArtifacts` 一一对应，observations 必须与 sequence 深度相等。这样 catalog 冻结集合与
静态语义，而 snapshot 绑定本次运行产生的 content hash，不要求 catalog 预知输出 hash。

Probe outcome 只允许 `success` 或 `permission-denied`。`success` 固定要求 `denial=null`、exit 0、
空 signal、非 timeout。`permission-denied` 必须使用 catalog hash-locked、retained、externally
reviewed 的 dedicated executable wrapper；receipt observed executable digest 必须等于 wrapper
lock，`ExecutableRef` 必须是唯一 `sandbox-probe-wrapper` input，argv 前缀必须是 wrapper、closed operation，allowedErrnos 必须 exact
`["EACCES","EPERM"]`。Wrapper 只在执行该 operation 并捕获对应 `PermissionError.errno` 时向
stderr 写 exact ASCII bytes `PF-SANDBOX-PROBE-DENIED\n` 并 exit 77；成功或其他异常使用其他
exit/bytes。Finalizer 机器验证的是 locked wrapper identity、closed argv、exit 77、stdout empty、
stderr exact marker；OS-event 语义仍依赖外部审阅过的 wrapper/catalog trust root，不能只凭 marker
反推 kernel event。Catalog 不接受任意 executable 或 regex。

单个 `proof-forge.evidence.v1` finalizer 只按 `EV.gate.id` 选择 catalog 中恰好一个 gate entry，
并只对该 entry 做 exact-set 比较；catalog 中其他 gate 不算当前 EV 的 extra。Future evidence-set
finalizer 才要求 catalog 中每个 required gate 恰出现一次，且不允许额外 gate。Selected entry 的
taskId/testIds 必须与 EV exact 相等；H1e 要求 EV 与 catalog qualification 都是 `development`，
任一 `formal` 都不得产生 development record。

## Evidence v1 typed bindings

`proof-forge.evidence.v1` 在 proposed 生命周期内增加下列可选字段；generic `validate` 仍只输出
`claims-not-verified`：

```text
gateCatalog?: {schema, id, version, contentSha256, catalogDigest}
runContextInput?: {role, path}
hostAttestation.observationInput?: {role, path}
sandboxPolicies[].renderedPolicyInput?: {role, path}
sandboxPolicies[].probes[].receipt?: {
  invocationContextInput: {role, path}, role, path, stdoutLog, stderrLog
}
```

当 `gateCatalog` 存在时：

- 必须恰有一个 `inputs[].role="gate-catalog"`，其 path/size/raw SHA-256 与 catalog ref/file
  相符；finalizer 再 canonical parse 并重算 domain-separated digest。
- `runContextInput` 必须指向唯一 `inputs[].role="clean-room-run-context"`；host
  `observationInput` 必须指向唯一 `inputs[].role="host-observation"`。Finalizer 从前者 canonical
  bytes 重算 domain-separated run binding 并与 receipts 相等；后者 raw bytes SHA-256 必须等于
  `hostAttestation.observationSha256`。
- 必须恰有一个 `inputs[].role="sandbox-policy-renderer"`，其 captured bytes SHA-256 等于 catalog
  renderer lock。
- 每个 policy 必须有 `renderedPolicyInput`，指向唯一 input claim；claim SHA-256 必须等于
  `renderedSha256`。
- 每个 probe receipt 必须指向唯一 `inputs[].role="sandbox-invocation-receipt"`，stdout/stderr
  必须各指向唯一 log claim；`invocationContextInput` 必须指向唯一
  `inputs[].role="sandbox-invocation-context"`。context、receipt 与 stream path 均不能跨
  policy/probe 重用。

这些字段是 all-or-none extension：没有 `gateCatalog` 时，`runContextInput`、
`hostAttestation.observationInput`、所有 `renderedPolicyInput` 和 `receipt` 均禁止出现；存在
`gateCatalog` 时上述字段对每个相应 record 全部必填且不得 dangling。generic reader 只验证
结构/引用完整性，不据此声称 catalog verified。

新 reader 继续接受没有这些字段的旧 v1 record；catalog finalizer 必须拒绝未绑定的旧 record，
不能追溯升级，必须重跑并分配新 EV ID。旧 reader 拒绝新 record 是预期 forward fail-closed，
不是 forward compatibility。

### Host observation semantic join

Retained `host-observation` 不是 opaque hash。H1e-c producer 当前输出一行 restricted canonical
JSON 加恰好一个 LF；raw input SHA-256 包含该 LF，finalizer 移除且只移除该 LF 后要求 canonical
bytes。Root 恰含：

```text
{
  attestationScope: "local-observation-only",
  eligibleForHermetic: boolean,
  hostProfileId: safe-id,
  platform: {
    productVersion, buildVersion, kernelRelease, arch,
    procTranslated: boolean,
    sip: "enabled" | "disabled",
    authenticatedRoot: "enabled" | "disabled",
    systemVolumeSeal: "sealed" | "unsealed" | "broken"
  },
  remoteAttestation: false,
  xcode: {buildVersion, cdHash, identifier, mutableByCurrentUser: boolean, version}
}
```

所有未标 enum 的值都是 non-empty bounded strings，nested object 同样无 unknown fields。
Finalizer 必须把 `local-observation-only` 显式映射到 EV/hostPolicy 的
`scope="local-point-in-time"`，并令 profile id、eligibility、remoteAttestation 与 EV、catalog
三方 exact 相等；platform arch 还必须等于 `EV.environment.arch`。Host profile/Stage-0 lock joins
按前述 retained inputs 继续验证。只匹配 raw hash、但 semantic fields 分裂时返回
`PF-EVIDENCE-HOST-BINDING`。

## Single safe-open snapshot

Finalizer 不得先调用 `verify_bundle()` 再按 pathname 重开语义文件。Bundle verifier 必须扩展为
一次 safe-open/hash：在同一 verified fd 上捕获 catalog 指定的小型 catalog/policy/receipt/log/
base-run-context/invocation-context/host-observation/locks/launchers/verifiers/renderer/probe-wrapper bytes，随后只解析
snapshot。Capture path 必须已存在于 evidence claims，单文件
和总 capture 大小另设严格上限；不得捕获 artifacts 或未声明路径。

Snapshot semantic capture 限制为单文件 4 MiB、合计 64 MiB；整个 bundle integrity 仍使用
单文件 64 MiB、合计 256 MiB。Snapshot 返回 checked file count、claim-set digest、verified
inode identities 与 captured bytes。
任何 path/inode/casefold alias、symlink/hardlink、size/hash/metadata 变化或 I/O error 都失败。
Finalizer 必须用 directory fd 精确枚举 dedicated `policies/` 与 `contexts/`：前者的 rendered
`.sb`、`sandbox-*.receipt.json`、`sandbox-*.stdout.log`、`sandbox-*.stderr.log`，后者的
`sandbox-<stage>-<invocation>.json` 必须与 selected gate claims 一一相等；任何 hidden、unknown、
未 claim 或 crash 遗留 entry 都作为 orphan/extra 失败。不能只 glob 已知 suffix，也不能用
partial streams/context 逃过 exact-set。

Claim-set digest 固定为：

```text
SHA256(
  ASCII("pf.evidence.claim-set.v1") || NUL ||
  canonical_pf_jcs({inputs: EV.inputs, artifacts: EV.artifacts, logs: EV.logs})
)
```

## Development finalization record

Catalog evaluation 不改写或覆盖原 EV。成功时原子发布独立 immutable record：

```text
schema: "proof-forge.evidence-finalization.v1"
id: "EVF-YYYYMMDD-NNNN"
finalizedUtc
qualification: "development"
catalog: {schema,id,version,contentSha256,catalogDigest}
gate: {id,taskId,testIds}
evidence: {id,path,size,sha256}
run: {id,runBindingSha256}
claimSetSha256
candidate: {commit,treeObjectId,archiveSha256}
host: {profileId,observationSha256}
finalizer: {sha256}
result: "catalog-verified"
limitations: [
  "formal-not-verified",
  "freshness-not-verified",
  "private-scan-not-verified",
  "revocation-not-verified"
]
```

Root 不接受其他字段。`finalizedUtc` 使用 SPEC-COMMON-001 的 UTC 整秒格式，EVF ID 的日期必须等于其 UTC
日期；该时间仍不证明 freshness。`gate` 复制 selected EV/catalog identity，testIds 唯一升序。
`evidence.path` 是 normalized `bundleRoot`-relative path，INPUT 必须由该 root safe-open；size/hash
来自同一 snapshot。`run` 来自 captured base context。`claimSetSha256` 按上节公式计算。
`limitations` 是上列四项的固定、唯一、
字典序 exact set，不接受调用者删减或追加。Development output 使用与 schema-only EV
不同的 `finalized-development/<catalog-id>/<gate-id>/` namespace；consumer 因而可以区分
schema publication 与 catalog evaluation。Future `proof-forge.evidence-set.v1` 才表达同一
candidate/host/catalog 下所有 required gates 的聚合事实；H1e 不把单 gate record伪装成 set。

current development finalization 的 content digest authority 属于本规格，固定为：

```text
SHA-256("pf.evidence-finalization.v1" || NUL ||
  canonical_pf_jcs(evidence-finalization.v1 record))
```

该值以 SPEC-COMMON-001 `Digest` wire form 进入
`FinalizationRef{schema="proof-forge.evidence-finalization.v1",id,digest}`。所有
`FinalizationRef` 的 wire object 都恰为 `{schema,id,digest}`；consumer 必须按 schema 选择 digest
domain，拒绝裸 ID、缺 schema、unknown schema 或跨 schema/domain 复用。development ref 只证明
record 的 exact bytes，不能把 `qualification="development"` 提升成 formal；formal finalization
使用下节的独立 schema/domain，不得复用这个 digest tag。

`--output` 必须精确匹配
`<trusted-root>/finalized-development/<catalog-id>/<gate-id>/EVF-YYYYMMDD-NNNN.json`；basename
提供 ID，finalizer 在全部验证成功后、publication 前读取 UTC clock 并规范化为整秒
`finalizedUtc`，并要求两者日期相同。NNNN 由 caller 分配，no-clobber publication 处理冲突；
H1e 不把该 clock/sequence 当 freshness authority。

## Formal finalization schema（specified，producer 尚未实现）

formal record 使用独立 schema `proof-forge.formal-evidence-finalization.v1`，root object
恰含：

```text
{
  schema, id, qualification: "formal",
  candidate: {commit, treeObjectId, archiveDigest, digest},
  hostProfile: ContentRef,
  stage0Handoff: ContentRef,
  sessionContainment: ContentRef,
  requiredTestSet: ContentRef,
  catalog: {schema, id, version, contentSha256, catalogDigest},
  catalogApproval: ContentRef,
  gates: [{
    id, testIds,
    build: null | BuildIdentity,
    evidenceRefs: [{id, digest}, ...]
  }, ...],
  evidenceCoreDigest,
  evidenceSetDigest,
  freshnessAuthority: ContentRef, finalizedAt, expiresAt,
  privateScan: ContentRef,
  revocationLedger: ContentRef,
  finalizer: ContentRef,
  bootstrapApproval: {
    set: ContentRef,
    verifierReceipt: BootstrapApprovalVerifierReceiptRefV1
  }
}
```

上述六个 formal input ref 不允许退化成裸 digest。`hostProfile` 必须 exact 等于 handoff 中已验证的
hostProfile ContentRef；其余 closed payload 为：

```text
SessionContainmentReceiptV1 {
  schema, id, version, candidate, stage0Handoff,
  supervisorDigest, rootSessionId,
  descendants: [{pid,parentPid,startToken,sessionId,executableDigest,termination}, ...],
  escapeProbes: [{id,result:"contained"}, ...],
  startedAt, finishedAt, result:"contained",
  signatures: NonEmptyArray<ApprovalSignatureV1>
}

FreshnessAuthoritySnapshotV1 {
  schema, id, version, authorityPolicy,
  observedAt, maximumAgeSeconds, clockSourceDigest,
  signatures: NonEmptyArray<ApprovalSignatureV1>
}

PrivateScanReceiptV1 {
  schema, id, version, candidate, evidenceCoreDigest,
  scannerDigest, policy: ContentRef,
  scannedEvidenceRefs: [{id,digest}, ...],
  scannedMembers: [ScannedMemberRefV1, ...],
  findings: [], result:"clean",
  signatures: NonEmptyArray<ApprovalSignatureV1>
}

ScannedMemberRefV1 {evidence:{id,digest},role,path,size,digest}

RevocationLedgerSnapshotV1 {
  schema, id, version, authorityPolicy,
  records: [RevocationRecordRefV1, ...], head: null | RevocationRecordRefV1,
  recordsDigest,
  signatures: NonEmptyArray<ApprovalSignatureV1>
}

RevocationRecordRefV1 {schema, id, version, digest}

FormalFinalizerIdentityV1 {
  schema, id, version,
  executableDigest, closureDigest, toolchainLockDigest
}
```

schema/domain 分别固定为：

| Formal input | schema | digest domain |
|---|---|---|
| sessionContainment | `proof-forge.session-containment-receipt.v1` | `pf.session-containment-receipt.v1` |
| freshnessAuthority | `proof-forge.freshness-authority-snapshot.v1` | `pf.freshness-authority-snapshot.v1` |
| privateScan | `proof-forge.private-scan-receipt.v1` | `pf.private-scan-receipt.v1` |
| revocationLedger | `proof-forge.revocation-ledger-snapshot.v1` | `pf.revocation-ledger-snapshot.v1` |
| finalizer | `proof-forge.formal-finalizer-identity.v1` | `pf.formal-finalizer-identity.v1` |

四个 signed input 的 authority 与 signature domains 固定为：

| Input | policy rule | statement domain | signature domain |
|---|---|---|---|
| sessionContainment | `sessionContainmentRule` | `pf.session-containment-receipt-statement.v1` | `pf.session-containment-receipt-signature.v1` |
| freshnessAuthority | `freshnessAuthorityRule` | `pf.freshness-authority-snapshot-statement.v1` | `pf.freshness-authority-snapshot-signature.v1` |
| privateScan | `privateScanRule` | `pf.private-scan-receipt-statement.v1` | `pf.private-scan-receipt-signature.v1` |
| revocationLedger | `revocationSnapshotRule` | `pf.revocation-ledger-snapshot-statement.v1` | `pf.revocation-ledger-snapshot-signature.v1` |

对每项，unsigned statement 是只移除 root `signatures` 后保持 declaration field order 的 closed
object；`statementDigest = SHA-256(statementDomain || NUL || canonical_pf_jcs(unsigned))`，每个
Ed25519 signature 的 message 是 `signatureDomain || NUL || raw-32-byte(statementDigest)`。consumer
必须按表中 exact policy rule 校验 distinct principal/role/threshold；candidate、handoff、core digest、
clock、scan 或 record-set 变化都必须重新签名，不能复用另一 schema/domain 的 signatures。

formal consumer 必须先从 `stage0Handoff.authorityPolicy`、resolved
`BootstrapApprovalSetV1.authorityPolicy` 与
`BootstrapApprovalVerifierReceiptV1.authorityPolicy` 得到逐字节相等的唯一
`externalAuthorityPolicy` ContentRef，并重新解析/验证该 external object；四类 signed input 的
signatures 只能在这一个 policy 的对应 rule 下验证，禁止按 input 自报或 caller 选择另一个 authority。
字段级 joins 还必须同时满足：

- `SessionContainmentReceiptV1.candidate == formalRecord.candidate`，且其
  `stage0Handoff == formalRecord.stage0Handoff`；
- `PrivateScanReceiptV1.candidate == formalRecord.candidate`，且其
  `evidenceCoreDigest` 等于 consumer 从本 formal record 重算的 exact `evidenceCoreDigest`；
- `FreshnessAuthoritySnapshotV1.authorityPolicy == externalAuthorityPolicy`，且
  `RevocationLedgerSnapshotV1.authorityPolicy == externalAuthorityPolicy`；
- `PrivateScanReceiptV1.policy == resolvedPolicy.privateScanPolicy`。这里的 `policy` 是扫描范围、
  member coverage 与 finding 判定的策略 ContentRef，不是签名 authority root；签名 authority 仍只能是
  `externalAuthorityPolicy.privateScanRule`。

任一 join 缺失、multiple、stale 或不相等都返回 `PF-EVIDENCE-FORMAL-UNVERIFIED`，不得发布
formal record、support binding 或 staging。

每个 object additionalProperties=false，id/version 使用 ContentRef 规则，ContentRef digest 为
`SHA-256(ASCII(domain) || NUL || canonical_pf_jcs(object))`。时间是 UtcInstant；所有 array 按
其完整 canonical tuple 唯一升序；所有 `signatures` 按 keyId 唯一升序并使用前文 exact
ApprovalSignatureV1。
containment 的 PID/session/start token 使用 UInt64，termination
只允许 `exited|killed`；rootSessionId/escape probe ID 使用 safe-id。freshness maximumAgeSeconds 必须
nonzero 且纳入 formal freshness 计算；private scan 的 empty findings 与 scannedEvidenceRefs exact
覆盖本 record 全部 evidenceRefs，scannedMembers 必须无遗漏、无额外地覆盖这些 EV 所引用的全部
retained input/artifact/log member。role 使用 EV catalog role，path 是 ProjectRelativePath，size 是
不超过 `2^53-1` 的 UInt64，digest 对 member raw bytes 计算；同一 `(evidence,path)` 只出现一次并按该 tuple 排序。
`PrivateScanReceiptV1.evidenceCoreDigest` 只绑定下文不含 privateScan ref 的 core digest；最终
evidenceSetDigest 再单向绑定 `{evidenceCoreDigest,privateScan}`。private scan 不得直接包含最终
evidenceSetDigest，从而不存在 scan-ref ↔ evidence-set hash cycle。

revocation `records` 只允许 resolve 到 TRACE-EV-001 的
`proof-forge.evidence-revocation.v1` canonical record。`RevocationRecordRefV1.schema` 固定为该
schema，id 使用 `RVK-YYYYMMDD-NNNN`，version 固定 `1.0.0`，digest 固定为
`SHA-256("pf.evidence-revocation.v1" || NUL || canonical_pf_jcs(record))`。records 按 record ID
唯一升序且同时满足 record 内 previousRecordSha256 chain；head 为 empty 时 null，否则 exact 最后一项。
aggregate 不是裸 concatenation：

```text
recordsDigest = SHA-256(
  "pf.revocation-ledger-records.v1" || NUL ||
  concat(for ref in records: u32be(ref.digest.bytes.size) || ref.digest.bytes))
```

snapshot signature 覆盖 including recordsDigest 的 unsigned object。finalizer ref 必须由 handoff
`tcb.formalFinalizerDigest` 与 locked toolchain closure重算，不能引用当前输出 record 或 caller path。

`id` 使用 `EVF-YYYYMMDD-NNNN` 并与 basename 一致；`finalizedAt < expiresAt`，
两者使用 SPEC-COMMON-001 秒精度 UTC。catalog identity 必须来自
`qualification="formal"` 的 exact gate catalog。gates 按 id 唯一升序，test IDs 和
evidence refs 分别唯一升序；target support/acceptance gate 的 build 必须 non-null，
非 target D0 gate 才可为 null。每个 evidence ref 必须 safe-read 同一 immutable bundle 中的
canonical EV bytes 并重算 digest。`privateScan`、`revocationLedger`、
freshness authority、Stage-0 handoff、session containment、finalizer 和 bootstrap approval 都必须
指向本次 single-snapshot 评估的 exact content-addressed inputs，不允许 null或裸 label。
`requiredTestSet` 必须与 formal catalog 的 requiredTestSet ref、resolved
`RequiredTestSetV1` content digest 以及 bootstrap approval set/receipt 中的同名 ref exact 相等；
finalizer 必须重新验证 accepted PHASE-5 document ref、external authority policy、statement、签名和
required ID extraction。`gates[].testIds` 的 flatten 结果必须与 resolved requiredTestIds 是无重复 exact
partition，且每个 ID 对应至少一个 passed、non-revoked、non-expired evidence ref；调用者不能通过
catalog、gate selection 或 CLI omission 缩小分母。

`catalogApproval` 必须 resolve 到 external policy 授权的 exact `FormalGateCatalogApprovalV1`，其
policy/requiredTestSet/catalog refs 与本 record exact join并重新验证 role/threshold/signatures。
record gate IDs 必须与 catalog gate IDs exact 相等；每个 record gate 的 testIds/build 必须与对应
catalog requirement exact，evidenceRefs 必须 non-empty、各 gate 内和全局唯一。每份 EV 必须是
passed，并与 record/catalog 的 candidate、catalog identity、gate/task/testIds、适用的 BuildIdentity
exact 相等，同时通过 freshness、revocation 与 private scan。非 D0 gate 的 EV qualification 必须是
formal；D0-01..06 gate 的 EV 必须保持 development，并且是对应 signed TaskApproval 与 verifier
receipt 覆盖的 exact ref，不能改写 raw qualification。把全部 required IDs 放进错误 gate、弱 catalog
或重复 evidence 同样失败。

`bootstrapApproval.set` 只允许 resolve 到前节定义的、精确包含 `TASK-D0-01` 至
`TASK-D0-06` 六项 D0 trust-root task 的 canonical `BootstrapApprovalSetV1`；finalizer 必须 safe-read
set、六项 TaskApproval、evidence、reviews、PHASE-4/5 documents、policy 与 handoff，并重算全部 domain
digest、依赖顺序、六项 authenticated task receipts、test coverage 和签名。`bootstrapApproval.verifierReceipt` 必须 resolve 到由
external policy 锁定 verifier 在同一 eligible Stage-0 protected execution 中产生的 exact receipt，
receipt 的 set/policy/stage0Handoff/candidate/required-test-set/verifier/task approval/task receipt refs 必须与 formal
record 和当前 invocation exact join；record 的 hostProfile ContentRef 也必须与 handoff hostProfile
exact 相等并重算 resolved content digest。任一 producer、external
policy root、eligible handoff、protected authority-store service、签名
verifier 或 receipt consumer 缺失都必须 fail closed；ledger 中的 `passed` 文本、Grade 字符串或裸
approval digest 不能关闭 D0 task。这里的 bootstrap 是 Evidence Ledger task-closure grade，不是 gate
catalog/EV 的 qualification，不能扩展到其他 task，也不能替代本 record 对 formal gate/evidence/
freshness/private scan/revocation 的验证。

```text
evidenceCoreDigest = SHA-256("pf.formal-evidence-core.v1" || NUL ||
  canonical_pf_jcs({candidate,hostProfile,stage0Handoff,sessionContainment,
    requiredTestSet,catalog,catalogApproval,gates,freshnessAuthority,
    revocationLedger,finalizer,bootstrapApproval}))

evidenceSetDigest = SHA-256("pf.formal-evidence-set.v1" || NUL ||
  canonical_pf_jcs({evidenceCoreDigest,privateScan}))

formalFinalizationDigest = SHA-256(
  "pf.formal-evidence-finalization.v1" || NUL ||
  canonical_pf_jcs(formal record)
)
```

`FinalizationRef` 必须恰为
`{schema:"proof-forge.formal-evidence-finalization.v1",id,digest:formalFinalizationDigest}`。
consumer 先以 ref 安全定位 immutable record，再重算两层 digest 和全部 input joins；
任一 unknown/duplicate/unsorted field、development catalog/EV promotion、stale/revoked/private-scan
失败、required-test-set omission/substitution、bootstrap approval/receipt 未验证或 split-brain 都为
`PF-EVIDENCE-FORMAL-UNVERIFIED` 且 zero output。formal output
只能发布到
`<trusted-root>/finalized-formal/<catalog-id>/<required-test-set-id>/EVF-YYYYMMDD-NNNN.json`；两级目录
名必须分别 exact 等于 record `catalog.id` 与 resolved `RequiredTestSetV1.id`，basename exact 等于
record `id`。路径不得由 caller 另传 alias/未定义 gate-set identity，publication 使用 no-clobber
staging、fsync 和 receipt-last marker。

## Formal support-binding producer（specified，由 D0-07 实现）

未来 formal producer 是 `proof-forge.support-evidence-binding.v1` 的唯一可信 producer。它必须在
eligible Stage-0 直接 handoff、不可逃逸 process-session containment、formal gate/evidence-set
finalization、受信 UTC freshness authority、完整 private scan 与 append-only revocation lookup
全部成功后，才可按 [`SPEC-CAP-001`](capabilities-extensions.md) 生成 binding。输入必须同时精确绑定：

- canonical EV bytes 与 `EvidenceRef.digest`；
- qualification 为 formal 的独立 finalization record 与完整
  `FinalizationRef{schema,id,digest}`；
- `CandidateIdentity`、selected `BuildIdentity`、exact `RequirementKey` 与由完整 static
  `SupportClaim` 重算的 `claimDigest`；
- achieved support grade 所需的完整 gate vectors；
- `finalizedAt < expiresAt`、clock policy 与本次读取的完整 revocation-ledger digest。

producer 先一次 safe-open 捕获全部输入，再计算 candidate/binding domain digest，最后以 no-clobber、
receipt-last 方式发布 binding 与其 `SupportBindingRef`。同一 EV 可以为不同 requirement/build 产生
不同 binding；禁止只按 EV ID 复用。任何 development finalization、缺 profile digest、stale/revoked
EV、wrong/stale claimDigest、clock/private-scan 未验证或 partial gate set 都返回
`PF-EVIDENCE-FORMAL-UNVERIFIED`，且不得创建
binding/output staging。

当前仓库已冻结 formal finalization schema/domain，但没有 producer、formal support gate
catalog、RequiredTestSet producer/signer/verifier、bootstrap approval producer/verifier/receipt
consumer 或可信 binding store；因此本节只是冻结跨规格输入/输出边界，不能关闭
`TASK-D0-07`、提升 SupportEvidenceGrade 或
TargetMaturity。`finalize-development` 即使 catalog evaluation 成功也必须继续拒绝任何
`--support-binding-output` 请求。

## CLI 与执行顺序

```text
gate_evidence.py finalize-development
  --catalog CATALOG
  --catalog-sha256 SHA256
  --catalog-digest SHA256
  --run-binding-sha256 SHA256
  --evidence INPUT
  --bundle-root ROOT
  --output OUTPUT
```

Candidate/host expected facts 来自 caller 提供的 `--run-binding-sha256` 所绑定的 run context，
不再用可与 context 分裂的
重复 CLI 参数。固定顺序：isolated Python → evidence schema → qualification 必须是 development
→ caller expected identity syntax → catalog canonical bytes/digests/schema → selected gate → single
bundle snapshot → context domain digest 必须等于 caller digest 与全部 receipts → candidate/host/
policy/receipt/exact-set bindings → atomic finalization publication。
Formal 输入必须在 catalog/claimed bundle/output I/O 前拒绝。Catalog/evidence 内携 digest 不能
替代 caller expected digest；formal
信任根未来必须由 eligible Stage-0 或受保护外部 caller 注入。

为读取 `gate.qualification`，finalizer 必须先以 `bundleRoot`-relative `INPUT` 做一次 bounded
safe-open/canonical parse；这是 formal early rejection 唯一允许的 root read。若为 formal，立即
关闭 fd，并在读取 catalog、任何 claimed bundle member 或 output state 前拒绝。Development
路径复用同一 captured evidence bytes/inode，不能按 pathname 重开。

成功消息固定包含：

```text
development-catalog-verified ... formal-not-verified
freshness-not-verified revocation-not-verified private-scan-not-verified
```

禁止输出 `formal`、`attested`、`hermetic` 或无修饰的 `passed`。

## 稳定错误

| Code | 含义 |
|---|---|
| `PF-EVIDENCE-FORMAL-UNVERIFIED` | formal 输入进入 development finalizer |
| `PF-EVIDENCE-CATALOG` | catalog schema、identity、排序、重复、unknown gate |
| `PF-EVIDENCE-CATALOG-DIGEST` | expected/content/domain/ref/input digest 不一致或 split-brain |
| `PF-EVIDENCE-CATALOG-GATE` | gate/task/test/qualification/command exact set 不一致 |
| `PF-EVIDENCE-CATALOG-TOOLS` | required tool set/record 不一致 |
| `PF-EVIDENCE-CATALOG-POLICIES` | policy static semantics/set 不一致 |
| `PF-EVIDENCE-CATALOG-PROBES` | probe set/status/receipt mapping 不一致 |
| `PF-EVIDENCE-CATALOG-AUTHORITY` | FormalGateCatalogApproval policy/ref/signature 缺失或不一致 |
| `PF-EVIDENCE-REQUIRED-TEST-SET` | RequiredTestSet authority/document/signature/ref/exact partition 缺失或不一致 |
| `PF-EVIDENCE-BOOTSTRAP-UNVERIFIED` | bootstrap policy/set/task approvals/signatures/handoff/receipt 缺失或不一致 |
| `PF-EVIDENCE-CANDIDATE-BINDING` | candidate/subtree/archive/status/argv 不一致 |
| `PF-EVIDENCE-HOST-BINDING` | host observation/profile/lock/launcher/verifier 不一致 |
| `PF-EVIDENCE-POLICY-BINDING` | rendered policy bytes/hash/port 不一致 |
| `PF-EVIDENCE-RECEIPT-BINDING` | receipt identity/terminal/stream/binding 不一致 |

文件安全和 publication 继续使用 `PF-EVIDENCE-BUNDLE*`、`PF-EVIDENCE-PUBLISH` 与
`PF-EVIDENCE-EXISTS`。

## H1e 实施切片与验收

1. H1e-a：launcher opt-in metadata receipt schema、receipt-last commit marker；现有 alpha runner
   到 H1e-c 前不把临时 receipt 当 retained evidence。Self-test 必须覆盖：
   - 两份 context 的 fixed path/owner/mode/nlink/size/canonical/unknown/duplicate/domain digest，
     两项 CLI all-or-none、independent-codec golden，以及 runRoot/run-binding/stage/invocation
     cross-field mismatch 时 no-spawn/no-marker；
   - receipt exact keys/no newline/1 MiB preflight、policy/port/observed engine+launcher+executable、
     argv/env exact value/hash/order，且 argv[0] 等于 observed path；
   - exit 0、普通 nonzero、signal 三种 committed terminal；timeout/output-cap/spawn/cleanup/
     post-run identity failure 均无 metadata marker；
   - stdout/stderr/metadata 各自 preexisting、每个 publication step injected failure、receipt-last
     marker、无 marker orphan、raw/metadata/context/path replacement tamper；同 invocation
     reservation 竞争必须在 spawn 前失败且不能删除 owner 的 receipts。H1e-a 只证明“无
     marker 即未提交”；orphan/counterfeit exact-set rejection 属于 H1e-b。
2. H1e-b：catalog/ref/binding validators、single snapshot 与 synthetic realistic bundle 的 exact-set/
   digest/port/receipt/formal negatives。
3. H1e-c：`verify_isolation.sh` 捕获 Stage-0 observation，保留 candidate/policies/15 invocation
   receipts/tools/artifacts，安全发布 bundle 并调用 development finalizer。

H1e-c 前只能声称 invocation-receipt 或 catalog-core slice，不能声称 H1c 已被真实 finalization。
完整 old/new reader fixture matrix 继续属于 `TST-VER-001`；formal evidence set、freshness、
revocation、private scan、eligible runner、session containment 与 support-binding producer 继续 open。

## Attack matrix

- Receipt：missing/extra、unknown field、错误 stage/invocation/policy/port、stdout/stderr 互换、
  raw hash/size 不符、terminal 矛盾、preexisting/link/path replacement、partial publish。
- Catalog：non-canonical、wrong content/domain digest、duplicate/unsorted/unknown、version downgrade、
  same identity split-brain、development/formal 混用、unsigned/substituted/weak formal catalog approval。
- Required set：candidate-owned policy、PHASE-5 digest/review substitution、required ID omit/extra/duplicate、
  catalog flatten 保留 ID 但 gate/command 语义错绑。
- Bootstrap：同主体多 key 伪造 quorum、role/threshold 不足、D0 approval 缺项/乱序/依赖错绑、
  closure/verification handoff substitution、receipt key/verifier/store tuple/revocation/replay mismatch。
- Exact sets：gate/test/tool/policy/probe/input/artifact/log 任一 missing/extra/duplicate。
- Binding：EV A + catalog B、candidate A + archive B、host A + observation B、policy A + receipt B、
  EV/invocation-context/rendered-policy/receipt 四方端口任一变化、base/context/receipt 跨 gate/run/
  probe 重用、tool record A + ExecutableRef/receipt executable B。
- Filesystem：catalog/policy/receipt symlink/hardlink/casefold/inode alias、read-time mutation、
  capture budget、existing output、writable parent、staging replacement。
- Qualification：formal passed/failed/skipped、eligible host + development catalog、hidden override/
  environment fallback 均不得产生 development 或 formal output；development finalization 请求
  support binding 也必须 zero-output 拒绝。
