# Multi-backend ModulePlan — feasibility assessment and design

Status: **Phase 4 Step A + Step B + Step B.2 landed** (plan-driven NEAR lowering, dual-path parity green across scalar/map/array/struct state)

Date: 2026-07-07

Target phase: [RFC 0014](rfcs/0014-unified-semantic-lowering-contract.md) Phase 4 (NEAR plan layer)

Companion documents:

- [RFC 0014](rfcs/0014-unified-semantic-lowering-contract.md) — the unified lowering contract.
- [target-lowering-interface.md](target-lowering-interface.md) — per-backend invariants.
- [solana-module-plan-design.md](solana-module-plan-design.md) — the field-level design for
  `SolanaModulePlan` (Phase 2, already landed on `main`).
- [shared-diagnostic-design.md](shared-diagnostic-design.md) — shared `LoweringDiagnostic`.

## 1. Purpose

RFC 0014 Phase 4 brings the Tier B "explicit `*ModulePlan` before AST" contract to the
NEAR (WasmNear), Psy, and Move (Sui) backends, mirroring what EVM and Solana already have.
This document records the audit of each candidate backend's current lowering path,
picks the easiest first candidate, and specifies the field-level design for that
candidate's `*ModulePlan`.

This is a **research + design** step. No lowering path is refactored here. The only
implementation artifact (optional, additive) is a type-only `NearModulePlan` stub that
does not touch the EmitWat lowering path (see §6).

## 2. Audit method

For each candidate backend we asked:

1. **Lowering entry point.** Where does IR → AST/source lowering happen? (The
   equivalent of `SbpfAsm.lowerModule` / `Evm.IR.lowerModule`.)
2. **Implicit "plan-like" structure.** Is there a `LowerCtx`, a `buildCtx`, or a
   pre-computed schema? What semantic decisions are made before/while generating the AST?
3. **LowerCtx-equivalent.** The ephemeral context that holds derived layout/dispatch/
   schema info — the thing a `*ModulePlan` + `*LowerCtxSeed` would replace, exactly as
   Solana's `LowerCtx` was split into plan-derived vs lowering-local fields.
4. **Existing plan.** Does the backend already have a `*ModulePlan`-shaped artifact
   (even if it is metadata-only or not wired into the lowering)?
5. **Coupling.** How coupled is the lowering to its context? Would a plan-driven path
   require a big refactor (like Solana needed `lowerModuleCoreWithSeed`), or is the
   lowering already mostly pure?
6. **Difficulty.** Easy / medium / hard, with evidence.

## 3. Per-backend feasibility table

| Backend | Current lowering shape | Has implicit ctx? | Has existing plan? | Difficulty | Recommended order |
|---|---|---|---|---|---|
| **NEAR (WasmNear)** | Two parallel paths: (a) `WasmNear/IR.lean` — Rust sourcegen (~1.3k LOC), `validateModule` → `renderLibRs` builds Rust source inline, no plan; (b) `WasmNear/EmitWat.lean` (~2.7k LOC) — IR → Wasm AST, **already consumes `WasmNear.Plan.ModulePlan`** (`buildModulePlan`) for host imports / helper pruning, then builds an inline `Ctx` (scalars/maps/strings/panics/crosscallStrings) for data layout. | Yes — `EmitWat.Ctx` (scalars, maps, strings, panics, crosscallStrings, structs, allocator). `WasmNear/IR.lean` sourcegen has no `Ctx`, lowering is stateless string-building. | **Yes** — `ProofForge/Backend/WasmNear/Plan.lean` already defines `ModulePlan` + `buildModulePlan` + `ModuleSurface` (a rich host-import/helper-discovery plan). EmitWat consumes it. The gap is that the layout `Ctx` is still built inline, not plan-derived. | **Easy–medium** | **1st** |
| **Psy** | `Psy/IR.lean` — `buildModule` consumes `PsyModulePlan` via a `BuildContext` (module + storage layout). Lowering is already plan-driven: `BuildContext.layout` is consulted for every state lookup (`lookupState?`, `requireScalarStateCtx`, ...). No inline `LowerCtx` accumulation; the plan is the context. | Partially — `BuildContext` is just `{ module, layout }`, where `layout` comes from the plan. No mutable lowering-local state. | **Yes** — `PsyModulePlan` (storage shapes, context ops, events, crosscalls, test plan, capabilities). Metadata-only (no `ExprPlan`/`StmtPlan`), already consumed by `IR.lean` and `Metadata*.lean`. | **Easy** (for seam alignment) — but lower payoff than NEAR because the plan is already wired and the lowering is already pure. | **3rd** (deferred — see §7) |
| **Move (Sui)** | `Move/Sui.lean` — `renderSource` is a hardcoded Counter MVP template (~80 LOC). No lowering, no `Ctx`, no plan. `checkCapabilities` + `requireScalarState` then string-templates a Move module. Only scalar u64 state, fixed entrypoint names (create/initialize/increment/value/get/destroy). | No — no implicit context; lowering is string interpolation. | No. | **Hard** (for a real plan) — but the backend itself is an MVP spike, not a real lowering. A `SuiModulePlan` would have to precede building a real Move lowering, not the other way around. | **2nd** (deferred — see §7) |

