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
| **B** | Shared lowering *contract*: per-backend `validateModule*` + `*ModulePlan` + `lowerToAst` + plan-driven metadata + golden `*-semantic-plan` smokes. | EVM done; Psy easy–medium; NEAR medium; Solana medium–hard. | **Yes.** |
| **C-diff** | Differential trace replay: the Quint MBT backend generates ITF traces from `IR.Semantics` and replays them against each backend's actual emitted artifact (bytecode via Foundry for EVM; Mollusk for Solana; offline-host for NEAR). Acts as a pragmatic substitute for a full target-chain formal semantics. | EVM landed (`just quint-evm-backend-replay-gate`); portable to any backend once its `*ModulePlan` exists. | **Partial.** RFC 0014 consumes the Quint backend's traces for end-to-end smoke; it does not redesign the Quint backend itself. |
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
  day one. Body planning is backloaded (Phase 5) and only where it pays.

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

CI: `just evm-plan` (`Tests/EvmPlan.lean`), `just evm-semantic-plan`
(`Tests/EvmSemanticPlan.lean`), and `lake build ProofForge.Backend.Evm.Refinement`
(theorems are `#check`-anchored from `Tests/NearWasmFormal.lean`).

### NEAR (validate-rich, plan-poor, formal-strong)

- `ProofForge/Backend/WasmNear/IR.lean` — `validateModule`: capabilities +
  identifiers + state + per-entrypoint param/return/type + return-path checks.
- `ProofForge/Backend/WasmNear/EmitWat.lean` — `checkTargetPlan` and a call to
  `IR.Ownership.checkModule` before render.
- `ProofForge/Backend/WasmNear/Refinement.lean` — richest formal layer: IR
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
| NEAR | `WasmNear.Plan.NearModulePlan` (**new**) | `Backend/WasmNear/Plan.lean` (**new**) | `Compiler/Wasm` |
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
to Phase 5; Phase 2 plans only the layout/dispatch/CPI/account schema.

**NEAR**: `NearModulePlan` covers:

- `ExportPlan` — Wasm function exports and selector/dispatch surface.
- `StorageKeyPlan` — `storage_{read,write}` key layout per state field.
- `HostImportPlan` — required NEAR host imports (`storage_*`, `log`, `sha256`,
  `account_id`, `block_height`, …) discovered from effects.
- `PromisePlan` (future) — crosscall lowering targets; today crosscall →
  Promise lowering is a documented EmitWat gap.

**Psy**: `PsyModulePlan` is extended **later** (Phase 5) toward entrypoint/body
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

Golden plan snapshots (Phase 6 stretch) would serialize plans to JSON for human
review; that is an open question, not a Phase 1–4 requirement.

## Phased rollout

Each phase is independently shippable and reverses cleanly. Phases 0–3 are
Tier B; Phase 4 begins the Tier C seam without delivering full proofs.

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
- Add `Tests/SolanaSemanticPlan.lean` and `just solana-semantic-plan`,
  mirroring `evm-plan` (layout + entrypoint + manifest + CPI/account schema
  consistency).

**Touch list:**

- `ProofForge/Backend/Solana/Plan.lean` (new)
- `ProofForge/Backend/Solana/SbpfAsm.lean`, `StateLayout.lean`,
  `Manifest.lean`, `Idl.lean`, `Package.lean`
- `justfile`, `.github/workflows/ci.yml` (add to `solana-lean` family or `check`)

**Risks:** `SbpfAsm.lean` is ~1.7k LOC and feeds golden asm + Pinocchio
reference-equivalence gates; refactor must keep them byte-stable. Recommend
landing behind a feature flag (e.g. `--solana-plan=v2`) and switching after
golden parity is demonstrated.

**Scope cut:** body planning (`ExprPlan`/`StmtPlan` for Solana) → Phase 5.

### Phase 3 — NEAR plan layer (8–12 weeks)

**Milestones:**

