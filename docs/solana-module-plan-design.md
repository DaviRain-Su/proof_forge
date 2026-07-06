# SolanaModulePlan — Field-Level Design Draft

Status: **Draft** (design only — not implemented)

Date: 2026-07-06

Target phase: [RFC 0014](rfcs/0014-unified-semantic-lowering-contract.md) Phase 2

Companion: [target-lowering-interface.md](target-lowering-interface.md) (Solana deep-dive)

## 1. Purpose & status

This document specifies the **field-level shape** of the proposed
`SolanaModulePlan` and its sub-plans, so it can be reviewed before Phase 2
implementation touches any Lean code. Nothing here is implemented yet. The
intent is to lock down:

- Which sub-plans exist and what each contains.
- Where every plan field is sourced from in today's code.
- Which `LowerCtx` fields become plan-derived vs stay lowering-local.
- How the new plan relates to today's `ProgramExtensions`.
- A safe, byte-stable migration path.

This is a **Tier B** design (per RFC 0014): an inspectable, pure-data plan
artifact that sits between `validateCapabilities` and `lowerToAst`. Body
planning (`ExprPlan` / `StmtPlan` for Solana instruction bodies) is **not** in
scope — it is a Phase 5 non-goal.

All file paths, struct names, and field names below are real and were verified
against the source. New fields/types proposed here are prefixed with `new:` in
sourcing tables.

## 2. Design principles

- **Plan is pure data.** `SolanaModulePlan` is built once, after validation,
  and is never mutated during AST emission. Reviewers, golden tests, and (later)
  refinement obligations read it directly.
- **`LowerCtx` becomes plan-derived.** Today `LowerCtx` is built inline inside
  `SbpfAsm.lowerModuleCore` and accumulates state during emission. Under the new
  design the plan-seeded fields are populated from `SolanaModulePlan`; only
  genuinely ephemeral lowering state (label counter, scratch bump) stays
  local to `lowerToAst`.
- **Byte-stability is the #1 acceptance gate.** Golden asm output and the
  Pinocchio reference-equivalence gate must stay byte-identical when the plan
  path is enabled. Migration lands behind `--solana-plan=v2` and switches only
  after parity is demonstrated over N probes.
- **No body planning yet.** Phase 2 plans layout + dispatch + account/CPI/
  syscall schema only. Instruction-body lowering continues to emit `AstNode`
  sequences from `Expr`/`Statement` as today, but reading plan-seeded context.
- **Reuse `ProgramExtensions` types where they fit.** `DeclaredAccount`,
  `PdaDerive`, `CpiInvoke`, `SysvarKind`, `CryptoHashOp` etc. are already
  well-shaped data types; the plan reuses them rather than inventing parallel
  structures (see §6).

## 3. Top-level type

Illustrative Lean 4 (not required to compile; for review):

```lean
-- new: top-level plan artifact for the Solana target (RFC 0014 Phase 2)
structure SolanaModulePlan where
  moduleName   : String
  -- Storage / account layout the program operates over
  storageAccountPlan : StorageAccountPlan
  -- One entry per IR.Entrypoint (discriminator, decode order, accounts used)
  entrypointPlans    : Array EntrypointPlan
  -- Byte layout of the on-chain instruction data stream
  instructionDataPlan : InstructionDataPlan
  -- Cross-program invocations the program may issue
  cpiPlan        : CpiPlan
  -- Syscalls / host functions the body will call (for CU + manifest)
  syscallPlan    : SyscallPlan
  -- Linkage consumed by Manifest / Idl / Client / Package emitters
  manifestPlan   : ManifestPlan
  -- Reference to the shared capability plan (CPI/PDA/sysvar enablement)
  capabilityPlan : ProofForge.Target.CapabilityPlan
  deriving Repr
```

Built once via:

```lean
-- new
def buildSolanaModulePlan (module : IR.Module)
    (plan : ProofForge.Target.CapabilityPlan) :
    Except SolanaPlanError SolanaModulePlan := ...
```

`buildSolanaModulePlan` is **pure** and runs after `validateCapabilities`. It
replaces the inline schema/layout computation currently at the top of
`SbpfAsm.lowerModuleCore`.

## 4. Sub-plan designs

For each sub-plan: (a) Lean struct sketch, (b) field sourcing table
(`Plan field | Current source | Invariant`), (c) downstream consumers.

