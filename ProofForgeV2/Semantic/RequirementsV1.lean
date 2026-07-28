/-
  ProofForgeV2.Semantic.RequirementsV1 — S2 exact ProgramRequirementsV1 freeze
  for the Semantic normalizer path (Counter / S1 surface only).

  Internalizes the contribution rules of Typed.RequirementsInferV1 as a pure
  ProgramV1 walk that emits closed engineering RequirementRequestV1 keys
  **without** returning or bridging through alpha `ProgramRequirement`.

  S2 closed catalog (IDs only from existing ProgramRequirement.id strings):
    * state.persistent
    * value.checked-arithmetic
    * failure.atomic-rollback
  Predicates: empty for all three.
  Version: SemVer core 1.0.0 (engineering; formal CAP registry pending).
  Digest: domainSeparatedSha256("pf.requirement-key.engineering.v1", UTF-8(id))
    — engineering key content-address pending formal requirement-semantics
      registry; not claimed as formal CAP resolution.

  Wire order is SPEC key order (id UTF-8 ascending, then SemVer, then digest),
  **not** first-seen inference order:
    1. failure.atomic-rollback
    2. state.persistent
    3. value.checked-arithmetic

  Non-catalog inferred IDs fail closed on this path (unsupported). Consumed only
  by NormalizeV1 before encodeSemanticProgramDataV1 / semanticHashV1.
  Does not wire CheckV1 / compile / CLI. Formal TASK-D2-05 remains pending.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace ProofForgeV2.Semantic.RequirementsV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1

-- Selective source AST abbrevs to avoid WireV1 name clashes.
private abbrev SrcType := ProofForgeV2.Source.AstV1.TypeV1
private abbrev SrcVis := ProofForgeV2.Source.AstV1.VisibilityV1
private abbrev SrcExpr := ProofForgeV2.Source.AstSpineV1.ExprV1
private abbrev SrcStmt := ProofForgeV2.Source.AstSpineV1.StmtV1
private abbrev SrcPlace := ProofForgeV2.Source.AstSpineV1.PlaceV1
private abbrev SrcBlock := ProofForgeV2.Source.AstSpineV1.BlockV1
private abbrev SrcParam := ProofForgeV2.Source.AstSupportV1.ParamV1
private abbrev SrcStateDecl := ProofForgeV2.Source.AstDeclV1.StateDeclV1
private abbrev SrcBinaryOp := ProofForgeV2.Source.AstV1.BinaryOpV1
private abbrev SrcUnaryOp := ProofForgeV2.Source.AstV1.UnaryOpV1

/-- Domain tag for engineering requirement-key digests (S2 closed table only). -/
def engineeringRequirementKeyDomainV1 : String :=
  "pf.requirement-key.engineering.v1"

/-- Sole engineering SemVer core for the closed S2 requirement table. -/
def s2RequirementVersionV1 : SemVer :=
  { major := 1, minor := 0, patch := 0 }

/-- Closed S2 catalog IDs in SPEC wire order (UTF-8 ascending). -/
def s2CatalogIdsWireOrderV1 : Array String :=
  #["failure.atomic-rollback", "state.persistent", "value.checked-arithmetic"]

def isS2CatalogIdV1 (id : String) : Bool :=
  s2CatalogIdsWireOrderV1.contains id

/-- Engineering content-address digest for a closed catalog requirement id. -/
def engineeringRequirementDigestV1 (id : String) : Except String Digest :=
  domainSeparatedSha256 engineeringRequirementKeyDomainV1 id.toUTF8

/-- Build one RequirementRequestV1 for a catalog id (empty predicates). -/
def mkS2RequirementRequestV1 (id : String) : Except String RequirementRequestV1 := do
  unless isS2CatalogIdV1 id do
    throw s!"S2 requirements catalog rejects non-catalog id '{id}'"
  let digest ← engineeringRequirementDigestV1 id
  pure {
    id
    version := s2RequirementVersionV1
    digest
    predicates := #[]
  }

private def compareDigestBytes (left right : ByteArray) : Ordering :=
  let n := Nat.min left.size right.size
  let rec loop (i : Nat) : Ordering :=
    if i < n then
      let bl := left.get! i
      let br := right.get! i
      if bl.toNat < br.toNat then .lt
      else if bl.toNat > br.toNat then .gt
      else loop (i + 1)
    else if left.size < right.size then .lt
    else if left.size > right.size then .gt
    else .eq
  loop 0

