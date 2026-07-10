# RFC 0002: 目标实现设计

状态：已接受

日期：2026-06-30

## 摘要

RFC 0001 定义了产品方向。本 RFC 定义了实现该方向的初步工程形态。

ProofForge 不应为每个链使用单一的后端策略。它应该将目标划分为不同的实现家族：

- 直接编译器目标：ProofForge 拥有大部分降级逻辑，如当前的 EVM/Yul 后端。
- Wasm 宿主目标：ProofForge 发射 Wasm 模块以及特定于链的宿主 ABI 适配器，如 NEAR 和 CosmWasm。
- 二进制工具链目标：ProofForge 发射中间对象/位码并调用特定于链的打包器/链接器，如 Solana sBPF。
- 源代码生成目标：ProofForge 发射目标源代码包，如 Sui Move 和 Aptos Move。
- ZK 电路源代码生成目标：ProofForge 发射目标源代码包，并将电路制品生成委托给目标原生工具，如 Psy/DPN。

这在保持可移植合约模型稳定的同时，允许每个链家族保留其原生的 ABI、存储模型、工具和测试。

## 设计目标

- 保持 Lean 作为面向用户的业务逻辑、类型和证明语言。
- 通过能力和目标清单使目标差异保持显式。
- 在替换成熟的目标原生工具之前，先与其集成。
- 使每次构建都生成机器可读的制品元数据。
- 使每个受支持的目标通过至少一个本地冒烟测试和一个能力矩阵条目来获得支持。

非目标：不应期望任意 Lean 代码都能编译到每个目标。受支持的子集将由可移植合约 IR 和所选目标的能力 profile 决定。

## 建议的仓库形态

当前仓库可以向此布局演进（标记为 *planned* 的路径尚未在仓库中）：

```text
ProofForge/
  Target.lean                    # planned
  Target/
    Capability.lean              # planned
    Artifact.lean                # planned
    Registry.lean                # planned
  IR/
    Contract.lean                # planned — see docs/portable-ir.md
    Type.lean                    # planned
    Effect.lean                  # planned
    Manifest.lean                # planned
  Backend/
    Evm.lean
    Wasm/
      Near.lean                  # planned
      CosmWasm.lean              # planned
    Solana/
      SbfLinker.lean             # planned
      SolanaZig.lean             # planned
    Move/
      Sui.lean                   # planned
      Aptos.lean                 # planned
    Zk/
      PsyDpn.lean                # planned
runtime/
  zig/
    lean_rt/                     # planned
    host/
      near/                      # planned
      cosmwasm/                  # planned
      solana/                    # planned
tools/
  zigc-near                      # planned
  zigc-cosmwasm                  # planned
  zigc-solana-sbpf               # planned
scripts/
  evm/
  near/                          # planned
  cosmwasm/                      # planned
  solana/                        # planned
  move/                          # planned
  psy/                           # planned
Examples/
  Evm/
  Near/                          # planned
  CosmWasm/                      # planned
  Solana/                        # planned
  Move/                          # planned
  Psy/                           # planned
```

这不是一个必须的一次性重构。它是阶段性工作的方向。
现有的 EVM 实现可以保留在原处，直到 `Target` 和 `IR` 模块存在。

## 目标 profile

每个目标都应该由一个 `TargetProfile` 来描述。

从概念上讲：

```lean
inductive TargetFamily where
  | evm
  | wasm
  | solana
  | move
  | zkCircuit

inductive ArtifactKind where
  | evmBytecode
  | wasm
  | solanaElf
  | movePackage
  | psyCircuitJson

structure TargetProfile where
  id : String
  family : TargetFamily
  artifactKind : ArtifactKind
  capabilities : CapabilitySet
  buildSteps : Array BuildStep
  smokeTests : Array SmokeTest
```

初始 target id（历史快照；当前阶段见 [Backend Status](../README-root.zh.md)
和 [doc-code-sync-audit-2026-07.md](../../doc-code-sync-audit-2026-07.md)）：

