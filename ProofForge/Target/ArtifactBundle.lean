import Init.Data.Array.Basic
import Init.Data.String.Basic

namespace ProofForge.Target.ArtifactBundle

/-- Validation state for a named check on an artifact bundle (PF-P1-03).

`notRun` must never be serialized as `passed`. Tool absence is `unavailable`,
not a green pass. -/
inductive ValidationState where
  | notRun
  | passed
  | failed
  | unavailable
  deriving BEq, DecidableEq, Repr, Inhabited

def ValidationState.id : ValidationState → String
  | .notRun => "notRun"
  | .passed => "passed"
  | .failed => "failed"
  | .unavailable => "unavailable"

/-- Role of one typed output inside a bundle. -/
inductive OutputRole where
  | intermediate
  | primary
  | finalDeployable
  | sidecar
  deriving BEq, DecidableEq, Repr, Inhabited

def OutputRole.id : OutputRole → String
  | .intermediate => "intermediate"
  | .primary => "primary"
  | .finalDeployable => "final-deployable"
  | .sidecar => "sidecar"

/-- One concrete typed artifact (Yul, sBPF asm, WAT, bytecode, ELF, Wasm, …). -/
structure TypedOutput where
  /-- Stable artifact type id, e.g. `yul`, `sbpf-asm`, `wat`, `evm-bytecode`, `solana-elf`. -/
  kind : String
  role : OutputRole
  path? : Option String := none
  sha256? : Option String := none
  bytes? : Option Nat := none
  deriving Repr, Inhabited, BEq

/-- Source identity carried into metadata (no silent Counter substitution). -/
structure SourceIdentity where
  moduleName : String
  path? : Option String := none
  kind : String := "contract-source"
  deriving Repr, Inhabited, BEq

/-- Toolchain provenance for one tool invocation or requirement. -/
structure ToolProvenance where
  tool : String
  stage : String
  available : Bool
  version? : Option String := none
  deriving Repr, Inhabited, BEq

/-- Named validation entry. -/
structure ValidationEntry where
  name : String
  state : ValidationState
  detail? : Option String := none
  deriving Repr, Inhabited, BEq

/-- Multi-output artifact bundle (PF-P1-03).

Replaces the single `ArtifactKind` claim with explicit intermediate/final
outputs and honest validation states. -/
structure ArtifactBundle where
  targetId : String
  source : SourceIdentity
  outputs : Array TypedOutput := #[]
  primaryOutput? : Option String := none
  finalOutput? : Option String := none
  toolchain : Array ToolProvenance := #[]
  validations : Array ValidationEntry := #[]
  deriving Repr, Inhabited, BEq

/-- Schema / honesty errors for a bundle. -/
structure BundleError where
  message : String
  deriving Repr, Inhabited

def BundleError.render (err : BundleError) : String := err.message

def findOutput? (bundle : ArtifactBundle) (kind : String) : Option TypedOutput :=
  bundle.outputs.find? (fun o => o.kind == kind)

def hasOutputKind (bundle : ArtifactBundle) (kind : String) : Bool :=
  (findOutput? bundle kind).isSome

def validationState? (bundle : ArtifactBundle) (name : String) : Option ValidationState :=
  match bundle.validations.find? (fun v => v.name == name) with
  | some v => some v.state
  | none => none

/-- Fail closed if any validation claims `passed` while marked `notRun` (impossible
by construction) or if a missing final is advertised as finalOutput. -/
def validateHonesty (bundle : ArtifactBundle) : Except BundleError Unit := do
  if let some finalKind := bundle.finalOutput? then
    match findOutput? bundle finalKind with
    | none =>
        .error {
          message :=
            s!"artifact bundle for `{bundle.targetId}` advertises finalOutput `{finalKind}` \
but no typed output of that kind is present"
        }
    | some out =>
        if out.role != .finalDeployable && out.role != .primary then
          .error {
            message :=
              s!"artifact bundle finalOutput `{finalKind}` has role `{out.role.id}`; \
expected final-deployable or primary"
          }
  if let some primaryKind := bundle.primaryOutput? then
    if !(hasOutputKind bundle primaryKind) then
      .error {
        message :=
          s!"artifact bundle for `{bundle.targetId}` advertises primaryOutput `{primaryKind}` \
but no typed output of that kind is present"
      }
  for tool in bundle.toolchain do
    if !tool.available then
      -- Missing tools must not appear as validation `passed`.
      for v in bundle.validations do
        if v.name == tool.stage || v.name == tool.tool then
          if v.state == .passed then
            .error {
              message :=
                s!"validation `{v.name}` is passed but tool `{tool.tool}` is unavailable; \
use unavailable or failed"
            }
  for v in bundle.validations do
    if v.state == .notRun then
      pure ()
  .ok ()

