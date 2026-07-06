/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Phase 1 shared validate smoke (RFC 0014)

Focused unit tests for `ProofForge.Backend.SharedValidate`. These exercise the
genuinely shared helpers extracted in Phase 1:

  * `ensureType` — the byte-identical type-equality diagnostic shared between
    EVM and NEAR (and Psy). Asserts both the success path and the exact
    rendered message on mismatch, since diagnostic stability is the #1
    Phase 1 acceptance criterion.
  * `sharedParamBindings` — the shared projection used by every backend's
    `entrypointTypeEnv`.
  * `statementAlwaysReturns` / `statementsAlwaysReturn` — the shared
    control-flow-returns predicate previously duplicated inside EVM
    (`Evm.Validate` + `Evm.IR`).

It deliberately does **not** test:

  * `validateCapabilities` — not shared (EVM resolves a CapabilityPlan,
    NEAR calls requireCapabilities).
  * The entrypoint return-path *check* — not shared (EVM analyses every
    control-flow path and special-cases fallback/receive; NEAR checks only
    the last statement).
  * Identifier validity — NEAR-only Rust rules.
  * `checkOwnership` — opt-in hook; NEAR/CosmWasm already cover it via
    `Tests/IROwnership.lean`.

Mirrors the harness style of `Tests/IROwnership.lean` and `Tests/EvmPlan.lean`.
-/

import ProofForge.Backend.SharedValidate
import ProofForge.IR.Contract

namespace ProofForge.Tests.SharedValidate

open ProofForge.IR
open ProofForge.Backend.SharedValidate

/-- Tiny entrypoint used to exercise `sharedParamBindings` / return-path
predicates without pulling in a full example module. -/
def sampleEntrypoint : Entrypoint := {
  name := "inc"
  params := #[("x", .u64), ("delta", .u32)]
  returns := .u64
  body := #[.return (.add (.local "x") (.cast (.local "delta") .u64))]
}

def sampleModule : Module := {
  name := "SharedValidateProbe"
  state := #[]
  entrypoints := #[sampleEntrypoint]
}

-- ---------------------------------------------------------------------------
-- ensureType
-- ---------------------------------------------------------------------------

def requireOk (name : String) (result : Except String Unit) : IO Bool := do
  match result with
  | .ok _ =>
    IO.println s!"shared-validate: ok: {name}"
    pure true
  | .error message =>
    IO.eprintln s!"shared-validate: FAILED: {name}"
    IO.eprintln s!"  expected success, got: {message}"
    pure false

def requireError (name : String) (result : Except String Unit) (expected : String) :
    IO Bool := do
  match result with
  | .error message =>
    if message == expected then
      IO.println s!"shared-validate: ok: {name}"
      pure true
    else
      IO.eprintln s!"shared-validate: FAILED: {name}"
      IO.eprintln s!"  expected: {expected}"
      IO.eprintln s!"  actual:   {message}"
      pure false
  | .ok _ =>
    IO.eprintln s!"shared-validate: FAILED: {name}"
    IO.eprintln "  expected a type mismatch error"
    pure false

def testEnsureTypeMatches : IO Bool := do
  pure <| ← requireOk "ensureType matching U64" (ensureType "probe" .u64 .u64)

def testEnsureTypeMismatchMessage : IO Bool := do
  -- The shared diagnostic is built only from ValueType.name, so it renders
  -- identically in EVM and NEAR. Pin the exact text to guard against drift.
  let expected := "probe expected `U64`, got `U32`"
  pure <| ← requireError "ensureType mismatch U64 vs U32"
    (ensureType "probe" .u64 .u32) expected

def testEnsureTypeStructMismatchMessage : IO Bool := do
  -- Struct types also render via ValueType.name; ensure the shared helper
  -- preserves the per-backend struct-type diagnostic shape.
  let expected := "field `owner` expected `Address`, got `Hash`"
  pure <| ← requireError "ensureType mismatch Address vs Hash"
    (ensureType "field `owner`" .address .hash) expected

-- ---------------------------------------------------------------------------
-- sharedParamBindings
-- ---------------------------------------------------------------------------

def requireEqNat (actual expected : Nat) (message : String) : IO Bool := do
  if actual == expected then
    pure true
  else
    IO.eprintln s!"shared-validate: FAILED: {message}: expected {expected}, got {actual}"
    pure false

def requireEqStr (actual expected : String) (message : String) : IO Bool := do
  if actual == expected then
    pure true
  else
    IO.eprintln s!"shared-validate: FAILED: {message}: expected {expected}, got {actual}"
    pure false

def testSharedParamBindings : IO Bool := do
  let bindings := sharedParamBindings sampleEntrypoint
  let mut ok := true
  ok := ok && (← requireEqNat bindings.size 2 "sharedParamBindings count")
  if bindings.size >= 1 then
    ok := ok && (← requireEqStr bindings[0]!.name "x" "sharedParamBindings[0].name")
    ok := ok && (← requireEqStr bindings[0]!.type.name "U64" "sharedParamBindings[0].type")
    ok := ok && (← requireEqNat (if bindings[0]!.isMutable then 1 else 0) 0
      "sharedParamBindings[0].isMutable=false")
  if bindings.size >= 2 then
    ok := ok && (← requireEqStr bindings[1]!.name "delta" "sharedParamBindings[1].name")
    ok := ok && (← requireEqStr bindings[1]!.type.name "U32" "sharedParamBindings[1].type")
  pure ok

