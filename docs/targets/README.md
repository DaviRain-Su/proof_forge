---
id: TARGET-INDEX
title: Target 研究与实现档案
status: proposed
owner: architecture
updated: 2026-08-03
normative: true
---

# Target 研究与实现档案

状态：`proposed`
更新日期：2026-08-03

本目录按执行语义而不是文件后缀组织目标。`family` 是阅读视图，编译器实际依据多轴 `TargetDescriptor` 和 exact `SupportClaim` 决策。

工程缺口队列：[`../engineering-backlog.md`](../engineering-backlog.md)；op×target 格子：
[`../research/12-target-coverage-matrix.md`](../research/12-target-coverage-matrix.md)。

## 成熟度

> **双轨（显著）**：
>
> 1. **Accepted PRD Phase 1 范围**仍为 **四目标**：`evm` / `solana` / `near` / `noir`。
> 2. **Engineering implemented leaves** 另有 `aleo` / `psy` / `cosmwasm` / `ton` /
>    `quint`（工程已可寻址并 materialize，**不**等于 accepted 产品范围已扩）。二者
>    reconciliation 由 **`DOC-ADR-SCOPE`** 跟踪；不得因表格「implement」字样静默扩大
>    accepted scope。`quint` 为 ADR-0026 冻结并已接线的 source-only model surface。

| Target | 视图 | 本阶段 | Static dossier ceiling | 当前证据与限制（工程观察，非 formal binding） | Dossier |
|---|---|---|---|---|---|
| `evm` | contract VM | accepted Phase 1 implement | `specified` | retained-V1 Plan + Yul/locked-solc bytecode + EvmSolc + G4 Anvil 工程差分；**非** formal maturity / Reference↔Anvil 闭包 | [EVM](01-evm.md) |
| `solana` | explicit-account SVM | accepted Phase 1 implement | `specified` | retained-V1 Plan + SBPF asm → ELF `.so` + Mollusk runtime 差分；**非** formal Stage-0/hermetic | [Solana](02-solana.md) |
| `near` | Wasm host | accepted Phase 1 implement | `specified` | retained-V1 Plan + locked `wat2wasm` 结构编译 / host-optional runtime load + locked near-sandbox 2.13.0 deploy/init/mutate/view receipt 工程门与 deterministic HostModel；**非** formal Reference↔sandbox / Stage-0 | [NEAR](03-near.md) |
| `cosmwasm` | Wasm host | engineering implemented (scope ADR open) | `research` | retained-V1 Plan/IR → WAT + locked `wat2wasm` + `cosmwasm-check` 3.0.9 + cosmwasm-vm mock 差分；registry label `wasm-validated-alpha`；**sync call FC**、async→`SubMsg{reply_on:never}`（同 tx savepoint，子消息失败打爆整笔 tx，非跨 tx async）；**非** wasmd/链上/formal；**非** accepted Phase 1 范围 | [CosmWasm](04-cosmwasm.md) |
| `soroban` | Wasm host | design only | `research` | design-only；无产品 backend | [Soroban](05-soroban.md) |
| `icp` | Wasm actor host | design only | `research` | design-only；无产品 backend | [ICP](06-icp.md) |
| `noir` | circuit compiler | accepted Phase 1 implement | `specified` | retained-V1 Plan + relation source packages + locked nargo 1.0.0-beta.26 compile-only 门；**无** ACIR/witness/prove/verify，仍 source-only | [Noir](07-noir.md) |
| `openvm` | zkVM | design only | `research` | design-only；无产品 backend | [OpenVM](08-openvm.md) |
| `aleo` | ZK application chain | engineering implemented (scope ADR open) | `specified` | 工程 source-only leaf；locked leo 4.0.2 compile-only 验收；无 VM/prove/deploy；**非** accepted Phase 1 范围 | [Aleo](09-aleo.md) |
| `psy` | ZK application chain | engineering implemented (scope ADR open) | `specified` | 工程 source-only leaf；host tool 可用时 optional compile，但无 Tool Lock/VM/proof；**非** accepted Phase 1 范围 | [Psy](10-psy.md) |
| `ton` | TVM Stack-Account | engineering implemented (scope ADR open) | `research` | retained-V1 Plan/IR → Tolk + real BoC + `@ton/sandbox` 工程差分；registry label `source-only`；resolver 开 `effect.asynchronous-workflow`/event、**Plan schedule 仍 FC**（destination/send-mode 未接线）；sync call 显式 FC；**非** 主网/formal；**非** accepted Phase 1 范围 | [TON](11-ton.md) · [family](family-tvm-stack-account.md) |
| `quint` | executable specification / model | engineering implemented (scope ADR open) | `research` | retained-V1 Q0 Plan/IR → `.qnt` + **zero-tool** finalize；profile `quint-source-u64-model-v1`；resolver 仅 4-key；完整 UInt64 域；失败=显式 outcome+business-state stutter；zero-param Bool invariant→`val`；本机 Quint 0.32 typecheck/run 仅 host observation，非 locked gate；ITF/MBT/verify 未声称；不可部署、非 accepted Phase 1/formal D3/D4 | [Quint](12-quint.md) · [ADR-0026](../adr/0026-quint-target-integration.md) |

> **Registry 计数（当前工程事实，2026-08-03）**：**12 = 9 implemented + 3
> design-only**。九个 materializer：`evm` / `solana` / `near` / `noir` / `aleo` /
> `psy` / `quint` / `cosmwasm` / `ton`。三个 design-only：`soroban` / `icp` /
> `openvm`。其中 **accepted PRD Phase 1** 仍仅前四；`aleo`/`psy`/`quint`/`cosmwasm`/
> `ton` 为 engineering leaves，`DOC-ADR-SCOPE` 未闭合前不得写成 accepted 范围。
> Registry maturity 标签（如 CosmWasm `wasm-validated-alpha`、TON/Quint
> `source-only`）不变；compile / mock / sandbox / 模型检查不得写成 formal 或 hermetic 完成。

## Family 视图

- [EVM contract VM](family-evm-contract-vm.md)
- [Solana explicit-account SVM](family-svm-explicit-account.md)
- [Wasm artifact and host](family-wasm-host.md)
- [ZK circuit](family-zk-circuit.md)
- [zkVM](family-zkvm.md)
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
