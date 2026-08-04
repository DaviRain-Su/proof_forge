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

> **Registry 计数（2026-08-03，Quint Q0 后）**：工程 registry **12 = 9
> implemented + 3 design-only**。九个 materializer 均有 `materializeResult` dispatch：
> EVM / Solana / NEAR / Noir / Aleo / Psy / **Quint** / **CosmWasm** / **TON**。下列
> §1 主表保留原六 target 细格；**CosmWasm/TON 的真实 MVP 范围见 §1b，Quint 见 §1c**。
> compile / mock / sandbox / host-only Quint typecheck **不是** formal 或 hermetic。
>
> **双轨**：accepted PRD Phase 1 范围仍为 **EVM/Solana/NEAR/Noir**；
> Aleo/Psy/Quint/CosmWasm/TON 为 engineering leaves，**不**自动扩 accepted scope
>（`DOC-ADR-SCOPE` 仍 open）。

## 1. 语义 op 覆盖矩阵（wire Op × target；原六 materializer 细格）

| wire Op / feature | EVM | Solana | NEAR | Noir | Psy | Aleo |
|---|---|---|---|---|---|---|
| stateLoad/stateStore（标量） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| stateLoad/stateStore（named 聚合） | LOWERED(N3) | LOWERED(L2) | LOWERED(L1) | LOWERED(NoirAggregate) | LOWERED(H3) | LOWERED(H3) |
| stateLoad/stateStore（Array） | LOWERED(EvmIndex) | LOWERED(ArrayState) | LOWERED(NearAggregate) | LOWERED(NoirContainer) | LOWERED | LOWERED(H3 flatten) |
| stateLoad/stateStore（Map） | LOWERED(cap-8; atomic store) | LOWERED(cap-8; aggregate CSE→storeStateMulti；ELF+Mollusk 4/4) | LOWERED(cap-8; atomic KV store) | LOWERED(cap-8; atomic multi-leaf PI) | FAIL-CLOSED | LOWERED(cap-2; atomic mapping store) |
| stateLoad/stateStore（Bytes） | LOWERED(D4-E2: N×UInt8 leaves) | LOWERED(L2: N×UInt8 leaves) | LOWERED(N×UInt8 KV leaves) | LOWERED(L3: N×UInt8 leaves) | FAIL-CLOSED | LOWERED(Bytes N: N×u8 mappings) |
| stateLoad/stateStore（Option） | **LOWERED(BL-31: Option UInt64 only)** | **LOWERED(BL-29: Option UInt64 only)** | **LOWERED(BL-30: Option UInt64 only)** | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
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
| contextRead | FAIL-CLOSED(全target；**EVM caller encoding 已冻结 ADR-0025：`u32le(20)\|\|CALLER`，Plan 未开**) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| commit | LOWERED(身份透传) | LOWERED(身份透传) | LOWERED(身份透传) | FAIL-CLOSED | FAIL-CLOSED | LOWERED(身份透传) |
| externalCall（sync call） | LOWERED(static QN→CALL；result-bearing UInt64 读 returndata；callee address stub，语义 PARTIAL) | LOWERED(static QN→`sol_invoke_signed_c`；result-bearing UInt64 读 `sol_get_return_data`；空 AccountMeta/外层 callee account 未闭合，语义 PARTIAL) | FAIL-CLOSED | LOWERED(relation slots；语义 PARTIAL) | LOWERED(`__invoke_sync` source；语义 PARTIAL) | FAIL-CLOSED(resolver+plan) |
| schedule（async） | LOWERED(static QN→同步 CALL+忽略结果；语义 stub) | LOWERED(static QN→`sol_invoke_signed_c`；空 AccountMeta/外层 callee account 未闭合，语义 PARTIAL) | LOWERED(promise；fire-and-forget) | LOWERED(relation slots；语义 PARTIAL) | FAIL-CLOSED | FAIL-CLOSED(resolver+plan) |
| **match String scrutinee** | LOWERED(N-A1) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| **named aggregate entry/view return（B-RET-ABI）** | LOWERED(≤8 UInt64/Int64 叶 tuple ABI) | LOWERED(≤8 叶 N×8-byte LE) | LOWERED(≤8 叶 N×8-byte LE) | LOWERED(per-leaf verifier inputs) | LOWERED(entry/view `[Felt; N]`) | LOWERED(non-Final entry tuple；computed view-over-state FC) |
| **anonymous Array/Map/Option/Bytes result（N-ANON-RESULT）** | LOWERED(Array UInt64 N≤8 / Option UInt64；Map/Bytes FC) | LOWERED(Array UInt64 N≤8 / Option UInt64；Map/Bytes FC) | LOWERED(Array UInt64 N≤8 / Option UInt64；Map/Bytes FC) | LOWERED(Array UInt64 N≤8 / Option UInt64；Map/Bytes FC) | LOWERED(Array UInt64 N≤8 / Option UInt64；Map/Bytes FC) | LOWERED(Array UInt64 N≤8 / Option UInt64；Map/Bytes 与 computed view-over-state FC) |
| **match 多臂同构造器** | LOWERED(N-A2) | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| **Principal state/params** | LOWERED(T10: leaf storage; ≠address) | LOWERED(T12: 9×u64 leaves; ≠32B pubkey) | LOWERED(T12: 9×KV leaves; ≠account-id) | LOWERED(T12: 9×u64 inputs; ≠Field) | FAIL-CLOSED | FAIL-CLOSED |
| **UInt128 state/param/body** | LOWERED(T9b 原生 word) | LOWERED(T9e 2×u64 multiword；**mul 真 schoolbook B-SOL-MUL**；div/mod low64 FC) | LOWERED(T9e 2×i64 multiword；**mul 真 schoolbook NEAR lane**；div/mod/shift FC) | LOWERED(T11 原生 u128 / multi-limb analogue；mul/div/mod FC；UInt256 FC) | FAIL-CLOSED | FAIL-CLOSED |
| **UInt256 state/param/body** | LOWERED(T9b) | LOWERED(T9e 4×u64；**mul 真 schoolbook B-SOL-MUL**；div/mod low64 FC) | LOWERED(T9e 4×i64；**mul 真 schoolbook NEAR lane**；div/mod/shift FC) | LOWERED(T13；add/sub/cmp/bit；mul/div/mod FC) | FAIL-CLOSED | FAIL-CLOSED |

