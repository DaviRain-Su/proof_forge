# Tutorial: One Business Module, Three Targets, Zero Source Forks

Status: **Worked example (CS-5.3)**

This tutorial shows the ProofForge authoring model end to end: write portable
business logic once in `contract_source`, then compile the **same Lean file**
to EVM, Solana sBPF, and NEAR/Wasm by changing only `--target`.

Related:

- [Authoring model](../authoring-model.md)
- [Shared scenario](../shared-scenario.md)
- [Examples/Shared/Counter.lean](../../Examples/Shared/Counter.lean)

## What you will build

You will use the canonical Counter module at
`Examples/Shared/Counter.lean`. It exposes three entrypoints:

| Call | Effect |
|---|---|
| `initialize` | Set counter to `0` |
| `increment` | Add `1` |
| `get` | Return current value |

The module uses only portable capabilities (`storage.scalar`). No EVM Yul,
Solana account layout, or NEAR host imports appear in the source.

## Step 1 — Read the source (no target forks)

Open `Examples/Shared/Counter.lean`:

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
end Examples.Shared.Counter
```

Notice:

- Business state and control flow live in Lean SDK syntax.
- There is no `if target == evm` branch and no copied file per chain.
- Target routing happens later, at build time.

## Step 2 — Build to each primary target

From the repository root, compile the same file three times:

```bash
lake env proof-forge build --target evm --root . \
  -o build/tutorial-counter/Counter.bin \
  --yul-output build/tutorial-counter/Counter.yul \
  --artifact-output build/tutorial-counter/Counter.proof-forge-artifact.json \
  Examples/Shared/Counter.lean

lake env proof-forge build --target solana-sbpf-asm --root . \
  -o build/tutorial-counter/Counter.s \
  --artifact-output build/tutorial-counter/Counter.solana-artifact.json \
  Examples/Shared/Counter.lean

lake env proof-forge build --target wasm-near --root . \
  -o build/tutorial-counter/near \
  --artifact-output build/tutorial-counter/Counter.near-artifact.json \
  Examples/Shared/Counter.lean
```

Each command emits target-native artifacts plus structured metadata JSON. The
Lean source file never changes.

## Step 3 — Run the checked multi-target demo

ProofForge ships a script that builds, diffs goldens, validates metadata, and
exercises the NEAR WAT through the offline host when available:

```bash
just portable-counter-multi-target
```

This is the fastest way to confirm that your environment can lower the shared
Counter module on all three primary targets.

## Step 4 — Prove behavior and budget parity in testkit

The unified testkit runs the same scenario definition against every declared
target and compares observable traces:

```bash
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter
```

Expected summary lines include:

```text
scenario counter target wasm-near: ok (4 call outcome(s))
scenario counter target evm: ok (4 call outcome(s))
scenario counter target solana-sbpf-asm: ok (4 call outcome(s))
scenario counter trace parity: ok (3 target(s))
```

Budget baselines for EVM gas, Solana compute units, and NEAR gas are pinned in
`testkit/scenarios/counter.toml`. Run the focused budget gate with:

```bash
just testkit-budget-gate
```

## Step 5 — Extend to richer portable logic (ValueVault)

When a contract needs events and block context, the same pattern applies.
`Examples/Shared/ValueVault.lean` adds `events.emit` and `env.block` while
remaining chain-neutral in source form.

Build and validate:

```bash
just portable-value-vault
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault
```

ValueVault budget baselines live in `testkit/scenarios/value-vault.toml`.

## Step 6 — Use high-level token intent (optional)

Portable Counter/ValueVault demonstrate chain-neutral contract logic. Fungible
tokens use the higher-level `TokenSpec` intent boundary instead of naming a
chain protocol in source:

```bash
lake env proof-forge build --target evm --token --root . \
  -o build/shared-fungible-token/FungibleToken.erc20.bin \
  --yul-output build/shared-fungible-token/FungibleToken.erc20.yul \
  Examples/Shared/FungibleToken.lean

lake env proof-forge build --target solana-sbpf-asm --token --root . \
  -o build/shared-fungible-token/FungibleToken.solana-token-plan.json \
  Examples/Shared/FungibleToken.lean
```

The source stays target-neutral; the EVM target chooses an ERC-20-compatible
artifact and the Solana target chooses an SPL Token / Token-2022 plan. EVM
stdlib composition examples remain under `Examples/Evm/Contracts/`.

## Checklist

- [ ] One Lean module under `Examples/Shared/` (or your project root) with no
      per-target source copies.
- [ ] Three `proof-forge build --target ...` commands succeed for
      `evm`, `solana-sbpf-asm`, and `wasm-near`.
- [ ] `just portable-counter-multi-target` passes locally.
- [ ] `just testkit-budget-gate` passes (behavior + resource budgets).
- [ ] Artifact metadata records `sourceKind: contract-sdk` and the expected
      capabilities for your module.
- [ ] Token examples use `TokenSpec` or another high-level intent boundary
      instead of naming target protocols in shared source.

## Next steps

- Read [shared-scenario.md](../shared-scenario.md) for Counter/ValueVault
  capability tables and budget baseline notes.
- Scaffold a new project with `proof-forge init` and point `--root` at your
  workspace.
- Track product backlog items in
  [implementation-backlog.md](../implementation-backlog.md) Workstream 34.
