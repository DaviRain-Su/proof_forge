# Arbitrum Stylus Hybrid Backend Design

## Status

Approved architecture direction on 2026-07-12. This document defines the final
general-contract shape before implementation planning. It does not promote a new
registry target or claim Stylus runtime compatibility.

## Decision

ProofForge will support Arbitrum Stylus through one target plan and two renderers:

```text
Canonical Contract
  -> Stylus capability validation
  -> StylusPlan
       |-> Rust SDK renderer -> cargo stylus -> Wasm
       `-> direct Wasm renderer -> Stylus HostIO Wasm
                         |
                  differential evidence
```

The direct Wasm renderer is the final canonical backend. The Rust SDK renderer is
the bootstrap implementation, compatibility path, and differential oracle. Both
consume the same immutable `StylusPlan`; neither may re-derive contract semantics
from the source contract.

The planned target id is `wasm-arbitrum-stylus`. It belongs to the `wasmHost`
family because its deployed program is Wasm, but its ABI, storage, event, call,
and context semantics are EVM-compatible. It must not reuse the NEAR/Soroban
key-value lowering merely because those targets also emit Wasm.

## Meaning of General Contract Support

"Any contract" means any canonical contract that:

1. passes canonical validation;
2. passes the Stylus target capability gate;
3. uses only types and effects implemented by the selected renderer; and
4. has complete target-native ABI, storage, host-call, and resource plans.

It does not mean arbitrary Rust, arbitrary Solidity, every Stylus SDK feature,
or contracts outside ProofForge's canonical IR. Unsupported behavior must return
a named diagnostic before artifact emission.

## Why Stylus Is a Distinct Wasm Target

Stylus programs compile to `wasm32-unknown-unknown`, but execute with Ethereum
contract semantics:

- method dispatch and return/revert data use the Solidity ABI;
- persistent storage is the EVM state trie addressed by 256-bit slots;
- storage reads and writes operate on 32-byte words and writes are cached until
  explicitly flushed;
- logs use EVM topics plus data;
- calls follow EVM call and return-data behavior;
- sender, value, contract address, block, chain, gas, and ink are HostIO values.

Therefore the reusable seam is not `NearModulePlan -> different import names`.
The reusable seams are canonical semantics, selected EVM ABI/storage planning,
the Wasm AST/printer, artifact infrastructure, and generic refinement machinery.

Authoritative references:

- <https://github.com/OffchainLabs/stylus-sdk-rs>
- <https://github.com/OffchainLabs/cargo-stylus>
- <https://raw.githubusercontent.com/OffchainLabs/stylus-sdk-rs/main/stylus-sdk/src/hostio.rs>

## Architecture Boundaries

### Target Profile

The eventual registry profile will declare:

- id: `wasm-arbitrum-stylus`;
- family: `wasmHost`;
- artifact: deployable Wasm plus Solidity ABI and ProofForge metadata;
- deployment allocator: Wasm linear-memory allocator compatible with Stylus;
- required tools during bootstrap: Rust, the pinned Stylus SDK, and
  `cargo stylus`;
- maturity: `research` until the first runtime slice passes every promotion
  gate;
- input surface: not advertised as a primary `contract_source` compiler.

The initial docs/classification step does not add this profile to
`Target.knownIds`, `--list-targets`, or the build whitelist.

### StylusPlan

`StylusPlan` is the only renderer input. Its public contract is:

```lean
structure StylusPlan where
  targetId : String
  moduleName : String
  abi : StylusAbiPlan
  storage : StylusStoragePlan
  functions : Array StylusFunctionPlan
  events : Array StylusEventPlan
  calls : Array StylusCallPlan
  hostOps : Array StylusHostOpPlan
  resources : StylusResourcePlan
  artifacts : StylusArtifactPlan
