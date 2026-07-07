# Multi-backend ModulePlan — feasibility assessment and design

Status: **Phase 4 Step A + Step B + Step B.2 + Step C landed** (plan-driven NEAR lowering is the only path; inline `Ctx` deleted; dual-path parity retired) **+ Solana Phase 2 Step C landed** (plan-driven Solana lowering is the only path; inline `buildCtx` deleted; dual-path parity retired) **+ EVM audit landed** (EVM confirmed already plan-only; no Step C refactor needed)

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

**Step C — Switch default. — LANDED (2026-07-07).**
- The plan-driven path is the ONLY lowering path. The inline ad-hoc `Ctx`
  assembly at the top of `EmitWat.lowerModule` (the lines that called
  `stateLayout`/`mapLayout`/`stringPool`/`panicPool`/`crosscallStringInfos` and
  assembled `Ctx` field-by-field) is deleted. `EmitWat.lowerModule` now
  derives its `Ctx` via `EmitWat.buildLowerCtx` → `EmitWat.Ctx.fromPlanSeed`,
  the same reconstruction `NearModulePlan.Ctx.fromPlanSeed` uses, so the
  `*ModulePlan` is the authoritative source for lowering decisions and the
  two paths cannot drift. The shared `lowerModuleCoreWithCtx` body is
  unchanged.
- `EmitWat.Ctx.fromPlanSeed` is owned by `EmitWat` (which owns the `Ctx`
  type); `NearModulePlan.Ctx.fromPlanSeed` delegates to it. This keeps the
  import graph one-directional (`NearModulePlan` imports `EmitWat`, not vice
  versa) and ensures the plan artifact and the lowering entry share one
  reconstruction path.
- `NearModulePlan.lowerModuleFromPlan` now runs the same
  `EmitWat.validateScratchCapacities` gate as the lowering entry, closing a
  Step B gap where the plan path skipped scratch-capacity validation.
- The dual-path parity check that landed in Step B/B.2 is retired: there is
  no second path to agree with. `Tests/NearModulePlan.lean` is now a
  single-path regression gate — the plan golden diff pins the layout artifact
  and the `--render` flag confirms the plan-driven lowering still emits WAT
  for each fixture, with the char count surfaced in CI logs so byte-churn is
  observable. `scripts/near/plan-smoke.sh` switches `--parity` to `--render`.
- `WasmNear/Refinement.lean` reads the plan-driven output automatically:
  its `EmitWat.lowerModule` call sites now lower through the plan-derived
  `Ctx`, so the plan is the authoritative source for the refinement
  obligations too. No `Refinement.lean` code change was needed — the dispatch
  switch in `EmitWat.lowerModule` itself routes through the plan.
- Verification: `lake build` green; `just near-plan-smoke` passes (4/4
  fixtures, plan golden diff + plan-driven render); `just wasm-near-plan`
  passes (WAT surface pruning unchanged); frozen WAT goldens
  (`Counter.golden.wat`, `ValueVault.golden.wat`) and all `plan.txt` goldens
  unchanged. Render char counts match the Step B.2 parity results exactly
  (Counter 2228, EvmMapProbe 3498, EvmStorageArrayProbe 4703,
  EvmStorageStructProbe 3375), confirming byte-stability.

**Byte-stability guard.** The existing `Examples/WasmNear/Counter.golden.wat` and
`ValueVault.golden.wat` pin the WAT output. The `just wasm-near-plan` smoke pins the
host-import/helper surface. `just near-plan-smoke` pins the layout plan as a golden
text artifact (Step A) and, since Step C, asserts the plan-driven lowering still
emits WAT for each fixture (the `--render` flag), mirroring `solana-plan-smoke`.
Step B's extraction was purely additive to the lowering body, so the inline path
and the frozen WAT goldens were unchanged through Step B.2; Step C deleted the
inline path only after the wider parity coverage proved the plan-driven path
preserves semantics across scalar / map / array / struct state shapes. The
frozen WAT goldens and all `plan.txt` goldens are unchanged by Step C.

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

## 8. Landed stub + Step B/B.2/C wiring: `NearModulePlan.lean`

Because NEAR is confirmed easy and the stub is purely additive (no lowering-path
changes), Step A delivered a minimal type-only stub, Step B wired it into
lowering (dual-path), Step B.2 widened parity coverage, and Step C made the
plan-driven path the only path:

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

Step C (2026-07-07):

