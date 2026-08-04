/-
  ProofForgeV2.Semantic.RequirementsV1 — sole engineering ProgramRequirementsV1
  freeze for the Semantic normalizer path.

  ProgramV1 traversal is owned only by
  `Typed.RequirementsInferV1.inferRequirementContributionsV1`, which emits
  target-neutral stable contribution identities. This module is its sole
  product consumer and exclusively owns catalog recognition, SemVer/digest
  binding, predicate shape, deduplication, canonical key sorting, and
  `ProgramRequirementsV1` construction.

  S2 closed catalog:
    * effect.asynchronous-workflow
    * effect.event
    * effect.synchronous-call
    * state.persistent
    * value.checked-arithmetic
    * value.bool
    * failure.atomic-rollback
  Predicates: empty for all seven.
  Version: SemVer core 1.0.0 (engineering; formal CAP registry pending).
  Digest: domainSeparatedSha256("pf.requirement-key.engineering.v1", UTF-8(id)).

  Wire order is SPEC key order (id UTF-8 ascending, then SemVer, then digest),
  not contribution first-seen order:
    1. effect.asynchronous-workflow
    2. effect.event
    3. effect.synchronous-call
    4. failure.atomic-rollback
    5. state.persistent
    6. value.bool
    7. value.checked-arithmetic

  Infer-only disclosure contribution ids (`disclosure.private-state`,
  `disclosure.commitment-state`, `disclosure.private-witness`,
  `disclosure.commitment`) are **skipped** (not rejected, not frozen) so that
  private/commitment state and params can open the product chain without a CAP
  catalog expansion. Product disclosure remains sole authority of
  CheckV1/DisclosureCheck (PF-VIS-001) before Normalize. Other non-catalog
  Field type contribution (`value.field.bn254-fr`) is freeze-skipped (N2b;
  covered by `value.checked-arithmetic`). Other non-catalog keys still fail
  closed. Formal
  TASK-D2-05 / RequirementRef / predicate merge / contribution origins remain
  pending.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.RequirementsInferV1

namespace ProofForgeV2.Semantic.RequirementsV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.RequirementsInferV1

/-- Domain tag for engineering requirement-key digests (S2 closed table only). -/
def engineeringRequirementKeyDomainV1 : String :=
  "pf.requirement-key.engineering.v1"

/-- Sole engineering SemVer core for the closed S2 requirement table. -/
def s2RequirementVersionV1 : SemVer :=
  { major := 1, minor := 0, patch := 0 }

