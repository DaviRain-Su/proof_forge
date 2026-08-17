---
id: RESEARCH-012
title: Target Plan/IR/Emitter 覆盖缺口矩阵（工程轨道权威清单）
status: draft
owner: engineering
updated: 2026-08-15
normative: false
---

# Target Plan/IR/Emitter 覆盖缺口矩阵

> **目的**：工程轨道 op×target **格子**的事实源。每个 wave 闭合哪些格子在此可查；
> wave 完成后由 worker 简报的"已 lower op 列表"验证，矩阵随之更新。  
> **总执行队列**（优先级/并行规则）：[`../engineering-backlog.md`](../engineering-backlog.md)。  
> **可移植性 / 跨合约原子性（为何不能假同步多链）**：见  
> [`22-portable-surface-vs-chain-reality.md`](22-portable-surface-vs-chain-reality.md)。  
> 非 formal：D2–D4 formal task 不在此矩阵（走 release-qualification 轨道）。

## 矩阵说明

- **LOWERED** = 产品路径已下降该 op/feature 并有测试覆盖
- **FAIL-CLOSED** = 显式拒绝（planInvariant/failUnsupported），文档化边界
- **GAP** = 未实现且未显式拒绝（应闭合：要么 LOWER，要么显式 FAIL-CLOSED + 测试）
- 空白 = 不适用该 target（family 边界）

数据来源：产品测试（EvmSmoke/Mollusk/NoirRelationModel 等）+ LowerSemanticV1 代码扫描。
**初版可能不精确**——每个 wave worker 须核对并修正自己 target 行的真实边界。

> **Registry 计数（当前工程事实，2026-08-14）**：工程 registry **12 = 12
> implemented + 0 design-only**。十二个 materializer 均有 `materializeResult` dispatch：
> EVM / Solana / NEAR / Noir / Aleo / Psy / Quint / CosmWasm / TON / Soroban / OpenVM / ICP。
> 下列 §1 主表保留原六 target 细格；**CosmWasm/TON 的真实 MVP 范围见 §1b，Quint 见 §1c**。
> compile / mock / sandbox / host-only Quint typecheck **不是** formal 或 hermetic。
>
> **双轨**：accepted PRD Phase 1 范围仍为 **EVM/Solana/NEAR/Noir**；
> 其余八个为 engineering leaves，**不**自动扩 accepted scope
>（ADR-0036 固定 engineering 12+0 不静默改写 accepted scope，formal lighthouse=EVM-first）。

## 1. 语义 op 覆盖矩阵（wire Op × target；原六 materializer 细格）

