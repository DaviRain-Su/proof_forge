# RFC 0014: Unified semantic lowering contract across backends

Status: **Draft**

Date: 2026-07-06

Builds on: [RFC 0003](0003-portable-ir-and-runtime.md) (portable IR),
[RFC 0004](0004-evm-semantic-plan.md) (EVM semantic plan),
[RFC 0005](0005-solana-sbpf-assembly-backend.md) (Solana sBPF backend).

## Summary

Each ProofForge target backend should lower portable IR through the same
**pipeline shape**:

```text
contract_source / ContractSpec
  -> ProofForge.IR.Module
  -> resolveCapabilities          -- shared, via Target.Adapter
  -> validateModule*              -- per-target checks + shared subset
  -> buildModulePlan*             -- inspectable target-semantic plan
  -> lowerToAst                   -- syntax AST (Yul / Wasm / sBPF / Psy / Leo)
  -> printer -> external toolchain
  -> buildArtifactMetadata        -- plan-driven
```

EVM already follows this shape end to end (`Backend/Evm/{Validate,Plan,Lower,IR}`,
gated by `just evm-plan` / `just evm-semantic-plan`, with a `Refinement` layer).
The other primary backends do not: **Solana** has only `validateCapabilities`
plus an implicit `LowerCtx`, **NEAR** has a rich `validateModule` but no plan
module, and **Psy** has a metadata-only `PsyModulePlan`.

This RFC proposes **Tier B unification**: align every primary backend on the
same *contract* (validate, plan, AST, smoke) without forcing a single global
`ModulePlan` type. Plan types stay per-target, as [RFC 0004](0004-evm-semantic-plan.md)
non-goals already require, because account/CPI, host-import, and circuit models
differ. The two adjacent tiers — shared IR operational semantics (Tier A) and
end-to-end refinement proofs (Tier C) — are scoped but not delivered by this RFC.

## Motivation

Enforcement today is uneven and, outside EVM, scattered:

| Backend | Validate | ModulePlan | Refinement | Semantic-plan CI gate |
|---|---|---|---|---|
| EVM | `Evm.Validate.lean` (~1.7k LOC) | `Evm.Plan.ModulePlan` incl. `ExprPlan`/`StmtPlan` | `Evm.Refinement` (`TraceObligation`, `YulSemantics`) | `just evm-plan`, `just evm-semantic-plan` |
| NEAR | `WasmNear/IR.validateModule` (rich) | **none** | `WasmNear/Refinement.lean` (strongest formal layer) | none (formal anchors in `Tests/NearWasmFormal.lean`) |
| Psy | `validateCapabilities` only | `PsyModulePlan` (storage/context/events/crosscalls — metadata-only) | differential `dargo execute` (FV-4) | `just psy-metadata*` |
| Solana | `validateCapabilities` only | **none** | **none** | none (behavioral: golden asm, Mollusk, surfpool/web3) |

The gap is most visible on Solana:

- `SbpfAsm.lowerModuleCore` opens with `validateCapabilities` (target profile
  check, V-GATE-SOLANA-05) and then immediately builds account schema, state
  layout, locals, scratch space, and allocator inside a `LowerCtx`.
- There is no `Solana/Plan.lean`. Account layout lives in `StateLayout.lean` and
  `buildModuleInputSchema`; CPI/PDA/sysvar lowering lives in `Extension.lean`
  (`ProgramExtensions.fromPlan`, `lowerPlan : Array AstNode`); manifest and IDL
  are emitted downstream from the same lowering.
- PDA validation in `Extension.lean` currently emits **comments** on missing
  account bindings, not a pre-lowering plan check.
- There is no `Solana/Refinement.lean` and no link from `Solana` to
  `ProofForge.IR.Semantics.lean`.

The consequence: on Solana, "semantic enforcement" is distributed across
diagnostics, golden asm, Mollusk, and surfpool/Web3 gates, with **no inspectable
plan artifact** that a reviewer, a golden test, or a refinement obligation can
hold. That asymmetry is not forced by portable IR — `IR.Semantics.lean` is
already chain-neutral — it is the result of each backend choosing its own
lowering shape.

Unifying the *contract* (not the plan algebra) makes three things possible:

1. Reviewable plan artifacts per backend, mirrored as `just *-semantic-plan`
   smokes analogous to `evm-semantic-plan`.
2. A place to hang cross-backend obligations from
   [`docs/formal-verification.md`](../formal-verification.md) workstream 25
   (FV-2 semantics growth, FV-8 ValueVault invariants).
3. A shared `validate` subset (identifiers, return paths, ownership hook) that
   every backend either delegates to or explicitly overrides, instead of each
   backend reinventing the same checks.

## Four tiers of "semantic unification"

| Tier | Meaning | Cost | In scope for this RFC? |
|---|---|---|---|
| **A** | Shared IR operational semantics (`IR/Semantics.lean`) is the ground truth; every backend passes shared-scenario trace obligations for the IR subset semantics currently covers. | Medium — semantics exists but must grow (FV-2/FV-3). | **No** (acknowledged dependency; tracked by FV workstream). |
| **B** | Shared lowering *contract*: per-backend `validateModule*` + `*ModulePlan` + `lowerToAst` + plan-driven metadata + golden `*-semantic-plan` smokes. | EVM done; Solana done; NEAR easy–medium (Phase 4 chosen first); Psy easy (deferred); Move-Sui hard (deferred). | **Yes.** |
| **C-diff** | Differential trace replay: the Quint MBT backend generates ITF traces from `IR.Semantics` and replays them against each backend's actual emitted artifact (bytecode via Foundry for EVM; Mollusk for Solana; offline-host for NEAR). Acts as a pragmatic substitute for a full target-chain formal semantics. | EVM landed (`just quint-evm-backend-replay-gate`); portable to any backend once its `*ModulePlan` exists. 2026-07-07 audit selected NEAR as the next candidate (see `docs/quint-cdiff-multi-backend-design.md`). | **Partial.** RFC 0014 consumes the Quint backend's traces for end-to-end smoke; it does not redesign the Quint backend itself. |
| **C-proof** | Machine-checked end-to-end refinement: Lean IR-semantics ⟷ formal target-chain execution model. | Hard. EVM can lean on `powdr-labs/evm-semantics` (a Lean EVM semantics passing `ethereum/tests`). Solana is research (FV-4): no off-the-shelf sBPF Lean semantics exists. | **No** (explicit non-goal). |

**Splitting the old Tier C into C-diff and C-proof is load-bearing.** It separates
"we can run the same scenario against the real chain and check the state
transitions agree" (Tier C-diff — engineering, broadly portable) from "we have a
machine-checked proof that the IR semantics and the target execution model agree
on every behavior" (Tier C-proof — research-grade, ecosystem-dependent).

### Role of the Quint verification backend

The Quint backend (`ProofForge/Backend/Quint/*`, see [`docs/quint.md`](../quint.md))
is the first ProofForge backend whose "artifact" is a **verification artifact**
rather than a deploy artifact. From portable IR it emits:

- A Quint state-machine model (`.qnt`) used by Apalache for `quint verify`
  model-checking of `quint_invariant` safety / `quint_liveness` temporal
  properties — Tier A invariants enforced upstream of every backend.
- MBT traces (ITF format via `quint run --mbt --out-itf`) that are replayed
  through `ProofForge.IR.Semantics` (`Tests/Quint/*Replay.lean`) — Tier A
  differential coverage that grows with the IR subset.
- EVM backend replay (`just quint-evm-backend-replay-gate`): the same ITF trace
  is lowered to a Foundry test and replayed against etched runtime bytecode —
  the current instantiation of **Tier C-diff for EVM**.

Concretely, this RFC's Tier B `*ModulePlan` artifacts are the **bridge** that
lets Tier C-diff scale beyond EVM: once a backend has an inspectable plan and
a stable artifact emitter, a `*-quint-backend-replay-gate` analogous to the EVM
one can replay Quint MBT traces against that backend's output (Mollusk for
Solana, offline-host for NEAR, `dargo execute` for Psy) without waiting for a
Lean formal model of the target VM to exist. Tier C-proof remains the path for
chains with mature Lean semantics (EVM via powdr-style integration); Tier
C-diff is the pragmatic floor for every other backend.

This RFC targets **Tier B only**. Tier A and Tier C-diff are acknowledged as
already-shipped dependencies (Quint backend, `IR/Semantics.lean`); Tier C-proof
remains a non-goal.

## Design goals

- Make every primary backend lower through **validate → plan → AST** with the
  plan being an **inspectable artifact**, not an ephemeral lowering context.
- Mirror EVM's smoke pattern (`just evm-plan`, `just evm-semantic-plan`) on Psy,
  NEAR, and Solana so a reviewer can diff plans, not just bytecode/asm.
- Extract the genuinely shared `validate` subset (identifiers, entrypoint
  return paths, unsupported-type-by-profile, ownership hook) so backends stop
  duplicating it.
- Preserve RFC 0004's boundary: target plan types are **target-specific**, not
  a single `ModulePlan` generic over all chains.
