import ProofForgeV2.Targets.Aleo.ValidatePlanV1
import ProofForgeV2.Targets.Aleo.Instructions.LowerPlanV1
import ProofForgeV2.Targets.Aleo.Instructions.TextCodecV1

/-!
# Aleo EmitIRV1 — direct Plan → Aleo Instructions

The Aleo target owns one product IR: canonical Aleo Instructions. No alternate
source AST, debug dual-write, compiler profile, or compiler finalization exists.
-/

namespace ProofForgeV2.Targets.Aleo

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.Aleo.Instructions.SchemaV1
open ProofForgeV2.Targets.Aleo.Instructions.TextCodecV1
open ProofForgeV2.Targets.Aleo.Instructions.LowerPlanV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .aleo message

/-- Target-owned Aleo Instructions IR bound to its exact source Plan/profile. -/
structure IR where
  sourcePlan : Plan
  program : ProgramV1
  codegenProfile : CodegenProfileId
  deriving BEq, Repr

private def asciiLower (value : String) : String :=
  String.ofList <| value.toList.map fun c =>
    let code := c.toNat
    if 65 <= code && code <= 90 then Char.ofNat (code + 32) else c

private def lower (plan : Plan) (profile : CodegenProfileId) : CompileResult IR := do
  validatePlan plan
  unless profile == CodegenProfileId.aleoInstructionsV1 do
    planError s!"unsupported Aleo codegen profile '{profile}'"
  let program ← lowerPlanToInstructionsV1 plan
  pure { sourcePlan := plan, program, codegenProfile := profile }

/-- Recheck the Plan/profile join and canonical Instructions codec round trip. -/
def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless ir.codegenProfile == CodegenProfileId.aleoInstructionsV1 do
    planError s!"unsupported Aleo codegen profile '{ir.codegenProfile}'"
  let expected ← lowerPlanToInstructionsV1 ir.sourcePlan
  unless expected == ir.program do
    planError "Aleo Instructions IR does not match its source Plan"
  let encoded := encodeProgram ir.program
  unless decodeProgram? encoded == some ir.program do
    planError "Aleo Instructions failed canonical codec round trip"

private def mappingKey : String := "0u8"

private def leafTypeString
    (isInt : Bool) (isField : Bool) (uintWidth : Nat) : String :=
  if isField then "field"
  else if isInt then
    match uintWidth with
    | 8 => "i8"
    | 16 => "i16"
    | 32 => "i32"
    | _ => "i64"
  else match uintWidth with
    | 8 => "u8"
    | 16 => "u16"
    | 32 => "u32"
    | 128 => "u128"
    | _ => "u64"

private def leafDefaultString
    (isInt : Bool) (isField : Bool) (uintWidth : Nat) : String :=
  if isField then "0field"
  else if isInt then
    match uintWidth with
    | 8 => "0i8"
    | 16 => "0i16"
    | 32 => "0i32"
    | _ => "0i64"
  else match uintWidth with
    | 8 => "0u8"
    | 16 => "0u16"
    | 32 => "0u32"
    | 128 => "0u128"
    | _ => "0u64"

private def renderMappingJson (i : Nat) (plan : Plan) : String :=
  let dslName := plan.stateFieldNames[i]!
  let isInt := plan.stateFieldIsInt.getD i false
  let isField := plan.stateFieldIsField.getD i false
  let width := plan.stateFieldUintWidth.getD i 0
  "{" ++
    s!"\"name\":\"pf_state_{i}\"," ++
    s!"\"dslName\":\"{Targets.escapeJson dslName}\"," ++
    s!"\"type\":\"{leafTypeString isInt isField width}\"," ++
    s!"\"default\":\"{leafDefaultString isInt isField width}\"" ++
    "}"

private def cmpOpJson : ComparisonOp → String
  | .eq => "eq" | .ne => "ne" | .lt => "lt" | .le => "le" | .gt => "gt" | .ge => "ge"

