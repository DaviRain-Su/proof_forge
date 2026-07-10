# Target lowering interface

Status: **Current (PF-P1-06 refresh)** — stage contract + live module map

Date: 2026-07-10 (originally 2026-07-06 Phase 0 design)

Promotion contract (PF-P1-06): **`IR → target Plan → typed AST → printer/package`**.
Unsupported AST nodes must return structured errors (never comment placeholders).
Primary triad CLI dispatch is registry-backed (`TargetBackend` / `TargetCliDriver`);
per-target plan **types** stay non-isomorphic (RFC 0004 / 0014).

Related audit: [Multi-chain Vision Gap Audit (2026-07-10)](multi-chain-gap-audit-2026-07-10.md).

Related: [RFC 0014](rfcs/0014-unified-semantic-lowering-contract.md) (the
contract this page elaborates), [RFC 0004](rfcs/0004-evm-semantic-plan.md)
(EVM plan boundary), [RFC 0003](rfcs/0003-portable-ir-and-runtime.md)
(portable IR), [portable IR](portable-ir.md), [formal
verification](formal-verification.md), [validation
gates](validation-gates.md).

## Purpose

This page defines the lowering **contract** every primary ProofForge backend
(EVM, Solana, NEAR, Psy) is being aligned onto under [RFC 0014](rfcs/0014-unified-semantic-lowering-contract.md)
Tier B. It is *not* an API or a typeclass: it is a prose + module-layout
contract that names the stages each backend must expose, the invariants each
plan type must satisfy, and the smoke gate that lets reviewers and CI hold
the plan to bytecode/asm equivalence.

The contract preserves [RFC 0004](rfcs/0004-evm-semantic-plan.md)'s
explicit non-goal: **plan TYPES stay per-target**. There is no single global
`ModulePlan` shared across EVM, Solana, NEAR, and Psy. Account/CPI
(Solana), host-import (NEAR), and circuit (Psy) models are not isomorphic
to EVM storage slots + ABI selectors, and this page does not pretend they
are. What is unified is the *shape* of the lowering, not its algebra.

