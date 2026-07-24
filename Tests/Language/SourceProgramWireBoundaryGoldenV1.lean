import Lean
import ProofForgeV2.Core.Crypto
import ProofForgeV2.Source.AstCanonicalRootDecodeV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.SourceProgramWireBoundaryGoldenV1

open Lean
open ProofForgeV2
open ProofForgeV2.Source.AstCanonicalRootDecodeV1
open ProofForgeV2.Source.ValidatedSourceV1

private structure CategoryCount where
  category : String
  count : Nat
  deriving DecidableEq, FromJson, Repr

private structure MutationRow where
  caseId : String
  category : String
  expectedError : String
  mutatedSha256 : String
  mutatedSize : Nat
  offset : Nat
  removeLength : Nat
  removedSha256 : String
  replacementHex : String
  deriving FromJson, Repr

private structure MutationManifest where
  baseCanonicalBytesSha256 : String
  baseCanonicalFile : String
  baseCaseId : String
  categories : Array CategoryCount
  categoryCount : Nat
  mutationCount : Nat
  mutations : Array MutationRow
  schema : String
  scope : String
  deriving FromJson, Repr

private def basePath : System.FilePath :=
  "testdata/golden/source-program-v1/full-tag-v1/canonical.bin"

private def manifestPath : System.FilePath :=
  "testdata/golden/source-program-v1/boundary-v1/manifest.json"

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error detail => throw <| IO.userError s!"{label}: unexpected error: {detail}"

private def expectedCategories : Array CategoryCount := #[
  { category := "array-count", count := 7 },
  { category := "component-count", count := 7 },
  { category := "component-length", count := 6 },
  { category := "identity", count := 2 },
  { category := "integer-width", count := 8 },
  { category := "numeric-bound", count := 3 },
  { category := "qualified-id-count", count := 8 },
  { category := "string-length", count := 1 },
  { category := "tag-framing", count := 5 },
  { category := "trailing", count := 1 },
  { category := "truncation", count := 8 },
  { category := "unicode", count := 7 },
  { category := "validated-scalar", count := 4 }
]

private def expectedCaseIds : Array String := #[
  "array-length-4097",
  "block-statements-count-max",
  "bytes-length-4097",
  "enumdecl-variants-count-max",
  "expr-match-arms-count-max",
  "extension-digest-prefix",
  "extension-digest-uppercase",
  "extension-qid-count-0",
  "extension-qid-count-1",
  "extension-qid-count-257",
  "extension-qid-count-4294967295",
  "extension-semver-invalid",
  "field-id-invalid",
  "for-bound-4097",
  "identity-invalid-utf8",
  "int-width-0",
  "int-width-257",
  "int-width-65535",
  "int-width-7",
  "literal-string-invalid-utf8",
  "literal-string-length-max",
  "literal-string-non-nfc",
  "module-closing-guillemet",
  "module-component-count-0",
  "module-component-count-257",
  "module-component-count-4294967295",
  "module-control",
  "module-identity-mismatch",
  "module-invalid-utf8",
  "module-length-0",
  "module-length-241",
  "module-length-4294967295",
  "module-non-nfc",
  "pattern-constructor-args-count-max",
  "program-identity-count-0",
  "program-identity-count-1",
  "program-identity-count-257",
  "program-identity-count-4294967295",
  "program-items-count-max",
  "program-items-empty",
  "program-name-length-0",
  "program-name-length-241",
  "program-name-length-4294967295",
  "program-name-mismatch",
  "program-tag-invalid-utf8",
  "program-tag-length-0",
  "program-tag-length-22",
  "program-tag-length-4294967295",
  "program-tag-nonascii",
  "structdecl-fields-count-max",
  "theorem-qid-count-0",
  "theorem-qid-count-1",
  "theorem-qid-count-257",
  "theorem-qid-count-4294967295",
  "trailing-one-byte",
  "truncate-after-module-count",
  "truncate-empty",
  "truncate-final-byte",
  "truncate-partial-module-length",
  "truncate-partial-module-value",
  "truncate-u256",
  "truncate-u32-one-byte",
  "truncate-u32-three-bytes",
  "uint-width-0",
  "uint-width-257",
  "uint-width-65535",
  "uint-width-7"
]

