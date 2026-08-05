---
id: TARGET-COSMWASM
title: CosmWasm target dossier
status: draft
owner: architecture
updated: 2026-08-04
normative: true
---

# Target Dossier：CosmWasm

状态：`draft`
Target ID：`cosmwasm`
工程 MVP：**已实现**（2026-08-03，见 §0；此前 A0→隔离→修复/design-exit 的完整过程见 §0.1）。
**Engineering only**——**非** accepted PRD Phase 1 四目标范围；accepted scope reconciliation
见 **`DOC-ADR-SCOPE`**。

## 0. 工程状态（2026-08-04，当前）

**已实现（engineering MVP）**：registry implemented（profile
`cosmwasm-wasm-u64-v1`，maturity `wasm-validated-alpha`）；`Targets/CosmWasm/**`
target-owned Plan/IR/WAT emitter（KV state→`env.db_*`、init/entry/view →
`instantiate`/`execute`/`query`、有界 JSON、emit attributes、revert
`ContractResult::Err`、if/match/bounded for/pureFn、checked arithmetic/bit ops）。Finalize
经 locked `wat2wasm` 产 `{name}.wasm`；`cosmwasm-check 3.0.9` 对 fixtures 与产品制品做
静态 ABI 验收。

**后续工程扩面**：UInt8/16/32 state/param/result 与 body narrow guards 已开（物理 KV 仍为
8-byte LE 并检查高位；UInt128/256 与窄 Int FC）；named Struct/Enum state、`Array UInt64 N` state 与 dense `Map UInt64 UInt64` cap-8 state 已开；≤8 个
UInt64/Int64 leaf 的 named entry/view aggregate return，以及 anonymous `Array UInt64 N`
（1..8）/`Option UInt64` entry/view return 已开。Map/Bytes return、Option/Bytes state、
nested/非 UInt64元素、aggregate param/pureFn仍 fail closed。

**runtime rungs**：`runtime-tests/cosmwasm` 的 cosmwasm-vm 3.0.9 mock 当前有 28 个
`#[test]`，覆盖 Counter/Accumulator/EventFlow、hardening、ScheduleFlow、NarrowCounter、
PairRet、ArrayRet、OptionRet；另有 `scripts/cosmwasm_wasmd_test.sh` 的 wasmd v0.70.3
Docker 工程 rung，覆盖 Counter 与 ScheduleFlow 子消息失败导致 whole-tx abort。两者都不是
主网、formal 或 hermetic evidence。

**schedule**：`schedule` → `SubMsg{reply_on:never,id:0,WasmMsg::Execute}`；`msg` 已由
CW-6 升级为 UTF-8 method JSON 的 Binary/base64。它仍是同事务 savepoint 分发（非跨 tx
async），子消息失败打爆整笔交易；`contract_addr` 为静态 QN stub，无 reply entry。sync call
继续 resolver+Plan 双拒（**但见下：pf.assets sync bank 已开**）。

**`pf.assets` sync binding（ADR-0029 Phase C1，2026-08-05）**：resolver advertise exact
`extension.pf-assets` + `effect.synchronous-call`（后者仅覆盖 pf.assets catalog；generic
非 catalog sync call 在 Plan 层继续 fail closed）。`pf.assets.native.deposit` →
`info.funds` 恰好一枚 `{denom:"stake", amount}` 的 exact 校验（多/零/错 denom/错 amount
均 trap；无 deposit 的 entry/init 要求 funds 为空）；`pf.assets.native.transfer` →
`BankMsg::Send` SubMsg（`reply_on=never`：**error-propagating**——submsg 失败打爆整笔
交易，与 CW-4 async schedule 同 reply 模式但语义契约不同；不用 ReplyOn::Error 因它需要
reply entry 且允许父合约继续，弱于 sync failure-propagation 契约）；dst Principal 运行时
须 exact `u32le(len)||utf8-bech32-bytes`（len∈1..64 且高位清零）。单一冻结 denom
`stake`（多 denom/资产实例身份归 NetworkProfile asset registry 后续）。token/async QN
保持 FC。cosmwasm-vm mock 新增 `tipjar.rs`（deposit/transfer/四类 funds 负例，1/1）；
产品纵切 `Tests/Product/TipJarCosmWasmV1`（WAT + locked cosmwasm-check + exact closure）。