- The plan-driven path is the ONLY lowering path. The inline ad-hoc `Ctx`
  assembly at the top of `EmitWat.lowerModule` is deleted; `lowerModule`
  now derives its `Ctx` via `EmitWat.buildLowerCtx` →
  `EmitWat.Ctx.fromPlanSeed` (owned by `EmitWat`, which owns the `Ctx` type).
  `NearModulePlan.Ctx.fromPlanSeed` delegates to it, keeping the import
  graph one-directional and ensuring the plan artifact and the lowering entry
  share one reconstruction path.
- `NearModulePlan.lowerModuleFromPlan` now runs the same
  `EmitWat.validateScratchCapacities` gate as the lowering entry, closing a
  Step B gap where the plan path skipped scratch-capacity validation.
- `Tests/NearModulePlan.lean` converted from a dual-path parity check to a
  single-path regression gate: the `--parity` flag (plan-driven WAT vs inline
  WAT) is replaced by `--render` (plan-driven WAT emits cleanly, char count
  surfaced in CI logs). The plan golden diff remains. The 4 fixtures
  (Counter, EvmMapProbe, EvmStorageArrayProbe, EvmStorageStructProbe) stay
  as the coverage set.
- `scripts/near/plan-smoke.sh` switches `--parity` to `--render`.
- `WasmNear/Refinement.lean` reads the plan-driven output automatically via
  its existing `EmitWat.lowerModule` call sites (now plan-driven); no code
  change needed.
- Verification: `lake build` green; `just near-plan-smoke` passes (4/4);
  `just wasm-near-plan` passes; frozen WAT goldens and all `plan.txt`
  goldens unchanged. Render char counts match Step B.2 parity results
  exactly, confirming byte-stability.

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

## 13. Solana Phase 2 Step C (plan-driven lowering, single path)

Solana Phase 2 landed `SolanaModulePlan` + `lowerModuleFromPlan` on `main`
ahead of this NEAR feasibility doc. The Phase 2 work routed `Package.renderPackage`
through `Plan.lowerModuleFromPlan`, but `SbpfAsm.lowerModuleCore` still built its
`LowerCtx` inline via `buildCtx` — a separate lowering path that derived
`stateFieldOffsets`/`structs`/`stateDecls` directly from the IR module. Dual-path
parity (plan-driven asm vs inline asm) was verified byte-identical for the four
fixtures (Counter, EvmStorageArrayProbe, EvmMapProbe, EvmStorageStructProbe).

**Step C (RFC 0014 Phase 2, landed 2026-07-07).** Mirrors NEAR Step C exactly:
the inline `buildCtx` is deleted; `SbpfAsm.lowerModuleCore` now derives its
`LowerCtx` via `SbpfAsm.buildLowerCtx` → `SbpfAsm.LowerCtx.fromPlanSeed`, the
same reconstruction `Solana.Plan.LowerCtx.fromSeed` delegates to, so the
`*ModulePlan` is the authoritative source for lowering decisions and the two
paths cannot drift. The shared `lowerModuleCoreWithSeed` body is unchanged.

- `SbpfAsm.LowerCtx.fromPlanSeed` is owned by `SbpfAsm` (which owns the
  `LowerCtx` type); `Solana.Plan.LowerCtx.fromSeed` delegates to it. This keeps
  the import graph one-directional (`Plan.lean` imports `SbpfAsm.lean`, not
  vice versa), mirroring how `NearModulePlan.Ctx.fromPlanSeed` delegates to
  `EmitWat.Ctx.fromPlanSeed`.
- `Tests/SolanaModulePlan.lean` is converted from a golden-only check to a
  single-path regression gate: the plan golden diff pins the semantic artifact
  and the `--render` flag renders the module via the plan-driven path
  (`Solana.Plan.renderModuleFromPlan`), surfacing the sBPF assembly char count
  in CI logs so byte-churn is observable. The dual-path parity check is retired
  (there is no second path to agree with). The 4 fixtures
  (Counter, EvmStorageArrayProbe, EvmMapProbe, EvmStorageStructProbe) stay as
  the coverage set.
- `scripts/solana/plan-smoke.sh` switches to the `--render` flag and rebrands
  from "golden smoke" to "golden + render smoke", mirroring
  `scripts/near/plan-smoke.sh`.
- No Step C exceptions needed: all `SbpfAsm.lowerModule`/`renderModule`/
  `lowerModuleWithPlan`/`renderModuleWithPlan` call sites (Cli.lean's three
  Counter/ErrorRefProbe/ControlFlowAssertProbe emit paths, the nine
  `Tests/Solana*.lean` emission tests, and `Package.renderPackageWithPlan`)
  route through `lowerModuleCore` and now lower through the plan-derived
  `LowerCtx` automatically.