## 1b. CosmWasm / TON 工程 MVP 真实范围（第八 materializer 对）

> 两列均已有 target-owned Plan/IR/emitter/finalizer + 产品 `build` 路径。下列为 **MVP
> 精确边界**，不是 formal SupportClaim，也不是完整语言面。

### CosmWasm（`cosmwasm-wasm-u64-v1`，label `wasm-validated-alpha`）

| 面 | 状态 | 说明 |
|---|---|---|
| public UInt8/16/32/64 state / param / result | **LOWERED** | KV → `env.db_*`；narrow physical slot 仍 8B LE并校验高位；UInt128/256与窄 Int FC |
| checked + − × / % · unary · shift/bitwise/logical · eq/order | **LOWERED** | UInt64 + narrow UInt body guards |
| if / match / bounded for / pureFn | **LOWERED** | 多块 CFG；match 多臂同构造器随 Normalize；Int induction FC |
| emit / revert / bare assert | **LOWERED** | attributes / `ContractResult::Err` |
| schedule（async） | **LOWERED（语义 PARTIAL）** | → `SubMsg{reply_on:never,id:0,WasmMsg::Execute}`；msg=Binary(base64 inner JSON)；同 tx savepoint，子失败 abort整 tx；QN address stub；非跨 tx async |
| externalCall（sync） | **FAIL-CLOSED** | resolver + Plan 双拒；不得 alias 为 sync CALL |
| named Struct/Enum state + entry/view return | **LOWERED** | ≤8 UInt64/Int64 leaves；execute/query JSON array；aggregate param/pureFn FC |
| Array/Map state | **LOWERED** | Array UInt64；dense Map UInt64 cap-8；atomic KV store |
| anonymous Array/Option result | **LOWERED** | `Array UInt64 N`(1..8) / `Option UInt64` entry+view；Map/Bytes/nested/非 UInt64 FC |
| ContextRead / Commit · nonempty invariants · Option/Bytes state · Field/Principal/String interface | **FAIL-CLOSED** | iterator/IBC/migrate/reply entry亦未开 |
| 制品 / 验收 | WAT + locked `wat2wasm` + `cosmwasm-check` 3.0.9 + cosmwasm-vm mock 28 tests + wasmd v0.70.3 Docker rung-1 | **非** 主网 / formal / hermetic |

