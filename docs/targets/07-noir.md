---
id: TARGET-NOIR
title: Noir target dossier
status: proposed
owner: architecture
updated: 2026-07-30
normative: true
---

# Target Dossier：Noir

状态：`proposed`
Target ID：`noir`
Phase 1：实现

## 当前工程迁移状态（非 formal 完成）

`planFromCapability` 已直接读取 retained `SemanticProgramV1` 并在 target 内重新执行 structure gate；
Noir module 内 `alphaResidualOf`、`makePlanFromAlpha`、alpha requirement re-derive均已归零。当前只
lower NormalizeV1 当前 public-UInt64 envelope 的 anonymous UInt64/Unit、public state/params/results、
single-block initializer/entry/view 与 literal/stateLoad/checked add-sub/stateStore/return；dense `ValueId`、
expanded-tree cost及 store/return effect segment均 fail closed，并继续支持 stateless relation。checked-sub
source先约束 `lhs >= rhs`，再执行 `u64` subtraction；仍无 ACIR/runtime proof evidence。

`NoirPlan.sourceHash/semanticHash` 由 `CompiledSemanticV1` 的 canonical source/semantic Digest在
Plan边界派生；carrier不存第二份 hash字符串，也不依赖 alpha residual。`TargetDescriptor` 已删除
residual requirement list，Noir engineering plan-hash descriptor preimage只编码 target/profile/axis identity。
这些仍是 engineering Plan identity，
不是 formal BuildIdentity/Plan digest。现有 maturity仍是 relation IR与source package：无 ACIR/witness/proof/VK/verify，不关闭 formal Noir
milestone。

## 1. 身份与来源

