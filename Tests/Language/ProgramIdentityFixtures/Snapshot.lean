import ProofForgeV2.Language.ProgramPayload
import ProofForgeV2.Language.ProgramExport
import Lean

open Lean Elab.Command
open ProofForgeV2.Language.ProgramPayload

structure IdentityRow where
  declaration : String
  qualifiedName : String
  sourceHash : String
  deriving BEq, Repr, Inhabited

private def quoteRow (row : IdentityRow) : CommandElabM (TSyntax `term) := do
  `(IdentityRow.mk $(Syntax.mkStrLit row.declaration)
      $(Syntax.mkStrLit row.qualifiedName) $(Syntax.mkStrLit row.sourceHash))

elab "#snapshot_program_identities " id:ident : command => do
  match programPayloads (← getEnv) with
  | .error message => throwError message
  | .ok rows =>
      let rs := rows.map fun (ex, p) =>
        { declaration := ex.declaration.toString
          qualifiedName := p.qualifiedName, sourceHash := p.sourceHash }
      let elems ← rs.mapM quoteRow
      let i := mkIdent id.getId
      elabCommand (← `(def $i : Array IdentityRow := #[$elems,*]))

elab "#expect_program_identities_error" msg:str "as" id:ident : command => do
  match programPayloads (← getEnv) with
  | .ok _ => throwError "expected identity failure"
  | .error message =>
      unless message == msg.getString do
        throwError s!"expected `{msg.getString}`, got `{message}`"
      let i := mkIdent id.getId
      elabCommand (← `(def $i : String := $(Syntax.mkStrLit message)))

elab "#expect_program_payloads_prefix" pref:str "as" id:ident : command => do
  match programPayloads (← getEnv) with
  | .ok _ => throwError "expected payloads failure"
  | .error message =>
      unless message.startsWith pref.getString do
        throwError s!"expected prefix `{pref.getString}`, got `{message}`"
      let i := mkIdent id.getId
      elabCommand (← `(def $i : String := $(Syntax.mkStrLit message)))
