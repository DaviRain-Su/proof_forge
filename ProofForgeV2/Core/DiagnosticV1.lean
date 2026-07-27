/-
  ProofForgeV2.Core.DiagnosticV1 — typed diagnostic carrier for D1-07.

  This module introduces a closed code enumeration and a structured diagnostic
  record with `SourceOrigin` provenance.  It provides the exact human line
  format used by existing producers today (`PF-*: message`) and a canonical
  PF-JCS JSON representation.  A total order on diagnostics enables stable
  sorting and deduplication.

  Origins are normalized (sorted and deduplicated) before they participate in
  comparison or canonical serialization, so two diagnostics that differ only
  by origin order or duplicate origins compare equal and serialize identically.

  The carrier is now wired into `ProofForgeV2.Language.Loader` for error-time
  origins on parser-boundary and duplicate-program failures; all other producers
  remain on `CompileError` until their bounded migration slices.  Error-time
  origins use `errorSentinelNodeId` when a trustworthy source position exists but
  a canonical traversal `NodeId` has not been assigned.  The sentinel is the
  16-zero-byte value, which is valid per `validateNodeId` and cannot collide
  with real canonical NodeIds because those are derived from cryptographic
  hashes.  Origins are omitted (empty array) when no trustworthy position is
  available.
-/
import ProofForgeV2.Core.Common

open ProofForgeV2.Core.Common

namespace ProofForgeV2.Core.DiagnosticV1

/-- Documented zero-filled 16-byte sentinel used for error-time origins when a
    canonical traversal `NodeId` has not been assigned.  It is valid per
    `validateNodeId` and never collides with real NodeIds, which are derived from
    cryptographic hashes. -/
def errorSentinelNodeId : NodeId where
  bytes := ByteArray.mk (Array.replicate 16 (0 : UInt8))

/-- `Array.qsort`/`get!` on `SourceOrigin` arrays need an `Inhabited` instance. -/
instance : Inhabited SourceOrigin where
  default := {
    sourcePath := { value := "" },
    startByte := 0,
    endByte := 0,
    nodeId := { bytes := ByteArray.empty }
  }

/-- Closed vocabulary of product diagnostic codes for the current ProgramV1
    product slice.  No producer is rewired by this module. -/
inductive DiagnosticCodeV1 where
  | sourceInvalid
  | resourceBound
  | toolchainMissing
  | toolchainMismatch
  | targetNotImplemented
  | outputAtomicity
  | internal
  | effectDisallowed
  | visibilityViolation
  deriving BEq, DecidableEq, Repr, Inhabited

namespace DiagnosticCodeV1

/-- Explicit stable priority constants.  `rank` is independent of the declaration
    order of the constructors, so adding or reordering constructors cannot
    silently change diagnostic sorting. -/
private def sourceInvalidRank : Nat := 0
private def resourceBoundRank : Nat := 1
private def toolchainMissingRank : Nat := 2
private def toolchainMismatchRank : Nat := 3
private def targetNotImplementedRank : Nat := 4
private def outputAtomicityRank : Nat := 5
private def internalRank : Nat := 6
private def effectDisallowedRank : Nat := 7
private def visibilityViolationRank : Nat := 8

/-- Stable rank used for total ordering. -/
def rank : DiagnosticCodeV1 → Nat
  | .sourceInvalid => sourceInvalidRank
  | .resourceBound => resourceBoundRank
  | .toolchainMissing => toolchainMissingRank
  | .toolchainMismatch => toolchainMismatchRank
  | .targetNotImplemented => targetNotImplementedRank
  | .outputAtomicity => outputAtomicityRank
  | .internal => internalRank
  | .effectDisallowed => effectDisallowedRank
  | .visibilityViolation => visibilityViolationRank

/-- Exact wire code string for each diagnostic code.  These must be byte-identical
    to the strings produced by the existing `CompileError` renderer. -/
def wire : DiagnosticCodeV1 → String
  | .sourceInvalid => "PF-SRC-INVALID"
  | .resourceBound => "PF-BOUND-001"
  | .toolchainMissing => "PF-TOOLCHAIN-MISSING"
  | .toolchainMismatch => "PF-TOOLCHAIN-MISMATCH"
  | .targetNotImplemented => "PF-TARGET-NOT-IMPLEMENTED"
  | .outputAtomicity => "PF-OUTPUT-ATOMICITY"
  | .internal => "PF-INTERNAL"
  | .effectDisallowed => "PF-EFFECT-001"
  | .visibilityViolation => "PF-VIS-001"

