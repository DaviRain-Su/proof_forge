---
id: RESEARCH-V1-V2-FRONTEND
title: V1 与 V2 前端及 IR 对照
status: draft
owner: architecture
updated: 2026-07-15
normative: false
---

# V1 与 V2 前端及 IR 对照

本文记录 2026-07-15 的代码审查结论，不把父项目作为 V2 依赖或运行时 fallback。

## 结论

Lean 4 的 parser 确实应当负责词法、缩进和 syntax tree；V2 不需要手写逐行文本 parser。
但 Lean `Syntax` 只说明“源码长什么样”，不能替代 ProofForge 的名称解析、类型信息、
目标中立业务语义和 target-owned Plan/IR。因此 V2 的边界是：

```text
Lean Parser Syntax
→ ProofForge syntax decoder
→ Source.Program
→ Typed.Program
→ Semantic.Program
→ resolve(--target)
→ target Plan
→ target IR
→ artifact
```

`--target` 从 resolver/materializer 才进入；它不能改变前三层的业务语义，也不要求作者在
源码写 `kind`。

## V1 实际结构

V1 的 `contract_source` 本身也是 Lean custom command grammar，而不是普通文本 parser：
`ProofForge/Contract/Source.lean` 定义 syntax categories 和 command elaboration，并展开出
`ContractSpec`/旧 `IR.Module` 常量。`ProofForge/Cli/ContractLoader.lean` 使用 Lean frontend
加载模块，再通过环境常量求值取得 payload；`Contract/Builder.lean` 用 builder 构造旧 IR。

问题不在“V1 没用 Lean AST”，而在同一项目逐步累积了 source macro、`ContractSpec`、旧
`IR.Module`、Authored/Surface、Canonical Core 和 target Plan 等重叠表示。兼容路径和多套
source-of-truth 让读者难以判断某一语义究竟由哪层拥有。

## V2 的明确分工

| 层 | 只负责 | 不负责 |
|---|---|---|
| Lean `Syntax` | token、layout、grammar tree | 类型、合约语义、target |
| `Source.Program` | DSL 领域 AST、源码名称、source identity | 名称解析、capability 宣称 |
| `Typed.Program` | resolved IDs、类型与当前 effect rules | target 支持判断、ABI/layout |
| `Semantic.Program` | canonical target-neutral operations、requirements、semantic hash | 链宿主细节 |
| target `Plan` | ABI、状态布局、账户/host/proof wiring、提交边界 | 重新解释源码 |
| target IR/emitter | 目标机器结构与确定编码 | 补猜 Plan 缺失语义 |

当前 CLI loader 只加载受信任的 ProofForge grammar initializer，调用 Lean Parser 后对白名单
command 解码；它拒绝 `run_cmd` 等任意 Lean command，不 elaboration 用户 module。直接由
Lean 编译源码时，command elaborator 和 CLI loader 使用同一 decoder，避免两套语法语义。

## 保留与舍弃

V2 保留 V1 已验证的方向：Lean custom syntax、显式领域 IR、target Plan 和严格拒绝。V2
舍弃的是表示重叠和兼容回退，不是舍弃 IR。新的 `Semantic.Program` 正是重新建立的
canonical IR；`Typed.Program` 则让“parser AST”和“业务语义 IR”之间的检查边界可见。
