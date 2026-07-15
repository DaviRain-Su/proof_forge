---
id: RPT-001
title: 当前系统与 V2 起点审计
status: draft
owner: research
updated: 2026-07-15
normative: false
---

# 当前系统与 V2 起点审计

状态：`draft`
研究日期：2026-07-15

## 问题与范围

本报告回答两个问题：`new_design/` 的真实起点是什么；父 ProofForge 项目中哪些内容可以作为研究输入、哪些内容不得进入 V2。它不评判父项目代码质量，也不把父项目测试结果继承为 V2 证据。

## 方法

- 在 `new_design/` 执行只读文件枚举和 Git 状态检查。
- 在父仓库 commit `26d2a8dd33b76201eb7062e3a86fbf87641697cd` 枚举目标文档、CLI、IR、EVM、Wasm、Psy、Leo 等路径。
- 不导入、不执行、不复制父项目实现；观察记录归入 `SRC-LOCAL-001`。

## 原子结论

| Claim | 状态 | 结论 | 证据 |
|---|---|---|---|
| `CLM-CLEAN-001` | verified | 审计开始时 `new_design/` 没有已跟踪 V2 文件 | `SRC-LOCAL-001` |
| `CLM-SCOPE-001` | accepted | Phase 1 只实现 EVM、Solana、NEAR、Noir | 已批准计划 |
| `AUD-001` | verified | 父项目同时存在旧前端、共享/目标 IR、多个 CLI 路由和目标文档 | `SRC-LOCAL-001` 文件清单 |
| `AUD-002` | decision | 父项目行为不是 V2 规范，也不是 V2 测试 oracle | ADR-0012 |

## 冲突与解释

父项目能够提供平台需求、失败案例和测试场景，但直接迁移类型与控制流会把既有理解成本带入 V2。所谓“可参考实现”因此被严格解释为：可以记录某个文件在某个 commit 表达了什么问题，并把该问题重新写成独立规格和独立测试；不能复制结构后仅换名称。

`new_design/` 位于父 Git 工作树内不等于 V2 是父 Lake package 的子模块。V2 必须拥有自己的 toolchain、package manifest、入口、依赖锁和构建命令；最终通过复制到空目录的 archive gate 证明独立性。

## 结论

V2 采用 greenfield、spec-first、clean-room engineering。以下旧概念不得直接移植：旧 source macro/builder、`ContractSpec`、旧 `IR.Module/Core`、Canonical 类型、旧 Capability/HostOp、旧 registry/backend records、兼容 CLI mapper、旧 ArtifactBundle 和各旧 Plan。允许重用的是公开平台事实、通用编译理论、业务场景名称和独立重写后的测试期望。

## 限制

- 本审计只确认目录和文件级事实，没有对父项目每个模块做语义审查。
- 同项目内部的“clean-room”是工程隔离与认知降复杂度策略，不主张法律意义上的独立实现。
- 父仓库后续变化不会自动更新本报告；必须新增带 commit 的参考记录。

## 对设计的影响

- V2 命名空间固定为 `ProofForgeV2`，可执行文件固定为 `proof-forge-next`。
- V2 测试从语义规格生成；父项目 golden 只能成为待重新验证的候选场景。
- 所有目标实现先有 dossier、Plan schema 和独立运行时验证计划。

## 待办

- 代码阶段建立 parent-import、symlink、binary fallback 和 environment leakage 检查。
- 每次引用父实现时追加“commit + path + observation → V2 decision/test”的参考条目。