- Leave a clean seam for Tier A (shared semantics) and Tier C (refinement) to
  attach later without re-litigating the lowering boundary.

## Non-goals

- A single global `ModulePlan` type shared by all backends. RFC 0004 non-goals
  already rule this out; account/CPI, host-import, and circuit models differ.
- Machine-checked end-to-end refinement (Tier C-proof), including a Lean model
  of Solana syscalls or sBPF semantics, or wiring the EVM backend to
  `powdr-labs/evm-semantics`. Tier C-diff (differential trace replay via the
  Quint MBT backend) is in scope as a pragmatic substitute; Tier C-proof
  remains a non-goal.
- Redesigning the Quint verification backend. This RFC consumes its traces
  (Tier A and Tier C-diff for EVM); the Quint backend's own evolution is
  tracked separately under the Quint workstream.
- Proving external toolchains (`solc`, `sbpf`, `wat2wasm`, `dargo`, Mollusk).
  These remain outside the proof TCB per `docs/formal-verification.md`.
- Extending the contract to CosmWasm, Move (Sui/Aptos), Aleo, Cloudflare TS in
  the initial scope. Those may follow once the four primary backends are aligned.
- Replacing the existing AST printers or external tool invocations. The contract
  sits *above* the AST layer; printers stay as they are.
- Forcing every backend to grow EVM-shaped `ExprPlan`/`StmtPlan` body plans on
  day one. Body planning is backloaded (Phase 6) and only where it pays.

## Current state per backend

### EVM (reference stack)

- `ProofForge/Backend/Evm/Validate.lean` — type/shape/capability checks, init
  code, map-presence domain, event signature types.
- `ProofForge/Backend/Evm/Plan.lean` — `StorageLayout`, `EntrypointPlan`,
  `DispatchPlan`, `EventPlan`, crosscall/create specs, `MetadataPlan`, and the
  body-planning `ExprPlan` / `StmtPlan` that compose `ModulePlan`.
- `ProofForge/Backend/Evm/Lower.lean` — `buildModulePlan`,
  `buildFullModulePlan`, `buildFullModulePlanWithTargetPlan`.
- `ProofForge/Backend/Evm/IR.lean` — `buildSemanticPlan`,
  `lowerModuleWithPlan`, `renderSemanticPlan` (plan inspection).
- `ProofForge/Backend/Evm/{ToYul,Metadata,ConstructorInit}.lean` — plan → Yul
  AST and deploy/artifact metadata.
- `ProofForge/Backend/Evm/Refinement.lean` + `YulSemantics.lean` —
  `TraceObligation` over IR traces vs selector-dispatched Yul surface vs an
  executable Yul subset (Counter, ValueVault, Map/TypedStorage/StorageStruct/
  AbiAggregate/Conditional/Loop/Event probes).

CI: `just evm-plan` (`Tests/Backend/Evm/EvmPlan.lean`), `just evm-semantic-plan`
(`Tests/Backend/Evm/EvmSemanticPlan.lean`), and `lake build ProofForge.Backend.Evm.Refinement`
(theorems are `#check`-anchored from `Tests/NearWasmFormal.lean`).

**EVM audit (2026-07-07, RFC 0014 Tier B reference backend).** A mirror audit
of EVM was performed after Solana and NEAR completed their Step C, asking
whether EVM had any analogous inline `Ctx`-like derivation that bypasses
`Evm.Plan.ModulePlan` (the Step C dual-path pattern). **Finding: EVM is
already cleanly plan-only — no Step C refactor was needed.** The lowering
dispatch is `lowerModule module = lowerModuleWithPlan module (buildSemanticPlan module)`
(strict) and `lowerModuleBestEffort module = lowerModuleWithPlan module (buildSemanticPlanBestEffort module)`
(best-effort); both route through `lowerModuleWithPlan`. EVM has no `Ctx` /
`LowerCtx` struct at all — the plan is consumed directly. The
`lowerModule` vs `lowerModuleBestEffort` split (commit `06e57e12`) is
intentional strict-vs-best-effort, not a Step C dual-path: both go through a
plan. The internal best-effort fallbacks in `lowerModuleWithPlan`
(`lowerEntrypoint` / `dispatchBlock` when the plan's entrypoint/dispatch
arrays are incomplete) are also plan-routed — each builds an
`EntrypointPlan` / `DispatchPlan` via `Lower.buildEntrypointSurfacePlan` and
calls the corresponding `*WithPlan` function. There is no inline storage /
ABI / dispatch derivation duplicating the plan. EVM is the reference
implementation the other backends were aligned to; it never accumulated the
inline `Ctx` residue that Solana (`buildCtx`) and NEAR (inline `Ctx`
assembly) carried before their Step C. Full audit, call-site table, and
verification in
[`docs/multi-backend-moduleplan-design.md`](../multi-backend-moduleplan-design.md)
§14. `lake build` green; `just evm-plan` / `just evm-semantic-plan` /
`just evm-build-examples` pass; frozen EVM goldens unchanged.

### NEAR (validate-rich, plan-poor, formal-strong)

- `ProofForge/Backend/WasmHost/IR.lean` — `validateModule`: capabilities +
  identifiers + state + per-entrypoint param/return/type + return-path checks.
- `ProofForge/Backend/WasmHost/EmitWat.lean` — `checkTargetPlan` and a call to
  `IR.Ownership.checkModule` before render.
- `ProofForge/Backend/WasmHost/Refinement.lean` — richest formal layer: IR
  traces, WAT exports, Wasm AST host-boundary frames, offline-host Borsh/hex
  obligations; ValueVault invariant bridge.
- **No** `WasmNear/Plan.lean`. Lowering goes IR → Wasm AST inside `WasmNear/IR`
  after `validateModule`.

### Psy (partial EVM mirror — metadata only)

- `ProofForge/Backend/Psy/Plan.lean` — `PsyModulePlan`: storage shapes,
  context ops, events, crosscalls, test plan, capabilities. **No**
  `ExprPlan`/`StmtPlan`.
- `ProofForge/Backend/Psy/IR.lean` — `validateCapabilities`, `buildModulePlan`
  → `buildModuleWithPlan`.
- `ProofForge/Backend/Psy/{Metadata,MetadataJson}.lean` — plan-driven metadata.
- **No** refinement layer; differential `dargo execute` only (FV-4).

### Solana (the main gap)

- `ProofForge/Backend/Solana/SbpfAsm.lean` — `validateCapabilities` (target
  profile check) at the top of `lowerModuleCore`; the rest of lowering builds
  account schema, state offsets, locals, scratch, allocator inside `LowerCtx`.
  `lowerModule` uses an empty `ProgramExtensions {}`; `lowerModuleWithPlan`
  layers CPI/account extensions from a `CapabilityPlan`.
- `ProofForge/Backend/Solana/StateLayout.lean`, `Extension.lean` (with
  `ProgramExtensions.fromPlan` and `lowerPlan : Array AstNode`), `Manifest.lean`,
  `Idl.lean`, `Client.lean`, `Package.lean`, `Syscalls.lean`, `Register.lean`.
- **No** `Solana/Plan.lean`. **No** `Solana/Refinement.lean`. No `*-semantic-plan`
  gate; enforcement is behavioral (golden asm/manifest, Mollusk/testkit,
  surfpool/web3).

### Shared infrastructure

- `ProofForge/IR/Semantics.lean` — trace interpreter over scalars, fixed
  arrays, structs, storage (scalar/array/struct/path, map insert/set),
  `ifElse`, `boundedFor`, event-log; deterministic-by-construction theorems.
- `ProofForge/IR/Ownership.lean` — `checkModule` / `checkEntrypoint` over
  `release` and owned heap locals. **Only** NEAR/CosmWasm EmitWat paths call it
  today; EVM/Psy/Solana do not.
- `ProofForge/Target/Plan.lean` — `CapabilityPlan` (targetId + resolved
  capability calls). **Not** a semantic lowering plan.
- `ProofForge/Target/{Adapter,Registry,Check}.lean` — capability resolution,
  `TargetProfile`, `resolveModule` for IR-only emit.

## Detailed design

### Target lowering interface (contract, not typeclass)

Every primary backend exposes five stages. The contract is **prose + module
layout**, not a Lean typeclass — Lean typeclass encoding is an explicit
open question (see below) and is not required to land Tier B.

```text
resolveCapabilities : IR.Module -> Except Diagnostic CapabilityPlan
                  -- shared: Target.Adapter.defaultResolve + requireCapabilityPlan

validateModule*    : IR.Module -> Except Diagnostic Unit
                  -- shared subset (SharedValidate) + per-backend checks

buildModulePlan*   : IR.Module -> CapabilityPlan -> Except Diagnostic <Target>ModulePlan
                  -- inspectable artifact; pure; no AST construction

lowerToAst         : IR.Module -> <Target>ModulePlan -> Except LowerError <Target>.AST
                  -- plan-driven; pure; printers untouched

buildArtifactMetadata : <Target>ModulePlan -> ArtifactMetadata
                  -- plan-driven; consumed by CLI deploy/emit
```

