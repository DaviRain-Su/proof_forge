# Incremental Legacy Replacement

## Status

Accepted design direction (2026-07-12). This document defines the migration
policy that accompanies D-052. It does not replace the Portable Intent design
or its A/B/C delivery order.

## Decision

ProofForge replaces legacy paths through a mixed migration program:

1. establish the replacement boundary and a no-new-legacy rule;
2. migrate the callers touched by each A/B/C architecture task;
3. prove old/new parity before switching defaults;
4. delete a legacy path only after a separate, reviewable removal gate.

This is not a repository-wide rewrite. New product behavior must use the new
architecture, while existing product families migrate one independently
verifiable slice at a time.

## Why A Separate Migration Program Is Required

The repository uses the word "legacy" for several different things:

- old authoring or CLI surfaces that should eventually disappear;
- compatibility adapters that are still required during migration;
- frozen baseline implementations used only for parity evidence;
- `ContractSpec`, which currently has both compatibility and legitimate
  compiler-exchange roles.

Treating all four as equivalent would either preserve obsolete product routes
forever or remove compiler contracts before their replacements exist. The
migration program therefore tracks boundaries and callers, not filenames or
names alone.

## Target Architecture

The target product flow is:

```text
portable source / product intent
  -> target-neutral normalization
  -> IntentContract or Surface v2
  -> CheckedCanonicalContract
  -> CapabilityPlan
  -> target materializer / target plan
  -> artifact bundle and runtime evidence
```

During migration, a materializer may produce a `ContractSpec` as an internal
exchange value before canonical adaptation. That use is allowed. Product
frontends selecting a target, routing through legacy flags, or constructing a
target-shaped `ContractSpec` directly are not part of the target architecture.

## Migration Lines

### D1: Source Grammar Ownership

**Legacy boundary:** Solana PDA, CPI, and realloc grammar is visible through
the portable `ProofForge.Contract.Source` import.

**Replacement:** portable grammar stays in `Contract.Source`; Solana-only
categories and productions live behind `Contract.Source.Solana`.

**Trigger:** A1.

**Removal gate:** portable-only imports reject Solana forms, Solana imports
preserve generated IR, and the Solana product/backend gates remain unchanged.

### D2: Product Intent To Compiler Exchange

**Legacy boundary:** product entrypoints directly construct or route a
`ContractSpec`, coupling authoring choices to the existing compiler exchange
format.

**Replacement:** product specs normalize to `IntentContract`; the registry
selects a target materializer; the materializer returns a checked exchange
value for the existing canonical and target-plan pipeline.

**Triggers:** A2 establishes the contract; A3-A6 prove it with the NFT slice.
After A6, Counter, ValueVault, Token, and Remote migrate as separate product
families.

**Removal gate:** the migrated product family has no direct target dispatch or
target-shaped `ContractSpec` construction, and its artifacts, diagnostics, and
runtime behavior match the pinned baseline.

### D3: Canonical Pipeline Input And Fallback

**Legacy boundary:** `IR.Legacy.Adapter.adaptLegacy`, explicit `.legacy`
pipeline mode, and advisory canonical gates that permit an adapter or target
builder gap to fall through successfully.

**Replacement:** new sources enter as `Surface v2` or a checked canonical
contract; promoted fragments use a strict canonical gate and never translate
Surface back into Legacy.

**Triggers:** A2 creates a native intent boundary; A5 requires strict accepted
NFT materializations; B2 establishes the reusable strict target gate.

**Removal gate:** all advertised product families and primary targets use the
strict path by default. Adapter failure, missing HostOp handling, and target
builder rejection remain observable errors. The frozen legacy mode may then be
removed from production code while parity fixtures move to test-only helpers.

### D4: CLI Target-First Dispatch

**Legacy boundary:** `newCommandArgsToLegacy`, legacy flag builders, and the
target-first command path reparsing translated legacy arguments.

**Replacement:** typed target-first requests resolve a registered target driver
and invoke native build, emit, or check operations without argument round trips.

