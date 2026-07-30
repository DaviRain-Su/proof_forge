---
id: MOD-SOURCE-001
title: SourceFrontend 模块规格
status: proposed
owner: frontend
updated: 2026-07-30
normative: true
---

# SourceFrontend

产品输入为 UTF-8 Lean source、显式 main-module `Lean.Name` 与可选的精确 program selector；
输出为 `ValidatedSourceV1`。模块拥有 grammar、bounded Syntax preflight、raw source identity、
ProgramV1 declaration validation、canonical source hash 与派生 NodeId 输入；不做 target lookup、
storage/ABI planning 或外部网络 I/O。

## 当前产品路径

CLI 的唯一产品路径为：

```text
canonical ProjectRelativePath + lexical absolute project root
  → pinned safe-open helper (no-follow, bounded snapshot)
  → request-bound Frontend.Req.v1
  → pinned B10 worker / locked Lean parser
  → command whitelist / namespace tracking
  → decodeProgramCommandV1Checked(moduleName, namespace, syntax)
  → validateSourceV1 + spans
  → request-bound Frontend.Ok.v1 / Frontend.Err.v1
  → supervisor sole reconstruct → ValidatedSourceV1 + OriginInventoryV1
```

`proof-forge-next build` 必须接收 `--module <Lean.Name>`。Loader 使用锁定 Lean term parser
exact-consume 该值，并且只接受最终 Syntax 为一个 pure `.str` identifier chain；不得从文件路径推导、
按 `.` 做字符串 split、NFC/casefold 或使用 rendered name 作为 canonical identity。
`programIdentity` 精确等于
`moduleName.components ++ activeNamespace.components ++ declarationName.components`。
`--program` 使用同一 parser 和 raw component equality。

当前恢复切片直接覆盖 Counter/Accumulator 所需的 state/init/entry/view、UInt64、name/integer/add、
assignment/return 构造。其他已被 parser 接受但尚未接入本 V1 decoder 的 DSL 构造必须稳定拒绝；
不得 fallback 到 legacy decoder。

## ParserSession

`ParserSession.create` 只导入锁定的 `ProofForgeV2.Language.Syntax` environment；同一进程在一个
control thread 创建后复用该 immutable session。产品 API 是
`parseProgramsV1(source, fileName, moduleName)` 与
`selectProgramV1(source, fileName, moduleName, requested?)`。session 不保存用户 source、program、
typed/core cache 或 target 状态，因此复用只能称为 same-session full recheck。

source byte cap 为 16 MiB；每个 program command 在递归 decoder 前执行 100000-node、
root-inclusive 256-depth preflight。namespace scope 可以临时超过 256 components；Loader 保存可恢复的
overflow state，并在退回合法 scope 后才构造 identity。CLI 不 elaboration、不执行 `run_cmd` 或其他
非白名单 Lean command。

## 迁移与兼容边界

**sole CLI source 入口**为 B12 `superviseFrontendSourceV1`：safe-open snapshot 进入 B10 worker，worker 在同一 parser snapshot 上 parse/select→SpanJoin，composer request-bind 后仅经 `reconstructFrontendSuccessV1` 一次构造 `ValidatedSourceV1 × OriginInventoryV1` 并以 private carrier交给 compiler。CLI 不 import Loader、不 reopen/reparse。`selectProgramV1Product` 是 worker共享实现之外的非 CLI 产品库入口；其余
**非产品库 API** 为 `parseProgramsV1` / `selectProgramV1` / `selectProgramV1WithSpans` /
`selectProgramV1WithOrigins`（`WithOrigins` 在同一 immutable snapshot 上串联 SpanJoin→OriginJoin，
产出 opaque `OriginInventoryV1`；identity/canonical bytes/sourceHash 不变）。
已删除的 raw `*WithDiagnostics` / `Except (Array DiagnosticV1)` failure carrier **不得**复活。
legacy source-reading/export decoder 家族（`parsePrograms`/`selectProgram`、
`decodeProgramCommandChecked`、`decodeType`/`Param`/`Expr`/`Statement`/`Item`/`Program`、
`proof-forge.program-export.v1` payload 路径）**已删除**；产品路径禁止 dual reader、
legacy→ProgramV1 adapter 或第二套 ProgramV1 decoder。残存 alpha `Core/Source` /
Typed-alpha carriers（若仍存在）仅供 D2 consumer 清理，**不是**产品 dual reader，
也不得从 CLI/Loader 重新挂回。