Concretely per backend:

| Backend | `ModulePlan` type | Plan module | AST module |
|---|---|---|---|
| EVM | `Evm.Plan.ModulePlan` (exists) | `Backend/Evm/Plan.lean`, `Lower.lean` | `Compiler/Yul` |
| Psy | `Psy.Plan.PsyModulePlan` (exists, extend) | `Backend/Psy/Plan.lean`, `IR.lean` | `Lean.Compiler.Psy` |
| NEAR | `WasmNear.Plan.NearModulePlan` (**new**) | `Backend/WasmHost/Plan.lean` (**new**) | `Compiler/Wasm` |
| Solana | `Solana.Plan.SolanaModulePlan` (**new**) | `Backend/Solana/Plan.lean` (**new**) | `Solana/Asm.AstNode` |

### Per-backend plan type sketch

**EVM**: unchanged. `Evm.Plan.ModulePlan` remains the reference; body plans
(`ExprPlan`/`StmtPlan`) continue to grow per `docs/implementation-backlog.md`.

**Solana**: `SolanaModulePlan` covers, initially:

- `StorageAccountPlan` — account ordering, sizes, owner/signer/writable flags,
  derived from `StateLayout`.
- `EntrypointPlan` — 8-bit discriminator, parameter decode order, account
  bindings consumed.
- `InstructionDataPlan` — layout of the instruction byte stream (header,
  discriminator, args, length prefixes).
- `CpiPlan` — summary of cross-program invocations, PDA seeds, account
  dependencies (the artifact currently produced ad hoc by `Extension.lowerPlan`).
- `SyscallPlan` — summary of syscalls the body will invoke (`sol_log_`,
  `sol_memcpy_`, `sol_invoke_signed_`, return-data), used by manifest and CU
  estimation.
- `ManifestPlan` — linkage fields the manifest/IDL/client emitters read.

Body planning (`ExprPlan`/`StmtPlan` for Solana instructions) is **deferred**
to Phase 6; Phase 2 plans only the layout/dispatch/CPI/account schema.

**NEAR**: `NearModulePlan` covers:

- `ExportPlan` — Wasm function exports and selector/dispatch surface.
- `StorageKeyPlan` — `storage_{read,write}` key layout per state field.
- `HostImportPlan` — required NEAR host imports (`storage_*`, `log`, `sha256`,
  `account_id`, `block_height`, …) discovered from effects.
- `PromisePlan` (future) — crosscall lowering targets; today crosscall →
  Promise lowering is a documented EmitWat gap.

**Psy**: `PsyModulePlan` is extended **later** (Phase 6) toward entrypoint/body
plans; initial scope keeps the existing metadata-only plan and aligns the
`buildModulePlan` → `buildModuleWithPlan` seam to the shared contract.

### Shared validate subset

New module: `ProofForge/Backend/SharedValidate.lean` (landed in Phase 1).

**Phase 1 (landed) — genuinely byte-identical pure helpers.** Inventory of
EVM and NEAR validation found that only four helpers are truly duplicated with
identical signatures, rules, and diagnostic strings. These were extracted:

- `SharedValidate.ensureType` — type-mismatch formatter
  (`{context} expected \`{expected}\`, got \`{actual}\``). Was byte-identical
  across `Evm.Validate`, `Evm.IR`, `WasmNear.IR`, and `Psy.IR`.
- `SharedValidate.sharedParamBindings` — backs every backend's
  `entrypointTypeEnv` (param name → `LocalBinding`).
- `SharedValidate.statementAlwaysReturns` / `statementsAlwaysReturn` —
  control-flow return-path predicate (was duplicated *within* EVM between
  `Validate.lean` and `IR.lean`).
- `SharedValidate.checkOwnership` — documented opt-in stub wrapping
  `IR.Ownership.checkModule`. Not newly wired into any backend; NEAR/CosmWasm
  continue to call `IR.Ownership.checkModule` directly.

EVM (`Validate.lean`, `IR.lean`) and NEAR (`WasmNear/IR.lean`) now delegate to
`SharedValidate` for those helpers. Diagnostic strings are byte-identical to
pre-extraction behavior (pinned by `Tests/SharedValidate.lean`).

**Phase 1 finding — what is NOT safely extractable today.** The earlier prose
draft of this section listed "identifier validity, entrypoint return-path
checks, unsupported-type-by-profile, ownership hook" as the shared subset.
Implementation inventory showed these are **not** genuinely duplicated across
backends — they have per-backend signatures, rules, and messages:

- `validateCapabilities` — EVM calls `Target.resolveModule Target.evm`
  (returns `CapabilityPlan`); NEAR calls `requireCapabilities Target.wasmNear`
  (returns `Unit`). Different signatures and error-wrapping.
- **Return-path check** — EVM analyzes every control-flow path
  (`statementsAlwaysReturn`, message `"does not return on every control-flow
  path"`); NEAR uses `bodyEndsWithReturn` (syntactic last-statement check,
  message `"does not end with a return statement"`). Different rules and
  messages — unifying would churn NEAR diagnostics.
- Identifier validity — NEAR has Rust-identifier rules; EVM has no equivalent
  check.
- `ensureNumericType` — EVM returns a `ValueType` (supports U8); NEAR returns
  `Unit` (U32/U64 only). Not isomorphic.

Unifying these requires introducing a shared `Diagnostic` type and aligning
return-path semantics across backends first. That refactor is scoped to a
**Phase 2+ prerequisite** (see Open questions), not Phase 1. Phase 1 as landed
extracts the real duplication and leaves the rest per-backend — the conservative
outcome the diagnostic-stability constraint mandates.

Solana's `validateCapabilities` is retained in Phase 2 and augmented with the
shared helpers where they apply; it does not replace capability checking.

### Smoke gate pattern

Mirror EVM's twin gates on every aligned backend:

```text
just <target>-plan            -- layout/dispatch/metadata plan smokes
just <target>-semantic-plan   -- deeper: entrypoints, events, body plans where applicable
```

Plus a unified comparison entry:

```text
just semantic-plan-matrix     -- runs evm + psy + near + solana semantic-plan gates
```

Golden plan snapshots (Phase 7 stretch) would serialize plans to JSON for human
review; that is an open question, not a Phase 1–5 requirement.

## Phased rollout

Each phase is independently shippable and reverses cleanly. Phases 0–4 are
Tier B; Phase 5 begins the Tier C seam without delivering full proofs.

### Phase 0 — Lowering interface document (4–6 weeks)

**Milestones:**

- Publish `docs/target-lowering-interface.md`: required stages, per-target
  invariants (Solana: account-layout ↔ manifest ↔ asm consistency; EVM:
  plan.metadata ↔ `Metadata.lean`; NEAR: storage-key plan ↔ WAT exports;
  Psy: plan ↔ `MetadataJson`).
- Add a `LoweringStage` inductive stub in `ProofForge/Backend/Lowering.lean`
  (design-only; no behavior).

**Touch list:** `docs/`, `docs/rfcs/0014-…` (this RFC), optional
`ProofForge/Backend/Lowering.lean` stub.

**New recipes:** none (documentation only).

**Risks:** over-specifying a single `ModulePlan` type — explicitly avoided.

**Scope cut:** Lean typeclass encoding (open question).

### Phase 1 — Shared validate subset (landed 2026-07-06)

**Status:** Landed. Build green, tests green, diagnostics byte-identical.

**What was extracted (the genuinely duplicated pure helpers):**

- `ProofForge/Backend/SharedValidate.lean` (new) — `ensureType`,
  `sharedParamBindings`, `statementAlwaysReturns`/`statementsAlwaysReturn`,
  and a `checkOwnership` opt-in stub.
- EVM `Validate.lean` + `IR.lean` and NEAR `WasmNear/IR.lean` delegate to
  `SharedValidate` for those four helpers.
- `Tests/SharedValidate.lean` (12 cases) pins behavior and the exact
  `ensureType` diagnostic.
- `justfile`: `shared-validate-smoke` recipe added to `check`.

**What was NOT extracted (per-backend signatures/rules/messages differ):**

- `validateCapabilities`, return-path check, identifier validity,
  `ensureNumericType` — see "Shared validate subset" above for the full
  inventory of why each is not safely extractable without a shared
  `Diagnostic` type and return-path semantic alignment.

**Diagnostic stability:** unchanged. `Tests/SharedValidate.lean`'s
`testEnsureTypeMismatchMessage` pins `"probe expected \`U64\`, got \`U32\`"`.
No golden diagnostic test needed updating.

**Deferred to Phase 2+ prerequisite:** introduce a shared `Diagnostic` type
and align return-path semantics across backends so `validateCapabilities` and
the return-path check can be unified without churning NEAR diagnostics. This
is tracked as an Open question; it is not Phase 2 (SolanaModulePlan) work and
does not block it.

### Phase 2 — `SolanaModulePlan` + semantic-plan smoke (10–16 weeks)