private def compareRequirementKeyString
    (left right : RequirementRequestV1) : Except String Ordering := do
  if left.id < right.id then return .lt
  if left.id > right.id then return .gt
  let verL ← renderSemVer left.version
  let verR ← renderSemVer right.version
  if verL < verR then return .lt
  if verL > verR then return .gt
  validateDigest left.digest
  validateDigest right.digest
  pure (compareDigestBytes left.digest.bytes right.digest.bytes)

/-- Sort requirement requests by SPEC key order (id, SemVer render, digest). -/
private def sortRequirementRequestsV1 (items : Array RequirementRequestV1) :
    Except String (Array RequirementRequestV1) := do
  let mut out : Array RequirementRequestV1 := #[]
  for item in items do
    let mut inserted := false
    let mut next : Array RequirementRequestV1 := #[]
    for existing in out do
      if inserted then
        next := next.push existing
      else
        let cmp ← compareRequirementKeyString existing item
        match cmp with
        | .lt => next := next.push existing
        | .eq | .gt =>
            next := next.push item
            next := next.push existing
            inserted := true
    if !inserted then
      next := next.push item
    out := next
  pure out

/-- Internal contribution keys (catalog ids only). Mirrors RequirementsInferV1
    rules that can fire on the S1 Counter surface; richer contributions that
    produce non-catalog ids are collected then rejected at freeze. -/
private inductive ContribKey where
  | catalog (id : String)
  | foreign (id : String)
  deriving BEq

private def contribId : ContribKey → String
  | .catalog id | .foreign id => id

private def statePersistent : ContribKey := .catalog "state.persistent"
private def checkedArithmetic : ContribKey := .catalog "value.checked-arithmetic"
private def atomicRollback : ContribKey := .catalog "failure.atomic-rollback"

private def foreignPrivateState : ContribKey := .foreign "disclosure.private-state"
private def foreignCommitmentState : ContribKey := .foreign "disclosure.commitment-state"
private def foreignPrivateWitness : ContribKey := .foreign "disclosure.private-witness"
private def foreignCommitmentDisclosure : ContribKey := .foreign "disclosure.commitment"
private def foreignBoolValues : ContribKey := .foreign "value.bool"
private def foreignFieldBn254 : ContribKey := .foreign "value.field.bn254-fr"
private def foreignSyncCall : ContribKey := .foreign "effect.synchronous-call"
private def foreignAsyncWorkflow : ContribKey := .foreign "effect.asynchronous-workflow"
private def foreignEventEmission : ContribKey := .foreign "effect.event"

private def typeKeys : SrcType → Array ContribKey
  | .bool => #[foreignBoolValues]
  | .field id =>
      if id.raw == "bn254_fr" then #[foreignFieldBn254] else #[]
  | .option element => typeKeys element
  | .array element _ => typeKeys element
  | .map key value => typeKeys key ++ typeKeys value
  | .uint _ | .int _ | .principal | .unit | .named _ | .bytes _ => #[]

private def stateVisibilityKeys : SrcVis → Array ContribKey
  | .public_ => #[]
  | .private_ => #[foreignPrivateState]
  | .commitment => #[foreignCommitmentState]

private def paramVisibilityKeys : SrcVis → Array ContribKey
  | .public_ => #[]
  | .private_ => #[foreignPrivateWitness]
  | .commitment => #[foreignCommitmentDisclosure]

private def paramKeys (param : SrcParam) : Array ContribKey :=
  typeKeys param.type_ ++ paramVisibilityKeys param.visibility

private def stateKeys (state : SrcStateDecl) : Array ContribKey :=
  typeKeys state.type_ ++ stateVisibilityKeys state.visibility