/-- Intermediate-only build: primary is assembly/WAT/Yul; no final deployable. -/
def intermediateOnly
    (targetId : String) (source : SourceIdentity) (output : TypedOutput)
    (validations : Array ValidationEntry := #[]) : Except BundleError ArtifactBundle := do
  let bundle : ArtifactBundle := {
    targetId := targetId
    source := source
    outputs := #[output]
    primaryOutput? := some output.kind
    finalOutput? := none
    validations := validations
  }
  validateHonesty bundle
  pure bundle

/-- Final deployable present (bytecode / ELF / Wasm). -/
def withFinal
    (targetId : String) (source : SourceIdentity)
    (intermediate? : Option TypedOutput) (finalOut : TypedOutput)
    (toolchain : Array ToolProvenance := #[])
    (validations : Array ValidationEntry := #[]) : Except BundleError ArtifactBundle := do
  let mut outs : Array TypedOutput := #[]
  if let some inter := intermediate? then
    outs := outs.push inter
  outs := outs.push { finalOut with role := .finalDeployable }
  let bundle : ArtifactBundle := {
    targetId := targetId
    source := source
    outputs := outs
    primaryOutput? := some finalOut.kind
    finalOutput? := some finalOut.kind
    toolchain := toolchain
    validations := validations
  }
  validateHonesty bundle
  pure bundle

/-- Missing-tool case: final not produced; validation must be unavailable. -/
def missingTool
    (targetId : String) (source : SourceIdentity)
    (intermediate : TypedOutput) (tool : ToolProvenance)
    (stageValidation : String) : Except BundleError ArtifactBundle := do
  let bundle : ArtifactBundle := {
    targetId := targetId
    source := source
    outputs := #[intermediate]
    primaryOutput? := some intermediate.kind
    finalOutput? := none
    toolchain := #[tool]
    validations := #[{
      name := stageValidation
      state := if tool.available then .notRun else .unavailable
      detail? := some s!"tool `{tool.tool}` required for stage `{tool.stage}`"
    }]
  }
  validateHonesty bundle
  pure bundle

/-- Failed toolchain after a tool ran. -/
def failedToolchain
    (targetId : String) (source : SourceIdentity)
    (intermediate : TypedOutput) (tool : ToolProvenance)
    (stageValidation detail : String) : Except BundleError ArtifactBundle := do
  let bundle : ArtifactBundle := {
    targetId := targetId
    source := source
    outputs := #[intermediate]
    primaryOutput? := some intermediate.kind
    finalOutput? := none
    toolchain := #[tool]
    validations := #[{
      name := stageValidation
      state := .failed
      detail? := some detail
    }]
  }
  validateHonesty bundle
  pure bundle

/-! ## JSON (compact, schemaVersion 1) -/

def jsonEscape (s : String) : String :=
  s.replace "\\" "\\\\" |>.replace "\"" "\\\"" |>.replace "\n" "\\n"

def jsonString (s : String) : String := s!"\"{jsonEscape s}\""

def jsonStringOption : Option String → String
  | none => "null"
  | some s => jsonString s

def jsonNatOption : Option Nat → String
  | none => "null"
  | some n => toString n

def jsonBool (b : Bool) : String := if b then "true" else "false"

def typedOutputJson (o : TypedOutput) : String :=
  s!"\{\"kind\": {jsonString o.kind}, \"role\": {jsonString o.role.id}, \
\"path\": {jsonStringOption o.path?}, \"sha256\": {jsonStringOption o.sha256?}, \
\"bytes\": {jsonNatOption o.bytes?}}"

def toolJson (t : ToolProvenance) : String :=
  s!"\{\"tool\": {jsonString t.tool}, \"stage\": {jsonString t.stage}, \
\"available\": {jsonBool t.available}, \"version\": {jsonStringOption t.version?}}"

def validationJson (v : ValidationEntry) : String :=
  s!"\{\"name\": {jsonString v.name}, \"state\": {jsonString v.state.id}, \
\"detail\": {jsonStringOption v.detail?}}"

def sourceJson (s : SourceIdentity) : String :=
  s!"\{\"moduleName\": {jsonString s.moduleName}, \"path\": {jsonStringOption s.path?}, \
\"kind\": {jsonString s.kind}}"

def ArtifactBundle.toJson (bundle : ArtifactBundle) : String :=
  let outs := String.intercalate ", " (bundle.outputs.toList.map typedOutputJson)
  let tools := String.intercalate ", " (bundle.toolchain.toList.map toolJson)
  let vals := String.intercalate ", " (bundle.validations.toList.map validationJson)
  s!"\{\"schemaVersion\": \"1\", \"kind\": \"proof-forge-artifact-bundle\", \
\"targetId\": {jsonString bundle.targetId}, \"source\": {sourceJson bundle.source}, \
\"outputs\": [{outs}], \"primaryOutput\": {jsonStringOption bundle.primaryOutput?}, \
\"finalOutput\": {jsonStringOption bundle.finalOutput?}, \
\"toolchain\": [{tools}], \"validations\": [{vals}]}"

end ProofForge.Target.ArtifactBundle
