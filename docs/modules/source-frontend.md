---
id: MOD-SOURCE-001
title: SourceFrontend 模块规格
status: proposed
owner: frontend
updated: 2026-08-02
normative: true
---

# SourceFrontend

> **当前工程覆盖（2026-08-02）**：2026-08-01 的产品决策已删除 B11/B12
> safe-open / supervisor 层、对应 native 实现、safe-open worker executable 与删除门禁；
> B10 frontend worker 模块及 standalone optional executable 仍保留。当前 CLI 在进程内以
> `IO.FS.readFile` 读取已做词法校验的 root-relative path，随后调用
> `Loader.selectProgramV1Product`；该 frontend worker 不在产品调用链。
> 本文后半部的 B11/B12 细节只保留为 **superseded 历史设计**，不得用于描述当前产品
> assurance、测试资格或 release 状态。该工程决策与 accepted ADR-0022/架构中的 contained
> frontend 意图尚待正式 ADR 处置。

产品输入为 UTF-8 Lean source、显式 main-module `Lean.Name` 与可选的精确 program selector；
输出为 `ValidatedSourceV1`。模块拥有 grammar、bounded Syntax preflight、raw source identity、
ProgramV1 declaration validation、canonical source hash 与派生 NodeId 输入；不做 target lookup、
storage/ABI planning 或外部网络 I/O。

## 当前产品路径

CLI 的唯一产品路径为：

```text
canonical ProjectRelativePath + lexically resolved project root
  → in-process IO.FS.readFile
  → Loader.selectProgramV1Product / locked Lean parser
  → command whitelist / namespace tracking
  → decodeProgramCommandV1Checked(moduleName, namespace, syntax)
  → validateSourceV1 + SpanJoin + OriginJoin
  → ValidatedSourceV1 + OriginInventoryV1
```

`proof-forge-next build` 必须接收 `--module <Lean.Name>`。Loader 使用锁定 Lean term parser
exact-consume 该值，并且只接受最终 Syntax 为一个 pure `.str` identifier chain；不得从文件路径推导、
按 `.` 做字符串 split、NFC/casefold 或使用 rendered name 作为 canonical identity。
`programIdentity` 精确等于
`moduleName.components ++ activeNamespace.components ++ declarationName.components`。
`--program` 使用同一 parser 和 raw component equality。

ProgramV1 Loader 已覆盖当前统一语言表面（declarations、recursive types、control flow、
match、calls/effects、aggregates 与现有 expression/operator families）；具体 shipped lowering 能力由
Typed/Normalize 与各 target capability gate 决定。parser 可接受但 decoder/typed/semantic/target 尚未
支持的形状必须在对应边界稳定 fail closed；不得 fallback 到 legacy decoder。

## ParserSession

`ParserSession.create` 只导入锁定的 `ProofForgeV2.Language.Syntax` environment；同一进程在一个
control thread 创建后复用该 immutable session。sole 产品 Loader API 是
`selectProgramV1Product(source, logicalSourcePath, moduleName, requested?)`；
`parseProgramsV1` / `selectProgramV1` 是非产品库面。session 不保存用户 source、program、
typed/core cache 或 target 状态，因此复用只能称为 same-session full recheck。

source byte cap 为 16 MiB；每个 program command 在递归 decoder 前执行 100000-node、
root-inclusive 256-depth preflight。namespace scope 可以临时超过 256 components；Loader 保存可恢复的
overflow state，并在退回合法 scope 后才构造 identity。CLI 不 elaboration、不执行 `run_cmd` 或其他
非白名单 Lean command。

## 迁移与兼容边界

**sole CLI source 入口**为 `CLI.Main.loadSourceProduct`：在 lexically resolved project root 下以
`IO.FS.readFile` 读取 canonical `ProjectRelativePath`，再调用
`Loader.selectProgramV1Product`。后者在同一 parser snapshot 上完成 parse/select→SpanJoin→OriginJoin，
构造 `ValidatedSourceV1 × OriginInventoryV1` 后交给 compiler；不 reparse、不 fallback。
`Frontend.ProtocolV1` / `WorkerV1` 当前不在产品调用链。其余 **非产品库 API** 为
`parseProgramsV1` / `selectProgramV1` / `selectProgramV1WithSpans` /
`selectProgramV1WithOrigins`（`WithOrigins` 在同一 immutable snapshot 上串联 SpanJoin→OriginJoin，
产出 opaque `OriginInventoryV1`；identity/canonical bytes/sourceHash 不变）。
已删除的 raw `*WithDiagnostics` / `Except (Array DiagnosticV1)` failure carrier **不得**复活。
legacy source-reading/export decoder 家族（`parsePrograms`/`selectProgram`、
`decodeProgramCommandChecked`、`decodeType`/`Param`/`Expr`/`Statement`/`Item`/`Program`、
`proof-forge.program-export.v1` payload 路径）**已删除**；产品路径禁止 dual reader、
legacy→ProgramV1 adapter 或第二套 ProgramV1 decoder。alpha `Core/Source`、Typed/SemanticIR/
Semantics 与 AlphaCompatibility 产品链已物理删除，不得从 CLI/Loader 重新引入。

