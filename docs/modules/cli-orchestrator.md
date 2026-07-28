---
id: MOD-CLI-001
title: CliOrchestrator 模块规格
status: proposed
owner: cli
updated: 2026-07-29
normative: true
---

# CliOrchestrator

模块把 argv 转成 typed command，调用 frontend/semantics/resolver/materializer/artifact public
API，并渲染 human/JSON result。它不 import target Plan/IR 模块，不读取 registry 之外的 target
常量，不用 shell 拼接命令。

命令状态：`parse → validate options → invoke one service → render → exit`；每个 invocation 只
执行一个 command。stdout JSON 原子写单 object；日志 stderr；broken pipe 作为 I/O error，
不重跑副作用命令。

## Parser selection（ADR-0022 D1 / SPEC-CLI-001）

`check`/`build` 的 `--language-version` 只解析 static registry 内 exact SemVer。当前 major `1`
的 sole default 为 **`1.0.0`**（omit ≡ `1.0.0`）。orchestrator 不得实现 ranges、`latest` 或
negotiation；selection 失败映射既有 `PF-LANGUAGE-*` 诊断。`languageVersion` 不传入
ProgramV1 identity/hash/NodeId 构造。

## Supervised public `receipts`（ADR-0022 D3）

supervised `check`/`build` 的 JSON object 在 **success 与 failure** 均带顶层 **`receipts`**：
bounded public-safe supervisor projection/digest。orchestrator **不得**：

- 把 raw/full receipt、stream tails、host paths 或 secrets 写入 stdout JSON；
- 把 receipt 当作 `diagnostics[]` 元素或 diagnostic 字段；
- 把 receipt 当作 OutputSet artifact 或 artifact path；
- 以 human stderr 文本充当稳定 receipt API。

development in-process 路径若发出 observation 投影，assurance class 必须可区分
（`darwin-development-observed` 永不等于 `contained` / formal evidence；Linux `contained` 仅在
controller-bound + controller-event attribution 下成立，禁止 silent fallback）。

覆盖全部命令/flags、multi-program、unknown target/profile/network、exit priority、JSON/human、
TTY、signals、private file/FD、build network prohibition、deploy bundle revalidation、proof
mismatch、output force、parser default `1.0.0`、supervised `receipts` 形状。关联
`SPEC-CLI-001`、`SPEC-DIAG-001`、`ADR-0022`、`TASK-D3-06`、`TST-CLI-*`。
