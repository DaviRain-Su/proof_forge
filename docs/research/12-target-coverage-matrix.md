---
id: RESEARCH-012
title: Target Plan/IR/Emitter 覆盖缺口矩阵（工程轨道权威清单）
status: draft
owner: engineering
updated: 2026-08-03
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

> **CosmWasm A0 边界（2026-08-03）**：engineering registry/descriptor/resolver/CLI 已把
> `cosmwasm` 标为 implemented，但尚无 `Targets/CosmWasm*` Plan/IR/emitter/finalizer，且
> `Registry.materializeResult` 无 `.cosmwasm` dispatch。因此下列 op×target 与验收表只列六个
> **现有 materializer**；CosmWasm 的全部 materialization/acceptance 格子均为 **GAP（CW-A1）**，
> 不能按 CLI 的 `wasm-validated-alpha` label 记为 LOWERED 或已验证，也不能写成 target Plan
> FAIL-CLOSED（目前是在 registry dispatch 前以 `PF-TARGET-NOT-IMPLEMENTED` 拒绝）。

## 1. 语义 op 覆盖矩阵（wire Op × target）

| wire Op / feature | EVM | Solana | NEAR | Noir | Psy | Aleo |
|---|---|---|---|---|---|---|
| stateLoad/stateStore（标量） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| stateLoad/stateStore（named 聚合） | LOWERED(N3) | LOWERED(L2) | LOWERED(L1) | LOWERED(NoirAggregate) | LOWERED(H3) | LOWERED(H3) |
| stateLoad/stateStore（Array） | LOWERED(EvmIndex) | LOWERED(ArrayState) | LOWERED(NearAggregate) | LOWERED(NoirContainer) | LOWERED | LOWERED(H3 flatten) |
| stateLoad/stateStore（Map） | LOWERED(cap-8; atomic store) | LOWERED(cap-8; aggregate CSE→storeStateMulti；ELF+Mollusk 4/4) | LOWERED(cap-8; atomic KV store) | LOWERED(cap-8; atomic multi-leaf PI) | FAIL-CLOSED | LOWERED(cap-2; atomic mapping store) |
| stateLoad/stateStore（Bytes） | LOWERED(D4-E2: N×UInt8 leaves) | LOWERED(L2: N×UInt8 leaves) | LOWERED(N×UInt8 KV leaves) | LOWERED(L3: N×UInt8 leaves) | FAIL-CLOSED | LOWERED(Bytes N: N×u8 mappings) |
| stateLoad/stateStore（Option） | FAIL-CLOSED（Normalize **admitted** N-A4；target container 永不 admit） | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| stateLoad/stateStore（String） | LOWERED(N4) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| stateLoad/stateStore（Field bn254） | LOWERED(N2b-EVM) | FAIL-CLOSED | FAIL-CLOSED | LOWERED(原生) | FAIL-CLOSED(非Goldilocks) | FAIL-CLOSED(非BLS12-377) |
| stateLoad/stateStore（Field BLS12-377） | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | **LOWERED(T14)** |
| stateLoad/stateStore（Field Goldilocks） | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | **LOWERED(T14)** | FAIL-CLOSED |
| construct（named Struct/Enum） | LOWERED(N3) | LOWERED(L2) | LOWERED(L1) | LOWERED(NoirAggregate) | LOWERED(H3) | LOWERED(H3) |
| fieldGet/fieldSet | LOWERED(N3) | LOWERED(L2) | LOWERED(L1) | LOWERED(NoirAggregate) | LOWERED(H3) | LOWERED(H3) |
| variantTag/variantPayload | LOWERED(N3) | LOWERED | LOWERED(NearAggregate) | LOWERED(NoirAggregate) | LOWERED | LOWERED(H3) |
| indexGet/indexSet（Array） | LOWERED(EvmIndex) | LOWERED(ArrayState) | LOWERED(NearAggregate) | LOWERED(NoirContainer) | LOWERED | LOWERED(H3 flatten) |
| indexGet/indexSet（Map） | LOWERED(Map+Option) | LOWERED(Map+Option) | LOWERED(Map+Option) | LOWERED(Map+Option) | FAIL-CLOSED | LOWERED(dense Map cap-2) |
| indexGet/indexSet（Bytes） | LOWERED(D4-E2) | LOWERED(L2: literal index) | FAIL-CLOSED | LOWERED(L3: compile-time literal index、UInt8 leaf；动态索引 FC) | FAIL-CLOSED | FAIL-CLOSED |
| fieldAdd/Sub/Mul/Div/Neg（Field） | LOWERED(N2b-EVM bn254) | FAIL-CLOSED | FAIL-CLOSED | LOWERED(原生 bn254) | **LOWERED(T14 Goldilocks)** | **LOWERED(T14 BLS12-377)** |
| eq/ne（所有支持类型） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| ordering 比较 | LOWERED(UInt/Int) | LOWERED(UInt/Int) | LOWERED | LOWERED(UInt/Field) | LOWERED | LOWERED |
| unary（-/~/!） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED(UInt64 `~`→checkedBitNot，x<2^32−1 运行时 trap；Int64 `~` FC；UInt32 `~` XOR mask) | LOWERED(~/!;neg FC) |
| binary 算术（checked + - * / %） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| shift/bitwise/logical | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| pureCall（fn/localCall） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| emit / revert | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | FAIL-CLOSED emit; bare revert LOWERED |
| assertOp | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| contextRead | FAIL-CLOSED(全target) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| commit | LOWERED(身份透传) | LOWERED(身份透传) | LOWERED(身份透传) | FAIL-CLOSED | FAIL-CLOSED | LOWERED(身份透传) |
| externalCall（sync call） | LOWERED(static QN→CALL；语义 PARTIAL) | LOWERED(static QN；SBPF 仅 log stub，非 CPI) | FAIL-CLOSED | LOWERED(relation slots；语义 PARTIAL) | LOWERED(`__invoke_sync` source；语义 PARTIAL) | FAIL-CLOSED(resolver+plan) |
| schedule（async） | LOWERED(static QN→同步 CALL+忽略结果；语义 stub) | LOWERED(static QN；SBPF 仅 log stub) | LOWERED(promise；fire-and-forget) | LOWERED(relation slots；语义 PARTIAL) | FAIL-CLOSED | FAIL-CLOSED(resolver+plan) |
| **match String scrutinee** | LOWERED(N-A1) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| **named aggregate entry/view return（B-RET-ABI）** | LOWERED(≤8 UInt64/Int64 叶 tuple ABI) | FAIL-CLOSED | FAIL-CLOSED | LOWERED(per-leaf verifier inputs) | FAIL-CLOSED | FAIL-CLOSED |
| **anonymous Array/Map/Option/Bytes result（N-ANON-RESULT）** | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| **match 多臂同构造器** | LOWERED(N-A2) | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| **Principal state/params** | LOWERED(T10: leaf storage; ≠address) | LOWERED(T12: 9×u64 leaves; ≠32B pubkey) | LOWERED(T12: 9×KV leaves; ≠account-id) | LOWERED(T12: 9×u64 inputs; ≠Field) | FAIL-CLOSED | FAIL-CLOSED |
| **UInt128 state/param/body** | LOWERED(T9b 原生 word) | LOWERED(T9e 2×u64 multiword；**mul 真 schoolbook B-SOL-MUL**；div/mod low64 FC) | LOWERED(T9e 2×i64 multiword；**mul 真 schoolbook NEAR lane**；div/mod/shift FC) | LOWERED(T11 原生 u128 / multi-limb analogue；mul/div/mod FC；UInt256 FC) | FAIL-CLOSED | FAIL-CLOSED |
| **UInt256 state/param/body** | LOWERED(T9b) | LOWERED(T9e 4×u64；**mul 真 schoolbook B-SOL-MUL**；div/mod low64 FC) | LOWERED(T9e 4×i64；**mul 真 schoolbook NEAR lane**；div/mod/shift FC) | LOWERED(T13；add/sub/cmp/bit；mul/div/mod FC) | FAIL-CLOSED | FAIL-CLOSED |

