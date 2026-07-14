# Cross-Target Native Differential Validation Design

Status: **Accepted (2026-07-14)**

## Purpose

ProofForge promises one target-neutral business contract that is checked as
portable IR and then materialized through a selected target. Compiler tests
alone do not establish that the emitted contract behaves like an implementation
written with that target's native SDK. This design standardizes an independent
native-reference differential layer across the supported target families.

This is a validation architecture. It does not add target-specific constructors
to shared authoring or Canonical Core, and it does not create another compiler
route.

## Compiler Boundary Under Test

```text
single portable source
  -> Authored contract
  -> checked target-neutral Canonical Core
  -> target capability/extension match
  -> target-owned materializer and plan
  -> target artifact

independent native reference source
  -> native target toolchain
  -> native target artifact

shared scenario
  -> ProofForge runner ----\
                           +-> normalized observations -> fail-closed compare
  -> native runner --------/
```

Solana account, PDA, CPI, and instruction-data behavior belongs to Solana
extensions and `ModulePlan`; NEAR promises, JSON ABI, receipts, and host storage
belong to the NEAR target; EVM ABI, logs, calls, revert data, and storage layout
belong to the EVM target. The comparison layer observes those results but never
moves their semantics into portable IR.

## Existing Foundation

The repository already contains useful but separate comparison systems:

- `testkit/scenarios` executes normalized portable scenarios on EVM, Solana,
  and NEAR runners and records target resource metrics.
- `testkit/compare/near` contains Rust `near-sdk` references and a Sandbox
  dual-deploy runner with fail-closed observation coverage.
- `references/solana/pinocchio` contains independent Pinocchio programs,
  reference manifests, static equivalence gates, and live Surfpool comparisons.
- Stylus gates compare direct ProofForge Wasm with pinned Rust `stylus-sdk`
  references and local VM/Nitro-compatible runners.
- EVM has runtime, Yul, bytecode, Anvil, Foundry, and `revm` gates, but its
  native Solidity-reference layer is not yet normalized with the other targets.

The implementation must consolidate these assets rather than replace them.

## Reference Rule

A native reference is independent executable code written for the target's
normal developer toolchain:

| Target | Primary native reference |
|---|---|
| EVM | Solidity compiled with a pinned `solc`; Rust may be an additional semantic model, not the native oracle |
| Solana | Rust program using Pinocchio, native program crates, or Anchor when the scenario requires it |
| NEAR | Rust contract using pinned `near-sdk` or `near-contract-standards` |
| Arbitrum Stylus | Rust contract using pinned `stylus-sdk` |

References may be minimal independent rewrites of an upstream contract or a
pinned upstream example. Every reference manifest must record its upstream URL
or local origin, commit/tag or package version, license, toolchain, covered
scenario, and intentional semantic differences. ProofForge planner/lowering
code must never be imported into the reference implementation.

## Scenario Classes

### Portable scenarios

Portable scenarios express behavior shared across target families, such as
Counter, ValueVault, ownership, pausing, maps, events, and portable remote-call
intent. One `Examples/Product` source is compiled for every advertised target.
Target runners translate the same logical actors and inputs into native calls.

### Target-extension scenarios

Target-extension scenarios validate chain-native behavior without pretending
that the behavior is portable:

- Solana: account constraints, PDA seeds/bumps, CPI account order, signer and
  writable flags, instruction-data layout, return data, and compute units.
- NEAR: JSON argument/return encoding, storage keys, attached deposit, promise
  actions/results, receipt behavior, logs, and gas.
- EVM: selectors, calldata/returndata, revert categories/data, topics/logs,
  call/create behavior, storage layout, and gas.
- Stylus: Solidity ABI compatibility, HostIO storage/calls/logs, Wasm validity,
  ink/gas observations, and Rust SDK interoperability.

These scenarios are owned by the target test catalog. They may start from a
target Source facade, but the facade must lower to typed target extensions
before checked Canonical Core.

## Normalized Observation Contract

Semantic equivalence is based on observations, never byte-for-byte artifact
identity. A scenario result must be able to report:

1. Call status and normalized error category.
2. Typed return values or canonical return bytes.
3. Named state snapshots and balances before and after each step.
4. Ordered events/logs with normalized names and typed fields.
5. External actions: EVM calls/creates, Solana CPIs, or NEAR promise/receipt
   actions, represented by target-owned observation payloads.
6. ABI, account, or interface metadata asserted by the scenario.
7. Resource observations such as EVM gas, Solana compute units, NEAR gas, Wasm
   fuel, and artifact size.

The comparator must distinguish:

- `observedMatch`: every collected comparable value matched.
- `observationCoverage`: covered and missing required dimensions.
- `semanticMatch`: true only when `observedMatch` is true and required coverage
  is complete.

Missing data, unknown schema versions, runner skips, and unclassified errors
fail closed for semantic promotion. Resource results use target-local budgets;
gas, compute units, and NEAR gas are not combined into a cross-chain score.

## Validation Layers

| Layer | Purpose | Typical gate |
|---|---|---|
| L0 migration parity | Temporary old/new compiler-route comparison during Legacy removal | focused canonical/plan/artifact equivalence |
| L1 structural conformance | ABI, account layout, manifest, target-plan, and artifact invariants | deterministic static gate |
| L2 VM behavior | Independent artifacts execute the same scenario in deterministic local VMs | `revm`, Mollusk, `near-vm-runner`, Stylus VM runner |
| L3 local-chain behavior | Deploy both artifacts to the same local node/sandbox and compare observations | Anvil, Surfpool, NEAR Sandbox, local Nitro harness |
| L4 resource regression | Pin target-local size and execution bands after behavior matches | budget gate with explicit tolerance |

L0 exists only to protect a migration slice and is deleted with the retired
route. Native references remain after Legacy removal and are the durable oracle.

## Scheduling Impact

The comparison program does not block A-CUT1e-c2. That task already has typed
Solana plan coverage and Pinocchio structural/live references; its acceptance
must additionally prove that public Solana macros reach the same target-owned
plan without `Source.Solana.Legacy`.

The program becomes a required exit criterion at these later boundaries:

| Architecture task | Required differential evidence |
|---|---|
| A-CUT2 | Counter portable scenario on all primary targets from the direct Authored/Canonical route |
| A-CUT3 | Stateful ValueVault plus representative catalog families from the single Product source |
| IR-B5 | Solana account/PDA/CPI target-extension scenarios against independent Rust references |
| NEAR-R4 | Existing NEAR native comparisons replayed from the canonical-only public artifact |
| IR-B8 / A-CUT5 | No production Legacy route; comparison matrix and coverage validator pass fail closed |

This sequencing prevents a test-framework rewrite from delaying the immediate
authoring cutover while ensuring later route deletion cannot rely on static
compiler assertions alone.

## Non-Goals

- Equal bytecode, storage encoding, or instruction layout across chains.
- Treating Rust as a universal native language for every target.
- One numeric performance ranking across different fee/resource models.
- Using the old compiler route as a permanent oracle.
- Adding chain-native concepts to portable IR for test convenience.
- Claiming full protocol compliance from a minimal comparison scenario.

## Acceptance

The design is realized when a versioned shared reference/scenario schema,
normalized observation contract, and coverage validator drive at least Counter
and ValueVault across the primary triad; target-extension suites cover Solana,
NEAR, and EVM native behavior; every reference has provenance; and CI separates
fast deterministic gates from optional heavyweight local-chain execution.
