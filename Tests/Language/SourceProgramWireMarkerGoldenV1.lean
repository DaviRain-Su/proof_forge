import Lean
import ProofForgeV2.Core.Crypto
import ProofForgeV2.Source.AstCanonicalRootDecodeV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.SourceProgramWireMarkerGoldenV1

open Lean
open ProofForgeV2
open ProofForgeV2.Source.AstCanonicalRootDecodeV1
open ProofForgeV2.Source.ValidatedSourceV1

private structure MutationRow where
  baseMarker : Nat
  caseId : String
  expectedError : String
  fieldName : String
  markerKind : String
  markerOffset : Nat
  mutatedMarker : Nat
  ownerTag : String
  deriving FromJson, Repr

private structure MutationManifest where
  baseCanonicalBytesSha256 : String
  baseCanonicalFile : String
  baseCaseId : String
  boolMutationCount : Nat
  boolOccurrenceCount : Nat
  mutationCount : Nat
  mutations : Array MutationRow
  optionFieldCount : Nat
  optionMutationCount : Nat
  optionOccurrenceCount : Nat
  schema : String
  scope : String
  deriving FromJson, Repr

private def basePath : System.FilePath :=
  "testdata/golden/source-program-v1/full-tag-v1/canonical.bin"

private def manifestPath : System.FilePath :=
  "testdata/golden/source-program-v1/marker-v1/manifest.json"

private def expectedKeys : Array String := #[
  "bool|Literal.Bool|value|0",
  "bool|Literal.Bool|value|1",
  "option|Stmt.Assert|error|0",
  "option|Stmt.Assert|error|1",
  "option|Stmt.If|elseBlock|0",
  "option|Stmt.If|elseBlock|1",
  "option|Stmt.Let|typeAnn|0",
  "option|Stmt.Let|typeAnn|1",
  "option|Stmt.Return|value|0",
  "option|Stmt.Return|value|1"
]

private def expectedCaseIds : Array String := #[
  "marker-bool-literal-bool-value-0-to-2",
  "marker-bool-literal-bool-value-1-to-2",
  "marker-option-stmt-assert-error-0-to-2",
  "marker-option-stmt-assert-error-1-to-2",
  "marker-option-stmt-if-elseblock-0-to-2",
  "marker-option-stmt-if-elseblock-1-to-2",
  "marker-option-stmt-let-typeann-0-to-2",
  "marker-option-stmt-let-typeann-1-to-2",
  "marker-option-stmt-return-value-0-to-2",
  "marker-option-stmt-return-value-1-to-2"
]

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error detail => throw <| IO.userError s!"{label}: unexpected error: {detail}"

private def readManifest : IO MutationManifest := do
  let payload ← IO.FS.readFile manifestPath
  match Json.parse payload >>= fromJson? with
  | .ok manifest => pure manifest
  | .error detail => throw <| IO.userError s!"invalid PA127 mutation manifest: {detail}"

private def markerKey (row : MutationRow) : String :=
  row.markerKind ++ "|" ++ row.ownerTag ++ "|" ++ row.fieldName ++ "|" ++
    toString row.baseMarker

private def expectDecodeError (row : MutationRow) (bytes : ByteArray) : IO Unit :=
  match decodeCanonicalSourceAstBytesV1 bytes with
  | .error detail =>
      expect (detail == row.expectedError)
        s!"{row.caseId}: expected '{row.expectedError}', got '{detail}'"
  | .ok _ => throw <| IO.userError s!"{row.caseId}: unexpectedly decoded"

/-- D1-PA-127: Bool/Option noncanonical marker negatives over the PA125 base. -/
def run : IO Unit := do
  let canonical ← IO.FS.readBinFile basePath
  let manifest ← readManifest
  let baseSha := Crypto.sha256Hex canonical
  expect (manifest.schema ==
      "proof-forge.source-program-marker-golden-prerequisite.v1")
    "marker descriptor schema"
  expect (manifest.scope ==
      "pa125-base-lowest-bool-option-noncanonical-marker")
    "marker descriptor scope"
  expect (manifest.baseCaseId == "full-tag-valid-v1" &&
      manifest.baseCanonicalFile ==
        "testdata/golden/source-program-v1/full-tag-v1/canonical.bin")
    "marker base identity"
  expect (manifest.baseCanonicalBytesSha256 == "sha256:" ++ baseSha &&
      baseSha == "a7075ca364c099e18510c1f5a8961449e3859d6a45fec46820d327a7d095a0d8")
    "marker base digest"
  expect (manifest.boolOccurrenceCount == 25 &&
      manifest.optionOccurrenceCount == 16 && manifest.optionFieldCount == 4 &&
      manifest.boolMutationCount == 2 && manifest.optionMutationCount == 8 &&
      manifest.mutationCount == 10 && manifest.mutations.size == 10 &&
      expectedKeys.size == 10 && expectedCaseIds.size == 10)
    "marker descriptor cardinalities"

  let mut observedKeys : Array String := #[]
  let mut observedCaseIds : Array String := #[]
  let mut observedOffsets : Array Nat := #[]
  let mut previous? : Option String := none
  for row in manifest.mutations do
    let key := markerKey row
    expect (expectedKeys.contains key) s!"{row.caseId}: unknown marker key {key}"
    expect (!observedKeys.contains key) s!"{row.caseId}: duplicate marker key"
    expect (!observedCaseIds.contains row.caseId) s!"{row.caseId}: duplicate case id"
    expect (!observedOffsets.contains row.markerOffset) s!"{row.caseId}: duplicate offset"
    match previous? with
    | none => pure ()
    | some previous =>
        expect (previous < key) s!"{row.caseId}: mutation rows are not sorted"
    previous? := some key
    observedKeys := observedKeys.push key
    observedCaseIds := observedCaseIds.push row.caseId
    observedOffsets := observedOffsets.push row.markerOffset

    expect (row.markerOffset < canonical.size)
      s!"{row.caseId}: marker offset outside canonical.bin"
    expect (row.baseMarker ≤ 1 && row.mutatedMarker == 2)
      s!"{row.caseId}: marker mutation must be 0/1 to 2"
    expect ((canonical.get! row.markerOffset).toNat == row.baseMarker)
      s!"{row.caseId}: base marker mismatch"
    let exactError := if row.markerKind == "bool" then
      "invalid bool marker" else "invalid option marker"
    expect (row.expectedError == exactError)
      s!"{row.caseId}: expected error mismatch"

    let mutated := canonical.set! row.markerOffset (UInt8.ofNat row.mutatedMarker)
    expect (mutated.size == canonical.size && mutated != canonical &&
        (mutated.get! row.markerOffset).toNat == 2)
      s!"{row.caseId}: one-byte mutation failed"
    expectDecodeError row mutated
    expect (Crypto.sha256Hex canonical == baseSha)
      s!"{row.caseId}: base canonical bytes changed"

  expect (observedKeys == expectedKeys) "closed marker key matrix"
  expect (observedCaseIds == expectedCaseIds) "closed marker case-id matrix"

  let decoded ← liftResult "decode unchanged PA125 base"
    (decodeCanonicalSourceAstBytesV1 canonical)
  let reencoded ← liftResult "re-encode unchanged PA125 base"
    (canonicalValidatedSourceAstBytesV1 decoded)
  expect (reencoded == canonical && Crypto.sha256Hex canonical == baseSha)
    "PA125 base must remain an exact decode/re-encode fixed point"

end Tests.Language.SourceProgramWireMarkerGoldenV1
