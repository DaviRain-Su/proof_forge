---
id: MOD-SOURCE-001
title: SourceFrontend 模块规格
status: proposed
owner: frontend
updated: 2026-07-15
normative: true
---

# SourceFrontend

输入为 Lean syntax/environment 和 UTF-8 source metadata；当前 alpha 输出
`Source.Program`，完整规格后再增加 `SourceOrigin`，或返回 `PF-SRC/EXPORT-*`。
API：共享 syntax decoder、`parsePrograms`、`selectProgram(name?)`，以及供 Lean 源码直接
编译使用的 command elaborator。它拥有 grammar、NodeId、span、SourceHash；
不做 target lookup、storage/ABI planning 或外部 I/O。

状态：CLI 路径为 `tokens → Lean Syntax → whitelist/decode → Source.Program`；直接 Lean
编译路径为 `tokens → Lean Syntax → shared decode validation → registered constant`。CLI
路径不得 elaboration 或执行用户 command；失败不得修改 environment extension。

前置：Lean module name 已知、source limits 内；后置：payload schema v1、所有引用 span
有效、hash canonical。边界：零/多 program、重复名/import diamond、NFC、非法 UTF-8、
deep AST、proof ref 缺失、attribute schema mismatch、路径变化、error recovery、并行 module
build。安全：不执行任意 term/macro callback、无文件/网络访问。

关联 `SPEC-LANG-001`、`TASK-D1-*`、`TST-SRC-*`；验收为语法 golden、fuzz、跨模块
loader 和 environment rollback tests。
