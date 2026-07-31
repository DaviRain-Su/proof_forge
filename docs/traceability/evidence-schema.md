---
id: TRACE-EV-001
title: Gate Evidence Schema
status: proposed
owner: quality
updated: 2026-07-17
normative: true
---

# Gate Evidence Schema

本页描述当前 `scripts/evidence_v1_core.py` 纯验证核心与
`scripts/gate_evidence.py` CLI 接受的
`proof-forge.evidence.v1`。bootstrap pure consumer 复用同一 exact sibling core，不维护缩减版 raw EV
validator。本页把“结构有效”“文件在某一时点完整”和“gate 事实已获正式
认可”分成三个不同判断。当前只有前两层工具；development gate-catalog finalizer 与 formal
finalizer/producer 均尚未实现。因此 schema 通过或 bundle hash 通过既不能关闭
`TST-EVIDENCE-001`/`TASK-D0-03`，也不能关闭 `TST-BOOTSTRAP-001`/`TASK-D0-04`，或
`TST-EVIDENCE-002`、`TST-ISO-002`/`TASK-D0-07`，更不能提升 maturity。

## PF integer-only / ASCII-graphic-key JCS restricted profile

v1 不是任意 JSON，也不是对完整 RFC 8785 number domain 的实现。它使用一个受限、可由锁定
Python 稳定编码的 profile：

- 输入必须是无 BOM 的 UTF-8，最大 4 MiB；canonical 文件不得含前后空白或 trailing newline。
- object key 必须为 1–256 个 ASCII graphic 字符（`0x21..0x7e`）；duplicate key 立即拒绝。
- number 只允许整数，范围为 `[-(2^53-1), 2^53-1]`；float、NaN 与 Infinity 全部拒绝。
- string 不得含 NUL 或 surrogate；普通 Unicode value 保持 UTF-8，不做业务层 Unicode
  改写。相对路径另要求 NFC、POSIX 分隔、无 absolute/`.`/`..`/空组件/control/backslash。
- JSON 最大深度 64、最大 value node 数 100,000、单 string 最大 1 MiB。
- object key 按 ASCII 字节序排序、array 保持规格规定的顺序，字符串使用 JCS escaping，
  输出不含非必要空白。所有结构 object 都是 `additionalProperties=false`；
  `return`、`logicalState`、`effects` 是受同一 JSON profile 约束的业务 payload。

`validate INPUT` 还要求输入 bytes 已经是上述 canonical 表示；`publish INPUT OUTPUT` 可消费
非 canonical 但结构有效的 development 输入，并在发布前重新编码。所有 gate 调用必须使用
Stage-0 锁定的 direct Python 并带 `-I -S`；当前 host profile 的精确 executable 是
`/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9`。
下文 `$PF_PINNED_PYTHON` 只是这个已验证绝对路径的简写，不是允许从继承环境解析的工具。

### Common primitives

- `sha256`：64 位小写十六进制。
- `git-object-id`：40 或 64 位小写十六进制。
- `safe-id`：1–256 个 ASCII 字符；首尾是 ASCII 字母或数字，中间只允许字母、数字、
  `.`、`_`、`:`、`+`、`-`。
- `taskId` / `testId`：分别以 `TASK-` / `TST-` 开头，后接一个或多个大写字母/数字段，
  段之间只用单个 `-`。
- `relative-path`：非空、NFC、normalized POSIX relative path；只有 `subtree` 与
  `cwdRelative` 可用单独的 `.` 表示根。
- `size`、`durationMs`、attempt number/code/signal 都是 safe integer；size/duration 非负，
  attempt number 从 1 开始，exit code 为 `0..255`，signal 为 `1..255`。
- `mediaType` 使用无空白的 ASCII `type/subtype` token，可带无空白 `;key=value` token。

## Root object

根 object 恰好包含下列字段：