mutual
  private partial def placeKeys : SrcPlace → Array ContribKey
    | .name _ => #[]
    | .field base _ => placeKeys base
    | .index base idx => placeKeys base ++ exprKeys idx

  private partial def exprKeys : SrcExpr → Array ContribKey
    | .literal _ => #[]
    | .place p => placeKeys p
    | .constructor _ args => args.flatMap exprKeys
    | .unary op operand =>
        let child := exprKeys operand
        if op == ProofForgeV2.Source.AstV1.UnaryOpV1.neg then
          child ++ #[checkedArithmetic, atomicRollback]
        else
          child
    | .binary op lhs rhs =>
        let child := exprKeys lhs ++ exprKeys rhs
        if op == ProofForgeV2.Source.AstV1.BinaryOpV1.add ||
            op == ProofForgeV2.Source.AstV1.BinaryOpV1.sub ||
            op == ProofForgeV2.Source.AstV1.BinaryOpV1.mul ||
            op == ProofForgeV2.Source.AstV1.BinaryOpV1.div ||
            op == ProofForgeV2.Source.AstV1.BinaryOpV1.mod then
          child ++ #[checkedArithmetic, atomicRollback]
        else
          child
    | .localCall _ args => args.flatMap exprKeys
    | .match_ scrutinee arms =>
        exprKeys scrutinee ++ arms.flatMap (fun arm => exprKeys arm.value)

  private partial def stmtKeys : SrcStmt → Array ContribKey
    | .let_ _ typeAnn? value =>
        (match typeAnn? with
          | some t => typeKeys t
          | none => #[]) ++
          exprKeys value
    | .assign target value =>
        placeKeys target ++ exprKeys value
    | .if_ cond thenB elseB? =>
        exprKeys cond ++ blockKeys thenB ++
          (match elseB? with
            | some b => blockKeys b
            | none => #[])
    | .match_ scrutinee arms =>
        exprKeys scrutinee ++ arms.flatMap (fun arm => blockKeys arm.body)
    | .for_ _ start endEx _ body =>
        exprKeys start ++ exprKeys endEx ++ blockKeys body
    | .assert_ cond _ =>
        exprKeys cond ++ #[atomicRollback]
    | .revert _ args =>
        args.flatMap exprKeys ++ #[atomicRollback]
    | .emit _ args =>
        args.flatMap exprKeys ++ #[foreignEventEmission]
    | .return_ value? =>
        match value? with
        | some e => exprKeys e
        | none => #[]
    | .call call =>
        call.args.flatMap exprKeys ++ #[foreignSyncCall, atomicRollback]
    | .schedule call =>
        call.args.flatMap exprKeys ++ #[foreignAsyncWorkflow]

  private partial def blockKeys (block : SrcBlock) : Array ContribKey :=
    block.statements.flatMap stmtKeys
end

private def itemKeys : ProgramItemV1 → Array ContribKey
  | .state decl => stateKeys decl
  | .init decl =>
      decl.params.flatMap paramKeys ++ blockKeys decl.body
  | .entry decl =>
      decl.params.flatMap paramKeys ++
        typeKeys decl.result ++
        blockKeys decl.body
  | .view decl =>
      decl.params.flatMap paramKeys ++
        typeKeys decl.result ++
        blockKeys decl.body
  | .fn decl =>
      decl.params.flatMap paramKeys ++
        typeKeys decl.result ++
        blockKeys decl.body
  | .const decl =>
      typeKeys decl.type_ ++ exprKeys decl.value
  | .invariant decl => exprKeys decl.predicate
  | .struct _ | .enum _ | .event _ | .error _ | .extensionReq _ | .proof _ => #[]

/-- Infer contribution keys from ProgramV1 (first-seen order, raw walk). -/
private def inferContributionKeysV1 (program : ProgramV1) : Array ContribKey :=
  Id.run do
    let hasState := program.items.any fun item =>
      match item with
      | .state _ => true
      | _ => false
    let head : Array ContribKey :=
      if hasState then #[statePersistent] else #[]
    let collected := program.items.foldl (fun acc item =>
      acc ++ itemKeys item) head
    let mut seen : Array String := #[]
    let mut out : Array ContribKey := #[]
    for k in collected do
      let id := contribId k
      if !seen.contains id then
        seen := seen.push id
        out := out.push k
    pure out

/-- Freeze exact ProgramRequirementsV1 for the semantic path.
    Rejects any non-catalog contribution key (fail closed; no partial table). -/
def freezeProgramRequirementsV1 (program : ProgramV1) :
    Except String ProgramRequirementsV1 := do
  let keys := inferContributionKeysV1 program
  let mut rawIds : Array String := #[]
  for k in keys do
    match k with
    | .catalog id => rawIds := rawIds.push id
    | .foreign id =>
        throw s!"S2 semantic requirements freeze rejects non-catalog key '{id}'"
  let mut items : Array RequirementRequestV1 := #[]
  for id in rawIds do
    items := items.push (← mkS2RequirementRequestV1 id)
  let sorted ← sortRequirementRequestsV1 items
  pure { items := sorted }

/-- Freeze from a validated source unit. -/
def freezeProgramRequirementsFromSourceV1 (source : ValidatedSourceV1) :
    Except String ProgramRequirementsV1 :=
  freezeProgramRequirementsV1 source.program

end ProofForgeV2.Semantic.RequirementsV1
