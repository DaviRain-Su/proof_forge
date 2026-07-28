import ProofForgeV2.Materialization.Protocol
import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2.Targets

open ProofForgeV2 Source

def maxRequirementKinds : Nat := 13

def validateRequirementEnvelope (program : SemanticProgram) : CompileResult Unit := do
  if program.requirements.size > maxRequirementKinds then
    throw <| .invalidProgram
      s!"semantic requirement count exceeds canonical limit {maxRequirementKinds}"
  let mut seen : Array ProgramRequirement := #[]
  for requirement in program.requirements do
    if seen.contains requirement then
      throw <| .invalidProgram s!"duplicate semantic requirement '{requirement}'"
    seen := seen.push requirement

/-- Revalidate the public `ResolvedProgram` seam before target planning. The
structure is intentionally inspectable, so a direct constructor call must not
bypass descriptor equality or requirement support established by `resolve`. -/
def validateResolved (kind : TargetKind) (expected : TargetDescriptor)
    (resolved : ResolvedProgram kind) : CompileResult Unit := do
  unless resolved.descriptor == expected do
    throw <| .planInvariant kind
      "resolved target descriptor does not match the target profile"
  unless expected.targetId == TargetId.ofKind kind do
    throw <| .planInvariant kind
      "resolved target descriptor identity does not match the target kind"
  validateRequirementEnvelope resolved.source
  for requirement in resolved.source.requirements do
    unless expected.supportedRequirements.contains requirement do
      throw <| .unsupportedRequirement requirement kind

def resolve (kind : TargetKind) (descriptor : TargetDescriptor) (program : SemanticProgram) :
    CompileResult (ResolvedProgram kind) := do
  unless descriptor.targetId == TargetId.ofKind kind do
    throw <| .planInvariant kind
      "descriptor target identity does not match the requested kind"
  validateRequirementEnvelope program
  for requirement in program.requirements do
    unless descriptor.supportedRequirements.contains requirement do
      throw <| .unsupportedRequirement requirement kind
  return { source := program, descriptor }

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
    s!"  \"codegenProfile\": \"{escapeJson manifest.codegenProfile.toString}\",\n" ++
    s!"  \"sourceHash\": \"{manifest.sourceHash}\",\n" ++
    s!"  \"semanticHash\": \"{manifest.semanticHash}\",\n" ++
    s!"  \"deployable\": {deployable},\n" ++
    s!"  \"files\": [{files}]\n" ++
    "}\n"

end ProofForgeV2.Targets
