/-
  ProofForgeV2.Typed.RequirementsInferV1 — target-neutral ProgramV1 requirement
  contribution analysis.

  This module is the sole ProgramV1 AST walk for requirement inference. It emits
  stable first-seen contribution identities only; it does not know Semantic wire
  records, versions, digests, predicates, target support, or the legacy alpha
  `ProgramRequirement` enum.

  `Semantic.RequirementsV1` is the sole product consumer. That layer validates
  the closed engineering catalog, mints `RequirementRequestV1` rows, and applies
  canonical wire ordering. Targets and resolvers must consume only the frozen
  `ProgramRequirementsV1` embedded in `SemanticProgramV1`.

  Formal TASK-D2-05 / RequirementRef / predicate merge / contribution origins
  remain pending.
-/
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.ContextCommitSurfaceV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace ProofForgeV2.Typed.RequirementsInferV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.ContextCommitSurfaceV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

/-- Render a source qualified name as a dot-separated string (for catalog QN
    comparison). Mirrors `Typed.ModelV1.sourceQualifiedNameV1ToString`. -/
private def qnToString (qn : SourceQualifiedNameV1) : String :=
  String.intercalate "." ((NonEmptyArray.toArray qn.components).map (·.raw) |>.toList)

/-- One target-neutral requirement contribution identity.
    Private constructor: only this AST analysis can mint contributions. -/
structure RequirementContributionV1 where
  private mk ::
  id : String
  deriving BEq, Repr, Inhabited

namespace RequirementContributionV1

def idOf (contribution : RequirementContributionV1) : String := contribution.id

end RequirementContributionV1

private def contribution (id : String) : RequirementContributionV1 :=
  RequirementContributionV1.mk id

private def persistentState := contribution s2StatePersistentIdV1
private def checkedArithmetic := contribution s2ValueCheckedArithmeticIdV1
private def transactionalRollback := contribution s2FailureAtomicRollbackIdV1
private def synchronousCall := contribution s2EffectSyncCallIdV1
private def asynchronousWorkflow := contribution s2EffectAsyncWorkflowIdV1
private def privateWitness := contribution inferDisclosurePrivateWitnessIdV1
private def eventEmission := contribution s2EffectEventIdV1
private def boolValues := contribution s2ValueBoolIdV1
private def commitmentDisclosure := contribution inferDisclosureCommitmentIdV1
private def fieldBn254 := contribution inferValueFieldBn254FrIdV1
/-- T14 catalog v2: BLS12-377 Fr Field type contribution (Aleo native field). -/
private def fieldBls12377 := contribution inferValueFieldBls12377FrIdV1
/-- T14 catalog v2: Goldilocks Field type contribution (Psy native Felt). -/
private def fieldGoldilocks := contribution inferValueFieldGoldilocksIdV1
private def privateState := contribution inferDisclosurePrivateStateIdV1
private def commitmentState := contribution inferDisclosureCommitmentStateIdV1
/-- T-3: ContextRead / Commit contribution identities (wire spellings; freeze-skipped
    because Normalize merges exact wire rows after S2 freeze). -/
private def contextUnixTime := contribution wireContextUnixTimeSecondsIdV1
private def contextCaller := contribution wireContextCallerIdV1
private def contextBlockHeight := contribution wireContextBlockHeightIdV1
private def commitOp := contribution wireCommitmentDisclosureIdV1

/-- ADR-0030 E2: env-read catalog call sites require the `extension.pf-assets`
    requirement row (same catalog-call-requires-that-row discipline as the
    statement QNs). Env-read produces NO effect (not synchronous-call). -/
private def pfAssetsExtensionRow := contribution wireExtensionPfAssetsIdV1

private def stableUniqueContributions
    (values : Array RequirementContributionV1) : Array RequirementContributionV1 :=
  values.foldl (fun found value =>
    if found.any (fun existing =>
        RequirementContributionV1.idOf existing == RequirementContributionV1.idOf value) then
      found
    else
      found.push value) #[]

private partial def typeContributions : TypeV1 → Array RequirementContributionV1
  | .bool => #[boolValues]
  | .field id =>
      -- T14 catalog v2: one contribution per closed-catalog Field token.
      if id.raw == "bn254_fr" then #[fieldBn254]
      else if id.raw == "bls12_377_fr" then #[fieldBls12377]
      else if id.raw == "goldilocks" then #[fieldGoldilocks]
      else #[]
  | .option element => typeContributions element
  | .array element _ => typeContributions element
  | .map key value => typeContributions key ++ typeContributions value
  | .uint _ | .int _ | .principal | .unit | .string | .named _ | .bytes _ => #[]

private def stateVisibilityContributions : VisibilityV1 → Array RequirementContributionV1
  | .public_ => #[]
  | .private_ => #[privateState]
  | .commitment => #[commitmentState]

private def paramVisibilityContributions : VisibilityV1 → Array RequirementContributionV1
  | .public_ => #[]
  | .private_ => #[privateWitness]
  | .commitment => #[commitmentDisclosure]

private def paramContributions (param : ParamV1) : Array RequirementContributionV1 :=
  typeContributions param.type_ ++ paramVisibilityContributions param.visibility

private def stateContributions (state : StateDeclV1) : Array RequirementContributionV1 :=
  typeContributions state.type_ ++ stateVisibilityContributions state.visibility