ProgramV1 的产品诊断 Typed 边界是 `normalizeProgramLocatedV1` 对
`checkProgramTypedLocatedResultV1` 的单次调用；成功后 compiler 只 mint `CompiledSemanticV1`，
resolver、target Plan与artifact identity均不再调用 alpha Typed/Semantic bridge。产品链直接消费
`ValidatedSourceV1`，不构造 legacy `Source.Program`；隔离的 alpha compatibility只供 hand-built测试。
source hash 只来自 `sourceHashV1`。NodeId 由
`assignNodeIdsV1(moduleName, programIdentity, program)` 从 validated source 派生；文件路径、span、
comment 与 allocation history 不参与 identity/hash。

B12 已把产品 CLI `build`/`build-counter` 原子切到 physical app-path、regular non-symlink sibling safe-open helper + B10 worker；Main 内 source `realPath`/`readFile`/Loader/caller reconstruct/embedded Counter fallback 已删除，并由 durable deletion gate 固定。B11a 提供 native safe-open foundation，B11a2 提供纯
`darwin-development-observed` public-safe receipt model；B11b1 监督已编码 canonical frame，
B11b2 进一步以 pinned standalone safe-open helper + B10 worker 逐阶段复用该 hardened
`posix_spawn` primitive。B12 的 native spawn 不再执行 caller pathname：先以 no-follow fd冻结
regular/single-link/executable、`≤512 MiB` worker，以 fresh 0600/O_EXCL、无 extended ACL 的有界 exact-copy写入 source-fd physical worker同目录的 128-bit 随机私有 snapshot；Darwin `START_SUSPENDED` + kqueue vnode/metadata 双检后才恢复执行，
snapshot 清理也进入 cleanup 语义。private native `CLOCK_MONOTONIC` capability 的同一 absolute
start 覆盖 snapshot/open、parent request construction 与 frontend worker；SafeOpen Ok/Err 携 exact
request digest，最终 receipt 合并两阶段 peak，request-bound canonical SafeOpen fault + complete
cleanup 才产生 live `sourceOpenFailed`。`SupervisedFrontendV1` 同时只保留该 canonical Err 的 closed
`SafeOpenFaultV1`（无 path/errno prose）；CLI 据此把 `.tooLarge` 恢复为精确 16 MiB
`PF-SRC-INVALID`，其余 open fault 仍用稳定 source-open 诊断，且不得 reopen/stat source。
B12 只把该 seam 提升为产品 CLI source authority；assurance
仍只是 Darwin development observation，不是 formal executable/import identity、controller-backed
containment 或 formal/hermetic evidence。

## FrontendProtocolV1、worker、safe-open 与 Darwin supervisor（B9/B9R/B10/B11a/B11a2/B11b1/B11b2/B12）

**B9** 新增 `ProofForgeV2/Frontend/ProtocolV1.lean`：版本化、封闭、one-frame binary
request/response 地基；该历史切片当时 inert。**B9R** 修复两处边界：去掉任意 4096-byte
selector 语义上限；在 `parsePfJcs` 分配诊断数组前做 top-level PF-JCS 条目预扫描。
**B10** 在不改变 wire 的前提下新增 standalone worker，B12 后成为产品 CLI 的 pinned frontend stage。**B11a** 新增 package-owned native safe-open foundation，B11b2/B12 经 pinned helper消费。**B11a2** 新增只建模 canonical
public-safe Darwin development observation 的纯 receipt carrier/codec。**B11b1** 以 package-owned
Darwin primitive 监督已编码 frame 并实际产生该 receipt；**B11b2** 新增 closed safe-open helper
protocol/process 与 `superviseFrontendSourceV1` shared-wall composer；**B12** 再完成 CLI/Loader/Compiler 产品切换与 closed diagnostic mapping。仍无 controller-backed contained assurance、完整 formal host/race matrix 或 target 变更。

| 帧 | Tag | 载荷 |
|---|---|---|
| Request | `Frontend.Req.v1` | exact SemVer `languageVersion`；validated `ProjectRelativePath`；raw UTF-8 `moduleSelector` / optional `programSelector`（无 NFC gate；**无** 4096 语义上限）；raw `sourceBytes`（协议层不校验 UTF-8） |
| Success | `Frontend.Ok.v1` | `requestDigest` + canonical `ValidatedSourceV1` root bytes + `SourceByteSpanV1` 仅在 `NodeAssignmentV1` preorder（**不**传 path） |
| Failure | `Frontend.Err.v1` | `requestDigest` + canonical PF-JCS `DiagnosticBundleV1` 数组文本 |