**Summary:** NEAR is the clear first candidate. Unlike Solana (which needed a
`lowerModuleCoreWithSeed` refactor to make `LowerCtx` plan-derived), NEAR's EmitWat
**already consumes a plan** for the host-import/helper surface. The remaining gap is
narrower: the data-layout `Ctx` (scalar key pointers, map prefix pointers, string pool,
panic pool, crosscall string pool) is still computed inline at the top of `lowerModule`
(lines 2574–2583). Promoting that layout to the plan is a smaller, more contained change
than Solana's `LowerCtx` split.

## 4. Chosen first candidate: NEAR (WasmNear)

### 4.1 Why NEAR is easiest — evidence

1. **A plan already exists and is consumed.** `ProofForge/Backend/WasmNear/Plan.lean`
   defines `ModulePlan` (1138–1180) and `buildModulePlan` (1182–1226). `EmitWat.lowerModule`
   calls `buildModulePlan mod` at line 2570 and uses the result to drive host imports,
   helper emission, and globals. This is further along than Solana was at the start of
   Phase 2 (Solana had no plan at all).
2. **The lowering is already mostly pure.** `lowerEntrypoint` takes a `Ctx` and produces
   a `Func`; it does not mutate the `Ctx`. The `Ctx` fields that *are* lowering-local
   (none, actually — `Ctx` is read-only inside `lowerEntrypoint`) are smaller than
   Solana's `LowerCtx` (which had `locals`, `nextLocalOffset`, `scratchOffset`,
   `nextLabel`, `allocator` as genuine lowering-local state).
3. **The gap is layout, not dispatch.** The inline `Ctx` holds data-segment layout
   (`StateInfo` key pointers, `MapInfo` prefix pointers, `StringInfo` string pool,
   `StringInfo` panic pool, `StringInfo` crosscall string pool). These are
   *deterministic functions of the module* — exactly the kind of fact a plan should own.
   There is no mutable per-entrypoint state to split out.
4. **WAT golden churn risk is bounded.** EmitWat already has a `wasm-near-plan` smoke
   (`Tests/WasmNearPlan.lean`) that asserts host-import/helper pruning. The frozen
   WAT golden (`Examples/WasmNear/Counter.golden.wat`, `ValueVault.golden.wat`) pins
   byte-stable output. The migration can land behind the same feature-flag strategy
   Solana uses.
5. **The Rust sourcegen path (`WasmNear/IR.lean`) is out of scope.** It is a parallel,
   simpler lowering with no `Ctx` and no plan; bringing it under Tier B is a separate,
   later decision (see §7).

### 4.2 What is already plan-driven in EmitWat

`EmitWat.lowerModule` (lines 2570–2639) already reads these plan fields:

- `modulePlan.usesEventApi` → event data segments + `log_utf8` import.
- `modulePlan.usesPromiseCreate` → `[]` crosscall args data + promise imports.
- `modulePlan.usesPromiseThen` / `usesPromiseResults` → promise imports.
- `modulePlan.usesU64IndexedContains` / `usesHashIndexedContains` → `storage_has_key`.
- `modulePlan.scalarReadTypes` / `scalarWriteTypes` → scalar storage helper funcs.
- `modulePlan.u64IndexedReadTypes` / `u64IndexedWriteTypes` → map helper funcs.
- `modulePlan.hashIndexedReadTypes` / `hashIndexedWriteTypes` → hash-map helper funcs.
- `modulePlan.contextOps` → context helper funcs + imports.
- `modulePlan.usesNativeValue` → `attached_deposit` import.
- `modulePlan.usesHashMake` / `usesHashPreimage` / `usesHashTwoToOne` / `usesHashEq`
  → hash helper funcs.
