---
id: SPEC-SEC-001
title: 安全与隐私规格
status: proposed
owner: security
updated: 2026-08-03
normative: true
---

# 安全与隐私规格

> **当前工程偏离（2026-08-02）**：B11/B12 safe-open/supervisor/native 层已按产品决策
> 删除。CLI 当前对 root/source 做词法校验后使用进程内 `IO.FS.readFile`；因此本规格所要求的
> pre-read bounded no-follow、regular/single-link、worker process containment 与 controller 资源
> 归因均 **未由当前产品路径实现**。Loader 仍在读入后执行 16 MiB source gate。下文 B11/B12
> 实现叙述只作为 superseded 历史记录；accepted 安全/架构意图是否修订仍需 ADR 决策。

## 资产与攻击者

资产：业务语义、private witness/secret、制品完整性、toolchain/registry 身份、输出目录、
发布签名和用户密钥。攻击者可控制 source、CLI 参数、cwd/env、外部工具输出、RPC 响应、
artifact consumer 输入和部分文件系统；不得假定父目录或 PATH 可信。

## 信任边界

Lean kernel/toolchain 与已校验 V2 source 是最小 TCB；外部 packager、prover、validator、
runtime、RPC、network profile 和父项目均不可信。编译器不执行 source 任意 Lean code、
动态 plugin、build script 或 network fetch。

## 强制控制

- 输入：[`SPEC-COMMON-001`](common-types.md) 的 frontend wall budget 在 source open 前启动；
  dirfd/no-follow/nonblocking `open` + `fstat` 只接受 regular single-link file，bounded read 强制
  16 MiB/source。Lean parser、每个 portable program command 的 100000 Syntax nodes、
  nesting/qualified identity 256 preflight 和 declaration decoder/check 都在 frontend stage；
  name/type/effect/semantic 在独立 compiler-core stage。direct Lean command 只可由覆盖两 stage
  的 outer build runner 执行；未受控 elaborator/library API 不属于 untrusted-source 或
  formal-evidence surface。
- 资源：frontend/core/external-tool/artifact-output 四 stage 使用 `ResourceProfileV1` hard maxima；
  CLI/profile 只能降低。aggregate memory、进程/session、protocol/stderr/published bytes、归因优先级、
  exact-limit 接受、over-limit kill/cleanup/零部分输出均以 SPEC-COMMON-001 为唯一规则。
- 进程：tool path 来自 lock-resolved absolute path；清理 env；timeout；stdout/stderr cap；
  不经 shell 拼接参数；验证 exit code、version、hash 和产物。
- 文件：output root containment、open-no-follow、拒绝 symlink/hardlink escape、临时目录
  `0700`、原子 rename、无 world-writable executable search path。
- 网络：check/build/emit 默认 deny；deploy/prove（若 remote）需显式 network policy。
- secret：private key 只能通过 OS secret provider/FD 输入，不能是 CLI、env、manifest、log。
- 隐私：taint/disclosure 检查覆盖 explicit/implicit flow；witness 目录 `0700/0600` 且不进入
  OutputSet；失败清理；core dump 禁用。
- 供应链：exact commit/version、asset checksum、license、SBOM、签名/来源记录。
- 构建：registry 静态、dirty release 禁止、reproducible/clean-room gate required。

development sandbox 使用独立 deny-default stage policies、关闭继承 FD、`/dev/null` stdin、
bounded pipes、固定 timeout 和 current-user `0400` single-link receipts。launcher 在 leader
被 reap 前清理其原 process group，以降低 descendant-held pipe、timeout/output-cap 与
PGID-reuse 风险。

这不是 formal process containment：fork 后的 descendant 可调用 `setsid()` 逃离原 group。
formal runner 必须提供 workload 无法逃逸的 session/job/VM 边界。stage 外的失败 tail 先转成
ASCII representation 再输出，可阻止 ANSI/OSC/control bytes 操纵终端，但不会自动删除
printable secret；正式日志在 retained/private scan/redaction 前不得直接回显。

