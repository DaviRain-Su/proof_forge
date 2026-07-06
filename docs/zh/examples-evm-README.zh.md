# ProofForge EVM 示例

本目录演示如何通过 ProofForge 的统一 portable 入口编译 EVM 合约。

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
  Examples/Evm/Contracts/Counter.lean
```

`ArrayExample.lean` 以及 stdlib 示例通过相同的统一路径，使用 `contract_source` / `def spec : ContractSpec`。

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

## 共享场景 Counter

`Counter.lean` 遵循跨目标共享场景（`initialize`、`increment`、`get`）。请参阅 [docs/shared-scenario.md](../../docs/shared-scenario.md)。
