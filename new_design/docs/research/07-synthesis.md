---
id: RPT-007
title: 调研综合结论
status: draft
owner: research
updated: 2026-07-15
normative: false
---

# 调研综合结论

状态：`draft`
研究日期：2026-07-15

## 决策摘要

ProofForge V2 是一个 Lean 4 多目标语义编译器，而不是把多套 SDK 藏在一个命令后的代码生成器。用户只写 `program Name where`；源码没有执行类别。target 选择制品形态，requirements 决定该 target 是否能保持业务语义。

## 统一与分离

统一层负责：DSL、类型/effect、逻辑状态、确定性 step semantics、requirements、诊断、provenance 和参考解释器。

目标层负责：ABI、物理状态布局、授权/调用协议、提交边界、资源规则、机器 IR、proof wiring、制品和部署/验证流程。每个目标拥有其 Plan；family 只用于文档导航。

Wasm 只共享 AST/encoder/structural validator。NEAR、CosmWasm、Soroban、ICP 分别拥有 Plan。ZK 也不是一个 Plan：Noir 是 circuit、OpenVM 是 zkVM、Aleo/Psy 是 ZK application chain。

## 第一阶段

实现顺序：

1. DSL、typed program、semantic core、requirements 和参考解释器。
2. EVM、Solana、NEAR、Noir 四个 materializer。
3. Counter 四目标语义差分；PrivateSum4 披露测试。
4. runtime/proof、reproducibility、archive isolation gates。

CosmWasm、Soroban、ICP、OpenVM、Aleo、Psy 只完成 decision-complete dossier 与 roadmap。它们不得出现空实现、假 registry 支持或“生成了文本所以 supported”的声明。

## 关键不变量

- `--target` 不得改变 source semantics。
- 未满足 requirement 必须精确失败。
- Plan/TargetIR 不得擦除为无类型 payload。
- 披露、授权、状态托管是不同维度。
- circuit/zkVM 没有 settlement adapter 时不得称为 deployable contract。
- 父项目只作研究参考，不能成为依赖、oracle 或 fallback。

## 证据阶梯

```text
specified
→ implemented
→ artifact_validated
→ local_runtime_validated
→ network_or_proof_validated
```

文档或静态 golden 不能替代更高等级证据。每个目标 README 状态必须取已记录的最低完整等级。

## 未关闭的研究项

- 冻结 CosmWasm transaction/reply profile。
- 选择单一 OpenVM 版本线。
- 冻结 Leo 4.x 具体编译器与 network profile。
- 在版本化 sandbox 中复现 Psy compiler、deploy、proof 和 finalization。
- 验证 Lean persistent attribute 的跨模块、重复导入和增量编译行为。

## 实施准入

只有当对应 ADR accepted、language/semantic/capability/backend/output specs accepted、target dossier 无未决语义问题、test spec 为每条 requirement 提供正负场景时，目标代码任务才可开始。Phase 1 的四个目标也必须逐个满足该条件，不能因为已列入范围而跳过。
