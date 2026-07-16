# Bitcoin Cash CashScript 目标

状态：**Research（文档优先候选）**

候选 target id：**`bch-cashscript`**

英文权威文档：[../../targets/bitcoin-cash-cashscript.md](../../targets/bitcoin-cash-cashscript.md)

## 结论

Bitcoin Cash 通过 CashScript 应归类为 UTXO script / covenant sourcegen 目标。

```text
Bitcoin Cash CashScript 目标
  -> 生成或包装 .cash source
  -> cashc contract artifact JSON
  -> BCH Script locking bytecode
  -> TypeScript SDK transaction builder / unlockers
  -> local MockNetworkProvider、chipnet 或 node-backed validation
```

BCH 不是 EVM、Wasm、Move、Solana，也不应简单叫“generic Bitcoin target”。它继承 UTXO 模型，但通过 CashVM upgrades、native introspection、CashTokens 等机制形成了自己的合约语义。

## 对 ProofForge 的含义

`bch-cashscript` 应先作为文档优先的 Research candidate。第一步不直接加入 `ProofForge.Target.Registry`。

目标特有问题包括：

- contracts lock UTXOs；contract functions 是 spend paths；
- 没有 global mutable contract state；
- constructor arguments 进入 locking script；
- function arguments 由 unlocking script 提供，必须视为不可信；
- covenants 通过 introspection 约束当前交易，尤其是 outputs；
- local state 可通过 CashTokens NFT commitments 或新的 P2SH locking bytecode 模拟；
- value 是 UTXO 上的 BCH satoshis；
- CashTokens 暴露 token category、capability、NFT commitment 和 fungible amount；
- SDK transaction builder 是实际目标表面的一部分。

## 候选能力

以下能力应先作为候选项保留在文档中：

| 候选能力 | 含义 |
|---|---|
| `storage.utxo` | state 和 value 位于 spendable UTXOs。 |
| `script.p2sh` | contract deployment/addressing 使用 P2SH locking scripts。 |
| `script.unlocker` | contract calls 是 selected UTXOs 的 unlocking scripts。 |
| `tx.introspection` | contract 读取当前交易 inputs/outputs 和 active input data。 |
| `covenant.introspection` | contract 通过 introspection 约束 successor outputs。 |
| `storage.local_state` | local state 通过 script data 或 CashTokens commitments 模拟。 |
| `asset.cashtoken` | contract 处理 CashTokens category、capability、NFT commitment 和 token amount。 |
| `timelock.locktime` | contract 依赖 locktime、sequence 或 age checks。 |
| `signature.checksig` | contract 将 signature verification 作为 spend condition。 |
| `artifact.cashscript` | 构建输出 CashScript artifact JSON 和 bytecode metadata。 |
| `tx.builder` | validation 包含构造并评估 spend transaction。 |

## 两条接入路线

1. **CashScript sourcegen**：先生成或包装 `.cash` 合约，通过 `cashc` 与 CashScript SDK 验证。这是最保守路线。
2. **Restricted UTXO covenant IR**：在 sourcegen spike 后，抽象 UTXO spend paths、successor-output constraints、active input、tokens 和 timelocks，再生成 CashScript。

## 第一阶段非目标

- 不把 `bch-cashscript` 加入代码 registry。
- 不把 BCH 归类为 EVM、Wasm-host、Move 或 generic Bitcoin。
- 不把 contract functions 当成 stateful method calls。
- 不把 UTXO-local state 当成 global storage。
- 不隐藏 transaction-builder requirements。
- 不把 CashTokens 当成 generic ERC-20-like assets。
