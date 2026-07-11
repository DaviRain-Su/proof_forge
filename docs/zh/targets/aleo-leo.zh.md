# Aleo Leo 目标

状态：**Research sourcegen 注册目标**。`aleo-leo` 已进入 registry 和
`--list-targets`，但不声明最终可部署包。

目标 id：**`aleo-leo`**（`TargetFamily.zkCircuitSourcegen`，
`ArtifactKind.leoSource`）

本文记录 ProofForge 对 Aleo 的分类和当前受限的 Leo sourcegen 边界。进入 registry
不代表所有 portable contract 都可降级；完整 Counter 就因 getter ABI 无法保持而拒绝。

主要交付物：

- `ProofForge.Backend.Aleo.IR` 通过通用 IR→AST→source 流水线降级已验证子集。
- 完整 Counter 稳定 fail closed：Leo 4.0.2 无法从 `final` 返回 mapping-backed
  `get() -> U64`，后端不会把它悄悄改成 `Final`。
- `scripts/aleo/counter-smoke.sh` 验证该拒绝；write-only Counter fragment 是编译正例。
- `FunctionPlan` 只允许 pure、Unit-returning final，以及返回值与状态无关的
  `(T, Final)`；metadata 使用同一 plan。
- `.add`/`.sub`/`.mul` 由表达式节点的 `overflowChecked` 位选择 checked 或
  Leo `_wrapped` 运算；`Module.overflowChecked` 仅控制没有节点级模式位的
  compound `AssignOp`。
- mixed `(T, Final)` 只接受保持原顺序的规范形：immutable pure prefix、连续
  final/storage region、单一 terminal state-independent return。mutable local、
  control flow、named crosscall 或 final region 后的 pure statement 都会 fail closed。
- linear record 会递归穿透 struct/fixed array 检测，并禁止出现在 state key/value。
- `Mapping::get_or_use` 需要默认值时，直接或递归嵌套在普通 value struct 中的
  `address` 都会 fail closed：Leo 4.0.2 不接受 `none` 作为 address，系统也不会
  伪造零地址。write-only address storage 仍然支持。
- 普通 value struct 禁止使用字段名 `owner`；该名称保留给 linear record，
  record 必需的 `owner: address` 正常支持。
- `proof-forge emit --target aleo-leo --fixture pure-math --format leo` 输出
  `PureMath.leo`。
- `Examples/Backend/Aleo/PureMath.golden.leo` 是已跟踪的 golden fixture。
- `scripts/aleo/pure-math-smoke.sh` 端到端验证 PureMath fixture。

主要来源：

