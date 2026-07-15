---
id: MOD-CLI-001
title: CliOrchestrator 模块规格
status: proposed
owner: cli
updated: 2026-07-15
normative: true
---

# CliOrchestrator

模块把 argv 转成 typed command，调用 frontend/semantics/resolver/materializer/artifact public
API，并渲染 human/JSON result。它不 import target Plan/IR 模块，不读取 registry 之外的 target
常量，不用 shell 拼接命令。

命令状态：`parse → validate options → invoke one service → render → exit`；每个 invocation 只
执行一个 command。stdout JSON 原子写单 object；日志 stderr；broken pipe 作为 I/O error，
不重跑副作用命令。

覆盖全部命令/flags、multi-program、unknown target/profile/network、exit priority、JSON/human、
TTY、signals、private file/FD、build network prohibition、deploy bundle revalidation、proof
mismatch、output force。关联 `SPEC-CLI-001`、`TASK-D3-06`、`TST-CLI-*`。
