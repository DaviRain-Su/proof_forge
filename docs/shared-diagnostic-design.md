# Shared lowering diagnostic contract — design note

Status: **Phase 3 landed + follow-ups A & B landed (2026-07-07)**

Companion to [RFC 0014](rfcs/0014-unified-semantic-lowering-contract.md) Phase 3.
This note records the field-level audit of every backend lowering/plan/emit
error type, the design decision (shared concrete type + typeclass contract),
what is safe to extract now vs deferred, and the migration path.

## 1. Audit: per-backend error types

Every type used to signal a lowering, plan, or emit failure in a ProofForge
backend was inspected. The overwhelming finding is that they are *already* the
same shape: a single-field structure `{ message : String }` whose `render` is
`err.message`. No backend carries severity, source location, or an offending
type/code field *inside its lowering error*; those richer fields only appear in
the CLI report layer (`ProofForge.Cli.Check.Diagnostic`), which is a separate
presentation concern and is intentionally out of scope for this stub.

| Backend / layer | Error type (file) | Fields | `render` format | Can share? |
|---|---|---|---|---|
| EVM validate | `Evm.Validate.LowerError` (`Backend/Evm/Validate.lean`) | `message : String` | `err.message` | Yes |
| EVM lowering | `Evm.IR.LowerError` (`Backend/Evm/IR.lean`) | `message : String` | `err.message` | Yes |
| EVM plan | `Evm.Plan.PlanError` (`Backend/Evm/Plan.lean`) | `message : String` | `err.message` | Yes |
| EVM constructor init | `Evm.ConstructorInit.InitError` (`Backend/Evm/ConstructorInit.lean`) | `message : String` | `err.message` | Yes |
| NEAR lowering | `WasmNear.IR.LowerError` (`Backend/WasmNear/IR.lean`) | `message : String` | `err.message` | Yes |
| NEAR plan | `WasmNear.Plan.PlanError` (`Backend/WasmNear/Plan.lean`) | `message : String` | `err.message` (via `err` helper) | Yes |
| NEAR emit | `WasmNear.EmitWat.EmitError` (`Backend/WasmNear/EmitWat.lean`) | `message : String` | `err.message` (via `err` helper) | Yes |
| Solana lowering | `Solana.SbpfAsm.LowerError` (`Backend/Solana/SbpfAsm.lean`) | `message : String` | `err.message` | Yes |
| Solana plan | `Solana.Plan.PlanError` (`Backend/Solana/Plan.lean`) | `message : String` | `err.message` | Yes |
| Psy lowering | `Psy.IR.LowerError` (`Backend/Psy/IR.lean`) | `message : String` | `err.message` | Yes |
| Psy plan | `Psy.Plan.PlanError` (`Backend/Psy/Plan.lean`) | `message : String` | `err.message` | Yes |
| CosmWasm lowering | `CosmWasm.IR.LowerError` (`Backend/CosmWasm/IR.lean`) | `message : String` | `err.message` | Yes |
| CosmWasm emit | `CosmWasm.EmitWat.EmitError` (`Backend/CosmWasm/EmitWat.lean`) | `message : String` | `err.message` (via `err` helper) | Yes |
| Aleo lowering | `Aleo.IR.LowerError` (`Backend/Aleo/IR.lean`) | `message : String` | `err.message` | Yes |
| Move (Sui) emit | `Move.Sui.EmitError` (`Backend/Move/Sui.lean`) | `message : String` | `err.message` (via `err` helper) | Yes |
| Move (Aptos) emit | `Move.Aptos.EmitError` (`Backend/Move/Aptos.lean`) | `message : String` | `err.message` (via `err` helper) | Yes |
| Quint lowering | `Quint.Lower.LowerError` (`Backend/Quint/Lower.lean`) | `message : String` | `err.message` | Yes |
| Quint replay | `Quint.Replay.ReplayError` (`Backend/Quint/Replay.lean`) | `message : String` | `err.message` | Yes |
| Quint inv expr | `Quint.InvExpr.ParseError` (`Backend/Quint/InvExpr.lean`) | `message : String` | `err.message` | Yes |
| Capability layer | `ProofForge.Target.Diagnostic` (`Target/Adapter.lean`) | `message : String` | `diag.message` | Yes (already shared) |
| Capability error | `ProofForge.Target.CapabilityError` (`Target/Check.lean`) | structured | `err.render` (its own format) | No — wrapped by each backend's `capabilityError`/`diagnosticError` |
| CLI report | `ProofForge.Cli.Check.Diagnostic` (`Cli/Check.lean`) | `severity, code, message, file?, line?, column?` | JSON / structured | Out of scope — CLI presentation layer, not a lowering error |

