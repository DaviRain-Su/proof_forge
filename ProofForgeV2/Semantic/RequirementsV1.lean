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

  A non-catalog contribution fails closed; no partial table is returned. Formal
  TASK-D2-05 / RequirementRef / predicate merge / contribution origins remain
  pending.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.RequirementsInferV1

namespace ProofForgeV2.Semantic.RequirementsV1

open ProofForgeV2.Core.Common
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

/-- Closed S2 catalog IDs in SPEC wire order (UTF-8 ascending). -/
def s2CatalogIdsWireOrderV1 : Array String :=
  #["effect.asynchronous-workflow", "effect.event", "effect.synchronous-call",
    "failure.atomic-rollback", "state.persistent", "value.bool",
    "value.checked-arithmetic"]

def isS2CatalogIdV1 (id : String) : Bool :=
  s2CatalogIdsWireOrderV1.contains id

/-- Engineering content-address digest for a closed catalog requirement id. -/
def engineeringRequirementDigestV1 (id : String) : Except String Digest :=
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

/-- Freeze exact ProgramRequirementsV1 from the sole ProgramV1 contribution
    analysis. Unknown contribution identities fail closed before any request is
    minted; contribution duplicates have already been removed first-seen by the
    analysis, while final requests are sorted by canonical wire key. -/
def freezeProgramRequirementsV1 (program : ProgramV1) :
    Except String ProgramRequirementsV1 := do
  let contributions := inferRequirementContributionsV1 program
  let mut items : Array RequirementRequestV1 := #[]
  for contribution in contributions do
    let id := RequirementContributionV1.idOf contribution
    unless isS2CatalogIdV1 id do
      throw s!"S2 semantic requirements freeze rejects non-catalog key '{id}'"
    items := items.push (← mkS2RequirementRequestV1 id)
  pure { items := ← sortRequirementRequestsV1 items }

/-- Freeze from a validated source unit. -/
def freezeProgramRequirementsFromSourceV1 (source : ValidatedSourceV1) :
    Except String ProgramRequirementsV1 :=
  freezeProgramRequirementsV1 source.program

end ProofForgeV2.Semantic.RequirementsV1
