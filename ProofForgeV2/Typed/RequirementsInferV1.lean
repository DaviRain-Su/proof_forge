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
private def contextChainId := contribution wireContextChainIdIdV1
private def contextSelf := contribution wireContextSelfIdV1
private def contextAttachedValue := contribution wireContextAttachedValueIdV1
private def commitOp := contribution wireCommitmentDisclosureIdV1

/-- ADR-0030 E2: env-read catalog call sites require the `extension.pf-assets`
    requirement row (same catalog-call-requires-that-row discipline as the
    statement QNs). Env-read produces NO effect (not synchronous-call). -/
private def pfAssetsExtensionRow := contribution wireExtensionPfAssetsIdV1

private def stringEqV1 (left right : String) : Bool :=
  left.toUTF8 == right.toUTF8

private def contributionIdInV1
    (value : RequirementContributionV1) : List RequirementContributionV1 → Bool
  | [] => false
  | existing :: rest =>
      stringEqV1 (RequirementContributionV1.idOf existing)
          (RequirementContributionV1.idOf value) ||
        contributionIdInV1 value rest

private def stableUniqueContributionsListV1
    (found : List RequirementContributionV1) :
    List RequirementContributionV1 → List RequirementContributionV1
  | [] => found.reverse
  | value :: rest =>
      if contributionIdInV1 value found then
        stableUniqueContributionsListV1 found rest
      else
        stableUniqueContributionsListV1 (value :: found) rest

private def stableUniqueContributions
    (values : Array RequirementContributionV1) : Array RequirementContributionV1 :=
  (stableUniqueContributionsListV1 [] values.toList).toArray

private def typeContributions : TypeV1 → Array RequirementContributionV1
  | .bool => #[boolValues]
  | .field id =>
      -- T14 catalog v2: one contribution per closed-catalog Field token.
      if stringEqV1 id.raw "bn254_fr" then #[fieldBn254]
      else if stringEqV1 id.raw "bls12_377_fr" then #[fieldBls12377]
      else if stringEqV1 id.raw "goldilocks" then #[fieldGoldilocks]
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

private def sourceDepthFuelV1 : Nat := 256

/-- An exhausted hand-built source fixture contributes an unknown identity, so
    the sole S2 freezer rejects it instead of silently omitting requirements. -/
private def sourceDepthExceededV1 : Array RequirementContributionV1 :=
  #[contribution "proof-forge.internal.source-depth-exceeded"]