### 4.1 `StorageAccountPlan`

Account layout the program reads/writes: ordering, sizes, ownership/signer/
writable flags, PDA derivations, and state field offsets.

```lean
-- new
structure StorageAccountPlan where
  -- Ordered accounts the entrypoint expects (matches instruction stream order)
  accounts        : Array ProofForge.Backend.Solana.Extension.DeclaredAccount
  -- PDA derivations: name -> seeds + bump + signer
  pdas            : Array ProofForge.Backend.Solana.Extension.PdaDerive
  -- Absolute byte offset of each state field within account[0]'s data region
  stateFieldOffsets : Array (String × Nat)
  -- Struct byte sizes (for memcpy / field access)
  structLayouts   : Array (String × Nat)  -- typeName × totalByteSize
  -- State declarations (mirror IR.StateDecl array for convenience)
  stateDecls      : Array IR.StateDecl
  deriving Repr
```

| Plan field | Current source (file + function/struct) | Invariant |
|---|---|---|
| `accounts` | `SbpfAsm.buildModuleInputSchema` → `accounts` (`ModuleInputSchema.accounts`, built from `buildInstructionsWithExtensions` / `buildDefaultAccounts`) | Order matches instruction stream; stable across plan → asm |
| `pdas` | `Extension.ProgramExtensions.pdas` (from `ProgramExtensions.fromPlan`) | Seeds reproducible; bump optional but deterministic |
| `stateFieldOffsets` | `LowerCtx.stateFieldOffsets` (computed in `SbpfAsm.buildCtx`) + `StateLayout.lean` | Offsets unique within account[0]; ascending |
| `structLayouts` | `SbpfAsm.structByteSize` over `LowerCtx.structs` (`IR.StructDecl` array) | Sum of field byte sizes; matches `valueTypeByteSize` rules |
| `stateDecls` | `LowerCtx.stateDecls` (passed through from `IR.Module`) | Subset of `module.stateDecls` accepted by the target profile |

**Consumers:** asm lowering (slot read/write), Manifest emitter (account
metadata), Idl emitter (account types), Package emitter (account list).

### 4.2 `EntrypointPlan`

One per `IR.Entrypoint`: discriminator, parameter decode order, accounts
consumed, return shape.

```lean
-- new
structure EntrypointPlan where
  name          : String
  -- 8-bit selector in the instruction data stream (index in module.entrypoints)
  discriminator : Nat
  -- Decode order for instruction parameters (name × ValueType × byte size)
  paramDecodes  : Array (String × ProofForge.Backend.Solana.Asm.ValueType × Nat)
  -- Accounts this entrypoint touches (subset of StorageAccountPlan.accounts)
  accountsUsed  : Array String
  -- Whether the body ends in a typed return vs void
  returnsValue  : Bool
  deriving Repr
```

| Plan field | Current source | Invariant |
|---|---|---|
| `discriminator` | `SbpfAsm.lowerModuleCore` entrypoint loop (sequential index) | Equals position in `module.entrypoints`; fits in u8 |
| `paramDecodes` | `lowerEntrypoint` parameter unpacking in `SbpfAsm.lean` + `valueTypeByteSize` | Decode order matches instruction arg order; sizes via `valueTypeByteSize` |
| `accountsUsed` | `lowerEntrypoint` account binding resolution | Subset of `StorageAccountPlan.accounts` names |
| `returnsValue` | `IR.Entrypoint.returnType` check in `validateModule` (Phase 1 shared validate) | True iff return type ≠ unit |

**Consumers:** asm lowering (dispatch table + param decode prologue), Manifest
(method list), Idl (method signatures), Client (method bindings).

### 4.3 `InstructionDataPlan`

Byte layout of the on-chain instruction data stream that the runtime parses.

```lean
-- new
structure InstructionDataPlan where
  -- Total byte length of the instruction data region (header + discriminator + args)
  totalLen      : Nat
  -- Offset where the 1-byte discriminator lives
  discriminatorOffset : Nat
  -- Account pointer table layout (offsets saved on entry, see entryInstructionDataSaveOffset)
  accountPtrTable : Array (String × Nat)  -- account name × save offset on frame
  -- Length-prefixed dynamic args: name × offset × hasLengthPrefix
  argLayout     : Array (String × Nat × Bool)
  -- Realloc flags affecting layout (from computeInputLayoutWithReallocFlags)
  reallocFlags  : Array String
  deriving Repr
```

