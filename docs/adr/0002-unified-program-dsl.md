---
id: ADR-0002
title: 统一使用 program where DSL
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# ADR-0002：统一使用 `program ... where` DSL

- 状态：`proposed`
- 日期：2026-07-15

## 背景

业务作者需要只学习一套语言。以“合约、电路、guest”命名多个入口会让业务逻辑过早绑定执行平台。

## 决定

唯一顶层入口为：

```lean
program Name where
  ...
```

锁定的 Lean grammar initializer 只负责产生 `Syntax`。两条入口必须共用唯一的 bounded checked
decoder/declaration validation 和 `Source.Program`；该值随后进入唯一的 contained
name/type/effect/semantic core pipeline：

- CLI orchestration parent 不解析或 elaboration 用户 module；它在 frontend worker 中加载
  grammar、解析、preflight、decode 和 declaration validation，再把 `Source.Program` 交给 core
  worker。两个 worker 都使用 SPEC-COMMON-001 hard maxima，并由 parent 把 controller event 或
  protocol failure 转换为稳定诊断。
- Lean custom command elaborator 只可调用同一 checked decoder，并 quote 已验证的
  `Source.Program`；不得从 raw `Syntax` 构造第二套 AST 或实现第二套业务检查逻辑。需要完整
  compile/check 时仍调用同一 core pipeline，command elaboration 不能成为替代 checker。

两路以 AST/source hash/diagnostic 等价测试防止漂移。除明确 proof reference 位置外，不接受任意
Lean term escape；proof reference 也只能解析为受约束身份，不执行任意 host computation。

## 后果

所有目标共享 source semantics；平台差异通过 requirements、extensions 和 materializer 表达。语言实现成本高于简单宏，但诊断、终止性与安全边界可控。

## 否决方案

- 多套 `contract/circuit/guest` DSL：业务模型分裂。
- 普通 Lean builder/StateM：允许任意 host computation，难以静态抽取完整语义。

## 验证

parser/elaborator 正负例、双入口 AST/diagnostic 等价、worker time/memory/process/output 边界、
source span、跨模块导出、重复名称和任意 Lean escape tests。