## 2. 验收/差分覆盖矩阵

| 验收门 | EVM | Solana | NEAR | Noir | Psy | Aleo |
|---|---|---|---|---|---|---|
| Plan canonicity (ValidatePlan) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| IR 结构验证 (ValidateIR) | ✅(M4) | N/A | N/A | N/A | N/A | N/A |
| 真实工具链编译验收 | ✅(EvmSolc: solc) | ✅(Mollusk runtime) | ✅(NearWasmAcceptance: locked wat2wasm + host-optional wasm-interp/wasmtime/wasmer load) | ✅(NoirCompileAcceptance: nargo 1.0.0-beta.26 compile-only；G123；缺席 skip；**非** prove/verify) | ❌(source-only) | ✅(AleoAcceptance: leo 4.0.2 Tool Lock pin（G123）；缺席 skip；非 prove/deploy) |
| 运行时差分 (Reference↔target) | ⚠️(G4 工程 Anvil 差分：Counter/Accumulator/ArithOps/EventFlow overflow state-hold + emit 日志；**非** formal C-3) | ✅(S3b Mollusk 工程差分；**非** formal Stage-0 / Reference↔target closure) | ⚠️(WABT dummy env + 可选 near-sandbox 2.13.0 receipt 工程门（G123：deploy/init/mutate/view）；非 Reference↔Wasm formal) | ❌ | ❌ | ❌ |

