# Algorand AVM 目标

状态：**Research（文档优先候选）**

候选 target id：**`algorand-avm`**

英文权威文档：[../../targets/algorand-avm.md](../../targets/algorand-avm.md)

## 结论

Algorand 应归类为 AVM / TEAL source 或 package-generation 目标，而不是
EVM、Wasm-host、Move、Solana sBPF、TVM、UTXO script 或 ZK circuit 目标。

```text
Algorand AVM 目标
  -> 生成或包装 Algorand Python / TypeScript / TEAL package
  -> Puya / AlgoKit compile path
  -> approval + clear-state AVM programs，或 LogicSig program
  -> ARC-4 / ABI 和 app spec metadata
  -> localnet 或 simulator-backed application call validation
```

Algorand Python / TypeScript 是高层开发表面，但 ProofForge 的目标边界应是
AVM 执行模型和制品模型。

## 对 ProofForge 的含义

`algorand-avm` 应先作为文档优先的 Research candidate。第一步不直接加入
`ProofForge.Target.Registry`。

目标特有问题包括：

- stateful applications 有 approval program 和 clear-state program；
- stateless smart signatures 使用 LogicSig program，是另一种制品形态；
- public method dispatch 通常通过 ABI / ARC-4 conventions 表达；
- persistent data 可以是 global state、account-local state 或 box storage；
- application calls 访问 accounts、assets、boxes 或 other apps 时需要显式
  resource references；
- transactions 可以 atomic group 组合，合约可以检查 grouped transactions；
- applications 可以提交 inner transactions；
- native assets 是 Algorand Standard Assets，而不是 ERC-20-like contracts；
- AVM opcode costs、program limits 和 minimum balance requirements 会影响
  lowering 与 validation。

Algorand 有 cryptographic primitives，也有 consensus-level state proofs，但这个
目标不是 ZK circuit sourcegen target。只有当 Algorand 应用目标实际验证或消费
proof data 时，才应把相关语义建模为能力。

## 候选能力

以下能力应先作为候选项保留在文档中：

| 候选能力 | 含义 |
|---|---|
| `avm.application` | target 发射 stateful application approval 和 clear-state programs。 |
| `avm.logicsig` | target 发射 stateless LogicSig program。 |
| `abi.arc4` | 构建输出或验证 ARC-4 ABI / app spec metadata。 |
| `storage.global` | contract 使用 application global state。 |
| `storage.local` | contract 使用 account-local application state。 |
| `storage.box` | contract 使用 box storage，并带显式 box references。 |
| `tx.group` | contract 依赖 atomic transaction group ordering 或 inspection。 |
| `tx.resource_refs` | app call 需要显式 accounts、assets、apps 或 boxes references。 |
| `itxn.submit` | application 提交 inner transactions。 |
| `asset.asa` | contract 处理 Algorand Standard Assets。 |
| `gas.avm_budget` | lowering 跟踪 AVM opcode budget、costs 和 program limits。 |
| `artifact.algokit` | 构建输出 AlgoKit / Puya app artifacts 和 validation metadata。 |

## 两条接入路线

1. **Algorand Python 或 TypeScript package sourcegen**：先生成或包装一个小型
   Algorand application，通过 AlgoKit / Puya 编译并在 localnet 或 simulator-backed
   app-call flow 中验证。这是最保守路线。
2. **Restricted TEAL / AVM emitter**：在 package route 澄清制品和验证形态后，
   再考虑直接发射受限 TEAL / AVM 子集。

## 第一阶段非目标

- 不把 `algorand-avm` 加入代码 registry。
- 不把 Algorand 归类为 Wasm-host、EVM、Move、Solana、TVM、UTXO 或 ZK
  circuit sourcegen。
- 不把 Algo payment 建模成 EVM call value。
- 不把 global、local 和 box storage 当成一个无差别 map。
- 不隐藏 app-call resource references。
- 不从 stateful application-only spike 推导出 LogicSig support。
- 在存在本地 compile 和 app-call smoke 前，不声称支持 Algorand output。
