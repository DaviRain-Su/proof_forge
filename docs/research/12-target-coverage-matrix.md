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
| stateLoad/stateStore（named 聚合） | LOWERED(N3) | FAIL-CLOSED | LOWERED(NearAggregate) | LOWERED(NoirAggregate) | FAIL-CLOSED | FAIL-CLOSED(scalar mapping) |
| stateLoad/stateStore（Array） | LOWERED(EvmIndex) | LOWERED(ArrayState) | LOWERED(NearAggregate) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| stateLoad/stateStore（Map） | LOWERED(EVM dense Map cap-8) | LOWERED(Solana dense Map cap-8) | LOWERED(NEAR dense Map cap-8) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| stateLoad/stateStore（Bytes） | LOWERED(D4-E2: N×UInt8 leaves) | FAIL-CLOSED | FAIL-CLOSED(NearAggregate) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| stateLoad/stateStore（Option） | FAIL-CLOSED（Normalize **admitted** N-A4；target container 永不 admit） | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| stateLoad/stateStore（String） | LOWERED(N4) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| stateLoad/stateStore（Field bn254） | LOWERED(N2b-EVM) | FAIL-CLOSED | FAIL-CLOSED | LOWERED(原生) | FAIL-CLOSED(非Goldilocks) | FAIL-CLOSED(非BLS12-377) |
| stateLoad/stateStore（Field BLS12-377） | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | **LOWERED(T14)** |
| stateLoad/stateStore（Field Goldilocks） | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | **LOWERED(T14)** | FAIL-CLOSED |
| construct（named Struct/Enum） | LOWERED(N3) | FAIL-CLOSED | LOWERED(NearAggregate) | LOWERED(NoirAggregate) | LOWERED | FAIL-CLOSED(struct deferred) |
| fieldGet/fieldSet | LOWERED(N3) | LOWERED | LOWERED(NearAggregate) | LOWERED(NoirAggregate) | LOWERED | FAIL-CLOSED |
| variantTag/variantPayload | LOWERED(N3) | LOWERED | LOWERED(NearAggregate) | LOWERED(NoirAggregate) | LOWERED | FAIL-CLOSED |
| indexGet/indexSet（Array） | LOWERED(EvmIndex) | LOWERED(ArrayState) | LOWERED(NearAggregate) | FAIL-CLOSED | LOWERED | FAIL-CLOSED |
| indexGet/indexSet（Map） | LOWERED(EVM Map+Option) | LOWERED(Solana Map+Option) | LOWERED(NEAR Map+Option) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| indexGet/indexSet（Bytes） | LOWERED(D4-E2) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| fieldAdd/Sub/Mul/Div/Neg（Field） | LOWERED(N2b-EVM bn254) | FAIL-CLOSED | FAIL-CLOSED | LOWERED(原生 bn254) | **LOWERED(T14 Goldilocks)** | **LOWERED(T14 BLS12-377)** |
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
| **Principal state/params** | LOWERED(T10: leaf storage; ≠address) | LOWERED(T12: 9×u64 leaves; ≠32B pubkey) | LOWERED(T12: 9×KV leaves; ≠account-id) | LOWERED(T12: 9×u64 inputs; ≠Field) | FAIL-CLOSED | FAIL-CLOSED |
| **UInt128 state/param/body** | LOWERED(T9b 原生 word) | LOWERED(T9e 2×u64 multiword) | LOWERED(T9e 2×i64 multiword) | LOWERED(T11 原生 u128 / multi-limb analogue；mul/div/mod FC；UInt256 FC) | FAIL-CLOSED | FAIL-CLOSED |
| **UInt256 state/param/body** | LOWERED(T9b) | LOWERED(T9e 4×u64) | LOWERED(T9e 4×i64) | FAIL-CLOSED(T11) | FAIL-CLOSED | FAIL-CLOSED |

## 2. 验收/差分覆盖矩阵

