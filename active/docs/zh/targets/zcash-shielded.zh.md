# Zcash Shielded 目标

状态：**Research（文档优先候选）**

候选目标 id：**`zcash-shielded`**

本文记录 ProofForge 对 Zcash 的第一版分类。它不会立刻添加 Lean target
profile。目的是在修改 registry 或编译器前，先确定 Zcash 的 ZK 隐私模型如何
进入目标系统。

主要来源：

- [How is Zcash different than Bitcoin?](https://z.cash/learn/how-is-zcash-different-than-bitcoin/)
- [Zcash protocol specification](https://zips.z.cash/protocol/protocol.pdf)
- [ZIP 224: Orchard Shielded Protocol](https://zips.z.cash/zip-0224)
- [Zcash RPC documentation](https://zcash.github.io/rpc/)
- [z_sendmany RPC](https://zcash.github.io/rpc/z_sendmany.html)

## 分类

Zcash 比账户型智能合约链更接近 Bitcoin，但不应该被并入 Bitcoin
Script/Miniscript 目标。

更合适的第一版分类是：

```text
Zcash privacy UTXO payment target
  with Bitcoin-derived transparent transaction support
  with Sapling/Orchard shielded pools
  with consensus-verified ZK proofs for shielded spends and outputs
```

ZK 部分不是通用的“在脚本里验证任意证明”。Zcash 共识验证的是 Zcash
交易格式中的证明。这些证明证明的是协议特定语句：shielded note、
nullifier、commitment tree、value balance 和授权。

这让 Zcash 与现有 ProofForge 目标家族不同：

- Bitcoin Script/Miniscript：只表达 spending policy，没有 shielded note
  系统。
- BCH/CashScript：UTXO script/covenant sourcegen，没有原生 shielded pool。
- Kaspa Toccata：在 covenant 执行中可选 inline proof verification。
- Psy/DPN：目标程序编译为 ZK circuit 制品。

## ZK 如何进入 JDL-Z11-like 脚本

面向用户的脚本不能假装 Zcash 暴露了带私有存储的通用链上合约方法。类似
JDL-Z11 的脚本应该通过受限的 privacy transaction DSL 使用 Zcash ZK：

```text
shielded zcash OrchardPayment {
  spend note input0 proving:
    owner_authorized(input0)
    note_in_commitment_tree(input0, anchor)
    nullifier_is_fresh(input0)

  create note output0:
    recipient = bob_unified_address
    value = private amount
    memo = private memo

  public:
    pool = orchard
    anchor = current_orchard_anchor
    nullifiers = [nf(input0)]
    value_balance = 0
    fee = transparent fee
}
```

脚本描述的是证明义务和交易形态。后端不会把它降级为 Bitcoin Script，也不会
降级为 Zcash 的“合约函数”。它会降级为 shielded transaction manifest：

```text
ProofForge script
  -> privacy-aware portable IR subset
  -> Zcash Orchard/Sapling transaction builder inputs
  -> proving manifest and witness requirements
  -> Zcash transaction with shielded proof bundle
  -> zcashd / lightwallet / library-backed validation
```

关键边界：

- private note value、recipient data、memo 和 witness path 仍是链下 witness
  data；
- public transaction data 包含协议暴露的 anchors、nullifiers、value balance、
  fees 和 pool/action metadata；
- ProofForge 可以证明自身 source-level invariant：用户想表达的是哪种 payment
  policy；
- Zcash 共识验证的是协议 ZK proof，不是任意 ProofForge 业务逻辑。

换句话说，Zcash ZK 在脚本中的用法是**内建的 confidential payment
primitive**，不是任意可编程 verifier。

## 为什么这对 ProofForge 重要

把 Zcash 简化成“Bitcoin plus ZK”太粗。transparent 侧可以复用 Bitcoin-like
UTXO 概念，但 shielded 侧需要目标专属建模：

- shielded state 是 note set 和 commitment tree，不是 global contract
  storage；
- note spend 通过公开 nullifier 防止双花，但不公开被花费的 note；
- proof statement 由 Sapling/Orchard 协议规则固定；
- value conservation 通过 shielded value balance 和 transparent turnstile
  执行；
- viewing key 和 wallet scanning 是链下可观测性工具，不是合约状态；
- privacy 取决于 transaction construction policy，而不只是 proof 是否验证通过。

## 候选目标家族

在目标模型能表达 shielded note 和 privacy 能力前，不要把它加入
`ProofForge.Target.Registry`。

候选家族：

```text
privacy-utxo-zk-payment
```

候选制品形态：

```text
zcash-shielded-package
  - transparent input/output manifest
  - shielded pool selection: Sapling or Orchard
  - shielded note input/output schema
  - nullifier and anchor manifest
  - value-balance and fee manifest
  - proving/witness manifest
  - viewing-key and disclosure policy metadata
  - zcashd or library validation result
```

第一版制品不应该尝试成为可部署智能合约。第一个有价值的制品，是一个用于极小
shielded payment policy 的可审查 transaction/proof package。

## 候选能力

这些是 research candidate，不是规范 capability id。

当语义匹配时，transparent Zcash 流程可以复用已有 UTXO 和 Bitcoin 候选能力，
包括 `storage.utxo`、`tx.builder`、`signature.checksig`、`fee.weight` 和
`test.bitcoin_core` 风格的本地节点验证。shielded 路径需要新增能力：

| 候选能力 | 含义 |
|---|---|
| `privacy.shielded` | 目标使用 shielded value pool。 |
| `privacy.transparent` | 目标同时处理 transparent Zcash inputs 或 outputs。 |
| `pool.sapling` | 目标使用 Sapling shielded semantics。 |
| `pool.orchard` | 目标使用 Orchard shielded semantics。 |
| `note.shielded` | state/value unit 是 shielded note。 |
| `note.commitment` | 制品记录 note commitment 语义。 |
| `nullifier.reveal` | spend 公开 nullifier 作为 double-spend guard。 |
| `anchor.commitment_tree` | spend 针对 commitment tree anchor 证明 membership。 |
| `zk.zcash_proof` | 交易携带 Zcash protocol proof。 |
| `zk.witness` | 构建需要用于 proving 的 private witness data。 |
| `value.balance` | 制品记录 shielded value-balance constraints。 |
| `key.viewing` | validation/disclosure 可以使用 viewing keys。 |
| `address.unified` | 目标处理 unified addresses 和 receiver selection。 |
| `privacy.policy` | 制品记录允许的信息泄漏。 |
| `test.zcashd` | validation 使用 zcashd RPC 或兼容本地库。 |

`zk.circuit` 不是 Zcash 的第一能力。只有未来辅助目标在 Zcash 共识证明系统之外
生成或验证自定义电路时，它才可能适用。对普通 Zcash 转账来说，proof circuit
由协议固定。

## 实现路径

### Road 1: Transparent Zcash UTXO

用这条路径验证 Bitcoin-derived transaction handling，不触碰 shielded proofs。

第一版 spike：

- 构造一个 transparent Zcash transaction 场景；
- 在安全处复用 Bitcoin-like UTXO 和 fee metadata；
- 记录 Zcash network、address、fee 和 transaction-version 差异；
- 通过 zcashd RPC 或兼容本地库验证。

这只是 stepping stone。它不能证明 ProofForge 已经能使用 Zcash 的 ZK 能力。

### Road 2: Orchard Shielded Payment Manifest

这是第一条真正的 Zcash ZK 集成路径。

第一版 spike：

- 定义一个 one-input、one-output shielded payment policy；
- 建模 shielded note、commitment anchor、nullifier、value balance、fee 和
  recipient；
- 生成 transaction/proving manifest，而不是 raw proving internals；
- 调用 zcashd RPC、lightwallet flow 或 Rust library boundary 来生成或验证交易；
- 记录哪些是 public、哪些仍是 private witness data、viewing-key disclosure 能
  揭示什么。

除非工具链阻塞让 Sapling 在本地容易很多，否则这条路径应从 Orchard 开始。

### Road 3: JDL-Z11-like Privacy DSL Frontend

当 transaction manifest 形态明确后，再走这条路径。

第一版 spike：

- 定义 script-level primitives，例如 `shield`、`spendNote`、`createNote`、
  `revealNullifier`、`selectAnchor` 和 `privacyPolicy`；
- 静态拒绝不支持的模式，例如 global mutable shielded storage、contract method
  dispatch、arbitrary proof verification，以及从 public code 读取 private note
  data；
- 将脚本降级到 Road 2 manifest；
- 保持 proof generation boundary 显式，让用户能审计需要哪些 witness fields。

该脚本是 policy 和 transaction-construction DSL，不是链上合约语言。

## 第一阶段非目标

- 在候选能力完成审查前，不要把 `zcash-shielded` 加入代码 registry。
- 不把 Zcash 归类为通用智能合约链。
- 不把 Zcash shielded logic 降级到 Bitcoin Script 或 Miniscript。
- 第一版 spike 不让 ProofForge 负责实现 Orchard/Sapling proving internals。
- 不声称 Zcash 支持 arbitrary ZK verification。
- 不把 shielded notes 建模为 EVM-style global storage。
- 如果交易跨越 transparent 和 shielded pools 并泄漏 sender、recipient 或 amount
  信息，不声称它具备完整隐私。

## Research 退出标准

Zcash 只有在满足以下条件后才能离开 Research：

- 经过审查的 target profile proposal；
- 针对 shielded notes、nullifiers、anchors、value balance 和 privacy policy 的
  已提交 capability proposal；
- 针对 transparent 和 shielded transaction 路径的最小 artifact manifest schema；
- 本地验证工具链决策，可能是 zcashd RPC 或 Rust wallet/protocol library
  boundary；
- 一个可重复的本地命令或脚本，能够验证极小 shielded payment manifest，或记录
  明确的外部工具阻塞。
