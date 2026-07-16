# Tezos Michelson/LIGO 目标

状态：**Research（文档优先候选）**

候选 target id：**`tezos-michelson-ligo`**

英文权威文档：[../../targets/tezos-michelson-ligo.md](../../targets/tezos-michelson-ligo.md)

## 结论

Tezos 应归类为 Michelson source/artifact 目标，第一条接入路线建议使用 LIGO
sourcegen，再编译为 Michelson contract。

```text
Tezos Michelson/LIGO 目标
  -> 生成或包装 LIGO source
  -> compiled Michelson contract
  -> parameter / storage / entrypoint schema
  -> operation-list、view、event metadata
```

它不是 EVM、Wasm-host、Move、Solana、TVM、AVM、UTXO script 或 ZK circuit
sourcegen。

## 对 ProofForge 的含义

`tezos-michelson-ligo` 应先作为文档优先的 Research candidate。第一步不直接加入
`ProofForge.Target.Registry`。

目标特有问题包括：

- entrypoint 接收参数，并返回 operation list 和 new storage；
- storage 是 typed Michelson / Micheline value，不是 slot map；
- `big_map` 有目标特有的 persistence 与 indexing 行为；
- views 和 events 是独立 public surfaces；
- tickets、Sapling、delegation 和 tokens 都需要单独能力审查；
- gas 和 storage burn 不同于 EVM gas。

## 候选能力

| 候选能力 | 含义 |
|---|---|
| `vm.michelson` | target 发射或验证 Michelson code。 |
| `abi.entrypoint` | 构建输出 entrypoint / parameter schema metadata。 |
| `storage.micheline` | storage 编码为 typed Micheline data。 |
| `storage.big_map` | contract 使用 Tezos `big_map` storage。 |
| `operation.list` | entrypoint 返回 Tezos operations list。 |
| `view.contract` | contract 暴露 Tezos views。 |
| `events.tezos` | contract 发射 Tezos events。 |
| `ticket.handle` | contract 创建、转移或消费 tickets。 |
| `privacy.sapling` | contract 使用 Sapling state 或 transactions。 |
| `delegate.set` | contract 可以 change 或 clear delegation。 |
| `gas.tezos` | artifact 记录 Tezos gas / storage-burn constraints。 |
| `artifact.ligo` | 构建输出 LIGO 和 compiled Michelson metadata。 |

## 两条接入路线

1. **LIGO sourcegen**：先生成或包装一个 LIGO Counter contract，通过本地测试或
   sandbox 调用 entrypoint 并检查 storage。
2. **Restricted Michelson IR**：在 LIGO route 验证 artifact shape 后，再定义
   stack/effect IR，显式建模 storage update、operation list 和 views。

## 第一阶段非目标

- 不把 `tezos-michelson-ligo` 加入代码 registry。
- 不把 Tezos 归类为 EVM、Wasm-host、Move、Solana、TVM、AVM、UTXO 或 ZK。
- 不用 generic cross-contract calls 隐藏 operation-list semantics。
- 不把 `big_map`、tickets 或 Sapling 当成普通 maps/assets。
