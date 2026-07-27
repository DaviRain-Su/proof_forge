/-
  ProofForgeV2.Typed.RequirementsInferV1 — D2-05 ProgramRequirements inference
  engineering subset.

  Independent pure-AST walk over ValidatedSourceV1 / ProgramV1 that produces a
  deterministic `Array ProgramRequirement` (alpha `Core.Diagnostic.ProgramRequirement`
  carrier) with source-order first-seen `stableUnique` semantics matching
  `Semantic.deriveRequirements`.

  Inference covers only currently expressible ProgramV1 surface:
    * non-empty state ⇒ `.persistentState`
    * state visibility: public_ none; private_ ⇒ `.privateState`;
      commitment ⇒ `.commitmentState` (never `.privateWitness` for state)
    * init/entry/view/fn param visibility: private_ ⇒ `.privateWitness`;
      commitment ⇒ `.commitmentDisclosure`
    * type carriers (state/param/result/const; Option/Array recurse; Map key+value):
      `.bool` ⇒ `.boolValues`; `.field bn254_fr` ⇒ `.fieldBn254`
    * arithmetic binary `+ - * / %` and unary `-` ⇒ `.checkedArithmetic` +
      `.transactionalRollback`
    * `Stmt.call` ⇒ `.synchronousCall` + `.transactionalRollback`
    * `Stmt.schedule` ⇒ `.asynchronousWorkflow` only (alpha has no schedule
      rule; fail-closed stable choice — no invented transactionalRollback)
    * `Stmt.emit` ⇒ `.eventEmission`
    * `assert_` / `revert` ⇒ `.transactionalRollback`

  Does NOT invent `.callerContext`, authority.*, state-custody.*, or
  disclosure.commit. Does NOT depend on call-graph edges, so duplicate `fn`
  keys still yield `analysisComplete = true` / `ok = true` for declaration-
  level requirements (body walk is pure AST, not name-resolution edges).

  Product wiring (this engineering subset):
    * NOT composed into CheckV1 phases
    * does NOT change Typed.checkV1 / compileValidatedSourceV1 / CLI
    * does NOT replace Semantic.deriveRequirements
    * independent module + tests only (same posture as early EffectCheck)

  Formal TASK-D2-05 / RequirementRef / predicate merge / SemanticProgramV1 /
  provenance remain pending.
-/
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace ProofForgeV2.Typed.RequirementsInferV1

open ProofForgeV2.Core
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1

/-- Result of independent ProgramV1 requirements inference. -/
structure RequirementsInferResultV1 where
  requirements : Array ProgramRequirement
  ok : Bool
  analysisComplete : Bool
  deriving BEq, Repr, Inhabited

/-- First-seen stable unique, matching `SemanticIR.stableUnique`. -/
def stableUnique [BEq α] (values : Array α) : Array α :=
  values.foldl (fun found value =>
    if found.contains value then found else found.push value) #[]

/-- Type-carrier requirements (alpha `ValueType.requirements` + Map recurse). -/
partial def typeRequirements : TypeV1 → Array ProgramRequirement
  | .bool => #[.boolValues]
  | .field id =>
      if id.raw == "bn254_fr" then #[.fieldBn254] else #[]
  | .option element => typeRequirements element
  | .array element _ => typeRequirements element
  | .map key value => typeRequirements key ++ typeRequirements value
  | .uint _ | .int _ | .principal | .unit | .named _ | .bytes _ => #[]

/-- State visibility → state-specific disclosure (never privateWitness). -/
def stateVisibilityRequirements : VisibilityV1 → Array ProgramRequirement
  | .public_ => #[]
  | .private_ => #[.privateState]
  | .commitment => #[.commitmentState]

/-- Param visibility on init/entry/view/fn. -/
def paramVisibilityRequirements : VisibilityV1 → Array ProgramRequirement
  | .public_ => #[]
  | .private_ => #[.privateWitness]
  | .commitment => #[.commitmentDisclosure]

def paramRequirements (param : ParamV1) : Array ProgramRequirement :=
  typeRequirements param.type_ ++ paramVisibilityRequirements param.visibility

def stateRequirements (state : StateDeclV1) : Array ProgramRequirement :=
  typeRequirements state.type_ ++ stateVisibilityRequirements state.visibility

