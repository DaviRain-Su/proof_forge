# Kaspa Toccata 目标

状态：**Research（文档优先候选）**

候选 target id：**`kaspa-toccata`**

英文权威文档：[../../targets/kaspa-toccata.md](../../targets/kaspa-toccata.md)

## 结论

Toccata 不应该先被归类为类似 `psy-dpn` 的“ZK 电路源代码生成目标”。

更准确的第一版分类是：

```text
Kaspa L1 UTXO covenant 目标
  支持 transaction v1
  可选支持 inline proof verification
  另有 based app 结算架构
```

也就是说，Toccata 的 ZK 是能力和结算模式，不是整个目标家族的唯一身份：

- Inline ZK：covenant spend 在脚本内验证证明，并把证明输出绑定到后继 covenant state。
- Based app：用户通过 L1 user lane 提交普通交易 payload；链下状态机执行逻辑；L1 settlement covenant 验证 lane activity 和新状态承诺。

这和 `psy-dpn` 不同。`psy-dpn` 的主制品是 circuit/proof-oriented 程序制品；Toccata 的主制品仍然应是 Kaspa covenant / transaction package，只是可以携带证明验证。

## 对 ProofForge 的含义

第一步不应该直接改 `ProofForge.Target.Registry`。应先把 UTXO/covenant 语义讲清楚，再决定正式 capability id。

候选能力先只放在文档里：

| 候选能力 | 含义 |
|---|---|
| `storage.utxo` | 状态位于 covenant 控制的 UTXO 或状态承诺中。 |
| `covenant.lineage` | 后继输出保持在被授权的 covenant family 中。 |
| `tx.v1` | 目标依赖 Kaspa transaction v1 语义。 |
| `tx.compute_budget` | v1 input 显式携带脚本执行预算。 |
| `lane.user` | app operation 可以通过 user lane 排序和锚定。 |
| `zk.verify` | 脚本验证 L1 支持的证明。 |
| `zk.proof` | 目标流程可能包含证明生成或 settlement proof 处理。 |

`zk.circuit` 不适合作为 Toccata base path 的能力。只有辅助证明程序目标才可能需要它。

## 三条接入路线

1. **L1 covenant app**：适合状态小、公开、可切分为独立 UTXO lane 的应用。第一步应研究 Silverscript 或手写 covenant source，而不是自造 Kaspa script generator。
2. **Inline ZK covenant**：适合单个 covenant transition 私密或昂贵的场景。关键是证明必须绑定正确的 program、public input、旧状态承诺、新状态承诺和后继输出。
3. **Based app settlement**：适合多用户修改共享链下状态的应用。它是执行架构，不是简单的智能合约后端。

## 第一阶段非目标

- 不在 capability 设计完成前把 `kaspa-toccata` 加入代码 registry。
- 不把 Toccata 伪装成通用 ZK circuit target。
- 不把 Kaspa covenant state 当成 EVM slot storage。
- 不把 user lane 当成 account-chain shard。
- 不在第一版 covenant spike 中让 ProofForge 承担证明系统内部实现。

