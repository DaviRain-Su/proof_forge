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

## Gate catalog lock

Catalog 是独立、canonical、不可自包含 self-hash 的 policy lock；最大 4 MiB，root object
恰含：

```text
schema: "proof-forge.gate-catalog.v1"
id: safe-id
version: exact SemVer
qualification: "development" | "formal"
locks: {
  hostBootstrapSha256, hostProfileLockSha256, toolchainLockSha256,
  stage0LauncherSha256, stage0VerifierSha256,
  sandboxEngineSha256, sandboxRendererSha256, sandboxLauncherSha256,
  sandboxProbeWrapperSha256,
  evidenceValidatorSha256, finalizerSha256
}
gates: [GateRequirement, ...]  # non-empty
```

Catalog identity 是 `(schema,id,version,catalogDigest)`：

```text
contentSha256 = SHA256(canonical catalog bytes)
catalogDigest = SHA256("pf.gate-catalog.v1" || NUL || canonical catalog bytes)
```

同一次 finalizer 调用中 catalog bytes、caller expected identity、EV ref 或 retained catalog input
对同一 `(id,version)` 给出不同 digest 是 split-brain，必须失败。H1e 不承诺跨调用的 immutable
catalog registry；跨调用冲突检测属于未来受保护 catalog store。Catalog 不允许 version range、
`latest`、alias、wildcard、regex、script、plugin 或 best-effort。gate/test/tool/policy/probe/input/
artifact/log 均是 closed、sorted、unique exact sets；缺失和额外项同样失败。Catalog 内容改变必须
使用新的 exact version/digest，不得覆盖旧 lock。

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

Root 不接受其他字段。`finalizedUtc` 使用 UTC 秒或毫秒格式，EVF ID 的日期必须等于其 UTC
日期；该时间仍不证明 freshness。`gate` 复制 selected EV/catalog identity，testIds 唯一升序。
`evidence.path` 是 normalized `bundleRoot`-relative path，INPUT 必须由该 root safe-open；size/hash
来自同一 snapshot。`run` 来自 captured base context。`claimSetSha256` 按上节公式计算。
`limitations` 是上列四项的固定、唯一、
字典序 exact set，不接受调用者删减或追加。Development output 使用与 schema-only EV
不同的 `finalized-development/<catalog-id>/<gate-id>/` namespace；consumer 因而可以区分
schema publication 与 catalog evaluation。Future `proof-forge.evidence-set.v1` 才表达同一
candidate/host/catalog 下所有 required gates 的聚合事实；H1e 不把单 gate record伪装成 set。

`--output` 必须精确匹配
`<trusted-root>/finalized-development/<catalog-id>/<gate-id>/EVF-YYYYMMDD-NNNN.json`；basename
提供 ID，finalizer 在全部验证成功后、publication 前读取 UTC clock 生成毫秒精度
`finalizedUtc`，并要求两者日期相同。NNNN 由 caller 分配，no-clobber publication 处理冲突；
H1e 不把该 clock/sequence 当 freshness authority。

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
revocation、private scan、eligible runner 与 session containment 继续 open。

## Attack matrix

- Receipt：missing/extra、unknown field、错误 stage/invocation/policy/port、stdout/stderr 互换、
  raw hash/size 不符、terminal 矛盾、preexisting/link/path replacement、partial publish。
- Catalog：non-canonical、wrong content/domain digest、duplicate/unsorted/unknown、version downgrade、
  same identity split-brain、development/formal 混用。
- Exact sets：gate/test/tool/policy/probe/input/artifact/log 任一 missing/extra/duplicate。
- Binding：EV A + catalog B、candidate A + archive B、host A + observation B、policy A + receipt B、
  EV/invocation-context/rendered-policy/receipt 四方端口任一变化、base/context/receipt 跨 gate/run/
  probe 重用、tool record A + ExecutableRef/receipt executable B。
- Filesystem：catalog/policy/receipt symlink/hardlink/casefold/inode alias、read-time mutation、
  capture budget、existing output、writable parent、staging replacement。
- Qualification：formal passed/failed/skipped、eligible host + development catalog、hidden override/
  environment fallback 均不得产生 development 或 formal output。
