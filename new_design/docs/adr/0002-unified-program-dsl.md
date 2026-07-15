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

通过 Lean custom command elaborator 实现专用 grammar、类型/effect 检查、source span 和稳定导出。除明确 proof reference 位置外，不接受任意 Lean term escape。

## 后果

所有目标共享 source semantics；平台差异通过 requirements、extensions 和 materializer 表达。语言实现成本高于简单宏，但诊断、终止性与安全边界可控。

## 否决方案

- 多套 `contract/circuit/guest` DSL：业务模型分裂。
- 普通 Lean builder/StateM：允许任意 host computation，难以静态抽取完整语义。

## 验证

parser/elaborator 正负例、source span、跨模块导出、重复名称和任意 Lean escape tests。
