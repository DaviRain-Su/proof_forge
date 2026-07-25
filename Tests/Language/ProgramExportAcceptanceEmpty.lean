import ProofForgeV2.Language.ProgramExport
import Lean

open Lean Elab.Command
open ProofForgeV2.Language.ProgramExport

/-! Isolated empty-registry snapshot: only ProgramExport/programPayloadsV2, no attributed fixtures. -/

namespace Tests.Language.ProgramExportAcceptanceEmpty

elab "#snapshot_empty_registry " eId:ident pId:ident : command => do
  let env ← getEnv
  match programExports env with
  | .error m => throwError m
  | .ok et => do
      unless et.isEmpty do throwError s!"exports not empty: {et.size}"
      match programPayloadsV2 env with
      | .error m => throwError m
      | .ok pt => do
          unless pt.isEmpty do throwError s!"payloads not empty: {pt.size}"
          elabCommand (← `(def $(mkIdent eId.getId) : Nat := $(quote et.size)))
          elabCommand (← `(def $(mkIdent pId.getId) : Nat := $(quote pt.size)))

#snapshot_empty_registry emptyExportCount emptyPayloadCount

def run : IO Unit := do
  unless emptyExportCount == 0 do
    throw <| IO.userError s!"expected empty export registry, got {emptyExportCount}"
  unless emptyPayloadCount == 0 do
    throw <| IO.userError s!"expected empty payload registry, got {emptyPayloadCount}"

end Tests.Language.ProgramExportAcceptanceEmpty
