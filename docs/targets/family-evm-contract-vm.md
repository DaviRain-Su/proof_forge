---
id: FAMILY-EVM
title: EVM Contract VM family view
status: draft
owner: research
updated: 2026-07-15
normative: false
---

# Family View：EVM Contract VM

状态：`draft`

该视图描述 EVM 型合约执行：账户代码与持久 storage、同步嵌套 message call、交易级状态迁移、gas 与 revert。当前只登记 `evm` target。

共享候选包括 EVM opcode/bytecode encoder、ABI primitives 和 execution profile。会影响生成物或
可观察执行结果的 fork、precompile 与 gas schedule 属于 target semantics，并由
`CodegenProfile` exact 引用和实现、不得覆盖；
`NetworkProfile` 只拥有 chain/genesis identity、endpoint、fee、签名和部署限制，并声明其兼容的
exact target/codegen 组合。即使另一个平台接受 Wasm 或 EVM-compatible bytecode，也只有在上述
语义轴匹配时才可复用 materializer。

本视图不是源码类别。`program` 只有在其 requirements 能由具体 EVM profile 保持时才能解析为 `ResolvedProgram .evm`。
