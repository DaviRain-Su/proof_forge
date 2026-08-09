/-
  Focused wave-3 MiniAmm L1 empty-pool admit (engineering).
-/
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.ReferenceV1
import ProofForgeV2.Semantic.WireV1
import Tests.Language.ParserSession

namespace Tests.Semantic.MiniAmmL1Admit

open ProofForgeV2.Language.Loader
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

private def expect (cond : Bool) (msg : String) : IO Unit := do
  unless cond do throw <| IO.userError msg

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let pathStr := "Examples/MiniAmmL1.lean"
  let source ← IO.FS.readFile pathStr
  expect (source.contains "emptyPool") "must declare emptyPool"
  let validated ←
    match ← session.selectProgramV1 source pathStr "Examples.MiniAmmL1" none with
    | .ok v => pure v
    | .error error => throw <| IO.userError s!"load: {error.render}"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"validate: {repr e}"
  expect (data.invariants.size == 1) "one invariant"
  match data.invariants[0]? with
  | none => throw <| IO.userError "missing inv"
  | some inv => expect (inv.name == "emptyPool") "name emptyPool"
  match admitReferenceProgramSliceV1 carrier with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"admit: {repr e}"
  IO.println s!"Tests.Semantic.MiniAmmL1Admit: ok bytes={carrier.canonicalBytes.size}"

end Tests.Semantic.MiniAmmL1Admit

unsafe def main : IO Unit :=
  Tests.Semantic.MiniAmmL1Admit.run
