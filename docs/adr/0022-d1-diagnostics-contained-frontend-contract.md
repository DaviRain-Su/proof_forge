---
id: ADR-0022
title: D1 diagnostic and contained-frontend engineering contract
status: proposed
owner: architecture
updated: 2026-07-29
normative: true
---

# ADR-0022：D1 diagnostic / contained-frontend engineering contract

- 状态：`proposed`
- 日期：2026-07-29

本文是 **decision-complete proposed** 工程契约：冻结 D1 诊断面与 contained frontend 边界上
若干必须先钉死的选择，供后续 B 系列实现切片引用。本文 **不是** formal approval、release
qualification、worker frame protocol 规格，也不宣称任何代码已迁移完成。

## 背景

D1 恢复路径同时依赖：

1. exact DSL parser version selection（`SPEC-VER-001` registry、`SPEC-CLI-001`
   `--language-version`）；
2. process/session containment 与 resource attribution（`SPEC-COMMON-001` ResourceProfile、
   supervisor receipt）；
3. 稳定机器诊断（`SPEC-DIAG-001`）与 CLI JSON 结果面（`SPEC-CLI-001`）。

当前文档对这些边界存在可实现歧义：parser default 的 exact SemVer 未钉到 sole
`1.0.0`；Darwin 开发观察与 Linux controller-backed containment 易被混写为 formal evidence；
supervisor receipt 与 public diagnostic 边界不清；pre-node parser 位置缺少显式 nullable
`NodeId` 诊断 origin；alpha runtime `PF-SEM-*` 子原因字符串若过早冻结会与未闭合的 D2
semantic outcomes 冲突。

本 ADR 只记录最小 decision-complete 工程契约，并要求对应 specs/modules 作澄清性对齐。
**非目标（explicit non-goals）**：

- worker request/response schema ID、binary framing/magic、frame protocol；
- 新 diagnostic phase/code 全量 registry 或新 CLI exit codes；
- cgroup layout、polling cadence、OS API、host-probe taxonomy 的 operational freeze；
- SemVer ranges、`latest`、negotiation 或 common `SourceOrigin` 可空 NodeId；
- B6–B12 实现完成、formal approval、approvers、reviewCommit、accepted 声明；
- alpha `PF-SEM-*` runtime reason string/context 注册。

## 决定

### D1. Frontend parser version selection

1. Static parser registry 的 **current major 为 `1`**。
2. 当前 major 上唯一 enabled exact default 为 **`1.0.0`**。
3. `check`/`build` 省略 `--language-version` 与显式传入 `1.0.0` **解析为同一**
   `LanguageParserDescriptor`（omit ≡ `1.0.0`）。
4. 只接受 registry 内 **exact SemVer** 选择。必须拒绝：version ranges、`latest`、
   major/minor negotiation、unknown exact version、disabled/revoked parser、以及
   non-unique current-major default。稳定码沿用 `PF-LANGUAGE-VERSION-UNKNOWN`、
   `PF-LANGUAGE-VERSION-DISABLED`、`PF-LANGUAGE-DEFAULT`（见 `SPEC-DIAG-001`）。
5. **`languageVersion` 永不进入** ProgramV1 `programIdentity`、`sourceHashV1` 或 `NodeId`
   preimage。parser selection 是 host/CLI boundary 输入；同一源码在合法 parser 选择下的
   source identity 不因 version flag 拼写变化。

### D2. Containment assurance classes

1. **`darwin-development-observed`** 是 development observation class：允许在 Darwin 上运行
   ordinary `docs-check` / `dev-check` / `ci` 与 product development。它 **永不** 表示
   process/session containment 已实现，也 **永不** 表示 formal/hermetic evidence 可发布。
2. **Linux 才可声明 `contained`**，且仅当同时成立：
   - 每一个 worker descendant 仍受 controller 绑定（不可逃逸 session/job 边界）；
   - resource attribution 由 **controller event** 支撑（process denial / memory controller /
     protocol-output cap / monotonic deadline 的既有优先级；见 `SPEC-COMMON-001`）。
3. 禁止 silent assurance fallback：无法证明 controller-bound 或缺少 controller event 时，
   不得将 development observation 升格为 `contained`，也不得用 stderr 猜测 OOM/逃逸。
4. 本文 **不** 冻结 cgroup 目录布局、polling 周期、具体 OS API 表面或 host-probe 分类法；
   那些属于后续 operational / B 系列实现 contract。

### D3. Supervised check/build public receipts

1. 在 **supervised** `check`/`build` 路径上，JSON stdout object 在 **success 与 failure**
   均携带顶层 **`receipts`** 字段。
2. `receipts` 是 controller/supervisor 结果的 **bounded public-safe projection 与 digest**
   （hard/effective profile id/digest、observed peak/elapsed 的可公开摘要、controller event
   class、cleanup result 等已由 resource 规格约束的公开投影）。它不是：
   - raw 或 full internal receipt bytes；
   - stream tails、host absolute paths、secret env、private key 或 unredacted stderr；
   - `Diagnostic` / `diagnostics[]` 成员；
   - OutputSet artifact 或 artifact path。
3. human stderr 输出 **不是** 稳定 API；不得用 human 文本稳定承诺替代 JSON `receipts`
   或 diagnostics schema。
4. clean-room / formal stage failure retained receipts 继续按 `SPEC-DIAG-001` 隐私规则处理，
   不属于本顶层 public `receipts` 投影的扩充。

### D4. Diagnostic-only origins and ordering

1. Common **`SourceOrigin`**（`sourcePath,startByte,endByte,nodeId` 四字段、非空 `NodeId`）
   **保持不变**；不得把 nullable NodeId 塞进 common `SourceOrigin`。
