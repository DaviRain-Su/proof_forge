import ProofForge.IR.Contract
import ProofForge.Target
import ProofForge.Target.Preflight
import ProofForge.IR.Examples.Counter

namespace ProofForge.Tests.PreflightL2

open ProofForge.IR
open ProofForge.Target
open ProofForge.Target.Preflight

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure ()
  else throw <| IO.userError message

/-- U128 module: previously rejected, now accepted by NEAR EmitWat after P1-NEAR-2. -/
def u128Module : Module := {
  name := "U128Probe"
  state := #[{ id := "x", kind := .scalar, type := .u128 }]
  entrypoints := #[{
    name := "get"
    kind := .function
    returns := .u128
    body := #[.return (.effect (.storageScalarRead "x"))]
  }]
}

/-- U128 literal exceeding U64 range: passes L1 (U128 is a supported capability) but
fails L2 EmitWat rendering (full U128 literal lowering not yet supported). -/
def u128LargeLiteralModule : Module := {
  name := "U128LargeLiteralProbe"
  state := #[{ id := "x", kind := .scalar, type := .u128 }]
  entrypoints := #[{
    name := "get"
    kind := .function
    returns := .u128
    body := #[.return (.literal (.u128 18446744073709551616))]  -- 2^64, exceeds U64 range
  }]
}

/-- PF-P1-04: readyToMaterialize requires L2 backend fragment validation when registered. -/
def main : IO UInt32 := do
  -- Counter is ready on primary triad after L0+L1+L2.
  let counter := ProofForge.IR.Examples.Counter.module
  for id in #["evm", "solana-sbpf-asm", "wasm-near"] do
    let profile ← match find? id with
      | some p => pure p
      | none => throw <| IO.userError s!"missing {id}"
    let r := run profile counter
    require r.capabilityOk s!"{id} Counter capabilityOk"
    require r.portabilityOk s!"{id} Counter portabilityOk"
    require r.backendOk s!"{id} Counter backendOk: {r.note}"
    require r.readyToMaterialize
      s!"{id} Counter must be ready after L0+L1+L2: {r.note}"
    require (r.backendStage == "passed")
      s!"{id} backendStage should be passed, got {r.backendStage}"

  -- Secondary without L2 hooks: backend stage notRegistered; L0+L1 still gates ready.
  let cosmwasm ← match find? "wasm-cosmwasm" with
    | some p => pure p
    | none => throw <| IO.userError "missing cosmwasm"
  let rCw := run cosmwasm counter
  require (rCw.backendStage == "notRegistered")
    s!"cosmwasm should not register L2 hooks yet: {rCw.backendStage}"
  -- Counter on cosmwasm may fail L1 capability — only assert stage.

  -- NEAR now accepts U128 at L2 after P1-NEAR-2 (EmitWat supports U128 scalar state + return).
  let near ← match find? "wasm-near" with
  | some p => pure p
  | none => throw <| IO.userError "missing near"
  let rU128 := run near u128Module
  require rU128.backendOk s!"L2 must accept U128 after P1-NEAR-2: {rU128.note}"
  require (rU128.backendStage == "passed")
    s!"U128 backendStage should be passed, got {rU128.backendStage}"

  -- NEAR rejects U128 literal exceeding U64 range at L2 (EmitWat rendering fails).
  let rBad := run near u128LargeLiteralModule
  require (!rBad.backendOk) s!"L2 must reject large U128 literal: {rBad.note}"
  require (!rBad.readyToMaterialize)
    s!"readyToMaterialize must be false when L2 fails: {rBad.note}"
  match rBad.backendError? with
  | none => throw <| IO.userError "backendError? must carry L2 diagnostic"
  | some err =>
      require (err.contains "U128" || err.contains "not supported")
        s!"L2 diagnostic should match U128 literal reject, got: {err}"

  IO.println "PreflightL2: ok"
  return 0

end ProofForge.Tests.PreflightL2

def main : IO UInt32 :=
  ProofForge.Tests.PreflightL2.main