| wire Op / feature | EVM | Solana | NEAR | Noir | Psy | Aleo |
|---|---|---|---|---|---|---|
| stateLoad/stateStore（标量） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| stateLoad/stateStore（named 聚合） | LOWERED(N3) | LOWERED(L2) | LOWERED(L1) | LOWERED(NoirAggregate) | LOWERED(H3) | LOWERED(H3) |
| stateLoad/stateStore（Array） | LOWERED(EvmIndex; UInt8/16/32/64 **or Int64**; signedness on `LoweredValueV1.isInt`) | LOWERED(ArrayState; UInt64 **or Int64** N×8-byte `isInt` leaves) | LOWERED(NearAggregate; UInt64 **or Int64** N×8-byte `isInt` leaves) | LOWERED(NoirContainer; UInt64 **or Int64** N×`inputType` `.u64`/`.i64` leaves) | LOWERED(UInt64 **or Int64** names-only Felt leaves; `isInt` from TypeId) | LOWERED(H3 flatten; UInt64 **or Int64** N×`i64`/`u64` mapping leaves；Int8/return FC) |
| stateLoad/stateStore（Map） | LOWERED(**hashed 1-slot** UInt64 key + UInt64 **or Int64** val; Principal key UInt64-only; not 24-leaf isInt table) | LOWERED(cap-8 UInt64 key + UInt64 **or Int64** val; aggregate CSE→storeStateMulti；ELF+Mollusk 4/4) | LOWERED(cap-8 UInt64 key + UInt64 **or Int64** val; atomic KV store) | LOWERED(cap-8 UInt64 key + UInt64 **or Int64** val; atomic multi-leaf PI；val slots `.i64`) | LOWERED(cap-8 UInt64 key + UInt64 **or Int64** val; names-only 24 Felt leaves; mux `.select`) | LOWERED(cap-2 / 6 leaves; UInt64 key + UInt64 **or Int64** val; atomic mapping store；Int64-key FC) |
| stateLoad/stateStore（Bytes） | LOWERED(D4-E2: N×UInt8 leaves) | LOWERED(L2: N×UInt8 leaves) | LOWERED(N×UInt8 KV leaves) | LOWERED(L3: N×UInt8 leaves) | LOWERED(N×Felt u8 leaves) | LOWERED(Bytes N: N×u8 mappings) |
| stateLoad/stateStore（Option） | **LOWERED(BL-31: Option UInt64 **or Int64**; tag unsigned + payload `isInt`)** | **LOWERED(BL-29: Option UInt64 **or Int64**)** | **LOWERED(BL-30: Option UInt64 **or Int64**)** | **LOWERED(BL-32: Option UInt64 **or Int64**)** | **LOWERED(BL-36: Option UInt64 **or Int64**)** | **LOWERED(BL-35: Option UInt64 **or Int64**；Int8/return FC)** |
| stateLoad/stateStore（String） | LOWERED(N4) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| stateLoad/stateStore（Field bn254） | LOWERED(N2b-EVM) | FAIL-CLOSED | FAIL-CLOSED | LOWERED(原生) | FAIL-CLOSED(非Goldilocks) | FAIL-CLOSED(非BLS12-377) |
| stateLoad/stateStore（Field BLS12-377） | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | **LOWERED(T14)** |
| stateLoad/stateStore（Field Goldilocks） | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | **LOWERED(T14)** | FAIL-CLOSED |
| constant（`Op.Constant`） | **LOWERED(T3: scalar via `Op.Literal`；String/aggregate/Principal FC)** | **LOWERED(T3 product Lower；`Cpi*IR` 空表门仍在)** | **LOWERED(NEAR const slot)** | **LOWERED(T3: scalar via literal)** | **LOWERED(UInt8/16/32、Bool、UInt64<p、非负 Int64；显式 VM profile 另开 UInt128 canonical 16B→4×UInt32 limbs；Goldilocks ConstantV1 复用 decoder，source 无 Field literal；负 Int64/UInt64≥p FC)** | **LOWERED(ALEO-CONST: `lowerLiteral` 内联)** |
| construct（named Struct/Enum） | LOWERED(N3) | LOWERED(L2) | LOWERED(L1) | LOWERED(NoirAggregate) | LOWERED(H3) | LOWERED(H3) |
| fieldGet/fieldSet | LOWERED(N3) | LOWERED(L2) | LOWERED(L1) | LOWERED(NoirAggregate) | LOWERED(H3) | LOWERED(H3) |
| variantTag/variantPayload | LOWERED(N3) | LOWERED | LOWERED(NearAggregate) | LOWERED(NoirAggregate) | LOWERED | LOWERED(H3) |
| indexGet/indexSet（Array） | LOWERED(EvmIndex) | LOWERED(ArrayState) | LOWERED(NearAggregate) | LOWERED(NoirContainer) | LOWERED | LOWERED(H3 flatten) |
| indexGet/indexSet（Map） | LOWERED(Map+Option) | LOWERED(Map+Option) | LOWERED(Map+Option) | LOWERED(Map+Option) | LOWERED(Map+Option; UInt64 **or Int64** val; mux `.select`) | LOWERED(dense Map cap-2) |
| indexGet/indexSet（Bytes） | LOWERED(D4-E2) | LOWERED(L2: literal index) | LOWERED(NearAggregate: literal index、UInt8 leaf；动态索引 FC) | LOWERED(L3: compile-time literal index、UInt8 leaf；动态索引 FC) | LOWERED(literal index；动态索引 FC) | LOWERED(literal index；动态索引 FC) |
| fieldAdd/Sub/Mul/Div/Neg（Field） | LOWERED(N2b-EVM bn254) | FAIL-CLOSED | FAIL-CLOSED | LOWERED(原生 bn254) | **LOWERED(T14 Goldilocks)** | **LOWERED(T14 BLS12-377)** |
| eq/ne（所有支持类型） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| ordering 比较 | LOWERED(UInt/Int) | LOWERED(UInt/Int) | LOWERED | LOWERED(UInt/Field) | LOWERED | LOWERED |
| unary（-/~/!） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED(UInt64 `~`→checkedBitNot，x<2^32−1 运行时 trap；Int64 `~` FC；UInt32 `~` XOR mask) | LOWERED(~/!;neg FC) |
| binary 算术（checked + - * / %） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED（标量；VM profile UInt128 checked add/sub/mul/div/mod；mul=8×UInt16 schoolbook；div/mod=四段 restoring） | LOWERED |
| shift/bitwise/logical | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED（标量；UInt128 shift/bitwise FC） | LOWERED |
| pureCall（fn/localCall） | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED（VM profile 可展开 UInt128 args；UInt128 pureFn result FC） | LOWERED |
| emit / revert | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | FAIL-CLOSED emit; bare revert LOWERED |
| assertOp | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| contextRead | **LOWERED**（`unixTimeSeconds`→`timestamp()`；`blockHeight`→`number()`；`caller`→`u32le(20)\|\|CALLER`；`chainId`→`chainid()` UInt64 guard；`self`→`address()` ADR-0025；`attachedValue`→`callvalue()` / payable entry，view 读得 0；未知键 FC） | **PARTIAL**（sole `solana-sbpf-cpi-elf-v1`：`caller`→`pf_caller` signer；`blockHeight`→`sol_get_clock_sysvar`/`Clock.slot`，物理 slot 非逻辑块号；`unixTimeSeconds`/`self`/`attachedValue`/`chainId` FC。legacy plan/elf 已删） | **PARTIAL**（`unixTimeSeconds`→`block_timestamp` ns÷10^9；`blockHeight`→view-safe `block_index()`；`caller`→`predecessor_account_id` 仅 init/entry、view FC；`self`→`current_account_id` view-safe；`attachedValue`→`attached_deposit` init/entry、view FC；`chainId` FC） | FAIL-CLOSED（电路域无锚定时钟/caller；named no-host） | FAIL-CLOSED（named no-host） | FAIL-CLOSED（named no-host） |
| commit | LOWERED(身份透传) | LOWERED(身份透传) | LOWERED(身份透传) | FAIL-CLOSED | FAIL-CLOSED | LOWERED(身份透传) |
| externalCall（sync call） | LOWERED(static QN→CALL；result-bearing UInt64 读 returndata；callee address stub，语义 PARTIAL) | LOWERED(static QN→`sol_invoke_signed_c`；result-bearing UInt64 读 `sol_get_return_data`；空 AccountMeta/外层 callee account 未闭合，语义 PARTIAL) | FAIL-CLOSED | LOWERED(relation slots；语义 PARTIAL) | PARTIAL(void call→DPN `InvokeExternal`；result-bearing call FC) | FAIL-CLOSED(resolver+plan) |
| schedule（async） | LOWERED(static QN→同步 CALL+忽略结果；语义 stub) | LOWERED(static QN→`sol_invoke_signed_c`；空 AccountMeta/外层 callee account 未闭合，语义 PARTIAL) | LOWERED(promise；fire-and-forget) | LOWERED(relation slots；语义 PARTIAL) | FAIL-CLOSED | FAIL-CLOSED(resolver+plan) |
| **match String scrutinee** | LOWERED(N-A1) | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED | FAIL-CLOSED |
| **named aggregate entry/view return（B-RET-ABI）** | LOWERED(≤8 UInt64/Int64 叶 tuple ABI) | LOWERED(≤8 叶 N×8-byte LE) | LOWERED(≤8 叶 N×8-byte LE) | LOWERED(per-leaf verifier inputs) | LOWERED(ordered DPN `circuit_outputs`) | LOWERED(non-Final entry tuple；computed view-over-state FC) |
| **anonymous Array/Map/Option/Bytes result（N-ANON-RESULT）** | LOWERED(Array UInt64 N≤8 / Option UInt64；Array/Option/Map Int64 return + Map/Bytes FC) | LOWERED(Array UInt64 N≤8 / Option UInt64；Map/Bytes FC) | LOWERED(Array UInt64 N≤8 / Option UInt64；Map/Bytes FC) | LOWERED(Array UInt64 N≤8 / Option UInt64；Map/Bytes FC) | LOWERED(Array UInt64 N≤8 / Option UInt64；Map/Bytes FC) | LOWERED(Array UInt64 N≤8 / Option UInt64；Map/Bytes / Int64 container return 与 computed view-over-state FC) |
| **match 多臂同构造器** | LOWERED(N-A2) | LOWERED | LOWERED | LOWERED | LOWERED | LOWERED |
| **Principal state/params** | LOWERED(T10: leaf storage; ≠address) | LOWERED(T12: 9×u64 leaves; ≠32B pubkey) | LOWERED(T12: 9×KV leaves; ≠account-id) | LOWERED(T12: 9×u64 inputs; ≠Field) | LOWERED(9-leaf wire identity；≠network address) | **LOWERED(T3: 9×u64 identity leaves；≠address/Field；return FC)** |
| **UInt128 state/param/body** | LOWERED(T9b 原生 word) | LOWERED(T9e 2×u64 multiword；mul schoolbook；div/mod restoring binary long division `910835aa4`，runtime differential 待补) | LOWERED(T9e 2×i64 multiword；**mul 真 schoolbook NEAR lane**；div/mod/shift FC) | LOWERED(T11 原生 u128 / multi-limb analogue；mul/div/mod FC；UInt256 FC) | LOWERED(DPN 4×UInt32 LE limbs；checked arithmetic/compare/bitwise/shift) | FAIL-CLOSED |
| **UInt256 state/param/body** | LOWERED(T9b) | LOWERED(T9e 4×u64；mul schoolbook；div/mod restoring binary long division `910835aa4`，runtime differential 待补) | LOWERED(T9e 4×i64；**mul 真 schoolbook NEAR lane**；div/mod/shift FC) | LOWERED(T13；add/sub/cmp/bit；mul/div/mod FC) | LOWERED(DPN 8×UInt32 LE limbs；bounded wide algorithms) | FAIL-CLOSED |

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
| ContextRead | **PARTIAL** | `unixTimeSeconds` OPEN（Env JSON time）；`blockHeight`→Env JSON bare-u64 `height`；`caller`→`MessageInfo.sender` 仅 instantiate/execute，query/view FC；`self`→`Env.contract.address` view-safe；`attachedValue`→`MessageInfo.funds` 单 denom `stake` execute/init，query FC；`chainId` FC（host 为 String，不静默哈希成 UInt64） |
| Commit · nonempty invariants · Field/Principal/String interface | **FAIL-CLOSED** | Bytes N state 已 LOWERED；Option UInt64 state 已 LOWERED（B-OPT-STATE）；iterator/IBC/migrate/reply entry 未开 |
| 制品 / 验收 | WAT + locked `wat2wasm` + `cosmwasm-check` 3.0.9 + cosmwasm-vm mock 48 tests + wasmd v0.70.3 Docker rung-1 | **非** 主网 / formal / hermetic |

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
| ContextRead | **PARTIAL** | `unixTimeSeconds` OPEN（`blockchain.now()`）；`attachedValue`/`chainId`/`self`/`caller` named no-host FC（T4 已 Admit Principal 存储，不映射 TON address） |
| Principal state/params | **LOWERED** | T4：9 叶 `owner_len`+`w0..w7` identity（≠ TON address）；return / caller→address 仍 FC |
| Commit · nonempty invariants · Field/String interface | **FAIL-CLOSED** | scalar `Op.Constant` 已 LOWERED（T3）；Option UInt64 state 已 LOWERED（B-OPT-STATE） |
| 制品 / 验收 | Tolk 1.4.2 → `.fif` + real BoC + `@ton/sandbox` 10/10（含 ScheduleFlow） | **非** 主网 / formal / hermetic |

