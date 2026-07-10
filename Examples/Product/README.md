# Product examples (business logic only)

**Canonical authoring surface.** See [docs/product-sdk.md](../../docs/product-sdk.md).

Authors write **intents and rules** here. `proof-forge build --target …`
materializes EVM / Solana / NEAR / Soroban form. You do **not** write accounts,
PDA, CPI, Promise, slots, token standards, or pack layouts (JSON/ABI/ix).

```bash
just product
just product-token-near     # TokenSpec plan + NEP-141 body on wasm-near
just near-compare           # NEAR compare bench (testkit/compare/near/counter)
just product-token-solana   # TokenSpec → Solana SPL plan
just product-protocol-ft    # external_token transfer (no Protocols import)
```

Taxonomy: [docs/examples-and-tests-taxonomy.md](../../docs/examples-and-tests-taxonomy.md).

## Rules (`just portable-default`)

- `import ProofForge.Contract.Source` or `ProofForge.Contract.Token` only
- No `Source.Solana` / `Source.Near` / chain backends
- No author-selected `TokenStandard` — only `TokenFeature`s
- No account/PDA/CPI DSL; no NEAR Promise; no CREATE2 / selector pins
- Name-only `entry` / `query`

## Tutorial from zero

| Step | Source | Gate |
|------|--------|------|
| 0 | rules | `just portable-default` |
| 1 | [Counter.lean](Counter.lean) | `just portable-counter-multi-target` |
| 2 | [Ownable.lean](Ownable.lean) | `just portable-auth-materialize` |
| 3 | [FungibleToken.lean](FungibleToken.lean) | `just shared-token-intent` · `just token-feature-matrix` |
| 4 | [RemoteCall.lean](RemoteCall.lean) | `just portable-remote-call-multi-target` |
| 5 | [ExternalTokenTransfer.lean](ExternalTokenTransfer.lean) | `just product-protocol-ft` |
| 6 | [AuthRemoteCall.lean](AuthRemoteCall.lean) | `just portable-solana-accounts` |

Full narrative: [docs/tutorials/portable-shared-path.md](../../docs/tutorials/portable-shared-path.md).

## Solana account auto-fill (U3 — no Source.Solana)

Product examples **must not** import `ProofForge.Contract.Source.Solana`.
Accounts are inferred at materialize time from portable intents:

| Product intent | Solana accounts synthesized | Gate |
|----------------|----------------------------|------|
| Ownable / roles / caller | leading `authority` signer + program state | `just portable-solana-accounts` |
| `nativeValue` (StakingVault) | **writable** leading signer@0 + state | same |
| `remote` / `declareRemote` (RemoteCall) | payer/signer + state + `callee_program` | `just portable-remote-call-multi-target` |
| caller + debit + remote (AuthRemoteCall) | authority + state + `callee_program` | `just portable-solana-accounts` |
| `external_token` / vault protocol peers | peer strings in pool + CPI/callee roles | `just product-protocol-ft` / matrix |

**Peer declaration:** use `remote name "logical.peer" "method";` (or `declareRemote`).
Solana **empty peer** fails closed at `resolveSpec` with a diagnostic that points
at `remote` / `declareRemote` (no silent `portable.peer` invent). Deploy-time
host rewrite: `--peer logical.peer=…` / PeerMap.


## Catalog

| Example | Role |
|---------|------|
| [Counter.lean](Counter.lean) | state + entrypoints |
| [RemoteCall.lean](RemoteCall.lean) | portable remote + scalar ABI |
| [ExternalTokenTransfer.lean](ExternalTokenTransfer.lean) | external FT protocol intent (no Protocols import) |
| [ExternalVault.lean](ExternalVault.lean) | external ERC-4626 vault protocol intent |
| [ERC4626Vault.lean](ERC4626Vault.lean) | deployable ERC-4626 vault body (stdlib pro-rata; **product v1 frozen**) |
| [AuthRemoteCall.lean](AuthRemoteCall.lean) | caller + debit + remote |
| [ArrayExample.lean](ArrayExample.lean) | arrays |
| [HostEnvProbe.lean](HostEnvProbe.lean) | triad HostEnv (`timestamp`/`checkpointId`/`contractId`/`caller`) |
| [Ownable.lean](Ownable.lean) | owner policy |
| [OwnableHash.lean](OwnableHash.lean) | hash-width owner |
| [Pausable.lean](Pausable.lean) | pause policy |
| [OwnablePausable.lean](OwnablePausable.lean) | owner-gated pause |
| [AccessControl.lean](AccessControl.lean) | roles |
| [ReentrancyGuard.lean](ReentrancyGuard.lean) | lock-state |
| [ValueVault.lean](ValueVault.lean) | events + context |
| [StakingVault.lean](StakingVault.lean) | nativeValue deposits |
| [RoleGatedToken.lean](RoleGatedToken.lean) | roles + transfer |
| [FungibleToken.lean](FungibleToken.lean) | TokenSpec mintable+burnable |
| [FeeToken.lean](FeeToken.lean) | transfer_fee feature |
| [SoulboundToken.lean](SoulboundToken.lean) | non_transferable feature |

Chain goldens live under [`../Backend/`](../Backend/) — not authoring sources.