private def fieldOpJson : FieldArithOp → String
  | .add => "add" | .sub => "sub" | .mul => "mul" | .div => "div"

private partial def renderExprJson (e : Expr) : String :=
  let bin (op : String) (l r : Expr) :=
    s!"\{\"op\":\"{op}\",\"lhs\":{renderExprJson l},\"rhs\":{renderExprJson r}}"
  let un (op : String) (o : Expr) :=
    s!"\{\"op\":\"{op}\",\"operand\":{renderExprJson o}}"
  let nbin (op : String) (w : Nat) (l r : Expr) :=
    s!"\{\"op\":\"{op}\",\"bitWidth\":{w},\"lhs\":{renderExprJson l},\"rhs\":{renderExprJson r}}"
  let nun (op : String) (w : Nat) (o : Expr) :=
    s!"\{\"op\":\"{op}\",\"bitWidth\":{w},\"operand\":{renderExprJson o}}"
  match e with
  | .literal v => s!"\{\"op\":\"literal\",\"value\":\"{v}\"}"
  | .i64Literal v => s!"\{\"op\":\"i64Literal\",\"value\":\"{v}\"}"
  | .uintLiteral w v => s!"\{\"op\":\"uintLiteral\",\"bitWidth\":{w},\"value\":\"{v}\"}"
  | .boolLiteral v => s!"\{\"op\":\"boolLiteral\",\"value\":{if v then "true" else "false"}}"
  | .param i => s!"\{\"op\":\"param\",\"index\":{i}}"
  | .loopVar d => s!"\{\"op\":\"loopVar\",\"depth\":{d}}"
  | .stateLoad i => s!"\{\"op\":\"stateLoad\",\"index\":{i}}"
  | .checkedAdd l r => bin "add" l r
  | .checkedSub l r => bin "sub" l r
  | .checkedMul l r => bin "mul" l r
  | .checkedDiv l r => bin "div" l r
  | .checkedMod l r => bin "mod" l r
  | .narrowCheckedAdd w l r => nbin "add" w l r
  | .narrowCheckedSub w l r => nbin "sub" w l r
  | .narrowCheckedMul w l r => nbin "mul" w l r
  | .narrowCheckedDiv w l r => nbin "div" w l r
  | .narrowCheckedMod w l r => nbin "mod" w l r
  | .compare op l r =>
      s!"\{\"op\":\"{cmpOpJson op}\",\"lhs\":{renderExprJson l},\"rhs\":{renderExprJson r}}"
  | .signedCheckedAdd l r => bin "signedAdd" l r
  | .signedCheckedSub l r => bin "signedSub" l r
  | .signedCheckedMul l r => bin "signedMul" l r
  | .signedCheckedDiv l r => bin "signedDiv" l r
  | .signedCheckedMod l r => bin "signedMod" l r
  | .signedCompare op l r =>
      s!"\{\"op\":\"signed_{cmpOpJson op}\",\"lhs\":{renderExprJson l},\"rhs\":{renderExprJson r}}"
  | .bitAnd l r => bin "bitAnd" l r
  | .bitOr l r => bin "bitOr" l r
  | .bitXor l r => bin "bitXor" l r
  | .narrowBitAnd w l r => nbin "bitAnd" w l r
  | .narrowBitOr w l r => nbin "bitOr" w l r
  | .narrowBitXor w l r => nbin "bitXor" w l r
  | .signedBitAnd l r => bin "signedBitAnd" l r
  | .signedBitOr l r => bin "signedBitOr" l r
  | .signedBitXor l r => bin "signedBitXor" l r
  | .logicalAnd l r => bin "and" l r
  | .logicalOr l r => bin "or" l r
  | .shl l r => bin "shl" l r
  | .shr l r => bin "shr" l r
  | .narrowShl w l r => nbin "shl" w l r
  | .narrowShr w l r => nbin "shr" w l r
  | .signedShl l r => bin "signedShl" l r
  | .signedShr l r => bin "signedShr" l r
  | .bitNot o => un "bitNot" o
  | .signedBitNot o => un "signedBitNot" o
  | .narrowBitNot w o => nun "bitNot" w o
  | .boolNot o => un "boolNot" o
  | .checkedNeg o => un "neg" o
  | .ternary c t e =>
      s!"\{\"op\":\"ternary\",\"cond\":{renderExprJson c},\"then\":{renderExprJson t},\"else\":{renderExprJson e}}"
  | .fieldLiteral v => s!"\{\"op\":\"fieldLiteral\",\"value\":\"{v}\"}"
  | .fieldBinary op l r =>
      s!"\{\"op\":\"field_{fieldOpJson op}\",\"lhs\":{renderExprJson l},\"rhs\":{renderExprJson r}}"
  | .fieldCompare op l r =>
      s!"\{\"op\":\"field_{cmpOpJson op}\",\"lhs\":{renderExprJson l},\"rhs\":{renderExprJson r}}"
  | .fieldNeg o => un "fieldNeg" o
  | .callFn name args =>
      let parts := args.map renderExprJson
      s!"\{\"op\":\"call\",\"name\":\"{Targets.escapeJson name}\",\"args\":[{String.intercalate "," parts.toList}]}"

