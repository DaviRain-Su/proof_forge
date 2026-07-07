# ProofForge Examples

Examples are split by authoring intent, not by backend implementation detail.

## Shared Portable Contracts

Use `Examples/Shared/` for contracts that should compile to multiple targets by
changing only `--target`. These are the canonical application-facing examples:

- `Counter.lean`
- `ArrayExample.lean`
- `Ownable.lean`, `Pausable.lean`, and `ReentrancyGuard.lean` for portable
  stdlib mixin facades
- `RoleGatedToken.lean`
- `StakingVault.lean`
- `ValueVault.lean`
- `FungibleToken.lean`, `FeeToken.lean`, and `SoulboundToken.lean` for
  target-neutral token intent examples

These modules should avoid target-only capabilities unless the compiler can
route or reject them through target capabilities. The portable smoke scripts and
Rust testkit scenarios should prefer this directory.

## Target-Specific Contracts

Use target directories when the source intentionally exercises one chain's
native surface or a backend-specific artifact format:

- `Evm/` for EVM-specific ABI, constructor, event, proxy, and Yul golden probes.
- `Solana/` for Solana sBPF assembly, manifest, PDA/CPI/sysvar, and account
  layout probes.
- `WasmNear/` and `near/spike/` for NEAR/Wasm target-first examples and older
  EmitWat spike fixtures.
- `Psy/`, `Aleo/`, `CosmWasm/`, `CloudflareWorkers/`, and
  `cloudflare-workers-spike/` for target research or target-specific golden
  artifacts.

If an example starts in a target directory but its contract logic is useful
across chains, move the shared logic to `Examples/Shared/` and keep only
target-specific golden files, manifests, or runtime probes in the target
directory. Compatibility entrypoints may import the shared module and attach
target-only metadata such as EVM constructor bindings.

## Legacy Parser Fixtures

`Examples/Learn/` contains compatibility fixtures for the legacy `.learn`
parser and token intent syntax. New product examples should use Lean
`contract_source` modules in `Examples/Shared/` unless they are deliberately
testing the Learn parser.
