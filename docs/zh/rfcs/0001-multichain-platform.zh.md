# RFC 0001: Lean 优先的多链合约平台

状态：已接受

日期：2026-06-30

## 摘要

ProofForge 应该从一个 EVM 后端实验演进为一个 Lean 优先的多链合约平台。开发者在 Lean 中编写合约业务逻辑、状态机规则和证明。在构建时，他们选择一个目标链家族，ProofForge 会生成特定目标的制品、测试和部署包。

第一个架构决策是使用可移植核心加能力模型：

- 可移植核心：纯业务逻辑、算术、状态机转换、不变性以及应保持链无关的证明。
- 能力：显式的面向链的操作，例如存储、调用者身份、价值转移、事件、跨合约调用、账户访问、对象/资源访问以及链环境读取。
- 目标适配器：针对特定目标家族的 ABI、制品、测试运行器、部署和宿主运行时胶合代码。

该模型避免了假装 EVM、Solana、Wasm 链、Move 链、ZK/电路目标以及类比特币系统具有相同的语义。目标不是一种“最小公分母”语言。目标是一个经过验证的业务核心，具有清晰、可审计的目标边界。

## 当前基线

仓库目前有一个 EVM 基线：

```text
Lean contract
  -> Lean frontend / LCNF
  -> EmitYul
  -> Yul
  -> solc --strict-assembly
  -> EVM runtime bytecode
  -> Foundry smoke tests
```

今日已实现：

- `ProofForge.Evm`：EVM SDK 原语和类型化辅助程序。
- `ProofForge.Compiler.LCNF.EmitYul`：LCNF 到 Yul 的降级。
- `proof-forge --evm-bytecode`：EVM 字节码 CLI 模式。
- `.evm-methods`：用于 ABI 选择器的方法分派元数据。
- 使用生成的运行时字节码的 Foundry 冒烟测试。

今日未实现：

- 一个目标无关的合约 IR。
- Solana/sBPF、Wasm 家族、Move 家族或 ZK/电路后端。
- 云端构建、部署、制品注册表或托管测试网流程。

## 外部格局

多链合约领域已有相关项目，但尚无主导性的 Lean 优先的经过验证的多链部署平台。

| 领域 | 参考 | 相关性 |
|---|---|---|
| 多链语言 | Reach, https://www.reach.sh/ | 编写一次应用程序并部署到多个链的最接近的高层先例。 |
| Solidity 多目标编译器 | Solang, https://solang.readthedocs.io/ | 表明一种源语言可以降级到非 EVM 区块链目标，但它是从 Solidity 而非 Lean/证明开始的。 |
| EVM | Foundry 和 solc 工具链 | 成熟的本地测试和字节码流水线；当前的 ProofForge 基准。 |
| Solana | Programs docs, https://solana.com/docs/core/programs | 高价值目标，其账户/指令模型与 EVM 截然不同。 |
| Wasm 链 | NEAR, https://docs.near.org/smart-contracts/what-is | 具有特定链宿主 ABI 和账户模型的 Wasm 合约模型。 |
| Wasm 链 | CosmWasm, https://cosmwasm.cosmos.network/ | 跨 Cosmos 链的 Wasm 合约，具有独特的消息/存储模型。 |
| Wasm 链 | ink!, https://use.ink/docs/v5/why-webassembly-for-smart-contracts/ | 通过 Wasm 实现的 Polkadot/Substrate 智能合约。 |
| Move 链 | Sui Move, https://docs.sui.io/concepts/sui-move-concepts | 对象/资源语义、强类型约束以及 Move VM 目标家族。 |
| Move 链 | Aptos 智能合约, https://aptos.dev/en/build/smart-contracts | 具有独立账户和部署模型的 Move 模块/资源模型。 |
| ZK/电路目标 | Psy 编译器, https://github.com/PsyProtocol/psy-compiler | 面向 ZK 的合约编译器，发射 DPN 电路函数定义而非 EVM 风格的字节码。 |
| 比特币生态系统 | Stacks Clarity, https://docs.stacks.co/learn/clarity | 具有可判定性目标的比特币邻近智能合约语言。 |
| 比特币生态系统 | BitVM, https://bitvm.org/ | 比特币计算验证的 Research 方向，不是直接的首选后端目标。 |

## 目标架构

