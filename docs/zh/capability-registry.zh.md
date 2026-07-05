# 能力注册表

状态：**草案规范 (Phase 1)**

用于目标 profile、制品元数据和编译时拒绝的规范能力 id。语义含义与 [RFC 0002](rfcs/0002-target-implementation-design.md) 中的矩阵保持一致。

图例：**Y** 已支持（计划中或已实现），**P** 部分支持/仅限 spike，**N** 不支持，**—** 不适用。

## 与目标 id 的关系

- 目标 id 记录在 `docs/decisions.md` 中，并由 `docs/rfcs/0002-target-implementation-design.md` 汇总。
- 此注册表拥有能力 id，而非目标生命周期阶段。
- 文档不得为相同的语义发明替代 id。

## 与 Contract Intent 和 Target Extension 的关系

capability id 是 target selection 之后使用的下层协议，不是默认面向用户的 SDK。portable contract 通常应调用链中立的 Contract Intent API。所选 target adapter 会把这些 intent 解析为 capability plan，然后在降级前检查本注册表。

Target Extension SDK 可以暴露 Solana PDA/CPI/runtime allocator 配置、Move resource 或 UTXO covenant primitive 等目标特定操作。这些 extension 仍通过 capability id 和 target metadata 路由，使诊断、制品元数据和跨 target 支持检查保持统一。

## 核心能力

> **Solana** 列反映规范的 `solana-sbpf-asm` 路线（D-026）：直接生成
> sBPF assembly。Solana 使用 `crosscall.cpi`（不是 `crosscall.invoke`）和
> `storage.pda`，这些按 D-027 保持为 Solana 特定能力。

| 能力 id | 可移植含义 | EVM | NEAR | CosmWasm | Solana | Aptos | Sui | Psy DPN |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `storage.scalar` | 单个持久化标量 | Y | Y | Y | Y | Y | Y | Y |
| `storage.map` | 键值对或映射存储 | Y | Y | Y | P | P | P | P |
| `storage.array` | 固定大小的索引存储数组 | P | P | N | Y | N | N | P |
| `caller.sender` | 交易签名者/调用者 | Y | Y | Y | Y | Y | Y | P |
| `value.native` | 调用附带的原生代币 | Y | Y | Y | Y | Y | Y | P |
| `events.emit` | 结构化日志/事件输出 | Y | Y | Y | Y | Y | Y | Y |
| `crosscall.invoke` | 调用另一个合约/程序 | Y | N | Y | N | Y | Y | P |
| `env.block` | 区块高度/时间/链 id 读取 | Y | Y | P | P | P | P | P |
| `control.conditional` | 使用目标支持的布尔谓词进行语句级条件分支 | P | P | N | Y | N | N | P |
| `control.bounded_loop` | 目标可展开或静态处理的有界循环 | N | P | N | P | N | N | P |
| `data.fixed_array` | 固定大小数组值类型、字面量和索引表达式 | P | P | N | Y | N | N | P |
| `data.struct` | 结构体值类型、字面量和字段访问 | P | P | N | Y | N | N | P |
| `crypto.hash` | 宿主或库哈希 | Y | Y | Y | Y | Y | Y | Y |
| `assertions.check` | 从 portable IR 语句发射运行时或电路断言 | Y | Y | N | Y | N | N | P |
| `account.explicit` | 具名账户/对象/资源绑定 | P | Y | N | Y | Y | Y | P |
| `storage.pda` | 程序派生地址状态 | N | N | N | Y | N | N | N |
| `runtime.allocator` | 目标运行时堆分配器约定 | N | Y | P | Y | P | P | P |
| `runtime.memory` | 目标运行时内存操作 | N | N | N | Y | N | N | N |
| `runtime.return_data` | 目标运行时返回数据缓冲区操作 | N | N | N | Y | N | N | N |
| `runtime.compute_units` | 目标运行时计算预算自省 | N | N | N | P | N | N | N |
| `crosscall.cpi` | 带有账户元数据的 Solana CPI | N | N | N | Y | N | N | N |
| `zk.circuit` | 将入口编译为目标电路定义 | N | N | N | N | N | N | Y |
| `zk.proof` | 目标证明生成或验证流 | N | N | N | N | N | N | P |

