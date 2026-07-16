/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Phase 1 shared validate subset (RFC 0014)

This module is the **Phase 1** landing of
[RFC 0014](../../docs/rfcs/0014-unified-semantic-lowering-contract.md) and the
"Shared validate subset" section of
[`docs/target-lowering-interface.md`](../../docs/target-lowering-interface.md).

Phase 1's scope is deliberately narrow: extract only the validation helpers
that are **genuinely duplicated** between `ProofForge.Backend.Evm.Validate` /
`ProofForge.Backend.Evm.IR` and `ProofForge.Backend.WasmHost.IR` *with
byte-identical behavior*. Diagnostic-message stability is the #1 acceptance
criterion (see `Tests/Backend/Solana/SolanaDiagnostics.lean`, EVM diagnostic smokes), so this
module owns only helpers that either:

  * produce **no diagnostic of their own** (pure predicates / environment
    builders such as `entrypointTypeEnv`, `statementAlwaysReturns`); or
  * produce a diagnostic whose text depends **only** on `ValueType.name`,
    which is shared IR (`ProofForge.IR.Contract.ValueType`) and therefore
    renders identically in every backend (e.g. `ensureType`).

Everything that depends on a per-backend rule — `validateCapabilities`
(EVM resolves a `CapabilityPlan`, NEAR calls `requireCapabilities`),
entrypoint return-path *checks* (EVM analyses every control-flow path and
special-cases fallback/receive; NEAR only checks the last statement),
identifier validity (NEAR-only Rust rules), storage/struct type whitelists,
`ensureNumericType` (EVM returns a type incl. U8; NEAR returns Unit on
U32/U64) — stays in its own backend. Forcing any of those into a shared
signature would change observable diagnostics and trigger golden churn, which
RFC 0014 explicitly forbids for Phase 1.

The optional ownership hook (`IR.Ownership.checkModule`) is left as a
documented stub: NEAR/CosmWasm already wire it from `EmitWat.renderCheckedModule`,
and EVM/Psy/Solana opt-in is deferred per the constraint that Phase 1 must not
introduce new ownership failures.

## Phase 3 migration (2026-07-07)

The helpers now return `Except LoweringDiagnostic α` instead of
`Except String α`. `SharedError` is now an alias for `LoweringDiagnostic`
(see `ProofForge.Backend.Diagnostic`). The `message` text produced by each
helper is byte-identical to the Phase 1 output — only the error *type*
changed, not the error *content*. Each backend call site that previously
pattern-matched `.error message` now pattern-matches `.error diag` and folds
`diag.message` into its own concrete `LowerError`, preserving byte-identical
`.render` output. `Tests/SharedValidate.lean` pins the exact message bytes
(`testEnsureTypeMismatchMessage`).
-/

import ProofForge.Backend.Diagnostic
import ProofForge.IR.Contract
import ProofForge.IR.Ownership

namespace ProofForge.Backend.SharedValidate

open ProofForge.IR
open ProofForge.Backend.Diagnostic

/-- A minimal, backend-neutral error type used by the shared helpers.

Phase 3 migrated this alias from `String` to `LoweringDiagnostic`. Every
primary backend models its `LowerError` as a thin wrapper around a
`message : String` (see `Evm.Validate.LowerError`, `WasmNear.IR.LowerError`),
and each now carries a trivial `LoweringError` adapter instance (RFC 0014
Phase 3). The shared helpers therefore return `Except LoweringDiagnostic α`
and each call site folds the shared diagnostic into its own `LowerError` via
its adapter. `LoweringDiagnostic.render` outputs only `message`, so the
rendered bytes are identical to the previous `Except String` shape. -/
abbrev SharedError := LoweringDiagnostic

/-! ## Type-checking helpers shared across backends

`ensureType` is byte-identical between `Evm.Validate`, `Evm.IR`, `WasmNear.IR`,
and `Psy.IR`. Because the diagnostic is built only from `ValueType.name`
(defined on the shared `ProofForge.IR.ValueType`), the rendered message is
identical in every backend, so delegating to this implementation cannot
change any golden diagnostic. -/