**Milestones:**

- Add `ProofForge/Backend/Solana/Plan.lean` with `SolanaModulePlan` and the
  sub-plans above.
- Refactor `SbpfAsm.lowerModuleCore` so `LowerCtx` is **derived from the plan**,
  not built inline. Keep `lowerModuleWithPlan` for `CapabilityPlan` extensions.
- Add `Tests/Backend/Solana/SolanaSemanticPlan.lean` and `just solana-semantic-plan`,
  mirroring `evm-plan` (layout + entrypoint + manifest + CPI/account schema
  consistency).
- Step C (switch default) — **LANDED (2026-07-07).** The plan-driven path is the
  ONLY lowering path. The inline `buildCtx` that previously lived beside
  `SbpfAsm.lowerModuleCore` (deriving `stateFieldOffsets` via
  `buildStateOffsetsAtBase` and assembling `LowerCtx` field-by-field) is
  deleted; `lowerModuleCore` now derives its `LowerCtx` via
  `SbpfAsm.buildLowerCtx` → `SbpfAsm.LowerCtx.fromPlanSeed` (owned by `SbpfAsm`,
  which owns the `LowerCtx` type; `Solana.Plan.LowerCtx.fromSeed` delegates to
  it, keeping the import graph one-directional). The shared
  `lowerModuleCoreWithSeed` body is unchanged. The dual-path parity check that
  landed in Phase 2 is retired (there is no second path to agree with);
  `Tests/Backend/Solana/SolanaModulePlan.lean` is now a single-path regression gate (plan
  golden diff + `--render` confirms the plan-driven lowering still emits sBPF
  assembly, char count surfaced in CI logs). `scripts/solana/plan-smoke.sh`
  switches to `--render`. All `SbpfAsm.lowerModule`/`renderModule`/
  `lowerModuleWithPlan` call sites (Cli.lean, the nine `Tests/Solana*.lean`
  emission tests, `Package.renderPackageWithPlan`) now lower through the
  plan-derived `LowerCtx` automatically. Verification: `lake build` green;
  `just solana-plan-smoke` passes (4/4); `just solana-build-examples` passes
  (`Counter.s` matches frozen golden); `just solana-lean` and
  `just solana-emit-control` pass; frozen `.s` goldens
  (`Counter.golden.s`, `ValueVault.golden.s`) and all `plan.txt` goldens
  unchanged. Render char counts: Counter 3830, EvmStorageArrayProbe 6609,
  EvmMapProbe 4470, EvmStorageStructProbe 2707, confirming byte-stability.

  **EVM audit (2026-07-07, after Solana + NEAR Step C).** A mirror audit of
  EVM (the reference Tier B backend) confirmed EVM was already cleanly
  plan-only and needed no Step C refactor: `lowerModule` delegates to
  `lowerModuleWithPlan module (buildSemanticPlan module)`, EVM has no `Ctx` /
  `LowerCtx` struct, and the strict/best-effort split is plan-routed on both
  sides. EVM is the reference implementation Solana and NEAR were aligned to;
  it never carried the inline `Ctx` residue. Full finding in
  [`docs/multi-backend-moduleplan-design.md`](../multi-backend-moduleplan-design.md)
  §14.

**Touch list:**

- `ProofForge/Backend/Solana/Plan.lean` (new)
- `ProofForge/Backend/Solana/SbpfAsm.lean`, `StateLayout.lean`,
  `Manifest.lean`, `Idl.lean`, `Package.lean`
- `justfile`, `.github/workflows/ci.yml` (add to `solana-lean` family or `check`)

**Risks:** `SbpfAsm.lean` is ~1.7k LOC and feeds golden asm + Pinocchio
reference-equivalence gates; refactor must keep them byte-stable. Recommend
landing behind a feature flag (e.g. `--solana-plan=v2`) and switching after
golden parity is demonstrated.

**Scope cut:** body planning (`ExprPlan`/`StmtPlan` for Solana) → Phase 6.

### Phase 3 — Shared diagnostic contract (prerequisite, landed 2026-07-07)

**Status:** Stub landed 2026-07-07; follow-ups A (per-backend instances) and B
(`SharedValidate` migration) landed 2026-07-07. Build green, smoke green, no
existing diagnostic bytes changed.

**Motivation:** Phase 1 found that `validateCapabilities`, the return-path
check, identifier validity, and `ensureNumericType` could not be safely unified
because each backend's error type, rules, and messages differ. A shared
diagnostic vocabulary is the prerequisite for growing the shared validate
surface beyond the four Phase 1 pure helpers. This phase introduces it without
migrating any backend.

**What was landed (the minimal, safe stub):**

- `ProofForge/Backend/Diagnostic.lean` (new) — `LoweringDiagnostic`
  (`message` + optional `backend?` / `severity` / `code?` metadata),
  `Severity`, the `LoweringError` typeclass contract, two trivial adapters
  (`LoweringDiagnostic` identity, `String` for the `Except String` shape
  `SharedValidate` uses today), `fromTargetDiagnostic`, and `liftSharedError`.
- `Tests/Diagnostic.lean` (new, 9 cases) pins the byte-stability invariant:
  `LoweringDiagnostic.render` outputs **only** `message`, so any backend
  delegating to it sees byte-identical output to its existing
  `<Name>.render := err.message`.
- `justfile`: `diagnostic-smoke` recipe added to `check`.

**Design decision (shared type + typeclass, not typeclass-only):** a field-level
audit (see [`docs/shared-diagnostic-design.md`](../shared-diagnostic-design.md))
showed every backend lowering/plan/emit error type is *already* the same shape —
a single-field `structure <Name> where message : String` whose `render` is
`err.message`. A shared concrete type is therefore justified, not premature: a
typeclass-only contract would leave `SharedValidate` returning `Except String`
(the Phase 1 status quo), which is what this phase grows beyond. The optional
metadata fields do not participate in `render`, so they cannot perturb golden
diagnostics.

**What was NOT done (deferred follow-ups, explicitly tracked):**

- **Per-backend `LoweringError` instances — LANDED 2026-07-07 (follow-up A).**
  The three Tier-B-completed backends (EVM, Solana, NEAR) now carry trivial
  `LoweringError` adapter instances on all 8 concrete error types listed in the
  audit (`Evm.Validate.LowerError`, `Evm.IR.LowerError`, `Evm.Plan.PlanError`,
  `Solana.SbpfAsm.LowerError`, `Solana.Plan.PlanError`, `WasmNear.IR.LowerError`,
  `WasmNear.Plan.PlanError`, `WasmNear.EmitWat.EmitError`). Each instance is
  `toDiagnostic := fun e => { message := e.message, backend? := some
  "<backend>" }` and relies on the class default `render`. `Tests/Diagnostic.lean`
  was extended from 9 to 17 cases, asserting `LoweringError.toDiagnostic err
  |>.render` equals each backend's own `<Name>.render err` and the bare
  `message`. Remaining backends (Psy, CosmWasm, Aleo, Move, Quint) follow the
  same trivial pattern when their Tier-B work lands.
- **Migrating `SharedValidate` helpers to return
  `Except LoweringDiagnostic α` — LANDED 2026-07-07 (follow-up B).**
  `SharedError` is now an alias for `LoweringDiagnostic`. `ensureType` and
  `checkOwnership` construct `{ message := ... }` instead of returning a bare
  `String`; the message *text* is byte-identical. Callers (`Evm/Validate.lean`,
  `Evm/IR.lean`, `WasmNear/IR.lean`) were updated from `.error message =>
  .error { message := message }` to `.error diag => .error { message :=
  diag.message }`. `Tests/SharedValidate.lean` was adapted to pattern-match on
  `Except LoweringDiagnostic` and check `diag.message`; all 12 cases pass,
  including `testEnsureTypeMismatchMessage` which still pins the exact bytes.
- **Unifying `validateCapabilities` / the return-path check / identifier
  validity / `ensureNumericType`.** A shared `Diagnostic` type is a
  *prerequisite*, not a sufficient condition — the per-backend rules and
  messages must also be aligned first. Deferred to a later phase.

**Diagnostic stability:** unchanged. `Tests/Diagnostic.lean` pins
`LoweringDiagnostic.render` to the bare `message`. No backend's concrete
`render` was touched; no golden diagnostic test needed updating.

**Touch list (stub):**

- `ProofForge/Backend/Diagnostic.lean` (new)
- `Tests/Diagnostic.lean` (new)
- `justfile` (`diagnostic-smoke`, wired into `check`)
- `docs/shared-diagnostic-design.md` (new — field-level audit + design)
- `docs/rfcs/0014-…` (this RFC), `docs/zh/rfcs/0014-…` (translation sync)

**Touch list (follow-ups A + B, landed 2026-07-07):**

- `ProofForge/Backend/Evm/{Plan,Validate,IR}.lean` — `LoweringError` instances
  on `PlanError` / `LowerError` (×2); `Evm.Validate` / `Evm.IR` `ensureType`
  wrapper updated to fold `diag.message`.