## ZK 特有控制

Noir Phase 1 禁止 unconstrained functions、foreign/oracle、未批准 Brillig、递归证明和动态
black-box op；出现时 `PF-REQ-UNSUPPORTED`。public input 顺序和 verification key 绑定到
semantic/plan hash；prove 前重算 circuit hash，verify 检查 proof/VK/public-input 三者。
private input 不得出现在 error branch、artifact、diagnostic、telemetry 或 cache key。

### ZK backend security contract 与审批绑定

proof-producing Codegen profile 不能只以工具名称或“支持 ZK”作为安全前提。它必须引用一个
content-addressed `ZkBackendSecurityProfileV1`；针对 release candidate 的启用还必须有独立
`ZkSecurityApprovalV1`，从而避免 security profile 与包含其 digest 的 Codegen profile 形成
自引用 hash。

```lean
structure ZkSecurityProfileId where value : String

structure ZkBackendSecurityProfileV1 where
  schema               : SchemaId
  id                   : ZkSecurityProfileId
  version              : SemVer
  targetSemantics      : TargetSemanticIdentity
  circuitLanguage      : ContentRef
  provingSystem        : ContentRef
  provingBackend       : ContentRef
  crsPolicy            : ContentRef
  arithmeticModel      : ContentRef
  allowedFeatures      : Array ContentRef
  soundnessAssumptions : NonEmptyArray ContentRef
  proofBindingRule     : ContentRef
  privacyGuarantee     : ContentRef

structure ZkSecurityApprovalV1 where
  schema                 : SchemaId
  candidate              : CandidateIdentity
  build                  : BuildIdentity
  securityProfile        : ContentRef
  reviewProfile          : ContentRef
  evidence               : NonEmptyArray EvidenceRef
  finalization           : FinalizationRef
  approvedAt             : UtcInstant
  expiresAt              : UtcInstant
  revocationLedgerDigest : Digest
```

`revocationLedgerDigest` 必须 exact 等于 `finalization` resolved formal record 的 typed
`revocationLedger.digest`；approval 不得选择另一 ledger/schema/domain。

`ZkSecurityProfileId` 使用 1..127-byte profile ID grammar。security profile 的 wire object
字段恰为上述 declaration order；`schema` 固定为
`proof-forge.zk-backend-security-profile.v1`，digest 唯一为：

```text
SHA-256("pf.zk-backend-security-profile.v1" || NUL ||
  JCS(ZkBackendSecurityProfileV1))
```

所有 `ContentRef` 均按 SPEC-COMMON-001 exact resolve；`allowedFeatures`、
`soundnessAssumptions` 分别按 `(schema,id,version,digest)` 唯一升序。功能 allowlist 之外的
black-box op、Brillig opcode、oracle、foreign call、recursive proof、aggregation 或 dynamic
allocation 一律 `PF-REQ-UNSUPPORTED`，不能由 CLI 放宽。`crsPolicy` 必须承诺 CRS 获取方式、
ceremony/transcript 或 deterministic test CRS 身份、尺寸边界和 digest；`arithmeticModel` 必须承诺
integer width/range/overflow 与 Field modulus；`soundnessAssumptions` 不能为空，且每一项必须有
不可变正文，而不能是自由文本标签。

`proofBindingRule` 的 v1 payload 必须要求 proof envelope 同时承诺
`CandidateIdentity`、完整 `BuildIdentity`、security-profile digest、source/semantic/Plan/circuit
digest、VK digest、按 ABI 顺序的 typed public-input vector digest、proving-system/backend/CRS
digest；verify 在调用外部 verifier 前逐项重算并 exact compare。`privacyGuarantee` 的 v1 payload
必须区分“private input 不进入结构化公开面”和密码学 zero-knowledge 主张：前者由 taint、artifact
schema 与 retained private scan 验证；后者只能来自所引用 proving system/backend/CRS 假设及
formal review，不能由 proof byte substring scan 推导。