**`pf.assets.token.transfer` binding（ADR-0030 E1-CW，2026-08-05）**：payload 不变的
per-target 绑定。→ CW20 `Transfer` execute 作 `WasmMsg::Execute` SubMsg
`reply_on=never`（error-propagating 同 C1；CW20 调用失败打爆整笔交易）；mint/dst
均 exact `u32le(len)||utf8-bech32-bytes`（受控动态 callee，仅 catalog token 家族；
generic dynamic callee 仍 FC）；funds 为空、entry 非 payable（C1 funds-exactness
不变）；合约自身 CW20 余额即 vault；`token.transferAsync` 保持 FC。**bech32
charset 安全门**：emitter 对 mint/dst body 强制 lowercase `[a-z0-9]`（C1 文档原称
"printable ASCII" 未实现且不足以防 JSON 注入——现按构造排除引号/反斜线/控制字节，
覆盖 C1 native dst 与 E1-CW mint/dst 三路；注入负例 `tipjar.rs`/`tokenjar.rs` 全过）。
cosmwasm-vm mock 新增 `tokenjar.rs`（CW20 SubMsg shape + base64 解码 payload、tips
状态、非 payable/畸形 wire-shape/charset 负例、no-BankMsg 诚实门，6/6）；产品纵切
`Examples/TokenJar.lean`（`cosmwasm_runtime_test.sh` 产品构建）。诚实上限：mock
不分发 SubMsg 到真实 CW20 合约（cw-multi-test 不能宿主裸 Wasm），CW20 余额差值属
wasmd rung 未声明；**非** formal/mainnet parity。

**仍 fail closed / 未闭合**：iterator、IBC、migrate、reply entry、Option state、Map/Bytes
return、Field/Principal/String interface、ContextRead/Commit、nonempty invariants、UInt128/256、
narrow Int、JSON 全集与 gas model。wasmd smart query 当前仍非 Binary，rung-1 harness 使用 raw state。

## 0.1 A0→隔离→修复/design-exit 过程记录（2026-08-03）

commit `dd607de72` 先把 CosmWasm 标为 engineering registry `implemented`（profile、
descriptor、resolver row），但当时**没有** target-owned Plan/IR/emitter，产品
`build --target cosmwasm` 仍 `PF-TARGET-NOT-IMPLEMENTED`。未合入候选 `48e8bffad`
（A1 emitter）经三路只读审计判为不可合：流程上缺少 ABI/scope 授权（dossier §6/§10 的
design-exit 未完成、`SRC-CW-002` 仍 provisional），代码上认定静态内存布局重叠、JSON
UInt64 溢出 wrap、Int64 `min × -1` 漏 guard、attribute/heap 无界四类 P0 候选，另发现
产品 build soft-skip acceptance。随后：四个 P0 经独立复核全部属实并已修复（各配运行时
与 Plan 钉测，另清除 dead code、验收硬化为硬失败）；`CW-ABI-FREEZE` 的完整
design-exit 已交付（§6 版本冻结 + §10 批准 structural-WAT 工程先导 + `SRC-CW-002`
升级 verified + `SRC-CW-003/004` 与 `CLM-CW-001..004` 登记）。`DOC-ADR-SCOPE`
（accepted 四目标 vs engineering registry implemented target 扩大）决策债另行跟踪。

## 1. 身份与来源

