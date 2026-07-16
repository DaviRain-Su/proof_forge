---
id: MOD-SOURCE-001
title: SourceFrontend 模块规格
status: proposed
owner: frontend
updated: 2026-07-16
normative: true
---

# SourceFrontend

输入为 Lean syntax/environment 和 UTF-8 source metadata；当前 alpha 输出
`Source.Program`，完整规格后再增加 `SourceOrigin`，或返回 `PF-SRC/EXPORT-*`。
API：共享 syntax decoder、one-shot `parsePrograms`/`selectProgram(name?)`、可复用不可变
Lean parser environment 的 `ParserSession`，以及供 Lean 源码直接编译使用的 command
elaborator。它拥有 grammar、NodeId、span、SourceHash；
不做 target lookup、storage/ABI planning 或外部 I/O。

状态：CLI 路径为 `16 MiB byte cap → Lean parser → per-program iterative Syntax preflight →
whitelist/checked decode → Source.Program`；直接 Lean 编译路径为 `Lean parser → per-program
iterative Syntax preflight → shared decode validation → quote decoded Source.Program → registered constant`。
两路共享 100000 nodes、root-inclusive nesting 256 与 qualified identity components 256；
预算按 program command 计算，不按整个 module 累计。CLI 路径不得 elaboration 或执行用户
command；失败不得修改 environment extension。namespace scope 可以临时超过 256 components；
Loader 此时只保存可恢复的 overflow state，不构造超限聚合 `Name`，并在退回合法 scope 后按
最终 program identity 判定。

`ParserSession.create` 只导入锁定的 `ProofForgeV2.Language.Syntax` environment；同一进程内
必须在单一 control thread 创建后复用/共享该 immutable session；不支持并发 create，且连续
解析多个独立 source 时不能为每个 negative vector 重复
执行 `enableInitializersExecution/initSearchPath/importModules`。one-shot API 仍为 CLI 单文件
调用保留，并必须在创建 session 前执行 16 MiB byte-cap fast rejection；session method 内仍
重复同一 byte-cap 检查。session 不保存用户 source、program 或 target 状态。

parser 前置只有 CLI byte cap；Syntax/node/nesting budget 在 parser 成功后、递归 decoder 前
验证，因此不保护 Lean parser。后置：payload schema v1、所有引用 span 有效、hash canonical。
边界：零/多 program、重复名/import diamond、NFC、非法 UTF-8、deep Syntax、proof ref 缺失、
attribute schema mismatch、路径变化、error recovery、并行 module build。安全：不执行任意
term/macro callback、无文件/网络访问。直接构造 `Source.Program` 的 API 不经过本模块。

`decodeProgramCommandChecked` 同时拥有当前 alpha declaration validation；其返回值是两条生产
路径唯一的业务 AST。Loader 不得重复验证 program 内 declarations，command elaborator 不得从
raw `Syntax` 重新构造第二份 AST，只能穷举 quote 已 decode 的 `Source.Program`。双入口对当前
全部 constructor 的 `Source.Program` 与 `sourceHash` 必须相等；zero-callable、duplicate
state/entry/initializer parameter/entry parameter 必须返回相同 code/message 且不注册常量或发布
CLI output。

关联 `SPEC-LANG-001`、`TASK-D1-*`、`TST-SRC-*`；验收为语法 golden、fuzz、跨模块
loader 和 environment rollback tests。
