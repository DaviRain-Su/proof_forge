import ProofForgeV2.Language.ProgramPayload
import ProofForgeV2.Language.ProgramExport
import ProofForgeV2.Core.Source
import Tests.Language.ProgramPayloadFixtures.Rich
import Lean

open Lean Elab.Command
open ProofForgeV2.Language.ProgramPayload
open ProofForgeV2.Language.ProgramExport
open ProofForgeV2.Source

structure PayloadRow where
  declaration : String
  programName : String
  qualifiedName : String
  sourceHash : String
  deriving BEq, Repr, Inhabited

private def quoteRow (row : PayloadRow) : CommandElabM (TSyntax `term) := do
  `(PayloadRow.mk $(Syntax.mkStrLit row.declaration) $(Syntax.mkStrLit row.programName)
      $(Syntax.mkStrLit row.qualifiedName) $(Syntax.mkStrLit row.sourceHash))

elab "#snapshot_program_payloads " id:ident : command => do
  let env ← getEnv
  match programPayloads env with
  | .error message => throwError message
  | .ok rows =>
      let payloadRows := rows.map fun (entry, prog) =>
        { declaration := entry.declaration.toString, programName := prog.name
          qualifiedName := prog.qualifiedName, sourceHash := prog.sourceHash }
      let elems ← payloadRows.mapM quoteRow
      elabCommand (← `(def $id : Array PayloadRow := #[$elems,*]))

elab "#capture_program_payload_error " n:ident " as " id:ident : command => do
  let env ← getEnv
  let name ← resolveGlobalConstNoOverload n
  match programPayload env name with
  | .ok _ => throwError "expected PF-EXPORT-004 failure"
  | .error message =>
      unless message.startsWith "PF-EXPORT-004" do
        throwError s!"expected PF-EXPORT-004, got {message}"
      elabCommand (← `(def $id : String := $(Syntax.mkStrLit message)))

elab "#capture_program_payloads_error as " id:ident : command => do
  match programPayloads (← getEnv) with
  | .ok _ => throwError "expected PF-EXPORT-004 all-or-nothing failure"
  | .error message =>
      unless message.startsWith "PF-EXPORT-004" do
        throwError s!"expected PF-EXPORT-004, got {message}"
      elabCommand (← `(def $id : String := $(Syntax.mkStrLit message)))

elab "#assert_rich_program_payload " n:ident : command => do
  let env ← getEnv
  let name ← resolveGlobalConstNoOverload n
  match programPayload env name with
  | .error message => throwError message
  | .ok p => do
      unless name == ``Tests.Language.ProgramPayloadFixtures.Rich.RichPayload &&
          p == Tests.Language.ProgramPayloadFixtures.Rich.RichPayload do
        throwError "reconstructed payload must BEq the rich DSL elaborator constant"
      unless p.name == "RichPayload" && p.qualifiedName.endsWith "RichPayload" do
        throwError "rich identity"
      unless p.state.size ≥ 8 && p.structs.size ≥ 1 && p.enums.size ≥ 1 &&
          p.consts.size ≥ 1 && p.events.size ≥ 1 && p.errors.size ≥ 1 &&
          p.initializer.isSome && p.entries.size ≥ 2 && p.functions.size ≥ 1 &&
          p.invariants.size ≥ 1 && p.extensionRequirements.size ≥ 1 &&
          p.proofReferences.size ≥ 1 do
        throwError "rich surface incomplete"
      elabCommand (← `(def richPayloadAsserted : Bool := true))
      elabCommand (← `(def richPayloadName : String := $(Syntax.mkStrLit p.name)))
      elabCommand (← `(def richPayloadQualifiedName : String :=
          $(Syntax.mkStrLit p.qualifiedName)))
      elabCommand (← `(def richPayloadSourceHash : String :=
          $(Syntax.mkStrLit p.sourceHash)))
