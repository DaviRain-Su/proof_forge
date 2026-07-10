# ProofForge Examples

**Product thesis:** write business logic once; choose `--target` to materialize
chain form. **Start here:** [docs/product-sdk.md](../docs/product-sdk.md).

Taxonomy: [examples-and-tests-taxonomy](../docs/examples-and-tests-taxonomy.md).

## Product (author-facing)

**[`Product/`](Product/)** — portable contracts and TokenSpec intents only.
This is the **only** authoring tree for multi-chain apps.

```bash
just product
```

Canonical sources (change only `--target` to build EVM · Solana · NEAR · …):

- `Counter.lean`
- `HostEnvProbe.lean`
- `ArrayExample.lean`
- `RemoteCall.lean`, `AuthRemoteCall.lean`
- `Ownable.lean`, `OwnableHash.lean`, `Pausable.lean`, `OwnablePausable.lean`,
  `AccessControl.lean`, `ReentrancyGuard.lean`
- `RoleGatedToken.lean`, `StakingVault.lean`, `ValueVault.lean`
- `FungibleToken.lean`, `FeeToken.lean`, `SoulboundToken.lean`,
  `SoulboundTokenBody.lean`
- `ERC4626Vault.lean`, `ExternalVault.lean`, `ExternalTokenTransfer.lean`,
  `ProRataVault.lean`, `StorageDeposit.lean`
- `StatusMessage.lean`, `GuestBook.lean`, `EscrowVault.lean`
- `VestingVault.lean`, `TimelockVault.lean`, `HeightLockVault.lean`

Rules: no Solana account/PDA/CPI DSL, no NEAR Promise, no hand-written EVM
selectors, no author-chosen token standard. Enforced by `just portable-default`.

Tutorial: [docs/tutorials/portable-shared-path.md](../docs/tutorials/portable-shared-path.md)
and `Product/README.md`.

## Backend (compiler / fixtures only)

**[`Backend/`](Backend/)** — **not** the product authoring path.
Engine goldens (Yul/sBPF/WAT), Solana CPI packing fixtures, Learn parser
samples. Do not teach Backend as the SDK.

| Path | Role |
|------|------|
| `Backend/Evm/` | Yul goldens, Foundry probes, UUPS/CREATE2 fixtures |
| `Backend/Solana/` | sBPF goldens, manifests; Source.Solana only when needed |
| `Backend/WasmNear/` | WAT goldens / NEAR fixtures |
| `Backend/Learn/` | Legacy `.learn` parser fixtures |
| `Backend/Psy/`, `Aleo/`, `Aptos/`, `CosmWasm/`, `CloudflareWorkers/`, … | Research / target spikes |

If a Backend fixture starts as useful business logic, **move the logic into
`Product/`** and leave only goldens or thin re-exports under Backend.

## Tests

| Gate | Command |
|------|---------|
| Product multi-target | `just product` |
| Full engineering | `just check` |

Product tests assert materialization from Product sources. Backend tests
(Solana CPI packing, EmitWat probes, …) validate the compiler — they do not
define the author API.