approval 的 wire object 字段也恰为上述 declaration order；`schema` 固定为
`proof-forge.zk-security-approval.v1`，digest 为：

```text
SHA-256("pf.zk-security-approval.v1" || NUL || JCS(ZkSecurityApprovalV1))
```

`evidence` 按 `(id,digest)` 唯一升序，`finalization.schema` 必须是
`proof-forge.formal-evidence-finalization.v1`。formal evidence-set 中以
`(candidate.digest,build,securityProfile.digest)` 为唯一 key，最多存在一个未过期、未撤销 approval；
safe-read 后必须重算 profile、approval、evidence、finalization 和 revocation digest，并要求
`securityProfile.targetSemantics == build.targetSemantics`、Codegen profile 的 exact
`securityContract == securityProfile ref`、全部 evidence refs 都是 resolved formal finalization 的成员。
时间关系固定为 `finalization.finalizedAt <= approvedAt <= currentTrustedTime < expiresAt <=
finalization.expiresAt`；consumer 必须用同一受信 UTC snapshot 同时完成 not-before 与两项 expiry
判断。任一缺失、development finalization、
wrong candidate/build/profile、evidence 非成员、时间不等式、过期、撤销或 clock authority 不合格均以
`PF-REQ-EVIDENCE` 零输出失败。

`CodegenProfileV1.securityContract` 对不产生 circuit executable、witness、proof、verification key
或 verification result 的 profile 必须为 `none`；任何产生其中一类制品的 profile 必须为 `some`
且引用上述 exact security profile。`noir-acir-proof-v1` 只有在当前 candidate/build 的 approval 验证通过后才能进入 registry
或被 build/prove 选择；approval 不得原地提升 `noir-source-u64-relations-v1`，也不得成为更换
target-neutral 业务语义的入口。

## Chain 特有控制

EVM selector/storage collision、delegate/static/value call 模式；Solana account owner/signer/
writable/order/PDA；NEAR predecessor/signer、attached value、Promise callback/receipt commit；
均由 target Plan validator 覆盖。Phase 1 Counter 不开放 arbitrary external call/deploy。

## 安全失败

安全检查失败一律 error，不允许 warning override。Syntax/identity 资源超限
`PF-BOUND-001`，CLI source 16 MiB 超限 `PF-SRC-INVALID`。当前 in-process CLI 强制
stage `wall-ms` 并以 `PF-RESOURCE-TIME` 失败；build 另在 sidecar 写入/rename 前强制
`artifact-output.published-bytes`，超限以 `PF-RESOURCE-OUTPUT`/exit 6 清理 staging 且不发布。
`PF-RESOURCE-MEMORY`、`PF-RESOURCE-PROCESS`、supervised protocol/stderr attribution 与
`PF-FRONTEND-PROTOCOL` 仍无产品 controller producer。不可信工具
`PF-TOOL-UNTRUSTED`，路径 `PF-OUTPUT-PATH`，披露 `PF-VIS-001`。`--force` 只允许替换输出
目录，不绕过任何安全/语义/版本检查。

## Superseded B10–B12 历史实现快照

以下内容记录 2026-07-30 的 worker/safe-open/supervisor 切片；2026-08-01 已从产品与源码中
删除 B11/B12 部分，B10 模块仅作非产品协议面保留。

B10 standalone frontend worker 只定义 abnormal process 的稳定本地 stderr token 与退出值：
argv misuse=`64`、malformed protocol=`65`、internal fault=`70`；有效 request 的 source/parser
失败必须返回 `Frontend.Err.v1` 且退出 `0`。B11a 新增独立 native safe-open primitive：trusted
absolute root 下 component-by-component no-follow，leaf regular/single-link，16 MiB pre-read gate，
initial-size read + one-byte probe 与 fd/path metadata recheck；fault 为 closed redacted class。

