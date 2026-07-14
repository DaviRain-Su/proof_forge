# Tutorial: Shared path from zero (Counter → Ownable → Token → Remote)

Status: **Product tutorial (T4.2)**  
Audience: new contributors writing portable business intent only

This is the recommended **zero-to-multi-target** path. Every source lives under
`Examples/Product/`, uses name-only `entry`/`query` (no hand-written EVM
selectors), and never imports Solana/NEAR chain Surfaces.

Related:

- [Examples/Product/README](../../Examples/Product/README.md) — table + rules
- [Portable three-target Counter](portable-contract-three-targets.md) — deeper Counter lab
- [Authoring model](../authoring-model.md) — selectors & family-only constructors
- Aggregate gate: `just portable-tutorial`

## Prerequisites

```bash
# From repo root
lake build
# Optional tools used by multi-target scripts
# solc, wat2wasm, cast — gates skip or soft-fail when missing where documented
```

## Step 0 — Shared product rules

```bash
just portable-default
```

Confirms Shared sources stay business-only (no chain Surface, no TokenStandard,
no Promise/CREATE2/selector pins).

## Step 1 — Counter (state + entrypoints)

**Source:** [Examples/Product/Counter.lean](../../Examples/Product/Counter.lean)

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
```

```bash
just portable-counter-multi-target
```

Same file → EVM bytecode · Solana sBPF · NEAR WAT. No per-chain source fork.

## Step 2 — Ownable (business check → native fail)

**Sources:** [Ownable.lean](../../Examples/Product/Ownable.lean),
[OwnablePausable.lean](../../Examples/Product/OwnablePausable.lean)

Authors write `guard_owner` / `caller` only. Solana synthesizes a leading
`authority` signer; NEAR/Soroban panic/unreachable; EVM reverts.

```bash
just portable-auth-materialize
# equivalent: lake env lean --run Tests/PortableAuthMaterialize.lean
```

Chooser: Ownable (u64 handle) vs OwnableHash — see
[product-authoring-architecture](../product-authoring-architecture.md)
“When to use Ownable vs OwnableHash”.

## Step 3 — Token intent (features, not standards)

**Source:** [FungibleToken.lean](../../Examples/Product/FungibleToken.lean)

```lean
def spec : TokenSpec := {
  name := "Proof Token"
  symbol := "PRF"
  decimals := 9
  initialSupply? := some 1000000
  features := #[.mintable, .burnable]
}
```

No `TokenStandard` in source. `--target` + `--token` chooses ERC-20 / SPL /
NEP-141 plan.

```bash
just shared-token-intent
just token-feature-matrix
# fuller multi-host token smoke (needs more toolchains):
# just token-intent-smoke
```

EVM permanently rejects fee/soulbound/permit features with a Solana pointer
(T2.2). Soroban has **no** TokenSpec lane.

## Step 4 — Remote (logical peer + scalar ABI)

**Source:** [RemoteCall.lean](../../Examples/Product/RemoteCall.lean)

```lean
remote callee "peer.callee" "remote_call";
entry call_with_args returns(.u64) do
  return ProofForge.Contract.Source.remoteCallRef callee #[u64 42, u64 7];
```

```bash
just portable-remote-call-multi-target
```

Materializes EVM CALL · Solana CPI · NEAR `promise_create` · Soroban
`invoke_contract`. Deploy-time peer map: `--peer` / `--peers-demo`.

## Step 5 — Auth + transfer-style debit + remote

**Source:** [AuthRemoteCall.lean](../../Examples/Product/AuthRemoteCall.lean)

Combines `caller`, local balance debit, and remote forward. Solana auto-fills
authority / state / `callee_program` without any account DSL (T3.2).

```bash
just portable-solana-accounts
```

## Checklist

- [ ] `just portable-tutorial` green (or each step above)
- [ ] Shared sources use **name-only** entrypoints
- [ ] No `import` of Solana/NEAR Surface modules under Shared
- [ ] Token examples use `TokenFeature` only
- [ ] Remotes use `remote` + `remoteCallRef`, not host string-pool APIs

## Next

- Scaffold: `proof-forge init` + `just portable-init-smoke`
- Deeper Counter lab: [portable-contract-three-targets.md](portable-contract-three-targets.md)
- Policy multi-host: Pausable, AccessControl, Reentrancy — `portable-auth-materialize`
- Product plan status: [portable-sdk-unification plan](../superpowers/plans/2026-07-09-portable-sdk-unification.md)
