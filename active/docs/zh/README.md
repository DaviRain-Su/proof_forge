# ProofForge 中文文档

ProofForge 的工程权威文档是英文的（RFC、decisions、capability registry、
validation gates 等）。本目录提供两类中文文档：

1. **原生中文文档**：面向中文讨论、融资叙事、战略判断和产品路线的分析文档。
2. **英文文档的中文翻译**：由 `scripts/translate-docs.py` 自动从英文权威文档
   同步生成，文件名以 `.zh.md` 结尾。

英文工程文档是单一权威源（见
[development-standards](../development-standards.md)）；中文翻译必须与英文
保持一致，不能引入独立的工程策略。

## 同步机制

中文翻译由翻译脚本增量维护，不需要手动翻译：

```sh
# 翻译所有有变更的英文文档
python3 scripts/translate-docs.py

# 只检查哪些文档过期，不翻译
python3 scripts/translate-docs.py --check

# 列出所有文档映射和状态
python3 scripts/translate-docs.py --list

# 强制重新翻译所有文档
python3 scripts/translate-docs.py --force

# 指定模型（默认 gemini-3-flash-preview）
python3 scripts/translate-docs.py --model glm-4.7
```

工作原理：

- `scripts/i18n/manifest.json` 记录每个英文文档上次翻译时的 sha256。
- 脚本比对当前英文文件 sha256 与 manifest 记录，只翻译有变化的文档。
- `scripts/i18n/glossary.json` 是术语表，约束技术术语的中文翻译一致性。
- 代码块、内联代码、CLI 标志、文件路径、target id、capability id 保持原文。
- 需要 `OLLAMA_API_KEY` 环境变量（Ollama Cloud）。

新增英文文档时，在 `scripts/translate-docs.py` 的 `DOC_MAP` 里添加映射条目。

## 英文文档入口

- [Documentation index (INDEX)](../INDEX.md) / [中文翻译](INDEX.zh.md)
- [RFC 0001: 多链合约平台](../rfcs/0001-multichain-platform.md) / [中文](rfcs/0001-multichain-platform.zh.md)
- [RFC 0002: 目标实现设计](../rfcs/0002-target-implementation-design.md) / [中文](rfcs/0002-target-implementation-design.zh.md)
- [RFC 0003: 可移植 IR 与运行时](../rfcs/0003-portable-ir-and-runtime.md) / [中文](rfcs/0003-portable-ir-and-runtime.zh.md)
- [Design decisions](../decisions.md) / [中文](decisions.zh.md)
- [Capability registry](../capability-registry.md) / [中文](capability-registry.zh.md)
- [Portable IR](../portable-ir.md) / [中文](portable-ir.zh.md)
- [Shared scenario](../shared-scenario.md) / [中文](shared-scenario.zh.md)
- [Implementation backlog](../implementation-backlog.md) / [中文](implementation-backlog.zh.md)
- [Multi-chain vision gap audit (2026-07-10)](../multi-chain-gap-audit-2026-07-10.md) / [中文](multi-chain-gap-audit-2026-07-10.zh.md)
- [Development standards](../development-standards.md) / [中文](development-standards.zh.md)
- [Contributor onboarding](../onboarding.md) / [中文](onboarding.zh.md)
- [Validation gates](../validation-gates.md) / [中文](validation-gates.zh.md)
- [Review checklist](../review-checklist.md) / [中文](review-checklist.zh.md)
- [Target notes](../targets/README.md) / [中文](targets-README.zh.md)

## 原生中文文档

- [架构评审（2026-07）：统一 SDK 输入与分支收敛](architecture-review-2026-07.md)
- [全量代码 + 架构评审（2026-07，FV-5 能力门分支）](code-review-2026-07-fv5-capability-gate.md) — 实现正确性与 FV 可靠性评审
- [执行任务清单 + WASM 家族与调用层规划（2026-07）](execution-plan-2026-07.md) — 分轨任务、WASM 新链模板、调用文档生成
- [贡献者入职指南](onboarding.zh.md)
- [多链愿景可行性分析](feasibility-analysis.md)
- [多链技术实现方案](technical-implementation-plan.md) — 摘要版，工程细节见 RFC 0002
- [多链方案 Review 清单](review-checklist.md)
- [Psy/DPN ZK Target 初步分析](zk-psy-target-analysis.md)
- [Kaspa Toccata 目标说明](targets/kaspa-toccata.zh.md)
- [Stellar Soroban 目标说明](targets/stellar-soroban.zh.md)
- [Internet Computer 目标说明](targets/internet-computer.zh.md)
- [Algorand AVM 目标说明](targets/algorand-avm.zh.md)
- [Cardano Plutus/Aiken 目标说明](targets/cardano-plutus-aiken.zh.md)
- [Tezos Michelson/LIGO 目标说明](targets/tezos-michelson-ligo.zh.md)
- [Starknet Cairo 目标说明](targets/starknet-cairo.zh.md)
- [Aleo Leo 目标说明](targets/aleo-leo.zh.md)
- [TON TVM 目标说明](targets/ton-tvm.zh.md)
- [Bitcoin Script/Miniscript 目标说明](targets/bitcoin-script-miniscript.zh.md)
- [Zcash Shielded 目标说明](targets/zcash-shielded.zh.md)
- [Bitcoin Cash CashScript 目标说明](targets/bitcoin-cash-cashscript.zh.md)