2. 诊断面新增 **diagnostic-only** `DiagnosticOriginV1`：
   - 携带与 source snapshot 对齐的 path/byte range；
   - **`nodeId` 显式可空**（`Option NodeId` / JSON `null`），专供尚无 NodeId 的 pre-node
     parser/token/open 失败位置；
   - 不得用全零 16-byte sentinel 伪装“无节点”为合法 `NodeId`。**B7** 是将 diagnostic 路径
     上 zero-sentinel 替换为显式 `nodeId: null` 的实现切片；在 B7 完成前不得把 sentinel 当
     长期 public golden 语义，也不得声称迁移已完成（**本文不声称代码已迁移**）。
3. 每个诊断可携带 **stable redacted machine context**：
   - 公开字段名约定为 `context`（完整 redacted machine bag，按所属 code 条件必填规则）与
     排序用 **`stableContext`**（从 redacted bag 导出的 message-independent 稳定键；
     wire 可为 `null`/`Option.none`，**order/dedupe 键始终归一化为字符串**，`null` ≡ `""`）；
   - 值必须 redacted：禁止 secret、absolute host path、backtrace 地址进入 release JSON。
4. 多诊断 **order / dedupe 不得依赖可变 prose `message`**。规范排序键为
   `(sourcePath, startByte, code, orderStableContext)`，其中 `orderStableContext` 为
   `stableContext` 的字符串形式（`null`/`none` → `""`；与 `docs/03-technical-spec.md` 既有
   `stableContext` 方向一致）。`related : Array DiagnosticOriginV1`；origin 全序为
   `(sourcePath, startByte, endByte, orderNodeId)`，`nodeId=none` 严格小于任意 `some`。
   同键去重时亦忽略 message 措辞差异。

### D5. Semantic diagnostic codes freeze boundary

1. 规范语义码 **仅保留** 既有三条：
   - `PF-SEMANTICS-MISMATCH`
   - `PF-SEMANTIC-INVALID`
   - `PF-SEMANTIC-INTERNAL`
2. **推迟** 一切 alpha runtime `PF-SEM-*` 子原因字符串、子 code 与专用 context 注册，直至
   D2 semantic outcomes（normalize/reference/interpreter）闭合后再开独立切片。
3. 本文不新增 semantic phase 子码表，不扩展 exit code 表。

## 对 specs / modules 的澄清义务

| 文档 | 澄清范围 |
|---|---|
| `docs/specs/diagnostics.md` | DiagnosticOriginV1、nullable NodeId、stableContext 排序、语义码边界、receipt≠diagnostic |
| `docs/specs/common-types.md` | SourceOrigin 不变；diagnostic-only origin 指针；containment assurance 与 controller-event 归因不 silent fallback |
| `docs/specs/cli.md` | parser default `1.0.0`；supervised JSON 顶层 `receipts` |
| `docs/modules/source-frontend.md` | languageVersion 不进 identity/hash/NodeId；darwin-development-observed 边界 |
| `docs/modules/cli-orchestrator.md` | supervised receipts 投影；不把 receipt 当 diagnostic/artifact |

各文档保持其当前 lifecycle status（多为 `proposed`），仅更新 `updated` 日期与规范性澄清，
不把本 ADR 写成 `accepted`。

## 后果

- 实现切片可按 exact `1.0.0` default 与 omit 等价编写 parser registry，无需 range 引擎。
- Darwin CI 继续合法，但不能把 development observation 写成 contained/formal。
- CLI JSON consumer 可依赖顶层 `receipts` 的 public-safe 形状，而不解析 internal receipt。
- 诊断排序/golden 可固定 code+stableContext，允许改 human message 而不破坏 order golden。
- D2 semantic 子原因可在 outcomes 明确后独立设计，不被过早 alpha 字符串锁死。

## 否决方案

| 方案 | 否决原因 |
|---|---|
| 允许 `latest`/range/negotiation | 破坏 exact registry 与可复现 selection |
| 把 languageVersion 编入 sourceHash/NodeId | 同一源码因 CLI flag 产生不同 identity |
| Darwin observed ≡ contained | 伪造 process/session 边界与 formal evidence |
| 缺 controller event 时 silent 升格 contained | 归因不可审计，违反 fail-closed |
| receipt 并入 diagnostics 或 artifact | 混淆 public 诊断 schema 与 supervisor 投影 |
| common SourceOrigin 可空 NodeId | 污染 provenance/join 的非空 NodeId 不变量 |
| 用零 NodeId sentinel 作为长期 public 契约 | 与真实 NodeId 碰撞面；B7 才退役实现 |
| 现在冻结 alpha `PF-SEM-*` | D2 reference/interpreter 未闭合，会制造假稳定面 |

## 验证（工程，非 formal）

文档切片验收（development only）：

```text
just docs-check
git diff --check
rg -n 'ADR-0022|1\.0\.0|darwin-development-observed|DiagnosticOriginV1|stableContext|receipts' \
  docs/adr/0022-d1-diagnostics-contained-frontend-contract.md \
  docs/specs/diagnostics.md \
  docs/specs/common-types.md \
  docs/specs/cli.md \
  docs/modules/source-frontend.md \
  docs/modules/cli-orchestrator.md
```

后续实现切片（**不在本文范围**）才要求代码、SBOM pin、聚焦 Lean 测试与 ordinary `just ci`。
本文通过 **不** 构成 formal Stage-0、TaskQualification 或 release evidence。

## 后续实现指针（非完成声明）

- B 系列：contained frontend worker、supervisor receipt encoder、DiagnosticOriginV1 接线。
- **B7**：退役 diagnostic 路径上的零 NodeId sentinel，改走显式 nullable `DiagnosticOriginV1`。
- D2 闭合后：再评估是否需要 runtime semantic 子原因码（独立 ADR/spec 切片）。