### TON（`ton-tolk-boc-v1`，label `source-only`）

| 面 | 状态 | 说明 |
|---|---|---|
| public UInt8/16/32/64 c4 state / param / result | **LOWERED** | exact cell bit widths + int257 range guards；UInt128/256与窄 Int FC |
| checked 算术 · unary · shift/bitwise/logical · eq/order | **LOWERED** | TVM int257 上显式 declared-width 范围检查 |
| if / match / bounded for / pureFn | **LOWERED** | Int induction 与 aggregate pureFn FC |
| emit / revert / bare assert | **LOWERED** | external out / throw |
| externalCall（sync） | **FAIL-CLOSED** | 纯异步 actor；resolver 拒 sync |
| schedule（async） | **LOWERED（语义 PARTIAL）** | → `createMessage`；NoBounce、value=0、fixed send-mode、hash destination stub；init/mutate only；无 callback round-trip |
| named Struct/Enum state + aggregate view return | **LOWERED** | view multi-stack tuple≤8 leaves；entry aggregate FC |
| Array/Map/Bytes state | **LOWERED** | Array UInt64；dense Map UInt64 cap-8；fixed Bytes N；c4 flatten |
| anonymous Array/Option view result | **LOWERED** | `Array UInt64 N`(1..8) / `Option UInt64`；entry、Map/Bytes/nested/非 UInt64 FC |
| ContextRead / Commit · nonempty invariants/constants · Option state · Field/Principal/String interface | **FAIL-CLOSED** | |
| 制品 / 验收 | Tolk 1.4.2 → `.fif` + real BoC + `@ton/sandbox` 10/10（含 ScheduleFlow） | **非** 主网 / formal / hermetic |

## 1c. Quint Q0 executable-model 真实范围（第九 materializer）

| 面 | 状态 | 说明 |
|---|---|---|
| anonymous UInt64/Bool/Unit；public UInt64 state/params | **LOWERED** | 完整 UInt64 域 `oneOf(0.to(PF_MAX_U64))`；target-owned namespace |
| checked + − × / %、比较、Bool and/or/not | **LOWERED** | unbounded Quint int + success checks；div/mod 零值 guarded，first-failure code |
| StateLoad/StateStore、bare assert | **LOWERED** | 所有业务 store 只在 aggregate success 时提交；失败显式 outcome + state stutter |
| pureCall | **LOWERED** | target 内联；depth≤64、expanded op≤4096、checks≤128、单表达式 fully-expanded rendered node budget≤16384（含 div/mod guard duplication）；state/effect FC，未调用 pureFn 也完整验证 |
| zero-param public-Bool invariant | **LOWERED** | read-only single-block；发射为不依赖 `pf_last_*` instrumentation 的 `val` |
| multi-block/if/match/for、Int/Field/Principal/String/aggregates/containers | **FAIL-CLOSED** | Q0 不做语义近似 |
| event/nonzero revert payload/call/schedule/ContextRead/Commit/constants | **FAIL-CLOSED** | zero-payload declared revert 保留 ErrorId（failure code=`256+id`）；resolver 仅 rollback/state/Bool/checked-arithmetic 四键 |
| 制品 / 验收 | `.qnt` + zero-tool finalize；host-optional exact Quint 0.32 typecheck + TS smoke | 不可部署；非 ITF/MBT/verify/Apalache/formal |

## 2. 验收/差分覆盖矩阵