```text
                 +---------------------------+
                 | Lean contract + proofs    |
                 +-------------+-------------+
                               |
                               v
                 +---------------------------+
                 | Lean frontend / LCNF      |
                 +-------------+-------------+
                               |
                               v
                 +---------------------------+
                 | Portable Contract IR      |
              +------+------+------+------+------+
                     |      |      |      |      |
                     v      v      v      v      v
                  +-----+ +-------------+ +-------------+ +-------------+ +--------+
                  | EVM | | Solana/sBPF | | Wasm family | | Move family | | ZK/DPN |
                  +-----+ +-------------+ +-------------+ +-------------+ +--------+
                     |          |              |               |             |
                     v          v              v               v             v
                 Yul/solc  Solana program  NEAR/CosmWasm  Sui/Aptos     Psy/DPN
                                           Polkadot/ink!
```

可移植 IR 必须位于目标 ABI 细节之上，Lean 源代码语法之下。
它应该表示：

- 导出的合约入口和方法元数据。
- 可移植的值、结构体、枚举、数组、映射和错误。
- 状态转换函数和声明的不变量。
- 作为类型化效应（typed effects）而非原始目标操作码的能力调用。
- 在后端降级之前可以检查的携带证明的事实。

目标后端将此 IR 降级到每个链家族：

- EVM 后端：Yul 对象、ABI 选择器分发、`solc` 字节码、Foundry 测试。
- Solana 后端：sBPF 包、指令分发、账户元数据、PDA 辅助函数、CPI 边界、Solana 本地验证器测试。
- Wasm 后端家族：共享的 Wasm 降级以及针对 NEAR、CosmWasm 和 Polkadot/ink 风格合约的特定链宿主 ABI 适配器。
- Move 后端家族：针对 Sui 和 Aptos 的 Move 模块/包适配器，包含一个针对直接 Move 字节码或生成的 Move 源代码的 Research 阶段。
- ZK 电路后端家族：目标源代码生成以及目标原生电路制品生成，从 Psy/DPN 开始。

## 能力模型

可移植代码不得直接调用原始 EVM、Solana、Wasm、Move 或 ZK VM 宿主 API。它调用 ProofForge 能力。每个目标声明其支持哪些能力以及如何降级它们。

初始能力组：

| 能力 | 可移植含义 | 目标说明 |
|---|---|---|
| 存储 | 读/写合约状态 | EVM 插槽、Solana 账户、Wasm 存储、Move 资源/对象差异显著。 |
| 调用者 | 识别交易签名者/调用者 | EVM `caller`、Solana 签名者账户、Wasm 发送者、Move 交易发送者。 |
| 数值 | 原生代币转移或接收的数值 | 并非所有链都暴露 EVM 风格的 `msg.value`；适配器必须明确这一点。 |
| 事件 | 发射索引化或结构化的输出 | EVM 日志、Solana 日志/事件、Wasm 事件、Move 事件。 |
| 跨合约调用 | 调用另一个合约/程序/模块 | EVM 调用、Solana CPI、Wasm 消息/promise、Move 模块调用。 |
| 时间/环境 | 区块高度、时间戳、链 id | 可用性和最终性语义因目标而异。 |
| 密码学 | 哈希、签名恢复、预编译 | 一些目标暴露宿主函数，其他目标需要库降级。 |
| 账户/对象/资源 | 链原生状态容器 | 对 Solana 账户和 Move 对象/资源尤为重要。 |
| ZK/电路 | 电路制品生成和证明流 | 对 Psy/DPN 和未来的 ZK VM 目标尤为重要。 |

当合约使用不支持的能力时，编译器应拒绝目标构建。拒绝优于默默地改变语义。

## CLI 与产品界面

未来的本地 CLI 应将目标选择作为稳定的公共接口：

```sh
proof-forge build --target evm --out build/evm
proof-forge build --target solana-sbpf-asm --out build/solana
proof-forge build --target wasm-near --out build/near
proof-forge build --target wasm-cosmwasm --out build/cosmwasm
proof-forge build --target move-sui --out build/sui
proof-forge build --target move-aptos --out build/aptos
proof-forge build --target psy-dpn --out build/psy-dpn
```

Polkadot/ink 风格的合约 (`wasm-polkadot`) 在目标 profile 和 spike 计划确定前仍仅限 Research 阶段。参见 [decisions.md](../decisions.zh.md)。
Psy/DPN (`psy-dpn`) 现在针对受限的可移植 IR 子集处于 Experimental 阶段；集成路径仍然是生成 `.psy` 源代码加 Dargo，而不是公开的类 Yul IR。

当前的 `proof-forge --evm-bytecode` 模式在面向目标的 `build` 命令存在之前，仍将作为 EVM 基准。

未来的云平台界面：

- 从 GitHub 导入。
- 选择目标矩阵。
- 在隔离的 worker 中运行确定性构建。
- 运行目标原生的本地/测试网冒烟测试。
- 存储制品、ABI、证明、部署元数据和验证报告。
- 在显式签名或钱包批准后部署到配置的测试网/主网。
- 显示类似 Vercel/Cloudflare 的项目仪表板，包含构建、环境、部署、日志和特定链的健康检查。