| Plan field | Current source | Invariant |
|---|---|---|
| `totalLen` | `ModuleInputSchema.inputLayout.instructionDataLenOff` | Accounts for header + discriminator + args + length prefixes |
| `discriminatorOffset` | `lowerInstructionDataPointerSetup` (`entryInstructionDataReg` + `U64_SIZE`) | Fixed offset after length header |
| `accountPtrTable` | `lowerAccountPtrTableSetup` ("entrypoint", accountCount) | One slot per account; offsets into frame at `entryInstructionDataSaveOffset` |
| `argLayout` | `accountInputSpecs` / `computeInputLayoutWithReallocFlags` | Matches `EntrypointPlan.paramDecodes` order |
| `reallocFlags` | `computeInputLayoutWithReallocFlags` realloc branch | Stable across plan → asm |

**Consumers:** asm lowering (entry pointer setup), Client (instruction data
serialization), Idl (arg layout).

### 4.4 `CpiPlan`

Cross-program invocations the program may issue.

```lean
-- new
structure CpiPlan where
  -- Direct CPI invocations declared in the IR (program/instruction/accounts)
  invokes       : Array ProofForge.Backend.Solana.Extension.CpiInvoke
  -- Account bindings for each CPI (name × layout)
  accountBindings : Array ProofForge.Backend.Solana.SbpfAsm.CpiAccountBinding
  -- Value bindings (state/param offsets the CPI reads)
  valueBindings : Array ProofForge.Backend.Solana.SbpfAsm.CpiValueBinding
  -- PDA signer seeds chain for each CPI that needs invoke_signed
  signerSeeds   : Array (String × Array String)  -- cpiName × seeds
  deriving Repr
```

| Plan field | Current source | Invariant |
|---|---|---|
| `invokes` | `Extension.ProgramExtensions.cpis` (`CpiInvoke`: name, program, instruction, accounts, signerSeeds, dataLayout?, signed, …) | Every invoke has ≥1 account; program id resolves |
| `accountBindings` | `SbpfAsm.buildCpiAccountBindings` over `ModuleInputSchema.accounts` + layouts | One binding per CPI account; layout non-empty |
| `valueBindings` | `SbpfAsm.buildStateCpiValueBindings` + `buildEntrypointParamCpiValueBindings` + `lowerModuleWithPlan`'s `valueBindings` | absOff within account[0] data region; byteSize ≥ 0 |
| `signerSeeds` | `CpiInvoke.signerSeeds` + PDA resolution from `ProgramExtensions.pdas` | Seeds chain reproducible; signer account is PDA |

**Consumers:** asm lowering (`Extension.lowerPlan : Array AstNode` today becomes
`lowerToAst` consuming `CpiPlan`), Manifest (CPI metadata), Client (CPI helper
generation).

### 4.5 `SyscallPlan`

Summary of syscalls the body will invoke — drives CU estimation and the
manifest's required-host surface.

```lean
-- new
structure SyscallPlan where
  -- Memory ops (memcpy/memmove/memset/memcmp) with counts
  memoryOps       : Array (ProofForge.Backend.Solana.Extension.MemoryOp × Nat)
  -- Crypto hashes (sha256/keccak256/blake3) with counts
  cryptoHashOps   : Array (ProofForge.Backend.Solana.Extension.CryptoHashOp × Nat)
  -- Sysvar reads (rent/epochSchedule/epochRewards/lastRestartSlot)
  sysvarReads     : Array ProofForge.Backend.Solana.Extension.SysvarKind
  -- Whether the program uses sol_invoke_signed_ (CPI) — derived from CpiPlan
  usesInvokeSigned : Bool
  -- Whether the program reads return data (sol_get_return_data)
  usesReturnDataRead : Bool
  -- Whether the program writes return data (sol_log_data_)
  usesReturnDataWrite : Bool
  -- Log syscalls used (sol_log_64_, sol_log_pubkey_, sol_log_data_)
  logSyscalls     : Array String  -- subset of {"sol_log_64_", "sol_log_pubkey_", "sol_log_data_"}
  -- Compute budget advice (heap frame requests via compute_budget)
  computeBudget   : Array ProofForge.Backend.Solana.Extension.ComputeBudgetAdvice
  deriving Repr
```