## Id 命名规则

- 格式：`<domain>.<operation>` 或 `<domain>.<variant>`（小写，点分隔）。
- 领域：`storage`, `caller`, `value`, `events`, `crosscall`, `env`, `control`, `data`, `crypto`, `assertions`, `account`, `runtime`, `zk`。
- 制品元数据列出了构建所使用的 id（参见 RFC 0002 制品 schema）。
- 诊断信息在拒绝时必须引用能力 id 和目标 id。

## 尚未注册的候选能力

这些候选项仅用于目标研究。在目标 profile 和 lowering 规则被接受前，不要将它们加入
`ProofForge.Target.Capability`。

### Kaspa Toccata

参见 [Kaspa Toccata 目标](targets/kaspa-toccata.zh.md)。

| 候选 id | 可移植含义 | 为什么需要单独表达 |
|---|---|---|
| `storage.utxo` | 状态位于 covenant 控制的 UTXO 或状态承诺中 | 不是账户/对象存储，也不是 EVM slot |
| `covenant.lineage` | 后继输出保持在被授权的 covenant family 中 | 这是交易/输出校验，不是普通存储 |
| `tx.v1` | 目标使用 Kaspa transaction v1 语义 | 交易投影和 payload 规则会影响正确性 |
| `tx.compute_budget` | 每个 input 的脚本 compute budget 是显式字段 | 预算是交易设计的一部分，不只是 gas 计量 |
| `lane.user` | app operation 可以使用 user lane | based-app 排序和 proof anchoring 需要它 |
| `zk.verify` | 脚本验证 L1 支持的证明 | 不等同于把目标本身编译成电路 |

`zk.circuit` 仍保留给主制品是电路或电路导向源包的目标。Toccata 可以使用证明，但它的
base target 是 Kaspa covenant package。

### Stellar Soroban

参见 [Stellar Soroban 目标](targets/stellar-soroban.zh.md)。

大部分 Soroban 行为可以先从现有 Wasm-host 能力集开始，但若干目标语义还没有被当前 registry 覆盖。

| 候选 id | 可移植含义 | 为什么需要单独表达 |
|---|---|---|
| `auth.require` | 合约要求地址级 authorization payload | 比读取 caller/sender 更强、更结构化 |
| `auth.account_contract` | contract account 通过目标原生账户逻辑验证 authorization | Soroban account-contract flow 需要它 |
| `storage.ttl` | 状态条目有 TTL extension、archival 和 restoration 行为 | 标量/映射存储本身无法表达 |
| `artifact.contract_spec` | 构建输出包含 tooling 和 bindings 使用的 contract interface/spec metadata | 这是制品级要求，不是运行时存储 |
| `asset.stellar` | 合约使用 Stellar Asset Contract 或 token-interface 集成 | 原生资产表面不同于通用 `value.native` |

### Internet Computer

参见 [Internet Computer 目标](targets/internet-computer.zh.md)。

ICP canister 与 Wasm-host 家族有重叠，但在添加 target profile 前，需要显式表达若干 canister 语义。