ProgramV1 的产品诊断 Typed 边界是 `normalizeProgramLocatedV1` 对
`checkProgramTypedLocatedResultV1` 的单次调用；成功后 compiler 只 mint `CompiledSemanticV1`，
resolver、target Plan与artifact identity均不再调用 alpha Typed/Semantic bridge。产品链直接消费
`ValidatedSourceV1`，不构造 legacy `Source.Program`；`AlphaCompatibility` 已物理删除，不存在
hand-built 或产品兼容路径。
source hash 只来自 `sourceHashV1`。NodeId 由
`assignNodeIdsV1(moduleName, programIdentity, program)` 从 validated source 派生；文件路径、span、
comment 与 allocation history 不参与 identity/hash。

2026-08-01 产品决策已 **supersede 并删除** B11a/B11a2/B11b1/B11b2/B12 产品监督层：
`SafeOpen*`、`DarwinSupervisor*`、native C、safe-open worker executable 与 B12 deletion gate
均不再存在；B10 frontend worker 模块与 standalone optional executable 保留。当前 CLI source
authority 是上述进程内 `IO.FS.readFile` →
`selectProgramV1Product`；16 MiB gate 在 source 已读入后由 Loader 执行。该路径不提供
no-follow/single-link snapshot、worker isolation、receipt 或 contained assurance。协议与
`WorkerV1` 保留作非产品表面；formal `TASK-D1-07/08` 仍 pending，且 contained/formal 资格不能从
已删除实现推导。

## Protocol/worker retained surface 与已删除 supervisor 的历史记录

**当前保留**：B9/B9R 的 `Frontend.ProtocolV1` one-frame wire，以及 B10 的
`Frontend.WorkerV1` / `WorkerMainV1` 模块源码和 lakefile 注册的 standalone
`proof-forge-frontend-worker-v1`；它不在产品 CLI 调用链。**历史且已删除**：
B11a/B11a2/B11b1/B11b2/B12 的 safe-open、receipt、native
supervisor 与 product cutover。以下小节记录当时设计/测试语义，全部视为 superseded，不得据此
声称当前路径具有 snapshot、receipt、resource attribution 或 containment。

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
本身不提供 safe-open 或 supervisor/receipt。历史 B11a/B11a2/B11b1 曾分别交付 safe-open
foundation、pure receipt 与 Darwin development-only worker supervision；B11b2 曾交付 shared
source-open/worker deadline composition，B12 曾完成产品原子切换，但这些监督实现随后已删除。
formal TASK-D1-08 仍 pending。

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
process observations、closed event/result/cleanup class，并按 host 固定 assurance
`darwin-development-observed` 或 `linux-development-observed`。Linux hard profile明确使用
`linuxProcRssAggregate`，不是 Darwin footprint 或 cgroup metric。PF-JCS 是 11-field closed object，4 KiB pre-parse cap，profile/request/
receipt digest 全部 domain-separated 且 parse 后 exact re-encode；unknown privacy fields（path、PID、
signal、exit code、stderr/tail/secret/detail）无 carrier 并在 decoder 边界拒绝。

`Tests/Frontend/DarwinSupervisorReceiptV1.lean` 固定 exact 929-byte golden、receipt digest KAT、
request replay rejection、lower-only effective profile、event/result/request cross-field invariants、
equal/first-over resource projection、closed enum/field/canonical failures和 privacy key rejection。
本模块自身仍是纯模型：**不** open/spawn/measure/kill/reap，不输出 CLI JSON，也不代表任何 host
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

`Tests/Frontend/DarwinWorkerSupervisorV1.lean` 在 Darwin 与 Linux 以真实 worker/子进程覆盖 Ok/Err、deadline、
process/memory、stdout/stderr cap 与 exact-cap acceptance、nonzero exit/signal、malformed/cross-request、
missing worker、lower-only profile、private snapshot path/cleanup、snapshot self-mutation、inherited
writable ACL清除（Darwin）、ambient descriptor拒绝（Linux）、worker symlink/hardlink/non-executable/oversize rejection和 cleanup/result join。Linux snapshot位于验证过的root-owned sticky `/tmp`，fork child在exec前以`close_range`清除fd 3以上能力，并通过`/proc`采样原process group与aggregate RSS；采样错误fail closed。

B11b1 primitive **不** import `SafeOpenV1`、不读取 source path，也无法阻止 descendant `setsid()`
逃离 process group；B12 虽已消费它作为 CLI source authority，assurance仍只是对应host的
development-observed。snapshot 不构成 formal executable digest/signature；在 sole native open
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

该历史路径当时只声明 `darwin-development-observed`；process-group polling不能阻止 `setsid()`
escape，且从未闭合完整 host race/controller-backed containment/formal qualification。B12 当时的
产品 authority 已被后续删除；不得把其历史 receipt 写成当前 contained/formal evidence。

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
**B8b** 已接线 located multi-error compiler chain；当前 sole CLI source 入口为进程内
`IO.FS.readFile` → `selectProgramV1Product`，并在 Loader 同一 snapshot 内完成
parse/select→SpanJoin→OriginJoin。产品路径不使用 raw diagnostic-array carrier、
`*WithDiagnostics`、第二 decoder 或 fallback；Protocol/Worker 只保留为非产品表面。
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