| Plan field | Current source | Invariant |
|---|---|---|
| `memoryOps` | `Extension.ProgramExtensions.memoryActions` (`MemoryAction` array, op kind from `MemoryOp`) | Counts ≥ 0; op kind valid |
| `cryptoHashOps` | `ProgramExtensions.cryptoHashActions` (`CryptoHashAction`, op via `CryptoHashOp`) | Counts ≥ 0; blake3 feature-gated (`CryptoHashOp.featureGated`) |
| `sysvarReads` | `ProgramExtensions.sysvarActions` (`SysvarReadAction`, kind via `SysvarKind`) | Subset of supported sysvars |
| `usesInvokeSigned` | Derived: `CpiPlan.invokes.any (·.signed)` | True iff any CPI is signed |
| `usesReturnDataRead` | `ProgramExtensions.returnDataReadActions` non-empty | Mutually exclusive with void return per EmitWat-style rule |
| `usesReturnDataWrite` | `ProgramExtensions.returnDataActions` non-empty | — |
| `logSyscalls` | `ProgramExtensions.pubkeyLogActions` + `dataLogActions` + (computeUnits log) | Subset of supported log syscalls |
| `computeBudget` | `ProgramExtensions.computeBudgetActions` | Heap frame ≥ 0 |

**Consumers:** asm lowering (syscall emit + CU estimation), Manifest (required
host surface), future refinement (host-boundary obligations).

### 4.6 `ManifestPlan`

Linkage fields consumed by the `Manifest` / `Idl` / `Client` / `Package`
emitters — what today each emitter re-derives from `ModuleInputSchema` +
`ProgramExtensions` directly.

```lean
-- new
structure ManifestPlan where
  -- Account names + roles for the manifest account list
  accountRoles   : Array (String × String)  -- name × role (writable/signer/owner)
  -- IDL method entries: name × arg types × return type
  idlMethods     : Array (String × Array String × String)
  -- Client method signatures (TS) for each entrypoint
  clientMethods  : Array (String × String)  -- methodName × signature
  -- Package layout: project name + output dirs (ELF, manifest, idl, client)
  packageLayout  : PackageLayoutPlan
  deriving Repr

-- new
structure PackageLayoutPlan where
  projectName : String
  elfDir      : String  -- typically "deploy/"
  manifestDir : String
  idlDir      : String
  clientDir   : String
  deriving Repr
```

| Plan field | Current source | Invariant |
|---|---|---|
| `accountRoles` | `Manifest.buildInstructionsWithPlan` account metadata + `DeclaredAccount.{access,signer,owner}` | Roles match `StorageAccountPlan.accounts` flags |
| `idlMethods` | `Idl.renderWithPlan` + `capabilitiesJson` | Method names match `EntrypointPlan.name` set |
| `clientMethods` | `Client.renderWithPlan` | Signatures match `EntrypointPlan.paramDecodes` |
| `packageLayout` | `Package.renderPackageWithPlan` project name + dir layout | Dirs match `lake env proof-forge` output convention |

**Consumers:** Manifest emitter, Idl emitter, Client emitter, Package emitter.

## 5. LowerCtx derivation

Today's `LowerCtx` (from `SbpfAsm.lean`):

```lean
structure LowerCtx where
  stateFieldOffsets : Array (String × Nat)
  structs           : Array StructDecl
  stateDecls        : Array StateDecl
  locals            : Array LocalSlot
  nextLocalOffset   : Nat
  scratchOffset     : Nat
  nextLabel         : Nat
  allocator         : Allocator
  deriving Inhabited
```

Under the new design:

| `LowerCtx` field | Plan-derived or lowering-local | Source plan field(s) | Notes |
|---|---|---|---|
| `stateFieldOffsets` | **plan-derived** | `StorageAccountPlan.stateFieldOffsets` | Seeded directly; not mutated during emission |
| `structs` | **plan-derived** | `StorageAccountPlan.structLayouts` (names) + `IR.Module.structs` (bodies) | Plan carries sizes; struct bodies come from IR |
| `stateDecls` | **plan-derived** | `StorageAccountPlan.stateDecls` | Mirror of IR subset accepted by the profile |
| `locals` | **plan-seeded, then lowering-local** | `EntrypointPlan.paramDecodes` (seed) + per-block local allocation | Reset per entrypoint (`LowerCtx.resetLocals`); mutated as locals are allocated |
| `nextLocalOffset` | **lowering-local** | — | Bumped during local allocation; reset per entrypoint |
| `scratchOffset` | **lowering-local** | — | Scratch frame bump; reset per entrypoint |
| `nextLabel` | **lowering-local** | — | Label counter; reset per `lowerToAst` invocation |
| `allocator` | **lowering-local** | — | Heap allocator handle; rebuilt per emission |

