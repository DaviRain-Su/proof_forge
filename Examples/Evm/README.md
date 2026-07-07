# ProofForge EVM Examples

This directory keeps EVM-specific fixtures for ProofForge's unified portable
entry path: golden Yul files, Foundry runtime smokes, constructor/proxy probes,
and stdlib/protocol-specific composition examples.

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

`Counter`, `ArrayExample`, `Ownable`, `Pausable`, `ReentrancyGuard`,
`ValueVault`, `RoleGatedToken`, and `StakingVault` are the primary multi-target
shared contract scenarios.

`Examples/Evm/Contracts/Counter.lean` and
`Examples/Evm/Contracts/ArrayExample.lean` are compatibility wrappers around
the corresponding modules in `Examples/Shared`. Counter adds only EVM
deploy-time constructor metadata used by constructor-init smokes; ArrayExample
preserves the historical EVM golden Yul path.
The `stdlib/Ownable.lean`, `stdlib/Pausable.lean`, and
`stdlib/ReentrancyGuard.lean` paths are also compatibility wrappers around
shared facades for the canonical stdlib mixins.

`SimpleToken`, `OwnableERC20`, `AccessControlProbe`, `VerifiedVault.lean`,
constructor probes, proxy probes, and the remaining `stdlib/` wrappers are
EVM-focused fixtures because they exercise EVM ABI, ERC-style stdlib
composition, deployment, callvalue/native-transfer, or golden-output behavior.
Chain-neutral token intent lives in
`Examples/Shared/FungibleToken.lean` as a `TokenSpec`; the EVM target lowers
that intent to an ERC-20-compatible artifact.

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
ValueVault scenario details. See
[Examples/Shared/FungibleToken.lean](../Shared/FungibleToken.lean) for the
target-neutral token-intent example.
