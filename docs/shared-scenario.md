# Shared Contract Scenarios: Counter and ValueVault

Status: **Draft spec (Phase 1–2)**

The Counter scenario is the first cross-target acceptance test. It exercises
portable scalar state without chain-specific account models in the Lean business
core. ValueVault is the next shared scenario: it exercises multiple scalar
state fields, arithmetic, event emission, and block-context reads while still
keeping the application source chain-neutral.

Related: [Portable IR](portable-ir.md),
[Capability registry](capability-registry.md),
[Decisions](decisions.md).

## Scenario Definition

### Counter

A contract maintains a single unsigned 64-bit counter.

| Operation | Behavior |
|---|---|
| `initialize` | Set counter to `0` |
| `increment` | Add `1` to counter |
| `get` | Return current counter value |

No native token transfer, no cross-contract calls, no events required for v0
(optional `events.emit` in v1).

### ValueVault

A contract tracks deposits, releases, accumulated fees, the last value seen,
the last checkpoint, and an operation counter.

| Operation | Behavior |
|---|---|
| `initialize(initial)` | Set the starting balance and checkpoint |
| `deposit(amount)` | Add `amount` to balance and emit `ValueDeposited` |
| `charge_fee(gross, fee_bps)` | Split gross value into fee/net, add net to balance, accumulate fees, and emit `ValueCharged` |
| `release(amount)` | Subtract `amount` from balance, add it to released value, and emit `ValueReleased` |
| `snapshot` | Read the target block/checkpoint context, update `last_checkpoint`, emit `ValueSnapshot`, and return balance |
| `get_balance` | Return balance |
| `get_net_value` | Return `balance - fees` |

No operation embeds EVM, Solana, or NEAR-specific APIs in the application
module. Target-specific selectors, Solana instruction tags, WAT exports,
metadata, manifests, IDL, and clients are adapter outputs.

## Required Capabilities

| Capability id | Used by |
|---|---|
| `storage.scalar` | Counter and ValueVault state operations |
| `events.emit` | ValueVault lifecycle events |
| `env.block` | ValueVault checkpoint reads |
| `caller.sender` | optional access control in v1 |

## Target-Specific Adaptation

Each target adapter maps the same logical scenario to native mechanics:

| Target | State representation | Smoke test |
|---|---|---|
| `evm` | contract storage slot | Foundry + `vm.etch` |
| `wasm-cosmwasm` | string-key `"count"` in host KV | `cosmwasm-check` + instantiate/execute/query |
| `wasm-cloudflare-workers` | Workers KV key `"count"` or Durable Object state | `wrangler dev` + `POST /increment` / `GET /count` |
| `solana-sbpf-asm` | account data field | `sbpf test` (Mollusk) + Surfpool/Rust live smoke |
| `move-aptos` | `Counter` resource under signer account | `aptos move test` |
| `psy-dpn` | Psy storage field, likely `Felt`/`U32` in v0 | `dargo compile` + in-memory smoke |

Target-specific account schemas and manifests are adapter concerns — not hidden
inside portable Lean logic. See [solana-sbpf-asm.md](targets/solana-sbpf-asm.md)
for instruction manifest format and the direct-assembly route (D-026).

## Phase 2 Acceptance Criteria

Phase 2 is complete when **both** parallel spikes pass independently:

### CosmWasm (`wasm-cosmwasm`)

- [ ] Counter Wasm exports required CosmWasm entrypoints.
- [ ] `cosmwasm-check` passes.
- [ ] instantiate → increment → query returns expected count.
- [ ] Artifact metadata records `target: wasm-cosmwasm` and capabilities used.

### Solana (`solana-sbpf-asm`)

- [ ] `--emit-sbpf-asm` produces valid `.s` accepted by `sbpf build`.
- [ ] `sbpf build` produces a loadable eBPF ELF (`.so`).
- [ ] initialize → increment → read counter in `sbpf test` (Mollusk) and
      Surfpool/Rust live smoke.
- [ ] Instruction manifest (`manifest.toml`) documents account layout.
- [ ] Capability checker rejects unsupported capabilities with target-id diagnostic.

### Joint (after both spikes)

- [x] Same `contract_source` module lowers to EVM + Solana + NEAR (see
      `Examples/Shared/Counter.lean` and `just portable-counter-multi-target`).
- [x] ValueVault lowers from one `contract_source` module to EVM + Solana +
      NEAR, including EVM metadata, Solana manifest/IDL/client metadata, and
      NEAR WAT/deploy metadata (see `Examples/Shared/ValueVault.lean` and
      `just portable-value-vault`).
- [ ] Document lists capabilities supported per target for this scenario.

## Multi-target authoring demo (CS-1.5)