```

The concrete types must be target-neutral where their semantics are genuinely
shared. For example, Solidity selectors and 256-bit storage-slot expressions
may reuse or extract neutral pieces from the EVM backend. Yul statements and
EVM bytecode instructions must not leak into `StylusPlan`.

### ABI Plan

`StylusAbiPlan` owns:

- Solidity canonical signatures and four-byte selectors;
- calldata bounds checks and dispatch;
- parameter and return layouts;
- dynamic head/tail offsets;
- success return bytes and typed revert bytes;
- constructor/initialization policy;
- generated Solidity interface and client schema.

Initial scalar types are `bool`, unsigned integers through `u256`, `address`,
and fixed bytes/hash. Structs, fixed arrays, dynamic bytes/string, dynamic
arrays, and tuples are added only with shared ABI conformance vectors.

### Storage Plan

`StylusStoragePlan` models EVM-compatible 256-bit slots, not host string keys.
It owns:

- declared base slot for every state value;
- Solidity-compatible packing offsets;
- mapping slot derivation using Keccak-256;
- fixed and dynamic array layout;
- bytes/string short and long representation when supported;
- 32-byte load, masked update, cached write, and final flush obligations;
- reentrancy boundaries that require cache clear/flush behavior.

The existing EVM storage planner should be split only where a neutral slot
layout contract removes real duplication. Stylus-specific HostIO calls remain
in the Stylus renderer.

### Host Operation Plan

Host operations are explicit planned effects, including:

- storage load/cache/flush;
- calldata size/copy and return-data write;
- sender, value, origin, contract address, chain id, block number/timestamp,
  base fee, gas left, and ink left;
- Keccak and other supported crypto;
- EVM-compatible log emission;
- call/static-call/delegate-call, return-data length/copy, and failure status;
- revert and out-of-resource behavior.

Each operation has a capability id, exact pointer/width convention, renderer
handler, offline/runtime handler, and diagnostic for missing support.

### Function Plan

`StylusFunctionPlan` consumes canonical CFG/SSA values and references ABI,
storage, event, call, and HostIO plan entries by stable ids. It does not contain
Rust syntax or raw WAT strings. The Rust renderer and direct Wasm renderer must
produce observably equivalent behavior from the same function plan.

## Renderer A: Rust SDK Bootstrap

The Rust renderer produces a deterministic crate containing:

- a pinned `stylus-sdk` dependency and toolchain metadata;
- `sol_storage!` declarations derived exclusively from `StylusStoragePlan`;
- `#[entrypoint]` and `#[public]` methods derived from `StylusAbiPlan`;
- Alloy-compatible types;
- explicit events, calls, errors, and initialization behavior;
- generated Rust tests and ABI snapshot;
- no handwritten business logic outside generated plan interpretation.

This renderer provides the earliest real-chain-compatible artifact and acts as
the semantic oracle. SDK macros are an output mechanism, not an architectural
dependency of canonical IR or `StylusPlan`.

## Renderer B: Direct Stylus Wasm

The direct renderer becomes canonical after parity gates pass. It produces a
Wasm AST using the official `vm_hooks` HostIO module and implements:

- Solidity calldata dispatch and ABI codecs;
- 256-bit slot arithmetic and 32-byte storage buffers;
- storage cache flush on every successful top-level return;
- ABI return/revert buffers;
- event topic/data packing;
- external call and return-data handling;
- memory allocation and bounds checks;
- deterministic trap-to-revert policy;
- Stylus-compatible imports, exports, and deployment metadata.

It may reuse the generic Wasm AST/printer and execution/refinement framework.
It must not route through `NearModulePlan`, NEAR Borsh, promise operations, or
the Soroban `_get`/`_put` spike ABI.

## Data Flow

```text
Contract.Source / portable intents
  -> canonical adapter and validation
  -> capability inventory
  -> StylusPlan.Core.buildFromCore
  -> strict Stylus plan validation
  -> renderer selection
  -> Rust crate or Wasm AST
  -> cargo stylus check / direct Wasm validation
  -> artifact bundle, ABI, client, deploy metadata
```

Renderer selection changes representation only. It cannot change capabilities,
storage slots, selectors, event topics, or observable results.

## Fail-Closed Rules

Compilation fails before emission when:

