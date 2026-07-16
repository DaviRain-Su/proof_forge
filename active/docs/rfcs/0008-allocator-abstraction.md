# RFC 0008: Chain-Decoupled Allocator Abstraction

Status: **Accepted and partially implemented (D-036/D-038).**
Date: 2026-07-02

## Problem

After the 2026-07 consolidation, the repository has three allocator surfaces
that are not one design:

1. **Portable IR layer (from the NEAR work):** `ProofForge/IR/Allocator.lean`
   defines `AllocatorConfig` (`Module.allocator`) with chain-deployment
   strategies (`bump`, `bumpReset`, `nearWeeModel`, `minimalMalloc`,
   `cosmWasmRegion`) and offline experiments (`hostBump`, jemalloc/mimalloc
   shapes). `TargetProfile` carries `deploymentAllocator?` /
   `offlineAllocators`. EmitWat consumes all of this; `Statement.release`
   lowers to the matching deallocator. See
   [wasm-allocators](../targets/wasm-allocators.md).
2. **Solana layer:** a separate `RuntimeAllocator` record in
   `Backend/Solana/Extension.lean`, driven by `solana.allocator.*` target
   metadata (kind `bump`, heap start `0x300000000`, heap size), surfaced in
   the IDL. The sBPF backend mostly avoids the heap: temporaries prefer
   registers, then `r10`-relative stack slots.
3. **EVM layer:** no explicit abstraction. Yul lowering uses word-addressed
   memory (`mload`/`mstore`) with compiler-chosen offsets; memory is
   transaction-scoped scratch and is never freed.

The question this RFC answers: can allocation be modeled once, decoupled
from the chains — and what must intentionally *not* be unified?

## Memory model survey (the three priority chains)

| Property | EVM | Solana (sBPF) | NEAR (Wasm) |
|---|---|---|---|
| Address space | per-call linear memory, byte-addressed, zero-initialized | fixed regions: stack frames via `r10`, heap `0x300000000` (32KB default, request up to 256KB), account data regions | wasm linear memory, growable via `memory.grow` |
| Allocation cost | gas: quadratic memory-expansion cost | compute units; heap size fixed at invocation | gas per instruction; `memory.grow` pages |
| Deallocation | none — memory dies with the call | none native — bump allocator by convention; custom allocators possible | meaningful — long-lived instances benefit from reuse (`wee_alloc`-style or free-list) |
| Lifetime | one call | one instruction invocation | contract instance persists across calls; memory persists per call only, but allocator state can matter within a call |
| Persistent state | storage slots (separate from memory) | account data (separate from heap) | storage host functions (separate from linear memory) |

Key observation: **all three fit one abstract contract** — a region-scoped
allocator with `alloc`, optional `release`, and an end-of-scope policy — but
they differ in which operations are *profitable*, not in which are
*expressible*. That is exactly the shape `AllocatorConfig` already models
for Wasm; the design below generalizes it instead of inventing a new one.

## Proposal

### One vocabulary, three bindings

Keep a single chain-neutral allocator model at the IR/Target layer and make
each backend *bind* it, never bypass it:

```text
AllocatorModel (chain-neutral, IR layer)
  strategy  : bump | bumpReset | freeList | hostImport       (semantic family)
  region    : { base, size?, growable }                       (address-space facts)
  release   : none | noop | reuse                             (what Statement.release means)

TargetProfile binding (per target, Registry layer)
  evm             -> { strategy = bump,      region = call-scratch,        release = noop* }
  solana-sbpf-asm -> { strategy = bump,      region = heap@0x300000000/32K, release = noop }
  wasm-near       -> { strategy = freeList | bump | bumpReset, region = linear-memory@heapBase, growable, release = reuse | noop }
```

```mermaid
flowchart TB
  IRA["IR: Statement.release +<br/>Module.allocator (AllocatorModel)"]
  OWN["Ownership checker<br/>(no use-after-release / double release)"]
  MODEL["AllocatorModel<br/>strategy × region × release"]
  CAPG["Capability gate<br/>runtime.allocator"]
  subgraph bindings ["Per-target bindings (TargetProfile)"]
    BE["evm: bump over call-scratch<br/>release = noop*"]
    BS["solana: bump over heap 0x300000000/32K<br/>release = noop"]
    BN["wasm-near: freeList/bump/bumpReset<br/>linear memory, release = reuse"]
  end
  OUT["Out of scope, stays chain-specific:<br/>EVM storage · Solana account data · NEAR storage"]

  IRA --> OWN --> MODEL
  MODEL --> CAPG
  CAPG --> BE & BS & BN
  MODEL -. "explicitly not covered" .-> OUT
```

