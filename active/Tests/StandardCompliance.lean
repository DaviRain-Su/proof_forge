/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Standard compliance manifest and evidence honesty tests.
-/
import ProofForge.Contract.Compliance

namespace ProofForge.Tests.StandardCompliance

open ProofForge.Contract.Compliance

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def requireOk {α : Type} (result : Except ComplianceError α) (message : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error err => throw <| IO.userError s!"{message}: {err.message}"

def requireError {α : Type} (result : Except ComplianceError α)
    (needle : String) : IO Unit :=
  match result with
  | .ok _ => throw <| IO.userError s!"expected compliance error containing `{needle}`"
  | .error err =>
      require (err.message.contains needle)
        s!"compliance error `{err.message}` does not contain `{needle}`"

def adapter : AdapterRef := {
  id := "test-adapter"
  version := "1.0.0"
}

def artifactDigest : String := "sha256:test-artifact"

def evidenceFor (status : RequirementStatus) (requirement : Requirement) :
    RequirementEvidence := {
  requirementId := requirement.id
  adapter := adapter
  artifactDigest := artifactDigest
  oracleId := "proof-forge-test-oracle"
  oracleVersion := "1"
  command := s!"lake env lean --run Tests/StandardCompliance.lean -- {requirement.id}"
  toolchains := #[{
    id := "lean"
    version := Lean.versionString
  }]
  status := status
  runResultDigest := s!"sha256:result-{requirement.id}"
}

def passedEvidence (manifest : StandardManifest) : Array RequirementEvidence :=
  manifest.requirements.map (evidenceFor .passed)

def hasKind (manifest : StandardManifest) (kind : RequirementKind) : Bool :=
  manifest.requirements.any (fun requirement => requirement.kind == kind)

def main : IO UInt32 := do
  let _ ← requireOk (validateCatalog knownManifests) "invalid compliance catalog"
  for manifest in knownManifests do
    let _ ← requireOk (validateManifest manifest)
      s!"invalid manifest {manifest.standard.id}"
    require (hasKind manifest .interface)
      s!"{manifest.standard.id} manifest lacks interface requirements"
    require (hasKind manifest .behavior)
      s!"{manifest.standard.id} manifest lacks behavior requirements"
    require (hasKind manifest .security)
      s!"{manifest.standard.id} manifest lacks security requirements"

  require (erc20Manifest.standard.id != erc20ProductProfileManifest.standard.id)
    "ERC-20 MUST manifest must stay separate from optional product metadata/policy"
  require (erc173Manifest.standard.id != roleAccessProfileManifest.standard.id)
    "ERC-173 ownership must stay separate from the role-access product profile"
  for expectedId in #[
    "erc-20", "proof-forge-erc20-product", "erc-165", "erc-173", "erc-721",
    "erc-1155", "erc-2612", "erc-4626", "nep-141", "nep-145", "spl-token",
    "spl-token-2022"
  ] do
    require (knownManifests.any (fun manifest => manifest.standard.id == expectedId))
      s!"missing standard manifest `{expectedId}`"

  let exact ← requireOk
    (verify erc20Manifest adapter artifactDigest .full (passedEvidence erc20Manifest))
    "full ERC-20 evidence"
  require (exact.level == .exact) "full passing evidence must derive exact"
  require (exact.satisfiedRequirementIds == exact.applicableRequirementIds)
    "exact report must satisfy every applicable requirement"

  let scopedIds := (erc721Manifest.requirements.take 2).map (·.id)
  let scopedEvidence := (erc721Manifest.requirements.take 2).map (evidenceFor .passed)
  let scopedReport ← requireOk
    (verify erc721Manifest adapter artifactDigest (.subset scopedIds) scopedEvidence)
    "scoped ERC-721 evidence"
  require (scopedReport.level == .scoped) "explicit passing subset must derive scoped"
  require (scopedReport.applicableRequirementIds == scopedIds)
    "scoped report must expose the exact selected requirement subset"

  let missing ← requireOk
    (verify erc1155Manifest adapter artifactDigest .full #[])
    "missing ERC-1155 evidence"
  require (missing.level == .experimental)
    "missing evidence must never derive exact"

  let skipped ← requireOk
    (verify erc2612Manifest adapter artifactDigest .full
      (erc2612Manifest.requirements.map (evidenceFor .skipped)))
    "skipped ERC-2612 evidence"
  require (skipped.level == .experimental)
    "skipped evidence must never satisfy a requirement"
  require skipped.satisfiedRequirementIds.isEmpty
    "skipped evidence must not appear in the satisfied subset"

  let some firstErc20Requirement := erc20Manifest.requirements[0]?
    | throw <| IO.userError "ERC-20 manifest unexpectedly has no requirements"
  let mismatched := {
    evidenceFor .passed firstErc20Requirement with
    artifactDigest := "sha256:other-artifact"
  }
  requireError
    (verify erc20Manifest adapter artifactDigest .full #[mismatched])
    "artifact digest"

  let wrongAdapter := {
    evidenceFor .passed firstErc20Requirement with
    adapter := { id := "other-adapter", version := "1.0.0" }
  }
  requireError
    (verify erc20Manifest adapter artifactDigest .full #[wrongAdapter])
    "does not match adapter"

  let missingCommand := {
    evidenceFor .passed firstErc20Requirement with
    command := ""
  }
  requireError
    (verify erc20Manifest adapter artifactDigest .full #[missingCommand])
    "missing its command"

  requireError
    (verify erc20Manifest adapter artifactDigest
      (.subset #["erc20.requirement.does-not-exist"]) #[])
    "unknown requirement"

  let current ← requireOk currentAtRiskReports "current at-risk reports"
  for report in current do
    require (report.level != .exact)
      s!"current unbound claim `{report.manifest.id}` must not report exact"
  for requiredId in #["erc-721", "erc-1155", "erc-2612", "nep-141", "spl-token"] do
    require (current.any (fun report => report.manifest.id == requiredId))
      s!"missing current at-risk report for {requiredId}"

  let docs ← IO.FS.readFile "docs/sdk-ecosystem-gaps-2026-07.md"
  for report in current do
    let expectedRow := s!"| `{report.manifest.id}` | `{report.level.id}` |"
    require (docs.contains expectedRow)
      s!"SDK gap documentation is missing machine-derived row: {expectedRow}"

  IO.println (renderSummary current)
  return 0

end ProofForge.Tests.StandardCompliance

def main : IO UInt32 :=
  ProofForge.Tests.StandardCompliance.main
