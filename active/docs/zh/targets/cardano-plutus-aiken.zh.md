# Cardano Plutus/Aiken 目标

状态：**Research（文档优先候选）**

候选 target id：**`cardano-plutus-aiken`**

英文权威文档：[../../targets/cardano-plutus-aiken.md](../../targets/cardano-plutus-aiken.md)

## 结论

Cardano 应归类为 eUTXO validator sourcegen 目标。第一条接入路线建议使用
Aiken sourcegen，再编译为 UPLC / Plutus validator artifacts 和 CIP-57 Plutus
Blueprint。

```text
Cardano Plutus/Aiken 目标
  -> 生成或包装 Aiken source
  -> compiled validators / UPLC artifacts
  -> Plutus blueprint metadata
  -> datum / redeemer / script-context transaction scenario
```

它不是 EVM、Wasm-host、Move、Solana、TVM、Algorand AVM，也不是 generic
Bitcoin-like UTXO。

## 对 ProofForge 的含义

`cardano-plutus-aiken` 应先作为文档优先的 Research candidate。第一步不直接加入
`ProofForge.Target.Registry`。

目标特有问题包括：

- contract logic 通过 datum、redeemer 和 script context 验证交易；
- persistent state 位于 UTXO 和 successor outputs；
- spending、minting、withdrawal validators 有不同语义；
- value 可包含 ADA 和 native multi-assets；
- validity range、signatories、execution units 和 transaction balancing 都会影响正确性；
- Plutus Blueprint 是 tooling-visible artifact metadata。

## 候选能力

| 候选能力 | 含义 |
|---|---|
| `storage.eutxo` | state 和 value 位于 eUTXO outputs。 |
| `validator.spend` | target 发射 spending validator。 |
| `validator.mint` | target 发射 minting policy。 |
| `validator.withdraw` | target 发射 withdrawal validator。 |
| `datum.inline` | contract 依赖 inline datum encoding。 |
| `redeemer.input` | entrypoint arguments 是 redeemers。 |
| `tx.script_context` | validator 读取 Cardano script context。 |
| `tx.validity_range` | validator 约束 slot/time validity。 |
| `tx.balancing` | validation 包含 transaction balancing 和 fee handling。 |
| `asset.native_token` | contract 处理 Cardano native multi-assets。 |
| `budget.exunits` | artifact 记录 Plutus execution units。 |
| `artifact.plutus_blueprint` | 构建输出 CIP-57 blueprint metadata。 |

## 两条接入路线

1. **Aiken sourcegen**：生成或包装一个 Aiken spending validator，用 UTXO datum
   表达 Counter-like state machine，并验证 successor output。
2. **Restricted Plutus/UPLC IR**：在 Aiken route 澄清 artifact 与 transaction
   semantics 后，再考虑直接面向 Plutus / UPLC 的受限 IR。

## 第一阶段非目标

- 不把 `cardano-plutus-aiken` 加入代码 registry。
- 不把 Cardano 归类为 EVM、Wasm-host、Move、Solana、TVM、AVM 或 generic UTXO。
- 不把 UTXO datum 当成 global mutable storage。
- 不隐藏 off-chain transaction-building requirements。