## 1c. Quint Q0 executable-model 真实范围（第九 materializer）

| 面 | 状态 | 说明 |
|---|---|---|
| anonymous UInt64/Bool/Unit；public UInt64 state/params | **LOWERED** | 完整 UInt64 域 `oneOf(0.to(PF_MAX_U64))`；target-owned namespace |
| checked + − × / %、比较、Bool and/or/not | **LOWERED** | unbounded Quint int + success checks；div/mod 零值 guarded，first-failure code |
| StateLoad/StateStore、bare assert | **LOWERED** | 所有业务 store 只在 aggregate success 时提交；失败显式 outcome + state stutter |
| pureCall | **LOWERED** | target 内联；depth≤64、expanded op≤4096、checks≤128、单表达式 fully-expanded rendered node budget≤16384（含 div/mod guard duplication）；state/effect FC，未调用 pureFn 也完整验证 |
| zero-param public-Bool invariant | **LOWERED** | read-only single-block；发射为不依赖 `pf_last_*` instrumentation 的 `val` |
| Array/Option/Map state（齐次 UInt64 或 Int64） | **LOWERED** | N=1..8 Array flatten；Option tag+payload；Map cap-8 occ/key/val；元素/payload/key/value 跟随程序级 signedNumeric；无原生 List/Option/Map；错域混用 / entry return / N∉1..8 仍 FC |
| Bytes N state | **LOWERED** | N=1..8 UInt64 叶存低 8 位；IndexGet/Set 复用 Array 字面量下标；param/return/N=0 仍 FC |
| scalar `Op.Constant` | **LOWERED** | 经已有 `lowerLiteral`（UInt64/Int64/UInt32/Bool）；String/aggregate/Principal const 仍 FC |
| Principal state/params | **LOWERED** | T4：9×UInt64 identity 叶（`owner_len`+`w0..w7`）；pf.assets `transfer` 仍按 `.principal` 在 call site 重装；return / `context.caller`/`self` 仍 FC |
| named Struct/Enum state | **LOWERED** | T5：`p_x`/`p_y` 与 MaybeMark tag+payload 叶 flatten |
| Array/Option/named **view** 叶返回 | **LOWERED** | T6：view-only 元组/多 `int`（无原生 List/Option）；entry 聚合仍 FC |
| multi-block/if/match/for、Field/String | **FAIL-CLOSED** | Q0 不做语义近似；named entry return 仍 FC |
| event/nonzero revert payload/call/schedule/ContextRead/Commit | **FAIL-CLOSED** | zero-payload declared revert 保留 ErrorId（failure code=`256+id`）；resolver 仅 rollback/state/Bool/checked-arithmetic 四键 |
| 制品 / 验收 | `.qnt` + zero-tool finalize；host-optional exact Quint 0.32 typecheck + TS smoke | 不可部署；非 ITF/MBT/verify/Apalache/formal |

