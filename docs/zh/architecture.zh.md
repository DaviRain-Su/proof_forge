# 规范编译器架构

ProofForge 将合约语义与目标物化分离。公开编译路径为：

```text
Legacy v1 适配器或 Surface v2
  -> CanonicalContract + CanonicalEvidence
  -> 已检查的 CanonicalContract + CapabilityPlan
  -> 目标语义计划
  -> 现有目标渲染器与制品流水线
```

## 输入边界

- **Legacy v1** 是冻结的 `ProofForge.IR.Contract` 兼容输入，仅用于迁移和
  parity 测试，不再承载新语法。
- **Surface v2** 是新可移植能力的独立编写输入，直接规范化为 canonical
  contract。
- 两条路径在共享子集上必须产生相同的已检查语义，由 canonical parity
  门禁强制验证。

`CanonicalContract` 只包含语义数据：类型、逻辑状态、入口、控制流、effect、
host operation 和与源码无关的标识。`CanonicalEvidence` 包含诊断、源码位置、
迁移来源和比较追踪。Evidence 不得影响能力选择、目标计划、渲染制品或哈希。

## 状态所有权

Canonical 层拥有标量、Map、数组、Queue、Set 等**逻辑状态**及其操作，但不
分配 EVM slot、Solana 账户偏移或 Wasm 线性内存地址。每个目标语义计划负责
物理分配并在渲染前验证目标约束。渲染器只消费计划，不从源码语法或 evidence
重新推导布局。

## 公开目标路径

Canonical 实现复用现有计划与渲染器，不公开平行的 `*-core` 目标 id，也不把
skeleton 制品描述为受支持输出。

| 公开目标 id | Canonical 物化 | 现有输出流水线 |
|---|---|---|
| `evm` | `ProofForge.Backend.Evm.Plan.Core.buildFromCore` | EVM `ModulePlan` -> Yul -> `solc` |
| `solana-sbpf-asm` | `ProofForge.Backend.Solana.Plan.Core.buildFromCore` | `SolanaModulePlan` -> sBPF 汇编 -> ELF |
| `wasm-near` | `ProofForge.Backend.Wasm.NearModulePlan.Core.buildFromCore` | `NearModulePlan` -> Wasm AST/WAT -> Wasm |

不支持的 canonical 操作在渲染前失败。公开目标 id 始终选择该路径，生产流程
不存在退回 Legacy lowering 的 fallback。

## 回滚窗口

Canonical 提升后的一个发布版本内，冻结的 Legacy 适配器和 dual-run 比较工具
仅保留给测试。它们可通过比较语义、计划和制品诊断回归，但 CLI、registry 和
产品编译器不能选择 Legacy fallback。窗口结束时应删除比较代码；如需保留，
必须通过新的决策明确理由和截止时间。

目标实现约束见[后端接口](backend-interface.zh.md)，可执行门禁见
[验证门禁](validation-gates.zh.md)。
