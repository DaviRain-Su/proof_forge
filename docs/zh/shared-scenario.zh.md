# 共享合约场景：Counter 和 ValueVault

状态：**草案规范 (Phase 1–2)**

Counter 场景是第一个跨目标验收标准测试。它在 Lean 业务核心中练习可移植标量状态，而不涉及特定于链的账户模型。
ValueVault 是下一个共享场景：它覆盖多个标量状态字段、算术、事件发射和区块上下文读取，同时应用源代码仍保持链无关。

相关：[可移植 IR](portable-ir.md),
[能力注册表](capability-registry.md),
[Decisions](decisions.md)。

## 场景定义

### Counter

一个合约维护单个无符号 64 位计数器。

| 操作 | 行为 |
|---|---|
| `initialize` | 将计数器设置为 `0` |
| `increment` | 将 `1` 加到计数器 |
| `get` | 返回当前计数器值 |

v0 不需要原生代币转账、跨合约调用或事件（v1 中可选 `events.emit`）。

### ValueVault

一个合约跟踪 deposit、release、累计 fee、最近值、最近 checkpoint 以及操作计数。

| 操作 | 行为 |
|---|---|
| `initialize(initial)` | 设置初始 balance 和 checkpoint |
| `deposit(amount)` | 将 `amount` 加到 balance，并发射 `ValueDeposited` |
| `charge_fee(gross, fee_bps)` | 将 gross 拆分成 fee/net，把 net 加到 balance，累计 fees，并发射 `ValueCharged` |
| `release(amount)` | 从 balance 中减去 `amount`，加入 released，并发射 `ValueReleased` |
| `snapshot` | 读取目标区块/checkpoint 上下文，更新 `last_checkpoint`，发射 `ValueSnapshot`，并返回 balance |
| `get_balance` | 返回 balance |
| `get_net_value` | 返回 `balance - fees` |

应用模块里不嵌入 EVM、Solana 或 NEAR 专用 API。目标相关的 selector、Solana instruction tag、WAT export、metadata、manifest、IDL 和 client 都是 adapter 输出。

## 所需能力

| 能力 id | 使用者 |
|---|---|
| `storage.scalar` | Counter 和 ValueVault 的状态操作 |
| `events.emit` | ValueVault 生命周期事件 |
| `env.block` | ValueVault checkpoint 读取 |
| `caller.sender` | v1 中的可选访问控制 |

## 目标特定适配

每个目标适配器将相同的逻辑场景映射到原生机制：

| 目标 | 状态表示 | 冒烟测试 |
|---|---|---|
| `evm` | 合约存储槽 | Foundry + `vm.etch` |
| `wasm-cosmwasm` | 宿主 KV 中的字符串键 `"count"` | `cosmwasm-check` + instantiate/execute/query |
| `solana-sbpf-asm` | 账户数据字段 | `sbpf test` (Mollusk) + Surfpool/Rust live smoke |
| `move-aptos` | 签名者账户下的 `Counter` 资源 | `aptos move test` |
| `psy-dpn` | Psy 存储字段，在 v0 中可能是 `Felt`/`U32` | `dargo compile` + 内存冒烟测试 |

目标特定的账户 schema 和 manifest 是适配器关注点——不会隐藏在可移植 Lean 逻辑内部。有关指令 manifest 格式和 direct-assembly 路线（D-026），请参阅 [solana-sbpf-asm.md](targets/solana-sbpf-asm.md)。

## Phase 2 验收标准

当**两个**并行 spike 独立通过时，Phase 2 即告完成：

### CosmWasm (`wasm-cosmwasm`)

- [ ] Counter Wasm 导出所需的 CosmWasm 入口。
- [ ] `cosmwasm-check` 通过。
- [ ] instantiate → increment → query 返回预期计数。
- [ ] 制品元数据记录 `target: wasm-cosmwasm` 和所使用的能力。

### Solana (`solana-sbpf-asm`)

- [ ] `--emit-sbpf-asm` 产生可被 `sbpf build` 接受的有效 `.s`。
- [ ] `sbpf build` 产生可加载的 eBPF ELF (`.so`)。
- [ ] 在 `sbpf test` (Mollusk) 和 Surfpool/Rust live smoke 中执行 initialize → increment → read counter。
- [ ] 指令 manifest (`manifest.toml`) 记录账户布局。
- [ ] 能力检查器用包含 target id 的诊断拒绝不支持的能力。

### 联合（在两个 spike 之后）

- [x] 同一个 `contract_source` 模块降级到 EVM + Solana + NEAR（见
      `Examples/Shared/Counter.lean` 和 `just portable-counter-multi-target`）。
- [x] ValueVault 从同一个 `contract_source` 模块降级到 EVM + Solana + NEAR，
      覆盖 EVM metadata、Solana manifest/IDL/client metadata，以及 NEAR
      WAT/deploy metadata（见 `Examples/Shared/ValueVault.lean` 和
      `just portable-value-vault`）。
