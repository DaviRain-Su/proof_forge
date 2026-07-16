import ProofForge.Frontend.Surface
import ProofForge.IR.Core.Semantics

/-! Task 13 semantic parity: independently execute Surface and normalized Core. -/

open ProofForge.Frontend.Surface
open ProofForge.IR.Core
open ProofForge.IR.Core.Semantics

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def host : HostSemantics where
  handle call _ _ := .error (.unknownHostOp call.id)
  handleContext field := .error (.unsupportedContext field)
  handleHash _ := .error .unsupportedHash
  handleCrosscall request _ := .error (.unsupportedCrosscall request.mode)

def emptySurfaceState : SurfaceRuntimeState := { storage := {}, events := #[] }
def emptyCoreState : LogicalState := { storage := fun _ => none }

def coreStorageNat (state : LogicalState) (id : Nat) : Option Nat :=
  match state.storage ⟨id⟩ with
  | some (.scalar (.u64 value)) => some value.toNat
  | _ => none

def coreEvent (effect : ObservableEffect) : Option (Nat × Array Nat) :=
  match effect with
  | .emit id args =>
      let values := args.map fun value => match value with | .u64 n => n.toNat | _ => 0
      some (id.value, values)
  | _ => none

def runStep (contract : SurfaceContract) (entrypoint : String) (functionId : Nat)
    (args : Array Nat) (surfaceState : SurfaceRuntimeState) (coreState : LogicalState) :
    IO (SurfaceRuntimeState × LogicalState × CoreValue) := do
  let beforeEvents := surfaceState.events.size
  let surface ← match runEntrypoint contract entrypoint args surfaceState with
    | .ok state => pure state
    | .error e => throw <| IO.userError s!"Surface `{entrypoint}` failed: {e}"
  let bundle ← match normalizeSurface contract with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"normalize `{entrypoint}` failed: {repr e}"
  let coreArgs := args.map (fun n => CoreValue.u64 n.toUInt64)
  let core ← match execute host 100 bundle.contract ⟨functionId⟩ coreArgs coreState with
    | .ok result => pure result
    | .error e => throw <| IO.userError s!"Core `{entrypoint}` failed: {repr e}"
  for state in bundle.contract.contract.materialization.stateSymbols do
    require (surface.storage.get? state.name == coreStorageNat core.finalState state.stateId.value)
      s!"storage mismatch after `{entrypoint}` at `{state.name}`"
  let surfaceDelta := (surface.events.extract beforeEvents surface.events.size).map fun event =>
    let eventId := contract.events.findIdx? (fun declaration => declaration.name == event.1) |>.getD contract.events.size
    (eventId, event.2)
  let coreEvents := core.trace.effects.filterMap coreEvent
  require (surfaceDelta == coreEvents) s!"event mismatch after `{entrypoint}`"
  return (surface, core.finalState, core.returnValue)

def counter : SurfaceContract := {
  name := "Counter", structs := #[],
  state := #[{ name := "count", kind := .scalar .u64 }], events := #[], errors := #[],
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call, params := #[], retType := .unit,
      body := #[.stateWrite "count" (.literal (.u64Lit 0))] },
    { name := "increment", kind := .function, mutability := .call, params := #[], retType := .unit,
      body := #[.stateWrite "count" (.arith .add true (.stateRead "count") (.literal (.u64Lit 1)))] },
    { name := "get", kind := .function, mutability := .view, params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "count")] }
  ], constructorParams := #[], constructorBindings := #[]
}

def vault : SurfaceContract := {
  name := "ValueVault", structs := #[],
  state := #[{ name := "balance", kind := .scalar .u64 }, { name := "released", kind := .scalar .u64 }],
  events := #[
    { name := "Deposited", fields := #[{ name := "amount", type := .u64, indexed := false }] },
    { name := "Released", fields := #[{ name := "amount", type := .u64, indexed := false }] }
  ], errors := #[],
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      params := #[{ name := "initial", type := .u64 }], retType := .unit,
      body := #[.stateWrite "balance" (.local "initial"), .stateWrite "released" (.literal (.u64Lit 0))] },
    { name := "deposit", kind := .function, mutability := .call,
      params := #[{ name := "amount", type := .u64 }], retType := .unit,
      body := #[.stateWrite "balance" (.arith .add true (.stateRead "balance") (.local "amount")),
        .emit "Deposited" #[.local "amount"]] },
    { name := "release", kind := .function, mutability := .call,
      params := #[{ name := "amount", type := .u64 }], retType := .unit,
      body := #[.stateWrite "balance" (.arith .sub true (.stateRead "balance") (.local "amount")),
        .stateWrite "released" (.arith .add true (.stateRead "released") (.local "amount")),
        .emit "Released" #[.local "amount"]] }
  ], constructorParams := #[], constructorBindings := #[]
}

def main : IO Unit := do
  let (c1, cs1, _) ← runStep counter "initialize" 0 #[] emptySurfaceState emptyCoreState
  let (c2, cs2, _) ← runStep counter "increment" 1 #[] c1 cs1
  let (_, _, result) ← runStep counter "get" 2 #[] c2 cs2
  require (result == .u64 1) "Counter return mismatch"

  let (v1, vs1, _) ← runStep vault "initialize" 0 #[100] emptySurfaceState emptyCoreState
  let (v2, vs2, _) ← runStep vault "deposit" 1 #[25] v1 vs1
  let (v3, vs3, _) ← runStep vault "release" 2 #[20] v2 vs2
  require (v3.storage.get? "balance" == some 105) "ValueVault balance mismatch"
  require (coreStorageNat vs3 1 == some 20) "ValueVault released mismatch"

  let overflowState : SurfaceRuntimeState := { emptySurfaceState with
    storage := ({} : Std.HashMap String Nat).insert "count" 18446744073709551615 }
  match runEntrypoint counter "increment" #[] overflowState with
  | .error "arithmeticOverflow" => pure ()
  | result => throw <| IO.userError s!"Surface checked overflow did not fail: {repr result}"
  let overflowBundle ← match normalizeSurface counter with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"overflow normalization failed: {repr e}"
  let overflowCoreState : LogicalState := {
    storage := fun id => if id == ⟨0⟩ then
      some (.scalar (.u64 18446744073709551615)) else none }
  match execute host 100 overflowBundle.contract ⟨1⟩ #[] overflowCoreState with
  | .error .arithmeticOverflow => pure ()
  | result => throw <| IO.userError s!"Core checked overflow did not fail: {repr result}"

  IO.println "surface-parity: ok"