- Verification: `lake build` green; `just solana-plan-smoke` passes (4/4,
  plan golden diff + plan-driven render); `just solana-build-examples`
  passes (`Counter.s` and `manifest.toml` match frozen goldens);
  `just solana-lean` and `just solana-emit-control` pass (all `SbpfAsm`
  emission tests unaffected); frozen `.s` goldens (`Counter.golden.s`,
  `ValueVault.golden.s`) and all `plan.txt` goldens unchanged. Render char
  counts: Counter 3830, EvmStorageArrayProbe 6609, EvmMapProbe 4470,
  EvmStorageStructProbe 2707.

## 14. EVM audit (RFC 0014 Tier B reference backend, 2026-07-07)

EVM is the reference Tier B backend: `Evm.Plan.ModulePlan` has existed the longest
and is consumed by `Evm.IR.lowerModuleWithPlan`. Solana and NEAR just completed
their Step C (deleting inline `Ctx` builders, making the `*ModulePlan` the sole
authoritative source for lowering decisions). This section records the
mirror audit of EVM: does EVM have any analogous inline residue / dual-path
that can be cleaned up, or is it already cleanly plan-only?

### 14.1 Audit finding — EVM is already plan-only

**Finding: EVM is already cleanly plan-only. No Step C refactor was needed.**

The lowering dispatch in `ProofForge/Backend/Evm/IR.lean` is:

- `lowerModule module = lowerModuleWithPlan module (buildSemanticPlan module)`
  (strict; `buildSemanticPlan` wraps `Lower.buildFullModulePlan`).
- `lowerModuleBestEffort module = lowerModuleWithPlan module (buildSemanticPlanBestEffort module)`
  (best-effort; `buildSemanticPlanBestEffort` falls back to `Plan.buildModulePlan`
  then a default plan if the strict build errors, so diagnostic smokes that feed
  unsupported shapes still render the expected diagnostic rather than aborting at
  plan time).
- `renderModule module = render (lowerModule module)`.
- `renderModuleBestEffort module = render (lowerModuleBestEffort module)`.

Both lowering entries route through `lowerModuleWithPlan`. There is **no** inline
`Ctx`-like derivation that bypasses `Evm.Plan.ModulePlan`: EVM does not use a
`Ctx` / `LowerCtx` struct at all — the plan is consumed directly. A grep for
`buildCtx` / `Ctx.` / `structure Ctx` in `Evm/IR.lean` returns no matches,
confirming EVM never had the Solana/NEAR-style ephemeral lowering context to
delete.

The `lowerModule` vs `lowerModuleBestEffort` split (commit `06e57e12`) is
intentional and is **not** a Step C dual-path: both go through a plan. The
strict entry fails fast on plan-construction errors; the best-effort entry
catches them so diagnostic smokes can render the unsupported-shape diagnostic
from the lowering pass instead of aborting at plan time. This is the same
strict-vs-best-effort distinction the other backends use, just factored into
two named entry points.

### 14.2 Internal best-effort fallbacks are plan-routed too

`lowerModuleWithPlan` has internal completeness checks
(`entrypointBodyPlanIsComplete`, `dispatchEntrypointPlanIsComplete`) that fall
back to `lowerEntrypoint module entrypoint` / `dispatchBlock module` when the
plan's entrypoint/dispatch arrays are not fully populated. These fallbacks are
**not** a Step C dual-path either: each fallback still builds a plan and routes
through a `*WithPlan` function:

- `lowerEntrypoint module entrypoint` builds `Lower.buildEntrypointSurfacePlan`
  and calls `lowerEntrypointWithPlan module entrypoint entrypointPlan`.
- `dispatchBlock module` builds `dispatchPlanForModule` (which itself calls
  `Lower.buildEntrypointSurfacePlan` per entrypoint) and calls
  `dispatchBlockWithPlan module dispatchPlan`.

So even the best-effort fallback path reaches Yul through a plan-derived
`EntrypointPlan` / `DispatchPlan`. There is no code path that derives storage
slots, ABI selectors, or dispatch tables directly from the IR module without
going through a plan node. The `lowerEntrypointBodyWithPlan?` → `lowerStatements`
fallback inside `lowerEntrypointWithPlan` is a per-statement-body best-effort
fallback (planned `StmtPlan` body where supported, legacy statement lowering
where not), not a parallel Ctx derivation — it reads the entrypoint plan's
params/returns and the module's storage layout, which come from the plan.

