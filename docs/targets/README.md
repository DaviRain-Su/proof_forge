---
id: TARGET-INDEX
title: Target 研究与实现档案
status: proposed
owner: architecture
updated: 2026-07-16
normative: true
---

# Target 研究与实现档案

状态：`proposed`
更新日期：2026-07-16

本目录按执行语义而不是文件后缀组织目标。`family` 是阅读视图，编译器实际依据多轴 `TargetDescriptor` 和 exact `SupportClaim` 决策。

## 成熟度

| Target | 视图 | 本阶段 | Static dossier ceiling | 当前证据与限制 | Dossier |
|---|---|---|---|---|---|
| `evm` | contract VM | Phase 1 implement | `specified` | development `EV-20260715-0004`/`EV-20260716-0018` 只是 alpha 观察：Counter/Accumulator + Anvil；不是 formal maturity binding | [EVM](01-evm.md) |
| `solana` | explicit-account SVM | Phase 1 implement | `specified` | development `EV-20260716-0019` 只是 alpha 观察：typed non-executable `.sbpf-plan` + IDL；无 sBPF object/ELF/runtime | [Solana](02-solana.md) |
| `near` | Wasm host | Phase 1 implement | `specified` | development `EV-20260716-0020` 只是 alpha 观察：raw-u64 Wasm 结构验证；无 sandbox receipt | [NEAR](03-near.md) |
| `cosmwasm` | Wasm host | design only | `research` | transaction profile 仍 provisional | [CosmWasm](04-cosmwasm.md) |
| `soroban` | Wasm host | design only | `research` | host model已调研，protocol/tool profile 未冻结；无 backend | [Soroban](05-soroban.md) |
| `icp` | Wasm actor host | design only | `research` | actor model已调研，protocol/tool profile 未冻结；无 backend | [ICP](06-icp.md) |
| `noir` | circuit compiler | Phase 1 implement | `specified` | development `EV-20260716-0021` 只是 alpha 观察：relation source packages；无 Nargo/ACIR/prove/verify | [Noir](07-noir.md) |
| `openvm` | zkVM | design only | `research` | exact version/toolchain line 仍 provisional | [OpenVM](08-openvm.md) |
| `aleo` | ZK application chain | design only | `research` | Leo 4.x model已调研，exact patch/profile 未冻结；无 backend | [Aleo](09-aleo.md) |
| `psy` | ZK application chain | research only | `research` | pre-testnet/live workflow provisional | [Psy](10-psy.md) |

## Family 视图

- [EVM contract VM](family-evm-contract-vm.md)
- [Solana explicit-account SVM](family-svm-explicit-account.md)
- [Wasm artifact and host](family-wasm-host.md)
- [ZK circuit](family-zk-circuit.md)
- [zkVM](family-zkvm.md)
- [ZK application chain](family-zk-application-chain.md)

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
