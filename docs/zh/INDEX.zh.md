# ProofForge 文档索引

ProofForge 是一个 Lean 优先的多链智能合约平台。经过 2026-07 分支收敛，主干在同一套可移植 IR 和 capability registry 之上包含 EVM 基线，以及 Solana（sBPF assembly）、NEAR（EmitWat）、Psy/DPN、Aleo Leo 和 Cloudflare Workers 后端。

**当前阶段：** Gate P0 已经关闭，三条主产品链 `solana-sbpf-asm`、`evm`
和 `wasm-near` 已完成生产级本地/CI 门禁签署。下一条硬化主线是 CLI M3/M4：
把 legacy flags 迁移到 `proof-forge build|emit|check --target ...`；Tier-1
M3/M4 工作排在这次清理之后。

## 文档地图

| 如果你是... | 从这里开始 | 然后阅读 |
|---|---|---|
| 新贡献者 | 本页面 + [README](../README.md) + [入职指南](onboarding.zh.md) | [三目标可移植教程](tutorials/portable-contract-three-targets.md), [验证门禁](validation-gates.md), [待办事项](implementation-backlog.md) |
| 实现后端 | [RFC 0002](rfcs/0002-target-implementation-design.md) | [决策](decisions.md), [可移植 IR](portable-ir.md), 目标说明 |
| 评审设计 | [评审清单](review-checklist.md) | RFCs, [能力注册表](capability-registry.md), [共享场景](shared-scenario.md) |
| 策略 / 中文读者 | [zh/README](zh/README.md) | [可行性分析](zh/feasibility-analysis.md), [决策](decisions.md) |

```mermaid
flowchart TB
  INDEX[INDEX.md]
  RFC1[RFC 0001 vision]
  RFC2[RFC 0002 engineering]
  DEC[decisions.md]
  IR[portable-ir.md]
  CAP[capability-registry.md]
  SCN[shared-scenario.md]
  BL[implementation-backlog]
  TGT[targets/*]
  INDEX --> RFC1
  INDEX --> RFC2
  INDEX --> DEC
  RFC2 --> IR
  RFC2 --> CAP
  DEC --> BL
  IR --> SCN
  BL --> TGT
```

## 规格与决策

- [设计决策](decisions.md)：确定的架构选择和路线图摘要。
- [可移植合约 IR](portable-ir.md)：IR 草案和阶段 1 验收标准。
- [RFC 0003: 可移植 IR 与运行时](rfcs/0003-portable-ir-and-runtime.md)：详细的 IR/能力/运行时草案。
- [RFC 0004: EVM semantic plan 与 Yul AST 边界](rfcs/0004-evm-semantic-plan.md)：位于 portable IR 和低层 Yul 语法之间的 EVM target-semantic plan 层。
- [能力注册表](capability-registry.md)：规范的能力 id。
- [共享场景：计数器](shared-scenario.md)：跨目标验收测试。
- [教程：一个模块、三个目标](tutorials/portable-contract-three-targets.md)：可移植 `contract_source` 演练（CS-5.3）。

## RFC

已接受的工程方向 ([rfcs/README](rfcs/README.md))：

- [RFC 0001: Lean 优先的多链合约平台](rfcs/0001-multichain-platform.md)
- [RFC 0002: 目标实现设计](rfcs/0002-target-implementation-design.md)
- [RFC 0003: 可移植 IR 与运行时 profile](rfcs/0003-portable-ir-and-runtime.md) (草案 — 扩展 0001/0002)
- [RFC 0004: EVM semantic plan 与 Yul AST 边界](rfcs/0004-evm-semantic-plan.md) (草案 — EVM 后端内部架构)

## 工程