| 验收门 | EVM | Solana | NEAR | Noir | Psy | Aleo |
|---|---|---|---|---|---|---|
| Plan canonicity (ValidatePlan) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| IR 结构验证 (ValidateIR) | ✅(M4) | N/A | N/A | N/A | N/A | N/A |
| 真实工具链编译验收 | ✅(EvmSolc: solc) | ✅(Mollusk runtime) | ✅(NearWasmAcceptance: wat2wasm+wasm-interp) | ❌(source-only) | ❌(source-only) | ✅(AleoAcceptance: leo 4.0.2 build; 缺席 skip；非 Tool Lock pin) |
| 运行时差分 (Reference↔target) | ❌(Anvil formal 缺) | ✅(S3b Mollusk) | ⚠️(WABT load+dummy env; 非 sandbox receipt / 非 Reference↔Wasm) | ❌ | ❌ | ❌ |

## 3. 工程轨道未实现 feature 全清单（A/B/C/D 组）

> 与项目全面审查报告对齐。每个缺口带 ID、现状、wave 归属。
> 闭合 = GAP→LOWERED 或 GAP→FAIL-CLOSED（显式拒绝 + 测试）。

### A 组：Normalize/语义面剩余缺口（跨 target 通用，最高优先）

这些缺口在 sole Normalize 层，影响所有 target；N 家族共享 NormalizeV1/ReferenceV1/EnvelopeV1，**必须串行**（一个 wave 一个）。

| ID | 缺口 | 现状 | 影响范围 | wave 归属 |
|---|---|---|---|---|
| **N-A1** | EVM String match-switch | **已闭合(EvmStringMatch)**：EVM Lower 将 `match String` desugar 为 leaf-wise eq + nested ifThenElse（Plan `switchOn` 仍仅 UInt64 case）；catch-all fallthrough；非 String aggregate switch 与非 String pattern 仍 fail-closed | EVM | EvmStringMatch ✅ |
| **N-A2** | 多臂同构造器 match 细化 | **已闭合(MultiArmCtor)**：Normalize 允许同外构造器多臂，子模式可区分时 first-match 嵌套 guard（nested ctor→VariantTag eq，nested lit→value eq；fallthrough→outer catch-all 或 trap.unreachable）；结构 pattern key 重复（bind≡wildcard、ctor by vIdx、lit by valueBytes）仍 fail-closed；TypeCheck 同源 duplicate pattern 诊断；四 target 经 sole Normalize 继承 | 全 target | MultiArmCtor ✅ |
| **N-A3** | Map/Bytes 穿透元素赋值 | **已闭合(MapBytesAssign)**：Map/Bytes **state 已由 ArrayState 开放**（默认 empty Map / zero Bytes）；TypeCheck 开 Bytes 下标 rvalue→UInt8，assign 目标 Map 下标→value（非 Option）、Bytes→UInt8；Normalize 单步 `m[k]:=v`/`b[i]:=u8` → IndexSet（load→set→store）；Reference 既有 Map/Bytes IndexSet 步进 + **Bytes state 产品 Normalize→step**；Map state 整程序 Reference admission 仍因 maxMapEntries 资源模型 fail-closed（手建无-state Map IndexSet 迹保留）；**嵌套穿透** `m[k].x:=v` 仍 fail-closed（Option 中间值）；**target Plan** Map/Bytes 保持 Envelope admitMap/admitBytes=false（B-1d/e） | 全 target（Normalize）；Reference Bytes state；Plan 仍 FAIL-CLOSED | MapBytesAssign ✅ |
| **N-A4** | Option state | **闭合**：Normalize+Reference default none；全 target Plan **FAIL-CLOSED**+测 | 全 target | OptionState ✅ |

### B 组：各 target 的 Plan/IR/emitter 覆盖缺口

