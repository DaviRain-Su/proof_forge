---
id: ADR-0003
title: 由 target 选择物化且源码不声明执行类别
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# ADR-0003：由 target 选择物化，源码不声明执行类别

- 状态：`proposed`
- 日期：2026-07-15

## 背景

同一业务程序可能部署为链合约，也可能生成 state-transition circuit 或 zkVM workload。要求作者写顶层类别会人为制造互不兼容的 DSL。

## 决定

源码中不提供 `kind` 或等价字段。`--target` 只选择 materializer；前端根据业务操作推导 `ProgramRequirements`。target 仅在能够保持全部语义时接受程序，否则返回精确错误。

披露、授权和状态托管仍需在业务源码中显式描述，因为它们本身会改变语义；它们不是顶层执行类别。
默认程序不可升级。upgrade authority、proxy/controller 和 migration 只能来自显式、版本化
requirement/extension；target 不得自行增加管理员或升级路径。

## 后果

Counter 可同源编译到四个 Phase 1 target。并非每个 program 都保证支持每个 target；target extension 会缩小兼容集合。

## 否决方案

- 根据 target 改写 source semantics：结果不可比较。
- 自动丢弃 unsupported effects：制造错误成功。

## 验证

四目标 semantic hash 一致；unsupported requirement、semantics mismatch 和 nondeployable artifact 均 fail closed。