## 3. 工程轨道未实现 feature 全清单（A/B/C/D 组）

> 与项目全面审查报告对齐。每个缺口带 ID、现状、wave 归属。
> 闭合 = GAP→LOWERED 或 GAP→FAIL-CLOSED（显式拒绝 + 测试）。

### A 组：Normalize/语义面剩余缺口（跨 target 通用，最高优先）

这些缺口在 sole Normalize 层，影响所有 target；N 家族共享 NormalizeV1/ReferenceV1/EnvelopeV1，**必须串行**（一个 wave 一个）。

| ID | 缺口 | 现状 | 影响范围 | wave 归属 |
|---|---|---|---|---|
| **N-A1** | EVM String match-switch | **已闭合(EvmStringMatch)**：EVM Lower 将 `match String` desugar 为 leaf-wise eq + nested ifThenElse（Plan `switchOn` 仍仅 UInt64 case）；catch-all fallthrough；非 String aggregate switch 与非 String pattern 仍 fail-closed | EVM | EvmStringMatch ✅ |
| **N-A2** | 多臂同构造器 match 细化 | **已闭合(MultiArmCtor)**：Normalize 允许同外构造器多臂，子模式可区分时 first-match 嵌套 guard（nested ctor→VariantTag eq，nested lit→value eq；fallthrough→outer catch-all 或 trap.unreachable）；结构 pattern key 重复（bind≡wildcard、ctor by vIdx、lit by valueBytes）仍 fail-closed；TypeCheck 同源 duplicate pattern 诊断；六 target 经 sole Normalize 继承 | 全 target | MultiArmCtor ✅ |
| **N-A3** | Map/Bytes 穿透元素赋值 | **已闭合(MapBytesAssign)**：TypeCheck/Normalize 单步 `m[k]:=v`/`b[i]:=u8` → IndexSet（load→set→store）；Reference 已有 Map/Bytes step。target 覆盖非均匀：EVM Map+Bytes、Solana Map、NEAR Map 与 fixed Bytes state、Noir Map、Aleo Map+Bytes 已部分 LOWERED，Psy 与其余组合按上表 FAIL-CLOSED；五个 Map-capable target 的 aggregate StateStore snapshot hazard 已修。Map 整程序 Reference 仍受 maxMapEntries 保守资源门；**嵌套穿透** `m[k].x:=v` 仍 fail-closed | 全 target Normalize；target 见 op 表 | MapBytesAssign + B-SOL-MAP-UPSERT ✅ |
| **N-A4** | Option state | **闭合**：Normalize+Reference default none；全 target Plan **FAIL-CLOSED**+测 | 全 target | OptionState ✅ |

