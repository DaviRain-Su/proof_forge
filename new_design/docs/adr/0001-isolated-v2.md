---
id: ADR-0001
title: 建立完全独立的 V2 工程
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# ADR-0001：建立完全独立的 V2 工程

- 状态：`proposed`
- 日期：2026-07-15
- 决策者：Project owner

## 背景

既有项目的模块与兼容路径已经难以被项目所有者整体理解。V2 需要在可验证边界内重新建立模型，而不是继续叠加迁移层。

## 决定

`new_design/` 建立独立 Lake package `proof-forge-next`、命名空间 `ProofForgeV2`、可执行文件 `proof-forge-next`，拥有独立 `lean-toolchain`、manifest、justfile、dependency/toolchain lock 与 CI gates。

禁止 `require ..`、`import ProofForge.*`、父路径 symlink、父源码/fixture/script/build output、旧 binary 和失败 fallback。最终 archive gate 在空目录与隔离环境中验证。

## 后果

优点是架构和证据可独立推理；成本是不能直接继承父实现与测试通过状态。两个产品在 V2 达到发布标准前并存。

## 否决方案

- 在父 package 内继续大规模重构：无法满足独立性与认知重置目标。
- fork 后批量改名：仍会继承旧控制流与兼容假设。

## 验证

archive build/test、import/path/symlink/binary scans、manifest provenance 无父绝对路径。