/-- Closed S2 catalog IDs in SPEC wire order (UTF-8 ascending).
    Sole spelling/order source: `s2CatalogIdsWireOrderListV1`
    (this Array is that list's `.toArray` projection). -/
def s2CatalogIdsWireOrderV1 : Array String :=
  ProofForgeV2.Core.RequirementIdsV1.s2CatalogIdsWireOrderV1

/-- Closed-catalog membership via sole list authority exact `List.contains`
    (kernel-reducible; no second enumerated if-chain). -/
def isS2CatalogIdV1 (id : String) : Bool :=
  s2CatalogIdsWireOrderListV1.contains id

/-! ### Kernel-transparent S2 catalog digests

    `domainSeparatedSha256` is pure Lean SHA-256 via `Id.run`/`forIn` and does
    not reduce in the kernel. Closed S2 catalog digests are therefore pinned as
    transparent spines equal to
    `domainSeparatedSha256("pf.requirement-key.engineering.v1", UTF-8(id))`
    so encode/structure certificates can refine by definitional equality without
    whole-tree SHA reduction. Runtime identity is preserved byte-for-byte. -/

/-- Exact engineering digest bytes for `effect.asynchronous-workflow`. -/
def s2EffectAsyncWorkflowDigestBytesV1 : ByteArray :=
  ByteArray.mk (List.toArray [
    253, 112, 194, 166, 25, 80, 63, 79, 195, 43, 44, 203, 95, 222, 24, 104,
    200, 202, 145, 32, 121, 67, 113, 158, 205, 251, 243, 100, 114, 61, 100, 133
  ])

/-- Exact engineering digest bytes for `effect.event`. -/
def s2EffectEventDigestBytesV1 : ByteArray :=
  ByteArray.mk (List.toArray [
    74, 184, 221, 219, 124, 134, 3, 223, 226, 120, 126, 108, 126, 53, 221, 204,
    64, 225, 81, 219, 53, 54, 235, 193, 137, 171, 147, 108, 190, 111, 146, 136
  ])

/-- Exact engineering digest bytes for `effect.synchronous-call`. -/
def s2EffectSyncCallDigestBytesV1 : ByteArray :=
  ByteArray.mk (List.toArray [
    205, 152, 134, 50, 128, 130, 148, 206, 97, 200, 156, 186, 47, 47, 190, 5,
    66, 36, 251, 190, 144, 39, 18, 1, 61, 62, 132, 220, 11, 232, 139, 83
  ])

/-- Exact engineering digest bytes for `failure.atomic-rollback`. -/
def s2FailureAtomicRollbackDigestBytesV1 : ByteArray :=
  ByteArray.mk (List.toArray [
    254, 98, 216, 232, 64, 20, 227, 236, 31, 23, 247, 108, 127, 85, 250, 195,
    25, 2, 68, 236, 163, 173, 18, 77, 208, 78, 23, 195, 201, 209, 17, 101
  ])

/-- Exact engineering digest bytes for `state.persistent`. -/
def s2StatePersistentDigestBytesV1 : ByteArray :=
  ByteArray.mk (List.toArray [
    2, 63, 255, 245, 41, 95, 167, 238, 77, 158, 78, 73, 144, 154, 62, 183,
    241, 252, 12, 86, 31, 142, 126, 160, 111, 18, 66, 52, 12, 20, 110, 229
  ])

/-- Exact engineering digest bytes for `value.bool`. -/
def s2ValueBoolDigestBytesV1 : ByteArray :=
  ByteArray.mk (List.toArray [
    237, 52, 225, 6, 29, 14, 102, 99, 155, 106, 118, 55, 29, 216, 166, 193,
    204, 215, 46, 122, 154, 20, 116, 84, 218, 122, 83, 193, 167, 71, 84, 124
  ])

/-- Exact engineering digest bytes for `value.checked-arithmetic`. -/
def s2ValueCheckedArithmeticDigestBytesV1 : ByteArray :=
  ByteArray.mk (List.toArray [
    226, 24, 107, 1, 207, 88, 19, 81, 17, 247, 78, 197, 106, 83, 227, 51,
    135, 188, 48, 22, 72, 104, 7, 27, 31, 82, 74, 242, 34, 184, 191, 205
  ])

/-- Engineering content-address digest for a closed catalog requirement id.
    Closed S2 ids use transparent precomputed spines (exact
    `domainSeparatedSha256` results); unknown ids still compute via the pure
    SHA path. -/
def engineeringRequirementDigestV1 (id : String) : Except String Digest :=
  if id == s2EffectAsyncWorkflowIdV1 then
    pure { algorithm := .sha256, bytes := s2EffectAsyncWorkflowDigestBytesV1 }
  else if id == s2EffectEventIdV1 then
    pure { algorithm := .sha256, bytes := s2EffectEventDigestBytesV1 }
  else if id == s2EffectSyncCallIdV1 then
    pure { algorithm := .sha256, bytes := s2EffectSyncCallDigestBytesV1 }
  else if id == s2FailureAtomicRollbackIdV1 then
    pure { algorithm := .sha256, bytes := s2FailureAtomicRollbackDigestBytesV1 }
  else if id == s2StatePersistentIdV1 then
    pure { algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 }
  else if id == s2ValueBoolIdV1 then
    pure { algorithm := .sha256, bytes := s2ValueBoolDigestBytesV1 }
  else if id == s2ValueCheckedArithmeticIdV1 then
    pure { algorithm := .sha256, bytes := s2ValueCheckedArithmeticDigestBytesV1 }
  else
    domainSeparatedSha256 engineeringRequirementKeyDomainV1 id.toUTF8

/-- Build one RequirementRequestV1 for a catalog id (empty predicates). -/
def mkS2RequirementRequestV1 (id : String) : Except String RequirementRequestV1 := do
  unless isS2CatalogIdV1 id do
    throw s!"S2 requirements catalog rejects non-catalog id '{id}'"
  let digest ← engineeringRequirementDigestV1 id
  pure {
    id
    version := s2RequirementVersionV1
    digest
    predicates := #[]
  }

private def compareDigestBytes (left right : ByteArray) : Ordering :=
  let n := Nat.min left.size right.size
  let rec loop (i : Nat) : Ordering :=
    if i < n then
      let bl := left.get! i
      let br := right.get! i
      if bl.toNat < br.toNat then .lt
      else if bl.toNat > br.toNat then .gt
      else loop (i + 1)
    else if left.size < right.size then .lt
    else if left.size > right.size then .gt
    else .eq
  loop 0

private def compareRequirementKeyString
    (left right : RequirementRequestV1) : Except String Ordering := do
  if left.id < right.id then return .lt
  if left.id > right.id then return .gt
  let verL ← renderSemVer left.version
  let verR ← renderSemVer right.version
  if verL < verR then return .lt
  if verL > verR then return .gt
  validateDigest left.digest
  validateDigest right.digest
  pure (compareDigestBytes left.digest.bytes right.digest.bytes)

/-- Sort requirement requests by SPEC key order (id, SemVer render, digest). -/
private def sortRequirementRequestsV1 (items : Array RequirementRequestV1) :
    Except String (Array RequirementRequestV1) := do
  let mut out : Array RequirementRequestV1 := #[]
  for item in items do
    let mut inserted := false
    let mut next : Array RequirementRequestV1 := #[]
    for existing in out do
      if inserted then
        next := next.push existing
      else
        let cmp ← compareRequirementKeyString existing item
        match cmp with
        | .lt => next := next.push existing
        | .eq | .gt =>
            next := next.push item
            next := next.push existing
            inserted := true
    if !inserted then
      next := next.push item
    out := next
  pure out

/-- Infer-only disclosure ids that CheckV1/DisclosureCheck already enforces.
    Skipped at freeze (N1) so private/commitment state/params do not invent
    non-catalog S2 rows or block the product chain. CAP catalog promotion of
    these ids remains a later formal decision. -/
private def isSkippedInferDisclosureIdV1 (id : String) : Bool :=
  id == inferDisclosurePrivateWitnessIdV1 ||
  id == inferDisclosureCommitmentIdV1 ||
  id == inferDisclosurePrivateStateIdV1 ||
  id == inferDisclosureCommitmentStateIdV1

/-- ContextRead / Commit / exact extension contribution ids use wire-owned
    identities. Normalize merges their exact rows after S2 freeze; freeze must
    skip them so they never invent S2 catalog rows or digest domains. -/
private def isSkippedWireOwnedIdV1 (id : String) : Bool :=
  id == wireContextUnixTimeSecondsIdV1 ||
  id == wireContextCallerIdV1 ||
  id == wireCommitmentDisclosureIdV1 ||
  id == wireExtensionSolanaCpiAccountsIdV1

/-- Infer-only Field type contribution. Field arithmetic is exact modular
    (no overflow); product arithmetic is covered by the existing S2 key
    `value.checked-arithmetic`. No new S2 catalog entry is minted for any
    `value.field.*` id — skip at freeze (N2b; T14 catalog v2 extends the
    closed field set to bn254 Fr, BLS12-377 Fr, and Goldilocks). -/
private def isSkippedInferFieldIdV1 (id : String) : Bool :=
  id == inferValueFieldBn254FrIdV1 ||
  id == inferValueFieldBls12377FrIdV1 ||
  id == inferValueFieldGoldilocksIdV1

/-- Freeze exact ProgramRequirementsV1 from the sole ProgramV1 contribution
    analysis. Infer-only disclosure and Field type contribution ids are
    skipped (see module doc). Other unknown contribution identities fail
    closed before any request is minted; contribution duplicates have already
    been removed first-seen by the analysis, while final requests are sorted
    by canonical wire key. -/
def freezeProgramRequirementsV1 (program : ProgramV1) :
    Except String ProgramRequirementsV1 := do
  let contributions := inferRequirementContributionsV1 program
  let mut items : Array RequirementRequestV1 := #[]
  for contribution in contributions do
    let id := RequirementContributionV1.idOf contribution
    if isSkippedInferDisclosureIdV1 id || isSkippedInferFieldIdV1 id ||
        isSkippedWireOwnedIdV1 id then
      pure ()
    else do
      unless isS2CatalogIdV1 id do
        throw s!"S2 semantic requirements freeze rejects non-catalog key '{id}'"
      items := items.push (← mkS2RequirementRequestV1 id)
  pure { items := ← sortRequirementRequestsV1 items }

/-- Freeze from a validated source unit. -/
def freezeProgramRequirementsFromSourceV1 (source : ValidatedSourceV1) :
    Except String ProgramRequirementsV1 :=
  freezeProgramRequirementsV1 source.program

end ProofForgeV2.Semantic.RequirementsV1