- a canonical type has no ABI or storage representation;
- a storage layout cannot prove non-overlap;
- an effect lacks a Stylus HostIO handler;
- a call mode or reentrancy requirement is unsupported;
- a renderer cannot implement a plan entry supported by the other renderer;
- SDK and direct renderer artifact metadata disagree;
- a claimed deployable artifact has not passed the appropriate validator.

Diagnostics name the target, contract, function, canonical operation,
capability, and missing renderer handler.

## Formal and Differential Evidence

The proof structure is:

```text
Canonical semantics
  -> StylusPlan refinement
  -> abstract Stylus HostIO execution
  -> renderer trace refinement
```

The abstract host state contains EVM-compatible storage words, calldata,
return/revert data, logs, call frames, context, gas/ink counters, and storage
cache state. Rust SDK and direct Wasm executions are compared by normalized
observable traces rather than byte-identical Wasm.

Required differential properties include equal selectors, storage slots,
return/revert bytes, event topics/data, external-call envelopes, state deltas,
and success/failure status.

## Delivery Slices

The architecture is general from the first commit. Delivery uses vertical
slices to grow the supported fragment:

1. **Foundation:** docs/classification, `StylusPlan` types, strict validator,
   and renderer completeness contract.
2. **Counter:** scalar `u256` storage, selector dispatch, set/increment/get,
   checked arithmetic, return/revert, cache flush, Rust SDK artifact.
3. **ValueVault:** address, sender, value, block context, authorization,
   payable behavior, and rejection traces.
4. **Token:** mappings, address keys, indexed events, `u256`, allowance, and
   external ABI compatibility.
5. **RemoteCall:** call/static-call, value/gas, return data, revert propagation,
   and reentrancy/cache rules.
6. **Aggregates:** structs, fixed arrays, dynamic arrays, bytes, and string.
7. **Direct renderer:** implement the same slices in Wasm and make differential
   parity required.
8. **Canonical cutover:** direct Wasm becomes default; Rust remains an explicit
   compatibility/oracle renderer.

Counter is the first acceptance fixture, not a Counter-specific architecture.

## Promotion Gates

No maturity increase occurs until the applicable slice has:

- strict canonical target-gate coverage;
- exact plan snapshot and renderer-completeness validation;
- Rust unit/property tests;
- `cargo stylus check` on the pinned toolchain;
- local Stylus VM or official test harness lifecycle execution;
- ABI compatibility tests from an EVM client;
- deterministic artifact and deployment metadata;
- normalized Rust/direct differential traces once direct Wasm exists;
- resource measurements for Wasm size, ink, and EVM gas accounting;
- CI coverage with optional live deployment isolated from the static baseline.

Mainnet or public-testnet deployment evidence is a separate promotion gate and
must not be inferred from `cargo stylus check` alone.

## Repository Placement

Planned modules:

```text
ProofForge/Backend/Stylus/
  Plan.lean
  Plan/Core.lean
  Validate.lean
  Semantics.lean
  RustSdk/AST.lean
  RustSdk/Render.lean
  DirectWasm/Imports.lean
  DirectWasm/Abi.lean
  DirectWasm/Storage.lean
  DirectWasm/Lower.lean
  Artifact.lean
  Refinement.lean
```

Target/profile metadata belongs under `ProofForge/Target`. Generated examples
belong under `build/`; checked-in source fixtures exist only where a golden or
external tool requires them.

## Explicit Non-Goals

- Forking or embedding `stylus-sdk-rs`.
- Treating Rust source generation as the final compiler architecture.
- Reusing NEAR Borsh or Soroban storage semantics.
- Claiming all Solidity or Stylus SDK features.
- Adding the target to the public registry before the docs/classification and
  strict-gate slice is approved.
- Advancing Stylus ahead of required primary-triad work; implementation slices
  must follow the repository's active portfolio policy.

## Acceptance of This Design

The design is complete when an implementation plan can assign every change to
one of three stable contracts: canonical-to-plan construction, renderer
implementation, or target-native evidence. No task may bypass `StylusPlan` by
lowering canonical IR directly into Rust syntax or WAT strings.