private partial def renderStmtJson (s : Statement) : String :=
  match s with
  | .returnValue e => s!"\{\"op\":\"return\",\"expr\":{renderExprJson e}}"
  | .returnNone => "{\"op\":\"returnNone\"}"
  | .assert e => s!"\{\"op\":\"assert\",\"cond\":{renderExprJson e}}"
  | .ifThenElse c t e =>
      let ts := String.intercalate "," (t.map renderStmtJson).toList
      let es := String.intercalate "," (e.map renderStmtJson).toList
      s!"\{\"op\":\"if\",\"cond\":{renderExprJson c},\"then\":[{ts}],\"else\":[{es}]}"
  | .switchOn scrut cases d =>
      let cs := String.intercalate "," (cases.map fun (k, body) =>
        let bs := String.intercalate "," (body.map renderStmtJson).toList
        s!"\{\"tag\":\"{k}\",\"body\":[{bs}]}").toList
      let ds := String.intercalate "," (d.map renderStmtJson).toList
      s!"\{\"op\":\"switch\",\"scrutinee\":{renderExprJson scrut},\"cases\":[{cs}],\"default\":[{ds}]}"
  | .returnAggregate leaves leafIsInt =>
      let leafJson := String.intercalate "," (leaves.map renderExprJson).toList
      let intJson := String.intercalate ","
        (leafIsInt.map (fun b => if b then "true" else "false")).toList
      s!"\{\"op\":\"returnAggregate\",\"leaves\":[{leafJson}],\"leafIsInt\":[{intJson}]}"
  | .store .. | .storeAggregate .. | .forLoop ..
  | .emitEvent .. | .revertError .. =>
      "{\"op\":\"forbidden\"}"

private def renderViewResultType
    (isBool isInt isField : Bool) (uintWidth : Nat) : String :=
  leafTypeString isInt isField uintWidth |> fun t =>
    if isBool then "bool" else t

