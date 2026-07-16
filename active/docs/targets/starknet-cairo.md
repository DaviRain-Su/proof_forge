# Starknet Cairo Target

Status: **Research (docs-first candidate)**

Candidate target id: **`starknet-cairo`**

This note records the first ProofForge classification for Starknet smart
contracts through Cairo, Sierra, and CASM artifacts. It does not add a Lean
target profile yet.

Primary sources:

- [Starknet quickstart](https://docs.starknet.io/build/quickstart/overview)
- [Starknet by Example: Counter](https://docs.starknet.io/build/starknet-by-example/basic/counter)
- [Starknet by Example: storage](https://docs.starknet.io/build/starknet-by-example/basic/storage)
- [Starknet by Example: events](https://docs.starknet.io/build/starknet-by-example/basic/events)
- [Starknet by Example: Sierra IR](https://docs.starknet.io/build/starknet-by-example/advanced/sierra-ir)
- [Starknet accounts](https://docs.starknet.io/learn/protocol/accounts)
- [Starknet messaging](https://docs.starknet.io/learn/protocol/messaging)
- [Cairo storage](https://www.starknet.io/cairo-book/ch101-01-00-contract-storage.html)
- [Cairo events](https://www.starknet.io/cairo-book/ch101-03-contract-events.html)
- [Scarb docs](https://docs.swmansion.com/scarb/docs.html)
- [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/)

## Classification

Starknet should be treated as a Cairo/Sierra/CASM source-generation target. It
is not EVM, Wasm-host, Move, Solana sBPF, TVM, AVM, UTXO script, or a generic ZK
circuit sourcegen target.

```text
Starknet Cairo target
  -> generated or wrapped Cairo package
  -> Scarb build
  -> Sierra contract class and CASM artifact
  -> ABI, class hash, declare/deploy metadata
  -> Starknet Foundry or devnet validation
```

Starknet uses provable execution, but the product target is a chain contract
class and deployed contract instance. That is different from `psy-dpn`, where
the primary output is a circuit package.

## Lean 4 semantics availability — the FV-import path (2026-07)

Unlike most sourcegen targets, Cairo has an **existing Lean 4 formal semantics**, which
makes Starknet a **double-path candidate: sourcegen (deploy) AND FV-import (verify)**.

- **[`starkware-libs/formal-proofs`](https://github.com/starkware-libs/formal-proofs)** — a
  Lean project (the `main` folder is Lean 4; a `lean3` folder holds legacy CairoZero work).
  It contains a specification of the **Cairo CPU/VM execution semantics** (`Cpu.lean`,
  `Vm.lean`), a proof of the **AIR (STARK) encoding** correctness, and soundness/completeness
  proofs for a growing set of Cairo **libfuncs**. It is a proof-producing-compiler line of
  work (papers: CPP 2022 "A verified algebraic representation of Cairo program execution";
  JAR 2025 "A Proof-Producing Compiler for Blockchain Applications").

Because the Cairo VM semantics is an *executable/relational Lean 4 model*, ProofForge can
treat Cairo like the EVM lane treats `powdr-labs/evm-semantics`: **refine the portable IR
against Cairo's `Step` via the shared `CounterUniversal` induction.** See the **ZK-import
group** in
[the FV target-semantics plan](../superpowers/plans/2026-07-07-fv-target-semantics.md) and
the Lean-semantics axis in [execution-plan §6](../zh/execution-plan-2026-07.md).

**Boundary (non-goal, like `solc`):** the STARK proving/verification stays external — we
prove IR ⟷ Cairo's computed function; "the STARK is sound / the proof verifies" is
StarkWare's `formal-proofs` job, not ProofForge's.

**Prerequisite:** this FV path is **gated on first building the IR → Cairo codegen** (the
sourcegen Road below). No Lean semantics can be refined against an artifact that does not
exist yet.

## Why This Matters For ProofForge

ProofForge should model Starknet around Cairo contracts, contract classes, and
Starknet account/call semantics.

Target-specific concerns:

- Cairo source compiles through Sierra and CASM before declaration/deployment;
- contracts have class declarations and deployed instances;
- account abstraction is native to Starknet, not an optional wallet layer;
- contract addresses, class hashes, selectors, and ABI shape are target-native;
- storage paths, maps, components, and events follow Cairo/Starknet rules;
- cross-contract calls use Starknet dispatchers/syscalls;
- L1/L2 messaging is a separate capability from ordinary contract calls;
- testing should use Scarb plus Starknet Foundry or devnet before claiming
  output.

## Candidate Target Family

Candidate family:

```text
cairo-sourcegen
```

Candidate artifact shape:

```text
starknet-cairo-package
  - generated Cairo source or wrapped Scarb package
  - Sierra contract class artifact
  - CASM artifact
  - ABI and selector manifest
  - class-hash / declaration / deployment manifest
  - storage and event manifest
  - Starknet Foundry or devnet validation report
```

## Candidate Capabilities

Some existing capabilities have rough Starknet interpretations, but they need
review:

| Existing capability | Starknet interpretation |
|---|---|
| `storage.scalar` | Cairo contract storage field. |
| `storage.map` | Starknet storage map or component-owned storage. |
| `caller.sender` | Caller address from Starknet execution info. |
| `value.native` | Not generic call value; token movement is contract-mediated. |
| `events.emit` | Starknet event emission. |
| `crosscall.invoke` | Starknet contract call or dispatcher/syscall. |
| `env.block` | Block, sequencer, chain, and execution info. |
| `crypto.hash` | Pedersen, Poseidon, Keccak, ECDSA, and Cairo hash primitives. |
| `assertions` | Cairo assertions and panics. |

Candidate capabilities that may need explicit ids later:

| Candidate capability | Meaning |
|---|---|
| `vm.cairo` | Target emits Cairo source for Starknet. |
| `artifact.sierra` | Build emits Sierra contract class artifacts. |
| `artifact.casm` | Build emits CASM artifacts. |
| `class.declare` | Deployment flow includes class declaration. |
| `class.hash` | Artifact records class hash and class identity. |
| `abi.starknet` | Build emits Starknet ABI and selector metadata. |
| `storage.starknet` | Contract uses Starknet storage paths/maps/components. |
| `account.abstraction` | Target depends on Starknet account-contract semantics. |
| `syscall.starknet` | Contract uses Starknet syscalls. |
| `message.l1_l2` | Contract sends or consumes L1/L2 messages. |
| `fee.starknet` | Artifact records Starknet fee/resource constraints. |
| `test.snforge` | Validation uses Starknet Foundry or devnet. |

Do not add these ids to `ProofForge.Target.Capability` until a target profile
and lowering rules are reviewed.

## Implementation Road

### Road 1: Cairo Package Sourcegen

This is the most conservative first spike.

First spike:

- choose a simple Counter contract with storage, an increment external function,
  a read function, and one event;
- generate or wrap a Scarb package;
- compile to Sierra/CASM;
- run `snforge` or devnet-backed tests;
- record source, Sierra, CASM, ABI, class hash, tool versions, and validation
  result in artifact metadata.

### Road 2: Restricted Cairo IR

This road should wait until the source package route proves the artifact shape.

First spike:

- define a restricted Cairo-compatible IR;
- model storage fields, events, external/view functions, assertions, and
  dispatchers;
- keep account contracts, L1/L2 messaging, components, and upgrade patterns out
  of the first direct path.

## Non-Goals For The First Pass

- Do not add `starknet-cairo` to the code registry yet.
- Do not classify Starknet as EVM, Wasm-host, Move, Solana, TVM, AVM, UTXO, or
  `psy-dpn`-style ZK circuit sourcegen.
- Do not hide Sierra/CASM/class-hash metadata behind generic bytecode metadata.
- Do not model token movement as EVM call value.
- Do not claim direct Cairo IR lowering before the Scarb package route is
  validated.

## Research Exit Criteria

Starknet can leave Research only when we have:

- a reviewed target profile proposal;
- a decided first spike path, likely Cairo package sourcegen;
- a minimal Counter-like scenario with storage, event, and read path;
- an ABI/selector and class-hash policy;
- a Sierra/CASM artifact policy;
- a documented toolchain requirement set, including Scarb and Starknet Foundry
  or devnet;
- at least one reproducible local validation command;
- artifact metadata for source, Sierra, CASM, ABI, class hash, toolchain
  versions, and validation result.
