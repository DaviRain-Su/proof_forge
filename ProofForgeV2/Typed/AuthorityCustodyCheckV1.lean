/-
  ProofForgeV2.Typed.AuthorityCustodyCheckV1 — T-1 engineering authority/custody axis.

  Distinct from visibility (`DisclosureCheckV1` / `PF-VIS-001`):

  * **Authority** is derived from reading `context.caller` (Principal identity).
  * **Custody** of private logical state requires authority evidence on
    **entry** bodies that write private state.

  Engineering rule (bounded subset, not formal TST-VIS-002):

    When an `entry` assigns to a state declared `private`, the entry body must
    contain at least one `context.caller` ContextRead surface (authority
    evidence). Missing evidence → `DiagnosticCodeV1.reqPrecondition` with an
    authority-custody message (not PF-VIS-001).

  Out of scope: owner-key graphs, authorizers/randomness keys, extension
  custody annotations, formal lattice proofs.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.ContextCommitSurfaceV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.DiagnosticDraftV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1

namespace ProofForgeV2.Typed.AuthorityCustodyCheckV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.ContextCommitSurfaceV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.DiagnosticDraftV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

/-- Draft-bearing authority/custody result. -/
structure AuthorityCustodyDraftResultV1 where
  drafts : Array TypedDiagnosticDraftV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

/-- Unlocated result projection. -/
structure AuthorityCustodyResultV1 where
  diagnostics : Array DiagnosticV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

private def eraseDrafts (r : AuthorityCustodyDraftResultV1) : AuthorityCustodyResultV1 :=
  { diagnostics := eraseArray r.drafts
    ok := r.ok
    analysisComplete := r.analysisComplete }

/-- Names of states declared `private` (exact raw spelling). -/
private def privateStateNamesV1 (tables : DeclarationTablesV1) : Array String :=
  tables.state.rows.filterMap fun row =>
    match row.item with
    | .state s =>
        if s.visibility == .private_ then some s.name.raw else none
    | _ => none

/-- True when place root is a bare name equal to `raw`. -/
private def placeRootRawEq (p : PlaceV1) (raw : String) : Bool :=
  match p with
  | .name n => n.raw == raw
  | .field base _ => placeRootRawEq base raw
  | .index base _ => placeRootRawEq base raw
  | .qualified _ => false

private partial def exprHasCallerV1 : ExprV1 → Bool
  | .place p => isContextCallerPlaceV1 p
  | .unary _ e => exprHasCallerV1 e
  | .binary _ l r => exprHasCallerV1 l || exprHasCallerV1 r
  | .constructor _ args => args.any exprHasCallerV1
  | .localCall _ args => args.any exprHasCallerV1
  | .match_ scrut arms =>
      exprHasCallerV1 scrut ||
        arms.any fun a => exprHasCallerV1 a.value
  | .literal _ => false

private partial def stmtWritesPrivateV1
    (privateNames : Array String) : StmtV1 → Bool
  | .assign target _ =>
      privateNames.any fun n => placeRootRawEq target n
  | .let_ _ _ _ body =>
      body.any (stmtWritesPrivateV1 privateNames)
  | .if_ _ t e? =>
      t.any (stmtWritesPrivateV1 privateNames) ||
        (match e? with
         | some e => e.any (stmtWritesPrivateV1 privateNames)
         | none => false)
  | .match_ _ arms =>
      arms.any fun a => a.body.any (stmtWritesPrivateV1 privateNames)
  | .for_ _ _ _ _ body =>
      body.any (stmtWritesPrivateV1 privateNames)
  | .assert _ | .return_ _ | .revert _ _ | .emit _ _ | .call _ _ | .schedule _ _ =>
      false

/-- Also detect caller inside statements (not only RHS of writes). -/
private partial def stmtHasCallerV1 : StmtV1 → Bool
  | .assign _ rhs => exprHasCallerV1 rhs
  | .let_ _ _ e? body =>
      (match e? with | some e => exprHasCallerV1 e | none => false) ||
        body.any stmtHasCallerV1
  | .if_ cond t e? =>
      exprHasCallerV1 cond ||
        t.any stmtHasCallerV1 ||
        (match e? with | some e => e.any stmtHasCallerV1 | none => false)
  | .match_ scrut arms =>
      exprHasCallerV1 scrut ||
        arms.any fun a => a.body.any stmtHasCallerV1
  | .for_ _ start end_ _ body =>
      exprHasCallerV1 start || exprHasCallerV1 end_ || body.any stmtHasCallerV1
  | .assert e => exprHasCallerV1 e
  | .return_ e? => match e? with | some e => exprHasCallerV1 e | none => false
  | .revert _ args => args.any exprHasCallerV1
  | .emit _ args => args.any exprHasCallerV1
  | .call _ args => args.any exprHasCallerV1
  | .schedule _ args => args.any exprHasCallerV1

private def bodyHasCallerV1 (body : Array StmtV1) : Bool :=
  body.any stmtHasCallerV1

private def bodyWritesPrivateV1
    (privateNames : Array String) (body : Array StmtV1) : Bool :=
  body.any (stmtWritesPrivateV1 privateNames)

private def authorityPrivateWriteMessage (entryName : String) : String :=
  s!"authority/custody: entry '{entryName}' writes private state without context.caller authority evidence"

/-- Sole draft authority for T-1. -/
def checkAuthorityCustodyDraftsV1
    (program : ProgramV1) (tables : DeclarationTablesV1) :
    AuthorityCustodyDraftResultV1 :=
  if tables.fn.hasDuplicateKey then
    { drafts := #[]
      ok := false
      analysisComplete := false }
  else
    let privateNames := privateStateNamesV1 tables
    if privateNames.isEmpty then
      { drafts := #[]
        ok := true
        analysisComplete := true }
    else
      let mut drafts : Array TypedDiagnosticDraftV1 := #[]
      for item in program.items do
        match item with
        | .entry e =>
            let writes := bodyWritesPrivateV1 privateNames e.body
            let hasAuth := bodyHasCallerV1 e.body
            if writes && !hasAuth then
              let msg := authorityPrivateWriteMessage e.name.raw
              let d : DiagnosticV1 :=
                DiagnosticV1.make .reqPrecondition msg
              drafts := drafts.push { diagnostic := d, location := none }
        | _ => pure ()
      { drafts := drafts
        ok := drafts.isEmpty
        analysisComplete := true }

def checkAuthorityCustodyDraftsResultV1 (source : ValidatedSourceV1) :
    AuthorityCustodyDraftResultV1 :=
  let resolution := resolveProgramDraftsV1 source
  if !resolution.ok then
    { drafts := #[]
      ok := false
      analysisComplete := !resolution.tables.fn.hasDuplicateKey }
  else
    checkAuthorityCustodyDraftsV1 source.program resolution.tables

def checkAuthorityCustodyResultV1 (source : ValidatedSourceV1) :
    AuthorityCustodyResultV1 :=
  eraseDrafts (checkAuthorityCustodyDraftsResultV1 source)

def checkAuthorityCustodyV1 (source : ValidatedSourceV1) : Array DiagnosticV1 :=
  (checkAuthorityCustodyResultV1 source).diagnostics

end ProofForgeV2.Typed.AuthorityCustodyCheckV1
