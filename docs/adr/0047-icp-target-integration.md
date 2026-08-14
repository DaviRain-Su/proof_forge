---
id: ADR-0047
title: ICP（Internet Computer canister / Wasm actor）capability-gated target 集成
status: proposed
owner: architecture
updated: 2026-08-13
normative: true
---

# ADR-0047：ICP capability-gated target 集成

## 状态

proposed

## 背景

[`docs/targets/06-icp.md`](../targets/06-icp.md) 与 research 源
（`SRC-ICP-001..004`）早已登记 Internet Computer canister 为 Wasm **actor**
宿主：System API、Candid、heap/stable memory、cycles、update/query 分界，以及
inter-canister `await` 造成的 **message commit 分段**。仓库轴已存在
（`icpCanister` / `awaitSegmented` / `canisterHeapStable` / `asynchronousActor` /
`icpSubnet`），但 `TargetRegistryV1` 仍将其标为 design-only，且 **ADR-0036** 将
Soroban/ICP/OpenVM 锁在 design-only 集合。

ICP 与 NEAR/CosmWasm **同为 Wasm 制品容器**，但宿主语义不可共享（ADR-0007）：
- NEAR：receipt-local + Promise DAG + account KV
- CosmWasm：transaction savepoints + SubMsg/reply + Cosmos KV
- ICP：await-segmented + asynchronous actor + canister heap/stable + Candid/Principal

因此不得把 ICP 做成「NEAR/CW Plan + 不同 imports」。语义上更接近 TON 的
`asynchronousActor`（纯异步跨合约；sync call 必须 fail closed），但结算与状态
绑定仍是 ICP 私有（subnet / canister memory），不得复用 TON Plan/IR。

本 ADR 把 `icp` 提升为 **第 10 个 capability-gated engineering materializer**
（registry **12 = 10 implemented + 2 design-only**），并采用与 TON-1（ADR-0024）
相同的两片落地：先冻结身份/capability/制品边界（ICP-1），再交付 target-owned
Plan/IR leaf（ICP-2）与 local replica / PocketIC 工程门（ICP-3）。

## 决策

1. **身份与归类**：`TargetId.icp`；family 阅读视图 = Wasm artifact/host，但
   **Plan/IR 为 ICP 独占**（ADR-0007）。六轴保持既有 registry seed：
   `ExecutionHostV1.icpCanister`、`CommitModelV1.awaitSegmented`、
   `StateBindingV1.canisterHeapStable`、`CallModelV1.asynchronousActor`、
   `ProofModelV1.noProof`、`SettlementModelV1.icpSubnet`。
2. **Registry**：`icp` 由 design-only 提升为 implemented；sole profile
   `CodegenProfileId.icpWasmCandidU64V1`（wire `icp-wasm-candid-u64-v1`）；
   acceptance `phase1.icp-u64.v1`；maturity 初标 `source-only`（ICP-2 leaf 与
   Wasm/Candid 制品验收前不声明 `wasm-validated-*` / runtime / deployable）。
   design-only 剩余 `soroban` / `openvm`（2）。**Accepted PRD Phase 1 仍为四目标**；
   本扩面是 engineering leave，不静默改写 accepted 范围（ADR-0036 后果由本 ADR
   修订为 10+2）。
3. **Capability（honest 子集）**：
   - **开**：`state.persistent`、`value.checked-arithmetic`、`value.bool`、
     `failure.atomic-rollback`（**仅单 message 内**可回滚更新；已发出的
     inter-canister 消息与此前 commit 边界不得伪装成全事务原子）、
     `effect.asynchronous-workflow`（inter-canister / 分段 continuation 的
     未来 Plan 入口；ICP-1 可先 advertise、ICP-2 Plan 对未实现 shape fail closed）。
   - **关**：`effect.synchronous-call`（ICP 无 sync inter-canister；禁止把
     await/callback 伪装成 CALL）。
   - **关（MVP）**：`effect.event`（无 portable 一等事件总线；不得把 trap/reject
     或任意 log 别名成 `emit`）。后续若冻结 candid/log 映射，另开切片。
