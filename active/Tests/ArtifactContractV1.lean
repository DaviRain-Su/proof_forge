/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Artifact Contract v1 gate (LR-0 / Seam B)

Freezes consumer field names and inventories primary-triad emitters so required
metadata keys cannot disappear silently. Nested honesty remains in
`Tests/ArtifactBundle.lean`.
-/
import ProofForge.Target.ArtifactBundle
import ProofForge.Target.ArtifactContract

namespace ProofForge.Tests.ArtifactContractV1

open ProofForge.Target.ArtifactContract
open ProofForge.Target.ArtifactBundle

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def requireOk (result : Except String Unit) (msg : String) : IO Unit :=
  match result with
  | .ok () => pure ()
  | .error err => throw (IO.userError s!"{msg}: {err}")

def requireErr (result : Except String Unit) (needle : String) : IO Unit :=
  match result with
  | .ok () => throw (IO.userError s!"expected contract failure containing `{needle}`")
  | .error err =>
      require (err.contains needle)
        s!"error `{err}` missing `{needle}`"

def fileContainsAll (path : System.FilePath) (needles : Array String) : IO Unit := do
  let text ← IO.FS.readFile path
  for needle in needles do
    require (text.contains needle)
      s!"{path} missing required emission marker `{needle}`"

def main : IO UInt32 := do
  require (documentSchemaId == "proof-forge-artifact")
    s!"documentSchemaId drift: {documentSchemaId}"
  require (schemaVersion == 1) s!"schemaVersion drift: {schemaVersion}"
  require (bundleSchemaVersion == "1")
    s!"bundleSchemaVersion drift: {bundleSchemaVersion}"
  require (bundleKind == "proof-forge-artifact-bundle")
    s!"bundleKind drift: {bundleKind}"

  -- Required consumer fields are stable names (design table).
  require (requiredTopLevelFields == #["schemaVersion", "target", "artifactKind", "sourceModule"])
    "requiredTopLevelFields drift"
  require (requiredTopLevelForExecution == #["artifacts", "artifactBundle"])
    "requiredTopLevelForExecution drift"
  require (consumerAllowlist.contains "schemaVersion"
      && consumerAllowlist.contains "artifactBundle"
      && consumerAllowlist.contains "artifacts")
    "consumerAllowlist missing core fields"

  -- Fail-closed pure validation.
  requireOk
    (validatePresentFields
      #["schemaVersion", "target", "artifactKind", "sourceModule"] false)
    "metadata-only minimum"
  requireErr
    (validatePresentFields #["schemaVersion", "target"] false)
    "missing required"
  requireErr
    (validatePresentFields
      #["schemaVersion", "target", "artifactKind", "sourceModule"] true)
    "missing execution"
  requireOk
    (validatePresentFields
      #["schemaVersion", "target", "artifactKind", "sourceModule",
        "artifacts", "artifactBundle"] true)
    "execution minimum"

  -- Nested bundle JSON still exposes the v1 identity used by consumers.
  let source : SourceIdentity := { moduleName := "Counter", kind := "portable-ir" }
  let bundle ← match withFinal "evm" source
      (some { kind := "yul", role := .intermediate })
      { kind := "evm-bytecode", role := .finalDeployable }
      #[] #[] with
    | .ok b => pure b
    | .error err => throw (IO.userError err.message)
  let json := ArtifactBundle.toJson bundle
  require (json.contains s!"\"schemaVersion\": \"{bundleSchemaVersion}\"")
    "bundle JSON schemaVersion"
  require (json.contains s!"\"kind\": \"{bundleKind}\"") "bundle JSON kind"
  require (json.contains "\"finalOutput\": \"evm-bytecode\"") "bundle finalOutput"
  require (json.contains "\"primaryOutput\"") "bundle primaryOutput"

  -- Primary-triad emitters must still emit the consumer-required keys.
  let emissionMarkers : Array String := #[
    "\"schemaVersion\"",
    "\"target\"",
    "\"artifactKind\"",
    "\"sourceModule\"",
    "\"artifacts\"",
    "\"artifactBundle\""
  ]
  for emitter in primaryTriadEmitters do
    fileContainsAll emitter.modulePath emissionMarkers

  -- Secondary inventory stays non-empty so LR-0 does not forget spike paths.
  require (secondaryEmitters.size ≥ 3)
    "secondary emitter inventory unexpectedly empty"

  IO.println
    s!"artifact-contract-v1: ok (schema={schemaVersion} primaryEmitters={primaryTriadEmitters.size})"
  pure 0

end ProofForge.Tests.ArtifactContractV1

def main : IO UInt32 :=
  ProofForge.Tests.ArtifactContractV1.main