## 路线图

### 阶段 0：EVM 基准

状态：已在此仓库中实现。

- 保持 EVM 示例通过 `proof-forge --evm-bytecode` 编译。
- 保持 Foundry 冒烟测试作为成熟的 EVM 测试框架。
- 将当前的 EVM SDK 原语视为第一个具体的能力来源。

### 阶段 1：目标模型和可移植 IR

- 引入目标注册表和目标标识符。
- 将特定于 EVM 的 SDK 调用与可移植合约能力分离。
- 定义可移植合约 IR ([spec](../portable-ir.zh.md))和制品元数据。
- 为不支持的目标能力添加编译时错误 ([注册表](../capability-registry.zh.md))。
- 定义 Counter [共享场景](../shared-scenario.zh.md)。

### 阶段 2：并行目标 spike (CosmWasm + Solana)

需要阶段 1 完成。CosmWasm 和 Solana spike 可以并行进行。

**CosmWasm (`wasm-cosmwasm`)：**

- 带有 region ABI 和 JSON 消息的 Wasm 宿主适配器。
- 通过 `cosmwasm-check` 进行 Counter 冒烟测试。

**Solana (`solana-sbpf-linker`)：**

- 将可移植入口映射到带有显式账户的指令调度。
- 通过原版 Zig + `sbpf-linker` 生成最小的 sBPF 制品。
- 在 Mollusk 或 Solana 本地验证节点下运行。

两个 spike 都使用相同的可移植 IR Counter 模块。参见 [decisions.md](../decisions.zh.md)。

### 阶段 3：Move 家族

- 从受限的可移植 IR 生成 Move 源代码（先是 Aptos POC，然后是 Sui）。
- 将 Sui 对象和 Aptos 资源建模为目标能力。
- 在 EVM 和 Aptos 上验证 Counter（或后续场景）。

### 阶段 3.5：ZK 电路目标研究

- 从受限的可移植 IR 生成 Psy 兼容的 `.psy` 源代码。
- 通过 Dargo 编译为 DPN 电路 JSON。
- 在本地节点/证明器部署冒烟测试之前，决定内存中的 Psy 执行是否足够。

### 阶段 4：跨目标场景加固

- 跨 EVM 和至少两个非 EVM 目标的共享场景测试。
- 黄金 IR 和制品快照。
- Counter v1 的能力矩阵覆盖（事件、访问控制可选）。

### 阶段 5：云平台

- 添加托管的目标矩阵构建。
- 添加制品注册表和部署历史。
- 添加测试网部署流程。
- 添加验证报告，显示证明状态、使用的目标能力以及特定于链的警告。

## 非目标

- 不要承诺每个合约都能编译到每个链。
- 不要隐藏链经济模型、最终性、账户模型或资源模型。
- 不要将任意 EVM 字节码翻译到每个目标。
- 不要将 Bitcoin L1 执行作为早期后端目标。
- 不要取代成熟的目标原生工具，如 Foundry、Solana 本地验证节点工具、NEAR 工具、CosmWasm 工具或 Move CLI。应先与它们集成。

## 测试策略

每个目标家族应有四个测试层级：- Lean 检查：证明、纯逻辑和状态机不变性。
- 黄金制品：针对小型示例的稳定 IR 和后端输出快照。
- 目标原生冒烟测试：针对 EVM 的 Foundry，针对 sBPF 的 Solana 本地验证器，特定链的 Wasm 运行器，Move 本地/测试网工具，以及针对 `psy-dpn` 的 Dargo/Psy 工具。
- 跨目标场景测试：相同的可移植合约场景应在支持的目标上产生等效的高层结果。

CI 应从仅支持 EVM 开始，然后随着新后端的落地扩展到目标矩阵。在拥有至少一个本地冒烟测试和一个共享的可移植场景测试之前，目标不被视为已支持。

## 开放性问题

- 在可移植合约 IR 中应保留多少 Lean 的 LCNF？
- 目标适配器是否应仅用 Lean 编写，或者当链工具使其更可靠时，某些适配器是否可以使用 Zig/Rust/Go？
- 对于 Move，生成的 Move 源代码对于第一个后端是否可以接受，还是为了平台叙事需要直接的 Move 字节码？
- 对于 Wasm，编译器应该发射一个通用的 Wasm 核心加适配器，还是从一开始就为每个链发射独立的 Wasm？
- 云部署应如何处理私钥、多签工作流和用户控制的签名？
