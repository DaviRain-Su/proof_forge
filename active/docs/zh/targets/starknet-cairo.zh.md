# Starknet Cairo 目标

状态：**Research（文档优先候选）**

候选 target id：**`starknet-cairo`**

英文权威文档：[../../targets/starknet-cairo.md](../../targets/starknet-cairo.md)

## 结论

Starknet 应归类为 Cairo / Sierra / CASM sourcegen 目标，而不是 generic ZK
circuit sourcegen。它和 `psy-dpn` 的区别是：Starknet 的产品目标是 chain
contract class 和 deployed contract instance，`psy-dpn` 的主制品是 circuit package。

```text
Starknet Cairo 目标
  -> 生成或包装 Cairo package
  -> Scarb build
  -> Sierra contract class 和 CASM artifact
  -> ABI、class hash、declare/deploy metadata
  -> Starknet Foundry 或 devnet validation
```

## 对 ProofForge 的含义

`starknet-cairo` 应先作为文档优先的 Research candidate。第一步不直接加入
`ProofForge.Target.Registry`。

目标特有问题包括：

- Cairo source 编译为 Sierra 和 CASM 后再 declare/deploy；
- contracts 有 class declarations 和 deployed instances；
- account abstraction 是 Starknet 原生语义；
- contract address、class hash、selector 和 ABI 是 target-native；
- storage paths、maps、components 和 events 遵循 Cairo / Starknet 规则；
- cross-contract calls 使用 Starknet dispatchers / syscalls；
- L1/L2 messaging 不是普通 contract call。

## 候选能力

| 候选能力 | 含义 |
|---|---|
| `vm.cairo` | target 发射 Starknet Cairo source。 |
| `artifact.sierra` | 构建输出 Sierra contract class artifacts。 |
| `artifact.casm` | 构建输出 CASM artifacts。 |
| `class.declare` | deployment flow 包含 class declaration。 |
| `class.hash` | artifact 记录 class hash 和 class identity。 |
| `abi.starknet` | 构建输出 Starknet ABI 和 selector metadata。 |
| `storage.starknet` | contract 使用 Starknet storage paths、maps、components。 |
| `account.abstraction` | target 依赖 Starknet account-contract semantics。 |
| `syscall.starknet` | contract 使用 Starknet syscalls。 |
| `message.l1_l2` | contract 发送或消费 L1/L2 messages。 |
| `fee.starknet` | artifact 记录 Starknet fee / resource constraints。 |
| `test.snforge` | validation 使用 Starknet Foundry 或 devnet。 |

## 两条接入路线

1. **Cairo package sourcegen**：先生成或包装一个 Scarb package，编译到
   Sierra/CASM，并用 `snforge` 或 devnet-backed tests 验证。
2. **Restricted Cairo IR**：在 package route 验证 artifact shape 后，再定义
   Cairo-compatible IR，建模 storage、events、external/view functions 和
   dispatchers。

## 第一阶段非目标

- 不把 `starknet-cairo` 加入代码 registry。
- 不把 Starknet 归类为 EVM、Wasm-host、Move、Solana、TVM、AVM、UTXO 或
  `psy-dpn` 风格 ZK circuit sourcegen。
- 不隐藏 Sierra / CASM / class-hash metadata。
- 不把 token movement 建模成 EVM call value。
