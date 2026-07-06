import ProofForge.Backend.Quint.Lower
import ProofForge.Backend.Quint.ITF
import ProofForge.Backend.Quint.Replay
import ProofForge.Backend.Quint.GuardAst
import ProofForge.IR.Examples.EvmStorageStructProbe

namespace Tests.Quint.StructDynamicPathReplay

open ProofForge.Backend.Quint
open ProofForge.Backend.Quint.GuardAst

def scenario : Scenario.Config := { maxUint := 1, users := #["alice"], indexFromZero := true }

def generateModel : IO String :=
  match Lower.renderModule ProofForge.IR.Examples.EvmStorageStructProbe.emitQuintDynamicStructPathModule scenario with
  | .ok s => pure s
  | .error e => throw (IO.userError s!"lower failed: {e.message}")

def runQuint (qntPath itfPath : String) : IO Unit := do
  let out ← IO.Process.output {
    cmd := "quint",
    args := #["run", qntPath, "--mbt", s!"--out-itf={itfPath}", "--max-samples=4", "--max-steps=8"]
  }
  if out.exitCode != 0 then
    throw (IO.userError s!"quint run failed: {out.stderr}")

def itfIntValue? (v : ITF.Value) : Option Nat :=
  match v with
  | .int n => some n
  | _ => none

def nondetIndex? (picks : List (String × ITF.Value)) : Option Nat :=
  match picks.find? (fun (k, _) => k == "index") with
  | some (_, v) =>
      match v with
      | .map entries =>
          match entries.find? (fun (k, _) => k == .str "tag") with
          | some (_, .str "Some") =>
              match entries.find? (fun (k, _) => k == .str "value") with
              | some (_, .int n) => some n
              | _ => none
          | _ => none
      | _ => none
  | none => none

def slotWrite45? (vars : List (String × ITF.Value)) : Bool :=
  ["points_0_x", "points_1_x"].any fun slot =>
    match vars.find? (fun (k, _) => k == slot) with
    | some (_, .int n) => n == 45
    | _ => false

def foldTraceCoverage (acc : Bool × Bool × Bool) (state : ITF.State) : Bool × Bool × Bool :=
  let (sawIndex0, sawIndex1, sawWrite45) := acc
  let sawIndex0 :=
    sawIndex0 || (match nondetIndex? state.nondetPicks with | some 0 => true | _ => false)
  let sawIndex1 :=
    sawIndex1 || (match nondetIndex? state.nondetPicks with | some 1 => true | _ => false)
  let sawWrite45 := sawWrite45 || slotWrite45? state.vars
  (sawIndex0, sawIndex1, sawWrite45)

def assertTraceCoverage (trace : ITF.Trace) : Option String :=
  if trace.states.length <= 1 then
    some s!"ITF trace must contain transitions beyond init (got {trace.states.length} states)"
  else
    let (sawIndex0, sawIndex1, sawWrite45) :=
      trace.states.tail.foldl foldTraceCoverage (false, false, false)
    if !sawIndex0 then
      some "ITF trace must exercise dynamic index 0"
    else if !sawIndex1 then
      some "ITF trace must exercise dynamic index 1"
    else if !sawWrite45 then
      some "ITF trace must reach write+assign result 45 on a flattened slot"
    else
      none

def main : IO UInt32 := do
  let qntPath := "build/quint/StructDynamicPathReplay.qnt"
  let itfPath := "build/quint/StructDynamicPathReplay.itf.json"
  let model ← generateModel
  match validateRenderedDynamicPathGuard model with
  | some err =>
      IO.eprintln s!"FAIL model guard: {err}"
      return 1
  | none => pure ()
  IO.FS.createDirAll "build/quint"
  IO.FS.writeFile qntPath model
  runQuint qntPath itfPath
  let itfJson ← IO.FS.readFile itfPath
  match ITF.parse itfJson with
  | .error err =>
      IO.eprintln s!"FAIL parse ITF: {err}"
      return 1
  | .ok trace =>
      match assertTraceCoverage trace with
      | some err =>
          IO.eprintln s!"FAIL trace coverage: {err}"
          return 1
      | none =>
          match Replay.replayTrace ProofForge.IR.Examples.EvmStorageStructProbe.emitQuintDynamicStructPathModule trace with
          | .error err =>
              IO.eprintln s!"FAIL replay: {err.message}"
              return 1
          | .ok () =>
              IO.println "PASS"
              return 0

end Tests.Quint.StructDynamicPathReplay

def main : IO UInt32 := Tests.Quint.StructDynamicPathReplay.main