| 候选 id | 可移植含义 | 为什么需要单独表达 |
|---|---|---|
| `abi.candid` | 构建输出并验证 Candid service interface | 公开 ABI 不只是导出的 Wasm symbol |
| `canister.method_mode` | entrypoint 区分 update、query 和 composite query method | call mode 影响 persistence、consensus 和 call restrictions |
| `storage.stable_memory` | 状态使用 stable memory 或 stable structures 跨 upgrade 保留 | 标量/映射存储本身无法表达 |
| `storage.orthogonal_persistence` | 状态遵循 Motoko-style orthogonal persistence 语义 | 不同于显式 key-value store |
| `principal.id` | caller/canister/user identity 是 Principal | 不是 EVM address 或通用 account id |
| `cycles.manage` | 目标可以 inspect、accept、send 或 account for cycles | cycles 是资源计量，不是普通 `value.native` |
| `crosscall.async` | cross-canister call 是异步消息流 | 不同于同步 contract call |
| `canister.lifecycle` | 目标支持 install、upgrade、stop/start 和 lifecycle hooks | lifecycle 是 deployment 与 state safety 的一部分 |
| `certified.data` | 目标暴露 certified variables 或 certified data responses | IC certification pattern 需要它 |
| `management.canister` | 目标可以调用 virtual management canister | system lifecycle API 是目标原生能力 |

### Algorand AVM

参见 [Algorand AVM 目标](targets/algorand-avm.zh.md)。

Algorand 与通用合约能力有部分重叠，但 AVM programs、storage classes、transaction groups 和 explicit resource references 在添加 target profile 前需要显式表达。

| 候选 id | 可移植含义 | 为什么需要单独表达 |
|---|---|---|
| `avm.application` | target 发射 stateful application approval 和 clear-state programs | application artifact 有两个 AVM programs 和 app lifecycle semantics |
| `avm.logicsig` | target 发射 stateless LogicSig program | LogicSig 是独立的 stateless authorization artifact，不是 app call |
| `abi.arc4` | 构建输出或验证 ARC-4 ABI / app spec metadata | public method shape 是 tooling-visible metadata，不只是导出的代码 |
| `storage.global` | contract 使用 application global state | limits 和 access rules 不同于 local 或 box state |
| `storage.local` | contract 使用 account-local application state | state 按 account 和 app 索引，不是 global contract map |
| `storage.box` | contract 使用 box storage，并带显式 box references | box access 需要 resource references 和 budget planning |
| `tx.group` | contract 依赖 atomic transaction group ordering 或 inspection | group semantics 是目标原生 transaction context |
| `tx.resource_refs` | app call 需要显式 accounts、assets、apps 或 boxes references | resource availability 会影响 AVM execution 能否访问数据 |
| `itxn.submit` | application 提交 inner transactions | inner effects 是 transaction-level，不是同步 method call |
| `asset.asa` | contract 处理 Algorand Standard Assets | native asset model 不同于通用 `value.native` |
| `gas.avm_budget` | lowering 跟踪 AVM opcode budget、costs 和 program limits | AVM budget constraints 不是 EVM gas 或 Wasm host fuel |
| `artifact.algokit` | 构建输出 AlgoKit / Puya app artifacts 和 validation metadata | 目标工具链需要 app spec 和 bytecode package metadata |

### Cardano Plutus/Aiken

参见 [Cardano Plutus/Aiken 目标](targets/cardano-plutus-aiken.zh.md)。

Cardano 与 UTXO covenant 目标有重叠，但 eUTXO validator roles、datum、redeemer、script context、execution units 和 Plutus blueprint metadata 在添加 target profile 前需要显式表达。

| 候选 id | 可移植含义 | 为什么需要单独表达 |
|---|---|---|
| `storage.eutxo` | state 和 value 位于 eUTXO outputs | 不是账户/对象存储或 global contract state |
| `validator.spend` | target 发射 spending validator | spending validator 有 datum/redeemer/script-context 语义 |
| `validator.mint` | target 发射 minting policy | minting policy 语义不同于 spending validation |
| `validator.withdraw` | target 发射 withdrawal validator | withdrawal validation 是 Cardano 独立角色 |
| `datum.inline` | contract 依赖 inline datum encoding | datum placement 会影响 transaction construction 和 validation |
| `redeemer.input` | entrypoint arguments 是 redeemers | arguments 来自 transaction redeemers，不是 method calldata |
| `tx.script_context` | validator 读取 Cardano script context | context 是 validation correctness 的核心 |
| `tx.validity_range` | validator 约束 slot/time validity | validity ranges 不同于通用 block reads |
| `tx.balancing` | validation 包含 transaction balancing 和 fee handling | off-chain transaction construction 是实际正确性的一部分 |
| `asset.native_token` | contract 处理 Cardano native multi-assets | native asset model 不同于通用 `value.native` |
| `budget.exunits` | artifact 记录 Plutus execution units | execution-unit budgeting 是目标特有能力 |
| `artifact.plutus_blueprint` | 构建输出 CIP-57 blueprint metadata | blueprint metadata 是 Cardano tooling surface 的一部分 |

