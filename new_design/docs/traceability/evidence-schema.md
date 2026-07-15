---
id: TRACE-EV-001
title: Gate Evidence Schema
status: proposed
owner: quality
updated: 2026-07-16
normative: true
---

# Gate Evidence Schema

本页描述当前 [`scripts/gate_evidence.py`](../../scripts/gate_evidence.py) 实现接受的
`proof-forge.evidence.v1`，并把“结构有效”“文件在某一时点完整”和“gate 事实已获正式
认可”分成三个不同判断。当前只有前两层工具；gate-catalog finalizer 尚未实现，因此正式
证据发布继续 fail closed，不能用 schema 通过或 bundle hash 通过关闭
`TST-EVIDENCE-001`、`TST-ISO-002`、`TASK-D0-03` 或提升 maturity。

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

`argv` 非空；UTC timestamp 允许零或三位小数，`durationMs` 必须精确等于 end-start。
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

### 3. Future gate-catalog finalizer

正式 finalizer 必须在一个受控 runner/workspace 内，把 Stage-0、external candidate anchor、
required gate/test/tool/probe catalog、bundle safe-open、freshness、private scan、revocation lookup
和发布动作绑定为一次 fail-closed protocol。该 finalizer 当前不存在。因此 `publish` 只允许
`qualification="development"`；formal 输入返回 `PF-EVIDENCE-FORMAL-UNVERIFIED`。

H1e 的 catalog、typed EV references、launcher receipt、single-snapshot 与独立 development
finalization record candidate 契约已在
[`SPEC-EVFINAL-001`](../specs/gate-catalog-finalization.md) 提出；当前实现尚未完成这些字段或
真实 retained bundle，因此本节的“future”状态和 formal fail-closed 结论不变。

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
hash chain，首条为 `null`。`authorityRef` 必须指向未来治理层认可的外部授权记录；replacement
只能引用另一份不可变 evidence，不能覆盖原文件。consumer 必须同时读取 EV store 与完整
revocation ledger，遇到 missing link、重复 revocation ID、未知 authority 或 hash chain 分叉
时 fail closed。

当前代码没有 revocation parser、publisher、authority verifier、append-only store 或 lookup；
本节只是为后续 `TST-EVIDENCE-001` 实现冻结独立 schema，不构成通过证据。

## 已知限制与验收状态

- local observation 不提供 remote attestation，也不能排除 observation 后 host 状态变化。
- 全局 exact/casefold path namespace、逐组件 safe-open、inode 去重和 readback 能拒绝路径别名、
  symlink、hardlink 及已观测的 pathname replacement，但不能完全排除同 UID 或 privileged
  actor 在两个检查点之间修改后恢复；formal 仍需受控 workspace。
- v1 没有 gate catalog、required probe/tool/test completeness、freshness、clock authority、
  evidence-set Merkle root 或 revocation lookup 实现。
- `networkPort` 已可条件表达，但尚未与 rendered policy bytes/digest、retained launcher
  logs/receipts 和 required probe catalog 绑定。
- `verify-bundle` 不扫描业务 private data；它只校验 evidence 声明的 scan 状态和 log bytes。
- `TST-EVIDENCE-001` 与 `TASK-D0-03` 继续未闭合。还需覆盖 malformed/duplicate ID、stale
  network evidence、wrong candidate、clock skew、revoked evidence、private witness/log、partial
  upload、concurrent publisher 和正式 finalizer 全链路。