- [开发标准](development-standards.md)：贡献者规则和单一真值源映射。
- [入职指南](onboarding.zh.md)：本地环境、编辑器说明和新贡献者最小验证循环。
- [开发日志](development-log.md)：带有验证说明和后续步骤的里程碑日志。
- [Authoring model](authoring-model.zh.md)：Learn source、`contract_source` 与内部 `ContractSpec` 边界。
- [验证门禁](validation-gates.md)：可运行的门禁和工具先决条件。
- [实现待办事项](implementation-backlog.md)：分阶段任务和验收标准。
- [评审清单 (英文)](review-checklist.md)
- [目标笔记](targets/README.md)：各家族的 Research 和 spike 计划。
  - [EVM](targets/evm.md)
  - [Wasm 家族](targets/wasm-family.md)
  - [Wasm-NEAR](targets/wasm-near.zh.md)
  - [Stellar Soroban 目标](targets/stellar-soroban.zh.md)
  - [Internet Computer 目标](targets/internet-computer.zh.md)
  - [Algorand AVM 目标](targets/algorand-avm.zh.md)
  - [Solana sBPF Asm](targets/solana-sbpf-asm.md)（规范 direct-assembly 路线）
  - [Solana sBPF](targets/solana-sbf.md)（已被取代的 Zig/sbpf-linker 路线）
  - [Move 家族](targets/move-family.md)
  - [Cardano Plutus/Aiken 目标](targets/cardano-plutus-aiken.zh.md)
  - [Tezos Michelson/LIGO 目标](targets/tezos-michelson-ligo.zh.md)
  - [Starknet Cairo 目标](targets/starknet-cairo.zh.md)
  - [Aleo Leo 目标](targets/aleo-leo.zh.md)
  - [TON TVM 目标](targets/ton-tvm.zh.md)
  - [Bitcoin Script/Miniscript 目标](targets/bitcoin-script-miniscript.zh.md)
  - [Zcash Shielded 目标](targets/zcash-shielded.zh.md)
  - [Bitcoin Cash CashScript 目标](targets/bitcoin-cash-cashscript.zh.md)
  - [Psy DPN ZK 目标](targets/psy-dpn.md)
  - [Kaspa Toccata 目标](targets/kaspa-toccata.zh.md)

## 中文笔记

- [中文文档索引](zh/README.md)
- [多链愿景可行性分析](zh/feasibility-analysis.md)
- [多链技术实现方案](zh/technical-implementation-plan.md) — 摘要；工程细节见 RFC 0002
- [多链方案 Review 清单](zh/review-checklist.md)
- [Psy/DPN ZK Target 初步分析](zh/zk-psy-target-analysis.md)
- [Kaspa Toccata 目标说明](zh/targets/kaspa-toccata.zh.md)
- [Stellar Soroban 目标说明](zh/targets/stellar-soroban.zh.md)
- [Internet Computer 目标说明](zh/targets/internet-computer.zh.md)
- [Cardano Plutus/Aiken 目标说明](zh/targets/cardano-plutus-aiken.zh.md)
- [Tezos Michelson/LIGO 目标说明](zh/targets/tezos-michelson-ligo.zh.md)
- [Starknet Cairo 目标说明](zh/targets/starknet-cairo.zh.md)
- [Aleo Leo 目标说明](zh/targets/aleo-leo.zh.md)
- [Aleo Leo 设计规格](zh/superpowers/specs/2026-07-01-aleo-leo-design.zh.md)
- [TON TVM 目标说明](zh/targets/ton-tvm.zh.md)
- [Bitcoin Script/Miniscript 目标说明](zh/targets/bitcoin-script-miniscript.zh.md)
- [Zcash Shielded 目标说明](zh/targets/zcash-shielded.zh.md)
- [Bitcoin Cash CashScript 目标说明](zh/targets/bitcoin-cash-cashscript.zh.md)

## 当前实现基线

- 目标注册表（`ProofForge/Target/Registry.lean`）、可移植 IR（`ProofForge/IR/Contract.lean`）、capability 路由和 `proof-forge-artifact.json` 产出均已实现。
- EVM：`proof-forge build --target evm` 将 `contract_source` 模块通过 portable
  IR、EVM semantic plan、Yul 和 `solc --strict-assembly` 编译。Foundry 和
  Anvil 冒烟验证运行时行为。
- Solana：`proof-forge emit --target solana-sbpf-asm --format s|elf` 产出 sBPF assembly 和 ELF 包，由 Mollusk、Surfpool/Web3.js 和 Pinocchio 等价性门禁验证。
- NEAR：`proof-forge emit|build --target wasm-near --format wat` 把 portable IR 经 Wasm AST 降级为 WAT，带形式化 trace obligation（`Tests/NearWasmFormal.lean`）、target-first metadata 和离线宿主冒烟。
- Psy/DPN、Aleo Leo 和 Cloudflare Workers 从 portable IR fixture 产出目标源码；各门禁的工具前置条件见 [validation-gates.md](validation-gates.zh.md)。
