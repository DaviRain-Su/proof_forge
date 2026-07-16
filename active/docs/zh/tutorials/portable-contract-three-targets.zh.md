# 教程：一个业务模块、三个目标、零源码分叉

状态：**Worked example (CS-5.3)**

本教程端到端演示 ProofForge 编写模型：在 `contract_source` 中编写一次可移植业务逻辑，然后仅通过更改 `--target` 将**同一个 Lean 文件**编译到 EVM、Solana sBPF 和 NEAR/Wasm。

相关文档：

- [编写模型](../authoring-model.zh.md)
- [共享场景](../shared-scenario.zh.md)
- [Examples/Product/Counter.lean](../../../Examples/Product/Counter.lean)

## 你将构建什么

使用 `Examples/Product/Counter.lean` 中的 canonical Counter 模块。它提供三个 entrypoint：

| 调用 | 效果 |
|---|---|
| `initialize` | 将 counter 设为 `0` |
| `increment` | 加 `1` |
| `get` | 返回当前值 |

该模块只使用可移植 capability（`storage.scalar`）。源码中不出现 EVM Yul、Solana 账户布局或 NEAR host import。

## 步骤 1 — 阅读源码（无目标分叉）

打开 `Examples/Product/Counter.lean`：

```lean
contract_source Counter do
  state count : .u64

  entry «initialize» do
    count := u64 0;

  entry increment do
    let n : .u64 := count;
    count := n +! u64 1;

  query get returns(.u64) do
    return count;
end Examples.Product.Counter
```

要点：

- 业务状态与控制流写在 Lean SDK 语法中。
- 没有 `if target == evm` 分支，也没有按链复制的文件。
- 目标路由发生在构建阶段。

## 步骤 2 — 编译到三个主目标

在仓库根目录，对同一文件执行三次 build：

```bash
lake env proof-forge build --target evm --root . \
  -o build/tutorial-counter/Counter.bin \
  --yul-output build/tutorial-counter/Counter.yul \
  --artifact-output build/tutorial-counter/Counter.proof-forge-artifact.json \
  Examples/Product/Counter.lean

lake env proof-forge build --target solana-sbpf-asm --root . \
  -o build/tutorial-counter/Counter.s \
  --artifact-output build/tutorial-counter/Counter.solana-artifact.json \
  Examples/Product/Counter.lean

lake env proof-forge build --target wasm-near --root . \
  -o build/tutorial-counter/near \
  --artifact-output build/tutorial-counter/Counter.near-artifact.json \
  Examples/Product/Counter.lean
```

每条命令都会生成目标原生 artifact 以及结构化 metadata JSON。Lean 源文件始终不变。

## 步骤 3 — 运行已校验的多目标演示

ProofForge 提供脚本，用于 build、golden diff、metadata 校验，并在可用时通过 offline host 执行 NEAR WAT：

```bash
just portable-counter-multi-target
```

这是确认环境能在三个主目标上 lower 共享 Counter 模块的最快方式。

## 步骤 4 — 在 testkit 中验证行为与 budget parity

统一 testkit 用同一份 scenario 定义跑每个声明的目标，并比较可观察 trace：

```bash
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter
```

预期摘要行包括：

```text
scenario counter target wasm-near: ok (4 call outcome(s))
scenario counter target evm: ok (4 call outcome(s))
scenario counter target solana-sbpf-asm: ok (4 call outcome(s))
scenario counter trace parity: ok (3 target(s))
```

EVM gas、Solana compute unit 和 NEAR gas 的 budget baseline 固定在
`testkit/scenarios/counter.toml`。运行聚焦的 budget gate：

```bash
just testkit-budget-gate
```

## 步骤 5 — 扩展到更丰富的可移植逻辑（ValueVault）

当合约需要 event 与 block 上下文时，模式相同。
`Examples/Product/ValueVault.lean` 增加 `events.emit` 和 `env.block`，源码仍保持链中立。

构建与校验：

```bash
just portable-value-vault
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault
```

ValueVault budget baseline 位于 `testkit/scenarios/value-vault.toml`。

## 步骤 6 — 使用高层 token intent（可选）

可移植 Counter/ValueVault 演示 chain-neutral contract logic。Fungible token
使用更高层的 `TokenSpec` intent 边界，而不是在 source 里命名某条链的协议：

```bash
lake env proof-forge build --target evm --token --root . \
  -o build/shared-fungible-token/FungibleToken.erc20.bin \
  --yul-output build/shared-fungible-token/FungibleToken.erc20.yul \
  Examples/Product/FungibleToken.lean

lake env proof-forge build --target solana-sbpf-asm --token --root . \
  -o build/shared-fungible-token/FungibleToken.solana-token-plan.json \
  Examples/Product/FungibleToken.lean
```

source 保持 target-neutral；EVM target 选择 ERC-20-compatible artifact，
Solana target 选择 SPL Token / Token-2022 plan。EVM stdlib composition 示例仍放在
`Examples/Backend/Evm/Contracts/`。

## 检查清单

- [ ] 在 `Examples/Product/`（或你的项目根）下有一个 Lean 模块，无按目标复制的源码。
- [ ] 三条 `proof-forge build --target ...` 对 `evm`、`solana-sbpf-asm`、
      `wasm-near` 均成功。
- [ ] 本地 `just portable-counter-multi-target` 通过。
- [ ] `just testkit-budget-gate` 通过（行为 + resource budget）。
- [ ] Artifact metadata 记录 `sourceKind: contract-sdk` 及模块所需 capability。
- [ ] Token 示例使用 `TokenSpec` 或其他高层 intent 边界，而不是在 shared source
      中命名 target protocol。

## 下一步

- 阅读 [shared-scenario.md](../shared-scenario.zh.md) 了解 Counter/ValueVault
  capability 表与 budget baseline 说明。
- 用 `proof-forge init` 脚手架新项目，并将 `--root` 指向你的工作区。
- 在 [implementation-backlog.md](../implementation-backlog.zh.md) Workstream 34
  中跟踪产品 backlog。