| Field | Type / constraint |
|---|---|
| `schema` | 固定 `"proof-forge.evidence.v1"` |
| `id` | `EV-YYYYMMDD-NNNN`；日期必须真实，且等于 `command.endedUtc` 的 UTC 日期 |
| `gate` | gate/test/task 身份与 qualification |
| `repository` | candidate commit/tree/archive 与运行前后状态 |
| `hostAttestation` | local point-in-time host observation 引用 |
| `environment` | 规范化环境/cache 记录 |
| `sandboxPolicies` | 非空、按 `id` 排序的 policy set |
| `tools` | 非空、按 `id` 排序的 tool set |
| `command` | 命令、UTC 时间、duration 与所有 attempts |
| `inputs` | 按 `(role,path)` 排序的 input set |
| `artifacts` | 按 `(target,role,path)` 排序的 artifact set |
| `artifactSetSha256` | domain-separated canonical artifact-set digest |
| `observations` | 有顺序的 normalized observation sequence |
| `logs` | 非空、按 `path` 排序的 log set |
| `result` | `passed`、`failed` 或 `skipped` |
| `skipAuthorization` | skipped authorization；其他 result 必须为 `null` |

### Array semantics

| Array | Semantics | Canonical key/order |
|---|---|---|
| `gate.testIds` | set-like | test ID；唯一升序 |
| `sandboxPolicies` | set-like | policy `id`；唯一升序 |
| `sandboxPolicies[].probes` | set-like | probe `id`；唯一升序 |
| `tools` | set-like | tool `id`；唯一升序 |
| `inputs` | set-like | `(role,path)`；唯一升序；path 还参与全局 claim namespace |
| `artifacts` | set-like | `(target,role,path)`；唯一升序；path 还参与全局 claim namespace |
| `logs` | set-like | path；唯一升序；path 还参与全局 claim namespace |
| `command.argv` | sequence | 调用参数顺序原样保留 |
| `command.attempts` | sequence | 执行顺序；`number=1..n` |
| `observations` | sequence | 语义/执行顺序原样保留 |

业务 payload 内部的 array 由其业务 schema 决定；v1 evidence validator 不把未知 payload array
自动当作 set 排序。

## Nested records

### `gate`

```text
{
  id,
  taskId: "TASK-...",
  testIds: ["TST-...", ...],
  qualification: "development" | "formal"
}
```

`testIds` 必须非空、唯一并按 ID 排序。`qualification` 是证据声明等级，不会改变 host
observation 的 scope。

### `repository`

```text
{
  commit,
  subtree,
  treeObjectId,
  anchorSource: "derived-development" | "external",
  dirty,
  dirtyDigest,
  unchangedDuringRun,
  archive: {format: "git-tar", sha256, size}
}
```

`commit`/`treeObjectId` 接受完整 40 或 64 位小写 Git object ID。`dirtyDigest` 在且仅在
`dirty=true` 时为 SHA-256，否则必须为 `null`。archive size 必须大于零；format 只有
`git-tar`。每个 passed record 必须恰有一个 `inputs[].role="candidate-archive"`，其 SHA-256
与 size 必须等于 `repository.archive`。formal passed 还要求 `anchorSource="external"`、
clean tree 和 `unchangedDuringRun=true`。

### `hostAttestation`

```text
{
  scope: "local-point-in-time",
  remoteAttestation: false,
  profileId,
  eligibleForHermetic,
  bootstrapLockSha256,
  hostProfileLockSha256,
  toolchainLockSha256,
  launcherSha256,
  verifierSha256,
  observationSha256
}
```

当前没有 remote attestation protocol；`remoteAttestation=true` 必须拒绝。scope 固定表示本地
时点观察，不与 development/formal qualification 混为一谈。formal passed 要求
`eligibleForHermetic=true`，但 schema 本身不重新执行 Stage-0。

### `environment`

```text
{
  os, arch, environmentSha256, sourceDateEpoch,
  cleanRoom, buildCache, assetCache
}
```

`environmentSha256` 是规范化环境记录摘要；cache 字段是明确的安全 ID，不是搜索路径。
formal passed 要求 `cleanRoom=true` 且 `sourceDateEpoch=0`。