private def expectedCategory (caseId : String) : String :=
  if caseId.startsWith "truncate-" then "truncation"
  else if caseId == "trailing-one-byte" then "trailing"
  else if caseId.startsWith "module-component-count-" ||
      caseId.startsWith "program-identity-count-" then "component-count"
  else if caseId.startsWith "module-length-" ||
      caseId.startsWith "program-name-length-" then "component-length"
  else if caseId == "module-identity-mismatch" ||
      caseId == "program-name-mismatch" then "identity"
  else if caseId.startsWith "uint-width-" || caseId.startsWith "int-width-" then
    "integer-width"
  else if caseId == "array-length-4097" || caseId == "bytes-length-4097" ||
      caseId == "for-bound-4097" then "numeric-bound"
  else if caseId.startsWith "extension-qid-count-" ||
      caseId.startsWith "theorem-qid-count-" then "qualified-id-count"
  else if caseId == "literal-string-length-max" then "string-length"
  else if caseId.startsWith "program-tag-" then "tag-framing"
  else if caseId == "program-items-empty" || caseId.endsWith "count-max" then
    "array-count"
  else if caseId == "identity-invalid-utf8" || caseId == "literal-string-invalid-utf8" ||
      caseId == "literal-string-non-nfc" || caseId == "module-closing-guillemet" ||
      caseId == "module-control" || caseId == "module-invalid-utf8" ||
      caseId == "module-non-nfc" then "unicode"
  else if caseId.startsWith "extension-" || caseId == "field-id-invalid" then
    "validated-scalar"
  else ""

private def expectedError (caseId : String) : String :=
  if caseId == "truncate-final-byte" ||
      caseId == "truncate-partial-module-value" then
    "string length exceeds remaining"
  else if caseId.startsWith "truncate-" then "truncated"
  else if caseId == "trailing-one-byte" then "trailing bytes"
  else if caseId.startsWith "module-component-count-" then
    "source qualified name must contain 1..256 components"
  else if caseId.startsWith "program-identity-count-" ||
      caseId.startsWith "extension-qid-count-" ||
      caseId.startsWith "theorem-qid-count-" then
    "source qualified id must contain 2..256 components"
  else if caseId.startsWith "module-length-" ||
      caseId.startsWith "program-name-length-" then
    "source name component must contain 1..240 UTF-8 bytes"
  else if caseId == "identity-invalid-utf8" ||
      caseId == "literal-string-invalid-utf8" || caseId == "module-invalid-utf8" then
    "invalid UTF-8"
  else if caseId == "literal-string-non-nfc" || caseId == "module-non-nfc" then
    "string must already be NFC under Unicode 17.0.0"
  else if caseId == "module-control" then
    "source name component must not contain a Cc code point"
  else if caseId == "module-closing-guillemet" then
    "source name component must not contain closing guillemet"
  else if caseId.startsWith "program-tag-length-" then
    "tag length must be 1..21 bytes"
  else if caseId == "program-tag-invalid-utf8" then "invalid UTF-8 tag"
  else if caseId == "program-tag-nonascii" then "tag must be ASCII"
  else if caseId == "module-identity-mismatch" then
    "program identity must begin with the exact module name components"
  else if caseId == "program-name-mismatch" then
    "program name must equal the last program identity component"
  else if caseId == "program-items-empty" then "program items must be nonempty"
  else if caseId.endsWith "count-max" then "array count exceeds caller limit"
  else if caseId.startsWith "uint-width-" || caseId.startsWith "int-width-" then
    "integer width must be one of 8,16,32,64,128,256"
  else if caseId == "array-length-4097" then "array length must be 0..4096"
  else if caseId == "bytes-length-4097" then "bytes length must be 0..4096"
  else if caseId == "for-bound-4097" then "for bound must be 0..4096"
  else if caseId == "literal-string-length-max" then "string length exceeds remaining"
  else if caseId == "extension-semver-invalid" then
    "extension version must use canonical exact SemVer"
  else if caseId.startsWith "extension-digest-" then
    "extension digest must use canonical sha256 spelling"
  else if caseId == "field-id-invalid" then "field id must be bn254_fr"
  else ""

private def hexNibble? (character : Char) : Option Nat :=
  if '0' ≤ character && character ≤ '9' then
    some (character.toNat - '0'.toNat)
  else if 'a' ≤ character && character ≤ 'f' then
    some (character.toNat - 'a'.toNat + 10)
  else
    none

