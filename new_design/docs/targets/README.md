---
id: TARGET-INDEX
title: Target 研究与实现档案
status: draft
owner: architecture
updated: 2026-07-15
normative: true
---

# Target 研究与实现档案

状态：`draft`
更新日期：2026-07-15

本目录按执行语义而不是文件后缀组织目标。`family` 是阅读视图，编译器实际依据多轴 `TargetDescriptor` 和 exact `SupportClaim` 决策。

## 成熟度

| Target | 视图 | 本阶段 | 证据状态 | Dossier |
|---|---|---|---|---|
| `evm` | contract VM | Phase 1 implement | `runtime-validated-alpha`：Counter bytecode + Anvil；非完整 backend | [EVM](01-evm.md) |
| `solana` | explicit-account SVM | Phase 1 implement | `plan-only`：typed non-executable `.sbpf-plan` + IDL；无 sBPF object/ELF/runtime | [Solana](02-solana.md) |
| `near` | Wasm host | Phase 1 implement | `wasm-validated-alpha`：raw-u64 Counter Wasm；无 sandbox receipt | [NEAR](03-near.md) |
| `cosmwasm` | Wasm host | design only | transaction profile provisional | [CosmWasm](04-cosmwasm.md) |
| `soroban` | Wasm host | design only | official model verified | [Soroban](05-soroban.md) |
| `icp` | Wasm actor host | design only | official model verified | [ICP](06-icp.md) |
| `noir` | circuit compiler | Phase 1 implement | `source-only`：`.nr`/Prover input；无 ACIR/prove/verify | [Noir](07-noir.md) |
| `openvm` | zkVM | design only | version line provisional | [OpenVM](08-openvm.md) |
| `aleo` | ZK application chain | design only | Leo 4.0 model verified | [Aleo](09-aleo.md) |
| `psy` | ZK application chain | research only | pre-testnet/live workflow provisional | [Psy](10-psy.md) |

## Family 视图

- [EVM contract VM](family-evm-contract-vm.md)
- [Solana explicit-account SVM](family-svm-explicit-account.md)
- [Wasm artifact and host](family-wasm-host.md)
- [ZK circuit](family-zk-circuit.md)
- [zkVM](family-zkvm.md)
- [ZK application chain](family-zk-application-chain.md)

## 通用状态规则

- `research`：只有一手材料和问题清单。
- `design`：Plan、制品、错误和验证阶梯 decision-complete。
- `implemented`：代码与静态/单元 gate 通过。
- `runtime-validated`：官方或兼容本地 runtime 行为通过。
- `network/proof-validated`：真实网络收据或完整 prove/verify 证据通过。

阶段不得跳跃。源程序只有统一的 `program` 声明，没有 target 类别字段；本表的分类不会进入用户源码。
