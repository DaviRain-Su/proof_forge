/-
  ProofForgeV2.Targets.BuildIdentityV1 — layout / wire foundation only (repair B)

  Five-field BuildIdentity structure + PF-JCS render. **No** mint from
  engineering digests, registry seed, or product selection.

  Until formal TargetSemanticsV1 + CodegenProfileV1 payloads exist, there is
  **no** reachable product BuildIdentity value and no binding into
  ResolvedEngineeringBuildV1 / MaterializedArtifactsV1 / on-disk manifest.

  No mint from engineering digests, registry seed, or product selection.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2.Targets.BuildIdentityV1

open ProofForgeV2
open ProofForgeV2.Core.Common

/-- Five-field BuildIdentity (SPEC-REG-001 flatten). Private constructor —
    **no** public mint in this engineering slice. -/
structure BuildIdentityV1 where
  private mk ::
  targetId : TargetId
  targetSemanticsVersion : SemVer
  targetSemanticsDigest : Digest
  codegenProfileId : CodegenProfileId
  codegenProfileDigest : Digest
  deriving Repr

namespace BuildIdentityV1

def targetIdOf (b : BuildIdentityV1) : TargetId := b.targetId
def targetSemanticsVersionOf (b : BuildIdentityV1) : SemVer := b.targetSemanticsVersion
def targetSemanticsDigestOf (b : BuildIdentityV1) : Digest := b.targetSemanticsDigest
def codegenProfileIdOf (b : BuildIdentityV1) : CodegenProfileId := b.codegenProfileId
def codegenProfileDigestOf (b : BuildIdentityV1) : Digest := b.codegenProfileDigest

/-- Exact field equality (digests by algorithm + raw bytes). -/
def beq (a b : BuildIdentityV1) : Bool :=
  a.targetId == b.targetId &&
  a.targetSemanticsVersion == b.targetSemanticsVersion &&
  a.targetSemanticsDigest.algorithm == b.targetSemanticsDigest.algorithm &&
  a.targetSemanticsDigest.bytes == b.targetSemanticsDigest.bytes &&
  a.codegenProfileId == b.codegenProfileId &&
  a.codegenProfileDigest.algorithm == b.codegenProfileDigest.algorithm &&
  a.codegenProfileDigest.bytes == b.codegenProfileDigest.bytes

instance : BEq BuildIdentityV1 := ⟨beq⟩

/-- Closed wire field names (ASCII order after PF-JCS key sort). The renderer
    consumes this table directly so layout inspection cannot drift from output. -/
def wireFieldNamesV1 : Array String :=
  #["codegenProfileDigest", "codegenProfileId", "targetId",
    "targetSemanticsDigest", "targetSemanticsVersion"]

/-- Closed field count derived from the renderer's key table. -/
def wireFieldCountV1 : Nat := wireFieldNamesV1.size

/-- PF-JCS wire for the five flatten fields (foundation only; no product mint). -/
def renderJcsV1 (b : BuildIdentityV1) : Except String String := do
  let ver ← renderSemVer b.targetSemanticsVersion
  let semDig ← renderDigest b.targetSemanticsDigest
  let profDig ← renderDigest b.codegenProfileDigest
  renderPfJcs (.object #[
    (wireFieldNamesV1[0]!, .string profDig),
    (wireFieldNamesV1[1]!, .string b.codegenProfileId.toString),
    (wireFieldNamesV1[2]!, .string b.targetId.toString),
    (wireFieldNamesV1[3]!, .string semDig),
    (wireFieldNamesV1[4]!, .string ver)
  ])

end BuildIdentityV1

end ProofForgeV2.Targets.BuildIdentityV1