### `sandboxPolicies`

每项恰含：

```text
{
  id, engine, engineSha256,
  defaultAction: "allow" | "deny",
  network: "deny-all" | "exact-local-port" | "loopback-only",
  networkPort?: integer 1..65535,
  templateSha256, renderedSha256,
  probes: [{id, status: "passed" | "failed" | "skipped"}, ...]
}
```

policy 按 `id` 唯一排序；每个 `probes` 非空并按 probe `id` 唯一排序。passed 要求所有已列
probe 都 passed。formal passed 要求每项 `defaultAction="deny"`，且至少一项
`network="deny-all"`。v1 schema 尚没有 required gate/policy catalog，因此“列出的 probes
全部通过”不等于“formal gate 所需 probes 完整”。

`networkPort` 当且仅当 `network="exact-local-port"` 时必填；此时必须是严格整数
`1..65535`。`deny-all` 与 `loopback-only` 必须不含该字段，不能用 `null` 表示缺席。新
validator 可读取扩展前不含 `networkPort` 的旧 v1 deny-all/loopback records；旧 validator 会因
未知字段拒绝新 exact-port record，这是预期的 fail-closed，不是 forward wire compatibility。
当前 schema 仍为 proposed；本次条件扩展不重解释旧 variant，且新 reader 保持旧 records
有效，因此在 pre-acceptance v1 candidate 内完成。当前 formal publisher disabled，仓库没有
tracked formal v1 JSON fixture；这只是仓库内事实，不是对外部 consumer 的穷举证明。schema
accepted 后，同类不兼容变化必须按 [`SPEC-VER-001`](../specs/versioning.md) 升级版本。

该字段只能诚实**声明** macOS SBPL 的 exact-local-port 语义；schema validation 还不会把
`networkPort` 与 `renderedSha256` 对应的 policy bytes、retained launcher logs/receipts 或
required probe catalog 重新绑定。H1c runtime 仍只是 manual development observation；在
gate-catalog finalizer 完成这些绑定前，不能据此发布 formal evidence。

### `tools`

```text
{
  id, version, source,
  assetSha256: SHA-256 | null,
  executableSha256, closureSha256
}
```

数组非空，按 `id` 唯一排序。host-profile tool 可没有 content asset，因而
`assetSha256=null`；executable 与 closure digest 始终必填。schema 不判断某个 gate 的
required tool catalog 是否完整。

### `command` 与 attempts

```text
{
  argv: [string, ...],
  cwdRelative,
  startedUtc, endedUtc,
  durationMs,
  attempts: [{
    number, exitCode, signal, timedOut,
    stdoutLog, stderrLog
  }, ...]
}
```

`argv` 非空；UTC timestamp 使用 SPEC-COMMON-001 `UtcInstant` 的整秒 `...SSZ` wire form；
`durationMs` 由 monotonic clock 独立记录，不能从已截断为秒的 UTC 差值反推。
attempt number 从 1 连续递增。每个 attempt 恰有一种终态：

1. `timedOut=true` 且 `exitCode=signal=null`；
2. `timedOut=false`、`signal!=null`、`exitCode=null`；或
3. `timedOut=false`、`exitCode!=null`、`signal=null`。

passed 的最后一次 attempt 必须为 exit 0、无 signal、非 timeout；formal passed 恰好一次
attempt。development 可记录多次 attempt，但不能据此升级为 formal。skipped 必须
`attempts=[]`；failed 至少有一次 attempt，且不能同时出现“final attempt 成功、所有 policy
probes/observations/log scans 全绿”的自相矛盾记录。每个 stdout/stderr path 必须引用
`logs` 中的现有记录。

### `inputs`、`artifacts` 与 artifact-set digest

```text
inputs[]:   {role, path, sha256, size}
artifacts[]:{target, role, path, mediaType, sha256, size, retained}
```