- [ ] 文档列出了此场景下每个目标支持的能力。

## 多 target authoring 演示（CS-1.5）

规范 portable Counter 位于
[`ProofForge/Contract/Examples/Counter.lean`](../../ProofForge/Contract/Examples/Counter.lean)
（`contract_source`）。面向应用的入口：

[`Examples/Shared/Counter.lean`](../../Examples/Shared/Counter.lean)

**同一个文件**构建到三条主链：

```bash
just portable-counter-multi-target
```

或手动：

```bash
lake env proof-forge build --target evm --root . \
  -o build/portable-counter/Counter.bin Examples/Shared/Counter.lean

lake env proof-forge build --target solana-sbpf-asm --root . \
  -o build/portable-counter/Counter.s Examples/Shared/Counter.lean

lake env proof-forge build --target wasm-near --root . \
  -o build/portable-counter/near Examples/Shared/Counter.lean
```

链的选择完全在 build time；Lean 模块不会 per-target 分叉。

规范 portable ValueVault 也遵循同一模式：

[`Examples/Shared/ValueVault.lean`](../../Examples/Shared/ValueVault.lean)

用同一个文件构建并验证三条主 target：

```bash
just portable-value-vault
```

legacy `Examples/Learn/ValueVault.learn` fixture 继续保留，用于 parser
等价覆盖。它不是新合约推荐的 authoring 路径。

分步 walkthrough 见
[tutorials/portable-contract-three-targets.md](../tutorials/portable-contract-three-targets.md)
（中文：[portable-contract-three-targets.zh.md](tutorials/portable-contract-three-targets.zh.md)）。

## Resource budget baseline（CS-5.2）

Gate G0 要求行为 parity **以及** 三个主目标的逐步 resource budget。
`contract_source` Counter 与 ValueVault 场景在以下文件中固定 baseline：

- `testkit/scenarios/counter.toml`
- `testkit/scenarios/value-vault.toml`

每个场景在 `[scenario.reference.toolchain]` 下记录参考 harness 工具链
（revm、Mollusk、wasmtime、sbpf）。当依赖升级改变测量成本时，应在同一 PR
中更新 scenario TOML。

| 场景 | 断言指标 | 典型容差 |
|---|---|---|
| Counter | 每步 `evm_gas`、`solana_cu`、`near_gas` | EVM ±10%，Solana/NEAR ±5% |
| ValueVault | 同上 | 同上 |

本地运行 budget gate：

```bash
just testkit-budget-gate
```

该命令通过 `just testkit` 执行 Counter 与 ValueVault 场景。CI 通过完整
`just testkit` 套件运行相同断言；Solana CU 或 EVM gas 的刻意回归会使 gate 失败。

锁定新 baseline 时，可用 `--trace` 查看测量值：

```bash
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter --trace
```

将报告的 `solana_cu`、`evm_gas`、`near_gas` 复制到 scenario 文件。详见
[RFC 0010](../rfcs/0010-resource-budgets-as-gates.md)。

## ZK 目标 Experimental 标准

`psy-dpn` 不属于 Phase 2 退出标准，但它现在已经通过生成 `.psy` 源码和 Dargo 验证复用了 Counter 场景。

- [x] Counter IR 可以用 Psy 兼容的标量类型表示。
- [x] 生成的 `.psy` 包可以使用 `dargo compile` 编译。
- [x] 发射 DPN 电路 JSON 并记录在制品元数据中。
- [x] 冒烟路径已经可运行，覆盖 `dargo test`、`dargo compile`、
      `dargo execute`、`dargo generate-abi` 和制品元数据校验。

## 示例位置

| 目标 | 路径 | 状态 |
|---|---|---|
| **所有主链** | `Examples/Shared/Counter.lean`、`Examples/Shared/ValueVault.lean`（`contract_source`） | **代码库中** — `just portable-counter-multi-target`、`just portable-value-vault` |
| EVM | `Examples/Evm/Contracts/Counter.lean` | **代码库中**（EVM 示例树） |
| CosmWasm | `Examples/CosmWasm/Counter.golden.wat` | **代码库中 (Spike)** — 通过 `proof-forge emit --target wasm-cosmwasm --fixture counter` 生成 golden WAT；`just cosmwasm-counter-smoke` |
| Solana | `Examples/Solana/Counter.lean` + manifest | **代码库中**（IR fixture 参考） |
| Aptos | `Examples/Aptos/Counter/golden/` | **代码库中 (Spike)** — golden Move module；`just aptos-counter-smoke` |
| Cloudflare Workers | `Examples/CloudflareWorkers/Counter/` + `emit --format ts` | **代码库中 (Spike)** — TS package + `scripts/ts/counter-ir-smoke.sh` |
| Psy DPN | `Examples/Psy/*.golden.psy`, `scripts/psy/*-smoke.sh` | **代码库中** |

## v0 范围之外

- PDA 派生
- CPI / 子消息
- 访问控制 / 所有权
- 超过 U64 的溢出（目标可能会限制得更低）
