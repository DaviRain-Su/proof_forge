import ProofForge.Frontend.Surface
import ProofForge.IR.Core.Semantics
import TestFixtures.SurfaceProducts.SetRegistry

/-! Task 15 semantic parity between Surface Set expansion and Core execution. -/

open ProofForge.Frontend.Surface
open ProofForge.IR.Core
open ProofForge.IR.Core.Semantics

def testSet := TestFixtures.SurfaceProducts.SetRegistry.registry
def setContract := TestFixtures.SurfaceProducts.SetRegistry.contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def host : HostSemantics where
  handle call _ _ := .error (.unknownHostOp call.id)
  handleContext field := .error (.unsupportedContext field)
  handleHash _ := .error .unsupportedHash
  handleCrosscall request _ := .error (.unsupportedCrosscall request.mode)

def surfaceEmpty : SurfaceRuntimeState := { storage := {}, maps := {}, events := #[] }
def coreEmpty : LogicalState := { storage := fun _ => none }

def surfaceMember (state : SurfaceRuntimeState) (key : Nat) : Nat :=
  let entries := state.maps.get? testSet.membersName |>.getD #[]
  (entries.find? (fun entry => entry.1 == key)).map (fun entry => entry.2) |>.getD 0

def coreMember (state : LogicalState) (key : Nat) : Nat :=
  match state.storage ⟨0⟩ with
  | some (.map _ _ _ entries) =>
      match entries.find? (fun entry => entry.1 == .u64 key.toUInt64) with
      | some (_, .bool value) => if value then 1 else 0
      | _ => 0
  | _ => 0

def coreCardinality (state : LogicalState) : Option Nat :=
  match state.storage ⟨1⟩ with
  | some (.scalar (.u64 value)) => some value.toNat
  | _ => none

def runStep (name : String) (id : Nat) (args : Array Nat)
    (surfaceState : SurfaceRuntimeState) (coreState : LogicalState) :
    IO (SurfaceRuntimeState × LogicalState × CoreValue) := do
  let surface ← match runEntrypoint setContract name args surfaceState with
    | .ok state => pure state
    | .error e => throw <| IO.userError s!"Surface {name}: {e}"
  let bundle ← match normalizeSurface setContract with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"normalize Set: {repr e}"
  let core ← match execute host 100 bundle.contract ⟨id⟩
      (args.map fun value => .u64 value.toUInt64) coreState with
    | .ok result => pure result
    | .error e => throw <| IO.userError s!"Core {name}: {repr e}"
  require (surface.storage.get? testSet.cardinalityName == coreCardinality core.finalState)
    s!"cardinality mismatch after {name}"
  for key in #[1, 2, 3] do
    require (surfaceMember surface key == coreMember core.finalState key)
      s!"membership mismatch after {name} for {key}"
  return (surface, core.finalState, core.returnValue)

def main : IO Unit := do
  let (s0, c0, _) ← runStep "initialize" 0 #[] surfaceEmpty coreEmpty
  let (s1, c1, _) ← runStep "insert" 1 #[1] s0 c0
  require (s1.storage.get? testSet.cardinalityName == some 1) "first insert cardinality"
  let (s2, c2, _) ← runStep "insert" 1 #[1] s1 c1
  require (s2.storage.get? testSet.cardinalityName == some 1) "duplicate insert changed cardinality"
  let (s3, c3, _) ← runStep "insert" 1 #[2] s2 c2
  require (s3.storage.get? testSet.cardinalityName == some 2) "isolated key insert"
  let (s4, c4, _) ← runStep "remove" 2 #[3] s3 c3
  require (s4.storage.get? testSet.cardinalityName == some 2) "absent remove changed cardinality"
  let (s5, c5, _) ← runStep "remove" 2 #[1] s4 c4
  require (s5.storage.get? testSet.cardinalityName == some 1) "present remove cardinality"
  let (surfaceContains, _, coreContains) ← runStep "contains" 3 #[2] s5 c5
  require (surfaceContains.returnValue == some 1 && coreContains == .bool true) "contains present"
  let (surfaceMissing, _, coreMissing) ← runStep "contains" 3 #[1] s5 c5
  require (surfaceMissing.returnValue == some 0 && coreMissing == .bool false) "contains removed"
  IO.println "set-parity: ok"