硬上限：`maxProtocolBytes=64 MiB`（亦为 selector 的 sole 分配/帧 guard；`maxSelectorBytes`
仅兼容别名且等于该值，**不是** qualified-name 语义限）、`maxSourceBytes=16 MiB`、
`maxNodeSpanCount=100000`。精确 Lean 组件面 `1..256 × 1..240` UTF-8 与源诊断分类仍由
Loader / `parseSourceQualifiedNameV1` 负责。Failure 在 `parsePfJcs` 前对 PF-JCS 数组文本做
非递归 O(n)/O(1) top-level 条目预扫描：拒绝 0 或 `> maxDiagnosticsV1+1`（101）条；嵌套
数组/对象与字符串内逗号不计入；语义/canonical 权威仍为 `parsePfJcs` +
`DiagnosticV1.fromPfJson` + `mkFailureBundleV1` 精确 re-encode identity（无静默 normalize）。

**Pure frame decoders**（`decodeFrontendRequestV1` / `decodeFrontendSuccessV1` /
`decodeFrontendFailureV1` / `decodeFrontendResponseV1`）：precheck 协议体积 → full-consume →
structure validate → re-encode 精确 byte identity。拒绝 truncation、wrong tag/field count、
oversize/count bomb、trailing/noncanonical frame 与 malformed 诊断包；success 另要求 carried
`ValidatedSourceV1` root bytes 等于 `canonicalValidatedSourceAstBytesV1` 的 sole 再编码（与
failure 的 PF-JCS/`mkFailureBundleV1` identity 对称）。pure decoder **不**绑定 request 上下文。

**Request-bound APIs**（`mkFrontendSuccessV1` / `mkFrontendFailureV1` / `bindFrontendSuccessV1` /
`bindFrontendFailureV1` / `reconstructFrontendSuccessV1`）：在 pure decode 之上强制
`requestDigest` 匹配（拒绝 cross-request digest replay）、failure 的 diagnostic
`sourcePath` 必须等于 request path（foreign path fail closed）、以及 span `endByte` 相对
request `sourceBytes` 的 range/count 门禁。`reconstructFrontendSuccessV1` 仅经
`decodeCanonicalSourceAstBytesV1` → `assignNodeIdsV1` zip spans → `joinOriginsV1`（无第二套
ProgramV1 decoder、无 caller-trusted OriginInventory 构造）。

`requestDigest` = `domainSeparatedSha256("proof-forge.frontend-request.v1", exact request bytes)`。
协议聚焦套件：`Tests/Frontend/ProtocolV1.lean`（含 B9R：>4096 legal plain QN selector
round-trip、selector 声明长度 bomb、102-entry tiny PF-JCS bomb、嵌套逗号不误计、
100+PF-DIAG-LIMIT=101 round-trip、101 non-limit raw noncanonical）。

### B10 standalone one-request worker

`ProofForgeV2/Frontend/WorkerV1.lean` 只消费已进入 stdin 的完整 request：先解码协议，随后按
**exact `1.0.0` language version → source UTF-8 → Loader** 的固定优先级处理。Loader 新增
`selectProgramV1FrontendPayload`，与 `selectProgramV1Product` 共享 private
parse/select/SpanJoin snapshot；worker 只在 SpanJoin 后移除 path 并传 canonical-preorder spans，
不 reparse、不构造 caller-trusted inventory，也不引入第二 decoder。

`proof-forge-frontend-worker-v1` 每进程只处理一个 request，frame 读到 EOF；正常 success 与
有效 request 的 source/parser diagnostic failure 都输出一个完整 `Frontend.Ok.v1` /
`Frontend.Err.v1` 并 exit 0。argv misuse、malformed/truncated/oversize protocol 与 internal fault
分别使用稳定 stderr token 及 exit 64/65/70；异常路径在 intentional stdout write 前失败。
`Tests/Frontend/WorkerV1.lean` 同时固定 direct parity 与真实 subprocess success/failure、两进程
byte determinism、malformed/truncated/declared-oversize/argv 的 zero-stdout + exact exit/token。
`just build`、`test` 与 `test-fast` 会先构建该 worker，避免 clean invocation 依赖陈旧二进制。

B10 **不**读取路径、不 spawn 子进程、不接受 target/profile、不写 cache/artifact；该 worker 模块
本身不提供 safe-open 或 supervisor/receipt。B11a/B11a2/B11b1 已分别交付 safe-open foundation、pure receipt 与 Darwin development-only worker supervision；B11b2 已交付 shared source-open/worker deadline composition，B12 已完成产品原子切换。formal TASK-D1-08 仍 pending。

