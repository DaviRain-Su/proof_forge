---
id: SPEC-DIAG-001
title: 稳定诊断规格
status: proposed
owner: frontend
updated: 2026-07-29
normative: true
---

# 稳定诊断规格

本规格对齐 [`ADR-0022`](../adr/0022-d1-diagnostics-contained-frontend-contract.md) 的 D1
diagnostic / contained-frontend 工程契约（proposed；非 formal approval）。

## Schema

```lean
structure DiagnosticOriginV1 where
  sourcePath : ProjectRelativePath
  startByte  : UInt64
  endByte    : UInt64
  nodeId     : Option NodeId   -- none = pre-node parser/token/open location

structure Diagnostic where
  schemaVersion : Nat -- 1
  code          : DiagnosticCode
  severity      : error | warning | note
  phase         : source | type | effect | semantic | resolve | plan | lower | emit | tool | deploy | verify
  message       : String
  primary       : Option DiagnosticOriginV1
  related       : Array DiagnosticOriginV1
  program       : Option Name
  target        : Option TargetId
  requirement   : Option RequirementKey
  extension     : Option ExtensionKey
  expected      : Option Json
  actual        : Option Json
  context       : Option Json      -- stable redacted machine bag (code-conditional)
  stableContext : Option String    -- message-independent order/dedupe key; order key normalizes null → ""
  suggestion    : Option String
```

JSON 模式 `proof-forge.diagnostic.v1`。人类 `message` 可改措辞；`code`、`phase` 和字段语义在
major version 内稳定。

### DiagnosticOriginV1 与 common SourceOrigin

- Common [`SourceOrigin`](common-types.md)（`sourcePath,startByte,endByte,nodeId`，**非空**
  `NodeId`）保持不变，继续服务 provenance/join 与 node-backed identity。
- 诊断 `primary`/`related` 均使用 **diagnostic-only** `DiagnosticOriginV1`（schema 字段
  `related : Array DiagnosticOriginV1`；无独立 `RelatedOrigin` 类型）：`nodeId` **显式可空**
  （JSON `null`），专供尚无 NodeId 的 pre-node parser/token/source-open 失败位置。
- Wire JSON 对每个 origin 对象字段为 `sourcePath`、`startByte`、`endByte`、`nodeId`
  （`nodeId` 可为 `null`）；`related` 为该对象数组，始终存在（可为空数组）。
- 不得把 nullable NodeId 回写 common `SourceOrigin`。
- 全零 16-byte NodeId sentinel 不是长期 public 契约。**B6** 已落地结构化 `DiagnosticV1`
  carrier/codec（closed code catalog、nullable `DiagnosticOriginV1`、PF-JCS encode/decode、
  message-independent order/dedupe、结构 redaction、`normalizeDiagnosticBundleV1` cap 工程
  子集；产品 multi-error bundle 未接线）。**B7a** 已退役 pre-node zero-sentinel：parser/
  duplicate 位置使用显式 `nodeId: null`（`none`），Source `DiagnosticLocateV1` + Loader
  `selectProgramV1WithOrigins` 提供 path→真实 NodeId 归因基础设施；**B7b** Typed producers
  经 child-path helpers + `DiagnosticDraftV1` 物化真实 primary/related 已工程完成
  （B7b1–B7b3d，含 CheckV1 draft composition 与 additive located API）；**B8**（public
  CLI/compiler multi-error DiagnosticBundle）仍 pending。不得把已删除的 zero-sentinel 写入
  golden，也不得把 B7a/B7b 工程子集写成 formal/B8 完成。

### 排序、去重与 stableContext

多错误按 **message-independent** 键排序与去重。规范排序/去重键为四元组：

```text
(sourcePath UTF-8, startByte, code, orderStableContext)
```

其中 **`orderStableContext` 永远是 `String`**：比较与 dedupe **始终**在字符串形式上执行；
JSON/`Option` 字段 `stableContext = null`（或 `none`）**归一化为空串 `""`**，与显式
`stableContext = ""` **同一键**。实现不得对 `Option String` 使用未定义的 `none`/`some` 字典序。