- `modulePlan.usesPowU32` / `usesPowU64` → pow helper funcs.
- `modulePlan.arrayLitShapes` / `arrayEqShapes` / `structLitNames` → aggregate helpers.
- `modulePlan.usesMemcpy` → memcpy helper.
- `modulePlan.usesArrAlloc` / `usesArrDealloc` → array allocator globals/helpers.

This is already the Tier B contract: the plan is an inspectable artifact that drives
the AST surface. The `just wasm-near-plan` smoke gates it.

### 4.3 What is NOT yet plan-driven (the gap)

The `Ctx` built inline at `EmitWat.lowerModule:2574–2583`:

```lean
structure Ctx where
  scalars : Array StateInfo      -- state id → linear-memory key pointer
  maps    : Array MapInfo         -- map prefix → pointer
  strings : Array StringInfo      -- event/field name string pool
  panics  : Array StringInfo      -- panic message string pool
  crosscallStrings : Array StringInfo  -- NEAR crosscall account/method strings
  structs : Array StructDecl      -- type metadata (read-only)
  allocator : AllocatorConfig      -- target profile config (read-only)
```

These six layout fields are deterministic functions of the module (plus the frozen
scratch-region base addresses like `KEY_BUF`, `MAPKEY_BUF`, `STRING_BASE`). They are
rebuilt on every `lowerModule` call. Under the Tier B contract they should live on a
`NearModulePlan` so:

