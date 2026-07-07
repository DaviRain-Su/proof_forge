# ProofForge EVM 示例

本目录保存 ProofForge 统一 portable 入口的 EVM 专用 fixture：golden Yul
文件、Foundry 运行时冒烟测试、constructor/proxy probe，以及 stdlib/protocol-specific
composition 示例。

只需改变 `--target` 就应编译到不同链的 portable 示例，应放在
[Examples/Shared](../../Examples/Shared/README.md)。

## 统一入口

在 Lean 中使用 `contract_source` 编写合约：

```lean
import ProofForge.Contract.Source

namespace MyContract
open ProofForge.Contract.Source

contract_source MyContract do
  state count : .u64
  entry «initialize» do
    count := u64 0;
  entry increment do
    let n : .u64 := count;
    count := n +! u64 1;
  query get returns(.u64) do
    return count;
end MyContract
```

构建：

```bash
lake env proof-forge build --target evm \
  --root . \
  -o build/evm/Counter.bin \
  Examples/Shared/Counter.lean
```

`Counter`、`ValueVault`、`RoleGatedToken` 和 `StakingVault` 是主要的多目标
shared contract 场景。

`SimpleToken`、`OwnableERC20`、`AccessControlProbe`、`ArrayExample.lean`、
`VerifiedVault.lean`、constructor probe、proxy probe 和 `stdlib/` wrapper 是
EVM-focused fixture，因为它们覆盖 EVM ABI、ERC-style stdlib composition、部署、
callvalue/native-transfer 或 golden-output 行为。Chain-neutral token intent 位于
`Examples/Shared/FungibleToken.lean`，形式是 `TokenSpec`；EVM target 会把该 intent
降低为 ERC-20-compatible artifact。

不需要 `.evm-methods` sidecar。CLI 会从 Lean 模块加载 `spec : ContractSpec`，并通过 portable IR EVM 后端降级。

请参阅 [docs/authoring-model.md](../../docs/authoring-model.md) 和
[docs/targets/evm.md](../../docs/targets/evm.md)。

## 构建所有示例

从仓库根目录执行：

```bash
scripts/evm/build-examples.sh
```

这会将每个 portable 合约编译为 EVM 字节码，把生成的 Yul 与同级 `.golden.yul` fixture 做 diff，并校验 artifact metadata。需要在 `PATH` 上安装 Foundry (`cast`/`forge`) 和 `solc`。

## 运行 Foundry 冒烟测试

```bash
scripts/evm/foundry-smoke.sh
```

## Shared 场景

canonical shared 示例位于 [Examples/Shared](../../Examples/Shared/README.md)。
Counter 和 ValueVault 场景细节见
[docs/shared-scenario.md](../../docs/shared-scenario.md)。Target-neutral token-intent
示例见 [Examples/Shared/FungibleToken.lean](../../Examples/Shared/FungibleToken.lean)。
