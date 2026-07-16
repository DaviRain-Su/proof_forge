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
`Source.Program`，完整规格必须同时输出 source origins，并从同一次 immutable source snapshot 与
production NodeId assigner 构造 `SPEC-SEM-WIRE-001` 的 transient `SourceNodeInventoryV1`；失败返回
`PF-SRC/EXPORT-*`。
API：共享 syntax decoder、one-shot `parsePrograms`/`selectProgram(name?)`、可复用不可变
Lean parser environment 的 `ParserSession`，以及供 Lean 源码直接编译使用的 command
elaborator。它拥有 grammar、NodeId、span、SourceHash；
不做 target lookup、storage/ABI planning 或外部 I/O。

状态：规范 CLI 路径为 `parent bounded 16 MiB read → contained frontend worker → Lean parser →
per-program iterative Syntax preflight → whitelist/checked decode → Source.Program`；直接 Lean
编译路径为 `outer contained build runner → Lean parser → per-program iterative Syntax preflight →
shared decode validation → quote decoded Source.Program → registered constant`。
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
重复同一 byte-cap 检查。session 不保存用户 source、program、typed/core cache 或 target 状态；
因此复用它只能称为 same-session warm full recheck，不能称为 incremental compilation。

`proof-forge.resource.frontend.v1` 在 source open 前由 parent/outer runner 按
[`SPEC-COMMON-001`](../specs/common-types.md) 强制 wall、aggregate memory、single-process、protocol
和 stderr hard maxima；
Syntax/node/nesting budget 在 parser 成功后、递归 decoder 前验证。当前 alpha 的 in-process
CLI loader 与普通 direct Lean invocation 尚未实现这层 containment，因此只能产生 development
evidence，不能作为规范 acceptance 或 formal evidence。后置：payload schema v1、所有引用 span
有效、hash canonical。
边界：零/多 program、重复名/import diamond、NFC、非法 UTF-8、deep Syntax、proof ref 语法、
attribute schema mismatch、路径变化、error recovery、并行 module build。安全：不执行任意
term/macro callback、无文件/网络访问。直接构造 `Source.Program` 的 API 不经过本模块。

frontend 对 proof reference 只验证语法、qualified theorem name 形状、invariant name 的 source
唯一性并保留 origin；它不加载 theorem、不构造 expected theorem type，也不执行完整 callable/
invariant type check。`ParserSession`、one-shot parser 与 command elaborator 都不得接受 proof-bundle
path、读取 `.olean`、扩展 import/search path 或查询 ambient Environment 中的同名 declaration。
这样 D1 parser 测试不依赖 proof toolchain，恶意 source 也不能借 `using` 触发 host code/import。

compiler-core 先完成 type/effect/bound/disclosure、normalization、`SemanticProgramV1` validation 与
canonical hash，并用该 trusted inventory 全量验证 `SemanticProvenanceV1` 的 path/span/NodeId
membership；inventory 不持久化、不得从 `.pfprov` 反序列化。只有 closed program/provenance 成功后，才把 frontend 保存的
`(invariantName,theoremQualifiedName,origin)`、selected program 的 sourceHash 与 CLI 的
digest-pinned `ProofBundleV1` 交给
SPEC-SEM-001 的 fresh contained proof loader。loader 产生 bounded certification record 或稳定失败，
不把 Lean Environment/constant value 返回 frontend，不回写 parser session，也不得改变已计算的
Source/Typed/Semantic value/hash。bundle validation 失败时 compiler 丢弃后续 target/output staging；
不存在 frontend、当前 source module、父 `.lake` 或 `LEAN_PATH` fallback。

`decodeProgramCommandChecked` 同时拥有当前 alpha declaration validation；其返回值是两条生产
路径唯一的业务 AST。Loader 不得重复验证 program 内 declarations，command elaborator 不得从
raw `Syntax` 重新构造第二份 AST，只能穷举 quote 已 decode 的 `Source.Program`。双入口对当前
全部 constructor 的 `Source.Program` 与 `sourceHash` 必须相等；zero-callable、duplicate
state/entry/initializer parameter/entry parameter 必须返回相同 code/message 且不注册常量或发布
CLI output。

关联 `SPEC-LANG-001`、`SPEC-SOURCE-WIRE-001`、`SPEC-SEM-WIRE-001`、`TASK-D1-*`、`TST-SRC-*`；验收为语法 golden、fuzz、跨模块
loader 和 environment rollback tests。