### Tezos Michelson/LIGO

参见 [Tezos Michelson/LIGO 目标](targets/tezos-michelson-ligo.zh.md)。

Tezos 与通用 contract storage 和 entrypoints 有部分重叠，但 Michelson typed data、operation-list effects、views、events、tickets 和 gas/storage-burn 语义需要在添加 target profile 前显式表达。

| 候选 id | 可移植含义 | 为什么需要单独表达 |
|---|---|---|
| `vm.michelson` | target 发射或验证 Michelson code | Michelson 是 typed stack VM，有目标特有约束 |
| `abi.entrypoint` | 构建输出 entrypoint/parameter schema metadata | public entrypoint shape 是 target-visible metadata |
| `storage.micheline` | storage 编码为 typed Micheline data | 不是 EVM slots 或 generic JSON |
| `storage.big_map` | contract 使用 Tezos `big_map` storage | `big_map` persistence/indexing 不同于普通 maps |
| `operation.list` | entrypoint 返回 Tezos operations list | effects 是返回数据，不是 direct synchronous calls |
| `view.contract` | contract 暴露 Tezos views | views 是独立 public read surface |
| `events.tezos` | contract 发射 Tezos events | event payload 和 indexing semantics 是目标原生语义 |
| `ticket.handle` | contract 创建、转移或消费 tickets | tickets 是 native linear assets，不是 generic tokens |
| `privacy.sapling` | contract 使用 Sapling state 或 transactions | privacy state 是目标原生且非通用 |
| `delegate.set` | contract 可以 change 或 clear delegation | delegation 是 Tezos-specific operation |
| `gas.tezos` | artifact 记录 Tezos gas/storage-burn constraints | fee model 不同于 EVM gas 和 Wasm fuel |
| `artifact.ligo` | 构建输出 LIGO 和 compiled Michelson metadata | 目标工具链要求 |

### Starknet Cairo

参见 [Starknet Cairo 目标](targets/starknet-cairo.zh.md)。

Starknet 与 contract storage、events 和 calls 有部分重叠，但 Cairo/Sierra/CASM artifacts、class hashes、account abstraction、syscalls 和 L1/L2 messaging 在添加 target profile 前需要显式表达。

| 候选 id | 可移植含义 | 为什么需要单独表达 |
|---|---|---|
| `vm.cairo` | target 发射 Starknet Cairo source | Cairo 是 source language 和 execution model boundary |
| `artifact.sierra` | 构建输出 Sierra contract class artifacts | Sierra 是必需的 intermediate contract class metadata |
| `artifact.casm` | 构建输出 CASM artifacts | CASM 是不同于 source 和 ABI 的目标制品 |
| `class.declare` | deployment flow 包含 class declaration | Starknet 将 declaring a class 与 deploying an instance 分离 |
| `class.hash` | artifact 记录 class hash 和 class identity | class hash 是 deployment 和 upgrade semantics 的一部分 |
| `abi.starknet` | 构建输出 Starknet ABI 和 selector metadata | ABI shape 不是 EVM ABI |
| `storage.starknet` | contract 使用 Starknet storage paths/maps/components | storage paths 和 components 是目标原生语义 |
| `account.abstraction` | target 依赖 Starknet account-contract semantics | accounts 是 contract-level protocol participants |
| `syscall.starknet` | contract 使用 Starknet syscalls | calls、deploys、events、storage 和 messaging 使用 syscall surfaces |
| `message.l1_l2` | contract 发送或消费 L1/L2 messages | messaging 不同于普通 contract calls |
| `fee.starknet` | artifact 记录 Starknet fee/resource constraints | fee/resource model 是目标特有语义 |
| `test.snforge` | validation 使用 Starknet Foundry 或 devnet | local smoke tooling 是 target validation 的一部分 |

