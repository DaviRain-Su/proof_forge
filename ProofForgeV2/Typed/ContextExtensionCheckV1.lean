/-
  ProofForgeV2.Typed.ContextExtensionCheckV1 — T-2 engineering context/extension gate.

  Threads closed ContextRead surfaces and extension-requirement presence into
  CheckV1 composition (after T-1 authority/custody):

  * Only `context.caller` and `context.unixTimeSeconds` are admitted ContextRead
    surfaces (Source.ContextCommitSurfaceV1). Any other `context.*` place is
    fail-closed with `reqPrecondition`.
  * Declared `requires extension …` items are not yet product-supported on the
    engineering Check path → `ext001` fail-closed (NameResolution still accepts
    table shape).

  Not formal extension catalog / full context key matrix.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.ContextCommitSurfaceV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.DiagnosticDraftV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1

namespace ProofForgeV2.Typed.ContextExtensionCheckV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.ContextCommitSurfaceV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.DiagnosticDraftV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

structure ContextExtensionDraftResultV1 where
  drafts : Array TypedDiagnosticDraftV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

structure ContextExtensionResultV1 where
  diagnostics : Array DiagnosticV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

private def eraseDrafts (r : ContextExtensionDraftResultV1) : ContextExtensionResultV1 :=
  { diagnostics := eraseArray r.drafts
    ok := r.ok
    analysisComplete := r.analysisComplete }

/-- True when place is `context.<field>` with any field (possibly multi-suffix). -/
private def isContextRootPlaceV1 : PlaceV1 → Bool
  | .field (.name root) _ => root.raw == "context"
  | .field base _ => isContextRootPlaceV1 base
  | .index base _ => isContextRootPlaceV1 base
  | .name _ => false

/-- Admitted ContextRead surfaces only. -/
private def isAdmittedContextPlaceV1 (p : PlaceV1) : Bool :=
  isContextReadPlaceV1 p

private partial def exprBadContextV1 : ExprV1 → Bool
  | .place p =>
      isContextRootPlaceV1 p && !isAdmittedContextPlaceV1 p
  | .unary _ e => exprBadContextV1 e
  | .binary _ l r => exprBadContextV1 l || exprBadContextV1 r
  | .constructor _ args => args.any exprBadContextV1
  | .localCall _ args => args.any exprBadContextV1
  | .match_ scrut arms =>
      exprBadContextV1 scrut || arms.any fun a => exprBadContextV1 a.value
  | .literal _ => false

private partial def stmtBadContextV1 : StmtV1 → Bool
  | .assign _ rhs => exprBadContextV1 rhs
  | .let_ _ _ e => exprBadContextV1 e
  | .if_ c t e? =>
      exprBadContextV1 c ||
        t.statements.any stmtBadContextV1 ||
        (match e? with | some b => b.statements.any stmtBadContextV1 | none => false)
  | .match_ s arms =>
      exprBadContextV1 s ||
        arms.any fun a => a.body.statements.any stmtBadContextV1
  | .for_ _ a b _ body =>
      exprBadContextV1 a || exprBadContextV1 b ||
        body.statements.any stmtBadContextV1
  | .assert_ e _ => exprBadContextV1 e
  | .return_ e? => match e? with | some e => exprBadContextV1 e | none => false
  | .revert _ args => args.any exprBadContextV1
  | .emit _ args => args.any exprBadContextV1
  | .call c => c.args.any exprBadContextV1
  | .schedule c => c.args.any exprBadContextV1

private def blockBadContextV1 (b : BlockV1) : Bool :=
  b.statements.any stmtBadContextV1

def checkContextExtensionDraftsV1
    (program : ProgramV1) (tables : TypedDeclTablesV1) :
    ContextExtensionDraftResultV1 :=
  if tables.fn.hasDuplicateKey then
    { drafts := #[], ok := false, analysisComplete := false }
  else
    Id.run do
      let mut drafts : Array TypedDiagnosticDraftV1 := #[]
      -- Extension declarations: engineering Check does not admit product extensions.
      if tables.extensionReq.size > 0 then
        let d := DiagnosticV1.make .ext001
          "extension requirements are not admitted on the engineering Check path"
        drafts := drafts.push { diagnostic := d, location := none }
      -- Unknown context.* surfaces in any callable body.
      for item in program.items do
        let bad :=
          match item with
          | .entry e => blockBadContextV1 e.body
          | .view v => blockBadContextV1 v.body
          | .fn f => blockBadContextV1 f.body
          | .init i => blockBadContextV1 i.body
          | .const c => exprBadContextV1 c.value
          | .invariant inv => exprBadContextV1 inv.predicate
          | _ => false
        if bad then
          let d := DiagnosticV1.make .reqPrecondition
            "unsupported context surface (only context.caller and context.unixTimeSeconds are admitted)"
          drafts := drafts.push { diagnostic := d, location := none }
      pure {
        drafts := drafts
        ok := drafts.isEmpty
        analysisComplete := true
      }

def checkContextExtensionDraftsResultV1 (source : ValidatedSourceV1) :
    ContextExtensionDraftResultV1 :=
  let resolution := resolveProgramDraftsV1 source
  if !resolution.ok then
    -- Incomplete: do not claim context/extension analysis finished.
    { drafts := #[]
      ok := false
      analysisComplete := false }
  else
    checkContextExtensionDraftsV1 source.program resolution.tables

def checkContextExtensionResultV1 (source : ValidatedSourceV1) :
    ContextExtensionResultV1 :=
  eraseDrafts (checkContextExtensionDraftsResultV1 source)

def checkContextExtensionV1 (source : ValidatedSourceV1) : Array DiagnosticV1 :=
  (checkContextExtensionResultV1 source).diagnostics

end ProofForgeV2.Typed.ContextExtensionCheckV1