The canonical portable Counter lives in
[`Examples/Shared/Counter.lean`](../Examples/Shared/Counter.lean)
(`contract_source`). `ProofForge.Contract.Examples.Counter` is a compatibility
alias for formal gates and older tests.

Build the **same file** to three primary targets:

```bash
just portable-counter-multi-target
```

Or manually:

```bash
lake env proof-forge build --target evm --root . \
  -o build/portable-counter/Counter.bin Examples/Shared/Counter.lean

lake env proof-forge build --target solana-sbpf-asm --root . \
  -o build/portable-counter/Counter.s Examples/Shared/Counter.lean

lake env proof-forge build --target wasm-near --root . \
  -o build/portable-counter/near Examples/Shared/Counter.lean
```

Chain choice is entirely build-time; the Lean module does not fork per target.

The canonical portable ValueVault follows the same pattern:

[`Examples/Shared/ValueVault.lean`](../Examples/Shared/ValueVault.lean)

`ProofForge.Contract.Examples.ValueVault` is likewise a compatibility alias for
the shared source; target adapters derive selectors, instruction tags, exports,
metadata, manifests, IDL, and clients below that layer.

Build and validate the same file across the three primary targets:

```bash
just portable-value-vault
```

The legacy `Examples/Learn/ValueVault.learn` fixture is retained for parser
equivalence coverage. It is not the recommended authoring path for new
contracts.

For a step-by-step walkthrough of this authoring model, see
[tutorials/portable-contract-three-targets.md](tutorials/portable-contract-three-targets.md).

## Resource budget baselines (CS-5.2)

Gate G0 requires behavior parity **and** per-step resource budgets for the
three primary targets. The `contract_source` Counter and ValueVault scenarios
pin baselines in:

- `testkit/scenarios/counter.toml`
- `testkit/scenarios/value-vault.toml`

Each scenario records the reference harness toolchains under
`[scenario.reference.toolchain]` (revm, Mollusk, wasmtime, sbpf). When a
dependency upgrade changes measured costs, update the scenario TOML in the same
PR that bumps the toolchain.

| Scenario | Metrics asserted | Typical tolerance |
|---|---|---|
| Counter | `evm_gas`, `solana_cu`, `near_gas` on every step | EVM ±10%, Solana/NEAR ±5% |
| ValueVault | same | same |

Run the budget gate locally:

```bash
just testkit-budget-gate
```

This executes the Counter and ValueVault scenarios through `just testkit`.
CI runs the full suite via `just testkit`, which includes the same budget
assertions. A deliberate regression in Solana CU or EVM gas fails the gate.

To inspect measured budgets while authoring new baselines, run:

```bash
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter --trace
```

Copy reported `solana_cu`, `evm_gas`, and `near_gas` values into the scenario
file when locking a new baseline. See [RFC 0010](rfcs/0010-resource-budgets-as-gates.md).

## ZK Target Experimental Criteria

`psy-dpn` is not part of Phase 2 exit criteria, but it now reuses the Counter
scenario through generated `.psy` source and Dargo validation.

- [x] Counter IR can be represented in a Psy-compatible scalar type.
- [x] Generated `.psy` package compiles with `dargo compile`.
- [x] DPN circuit JSON is emitted and recorded in artifact metadata.
- [x] Smoke path is documented and runnable through `dargo test`,
      `dargo compile`, `dargo execute`, `dargo generate-abi`, and artifact
      metadata validation.

## Example Locations

| Target | Path | Status |
|---|---|---|
| **All primary chains** | `Examples/Shared/Counter.lean`, `Examples/Shared/ValueVault.lean` (`contract_source`) | **In repo** — `just portable-counter-multi-target`, `just portable-value-vault` |
| EVM | `Examples/Evm/Contracts/Counter.lean` | **In repo** — compatibility wrapper around the shared Counter with EVM constructor-init metadata |
| CosmWasm | `Examples/CosmWasm/Counter.golden.wat` | **In repo (Spike)** — golden WAT via `proof-forge emit --target wasm-cosmwasm --fixture counter`; `just cosmwasm-counter-smoke` |
| Solana | `Examples/Solana/Counter.lean` + manifest | **In repo** — compatibility wrapper around the shared Counter plus sBPF golden/manifest fixtures |
| Aptos | `Examples/Aptos/Counter/golden/` | **In repo (Spike)** — golden Move module; `just aptos-counter-smoke` |
| Cloudflare Workers | `Examples/CloudflareWorkers/Counter/` + `emit --format ts` | **In repo (Spike)** — TS package + `scripts/ts/counter-ir-smoke.sh` |
| Psy DPN | `Examples/Psy/*.golden.psy`, `scripts/psy/*-smoke.sh` | **In repo** |

## Out of Scope for v0

- PDA derivation
- CPI / submessages
- Access control / ownership
- Overflow beyond U64 (targets may cap lower)