### Aleo Leo

参见 [Aleo Leo 目标](targets/aleo-leo.zh.md) 和
[docs/zh/superpowers/specs/2026-07-01-aleo-leo-design.zh.md](superpowers/specs/2026-07-01-aleo-leo-design.zh.md)。

Aleo 与 source-generation 和 ZK 目标有重叠，但它的 contract model 有明确的
proof/finalization split。private execution 生成 transitions 和 proofs；public
finalization 在链上更新 mappings 或 storage。Records、program ids、imports、
Aleo Instructions、Aleo VM bytecode、ABI、prover/verifier artifacts、fees 和
devnet validation 在添加 target profile 前需要显式表达。

#### 规范能力（Road 1 spike）

以下能力已被第一个 `aleo-leo` spike 接受，并在设计规格中文档化。在 spike 成功前，
它们**不会**被加入 `ProofForge.Target.Capability`。

| 能力 id | 可移植含义 | 为什么需要单独表达 |
|---|---|---|
| `lang.leo` | target 发射 Leo source packages | Leo 是第一版稳定 sourcegen boundary |
| `vm.aleo_avm` | target 运行在 Aleo VM 上 | 避免与 Algorand AVM 混淆 |
| `artifact.avm` | build 发射 Aleo VM bytecode | deployment artifact 是目标原生制品 |
| `artifact.aleo_abi` | build 发射 Aleo ABI metadata | ABI shape 遵循 Aleo program interfaces |
| `execution.finalize` | program 有公开链上 finalization logic | finalization 是 public 且 validator-executed |
| `state.mapping` | public state 位于 mappings | mappings 是链上公开 key-value state |
| `input.public` | function input 是 public data | public inputs 在 transaction context 中可见 |
| `output.public` | function output 是 public | public outputs 需要显式 metadata |
| `test.leo` | validation 使用 Leo tests | local validation 是目标工具链 |

#### 研究候选能力（未来 spike）

以下能力仍作为候选，直到 private records、transitions、proofs、imports、deployment
或 devnet validation 被纳入范围。

| 候选 id | 可移植含义 | 为什么需要单独表达 |
|---|---|---|
| `ir.aleo_instructions` | build 发射或消费 Aleo Instructions | Aleo lower-level compiler target 不同于 Leo |
| `proof.prover_key` | build 或 execute flow 生成 prover artifacts | proof generation 有 target-owned artifacts |
| `proof.verifier_key` | build 或 deploy flow 记录 verifier artifacts | verification keys 属于 deployment/execution metadata |
| `execution.transition` | entry execution 生成 transition 和 proof | transition 是 Aleo function-call unit |
| `state.record` | private state 位于 encrypted records | records 是 UTXO-like，不是 EVM storage |
| `state.storage` | public state 可使用 storage variables 或 storage vectors | Aleo storage 不同于 mappings 和 private records |
| `input.private` | function input 是 private proof-context data | privacy 是 function signature 的一部分 |
| `output.private` | function output 默认 private | output visibility 是目标语义 |
| `program.import` | program import 并调用另一个 Aleo program | cross-program calls 生成 composed transitions/finalization |
| `program.upgrade` | deployment 可支持显式 program upgrades | upgrade rules 是 program/deploy metadata |
| `transaction.execute` | validation 可生成 execute transaction | execute transactions 携带 transitions 和 proofs |
| `transaction.deploy` | validation 可生成或检查 deploy transaction | deploy 发布 program code 和 verification metadata |
| `fee.credits` | fees 以 Aleo Credits 支付，可 public 或 private | fee visibility 和来源会影响 privacy 与 validation |
| `test.aleo_devnet` | validation 使用 Leo devnet 或 devnode-backed flows | network-backed smoke 不同于 local compile/test |