Concretely, in code:

1. **Generalize `ProofForge/IR/Allocator.lean`** from its Wasm-flavored
   enum to the strategy/region/release triple above. The existing
   constructors map cleanly: `nearWeeModel`/`minimalMalloc` are `freeList`
   bindings with wasm-internal emission; `cosmWasmRegion` is a `hostImport`
   binding with an export ABI; the offline experiments keep
   `requiresHost = true`.
2. **Fold the Solana `RuntimeAllocator` into the same model.** The
   `solana.allocator.*` metadata keys stay as the Target-Extension override
   surface, but they populate the shared `AllocatorModel` instead of a
   parallel record, and the IDL renders from it. This resolves the open
   Workstream 24 decision ("unify or stay target-local"): **unify the
   model, keep the metadata keys as the Solana-specific configuration
   syntax.**
3. **Give EVM an explicit binding instead of implicit conventions.** No
   behavior change: the binding documents/centralizes what `EmitYul` and
   the EVM plan already do (bump over call-scratch memory, `release`
   rejected today). Later, `release` on EVM can become a checked no-op
   (`release = noop`) instead of a rejection once ownership checking (FV-3)
   guarantees it is safe — the IR then stays portable across all three
   chains without per-chain source edits.
4. **Capability alignment.** `runtime.allocator` in the
   [capability registry](../capability-registry.md) is the gate: a module
   whose `AllocatorConfig` demands `release = reuse` routes only to targets
   whose binding supports it; `release = noop` routes anywhere the
   ownership checker passes. Diagnostics cite the allocator id
   (`alloc.*`), as EmitWat already does.

### What stays chain-specific on purpose

- **Persistent state is not allocation.** EVM storage slots, Solana account
  data, and NEAR storage host calls stay behind the storage capabilities;
  the allocator model covers only transient in-call memory. Blurring these
  would repeat the "auto-map EVM slots to Solana accounts" mistake the
  review checklist warns against.
- **Solana account sizing** (rent, `create_account` space) is a deployment
  plan concern (Token SDK / CPI layer), not an allocator concern.
- **Register/stack promotion in the sBPF backend** is an optimization below
  the model: the binding only governs values that actually reach the heap.

### Invariants to state (feeds Workstream 25)

- Allocator soundness (FV-3 extension): under any binding with
  `release = noop`, evaluation traces of the IR semantics are identical to
  the `release = reuse` traces — i.e. release is semantically transparent
  and only affects the memory footprint. This single theorem justifies
  running one contract on EVM (noop), Solana (noop), and NEAR (reuse)
  without behavioral divergence.
- Region safety: `alloc` never returns offsets outside the declared region;
  for growable regions, growth is bounded by the target's page/heap limits
  (checked in testkit scenarios rather than proven, initially).

## Validation

- Unit: `Tests/Backend/Wasm/EmitWatAlloc.lean` already covers the Wasm strategies; add
  the equivalent Solana binding test (heap metadata → IDL → asm constants)
  and an EVM binding test (documented offsets match emitted Yul).
- Behavioral: one testkit scenario (RFC 0007) that allocates aggregates in
  a loop with `release`, executed on all three harnesses; NEAR asserts
  allocator counters (the offline host already reports
  allocations/reuses/deallocations), EVM/Solana assert identical observable
  results with release as noop.

## Milestones

1. **M1:** generalize `AllocatorConfig` to strategy/region/release; adapt
   EmitWat (no behavior change); record the unification decision in
   `decisions.md`.
2. **M2:** fold Solana `RuntimeAllocator` into the model; IDL and
   `solana.allocator.*` metadata read/write the shared type;
   `Tests/Backend/Solana/SolanaAllocator.lean` updated.
3. **M3:** explicit EVM binding + docs; decide `release` = rejection → noop
   transition criteria (blocked on FV-3).
4. **M4:** allocator testkit scenario across the three harnesses.

## Non-goals

- No custom allocator plug-ins for contract authors in v1; strategies are
  compiler-owned, selected per module/target.
- No unification of persistent-state models (see above).
- No CosmWasm activation; `cosmWasmRegion` stays a defined-but-dormant
  binding until the CosmWasm spike is scheduled.
