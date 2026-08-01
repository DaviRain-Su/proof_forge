---
id: RESEARCH-012
title: Target Plan/IR/Emitter 覆盖缺口矩阵（工程轨道权威清单）
status: draft
owner: engineering
updated: 2026-08-01
normative: false
---

# Target Plan/IR/Emitter 覆盖缺口矩阵

> **目的**：工程轨道 op×target **格子**的事实源。每个 wave 闭合哪些格子在此可查；
> wave 完成后由 worker 简报的"已 lower op 列表"验证，矩阵随之更新。  
> **总执行队列**（优先级/并行规则）：[`../engineering-backlog.md`](../engineering-backlog.md)。  
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
| stateLoad/stateStore（named 聚合） | LOWERED(N3) | FAIL-CLOSED | GAP | LOWERED(NoirAggregate) | FAIL-CLOSED | FAIL-CLOSED(scalar mapping) |
| stateLoad/stateStore（Array） | LOWERED(EvmIndex) | LOWERED(ArrayState) | GAP | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| stateLoad/stateStore（Map） | FAIL-CLOSED | FAIL-CLOSED | GAP | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| stateLoad/stateStore（Bytes） | FAIL-CLOSED | FAIL-CLOSED | GAP | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| stateLoad/stateStore（Option） | FAIL-CLOSED | FAIL-CLOSED | GAP | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| stateLoad/stateStore（String） | LOWERED(N4) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| stateLoad/stateStore（Field bn254） | LOWERED(N2b-EVM) | FAIL-CLOSED | FAIL-CLOSED | LOWERED(原生) | FAIL-CLOSED(Goldilocks证伪) | FAIL-CLOSED(BLS12-377≠bn254) |
| construct（named Struct/Enum） | LOWERED(N3) | FAIL-CLOSED | GAP | LOWERED(NoirAggregate) | LOWERED | FAIL-CLOSED(struct deferred) |
| fieldGet/fieldSet | LOWERED(N3) | LOWERED | GAP | LOWERED(NoirAggregate) | LOWERED | FAIL-CLOSED |
| variantTag/variantPayload | LOWERED(N3) | LOWERED | GAP | LOWERED(NoirAggregate) | LOWERED | FAIL-CLOSED |
| indexGet/indexSet（Array） | LOWERED(EvmIndex) | LOWERED(ArrayState) | GAP | FAIL-CLOSED | LOWERED | FAIL-CLOSED |
| indexGet/indexSet（Map） | FAIL-CLOSED | FAIL-CLOSED | GAP | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| indexGet/indexSet（Bytes） | FAIL-CLOSED | FAIL-CLOSED | GAP | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| fieldAdd/Sub/Mul/Div/Neg（Field） | LOWERED(N2b-EVM) | FAIL-CLOSED | FAIL-CLOSED | LOWERED(原生) | FAIL-CLOSED | FAIL-CLOSED(BLS12-377) |
| eq/ne（所有支持类型） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| ordering 比较 | LOWERED(UInt/Int) | LOWERED(UInt/Int) | LOWERED | LOWERED(UInt/Field) | LOWERED | LOWERED |
| unary（-/~/!） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED(~/!;neg FC) |
| binary 算术（checked + - * / %） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| shift/bitwise/logical | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| pureCall（fn/localCall） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| emit / revert | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | FAIL-CLOSED emit; bare revert LOWERED |
| assertOp | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| contextRead | FAIL-CLOSED(全target) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| commit | LOWERED(身份透传) | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED(身份透传) |
| externalCall（sync call） | FAIL-CLOSED(需address) | FAIL-CLOSED(需address) | FAIL-CLOSED | LOWERED | FAIL-CLOSED | FAIL-CLOSED(resolver+plan) |
| schedule（async） | FAIL-CLOSED(需address) | FAIL-CLOSED(需address) | LOWERED(promise) | LOWERED | FAIL-CLOSED | FAIL-CLOSED(resolver+plan) |
| **match String scrutinee** | LOWERED(N-A1) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| **match 多臂同构造器** | LOWERED(N-A2) | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| **Principal state/params** | FAIL-CLOSED(全) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |

## 2. 验收/差分覆盖矩阵