缺 `primary` origin 时，`sourcePath`/`startByte` 使用 schema 固定的 empty/zero 占位，不得回退到
`message` 字典序。`stableContext` 从 redacted machine `context` 导出；无机器上下文时 wire 可写
`null` 或 `""`（二者 order 等价）。**order 与 dedupe 不得依赖可变 prose `message`**。同键
diagnostics 去重时忽略 message 措辞差异。默认最多 100 errors，超出追加 `PF-DIAG-LIMIT`。

#### DiagnosticOriginV1 全序（primary / related）

`DiagnosticOriginV1` 的规范全序键为：

```text
(sourcePath UTF-8, startByte, endByte, orderNodeId)
```

- `endByte` **参与** origin 排序（含 `related[]` 内排序与 multi-origin 稳定顺序）。
- **`orderNodeId`**：`nodeId = none` / JSON `null` **严格小于** 任意 `some nodeId`；
  两个 `some` 按 NodeId raw 16-byte 字典序比较。不得对 `Option NodeId` 使用未定义序。
- `related` 数组在 emit 前按上述 origin 全序排序；诊断级排序键仍只取 `primary` 的
  `(sourcePath, startByte)`（缺 primary 用 empty/zero），不把 `related` 并入诊断级四元组。

`schemaVersion`、`code`、`severity`、`phase`、`message` 在每个 diagnostic 中始终必填；`related`
始终存在（可为空）。其余字段按下表条件必填，未列为 required 的字段允许为空；`suggestion`
始终可空，不能为了满足指标生成无意义建议。`context`/`stableContext` 在 source-backed 与
selection/resolution 类错误上应按 code 提供稳定 redacted bag；无机器上下文时 wire 允许
`stableContext` 为 `null`（order 归一化为 `""`），但一旦出现非空 `context`/`stableContext`
则必须 redacted（无 secret、无 absolute host path、无 backtrace 地址）。

| Condition | Required context | 必须为空/限制 |
|---|---|---|
| CLI usage、source open/UTF-8、零 program | `expected`, `actual` | `target`, `requirement`, `extension` 为空；无合法 span 时 `primary` 为空（或 `primary.nodeId = null` 仅有 byte range） |
| source/type/effect/semantic 且节点已建立 | `primary`（`nodeId = some`）, `program`, `expected`, `actual` | target-free `check` 的 `target` 为空 |
| `PF-TARGET-UNKNOWN`/profile/registry selection | `target`, `expected`, `actual` | 无 source-backed program 时 `primary`/`program` 为空 |
| `PF-REQ-*`/`PF-EXTENSION-VERSION` | `program`, `target`, `primary`, `requirement` 或 `extension`, `expected`, `actual` | `related` 包含其余全部 origin，按 DiagnosticOriginV1 全序键排序 |
| plan/lower/emit/artifact build failure | `program`, `target`, `expected`, `actual` | `primary` 仅在错误可追溯到 source 时出现 |
| tool/output/resource containment | `expected`, `actual` | 只有 build context 已建立时才要求 `program`/`target`；不得输出 secret/absolute cwd；**supervisor `receipts` 不是 diagnostic**（见 SPEC-CLI-001 / ADR-0022） |
| internal compiler fault | `actual` 为稳定 fault class | release JSON 不含 backtrace、地址或宿主路径 |

`TST-DIAG-001` 必须逐行覆盖 required-field 缺失、target-free 合法 null、source-backed span、
多 origin 顺序、context 尚未建立时的合法 null 和 privacy-forbidden value；schema validator 对
requiredness 失败使用 `PF-INTERNAL`，因为 emitter 生成非法自身协议属于 compiler bug。

## 初始错误码