mutual
  private def placeContributionsFuelV1
      (fuel : Nat) (place : PlaceV1) : Array RequirementContributionV1 :=
    match fuel, place with
    | 0, _ => sourceDepthExceededV1
    | _ + 1, .name _ => #[]
    | fuel + 1, .field base field =>
        -- T-3/ADR-0031-S2/S3: exact ContextRead surfaces.
        if isContextUnixTimeSecondsPlaceV1 (.field base field) then
          #[contextUnixTime]
        else if isContextCallerPlaceV1 (.field base field) then
          #[contextCaller]
        else if isContextBlockHeightPlaceV1 (.field base field) then
          #[contextBlockHeight]
        else if isContextChainIdPlaceV1 (.field base field) then
          #[contextChainId]
        else if isContextSelfPlaceV1 (.field base field) then
          #[contextSelf]
        else if isContextAttachedValuePlaceV1 (.field base field) then
          #[contextAttachedValue]
        else
          placeContributionsFuelV1 fuel base
    | fuel + 1, .index base index =>
        placeContributionsFuelV1 fuel base ++ exprContributionsFuelV1 fuel index

  private def exprContributionsFuelV1
      (fuel : Nat) (expr : ExprV1) : Array RequirementContributionV1 :=
    match fuel, expr with
    | 0, _ => sourceDepthExceededV1
    | _ + 1, .literal _ => #[]
    | fuel + 1, .place place => placeContributionsFuelV1 fuel place
    | fuel + 1, .constructor ctor args =>
        let child := args.flatMap (exprContributionsFuelV1 fuel)
        -- ADR-0030 E2: env-read catalog QNs require the extension.pf-assets
        -- requirement row; they produce NO effect (not synchronous-call).
        if isPfAssetsEnvReadQnV1 (qnToString ctor) then
          child ++ #[pfAssetsExtensionRow]
        else
          child
    | fuel + 1, .unary .neg operand =>
        exprContributionsFuelV1 fuel operand ++
          #[checkedArithmetic, transactionalRollback]
    | fuel + 1, .unary _ operand => exprContributionsFuelV1 fuel operand
    | fuel + 1, .binary op lhs rhs =>
        let child := exprContributionsFuelV1 fuel lhs ++
          exprContributionsFuelV1 fuel rhs
        match op with
        | .add | .sub | .mul | .div | .mod =>
            child ++ #[checkedArithmetic, transactionalRollback]
        | _ => child
    | fuel + 1, .localCall callee args =>
        let child := args.flatMap (exprContributionsFuelV1 fuel)
        -- T-3: intrinsic commit(x) shape (fn-shadow still product-resolved later).
        if isCommitLocalCallShapeV1 (.localCall callee args) then
          child ++ #[commitOp]
        else
          child
    | fuel + 1, .match_ scrutinee arms =>
        exprContributionsFuelV1 fuel scrutinee ++
          arms.flatMap (fun arm => exprContributionsFuelV1 fuel arm.value)
    | fuel + 1, .externalCall call =>
        -- N-CALL-RET: value-position sync call contributes the same
        -- synchronous-call + rollback requirements as statement call.
        -- SYS-S5: exact `pf.crypto.sha256|keccak256` are host syscall / precompile leaves
        -- (env-read discipline): no effect.synchronous-call contribution.
        let child := call.args.flatMap (exprContributionsFuelV1 fuel)
        if isPfCryptoHostSyscallQnV1 (qnToString call.callee) then
          child
        else
          child ++ #[synchronousCall, transactionalRollback]

  private def stmtContributionsFuelV1
      (fuel : Nat) (stmt : StmtV1) : Array RequirementContributionV1 :=
    match fuel, stmt with
    | 0, _ => sourceDepthExceededV1
    | fuel + 1, .let_ _ typeAnn? value =>
        (match typeAnn? with
          | some type => typeContributions type
          | none => #[]) ++
          exprContributionsFuelV1 fuel value
    | fuel + 1, .assign target value =>
        placeContributionsFuelV1 fuel target ++ exprContributionsFuelV1 fuel value
    | fuel + 1, .if_ condition thenBlock elseBlock? =>
        exprContributionsFuelV1 fuel condition ++
          blockContributionsFuelV1 fuel thenBlock ++
          (match elseBlock? with
            | some block => blockContributionsFuelV1 fuel block
            | none => #[])
    | fuel + 1, .match_ scrutinee arms =>
        exprContributionsFuelV1 fuel scrutinee ++
          arms.flatMap (fun arm => blockContributionsFuelV1 fuel arm.body)
    | fuel + 1, .for_ _ start endExclusive _ body =>
        exprContributionsFuelV1 fuel start ++
          exprContributionsFuelV1 fuel endExclusive ++
          blockContributionsFuelV1 fuel body
    | fuel + 1, .assert_ condition _ =>
        exprContributionsFuelV1 fuel condition ++ #[transactionalRollback]
    | fuel + 1, .revert _ args =>
        args.flatMap (exprContributionsFuelV1 fuel) ++ #[transactionalRollback]
    | fuel + 1, .emit _ args =>
        args.flatMap (exprContributionsFuelV1 fuel) ++ #[eventEmission]
    | fuel + 1, .return_ value? =>
        match value? with
        | some value => exprContributionsFuelV1 fuel value
        | none => #[]
    | fuel + 1, .call call =>
        let child := call.args.flatMap (exprContributionsFuelV1 fuel)
        if isPfCryptoHostSyscallQnV1 (qnToString call.callee) then
          child
        else
          child ++ #[synchronousCall, transactionalRollback]
    | fuel + 1, .schedule call =>
        call.args.flatMap (exprContributionsFuelV1 fuel) ++ #[asynchronousWorkflow]

  private def blockContributionsFuelV1
      (fuel : Nat) (block : BlockV1) : Array RequirementContributionV1 :=
    match fuel with
    | 0 => sourceDepthExceededV1
    | fuel + 1 => block.statements.flatMap (stmtContributionsFuelV1 fuel)
end

private def exprContributions (expr : ExprV1) : Array RequirementContributionV1 :=
  exprContributionsFuelV1 sourceDepthFuelV1 expr

private def blockContributions (block : BlockV1) : Array RequirementContributionV1 :=
  blockContributionsFuelV1 sourceDepthFuelV1 block

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
  let hasState := program.items.toList.any fun item =>
    match item with
    | .state _ => true
    | _ => false
  let head : Array RequirementContributionV1 :=
    if hasState then #[persistentState] else #[]
  let collected := program.items.toList.foldl (fun accumulated item =>
    accumulated ++ itemContributions item) head
  stableUniqueContributions collected

/-- Validated-source inspection projection of the sole contribution walk. -/
def inferRequirementContributionsFromSourceV1
    (source : ValidatedSourceV1) : Array RequirementContributionV1 :=
  inferRequirementContributionsV1 source.program

end ProofForgeV2.Typed.RequirementsInferV1
