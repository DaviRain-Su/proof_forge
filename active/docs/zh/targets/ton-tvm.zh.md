# TON TVM 目标

状态：**Research（文档优先候选）**

候选 target id：**`ton-tvm`**

英文权威文档：[../../targets/ton-tvm.md](../../targets/ton-tvm.md)

## 结论

TON 不应归类为 Wasm-host 目标。第一版分类应是 TVM / Tolk sourcegen 目标。

```text
TON TVM 目标
  -> Tolk source 或更底层的 TON contract package
  -> 通过 TON tooling 生成 Fift / TVM code
  -> cell/slice storage 和 TL-B serialization
  -> message handlers 和 get methods
  -> action list / outbound messages
```

当前 TON 文档将 Tolk 作为推荐的 smart-contract language，并将 Acton 作为推荐的一体化 toolchain。FunC/Fift 的历史知识仍然重要，因为 TVM 与 cells 仍是执行和数据基底。

## 对 ProofForge 的含义

`ton-tvm` 应先作为文档优先的 Research candidate。第一步不直接加入 `ProofForge.Target.Registry`。

目标特有问题包括：

- contract state 序列化到 cells，而不是 slots 或 account resources；
- entrypoint 是 message handler 和 get method；
- inbound message 可以是 internal 或 external，并带 TON 特有 body、value、bounce 和 sender 语义；
- outbound effects 通过 action list 表达，尤其是 send message；
- serialization / ABI 表面是 TL-B / cell-oriented；
- gas 和 fee 与 TVM execution、storage、forwarding 和 message handling 绑定；
- account lifecycle 和 execution phases 会影响行为；
- sharding 和异步 messaging 使同步 cross-contract 假设不安全；
- wallet、jetton、NFT 等标准合约是目标原生表面。

## 候选能力

以下能力应先作为候选项保留在文档中：

| 候选能力 | 含义 |
|---|---|
| `storage.cell` | contract state 编码为 cells、slices、builders。 |
| `abi.tlb` | 构建输出或验证 TL-B/cell layout metadata。 |
| `message.recv` | contract 处理 internal 或 external inbound messages。 |
| `message.send` | contract 通过 action semantics 发出 outbound messages。 |
| `method.get` | contract 暴露 off-chain get methods。 |
| `action.list` | target effects 累积在 TVM action lists 中。 |
| `state.init` | deploy 需要 code/data `StateInit` handling。 |
| `account.status` | account lifecycle/status 影响行为。 |
| `gas.tvm` | TVM gas 和 fee model 显式存在。 |
| `asset.jetton` | contract 集成 TON jetton/token standards。 |

## 两条接入路线

1. **Tolk package sourcegen**：先生成或包装 Tolk contract，用推荐 TON toolchain 验证。这是最保守路线。
2. **Lower-level TVM/cell IR**：在 sourcegen spike 澄清 contract shape 后，再考虑更直接地目标 TVM 与 cell/slice serialization IR。

## 第一阶段非目标

- 不把 `ton-tvm` 加入代码 registry。
- 不把 TON 归类为 Wasm-host、EVM、Move 或 ZK circuit sourcegen。
- 不把 TON storage 当成 EVM slot。
- 不把 message send 当成同步 cross-contract call。
- 不把 get method 和 message handler 当成同一种 entrypoint。
- 不用 generic JSON ABI 隐藏 cell / TL-B layout。
