/-
  ProofForgeV2.Typed.ContextExtensionCheckV1 — T-2 engineering context/extension gate.

  Threads closed ContextRead surfaces and extension-requirement presence into
  CheckV1 composition (after T-1 authority/custody):

  * Admitted ContextRead surfaces are the closed Source.ContextCommitSurfaceV1
    set (caller, unixTimeSeconds, blockHeight, chainId, self, attachedValue). Any other
    `context.*` place is
    fail-closed with `reqPrecondition`.
  * Engineering extensions are admitted only from the closed Core table
    `engineeringExtensionIdentitiesV1` (currently ADR-0028
    `solana.cpi.accounts@1.0.0` and ADR-0030 `pf.assets@1.1.0`/`@1.2.0`; the
    ADR-0029 `pf.assets@1.0.0` triple failed closed at the E2 acceptance cutover).
    Unknown ids fail with `ext001`; a known id with the wrong version/digest
    fails with `extensionVersion`. Distinct ids may coexist in one program.
    Admission only carries the declaration into Semantic; it does not
    advertise target support or permit artifact minting.

  Not a formal extension catalog / full context key matrix.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Core.RequirementIdsV1
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
open ProofForgeV2.Core.RequirementIdsV1
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

mutual
  /-- Bounded-total context scan. `none` is fuel exhaustion; `some true`
      short-circuits exactly like the former Bool `any` walk. -/
  def exprBadContextFuelV1 : Nat → ExprV1 → Option Bool
    | 0, _ => none
    | _fuel + 1, .place p =>
        some (isContextRootPlaceV1 p && !isAdmittedContextPlaceV1 p)
    | fuel + 1, .unary _ e => exprBadContextFuelV1 fuel e
    | fuel + 1, .binary _ l r =>
        match exprBadContextFuelV1 fuel l with
        | none => none
        | some true => some true
        | some false => exprBadContextFuelV1 fuel r
    | fuel + 1, .constructor _ args =>
        exprListBadContextFuelV1 fuel args.toList
    | fuel + 1, .localCall _ args =>
        exprListBadContextFuelV1 fuel args.toList
    | fuel + 1, .match_ scrut arms =>
        match exprBadContextFuelV1 fuel scrut with
        | none => none
        | some true => some true
        | some false => exprArmListBadContextFuelV1 fuel arms.toList
    | fuel + 1, .externalCall call =>
        exprListBadContextFuelV1 fuel call.args.toList
    | _fuel + 1, .literal _ => some false

  def exprListBadContextFuelV1 : Nat → List ExprV1 → Option Bool
    | _, [] => some false
    | 0, _ :: _ => none
    | fuel + 1, expr :: rest =>
        match exprBadContextFuelV1 fuel expr with
        | none => none
        | some true => some true
        | some false => exprListBadContextFuelV1 fuel rest

  def exprArmListBadContextFuelV1 : Nat → List ExprMatchArmV1 → Option Bool
    | _, [] => some false
    | 0, _ :: _ => none
    | fuel + 1, arm :: rest =>
        match exprBadContextFuelV1 fuel arm.value with
        | none => none
        | some true => some true
        | some false => exprArmListBadContextFuelV1 fuel rest

  def blockBadContextFuelV1 : Nat → BlockV1 → Option Bool
    | 0, _ => none
    | fuel + 1, block =>
        stmtListBadContextFuelV1 fuel block.statements.toList

  def stmtListBadContextFuelV1 : Nat → List StmtV1 → Option Bool
    | _, [] => some false
    | 0, _ :: _ => none
    | fuel + 1, stmt :: rest =>
        match stmtBadContextFuelV1 fuel stmt with
        | none => none
        | some true => some true
        | some false => stmtListBadContextFuelV1 fuel rest

  def stmtArmListBadContextFuelV1 : Nat → List StmtMatchArmV1 → Option Bool
    | _, [] => some false
    | 0, _ :: _ => none
    | fuel + 1, arm :: rest =>
        match blockBadContextFuelV1 fuel arm.body with
        | none => none
        | some true => some true
        | some false => stmtArmListBadContextFuelV1 fuel rest

  def stmtBadContextFuelV1 : Nat → StmtV1 → Option Bool
    | 0, _ => none
    | fuel + 1, .assign _ rhs => exprBadContextFuelV1 fuel rhs
    | fuel + 1, .let_ _ _ e => exprBadContextFuelV1 fuel e
    | fuel + 1, .if_ c t e? =>
        match exprBadContextFuelV1 fuel c with
        | none => none
        | some true => some true
        | some false =>
            match blockBadContextFuelV1 fuel t with
            | none => none
            | some true => some true
            | some false =>
                match e? with
                | none => some false
                | some block => blockBadContextFuelV1 fuel block
    | fuel + 1, .match_ s arms =>
        match exprBadContextFuelV1 fuel s with
        | none => none
        | some true => some true
        | some false => stmtArmListBadContextFuelV1 fuel arms.toList
    | fuel + 1, .for_ _ a b _ body =>
        match exprBadContextFuelV1 fuel a with
        | none => none
        | some true => some true
        | some false =>
            match exprBadContextFuelV1 fuel b with
            | none => none
            | some true => some true
            | some false => blockBadContextFuelV1 fuel body
    | fuel + 1, .assert_ e _ => exprBadContextFuelV1 fuel e
    | fuel + 1, .return_ e? =>
        match e? with
        | some e => exprBadContextFuelV1 fuel e
        | none => some false
    | fuel + 1, .revert _ args =>
        exprListBadContextFuelV1 fuel args.toList
    | fuel + 1, .emit _ args =>
        exprListBadContextFuelV1 fuel args.toList
    | fuel + 1, .call c =>
        exprListBadContextFuelV1 fuel c.args.toList
    | fuel + 1, .schedule c =>
        exprListBadContextFuelV1 fuel c.args.toList
