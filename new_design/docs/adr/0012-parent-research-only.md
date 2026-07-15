---
id: ADR-0012
title: 父项目仅作为研究资料
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# ADR-0012：父项目仅作为研究资料

- 状态：`proposed`
- 日期：2026-07-15

## 背景

V2 可以从父项目的目标研究和失败经验获益，但直接依赖或把父行为当 oracle 会重新引入旧架构。

## 决定

允许格式为：`commit + path + observation → V2 requirement/decision → V2-owned test`。禁止复制旧类型/控制流、父 import/package、fixture/script/build output/binary、symlink、cache 和 fallback。父测试结果不计入 V2 evidence。

## 后果

需求知识可保留，实现与证据必须重建。研究记录增加少量维护成本。

## 否决方案

- 直接移植后逐步清理：无法证明何时真正独立。
- 完全不看父项目：会重复已知平台调研与失败。

## 验证

reference ledger review、forbidden symbol/import/path scan、隔离 archive build/test。