inputs 以 `(role,path)` 为 set key；artifacts 以 `(target,role,path)` 排序。所有 input、artifact、
log path 共同构成一个全局 claim namespace：同一 path 不能复用于不同 role，两个不同 path 也
不能在 NFC + Unicode casefold 后碰撞。size 是非负 safe integer。
`artifactSetSha256` 必须等于：

```text
SHA-256(
  ASCII("pf.evidence.artifact-set.v1") || NUL ||
  canonical_pf_jcs(artifacts)
)
```

formal passed 要求 inputs/artifacts 非空，且所有 artifacts `retained=true`。该 digest 绑定
artifact claims，不读取 filesystem；实际 retained file 需要 bundle integrity 层复核。

### `observations`

```text
{
  step,
  status: "passed" | "failed" | "skipped",
  return,
  logicalState,
  effects,
  errorClass: safe-id | null
}
```

这是 sequence，不排序，因为执行/语义顺序本身是证据。development 可为空；任何 passed
record 中已有 observation 必须全部 passed，formal passed 至少一项。

该 object 是 gate step 的 verdict/diagnostic projection，不是 `SPEC-SEM-001 OutcomeV1` 的持久化
schema：`status` 是 step verdict，`errorClass` 只是可选 coarse safe-id，`return/logicalState/effects`
只是受 PF JSON profile 约束的业务 diagnostic payload，schema v1 没有为
`SemanticRevert.declared(errorId,args)`、`externalCallReverted(occurrence)` 或所有 fault/effect value
冻结 exact tags/field encoding。因此 observation presence、hash 或 equality 不能证明 structural
OutcomeV1 equality。需要 target/reference semantic differential 的 formal catalog 必须额外要求未来
versioned exact tagged reference-outcome retained artifact 与 verifier；它落地前该类 formal gate
fail closed，不能把 `errorClass`/target JSON/pretty text 当替代物。

### `logs`

```text
{
  path, sha256, size, truncated,
  privateDataScan: "passed" | "failed" | "not-run"
}
```

logs 非空并按 path 唯一排序。passed 不接受 truncated 或 `privateDataScan="failed"`；
development passed 可明确记录 `not-run`。formal passed 必须不截断且 scan 为 passed。

### `result` 与 `skipAuthorization`

`skipAuthorization` 在 result 为 skipped 时恰为 `{id,reason}`，其他 result 必须为 `null`。
skipped 不能关闭 FR/TST 或提升 maturity。failed、timeout、signal 和 retry 是可发布的
development 事实，但必须满足上述代数，不得被 summary lane 掩盖。

## 三层验证边界

### 1. Schema validation

```bash
$PF_PINNED_PYTHON -I -S scripts/gate_evidence.py validate INPUT
```

它验证 canonical bytes、字段、类型、排序、digest derivation 和跨字段不变量，输出明确为
`schema-validated ... claims-not-verified`。它不读取声明的 artifact/log/input，不重跑命令，
不查询 required gate catalog，也不证明 host observation 仍然新鲜。

### 2. Bundle point-in-time integrity

```bash
$PF_PINNED_PYTHON -I -S scripts/gate_evidence.py verify-bundle INPUT ROOT
```

它先做 schema validation，再以逐目录组件 `O_NOFOLLOW` 打开 ROOT，读取所有 inputs、retained
artifacts 和 logs，验证 regular file、owner、non-group/world-writable、single-link、稳定
inode、精确 size 与 SHA-256，并拒绝两个 claim 解析到同一 `(device,inode)`。资源上限与
[`SPEC-OUT-001`](../specs/output-contract.md) 的默认 profile 对齐：最多 1,024 个实际读取文件、
单文件 64 MiB、声明总量 256 MiB；超限稳定返回 `PF-EVIDENCE-BUNDLE-LIMIT`，路径/元数据/hash/
I/O 不一致返回 `PF-EVIDENCE-BUNDLE`，不会继续无界读取。结果是 `bundle-integrity-verified ...
gate-catalog-not-verified`：只证明这些路径在读取时与 claims 相符，不证明命令执行、语义观察、
host eligibility、required probes/tools/tests 或 release policy 完整。

