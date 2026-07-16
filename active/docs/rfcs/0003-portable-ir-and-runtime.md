# RFC 0003: Portable contract IR, capability lowering, and runtime profiles

Status: Draft

Date: 2026-06-30

## Summary

RFC 0001 names the portable contract IR as the layer between Lean source and
target backends. RFC 0002 lists the backends but leaves the IR, the capability
mechanism, and the runtime-selection question unspecified. This RFC closes that
gap. It defines three things that the rest of the platform depends on:

1. A chain-neutral Contract Intent API whose source-level operations are
   resolved by the selected target at build time.
2. A capability namespace, capability plan, and per-target lowering table that
   target adapters consult to lower each routed capability to a concrete host
   primitive.
3. A runtime profile per target that states how the Lean language runtime is
   reconciled with the chain host runtime, and that the compiler checks
   statically before lowering.

The core claim this RFC makes explicit: target selection is a build-time,
table-driven, statically checked decision. There is no runtime dispatch over
chains. A contract either resolves its portable intents and lowers cleanly to a
target under that target's capability and runtime constraints, or it is
rejected with a precise diagnostic before any artifact is produced.

This RFC does not define the full IR surface. The IR unit structure (Module,
Entrypoint, State, Effect) is defined in [`portable-ir.md`](../portable-ir.md);
the canonical capability ids and per-target support matrix are in
[`capability-registry.md`](../capability-registry.md). This RFC defines only
the load-bearing parts those specs do not cover: the capability lowering rule
format, the runtime profile, and the static checks. IR type and statement
detail beyond the Effect/capability representation is deferred to
`portable-ir.md` and to implementation once Solana constraints are known.

## Motivation

The current EVM backend proves that Lean can lower to a chain. It does not
prove that the design generalizes. Three things block generalization today:

- The EVM path bypasses any portable layer: `Lean → LCNF → EmitYul → Yul`. The
  host calls (`lean_evm_*`) are recognized by name inside EmitYul and fused
  into Yul opcodes. There is no IR where a capability call is represented
  abstractly, so there is nothing for a second backend to share.
- Capabilities are mentioned in RFC 0001 and RFC 0002 as a concept, but there
  is no mechanism that lets the compiler know which capabilities a contract
  uses, or that rejects a target which cannot satisfy them.
- The relationship between the Lean language runtime (`lean_rt`) and each
  chain's host runtime is never stated. In practice the EVM backend degenerates
  the Lean runtime into no-ops and treats EVM opcodes as the runtime. The NEAR
  reference in the Lean fork keeps the full Lean runtime and adds a host
  bridge. Move backends cannot carry the Lean runtime at all. Without an
  explicit model, every new backend re-derives these decisions ad hoc.

This RFC fixes the shared layer so that user contracts can start from one
chain-neutral SDK surface. Backends differ in intent routing, lowering tables,
and runtime profiles, not in their mental models.

## Non-goals

- This RFC does not specify the IR unit structure (Module/Entrypoint/State/
  Effect) — that is [`portable-ir.md`](../portable-ir.md). It specifies only
  the capability lowering rule format and the runtime profile that backends
  and the capability checker depend on.
- It does not define the canonical capability id set — that is
  [`capability-registry.md`](../capability-registry.md). It consumes those ids.
- It does not make capability calls the primary user-facing SDK. Capability ids
  are the lower-level protocol produced by target routing and used by target
  adapters and Target Extension SDKs.
- It does not pick the Solana runtime strategy. It defines the three strategies
  and the constraint that the Solana spike result feeds back into the IR subset.
- It does not define the cloud platform or artifact registry schema beyond what
  the capability and runtime fields require (RFC 0002 already sketches metadata).
- It does not require migrating the existing EVM path through the IR
  immediately. EVM may run dual-path (direct LCNF and via IR) until golden
  snapshots prove equivalence.

## Relationship to other specs

ProofForge now splits the shared-layer design across several documents. This
RFC is the runtime-and-lowering authority; the others own their own surfaces.