| Target id | 家族 | 制品 | 状态（2026-07 `main`） |
|---|---|---|---|
| `evm` | EVM | Runtime bytecode | Experimental — 范围化 P0 制品/运行时门禁已完成 |
| `wasm-near` | Wasm 宿主 | NEAR 兼容 Wasm | Experimental — `main` 上的 EmitWat（Gate P0） |
| `wasm-cosmwasm` | Wasm 宿主 | CosmWasm Wasm | Spike — Counter golden WAT + optional CI |
| `solana-sbpf-linker` | Solana | Solana sBPF ELF `.so` | **Deprecated**（D-026；使用 `solana-sbpf-asm`） |
| `solana-zig-fork` | Solana | Solana sBPF ELF `.so` | **Deprecated**（D-005/D-026） |
| `solana-sbpf-asm` | Solana | sBPF ELF | Experimental — 规范路线（Gate P0） |
| `move-sui` | Move | Sui Move 包 | Counter MVP — 本地 `just sui-*` gates |
| `move-aptos` | Move | Aptos Move 包 | Spike — Counter golden Move |
| `psy-dpn` | ZK 电路源代码生成 | DPN circuit JSON + ABI | Experimental subset |
| `wasm-cloudflare-workers` | Wasm 宿主（off-chain） | TypeScript Worker | Research spike — TS emit |
| `aleo-leo` | ZK / Leo | Leo package | Research spike — 仅 CLI（D-025） |

未来 Research（在排期前不在注册表中）：`wasm-polkadot` (ink!)。
参见 [decisions.md](../decisions.zh.md)。

## 能力矩阵

编译器在降级前应使用目标能力矩阵。如果合约使用了目标无法表示的能力，构建应失败并提供精确的诊断信息。

| 能力 | EVM | NEAR | CosmWasm | Solana | Sui | Aptos | Psy DPN |
|---|---|---|---|---|---|---|---|
| 持久化标量状态 | 插槽存储 | 宿主 KV | 宿主 KV | 账户数据 | 对象字段 | 账户资源 | Psy 存储/状态 |
| 调用者/发送者 | `msg.sender` | predecessor/signer | `MessageInfo.sender` | 签名者账户 | `TxContext.sender` | `signer` | Psy 用户/上下文 |
| 接收到的原生价值 | `msg.value` | 附加存款 | 消息信息中的资金 | lamport 账户 | coin 对象 | coin 资源 | Psy 特有的资产流 |
| 事件/日志 | EVM 日志 | 日志/事件 | 事件/属性 | 日志/事件 | 事件 | 事件 | Research |
| 跨合约调用 | call/staticcall | promises | 子消息 | CPI | 模块调用/交易 | 模块调用 | `invoke_sync` / `invoke_deferred` |
| 状态账户/对象选择 | 隐式合约 | 隐式合约 | 隐式合约 | 显式账户 | 显式对象 | 账户资源 | Psy 合约/用户状态 |
| 动态映射存储 | mapping/keccak 插槽 | KV 前缀 | KV 前缀 | 账户拥有的数据或 PDA | 动态字段/表 | 表资源 | 固定容量 Psy 存储 |
| 合约部署包 | 字节码 | Wasm | Wasm | ELF `.so` | Move 包 | Move 包 | DPN 电路 JSON + 部署 JSON |

能力 id 在 [capability-registry.md](../capability-registry.zh.md) 中是规范的。
下方的语义矩阵将可移植含义映射到目标机制。

## 制品元数据

每次构建都应在目标输出旁发射 `proof-forge-artifact.json`。

初始 schema：

```json
{
  "schemaVersion": 1,
  "package": "counter",
  "target": "wasm-cosmwasm",
  "source": {
    "entryFile": "Examples/Backend/CosmWasm/Counter.lean",
    "module": "Counter"
  },
  "proofs": {
    "checked": true,
    "warnings": []
  },
  "capabilities": [
    "storage.scalar",
    "caller.sender",
    "events.emit"
  ],
  "artifacts": [
    {
      "kind": "wasm",
      "path": "build/cosmwasm/counter.wasm",
      "sha256": "..."
    }
  ],
  "toolchain": {
    "proofForge": "0.1.0",
    "lean": "4.31.0",
    "zig": "0.15.x",
    "external": {
      "cosmwasm-check": "..."
    }
  },
  "targetMetadata": {}
}
```

云平台随后可以存储正是这些元数据，以及部署地址、交易哈希和测试报告。

## CLI 形态

当前 CLI 直接支持 EVM 字节码：