/-- Ensure `expected == actual`, failing with a shared diagnostic of the form
``{context} expected `{expected.name}`, got `{actual.name}```. The message
shape matches the pre-existing per-backend implementations verbatim. -/
def ensureType (context : String) (expected actual : ValueType) :
    Except SharedError Unit :=
  if expected == actual then
    .ok ()
  else
    .error { message := s!"{context} expected `{expected.name}`, got `{actual.name}`" }

/-! ## Entry-point environment construction

`entrypointTypeEnv` is byte-identical between `Evm.Validate`, `Evm.IR`, and
`WasmNear.IR`. It builds a `TypeEnv`-shaped array from an entrypoint's
parameters; it produces no diagnostic. Backends keep their own `TypeEnv` /
`LocalBinding` types (their fields can grow per-backend), so this helper
returns the shared `ProofForge.IR.Entrypoint.params` projection that each
backend can map into its own `TypeEnv`. -/

structure ParamBinding where
  name : String
  type : ValueType
  isMutable : Bool
  deriving Repr, BEq

/-- Explicit `Inhabited` instance: `ValueType` itself does not derive
`Inhabited`, so Lean cannot auto-derive one for `ParamBinding`. We anchor the
default on `.unit` so the instance is deterministic. -/
instance : Inhabited ParamBinding := ⟨{ name := "", type := .unit, isMutable := false }⟩

/-- Project an entrypoint's parameters into shared `(name, type, isMutable=false)`
bindings. Backends fold this into their own `TypeEnv` (e.g.
`Evm.Validate.entrypointTypeEnv` becomes `sharedParamBindings entrypoint |>.toArray`
mapped into `LocalBinding`). -/
def sharedParamBindings (entrypoint : Entrypoint) : Array ParamBinding :=
  entrypoint.params.map fun param =>
    { name := param.fst, type := param.snd, isMutable := false }

/-! ## Control-flow return-path predicate

`statementAlwaysReturns` / `statementsAlwaysReturn` are byte-identical between
`Evm.Validate` (L1548-1558) and `Evm.IR` (L3460-3471). They are pure
predicates over `ProofForge.IR.Statement` and produce no diagnostic. Extracting
them removes the within-EVM duplication and gives every backend a single
canonical control-flow-returns predicate to build on.

IMPORTANT: this predicate is **not** the same as NEAR's `bodyEndsWithReturn`,
which only checks that the *last* statement is a `return`. NEAR's syntactic
check stays in `WasmNear.IR`. The shared predicate here is the stronger
all-paths analysis that EVM already uses; NEAR is *not* migrated onto it in
Phase 1 because doing so would change NEAR's observable diagnostics. -/
mutual
  partial def statementAlwaysReturns : Statement → Bool
    | .return _ => true
    | .ifElse _ thenBody elseBody =>
        statementsAlwaysReturn thenBody && statementsAlwaysReturn elseBody
    | .boundedFor _ start stopExclusive body =>
        start < stopExclusive && statementsAlwaysReturn body
    | _ => false

  partial def statementsAlwaysReturn (statements : Array Statement) : Bool :=
    statements.any statementAlwaysReturns
end

/-! ## Optional ownership hook (Phase 1 stub)

Per RFC 0014 Phase 1 and the user constraint that Phase 1 must not introduce
new ownership failures, the ownership hook into `ProofForge.IR.Ownership.checkModule`
is provided here as a **documented, opt-in** helper. It is *not* wired into
EVM/Psy/Solana in Phase 1 (those backends do not lower owned heap today).
NEAR/CosmWasm already call `IR.Ownership.checkModule` directly from
`EmitWat.renderCheckedModule`; that call site is unchanged.

A backend that wishes to opt in can call `checkOwnership module` and fold the
`OwnershipError` message into its own `LowerError`. The render format matches
`IR.Ownership.OwnershipError.render` so backends that already surface that
text (NEAR/CosmWasm) see no change. -/

/-- Run the IR ownership checker and surface its rendered message as a shared
diagnostic. Opt-in: backends that lower owned heap (NEAR, CosmWasm) already call
`IR.Ownership.checkModule` directly; EVM/Psy/Solana are NOT wired in Phase 1. -/
def checkOwnership (module : Module) : Except SharedError Unit :=
  match ProofForge.IR.Ownership.checkModule module with
  | .ok _ => .ok ()
  | .error err => .error { message := err.render }

end ProofForge.Backend.SharedValidate
