import ProofForgeV2.Language.ProgramExport
import Lean

open Lean
open Lean.Elab.Command
open ProofForgeV2.Language.ProgramExport

structure ProgramExportRow where
  schema : String
  declaration : String
  deriving BEq, Repr, Inhabited

private def quoteRow (row : ProgramExportRow) : CommandElabM (TSyntax `term) := do
  `(ProgramExportRow.mk $(Syntax.mkStrLit row.schema) $(Syntax.mkStrLit row.declaration))

elab "#snapshot_program_exports " id:ident : command => do
  let env ← getEnv
  match programExports env with
  | .error message => throwError message
  | .ok table =>
      let rows := table.map fun entry =>
        { schema := entry.schema, declaration := Name.toString entry.declaration }
      let elems ← rows.mapM quoteRow
      let arr ← `(#[$elems,*])
      elabCommand (← `(def $id : Array ProgramExportRow := $arr))