### Shared shape

The shared shape is minimal but real:

```
structure LoweringDiagnostic where
  message  : String                  -- the only field that participates in .render
  backend? : Option String := none   -- metadata for the CLI report layer
  severity : Severity := .error       -- metadata; NOT used by .render
  code?    : Option String := none    -- metadata; NOT used by .render
```

`LoweringDiagnostic.render := diag.message` — byte-identical to every existing
backend `<Name>.render := err.message` that delegates to it.

## 2. Design decision: shared concrete type + typeclass contract

**Choice:** introduce a shared concrete `LoweringDiagnostic` type *and* a
`LoweringError` typeclass contract. Backends keep their concrete error types
and implement the typeclass with a trivial adapter.

**Why not a typeclass-only contract (no shared type)?** A typeclass alone
(`render : α → String`) would not give `SharedValidate` a concrete type to
return. The whole point of Phase 3 is to let shared validation helpers return
*one* error type that every backend can fold into its own concrete type. A
typeclass without a shared concrete type leaves `SharedValidate` still
returning `Except String` (the Phase 1 status quo), which is what we want to
grow beyond. The audit shows the concrete shape is already uniform, so a shared
concrete type is justified, not premature.

**Why not migrate backends onto the shared type as their public error type
now?** Diagnostic stability is sacred (RFC 0014 hard constraint). Each backend's
`.render` output is pinned by golden tests. Replacing a backend's concrete
`LowerError` with `LoweringDiagnostic` would, in the happy case, produce
byte-identical output — but the migration touches every call site and every
test, and a single accidental change to a `s!"..."` interpolation would break a
golden. Phase 3 is design + groundwork, not a big-bang refactor. Backends keep
their concrete types; the typeclass instance is purely additive.

**Why metadata fields (`backend?`, `severity`, `code?`)?** They are optional and
do not participate in `render`. They exist so the CLI report layer
(`ProofForge.Cli.Check`) can, in a later phase, project a `LoweringDiagnostic`
into its richer `Cli.Check.Diagnostic` without backends having to grow those
fields themselves. Leaving them optional-with-defaults means a backend adapter
can ignore them entirely and still implement the contract.

## 3. What is safe to extract now vs deferred

### Safe now (Phase 3 stub — landed)

- `ProofForge.Backend.Diagnostic` with `LoweringDiagnostic`, `Severity`,
  `LoweringError` typeclass, and two trivial adapters (`LoweringDiagnostic`
  identity, `String` for the `Except String` shape `SharedValidate` uses).
- `LoweringDiagnostic.fromTargetDiagnostic` to bridge the existing
  capability-layer `ProofForge.Target.Diagnostic` (already `{ message }`).
- `liftSharedError : Except String α → Except LoweringDiagnostic α` so future
  shared helpers can return the shared type without changing `SharedError`.
- `Tests/Diagnostic.lean` pinning the byte-stability invariant
  (`render` outputs only `message`) and the adapter behavior.
- `just diagnostic-smoke` recipe wired into `just check`.

### Deferred (explicitly called out in RFC 0014 Phase 3)