现有 `zk.circuit` capability 不足以描述 Aleo。它可以描述 proof surface 的一部分，
但 Aleo 还需要 program、transaction、state-record、finalization 和 artifact
能力。

### TON TVM

参见 [TON TVM 目标](targets/ton-tvm.zh.md)。

TON 与通用合约能力有部分重叠，但 TVM cells、messages 和 actions 在添加 target profile 前需要显式表达。

| 候选 id | 可移植含义 | 为什么需要单独表达 |
|---|---|---|
| `storage.cell` | contract state 编码为 TVM cells、slices 和 builders | 不是 EVM slot storage 或 host KV |
| `abi.tlb` | 构建输出或验证 TL-B/cell layout metadata | 公开数据形态是 cell-oriented |
| `message.recv` | contract 处理 internal 或 external inbound messages | entrypoint 形态由 message 驱动 |
| `message.send` | contract 通过 action semantics 发出 outbound messages | 不是同步 cross-contract calls |
| `method.get` | contract 暴露 off-chain get methods | 不同于会改变状态的 message handlers |
| `action.list` | target effects 累积在 TVM action lists 中 | send/deploy/reserve effects 需要它 |
| `state.init` | deploy 需要 code/data `StateInit` handling | deployment artifact 是目标原生制品 |
| `account.status` | account lifecycle/status 影响行为 | uninit/active/frozen/deleted handling 需要它 |
| `gas.tvm` | TVM gas 和 fee model 显式存在 | 不是通用 EVM gas 或 host fee metering |
| `asset.jetton` | contract 集成 TON jetton/token standards | 原生 token standard 不同于 `value.native` |

### Bitcoin Script/Miniscript

参见 [Bitcoin Script/Miniscript 目标](targets/bitcoin-script-miniscript.zh.md)。

Bitcoin 与 UTXO script targets 有重叠，但 base-layer Script 更适合建模为 spending policy，而不是 general contract execution。Miniscript、descriptors、Taproot/Tapscript、PSBT flows、standardness 和 weight/fee checks 在添加 target profile 前需要显式表达。

| 候选 id | 可移植含义 | 为什么需要单独表达 |
|---|---|---|
| `script.bitcoin` | target 发射 Bitcoin Script 或 script fragments | Bitcoin Script 有独立的 consensus 和 standardness rules |
| `script.miniscript` | target 发射可分析的 Miniscript policy | 对 spending policies 来说，它比 raw Script 更适合作为第一制品 |
| `descriptor.output` | target 发射 Bitcoin Core output descriptors | descriptors 驱动 wallet/address/script workflows |
| `script.segwit` | target 发射 P2WPKH/P2WSH 等 SegWit v0 script paths | SegWit witness semantics 不同于 legacy script paths |
| `script.taproot` | target 发射 Taproot key-path 或 script-path outputs | Taproot 改变 address、commitment 和 spend semantics |
| `script.tapscript` | target 发射或验证 Tapscript semantics | Tapscript 改变 opcode 和 signature behavior |
| `witness.stack` | artifact 声明 required witness stack items | unlocking data 是 spend validation 的一部分 |
| `sighash.mode` | signature semantics 依赖显式 sighash flags | sighash choice 影响 signature commits to 的内容 |
| `hashlock.preimage` | spending policy 依赖揭示 hash preimages | 常见 Bitcoin contract primitive |
| `multisig.threshold` | spending policy 使用 threshold signatures 或 multisig structure | 不等同于 account-level authorization |
| `psbt.flow` | validation 使用 PSBT creation、signing 和 finalization | 实际 Bitcoin workflows 依赖 transaction construction |
| `policy.standardness` | artifact 检查 relay/mining standardness policy | consensus-valid scripts 可能仍然 non-standard |
| `fee.weight` | artifact 记录 transaction weight、vbytes、fee 和 dust constraints | fee 和 relay viability 是实际正确性的一部分 |
| `test.bitcoin_core` | validation 使用 Bitcoin Core regtest 或 RPC checks | target validation 依赖 Bitcoin Core behavior |