| 验收门 | EVM | Solana | NEAR | Noir | Psy | Aleo |
|---|---|---|---|---|---|---|
| Plan canonicity (ValidatePlan) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| IR 结构验证 (ValidateIR) | ✅(M4) | N/A | N/A | N/A | N/A | N/A |
| 真实工具链编译验收 | ✅(EvmSolc: solc) | ✅(Mollusk runtime) | ❌(仅 wat2wasm 结构) | ❌(source-only) | ❌(source-only) | ❌(source-only) |
| 运行时差分 (Reference↔target) | ❌(Anvil formal 缺) | ✅(S3b Mollusk) | ❌ | ❌ | ❌ | ❌ |

## 3. 工程轨道未实现 feature 全清单（A/B/C/D 组）

> 与项目全面审查报告对齐。每个缺口带 ID、现状、wave 归属。
> 闭合 = GAP→LOWERED 或 GAP→FAIL-CLOSED（显式拒绝 + 测试）。

### A 组：Normalize/语义面剩余缺口（跨 target 通用，最高优先）

这些缺口在 sole Normalize 层，影响所有 target；N 家族共享 NormalizeV1/ReferenceV1/EnvelopeV1，**必须串行**（一个 wave 一个）。

| ID | 缺口 | 现状 | 影响范围 | wave 归属 |
|---|---|---|---|---|
| **N-A1** | EVM String match-switch | **已闭合(EvmStringMatch)**：EVM Lower 将 `match String` desugar 为 leaf-wise eq + nested ifThenElse（Plan `switchOn` 仍仅 UInt64 case）；catch-all fallthrough；非 String aggregate switch 与非 String pattern 仍 fail-closed | EVM | EvmStringMatch ✅ |
| **N-A2** | 多臂同构造器 match 细化 | **已闭合(MultiArmCtor)**：Normalize 允许同外构造器多臂，子模式可区分时 first-match 嵌套 guard（nested ctor→VariantTag eq，nested lit→value eq；fallthrough→outer catch-all 或 trap.unreachable）；结构 pattern key 重复（bind≡wildcard、ctor by vIdx、lit by valueBytes）仍 fail-closed；TypeCheck 同源 duplicate pattern 诊断；四 target 经 sole Normalize 继承 | 全 target | MultiArmCtor ✅ |
| **N-A3** | Map/Bytes 穿透元素赋值 | ArrayState 开 Array state + index 赋值（EVM/Solana 正例），Map/Bytes state 与穿透元素赋值仍 fail-closed | 全 target | MapBytesAssign |
| **N-A4** | Option state | ArrayState 明确"Option state: keep fail-closed" | 全 target | OptionState |

### B 组：各 target 的 Plan/IR/emitter 覆盖缺口

#### B-1：跨 target 聚合/容器覆盖不均（最高优先，可并行——按 target 文件分隔）

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **B-1a** | NEAR named 聚合 + Array/容器 | NEAR 只下降 7 op（stateStore/stateLoad/commit/contextRead/emit/revert/schedule），construct/fieldGet/fieldSet/variantTag/arrayIndexGet/fieldAdd(Field) 全 fail-closed | NearAggregate |
| **B-1b** | Noir named 聚合 | **闭合(NoirAggregate)**：named Struct/Enum construct/fieldGet/fieldSet/variantTag/variantPayload + named-aggregate stateLoad/store 经 leaf 扁平化 public inputs（circuit-native 字段约束）；Array/Map/Bytes/Option 容器 state 与 IndexGet/Set 显式 FAIL-CLOSED | NoirAggregate |
| **B-1c** | Aleo 全功能 | **AleoCoverage 已闭合（2026-08-01）**：核对代码后修正矩阵——LOWERED 为标量 UInt64 envelope（state/arith/compare/bitwise/shift/logical/pureCall/if/match/for/bare assert/bare revert）+ Commit 身份透传；**Field FAIL-CLOSED**（Aleo native field = BLS12-377 Fr ≠ catalog bn254 Fr，PsyFelt 式研究钉）；named 聚合/construct/field*/variant*/Array/Map/Bytes/Option/ContextRead/emit/externalCall/schedule 均显式 FAIL-CLOSED（不再 GAP）；Leo native struct/record 布局切片另排 | AleoCoverage ✅ |
| **B-1d** | Solana Map/Bytes/Option state | Solana 有 Array(UInt64) 正例，Map/Bytes/Option state FAIL-CLOSED（可保持或开放） | 后续 wave |
| **B-1e** | EVM Map/Bytes/Option state | EVM 有 Array+Field+String 正例，Map/Bytes/Option state FAIL-CLOSED（可保持或开放） | 后续 wave |