```sh
lake env proof-forge --evm-bytecode -o build/evm/Counter.bin \
  Examples/Backend/Evm/Contracts/Counter.lean
```

面向目标的 CLI 最终应暴露：

```sh
proof-forge build --target evm --out build/evm Examples/Backend/Evm/Contracts/Counter.lean
proof-forge build --target wasm-near --out build/near Examples/Near/Counter.lean          # planned
proof-forge build --target wasm-cosmwasm --out build/cosmwasm Examples/Backend/CosmWasm/Counter.lean  # planned
proof-forge build --target solana-sbpf-asm --out build/solana Examples/Backend/Solana/Counter.lean  # planned
proof-forge build --target move-aptos --out build/aptos Examples/Move/Aptos/Counter/       # planned
proof-forge test --target evm
proof-forge test --target solana-sbpf-asm
```

近期实现可以在 CLI 泛化期间将目标脚本保留在 `scripts/<target>/` 下。

## EVM 目标

当前流水线：

```text
Lean contract
  -> Lean frontend / LCNF
  -> EmitYul
  -> Yul
  -> solc --strict-assembly
  -> runtime bytecode
  -> Foundry smoke
```

实现说明：

- 保留 `ProofForge.Evm` 作为第一个具体的 target adapter / extension SDK。
- 在统一清单存在之前，保留 `.evm-methods` 作为目标元数据。
- 在现有字节码路径周围添加制品元数据。
- 在重大 IR 重构之前，为简单示例添加黄金 Yul 快照。

## NEAR 目标

Lean 分叉已经展示了所需的 Wasm-host 模式：

```text
Lean contract
  -> EmitZig
  -> generated Zig contract module
  -> NEAR Zig runtime + host bridge
  -> wasm32-wasi or wasm32-freestanding Wasm
  -> strip/stub incompatible WASI imports if needed
  -> NEAR-compatible Wasm
```

在 fork 中观察到的关键部分：

- `Lean.Near`：带有 `@[extern "lean_near_*"]` 函数的 Lean SDK。
- `host/near/lean_near.zig`：从 Lean 对象到 NEAR 宿主导入的桥接。
- `tools/zigc-near`：生成方法导出并链接运行时的包装器。
- `near-strip-wasi-imports.cjs`：移除 WASI 导入并检查 MVP Wasm 兼容性。

ProofForge 需要的实现改进：

- 将 `lean_near_*` extern 声明移出核心 EmitZig 运行时 extern。
- 使宿主桥接选择由目标驱动，而不是“所有 Wasm 都意味着 NEAR”。
- 将方法导出元数据移入通用的目标清单。
- 保留 NEAR 作为 Wasm-host 运行时形态的首个参考。

## CosmWasm 目标

CosmWasm 应与 NEAR 共享 Wasm-host 目标家族，但它需要一个单独的目标适配器。Wasm 是制品格式；合约 ABI 则不同。

预期流水线：

```text
Lean contract
  -> EmitZig
  -> generated Zig contract module
  -> CosmWasm Zig runtime + host bridge
  -> wasm32-freestanding or wasm32-unknown-style Wasm
  -> cosmwasm-check
  -> cw-multi-test or wasmd smoke
```

所需导出：

- `interface_version_8`
- `allocate`
- `deallocate`
- `instantiate`
- `execute`
- `query`
- 稍后可选：`migrate`, `reply`, `sudo`, `ibc_*`

入口适配器应使用 CosmWasm region-pointer ABI。第一个实现应保持消息以 JSON 为后端，以避免在后端存在之前添加完整的 schema 编译器。

**权威 SDK 与 spike 草案：** [targets/wasm-family.md](../targets/wasm-family.zh.md)
（Counter spike 章节）。请勿在此重复 SDK 定义。

Zig 桥接草案：

```zig
export fn instantiate(env: u32, info: u32, msg: u32) callconv(.c) u32 {
    return runLeanEntrypoint(.instantiate, env, info, msg);
}

export fn execute(env: u32, info: u32, msg: u32) callconv(.c) u32 {
    return runLeanEntrypoint(.execute, env, info, msg);
}

export fn query(env: u32, msg: u32) callconv(.c) u32 {
    return runLeanQuery(env, msg);
}
```

首次冒烟测试：