### 3. Development catalog finalizer 与 formal finalizer

`TASK-D0-03` 的 development finalizer 只把 external candidate、required development
gate/test/tool/probe catalog、bundle safe-open 与本次 launcher receipts 绑定为独立
`proof-forge.evidence-finalization.v1` record；它不验证 freshness、private scan、revocation 或
formal process containment，并且 formal 输入必须在 catalog/member/output I/O 前以
`PF-EVIDENCE-FORMAL-UNVERIFIED` zero-output 拒绝。该 finalizer 当前尚未实现，所以
`TST-EVIDENCE-001` 仍未闭合。

`TASK-D0-04` 只建立不依赖既有 activation 的 bootstrap foundation；取得其 six-item set activation
后，`TASK-D0-07` 的 formal finalizer/producer 才在受控 runner/workspace 内把 eligible Stage-0 direct
handoff、external candidate anchor、由外部治理根签名的 `RequiredTestSetV1`、formal required gate set、不可逃逸 process-session
containment、bundle safe-open、freshness、private scan、revocation lookup 和发布动作绑定为一次
fail-closed protocol。其 `proof-forge.formal-evidence-finalization.v1` schema/domain 已在
[`SPEC-EVFINAL-001`](../specs/gate-catalog-finalization.md) 冻结，但 producer 尚未实现。因此当前
`publish` 只允许 `qualification="development"`；formal 输入返回
`PF-EVIDENCE-FORMAL-UNVERIFIED`，且 `TST-EVIDENCE-002`/`TST-ISO-002` 仍未闭合。
formal record 的 host profile、session containment、freshness authority、private scan、revocation
ledger snapshot 与 finalizer identity 全部使用 SPEC-EVFINAL-001 exact ContentRef/schema/domain；禁止
裸 `*Digest` 字段。revocation aggregate 必须重算其 domain-separated length-prefixed recordsDigest；
四类 signed formal input 必须分别命中 external policy 的 exact rule/quorum/signature domain，private
scan 绑定无 scan-ref 的 evidenceCoreDigest，最终 evidenceSetDigest 再单向绑定 scan ref。

`RequiredTestSetV1` 是 formal 测试分母的唯一 authority record：它绑定 accepted PHASE-5 exact
content digest/reviewCommit、从完整 Test ID Catalog 提取并排序的 exact required IDs、candidate
外部 `BootstrapAuthorityPolicyV1` 以及满足该 policy 的 Ed25519 signatures。formal GateCatalog 必须
携带该 record 的 exact ContentRef；catalog gates 的 testIds 必须形成 required IDs 的无重复 exact
partition，formal finalization 再把同一 ref 与 catalog、gates、bootstrap approval 和 evidence-set
digest exact join。caller 提供的 catalog/digest 只用于 split-brain 检测，不能授权 caller omit test。
此外，policy-authorized `FormalGateCatalogApprovalV1` 必须签名绑定 exact required-set 与 catalog
identity，防止 caller 把完整 ID 分母映射到弱/no-op gate policy；formal finalization 必须逐 gate
exact join catalog gate ID/test/task/build 与全局唯一 evidence refs。GateCatalog identity 在 run
context、EV、development/formal finalization 与 approval 中统一使用
`{schema,id,version,contentSha256,catalogDigest}`，两个 hash 都是 64 位 lowercase hex；
`contentDigest` alias 或 SPEC-COMMON prefixed Digest 均拒绝。当前 RequiredTestSet 与 catalog
approval producer/signer/verifier 尚未实现，因此不能据此声称 formal completeness。

