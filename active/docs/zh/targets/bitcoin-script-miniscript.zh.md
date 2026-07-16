# Bitcoin Script/Miniscript 目标

状态：**Research（文档优先候选）**

候选 target id：**`bitcoin-script-miniscript`**

英文权威文档：[../../targets/bitcoin-script-miniscript.md](../../targets/bitcoin-script-miniscript.md)

## 结论

Bitcoin base layer 应归类为受限 UTXO spending-policy 目标，而不是通用
smart-contract chain。

```text
Bitcoin Script/Miniscript 目标
  -> 生成或包装 policy / Miniscript / descriptor
  -> Script、witness script 或 Tapscript output
  -> PSBT 或 raw transaction scenario
  -> Bitcoin Core regtest / testmempoolaccept / script verification validation
```

它适合表达 multisig、hash locks、time locks、Taproot script paths、descriptors
和 PSBT flows。不应承诺 global mutable state、method dispatch、events 或同步
cross-contract calls。

## 对 ProofForge 的含义

`bitcoin-script-miniscript` 应先作为文档优先的 Research candidate。第一步不直接加入
`ProofForge.Target.Registry`。

目标特有问题包括：

- state 和 value 位于 UTXOs，不是 accounts 或 contract storage；
- scripts lock outputs，witnesses unlock them；
- policy 通常表达谁可以花、何时可以花、需要哪些 signature 或 preimage；
- standardness、relay policy、transaction weight、fee rate、dust 和 script limits
  会影响 artifact 是否实际可用；
- Taproot / Tapscript 和 legacy P2SH / P2WSH 的 signature、address、script
  semantics 不同；
- output descriptors 和 Miniscript 是比 raw Script 更安全的第一阶段 artifact；
- PSBT 或 raw transaction construction 是 validation 的一部分。

## 候选能力

| 候选能力 | 含义 |
|---|---|
| `script.bitcoin` | target 发射 Bitcoin Script 或 script fragments。 |
| `script.miniscript` | target 发射可分析的 Miniscript policy。 |
| `descriptor.output` | target 发射 Bitcoin Core output descriptors。 |
| `script.segwit` | target 发射 P2WPKH/P2WSH 等 SegWit v0 script paths。 |
| `script.taproot` | target 发射 Taproot key-path 或 script-path outputs。 |
| `script.tapscript` | target 发射或验证 Tapscript semantics。 |
| `witness.stack` | artifact 声明 required witness stack items。 |
| `sighash.mode` | signature semantics 依赖显式 sighash flags。 |
| `hashlock.preimage` | spending policy 依赖揭示 hash preimages。 |
| `multisig.threshold` | spending policy 使用 threshold signatures 或 multisig structure。 |
| `psbt.flow` | validation 使用 PSBT creation、signing 和 finalization。 |
| `policy.standardness` | artifact 检查 relay/mining standardness policy。 |
| `fee.weight` | artifact 记录 transaction weight、vbytes、fee 和 dust constraints。 |
| `test.bitcoin_core` | validation 使用 Bitcoin Core regtest 或 RPC checks。 |

其中 `storage.utxo`、`script.p2sh`、`script.unlocker`、`timelock.locktime`、
`signature.checksig` 和 `tx.builder` 应复用已有 UTXO 候选能力语义。

## 两条接入路线

1. **Miniscript / descriptor sourcegen**：先生成 spending policy、Miniscript 和
   descriptor，再通过 Bitcoin Core regtest / PSBT flow 验证。
2. **Restricted Script / Tapscript emitter**：在 policy route 明确 artifact shape
   后，只对可静态分析的 signature、threshold、hash lock 和 time lock policy 发射
   Script 或 Tapscript。

## 第一阶段非目标

- 不把 `bitcoin-script-miniscript` 加入代码 registry。
- 不把 Bitcoin 归类为 EVM、Wasm-host、Move、Solana、TVM、AVM 或通用
  smart-contract platform。
- 不把 UTXO data 当成 global mutable storage。
- 不从基本 Script 支持推导出 covenant/state-machine support。
- 不把 BCH/CashScript semantics 当成 Bitcoin semantics。
- 不隐藏 PSBT / transaction-building requirements。
