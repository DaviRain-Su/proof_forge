# Aleo Leo 目标

状态：**Spike（本地冒烟已存在 — `scripts/aleo/counter-smoke.sh`）**

候选目标 id：**`aleo-leo`**

本文记录 ProofForge 对 Aleo 的第一版分类以及已实现的 Road 1 spike。它不会立刻
添加 Lean target profile；spike 先验证 Leo 源码生成边界，再决定是否修改代码注册表。

主要交付物：

- `ProofForge.Backend.Aleo.IR` 将 portable IR `Counter` fixture 降级为 Leo。
- `proof-forge emit --target aleo-leo --fixture counter --format leo` 输出
  `Counter.leo`。
- `Examples/Backend/Aleo/Counter.golden.leo` 是已跟踪的 golden fixture。
- `scripts/aleo/counter-smoke.sh` 生成 Leo 包、运行 `leo build` 和 `leo test`、
  写入 `proof-forge-artifact.json` 并校验 metadata。
- `ProofForge.Compiler.Leo.Emit` 额外支持带参数/返回值的纯函数入口，以及控制流语句
  （`assert`、`if/else`、`boundedFor`、`assign`、`assignOp`）。
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

Road 1 spike 通过以下脚本进行端到端验证：

```bash
./scripts/aleo/counter-smoke.sh
```

前置条件：

- `lean-toolchain` 指定的 Lean 工具链以及构建好的 `proof-forge` 二进制文件。
- 用于包/清单辅助脚本的 `python3`。
- `PATH` 上的 `leo` CLI（已在 Leo 4.0.2 上测试）；如果未安装 `leo`，脚本会
  输出生成的 `Counter.leo` 并以退出码 `127` 退出。

它证明了什么：

- Portable IR `ProofForge.IR.Examples.Counter` 可降级为 Leo 4.0 程序，包含
  公开 `mapping`、`@noupgrade constructor` 以及通过 `fn ... -> Final` 暴露、
  在 `final` 块中读写 mapping 的 entry point。
- 生成的 Leo source 与已跟踪的 golden fixture
  `Examples/Backend/Aleo/Counter.golden.leo` 一致。
- `leo build` 能生成 Aleo Instructions（`build/main.aleo`）和 ABI JSON
  （`build/abi.json`）。
- `leo test` 通过。
- `proof-forge-artifact.json` 被生成并通过了 schema 校验。

它没有证明什么：

- private records、transitions 或 proof generation。
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

## 候选目标家族

在目标模型能表达 Aleo 的 proof/finalization split 和 record/mapping state split
之前，不要把它加入 `ProofForge.Target.Registry`。

候选家族：

```text
zk-app-sourcegen
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

- 在候选能力完成审查前，不要把 `aleo-leo` 加入代码 registry。
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

**状态：** Road 1 spike 已满足“可重复本地命令”和“artifact manifest schema”
标准。其余标准（target profile、完整 capability proposal、devnet validation）
在 private records 和 transitions 审查完成前保持开放。

## Research 退出计划

详细的设计规格（Research 退出 + Road 1 spike）见
[docs/zh/superpowers/specs/2026-07-01-aleo-leo-design.zh.md](../superpowers/specs/2026-07-01-aleo-leo-design.zh.md)。

该规格确定了：

- 目标家族：`zk-app-sourcegen`。
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
- Spike 范围：仅 Road 1，公开 mapping Counter，输入为
  `ProofForge.IR.Examples.Counter`。

Road 1 spike 已实现；代码注册表修改
（`ProofForge.Target.Capability` / `ProofForge.Target.Registry`）仍推迟到
proof/finalization split 与 private-record 路线图审查之后。