H1e 的 catalog、typed EV references、launcher receipt、single-snapshot 与独立 development
finalization record candidate 契约也由 `SPEC-EVFINAL-001` 定义。H1e-a 已实现 opt-in launcher
contexts 与 invocation metadata receipt producer；catalog、typed EV references、single-snapshot
development finalizer 和真实 retained bundle 尚未实现，因此 formal fail-closed 结论不变。
Catalog 必须分别锁定 `gate_evidence.py` wrapper/finalizer bytes 与 exact sibling
`evidence_v1_core.py` schema-core bytes，后者还必须对应唯一 retained
`inputs[].role="evidence-schema-core"`；只锁 wrapper 的 helper substitution 不构成有效 TCB closure。
Development CLI 的 catalog path 只能来自 bundle-root-relative `gate-catalog` input claim；rendered
policy/context/receipt 的 repeated roles 分别固定为 `sandbox-rendered-policy`、
`sandbox-invocation-context`、`sandbox-invocation-receipt`。

development finalization 即使实现，也不能生成 [`SPEC-CAP-001`](../specs/capabilities-extensions.md)
的 `SupportEvidenceBinding`。formal support-binding producer 还必须把 canonical EV bytes 包装为
`EvidenceRef{id,digest}`、把独立 formal finalization 包装为
`FinalizationRef{schema,id,digest}`，并绑定
CandidateIdentity、selected BuildIdentity、RequirementKey、完整 static SupportClaim 的
`claimDigest`、freshness 与本次完整 revocation-ledger digest；其唯一 producer boundary 见
`SPEC-EVFINAL-001`，当前由 `TASK-D0-04` activation 前置与后续 `TASK-D0-07` 阻塞。raw evidence
schema 的 bare `sha256` 字段在进入这些 typed refs 时必须转换为 SPEC-COMMON-001 的
`sha256:<64 lowercase hex>` Digest wire form，禁止混用两种表示做字符串相等。

`FinalizationRef` 的 wire object 在 development 与 formal 路径都恰为
`{schema,id,digest}`。development schema 固定为 `proof-forge.evidence-finalization.v1`，formal
schema 固定为 `proof-forge.formal-evidence-finalization.v1`；consumer 必须先按 schema 选择对应
domain，再 safe-read exact immutable record 并重算 digest。裸 ID、缺 schema、unknown schema 或
跨 schema/domain 复用一律 fail closed。

Evidence Ledger 的 `Grade=bootstrap` 是文档任务关闭所用的独立控制面等级，不是
`proof-forge.evidence.v1.gate.qualification` 的第三个值，也不得写入 development/formal
finalization record 冒充运行资格。它只允许精确的 `TASK-D0-01` 至 `TASK-D0-06` 六项 D0
trust-root task，用于打破 formal binder 的自举循环；每项必须由 candidate 外部 authority policy
授权的 `TaskApprovalV1` 绑定 accepted PHASE-4 row、signed `RequiredTestSetV1`、exact
tests/dependencies/prerequisites、eligible
Stage-0 direct handoff、canonical EV refs、独立 review refs、signatures 与所有 dependency 的既有
authenticated completion refs。每个 D0 task 的单项 `done` 由该 TaskApproval 加 policy-pinned
verifier 产生并签名的 `BootstrapTaskVerifierReceiptV1` 独立关闭；store 按
`(policy,requiredTestSet,taskId,candidate,approval,handoff)` 唯一、non-revoked lookup。TaskApproval/
receipt 的 requiredTestSet ref 必须 exact 相等、通过签名验证，且 task owned TST 全是其成员。
每个 dependency completion receipt 的 candidate/policy/requiredTestSet 也必须与当前 TaskApproval
exact；candidate 变化后按 DAG 重验依赖，禁止回放历史 completion。D0-01/02/03/05/06 不依赖
六项 aggregate，因而不形成 dependency/checker deadlock。