- 带有 `instantiate`、`execute({"increment":{}})` 和 `query({"get_count":{}})` 的 Counter 合约。
- 构建 Wasm。
- 运行 `cosmwasm-check`。
- 运行一个调用 instantiate/execute/query 的本地 Rust 或基于 CLI 的冒烟测试。

## Solana 目标

Solana 应该有两个实现 profile。

### 首选路径：`solana-sbpf-linker`

`zignocchio` 项目展示了一个有用的无分叉流程：

```text
Zig source
  -> zig build-lib -target bpfel-freestanding -femit-llvm-bc=entrypoint.bc
  -> sbpf-linker --cpu v2 --export entrypoint -o program.so entrypoint.bc
  -> solana-test-validator or Mollusk smoke
```

这符合 EVM/Solang 风格流程所使用的“中间制品加目标打包器”模式。

ProofForge 流水线：

```text
Lean contract
  -> EmitZig
  -> generated Zig contract module
  -> generated solana_contract_root.zig
  -> zig build-lib -target bpfel-freestanding -femit-llvm-bc
  -> sbpf-linker
  -> Solana ELF `.so`
  -> smoke test
```

所需的 Solana 目标适配器组件：

- `Lean.Solana`：account、instruction data、signer、PDA、CPI、log、return data。
- Zig 中的 `lean_solana_*` 桥接函数。
- `solana_contract_root.zig`：导出单个 `entrypoint(input) -> u64`。
- 指令分发元数据，取代 NEAR 风格的方法导出。
- 每个入口的显式 account schema。

Solana 方法清单草案（格式：TOML v0，可能会有变动 —— 包含 account `index` 字段的完整示例见 [targets/solana-sbf.md](../targets/solana-sbf.zh.md)）：

```toml
[[instruction]]
name = "increment"
tag = 1
handler = "l_Counter_increment"
accounts = [
  { name = "payer", index = 0, signer = true, writable = true },
  { name = "counter", index = 1, signer = false, writable = true, owner = "program" }
]
```

根适配器草图：

```zig
export fn entrypoint(input: [*]u8) callconv(.c) u64 {
    var ctx = solana.deserialize(input);
    lean_rt.lean_initialize_runtime_module();
    return dispatchLeanInstruction(&ctx);
}
```

测试策略：

- 快速确定性程序测试：尽可能使用 Mollusk。
- 部署式冒烟测试：`solana-test-validator --bpf-program`。
- 第一个合约：无 CPI，一个 PDA/账户状态。
- 第二个合约：对 System Program 的 CPI。
- 第三个合约：SPL Token CPI。

### 回退/参考轨道：`solana-zig-fork`

`solana-sdk-mono` 项目展示了另一条路线：

```text
Zig source
  -> solana-zig target .sbf/.solana
  -> dynamic library `.so`
  -> Mollusk tests
```

这条路径很有用，因为 SDK 已经以成熟的方式对账户、CPI、类型化账户、事件和程序测试进行了建模。即使 ProofForge 首先选择 `sbpf-linker`，它也应该作为一个参考。

## Move 目标

Move 目标不应尝试编译完整的 Lean 运行时。第一个实现应该从受限的可移植 IR 生成 Move 源代码包。

共享的 Move 限制：

- 仅限一阶函数。
- 无闭包或高阶运行时值。
- 运行时无任意 Lean 堆对象。
- 数据类型必须映射到 Move 结构体/枚举或生成的变体。
- 副作用必须是目标能力，而不是任意 IO。
- 证明保留在 Lean 中，并在 Move 源代码生成之前进行检查。

### Sui

Sui 使用以对象为中心的 Move 模型。持久化状态应映射到带有 `UID` 的对象。

流水线：

```text
Lean portable contract
  -> Portable IR
  -> Sui Move package
  -> sui move build
  -> sui move test
  -> optional localnet/testnet publish
```

Sui 映射：

| 可移植概念 | Sui 映射 |
|---|---|
| 合约状态 | 带有 `UID` 的对象结构体 |
| 调用者 | `tx_context::sender` |
| 入口方法 | `entry fun` |
| 原生价值 | `sui::coin::Coin` 对象 |
| 事件 | `sui::event::emit` |
| 动态映射 | `sui::table`、动态字段或显式子对象 |

第一个 Sui POC：