**Trigger:** A6 must add the NFT route natively. Existing commands migrate by
operation and target after the replacement request/driver contract is proven.

**Removal gate:** executable callers use native target-first dispatch; old
aliases have an explicit compatibility-window decision; tests check alias
diagnostics instead of using aliases as their primary execution path.

### D5: Compatibility Fixtures And Imports

**Legacy boundary:** product or general tests import `IR.Legacy.*`, exercise
legacy wrappers as the primary success path, or keep duplicate backend-shaped
sources after the shared source is authoritative.

**Replacement:** parity fixtures are isolated under clearly test-only modules;
product tests exercise portable sources, intents, canonical contracts, and
registered targets.

**Trigger:** every D1-D4 slice must migrate the tests and examples it touches.

**Removal gate:** repository checks reject new production imports of the
retired module or API, the remaining allowlist contains only named parity
fixtures, and each allowlist entry has an owner and deletion condition.

## `ContractSpec` Policy

`ContractSpec` is not globally deprecated by this design.

Allowed transitional and compiler uses:

- an intent materializer returning an ordinary spec for the current canonical
  adapter;
- target-neutral client schema and metadata generation where the spec is the
  current stable input contract;
- backend, formal, and parity fixtures that explicitly test that boundary.

Disallowed growth:

- new product APIs whose public abstraction is `ContractSpec` rather than an
  intent or portable source;
- frontend `targetId` branches that build different specs;
- new fallback logic that converts a strict canonical failure into legacy
  success;
- new CLI commands implemented by translating typed requests into legacy
  argument strings when a native driver operation exists.

The type may be narrowed or replaced only after a later decision identifies
all remaining legitimate consumers and supplies a versioned exchange contract.

## Boundary State Machine

Every tracked boundary has exactly one state:

```text
inventoried
  -> replacement_ready
  -> parity_verified
  -> default_switched
  -> removed
```

- `inventoried`: callers, tests, public behavior, and owner are known.
- `replacement_ready`: the new interface exists and fails closed, but the old
  path may remain the default.
- `parity_verified`: positive behavior, rejection behavior, diagnostics,
  metadata, and artifacts required by the slice have reproducible evidence.
- `default_switched`: production callers use the replacement; the old path is
  compatibility-only and guarded against new callers.
- `removed`: implementation, aliases, imports, and obsolete tests are deleted;
  historical evidence remains in documentation and Git.

States never advance from prose claims alone. Each transition records the
revision and commands that establish it. A regression moves the boundary back
to the last state supported by current evidence.

## Migration Ledger

The executable ledger belongs in the implementation plan or a dedicated
current backlog section, not in this design specification. Every row records:

| Field | Meaning |
|---|---|
| Boundary ID | Stable identifier such as `D3-canonical-fallback` |
| Legacy entry | Exact module, function, flag, import, or source route |
| Replacement | Exact new interface and owning module |
| Callers | Production, CLI, tests, scripts, and documentation consumers |
| State | One state from the migration state machine |
| Trigger task | A/B/C task or dedicated migration task that can advance it |
| Parity gate | Exact positive and negative verification commands |
| Removal condition | Observable condition, not a date |
| Evidence | Commit or reviewed range plus CI run when applicable |

The root `AGENTS.md` reports only the active migration slice and links to the
ledger. It must not duplicate the entire caller inventory.

## Coupling To The Current Program

| Current task | Required legacy action |
|---|---|
| A1 | Complete D1 isolation and add the first no-new-portable-Solana-grammar gate |
| A2 | Inventory direct product `ContractSpec` construction; introduce D2 replacement without switching existing defaults |
| A3 | Ensure `NFTSpec` has no target-dependent fields or branches |
| A4 | Classify target stdlib candidates as materializer implementations, not portable APIs |
| A5 | Require strict canonical and target-plan success for every accepted NFT materialization |
| A6 | Implement native target-first NFT dispatch; switch only the NFT family to the new default |
| B1 | Preserve NEAR behavior while replacing NEAR-named shared Wasm plan ownership |
| B2 | Advance D3 strict-gate replacement; do not silently preserve advisory success for promoted fragments |
| B3/C1/C2 | New promoted routes start on strict canonical planning and create no legacy fallback |