### B 组：各 target 的 Plan/IR/emitter 覆盖缺口

#### B-1：跨 target 聚合/容器覆盖不均（最高优先，可并行——按 target 文件分隔）

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **B-1a** | NEAR 聚合与容器 | **闭合（L1）**：Array UInt、dense Map cap-8、fixed Bytes N 与 **named Struct/Enum** 已 flatten-to-KV（construct/fieldGet/fieldSet/variant ops + atomic storeAtomic；HostModel 端到端）；聚合返回值仍 FAIL-CLOSED（B-RET-ABI） | NearAggregate + NS-1 + Bytes + L1 |
| **B-1b** | Noir named 聚合 | **闭合(NoirAggregate + L3)**：named Struct/Enum + **Map UInt64 dense pilot**（cap-8 occ/key/val multi-leaf PI + IndexGet→Option + IndexSet；`storeAggregate` 两阶段 snapshot 与 empty-upsert relation model）+ **Array UInt64 state flatten** + **fixed Bytes N**（N×UInt8 leaves、literal IndexGet/Set、atomic store）；Bytes construct/param/动态索引与 Option/String state 仍 FAIL-CLOSED | NoirAggregate + NoirMap + NoirContainer + MapSnapshot + L3 ✅ |
| **B-1c** | Aleo 全功能 | **AleoCoverage + H3/NS-1/Bytes/Int64/T14 + G123**：标量、named Struct/Enum、Array、dense Map cap-2、fixed Bytes N、Commit 身份透传与 **BLS12-377 Fr** 已 LOWERED；Map aggregate StateStore 以 get-all-before-set two-phase 修复 empty upsert。bn254/Goldilocks、Option/Principal/String/ContextRead/externalCall/schedule/emit 仍 FAIL-CLOSED。Leo 4.0.2 已进入两平台 Tool Lock，`AleoAcceptance` 做 compile-only 验收；无 VM/prove/deploy 门 | AleoCoverage + T14 + MapSnapshot + G123 ✅ |
| **B-1d** | Solana Map/Bytes/Option state | **Map pilot + L2 已闭合**：Map 已进 ELF+Mollusk；named Struct/Enum 与 fixed Bytes N（N×UInt8 state/params、literal IndexGet/Set）已 flatten；`storeAggregate` structural CSE + `storeStateMulti` 固定 pre-store snapshot，峰值 177 temp/1424B，`put_into_empty` 已解除 ignore，MapMini 4/4 runtime 通过；Option state、Bytes construct 与动态索引仍 FAIL-CLOSED | SolanaMapPilot + B-SOL-MAP-ELF + B-SOL-MAP-UPSERT + L2 ✅ |
| **B-1e** | EVM Map/Bytes/Option state | **闭合(Map pilot)**：Array + Bytes + **Map UInt64 cap-8** deployable Token；aggregate `storeAtomic` 保证 leaf Expr/sload 全先于 sstore，EvmSmoke+solc 回归；Option-from-Map IndexGet | EvmMapPilot + MapSnapshot ✅ |

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
| **C-1** | NEAR Wasm 运行时差分 | **已闭合工程子集**：`NearWasmAcceptance` 将产品 Counter/DualField/LoopSum `.wat` 交给 locked `wat2wasm` 编译，并以 host-optional `wasm-interp`/`wasmtime`/`wasmer` 做 runtime load；后续 **C-6/G123** 又以 locked near-sandbox 2.13.0 对 Counter 做 deploy/init/mutate/view receipt 工程验收。工具未物化或 host runtime 缺席时 clean skip；两门都**不是** formal Reference↔Wasm/sandbox 差分或 Stage-0 证据 | NearWasmAcceptance + NearSandboxAcceptance ✅ |
| **C-2** | Aleo/Psy compiler/VM 验收研究 | **研究闭合（2026-08-02，RPT-015）** + **J2/G123 follow-up**：EmitIRV1 已对齐 Leo 4 语法；Leo 4.0.2 已进入两平台 Tool Lock，`AleoAcceptance` 对产品 `.aleo` 做 `leo build --offline` compile-only 验收（工具未物化时 clean skip）。Psy 仍无锁定 compiler/VM 门；两者均无 prove/deploy runtime 闭环。成熟度保持 source-only，**非** hermetic/runtime/formal | AleoPsyResearch + AleoEmissionFix + C-2-pin ✅ |
| **C-3** | EVM Reference↔Anvil formal differential | EVM 有 solc 验收 + G4 工程 Anvil 差分，formal Reference↔Anvil closure 仍缺 | EvmAnvilDiff（formal 轨道，按既定决定不做） |
| **C-4** | Noir prove/verify 验收门 | **prove/verify 研究结论仍为不升格**：G123 已将 nargo 1.0.0-beta.26 纳入两平台 Tool Lock，并由 `NoirCompileAcceptance` 对产品 Counter relation packages 做 compile-only 验收；但 Barretenberg/backend、CRS/security profile、witness/prove/verify 与 proof artifact binding 均未锁定，`validate_artifacts` 继续拒绝 proof-stage 叶子。成熟度保持 **source-only** relations；后续仅余独立 `NoirProveAcceptance` 决策与实现 | NoirProveResearch + NoirCompileAcceptance ✅（prove/verify 仍未实现） |
| **C-5** | Solana Mollusk fixture 跟 Normalize 新面 | **ongoing**：Counter + 13 fixtures 均产 ELF 并进入 Mollusk；当前 60 个 Rust tests 全 active/通过。MapMini 4/4 覆盖 empty upsert，WideMul 4/4 覆盖 UInt128/256 高肢/跨肢成功与 `0x1001` rollback，PrincipalStore 4/4 覆盖 `len + 8×UInt64` identity state/param、逐叶 equality 与高位清零（非 pubkey/CPI）；Option/Context/call 等运行覆盖仍待扩 | MolluskFixtures |