- 带有 `UID`、`key`、`store` 的 Counter 对象。
- 生成 `entry fun` 和 `public fun`。
- 添加 Move 单元测试。

### Aptos

Aptos 使用更接近账户作用域存储的模块/资源模型。

流水线：

```text
Lean portable contract
  -> Portable IR
  -> Aptos Move package
  -> aptos move compile
  -> aptos move test
  -> optional localnet/testnet publish
```

Aptos 映射：

| 可移植概念 | Aptos 映射 |
|---|---|
| 合约状态 | 账户下的 `struct State has key` |
| 调用者 | `&signer` |
| 入口方法 | `public entry fun` |
| 原生价值 | `aptos_coin` / 同质化资产 API |
| 事件 | event 模块 API |
| 动态映射 | table 资源 |

首个 Aptos POC：

- 账户拥有的 counter 资源。
- `initialize(account: &signer)`
- `increment(account: &signer)`
- `get(addr: address): u64`

Sui object POC 将在 Aptos 之后的独立切片中进行（参见 [decisions.md](../decisions.zh.md)）。

## 实现阶段

与 [RFC 0001](0001-multichain-platform.zh.md) 和 [decisions.md](../decisions.zh.md) 保持一致：

### 阶段 1：目标注册表、可移植 IR、元数据

- 添加目标 id 和能力集（[capability-registry.md](../capability-registry.zh.md)）。
- 按照 [portable-ir.md](../portable-ir.zh.md) 实现可移植 IR。
- 定义 Counter [共享场景](../shared-scenario.zh.md)。
- 添加制品元数据 schema。
- 保持当前 EVM 命令正常工作。

### 阶段 2：并行 spike（CosmWasm + Solana）

- Wasm-host 提取和 `wasm-cosmwasm` Counter spike。
- 带有指令清单的 `solana-sbpf-linker` Counter spike。
- 两者都依赖于阶段 1 的完成；可以并行运行。

### 阶段 3：EVM 强化（进行中）

- 为 EVM 构建发射 `proof-forge-artifact.json`。
- 核心 EVM 示例的黄金输出测试。

### 阶段 4：Move 源代码生成（Aptos 优先）

- 受限的 Move 兼容 IR 子集。
- Aptos counter 包；Sui object POC 作为后续。

### 阶段 5：跨目标场景强化和云准备

- 跨多个目标的共享场景测试。
- 在两个以上 Experimental 目标之后的云平台设计。

## 开放工程风险

- sBPF 上的 Lean 运行时可能太大或使用了不支持的 section。
- 完整的 Lean 堆/对象模型对于 Solana 的计算预算来说可能过于昂贵。
- CosmWasm 可能需要比 NEAR 的第一条路径更紧凑的 no-WASI 运行时。
- Move 代码生成需要真实的权属/资源模型，而不是字符串模板。
- 过于接近 EVM 的可移植 IR 将在 Solana 和 Move 上失败。
- 过于通用的可移植 IR 将变得无法用于实际合约。

## 已定决策

决策日志请参见 [decisions.md](../decisions.zh.md)。关键项：

- 在非 EVM spike 之前完成阶段 1。
- 阶段 1 之后并行进行 CosmWasm 和 Solana spike。
- `solana-sbpf-linker` 作为主要 Solana 路径；`solana-zig-fork` 作为备选。
- Aptos 优先的 Move POC；Sui 紧随其后。

## Research 参考

- 本仓库中的 EVM 基线：`ProofForge.Compiler.LCNF.EmitYul`，`ProofForge.Evm`，`scripts/evm/foundry-smoke.sh`。
- 本地 Lean fork (lean4-zig-compiler) 中的 NEAR 参考：`Lean.Near.lean`，`tools/zigc-near`，`src/runtime/zig/host/near`。
- Solana fork-target 参考：`https://github.com/DaviRain-Su/solana-sdk-mono.git`。
- Solana stock-Zig 参考：`https://github.com/vitorpy/zignocchio`。
- sbpf-linker：`https://github.com/blueshift-gg/sbpf-linker`。
- CosmWasm 文档：`https://cosmwasm.cosmos.network/`。
- Sui Move 文档：`https://docs.sui.io/concepts/sui-move-concepts`。
- Aptos Move 文档：`https://aptos.dev/network/blockchain/move`。