| Code | 条件 |
|---|---|
| `PF-SRC-001` | grammar/token 错误 |
| `PF-SRC-010` | declaration/name 重复 |
| `PF-SRC-020` | 非法/不受支持 item |
| `PF-SRC-NODEID-COLLISION` | 两个不同 canonical node preimage 截断为同一 128-bit NodeId；整份 program 零输出拒绝 |
| `PF-TYPE-001` | type mismatch |
| `PF-TYPE-002` | unknown/ambiguous name |
| `PF-TYPE-003` | invalid checked cast |
| `PF-TYPE-004` | non-serializable interface type |
| `PF-EFFECT-001` | callable 不允许推导出的 effect |
| `PF-EFFECT-002` | effect 未声明/不受支持 |
| `PF-BOUND-001` | portable Syntax/identifier/program identity 超过 100000 nodes 或 nesting/components 256；未来也用于无法证明的控制流 bound |
| `PF-SRC-INVALID` | source 非 UTF-8、超过 16 MiB 或无法进入 parser |
| `PF-RESOURCE-TIME` | contained compiler worker 超过 versioned monotonic wall budget |
| `PF-RESOURCE-MEMORY` | contained compiler worker 超过 versioned memory budget |
| `PF-RESOURCE-PROCESS` | contained compiler worker 创建超过允许数量的进程或逃逸 containment |
| `PF-RESOURCE-OUTPUT` | contained compiler worker protocol/stdout/stderr 超过 versioned budget |
| `PF-FRONTEND-PROTOCOL` | frontend worker 异常退出或返回 malformed/truncated/version-mismatched payload |
| `PF-LANGUAGE-VERSION-UNKNOWN` | 请求的 exact DSL parser version 未登记 |
| `PF-LANGUAGE-VERSION-DISABLED` | parser version 已禁用/撤销 |
| `PF-LANGUAGE-DEFAULT` | static parser registry 无唯一 current-major default |
| `PF-MIGRATION-FAILED` | source/schema migration 未能原子保持语义 |
| `PF-VIS-001` | 信息披露违规 |
| `PF-EXT-001` | 未声明 extension syntax |
| `PF-EXPORT-001` | exported program identity 冲突 |
| `PF-EXPORT-002` | 多 program 且选择缺失/歧义 |
| `PF-EXPORT-003` | source 中没有可导出的 program |
| `PF-EXPORT-004` | exported program constant payload 缺失、不安全、超界或不是受支持的 closed structural form |
| `PF-TARGET-UNKNOWN` | TargetId 不存在 |
| `PF-TARGET-NOT-IMPLEMENTED` | 只有设计档案 |
| `PF-PROFILE-UNKNOWN` | Codegen/Network profile 不存在或属于其他 target |
| `PF-PROFILE-REVOKED` | profile/evidence 已撤销或过期 |
| `PF-REGISTRY-DUPLICATE` | registry ID/key/default 重复 |
| `PF-REGISTRY-INVALID` | descriptor/profile/digest/compatibility invariant 失败 |
| `PF-REQ-UNSUPPORTED` | exact requirement 无 claim |
| `PF-REQ-PRECONDITION` | claim predicate 不满足 |
| `PF-REQ-EVIDENCE` | evidence 低于 profile 要求 |
| `PF-REQ-CONFLICT` | requirements 不可合并 |
| `PF-EVIDENCE-BINDING` | support EV 缺失 candidate/target/profile/requirement/freshness/revocation binding |
| `PF-SEMANTICS-MISMATCH` | target observation 不等价 |
| `PF-SEMANTIC-INVALID` | canonical semantic schema/invariant 失败 |
| `PF-SEMANTIC-INTERNAL` | reference interpreter 命中不可能状态 |
| `PF-EXTENSION-VERSION` | version/digest mismatch |
| `PF-PLAN-INVARIANT` | Plan 非法 |
| `PF-LOWER-INVARIANT` | TargetIR 非法 |
| `PF-TOOLCHAIN-MISMATCH` | tool missing/version/hash mismatch |
| `PF-TOOLCHAIN-MISSING` | required locked asset/cache/tool 不存在 |
| `PF-TOOL-UNTRUSTED` | executable/path/env/closure 未通过信任验证 |
| `PF-TOOL-PROTOCOL` | external tool 异常退出或返回 malformed/truncated/version-mismatched payload |
| `PF-HOST-STAGE0` | Stage-0 record、bootstrap digest、签名或启动环境无效 |
| `PF-HOST-INELIGIBLE` | live host 匹配 development profile，但不具备 formal hermetic 资格 |
| `PF-ARTIFACT-INVALID` | 制品/manifest 校验失败 |
| `PF-ARTIFACT-NONDEPLOYABLE` | 请求部署不可部署制品 |
| `PF-SETTLEMENT-UNAVAILABLE` | 无 settlement adapter |
| `PF-OUTPUT-PATH` | output path/containment/symlink 违规 |
| `PF-OUTPUT-COLLISION` | destination/artifact path/casefold 冲突 |
| `PF-OUTPUT-LIMIT` | file/count/path/published byte limit 超限 |
| `PF-OUTPUT-ATOMICITY` | staging/fsync/rename/rollback 失败 |
| `PF-DIAG-LIMIT` | 超过 100 条诊断后的唯一截断 sentinel |
| `PF-INTERNAL` | compiler bug；永不用于用户输入错误 |

