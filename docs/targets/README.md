---
id: TARGET-INDEX
title: Target 研究与实现档案
status: proposed
owner: architecture
updated: 2026-08-13
normative: true
---

# Target 研究与实现档案

状态：`proposed`
更新日期：2026-08-13

本目录按执行语义而不是文件后缀组织目标。`family` 是阅读视图，编译器实际依据多轴 `TargetDescriptor` 和 exact `SupportClaim` 决策。

工程缺口队列：[`../engineering-backlog.md`](../engineering-backlog.md)；op×target 格子：
[`../research/12-target-coverage-matrix.md`](../research/12-target-coverage-matrix.md)。
**剩余 target / 比特币脚本族 / 落地波次**：[`../research/25-remaining-target-landscape.md`](../research/25-remaining-target-landscape.md)
（非 accepted 扩面；Soroban/OpenVM/ICP engineering leaves 均已闭合，见 ADR-0044/0045/0046/0047）。

## 成熟度

> **双轨（显著）**：
>
> 1. **Accepted PRD Phase 1 范围**仍为 **四目标**：`evm` / `solana` / `near` / `noir`。
> 2. **Engineering implemented leaves** 另有 `aleo` / `psy` / `cosmwasm` / `ton` /
>    `quint` / `soroban` / `openvm` / `icp`（十二个 materializer 均已可寻址并
>    materialize，**不**等于 accepted 产品范围已扩）。二者
>    边界由 **ADR-0036** 固定；不得因表格「implement」字样静默扩大
>    accepted scope。`quint` 为 ADR-0026 冻结并已接线的 source-only model surface；
>    `soroban` 为 ADR-0044 source-only S0（`.rs` recipe，zero-tool）；
>    `openvm` 为 ADR-0045/0046 O0 guest-source + opt-in O1 ELF；
>    `icp` 为 ADR-0047 wat2wasm + host-optional PocketIC。

