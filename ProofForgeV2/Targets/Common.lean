import ProofForgeV2.Materialization.Protocol

namespace ProofForgeV2.Targets

open ProofForgeV2 Source

def maxRequirementKinds : Nat := 11

def validateRequirementEnvelope (program : SemanticProgram) : CompileResult Unit := do
  if program.requirements.size > maxRequirementKinds then
    throw <| .invalidProgram
      s!"semantic requirement count exceeds canonical limit {maxRequirementKinds}"
  let mut seen : Array ProgramRequirement := #[]
  for requirement in program.requirements do
    if seen.contains requirement then
      throw <| .invalidProgram s!"duplicate semantic requirement '{requirement}'"
    seen := seen.push requirement

def resolve (descriptor : TargetDescriptor) (program : SemanticProgram) : CompileResult (ResolvedProgram descriptor.targetId) := do
  validateRequirementEnvelope program
  for requirement in program.requirements do
    unless descriptor.supportedRequirements.contains requirement do
      throw <| .unsupportedRequirement requirement descriptor.targetId
  return { source := program, descriptor, targetMatches := rfl }

def makeOutput (descriptor : TargetDescriptor) (program : SemanticProgram)
    (deployable : Bool) (files : Array OutputFile) : OutputSet :=
  {
    manifest := {
      target := descriptor.targetId
      codegenProfile := descriptor.codegenProfile
      sourceHash := program.sourceHash
      semanticHash := program.semanticHash
      deployable
      files := files.map (·.path)
    }
    files
  }

def escapeJson (input : String) : String :=
  input.replace "\\" "\\\\" |>.replace "\"" "\\\"" |>.replace "\n" "\\n"

def manifestJson (manifest : OutputManifest) : String :=
  let files := String.intercalate "," <| manifest.files.toList.map fun path => s!"\"{escapeJson path}\""
  let deployable := if manifest.deployable then "true" else "false"
  "{\n" ++
    s!"  \"schemaVersion\": \"{manifest.schemaVersion}\",\n" ++
    s!"  \"target\": \"{manifest.target}\",\n" ++
    s!"  \"codegenProfile\": \"{escapeJson manifest.codegenProfile}\",\n" ++
    s!"  \"sourceHash\": \"{manifest.sourceHash}\",\n" ++
    s!"  \"semanticHash\": \"{manifest.semanticHash}\",\n" ++
    s!"  \"deployable\": {deployable},\n" ++
    s!"  \"files\": [{files}]\n" ++
    "}\n"

end ProofForgeV2.Targets