### B11a native safe-open foundation

`ProofForgeV2.Frontend.SafeOpenV1.safeOpenSourceV1` 接受 trusted absolute root 与已验证的
`ProjectRelativePath`，经 package-owned C FFI 从 `/` 开始逐 component `openat`。root 中间组件
与 relative parent 均要求 directory，并使用 `O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC`；leaf 使用
同样的 no-follow/nonblocking/close-on-exec flags，随后只接受 regular、`st_nlink == 1` 文件。
文件在读取前以 initial `fstat` 执行 `<=16 MiB` 门禁；读取 initial size 后额外探测一个 byte，
再比较 fd 与 parent-relative pathname 的 device/inode/mode/link-count/size/mtime/ctime。返回值为
opaque `SafeSourceSnapshotV1`；native fault 只使用 closed redacted wire labels，不返回 errno prose
或 host path，未知 label 在 Lean 边界 fail closed 为 `native-protocol`。

`Tests/Frontend/SafeOpenV1.lean` 固定 regular/empty/determinism、relative root、root/leaf/intermediate
symlink、hardlink、permission denied、directory/FIFO、missing 与 exact 16 MiB / 16 MiB+1；普通
full suite 执行真实大小边界，fast suite省略两个大文件。package source pin 的历史 schema 名保持
`proof-forge.lean-package-files.v1`，但枚举已扩为 `ProofForgeV2/**` 下 `.lean/.c/.h`，因此 native C
与 Lean wrapper 同属已钉住的 package source closure。

B11a 本身仍只是同步可复用 primitive；B11b2 通过独立 `proof-forge-frontend-safe-open-worker-v1`
把它放入 killable process-group unit，并与 B10 worker 共享 overall monotonic wall。B11b2 suite 固定
FIFO/socket/symlink/hardlink、16MiB±1、test-only hang opener、open transport limits 与 two-phase
non-rearm/peak join；并发 truncate/grow/rebind 的完整 host-isolated/formal matrix仍未闭合。B11a/B11b2
都不代表 CLI cutover、controller-backed containment 或 formal `TST-RESOURCE-001` 完成。

### B11a2 pure Darwin development-observation receipt model

`ProofForgeV2.Frontend.DarwinSupervisorReceiptV1` 定义 private-constructor
`DarwinFrontendSupervisorReceiptV1` 与唯一 smart constructor。它是 public-safe **internal** receipt，
不是当前 CLI 顶层 `receipts` envelope；B12 只消费内部 carrier，不公开 receipt。它只保留 hard/effective frontend
`ResourceProfileV1` identity/digest、optional canonical request digest、bounded elapsed/aggregate-memory/
process observations、closed event/result/cleanup class，并固定唯一 assurance
`darwin-development-observed`。PF-JCS 是 11-field closed object，4 KiB pre-parse cap，profile/request/
receipt digest 全部 domain-separated 且 parse 后 exact re-encode；unknown privacy fields（path、PID、
signal、exit code、stderr/tail/secret/detail）无 carrier 并在 decoder 边界拒绝。

`Tests/Frontend/DarwinSupervisorReceiptV1.lean` 固定 exact 929-byte golden、receipt digest KAT、
request replay rejection、lower-only effective profile、event/result/request cross-field invariants、
equal/first-over resource projection、closed enum/field/canonical failures和 privacy key rejection。
本模块自身仍是纯模型：**不** open/spawn/measure/kill/reap，不输出 CLI JSON，也不代表 Linux
`contained`。B11b1/B11b2 composer 消费其唯一 smart constructor并实际产生 worker-only/full-source
receipt，但这不关闭 CLI cutover、controller-backed containment、formal `TST-RESOURCE-001` 或
TASK-D1-08。

### B11b1 Darwin development-only worker supervisor

