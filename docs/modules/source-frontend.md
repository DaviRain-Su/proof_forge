---
id: MOD-SOURCE-001
title: SourceFrontend 模块规格
status: proposed
owner: frontend
updated: 2026-07-29
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
bounded source read
  → locked Lean parser
  → command whitelist / namespace tracking
  → decodeProgramCommandV1Checked(moduleName, namespace, syntax)
  → validateSourceV1
  → ValidatedSourceV1
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

**sole product Loader 入口**为 `selectProgramV1Product`：同一 parser snapshot 上 parse/select →
SpanJoin → OriginJoin，返回 `DiagnosticResultV1 (ValidatedSourceV1 × OriginInventoryV1)`。
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
`checkProgramTypedLocatedResultV1` 的单次调用；成功后 residual alpha `Typed.checkV1` 只负责
现有 Typed IR/materializer bridge，不是产品诊断 authority。两者都直接消费
`ValidatedSourceV1`，不构造 legacy `Source.Program`。source hash 只来自 `sourceHashV1`。NodeId 由
`assignNodeIdsV1(moduleName, programIdentity, program)` 从 validated source 派生；文件路径、span、
comment 与 allocation history 不参与 identity/hash。

当前产品 CLI 仍使用 in-process source open/Loader；B10 standalone worker 尚未接入产品，也没有
safe-open、supervisor 或 containment。因此输出仍是 development 级；这不妨碍普通产品测试，
但不能声称 formal/hermetic evidence。

## FrontendProtocolV1 与 standalone worker（B9/B9R/B10）

**B9** 新增 `ProofForgeV2/Frontend/ProtocolV1.lean`：版本化、封闭、one-frame binary
request/response 地基；该历史切片当时 inert。**B9R** 修复两处边界：去掉任意 4096-byte
selector 语义上限；在 `parsePfJcs` 分配诊断数组前做 top-level PF-JCS 条目预扫描。
**B10** 在不改变 wire 的前提下新增非产品 standalone worker；仍无 safe-open、supervisor/receipt、
CLI/Loader/Compiler 产品切换或 target 变更。

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

B10 **不**读取路径、不 spawn 子进程、不接受 target/profile、不写 cache/artifact；但它也**不**
提供 safe-open、timeout/OOM/process containment、supervisor/receipt 或 CLI product cutover。
这些属于 B11/B12；formal TASK-D1-08 仍 pending。

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
**B8b** 已接线 sole product Loader 入口 `selectProgramV1Product`：同一 parser snapshot 上
parse/select → SpanJoin → OriginJoin，返回 `DiagnosticResultV1 (ValidatedSourceV1 ×
OriginInventoryV1)`；产品路径不再使用 raw diagnostic-array carrier 或
`*WithDiagnostics`。非产品兼容面保留 `selectProgramV1` / `WithSpans` / `WithOrigins`。
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
