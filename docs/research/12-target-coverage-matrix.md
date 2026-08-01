---
id: RESEARCH-012
title: Target Plan/IR/Emitter 覆盖缺口矩阵（工程轨道权威清单）
status: draft
owner: engineering
updated: 2026-08-01
normative: false
---

# Target Plan/IR/Emitter 覆盖缺口矩阵

> **目的**：工程轨道"未实现 feature"的单一事实源。每个 wave 闭合哪些格子在此可查；
> wave 完成后由该 worker 简报的"已 lower op 列表"验证，矩阵随之更新。
> 非 formal：D2–D4 formal task 不在此矩阵（走 release-qualification 轨道）。

## 矩阵说明

- **LOWERED** = 产品路径已下降该 op/feature 并有测试覆盖
- **FAIL-CLOSED** = 显式拒绝（planInvariant/failUnsupported），文档化边界
- **GAP** = 未实现且未显式拒绝（应闭合：要么 LOWER，要么显式 FAIL-CLOSED + 测试）
- 空白 = 不适用该 target（family 边界）

数据来源：产品测试（EvmSmoke/Mollusk/NoirRelationModel 等）+ LowerSemanticV1 代码扫描。
**初版可能不精确**——每个 wave worker 须核对并修正自己 target 行的真实边界。

## 1. 语义 op 覆盖矩阵（wire Op × target）

| wire Op / feature | EVM | Solana | NEAR | Noir | Psy | Aleo |
|---|---|---|---|---|---|---|
| stateLoad/stateStore（标量） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| stateLoad/stateStore（named 聚合） | LOWERED(N3) | FAIL-CLOSED | GAP | GAP | FAIL-CLOSED | GAP |
| stateLoad/stateStore（Array） | LOWERED(EvmIndex) | LOWERED(ArrayState) | GAP | GAP | FAIL-CLOSED | GAP |
| stateLoad/stateStore（Map） | FAIL-CLOSED | FAIL-CLOSED | GAP | GAP | FAIL-CLOSED | GAP |
| stateLoad/stateStore（Bytes） | FAIL-CLOSED | FAIL-CLOSED | GAP | GAP | FAIL-CLOSED | GAP |
| stateLoad/stateStore（Option） | FAIL-CLOSED | FAIL-CLOSED | GAP | FAIL-CLOSED | FAIL-CLOSED | GAP |
| stateLoad/stateStore（String） | LOWERED(N4) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| stateLoad/stateStore（Field bn254） | LOWERED(N2b-EVM) | FAIL-CLOSED | FAIL-CLOSED | LOWERED(原生) | FAIL-CLOSED(Goldilocks证伪) | FAIL-CLOSED |
| construct（named Struct/Enum） | LOWERED(N3) | FAIL-CLOSED | GAP | GAP | LOWERED | GAP |
| fieldGet/fieldSet | LOWERED(N3) | LOWERED | GAP | GAP | LOWERED | GAP |
| variantTag/variantPayload | LOWERED(N3) | LOWERED | GAP | GAP | LOWERED | GAP |
| indexGet/indexSet（Array） | LOWERED(EvmIndex) | LOWERED(ArrayState) | GAP | GAP | LOWERED | GAP |
| indexGet/indexSet（Map） | FAIL-CLOSED | FAIL-CLOSED | GAP | GAP | FAIL-CLOSED | GAP |
| indexGet/indexSet（Bytes） | FAIL-CLOSED | FAIL-CLOSED | GAP | GAP | FAIL-CLOSED | GAP |
| fieldAdd/Sub/Mul/Div/Neg（Field） | LOWERED(N2b-EVM) | FAIL-CLOSED | FAIL-CLOSED | LOWERED(原生) | FAIL-CLOSED | FAIL-CLOSED |
| eq/ne（所有支持类型） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| ordering 比较 | LOWERED(UInt/Int) | LOWERED(UInt/Int) | LOWERED | LOWERED(UInt/Field) | LOWERED | LOWERED |
| unary（-/~/!） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| binary 算术（checked + - * / %） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| shift/bitwise/logical | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| pureCall（fn/localCall） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| emit / revert | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| assertOp | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| contextRead | FAIL-CLOSED(全target) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| commit | LOWERED(身份透传) | LOWERED | LOWERED | LOWERED | LOWERED | GAP |
| externalCall（sync call） | FAIL-CLOSED(需address) | FAIL-CLOSED(需address) | FAIL-CLOSED | LOWERED | FAIL-CLOSED | LOWERED |
| schedule（async） | FAIL-CLOSED(需address) | FAIL-CLOSED(需address) | LOWERED(promise) | LOWERED | FAIL-CLOSED | LOWERED |
| **match String scrutinee** | GAP(N-A1) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| **match 多臂同构造器** | GAP(N-A2) | GAP | GAP | GAP | GAP | GAP |
| **Principal state/params** | FAIL-CLOSED(全) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |

## 2. 验收/差分覆盖矩阵

| 验收门 | EVM | Solana | NEAR | Noir | Psy | Aleo |
|---|---|---|---|---|---|---|
| Plan canonicity (ValidatePlan) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| IR 结构验证 (ValidateIR) | ✅(M4) | N/A | N/A | N/A | N/A | N/A |
| 真实工具链编译验收 | ✅(EvmSolc: solc) | ✅(Mollusk runtime) | ❌(仅 wat2wasm 结构) | ❌(source-only) | ❌(source-only) | ❌(source-only) |
| 运行时差分 (Reference↔target) | ❌(Anvil formal 缺) | ✅(S3b Mollusk) | ❌ | ❌ | ❌ | ❌ |

## 3. 缺口分组（wave 规划依据）

### 组 1：跨 target 聚合/容器覆盖不均（最高优先）
- NEAR: named 聚合 / Array / 全部容器 GAP
- Noir: named 聚合 GAP（Field 已有）
- Aleo: named 聚合 / 全部容器 GAP
- Solana: Map/Bytes/Option state FAIL-CLOSED（可保持或开放）
- EVM: Map/Bytes/Option state FAIL-CLOSED（可保持或开放）

### 组 2：Normalize 语义细化
- N-A1 EVM String match-switch
- N-A2 多臂同构造器 match（全 target）
- N-A3 Map/Bytes 穿透元素赋值
- N-A4 Option state

### 组 3：call/schedule 的 address-bearing 类型
- Principal→address 映射可解锁 EVM/Solana externalCall/schedule
- 影响：cross-target call 全链

### 组 4：验收门升级
- NEAR Wasm 运行时差分
- Aleo/Psy compiler/VM 验收研究
- EVM Reference↔Anvil formal differential

## 4. 更新协议

- 每个 wave worker 须在简报里报告自己 target 行的真实边界（核对代码后修正本矩阵）
- wave 集成时由 integrator 把矩阵更新合入提交
- GAP → LOWERED 或 GAP → FAIL-CLOSED 都算闭合
- 新发现的 GAP 加到组里并排队 wave