### 14.3 No inline storage / ABI / dispatch derivation duplicating the plan

The audit specifically checked for inline derivation in `lowerModule` that
duplicates what `Evm.Plan.ModulePlan` carries:

- **Storage slots:** `lowerModule` does not compute storage slots inline.
  `Evm.Plan.storageLayout` / `stateInfo?` / `scalarStorageTargetPlan` /
  `mapValueSlotPlan` / `arraySlotPlan` / `structFieldSlotPlan` etc. live on
  the plan and are consumed by the lowering via plan-target structures
  (`ScalarStorageTargetPlan`, `MapReadTargetPlan`, `ArrayWriteTargetPlan`,
  …). The `lowerModuleWithPlan` body reads `plan.entrypoints`,
  `plan.dispatch`, `plan.helpers`, `plan.crosscalls`, `plan.creates`,
  `plan.localArrayGetLengths`, `plan.nestedLocalArrayGetShapes`.
- **ABI selectors:** `EntrypointPlan.selector` and `AbiParamPlan` are plan
  fields, built by `Lower.buildEntrypointSurfacePlan` /
  `Lower.assembleFullPlan`. The dispatch cases in
  `dispatchCaseWithEntrypointPlan` read `entrypointPlan.params` /
  `entrypointPlan.returns` — no inline selector computation in `lowerModule`.
- **Dispatch tables:** `DispatchPlan` (entrypoints + default) is built by
  `Plan.moduleDispatchPlan` / `Lower.assembleFullPlan` and consumed by
  `dispatchBlockWithPlan`. `moduleDispatchDefaultPlan` (the revert/uups/
  fallback/receive choice) is plan-owned.

There is no inline duplication. EVM is the reference implementation the
other backends were aligned to; it did not accumulate the inline `Ctx`
residue that Solana and NEAR carried before their Step C.

### 14.4 Call sites

All call sites route through the plan-driven dispatch automatically. No call
site bypasses the plan:

| Call site | Path used |
|---|---|
| `ProofForge/Cli.lean:4923` (`proof-forge build --target evm`) | `Evm.IR.lowerModule` → `lowerModuleWithPlan module (buildSemanticPlan module)` |
| `ProofForge/Cli/Evm.lean:9` (`renderYul`) | `Evm.IR.renderModule` → `lowerModule` → `lowerModuleWithPlan` |
| `ProofForge/Backend/Evm/Refinement.lean:390,434` (trace obligations) | `Evm.IR.lowerModule` → `lowerModuleWithPlan` |
| `Tests/TokenEvm.lean:25` | `Evm.IR.lowerModule` → `lowerModuleWithPlan` |
| `Tests/EvmDiagnostics.lean:560` (diagnostic smoke) | `Evm.IR.renderModule` (strict) — renders the diagnostic from `buildSemanticPlan`/lowering rather than best-effort, so the unsupported-shape diagnostic is surfaced |
| `docs/tier-c-proof-feasibility.md`, `docs/rfcs/0004-evm-semantic-plan.md`, `docs/zh/rfcs/0004-evm-semantic-plan.zh.md` | documentation references only |

`lowerModuleBestEffort` / `renderModuleBestEffort` have **no external call
sites** today (they were added in commit `06e57e12` as the strict/best-effort
split surface; diagnostic smokes currently use the strict `renderModule`).
They remain available for smokes that want to render past plan-construction
errors.

### 14.5 Action taken

**Documented as already plan-only. No `IR.lean` refactor was performed.**
EVM did not need a Step C cleanup because it never had the inline `Ctx`
builder that Solana (`buildCtx`) and NEAR (the inline `Ctx` assembly at the
top of `EmitWat.lowerModule`) carried. The strict/best-effort split is
intentional and plan-routed on both sides. Forcing a refactor here would
have been busywork that risked the frozen EVM goldens for no gain.

### 14.6 Verification

- `lake build` green (378 jobs, no errors; only pre-existing linter warnings).
- `just evm-plan` passes (`Tests/EvmPlan.lean`).
- `just evm-semantic-plan` passes (`Tests/EvmSemanticPlan.lean`).
- `just evm-build-examples` passes — bytecode emitted for all examples
  (Counter, ValueVault, ReentrancyGuard, UUPSProxy, VerifiedVault, …);
  frozen EVM goldens (`Examples/Evm/*.golden.yul`) unchanged.
- Working tree clean before and after the gate runs (no golden churn).
- No `IR.lean` change, so byte-stability is trivially preserved.

## 15. References

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