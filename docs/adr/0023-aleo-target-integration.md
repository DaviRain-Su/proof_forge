---
id: ADR-0023
title: Aleo（Leo 4.0.2）capability-gated target 集成
status: proposed
owner: architecture
updated: 2026-07-31
normative: true
---

# ADR-0023：Aleo（Leo 4.0.2）capability-gated target 集成

## 状态

proposed（`agent/aleo-target-port` 分支产物；与黑客松 `hackathon/aleo-2026-08`
的 V1-direct 平行路径**不同**）

## 背景

黑客松分支 `hackathon/aleo-2026-08`（ADR-0022/0023 黑客松授权）验证了 Leo 4.0.2
的语法面与 devnet 证据链，但其两条路径（alpha `--target aleo` 挂旧 Registry、
V1-direct 直接消费 ValidatedSourceV1）都与当前产品架构冲突：产品链要求所有
target 经 capability 消费 retained `SemanticProgramV1`（sole NormalizeV1 生产者），
且 alpha Registry 签名（`materializeResult (program : SemanticProgram)`、
`checkSupport`）已删除。

本 ADR 把 Aleo 移植为**第 5 个 capability-gated target leaf**：不合并黑客松分支，
复用其 Leo 4.0.2 语法知识（`Final`/`final {}` 模型、mapping 读写仅 finalization
context、原生 checked 算术 halt-on-overflow）与证据结论。

## 决策

1. **架构对齐**：`ProofForgeV2/Targets/Aleo.lean` 与 EVM/Solana/NEAR/Noir 同构——
   `planFromCapability`/`irFromCapability`/`buildFromCapability` 消费
   `ResolvedEngineeringBuildV1` → retained `SemanticProgramV1`；target-owned
   Plan/IR；emitter 产出 Leo 4.0.2 source。无 V1-direct 第二语义路径。
2. **Registry**：`TargetRegistryV1` 冻结 seed 中 aleo 由 design-only 提升为
   implemented（5 implemented + 5 design-only）；`DescriptorDataV1.aleo`；
   `RequirementResolverV1` 增加 aleo 行（**honest 4-key 子集**：state.persistent、
   value.checked-arithmetic、value.bool、failure.atomic-rollback；排除
   `effect.event` 与两个 call 家族）。
3. **Leo 4.0.2 语义映射**（基于黑客松 spike + devnet 证据）：
   - mapping 是唯一状态；读写仅 finalization context → state-touching callable
     物化为 `fn ... -> Final { return final { ... } }`
   - `Final` 函数无法返回值 → 非 Unit entry 记录 `resultDropped`（显式 Plan
     元数据，非静默省略），返回值交易后经 `leo query` 观察；dropped 表达式仍
     在 final block 内求值以保留失败语义（panic = revert）
   - 原生 u64 算术 checked（halt-on-overflow，spike 验证）；div/mod 零除显式
     `assert(rhs != 0u64)`；移位显式 `assert(count < 64u64)`
   - 嵌套 div/mod/shift 逐节点 guard + let 绑定（EVM statement 形纪律）
   - bounded `for`：常数界 Leo for + `if start < end { assert(end - start <= N) }`
     守卫 + 运行时 `c < (end - start)` 门控（boundExceeded halt = revert，
     可观察等价）
4. **Honest fail-closed**：`emit`（无链上事件日志）、带参 `revert`（payload 不可
   表示）、computed state-reading view → fail closed；bare `revert`/`trap` →
   `assert(false)`（halt = revert）；bare state-read view → 离链 `leo query`
   描述符（EVM `eth_call` 类比）。
5. **成熟度**：source-only（零工具 finalization，同 Noir 先例）；不声明
   leo build/execute/proof/deploy 证据。formal D4–D7 完成态不因本切片改变。

## 理由

- 唯一不违反"sole NormalizeV1 生产者 + capability-only Plan"边界的方式；
  黑客松的 Leo 语法证据是高质量输入，但代码形态必须重建。
- honest 子集由 main 的 per-target capability gate 机制承载（Wave I 已落地）。
- `resultDropped` 采用黑客松 alpha 设计的显式元数据方案，杜绝静默省略。

## 影响

- `TargetRegistryV1` 成员从 4+6 变为 5+5（相关测试同步更新）。
- `Materialization/Protocol.ArtifactEncoding` 增加 `leoSource`。
- CLI `--target aleo`/`build-counter --target aleo` 可用（source-only 产物）。
- 不改变任何既有 target 语义；不删除任何既有能力。

## 备选

- 合并黑客松分支（拒绝：双语义引擎 + 已删 API 复活 + ADR 编号冲突）。
- V1-direct 作为产品路径（拒绝：第二 AST 语义解释，产品禁例）。
- 保持 design-only（拒绝：Leo 语法面与 devnet 证据已充分，值得产品化）。
