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

| Target | 视图 | 本阶段 | Static dossier ceiling | 当前证据与限制（工程观察，非 formal binding） | Dossier |
|---|---|---|---|---|---|
| `evm` | contract VM | Phase 1 implement | `specified` | retained-V1 Plan + Yul/solc bytecode + EvmSolc 验收 + 历史 Anvil smoke；**非** formal maturity / Reference↔Anvil 闭包 | [EVM](01-evm.md) |
| `solana` | explicit-account SVM | Phase 1 implement | `specified` | retained-V1 Plan + SBPF asm → ELF `.so` + Mollusk runtime 差分；**非** formal Stage-0/hermetic | [Solana](02-solana.md) |
| `near` | Wasm host | Phase 1 implement | `specified` | retained-V1 Plan + WAT/`wat2wasm` + `wasm-interp --dummy-import-func` 结构/实例化门与 deterministic HostModel；**无** NEAR sandbox receipt runtime | [NEAR](03-near.md) |
| `cosmwasm` | Wasm host | design only | `research` | design-only；无产品 backend | [CosmWasm](04-cosmwasm.md) |
| `soroban` | Wasm host | design only | `research` | design-only；无产品 backend | [Soroban](05-soroban.md) |
| `icp` | Wasm actor host | design only | `research` | design-only；无产品 backend | [ICP](06-icp.md) |
| `noir` | circuit compiler | Phase 1 implement | `specified` | retained-V1 Plan + relation source packages；**无** Nargo/ACIR/prove/verify | [Noir](07-noir.md) |
| `openvm` | zkVM | design only | `research` | design-only；无产品 backend | [OpenVM](08-openvm.md) |
| `aleo` | ZK application chain | Phase 1 implement（工程 source leaf） | `specified` | 工程 source-only leaf（scalar 子集 + 显式 FAIL-CLOSED 边界）；host 有 `leo 4.0.2` 时 optional `leo build --offline`，但无 Tool Lock/VM/prove | [Aleo](09-aleo.md) |
| `psy` | ZK application chain | Phase 1 implement（工程 source leaf） | `specified` | 工程 source-only leaf；host tool 可用时 optional compile，但无 Tool Lock/VM/proof | [Psy](10-psy.md) |
| `ton` | TVM Stack-Account | research only | `research` | ADR-0017 研究期：dossier + family 归类 only；**无** TargetDescriptor/capability/制品；`TargetId` 枚举未登记，编译器不可寻址 | [TON](11-ton.md) · [family](family-tvm-stack-account.md) |

## Family 视图

- [EVM contract VM](family-evm-contract-vm.md)
- [Solana explicit-account SVM](family-svm-explicit-account.md)
- [Wasm artifact and host](family-wasm-host.md)
- [ZK circuit](family-zk-circuit.md)
- [zkVM](family-zkvm.md)
- [ZK application chain](family-zk-application-chain.md)
- [TVM Stack-Account](family-tvm-stack-account.md)

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