- [Aleo getting started](https://docs.aleo.org/build/getting-started)
- [Leo installation](https://docs.aleo.org/build/leo/documentation/getting_started/installation)
- [Aleo Instructions overview](https://docs.aleo.org/build/aleo-instructions/overview)
- [Public & Private State](https://docs.aleo.org/learn/core-concepts/public-and-private-state)
- [Programs](https://docs.aleo.org/learn/core-concepts/programs)
- [Transactions](https://docs.aleo.org/learn/core-concepts/transactions)
- [Leo finalization model](https://docs.aleo.org/build/leo/documentation/guides/finalization)
- [Leo CLI overview](https://docs.aleo.org/build/leo/documentation/cli/cli_overview)
- [leo build](https://docs.aleo.org/build/leo/documentation/cli/cli_build)
- [leo execute](https://docs.aleo.org/build/leo/documentation/cli/cli_execute)
- [leo test](https://docs.aleo.org/build/leo/documentation/cli/cli_test)

## 本地冒烟测试

支持路径和拒绝路径通过以下门禁验证：

```bash
./scripts/aleo/counter-smoke.sh
./scripts/aleo/pure-math-smoke.sh
just aleo-leo-build-smoke
```

前置条件：

- `lean-toolchain` 指定的 Lean 工具链以及构建好的 `proof-forge` 二进制文件。
- 用于包/清单辅助脚本的 `python3`。
- 正例编译/测试需要 `PATH` 上的 `leo` CLI（已在 Leo 4.0.2 上测试）。

它证明了什么：

- 完整 Counter 在 sourcegen 前被拒绝，而不是产生 ABI 不兼容的 getter。
- PureMath 匹配 `Examples/Backend/Aleo/PureMath.golden.leo`，并通过
  `leo build` / `leo test`。
- write-only Counter、map、context、record、hash、mixed-return 和 crosscall
  等正例会经过真实 Leo 编译门禁。

它没有证明什么：

- 跨 `final` 的通用 state-derived 返回值。
- record spend、proof generation 或 private-state 等价性。
- 直接生成 Aleo Instructions。
- devnet 部署或 execute transactions。
- 与 EVM/Psy Counter 语义的跨目标等价性。
- 独立的 `.avm` 字节码文件；当前 `leo build` 将 VM 制品嵌入编译包，而非输出
  单独文件。

## 分类

Aleo 是 ZK-native smart-contract L1。它不是 Zcash、Psy/DPN 或 Starknet 那种
目标形态。

更合适的第一版分类是：

```text
Aleo ZK application sourcegen target
  with Leo as the first source-generation boundary
  with Aleo Instructions as the lower-level compiler target
  with Aleo VM bytecode, prover/verifier artifacts, ABI, and transaction proofs
```

Aleo 之所以是 “ZK”，是因为程序执行分成两层：

- proof context：私有、链下执行，可以 consume/create records，并生成 ZK
  proofs；
- finalization context：公开、链上执行，读写 mappings、storage variables 和
  storage vectors。

这意味着 Aleo 更接近 privacy-aware contract chain，而不是普通 ZK circuit
output target。ProofForge 应把 Aleo programs 建模为可部署 program packages，
而不是只建模为 circuits。

## 为什么它不同于现有 ZK 目标

现有 ProofForge ZK 相关说明覆盖的是不同形态：

- `psy-dpn`：target source 编译成 DPN circuit JSON artifacts。
- `zcash-shielded`：ZK 证明协议定义的 shielded payment statements。
- `kaspa-toccata`：L1 covenant 可以 inline verify proof 或结算 based-app
  state。
- `starknet-cairo`：Cairo contracts 编译到 Sierra/CASM；Starknet 不建模为
  generic circuit target。

Aleo 需要自己的家族，因为：

- Leo programs 是 smart contracts，有 program ids、imports、entry functions、
  records、mappings、finalization logic 和 deploy/execute transactions；
- private state 使用 records，records 是 encrypted 且 UTXO-like；
- public state 使用 mappings/storage，在 `final` logic 中由 validators 更新；
- execute transactions 包含 transitions 和 ZK proofs；
- build outputs 包含 `.aleo` instructions、ABI、prover/verifier files 和 Aleo
  VM bytecode；
- 本地验证可以使用 `leo build`、`leo test`、`leo execute` 和 devnet deployment
  flows。

## 目标家族决策

已注册的编译器家族是：

```text
zk-circuit-sourcegen
```

候选后端模式：

```text
ProofForge portable IR subset
  -> generated Leo package
  -> leo build
  -> Aleo Instructions (.aleo)
  -> Aleo VM bytecode + ABI + prover/verifier artifacts
  -> leo test / leo execute / leo devnet validation metadata
```

直接生成 Aleo Instructions 是后续路径。它对 compiler backend 很有吸引力，但
Leo 是更安全的第一制品，因为它是官方推荐的开发语言，并且更清晰地暴露 program
structure。

候选制品形态：

```text
aleo-leo-package
  - generated Leo source
  - program id and imports
  - record / mapping / storage schema
  - proof-context entry functions
  - finalization manifest
  - compiled Aleo Instructions
  - AVM bytecode
  - ABI JSON
  - prover and verifier artifacts
  - execute/deploy transaction metadata
  - test/devnet validation result
```

## 候选能力

这些是 research candidate，不是规范 capability id。

| 候选能力 | 含义 |
|---|---|
| `lang.leo` | target 发射 Leo source packages。 |
| `ir.aleo_instructions` | build 发射或消费 Aleo Instructions。 |
| `vm.aleo_avm` | target 运行在 Aleo VM 上，不是 Algorand AVM。 |
| `artifact.avm` | build 发射 Aleo VM bytecode。 |
| `artifact.aleo_abi` | build 发射 Aleo ABI metadata。 |
| `proof.prover_key` | build 或 execute flow 生成 prover artifacts。 |
| `proof.verifier_key` | build 或 deploy flow 记录 verifier artifacts。 |
| `execution.transition` | entry execution 生成 transition 和 proof。 |
| `execution.finalize` | program 有公开链上 finalization logic。 |
| `state.record` | private state 位于 encrypted records。 |
| `state.mapping` | public state 位于 mappings。 |
| `state.storage` | public state 可使用 storage variables 或 storage vectors。 |
| `input.private` | function input 是 private proof-context data。 |
| `input.public` | function input 是 public data。 |
| `output.private` | function output 默认 private。 |
| `output.public` | function output 是 public。 |
| `program.import` | program import 并调用另一个 Aleo program。 |
| `program.upgrade` | deployment 可支持显式 program upgrades。 |
| `transaction.execute` | validation 可生成 execute transaction。 |
| `transaction.deploy` | validation 可生成或检查 deploy transaction。 |
| `fee.credits` | fees 以 Aleo Credits 支付，可 public 或 private。 |
| `test.leo` | validation 使用 Leo tests。 |
| `test.aleo_devnet` | validation 使用 Leo devnet 或 devnode-backed flows。 |

仅有 `zk.circuit` 不足以描述 Aleo。它可以描述 proof 侧，但 Aleo 还需要
program、state、transaction 和 finalization 能力。

## 实现路径

### Road 1: Leo Sourcegen Package

优先走这条路径。

第一版 spike：

- 选择一个极小 Counter-like program；
- 生成包含一个 entry `fn` 和一个 `final { }` block 的 Leo source；
- 使用 public `mapping` 保存 counter；
- 运行 `leo build`，记录 `.aleo`、ABI、bytecode 和 toolchain metadata；
- 运行 `leo test`，并把 `--prove` 作为可选的更重门禁。

这能验证 compiler boundary，同时不让 ProofForge 过早承担 Aleo VM internals。

### Road 2: Private Record Flow

用这条路径验证 Aleo 的 ZK-specific value proposition。

第一版 spike：

- 定义一个简单 private record type；
- 在 proof-context entry function 中 consume 一个 record 并 create 一个 successor
  record；
- 保持 record contents private，只暴露必要的 public outputs 或 finalize effects；
- 运行 `leo execute --print` 或 SDK-backed execution，检查 transaction 和 proof
  metadata。

这条路径能证明 Aleo support 不只是 account-chain source generator。

### Road 3: Direct Aleo Instructions

只有在 Leo sourcegen 验证语义后，再走这条路径。

第一版 spike：

- 将一个极小 typed IR fixture 直接降级到 `.aleo` instructions；
- 保留 public/private input annotations；
- 通过官方工具链生成或验证 prover/verifier artifacts；
- 与相同行为的 Leo-generated Aleo Instructions 对比输出。

这条路径有利于 compiler precision，但语义面比 Leo sourcegen 更大。

## 第一阶段非目标

- 没有经过语义映射和 fail-closed 门禁审查，不扩宽已注册 capability profile。
- 不把 Aleo 仅归类为 generic ZK circuit target。
- 不混淆 Aleo VM 与 Algorand AVM。
- 不把 records 建模成 EVM storage 或 Zcash shielded notes。
- 不把 `final` blocks 建模为 private execution；finalization 是公开链上执行。
- 没有可重复本地 build/test 命令前，不声明 full Aleo support。
- 如果 Leo sourcegen 已足够验证第一版 spike，不从 direct Aleo Instructions 起步。

## Research 退出标准

Aleo 只有在满足以下条件后才能离开 Research：

- 经过审查的 target profile proposal；
- 针对 Leo、Aleo Instructions、Aleo VM bytecode、transitions、finalization、
  records、mappings、proofs、ABI、fees 和 devnet validation 的已提交 capability
  proposal；
- 针对 Leo source、compiled outputs、prover/verifier artifacts、ABI 和
  transaction/deploy metadata 的最小 artifact manifest schema；
- 基于 Leo CLI、SDK、devnet 或 devnode 的本地验证工具链决策；
- 一个可重复的本地命令或脚本，能验证极小 Leo program package，即使
  proving-heavy gates 在 CI 中保持可选。

**状态：** Road 1 profile、可重复 sourcegen 命令和基础 artifact schema 已实现；
devnet、proof generation、record spend 和完整 state-return 语义仍保持开放。

## Research 退出计划

详细的设计规格（Research 退出 + Road 1 spike）见
[docs/zh/superpowers/specs/2026-07-01-aleo-leo-design.zh.md](../superpowers/specs/2026-07-01-aleo-leo-design.zh.md)。

该规格确定了：

- 原设计术语：`zk-app-sourcegen`；当前 registry family id 为
  `zk-circuit-sourcegen`。
- 第一个 spike 的规范能力：
  `lang.leo`、`vm.aleo_avm`、`artifact.avm`、`artifact.aleo_abi`、
  `execution.finalize`、`state.mapping`、`input.public`、`output.public`、
  `test.leo`。
- 留给未来 spike 的研究候选能力：
  `ir.aleo_instructions`、`proof.prover_key`、`proof.verifier_key`、
  `execution.transition`、`state.record`、`state.storage`、`input.private`、
  `output.private`、`program.import`、`program.upgrade`、`transaction.execute`、
  `transaction.deploy`、`fee.credits`、`test.aleo_devnet`。
- `aleo-leo-package` 的制品清单 schema。
- 工具链决策：`leo build` + `leo test` 为主；prove/execute 可选。
- Spike 范围：Road 1 的受限 Leo sourcegen；完整 mapping Counter getter 是
  明确拒绝样本，PureMath 和 write-only Counter 是正例。

Road 1 profile 已实现。Aleo 原生 proof、transaction、fee 和 devnet capability
仍需等相应语义与验证路径落地后再加入。