- The layout is inspectable (a reviewer can diff `StateInfo` key pointers between
  releases, like Solana's `StorageAccountPlan.stateFieldOffsets`).
- `WasmNear/Refinement.lean` can read the plan instead of re-deriving exports/imports.
- The plan can be golden-tested (`just near-plan-smoke`, mirroring `solana-plan-smoke`).

## 5. Field-level design: `NearModulePlan`

The design **extends the existing `WasmNear.Plan.ModulePlan`** rather than replacing
it. The existing plan is the "host-import / helper-discovery" surface; the extension
adds the "data-layout" surface. This mirrors how `SolanaModulePlan` carries both
`StorageAccountPlan` (layout) and the extension/account/dispatch plans.

### 5.1 Top-level type (proposed extension)

The existing `ModulePlan` is kept (it is already consumed by EmitWat and tested by
`Tests/WasmNearPlan.lean`). A new `NearModulePlan` wraps it and adds the layout fields:

```lean
-- proposed: ProofForge/Backend/WasmNear/NearModulePlan.lean
structure NearStatePlan where
  id : String
  kind : String          -- "scalar" | "map" | "array" | "dynamicArray"
  typeName : String
  keyPtr : Nat           -- linear-memory offset of the storage key string
  deriving Repr, BEq

structure NearMapPlan where
  id : String
  keyType : String
  valueType : String
  prefixPtr : Nat        -- linear-memory offset of the "<id>:" prefix bytes
  deriving Repr, BEq

structure NearStringPoolEntry where
  str : String
  ptr : Nat
  deriving Repr, BEq

structure NearLayoutPlan where
  scalars : Array NearStatePlan
  maps : Array NearMapPlan
  strings : Array NearStringPoolEntry      -- event/field name pool
  panics : Array NearStringPoolEntry       -- panic message pool
  crosscallStrings : Array NearStringPoolEntry
  stringPoolEnd : Nat
  deriving Repr, BEq

structure NearLowerCtxSeed where
  -- The frozen scratch-region base addresses (KEY_BUF, MAPKEY_BUF, ...).
  -- These are constants today; the seed makes them plan-owned so the lowering
  -- is a pure function of the plan + IR module.
  keyBuf : Nat
  mapkeyBuf : Nat
  stringBase : Nat
  crosscallStringBase : Nat
  -- Read-only type metadata carried verbatim from the IR module.
  structs : Array StructDecl
  allocator : AllocatorConfig

structure NearModulePlan where
  moduleName : String
  targetId : String           -- "wasm-near"
  artifactKind : String       -- "wasm-wat"
  irVersion : String           -- "portable-ir-v0"
  surface : WasmNear.Plan.ModulePlan   -- the existing host-import/helper plan
  layout : NearLayoutPlan
  lowerCtxSeed : NearLowerCtxSeed
  deriving Repr
```

### 5.2 Field sourcing table

| Plan field | Current source (file + symbol) | Invariant |
|---|---|---|
| `surface.*` | `WasmNear.Plan.buildModulePlan` / `ModuleSurface` (already plan-driven) | Unchanged; EmitWat already reads it |
| `layout.scalars[i].keyPtr` | `EmitWat.stateLayout mod` → `StateInfo.keyPtr` (computed from `KEY_BUF` + cumulative id lengths) | Pointers unique, ascending, within `KEY_BUF..KEY_BUF+4096` |
| `layout.maps[i].prefixPtr` | `EmitWat.mapLayout mod` → `MapInfo.prefixPtr` (from `MAPKEY_BUF` + cumulative prefix lengths) | Pointers unique, ascending, within `MAPKEY_BUF..MAPKEY_BUF+17500` |
| `layout.strings[i].ptr` | `EmitWat.stringPool mod STRING_BASE` → `StringInfo.ptr` | Within `STRING_BASE..STRING_BASE+1000` |
| `layout.panics[i].ptr` | `EmitWat.panicPool mod (stringInfoEnd STRING_BASE strs)` | After string pool; within scratch budget |
| `layout.crosscallStrings[i].ptr` | `EmitWat.crosscallStringInfos mod.nearCrosscallStrings CROSSCALL_STRING_BASE` | Within `CROSSCALL_STRING_BASE..CROSSCALL_STRING_BASE+1000` |
| `layout.stringPoolEnd` | `stringInfoEnd STRING_BASE strs` | End of string pool; panics start here |
| `lowerCtxSeed.keyBuf` etc. | `EmitWat.KEY_BUF` / `MAPKEY_BUF` / `STRING_BASE` / `CROSSCALL_STRING_BASE` constants | Frozen by `memoryLayoutNonoverlap_valid` theorem |
| `lowerCtxSeed.structs` | `mod.structs` (read-only mirror) | Subset accepted by `wasmNear` profile |
| `lowerCtxSeed.allocator` | `mod.allocator` (read-only mirror) | Must match `wasmNear` profile config |

### 5.3 Sub-plan: `ExportPlan` / `EntrypointPlan` (future)

The RFC 0014 sketch lists `ExportPlan` (Wasm function exports) and `StorageKeyPlan`.
The existing `ModulePlan` already covers the export surface indirectly (the helper
funcs are plan-driven). A dedicated `ExportPlan` (one entry per `Entrypoint`, naming
the exported Wasm function) is a natural Phase 4.2 addition but **not required** for the
first cut — it is derivable from `module.entrypoints` and is already implicit in
`lowerEntrypoint`'s `exportName := ep.name`. We defer it to keep the first cut minimal.

`StorageKeyPlan` (the `"<id>"` / `"<id>:"` byte prefixes and their pointers) **is** the
new surface — that is exactly what `NearLayoutPlan.scalars` and `.maps` capture.

### 5.4 `lowerCtxSeed` disposition

This mirrors Solana's `SolanaLowerCtxSeed`. The seed carries the large structural
objects (scratch base addresses, struct decls, allocator config) so the lowering is a
pure function of `NearModulePlan` + the IR module's statement bodies. EmitWat's `Ctx`
becomes:

```lean
-- proposed
def Ctx.fromSeed (seed : NearLowerCtxSeed) (layout : NearLayoutPlan) : Ctx :=
  { scalars := layout.scalars.map (fun s => { keyPtr := s.keyPtr, id := s.id : StateInfo })
    maps := layout.maps.map (fun m => { prefixPtr := m.prefixPtr, id := m.id : MapInfo })
    strings := layout.strings.map (fun s => { ptr := s.ptr, str := s.str : StringInfo })
    panics := layout.panics.map (fun s => { ptr := s.ptr, str := s.str : StringInfo })
    crosscallStrings := layout.crosscallStrings.map (fun s => { ptr := s.ptr, str := s.str : StringInfo })
    structs := seed.structs
    allocator := seed.allocator }
```

No lowering-local mutable state exists in `Ctx` today, so unlike Solana there is no
`locals` / `nextLabel` / `allocator` to keep lowering-local. The whole `Ctx` is
plan-derived. This is why NEAR is easier than Solana.

## 6. Migration path (NEAR)

Three steps, each behind the existing `renderModule` / `renderModuleWithPlan` seam.
No feature flag is needed initially because the change is additive (the inline `Ctx`
construction is replaced by `Ctx.fromSeed`, which produces the same fields).

**Step A — Types only (no behavior). — LANDED (commit 61cfa7a9).**
- Add `ProofForge/Backend/WasmNear/NearModulePlan.lean` with the struct definitions
  above (no construction, no consumers).
- `NearModulePlan` is buildable but unused; EmitWat path unchanged.
- CI stays green by construction. *(This is the optional stub this step delivers.)*

**Step B — Plan construction + `Ctx.fromSeed` (additive). — LANDED (2026-07-07).**
- Implement `buildNearModulePlan : IR.Module → Except PlanError NearModulePlan` by
  calling `WasmNear.Plan.buildModulePlan` for the `surface` and the existing
  `stateLayout` / `mapLayout` / `stringPool` / `panicPool` / `crosscallStringInfos`
  for the `layout`.
- Implement `Ctx.fromPlanSeed : NearLowerCtxSeed → NearLayoutPlan → EmitWat.Ctx`
  (the whole `Ctx` is plan-derived; no lowering-local mutable state) and
  `lowerModuleFromPlan : IR.Module → NearModulePlan → Except EmitError Wasm.Module`.
  The plan-driven path reconstructs the `Ctx` and hands it to a shared
  `EmitWat.lowerModuleCoreWithCtx` body extracted from the inline `lowerModule`
  (mirroring Solana's `lowerModuleCoreWithSeed`). The inline `Ctx` construction
  in `EmitWat.lowerModule` is kept (dual-path) until Step C.
- The `just near-plan-smoke` gate runs a dual-path parity check (the existing
  golden plan diff plus a `--parity` flag that asserts plan-driven WAT == inline
  WAT). Initial Step B coverage: `Counter: MATCH 2228 chars`.

**Step B.2 — Widen parity coverage to non-scalar state shapes. — LANDED (2026-07-07).**
- Extend `Tests/NearModulePlan.lean` with a `moduleFor` resolver and three
  sub-module fixtures mirroring the Solana Phase 2 array/map/struct probes:
  `EvmMapProbe` (map state, u64-keyed `balances`), `EvmStorageArrayProbe`
  (array state, `values` length 3), `EvmStorageStructProbe` (struct state,
  `current : Point`). Each sub-module only exercises lowering paths the NEAR
  backend already supports (`storageMapGet/Set`, `storageArrayRead/Write`,
  `storageStructFieldRead/Write`).
- Extend `scripts/near/plan-smoke.sh` to loop over all four fixtures
  (Counter + three new), generating + diffing each plan golden AND running the
  parity check per fixture. New golden `plan.txt` files added under
  `Examples/WasmNear/<Fixture>/golden/`.
- Parity results (plan-driven WAT == inline WAT, byte-identical):
  `Counter: MATCH 2228 chars`, `EvmMapProbe: MATCH 3498 chars`,
  `EvmStorageArrayProbe: MATCH 4703 chars`, `EvmStorageStructProbe: MATCH 3375 chars`.
- The inline `Ctx` construction in `EmitWat.lowerModule` is still kept
  (dual-path); Step C deletes it after this wider coverage proves the
  plan-driven path preserves semantics across scalar / map / array / struct
  state shapes. `ValueVault` (scalar) and `NearCrosscallProbe` (crosscall)
  were also probed and match, but are not wired as gate fixtures because
  `EvmMapProbe`/`EvmStorageArrayProbe`/`EvmStorageStructProbe` already cover
  the non-scalar state shapes and mirror Solana's fixture set exactly.

**Step C — Switch default.**
- After parity holds over N consecutive CI runs, flip the default to v2 and delete
  the inline `Ctx` construction.
- `WasmNear/Refinement.lean` switches from re-deriving exports/imports to reading
  `NearModulePlan.surface` + `NearModulePlan.layout`.

**Byte-stability guard.** The existing `Examples/WasmNear/Counter.golden.wat` and
`ValueVault.golden.wat` pin the WAT output. The `just wasm-near-plan` smoke pins the
host-import/helper surface. `just near-plan-smoke` pins the layout plan as a golden
text artifact (Step A) AND asserts dual-path WAT parity (Step B), mirroring
`solana-plan-smoke`. Step B's extraction is purely additive to the lowering body,
so the inline path and the frozen WAT goldens are unchanged.

## 7. Deferred backends

### 7.1 Psy (deferred — 3rd)

Psy is *easy* for seam alignment (the plan already exists and is consumed), but the
payoff is low: `PsyModulePlan` is metadata-only, `Psy/IR.lean` already reads it via
`BuildContext`, and there is no `LowerCtx` to split. The work is extending the plan to
cover entrypoint/body shapes (Phase 6 per RFC 0014), not introducing a plan. The
existing `psy-metadata*` smokes already gate the metadata surface.

**What needs to happen first:** a decision on whether Psy needs `ExprPlan`/`StmtPlan`
body planning (Phase 6), or whether the metadata-only plan is the steady state. This is
a product question, not a refactor question, and is out of scope for Phase 4.

### 7.2 Move-Sui (deferred — 2nd)

Move-Sui is a **Counter MVP spike**, not a real lowering. `renderSource` is a hardcoded
string template that only handles a single scalar u64 state with fixed entrypoint
names. There is no `Ctx`, no plan, no lowering — just interpolation.

A `SuiModulePlan` would have to precede building a real Move lowering, not the other
way around. The plan would need:

- `SuiStructPlan` — the module's `struct` definitions (Move resource types).
- `SuiEntrypointPlan` — `public fun` signatures, parameter types, return types.
- `SuiStatePlan` — `has key` resource fields (Move's storage model is object/UID-based,
  not slot-based).
- `SuiCapabilityPlan` — which Move abilities (`key`, `store`, `drop`, `copy`) each
  struct needs.

But none of that is useful until there is a real lowering that consumes it. The
current `renderSource` cannot consume a plan because it does not lower — it templates.

**What needs to happen first:** a real Move lowering that handles arbitrary modules
(not just Counter). That is a Phase 6+ research item, not Phase 4. The `move-sui`
backend is correctly listed in RFC 0014 non-goals ("extending the contract to ...
Move (Sui/Aptos) ... in the initial scope. Those may follow once the four primary
backends are aligned").

## 8. Landed stub + Step B wiring: `NearModulePlan.lean`

Because NEAR is confirmed easy and the stub is purely additive (no lowering-path
changes), Step A delivered a minimal type-only stub, and Step B wired it into
lowering:

Step A (commit 61cfa7a9):

- `ProofForge/Backend/WasmNear/NearModulePlan.lean` — the struct definitions from §5
  plus a `buildNearModulePlan` that constructs a plan for
  `ProofForge.IR.Examples.Counter.module`. It reuses the existing
  `WasmNear.Plan.buildModulePlan` for the `surface` and computes the layout fields
  using the same frozen constants EmitWat uses (`KEY_BUF`, `MAPKEY_BUF`,
  `STRING_BASE`, `CROSSCALL_STRING_BASE`).
- `Tests/NearModulePlan.lean` — builds the plan for `Counter.module` and renders it
  to a stable text format.
- `Examples/WasmNear/Counter/golden/plan.txt` — the golden plan output.
- `scripts/near/plan-smoke.sh` — mirrors `scripts/solana/plan-smoke.sh`.
- `justfile` recipe `near-plan-smoke`, wired into `just check`.

Step B (2026-07-07):

- `Ctx.fromPlanSeed` + `lowerModuleFromPlan` + `renderModuleFromPlan` in
  `NearModulePlan.lean` (the plan-driven path).
- `EmitWat.lowerModuleCoreWithCtx` extracted from `lowerModule` (the shared body
  both paths use), breaking the import cycle without changing the inline path's
  output.
- `Tests/NearModulePlan.lean` extended with a dual-path parity check
  (plan-driven WAT vs inline WAT, byte-identical); `scripts/near/plan-smoke.sh`
  runs it via `--parity`.
- Result: `Counter: MATCH 2228 chars`. The inline `Ctx` construction is kept
  (dual-path) until Step C.

Step B.2 (2026-07-07):

- `Tests/NearModulePlan.lean` extended with a `moduleFor` resolver and three
  sub-module fixtures (`EvmMapProbe`, `EvmStorageArrayProbe`,
  `EvmStorageStructProbe`) mirroring the Solana Phase 2 array/map/struct probes.
- `scripts/near/plan-smoke.sh` loops over all four fixtures (Counter + three
  new), generating + diffing each plan golden and running the parity check per
  fixture. New golden `plan.txt` files added under
  `Examples/WasmNear/<Fixture>/golden/`.
- Parity results (plan-driven WAT == inline WAT, byte-identical):
  `Counter: MATCH 2228 chars`, `EvmMapProbe: MATCH 3498 chars`,
  `EvmStorageArrayProbe: MATCH 4703 chars`,
  `EvmStorageStructProbe: MATCH 3375 chars`.
- Coverage now spans scalar / map / array / struct state shapes; the inline
  `Ctx` construction is still kept (dual-path) until Step C.

## 9. RFC 0014 Phase 4 update summary

RFC 0014 Phase 4 (en + zh) is updated to:

- Record that `WasmNear.Plan.ModulePlan` already exists and is consumed by EmitWat
  (the audit corrected the RFC's earlier "No `WasmNear/Plan.lean`" claim).
- Name NEAR as the chosen first candidate for Phase 4, with the field-level design
  from §5.
- Note that the migration is smaller than Solana's because the whole `Ctx` is
  plan-derived (no lowering-local mutable state to split out).
- Defer Psy and Move-Sui with the rationale from §7.
- Keep the Phase 4 scope as a *plan*, not a full implementation — the stub from §8 is
  the only implementation artifact, and it is additive.

## 10. Open questions

- Should `NearLayoutPlan` include the `ExportPlan` (one entry per entrypoint, naming
  the Wasm export)? Deferred to Phase 4.2; not required for the first cut.
- Should the Rust sourcegen path (`WasmNear/IR.lean`) also grow a plan? It is a
  parallel lowering with no `Ctx`; bringing it under Tier B is a separate decision.
  Recommendation: defer — the EmitWat path is the canonical NEAR lowering (decision
  D-023), and the sourcegen path is a legacy/alternative surface.
- Should `NearModulePlan` serialize to JSON for human review? Inherited open
  question from RFC 0004 / 0014 (Phase 7 stretch).
- Should `Ctx.fromSeed` be pure or monadic? Recommendation: pure — the seed fields
  are constants and the layout is deterministic.

## 11. Non-goals

- **Refactoring EmitWat's lowering path.** This step is design + an additive stub;
  no lowering output changes.
- **Body planning** (`ExprPlan`/`StmtPlan` for NEAR). Deferred to Phase 6, mirroring
  EVM and Solana.
- **Tier C refinement** for NEAR. `WasmNear/Refinement.lean` already exists; plan
  consumption is a Step C follow-up, not this step.
- **Single global `ModulePlan` type.** `NearModulePlan` is NEAR-specific, per
  RFC 0004 non-goal.
- **Move-Sui / Psy plan implementation.** Deferred per §7.

## 12. References

- [RFC 0014](rfcs/0014-unified-semantic-lowering-contract.md) — Phase 4 source.
- [target-lowering-interface.md](target-lowering-interface.md) — per-backend
  invariants table (NEAR row).
- [solana-module-plan-design.md](solana-module-plan-design.md) — the field-level
  design this document mirrors for NEAR.
- [shared-diagnostic-design.md](shared-diagnostic-design.md) — shared error type.
- `ProofForge/Backend/Evm/Plan.lean` — reference `ModulePlan` (1460 LOC).
- `ProofForge/Backend/Solana/Plan.lean` — `SolanaModulePlan` + `SolanaLowerCtxSeed`
  + `lowerModuleFromPlan` (378 LOC, landed).
- `ProofForge/Backend/WasmNear/Plan.lean` — existing `ModulePlan` +
  `buildModulePlan` + `ModuleSurface` (1228 LOC, already consumed by EmitWat).
- `ProofForge/Backend/WasmNear/EmitWat.lean` — `lowerModule` (2565), `Ctx`
  (1269–1276), `lowerEntrypoint` (2552), `memoryLayoutNonoverlap_valid` (156).
- `ProofForge/Backend/WasmNear/IR.lean` — Rust sourcegen path (1314 LOC, out of
  scope).
- `ProofForge/Backend/Psy/Plan.lean` — `PsyModulePlan` (539 LOC, metadata-only).
- `ProofForge/Backend/Psy/IR.lean` — `BuildContext` (41–43), plan-driven lowering.
- `ProofForge/Backend/Move/Sui.lean` — Counter MVP template (200 LOC).
- `Tests/WasmNearPlan.lean` — existing `wasm-near-plan` smoke (658 LOC).
- `Tests/SolanaModulePlan.lean` + `scripts/solana/plan-smoke.sh` — the golden plan
  smoke template this step mirrors.
- `Examples/Solana/Counter/golden/plan.txt` — the golden plan format.
- `ProofForge/IR/Examples/Counter.lean` — the `Counter.module` fixture.