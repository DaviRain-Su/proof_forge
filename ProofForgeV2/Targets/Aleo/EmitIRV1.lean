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
  else if isInt then "i64"
  else match uintWidth with
    | 8 => "u8"
    | 16 => "u16"
    | 32 => "u32"
    | _ => "u64"

private def leafDefaultString
    (isInt : Bool) (isField : Bool) (uintWidth : Nat) : String :=
  if isField then "0field"
  else if isInt then "0i64"
  else match uintWidth with
    | 8 => "0u8"
    | 16 => "0u16"
    | 32 => "0u32"
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

private def renderViewJson (view : PlanView) (plan : Plan) : String :=
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
