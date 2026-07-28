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

/-- Revalidate the public `ResolvedProgram` seam before target planning.

    **Residual characterization / backend defense.** Shipped aggregate
    materialize/emit require private `ResolvedEngineeringBuildV1` from
    `resolveEngineeringRequirementsV1` (product support authority). These alpha
    `supportedRequirements.contains` checks cannot grant aggregate/staging access
    and must not become a parallel product resolver — but this public residual
    seam still exists (not type-level impossibility of all alpha routes); next
    deletion gate is S6 direct Plan cutover. A direct `ResolvedProgram`
    constructor call must still not bypass descriptor equality or residual
    backend support. Formal SupportClaim still pending. -/
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

/-- Target-local residual resolve. **Engineering characterization seam** (public
    residual route still exists; not product aggregate/staging authority).
    Alpha `supportedRequirements.contains` is not product support authority —
    shipped aggregate materialize/emit require `ResolvedEngineeringBuildV1`.
    Next deletion gate: S6 direct Plan cutover. Formal still pending. -/
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