#### B-2：Normalize 语义细化（= A 组，N 家族串行）

见 A 组 N-A1/N-A2/N-A3/N-A4。

#### B-3：call/schedule 的 address-bearing 类型

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **B-3** | Principal→address 映射 | EVM/Solana 拒绝双键因无 address 类型；Principal 全 target Plan fail-closed；开放 Principal→address 可解锁 cross-target call | PrincipalAddr |

#### B-4：验收门升级（= C 组）

见 C 组。

### C 组：工程验证缺口（验收门升级）

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **C-1** | NEAR Wasm 运行时差分 | NEAR 成熟度 `wasm-validated-alpha`（wat2wasm 结构验证），无真实 Wasm 运行时差分（类比 EvmSolc/Mollusk） | NearWasmAcceptance |
| **C-2** | Aleo/Psy compiler/VM 验收研究 | Aleo/Psy 成熟度 `source-only`，无 compiler/VM 验收（Aleo 有 leo compiler？Psy 有 psy-vm？需研究） | AleoPsyResearch |
| **C-3** | EVM Reference↔Anvil formal differential | EVM 有 solc 验收 + 历史 Anvil Counter，formal Reference↔Anvil closure 仍缺 | EvmAnvilDiff（formal 轨道，按既定决定不做） |

### D 组：文档/checkpoint 同步缺口

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **D-1** | Phase 1 targets 表 | **已闭合（MatrixSync）**：AGENTS.md Phase 1 targets = 6 implemented（`evm`/`solana`/`near`/`noir`/`aleo`/`psy`）；Design-only = `cosmwasm`/`soroban`/`icp`/`openvm`；`MIGRATION_MATRIX` D3-02 seed 同步为 6+4 | MatrixSync |
| **D-2** | 成熟度声明 | **已闭合（MatrixSync）**：AGENTS 成熟度声明写明 EvmSolc 真实 solc 验收 + 历史 Anvil smoke；NEAR wat2wasm；Solana SBPF+Mollusk；Noir/Aleo/Psy source-only；coverage §2 验收矩阵与之一致 | MatrixSync |

## 4. Wave 队列（按优先级 + 可并行性）

### Phase D（当前批，4 波并行——B-1 + D，文件零重叠）
- **NearAggregate**（B-1a）：Near/**
- **NoirAggregate**（B-1b）：Noir/**
- **AleoCoverage**（B-1c）：Aleo/**
- **MatrixSync**（D-1/D-2）：docs only

### Phase E（A 组串行——N 家族共享 NormalizeV1/ReferenceV1/EnvelopeV1，必须一个一个）
- **EvmStringMatch**（N-A1）：**已闭合** — EVM LowerSemantic String match → leaf-wise eq + if chains + EvmSmoke pins
- **MultiArmCtor**（N-A2）：**已闭合** — NormalizeV1 + TypeCheckV1 multi-arm same-outer + 测试
- **MapBytesAssign**（N-A3）：NormalizeV1 + Reference + 每 target
- **OptionState**（N-A4）：NormalizeV1 + Reference + 每 target

### Phase F（B-3 + C 组，可并行）
- **PrincipalAddr**（B-3）：NormalizeV1 + EnvelopeV1 + EVM/Solana Plan（解锁 externalCall/schedule）
- **NearWasmAcceptance**（C-1）：Near runtime-tests + 脚本
- **AleoPsyResearch**（C-2）：docs/research 研究文档（Aleo leo compiler / Psy psy-vm 可用性）

### Phase G（formal 轨道，按既定决定不做，除非改决定）
- D2–D4 formal tasks（46 pending）——release qualification 流程

## 5. 更新协议

- 每个 wave worker 须在简报里报告自己 target 行/缺口的真实边界（核对代码后修正本矩阵）
- wave 集成时由 integrator 把矩阵更新合入提交
- GAP → LOWERED 或 GAP → FAIL-CLOSED 都算闭合
- 新发现的 GAP 加到对应组并排队 wave


- 每个 wave worker 须在简报里报告自己 target 行的真实边界（核对代码后修正本矩阵）
- wave 集成时由 integrator 把矩阵更新合入提交
- GAP → LOWERED 或 GAP → FAIL-CLOSED 都算闭合
- 新发现的 GAP 加到组里并排队 wave