After A6, migration tasks for Counter, ValueVault, Token, and Remote are
scheduled individually. They do not need to wait for B/C, but each must satisfy
the same parity and default-switch gates.

## No-New-Legacy Enforcement

Each boundary receives a narrow regression check when its replacement becomes
ready. Prefer semantic or import-level checks over raw global text counts.
Where no structured check is practical, use a reviewed allowlist that includes
the exact path and deletion condition.

Initial enforcement targets are:

1. portable `Source` cannot parse Solana-only grammar;
2. new product modules do not branch on `targetId`;
3. new Surface v2 routes cannot request `.legacy` mode;
4. strict target gates cannot swallow adapter or builder failures;
5. native CLI operations do not call `newCommandArgsToLegacy`;
6. production modules do not add imports from `ProofForge.IR.Legacy`.

The checks freeze or shrink legacy surface area. They must not encode a false
zero target while legitimate compatibility consumers still exist.

## Parity And Switching Gates

A boundary can reach `parity_verified` only when its applicable evidence is
green:

- success behavior and state transitions;
- unsupported behavior and stable diagnostics;
- capability and HostOp requirements;
- artifact, metadata, schema, and client identity;
- target-plan structure where it is a public compiler contract;
- runtime evidence for product behavior;
- resource-budget evidence when the baseline already promises it.

Run the focused parity gate first, then `just product`. Run `just check` before
switching a cross-module default or removing a compatibility boundary. Live
gates that require unavailable tools are recorded as skipped and block only a
transition whose acceptance contract explicitly requires them.

Default switching and removal are separate commits. This makes rollback a
normal revert of the switch without reintroducing already-modified legacy code.

## Failure And Rollback Policy

- No fallback may turn an unsupported or invalid new-path request into a
  successful legacy artifact.
- During pre-switch comparison, differences fail the parity gate and leave the
  old default unchanged.
- After switching, the compatibility path may be invoked only by an explicit
  alias or parity test, never automatically after new-path failure.
- If a post-switch regression appears, revert the default-switch commit or fix
  the replacement. Do not add a hidden retry fallback.
- Removal occurs only after the switched default has passed the full repository
  gate on a reviewed revision.

## Documentation And Agent Protocol

Every state transition updates:

1. the migration ledger and current implementation plan;
2. `docs/implementation-backlog.md` when scheduling changes;
3. `docs/gate-status.md` when a phase criterion changes;
4. `docs/implementation-log.md` with revision and commands;
5. the root `AGENTS.md` checkpoint when the active or next task changes;
6. public CLI, target, or architecture documentation affected by the boundary.

Historical documents retain old names and routes as evidence but must be
marked historical. They do not count as live callers.

## Completion Definition

The program is complete when:

- all advertised product families enter through portable source or intent;
- primary target compilation is strict canonical planning with no automatic
  legacy fallback;
- target-first CLI commands dispatch natively;
- remaining `ContractSpec` consumers are documented compiler contracts or
  isolated fixtures, not accidental product coupling;
- production imports and public documentation contain no retired legacy
  routes;
- removal revisions pass focused parity, `just product`, `just check`, docs
  checks, and `git diff --check`.

Completion does not require erasing historical terminology from old commits,
archived documents, or explicit migration evidence.

## Non-Goals

- Rewriting all backends before shipping the NFT vertical slice.
- Deleting `ContractSpec` merely because it predates `IntentContract`.
- Preserving automatic legacy fallback as a reliability feature.
- Changing artifact behavior while performing a structural migration.
- Promoting research targets through legacy cleanup alone.
- Combining default switching and legacy deletion into one irreversible patch.