private def decodeHex (value : String) : Except String ByteArray := do
  let characters := value.toList.toArray
  unless characters.size % 2 == 0 do
    throw "replacement hex must contain an even number of lowercase digits"
  let mut output := ByteArray.emptyWithCapacity (characters.size / 2)
  let mut index := 0
  while index < characters.size do
    let some high := hexNibble? characters[index]!
      | throw "replacement hex must contain only lowercase digits"
    let some low := hexNibble? characters[index + 1]!
      | throw "replacement hex must contain only lowercase digits"
    output := output.push (UInt8.ofNat (high * 16 + low))
    index := index + 2
  pure output

private def readManifest : IO MutationManifest := do
  let payload ← IO.FS.readFile manifestPath
  match Json.parse payload >>= fromJson? with
  | .ok manifest => pure manifest
  | .error detail => throw <| IO.userError s!"invalid boundary mutation manifest: {detail}"

private def expectDecodeError (row : MutationRow) (bytes : ByteArray) : IO Unit :=
  match decodeCanonicalSourceAstBytesV1 bytes with
  | .error detail =>
      expect (detail == row.expectedError)
        s!"{row.caseId}: expected '{row.expectedError}', got '{detail}'"
  | .ok _ => throw <| IO.userError s!"{row.caseId}: unexpectedly decoded"

/-- TASK-D1-01/TST-SRC-001 residual scalar, length, truncation, and trailing goldens. -/
def run : IO Unit := do
  let canonical ← IO.FS.readBinFile basePath
  let manifest ← readManifest
  let baseSha := Crypto.sha256Hex canonical
  expect (manifest.schema ==
      "proof-forge.source-program-boundary-golden-prerequisite.v1")
    "boundary descriptor schema"
  expect (manifest.scope == "pa125-base-scalar-length-truncation-trailing")
    "boundary descriptor scope"
  expect (manifest.baseCaseId == "full-tag-valid-v1" &&
      manifest.baseCanonicalFile ==
        "testdata/golden/source-program-v1/full-tag-v1/canonical.bin")
    "boundary base identity"
  expect (manifest.baseCanonicalBytesSha256 == "sha256:" ++ baseSha &&
      baseSha == "5d38eaca671e503ae50a517cc8ffaddba20b370d11da22f6bcdb807089aa64ce")
    "boundary base digest"
  expect (manifest.categories == expectedCategories && manifest.categoryCount == 13 &&
      manifest.mutationCount == 67 && manifest.mutations.size == 67 &&
      manifest.mutations.map (·.caseId) == expectedCaseIds)
    "boundary closed inventories"

  let mut seenOperations : Array String := #[]
  for row in manifest.mutations do
    let category := expectedCategory row.caseId
    let error := expectedError row.caseId
    expect (category != "" && row.category == category)
      s!"{row.caseId}: category mismatch"
    expect (error != "" && row.expectedError == error)
      s!"{row.caseId}: expected error mismatch"
    expect (row.offset ≤ canonical.size &&
        row.removeLength ≤ canonical.size - row.offset)
      s!"{row.caseId}: replacement range"
    let removed := canonical.extract row.offset (row.offset + row.removeLength)
    expect (row.removedSha256 == "sha256:" ++ Crypto.sha256Hex removed)
      s!"{row.caseId}: removed-byte binding"
    let replacement ← liftResult row.caseId (decodeHex row.replacementHex)
    let operation := s!"{row.offset}:{row.removeLength}:{row.replacementHex}"
    expect (!seenOperations.contains operation) s!"{row.caseId}: duplicate operation"
    seenOperations := seenOperations.push operation
    let mutated := canonical.extract 0 row.offset ++ replacement ++
      canonical.extract (row.offset + row.removeLength) canonical.size
    expect (mutated != canonical && mutated.size == row.mutatedSize &&
        row.mutatedSha256 == "sha256:" ++ Crypto.sha256Hex mutated)
      s!"{row.caseId}: mutated-byte binding"
    expectDecodeError row mutated
    expect (Crypto.sha256Hex canonical == baseSha)
      s!"{row.caseId}: base canonical bytes changed"

  let decoded ← liftResult "decode unchanged PA125 base"
    (decodeCanonicalSourceAstBytesV1 canonical)
  let reencoded ← liftResult "re-encode unchanged PA125 base"
    (canonicalValidatedSourceAstBytesV1 decoded)
  expect (reencoded == canonical && Crypto.sha256Hex canonical == baseSha)
    "PA125 base must remain an exact decode/re-encode fixed point"

end Tests.Language.SourceProgramWireBoundaryGoldenV1