| Surface | Authority | This RFC's role |
|---|---|---|
| Contract Intent API and IR unit structure | [`portable-ir.md`](../portable-ir.md) | Consumes it; adds target intent resolution and capability lowering rules on top of `Effect` |
| Capability ids + support matrix | [`capability-registry.md`](../capability-registry.md) | Consumes ids; defines the lowering rule format and how the backend uses them |
| Cross-target scenario | [`shared-scenario.md`](../shared-scenario.md) | Provides the test case the static checks must pass/reject |
| Settled decisions | [`decisions.md`](../decisions.md) | Inherits selected decisions; see below |

Decisions inherited from [`decisions.md`](../decisions.md) that affect this
RFC:

- **D-001**: RFC 0001/0002 are Accepted as engineering direction. This RFC is
  the missing piece they depend on.
- **D-002**: Phase 1 (target registry + portable IR + artifact metadata) must
  complete before non-EVM spikes. The capability checker and runtime profile
  defined here are Phase 1 deliverables.
- **D-003**: CosmWasm and Solana spikes run **in parallel** in Phase 2. This
  supersedes the earlier sequential roadmap (Solana-only Phase 2, or
  CosmWasm-before-Solana). Both validate different backend families; neither
  is gated on the other. The Solana runtime decision (B vs B') still must
  land before Solana can exit spike, but it no longer blocks CosmWasm.
- **D-004/D-005/D-026**: `solana-sbpf-asm` is the canonical Solana direct
  assembly route. `solana-sbpf-linker` and the Zig fork stay historical
  fallback/reference tracks.
- **D-007/D-008**: Move POC is Aptos-first source generation (strategy C).
  This RFC's strategy C and the Move runtime profile follow that.
- **D-027**: Solana CPI/PDA remain in the Solana-specific layer and are gated
  by capabilities rather than added to the portable IR.
- **D-028**: User contracts target a chain-neutral Contract Intent API; the
  selected target resolves intents into capability plans.


## Two runtimes, three reconciliation strategies

ProofForge must reconcile two distinct runtime layers:

- Lean language runtime (`lean_rt`): Lean's object model — boxed scalars
  `(n << 1) | 1`, constructor headers, reference counting, closures, thunks,
  bignum. Language-level machinery, chain-independent.
- Chain host runtime: the chain's own execution ABI — EVM opcodes, Solana
  syscalls, Wasm host imports, the Move VM.

These cannot coexist as two equal runtimes on a target. Each target picks one
of three reconciliation strategies. The strategy is the most important
per-target decision because it determines what the IR is allowed to contain.

### Strategy A: degenerate runtime (host IS the runtime)

The Lean language runtime is reduced to no-ops. Reference counting becomes
`lean_inc/dec/del → no-op`; `isShared` returns 1 always; the heap is
per-call scratch memory. Host calls are not routed through a bridge binary —
they are inlined into the emitted code at lowering time.

Used by: EVM.

Consequence for IR: the IR may use any pure Lean construct that lowers without
a heap (arithmetic, structs as memory regions, closures lowered to a generated
`switch`). It may not rely on unbounded allocation, GC, or persistent heap
objects across calls.

### Strategy B: full Lean runtime plus host bridge

The full Lean language runtime is compiled onto the target and linked against
exactly one host bridge module that translates Lean objects into the chain's
host ABI calls.

Used by: NEAR, CosmWasm, and (if it links) Solana.

Consequence for IR: the IR may use the full Lean subset that `lean_rt`
supports, including closures and heap objects, subject to the target's size and
budget limits.

### Strategy C: no Lean runtime (source generation)

No Lean runtime is shipped. The backend generates source in the target
language, and the target's own VM is the runtime. Lean is used only for types
and proofs, which are checked and erased before code generation.

Used by: Sui Move, Aptos Move.

Consequence for IR: the IR must be a restricted, first-order, Move-compatible
subset. No closures, no Lean heap objects, no arbitrary recursion. Resource,
object, and ability semantics must be represented explicitly in the IR.

### Variant B': restricted Lean runtime

A sub-strategy of B used when the full Lean runtime does not fit a target
(Solana sBPF is the expected case). A subset of `lean_rt` is compiled — boxed
scalars and explicit constructors, but closures, bignum, and the IR interpreter
may be dropped. The host bridge is unchanged.

Consequence for IR: if a target uses B', the IR must not use the dropped
features, and the static checker must reject them before lowering. The Solana
spike (Workstream 7) decides whether Solana uses B, B', or falls back toward an
A-like path.

## Capability model

### Intent resolution and capability plans

Portable IR does not contain target opcodes. The default user-facing SDK also
does not expose capability calls directly. Source code expresses contract
intents such as state declarations, entrypoints, events, caller reads, value
access, assertions, and proof obligations. The selected target adapter resolves
those intents into a capability plan before lowering.

Capability calls are the lower-level representation after routing. They record
the semantic operation that must be supported by the selected target and
provide a stable diagnostic/artifact surface. Target Extension SDKs may expose
target-specific operations, but those operations still route through capability
calls and target metadata.

Conceptual representation (Lean sketch; the concrete IR data structure is an
implementation detail, but it must carry this information):

```lean
/-- A capability identifier in a hierarchical namespace, e.g. `storage.scalar`. -/
structure CapId where
  parts : List String

/-- A source-level portable operation before target routing. -/
structure ContractIntent where
  kind   : IntentKind
  args   : Array IRExpr
  source : SourceSpan

/-- A capability call recorded after target routing. The `capability` field lets
    the backend lower it from the table rather than by name matching. -/
structure CapabilityCall where
  capability : CapId
  operation  : Name        -- e.g. ``Storage.load``, ``Solana.Cpi.invokeSigned``
  args       : Array IRExpr

/-- Target-selected plan consumed by the checker and backend. -/
structure CapabilityPlan where
  calls          : Array CapabilityCall
  targetMetadata : TargetMetadata
```

A target adapter provides the routing step:

```lean
structure TargetAdapter where
  targetId      : TargetId
  profile       : TargetProfile
  resolveIntent : ContractSpec -> Except Diagnostic CapabilityPlan
  lower         : CapabilityPlan -> IR.Module -> Except Diagnostic TargetAst
```

Lean attributes such as `@[capability "..."]` may still be used as an
implementation hook for opaque target-extension functions. They are not the
default product API. Backends never pattern-match `lean_evm_*` names again;
they read the resolved capability plan.

### Capability namespace

The canonical set of capability ids and their per-target support matrix live
in [`capability-registry.md`](../capability-registry.md), which is the single
source of truth for ids. RFC 0003 does not redefine them; it consumes them.

For reference, the registry's first version includes: `storage.scalar`,
`storage.map`, `storage.pda`, `caller.sender`, `value.native`, `events.emit`,
`crosscall.invoke`, `crosscall.cpi`, `env.block`, `crypto.hash`, and
`account.explicit`. Each id is a semantic capability (`<domain>.<operation>`),
not a target opcode. New ids are added to the registry by spec amendment, not
per-backend; backends propose ids, the registry owns them.

This RFC only adds two things on top of the registry:

1. The **lowering rule format** (next subsection) — how a backend emits a host
   primitive for a registered id. The registry says *which* ids a target
   supports; this RFC says *how* a supported id is lowered to host code.
2. The **runtime profile** (later section) — which constrains *what IR
   features* may appear under a target, independent of capability ids.

### Capability lowering table

Each target provides a table mapping each capability id it supports to a
lowering rule. The rule says how the backend emits the host primitive for that
capability, and whether the lowering requires extra target metadata (e.g. a
Solana account manifest, a Move ability annotation).

```lean
/-- How a target lowers one capability. -/
structure CapabilityLowering where
  capability : CapId
  -- A tag telling the backend which emitter to use for this capability.
  lowering   : LoweringKind
  -- Whether the lowering needs per-call target metadata from a manifest.
  needsMetadata : Bool

inductive LoweringKind where
  | evmOpcode   (op : String)              -- e.g. sload, sstore, caller
  | hostImport  (bridgeFn : Name)          -- e.g. `Lean.Near.storage_read`
  | syscall     (bridgeFn : Name)          -- e.g. `Lean.Solana.read_data`
  | generated   (targetApi : Name)         -- e.g. Move `sui::event::emit`
```

Examples:

| target | capability | lowering |
|---|---|---|
| evm | `storage.scalar` | `evmOpcode "sload"` / `"sstore"` |
| evm | `caller.sender` | `evmOpcode "caller"` |
| wasm-near | `storage.scalar` | `hostImport ``Lean.Near.storage_read`` |
| wasm-cosmwasm | `storage.scalar` | `hostImport ``Lean.CosmWasm.storage_read`` |
| solana-sbpf-asm | `storage.scalar` | `syscall ``Lean.Solana.read_data`` (needs account manifest) |
| solana-sbpf-asm | `storage.pda` | `syscall PDA derivation (needs account manifest) |
| solana-sbpf-asm | `crosscall.cpi` | `syscall CPI with account metas |
| move-sui | `events.emit` | `generated ``sui::event::emit`` |
| move-aptos | `storage.scalar` | `generated resource access (needs abilities + acquires)`` |

The set of capabilities a target supports is exactly the set of rows in its
table. A capability with no row for a target is unsupported for that target.

### Static capability checking

Before lowering, the compiler asks the selected target to resolve the contract
intents into a capability plan. It then computes the set of capability ids used
by that plan (plus any explicit target-extension calls in the IR) and checks it
against the target's supported set. This is a set operation; it either succeeds
or produces precise diagnostics.

```
usedCapabilities(contract) ⊆ supportedCapabilities(target)
```

On failure, the compiler emits one diagnostic per unsupported capability:

```
error: target `solana-sbpf-asm` does not support capability `value.native`
  hint: Solana has no EVM-style msg.value; model native assets as explicit
        lamport/Coin accounts via the `account.explicit` capability
  used at: Examples/Counter.lean:42
```

This check is what makes "reject unsupported targets instead of silently
changing semantics" a real compiler behavior rather than a documentation
promise. It replaces the current name-matching inside EmitYul.

### Feature usage tracking, not just capability tracking

The same static pass also tracks IR feature usage against the runtime profile
(see below): closure count, recursion depth, heap-object allocation, bignum
usage. A contract that uses closures targeting a B' runtime is rejected the
same way:

```
error: target `solana-sbpf-asm` runtime profile `restrictedLean` does not support closures
  used at: Examples/Counter.lean:55 (`fun x => ...`)
  hint: rewrite as a first-order function or inline the body
```

## Runtime profile

Each target declares a runtime profile. The profile states the reconciliation
strategy and the feature budget the Lean runtime has on that target. The
compiler checks the contract's feature usage against this budget statically.

```lean
inductive RuntimeMode where
  | degenerate       -- Strategy A: Lean runtime is no-ops; host is the runtime
  | fullLean         -- Strategy B: full lean_rt + host bridge
  | restrictedLean   -- Strategy B': subset of lean_rt
  | none             -- Strategy C: source generation; no lean_rt

inductive HostBridgeKind where
  | inlineOpcodes    -- EVM: no bridge binary; opcodes emitted inline
  | module (id : String)   -- "near" | "cosmwasm" | "solana"
  | none             -- source generation targets

inductive ChainAllocator where
  | bump             -- linear frontier in the final chain artifact
  | bumpReset        -- bump + reset at each entrypoint boundary
  | nearWeeModel     -- NEAR deployment profile; Rust SDK uses wee_alloc
  | minimalMalloc    -- direct-WAT internal free-list allocator
  | cosmWasmRegion   -- CosmWasm allocate/deallocate region ABI

inductive ExperimentAllocator where
  | hostBump
  | hostJemallocShape
  | hostMimallocShape

structure RuntimeProfile where
  mode              : RuntimeMode
  hostBridge        : HostBridgeKind
  deploymentAllocator? : Option ChainAllocator
  offlineAllocators : Array ExperimentAllocator
  supportsClosures  : Bool
  supportsBignum    : Bool
  supportsHeapObjects : Bool
  maxStackBytes     : Nat          -- EVM effectively unbounded; Solana 4096
  maxArtifactBytes  : Nat          -- target upload limit, if any
```

Initial profiles:

| target | mode | hostBridge | supportsClosures | supportsBignum | supportsHeapObjects |
|---|---|---|---|---|---|
| evm | degenerate | inlineOpcodes | false (lowered to switch) | false (U256-capped) | false (per-call scratch) |
| wasm-near | fullLean | module "near" | true | true | true |
| wasm-cosmwasm | fullLean | module "cosmwasm" | true | true | true |
| solana-sbpf-asm | restrictedLean (tentative) | module "solana" | TBD by spike | TBD | TBD |
| move-sui | none | none | false | false (fixed-width) | false (resources) |
| move-aptos | none | none | false | false (fixed-width) | false (resources) |

The Solana row is deliberately tentative. Its `restrictedLean` mode and its
feature booleans are not assumptions — they are outputs of Workstream 7. Until
that spike lands, the Solana profile records the open questions, not answers.

## Build flow

The target-oriented build, end to end:

1. Parse `--target <id>`; resolve the target profile and its runtime profile.
2. Compile Lean source to LCNF and build the chain-neutral `ContractSpec`,
   recording feature usage (closures, recursion, allocations).
3. Ask the selected target adapter to resolve contract intents into a
   `CapabilityPlan`, then build the portable IR: entrypoints, types, state
   transitions, and target-resolved capability calls tagged with their `CapId`.
   Proofs are checked in step 2 and erased; the IR carries proof-status
   metadata, not proof terms.
4. **Static check (set arithmetic, build-time, non-negotiable):**
   - `usedCapabilities ⊆ supportedCapabilities(target)`, else reject.
   - `usedFeatures ⊆ runtimeProfile.features`, else reject.
5. Lower: for each routed capability call, look up the target's lowering rule
   and emit the host primitive (opcode / bridge call / syscall / generated API).
6. Construct the runtime per `mode`:
   - degenerate → emit only the no-op RC stubs and the inlined host opcodes.
   - fullLean / restrictedLean → compile the corresponding `lean_rt` subset and
     link exactly one `host/<bridge>` module.
   - none → skip runtime construction; emit target source.
7. Package per the target's artifact kind and run its smoke test gate.

Steps 4 and 6 are where "the compiled code knows which runtime to call" is
decided. It is decided at build time by table lookup and link selection, never
at run time.

## Host bridge selection is link-time and exclusive

For strategy B and B' targets, exactly one host bridge module is linked. There
is no runtime choice and no symbol collision: each bridge implements a distinct
set of externs (`lean_near_*`, `lean_cosmwasm_*`, `lean_solana_*`). The build
selects the bridge from the runtime profile's `hostBridge` field.

The cleanup this requires versus today: the Lean fork hardcodes `lean_near_*`
in EmitZig's generic runtime extern list, so every Wasm build force-links the
NEAR bridge. Workstream 4 makes bridge selection target-driven: EmitZig emits
externs for the bridge named by the runtime profile, and the generic Wasm
runtime force-links nothing chain-specific. This is the engineering change that
turns "NEAR works" into "the Wasm family works."

## Solana constraints feed back into the IR

The Solana sBPF spike (Workstream 6/7) is not downstream of the IR; it
constrains the IR. The spike answers whether the full `lean_rt` links under
`bpfel-freestanding` within the 4KB stack and loader section constraints. The
outcomes, and what each forces on the IR:

- **Full runtime links (strategy B holds):** IR may keep closures and heap
  objects for Solana. Solana profile booleans flip to true.
- **Only a subset links (strategy B'):** the IR must support a first-order,
  no-closure, bounded-recursion subset that lowers under Solana. The static
  checker rejects Solana builds that exceed it. This subset likely overlaps the
  Move-compatible subset, which is strategically useful.
- **No viable runtime subset (fall back toward A):** the IR must lower directly
  to Zig without `lean_rt` on Solana, the way EmitYul lowers directly to Yul
  without `lean_rt` on EVM. Solana becomes a degenerate-runtime target whose
  "host is the runtime" via syscalls.

Because the outcome is unknown, the IR design must keep the B'-compatible
subset clean from the start: first-order functions, explicit entrypoints,
boxed scalars, explicit constructors. Features that would only survive under
strategy B (unbounded closures, arbitrary recursion, full bignum) must be
opt-in per target, not assumed.

## Relationship to the existing EVM backend

The EVM backend stays as the working baseline. It is not rewritten through the
IR on day one. The migration is staged:

1. Add the target profile, runtime profile, and capability lowering table for
   `evm`, with the table derived from what EmitYul already does.
2. Add capability and feature static checking as a pass that runs before
   EmitYul. Initially it only validates EVM contracts against the EVM profile.
3. Introduce the portable IR as an alternate path that lowers to the same Yul.
   Keep the direct LCNF→EmitYul path until golden Yul snapshots prove the two
   paths emit identical output for every example.
4. Once equivalence holds, the direct path may be removed.

The existing `@[extern "lean_evm_*"]` names become the lowering-rule targets
for the `evmOpcode` rows; EmitYul's internal name matching is replaced by table
lookup. No EVM behavior changes unless the snapshot diff says so.

## Acceptance criteria

This RFC is implemented when:

- A target profile exists for `evm` describing family, artifact kind,
  capability set, and runtime profile, without changing current EVM output.
- A contract that uses a capability absent from a target's table is rejected
  with a diagnostic naming the target id, capability id, and source location.
- A contract that uses a feature disallowed by a target's runtime profile is
  rejected with a diagnostic naming the feature and source location.
- The EVM build produces identical Yul/bytecode before and after the capability
  and feature checks are added (golden snapshot equivalence).
- At least one non-EVM target's runtime profile is recorded in the registry,
  even if its backend is not yet implemented, so the registry is the single
  source of truth for capability and runtime constraints.

## Open questions

- Should capability ids carry a payload describing the *kind* of state they
  touch (e.g. `storage.scalar` vs `storage.map` vs `account.explicit`), or is
  the current flat namespace in `capability-registry.md` enough for precise
  diagnostics?
- How are Contract Intent API operations recognized at the source level, and
  when do target-extension functions need an explicit `@[capability "..."]`
  implementation hook instead of target intent routing?
- Should the static feature check be conservative (reject anything that might
  use a closure) or precise (only reject confirmed closures)? Conservative is
  safer for a first cut.
- For Move source generation, where do resource abilities and `acquires`
  clauses live — in the IR, in the target manifest, or derived from capability
  usage? RFC 0002's Move notes lean toward IR; this RFC defers it.
- Should the portable IR be a Lean data structure consumed by Lean-implemented
  backends, or a serialized format consumable by external (Zig/Rust) backends?
  The answer affects whether backends can be non-Lean per RFC 0001's open
  question.

## Research references

- EVM baseline and the degenerate-runtime approach: `ProofForge.Evm`,
  `ProofForge.Compiler.LCNF.EmitYul`. The `lean_evm_*` recognition in EmitYul
  is the precursor of the capability lowering table.
- NEAR full-runtime-plus-bridge reference: local Lean fork `Lean.Near`,
  `tools/zigc-near`, `src/runtime/zig/host/near`.
- Solana runtime decision (strategy B vs B' vs fallback to A): Workstream 6/7
  in `docs/implementation-backlog.md`, `docs/targets/solana-sbf.md`.
- Move source-generation restrictions (strategy C IR subset):
  `docs/targets/move-family.md`.
- Capability matrix and target profiles: RFC 0002.
- IR unit structure (Module/Entrypoint/State/Effect): `docs/portable-ir.md`.
- Canonical capability ids and support matrix: `docs/capability-registry.md`.
- Settled decisions, including D-027 and D-028:
  `docs/decisions.md`.
- Cross-target Counter scenario: `docs/shared-scenario.md`.