| 验收门 | EVM | Solana | NEAR | Noir | Psy | Aleo | Quint | CosmWasm | TON |
|---|---|---|---|---|---|---|---|---|---|
| Plan canonicity (ValidatePlan) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| IR 结构验证 (ValidateIR) | ✅(M4) | N/A | N/A | N/A | N/A | N/A | ✅(structured Q AST) | N/A | N/A |
| 真实工具链编译验收 | ✅(EvmSolc: solc) | ✅(Mollusk runtime) | ✅(NearWasmAcceptance: locked wat2wasm + host-optional wasm-interp/wasmtime/wasmer load) | ✅(NoirCompileAcceptance: nargo 1.0.0-beta.26 compile-only；G123；缺席 skip；**非** prove/verify) | ❌(source-only) | ✅(AleoAcceptance: leo 4.0.2 Tool Lock pin（G123）；缺席 skip；非 prove/deploy) | ❌ product toolchain；⚠️ host-only exact Quint 0.32 typecheck（非 Tool Lock/finalize） | ✅(locked wat2wasm + cosmwasm-check 3.0.9；**非** wasmd) | ✅(tolk 1.4.2 → real BoC；**非** 主网) |
| 运行时差分 (Reference↔target) | ⚠️(G4 工程 Anvil 差分：Counter/Accumulator/ArithOps/EventFlow overflow state-hold + emit 日志；**非** formal C-3) | ✅(S3b Mollusk 工程差分；**非** formal Stage-0 / Reference↔target closure) | ⚠️(WABT dummy env + near-sandbox 2.13.0 Counter/aggregate-return/Option-state 工程门；非 Reference↔Wasm formal) | ❌ | ❌ | ❌ | ⚠️(TS evaluator smoke；非 Reference differential/verify) | ⚠️(cosmwasm-vm mock 28 tests + wasmd v0.70.3 Docker rung-1；**非** formal/主网) | ⚠️(@ton/sandbox 10/10 工程，含 ScheduleFlow；**非** formal/主网) |

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
| **N-A4** | Option state | **shared 闭合**：Normalize+Reference default none；target follow-up 已开 EVM/Solana/NEAR `Option UInt64` tag+payload state，Noir/Psy/Aleo/Quint/CosmWasm/TON 继续 **FAIL-CLOSED** | 全 target | OptionState ✅ + B-OPT-STATE ongoing |

### B 组：各 target 的 Plan/IR/emitter 覆盖缺口

#### B-1：跨 target 聚合/容器覆盖不均（最高优先，可并行——按 target 文件分隔）

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **B-1a** | NEAR 聚合与容器 | **闭合（L1 + follow-ups）**：Array UInt、dense Map cap-8、fixed Bytes N、**named Struct/Enum** 与 `Option UInt64` state 已 flatten-to-KV（construct/fieldGet/fieldSet/variant ops + atomic storeAtomic；HostModel 端到端）；named 与 anonymous Array/Option ≤8-leaf aggregate return 已由 B-RET-ABI/N-ANON-RESULT 开放 | NearAggregate + NS-1 + Bytes + L1 + BL-30 |
| **B-1b** | Noir named 聚合 | **闭合(NoirAggregate + L3)**：named Struct/Enum + **Map UInt64 dense pilot**（cap-8 occ/key/val multi-leaf PI + IndexGet→Option + IndexSet；`storeAggregate` 两阶段 snapshot 与 empty-upsert relation model）+ **Array UInt64 state flatten** + **fixed Bytes N**（N×UInt8 leaves、literal IndexGet/Set、atomic store）；Bytes construct/param/动态索引与 Option/String state 仍 FAIL-CLOSED | NoirAggregate + NoirMap + NoirContainer + MapSnapshot + L3 ✅ |
| **B-1c** | Aleo 全功能 | **AleoCoverage + H3/NS-1/Bytes/Int64/T14 + G123**：标量、named Struct/Enum、Array、dense Map cap-2、fixed Bytes N、Commit 身份透传与 **BLS12-377 Fr** 已 LOWERED；Map aggregate StateStore 以 get-all-before-set two-phase 修复 empty upsert。bn254/Goldilocks、Option state/Principal/String/ContextRead/externalCall/schedule/emit 仍 FAIL-CLOSED。Leo 4.0.2 已进入两平台 Tool Lock，`AleoAcceptance` 做 compile-only 验收；无 VM/prove/deploy 门 | AleoCoverage + T14 + MapSnapshot + G123 ✅ |
| **B-1d** | Solana Map/Bytes/Option state | **Map pilot + L2 + BL-29 已闭合**：Map 已进 ELF+Mollusk；named Struct/Enum、fixed Bytes N 与 `Option UInt64` state 已 flatten；`storeAggregate` structural CSE + `storeStateMulti` 固定 pre-store snapshot，峰值 177 temp/1424B，`put_into_empty` 已解除 ignore；Option state 6 项 Mollusk 通过；Option params/非 UInt64/nested、Bytes construct 与动态索引仍 FAIL-CLOSED | SolanaMapPilot + B-SOL-MAP-ELF + B-SOL-MAP-UPSERT + L2 + BL-29 ✅ |
| **B-1e** | EVM Map/Bytes/Option state | **闭合(Map pilot + BL-31)**：Array + Bytes + **Map UInt64 cap-8** + `Option UInt64` state 进入 locked-solc engineering finalization（`deployable=true` 仅为制品标志；258460 B Token creation bytecode 超 EIP-3860，无 chain/Anvil deploy 声明）；aggregate `storeAtomic` 保证 leaf Expr/sload 全先于 sstore；Option params/非 UInt64/nested 仍 FC | EvmMapPilot + MapSnapshot + B-EVM-MAP-STACK + BL-31 ✅ |