def testSharedParamBindingsEmpty : IO Bool := do
  let ep : Entrypoint := { name := "noop", params := #[], returns := .unit, body := #[] }
  let bindings := sharedParamBindings ep
  pure <| ← requireEqNat bindings.size 0 "sharedParamBindings empty"

-- ---------------------------------------------------------------------------
-- statementAlwaysReturns / statementsAlwaysReturn
-- ---------------------------------------------------------------------------

def testReturnStatementAlwaysReturns : IO Bool := do
  let stmt : Statement := .return (.literal (.u64 0))
  let ok := statementAlwaysReturns stmt
  if ok then
    IO.println "shared-validate: ok: return statement always returns"
    pure true
  else
    IO.eprintln "shared-validate: FAILED: return statement should always return"
    pure false

def testNonReturnStatementDoesNotAlwaysReturn : IO Bool := do
  let stmt : Statement := .effect (.storageScalarRead "x")
  let ok := !statementAlwaysReturns stmt
  if ok then
    IO.println "shared-validate: ok: effect statement does not always return"
    pure true
  else
    IO.eprintln "shared-validate: FAILED: effect statement should not always return"
    pure false

def testBodyEndingInReturnAlwaysReturns : IO Bool := do
  -- A body whose last statement is a return is the EVM all-paths shape.
  let body : Array Statement :=
    #[.letBind "y" .u64 (.literal (.u64 1)), .return (.local "y")]
  let ok := statementsAlwaysReturn body
  if ok then
    IO.println "shared-validate: ok: body ending in return always returns"
    pure true
  else
    IO.eprintln "shared-validate: FAILED: body ending in return should always return"
    pure false

def testBodyWithoutReturnDoesNotAlwaysReturn : IO Bool := do
  -- No return anywhere: the all-paths predicate must be false.
  let body : Array Statement :=
    #[.letBind "y" .u64 (.literal (.u64 1))]
  let ok := !statementsAlwaysReturn body
  if ok then
    IO.println "shared-validate: ok: body without return does not always return"
    pure true
  else
    IO.eprintln "shared-validate: FAILED: body without return should not always return"
    pure false

def testIfElseBothBranchesReturn : IO Bool := do
  -- ifElse counts as returning on every path iff BOTH branches always return.
  let body : Array Statement :=
    #[.ifElse (.literal (.bool true))
        #[.return (.literal (.u64 1))]
        #[.return (.literal (.u64 0))]]
  let ok := statementsAlwaysReturn body
  if ok then
    IO.println "shared-validate: ok: if/else with both branches returning"
    pure true
  else
    IO.eprintln "shared-validate: FAILED: if/else with both branches returning should always return"
    pure false

def testIfElseOnlyOneBranchReturns : IO Bool := do
  -- Only one branch returns -> not all paths return.
  let body : Array Statement :=
    #[.ifElse (.literal (.bool true))
        #[.return (.literal (.u64 1))]
        #[]]
  let ok := !statementsAlwaysReturn body
  if ok then
    IO.println "shared-validate: ok: if/else with one branch returning does not always return"
    pure true
  else
    IO.eprintln "shared-validate: FAILED: if/else with one branch returning should not always return"
    pure false

-- ---------------------------------------------------------------------------
-- Optional ownership hook stub smoke
-- ---------------------------------------------------------------------------

def testCheckOwnershipAcceptsValidModule : IO Bool := do
  -- The sample module has no release statements; the ownership hook must pass.
  let ok := (match checkOwnership sampleModule with | .ok _ => true | .error _ => false)
  if ok then
    IO.println "shared-validate: ok: checkOwnership accepts release-free module"
    pure true
  else
    IO.eprintln "shared-validate: FAILED: checkOwnership should accept a release-free module"
    pure false

-- ---------------------------------------------------------------------------
-- Main harness
-- ---------------------------------------------------------------------------

def main : IO UInt32 := do
  let mut failures := 0
  let cases : Array (IO Bool) := #[
    testEnsureTypeMatches,
    testEnsureTypeMismatchMessage,
    testEnsureTypeStructMismatchMessage,
    testSharedParamBindings,
    testSharedParamBindingsEmpty,
    testReturnStatementAlwaysReturns,
    testNonReturnStatementDoesNotAlwaysReturn,
    testBodyEndingInReturnAlwaysReturns,
    testBodyWithoutReturnDoesNotAlwaysReturn,
    testIfElseBothBranchesReturn,
    testIfElseOnlyOneBranchReturns,
    testCheckOwnershipAcceptsValidModule
  ]
  for test in cases do
    let ok ← test
    if !ok then
      failures := failures + 1
  if failures == 0 then
    IO.println s!"shared-validate: {cases.size} cases passed"
    pure 0
  else
    IO.eprintln s!"shared-validate: {failures} case(s) failed"
    pure 1

end ProofForge.Tests.SharedValidate

def main : IO UInt32 :=
  ProofForge.Tests.SharedValidate.main