`ProofForgeV2.Frontend.DarwinWorkerSupervisorV1.superviseDarwinWorkerFrameV1` 接受 absolute worker
path、完整 canonical request frame 与 lower-only frontend `ResourceProfileV1`。package-owned Darwin C
primitive 在首个 native worker snapshot/allocation/pipe/`posix_spawn` 前消费同一 `CLOCK_MONOTONIC`
budget。源 worker 经 `O_NOFOLLOW` fd、regular/single-link/execute-bit/512 MiB gate；fd-derived private
snapshot 由 `F_GETPATH` 定位到 source-fd physical worker同目录的 0700 私有目录；fresh file以 0600/O_EXCL 创建，目录与文件都显式清空并验证无 Darwin extended ACL，64 KiB bounded exact-copy完整 fsync 后 snapshot与目录分别收紧为0500并再次清除/验证 ACL；每批 copy检查 original absolute deadline。source xattr/ACL不复制。`POSIX_SPAWN_START_SUSPENDED` 后
再次验证 snapshot path/vnode；kqueue 监视 content/link/rename/delete，只有无 mutation 才 `SIGCONT`。
worker 使用独立 process group、CLOEXEC/nonblocking pipes，环境固定为 `HOME=/var/empty`、
`PATH=/usr/bin:/bin`、`LC_ALL=C`、`TZ=UTC`，并选择性继承 development Loader 所需的
`LEAN_SYSROOT` / `LEAN_PATH`。后两项尚不是 digest-locked import closure。stdin/stdout/stderr 均受
cap；`proc_listpids(PROC_PGRP_ONLY)` 与 `proc_pid_rusage(...).ri_phys_footprint` 提供 development-only
aggregate process/memory observation。事件优先级为 process → memory → output → deadline；等于 cap
接受，首次超过映射为 exact `limit+1` public observation。

leader 通过 `waitid(..., WNOWAIT)` 保留 PID/PGID identity 到 group cleanup；终止路径执行 bounded
process-group kill、pipe close 与 cleanup observation。无法在 bounded cleanup 内确认完成时返回
`incomplete`，detached reaper 只等待固定 child PID，不再按裸 PGID kill。native 仅返回 closed
`PFSUPV1\0` frame；Lean decoder强制 magic/reserved bytes/event/payload/full-consume、effective-profile
observation 和 response-only payload invariant，不保留 stderr、path、PID、signal 或 exit code。

`ProofForgeV2.Frontend.DarwinSupervisorV1.superviseFrontendRequestV1` 是 request/receipt composer：
canonical encode request 后调用 primitive；response candidate 只有在 cleanup=`observedComplete`、
`decodeFrontendResponseV1` 成功、request digest/path/span binding 成功时才成为
`responseAccepted`，success 还必须通过 `reconstructFrontendSuccessV1`。malformed、cross-request 或
request-inconsistent response fail closed 为 no-response；incomplete cleanup 永不接受 response。
unsupported platform 显式返回 error；其他 native closed fault 只产生零 observation、
`supervisorFault`/`noResponse`/`incomplete` receipt。

`Tests/Frontend/DarwinWorkerSupervisorV1.lean` 在 Darwin 以真实 worker/子进程覆盖 Ok/Err、deadline、
process/memory、stdout/stderr cap 与 exact-cap acceptance、nonzero exit/signal、malformed/cross-request、
missing worker、lower-only profile、private snapshot path/cleanup、snapshot self-mutation、inherited
writable ACL清除、worker symlink/hardlink/non-executable/oversize rejection和 cleanup/result join；非 Darwin 仅 compile 并 skip。

B11b1 primitive **不** import `SafeOpenV1`、不读取 source path，也无法阻止 descendant `setsid()`
逃离 process group；B12 虽已消费它作为 CLI source authority，assurance仍只支持
`darwin-development-observed`。snapshot 不构成 formal executable digest/signature；在 sole native open
之前已被替换的同路径 regular executable与 selectively inherited Lean import closure仍没有 formal identity。

### B11b2 shared safe-open/frontend supervisor

`SafeOpenWorkerProtocolV1` 定义 closed `SafeOpen.Req.v1` / `SafeOpen.Ok.v1` / `SafeOpen.Err.v1`
one-frame wire（full-consume + exact re-encode；unknown fault fail closed）。
`proof-forge-frontend-safe-open-worker-v1` 是 one-request process，只调用 sole
`safeOpenSourceV1`；其 bounded stdin reader不 import `WorkerV1` 或 Loader。调用方显式提供 pinned
safe-open/frontend executable paths，composer不查询 ambient `PATH`。