#### B-2：Normalize 语义细化（= A 组，N 家族串行）

见 A 组 N-A1/N-A2/N-A3/N-A4。

#### B-3：call/schedule 的 address-bearing 类型

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **B-3** | Principal→address 映射 | **已闭合为 FAIL-CLOSED 研究钉（PrincipalAddr, 2026-08-02）** + **AddressBearing followup 已闭合（static-callee open, 2026-08-02）** + **T10 EVM Principal storage pilot（2026-08-02）** + **T12 Solana/NEAR/Noir Principal storage pilot（2026-08-02）** + **EVMOZ-003 / ADR-0025（2026-08-03）冻结 EVM `context.caller` encoding，不改 B-3 pin**。Principal valueBytes = `u32le(len)\|body`（`1≤len≤4096`）共享 wire **不变**；**无** approximate 任意 Principal→address 映射，**无** Address TypeShape。ADR-0025 规定：未来 EVM ContextRead caller 结果 **仅** `u32le(20)\|\|CALLER`（network-order 20B）；**当前六 target ContextRead Plan 仍 FAIL-CLOSED**；不解锁 Solidity `address` ABI / dynamic CALL / Ownable F01。T10/T12 在 EVM/Solana/NEAR/Noir 开放 **wire identity 原样 leaf 存储**（`pilotPrincipalPolicyAdmit`；len+8×UInt64，≤64B body，与 N4 String 同构；非 20B address / 32B pubkey / account-id / Field）；Aleo/Psy 保持 `pilotPrincipalPolicyNone`。产品 `call`/`schedule` 为 wire `Op.ExternalCall`/`Schedule` 的 **static `QualifiedName` callee**（非 ValueId 地址）。AddressBearing 打开 EVM/Solana 双 call 键：EVM Plan `externalCall`/`schedule` → Yul `CALL` 至 `keccak256(targetPath)` 后 20 字节 + method selector；Solana Plan/IR `externalCall`/`schedule` → program id = SHA-256(targetPath) 32B，plan 文本 `external_call`/`schedule`，SBPF 以 `sol_log_data` 观测桩（完整 `invoke_signed` CPI 需 account metas，另排）。NEAR 仍拒 sync；Noir 七键不变 | PrincipalAddr ✅ + AddressBearing ✅ + T10/T12 storage ✅ + ADR-0025 encoding ✅（Plan open 见 B-CTX-OPEN） |

#### B-4：验收门升级（= C 组）

见 C 组。

