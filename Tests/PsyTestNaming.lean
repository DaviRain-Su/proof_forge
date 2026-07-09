/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Unit tests for `ProofForge.Backend.Psy.Plan.snakeCase` and the generalized
`testFunctionName`. Locks in the P1-02 refactor that replaced 24 hardcoded
fixture-name branches with a single CamelCase → snake_case derivation, so any
future `contract_source` module gets a deterministic test name without a
codegen-core special case.
-/
import ProofForge.Backend.Psy.Plan
import ProofForge.IR.Contract

namespace ProofForge.Tests.PsyTestNaming

open ProofForge.Backend.Psy.Plan
open ProofForge.IR

def checkEq (label : String) (actual expected : String) : IO Bool := do
  if actual == expected then
    IO.println s!"psy-test-naming: ok: {label}"
    pure true
  else
    IO.eprintln s!"psy-test-naming: FAILED: {label}"
    IO.eprintln s!"  expected: {expected}"
    IO.eprintln s!"  actual:   {actual}"
    pure false

/-- A synthetic module for the general-source test-name case. -/
def syntheticModule (name : String) : Module := { name := name, state := #[], entrypoints := #[] }

def main : IO UInt32 := do
  let mut failures : Nat := 0
  let cases : Array (String × String) := #[
    ("Counter", "counter"),
    ("U32HashPackingProbe", "u32_hash_packing_probe"),
    ("U32StorageScalarProbe", "u32_storage_scalar_probe"),
    ("U32ArithmeticProbe", "u32_arithmetic_probe"),
    ("StorageNestedAggregateProbe", "storage_nested_aggregate_probe"),
    ("NestedAggregateProbe", "nested_aggregate_probe"),
    ("AbiAggregateProbe", "abi_aggregate_probe"),
    ("StructArrayProbe", "struct_array_probe"),
    ("BoolStorageScalarProbe", "bool_storage_scalar_probe"),
    ("ExpressionPredicateProbe", "expression_predicate_probe"),
    ("ElseIfProbe", "else_if_probe"),
    ("HashStorageProbe", "hash_storage_probe"),
    ("GenericEntrypointProbe", "generic_entrypoint_probe"),
    -- general-source (not a known fixture) must still derive a stable name
    ("ValueVault", "value_vault"),
    ("RoleGatedToken", "role_gated_token")
  ]
  for (input, expected) in cases do
    let ok ← checkEq s!"snakeCase {input}" (snakeCase input) expected
    if !ok then failures := failures + 1

  -- testFunctionName: Counter keeps its lifecycle name; everything else is derived
  let nameCases : Array (String × String) := #[
    ("Counter", "test_counter_lifecycle"),
    ("U32HashPackingProbe", "test_u32_hash_packing_probe_fixture"),
    ("ValueVault", "test_value_vault_fixture"),
    ("RoleGatedToken", "test_role_gated_token_fixture")
  ]
  for (moduleName, expected) in nameCases do
    let actual := testFunctionName (syntheticModule moduleName)
    let ok ← checkEq s!"testFunctionName {moduleName}" actual expected
    if !ok then failures := failures + 1

  if failures == 0 then
    IO.println s!"psy-test-naming: {cases.size + nameCases.size} cases passed"
    pure 0
  else
    IO.eprintln s!"psy-test-naming: {failures} case(s) failed"
    pure 1

end ProofForge.Tests.PsyTestNaming

def main : IO UInt32 :=
  ProofForge.Tests.PsyTestNaming.main