- Add `ProofForge/Backend/WasmNear/Plan.lean` (`NearModulePlan`).
- `EmitWat` consumes the plan: `validateModule` → `buildModulePlan` →
  `lowerToAst` (mirroring EVM's `lowerModuleWithPlan`).
- Add `Tests/NearSemanticPlan.lean` and `just near-semantic-plan`.
- `WasmNear/Refinement.lean` consumes the plan where it currently re-derives
  exports/imports.

**Touch list:**

- `ProofForge/Backend/WasmNear/Plan.lean` (new), `EmitWat.lean`, `IR.lean`
- `ProofForge/Backend/WasmNear/Refinement.lean`

**Risks:** WAT golden churn; offline-host smokes must remain byte-stable. Same
feature-flag strategy as Phase 2.

**Scope cut:** full Wasm instruction semantics in Lean (Tier C, deferred).

### Phase 4 — Refinement seam (ongoing)

Phase 4 splits cleanly into two paths now that the Quint verification backend
exists as a Tier C-diff vehicle.

**Path 4a — Tier C-diff cross-backend rollout (engineering).**

- Mirror the existing `just quint-evm-backend-replay-gate` pattern on every
  backend once its `*ModulePlan` lands in Phase 2/3:
  - Solana: `just quint-solana-backend-replay-gate` — Quint MBT ITF trace →
    Mollusk invocation against the emitted `.so` (Tier C-diff; avoids needing a
    Lean sBPF semantics).
  - NEAR: `just quint-near-backend-replay-gate` — trace → offline-host
    wasmtime stub (already used by `scripts/near/emitwat-ci-smoke.sh`).
  - Psy: `just quint-psy-backend-replay-gate` — trace → `dargo execute`.
- Each gate consumes the same `IR.Semantics`-derived trace; only the replay
  harness differs per backend. The `*ModulePlan` is what makes the emitted
  artifact stable enough for trace-level differential testing.

**Path 4b — Tier C-proof seam (research).**

- Add `ProofForge/Backend/Solana/Refinement.lean` skeleton: Counter IR trace
  obligation against the selector-dispatched asm surface (no full sBPF
  semantics).
- Wire `Tests/NearWasmFormal.lean` to import Solana obligations when non-empty
  (CI build-gated).
- EVM: investigate projecting `Evm.Refinement.TraceObligation` onto an
  external Lean EVM semantics (e.g. `powdr-labs/evm-semantics`, which passes
  the official `ethereum/tests` conformance suites) instead of
  `Evm.YulSemantics`'s in-tree executable Yul subset. This is a research
  integration; the seam is sketched here, not delivered.
- Link [`docs/formal-verification.md`](../formal-verification.md) FV-8
  (ValueVault invariants) to per-backend obligations.

**Touch list:**

- Path 4a: `scripts/quint/*-backend-replay-gate.sh` (new per backend),
  `ProofForge/Backend/Quint/{Solana,Near,Psy}Replay.lean` (new, mirroring
  existing `EvmReplay.lean`), `justfile` recipes.
- Path 4b: `ProofForge/Backend/Solana/Refinement.lean` (new),
  `Tests/NearWasmFormal.lean`,
  `ProofForge/Contract/Examples/ValueVaultInvariant.lean`.

**Risks:** overstating what is "proven" — Path 4a is differential testing
(Tier C-diff), not a proof; Path 4b remains a seam (Counter/ValueVault trace
shape), not Tier C-proof completeness.

**Scope cut:** Tier C-proof for Solana (full syscall semantics in Lean).

### Phase 5–6 (stretch)

- **Phase 5:** Psy body plans; Solana `ExprPlan`/`StmtPlan`; EVM completes
  `StmtPlan` ownership per `docs/implementation-backlog.md`.
- **Phase 6:** `.evm-plan.json` / `.solana-plan.json` / `.near-plan.json`
  snapshots for human review (RFC 0004 open question); consider Lean typeclass
  encoding of the lowering contract if Phase 0–4 shapes stabilize.

## Feasibility / difficulty

| Backend | Tier B difficulty | Why | Reuse from EVM? |
|---|---|---|---|
| EVM | Done | Reference stack. | N/A |
| Psy | Easy–medium | `PsyModulePlan` exists; extend + align seam. | Metadata + storage-shape plan ideas. |
| NEAR | Medium | Strong `validateModule` already; refactor is about extracting plan from `EmitWat`/`IR`. | Plan-driven metadata pattern. |
| Solana | Medium–hard | New `AccountPlan`/`InstructionDataPlan`/`CpiPlan`; `LowerCtx` → plan-derived refactor in a ~1.7k-LOC module with byte-stable golden gates. | Helper/event plan *patterns*; account/syscall plans are new. |
| CosmWasm | Medium (later) | Clone NEAR split. | NEAR > EVM. |

**Dependencies:**

1. FV-2 IR semantics growth (Tier A) — needed for Phase 4 obligations to cover
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
  encoding is plausible once Phase 0–4 shapes stabilize, but locking it in
  before Solana/NEAR plans exist risks premature abstraction. Tracked as an
  open question for Phase 6.
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
- **WAT golden churn on NEAR.** Same mitigation; Phase 3 is gated by
  offline-host smoke parity.
- **RFC 0004 boundary drift.** This RFC must not be read as "every backend
  adopts EVM's plan types". The non-goals section is explicit.
- **CI time growth.** New `*-semantic-plan` gates add lean-only smokes; they
  replace nothing but are cheap. `just semantic-plan-matrix` is opt-in for
  reviewers, not added to `just check` until costs are measured.
- **Premature abstraction.** Phase 0 stays documentation; Phase 1 is the
  smallest reversible extraction (shared validate). If Phase 1 lands cleanly,
  Phase 2/3 proceed; if not, the RFC is revisited before Solana/NEAR work.

## Drawbacks

- Upfront engineering cost (Phase 2 alone is 10–16 weeks) before user-visible
  payoff. The payoff is reviewer-facing (inspectable plans, golden smokes) and
  formal-facing (refinement seam), not a new product capability.
- Risk of premature abstraction if the contract is over-specified before
  Solana/NEAR plans exist. Mitigated by backloading Lean typeclass encoding to
  Phase 6.

## Open questions

- Should plan artifacts be serialized to JSON for human review (Phase 6
  stretch)? RFC 0004 leaves this open; this RFC inherits the question.
- Should CosmWasm follow the NEAR split now or after Phase 3 lands?
- Should the lowering contract be encoded as a Lean typeclass, and if so, at
  which stage (Phase 0 stub vs Phase 6 stable shape)?
- Should `just semantic-plan-matrix` be part of `just check`, `just ci`, or a
  separate reviewer-only entry?
- **Phase 2+ prerequisite — shared Diagnostic type.** Phase 1 inventory showed
  that `validateCapabilities`, the return-path check, identifier validity, and
  `ensureNumericType` cannot be safely unified today because EVM and NEAR use
  different signatures, rules, and diagnostic strings. Should a shared
  `Diagnostic` type be introduced (with per-backend wrappers) so these checks
  can be unified in a later phase without churning existing golden diagnostic
  output? This does not block Phase 2 (SolanaModulePlan) or Phase 3 (NEAR plan)
  but is required before the "shared validate" surface can grow beyond the four
  pure helpers landed in Phase 1.

## Future work

- **Tier A:** grow `IR/Semantics.lean` per FV-2/FV-3 so shared-scenario trace
  obligations cover map/storage/events for every aligned backend.
- **Tier C-diff:** generalize the Quint backend replay harness beyond EVM
  (Solana via Mollusk, NEAR via offline-host, Psy via `dargo execute`) as each
  backend's `*ModulePlan` lands. Long-term goal: one
  `just quint-<target>-backend-replay-gate` per primary backend.
- **Tier C-proof:** deepen `Evm.Refinement` and `WasmNear.Refinement`; add
  `Solana.Refinement` beyond the Phase 4 Counter seam toward syscall-aware
  obligations. Evaluate integrating an external Lean EVM semantics such as
  `powdr-labs/evm-semantics` as the target execution model for the EVM
  refinement obligations (replacing or augmenting the in-tree
  `Evm.YulSemantics` executable subset).
- **Plan JSON snapshots** for cross-backend plan diffing in CI.
- **Lean typeclass** for the lowering contract once Phase 0–4 shapes are
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
- `ProofForge/Backend/WasmNear/{IR,EmitWat,Refinement}.lean`
- `ProofForge/Backend/Psy/{Plan,IR,Metadata}.lean`
- `ProofForge/Backend/Solana/{SbpfAsm,StateLayout,Extension,Manifest,Idl,Package}.lean`
- `ProofForge/IR/{Semantics,Ownership}.lean`
- `ProofForge/Target/{Plan,Adapter,Registry,Check}.lean`
- `Tests/{EvmPlan,EvmSemanticPlan,NearWasmFormal,IROwnership,SolanaDiagnostics,PsyMetadata}.lean`