mutual
  partial def placeRequirements : PlaceV1 → Array ProgramRequirement
    | .name _ => #[]
    | .field base _ => placeRequirements base
    | .index base idx => placeRequirements base ++ exprRequirements idx

  partial def exprRequirements : ExprV1 → Array ProgramRequirement
    | .literal _ => #[]
    | .place p => placeRequirements p
    | .constructor _ args => args.flatMap exprRequirements
    | .unary .neg operand =>
        exprRequirements operand ++ #[.checkedArithmetic, .transactionalRollback]
    | .unary _ operand => exprRequirements operand
    | .binary op lhs rhs =>
        let child := exprRequirements lhs ++ exprRequirements rhs
        match op with
        | .add | .sub | .mul | .div | .mod =>
            child ++ #[.checkedArithmetic, .transactionalRollback]
        | _ => child
    | .localCall _ args => args.flatMap exprRequirements
    | .match_ scrutinee arms =>
        exprRequirements scrutinee ++
          arms.flatMap (fun arm => exprRequirements arm.value)

  partial def stmtRequirements : StmtV1 → Array ProgramRequirement
    | .let_ _ typeAnn? value =>
        (match typeAnn? with
          | some t => typeRequirements t
          | none => #[]) ++
          exprRequirements value
    | .assign target value =>
        placeRequirements target ++ exprRequirements value
    | .if_ cond thenB elseB? =>
        exprRequirements cond ++ blockRequirements thenB ++
          (match elseB? with
            | some b => blockRequirements b
            | none => #[])
    | .match_ scrutinee arms =>
        exprRequirements scrutinee ++
          arms.flatMap (fun arm => blockRequirements arm.body)
    | .for_ _ start endEx _ body =>
        exprRequirements start ++ exprRequirements endEx ++ blockRequirements body
    | .assert_ cond _ =>
        exprRequirements cond ++ #[.transactionalRollback]
    | .revert _ args =>
        args.flatMap exprRequirements ++ #[.transactionalRollback]
    | .emit _ args =>
        args.flatMap exprRequirements ++ #[.eventEmission]
    | .return_ value? =>
        match value? with
        | some e => exprRequirements e
        | none => #[]
    | .call call =>
        call.args.flatMap exprRequirements ++
          #[.synchronousCall, .transactionalRollback]
    | .schedule call =>
        -- Alpha `deriveRequirements` has no schedule rule. Engineering choice:
        -- emit `.asynchronousWorkflow` only; do not invent transactionalRollback.
        call.args.flatMap exprRequirements ++ #[.asynchronousWorkflow]

  partial def blockRequirements (block : BlockV1) : Array ProgramRequirement :=
    block.statements.flatMap stmtRequirements
end

/-- Requirements contributed by one program item (excluding the top-level
    `.persistentState` flag, which is emitted once when any state exists). -/
def itemRequirements : ProgramItemV1 → Array ProgramRequirement
  | .state decl => stateRequirements decl
  | .init decl =>
      decl.params.flatMap paramRequirements ++ blockRequirements decl.body
  | .entry decl =>
      decl.params.flatMap paramRequirements ++
        typeRequirements decl.result ++
        blockRequirements decl.body
  | .view decl =>
      decl.params.flatMap paramRequirements ++
        typeRequirements decl.result ++
        blockRequirements decl.body
  | .fn decl =>
      decl.params.flatMap paramRequirements ++
        typeRequirements decl.result ++
        blockRequirements decl.body
  | .const decl =>
      typeRequirements decl.type_ ++ exprRequirements decl.value
  | .invariant decl => exprRequirements decl.predicate
  | .struct _ | .enum _ | .event _ | .error _ | .extensionReq _ | .proof _ => #[]

/-- Infer requirements from a ProgramV1 AST. Pure declaration+body walk;
    always complete (`analysisComplete = true`, `ok = true`). -/
def inferRequirementsFromProgramV1 (program : ProgramV1) : RequirementsInferResultV1 :=
  let hasState := program.items.any fun item =>
    match item with
    | .state _ => true
    | _ => false
  let head : Array ProgramRequirement :=
    if hasState then #[.persistentState] else #[]
  let collected := program.items.foldl (fun acc item =>
    acc ++ itemRequirements item) head
  { requirements := stableUnique collected
    ok := true
    analysisComplete := true }

/-- Infer requirements from a validated source unit. -/
def inferRequirementsV1 (source : ValidatedSourceV1) : RequirementsInferResultV1 :=
  inferRequirementsFromProgramV1 source.program

end ProofForgeV2.Typed.RequirementsInferV1
