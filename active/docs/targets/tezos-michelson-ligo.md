# Tezos Michelson/LIGO Target

Status: **Research (docs-first candidate)**

Candidate target id: **`tezos-michelson-ligo`**

This note records the first ProofForge classification for Tezos smart
contracts, with LIGO as the preferred first source-generation path and
Michelson as the target execution/artifact boundary. It does not add a Lean
target profile yet.

Primary sources:

- [Tezos smart contracts](https://docs.tezos.com/smart-contracts/)
- [Creating smart contracts](https://docs.tezos.com/smart-contracts/creating)
- [Smart contract languages](https://docs.tezos.com/smart-contracts/languages)
- [Michelson](https://docs.tezos.com/smart-contracts/languages/michelson)
- [Contract storage](https://docs.tezos.com/smart-contracts/storage)
- [Complex data types](https://docs.tezos.com/smart-contracts/data-types/complex-data-types)
- [Contract views](https://docs.tezos.com/smart-contracts/views)
- [Contract events](https://docs.tezos.com/smart-contracts/events)
- [Delegation](https://docs.tezos.com/smart-contracts/delegation)
- [Sapling](https://docs.tezos.com/smart-contracts/sapling)
- [Testing Tezos contracts](https://docs.tezos.com/developing/testing)
- [LIGO introduction](https://ligolang.org/docs/intro/introduction/)

## Classification

Tezos should be treated as a Michelson source/artifact target, with LIGO as the
first practical source-generation language. It is not EVM, Wasm-host, Move,
Solana sBPF, TVM, AVM, UTXO script, or ZK circuit sourcegen.

```text
Tezos Michelson/LIGO target
  -> generated or wrapped LIGO source
  -> compiled Michelson contract
  -> storage and parameter schema
  -> operation-list and view/event metadata
  -> local sandbox or test runner validation
```

Michelson is a typed stack-based language and Tezos contracts return updated
storage plus a list of operations. That effect shape should be explicit in
ProofForge metadata.

## Why This Matters For ProofForge

ProofForge should not model Tezos as an EVM-like account contract even though it
has persistent storage and entrypoints.

Target-specific concerns:

- entrypoints receive parameters and return an operation list plus new storage;
- storage is a typed Michelson/Micheline value, not a slot map;
- `big_map` has target-specific persistence and indexing behavior;
- contract views and events are distinct public surfaces;
- tickets, Sapling, delegation, and tokens are native Tezos features that need
  explicit capability review before broad support;
- fees, gas, and storage burn differ from EVM gas semantics;
- testing should use LIGO/Octez or a Tezos sandbox path before claiming output.

## Candidate Target Family

Candidate family:

```text
michelson-sourcegen
```

Candidate artifact shape:

```text
tezos-michelson-ligo-package
  - generated LIGO source or wrapped source package
  - compiled Michelson contract
  - parameter / storage / entrypoint schema
  - view and event manifest
  - operation-list manifest
  - optional big_map / ticket / Sapling manifest
  - local test or sandbox validation report
```

## Candidate Capabilities

Some existing capabilities have rough Tezos interpretations, but they need
review:

| Existing capability | Tezos interpretation |
|---|---|
| `storage.scalar` | Field in typed contract storage. |
| `storage.map` | Michelson map or `big_map`, with different persistence semantics. |
| `caller.sender` | Sender/source fields from Tezos execution context. |
| `value.native` | Tez amount attached to a call. |
| `events.emit` | Tezos contract events. |
| `crosscall.invoke` | Emit operations that call contracts; not an EVM-style direct call. |
| `env.block` | Chain id, level, timestamp, and context fields where available. |
| `crypto.hash` | Michelson/LIGO hash and signature primitives. |

Candidate capabilities that may need explicit ids later:

| Candidate capability | Meaning |
|---|---|
| `vm.michelson` | Target emits or validates Michelson code. |
| `abi.entrypoint` | Build emits entrypoint/parameter schema metadata. |
| `storage.micheline` | Storage is encoded as typed Micheline data. |
| `storage.big_map` | Contract uses Tezos `big_map` storage. |
| `operation.list` | Entrypoint returns a list of Tezos operations. |
| `view.contract` | Contract exposes Tezos views. |
| `events.tezos` | Contract emits Tezos events. |
| `ticket.handle` | Contract creates, transfers, or consumes tickets. |
| `privacy.sapling` | Contract uses Sapling state or transactions. |
| `delegate.set` | Contract can change or clear delegation. |
| `gas.tezos` | Artifact records Tezos gas/storage-burn constraints. |
| `artifact.ligo` | Build emits LIGO and compiled Michelson metadata. |

Do not add these ids to `ProofForge.Target.Capability` until a target profile
and lowering rules are reviewed.

## Implementation Road

### Road 1: LIGO Sourcegen

This is the most conservative first spike.

First spike:

- choose a simple Counter contract with one increment entrypoint and one view;
- generate or wrap LIGO source;
- compile to Michelson;
- run a local test or sandbox flow that calls the entrypoint and checks storage;
- record source, Michelson, storage/parameter schema, operations, tool versions,
  and validation result in artifact metadata.

### Road 2: Restricted Michelson IR

This road should follow only after the LIGO package route proves the artifact
shape.

First spike:

- define a restricted stack/effect IR for Michelson;
- model parameter unpacking, storage update, operation list production, and
  views;
- keep tickets, Sapling, FA2 integration, and advanced contract origination out
  of the first direct path.

## Non-Goals For The First Pass

- Do not add `tezos-michelson-ligo` to the code registry yet.
- Do not classify Tezos as EVM, Wasm-host, Move, Solana, TVM, AVM, UTXO, or ZK.
- Do not hide operation-list semantics behind generic cross-contract calls.
- Do not treat `big_map`, tickets, or Sapling as ordinary maps/assets.
- Do not claim direct Michelson emission before the LIGO sourcegen route is
  validated.

## Research Exit Criteria

Tezos can leave Research only when we have:

- a reviewed target profile proposal;
- a decided first spike path, likely LIGO sourcegen;
- a minimal Counter-like scenario with storage, one entrypoint, and one view;
- a parameter/storage schema policy;
- an operation-list and gas/storage-burn policy;
- a documented toolchain requirement set;
- at least one reproducible local validation command;
- artifact metadata for source, Michelson, schema, operations, toolchain
  versions, and validation result.