## 1d. Soroban / OpenVM / ICP 工程 MVP 真实范围

> 三列均已 registry-implemented。这里只钉诚实边界，不是 formal SupportClaim。

| Target | Profile | 已开 | 诚实 FC / 非声称 |
|---|---|---|---|
| **Soroban** | sole `soroban-source-u64-v1` | public UInt64/Bool/Unit Counter/StateCell `.rs`；4-key；zero-tool Finalize `deployable=false`；T3 scalar const 内联 + Bytes N（N UInt64 低 8 位叶）；**T4 Principal 9 叶 identity**（`owner_len`+`w0..w7`，≠ Address）；**T5 named Struct/Enum 叶 flatten**（`p_x`/`p_y`、MaybeMark tag+payload；`symbol_short` 只卡 state 叶）；**T6 Array/Option/named view 叶返回**（Rust `(u64, …)` 元组；entry 仍 FC） | auth/TTL/Wasm/stellar-cli；UInt64 ContextRead 四键 named no-host；`pf.crypto.*` / nativeVaultBalance named no-host；Principal / named entry return / `self`/`caller` 仍 FC |
| **OpenVM** | default `openvm-guest-source-v1`；opt-in `openvm-guest-elf-v1` | 受控 guest tree（O0 zero-tool）；O1 locked `cargo-openvm` 2.0.1 → ELF+`.vmexe` extras 仍 `deployable=false`；T3 scalar const 内联 + Bytes N；**T4 Principal 9 叶 identity**（≠ host address）；**T5 named Struct/Enum 叶 flatten**；**T6 Array/Option/named view 叶返回**（guest `(u64, …)` 连续写出；不新开 prove/IO ABI；entry 仍 FC） | keygen/execute/prove/verify；UInt64 ContextRead 四键 / `pf.crypto.*` / nativeVaultBalance named no-host；Principal / named entry return / caller 仍 FC |
| **ICP** | sole `icp-wasm-candid-u64-v1` | Counter/StateCell `.wat`+`.did`；locked wat2wasm `{name}.wasm` `deployable=true`；host-optional PocketIC；**CAP-1a** `unixTimeSeconds`→`ic0.time` ns÷10⁹（init/update/query）；T3 scalar const 内联 + Bytes N（N extra i64 globals，无 Candid `vec nat8`）；**T4 Principal 9 叶 identity**（9 extra i64 globals，无 Candid `principal`）；**T5 Option UInt64 2 叶 identity**（`o_tag`/`o_p0` extra i64 globals，无 Candid `opt`）；**T5 named Struct/Enum 叶 flatten**（extra i64 globals，无 Candid `record`/`variant`）；**T6 view 叶返回 = Candid 位置元组**（`.did` `-> (nat64, nat64) query`；WAT 连续 encode 多个 LE i64；**禁止** `record`/`opt`/`vec`/`variant`；entry 仍 FC） | PocketIC 不进 Finalize；sync+event FC；async advertise-only；Map 仍 FC（无动态 mux）；`blockHeight`/`attachedValue`/`chainId` / `pf.crypto.*` / nativeVaultBalance named no-host；Principal / entry aggregate / caller 仍 FC |