Sketch:

```lean
-- new
def LowerCtx.fromPlan (plan : SolanaModulePlan) : LowerCtx :=
  { stateFieldOffsets := plan.storageAccountPlan.stateFieldOffsets
    structs           := plan.storageAccountPlan.stateDecls.foldl ... -- from IR.Module.structs by name
    stateDecls        := plan.storageAccountPlan.stateDecls
    locals            := #[]            -- filled per-entrypoint
    nextLocalOffset   := 0              -- per-entrypoint
    scratchOffset     := defaultScratch -- per-entrypoint
    nextLabel         := 0              -- per-emission
    allocator         := Allocator.initial }
```

The split is the key refactor: everything that is **stable across the whole
module** (storage layout, structs, state decls) moves into the plan; everything
that is **ephemeral per entrypoint or per emission** (locals, label counter,
scratch) stays in `LowerCtx` but is now seeded from the plan rather than built
inline.

## 6. Relationship with `ProgramExtensions`

Today (`Extension.lean`):

```lean
structure ProgramExtensions where
  accounts              : Array DeclaredAccount := #[]
  allocators            : Array RuntimeAllocator := #[]
  pdas                  : Array PdaDerive := #[]
  cpis                  : Array CpiInvoke := #[]
  pdaActions            : Array PdaAction := #[]
  cpiActions            : Array CpiAction := #[]
  memoryActions         : Array MemoryAction := #[]
  cryptoHashActions     : Array CryptoHashAction := #[]
  sysvarActions         : Array SysvarReadAction := #[]
  returnDataActions     : Array ReturnDataAction := #[]
  returnDataReadActions : Array ReturnDataReadAction := #[]
  computeUnitsActions   : Array ComputeUnitsAction := #[]
  computeUnitsLogActions: Array ComputeUnitsLogAction := #[]
  computeBudgetActions  : Array ComputeBudgetAdvice := #[]
  pubkeyLogActions      : Array PubkeyLogAction := #[]
  dataLogActions        : Array DataLogAction := #[]
  accountReallocActions: Array AccountReallocAction := #[]
  deriving Repr, Inhabited
```

`ProgramExtensions.fromPlan : CapabilityPlan → ProgramExtensions` is today's
bridge from the shared `CapabilityPlan` to Solana-specific extension data.

**Recommendation: coexist, do not absorb.**

- `CpiPlan` (new) and `SyscallPlan` (new) become the **pure-data plan artifacts**
  — they are built once in `buildSolanaModulePlan` and read by emitters and
  (later) refinement.
- `ProgramExtensions` stays as today's **CapabilityPlan-derived view**, but is
  re-cast as a **lowering-time view over `CpiPlan` + `CapabilityPlan`** rather
  than the source of truth. `ProgramExtensions.fromCpiPlan` becomes the new
  derivation; `ProgramExtensions.fromPlan` is kept for backward compatibility
  during the migration.
- `Extension.lowerPlan : Array AstNode` today emits the CPI/PDA asm nodes.
  Under the new design this becomes part of `lowerToAst` consuming `CpiPlan`,
  so the asm emission for CPI is plan-driven rather than extensions-driven.

The key invariant: after migration, **no emitter reads `ProgramExtensions`
directly**; they read `CpiPlan` / `SyscallPlan` fields. `ProgramExtensions`
becomes an internal lowering helper, not a public plan artifact.

## 7. `buildSolanaModulePlan` signature sketch