### D 组：文档/checkpoint 同步缺口

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **D-1** | registry target 表 | **已随 A0 重开并闭合事实同步**：engineering seed = 7 registry-implemented（`evm`/`solana`/`near`/`noir`/`aleo`/`psy`/`cosmwasm`）+ 3 design-only（`soroban`/`icp`/`openvm`）；其中 CosmWasm 仅 A0、无 materializer，accepted Phase-1 四-target 范围的 reconciliation 仍由 `DOC-ADR-SCOPE` 阻塞 | MatrixSync + CosmWasm A0 |
| **D-2** | 成熟度声明 | **已闭合并随 G123/A0 刷新**：EVM 有 locked solc + G4 工程 Anvil 差分；NEAR 有 locked `wat2wasm` 结构编译、host-optional runtime load + locked near-sandbox receipt 工程门；Solana 有 SBPF+Mollusk；Noir 有 locked nargo compile-only、Aleo 有 locked leo compile-only，但 Noir/Aleo/Psy 仍是 source-only，且 Psy 无锁定 compiler/VM，三者均无 proof/deploy 闭环。CosmWasm 的 `wasm-validated-alpha` 仅为 registry label，CW-A1 前无 artifact/runtime gate。以上均非 formal/hermetic/Stage-0 maturity | MatrixSync + G123 + CosmWasm A0 |

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
- **NearWasmAcceptance**（C-1）：**已闭合工程子集** — `Tests/Materialization/NearWasmAcceptance.lean`；locked `wat2wasm` + host-optional `wasm-interp`/`wasmtime`/`wasmer` runtime-load 门
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