## 2. 验收/差分覆盖矩阵

| 验收门 | EVM | Solana | NEAR | Noir | Psy | Aleo | Quint | CosmWasm | TON | Soroban | OpenVM | ICP |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Plan canonicity (ValidatePlan) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| IR 结构验证 (ValidateIR) | ✅(M4) | N/A | N/A | N/A | N/A | N/A | ✅(structured Q AST) | N/A | N/A | N/A | N/A | N/A |
| 真实工具链编译验收 | ✅(EvmSolc: solc) | ✅(Mollusk runtime) | ✅(NearWasmAcceptance: locked wat2wasm + host-optional wasm-interp/wasmtime/wasmer load) | ✅(NoirCompileAcceptance: nargo 1.0.0-beta.26 compile-only；G123；缺席 skip；**非** prove/verify) | ❌ zero-tool direct DPN materializer；无 Dargo/compiler/runtime lane | ❌ zero-tool direct Aleo Instructions materializer；无 Leo/compiler/runtime lane | ❌ product toolchain；⚠️ host-only exact Quint 0.32 typecheck（非 Tool Lock/finalize） | ✅(locked wat2wasm + cosmwasm-check 3.0.9；**非** wasmd) | ✅(tolk 1.4.2 → real BoC；**非** 主网) | ❌ S0 zero-tool `.rs`；无 stellar-cli/Wasm | ⚠️ 默认 O0 zero-tool；opt-in O1 locked `cargo-openvm` ELF/VmExe（**非** prove） | ✅ locked wat2wasm `{name}.wasm`；PocketIC 不进 Finalize |
| 运行时差分 (Reference↔target) | ⚠️(G4 工程 Anvil 差分：Counter/Accumulator/ArithOps/EventFlow + caller/Ownable corpus；**非** formal C-3) | ✅(Mollusk 工程门 + ADR-0048 bounded HandlerIR↔sBPF observation；**非** formal Stage-0 / `.so`/validator) | ⚠️(WABT dummy env + near-sandbox 2.13.0 九套件，含 CallerCheck；非 Reference↔Wasm formal) | ❌ | ❌（DPN package emission only；无 local VM/proof） | ❌（Instructions emission only；无 VM/proof/network） | ⚠️(TS evaluator smoke；非 Reference differential/verify) | ⚠️(cosmwasm-vm mock 48 tests，含 CallerGate 7/7 + wasmd v0.70.3 Docker rung-1；**非** formal/主网) | ⚠️(@ton/sandbox 10/10 工程，含 ScheduleFlow；**非** formal/主网) | ❌ 无 local invoke | ❌ 无 keygen/execute/prove | ⚠️ host-optional PocketIC；**非** replica/mainnet/formal |

## 3. 工程轨道未实现 feature 全清单（A/B/C/D 组）

> 与项目全面审查报告对齐。每个缺口带 ID、现状、wave 归属。
> 闭合 = GAP→LOWERED 或 GAP→FAIL-CLOSED（显式拒绝 + 测试）。

### A 组：Normalize/语义面剩余缺口（跨 target 通用，最高优先）

这些缺口在 sole Normalize 层，影响所有 target；N 家族共享 NormalizeV1/ReferenceV1/EnvelopeV1，**必须串行**（一个 wave 一个）。