end DiagnosticCodeV1

/-- Structured diagnostic record.  Origins are validated `SourceOrigin` values,
    so absolute host paths are rejected before they can enter the canonical
    JSON representation. -/
structure DiagnosticV1 where
  code : DiagnosticCodeV1
  message : String
  origins : Array SourceOrigin
  deriving BEq, Repr, Inhabited

namespace DiagnosticV1

/-- Human rendering matching today's `{PF-*}: {message}` lines. -/
def renderHuman (diag : DiagnosticV1) : String :=
  s!"{diag.code.wire}: {diag.message}"

private def compareByteArray (left right : ByteArray) : Ordering :=
  if left.size < right.size then .lt
  else if left.size > right.size then .gt
  else
    let rec loop (i : Nat) : Ordering :=
      if i < left.size then
        let byteL := left.get! i
        let byteR := right.get! i
        if byteL.toNat < byteR.toNat then .lt
        else if byteL.toNat > byteR.toNat then .gt
        else loop (i + 1)
      else
        .eq
    loop 0

/-- Total order on `SourceOrigin` derived from the same tuple used by
    `sourceOriginKey`, but defined here so that it is available even for
    directly-constructed (possibly invalid) values used in tests. -/
def compareSourceOrigin (left right : SourceOrigin) : Ordering :=
  if left.sourcePath.value < right.sourcePath.value then .lt
  else if left.sourcePath.value > right.sourcePath.value then .gt
  else if left.startByte.toNat < right.startByte.toNat then .lt
  else if left.startByte.toNat > right.startByte.toNat then .gt
  else if left.endByte.toNat < right.endByte.toNat then .lt
  else if left.endByte.toNat > right.endByte.toNat then .gt
  else compareByteArray left.nodeId.bytes right.nodeId.bytes

/-- Sort origins and remove adjacent duplicates.  This is the canonical form
    used by both comparison and serialization. -/
def normalizeOrigins (origins : Array SourceOrigin) : Array SourceOrigin :=
  let sorted := origins.qsort (fun a b => compareSourceOrigin a b == .lt)
  sorted.foldl (fun acc o =>
    if acc.size > 0 && acc[acc.size - 1]! == o then acc else acc.push o) #[]

/-- Canonical PF-JCS JSON object with fields `code`, `message`, `origins`,
    and `schemaVersion`.  Each origin is rendered through the existing
    `SourceOrigin` codec and then parsed back, so any invalid origin fails
    closed. -/
def toCanonicalJson (diag : DiagnosticV1) : Except String String := do
  let originJson ← (normalizeOrigins diag.origins).mapM fun origin => do
    let originText ← renderSourceOriginJcs origin
    parsePfJcs originText
  renderPfJcs (.object #[
    ("code", .string diag.code.wire),
    ("message", .string diag.message),
    ("origins", .array originJson),
    ("schemaVersion", .int 1)
  ])

private def compareOriginArray (left right : Array SourceOrigin) : Ordering :=
  let n := min left.size right.size
  let rec loop (i : Nat) : Ordering :=
    if i < n then
      match compareSourceOrigin left[i]! right[i]! with
      | .lt => .lt
      | .gt => .gt
      | .eq => loop (i + 1)
    else if left.size < right.size then .lt
    else if left.size > right.size then .gt
    else .eq
  loop 0

/-- Total order by (normalized origins, code rank, message). -/
def compare (left right : DiagnosticV1) : Ordering :=
  match compareOriginArray (normalizeOrigins left.origins) (normalizeOrigins right.origins) with
  | .lt => .lt
  | .gt => .gt
  | .eq =>
    if left.code.rank < right.code.rank then .lt
    else if left.code.rank > right.code.rank then .gt
    else if left.message < right.message then .lt
    else if left.message > right.message then .gt
    else .eq

/-- Stable sort followed by adjacent deduplication. -/
def sortAndDedupe (diagnostics : Array DiagnosticV1) : Array DiagnosticV1 :=
  let sorted := diagnostics.qsort (fun a b => compare a b == .lt)
  sorted.foldl (fun acc d =>
    if acc.size > 0 && acc[acc.size - 1]! == d then acc else acc.push d) #[]

end DiagnosticV1

end ProofForgeV2.Core.DiagnosticV1