`superviseFrontendSourceV1` 在 open request 构造前由 native `CLOCK_MONOTONIC` sole mint private
budget capability，两个 child stage 都消费该 exact absolute start；native 在每次 allocation/pipe/spawn
前检查是否耗尽。SafeOpen Ok/Err 携 canonical `SafeOpen.Req.v1` domain-separated digest；只有 complete
cleanup + exact request binding + canonical `SafeOpen.Err.v1` 才 mint `sourceOpenFailed`（frontend request
digest 为 null），并在 private supervised carrier 中保留 exact closed fault；receipt 仍只暴露 coarse event。
malformed/unknown/cross-request/incomplete/abnormal transport fail closed。Open success 后
由 parent 构造 canonical `Frontend.Req.v1`，同一 absolute budget 继续覆盖该计算与 frontend worker。
最终 receipt 的 elapsed覆盖总 wall，process/memory peak取两阶段最大值；open process/memory/output/
deadline/exit/signal保留 closed attribution。

`Tests/Frontend/SafeOpenWorkerV1.lean` 固定 protocol/process contract；
`DarwinSourceSupervisorV1.lean` 固定 regular Ok/parser Err、open fault 无 frontend spawn、closed fault
join 与 exact `.tooLarge`、16MiB边界、test-only opener deadline、两段各低于 wall但总和超限的
non-rearm proof、two-phase peak join及 open transport limit/exit/signal。实现不含 `fork`、特殊产品
文件名或第二 ProgramV1 decoder。

该路径仍只声明 `darwin-development-observed`；process-group polling不能阻止 `setsid()` escape，完整
host race/controller-backed containment/formal qualification仍 pending。B12 已原子切产品 authority，但不得把 development-observed receipt 写成 contained/formal evidence。

## Parser version 与 identity 边界（ADR-0022 D1）

Static parser registry 当前 major 为 **`1`**，sole enabled default exact version 为 **`1.0.0`**
（omit `--language-version` ≡ 显式 `1.0.0`）。只接受 exact SemVer；拒绝 ranges、`latest`、
negotiation、unknown/disabled/nonunique default。**`languageVersion` 永不进入**
`programIdentity`、`sourceHashV1` 或 `NodeId` preimage；parser selection 是 host/CLI boundary
输入，不改变同一源码的 ProgramV1 identity。

## Containment assurance（ADR-0022 D2）

- **`darwin-development-observed`**：允许 ordinary development / `dev-check` / `ci`；**永不**
  表示 process/session containment 或 formal evidence。
- **Linux `contained`**：仅当每个 descendant 仍 controller-bound 且 resource attribution 为
  controller-event-backed 时可声明；禁止 silent assurance fallback。
- 本模块规格不冻结 cgroup 布局、polling、OS API 或 host-probe 分类。

诊断 pre-node 位置使用 diagnostic-only `DiagnosticOriginV1`（nullable `nodeId`）；common
`SourceOrigin` 保持非空 `NodeId`。**B6** 结构化 carrier 已存在；**B7a** 已退役 zero-sentinel
（parser/duplicate → `nodeId: null`），并提供 Source `DiagnosticLocateV1`（path draft →
inventory exact lookup → `nodeId=some`）与 `NodeTraversalV1.childPathV1` sole path helpers。
**B7b1–B7b3d** 工程已完成：Typed 各 producer 产出 canonical primary/related path drafts，且
`CheckV1` 提供 additive、`sourceHash`-gated located API（`checkProgramTypedLocated*`）；
**B8b** 已接线 located multi-error compiler chain；**B12** 把 sole CLI source 入口改为 `superviseFrontendSourceV1`，由 worker shared snapshot parse/select→SpanJoin，composer request-bind 后 sole reconstruct `ValidatedSourceV1 × OriginInventoryV1`。产品路径不再使用 raw diagnostic-array carrier、`*WithDiagnostics`、CLI Loader 或 caller-side reconstruct。非产品兼容面保留 `selectProgramV1Product` / `selectProgramV1` / `WithSpans` / `WithOrigins`。
不得把 B8b 工程 cutover 写成 formal D1/D2 完成、release 完成或 contained frontend 完成；
formal 与 release 仍 unassessed/pending。

## 边界与验收

必须覆盖：缺失/非法 `--module`、raw component identity、零/多 program、精确 `--program`、
重复 identity、非法 import/command、source/depth/node bounds、Counter 的
`Syntax → ValidatedSourceV1 → Typed → Semantic → EVM Plan/IR/artifacts`、以及 unsupported
构造 fail closed。任何失败不得发布 output，也不得尝试 legacy reader。parser default
`1.0.0`/omit 等价、languageVersion 不进 hash、development-observed 不冒充 contained。

关联 `ADR-0019`、`ADR-0022`、`SPEC-LANG-001`、`SPEC-SOURCE-WIRE-001`、`SPEC-SEM-WIRE-001`、
`SPEC-DIAG-001` 与 `TST-SRC-*`。