| ID | 缺口 | 现状 | 影响范围 | wave 归属 |
|---|---|---|---|---|
| **N-A1** | EVM String match-switch | **已闭合(EvmStringMatch)**：EVM Lower 将 `match String` desugar 为 leaf-wise eq + nested ifThenElse（Plan `switchOn` 仍仅 UInt64 case）；catch-all fallthrough；非 String aggregate switch 与非 String pattern 仍 fail-closed | EVM | EvmStringMatch ✅ |
| **N-A2** | 多臂同构造器 match 细化 | **已闭合(MultiArmCtor)**：Normalize 允许同外构造器多臂，子模式可区分时 first-match 嵌套 guard（nested ctor→VariantTag eq，nested lit→value eq；fallthrough→outer catch-all 或 trap.unreachable）；结构 pattern key 重复（bind≡wildcard、ctor by vIdx、lit by valueBytes）仍 fail-closed；TypeCheck 同源 duplicate pattern 诊断；六 target 经 sole Normalize 继承 | 全 target | MultiArmCtor ✅ |
| **N-A3** | Map/Bytes 穿透元素赋值 | **已闭合(MapBytesAssign)**：TypeCheck/Normalize 单步 `m[k]:=v`/`b[i]:=u8` → IndexSet（load→set→store）；Reference 已有 Map/Bytes step。target 覆盖非均匀：EVM Map+Bytes、Solana Map、NEAR Map 与 fixed Bytes state、Noir Map、Aleo Map+Bytes 已部分 LOWERED，Psy 与其余组合按上表 FAIL-CLOSED；五个 Map-capable target 的 aggregate StateStore snapshot hazard 已修。**Map 整程序 Reference admission（2026-08-07）** 已切 per-canonical-value/helper Wire envelope（无 sampled packing/第二 runtime capacity；empty state default exact 4B；whole-step cumulative work 仍 residual）；**MiniAmm `Map Principal UInt64` Normalize→admit 已通**（runtime upsert 仍 Wire 实际 limits）；**嵌套穿透** `m[k].x:=v` 仍 fail-closed | 全 target Normalize；target 见 op 表 | MapBytesAssign + B-SOL-MAP-UPSERT ✅ |
| **N-A4** | Option state | **shared 闭合**：Normalize+Reference default none；十二 materializer 均 Admit `Option UInt64` 2 叶 tag+payload state（T5 补 ICP：两个 extra i64 global，无 Candid `opt`）；Option return / params / 非 UInt64 / nested 仍 FC；ICP Map 仍 FC | 全 target | OptionState ✅ + B-OPT-STATE ✅ + T5 |

### B 组：各 target 的 Plan/IR/emitter 覆盖缺口

#### B-1：跨 target 聚合/容器覆盖不均（最高优先，可并行——按 target 文件分隔）

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **B-1a** | NEAR 聚合与容器 | **闭合（L1 + follow-ups）**：Array UInt、dense Map cap-8、fixed Bytes N、**named Struct/Enum** 与 `Option UInt64` state 已 flatten-to-KV（construct/fieldGet/fieldSet/variant ops + atomic storeAtomic；HostModel 端到端）；named 与 anonymous Array/Option ≤8-leaf aggregate return 已由 B-RET-ABI/N-ANON-RESULT 开放 | NearAggregate + NS-1 + Bytes + L1 + BL-30 |
| **B-1b** | Noir named 聚合 | **闭合(NoirAggregate + L3)**：named Struct/Enum + **Map UInt64 / Map UInt64 Int64 dense pilot**（cap-8 occ/key/val multi-leaf PI + IndexGet→Option + IndexSet；val slots `inputType .i64`；`storeAggregate` 两阶段 snapshot 与 empty-upsert relation model）+ **Array UInt64 / Array Int64 state flatten** + **Option UInt64 / Option Int64**（tag `.u64` + payload `.i64`）+ **fixed Bytes N**（N×UInt8 leaves、literal IndexGet/Set、atomic store）；Bytes construct/param/动态索引、Int8 容器、Int64-key Map、Int64 container return 与 nested 仍 FAIL-CLOSED | NoirAggregate + NoirMap + NoirContainer + MapSnapshot + L3 ✅ |
| **B-1c** | Aleo 全功能 | **AleoCoverage + H3/NS-1/Bytes/Int64/T14 + G123 + BL-35 + ALEO-I1–I4 + ALEO-INT64-CONTAINERS**：标量、named Struct/Enum、Array UInt64 **or Int64**、dense Map cap-2（UInt64 **or Int64** val，6 叶）、fixed Bytes N、**Option UInt64 or Int64 state**、Commit 身份透传与 **BLS12-377 Fr** 已 LOWERED；Map aggregate StateStore 以 get-all-before-set two-phase 修复 empty upsert。Plan content digest 已进入 identity chain；产品另发 content-bound query-contract sidecar（bare mappings/views/resultDropped，非 executable query）。bn254/Goldilocks、Option params/Int8 containers/Int64-key/Int64 container return/nested/String/ContextRead/externalCall/schedule/emit/pf.assets 仍 FAIL-CLOSED。Principal 9-leaf wire identity（≠address）已 LOWERED；return / caller→address 仍 FC。Leo 4.0.2 两平台 Tool Lock + locked-only acceptance + opt-in product compile finalization；无 VM/prove/deploy 门 | AleoCoverage + T14 + MapSnapshot + G123 + B-OPT-STATE + ALEO-I1–I4 ✅ |
| **B-1d** | Solana Map/Bytes/Option state | **Map pilot + L2 + BL-29 已闭合**：Map 已进 ELF+Mollusk；named Struct/Enum、fixed Bytes N 与 `Option UInt64` state 已 flatten；`storeAggregate` structural CSE + `storeStateMulti` 固定 pre-store snapshot，峰值 177 temp/1424B，`put_into_empty` 已解除 ignore；Option state 6 项 Mollusk 通过；Option params/非 UInt64/nested、Bytes construct 与动态索引仍 FAIL-CLOSED | SolanaMapPilot + B-SOL-MAP-ELF + B-SOL-MAP-UPSERT + L2 + BL-29 ✅ |
| **B-1e** | EVM Map/Bytes/Option state | **闭合(Map pilot + BL-31)**：Array + Bytes + **Map UInt64 cap-8** + `Option UInt64` state 进入 locked-solc engineering finalization（`deployable=true` 仅为制品标志；Token creation bytecode 现约 2.6 KiB，已低于 EIP-3860；chain/Anvil/OZ 产品门另计）；aggregate `storeAtomic` 保证 leaf Expr/sload 全先于 sstore；Option params/非 UInt64/nested 仍 FC | EvmMapPilot + MapSnapshot + B-EVM-MAP-STACK + BL-31 ✅ |