4. **ArtifactEncoding**：新增 `ArtifactEncoding.icpWasmCandid`（Wasm module +
   `.did` Candid 服务描述为配对制品面）。共享层仅 deterministic Wasm
   AST/encoder/结构校验；Candid、System API imports、stable layout、cycles 与
   upgrade hooks 留在 ICP Plan。
5. **落地切片**：
   - **ICP-1（本 ADR）**：registry/descriptor/resolver/CLI list-inspect 控制面；
     `install` 将 `icp` 视为 zero-tool implemented（同 Aleo/Psy 空工具表）；
     `materializeResult` 在 ICP-2 前对 `.icp` **显式失败**（清晰错误，无静默
     降级、无复用 Near/CosmWasm Plan）。
   - **ICP-2**：target-owned `IcpPlan` / IR → Wasm + `.did`；Counter 窄子集
     （public UInt64 state、init/update/query、checked +/-、message-local trap）；
     **无** upgrade / timers / HTTP outcalls / management canister / certified
     data；inter-canister 仅在 capability 已开且 Plan 形状冻结后按 continuation
     显式建模。
   - **ICP-3**：冻结 interface-spec revision + local replica / PocketIC 工程门
     （非 formal、非主网、非 Stage-0）。
6. **Principal / ContextRead（后续，非本 ADR 闭合）**：`context.caller` 的 ICP
   realization（`ic0.msg_caller_*` → portable Principal wire）与
   `ic0.time()` 等键按 ADR-0031 逐行开 leaf；无 exact counterpart 的
   `blockHeight` / `chainId` 保持 fail closed。
7. **不做（本 ADR 明确排除）**：复用 Near/CosmWasm/Soroban Plan；GenericWasmHostPlan；
   sync call 别名；把 message-local rollback 写成跨 await 全事务原子；dfx 作为
   编译语义来源；formal TASK/TST、hermetic、release qualification、accepted PRD
   扩面。

## 理由

- Actor/await 分段提交是 ICP 相对其它 Wasm host 的不可压缩差异；先冻结身份与
  honest capability，避免 leaf 用 NEAR/CW 捷径污染控制面。
- 与 TON 同属 `asynchronousActor`，可复用「sync FC / async 一等公民」的产品纪律，
  但制品与状态仍走 Candid + canister memory，必须独立 Plan。
- 两片落地降低一次 PR 的 blast radius：ICP-1 可测 registry/resolver/list；
  ICP-2 专注 Counter 物化。

## 影响

- `TargetRegistryV1`：10 implemented + 2 design-only；engineering registry root
  bytes/digest 钉测更新。
- `RequirementResolverV1`：新增一行 `icp` × `icp-wasm-candid-u64-v1`。
- `DescriptorDataV1.icp` + `ArtifactEncoding.icpWasmCandid`。
- CLI/`scripts/proof_forge_install.py`：`icp` 移出 design-only；ICP-3 后
  `local --target icp` → `scripts/pf_icp_test.sh`（PocketIC host-optional）。
- ADR-0036 工程范围陈述修订为 **10 + 2**（本 ADR 为扩面决定）。
- formal D1–D4 / accepted PRD / Stage-0 状态不变。

## 否决方案

- 保持 design-only（拒绝：axes/dossier/research 已足够支撑 engineering leave，
  且 branch `feature-icp` 的产品意图就是落地）。
- 「NEAR Wasm + ic0 imports」或共享 host Plan（拒绝：ADR-0007）。
- 一次性交付完整 async workflow + upgrade + cycles + management（拒绝：范围爆炸；
  违反 fail closed over best effort）。

## 验证

- `list-targets` 默认含 `icp\tsource-only`；`--all` 仅剩 `openvm`/`soroban` 为
  `research-only`。
- `resolveBuildSelectionV1 TargetId.icp none` → sole profile。
- Counter（或任意程序）`build --target icp` 在 ICP-2 前以稳定产品错误失败且
  零 destination 制品。
- `just docs-check`；聚焦 `Tests.Materialization.TargetRegistryV1` /
  `BuildSelectionV1` / `RequirementResolverV1` / `RegistryRootV1`。
