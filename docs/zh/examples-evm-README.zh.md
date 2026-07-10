# ProofForge EVM 示例

本目录存放 ProofForge 统一可移植入口路径的 EVM 特定 fixture：黄金 Yul 文件、Foundry 运行时冒烟测试、构造函数/代理探测，以及标准库/特定协议的组合示例。

仅需更改 `--target` 即可编译的可移植示例属于 [Examples/Product](../../Examples/Product/README.md)。

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
  Examples/Product/Counter.lean
```

`Counter`、`ArrayExample`、`Ownable`、`Pausable`、`ReentrancyGuard`、
`ValueVault`、`RoleGatedToken` 和 `StakingVault` 是主要的多目标共享合约场景。

`Examples/Backend/Evm/Contracts/Counter.lean` 和
`Examples/Backend/Evm/Contracts/ArrayExample.lean` 是围绕
`Examples/Product` 中相应模块的兼容性包装器。Counter 仅添加了由 constructor-init 冒烟测试使用的 EVM 部署时构造函数制品元数据；ArrayExample
保留了历史 EVM 黄金 Yul 路径。
`stdlib/Ownable.lean`、`stdlib/Pausable.lean` 和
`stdlib/ReentrancyGuard.lean` 路径也是围绕
规范 stdlib mixin 的共享外观的兼容性包装器。

`Ierc20Client` / `Ierc721Client`（Layer B：通过
`Protocols.Evm.IERC20` / `IERC721` 调用外部 ERC-20 / ERC-721；而非可部署的 `Stdlib` mixin）、
`SimpleToken`、`OwnableERC20`、`AccessControlProbe`、`VerifiedVault.lean`、
构造函数探测、代理探测以及剩余的 `stdlib/` 包装器是
专注于 EVM 的 fixture，因为它们行使了 EVM ABI、ERC 风格的 stdlib
组合、部署、callvalue/原生转账或黄金输出行为。
链中立的代币意图作为 `TokenSpec` 存在于
`Examples/Product/FungibleToken.lean` 中；EVM 目标将
该意图降级为 ERC-20 兼容的制品。

不需要 `.evm-methods` sidecar。CLI 从
Lean 模块加载 `spec : ContractSpec` 并通过可移植 IR EVM 后端进行降级。

参见 [docs/authoring-model.md](authoring-model.zh.md) 和
[docs/targets/evm.md](targets/evm.zh.md)。

## 构建所有示例

从仓库根目录：

```bash
scripts/evm/build-examples.sh
```

这会将每个可移植合约编译为 EVM 字节码，将生成的 Yul 与同级 `.golden.yul` fixture 进行对比，并验证制品元数据。它需要在 `PATH` 上安装 Foundry (`cast`/`forge`) 和 `solc`。

## 运行 Foundry 冒烟测试

```bash
scripts/evm/foundry-smoke.sh
```

## 共享场景

规范的共享示例位于 [Examples/Product](../../Examples/Product/README.md)。
参见 [docs/shared-scenario.md](shared-scenario.zh.md) 了解 Counter 和 ValueVault 场景详情。
参见 [Examples/Product/FungibleToken.lean](../../Examples/Product/FungibleToken.lean) 了解目标中立的 token-intent 示例。