Noir 是 backend-agnostic circuit language/toolchain；Nargo 负责
compile/execute/prove/verify workflow，证明后端另行选择。Noir 的 public input 写成
`name: pub Type`，未标 `pub` 的参数是 private witness；原生 `u64` 有 64-bit range，普通
整数加法在 overflow 时失败。依据官方 [Getting Started](https://noir-lang.org/docs/getting_started_manually)、
[Data Types](https://noir-lang.org/docs/noir/concepts/data_types)、
[Integers](https://noir-lang.org/docs/noir/concepts/data_types/integers)、
[Assert](https://noir-lang.org/docs/noir/concepts/assert) 与
[Unconstrained Functions](https://noir-lang.org/docs/noir/concepts/unconstrained)
（`SRC-NOIR-001..005`，verified；`CLM-NOIR-001..003`）。

## 2. 执行、状态、调用、失败与资源

- 执行：程序成为约束关系；inputs 分 public 与 private witness。
- 状态：没有原生持久链状态；有状态 `program` 编译为显式 pre/post state 或 commitments。
- 调用：只支持可内联/可约束的内部函数；链上外部调用不是原生能力。
- 失败：constraint unsatisfied 与 witness generation/tool failure 分开。
- 资源：constraint count、Brillig、proof backend memory/time 进入 profile/evidence。

## 3. Portable fragment 与扩展

目标 portable fragment 包含有限域/固定宽度整数、Bool、固定数组/struct、有界控制流、
纯函数、assert、public/private/commitment disclosure 与确定性 state transition relation。
当前已实现的 alpha slice 仅为 `UInt64`、Bool lifecycle、literal/parameter/state load、
checked add/sub、store、return；不能把目标范围误写成当前覆盖范围。

Phase 1 禁止 unconstrained functions、oracle、foreign calls、无界循环和动态分配。当前
`commitmentOnly` 输入也 fail closed；后续只能通过带 soundness obligation 的版本化
extension 开启。

## 4. `NoirPlan` schema

```text
NoirPlan {
  targetDescriptor, semanticSchemaVersion,
  codegenProfile, sourceDialect,
  continuity, failurePolicy, proofStatus,
  resourceLimits,
  programName, sourceHash, semanticHash, planHash,
  states[], relations[] {
    index, name, artifactStem, mode,
    params[] { sourceId, inputIndex, visibility },
    inputs[] { name, sourceName, type, visibility, role },
    body[]
  }
}
```

Plan 不保存 `SemanticProgram`。有状态程序必须有且只有一个首位 initializer relation；每个
initializer、mutate、view 都是独立 relation，禁止用 selector 和 inactive witness 把它们折叠
进一个电路。状态连续性固定为 `external-public-pre-post`：initializer 约束
`pre_initialized=false`、业务初始化和 `post_initialized=true`；mutate/view 约束
`true → true`，view 还必须逐字段约束 `postState = preState`。当前 state 与 result 都是
verifier-visible；参数严格保留源语义的 public/private disclosure，不能根据 target 自动改写。
`sourceId`、规范输入索引与 domain-separated complete Plan hash 提供当前 in-process 完整性
检查。该 self-hash 不是不可信序列化 Plan 的真实性证书，CLI 也不接受外部 Plan 输入；源
span/origin 尚未进入 `SemanticProgram`，所以正式 `TST-NOIR-001` 仍未关闭。

## 5. Target IR 与制品

当前路径是：

```text
SemanticProgramV1
  → NoirPlan
  → typed RelationIR { ValueRef, checkedAdd, assertEqual, assertBool }
  → one Noir package per relation
```

每个 package 只输出 `Nargo.toml` 与 `src/main.nr`；根目录输出
`<Program>.noir-relations.json`，记录 Plan hash、relation catalog、输入 role/visibility、continuity、原生
checked-u64 算术与 `proofStatus=not-produced`。`checkedAdd` 直接生成原生 `u64 + u64`，依赖
Noir 的整数 range/checked-overflow 语义，不先提升到 `Field` 后再遗漏 range constraint。官方
文档同时说明未使用的 overflow computation 可能被删除；因此当前 lowering 对每个 checked-add
做反向 liveness 检查，若结果没有传递到最终 post-state/result equality 就 fail closed，而不是
生成可能消除 overflow 的 source。

当前 profile 是 `noir-source-u64-relations-v1`、dialect 是
`noir-native-u64-relations-v1`；OutputSet 的 primary role 是 `noir-source-package`，exact
`ArtifactDeployability=intermediate-only`，`securityContract=null`。它不生成
ACIR、noirc ABI、witness、proof、VK 或 verification result，也不生成伪造示例值的
`Prover.toml`。未来完整路径才是 `.nr → ACIR/ABI → witness → proof/VK/verify`，届时所有
proof-stage artifact 必须绑定 semantic/profile/catalog hash。

## 6. 工具链

最终必须固定 `nargo/noirc` 与选定 proving backend（如 Barretenberg）的 exact version、
binary digest 和 CRS/profile。当前 lock 未包含 Nargo/Barretenberg，本机也没有可作为证据的
批准工具链；package 因此不写会被误解为 binary pin 的宽松 prerelease version range。
当前 intermediate profile 的 `securityContract=null`。未来 `noir-acir-proof-v1` 必须引用
[`SPEC-SEC-001`](../specs/security.md) 的 exact `ZkBackendSecurityProfileV1`，并在当前
`CandidateIdentity`/`BuildIdentity` 上验证未过期、未撤销的 formal `ZkSecurityApprovalV1`；只锁
Nargo/backend binary 而缺少 arithmetic、CRS、soundness、proof binding 与 privacy contract 时仍
不得进入 registry、build 或 prove。

## 7. 证明流程

目标流程是 compile → execute/witness → prove → verify。当前只完成 compile 之前的 typed
relation/source materialization，并用纯 Lean relation model 验证约束结构；该模型不是 Nargo、
ACIR execution、proof 或 verifier 证据。Counter/Accumulator 的 logical pre/post state 都是
external public relation inputs；ProofForge 不声称 proof 自动更新任何链。若未来增加
settlement adapter，作为独立 target/profile 评审。

## 8. 安全

关注 under-constrained witness、public/private 标注错误、field/integer wrap mismatch、range constraints、unconstrained Brillig、oracle 信任、commitment domain separation、proof/VK/config substitution。

## 9. 验证阶梯

1. Plan/typed IR/source/interface exact tests（当前已覆盖 Counter、Accumulator、PrivateSum4）。
2. 纯 Lean relation model 的 lifecycle、wrong result/state 与 `UInt64.max + 1` negatives
   （当前已覆盖，但不是 Noir runtime evidence）。
3. pinned Nargo compile + valid/invalid witness（未完成）。
4. exact ZK security profile/approval resolution 与 allowlist/CRS/substitution negatives（未完成）。
5. pinned backend prove/verify 与 proof/VK/public-input binding 检查（未完成）。
6. Counter 四目标差分和 UInt64 PrivateSum4 不泄露 witness（proof 部分未完成）。

## 10. 不支持、风险与成熟度退出

Phase 1 不支持 recursive proof、oracle、foreign call、dynamic collections、chain settlement。
当前只达到 source relation alpha：generic Accumulator materialization、exact artifact validation
和 repeatability 可以记录为静态编译证据，不能关闭 `TST-NOIR-004/005/006`。退出条件仍是
Counter/Accumulator relation、PrivateSum4、invalid witness、overflow、完整 prove/verify 与
repeatable proof-bound manifest 全部通过；此外必须关闭 `TST-ZKSEC-001`，不能用 source profile
或 development approval 代替。successor profile 的 proof artifact 使用 exact
`ArtifactDeployability=verifiable-workload`；没有 settlement adapter 时仍不是 deployable contract。
