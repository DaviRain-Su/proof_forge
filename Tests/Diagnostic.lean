/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Phase 3 shared diagnostic smoke (RFC 0014)

Focused unit tests for `ProofForge.Backend.Diagnostic`. These exercise the
Phase 3 shared `LoweringDiagnostic` type and the `LoweringError` contract
without depending on any backend module:

  * `LoweringDiagnostic.render` outputs **only** the message — the single
    acceptance criterion for diagnostic-stability. The optional `backend?` /
    `severity` / `code?` fields must NOT participate in `render`, so backends
    delegating to the shared type see byte-identical output to their existing
    `<Name>.render := err.message`.
  * The raw-string and self adapters (the two trivial instances shipped in
    `Diagnostic.lean`) produce the expected diagnostic.
  * `liftSharedError` lifts the `Except String` shape used by `SharedValidate`
    today into `Except LoweringDiagnostic` without perturbing the message.

It deliberately does **not** test any backend's concrete error type — backend
adapter instances are follow-up work tracked in RFC 0014 Phase 3, not part of
this minimal stub.

Mirrors the harness style of `Tests/SharedValidate.lean`.
-/

import ProofForge.Backend.Diagnostic

namespace ProofForge.Tests.Diagnostic

open ProofForge.Backend.Diagnostic

def requireEqStr (actual expected : String) (message : String) : IO Bool := do
  if actual == expected then
    pure true
  else
    IO.eprintln s!"diagnostic: FAILED: {message}: expected {expected}, got {actual}"
    pure false

def requireOk (name : String) (result : Except String Unit) : IO Bool := do
  match result with
  | .ok _ =>
    IO.println s!"diagnostic: ok: {name}"
    pure true
  | .error message =>
    IO.eprintln s!"diagnostic: FAILED: {name}"
    IO.eprintln s!"  expected success, got: {message}"
    pure false

-- ---------------------------------------------------------------------------
-- LoweringDiagnostic.render ignores metadata fields
-- ---------------------------------------------------------------------------

def testRenderOutputsOnlyMessage : IO Bool := do
  -- Even with backend/severity/code populated, render must return the bare
  -- message. This is the byte-stability guarantee for backend delegation.
  let diag : LoweringDiagnostic :=
    { message := "probe expected `U64`, got `U32`"
      backend? := some "evm"
      severity := .error
      code? := some "type.mismatch" }
  requireEqStr diag.render "probe expected `U64`, got `U32`"
    "LoweringDiagnostic.render ignores metadata"

def testRenderOfEmptyMessage : IO Bool := do
  let diag : LoweringDiagnostic := { message := "" }
  requireEqStr diag.render "" "LoweringDiagnostic.render of empty message"

def testFromStringDefaultsError : IO Bool := do
  let diag := LoweringDiagnostic.fromString "boom"
  let ok := diag.severity == .error && diag.render == "boom"
  if ok then
    IO.println "diagnostic: ok: fromString defaults to .error and bare message"
    pure true
  else
    IO.eprintln "diagnostic: FAILED: fromString should default to .error severity"
    pure false

-- ---------------------------------------------------------------------------
-- Adapters
-- ---------------------------------------------------------------------------

def testStringAdapter : IO Bool := do
  -- The raw-string adapter must wrap a bare string into the shared shape.
  let diag : LoweringDiagnostic := LoweringError.toDiagnostic "raw error"
  requireEqStr diag.render "raw error" "LoweringError String adapter renders message"

def testSelfAdapter : IO Bool := do
  -- The identity adapter must be a no-op.
  let diag : LoweringDiagnostic := { message := "self" }
  let diag' : LoweringDiagnostic := LoweringError.toDiagnostic diag
  requireEqStr diag'.render "self" "LoweringError LoweringDiagnostic identity adapter"

def testRenderDefaultUsesToDiagnostic : IO Bool := do
  -- The class default `render` must delegate to `toDiagnostic |> render`.
  -- Verifiable without a backend: the String instance's `render` (inherited
  -- default) must equal the shared diagnostic render of the same string.
  let s := "shared-default"
  let viaClass : String := LoweringError.render s
  let viaDiag : String := (LoweringError.toDiagnostic s).render
  requireEqStr viaClass viaDiag "LoweringError.render default matches toDiagnostic.render"

-- ---------------------------------------------------------------------------
-- fromTargetDiagnostic preserves the message verbatim
-- ---------------------------------------------------------------------------

def testFromTargetDiagnostic : IO Bool := do
  let td : ProofForge.Target.Diagnostic := { message := "capability `x` is not supported" }
  let diag := LoweringDiagnostic.fromTargetDiagnostic td
  requireEqStr diag.render "capability `x` is not supported"
    "LoweringDiagnostic.fromTargetDiagnostic preserves message"

-- ---------------------------------------------------------------------------
-- liftSharedError lifts the SharedValidate Except String shape
-- ---------------------------------------------------------------------------

def testLiftSharedErrorOk : IO Bool := do
  let r : Except String Unit := .ok ()
  match liftSharedError r with
  | .ok _ =>
    IO.println "diagnostic: ok: liftSharedError preserves ok"
    pure true
  | .error diag =>
    IO.eprintln s!"diagnostic: FAILED: liftSharedError should preserve ok, got {diag.render}"
    pure false

def testLiftSharedErrorErr : IO Bool := do
  let r : Except String Unit := .error "probe expected `U64`, got `U32`"
  match liftSharedError r with
  | .ok _ =>
    IO.eprintln "diagnostic: FAILED: liftSharedError should lift error"
    pure false
  | .error diag =>
    requireEqStr diag.render "probe expected `U64`, got `U32`"
      "liftSharedError preserves error message"

-- ---------------------------------------------------------------------------
-- Main harness
-- ---------------------------------------------------------------------------

def main : IO UInt32 := do
  let mut failures := 0
  let cases : Array (IO Bool) := #[
    testRenderOutputsOnlyMessage,
    testRenderOfEmptyMessage,
    testFromStringDefaultsError,
    testStringAdapter,
    testSelfAdapter,
    testRenderDefaultUsesToDiagnostic,
    testFromTargetDiagnostic,
    testLiftSharedErrorOk,
    testLiftSharedErrorErr
  ]
  for test in cases do
    let ok ← test
    if !ok then
      failures := failures + 1
  if failures == 0 then
    IO.println s!"diagnostic: {cases.size} cases passed"
    pure 0
  else
    IO.eprintln s!"diagnostic: {failures} case(s) failed"
    pure 1

end ProofForge.Tests.Diagnostic

def main : IO UInt32 :=
  ProofForge.Tests.Diagnostic.main