- **Per-backend `LoweringError` instances — LANDED (2026-07-07, follow-up A).**
  The three Tier-B-completed backends (EVM, Solana, NEAR) now carry trivial
  `LoweringError` adapter instances on every concrete error type listed in the
  audit table above:
  - `Evm.Validate.LowerError`, `Evm.IR.LowerError`, `Evm.Plan.PlanError`
  - `Solana.SbpfAsm.LowerError`, `Solana.Plan.PlanError`
  - `WasmNear.IR.LowerError`, `WasmNear.Plan.PlanError`,
    `WasmNear.EmitWat.EmitError`

  Each instance is `toDiagnostic := fun e => { message := e.message, backend?
  := some "<backend>" }`, and relies on the class default `render` (which
  delegates to `LoweringDiagnostic.render`, i.e. the bare `message`). This is
  byte-identical to each backend's existing `<Name>.render := err.message`.
  `Tests/Diagnostic.lean` was extended from 9 to 17 cases: one per backend
  error type constructs an error, converts via `LoweringError.toDiagnostic`,
  and asserts the shared `render` equals the backend's own `render` and the
  bare `message`. The remaining backends (Psy, CosmWasm, Aleo, Move, Quint)
  are not yet wired — they follow the same trivial pattern when their Tier-B
  work lands.
- **Migrating `SharedValidate` helpers to return `Except LoweringDiagnostic α`
  — LANDED (2026-07-07, follow-up B).** `SharedError` is now an alias for
  `LoweringDiagnostic` (previously `String`). `ensureType` and
  `checkOwnership` now construct `{ message := ... }` instead of returning a
  bare `String`; the message *text* is byte-identical to the Phase 1 output.
  Callers (`Evm/Validate.lean`, `Evm/IR.lean`, `WasmNear/IR.lean`) were
  updated from `.error message => .error { message := message }` to
  `.error diag => .error { message := diag.message }` — wrapping the shared
  diagnostic's `message` into the backend's concrete `LowerError`. The
  caller's observable `.render` is byte-identical.
  `testEnsureTypeMismatchMessage` in `Tests/SharedValidate.lean` still pins
  the exact message bytes; the harness was adapted to pattern-match on
  `Except LoweringDiagnostic` and check `diag.message`. All 12 cases pass.
- **Unifying `validateCapabilities`, the return-path check, identifier
  validity, and `ensureNumericType`.** These remain per-backend (Phase 1
  finding): their signatures, rules, and messages differ. A shared `Diagnostic`
  type is a *prerequisite* for unifying them, not a sufficient condition — the
  rules and messages must also be aligned first. Deferred to a later phase.
- **CLI report projection.** `ProofForge.Cli.Check` can later project
  `LoweringDiagnostic` (with `backend?`/`severity`/`code?`) into its richer
  `Cli.Check.Diagnostic`. Not part of this stub.

## 4. Migration path

1. **Phase 3 (stub, landed 2026-07-07):** shared type + contract + trivial
   adapters + smoke. No backend signature changes. No golden can move.
2. **Follow-up A (landed 2026-07-07):** added `LoweringError` instances to each
   Tier-B backend's concrete error type (EVM, Solana, NEAR — 8 error types
   total). Each instance is two lines; no call site changes; the extended
   `Tests/Diagnostic.lean` (17 cases) guards bytes at the instance level.
3. **Follow-up B (landed 2026-07-07):** migrated `SharedValidate` helpers to
   return `Except LoweringDiagnostic α`. `SharedError` is now an alias for
   `LoweringDiagnostic`. Each backend's `ensureType` wrapper folds
   `diag.message` into its concrete `LowerError`. Bytes preserved by
   construction and pinned by `testEnsureTypeMismatchMessage`.
4. **Follow-up C (post-Phase 2/3):** revisit whether `validateCapabilities`,
   the return-path check, identifier validity, and `ensureNumericType` can be
   unified now that a shared diagnostic and aligned rules exist. This is the
   "shared validate surface grows beyond Phase 1" goal from RFC 0014.

## 5. Diagnostic stability invariant

The single acceptance criterion for this stub and every follow-up is:

> For every backend `B` with a concrete error type `B.LowerError`, and for
> every `e : B.LowerError`, the bytes of `B.LowerError.render e` before and
> after introducing a `LoweringError B.LowerError` instance must be identical.

`Tests/Diagnostic.lean` pins the invariant at the shared-type level
(`LoweringDiagnostic.render` outputs only `message`). Each backend's existing
golden suite pins it at the backend level. The two layers together make
diagnostic drift loud in CI.