#### B-2：Normalize 语义细化（= A 组，N 家族串行）

见 A 组 N-A1/N-A2/N-A3/N-A4。

#### B-3：call/schedule 的 address-bearing 类型

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **B-3** | Principal→address 映射 | **已闭合为 FAIL-CLOSED 研究钉（PrincipalAddr, 2026-08-02）** + **AddressBearing followup：EVM static-callee open；Solana legacy 已 #111 fail closed（2026-08-03）** + **T10 EVM Principal storage pilot（2026-08-02）** + **T12 Solana/NEAR/Noir Principal storage pilot（2026-08-02）** + **EVMOZ-003 / ADR-0025（2026-08-03）冻结 EVM `context.caller` encoding，不改 B-3 pin**。Principal valueBytes = `u32le(len)\|body`（`1≤len≤4096`）共享 wire **不变**；**无** approximate 任意 Principal→address 映射，**无** Address TypeShape。ADR-0025 规定：EVM ContextRead caller 结果 **仅** `u32le(20)\|\|CALLER`（network-order 20B）；**2026-08-06 S1-EVM Plan 已开**（`callerPrincipalWord` + Anvil/corpus）；**非均匀 ContextRead** 见 §1 `contextRead` 行（EVM unixTime+blockHeight+caller；Solana exact CPI caller-only、legacy FC；NEAR unixTime+blockHeight+init/entry caller；CW unixTime+blockHeight+instantiate/execute caller；TON unixTime；Noir/Psy/Aleo 全 FC）；不解锁 Solidity `address` ABI / dynamic CALL / Ownable F01 全 OZ 信用。T10/T12 在 EVM/Solana/NEAR/Noir 开放 **wire identity 原样 leaf 存储**（`pilotPrincipalPolicyAdmit`；len+8×UInt64，≤64B body，与 N4 String 同构；非 20B address / 32B pubkey / account-id / Field）；Aleo/Psy 保持 `pilotPrincipalPolicyNone`。产品 `call`/`schedule` 为 wire `Op.ExternalCall`/`Schedule` 的 **static `QualifiedName` callee**（非 ValueId 地址）。AddressBearing 打开 EVM/Solana 双 call 键：EVM Plan `externalCall`/`schedule` → Yul `CALL` 至 `keccak256(targetPath)` 后 20 字节 + method selector；Solana Plan/IR `externalCall`/`schedule` → program id = SHA-256(targetPath) 32B，plan 文本 `external_call`/`schedule`，SBPF 以 `sol_log_data` 观测桩（完整 `invoke_signed` CPI 需 account metas，另排）。NEAR 仍拒 sync；Noir 七键不变 | PrincipalAddr ✅ + AddressBearing ✅ + T10/T12 storage ✅ + ADR-0025 encoding ✅（Plan open 见 B-CTX-OPEN） |

#### B-4：验收门升级（= C 组）

见 C 组。

### C 组：工程验证缺口（验收门升级）

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **C-1** | NEAR Wasm 运行时差分 | **已闭合工程子集**：`NearWasmAcceptance` 将产品 Counter/DualField/LoopSum `.wat` 交给 locked `wat2wasm` 编译，并以 host-optional `wasm-interp`/`wasmtime`/`wasmer` 做 runtime load；后续 **C-6/G123** 又以 locked near-sandbox 2.13.0 对 Counter 做 deploy/init/mutate/view receipt 工程验收。工具未物化或 host runtime 缺席时 clean skip；两门都**不是** formal Reference↔Wasm/sandbox 差分或 Stage-0 证据 | NearWasmAcceptance + NearSandboxAcceptance ✅ |
| **C-2** | Aleo/Psy compiler/VM 验收研究 | **历史研究闭合，产品 lane 已删除（ADR-0035，2026-08-10）**：Aleo 仅保留 `aleo-instructions-v1` direct canonical Instructions + query descriptor；Psy 仅保留 `psy-dpn-v1` direct canonical DPN package。Leo/Dargo compiler、local VM/proof、network wrapper、compiled extras、对应 Tool Lock 与 acceptance/runtime recipes 均不再属于产品或工程执行面。RPT-015/RPT-024 只保留历史实验事实，不是当前入口。两 target 均 zero-tool、`deployable=false`、无 runtime/formal refinement。 | DirectNativeCutover ✅ |
| **C-3** | EVM Reference↔Anvil formal differential | EVM 有 solc 验收 + G4 工程 Anvil 差分，formal Reference↔Anvil closure 仍缺 | EvmAnvilDiff（formal 轨道，按既定决定不做） |
| **C-4** | Noir prove/verify 验收门 | **prove/verify 研究结论仍为不升格**：G123 已将 nargo 1.0.0-beta.26 纳入两平台 Tool Lock，并由 `NoirCompileAcceptance` 对产品 Counter relation packages 做 compile-only 验收；但 Barretenberg/backend、CRS/security profile、witness/prove/verify 与 proof artifact binding 均未锁定，`validate_artifacts` 继续拒绝 proof-stage 叶子。成熟度保持 **source-only** relations；后续仅余独立 `NoirProveAcceptance` 决策与实现 | NoirProveResearch + NoirCompileAcceptance ✅（prove/verify 仍未实现） |
| **C-5** | Solana Mollusk fixture 跟 Normalize 新面 | **ongoing**：tracked runtime inventory 为 24 integration test binaries / 418 active tests，覆盖 legacy Counter/fixture ELF、active CPI product programs、TransferSol 与 CallerIsMe。legacy `CpiCaller` 已随 #111 退役；真实 CPI 仅 exact `solana-sbpf-cpi-elf-v1`。CallerIsMe 8/8 固定 `pf_caller` signer→Principal；MapMini/WideMul/PrincipalStore/OptionState 与 pf.assets suites 保持 active；WideDiv/WideDiv256 8 个独立数值/零除回滚 oracle，WideDivDispatch 1 个组合长距 handler runtime pin；`block_height` 4 测钉 `context.blockHeight` → `sol_get_clock_sysvar` Clock.slot（warp 双 slot 非常量 + stamp/get；≈400ms 物理 slot，非逻辑块号）；`sha256_check` 4 测钉 `pf.crypto.sha256` → `sol_sha256`（UInt256 LE word `0`/`1` known vectors + store/get + assembly honesty）。该门仍非 formal Stage-0 / Reference closure | MolluskFixtures |