#### B-1：跨 target 聚合/容器覆盖不均（最高优先，可并行——按 target 文件分隔）

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **B-1a** | NEAR named 聚合 + Array/容器 | **闭合(NearAggregate)**：named Struct/Enum + Array UInt flatten-to-KV；Map/Bytes FAIL-CLOSED | NearAggregate ✅ |
| **B-1b** | Noir named 聚合 | **闭合(NoirAggregate)**：named Struct/Enum construct/fieldGet/fieldSet/variantTag/variantPayload + named-aggregate stateLoad/store 经 leaf 扁平化 public inputs（circuit-native 字段约束）；Array/Map/Bytes/Option 容器 state 与 IndexGet/Set 显式 FAIL-CLOSED | NoirAggregate |
| **B-1c** | Aleo 全功能 | **AleoCoverage 已闭合（2026-08-01）**：核对代码后修正矩阵——LOWERED 为标量 UInt64 envelope（state/arith/compare/bitwise/shift/logical/pureCall/if/match/for/bare assert/bare revert）+ Commit 身份透传；**Field FAIL-CLOSED**（Aleo native field = BLS12-377 Fr ≠ catalog bn254 Fr，PsyFelt 式研究钉）；named 聚合/construct/field*/variant*/Array/Map/Bytes/Option/ContextRead/emit/externalCall/schedule 均显式 FAIL-CLOSED（不再 GAP）；Leo native struct/record 布局切片另排 | AleoCoverage ✅ |
| **B-1d** | Solana Map/Bytes/Option state | Solana 有 Array(UInt64) 正例，Map/Bytes/Option state FAIL-CLOSED（可保持或开放） | 后续 wave |
| **B-1e** | EVM Map/Bytes/Option state | EVM 有 Array+Field+String 正例，Map/Bytes/Option state FAIL-CLOSED（可保持或开放） | 后续 wave |

#### B-2：Normalize 语义细化（= A 组，N 家族串行）

见 A 组 N-A1/N-A2/N-A3/N-A4。

#### B-3：call/schedule 的 address-bearing 类型

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **B-3** | Principal→address 映射 | **已闭合为 FAIL-CLOSED 研究钉（PrincipalAddr, 2026-08-02）** + **AddressBearing followup 已闭合（static-callee open, 2026-08-02）** + **T10 EVM Principal storage pilot（2026-08-02）** + **T12 Solana/NEAR/Noir Principal storage pilot（2026-08-02）**。Principal valueBytes = `u32le(len)\|body`（`1≤len≤4096`）≠ EVM 20B / Solana 32B pubkey，**无** approximate Principal→address 映射。T10/T12 在 EVM/Solana/NEAR/Noir 开放 **wire identity 原样 leaf 存储**（`pilotPrincipalPolicyAdmit`；len+8×UInt64，≤64B body，与 N4 String 同构；非 20B address / 32B pubkey / account-id / Field）；Aleo/Psy 保持 `pilotPrincipalPolicyNone`。产品 `call`/`schedule` 为 wire `Op.ExternalCall`/`Schedule` 的 **static `QualifiedName` callee**（非 ValueId 地址）。AddressBearing 打开 EVM/Solana 双 call 键：EVM Plan `externalCall`/`schedule` → Yul `CALL` 至 `keccak256(targetPath)` 后 20 字节 + method selector；Solana Plan/IR `externalCall`/`schedule` → program id = SHA-256(targetPath) 32B，plan 文本 `external_call`/`schedule`，SBPF 以 `sol_log_data` 观测桩（完整 `invoke_signed` CPI 需 account metas，另排）。NEAR 仍拒 sync；Noir 七键不变 | PrincipalAddr ✅ + AddressBearing ✅ + T10/T12 storage ✅ |

#### B-4：验收门升级（= C 组）

见 C 组。

