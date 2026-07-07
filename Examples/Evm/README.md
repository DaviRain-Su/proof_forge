# ProofForge EVM Examples

This directory keeps EVM-specific fixtures for ProofForge's unified portable
entry path: golden Yul files, Foundry runtime smokes, constructor/proxy probes,
and compatibility entrypoints for shared examples.

Portable examples that should compile by changing only `--target` belong in
[Examples/Shared](../Shared/README.md).

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
  Examples/Shared/Counter.lean
```

`Counter`, `ValueVault`, `RoleGatedToken`, and `StakingVault` are the primary
multi-target shared scenarios. `SimpleToken`, `OwnableERC20`, and
`AccessControlProbe` are authored in `Examples/Shared/` as stdlib composition
examples; the same filenames under `Contracts/` are compatibility symlinks for
EVM golden and Foundry scripts.

`ArrayExample.lean`, `VerifiedVault.lean`, constructor probes, proxy probes, and
the `stdlib/` wrappers are EVM-focused fixtures because they exercise
EVM-specific ABI, deployment, callvalue/native-transfer, or golden-output
behavior.

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

## Shared Scenarios

The canonical shared examples live in [Examples/Shared](../Shared/README.md).
See [docs/shared-scenario.md](../../docs/shared-scenario.md) for the Counter and
ValueVault scenario details.
