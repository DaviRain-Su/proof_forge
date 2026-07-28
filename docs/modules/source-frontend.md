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

**sole source-reading 入口**为 `parseProgramsV1` / `selectProgramV1`（及 additive
`selectProgramV1WithSpans` / `*WithDiagnostics`）。legacy source-reading/export decoder 家族
（`parsePrograms`/`selectProgram`、`decodeProgramCommandChecked`、`decodeType`/`Param`/`Expr`/
`Statement`/`Item`/`Program`、`proof-forge.program-export.v1` payload 路径）**已删除**；产品
路径禁止 dual reader、legacy→ProgramV1 adapter 或第二套 ProgramV1 decoder。残存 alpha
`Core/Source` / Typed-alpha carriers（若仍存在）仅供 D2 consumer 清理，**不是**产品 dual
reader，也不得从 CLI/Loader 重新挂回。

ProgramV1 到 Typed 的产品边界是 `Typed.checkV1`，它直接消费 `ValidatedSourceV1`，不构造
legacy `Source.Program`。source hash 只来自 `sourceHashV1`。NodeId 由
`assignNodeIdsV1(moduleName, programIdentity, program)` 从 validated source 派生；文件路径、span、
comment 与 allocation history 不参与 identity/hash。

当前 in-process CLI loader 尚未实现规范 contained frontend worker，因此输出仍是 development
级；这不妨碍普通产品测试，但不能声称 formal/hermetic evidence。

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
`SourceOrigin` 保持非空 `NodeId`。**B7** 是将 diagnostic 路径上 zero-sentinel 替换为显式
`nodeId: null` 的实现切片；在 B7 完成前不得把 sentinel 当长期 public golden 语义，也**不**
因本澄清声称代码已迁移。

## 边界与验收

必须覆盖：缺失/非法 `--module`、raw component identity、零/多 program、精确 `--program`、
重复 identity、非法 import/command、source/depth/node bounds、Counter 的
`Syntax → ValidatedSourceV1 → Typed → Semantic → EVM Plan/IR/artifacts`、以及 unsupported
构造 fail closed。任何失败不得发布 output，也不得尝试 legacy reader。parser default
`1.0.0`/omit 等价、languageVersion 不进 hash、development-observed 不冒充 contained。

关联 `ADR-0019`、`ADR-0022`、`SPEC-LANG-001`、`SPEC-SOURCE-WIRE-001`、`SPEC-SEM-WIRE-001`、
`SPEC-DIAG-001` 与 `TST-SRC-*`。