### C 组：工程验证缺口（验收门升级）

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **C-1** | NEAR Wasm 运行时差分 | **已闭合工程子集**：`NearWasmAcceptance` 将产品 Counter/DualField/LoopSum `.wat` 交给 locked `wat2wasm` 编译，并以 host-optional `wasm-interp`/`wasmtime`/`wasmer` 做 runtime load；后续 **C-6/G123** 又以 locked near-sandbox 2.13.0 对 Counter 做 deploy/init/mutate/view receipt 工程验收。工具未物化或 host runtime 缺席时 clean skip；两门都**不是** formal Reference↔Wasm/sandbox 差分或 Stage-0 证据 | NearWasmAcceptance + NearSandboxAcceptance ✅ |
| **C-2** | Aleo/Psy compiler/VM 验收研究 | **研究闭合（2026-08-02，RPT-015）** + **J2/G123 follow-up**：EmitIRV1 已对齐 Leo 4 语法；Leo 4.0.2 已进入两平台 Tool Lock，`AleoAcceptance` 对产品 `.aleo` 做 `leo build --offline` compile-only 验收（工具未物化时 clean skip）。Psy 仍无锁定 compiler/VM 门；两者均无 prove/deploy runtime 闭环。成熟度保持 source-only，**非** hermetic/runtime/formal | AleoPsyResearch + AleoEmissionFix + C-2-pin ✅ |
| **C-3** | EVM Reference↔Anvil formal differential | EVM 有 solc 验收 + G4 工程 Anvil 差分，formal Reference↔Anvil closure 仍缺 | EvmAnvilDiff（formal 轨道，按既定决定不做） |
| **C-4** | Noir prove/verify 验收门 | **prove/verify 研究结论仍为不升格**：G123 已将 nargo 1.0.0-beta.26 纳入两平台 Tool Lock，并由 `NoirCompileAcceptance` 对产品 Counter relation packages 做 compile-only 验收；但 Barretenberg/backend、CRS/security profile、witness/prove/verify 与 proof artifact binding 均未锁定，`validate_artifacts` 继续拒绝 proof-stage 叶子。成熟度保持 **source-only** relations；后续仅余独立 `NoirProveAcceptance` 决策与实现 | NoirProveResearch + NoirCompileAcceptance ✅（prove/verify 仍未实现） |
| **C-5** | Solana Mollusk fixture 跟 Normalize 新面 | **ongoing**：Counter + 19 fixtures = 20 programs 均产 ELF 并进入 Mollusk；当前 89 个 Rust tests（`programs.rs` 74 + `counter.rs` 8 + `cpi.rs` 7）全 active/通过。除 MapMini/WideMul/PrincipalStore 外，OptionState 6 项固定 tag/payload state 与 stale-payload clear；CpiCaller 7 项固定真实 `sol_invoke_signed_c`/`sol_get_return_data` 发射并在缺外层 callee account 时 fail closed。ContextRead 与可成功 CPI 的多账户外层 ABI 仍待扩 | MolluskFixtures |

### D 组：文档/checkpoint 同步缺口

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **D-1** | registry target 表 | **已随 Quint Q0 刷新**：engineering seed = **9** registry-implemented（`evm`/`solana`/`near`/`noir`/`aleo`/`psy`/`quint`/`cosmwasm`/`ton`）+ **3** design-only（`soroban`/`icp`/`openvm`）= **12**；九 materializer 均有 Plan/IR/dispatch。accepted Phase-1 四-target 范围 reconciliation 仍由 `DOC-ADR-SCOPE` 阻塞 | MatrixSync + Quint/CW/TON MVP docs |
| **D-2** | 成熟度声明 | **已闭合并随 G123 + CW/TON MVP 刷新**：EVM locked solc + G4 Anvil 工程差分；NEAR locked `wat2wasm` + near-sandbox receipt；Solana SBPF+Mollusk；Noir locked nargo compile-only、Aleo locked leo compile-only、Psy host-optional；**CosmWasm** WAT+wat2wasm+check+mock 28 tests + wasmd rung-1（label 仍 `wasm-validated-alpha`）；**TON** Tolk/BoC+sandbox 10/10 + schedule createMessage PARTIAL（label 仍 `source-only`）；**Quint** `.qnt` + zero-tool finalize（label `source-only`；host-only typecheck/run 非 locked gate）。以上均**非** formal/hermetic/Stage-0 maturity | MatrixSync + G123 + CW/TON MVP |

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
- **PrincipalAddr**（B-3）：**已闭合为 FAIL-CLOSED 研究钉** — wire Principal ≠ EVM/Solana 固定地址 type；见 §B-3
- **AddressBearing**（B-3 followup）：**已闭合（static-callee open）** — research 确认 callee 为 static QN 非 dynamic address；EVM/Solana resolver 七键 + Plan/IR/emitter 打开；任意 Principal→CALL 地址仍 fail closed
- **EVMOZ-003 / ADR-0025 EVM caller encoding**：**encoding 决策已 accepted** — 未来 EVM `context.caller` = `u32le(20)||CALLER`；shared wire 不变；**Plan 仍 FAIL-CLOSED** 至原子 cutover；不解锁 address ABI / Ownable F01 / 他 target
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