| Target | 视图 | 本阶段 | Static dossier ceiling | 当前证据与限制（工程观察，非 formal binding） | Dossier |
|---|---|---|---|---|---|
| `evm` | contract VM | accepted Phase 1 implement | `specified` | retained-V1 Plan + Yul/locked-solc bytecode + EvmSolc + G4 Anvil 工程差分；**非** formal maturity / Reference↔Anvil 闭包 | [EVM](01-evm.md) |
| `solana` | explicit-account SVM | accepted Phase 1 implement | `specified` | retained-V1 Plan + SBPF asm → ELF `.so` + Mollusk runtime 差分；registry label `runtime-validated-alpha`（2026-08-12）；**非** formal Stage-0/hermetic | [Solana](02-solana.md) |
| `near` | Wasm host | accepted Phase 1 implement | `specified` | retained-V1 Plan + locked `wat2wasm` 结构编译 / host-optional runtime load + locked near-sandbox 2.13.0 deploy/init/mutate/view receipt 工程门与 deterministic HostModel；**非** formal Reference↔sandbox / Stage-0 | [NEAR](03-near.md) |
| `cosmwasm` | Wasm host | engineering implemented (scope ADR open) | `research` | retained-V1 Plan/IR → WAT + locked `wat2wasm`/`cosmwasm-check` 3.0.9；UInt8/16/32、named state、bounded aggregate/Array/Option return；**sync call FC**、async→Binary `SubMsg{reply_on:never}`（same-tx、QN stub）；cosmwasm-vm 28-test mock + wasmd v0.70.3 Docker rung-1；registry label `wasm-validated-alpha`；**非** 主网/formal；**非** accepted Phase 1 范围 | [CosmWasm](04-cosmwasm.md) |
| `soroban` | Wasm host | engineering implemented (ADR-0044 S0) | `research` | sole `soroban-source-u64-v1`；retained-V1 Plan → Soroban Rust dialect `.rs`；zero-tool finalize；`deployable=false`；4-key capability；auth/TTL/Wasm FC；**非** accepted Phase 1 / formal | [Soroban](05-soroban.md) · [ADR-0044](../adr/0044-soroban-source-u64-target.md) |
| `icp` | Wasm actor host | engineering implemented (ADR-0047) | `phase1` | sole `icp-wasm-candid-u64-v1`；sync+event FC；async advertise；wat2wasm finalize；PocketIC host-optional | [ICP](06-icp.md) |
| `noir` | circuit compiler | accepted Phase 1 implement | `specified` | retained-V1 Plan + relation source packages + locked nargo 1.0.0-beta.26 compile-only 门；**无** ACIR/witness/prove/verify，仍 source-only | [Noir](07-noir.md) |
| `openvm` | zkVM | engineering implemented (scope ADR open) | `research` | default `openvm-guest-source-v1`（zero-tool）+ opt-in `openvm-guest-elf-v1`（locked `cargo-openvm` 2.0.1 build/transpile → RV32IM ELF + `.vmexe`）；shared retained-V1 Plan → controlled Rust guest + catalog；无 keygen/execute/prove/verify；**非** accepted Phase 1 | [OpenVM](08-openvm.md) · [ADR-0045](../adr/0045-openvm-guest-source-o0.md) · [ADR-0046](../adr/0046-openvm-guest-elf-o1.md) |
| `aleo` | ZK application chain | engineering implemented (scope ADR open) | `specified` | sole `aleo-instructions-v1`；retained-V1 Plan → canonical Aleo Instructions `.aleo` + query descriptor；zero-tool finalization；无 VM/prove/deploy/network query；**非** accepted Phase 1 范围 | [Aleo](09-aleo.md) · [ADR-0035](../adr/0035-direct-native-artifact-materializers.md) |
| `psy` | ZK application chain | engineering implemented (scope ADR open) | `specified` | sole `psy-dpn-v1`；retained-V1 Plan → canonical `.dpn.json`；zero-tool finalization；无 DPN runtime/proof/UPS/network/deploy；**非** accepted Phase 1 范围 | [Psy DPN](10-psy.md) · [ADR-0035](../adr/0035-direct-native-artifact-materializers.md) |
| `ton` | TVM Stack-Account | engineering implemented (scope ADR open) | `research` | retained-V1 Plan/IR → Tolk + real BoC；UInt8/16/32 与 Int8/16/32/64、named state、bounded view aggregate/Array/Option return；async schedule→`createMessage`（hash dest/value=0/fixed mode，PARTIAL），sync call FC；`@ton/sandbox` 10/10；registry label `source-only`；**非** 主网/formal；**非** accepted Phase 1 范围 | [TON](11-ton.md) · [family](family-tvm-stack-account.md) |
| `quint` | executable specification / model | engineering implemented (scope ADR open) | `research` | retained-V1 Q0 Plan/IR → `.qnt` + **zero-tool** finalize；profile `quint-source-u64-model-v1`；resolver 仅 4-key；完整 UInt64 域；失败=显式 outcome+business-state stutter；zero-param Bool invariant→`val`；本机 Quint 0.32 typecheck/run 仅 host observation，非 locked gate；ITF/MBT/verify 未声称；不可部署、非 accepted Phase 1/formal D3/D4 | [Quint](12-quint.md) · [ADR-0026](../adr/0026-quint-target-integration.md) |
| `cairo` | zkVM (Cairo VM) | research (ADR-0017) | `research` | dossier + RPT-026 Plan/Q0；**无** materializer；Starknet syscall Q0 FC；非 accepted 扩面 | [Cairo](13-cairo.md) · [RPT-026](../research/26-zkvm-trio-cairo-risc0-sp1-design.md) |
| `risc0` | zkVM (RISC-V) | research (ADR-0017) | `research` | dossier + RPT-026；OpenVM 后第二叶候选 A；无 materializer | [RISC Zero](14-risc0.md) · [RPT-026](../research/26-zkvm-trio-cairo-risc0-sp1-design.md) |
| `sp1` | zkVM (RISC-V) | research (ADR-0017) | `research` | dossier + RPT-026；OpenVM 后第二叶候选 B；无 materializer | [SP1](15-sp1.md) · [RPT-026](../research/26-zkvm-trio-cairo-risc0-sp1-design.md) |

