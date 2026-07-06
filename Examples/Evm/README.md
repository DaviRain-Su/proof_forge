# ProofForge EVM Examples

This directory demonstrates compiling EVM contracts through ProofForge's unified
portable entry path.

## Unified entry

Write contracts with `contract_source` in Lean:

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

Build:

```bash
lake env proof-forge build --target evm \
  --root . \
  -o build/evm/Counter.bin \
  Examples/Evm/Contracts/Counter.lean
```

`ArrayExample.lean` and the stdlib examples use the same unified path via
`contract_source` / `def spec : ContractSpec`.

No `.evm-methods` sidecar is required. The CLI loads `spec : ContractSpec` from
the Lean module and lowers through the portable IR EVM backend.

See [docs/authoring-model.md](../../docs/authoring-model.md) and
[docs/targets/evm.md](../../docs/targets/evm.md).

## Build all examples

From the repository root:

```bash
scripts/evm/build-examples.sh
```

This compiles each portable contract to EVM bytecode, diffs generated Yul
against sibling `.golden.yul` fixtures, and validates artifact metadata. It
expects Foundry (`cast`/`forge`) and `solc` on `PATH`.

## Run Foundry smoke tests

```bash
scripts/evm/foundry-smoke.sh
```

## Shared scenario Counter

`Counter.lean` follows the cross-target shared scenario (`initialize`,
`increment`, `get`). See [docs/shared-scenario.md](../../docs/shared-scenario.md).
