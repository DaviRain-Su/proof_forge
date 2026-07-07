/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Shared lowering diagnostic contract (RFC 0014, Phase 3)

This module is the **Phase 3** landing of
[RFC 0014](../../docs/rfcs/0014-unified-semantic-lowering-contract.md): a
shared diagnostic vocabulary that every primary backend can produce and that
`ProofForge.Backend.SharedValidate` can return where it produces errors, *without*
changing any existing backend's concrete error type or its byte-identical
`.render` output.

## Audit finding (why a shared *type* is worth it)

A field-level inventory of every backend lowering / plan / emit error type shows
they are *already* the same shape: a single-field
`structure <Name> where message : String` whose `render` is `err.message`. This
holds for `Evm.Validate.LowerError`, `Evm.IR.LowerError`, `Evm.Plan.PlanError`,
`Evm.ConstructorInit.InitError`, `WasmNear.IR.LowerError`,
`WasmNear.Plan.PlanError`, `WasmNear.EmitWat.EmitError`,
`Solana.SbpfAsm.LowerError`, `Solana.Plan.PlanError`, `Psy.IR.LowerError`,
`Psy.Plan.PlanError`, `CosmWasm.IR.LowerError`, `CosmWasm.EmitWat.EmitError`,
`Aleo.IR.LowerError`, `Move.Sui.EmitError`, `Move.Aptos.EmitError`,
`Quint.Lower.LowerError`, `Quint.Replay.ReplayError`, `Quint.InvExpr.ParseError`,
and the already-shared `ProofForge.Target.Diagnostic`. The only richer shape is
`ProofForge.Cli.Check.Diagnostic` (severity + code + location), which is a CLI
*report* type, not a lowering error — it is intentionally out of scope here.

Because the shape is already uniform, a shared concrete `LoweringDiagnostic` type
is justified rather than a mere typeclass interface: backends already pay the
cost of a `{ message }` wrapper, so converging on one shared wrapper removes
duplication without forcing any new field on them.

## Design (conservative, migration-safe)

1. `LoweringDiagnostic` is the shared type. Its `render` outputs **only**
   `message`, so any backend that delegates to it sees byte-identical output.
   The optional `backend?` / `severity` / `code?` fields are *metadata* for the
   future CLI report layer; they do **not** participate in `render` and so
   cannot perturb golden diagnostics.
2. `LoweringError` is a typeclass (the *contract*) that each backend's concrete
   error type can implement with a trivial adapter
   `⟨fun e => { message := e.message }, fun e => e.message⟩`. Backends keep
   their concrete `LowerError` / `PlanError` / `EmitError` types untouched; the
   class instance is purely additive and does not alter any existing call site
   or `.render` bytes.
3. `SharedValidate`'s existing `SharedError = String` return type is **not**
   migrated in this stub — that is a follow-up task explicitly called out in
   RFC 0014 Phase 3, to be done once each backend has an adapter instance. This
   keeps Phase 3 a pure addition: no existing module's signature changes, no
   golden diagnostic can move.

## Non-goals of this stub

- No backend is migrated onto `LoweringDiagnostic` as its public error type.
- No `SharedValidate` helper signature changes.
- No existing `.render` output is touched. See `Tests/Diagnostic.lean` for the
  byte-stability pin.
-/

import ProofForge.Target.Adapter

namespace ProofForge.Backend.Diagnostic

/-! ## Severity

Mirrors `ProofForge.Cli.Check.Severity` but lives in the backend layer so the
lowering contract does not depend on the CLI. `LoweringDiagnostic.render`
ignores severity; it is carried for the CLI report layer and future structured
diagnostics. -/

inductive Severity where
  | error
  | warning
  | info
  deriving BEq, Inhabited, Repr

def Severity.id : Severity → String
  | .error => "error"
  | .warning => "warning"
  | .info => "info"

/-! ## Shared lowering diagnostic

The shared error shape. `render` outputs only `message` so that any backend
which delegates to this type produces byte-identical output to its existing
`<Name>.render := err.message`. The optional fields are metadata only. -/

structure LoweringDiagnostic where
  message : String
  backend? : Option String := none
  severity : Severity := .error
  code? : Option String := none
  deriving Inhabited, Repr

/-- Render a lowering diagnostic as its bare message.

This is the single source of truth for shared-diagnostic rendering. It
deliberately ignores `backend?` / `severity` / `code?` so that backends delegating
to `LoweringDiagnostic` see the same bytes as their existing
`<Name>.render := err.message`. Any richer render format belongs to the CLI
report layer (`ProofForge.Cli.Check`), not here. -/
def LoweringDiagnostic.render (diag : LoweringDiagnostic) : String :=
  diag.message

/-- Construct a shared diagnostic from a bare message, defaulting to
`.error` severity and no backend/code tag. -/
def LoweringDiagnostic.fromString (message : String) (backend? : Option String := none) :
    LoweringDiagnostic :=
  { message, backend?, severity := .error }

/-- Promote the existing capability-layer `ProofForge.Target.Diagnostic` (already
a `{ message }` shape) to the shared lowering diagnostic. The message is
preserved verbatim; `backend?` is left unset so the caller can tag it. -/
def LoweringDiagnostic.fromTargetDiagnostic (diag : ProofForge.Target.Diagnostic) :
    LoweringDiagnostic :=
  { message := diag.message }

/-! ## Lowering error contract (typeclass)

Each backend keeps its concrete error type and implements this class with a
trivial adapter. `render` defaults to projecting `toDiagnostic` and rendering
it, so a backend whose concrete `render` is already `err.message` can declare
just `toDiagnostic` and inherit the byte-identical default `render`. -/

class LoweringError (α : Type) where
  /-- Project a backend's concrete error into the shared diagnostic shape. -/
  toDiagnostic : α → LoweringDiagnostic
  /-- Render a backend's concrete error as a bare message string.

  Defaults to `toDiagnostic |> render` so that backends whose existing
  `<Name>.render := err.message` line up with the shared `render` automatically. -/
  render : α → String := fun e => toDiagnostic e |>.render

/-! ## Trivial adapters

Two trivial adapter instances that demonstrate the contract without depending
on any backend module: the identity adapter for `LoweringDiagnostic` itself,
and a raw-string adapter for the common `Except String` pattern that
`SharedValidate` currently uses (`SharedError = String`). -/

instance : LoweringError LoweringDiagnostic where
  toDiagnostic := id

instance : LoweringError String where
  toDiagnostic := fun s => { message := s }

/-- Lift an `Except String α` (the shape `SharedValidate` returns today) into
`Except LoweringDiagnostic α`. Provided so future shared helpers can return the
shared type without changing the existing `SharedError` alias. -/
def liftSharedError {α : Type} (result : Except String α) : Except LoweringDiagnostic α :=
  match result with
  | .ok value => .ok value
  | .error message => .error { message }

end ProofForge.Backend.Diagnostic