```lean
-- new
inductive SolanaPlanError where
  | unsupportedCapability   : String -> SolanaPlanError
  | accountSchemaMismatch   : String -> SolanaPlanError
  | invalidInstructionLayout: String -> SolanaPlanError
  | cpiResolutionFailure    : String -> SolanaPlanError

-- new
def buildSolanaModulePlan (module : IR.Module)
    (capPlan : ProofForge.Target.CapabilityPlan) :
    Except SolanaPlanError SolanaModulePlan := do
  -- 1. Re-run capability gating (today's validateCapabilities equivalent)
  -- 2. Build StorageAccountPlan from StateLayout + buildModuleInputSchema
  -- 3. Build EntrypointPlan[] from module.entrypoints + param decode rules
  -- 4. Build InstructionDataPlan from computeInputLayoutWithReallocFlags
  -- 5. Build CpiPlan from ProgramExtensions.fromPlan(capPlan)
  -- 6. Build SyscallPlan from ProgramExtensions action arrays
  -- 7. Build ManifestPlan from the above
  -- 8. Return the composite plan (pure; no AST construction)
  ...

-- new
def lowerToAst (module : IR.Module) (plan : SolanaModulePlan) :
    Except LowerError (Array AstNode) := do
  let ctx := LowerCtx.fromPlan plan
  -- ... entrypoint loop reads ctx + plan.entrypointPlans ...
```

Position in the future `lowerModuleCore`:

```text
validateCapabilities module            -- existing
buildSolanaModulePlan module capPlan   -- new (pure)
LowerCtx.fromPlan plan                 -- new (pure)
lowerToAst module plan                 -- new (plan-driven; replaces inline emission)
```

## 8. Smoke gate proposal — `just solana-semantic-plan`

Mirror of `just evm-plan` / `just evm-semantic-plan`. A new test module
`Tests/SolanaSemanticPlan.lean` asserts:

1. **Plan consistency.**
   - Every state field in `IR.Module.stateDecls` has an entry in
     `StorageAccountPlan.stateFieldOffsets`.
   - Every PDA in `StorageAccountPlan.pdas` has non-empty seeds.
   - Every CPI in `CpiPlan.invokes` has ≥1 account and resolves a program id.
2. **Layout stability (golden plan snapshot — future).**
   - Phase 2: assert plan structural equality against a checked-in fixture per
     probe (Counter, MapProbe, StorageStruct).
   - Phase 6: serialize plan to JSON for human diffing.
3. **Manifest ↔ asm agreement.**
   - Account ordering in `ManifestPlan.accountRoles` matches the account
     pointer table in `InstructionDataPlan.accountPtrTable`, which matches the
     asm entrypoint setup.
4. **Byte-stability guard.**
   - When `--solana-plan=v2` is enabled, the emitted `.s` must be byte-identical
     to the pre-plan path, verified by the existing Pinocchio reference-
     equivalence gate over the probe set.

Sketch (illustrative):

```lean
-- Tests/SolanaSemanticPlan.lean (illustrative shape)
#eval assertPlanConsistency Counter.module Counter.expectedPlan
#eval assertManifestAsmAgreement Counter.module
#eval assertByteStabilityV2 Counter.module   -- runs both paths, diffs asm
```

## 9. Migration plan

Three steps; each lands behind the feature flag and must demonstrate parity
before the next begins.

**Step A — Types only (no behavior).**
- Land `ProofForge/Backend/Solana/Plan.lean` with the struct definitions above
  (no construction, no consumers).
- `SolanaModulePlan` is buildable but unused; existing lowering path unchanged.
- CI stays green by construction.

**Step B — Plan construction + dual run (behind `--solana-plan=v2`).**
- Implement `buildSolanaModulePlan` + `LowerCtx.fromPlan`.
- When `--solana-plan=v2` is passed, build the plan, derive `LowerCtx`, and emit
  asm via `lowerToAst`; otherwise use the legacy inline path.
- Add a CI-only gate that runs BOTH paths for the probe set and asserts
  byte-equality of the `.s` output (Pinocchio reference-equivalence gate).
- Probes to cover: Counter, MapProbe, StorageStruct, AbiAggregate,
  Conditional, Loop, Event, TypedStorage (mirror EVM refinement probe set).

**Step C — Switch default.**
- After parity holds across the full probe set over N consecutive CI runs,
  flip the default to `--solana-plan=v2` and delete the legacy inline path.
- `ProgramExtensions.fromPlan` is demoted to a compatibility shim; emitters
  switch to reading `CpiPlan` / `SyscallPlan`.

**Incremental extraction order (recommended):**
1. `StorageAccountPlan` first (smallest surface; unblocks `LowerCtx.fromPlan`
   for storage fields).