Bitcoin 应在语义匹配时复用已有 UTXO candidate ids，包括 `storage.utxo`、`script.p2sh`、`script.unlocker`、`timelock.locktime`、`signature.checksig` 和 `tx.builder`。

### Zcash Shielded

参见 [Zcash Shielded 目标](targets/zcash-shielded.zh.md)。

Zcash 与 Bitcoin-derived UTXO flows 有重叠，但它的 shielded pools 不是普通
Bitcoin Script，也不是 generic ZK circuit target。Sapling/Orchard notes、
nullifiers、commitment tree anchors、value-balance constraints、viewing-key
disclosure 和 protocol-defined proofs 在添加 target profile 前需要显式表达。

| 候选 id | 可移植含义 | 为什么需要单独表达 |
|---|---|---|
| `privacy.shielded` | target 使用 shielded value pool | privacy 是 transaction construction property，不只是 proof flag |
| `privacy.transparent` | target 同时处理 transparent Zcash inputs 或 outputs | transparent 和 shielded pools 会泄漏不同信息 |
| `pool.sapling` | target 使用 Sapling shielded semantics | Sapling 有独立 notes、keys 和 proof semantics |
| `pool.orchard` | target 使用 Orchard shielded semantics | Orchard 有 action bundles 和 Halo 2 proof semantics |
| `note.shielded` | state/value unit 是 shielded note | 不是 EVM storage、account state 或普通 UTXO script data |
| `note.commitment` | artifact 记录 note commitment semantics | tree membership 和 output construction 需要它 |
| `nullifier.reveal` | spend 公开 nullifier 作为 double-spend guard | public nullifiers 是 shielded spend validity 的核心 |
| `anchor.commitment_tree` | spend 针对 commitment tree anchor 证明 membership | membership anchor 是 public proof statement 的一部分 |
| `zk.zcash_proof` | transaction 携带 Zcash protocol proof | circuit 由协议定义，不是 arbitrary application code |
| `zk.witness` | build 需要用于 proving 的 private witness data | witness data 必须留在链下，且边界可审计 |
| `value.balance` | artifact 记录 shielded value-balance constraints | shielded pools 与 transparent turnstiles 间的守恒是目标专属语义 |
| `key.viewing` | validation/disclosure 可以使用 viewing keys | 链下可观测性不是 contract state |
| `address.unified` | target 处理 unified addresses 和 receiver selection | address semantics 影响 pool choice 和 recipient leakage |
| `privacy.policy` | artifact 记录允许的信息泄漏 | zcashd 在 transaction construction 中暴露 privacy-policy 选择 |
| `test.zcashd` | validation 使用 zcashd RPC 或兼容本地库 | target validation 依赖 Zcash tooling，不只是 Bitcoin Core |

Zcash 在 transparent flows 中应在语义匹配时复用已有 UTXO candidate ids，包括
`storage.utxo`、`tx.builder`、`signature.checksig` 和 `fee.weight`。现有
`zk.circuit` capability 不是普通 Zcash shielded transfer 的第一抽象；它只适合
未来在 Zcash 共识证明系统之外做辅助 proof-program work。

### Bitcoin Cash CashScript

参见 [Bitcoin Cash CashScript 目标](targets/bitcoin-cash-cashscript.zh.md)。