mutual
  private partial def placeContributions : PlaceV1 → Array RequirementContributionV1
    | .name _ => #[]
    | .field base field =>
        -- T-3/ADR-0031-S2: exact ContextRead surfaces (context.unixTimeSeconds /
        -- context.caller / context.blockHeight).
        if isContextUnixTimeSecondsPlaceV1 (.field base field) then
          #[contextUnixTime]
        else if isContextCallerPlaceV1 (.field base field) then
          #[contextCaller]
        else if isContextBlockHeightPlaceV1 (.field base field) then
          #[contextBlockHeight]
        else
          placeContributions base
    | .index base index => placeContributions base ++ exprContributions index

  private partial def exprContributions : ExprV1 → Array RequirementContributionV1
    | .literal _ => #[]
    | .place place => placeContributions place
    | .constructor ctor args =>
        let child := args.flatMap exprContributions
        -- ADR-0030 E2: env-read catalog QNs require the extension.pf-assets
        -- requirement row; they produce NO effect (not synchronous-call).
        if isPfAssetsEnvReadQnV1 (qnToString ctor) then
          child ++ #[pfAssetsExtensionRow]
        else
          child
    | .unary .neg operand =>
        exprContributions operand ++ #[checkedArithmetic, transactionalRollback]
    | .unary _ operand => exprContributions operand
    | .binary op lhs rhs =>
        let child := exprContributions lhs ++ exprContributions rhs
        match op with
        | .add | .sub | .mul | .div | .mod =>
            child ++ #[checkedArithmetic, transactionalRollback]
        | _ => child
    | .localCall callee args =>
        let child := args.flatMap exprContributions
        -- T-3: intrinsic commit(x) shape (fn-shadow still product-resolved later).
        if isCommitLocalCallShapeV1 (.localCall callee args) then
          child ++ #[commitOp]
        else
          child
    | .match_ scrutinee arms =>
        exprContributions scrutinee ++
          arms.flatMap (fun arm => exprContributions arm.value)
    | .externalCall call =>
        -- N-CALL-RET: value-position sync call contributes the same
        -- synchronous-call + rollback requirements as statement call.
        call.args.flatMap exprContributions ++ #[synchronousCall, transactionalRollback]

  private partial def stmtContributions : StmtV1 → Array RequirementContributionV1
    | .let_ _ typeAnn? value =>
        (match typeAnn? with
          | some type => typeContributions type
          | none => #[]) ++
          exprContributions value
    | .assign target value =>
        placeContributions target ++ exprContributions value
    | .if_ condition thenBlock elseBlock? =>
        exprContributions condition ++ blockContributions thenBlock ++
          (match elseBlock? with
            | some block => blockContributions block
            | none => #[])
    | .match_ scrutinee arms =>
        exprContributions scrutinee ++
          arms.flatMap (fun arm => blockContributions arm.body)
    | .for_ _ start endExclusive _ body =>
        exprContributions start ++ exprContributions endExclusive ++
          blockContributions body
    | .assert_ condition _ =>
        exprContributions condition ++ #[transactionalRollback]
    | .revert _ args =>
        args.flatMap exprContributions ++ #[transactionalRollback]
    | .emit _ args =>
        args.flatMap exprContributions ++ #[eventEmission]
    | .return_ value? =>
        match value? with
        | some value => exprContributions value
        | none => #[]
    | .call call =>
        call.args.flatMap exprContributions ++
          #[synchronousCall, transactionalRollback]
    | .schedule call =>
        call.args.flatMap exprContributions ++ #[asynchronousWorkflow]

  private partial def blockContributions
      (block : BlockV1) : Array RequirementContributionV1 :=
    block.statements.flatMap stmtContributions
end

private def itemContributions : ProgramItemV1 → Array RequirementContributionV1
  | .state declaration => stateContributions declaration
  | .init declaration =>
      declaration.params.flatMap paramContributions ++
        blockContributions declaration.body
  | .entry declaration =>
      declaration.params.flatMap paramContributions ++
        typeContributions declaration.result ++
        blockContributions declaration.body
  | .view declaration =>
      declaration.params.flatMap paramContributions ++
        typeContributions declaration.result ++
        blockContributions declaration.body
  | .fn declaration =>
      declaration.params.flatMap paramContributions ++
        typeContributions declaration.result ++
        blockContributions declaration.body
  | .const declaration =>
      typeContributions declaration.type_ ++ exprContributions declaration.value
  | .invariant declaration => exprContributions declaration.predicate
  | .struct _ | .enum _ | .event _ | .error _ | .extensionReq _ | .proof _ => #[]

/-- Sole ProgramV1 requirement-contribution walk. Results are source-order,
    first-seen stable unique identities. Product callers must pass them through
    `Semantic.RequirementsV1.freezeProgramRequirementsV1`; they are not resolved
    support decisions or wire rows. -/
def inferRequirementContributionsV1
    (program : ProgramV1) : Array RequirementContributionV1 :=
  let hasState := program.items.any fun item =>
    match item with
    | .state _ => true
    | _ => false
  let head : Array RequirementContributionV1 :=
    if hasState then #[persistentState] else #[]
  let collected := program.items.foldl (fun accumulated item =>
    accumulated ++ itemContributions item) head
  stableUniqueContributions collected

/-- Validated-source inspection projection of the sole contribution walk. -/
def inferRequirementContributionsFromSourceV1
    (source : ValidatedSourceV1) : Array RequirementContributionV1 :=
  inferRequirementContributionsV1 source.program

end ProofForgeV2.Typed.RequirementsInferV1
