---
id: MOD-SOURCE-001
title: SourceFrontend 模块规格
status: proposed
owner: frontend
updated: 2026-07-25
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

旧 `parsePrograms`/`selectProgram`、`decodeProgramCommandChecked`、Lean command quote 与
`proof-forge.program-export.v1` 仍为历史 `Source.Program` characterization 测试服务；CLI、
`build-counter` 和 `compileValidatedSourceV1` 均不调用它们，也没有失败后回退。它们是下一轮删除/搬迁
清单，不得扩张新语法、identity、hash 或产品行为。

ProgramV1 到 Typed 的产品边界是 `Typed.checkV1`，它直接消费 `ValidatedSourceV1`，不构造
legacy `Source.Program`。source hash 只来自 `sourceHashV1`。NodeId 由
`assignNodeIdsV1(moduleName, programIdentity, program)` 从 validated source 派生；文件路径、span、
comment 与 allocation history 不参与 identity/hash。

当前 in-process CLI loader 尚未实现规范 contained frontend worker，因此输出仍是 development
级；这不妨碍普通产品测试，但不能声称 formal/hermetic evidence。

## 边界与验收

必须覆盖：缺失/非法 `--module`、raw component identity、零/多 program、精确 `--program`、
重复 identity、非法 import/command、source/depth/node bounds、Counter 的
`Syntax → ValidatedSourceV1 → Typed → Semantic → EVM Plan/IR/artifacts`、以及 unsupported
构造 fail closed。任何失败不得发布 output，也不得尝试 legacy reader。

关联 `ADR-0019`、`SPEC-LANG-001`、`SPEC-SOURCE-WIRE-001`、`SPEC-SEM-WIRE-001` 与
`TST-SRC-*`。