BCH/CashScript 与 UTXO covenant 目标有重叠，但 CashVM、transaction introspection、CashTokens 和 transaction-builder 语义在添加 target profile 前需要显式表达。

| 候选 id | 可移植含义 | 为什么需要单独表达 |
|---|---|---|
| `storage.utxo` | state 和 value 位于 spendable UTXOs | 不是账户/对象存储或 global contract state |
| `script.p2sh` | contract deployment/addressing 使用 P2SH locking scripts | deployment/address surface 是目标原生能力 |
| `script.unlocker` | contract calls 是 selected UTXOs 的 unlocking scripts | 不是普通 method dispatch |
| `tx.introspection` | contract 读取当前交易 inputs/outputs 和 active input data | BCH CashVM 的核心 covenant mechanism |
| `covenant.introspection` | contract 通过 introspection 约束 successor outputs | covenant-style state transition 需要它 |
| `storage.local_state` | local state 通过 script data 或 CashTokens commitments 模拟 | 不是 persistent global storage |
| `asset.cashtoken` | contract 处理 CashTokens category、capability、NFT commitment 和 token amount | native asset model 不同于通用 `value.native` |
| `timelock.locktime` | contract 依赖 locktime、sequence 或 age checks | 不同于普通 block reads |
| `signature.checksig` | contract 将 signature verification 作为 spend condition | UTXO spend authorization 是 script-level |
| `artifact.cashscript` | 构建输出 CashScript artifact JSON 和 bytecode metadata | 目标工具链要求 |
| `tx.builder` | validation 包含构造并评估 spend transaction | 实际目标语义需要 transaction construction |

## EVM 映射 (基准)

| 能力 id | EVM 降级 |
|---|---|
| `storage.scalar` | `Storage.load` / `Storage.store` (sload/sstore) |
| `storage.map` | `Storage.mapLoad` / `Storage.mapStore` |
| `caller.sender` | `Env.sender` |
| `value.native` | `Env.value` |
| `events.emit` | `log0`–`log4` |
| `crosscall.invoke` | `call`, `staticcall`, `delegatecall`, `create`, `create2` |
| `env.block` | `Env.blockNumber`, `timestamp()`, `chainid()`, `gasprice()`, `gas()`, `basefee()`, `prevrandao()`, `coinbase()`, `blockhash(n)` |
| `account.explicit` | `address()` |

目前通过 `ProofForge.Evm` / `Lean.Evm` 实现 —— 参见 [targets/evm.md](targets/evm.md)。

## 工具链能力

这些能力描述的是 ProofForge 工具链产生的验证与建模产物，而非已部署目标的运行时行为。它们附加到 `quint` 伪目标，或任何真实目标的验证阶段。

| 能力 id | 可移植含义 | 状态 |
|---|---|:---:|
| `model.quint` | 目标从 portable IR 生成 Quint 状态机模型。 | 已实现 |
| `verify.model_check` | 生成的模型可通过 Apalache/TLC 用 `quint verify` 进行模型检查。 | 已实现（需要 Java 17+） |
| `verify.simulation` | 生成的模型可通过 `quint run` 进行仿真。 | 已实现 |
| `test.mbt_trace` | 生成的模型可产生 ITF 追踪，用于对 IR 语义进行回放。 | 已实现 |

## Phase 1 验收标准

- [ ] 此表中的每个 id 至少出现在一个目标的 `TargetProfile.capabilities` 中。
- [ ] EVM Counter 构建在制品元数据中列出 `storage.scalar`（以及其他使用的 id）。
- [ ] 在 EVM 上尝试 `storage.pda` 会失败并显示 `capability unsupported` 诊断信息。
- [ ] 当 RFC 0002 语义矩阵发生变化时，注册表保持同步。

## 更新日志

| 日期 | 变更 |
|---|---|
| 2026-06-30 | 初始注册表；取代中文技术方案中的临时 id |
| 2026-06-30 | 添加了 Psy DPN research 列和 ZK 能力 id |