end

/-- Production context scan entry for one expression. Exposed so downstream
    certificates can replay the exact bounded walker rather than duplicate it. -/
def exprBadContextV1 (expr : ExprV1) : Option Bool :=
  exprBadContextFuelV1 100001 expr

/-- Production context scan entry for one block. Exposed so downstream
    certificates can replay the exact bounded walker rather than duplicate it. -/
def blockBadContextV1 (block : BlockV1) : Option Bool :=
  blockBadContextFuelV1 100001 block

/-- Closed extension identity check for one source item. -/
def checkExtensionProgramItemDraftsV1
    (item : ProgramItemV1) (itemIndex : Nat) :
    Array TypedDiagnosticDraftV1 :=
  match item with
  | .extensionReq declaration =>
      match programItemPathV1 itemIndex with
      | .error detail => #[pathInternalDraft detail]
      | .ok itemPath =>
          let id := sourceQualifiedNameV1ToString declaration.id
          match findExactEngineeringExtensionTripleV1 id
              declaration.version declaration.digest with
          | some _ => #[]
          | none =>
              let knownIds := engineeringExtensionIdentitiesV1.map (·.sourceId)
              if knownIds.contains id then
                let acceptedTriples := engineeringExtensionsBySourceIdV1 id
                let expectedTriples := acceptedTriples.map fun admitted =>
                  .object #[
                    ("digest", .string admitted.digest),
                    ("version", .string admitted.version)]
                let wireId := acceptedTriples[0]!.wireRequirementId
                #[makeLocated .extensionVersion
                  s!"extension '{id}' version/digest does not match the frozen contract"
                  itemPath
                  (expected := some (.array expectedTriples))
                  (actual := some (.object #[
                    ("digest", .string declaration.digest),
                    ("version", .string declaration.version)]))
                  (stableContext := some s!"{wireId}.version-digest")]
              else
                let closedIds := String.intercalate "," knownIds.toList
                #[makeLocated .ext001
                  s!"unsupported extension requirement '{id}'"
                  itemPath
                  (expected := some (.string closedIds))
                  (actual := some (.string id))
                  (stableContext := some "extension.id.unsupported")]
  | _ => #[]

def collectExtensionProgramItemDraftsV1 :
    List (ProgramItemV1 × Nat) → Array TypedDiagnosticDraftV1
  | [] => #[]
  | (item, itemIndex) :: rest =>
      checkExtensionProgramItemDraftsV1 item itemIndex ++
        collectExtensionProgramItemDraftsV1 rest

structure ContextSurfaceDraftResultV1 where
  drafts : Array TypedDiagnosticDraftV1
  analysisComplete : Bool
  deriving Repr, Inhabited

private def unsupportedContextDraft : TypedDiagnosticDraftV1 :=
  { diagnostic := DiagnosticV1.make .reqPrecondition
      "unsupported context surface (only context.caller, context.unixTimeSeconds, context.blockHeight, context.chainId, context.contractId and context.attachedValue are admitted)"
    location := none }

def checkContextSurfaceProgramItemDraftResultV1
    (item : ProgramItemV1) : ContextSurfaceDraftResultV1 :=
  let scanned : Option Bool :=
    match item with
    | .entry e => blockBadContextV1 e.body
    | .view v => blockBadContextV1 v.body
    | .fn f => blockBadContextV1 f.body
    | .init i => blockBadContextV1 i.body
    | .const c => exprBadContextV1 c.value
    | .invariant inv => exprBadContextV1 inv.predicate
    | _ => some false
  match scanned with
  | some false => { drafts := #[], analysisComplete := true }
  | some true => { drafts := #[unsupportedContextDraft], analysisComplete := true }
  | none =>
      { drafts := #[pathInternalDraft "context surface walk: traversal fuel exhausted"]
        analysisComplete := false }

def collectContextSurfaceDraftResultV1 :
    List ProgramItemV1 → ContextSurfaceDraftResultV1
  | [] => { drafts := #[], analysisComplete := true }
  | item :: rest =>
      let head := checkContextSurfaceProgramItemDraftResultV1 item
      let tail := collectContextSurfaceDraftResultV1 rest
      { drafts := head.drafts ++ tail.drafts
        analysisComplete := head.analysisComplete && tail.analysisComplete }

def checkContextExtensionDraftsV1
    (program : ProgramV1) (tables : TypedDeclTablesV1) :
    ContextExtensionDraftResultV1 :=
  if tables.fn.hasDuplicateKey then
    { drafts := #[], ok := false, analysisComplete := false }
  else
    let extensionDrafts :=
      collectExtensionProgramItemDraftsV1 program.items.zipIdx.toList
    let contextResult := collectContextSurfaceDraftResultV1 program.items.toList
    let drafts := extensionDrafts ++ contextResult.drafts
    { drafts := drafts
      ok := contextResult.analysisComplete && drafts.isEmpty
      analysisComplete := contextResult.analysisComplete }

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