B11a2 是 canonical/public-safe Darwin receipt pure model；B11b1 以独立 process group 监督已编码
frame，从 native allocation/pipe/spawn 前启动 monotonic budget，轮询 aggregate process/
`phys_footprint` 与 output/deadline caps，bounded kill/cleanup 后实际产生该 receipt。B11b2 另以 closed
one-request safe-open helper（不 import Loader）逐阶段复用相同 `posix_spawn` primitive；private native
`CLOCK_MONOTONIC` capability 的 absolute start 覆盖 open→request construction→frontend worker，每阶段
allocation/pipe/spawn 前检查耗尽，最终 peak取两阶段最大值。SafeOpen Ok/Err 都携 exact canonical request
digest；仅 request-bound canonical SafeOpen fault + complete cleanup产生 `sourceOpenFailed`；private
supervised carrier只额外保留该 closed fault class（无 path/errno），供 CLI 将 `.tooLarge` 精确映射为
16 MiB `PF-SRC-INVALID`，不得 reopen/stat source；malformed、cross-request 与 incomplete-cleanup
response均 fail closed，stderr/path/PID/signal/exit detail不进入 carrier。
process-group polling仍无法阻止 `setsid()` escape，也不是 controller-backed containment。历史 B12 曾完成 CLI cutover：physical compiler path逐 component拒绝 symlink，pinned sibling workers必须为 regular non-symlink；native以 no-follow fd作为 worker snapshot authority，拒绝非 regular/多链接/无 execute bit/`>512 MiB`，只从 source-fd physical worker同目录的 fd-derived 128-bit 随机私有 snapshot做 suspended spawn；snapshot是 fresh O_EXCL byte-only copy，不复制source xattr/ACL，目录与文件都清空并验证无 inherited extended ACL；vnode/path复核通过后才恢复，mutation或snapshot cleanup失败均 fail closed；`build-counter` source root只来自 checked package layout而非 caller cwd。source-open 映射 `PF-SRC-INVALID`，resource events 映射对应 `PF-RESOURCE-*`，abnormal protocol/supervisor 映射 `PF-FRONTEND-PROTOCOL`；receipt 不进入 diagnostics。snapshot不等于签名/digest worker identity；sole native open前已发生的同路径 replacement、selectively inherited `LEAN_SYSROOT`/`LEAN_PATH` import closure与同 UID/formal threat model仍不作保证。B10退出值、B11a fault labels、B11b1/B11b2 native event 与 B11a2 receipt都不证明 time/memory/process containment；产品消费该 engineering seam 不会将其升格为 formal assurance。该历史切片曾令非 Darwin 产品 build 以 closed protocol diagnostic/零制品拒绝；当前进程内产品路径已无此平台分支，且仍不构成 Linux containment 或 formal materialization evidence。

## Attack Matrix 与验收

必须测试 path traversal/symlink/TOCTOU、argument injection、恶意 executable shadowing、
env poisoning、inherited writable FD/interactive stdin、巨大/二进制/ANSI stderr、
descendant-held pipe、fast leader/PGID reuse、`setsid()` escape、timeout/fork bomb、
policy/receipt replacement、diagnostic printable-secret leak、artifact zip bomb、hash collision
格式、manifest duplicate key、private explicit/implicit leak、malicious proof/VK/public input、
RPC wrong chain/replay、registry/profile spoof、parent cache/import/binary 泄漏、concurrent output、
disk-full rollback、compiler panic。关联 `NFR-003/004/008/009`、`TST-SEC-001`、
`TST-VIS-*`、`TST-ISO-*`；其中 parser containment 必须覆盖恰好等于/超过每个
`ResourceProfileV1` 上限、hang、OOM、fork/`setsid()`、oversized protocol、truncated/
malformed response 和 worker signal。P0/P1 finding 阻断 release。