- `ProofForge/Backend/Solana/{SbpfAsm,Plan}.lean` — `LoweringError` instances
  on `LowerError` / `PlanError`.
- `ProofForge/Backend/WasmHost/{IR,Plan,EmitWat}.lean` — `LoweringError`
  instances on `LowerError` / `PlanError` / `EmitError`; `WasmNear.IR`
  `ensureType` wrapper updated to fold `diag.message`.
- `ProofForge/Backend/SharedValidate.lean` — `SharedError` alias retargeted
  to `LoweringDiagnostic`; `ensureType` / `checkOwnership` construct
  `{ message := ... }`; module doc updated with Phase 3 migration note.
- `Tests/Diagnostic.lean` — extended from 9 to 17 cases (per-backend instance
  checks).
- `Tests/SharedValidate.lean` — harness adapted to `Except LoweringDiagnostic`;
  message bytes unchanged.
- `docs/shared-diagnostic-design.md`, `docs/rfcs/0014-…`,
  `docs/zh/rfcs/0014-…` — follow-ups A & B marked landed.

**Risks:** none for the stub (purely additive, no backend signature changes).
Follow-ups A & B risk golden churn if an adapter or the `SharedValidate`
migration accidentally changes a `s!"..."` interpolation; mitigated by the
extended `Tests/Diagnostic.lean` (instance-level byte pin) and
`testEnsureTypeMismatchMessage` (shared-helper byte pin), plus each backend's
plan/diagnostic golden suite. No golden bytes moved in practice (EVM/Solana/NEAR
plan smokes and the shared-validate smoke all pass).

**Scope cut:** migrating backends onto `LoweringDiagnostic` as their public
error type (i.e. replacing the concrete `LowerError` types entirely);
unifying the per-backend validation rules. Both remain follow-ups.

### Phase 4 — NEAR plan layer (8–12 weeks)

**Audit finding (2026-07-07).** An audit of the three candidate backends (NEAR, Psy,
Move-Sui) corrected the earlier "No `WasmNear/Plan.lean`" claim: `WasmNear.Plan.lean`
already exists and defines `ModulePlan` + `buildModulePlan` + `ModuleSurface`, and
`EmitWat.lowerModule` already consumes it to drive host imports and helper-function
pruning (gated by `Tests/Backend/Wasm/WasmNearPlan.lean` / `just wasm-near-plan`). The remaining gap
is narrower than Solana's was: the data-layout `Ctx` (scalar key pointers, map prefix
pointers, string pool, panic pool, crosscall string pool) is still built inline at the
top of `EmitWat.lowerModule` rather than plan-derived. The full audit, per-backend
feasibility table, field-level design, and migration path are in
[`docs/multi-backend-moduleplan-design.md`](../multi-backend-moduleplan-design.md).

