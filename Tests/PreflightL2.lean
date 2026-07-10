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

/-- U128 is rejected by NEAR EmitWat production path (same diagnostic as build). -/
def unsupportedU128Module : Module := {
  name := "U128Probe"
  state := #[{ id := "x", kind := .scalar, type := .u128 }]
  entrypoints := #[{
    name := "get"
    kind := .function
    returns := .u128
    body := #[.return (.effect (.storageScalarRead "x"))]
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

  -- NEAR rejects U128 at L2 with the same EmitWat diagnostic as build (PF-P1-04).
  let near ← match find? "wasm-near" with
    | some p => pure p
    | none => throw <| IO.userError "missing near"
  let rBad := run near unsupportedU128Module
  require (!rBad.backendOk) s!"L2 must reject U128: {rBad.note}"
  require (!rBad.readyToMaterialize)
    s!"readyToMaterialize must be false when L2 fails: {rBad.note}"
  match rBad.backendError? with
  | none => throw <| IO.userError "backendError? must carry L2 diagnostic"
  | some err =>
      require (err.contains "U128" || err.contains "not supported")
        s!"L2 diagnostic should match build-style U128 reject, got: {err}"

  IO.println "PreflightL2: ok"
  return 0

end ProofForge.Tests.PreflightL2

def main : IO UInt32 :=
  ProofForge.Tests.PreflightL2.main