private def renderViewJson (view : PlanView) (plan : Plan) : String :=
  if view.isComputed then
    let params := String.intercalate "," (view.params.toList.map fun p =>
      let pty :=
        if p.isBool then "bool"
        else leafTypeString p.isInt p.isField p.uintWidth
      s!"\{\"name\":\"{Targets.escapeJson p.name}\",\"type\":\"{pty}\"}")
    let body := String.intercalate "," (view.body.map renderStmtJson).toList
    let resultJson :=
      match view.resultAggregateLeaves with
      | some leaves =>
          let parts := leaves.map fun (l : LeafAbiType) =>
            if l.isInt then "\"i64\""
            else if l.byteWidth == 1 then "\"u8\""
            else "\"u64\""
          s!"[{String.intercalate "," parts.toList}]"
      | none =>
          let rty := renderViewResultType view.resultIsBool view.resultIsInt
            view.resultIsField view.resultUintWidth
          s!"\"{rty}\""
    "{" ++
      s!"\"name\":\"{Targets.escapeJson view.name}\"," ++
      "\"kind\":\"computed\"," ++
      s!"\"params\":[{params}]," ++
      s!"\"result\":{resultJson}," ++
      s!"\"body\":[{body}]" ++
      "}"
  else
    let i := view.stateFieldIndex
    let isInt := plan.stateFieldIsInt.getD i false
    let isField := plan.stateFieldIsField.getD i false
    let width := plan.stateFieldUintWidth.getD i 0
    "{" ++
      s!"\"index\":{i}," ++
      s!"\"name\":\"{Targets.escapeJson view.name}\"," ++
      s!"\"mapping\":\"pf_state_{i}\"," ++
      s!"\"key\":\"{mappingKey}\"," ++
      s!"\"type\":\"{leafTypeString isInt isField width}\"," ++
      s!"\"default\":\"{leafDefaultString isInt isField width}\"" ++
      "}"

private def renderResultDroppedJson (fn : PlanFunction) : String :=
  "{" ++
    s!"\"name\":\"{Targets.escapeJson fn.name}\"," ++
    "\"observation\":\"post-transaction-mapping-query\"" ++
    "}"

private def renderQueryContract (ir : IR) : String :=
  let plan := ir.sourcePlan
  let programId := asciiLower plan.programName
  let mappingParts := plan.stateFieldNames.mapIdx fun i _ => renderMappingJson i plan
  let viewParts := plan.views.map fun view => renderViewJson view plan
  let droppedParts :=
    (plan.functions.filter (·.resultDropped)).map renderResultDroppedJson
  "{\n" ++
    "  \"schema\": \"proof-forge-aleo-query-contract/v1\",\n" ++
    s!"  \"program\": \"{Targets.escapeJson plan.programName}\",\n" ++
    s!"  \"programFile\": \"{Targets.escapeJson ir.program.name}\",\n" ++
    s!"  \"codegenProfile\": \"{Targets.escapeJson ir.codegenProfile.toString}\",\n" ++
    s!"  \"irSchema\": \"{schemaIdV1}\",\n" ++
    s!"  \"sourceHash\": \"{Targets.escapeJson plan.sourceHash}\",\n" ++
    s!"  \"semanticHash\": \"{Targets.escapeJson plan.semanticHash}\",\n" ++
    s!"  \"mappingKey\": \"{mappingKey}\",\n" ++
    "  \"executionModel\": \"network-state-descriptor\",\n" ++
    s!"  \"mappings\": [{String.intercalate "," mappingParts.toList}],\n" ++
    s!"  \"views\": [{String.intercalate "," viewParts.toList}],\n" ++
    s!"  \"resultDropped\": [{String.intercalate "," droppedParts.toList}]\n" ++
    "}\n"

/-- Retained as a classifier for the hard fail-closed boundary. -/
def isAleoInstructionsG5HardResidualAllowlistV1 (_message : String) : Bool :=
  false

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  validateIR ir
  let programId := asciiLower ir.sourcePlan.programName
  unless ir.program.name == s!"{programId}.aleo" do
    planError "Aleo Instructions program name does not match its source Plan"
  pure #[
    {
      path := ir.program.name
      mediaType := "text/plain"
      contents := encodeProgram ir.program
    },
    {
      path := s!"{programId}.aleo-query-contract.json"
      mediaType := "application/json"
      contents := renderQueryContract ir
    }
  ]

/-- Capability-gated public Instructions IR entry. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← materializePlanFromCapabilityV1 capability
  lower plan (ResolvedEngineeringBuildV1.codegenProfileOf capability)

/-- Capability-gated public Aleo Instructions materializer. -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  emitFromIR (← irFromCapability capability)

end ProofForgeV2.Targets.Aleo
