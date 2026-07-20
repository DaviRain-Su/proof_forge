import ProofForgeV2.Language.ProgramPayload
import ProofForgeV2.Language.ProgramExport
import Lean

open Lean Elab.Command
open ProofForgeV2.Language.ProgramPayload

structure BindingRow where
  declaration : String
  qualifiedName : String
  deriving BEq, Repr, Inhabited

private def quoteRow (row : BindingRow) : CommandElabM (TSyntax `term) := do
  `(BindingRow.mk $(Syntax.mkStrLit row.declaration)
      $(Syntax.mkStrLit row.qualifiedName))

/-- Table snapshot; asserts declaration.toString == qualifiedName for every row. -/
elab "#snapshot_binding_table " id:ident : command => do
  match programPayloads (← getEnv) with
  | .error message => throwError message
  | .ok rows => do
      for (ex, p) in rows do
        unless ex.declaration.toString == p.qualifiedName do
          throwError s!"table binding drift {ex.declaration} vs {p.qualifiedName}"
      let rs := rows.map fun (ex, p) =>
        { declaration := ex.declaration.toString, qualifiedName := p.qualifiedName }
      let elems ← rs.mapM quoteRow
      let i := mkIdent id.getId
      elabCommand (← `(def $i : Array BindingRow := #[$elems,*]))

/-- Single-name snapshot; asserts declaration.toString == payload.qualifiedName. -/
elab "#snapshot_binding_payload " n:ident "as" id:ident : command => do
  let env ← getEnv
  let name ← resolveGlobalConstNoOverload n
  match programPayload env name with
  | .error message => throwError message
  | .ok p => do
      unless name.toString == p.qualifiedName do
        throwError s!"single binding drift {name} vs {p.qualifiedName}"
      let i := mkIdent id.getId
      elabCommand (← `(def $i : BindingRow :=
          BindingRow.mk $(Syntax.mkStrLit name.toString)
            $(Syntax.mkStrLit p.qualifiedName)))

elab "#expect_binding_error_payloads" "as" id:ident : command => do
  match programPayloads (← getEnv) with
  | .ok _ => throwError "expected binding failure from programPayloads"
  | .error message =>
      let expected := "PF-EXPORT-001: exported program identity does not match declaration"
      unless message == expected do
        throwError s!"expected `{expected}`, got `{message}`"
      let i := mkIdent id.getId
      elabCommand (← `(def $i : String := $(Syntax.mkStrLit message)))

elab "#expect_binding_error_payload " n:ident "as" id:ident : command => do
  let env ← getEnv
  let name ← resolveGlobalConstNoOverload n
  match programPayload env name with
  | .ok _ => throwError "expected binding failure from programPayload"
  | .error message =>
      let expected := "PF-EXPORT-001: exported program identity does not match declaration"
      unless message == expected do
        throwError s!"expected `{expected}`, got `{message}`"
      let i := mkIdent id.getId
      elabCommand (← `(def $i : String := $(Syntax.mkStrLit message)))

elab "#expect_payloads_prefix" pref:str "as" id:ident : command => do
  match programPayloads (← getEnv) with
  | .ok _ => throwError "expected programPayloads failure"
  | .error message =>
      unless message.startsWith pref.getString do
        throwError s!"expected prefix `{pref.getString}`, got `{message}`"
      let i := mkIdent id.getId
      elabCommand (← `(def $i : String := $(Syntax.mkStrLit message)))