`TaskQualificationV1` 是另一个独立的任务关闭 control-plane record，其 closed schema/ref、
candidate-bound formal EV partition、command policy、eligible handoff/containment、freshness/private
scan/revocation、discriminated authenticated dependency refs、review/signature 与 constrained closeout
join 仅由 `SPEC-TASKQUAL-001` 定义。它不新增 evidence qualification/ledger grade，不修改
`RequiredTestSetV1` 或 full formal finalization，且不能替代 D8-04/TST-ISO-003 release aggregate。
其四个content verifier只接受exact `TaskQualificationContentBundleV1` bytes与subject bytes，并只陈述
caller-supplied instant处的content验证；production authority须由SPEC-TASKQUAL-001 §8 policy-pinned
protected adapter另证current policy/time/store/Git/FD/session provenance。fixture projection固定
`fixture-non-authoritative`，不得投影为本Ledger的任何grade；pure production结果也只为
`production-content-verified`，只有signed `ProtectedTaskQualificationAcceptanceV1`可成为
`production-candidate-bound` docs acceptance。

D0-04 的唯一 owned test `TST-BOOTSTRAP-001` 必须在没有既有 aggregate activation 的输入空间内
运行；其 evidence、TaskApproval 与 task receipt 不得引用或查询本次即将生成的 activation。D0-04
先取得自己的 TaskApproval 与 authenticated task receipt；随后 final candidate/run 按依赖拓扑
重新验证并按 D0-01..06 exact 顺序把六项 approval+task receipt 放入 `BootstrapApprovalSetV1`，再由
policy 锁定 verifier 产生 set activation `BootstrapApprovalVerifierReceiptV1`。只有 D0-04 的
`done` 额外要求该 set/activation receipt；formal record 同时绑定 set ContentRef 和 activation receipt
ref，并 exact join candidate/policy/handoff/RequiredTestSet/verifier/task approval/task receipt refs。
`TASK-D0-07` 不属于 six-item bootstrap set；它只在 current、non-revoked activation 存在后运行
formal `TST-ISO-002`/`TST-EVIDENCE-002` 并由 formal finalization record 关闭。

authority quorum 按 policy 中 distinct principalId 而非 keyId 计算，每个 required role 都要由对应
distinct principal 覆盖。TaskApproval 与 aggregate set 都签入各自本次 exact eligible Stage-0
handoff，因此每次 task completion/aggregate activation 都需要在线 quorum，旧 run approval 不可
复用。handoff 使用
`EligibleStage0HandoffV1` closed object/ContentRef，绑定 candidate、external policy、eligible host
observation/profile、pinned TCB digests、净化环境、exact inherited fd/channel set 和 zero fallback；
formal record 保存该 ContentRef，不接受裸 digest。task/activation receipt 都必须由 policy-pinned
receipt key 签名，并经 handoff 预开的 authenticated authority-store request/response service 执行
signed publish ack + exact readback；service descriptor 与 external policy/handoff exact 绑定，caller
不能选择 receipt path/store root/service。read-only directory/file、mutable root-manifest digest、
missing/unsigned ack、request replay 或 publish 后不回查均拒绝。

普通 Ledger `passed` 文本、完整 Tests 并集、`Grade=bootstrap` 字符串或 verifier 自报 digest 都不
构成上述 authority。当前仓库没有 external policy root、approval producer/signer、eligible handoff、
protected authority-store service、bootstrap verifier/receipt consumer；在它们全部实现前，任何 bootstrap
closure 和 D0 `done` 转换必须以 `PF-DOC-EVIDENCE-BOOTSTRAP-UNVERIFIED` fail closed。bootstrap
不得关闭其他 task、提升 SupportEvidenceGrade/TargetMaturity 或替代后续 formal evidence；因此
当前 `TASK-D0-01` 仍保持 `in_progress`。

development publish 会 canonicalize 并原子 no-clobber 写入固定布局：

```text
<trusted-root>/<gate.id>/<id>.json
```

basename 和 gate directory 必须精确匹配 record。输出目录逐组件 `O_NOFOLLOW`，中间目录只
接受 root/current-user owner 且不可 group/world writable，最终 gate 目录必须由当前用户拥有；
formal bundle 建议使用 `0700`。publisher 保持 staging fd 到结束，link 后对 staging/final
inode、nlink、size、mode、exact bytes/hash 做 readback；成功输出 mode 固定为 `0444`，异常
尽可能删除新 final 并 fsync。