### C 组：工程验证缺口（验收门升级）

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **C-1** | NEAR Wasm 运行时差分 | **已闭合(NearWasmAcceptance 工程切片)**：产品 path 物化 Counter/DualField（多字段 public UInt64 KV；named Struct 仍 NEAR Plan FC）/LoopSum → `.wat` → 主机 `wat2wasm` + `wasm-interp --dummy-import-func`（或 wasmtime compile / wasmer validate）实例化；工具缺席干净 skip；**非** NEAR sandbox receipt / Reference↔Wasm formal 差分 | NearWasmAcceptance ✅ |
| **C-2** | Aleo/Psy compiler/VM 验收研究 | **研究闭合（2026-08-02，RPT-015）** + **J2 AleoEmissionFix（2026-08-02）**：`leo 4.0.2` 主机可用时 `AleoAcceptance` 对产品 `.aleo` 做 `leo build --offline` 验收（缺席 skip；**无** Tool Lock pin / 非 prove-deploy）；EmitIRV1 已对齐 Leo 4 语法（`bool`、`return final {…};`、shift `as u8`、pureFn 文件级 helper、闭合 constructor）。Psy 仍无 VM 门。Aleo Field≠bn254 仍 FAIL-CLOSED。成熟度：**source package + optional host leo compile**，**非** hermetic/runtime | AleoPsyResearch ✅ / AleoEmissionFix |
| **C-3** | EVM Reference↔Anvil formal differential | EVM 有 solc 验收 + 历史 Anvil Counter，formal Reference↔Anvil closure 仍缺 | EvmAnvilDiff（formal 轨道，按既定决定不做） |
| **C-4** | Noir prove/verify 验收门 | **已闭合研究（2026-08-02，RPT-016）**：**不**升格。无 nargo/backend Tool Lock pin；host 无 nargo；`validate_artifacts` 故意拒绝 proof-stage 叶子；成熟度保持 **source-only** relations + Lean relation model。跟进需独立 `NoirProveAcceptance` + pin | NoirProveResearch ✅ |
| **C-5** | Solana Mollusk fixture 跟 Normalize 新面 | **ongoing**：Counter + LoopSum/MathOps/FnCall/Events/MultiField/MatchOps/NarrowGates 已在；N 系列 Map/Option/Context 等 Solana Plan 多为 FAIL-CLOSED，不发明 fake runtime 面 | MolluskFixtures |

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
- **PrincipalAddr**（B-3）：**已闭合为 FAIL-CLOSED 研究钉** — wire Principal ≠ EVM/Solana 固定地址；见 §B-3
- **AddressBearing**（B-3 followup）：**已闭合（static-callee open）** — research 确认 callee 为 static QN 非 dynamic address；EVM/Solana resolver 七键 + Plan/IR/emitter 打开；Principal→address 仍 fail closed
- **T10 EVM Principal storage**：**已闭合** — EVM `pilotPrincipalPolicyAdmit` + N4-isomorphic leaf storage（len+8×UInt64）；params/state/eq/ne；非 address；多宽 return 仍 fail closed
- **T12 NEAR/Solana/Noir Principal storage**：**已闭合** — 三 target `pilotPrincipalPolicyAdmit` + 同构 9-leaf layout（Solana account pitch / NEAR 9×KV / Noir 9×u64 inputs）；params/state/eq/ne；非 pubkey/account-id/Field；多宽 return 仍 fail closed；Aleo/Psy 仍 fail closed
- **NearWasmAcceptance**（C-1）：**已闭合** — `Tests/Materialization/NearWasmAcceptance.lean` + `scripts/near_wasm_acceptance.sh`；WABT wat2wasm+wasm-interp dummy-import 门
- **AleoPsyResearch**（C-2）：**已闭合** — `docs/research/15-aleo-psy-compiler-vm.md`（不升格门）
- **NoirProveResearch**（C-4）：**已闭合** — `docs/research/16-noir-prove-path.md`（不升格 prove/verify）
- **MolluskFixtures**（C-5）：ongoing fixture growth under `runtime-tests/solana`

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