### Semantic code freeze（ADR-0022 D5）

上表中 `PF-SEMANTICS-MISMATCH` / `PF-SEMANTIC-INVALID` / `PF-SEMANTIC-INTERNAL` 是 **唯一**
规范语义码。不得在 D2 semantic outcomes 闭合前登记、冻结或公开稳定 alpha runtime
`PF-SEM-*` 子原因字符串、子 code 或专用 context 形状；实现临时字符串不得进入上表或
release golden。

Requirement rejection 必须带 target、requirementId、version/digest、所有 source origins、
expected claim 和 actual/missing；toolchain error 带预期版本/checksum、解析到的 executable
路径与实际版本，但不输出敏感环境。

**实现状态（工程，非 formal）**：**B6** 已实现完整 `DiagnosticV1` record/JSON codec 与
catalog（见 `ProofForgeV2/Core/DiagnosticV1.lean` + `Tests/Core/DiagnosticV1`）；Loader 单错误
产品路径与 Typed producers 经 `DiagnosticV1.make` 发出结构化诊断（Typed primary 多为空，
真实节点归因见 B7）。**B7a** 已提供 Source path locate + pre-node `nodeId=null`，**B7b**
工程已完成（含 B7b3d CheckV1 located composition）；**B8** public bundle 仍 pending。Syntax preflight 通过 `CompileError.resourceBound` 保留稳定 code `PF-BOUND-001`，
human message 只说明超出的 node/nesting/identity limit。CLI 的 16 MiB parser 前文件上限仍是
`CompileError.invalidProgram` / `PF-SRC-INVALID`；这两个边界不得在证据中混写。

## 隐私与安全

diagnostic 只显示 source lexeme 的安全截断；private literal、witness、secret env、RPC token、
private key 一律替换为 `<redacted>`。路径默认 project-relative；`--verbose-paths` 也不进入
JSON/reproducible evidence。外部工具 stderr 以 64 KiB 截断、去 ANSI、标记 untrusted。

clean-room stage failure receipt 不属于公共 `Diagnostic v1`。development continuation 只把
stdout/stderr 各最后 32768 bytes 转成 ASCII representation 后回显，并同时输出 receipt
digest；该转义阻止控制字节操纵终端，但不会自动删除 printable secret。formal evidence
必须先 retained、private-scanned/redacted，再决定可公开的诊断摘要。

supervised `check`/`build` JSON 顶层 **`receipts`**（ADR-0022 D3 / SPEC-CLI-001）是
public-safe supervisor projection/digest，**不是** `diagnostics[]` 元素、也不是 artifact。
diagnostic emitter 不得把 raw/full receipt、stream tails、host paths 或 secrets 塞进
`Diagnostic` 字段。

## 边界与验收

覆盖无 span、多个 origin、pre-node `nodeId: null`、Unicode、100/101 errors、related cycle、
private literal、外部工具二进制输出/ANSI/巨大 stderr、unknown enum field、JSON roundtrip、
**message-independent 排序/dedupe（改 message 不改序）**、同 code 不同 target/stableContext、
suggestion 缺失、compiler bug backtrace（只在 debug）、broken pipe、receipts≠diagnostic。关联
`NFR-002`、`TST-DIAG-001`、全部 negative TST、`ADR-0022`；golden 固定 JSON fields/code/
stableContext 而非完整英文 message。