**Chosen first candidate: NEAR.** The whole `Ctx` is plan-derived (no lowering-local
mutable state to split out, unlike Solana's `locals`/`nextLabel`/`allocator`), so the
migration is smaller than Phase 2 was. Psy and Move-Sui are deferred: Psy's
`PsyModulePlan` is already consumed and metadata-only (low payoff without body
planning, a Phase 6 product question), and Move-Sui is a Counter MVP spike with no
real lowering (a `SuiModulePlan` would have to precede building one).

**Milestones:**

- Step A (types only, additive) — **LANDED (commit 61cfa7a9).** Added
  `ProofForge/Backend/WasmHost/NearModulePlan.lean` with `NearModulePlan`,
  `NearLayoutPlan`, `NearLowerCtxSeed`, and a `buildNearModulePlan` for
  `ProofForge.IR.Examples.Counter.module`. Not wired into EmitWat. Added
  `Tests/NearModulePlan.lean`, `Examples/Backend/WasmNear/Counter/golden/plan.txt`,
  and `just near-plan-smoke` (mirroring `solana-plan-smoke`).
- Step B (plan construction + `Ctx.fromSeed`, additive) — **LANDED (2026-07-07).**
  Implemented `Ctx.fromPlanSeed` (reconstructs `EmitWat.Ctx` from the plan's seed +
  layout; the whole `Ctx` is plan-derived since NEAR has no lowering-local mutable
  state) and `lowerModuleFromPlan` (drives lowering by handing the reconstructed
  `Ctx` to a shared `EmitWat.lowerModuleCoreWithCtx` body extracted from the
  inline path, mirroring Solana's `lowerModuleCoreWithSeed`). The inline `Ctx`
  construction in `EmitWat.lowerModule` is kept (dual-path) until Step C. The
  `near-plan-smoke` gate now also runs a dual-path parity check: for `Counter`,
  plan-driven WAT and inline WAT must be byte-identical (asserted as `MATCH N
  chars`). Result: `Counter: MATCH 2228 chars`. `lake build`, `just
  wasm-near-plan`, and the frozen `Counter.golden.wat` are unaffected.
- Step B.2 (widen parity coverage to non-scalar state shapes) — **LANDED
  (2026-07-07).** Extended `Tests/NearModulePlan.lean` with a `moduleFor`
  resolver and three sub-module fixtures mirroring the Solana Phase 2
  array/map/struct probes: `EvmMapProbe` (map state, u64-keyed `balances`),
  `EvmStorageArrayProbe` (array state, `values` length 3),
  `EvmStorageStructProbe` (struct state, `current : Point`). Each sub-module
  only exercises lowering paths the NEAR backend already supports.
  `scripts/near/plan-smoke.sh` now loops over all four fixtures (Counter +
  three new), generating + diffing each plan golden and running the parity
  check per fixture. New golden `plan.txt` files added under
  `Examples/Backend/WasmNear/<Fixture>/golden/`. Parity results (plan-driven WAT ==
  inline WAT, byte-identical): `Counter: MATCH 2228 chars`, `EvmMapProbe:
  MATCH 3498 chars`, `EvmStorageArrayProbe: MATCH 4703 chars`,
  `EvmStorageStructProbe: MATCH 3375 chars`. Coverage now spans scalar / map /
  array / struct state shapes; the inline `Ctx` construction is still kept
  (dual-path) until Step C, which now has wide coverage evidence to lean on.
- Step C (switch default) — **LANDED (2026-07-07).** The plan-driven path is
  the ONLY lowering path. The inline ad-hoc `Ctx` assembly at the top of
  `EmitWat.lowerModule` is deleted; `lowerModule` now derives its `Ctx` via
  `EmitWat.buildLowerCtx` → `EmitWat.Ctx.fromPlanSeed` (owned by `EmitWat`,
  which owns the `Ctx` type; `NearModulePlan.Ctx.fromPlanSeed` delegates to
  it, keeping the import graph one-directional). The shared
  `lowerModuleCoreWithCtx` body is unchanged. `NearModulePlan.lowerModuleFromPlan`
  now runs the same `EmitWat.validateScratchCapacities` gate as the lowering
  entry, closing a Step B gap. The dual-path parity check is retired (there
  is no second path to agree with); `Tests/NearModulePlan.lean` is now a
  single-path regression gate (plan golden diff + `--render` confirms the
  plan-driven lowering still emits WAT, char count surfaced in CI logs).
  `WasmNear/Refinement.lean` reads the plan-driven output automatically via
  its existing `EmitWat.lowerModule` call sites (now plan-driven); no
  `Refinement.lean` code change was needed. Verification: `lake build` green;
  `just near-plan-smoke` passes (4/4); `just wasm-near-plan` passes; frozen
  WAT goldens and all `plan.txt` goldens unchanged; render char counts match
  Step B.2 parity results exactly (Counter 2228, EvmMapProbe 3498,
  EvmStorageArrayProbe 4703, EvmStorageStructProbe 3375), confirming
  byte-stability.

**Touch list:**

- Step A: `ProofForge/Backend/WasmHost/NearModulePlan.lean` (new),
  `Tests/NearModulePlan.lean` (new), `Examples/Backend/WasmNear/Counter/golden/plan.txt`
  (new), `scripts/near/plan-smoke.sh` (new), `justfile`.
- Step B: `ProofForge/Backend/WasmHost/NearModulePlan.lean` (`Ctx.fromPlanSeed`,
  `lowerModuleFromPlan`, `renderModuleFromPlan`; `NearStatePlan`/`NearMapPlan`
  now carry `ValueType` so the seed can rebuild `StateInfo`/`MapInfo`),
  `ProofForge/Backend/WasmHost/EmitWat.lean` (`lowerModuleCoreWithCtx` extracted
  from `lowerModule` to break the import cycle),
  `Tests/NearModulePlan.lean` (dual-path parity check), `scripts/near/plan-smoke.sh`
  (`--parity`), `justfile`.
- Step B.2: `Tests/NearModulePlan.lean` (`moduleFor` + `mapSubModule` /
  `arraySubModule` / `structSubModule`), `scripts/near/plan-smoke.sh`
  (multi-fixture loop), `Examples/Backend/WasmNear/{EvmMapProbe,EvmStorageArrayProbe,
  EvmStorageStructProbe}/golden/plan.txt` (new goldens).
- Step C: `ProofForge/Backend/WasmHost/EmitWat.lean` (`Ctx.fromPlanSeed` +
  `buildLowerCtx` added; inline `Ctx` assembly in `lowerModule` deleted;
  `lowerModule` now routes through the plan-derived `Ctx`),
  `ProofForge/Backend/WasmHost/NearModulePlan.lean` (`Ctx.fromPlanSeed`
  delegates to `EmitWat.Ctx.fromPlanSeed`; `lowerModuleFromPlan` runs
  `validateScratchCapacities`), `Tests/NearModulePlan.lean` (dual-path
  parity → single-path `--render` gate), `scripts/near/plan-smoke.sh`
  (`--parity` → `--render`). `ProofForge/Backend/WasmHost/Refinement.lean`
  is unchanged — its `EmitWat.lowerModule` call sites now lower through the
  plan-derived `Ctx` automatically.

**Risks:** WAT golden churn; offline-host smokes must remain byte-stable. Same
feature-flag strategy as Phase 2 (run both paths in CI, flip default after parity).

**Scope cut:** full Wasm instruction semantics in Lean (Tier C, deferred); the Rust
sourcegen path (`WasmNear/IR.lean`) is out of scope (a parallel lowering with no
`Ctx`); `ExportPlan` (one entry per entrypoint) deferred to Phase 4.2.

**Deferred backends:**

- **Psy** — `PsyModulePlan` already exists and is consumed by `Psy/IR.lean` via
  `BuildContext`; there is no `LowerCtx` to split. Extending the plan to cover
  entrypoint/body shapes (`ExprPlan`/`StmtPlan`) is a Phase 6 product decision, not a
  Phase 4 refactor.
- **Move-Sui** — a Counter MVP spike with no real lowering. A `SuiModulePlan` would
  have to precede building a real Move lowering (struct/entrypoint/state/capability
  plans), which is a Phase 6+ research item, not Phase 4.

### Phase 5 — Refinement seam (ongoing)

Phase 5 splits cleanly into two paths now that the Quint verification backend
exists as a Tier C-diff vehicle.

**Path 5a — Tier C-diff cross-backend rollout (engineering).**

A full per-backend feasibility audit, the abstract replay interface (generalizing
from `EvmReplay`), the field-level design for the chosen next candidate (NEAR), and
the deferred backends with rationale are in
[`docs/quint-cdiff-multi-backend-design.md`](../quint-cdiff-multi-backend-design.md).
Summary:

- **Current coverage (2026-07-07 audit):** EVM only (`EvmReplay.lean`,
  `just quint-evm-backend-replay-gate`). The replay interface is a pure Lean
  trace → harness renderer (`renderFoundryTest`) that lowers an ITF trace to a
  Solidity/Foundry test; the target toolchain (`forge`) executes it. The
  chain-neutral trace interpretation (`resolveActionName`, `buildArgs`,
  `entrypointMap`, `buildInitialState`, `compareStates`, `itfValueToIr`) lives
  in `Replay.lean` and is reused by every shim.
- **Chosen next candidate: NEAR.** The `runtime/offline-host` (wasmtime) is
  in-tree, needs no external RPC, and its CLI is a flat arg list
  (`run <wat> <exports...> --inputs-hex <...>`). A `NearReplay.lean` shim renders
  that arg list from the same ITF trace; the offline-host executes it. This is
  simpler than EVM (which renders a Solidity test file). A minimal type-only stub
  (`ProofForge/Backend/Quint/NearReplay.lean` + `Tests/Quint/NearReplaySmoke.lean`
  + `just quint-near-replay-smoke`) is landed in this step; it is **not** wired
  into CI. Step B (full `renderOfflineHostArgs`, the wrapping test that spawns
  `quint` + offline-host, the gate script, `just
  quint-near-backend-replay-gate`) is a follow-up.
- **Recommended order:** EVM (done) → NEAR (stub landed) → Solana (stub
  landed; Mollusk is in-tree as a Rust crate, `SolanaModulePlan` exposes the
  discriminator/account schema; the shim renders a Rust Mollusk test file) → Psy
  (3rd, blocked on `dargo` not installed here) → Move-Sui / Aleo / Cloudflare
  (deferred, research spikes with no real lowering).
- **Multi-module rendering (2026-07-07):** the three C-diff shims are no longer
  Counter-only. `EvmReplay` generalizes its mutating/read/init step rendering
  to encode entrypoint ABI args (Counter path byte-identical; ValueVault now
  renders). `NearReplay` generalizes its `init` branch to look up the module's
  `initialize` entrypoint and encode its args from the ITF nondet picks
  (previously hard-coded `("initialize", "")`; Counter path byte-identical),
  and its smoke now covers ValueVault. `SolanaReplay` routes its account list
  and state layout through the `SolanaModulePlan` (Tier B) instead of a
  hard-coded Counter account, and its smoke covers ValueVault (multi-scalar)
  and an `EvmMapProbe` map sub-module (non-scalar state, with a v1 degradation
  that skips byte-level account-data assertion). The smokes are pure
  string-render checks, not wired into `just check`. See
  `docs/quint-cdiff-multi-backend-design.md` §15.
- Mirror the existing `just quint-evm-backend-replay-gate` pattern on every
  backend once its `*ModulePlan` lands in Phase 2/4:
  - Solana: `just quint-solana-backend-replay-gate` — Quint MBT ITF trace →
    Mollusk invocation against the emitted `.so` (Tier C-diff; avoids needing a
    Lean sBPF semantics).
  - NEAR: `just quint-near-backend-replay-gate` — trace → offline-host
    wasmtime stub (already used by `scripts/near/emitwat-ci-smoke.sh`).
  - Psy: `just quint-psy-backend-replay-gate` — trace → `dargo execute`.
- Each gate consumes the same `IR.Semantics`-derived trace; only the replay
  harness differs per backend. The `*ModulePlan` is what makes the emitted
  artifact stable enough for trace-level differential testing.

**Path 5b — Tier C-proof feasibility (assessed 2026-07-07).**

A full feasibility assessment has been completed and is recorded in
[`docs/tier-c-proof-feasibility.md`](../tier-c-proof-feasibility.md). Summary of findings:

- **Current state is *not* a machine-checked refinement.** `Evm.Refinement.lean`
  and `ValueVaultInvariant.lean` discharge `native_decide` executable trace-equivalence
  checks on *fixed* scenarios (Counter, ValueVault, etc.), not universally-quantified
  simulation proofs. `ValueVaultInvariant.lean` checks the accounting invariant for the
  *default* inputs only, not for all `ScenarioInputs`.
- **Target semantics.** The preferred Lean 4 EVM formal model is now
  [`powdr-labs/evm-semantics`](https://github.com/powdr-labs/evm-semantics), which pins
  Lean `v4.31.0` plus `mathlib @ v4.31.0` and exposes a relational EVM bytecode
  semantics (`Step` / `Eval`) plus executable shadow `stepF`. It is a standalone
  semantics, not a refinement framework — the simulation obligation is ProofForge's.
  `EVMYulLean` remains a useful sibling/reference, but its v4.22 toolchain pin blocks it
  as ProofForge's primary dependency today.
- **Biggest blocker (IR side).** `IR.Semantics` is an interpreter
  (`runEntrypointWithArgs`), not a small-step `step : State → Option State` relation. A
  simulation proof requires an explicit step relation + induction principle. This is the
  first prerequisite and needs no new dependency.
- **Second blocker (target side).** The in-tree `Evm.YulSemantics` is a *pseudo*-Yul
  semantics (pseudo-keccak, simplified storage) not conformance-tested. A real Tier
  C-proof wants the `powdr-labs/evm-semantics` bytecode `Step` relation plus executable
  `stepF`, which means adding an opt-in `lake` dependency that pulls mathlib.
- **Storage layout bridging.** IR flat `State` vs EVM 256-bit storage slots is currently
  encoded only implicitly in the lowering; `Evm.Plan.ModulePlan` storage layout is the
  right place to make it explicit (a side-benefit of the Tier B work).

**Phased roadmap (replaces the previous "research seam" sketch):**

- **Phase 6a — Tighten `Evm.Refinement` to a real simulation (internal, no new dep).**
  Introduce `ProofForge/IR/StepSemantics.lean` with a small-step `step` relation;
  reformulate `irTraceOk` as an inductive `IRTraceMatches` predicate; prove soundness by
  induction (not `native_decide`). Keep existing `native_decide` theorems as regression smoke.
  Deliverable: first universally-quantified IR-side trace lemmas.
  **Status (2026-07-07): landed.** `ProofForge/IR/StepSemantics.lean` defines the generic
  inductive `IRTraceMatches` predicate (structurally recursive over the call list), a
  generic `runTraceListGen` runner, and `runTraceListGen_sound` discharged by
  `induction calls generalizing s` (NOT `native_decide`) — the first universally-quantified
  IR-side trace lemma. A `Decidable` instance on `IRTraceMatches` (via the iff bridge to
  `runTraceListGen`) lets `native_decide` re-prove the fixed-scenario theorems. Design
  choice (b): big-step induction over the call list (keep the existing big-step interpreter
  `runEntrypointWithArgs` as the atomic step; small-step `step` relation deferred to 6b+).
  `Evm.Refinement.lean` adds `counter_ir_trace_matches_inductive` and
  `value_vault_ir_trace_matches_inductive`, preserving the existing
  `counter_ir_observable_trace_ok` / `value_vault_ir_observable_trace_ok` as regression
  smoke. `Tests/IRStepSemantics.lean` + `just ir-step-semantics-smoke` (wired into
  `just check`) anchor the layer. See the Phase 6a "landed" note in
  [`docs/tier-c-proof-feasibility.md`](../tier-c-proof-feasibility.md).
- **Phase 6b — Integrate `powdr-labs/evm-semantics` as an opt-in EVM refinement target.**
  Add `powdr-labs/evm-semantics` as a pinned, opt-in `lake` dependency for EVM
  refinement modules only; keep the default build mathlib-free. Provide a thin opt-in
  adapter exposing powdr's `State` / `Step` / executable `stepF` aligned with
  `ObservableStep`. Deliverable: a conformance-gated EVM bytecode semantics callable
  from Lean proofs.
  **Status (2026-07-07): powdr target wired; Phase 6b unblocked.** The earlier
  `EVMYulLean` route was investigated and blocked by a Lean toolchain + mathlib version
  mismatch (`v4.22.0` vs ProofForge's `v4.31.0`). The refinement target is now
  `powdr-labs/evm-semantics`, pinned in `lakefile.lean` and `lake-manifest.json` behind
  the opt-in `EvmRefinement` target, so default `lake build` remains mathlib-free while
  `lake build EvmRefinement` imports the real `EvmSemantics` modules. The default-build
  seam in `ProofForge/Backend/Evm/EvmBytecodeSemantics.lean` remains a mathlib-free stub
  by design; the real wrapper is `EvmRefinement/PowdrAdapter.lean`, which exposes
  powdr-backed `State`, `Step`, `stepF`, `runBytecode`, and the `runBytecode_steps`
  bridge to powdr's relational `Steps`. The pinned powdr tree exposes bytecode semantics,
  not a Yul-level relation, so the Yul→bytecode `solc` step remains an explicit trust
  boundary. The canonical low-order lane now pins a solc 0.8.30 fixed Counter trace.
  Its universal theorem remains explicit about the open
  `CounterCompiledPowdrEntrypointObligations`; the former prepared-frame opcode proof
  is retained under `LegacyHighPacked` as historical evidence. See
  [tier-c-proof-feasibility.md §2](../tier-c-proof-feasibility.md).
- **Phase 6c — Prove IR → bytecode refinement for Counter.** Define the simulation relation
  `R : IR.State ↔ EVM.State` for the Counter module (single U64 scalar → one storage slot);
  prove `R`-simulation for `initialize`/`increment`/`get`; lift to a trace theorem by
  induction over the call list. Deliverable: first end-to-end machine-checked refinement.
- **Phase 6d — Extend to ValueVault (storage map + events).** Extend `R` to map IR map
  state to EVM storage slot prefixes (using `Evm.Plan.ModulePlan`); prove refinement for
  all seven entrypoints including event emission; prove
  `value_vault_accounting_invariant` universally quantified over `ScenarioInputs`.
  Deliverable: a universally-quantified contract invariant carried from IR to bytecode.
- **Phase 6e — Generalize the simulation framework.** Extract a reusable
  parametric `SimulationFramework` so the same pattern can in principle target Solana
  (Mollusk/Pinocchio) or NEAR (offline-host wasm). Note: Tier C-proof for non-EVM chains
  requires a formal target semantics for each, which does not exist today; this phase is
  exploratory and non-EVM chains remain in Tier C-diff until such semantics exist.

**Touch list (updated):**

- Path 5a: `scripts/quint/*-backend-replay-gate.sh` (new per backend),
  `ProofForge/Backend/Quint/{Solana,Near,Psy}Replay.lean` (new, mirroring
  existing `EvmReplay.lean`), `justfile` recipes. **Landed in this step
  (additive stub):** `ProofForge/Backend/Quint/NearReplay.lean`,
  `Tests/Quint/NearReplaySmoke.lean`, `just quint-near-replay-smoke` (not wired
  into `just check`). **Landed 2026-07-07 (Solana stub):**
  `ProofForge/Backend/Quint/SolanaReplay.lean`,
  `Tests/Quint/SolanaReplaySmoke.lean`, `just quint-solana-replay-smoke` (not
  wired into `just check` — running end-to-end needs SBF platform-tools not
  installed here per AGENTS.md). The Solana shim renders a Rust Mollusk test
  file (option (a) from the design doc — mirrors EVM's Solidity test rendering
  and the in-tree `Tests/solana/counter_mollusk.rs.tpl` template); the
  account-model translation (instruction discriminator via
  `Manifest.externalDiscriminatorBytes?` + single writable state account +
  little-endian instruction-data bytes) is the main extra work vs NEAR. See
  [`docs/quint-cdiff-multi-backend-design.md`](../quint-cdiff-multi-backend-design.md).
- Path 5b: `docs/tier-c-proof-feasibility.md` (new — landed this step).
  **Landed 2026-07-07 (Phase 6a):** `ProofForge/IR/StepSemantics.lean`,
  `Tests/IRStepSemantics.lean`, `just ir-step-semantics-smoke` (wired into `just check`),
  `ProofForge/Backend/Evm/Refinement.lean` bridge theorems
  (`counter_ir_trace_matches_inductive`, `value_vault_ir_trace_matches_inductive`).
  **Landed 2026-07-07 (Phase 6b):** `lakefile.lean`, `lake-manifest.json`,
  `ProofForge/Backend/Evm/EvmBytecodeSemantics.lean`,
  `EvmRefinement/PowdrAdapter.lean`, `EvmRefinement/CounterRefinement.lean`,
  and the opt-in powdr smoke gates wire `powdr-labs/evm-semantics` as the
  EVM refinement target while keeping the default build mathlib-free.
  **Next (Phase 6c):** discharge the current low-order runtime's
  `CounterCompiledPowdrEntrypointObligations` through reusable automation; do not
  extend the legacy prepared-frame proof by hand.

**Risks:** overstating what is "proven" — Path 5a is differential testing
(Tier C-diff), not a proof; Path 5b's current `Evm.Refinement`/`ValueVaultInvariant`
are `native_decide` executable checks, not machine-checked refinement. The phased
roadmap (6a–6e) is the concrete path to a real Tier C-proof, with 6a as the
no-new-dependency first step.

**Scope cut:** Tier C-proof for Solana (full syscall semantics in Lean — no
off-the-shelf formal sBPF semantics exists). Tier C-proof for NEAR/Psy likewise
deferred pending formal target semantics; they stay in Tier C-diff. Full
EVM conformance-suite coverage and all EVM opcodes are out of scope for this RFC —
conformance belongs to the external EVM semantics package; ProofForge only needs its
adapter and simulation proofs to be correct.

### Phase 6–7 (stretch)

- **Phase 6:** Psy body plans; Solana `ExprPlan`/`StmtPlan`; EVM completes
  `StmtPlan` ownership per `docs/implementation-backlog.md`.
- **Phase 7:** `.evm-plan.json` / `.solana-plan.json` / `.near-plan.json`
  snapshots for human review (RFC 0004 open question); consider Lean typeclass
  encoding of the lowering contract if Phase 0–5 shapes stabilize.

## Feasibility / difficulty

| Backend | Tier B difficulty | Why | Reuse from EVM? |
|---|---|---|---|
| EVM | Done | Reference stack. | N/A |
| Solana | Medium–hard (landed on `main`) | New `AccountPlan`/`InstructionDataPlan`/`CpiPlan`; `LowerCtx` → plan-derived refactor in a ~1.7k-LOC module with byte-stable golden gates. | Helper/event plan *patterns*; account/syscall plans are new. |
| NEAR | Easy–medium (Phase 4 first candidate) | `WasmNear.Plan.ModulePlan` already exists and is consumed by `EmitWat` (drives host imports/helpers); the remaining gap is externalizing the data-layout `Ctx` into plan fields, and the whole `Ctx` is plan-derivable with no lowering-local mutable state to split. See `docs/multi-backend-moduleplan-design.md`. | Plan-driven metadata + helper-discovery pattern. |
| Psy | Easy (seam alignment; deferred) | `PsyModulePlan` exists and is consumed; no `LowerCtx` to split. Extending to body planning is a Phase 6 product decision. | Metadata + storage-shape plan ideas. |
| Move-Sui | Hard (research; deferred) | Counter MVP spike with no real lowering; a `SuiModulePlan` must precede building a real Move lowering, a Phase 6+ item. | None. |
| CosmWasm | Medium (later) | Clone NEAR split. | NEAR > EVM. |

**Dependencies:**

1. FV-2 IR semantics growth (Tier A) — needed for Phase 5 obligations to cover
   more than scalars + fixed aggregates.
2. FV-3 ownership rules — Phase 1 ownership hook depends on ownership being
   sound for the IR subset in scope.
3. `Target.resolveModule` / diagnostics — already in place
   (V-GATE-SOLANA-05, EVM/Psy `validateCapabilities`).
4. Testkit shared scenarios (`testkit/scenarios/*.toml`) — accepted oracles for
   Tier A/B cross-backend parity.

## Alternatives considered

- **Clone EVM `ModulePlan` verbatim into every backend.** Rejected: RFC 0004
  non-goals explicitly keep target plan types target-specific; account/CPI,
  host-import, and circuit models are not isomorphic to storage slots + ABI
  selectors. This RFC carries the same boundary forward.
- **Formal-only unification via a Lean typeclass.** Deferred: the typeclass
  encoding is plausible once Phase 0–5 shapes stabilize, but locking it in
  before Solana/NEAR plans exist risks premature abstraction. Tracked as an
  open question for Phase 7.
- **Status quo.** Rejected: on Solana, enforcement is scattered across
  diagnostics, golden asm, Mollusk, and surfpool/Web3 with no inspectable plan.
  That makes review harder, blocks Tier A/C attachment, and leaves Solana as
  the only primary backend without a `*-semantic-plan` gate.

## Risks

- **`SbpfAsm.lean` refactor regression.** Mitigation: feature flag
  `--solana-plan=v2`, golden-parity gate before switch.
- **Diagnostic message churn.** Phase 1 moves shared checks; golden diagnostic
  snapshots must update together. Mitigation: single PR per backend, CI red
  is loud.
- **WAT golden churn on NEAR.** Same mitigation; Phase 4 is gated by
  offline-host smoke parity.
- **RFC 0004 boundary drift.** This RFC must not be read as "every backend
  adopts EVM's plan types". The non-goals section is explicit.
- **CI time growth.** New `*-semantic-plan` gates add lean-only smokes; they
  replace nothing but are cheap. `just semantic-plan-matrix` is opt-in for
  reviewers, not added to `just check` until costs are measured.
- **Premature abstraction.** Phase 0 stays documentation; Phase 1 is the
  smallest reversible extraction (shared validate). If Phase 1 lands cleanly,
  Phase 2/4 proceed; if not, the RFC is revisited before Solana/NEAR work.

## Drawbacks

- Upfront engineering cost (Phase 2 alone is 10–16 weeks) before user-visible
  payoff. The payoff is reviewer-facing (inspectable plans, golden smokes) and
  formal-facing (refinement seam), not a new product capability.
- Risk of premature abstraction if the contract is over-specified before
  Solana/NEAR plans exist. Mitigated by backloading Lean typeclass encoding to
  Phase 7.

## Open questions

- Should plan artifacts be serialized to JSON for human review (Phase 7
  stretch)? RFC 0004 leaves this open; this RFC inherits the question.
- Should CosmWasm follow the NEAR split now or after Phase 4 lands?
- Should the lowering contract be encoded as a Lean typeclass, and if so, at
  which stage (Phase 0 stub vs Phase 7 stable shape)?
- Should `just semantic-plan-matrix` be part of `just check`, `just ci`, or a
  separate reviewer-only entry?
- **Phase 2+ prerequisite — shared Diagnostic type.** Phase 1 inventory showed
  that `validateCapabilities`, the return-path check, identifier validity, and
  `ensureNumericType` cannot be safely unified today because EVM and NEAR use
  different signatures, rules, and diagnostic strings. Should a shared
  `Diagnostic` type be introduced (with per-backend wrappers) so these checks
  can be unified in a later phase without churning existing golden diagnostic
  output? This does not block Phase 2 (SolanaModulePlan) or Phase 4 (NEAR plan)
  but is required before the "shared validate" surface can grow beyond the four
  pure helpers landed in Phase 1.

  **Resolution (2026-07-07, Phase 3 stub landed):** yes — introduce a shared
  concrete `LoweringDiagnostic` type *plus* a `LoweringError` typeclass contract
  in `ProofForge.Backend.Diagnostic`. A field-level audit (see
  [`docs/shared-diagnostic-design.md`](../shared-diagnostic-design.md)) showed
  every backend lowering/plan/emit error type is already the same shape — a
  single-field `structure <Name> where message : String` whose `render` is
  `err.message` — so a shared concrete type is justified, not premature. The
  shared `render` outputs **only** `message`, so backends delegating to it see
  byte-identical output; the optional `backend?` / `severity` / `code?` fields
  are metadata for the CLI report layer and do not participate in `render`.
  Backends keep their concrete error types and implement the typeclass with a
  trivial adapter; `SharedValidate`'s `SharedError = String` is not migrated in
  the stub. This unblocks the "shared validate surface grows beyond Phase 1"
  goal as a follow-up (after per-backend adapter instances land), but does not
  by itself unify `validateCapabilities` / the return-path check / identifier
  validity / `ensureNumericType` — those still require aligning the per-backend
  rules and messages first. See the "Phase 3 — Shared diagnostic contract"
  subsection below.

## Future work

- **Tier A:** grow `IR/Semantics.lean` per FV-2/FV-3 so shared-scenario trace
  obligations cover map/storage/events for every aligned backend.
- **Tier C-diff:** generalize the Quint backend replay harness beyond EVM
  (Solana via Mollusk, NEAR via offline-host, Psy via `dargo execute`) as each
  backend's `*ModulePlan` lands. Long-term goal: one
  `just quint-<target>-backend-replay-gate` per primary backend. Audit +
  abstract replay interface + field-level `NearReplay` design + minimal
  additive stub landed 2026-07-07; see
  [`docs/quint-cdiff-multi-backend-design.md`](../quint-cdiff-multi-backend-design.md). A per-backend
  feasibility audit and the abstract replay interface are recorded in
  [`docs/quint-cdiff-multi-backend-design.md`](../quint-cdiff-multi-backend-design.md);
  NEAR is the chosen next candidate (stub landed), Solana is 2nd (stub landed,
  Rust Mollusk test rendering), Psy is 3rd
  (tool-blocked), Move-Sui/Aleo/Cloudflare are deferred (research spikes). Audit (2026-07-07)
  chose NEAR as the next candidate; a type-only `NearReplay.lean` stub landed.
  A type-only `SolanaReplay.lean` stub (rendering a Rust Mollusk test file,
  option (a)) landed 2026-07-07.
  See [`docs/quint-cdiff-multi-backend-design.md`](../quint-cdiff-multi-backend-design.md)
  for the per-backend feasibility table, the abstract replay interface, and the
  field-level `NearReplay` (§7) and `SolanaReplay` (§8.1) designs.
- **Tier C-proof:** continue the opt-in EVM proof lane now pinned to
  `powdr-labs/evm-semantics`: finish the Counter per-entrypoint powdr `Step`
  obligations and universal trace lift, then extend the same shape beyond
  Counter. Deepen `WasmNear.Refinement`; add `Solana.Refinement` beyond the
  Phase 5 Counter seam toward syscall-aware obligations once a target semantics
  exists.
- **Plan JSON snapshots** for cross-backend plan diffing in CI.
- **Lean typeclass** for the lowering contract once Phase 0–5 shapes are
  proven.

## References

- [RFC 0002](0002-target-implementation-design.md) — target profiles and
  backend implementation design.
- [RFC 0003](0003-portable-ir-and-runtime.md) — portable IR, capability
  lowering, runtime profiles.
- [RFC 0004](0004-evm-semantic-plan.md) — EVM semantic plan and Yul AST
  boundary (the reference shape this RFC generalizes).
- [RFC 0005](0005-solana-sbpf-assembly-backend.md) — Solana sBPF assembly
  backend.
- [`docs/portable-ir.md`](../portable-ir.md) — shared pipeline diagram.
- [`docs/formal-verification.md`](../formal-verification.md) — FV-1..FV-8
  (FV-2 semantics growth, FV-4 Psy differential, FV-8 ValueVault invariants).
- [`docs/validation-gates.md`](../validation-gates.md),
  [`docs/gate-status.md`](../gate-status.md) — P0-2 EVM semantic-plan status.
- `ProofForge/Backend/Evm/{Validate,Plan,Lower,IR,Refinement,YulSemantics}.lean`
- `ProofForge/Backend/WasmHost/{IR,EmitWat,Refinement}.lean`
- `ProofForge/Backend/Psy/{Plan,IR,Metadata}.lean`
- `ProofForge/Backend/Solana/{SbpfAsm,StateLayout,Extension,Manifest,Idl,Package}.lean`
- `ProofForge/IR/{Semantics,Ownership}.lean`
- `ProofForge/Target/{Plan,Adapter,Registry,Check}.lean`
- `Tests/{EvmPlan,EvmSemanticPlan,NearWasmFormal,IROwnership,SolanaDiagnostics,PsyMetadata}.lean`
