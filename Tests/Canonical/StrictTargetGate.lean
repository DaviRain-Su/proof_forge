/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Strict Canonical Target Gate — Primary-Triad Positive Fixtures

Tests `runStrictCanonicalTargetGate` and `runStrictCanonicalContractGate`
on the primary-triad targets (`evm`, `solana-sbpf-asm`, `wasm-near`) using
the Counter and ValueVault IR fixtures.  Every target must pass every
stage — adapter, validator, capability planner, host-op handler check,
and `buildFromCore` — without any advisory fallback.

Failure-mode coverage (adapter, validator, host-op, builder, unknown
target) lives in `Tests/Canonical/StrictIntentMaterialization.lean`.
-/

import ProofForge.Compiler.CanonicalPipeline
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.Contract.Spec

open ProofForge.Compiler
open ProofForge.IR
open ProofForge.Contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def requireOk (result : Except String α) (label : String) : IO Unit :=
  match result with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"{label}: expected success, got: {e}"

def requireErrorPrefix (expectedPrefix : String) (result : Except String α) : IO Unit :=
  match result with
  | .ok _ => throw <| IO.userError s!"expected error starting with `{expectedPrefix}`, got success"
  | .error e => require (e.startsWith expectedPrefix)
      s!"expected error starting with `{expectedPrefix}`, got: {e}"

/-- Counter fixture as a ContractSpec. Selectors are kept because the EVM
builder requires them; Solana and NEAR builders ignore them. -/
def counterSpec : ContractSpec :=
  ContractSpec.fromIR ProofForge.IR.Examples.Counter.module

/-- ValueVault fixture as a ContractSpec. -/
def vaultSpec : ContractSpec :=
  ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module

def primaryTriad : Array String := #["evm", "solana-sbpf-asm", "wasm-near"]

def main : IO Unit := do
  -- -- Test 1: Counter passes the strict gate on every primary-triad target --
  for targetId in primaryTriad do
    requireOk (runStrictCanonicalTargetGate targetId counterSpec)
      s!"strict gate: Counter on {targetId}"

  -- -- Test 2: ValueVault passes the strict gate on every primary-triad target --
  for targetId in primaryTriad do
    requireOk (runStrictCanonicalTargetGate targetId vaultSpec)
      s!"strict gate: ValueVault on {targetId}"

  -- -- Test 3: runStrictCanonicalContractGate works from a raw canonical contract --
  -- Counter via adaptLegacy -> validateCanonical -> strict planning
  let bundle ← match ProofForge.IR.Legacy.Adapter.adaptLegacy counterSpec with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"adaptLegacy failed: {repr e}"
  for targetId in primaryTriad do
    requireOk (runStrictCanonicalContractGate targetId bundle.contract.contract)
      s!"strict contract gate: Counter on {targetId}"

  -- -- Test 4: strict gate rejects a truly unknown target with a named diagnostic --
  requireErrorPrefix "canonical: unknown target"
    (runStrictCanonicalTargetGate "nonexistent-target" counterSpec)

  -- -- Test 5: strict gate rejects a non-primary registered target with a
  -- capability or buildFromCore diagnostic (not unknown target, but still
  -- a hard error — verifying the gate does not silently accept it) --
  let nonPrimaryResult := runStrictCanonicalTargetGate "wasm-cosmwasm" counterSpec
  match nonPrimaryResult with
  | .ok _ => throw <| IO.userError "strict gate accepted wasm-cosmwasm (non-primary target)"
  | .error _ => pure ()  /- capability or buildFromCore rejection is correct -/

  -- -- Test 6: advisory gate and strict gate agree on success --
  -- Both gates must return the same result for a known-good spec.
  for targetId in primaryTriad do
    match runCanonicalValidationGate targetId counterSpec,
          runStrictCanonicalTargetGate targetId counterSpec with
    | .ok _, .ok _ => pure ()
    | .error e1, .error e2 =>
      -- Both rejected is fine, but both must reject (not just one)
      IO.println s!"  note: {targetId} rejected by both gates (advisory: {e1.take 60}…, strict: {e2.take 60}…)"
    | .ok _, .error e =>
      throw <| IO.userError s!"strict gate rejected {targetId} but advisory accepted: {e}"
    | .error e, .ok _ =>
      throw <| IO.userError s!"advisory gate rejected {targetId} but strict accepted: {e}"

  IO.println "strict-target-gate: ok"