## Revocation records（specified，尚未实现）

EV JSON 是不可变事实；不得原地增加 `revoked` 字段。未来 revocation 使用独立、append-only、
同样受 restricted PF JCS profile 约束的 record：

```text
schema: "proof-forge.evidence-revocation.v1"
id: "RVK-YYYYMMDD-NNNN"
evidence: {id: "EV-...", sha256}
revokedUtc
reasonCode: "incorrect" | "compromised" | "superseded" | "policy-violation"
reason
authorityRef
replacement: null | {id: "EV-...", sha256}
previousRecordSha256: null | SHA-256
```

该 object 不允许其他字段。`reason` 是 1–4096 UTF-8 bytes，`authorityRef` 是 safe-id；
`revokedUtc` 使用与 EV command 相同的 UTC timestamp 格式。`evidence` 与非 null
`replacement` 都恰含 `{id,sha256}`，replacement ID 不得等于被撤销 ID。
revocation ID 日期必须真实并等于 `revokedUtc` UTC 日期；`previousRecordSha256` 建立 ledger
hash chain，首条为 `null`；非首条必须等于前一 canonical record bytes 的 raw SHA-256。
用于 formal snapshot 的 exact `RevocationRecordRefV1` 为
`{schema:"proof-forge.evidence-revocation.v1",id,version:"1.0.0",digest}`，其中 digest 固定为
`SHA-256("pf.evidence-revocation.v1" || NUL || canonical_pf_jcs(record))`；raw chain hash 与该
domain-separated ContentRef digest 不得混用。`authorityRef` 必须指向未来治理层认可的外部授权记录；replacement
只能引用另一份不可变 evidence，不能覆盖原文件。consumer 必须同时读取 EV store 与完整
revocation ledger，遇到 missing link、重复 revocation ID、未知 authority 或 hash chain 分叉
时 fail closed。

当前代码没有 revocation parser、publisher、authority verifier、append-only store 或 lookup；
本节只是为后续 `TST-EVIDENCE-002`/`TASK-D0-07` 实现冻结独立 schema，不构成通过证据。

## 已知限制与验收状态

- local observation 不提供 remote attestation，也不能排除 observation 后 host 状态变化。
- 全局 exact/casefold path namespace、逐组件 safe-open、inode 去重和 readback 能拒绝路径别名、
  symlink、hardlink 及已观测的 pathname replacement，但不能完全排除同 UID 或 privileged
  actor 在两个检查点之间修改后恢复；formal 仍需受控 workspace。
- v1 没有 development gate catalog/required probe/tool/test completeness；formal
  RequiredTestSet/formal-catalog approval producer/signer/verifier、bootstrap approval
  producer/verifier/receipt consumer、
  evidence-set、freshness/clock authority、revocation lookup、private scan 与 support-binding producer
  也尚未实现。
- `networkPort` 已可条件表达，但尚未与 rendered policy bytes/digest、retained launcher
  logs/receipts 和 required probe catalog 绑定。
- `verify-bundle` 不扫描业务 private data；它只校验 evidence 声明的 scan 状态和 log bytes。
- `TST-EVIDENCE-001`/`TASK-D0-03` 继续未闭合：还需完成 development catalog、typed refs、真实
  retained bundle、single-snapshot development finalizer、malformed/duplicate ID、wrong candidate、
  partial upload/concurrent publisher，以及 formal 请求的 zero-output rejection。
- `TST-BOOTSTRAP-001`/`TASK-D0-04` 拥有 activation 前缺口：eligible Stage-0 handoff、
  RequiredTestSet/formal-catalog authority、bootstrap task/set/receipt protected validation 与
  process-session containment；其 test/approval/task receipt 不得要求已有 activation。
- `TST-EVIDENCE-002`/`TST-ISO-002`/`TASK-D0-07` 拥有 activation 后 formal 缺口：正式
  archive gate、evidence-set finalizer/producer、freshness/clock、private witness/log scan、revocation
  lookup 和 acceptance/support binding。
