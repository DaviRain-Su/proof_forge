---
id: TARGET-NOIR
title: Noir target dossier
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# Target Dossier：Noir

状态：`proposed`
Target ID：`noir`
Phase 1：实现

## 1. 身份与来源

Noir 是 backend-agnostic circuit language/toolchain；Nargo 负责 compile/execute/prove/verify workflow，证明后端另行选择。依据官方 [Getting Started](https://noir-lang.org/docs/getting_started_manually) 与 [Unconstrained Functions](https://noir-lang.org/docs/noir/concepts/unconstrained)（`SRC-NOIR-001/002`，verified）。

## 2. 执行、状态、调用、失败与资源

- 执行：程序成为约束关系；inputs 分 public 与 private witness。
- 状态：没有原生持久链状态；有状态 `program` 编译为显式 pre/post state 或 commitments。
- 调用：只支持可内联/可约束的内部函数；链上外部调用不是原生能力。
- 失败：constraint unsatisfied 与 witness generation/tool failure 分开。
- 资源：constraint count、Brillig、proof backend memory/time 进入 profile/evidence。

## 3. Portable fragment 与扩展

Portable：有限域/固定宽度整数、Bool、固定数组/struct、有界控制流、纯函数、assert、public/private/commitment disclosure、确定性 state transition relation。

Phase 1 禁止 unconstrained functions、oracle、foreign calls、无界循环和动态分配。后续只能通过带 soundness obligation 的版本化 extension 开启。

## 4. `NoirPlan` schema

```text
NoirPlan {
  profile, fieldModel,
  publicInputs, privateWitnesses,
  preState, postState, commitments,
  constraints, assertions,
  outputDisclosure, backendPolicy
}
```

Plan 必须明确状态连续性为 `external`，并绑定每个 public/witness value 到源 span；不能根据 target 自动把所有输入改成 private。

## 5. Target IR 与制品

`NoirPlan → NoirAST → .nr → ACIR/ABI`。输出 `.nr`、package/config、ACIR、ABI、witness schema、proof/VK metadata 和 manifest。proof、VK 与 semantic/profile hash 绑定。

## 6. 工具链

固定 `nargo/noirc` 与选定 proving backend（如 Barretenberg）的 exact version、binary digest 和 CRS/profile。当前文档研究不冻结最终版本；实现任务开始前补齐 lock。

## 7. 证明流程

compile → execute/witness → prove → verify。Counter 的 logical pre/post state 都作为 relation inputs/outputs；ProofForge 不声称 proof 自动更新任何链。若未来增加 settlement adapter，作为独立 target/profile 评审。

## 8. 安全

关注 under-constrained witness、public/private 标注错误、field/integer wrap mismatch、range constraints、unconstrained Brillig、oracle 信任、commitment domain separation、proof/VK/config substitution。

## 9. 验证阶梯

1. AST/.nr/ABI golden。
2. requirements 到 constraints 的单元/属性测试。
3. Nargo compile + valid/invalid witness。
4. pinned backend prove/verify 与 proof binding 检查。
5. Counter 四目标差分和 PrivateSum4 不泄露 witness。

## 10. 不支持、风险与成熟度退出

Phase 1 不支持 recursive proof、oracle、foreign call、dynamic collections、chain settlement。退出条件：Counter relation、PrivateSum4、invalid witness、overflow range constraint、完整 prove/verify、repeatable manifest 全部通过；输出标为 `provable-circuit` 而非 deployable contract。
