/-
  Engineering exact disk-closure adapter (D3/S7c + D3-E7 commit 1/2).

  Sole production entry: `validateEngineeringDiskClosureV1` consumes only the
  private-ctor `FinalizedArtifactsV1` authority and a staging directory. Expected
  physical leaves are derived exclusively from ordered base artifact paths +
  finalized extra paths + fixed transitional sidecars `evidence.json` and
  `manifest.json` — no caller-supplied expected list.

  Physical walk, content hash, and exact membership authority live solely in
  `ArtifactContentV1.scanArtifactContentClosureV1`. This module only derives
  path claims from `FinalizedArtifactsV1` and discards the inventory for the
  historical Unit API (Commit 2 will consume inventory for inspect/manifest).

  Engineering static/stable observation only (before/read/after metadata).
  Not formal OutputSetV1 / proof-forge.output.v1 / BuildIdentity / hermetic
  publisher / race-free containment / supervisor.
-/
import ProofForgeV2.Materialization.ArtifactContentV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1

namespace ProofForgeV2

open System

/-! ## Cap / sidecar re-exports (sole defs live in ArtifactContentV1)

  Importing this module still surfaces the historical names used by tests and
  CLI. Values are the ArtifactContentV1 constants (no second definition).
-/

-- `maxEngineeringDiskClosureFilesV1`, `maxEngineeringDiskClosureFileBytesV1`,
-- `maxEngineeringDiskClosureTotalBytesV1`, `maxEngineeringDiskClosureDirEntrySlackV1`,
-- `evidenceSidecarNameV1`, `manifestSidecarNameV1` are defined in ArtifactContentV1
-- under the same `ProofForgeV2` namespace (transitive via import).

/-- Package-visible: derive ordered path claims from private finalized carrier.

    Base files → `materializedBase` (source order); extras → `finalizedExtra`
    (source order). Does not sort; scanner canonicalizes for inventory. -/
def deriveArtifactPathClaimsFromFinalizedV1
    (finalized : FinalizedArtifactsV1) : Array ArtifactPathClaimV1 :=
  let base :=
    (MaterializedArtifactsV1.filesOf (FinalizedArtifactsV1.artifactsOf finalized)).map
      fun f => ({ role := .materializedBase, path := f.path } : ArtifactPathClaimV1)
  let extras :=
    (FinalizedArtifactsV1.extraFilesOf finalized).map fun p =>
      ({ role := .finalizedExtra, path := p } : ArtifactPathClaimV1)
  base ++ extras

/-- Fixed transitional sidecars for full engineering publish closure. -/
def engineeringFixedSidecarLeavesV1 : Array String :=
  #[evidenceSidecarNameV1, manifestSidecarNameV1]

/-- Package-visible: artifact-only scan (aux empty). For Commit 2 inspect helpers.

    Does not forge a Finalized carrier — caller supplies claims or finalized. -/
def scanEngineeringArtifactContentOnlyV1
    (finalized : FinalizedArtifactsV1) (stagingDir : FilePath) :
    IO ArtifactContentInventoryV1 :=
  scanArtifactContentClosureV1 stagingDir
    (deriveArtifactPathClaimsFromFinalizedV1 finalized) #[]

/-- Package-visible: full scan with fixed evidence/manifest sidecars. -/
def scanEngineeringArtifactContentWithSidecarsV1
    (finalized : FinalizedArtifactsV1) (stagingDir : FilePath) :
    IO ArtifactContentInventoryV1 :=
  scanArtifactContentClosureV1 stagingDir
    (deriveArtifactPathClaimsFromFinalizedV1 finalized)
    engineeringFixedSidecarLeavesV1

/-- Sole production engineering exact disk-closure validator (D3/S7c).

    Inputs: private `FinalizedArtifactsV1` + staging `FilePath`.
    Expected leaves = ordered base paths + ordered extras + `evidence.json` +
    `manifest.json`. No caller expected-list parameter. Delegates to sole
    `scanArtifactContentClosureV1` and discards inventory (historical Unit API). -/
def validateEngineeringDiskClosureV1
    (finalized : FinalizedArtifactsV1) (stagingDir : FilePath) : IO Unit := do
  let _inv ← scanEngineeringArtifactContentWithSidecarsV1 finalized stagingDir
  pure ()

end ProofForgeV2