### D 组：文档/checkpoint 同步缺口

| ID | 缺口 | 现状 | wave 归属 |
|---|---|---|---|
| **D-1** | registry target 表 | **已随 ICP ADR-0047 刷新**：engineering seed = **12 implemented + 0 design-only**（`evm`/`solana`/`near`/`noir`/`aleo`/`psy`/`quint`/`cosmwasm`/`ton`/`soroban`/`openvm`/`icp`）；十二 materializer 均有 Plan/IR/dispatch；resolver 15 rows（EVM×2、Noir×2、OpenVM×2、其余各一）。ADR-0036 固定 accepted Phase-1 四-target 不静默扩面，formal lighthouse=EVM-first | MatrixSync + ADR-0044/45/46/47 |
| **D-2** | 成熟度声明 | **已闭合并随 ADR-0035 + 后三 target 刷新**：EVM locked solc + G4 Anvil 工程差分；NEAR locked `wat2wasm` + near-sandbox receipt；Solana SBPF+Mollusk；Noir locked nargo compile-only；Aleo sole `aleo-instructions-v1` zero-tool Instructions；Psy sole `psy-dpn-v1` zero-tool DPN；**CosmWasm** WAT+wat2wasm+check+mock + wasmd rung-1；**TON** Tolk/BoC+sandbox；**Quint** `.qnt` zero-tool；**Soroban** S0 source-only `.rs` zero-tool（auth/TTL/Wasm FC）；**OpenVM** O0 guest-source zero-tool + opt-in O1 locked `cargo-openvm` ELF/VmExe（prove FC）；**ICP** locked wat2wasm `.wasm`+`.did` + host-optional PocketIC。以上均**非** formal/hermetic/Stage-0 maturity | MatrixSync + ADR-0044/45/46/47 |

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
- **AddressBearing**（B-3 followup）：**EVM static-callee open；Solana legacy 已 #111 fail closed** — research 确认 callee 为 static QN 非 dynamic address；EVM resolver 七键 + Plan/IR/emitter 打开；Solana legacy 删除双 call 键且 Plan/IR/SBPF 拒绝旧节点；真实 CPI 见 epic #110；任意 Principal→address 仍 fail closed
- **EVMOZ-003 / ADR-0025 EVM caller encoding**：**encoding 决策已 accepted** — EVM `context.caller` = `u32le(20)||CALLER`；shared wire 不变；**S1-EVM Plan 已原子 cutover（2026-08-06）**；不解锁 address ABI / Ownable F01 全 OZ 信用 / 他 target 自动镜像
- **T10 EVM Principal storage**：**已闭合** — EVM `pilotPrincipalPolicyAdmit` + N4-isomorphic leaf storage（len+8×UInt64）；params/state/eq/ne；非 address；多宽 return 仍 fail closed
- **T12 NEAR/Solana/Noir Principal storage**：**已闭合** — 三 target `pilotPrincipalPolicyAdmit` + 同构 9-leaf layout（Solana account pitch / NEAR 9×KV / Noir 9×u64 inputs）；params/state/eq/ne；非 pubkey/account-id/Field；多宽 return 仍 fail closed；**Aleo T3** 已开同构 9×u64 identity（≠address/Field；return FC）；**T4** 已开 TON + Quint/Soroban/OpenVM/ICP 同构 9 叶（ICP 为 9 i64 globals，无 Candid `principal`；return / caller 仍 FC）；**Psy PSY-SCALAR-ABI（2026-08-08）** 另开 wire-identity `len`+8×UInt32（max 32B；非 address；return FC）
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

> **Solana CPI epic #111–#125 engineering closed** (#110 engineering epic complete): legacy profiles fail closed on call/schedule; exact `solana-sbpf-cpi-elf-v1` advertises sync+extension (async still FC); CpiEscrowIRV1 composite escrow remains test-preactivation history; product activation is ordinary-resolver product capability (not formal TASK-D5).