> **并行车道（2026-08-13）**：`feature-soroban` / `feature-icp` / `feature-zkvm(OpenVM)`
> 为实现叶；本目录 Cairo/RISC0/SP1 为 **research dossier**，不抢那些 registry 改动。
> `aptos`/`sui` dossier 仍缺（ADR-0017），编号续排待 `TGT-MOVE-DOSSIER`。

> **Registry 计数（当前工程事实，2026-08-14）**：**12 = 12 implemented + 0
> design-only**。十二个 materializer：`evm` / `solana` / `near` / `noir` / `aleo` /
> `psy` / `quint` / `cosmwasm` / `ton` / `soroban` / `openvm` / `icp`。
> 其中 **accepted PRD Phase 1** 仍仅前四；其余 engineering leaves（含 Soroban S0 与
> OpenVM O0/O1）由 ADR-0036/0044/0045/0046 固定为非 accepted 扩面，formal lighthouse=EVM-first。
> Registry maturity 标签（如 CosmWasm `wasm-validated-alpha`、TON/Quint/Soroban/OpenVM
> `source-only`）不变；compile / mock / sandbox / 模型检查不得写成 formal 或 hermetic 完成。
> **cairo/risc0/sp1 未进 registry 枚举**（仅 dossier/research）。

## Family 视图

- [EVM contract VM](family-evm-contract-vm.md)
- [Solana explicit-account SVM](family-svm-explicit-account.md)
- [Wasm artifact and host](family-wasm-host.md)
- [ZK circuit](family-zk-circuit.md)
- [zkVM](family-zkvm.md)（OpenVM + 研究期 Cairo/RISC Zero/SP1；Plan 设计见
  [`../research/26-zkvm-trio-cairo-risc0-sp1-design.md`](../research/26-zkvm-trio-cairo-risc0-sp1-design.md)）
- [ZK application chain](family-zk-application-chain.md)
- [TVM Stack-Account](family-tvm-stack-account.md)
- Quint executable specification / model surface（见 [12-quint.md](12-quint.md)；无独立 family 文档）

## 通用状态规则

本表只允许 PRD 定义的 `TargetMaturity` 六个 wire value；`alpha`、`plan-only`、`source-only`、
`implemented` 等只能写在限制列，不得进入 registry。阶段不得跳跃。源程序只有统一的 `program`
声明，没有 target 类别字段；本表的分类不会进入用户源码。

上表不是 `MaturitySnapshot`；它只显示静态 dossier 在未来 evaluator 中可支持的
最高连续阶段。当前没有 candidate-bound authoritative snapshot。Phase 1 target 的静态上限为
`specified`；所列 development EV 不是 gate-catalog-finalized formal binding，因此不能提升
maturity。正式 evaluator 必须按 SPEC-REG-001 验证 exact
`AcceptanceProfileRef`、candidate/target/codegen/gate binding、freshness 和 revocation；无法验证时停在
上一连续阶段。snapshot 不进入 static registry hash，也不授权 build/deploy。

## CLI parity notes (2026-08-12)

- **Noir / Quint / TON** are first-class `pf` `TargetId`s:
  - `pf test` artifact smoke (Noir relations/ACIR JSON; Quint `*.qnt`; TON sandbox corpus when tools present)
  - `pf deploy` **save-only** packages under `build/<target>/tx/`
  - `--broadcast` **refused** (circuits/model surfaces / TON v0 policy)
- **`pf run` one-shot local execution now covers five chains** (2026-08-12 afternoon):
  EVM (local Anvil, `scripts/pf_evm_run.sh`) · Solana (Mollusk `sol_oneshot`) ·
  NEAR (locked near-sandbox, ABI-driven view mode) · CosmWasm (cosmwasm-vm mock
  `cw_oneshot`) · TON (`@ton/sandbox` one-shot). Aleo/Psy keep the interactive
  `pf run` surface; Noir/Quint point at `pf test`. All engineering local only —
  not testnet/mainnet/formal.