2. `InstructionDataPlan` (touches entry pointer setup).
3. `CpiPlan` + `SyscallPlan` (largest surface; touches `Extension.lowerPlan`).

Risk callout: `SbpfAsm.lean` is ~1.7k LOC and feeds golden asm + Pinocchio gates.
The feature-flag strategy keeps the legacy path as a fallback until Step C.

## 10. Open questions

- Should `SyscallPlan` store **counts** per op or just **presence**? Counts
  help CU estimation; presence is enough for the manifest. Recommendation:
  store counts, derive presence.
- Should `CpiPlan.invokes` reuse `Extension.CpiInvoke` verbatim or define a
  plan-native type? Recommendation: reuse — `CpiInvoke` is already well-shaped
  pure data.
- Should `ManifestPlan` be a separate struct or flattened onto the top-level
  plan? Recommendation: keep separate (single responsibility; consumers are
  distinct emitters).
- Should plan artifacts serialize to JSON for human review? This is RFC 0004 /
  0014's shared open question; Phase 6 stretch.
- Should `LowerCtx.fromPlan` be pure or monadic? Recommendation: pure; the
  lowering-local fields (label counter, allocator) are seeded with constants.

## 11. Non-goals

- **Body planning** (`ExprPlan` / `StmtPlan` for Solana instruction bodies) —
  Phase 5.
- **Tier C refinement** (machine-checked IR semantics ⟷ on-target behavior).
- **Proving `sbpf`** or any external toolchain.
- **Changing the asm AST** (`AstNode`) or its printer — the plan sits above the
  AST layer.
- **Single global `ModulePlan` type** across backends — RFC 0004 non-goal
  respected; `SolanaModulePlan` is Solana-specific.

## 12. References

- [RFC 0014](rfcs/0014-unified-semantic-lowering-contract.md) — Phase 2 source.
- [target-lowering-interface.md](target-lowering-interface.md) — Solana
  deep-dive and per-backend invariants table.
- [RFC 0004](rfcs/0004-evm-semantic-plan.md) — EVM reference plan shape
  (style reference only).
- [RFC 0005](rfcs/0005-solana-sbpf-assembly-backend.md) — Solana sBPF backend
  history.
- `ProofForge/Backend/Solana/SbpfAsm.lean` — `LowerCtx`, `LocalSlot`,
  `ModuleInputSchema`, `buildModuleInputSchema`, `buildCtx`, `lowerModuleCore`,
  `lowerModuleWithPlan`, `validateCapabilities`, `buildCpiAccountBindings`,
  `buildStateCpiValueBindings`, `buildEntrypointParamCpiValueBindings`,
  `lowerInstructionDataPointerSetup`, `lowerAccountPtrTableSetup`,
  `valueTypeByteSize`, `structByteSize`, `structFieldOffset`.
- `ProofForge/Backend/Solana/StateLayout.lean` — state field layout.
- `ProofForge/Backend/Solana/Extension.lean` — `ProgramExtensions`,
  `DeclaredAccount`, `PdaDerive`, `PdaSeed`, `CpiInvoke`, `MemoryOp`,
  `CryptoHashOp`, `SysvarKind`, `CpiAccountBinding`, `CpiValueBinding`,
  `ProgramExtensions.fromPlan`, `lowerPlan : Array AstNode`.
- `ProofForge/Backend/Solana/Manifest.lean` — `buildInstructionsWithPlan`,
  `renderManifestWithPlan`.
- `ProofForge/Backend/Solana/Idl.lean` — `renderWithPlan`, `capabilitiesJson`.
- `ProofForge/Backend/Solana/Syscalls.lean` — `sol_sha256`, `sol_keccak256`,
  `sol_blake3`, syscall identifiers.
- `ProofForge/Backend/Solana/Package.lean` — `renderPackageWithPlan`.
- `ProofForge/Backend/Solana/Asm.lean` — `AstNode`, `ValueType`, `Register`.
- `ProofForge/Backend/Evm/Plan.lean` — style reference for `ModulePlan`,
  `StorageLayout`, `EntrypointPlan`.
- `ProofForge/IR/Contract.lean` — `Module`, `Entrypoint`, `StateDecl`,
  `StructDecl`, `Expr`, `Statement`, `Effect`.
- `ProofForge/Target/Plan.lean` — `CapabilityPlan`.