CosmWasm 是 Cosmos SDK `x/wasm` 合约环境，强调 Cosmos modules 与 IBC 集成；官方总览见 [CosmWasm Documentation](https://cosmwasm.github.io/)（`SRC-CW-001`，verified）。transaction/SubMsg/reply 语义已按 wasmd v0.70.3 pinned dispatcher 冻结（`SRC-CW-002`，verified；`SRC-CW-003/004` 同步 verified）。

## 2. 执行、状态、调用、失败与资源

- 执行：固定 instantiate/execute/query/migrate/reply 等 entrypoint 与 JSON messages。
- 状态：合约实例前缀隔离的 KV store。
- 调用：返回 CosmosMsg/SubMsg，可能触发 reply；IBC 是协议化异步交互。
- 失败：transaction rollback、submessage error/reply/savepoint 的精确边界必须随 runtime profile 固定。
- 资源：Cosmos gas、Wasm gas、storage 和链定制模块共同决定。

## 3. Portable fragment 与扩展

Portable 候选：Cell/Map、JSON entry/query、checked arithmetic、event attributes、sender、funds、transaction-local failure。

扩展：CosmosMsg、SubMsg/reply policy、bank/staking/custom module messages、IBC packet/ack/timeout、migrate/admin、chain query。每种 custom message schema 属于 target semantics/CodegenProfile exact 引用的版本化 extension；NetworkProfile 只能声明兼容 BuildIdentity，不能定义 schema。

## 4. `CosmWasmPlan` schema

```text
CosmWasmPlan {
  profile, entrypoints, jsonSchemas,
  storageSchema, hostImports,
  responseMessages, submessages, replies,
  ibcHandlers, events, errors, gasAssumptions
}
```

Plan 必须表达 SubMsg id、reply policy、result decoding 与保存点；不能复用 `NearPlan` 的 Promise DAG。

## 5. Target IR 与制品

```text
CosmWasmPlan → CosmWasm IR (WAT recipe) → locked wat2wasm → {name}.wasm
  + cosmwasm-check@3.0.9 static ABI 门
  + cosmwasm-vm@3.0.9 mock runtime 差分（engineering）
```

工程制品：WAT 文本、Wasm、JSON message 形状、manifest/evidence。`cosmwasm-check` 与
mock VM 均为工程验收，**不是** wasmd 链上 runtime 或 formal 差分。migration metadata /
IBC handler 未接线。

## 6. 工具链（已冻结，2026-08-03 / CW-ABI-FREEZE 闭合）

**版本冻结（versioned profile，唯一权威）**：合约侧 `cosmwasm-std`/`cosmwasm-vm`/
`cosmwasm-check` **3.0.9**（monorepo tag，sha256 快照见 SRC-CW-003/004）；链侧语义以
`wasmvm` **3.0.7**（官方 checksums）与 wasmd **`v0.70.3`** 的 `DispatchSubmessages`
为准（SRC-CW-002 已升级 verified；`v0.61.14`（SDK 0.53 主流线）与 0.70.3 同控制流，
择 0.70.3 为文档基准）。**Rust-independent Wasm ABI**：单 memory 无 maximum、
`allocate`/`deallocate`、恰好一个 `interface_version_8` marker、entry 经 12B Region
传 JSON（SRC-CW-004 pinned `compatibility.rs`）。**allowed capabilities（MVP）**：
仅默认 KV（`db_read/db_write/db_remove`）与 `abort`；`iterator`/`staking`/`stargate`/
`cosmwasm_1_1..3_0`/`ibc2` 全部不声明（`requires_*` 导出全部缺席）。
**schema conventions**：消息/状态为 JSON；工程先导实现有界最小 JSON 子集
（flat instantiate 参数 + `{method:{decimal params}}`，非子集显式 Err）；CW-6 已将
SubMsg `msg` 冻结为该 inner JSON 的 Binary/base64，query response 的完整 Binary 兼容仍未闭合。**transaction/SubMsg/savepoint 语义（已按 pinned 源固定）**：
子消息经 `CacheContext` savepoint 执行，成功 commit、失败丢弃子状态与事件；
`reply_on=Never`/`reply_on=Success` 遇失败**直接把错误返回父 dispatch、整笔交易失败**
（父状态随 tx 回滚，**不是**「父继续」）；`reply_on=Never` 与 `reply_on=Error` 成功
时不回调（wasmd v0.70.3 `msg_dispatcher.go` L96–147，SRC-CW-002；事件 attribute 链侧
稳定排序、非确定性错误文本 redact 为 codespace/code）。

## 7. 部署流程

预期 gate：本地链 store code → instantiate → execute/query → SubMsg success/error/reply → migrate。每一步保存 tx/event/state evidence；IBC 另需双链 harness。

## 8. 安全

重点是 reply/savepoint 误建模、custom message schema confusion、fund denom/amount、address validation、IBC timeout/replay、migration admin、iterator determinism 和 gas amplification。

## 9. 验证阶梯

official ABI fixture → Wasm VM static validation → `cosmwasm-vm` unit → local `wasmd` transaction/reply → optional IBC two-chain evidence。当前进度：fixture ✓（A2）、static `cosmwasm-check` ✓（A2）、`cosmwasm-vm` mock unit ✓（CW-3）、wasmd v0.70.3 Docker Counter/ScheduleFlow rung-1 ✓（CW-9）；reply entry、完整 tx corpus 与 IBC 未做。

## 10. 不支持、风险与成熟度退出

**设计退出已完成（CW-ABI-FREEZE，2026-08-03）**：versioned profile 已按 §6 冻结并批准
**structural-WAT 工程先导**（bounded ABI subset：§0 所列 MVP 面）为首个 accepted
implementation profile。`wasm-validated-alpha` 的声明就此限定为：WAT 文本 + locked
`wat2wasm` 制品链 + `cosmwasm-check@3.0.9` 静态 ABI 验收 + `cosmwasm-vm@3.0.9` mock
runtime 差分，并有 wasmd v0.70.3 Docker 的 Counter/ScheduleFlow 工程 rung-1；**不**含
主网、reply entry、IBC、JSON 全集、formal 或 hermetic 完成态。A1 独立审计四个 P0（静态
内存重叠/JSON 溢出/Int64 min×-1/缓冲区无界）已修复并钉测；`SRC-CW-002` 已由
provisional 升级 verified，`SRC-CW-003/004` 同步登记。剩余风险：SubMsg `msg` 已是
Binary/base64，但 `contract_addr` 仍为静态 QN stub；smart-query Binary兼容与 gas 计量模型
未进入验收。
