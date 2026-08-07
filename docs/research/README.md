---
id: RESEARCH-INDEX
title: 调研证据索引
status: draft
owner: research
updated: 2026-08-07
normative: false
---

# 调研证据索引

状态：`draft`
更新日期：2026-08-07

本目录保存 ProofForge V2 的非规范性研究材料。研究结论不能越过已接受的 ADR、PRD、架构和技术规格；它们的作用是说明“为什么这样设计”，而不是暗中改变产品语义。

**工程执行队列**不在本目录：见 [`../engineering-backlog.md`](../engineering-backlog.md)。
日常只把 **11 + 12 + 13** 的缺口回写 backlog；**01–09** 为早期设计研究（已被 ADR/SPEC 吸收），**10** 为长期北极星（IBC），勿再平行开第四份 gap 清单。

## 阅读顺序

1. [`source-register.json`](source-register.json)：来源、版本、定位与访问状态。
2. [`claim-register.json`](claim-register.json)：可独立复核的原子结论。
3. [`01-current-system-audit.md`](01-current-system-audit.md)：空白 V2 与父项目参考边界。
4. [`02-execution-models.md`](02-execution-models.md)：各平台执行、状态和提交模型。
5. [`03-language-semantics.md`](03-language-semantics.md)：统一 `program` 语言的研究结论。
6. [`04-target-taxonomy.md`](04-target-taxonomy.md)：多轴目标分类。
7. [`05-backends-artifacts-toolchains.md`](05-backends-artifacts-toolchains.md)：后端、制品和工具链。
8. [`06-security-and-migration.md`](06-security-and-migration.md)：安全与 clean-room 迁移。
9. [`07-synthesis.md`](07-synthesis.md)：研究综合与实施准入。
10. [`08-v1-v2-frontend-ir-comparison.md`](08-v1-v2-frontend-ir-comparison.md)：V1 与 V2 的 Lean 语法入口、领域 IR 和编译边界对照。
11. [`09-assembler-semantics-bridge.md`](09-assembler-semantics-bridge.md)：汇编语义桥研究。
12. [`10-ibc-as-proofforge-programs.md`](10-ibc-as-proofforge-programs.md)：IBC-as-programs 可行性与语言前置（**北极星，非近期任务**）。
13. [`11-feature-coverage-audit.md`](11-feature-coverage-audit.md)：特性覆盖审查——分层缺口与按杠杆排序清单。
14. [`12-target-coverage-matrix.md`](12-target-coverage-matrix.md)：wire Op × target LOWERED/FAIL-CLOSED/GAP 矩阵（工程覆盖权威格子）。
15. [`13-spec-normalize-diff.md`](13-spec-normalize-diff.md)：SPEC-LANG/SEM/TYPE × NormalizeV1 机械对账（DOC-SPEC-AUDIT）。
16. [`14-n5-call-return-schema.md`](14-n5-call-return-schema.md)：N-5 external call 返回值 schema 影响（void ExternalCall 直至共享核 cutover）。
17. [`15-aleo-psy-compiler-vm.md`](15-aleo-psy-compiler-vm.md)：C-2 Aleo/Psy 历史研究 + follow-up——Aleo 有 locked leo compile-only；Psy 已 pin dargo v0.1.0 + bundled std，并有 Linux Counter + explicit-profile WideCounter UInt128 add/sub/mul/compare local-VM/base-proof 工程门（Darwin 仅 pin）与 focused Reference join；二者 registry 成熟度仍 source-only，均未升格 formal/UPS/deploy。
18. [`16-noir-prove-path.md`](16-noir-prove-path.md)：C-4 Noir prove/verify 路径——G123 后 nargo compile-only 已锁定并接门，但无 Barretenberg/CRS/proof binding，故**不**升格 prove/verify；保持 source-only relations。
19. [`13-noir-toolchain-research.md`](13-noir-toolchain-research.md)：RPT-017 的 2026-08-02 J1 历史快照及 2026-08-03 follow-up；明确哪些“无 nargo pin”结论已被 compile-only gate supersede，哪些 prove/verify 阻塞仍有效。
20. [`17-openzeppelin-ethereum-coverage-audit.md`](17-openzeppelin-ethereum-coverage-audit.md)：OpenZeppelin v5.7.0 × ProofForge EVM 行为能力审计；固定 112 个稳定实现到 20 个族，区分 primitive、行为、ABI 与标准兼容，并给出 oracle/differential 路线。对象归属见 [`openzeppelin-v5.7.0-family-membership-v1.json`](openzeppelin-v5.7.0-family-membership-v1.json)。
21. [`18-solana-program-examples-coverage.md`](18-solana-program-examples-coverage.md)：固定 QuickNode Solana examples commit 的 57 项外部应用 corpus 覆盖矩阵、分层测试策略与 P0–P2 研究建议；非规范、非第四份 live backlog。
22. [`19-solana-program-org-coverage.md`](19-solana-program-org-coverage.md)：`solana-program` 组织 38 仓库的 program/interface/client/tooling 角色清单、official-callee/pack/tx-deploy 分层及相对 QuickNode corpus 的覆盖增量；两份分母不可合并。
23. [`20-host-function-survey.md`](20-host-function-survey.md)：多链系统能力（host function / runtime API）全景调研——状态类 vs 电路类平台分类、各链能力浓缩清单、跨链能力维度对照，及"统一抽象候选"建议（RPT-020；2026-08-05）。
24. [`system-capabilities-evm-solana.md`](system-capabilities-evm-solana.md)：EVM/Solana 逐项 opcode / syscall / sysvar / builtin 清单（RPT-020 的详细平台报告；2026-08-05）。
25. [`21-system-programs-survey.md`](21-system-programs-survey.md)：各链官方链上程序（系统合约 / builtin program / precompile / management canister / 链级模块）全景——L2 系统能力层，含"能力 vs 形态"对照表与强制等级分级（RPT-021；2026-08-05）。
26. [`22-portable-surface-vs-chain-reality.md`](22-portable-surface-vs-chain-reality.md)：**可移植表面 vs 链上现实**——跨合约 / 资产 / 原子性总表（12-target）；解释为何一份 `program` 不能诚实直出「各链失败语义相同」的制品（NEAR Promise vs EVM/Solana CPI vs CW SubMsg；Wasm 不是原因）（RPT-022；2026-08-07）。
27. [`23-miniamm-formalization-ladder.md`](23-miniamm-formalization-ladder.md)：**通用程序形式化栈** L0/L1/L2；generic Preservation ABI foundation 已实现，ProofKind/inventory/certifier + **EvenCounter 首实例** pending；product Reference step 唯一，MiniAmm 为后续普通实例；D/L2 formal 最后（RPT-023；2026-08-07）。
28. [`24-aleo-local-proof-finalize.md`](24-aleo-local-proof-finalize.md)：locked Leo 4.0.2 的 package/build/execute/proof/finalize/query 实证冻结；offline build 三产物确定性已由 ALEO-I4 productize 为 opt-in non-deployable compile profile，network/proof/deploy 阶段仍阻塞（RPT-024；2026-08-07）。

## 证据等级

- `verified`：2026-07-15 已通过官方规范、官方文档或可复现本地事实核验。
- `provisional`：方向有一手材料支持，但版本、工具链或真实网络流程尚未冻结。
- `accepted`：项目设计决定；事实依据可复核，但决定本身由 ADR 管理。
- `rejected`：已核验后明确不采用。

网页没有被仓库快照化时，`contentHash` 为 `null`，并在 `hashStatus` 中明确说明。不能用 URL 字符串的哈希冒充来源内容哈希。进入实现前，所有工具链 profile 必须把文档、二进制和依赖固定到可重现版本。

## 维护规则

- 每个重要事实至少对应一个 `CLM-*`，每个 claim 引用一个或多个 `SRC-*`。
- 平台营销性能数字只作为待验证主张，不作为容量、费用或安全承诺。
- 父项目路径只能记录观察结果和 commit；不得被 V2 作为依赖、测试 oracle 或 fallback。
- 任何事实发生变化时，新增来源记录并更新 claim，不覆写历史语义。