The design stub in [`ProofForge/Backend/Lowering.lean`](../ProofForge/Backend/Lowering.lean)
documents these stages as an inductive `LoweringStage`; encoding the
contract as a Lean typeclass is explicitly deferred to Phase 6 (see
[Open questions](#open-questions)).

## The five stages

Every primary backend lowers an `IR.Module` through this pipeline (copied
verbatim from [RFC 0014](rfcs/0014-unified-semantic-lowering-contract.md)):

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

Each stage is specified below. Signatures are **Lean-like pseudocode**, not
real implementations — they document the contract shape. Real signatures
live in the per-backend modules cited inline.

### 1. `resolveCapabilities` — shared, `Target.Adapter`

```lean
-- Pseudocode — the real entry lives in ProofForge/Target/Adapter.lean.
resolveCapabilities :
  IR.Module -> Except Target.Diagnostic Target.CapabilityPlan
```

- **Location:** `ProofForge/Target/Adapter.lean` (`defaultResolve`,
  `requireCapabilityPlan`, `resolveSpec`, `resolveModule`) and
  `ProofForge/Target/Registry.lean` (`TargetProfile`).
- **What it does:** folds the `IR.Module`'s capability calls into a
  `CapabilityPlan` (target id + resolved capability calls + metadata) and
  rejects any call whose capability is not in the target's
  `TargetProfile.capabilities`, plus the D-027 target-extension-isolation
  check (Solana-only metadata on a non-`.solana` profile fails).
- **Must NOT:** make target-semantic decisions (account layout, storage
  slots, host imports, selectors). `CapabilityPlan` is a *capability
  routing* artifact, not a semantic lowering plan — see
  `ProofForge/Target/Plan.lean`.

### 2. `validateModule*` — shared subset + per-backend

```lean
-- Pseudocode — combines a future SharedValidate with a per-backend check.
validateModule* : IR.Module -> Except <Target>.LowerError Unit
```

- **Shared subset (Phase 1, `ProofForge/Backend/SharedValidate.lean`):**
  identifier validity, entrypoint return-path checks (non-unit returns must
  end in `return`), unsupported-type-by-profile (delegates to
  `Target.resolveModule` / `TargetProfile` so each backend still owns its
  type whitelist), and an optional ownership hook into
  `ProofForge/IR/Ownership.lean` `checkModule`.
- **Per-backend subset:** EVM owns ABI/storage slot validity
  (`ProofForge/Backend/Evm/Validate.lean`); NEAR owns param/return/type
  checks (`WasmNear/IR.lean` `validateModule`); Solana owns account
  well-formedness (today only `validateCapabilities` in `SbpfAsm.lean`);
  Psy owns capability re-check + Psy-specific shapes.
- **Must NOT:** construct AST. Validation may annotate the module; the plan
  pass consumes annotations.

### 3. `buildModulePlan*` — inspectable pure artifact

```lean
-- Pseudocode — real return type is per-target (EVM: Evm.Plan.ModulePlan,
-- Solana: Solana.Plan.SolanaModulePlan, NEAR: WasmHost.Plan.ModulePlan /
-- NearModulePlan, etc.).
buildModulePlan* :
  IR.Module -> Target.CapabilityPlan -> Except <Target>.<Error> <Target>ModulePlan
```

- **What it does:** produces the target-semantic plan — storage layout,
  dispatch surface, entrypoint metadata, events, crosscalls, host imports,
  CPI/PDA/account schema, syscall summary — depending on backend. **Pure.
  No AST construction.**
- **EVM reference:** `ProofForge/Backend/Evm/Plan.lean`
  (`buildModulePlan`, `buildModulePlanWithTargetPlan`) and
  `ProofForge/Backend/Evm/Lower.lean` (`buildFullModulePlan`,
  `buildFullModulePlanWithTargetPlan`). The plan type is
  `ProofForge.Backend.Evm.Plan.ModulePlan`.
- **Solana reference (landed):** `ProofForge/Backend/Solana/Plan.lean`
  (`SolanaModulePlan`, `buildSolanaModulePlan`, `lowerModuleFromPlan`).
- **NEAR reference (landed):** `ProofForge/Backend/WasmHost/Plan.lean`
  (`ModulePlan`, `buildModulePlan`) and `NearModulePlan.lean`
  (`NearModulePlan`, `buildNearModulePlan`). CLI production still primarily
  drives through `EmitWat.lowerModule` + plan surface helpers.
- **Must NOT:** render Yul/Wasm/sBPF text, allocate stack slots that depend
  on lowering-local state, or call the external toolchain.

### 4. `lowerToAst` — plan-driven, pure

```lean
-- Pseudocode — AST module is per-target (Yul.Object / Wasm.Module /
-- Solana.Asm.AstNode / Psy.Module).
lowerToAst :
  IR.Module -> <Target>ModulePlan -> Except <Target>.LowerError <Target>.AST
```

- **EVM reference:** `ProofForge/Backend/Evm/IR.lean`
  `lowerModuleWithPlan` (consumes `Evm.Plan.ModulePlan` →
  `Lean.Compiler.Yul.Object`).
- **Solana reference (current):** `ProofForge/Backend/Solana/SbpfAsm.lean`
  `lowerModuleCore` / `lowerModule` / `lowerModuleWithPlan`, plus
  `Solana/Plan.lean` `lowerModuleFromPlan` for plan-driven paths. Generic
  CLI still often seeds `LowerCtx` from IR + `CapabilityPlan`; full plan
  dominance is ongoing (see [Solana deep-dive](#solana-deep-dive)).
- **NEAR reference (current):** `ProofForge/Backend/WasmHost/EmitWat.lean`
  `lowerModule` builds `WasmHost.Plan.ModulePlan` then lowers to Wasm AST.
  `NearModulePlan` exists for inspectable NEAR-specific facts.
- **Must NOT:** make new target-support decisions (anything that reaches
  this pass is assumed valid for the target), re-discover facts already on
  the plan, or invoke the printer/toolchain. **Must NOT** print comment
  placeholders for unsupported AST nodes (PF-P1-06; Leo printer is fail-closed).

### 5. `buildArtifactMetadata` — plan-driven

```lean
-- Pseudocode.
buildArtifactMetadata : <Target>ModulePlan -> ArtifactMetadata
```

- **EVM reference:** `ProofForge/Backend/Evm/Metadata.lean` and the
  `MetadataPlan` field of `Evm.Plan.ModulePlan`.
- **Psy reference:** `ProofForge/Backend/Psy/{Metadata,MetadataJson}.lean`
  consume `PsyModulePlan`.
- **Solana reference (current):** `ProofForge/Backend/Solana/{Manifest,Idl,Client,Package}.lean`
  re-derive linkage fields from the lowered AST today. Phase 2 routes them
  through the plan.
- **Must NOT:** parse rendered Yul/sBPF/WAT to recover facts the plan
  already carries.

## Per-backend invariants

| Backend | Current plan module | Current validate path | AST module | Required invariants the plan must satisfy | Status (2026-07-10) |
|---|---|---|---|---|---|
| **EVM** | `Backend/Evm/Plan.lean` (`ModulePlan`), `Lower.lean` (`buildFullModulePlan`) | `Backend/Evm/Validate.lean`, `TargetBackend.validateModule` | `Compiler/Yul.Object` | `plan.metadata` ↔ `Backend/Evm/Metadata.lean`; storage slots unique and stable; selector ↔ ABI param count; helper set ⊆ plan-discovered specs; crosscall/create specs deterministic | **Reference / production** |
| **NEAR** | `Backend/WasmHost/Plan.lean` (`ModulePlan`), `NearModulePlan.lean` | EmitWat production path + `TargetBackend` hooks (align with EmitWat, not Rust-sourcegen-only `IR.validateModule`) | `Compiler/Wasm.Module` via EmitWat | storage-key / host-import surface ↔ WAT; ownership hook before WAT; nested mapKey supported in EmitWat | **Plan modules landed**; CLI driver still EmitWat-centric |
| **Psy** | `Backend/Psy/Plan.lean` (`PsyModulePlan`) | `Psy/IR.lean` `validateCapabilities` | `Compiler.Psy.Module` | plan ↔ `Psy/MetadataJson.lean`; storage shape plan deterministic | **Plan + metadata**; body-plan depth varies |
| **Solana** | `Backend/Solana/Plan.lean` (`SolanaModulePlan`) + `StateLayout` / `Extension` / `SbpfAsm` | `SbpfAsm.validateCapabilities` + plan builders | `Solana.Asm.AstNode` | account-layout ↔ manifest ↔ asm; PDA/CPI bindings stable; syscall summary ↔ `sol_*` | **Plan module landed**; generic CLI still mixes plan + LowerCtx |
| **Leo** | IR → Leo AST (`Compiler/Leo`) | Printer fail-closed (PF-P1-06): no `/* nand */` placeholders | `Compiler/Leo.AST` | unsupported ops → `Except LowerError` | **Sourcegen spike**; printer honesty fixed |
| **Move / CosmWasm / TS Workers** | string / spike emitters | capability / fixture gates | sourcegen | Counter/fixture honesty; not primary-triad production drivers | **Spike / MVP** (see registry `TargetSupport`) |

EVM remains the reference shape. Solana/NEAR plan **modules exist** on `main`;
remaining work is making every CLI path consume the same plan instance that
goldens assert (not “plans are nonexistent”).

## Solana deep-dive

This is the hardest backend to align and the user's stated focus. Solana
lowering is currently scattered across:

- `ProofForge/Backend/Solana/SbpfAsm.lean` (~1.7k LOC) — the IR → sBPF AST
  entrypoint. Opens with `validateCapabilities` (V-GATE-SOLANA-05), then
  builds account schema, state offsets, locals, scratch space, and an
  allocator inside `LowerCtx`. `lowerModuleCore` is the partial driver;
  `lowerModule` uses an empty `ProgramExtensions {}`;
  `lowerModuleWithPlan` layers CPI/account extensions from a
  `CapabilityPlan` via `ProgramExtensions.fromPlan` and
  `Extension.lowerProgramExtensionsWithBindings`.
- `ProofForge/Backend/Solana/StateLayout.lean` — serialized account input
  layout (`AccountInputLayout`, `InputLayout`, `computeInputLayout`,
  `computeAccountLayoutAt`, `computeInputLayoutWithReallocFlags`).
- `ProofForge/Backend/Solana/Extension.lean` — `AccountMeta`,
  `DeclaredAccount`, `PdaDerive`/`PdaSeed`/`PdaSeedKind`, `CpiInvoke`,
  `MemoryOp`, `CryptoHashOp`, `SysvarKind`, `ProgramExtensions.fromPlan`,
  `lowerPlan : CapabilityPlan -> Array AstNode`.
- `ProofForge/Backend/Solana/{Manifest,Idl,Client,Package}.lean` —
  downstream manifest/IDL/client/package emitters that re-derive linkage
  fields from the lowered AST.
- `ProofForge/Backend/Solana/{Syscalls,Register,Asm}.lean` — syscall
  symbol table, register bookkeeping, AST/printer.

The plan is to introduce `ProofForge/Backend/Solana/Plan.lean` with a
`SolanaModulePlan` that absorbs the inspectable facts currently rebuilt
inside `lowerModuleCore`, so that `LowerCtx` becomes **derived from the
plan** instead of built inline. Concrete mapping:

| Current Solana artifact | Will live in `SolanaModulePlan` as |
|---|---|
| `StateLayout.computeInputLayout` / `computeInputLayoutWithReallocFlags` / `AccountInputLayout` | `StorageAccountPlan` — account ordering, per-account byte sizes, owner/signer/writable/executable flags, data-start offsets, realloc reserve flags, rent epoch offsets |
| `SbpfAsm.buildModuleInputSchema` (`ModuleInputSchema`, `AccountEntry`, `buildInstructionsWithExtensions`, `buildDefaultAccounts`) | `InstructionDataPlan` — instruction byte stream layout (header, discriminator, args, length prefixes) + account ordering consumed by the dispatch switch |
| `SbpfAsm.buildStateCpiValueBindings` / `buildEntrypointParamCpiValueBindings` / `buildCpiValueBindings` | `InstructionDataPlan` (argument decode offsets) and feeds `CpiPlan` account/value bindings |
| `Extension.ProgramExtensions` + `ProgramExtensions.fromPlan` + `Extension.lowerPlan` (`lowerPlan : CapabilityPlan -> Array AstNode`) | `CpiPlan` — cross-program invocations, PDA seeds (`PdaDerive`/`PdaSeed`), account dependencies, signed flags; replaces the ad hoc `Array AstNode` artifact with an inspectable summary |
| `SbpfAsm` dispatcher (`jeq r2, idx, sol_<ep>`) + entrypoint lowering | `EntrypointPlan` — 8-bit discriminator, parameter decode order, account bindings consumed per entrypoint |
| `Syscalls.lean` symbol usage (`sol_log_`, `sol_memcpy_`, `sol_invoke_signed_`, `sol_sha256_`, `sol_keccak256_`, `sol_blake3_`, return-data syscalls, sysvar reads) discovered during body lowering | `SyscallPlan` — summary of syscalls the body will invoke, consumed by manifest and compute-unit (CU) estimation |
| `Manifest.lean` / `Idl.lean` / `Client.lean` / `Package.lean` re-derivation | `ManifestPlan` — linkage fields the manifest/IDL/client/package emitters read directly, instead of re-deriving from the lowered AST |

### `LowerCtx` field disposition

The `LowerCtx` struct in `SbpfAsm.lean` (lines 78–87) is currently the de
facto plan. Phase 2 splits it:

```lean
-- Current LowerCtx (ProofForge/Backend/Solana/SbpfAsm.lean)
structure LowerCtx where
  stateFieldOffsets : Array (String × Nat)   -- plan-derived
  structs         : Array StructDecl          -- plan-derived (type metadata)
  stateDecls      : Array StateDecl           -- plan-derived (type metadata)
  locals          : Array LocalSlot           -- lowering-local
  nextLocalOffset : Nat                       -- lowering-local
  scratchOffset   : Nat                       -- lowering-local
  nextLabel       : Nat                       -- lowering-local
  allocator       : Allocator                 -- lowering-local
```

| `LowerCtx` field | Becomes |
|---|---|
| `stateFieldOffsets` | **plan-derived** — lives on `StorageAccountPlan` as state field byte offsets; emitted as `.equ <STATE>_DATA <off>` constants deterministically from the plan |
| `structs` | **plan-derived** — type metadata carried on the plan so `structFieldOffset` / `structByteSize` lookups are stable |
| `stateDecls` | **plan-derived** — source-of-truth for `arrayStateElementType?` / `isOwnedHeapBacked` decisions |
| `locals` | **lowering-local** — stack slot allocation is a lowering concern; the plan describes data layout, not register/stack temporaries |
| `nextLocalOffset` | **lowering-local** — allocator state |
| `scratchOffset` | **lowering-local** — scratch region is a lowering concern (used by syscall argument marshalling) |
| `nextLabel` | **lowering-local** — label generation is a rendering concern |
| `allocator` | **lowering-local** — heap/cpi allocator state |

The split keeps the plan inspectable (reviewers can diff
`StorageAccountPlan` between releases) while leaving stack/label/allocator
bookkeeping inside `lowerModuleCore` where it belongs.

### Byte-stability constraint

`SbpfAsm.lean` feeds **byte-stable golden asm** and the **Pinocchio
reference-equivalence gate** (`just solana-pinocchio-reference-equivalence`,
part of `just solana-light`). Any refactor that changes emitted `.s` text
for existing examples breaks the golden files and the Pinocchio gate.

The Phase 2 refactor must keep the golden asm and Pinocchio gates green
byte-for-byte. To make this safe, [RFC 0014](rfcs/0014-unified-semantic-lowering-contract.md)
Phase 2 recommends landing the plan-driven lowering behind a feature flag
such as `--solana-plan=v2`, with the v1 (`lowerModuleCore` inline) path
preserved, and switching the default only after a golden-parity gate
demonstrates that v2 emits identical asm. The new
`just solana-semantic-plan` smoke (below) must assert layout + manifest +
asm consistency against the *same* plan artifact, not a re-derived one.

### Non-goal: Solana body planning

`ExprPlan`/`StmtPlan` for Solana instruction bodies (mirroring EVM's body
plan from [RFC 0004](rfcs/0004-evm-semantic-plan.md)) is **explicitly
deferred to Phase 5**. Phase 2 plans only layout/dispatch/CPI/account
schema/syscall summary. Body lowering continues to run inside
`lowerEntrypoint` driven by a `LowerCtx` whose plan-derived fields come
from `SolanaModulePlan`. This bounds Phase 2 to the
10–16 week estimate in RFC 0014 instead of ballooning into a full EVM-shaped
rewrite.

## Shared validate subset

Phase 1 landed `ProofForge/Backend/SharedValidate.lean` with the **four
genuinely byte-identical pure helpers** that EVM and NEAR duplicate today:

- `SharedValidate.ensureType` — type-mismatch formatter (was duplicated across
  `Evm.Validate`, `Evm.IR`, `WasmNear.IR`, `Psy.IR`).
- `SharedValidate.sharedParamBindings` — backs every backend's
  `entrypointTypeEnv`.
- `SharedValidate.statementAlwaysReturns` / `statementsAlwaysReturn` —
  control-flow return-path predicate (was duplicated within EVM).
- `SharedValidate.checkOwnership` — opt-in stub wrapping
  `ProofForge/IR/Ownership.lean` `checkModule`. NEAR/CosmWasm continue to call
  `checkModule` directly; not newly wired into EVM/Psy/Solana.

**Phase 1 finding (important):** the checks that this document's earlier draft
listed as the shared subset — *identifier validity, entrypoint return-path,
unsupported-type-by-profile, ownership hook* — are **not** safely extractable
today. They have per-backend signatures, rules, and diagnostic strings:

- `validateCapabilities` differs in signature (EVM returns `CapabilityPlan`,
  NEAR returns `Unit`).
- The return-path check differs in both rule and message: EVM analyzes every
  control-flow path (`"does not return on every control-flow path"`); NEAR
  checks the last statement syntactically (`"does not end with a return
  statement"`). Unifying would churn NEAR diagnostics.
- Identifier validity is NEAR-only (Rust identifier rules); EVM has no
  equivalent.
- `ensureNumericType` returns `ValueType` on EVM (supports U8) vs `Unit` on
  NEAR (U32/U64 only).

Unifying these requires a shared `Diagnostic` type and return-path semantic
alignment, tracked as a Phase 2+ prerequisite in RFC 0014 Open questions. It
does not block Phase 2 (SolanaModulePlan) or Phase 3 (NEAR plan).

What stays **per-backend** regardless:

- EVM: storage slot uniqueness, ABI param/return type restrictions,
  crosscall/create modes, checked-arithmetic detection
  (`Evm.Validate.moduleUsesCheckedArithmetic`).
- NEAR: per-entrypoint param/return/type restrictions
  (`validateEntrypointParameters`, `validateEntrypointReturn`,
  `validateEntrypointTypes`), host-import type rules.
- Solana: account well-formedness, PDA seed well-formedness
  (`Extension.lean` `PdaSeedKind`), CPI account-binding consistency.
- Psy: Psy capability re-check and storage-shape rules.

EVM `Evm.Validate.lean` and NEAR `WasmNear/IR.validateModule` **delegate**
the shared checks to `SharedValidate`. Solana's `validateCapabilities` is
**retained and augmented**: Phase 2 adds the shared subset alongside it; it
does not replace capability checking (V-GATE-SOLANA-05 stays).

## Smoke gate pattern

Mirror EVM's twin gates on every aligned backend. EVM today:

```text
just evm-plan            # lake build ProofForge.Backend.Evm.Plan + Tests/Backend/Evm/EvmPlan.lean
just evm-semantic-plan   # Tests/Backend/Evm/EvmSemanticPlan.lean — entrypoints, events, body plans
```

(from the `justfile`: `evm-plan` builds `ProofForge.Backend.Evm.Plan` and
runs `Tests/Backend/Evm/EvmPlan.lean`; `evm-semantic-plan` builds
`ProofForge.Backend.Evm.IR` plus the IR example probes and runs
`Tests/Backend/Evm/EvmSemanticPlan.lean`).

Future recipes once each phase lands:

```text
just solana-semantic-plan   # Phase 2 — see below
just near-semantic-plan     # Phase 3
just psy-semantic-plan      # Phase 5 (body plans)
just semantic-plan-matrix   # opt-in reviewer entry: runs all four
```

### `just solana-semantic-plan` (Phase 2)

Should build `ProofForge.Backend.Solana.Plan` and run a new
`Tests/Backend/Solana/SolanaSemanticPlan.lean` that asserts:

- **Plan consistency:** `SolanaModulePlan.StorageAccountPlan` matches the
  account layout produced by `StateLayout.computeInputLayoutWithReallocFlags`
  for every example in `Examples/Backend/Solana/`.
- **Layout stability:** state field byte offsets (`.equ <STATE>_DATA`)
  match the golden asm constants byte-for-byte.
- **Manifest ↔ asm agreement:** `ManifestPlan` account ordering, sizes, and
  flags match both the manifest JSON (`Manifest.lean` output) and the
  emitted asm's account pointer setup (`lowerInstructionDataPointerSetup`,
  `lowerAccountPtrTableSetup`).
- **CPI schema:** `CpiPlan` PDA seeds and account dependencies match the
  nodes emitted by `Extension.lowerProgramExtensionsWithBindings`.
- **Byte stability:** the asm produced by the plan-driven v2 path is
  byte-identical to the v1 `lowerModuleCore` path for every example, OR the
  diff is intentional and the golden asm + Pinocchio gates are updated in
  lockstep.

### `just near-semantic-plan` (Phase 3)

Asserts `NearModulePlan.ExportPlan` ↔ WAT exports,
`StorageKeyPlan` ↔ emitted `storage_{read,write}` keys, and
`HostImportPlan` ↔ effects discovered in the IR body. Offline-host smokes
(`Tests/NearWasmFormal.lean`) must stay byte-stable.

### `just semantic-plan-matrix`

Opt-in reviewer entry, **not** in `just check` initially (per RFC 0014
risk: CI time growth). Runs all four `*-semantic-plan` gates. Promotion
into `just check` is an open question for Phase 6.

Golden plan snapshots (`.solana-plan.json`, `.near-plan.json`) for human
review are a Phase 6 stretch (RFC 0004 open question carried forward); they
are **not** required by Phases 1–4.

## Tiered scope (RFC 0014)

This page targets **Tier B only**. Adjacent tiers are acknowledged but not
delivered:

| Tier | Meaning | In scope here? |
|---|---|---|
| **A** | Shared IR operational semantics (`ProofForge/IR/Semantics.lean`) as ground truth; every backend passes shared-scenario trace obligations. | No — FV-2/FV-3 dependency. |
| **B** | Shared lowering *contract*: per-backend `validateModule*` + `*ModulePlan` + `lowerToAst` + plan-driven metadata + `*-semantic-plan` smokes. | **Yes.** |
| **C** | End-to-end refinement: machine-checked IR-semantics ⟷ on-target behavior per backend. | No — explicit non-goal (FV-4 research). |

## Out of scope

- **Tier C refinement.** A Lean model of Solana syscalls or sBPF semantics,
  end-to-end EVM/Yul refinement, and Psy circuit proofs are not in scope.
  The Phase 4 refinement seam in RFC 0014 is a *seam* (Counter/ValueVault
  trace shape), not Tier C completeness.
- **Proving external toolchains.** `solc`, `sbpf`, `wat2wasm`, `dargo`,
  Mollusk, and surfpool remain outside the proof TCB per
  [`docs/formal-verification.md`](formal-verification.md) Non-goals.
- **Lean typeclass encoding.** Encoding this contract as a Lean typeclass
  is deferred to Phase 6, after Phase 0–4 shapes stabilize. Locking it in
  before Solana/NEAR plans exist risks premature abstraction (RFC 0014
  "Alternatives considered").
- **CosmWasm, Move (Sui/Aptos), Aleo, Cloudflare TS workers.** These may
  follow once the four primary backends are aligned. CosmWasm will likely
  clone the NEAR split; Move and Aleo are research spikes today.
- **EVM-shaped body plans for every backend.** `ExprPlan`/`StmtPlan` are
  backloaded to Phase 5 and only where they pay off. Solana body planning
  is explicitly a Phase 5 non-goal for Phase 2.
- **Replacing AST printers or external tool invocations.** The contract
  sits *above* the AST layer; printers stay as they are.

## Open questions

- Should plan artifacts serialize to JSON for human review (Phase 6
  stretch)? [RFC 0004](rfcs/0004-evm-semantic-plan.md) leaves this open;
  this page inherits it.
- Should CosmWasm follow the NEAR split now or after Phase 3 lands?
- Should the lowering contract be encoded as a Lean typeclass, and if so at
  which stage (Phase 0 stub vs Phase 6 stable shape)?
- Should `just semantic-plan-matrix` be part of `just check`, `just ci`, or
  a separate reviewer-only entry?

## References

- [RFC 0002](rfcs/0002-target-implementation-design.md) — target profiles
  and backend implementation design.
- [RFC 0003](rfcs/0003-portable-ir-and-runtime.md) — portable IR,
  capability lowering, runtime profiles.
- [RFC 0004](rfcs/0004-evm-semantic-plan.md) — EVM semantic plan and Yul
  AST boundary (the reference shape this contract generalizes).
- [RFC 0005](rfcs/0005-solana-sbpf-assembly-backend.md) — Solana sBPF
  assembly backend.
- [RFC 0014](rfcs/0014-unified-semantic-lowering-contract.md) — the
  contract this page elaborates.
- [`docs/portable-ir.md`](portable-ir.md) — shared pipeline diagram.
- [`docs/formal-verification.md`](formal-verification.md) — FV-1..FV-8
  (FV-2 semantics growth, FV-4 Psy differential, FV-8 ValueVault
  invariants).
- [`docs/validation-gates.md`](validation-gates.md),
  [`docs/gate-status.md`](gate-status.md) — P0-2 EVM semantic-plan status.
- [`ProofForge/Backend/Lowering.lean`](../ProofForge/Backend/Lowering.lean)
  — Phase 0 design stub (`LoweringStage` inductive).
- `ProofForge/Backend/Evm/{Validate,Plan,Lower,IR,Metadata,Refinement,YulSemantics}.lean`
- `ProofForge/Backend/WasmHost/{IR,EmitWat,Refinement}.lean`
- `ProofForge/Backend/Psy/{Plan,IR,Metadata,MetadataJson}.lean`
- `ProofForge/Backend/Solana/{SbpfAsm,StateLayout,Extension,Manifest,Idl,Client,Package,Syscalls,Register,Asm}.lean`
- `ProofForge/IR/{Semantics,Ownership}.lean`
- `ProofForge/Target/{Plan,Adapter,Registry,Check}.lean`
- `Tests/{EvmPlan,EvmSemanticPlan,NearWasmFormal,IROwnership,SolanaDiagnostics,PsyMetadata}.lean`
