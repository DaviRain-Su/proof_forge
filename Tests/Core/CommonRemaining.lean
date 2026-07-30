/-
  Tests.Core.CommonRemaining — RED acceptance for remaining TASK-D0-06 gaps.

  Authority (frozen TST-COMMON-001 / TASK-D0-06 / SPEC-COMMON-001 / ADR-0014):
    ProjectRelativePath, QualifiedName, ContentRef, SourceOrigin,
    PF-JCS + domain-separated SHA-256, ResourceProfileV1 hard maxima / lower-only /
    exact wire + digest.

  Out of scope (must not be satisfied by expanding this suite's API surface):
    Unicode default casefold uniqueness, filesystem safe-open, runtime enforcement,
    SBOM (D0-05), Stage-0/authority (D0-04).

  ---------------------------------------------------------------------------
  Planned minimal public API (ProofForgeV2.Core.Common unless noted)
  Coordinator implements exactly these names/types; tests do not invent extras.
  ---------------------------------------------------------------------------

  structure ProjectRelativePath where value : String
  def parseProjectRelativePath : String → Except String ProjectRelativePath
  def validateProjectRelativePath : ProjectRelativePath → Except String Unit
  def renderProjectRelativePath : ProjectRelativePath → Except String String

  structure QualifiedName where components : NonEmptyArray String
  def parseQualifiedName : Array String → Except String QualifiedName
  def validateQualifiedName : QualifiedName → Except String Unit
  def renderQualifiedNameComponents : QualifiedName → Except String (Array String)
  def renderQualifiedNameJcs : QualifiedName → Except String String
  def parseQualifiedNameJcs : String → Except String QualifiedName

  structure ContentRef where
    schema  : SchemaId
    id      : String
    version : SemVer
    digest  : Digest
  def validateContentRef : ContentRef → Except String Unit
  def renderContentRefJcs : ContentRef → Except String String
  def parseContentRefJcs : String → Except String ContentRef

  structure SourceOrigin where
    sourcePath : ProjectRelativePath
    startByte  : UInt64
    endByte    : UInt64
    nodeId     : NodeId
  def validateSourceOrigin : SourceOrigin → Except String Unit
  /-- Canonical key = (sourcePath UTF-8, startByte, endByte, nodeId raw 16 bytes). -/
  def sourceOriginKey :
      SourceOrigin → Except String (String × UInt64 × UInt64 × ByteArray)
  def renderSourceOriginJcs : SourceOrigin → Except String String
  def parseSourceOriginJcs : String → Except String SourceOrigin

  inductive PfJson where
    | null
    | bool (value : Bool)
    | int (value : Int)
    | string (value : String)
    | array (values : Array PfJson)
    | object (fields : Array (String × PfJson))
    deriving DecidableEq, Repr
  /-- Restricted PF-JCS UTF-8 text; object keys use RFC 8785 UTF-16 order. -/
  def renderPfJcs : PfJson → Except String String
  /-- Decode restricted PF-JCS; reject duplicate keys and non-canonical spellings. -/
  def parsePfJcs : String → Except String PfJson
  /-- Byte entry point additionally rejects invalid UTF-8 before JSON parsing. -/
  def parsePfJcsBytes : ByteArray → Except String PfJson

  /-- Raw SHA-256 over exact bytes (always defined). -/
  def sha256Bytes : ByteArray → Digest
  /-- SHA-256(UTF8(domainTag) || 0x00 || payload); domainTag nonempty lowercase ASCII. -/
  def domainSeparatedSha256 : String → ByteArray → Except String Digest

  inductive ResourceStage where
    | frontend | compilerCore | externalTool | artifactOutput
  inductive MemoryMetric where
    | darwinPhysFootprintAggregate
    | linuxProcRssAggregate
    | linuxCgroupMemoryCurrent
    | jobObjectCommitAggregate

  structure ResourceProfileV1 where
    schema                  : SchemaId
    profileId               : SchemaId
    stage                   : ResourceStage
    maxWallMillis           : UInt64
    maxAggregateMemoryBytes : UInt64
    memoryMetric            : MemoryMetric
    maxProcesses            : UInt32
    maxProtocolBytes        : UInt64
    maxStderrBytes          : UInt64
    maxPublishedBytes       : UInt64

  def parseResourceStage : String → Except String ResourceStage
  def renderResourceStage : ResourceStage → String
  def parseMemoryMetric : String → Except String MemoryMetric
  def renderMemoryMetric : MemoryMetric → String

  def hardFrontendProfile : ResourceProfileV1
  def hardCoreProfile : ResourceProfileV1
  def hardToolProfile : ResourceProfileV1
  def hardOutputProfile : ResourceProfileV1

  def validateResourceProfileV1 : ResourceProfileV1 → Except String Unit
  /-- Effective must not raise any hard maximum; hard=0 forces effective=0. -/
  def validateLowerOnlyResourceProfile :
      (hard effective : ResourceProfileV1) → Except String Unit
  def renderResourceProfileJcs : ResourceProfileV1 → Except String String
  def parseResourceProfileJcs : String → Except String ResourceProfileV1
  def resourceProfileDigest : ResourceProfileV1 → Except String Digest

  Goldens below are independent of any candidate implementation:
    * Path/QName/ContentRef/SourceOrigin vectors follow SPEC-COMMON-001 prose.
    * JCS strings follow RFC 8785 (lexicographic object keys, required escapes).
    * SHA-256 empty / "abc" / long FIPS vectors from NIST FIPS 180-2 examples.
    * ResourceProfile numbers from the SPEC-COMMON-001 hard-maxima table.
-/
import ProofForgeV2.Core.Common

namespace Tests.Core.CommonRemaining

open ProofForgeV2.Core.Common

private def expectOk {α} [BEq α] [Repr α]
    (label : String) (got : Except String α) (want : α) : IO Unit := do
  match got with
  | .ok value =>
    unless value == want do
      throw <| IO.userError s!"{label}: expected {repr want}, got {repr value}"
  | .error e => throw <| IO.userError s!"{label}: unexpected error {e}"

private def expectErr {α} (label : String) (got : Except String α) : IO Unit := do
  match got with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError s!"{label}: expected error"

private def expectTrue (label : String) (b : Bool) : IO Unit := do
  unless b do
    throw <| IO.userError s!"{label}: expected true"

private def ofScalars (codePoints : List Nat) : String :=
  codePoints.foldl (fun acc cp => acc.push (Char.ofNat cp)) ""

private def repeated (count : Nat) (value : Char) : String :=
  String.ofList (List.replicate count value)

private def bytesOf (xs : Array UInt8) : ByteArray :=
  ByteArray.mk xs

private def utf8Bytes (s : String) : ByteArray :=
  -- Production must treat String as UTF-8 scalar sequence; tests pass Lean strings
  -- whose utf8ByteSize matches ASCII/BMP fixtures used here.
  s.toUTF8

-- NIST FIPS 180-2 / di-mgt SHA-256 known answers (independent of project code).
private def sha256EmptyHex : String :=
  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
private def sha256AbcHex : String :=
  "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
private def sha256448Hex : String :=
  "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
private def sha256NullByteHex : String :=
  "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d"
private def sha256PfTestObjectHex : String :=
  "c396dde21c601d7650d29d1f965611cbc3cf72761972e1e7434a514675ba826d"
private def frontendHardDigestHex : String :=
  "5f3181e0fc5f7f15931ae4227782e5c3204e11e9177e1cb949918cc5bdbedc17"

private def digestFromHex (hex : String) : Except String Digest :=
  parseDigest ("sha256:" ++ hex)

-- ---------------------------------------------------------------------------
-- ProjectRelativePath
-- ---------------------------------------------------------------------------

private def testProjectRelativePath : IO Unit := do
  expectOk "path single segment"
    (parseProjectRelativePath "src") { value := "src" }
  expectOk "path nested"
    (parseProjectRelativePath "src/Main.lean") { value := "src/Main.lean" }
  expectOk "path min one byte"
    (parseProjectRelativePath "a") { value := "a" }
  let maxPath := repeated 1024 'a'
  expectOk "path max 1024 utf8 bytes"
    (parseProjectRelativePath maxPath) { value := maxPath }
  let maxMultibytePath := repeated 512 (Char.ofNat 0x00E9)
  expectOk "path max is measured in UTF-8 bytes"
    (parseProjectRelativePath maxMultibytePath) { value := maxMultibytePath }
  expectErr "path empty" (parseProjectRelativePath "")
  expectErr "path over 1024" (parseProjectRelativePath (repeated 1025 'a'))
  expectErr "path multibyte over 1024"
    (parseProjectRelativePath (repeated 513 (Char.ofNat 0x00E9)))
  expectErr "path absolute" (parseProjectRelativePath "/abs")
  expectErr "path Windows drive absolute" (parseProjectRelativePath "C:/abs")
  expectErr "path empty segment" (parseProjectRelativePath "a//b")
  expectErr "path dot segment" (parseProjectRelativePath "a/./b")
  expectErr "path only dot" (parseProjectRelativePath ".")
  expectErr "path parent segment" (parseProjectRelativePath "a/../b")
  expectErr "path only parent" (parseProjectRelativePath "..")
  expectErr "path backslash" (parseProjectRelativePath "a\\b")
  expectErr "path trailing slash empty segment" (parseProjectRelativePath "a/")
  expectErr "path leading slash absolute" (parseProjectRelativePath "/")
  -- Cc: U+0000 NUL, U+0009 TAB, U+000A LF, U+001F
  expectErr "path rejects NUL"
    (parseProjectRelativePath (ofScalars [0x61, 0x00, 0x62]))
  expectErr "path rejects TAB"
    (parseProjectRelativePath (ofScalars [0x61, 0x09, 0x62]))
  expectErr "path rejects LF"
    (parseProjectRelativePath (ofScalars [0x61, 0x0A, 0x62]))
  expectErr "path rejects DEL is not Cc-only path issue — DEL is Cc"
    (parseProjectRelativePath (ofScalars [0x61, 0x7F, 0x62]))
  -- NFC: precomposed e-acute accepted; NFD e + combining acute rejected (fail closed).
  expectOk "path composed e-acute NFC"
    (parseProjectRelativePath (ofScalars [0x00E9])) { value := ofScalars [0x00E9] }
  expectErr "path decomposed e-acute non-NFC"
    (parseProjectRelativePath (ofScalars [0x0065, 0x0301]))
  expectErr "path renderer validates direct construction"
    (renderProjectRelativePath { value := "/abs" })
  expectErr "path validation rejects parent"
    (validateProjectRelativePath { value := ".." })
  match parseProjectRelativePath "lib/Util.lean" with
  | .ok path =>
    expectOk "path render roundtrip" (renderProjectRelativePath path) "lib/Util.lean"
  | .error e => throw <| IO.userError s!"path happy parse failed: {e}"

-- ---------------------------------------------------------------------------
-- QualifiedName
-- ---------------------------------------------------------------------------

private def testQualifiedName : IO Unit := do
  match parseQualifiedName #["Counter"] with
  | .ok qn =>
    expectOk "qname singleton components"
      (renderQualifiedNameComponents qn) #["Counter"]
  | .error e => throw <| IO.userError s!"qname singleton: {e}"
  match parseQualifiedName #["Foo", "Bar", "baz"] with
  | .ok qn =>
    expectOk "qname preserves declaration order"
      (renderQualifiedNameComponents qn) #["Foo", "Bar", "baz"]
  | .error e => throw <| IO.userError s!"qname multi: {e}"
  expectErr "qname empty array" (parseQualifiedName #[])
  expectOk "qname underscore-prefixed identifier"
    (parseQualifiedName #["_value"])
    { components := { head := "_value", tail := #[] } }
  expectErr "qname empty component" (parseQualifiedName #["Foo", ""])
  expectErr "qname numeral component" (parseQualifiedName #["123"])
  expectErr "qname leading digit" (parseQualifiedName #["1abc"])
  expectErr "qname anonymous underscore" (parseQualifiedName #["_"])
  expectErr "qname space" (parseQualifiedName #["a b"])
  expectErr "qname slash" (parseQualifiedName #["a/b"])
  -- component max 240 UTF-8 bytes
  expectOk "qname component max 240"
    (parseQualifiedName #[repeated 240 'a'])
    { components := { head := repeated 240 'a', tail := #[] } }
  expectOk "qname component multibyte max 240"
    (parseQualifiedName #[repeated 120 (Char.ofNat 0x00E9)])
    { components := { head := repeated 120 (Char.ofNat 0x00E9), tail := #[] } }
  expectErr "qname component 241"
    (parseQualifiedName #[repeated 241 'a'])
  expectErr "qname component multibyte over 240"
    (parseQualifiedName #[repeated 121 (Char.ofNat 0x00E9)])
  -- 256 components ok; 257 rejected
  let maxComponents := Array.replicate 256 "a"
  match parseQualifiedName maxComponents with
  | .ok qn =>
    expectOk "qname 256 components"
      (renderQualifiedNameComponents qn) maxComponents
  | .error e => throw <| IO.userError s!"qname 256: {e}"
  expectErr "qname 257 components"
    (parseQualifiedName (Array.replicate 257 "a"))
  -- NFC on each component
  expectOk "qname composed component NFC"
    (parseQualifiedName #[ofScalars [0x00E9]])
    { components := { head := ofScalars [0x00E9], tail := #[] } }
  expectErr "qname decomposed component non-NFC"
    (parseQualifiedName #[ofScalars [0x0065, 0x0301]])
  expectErr "qname validate rejects numeral direct construction"
    (validateQualifiedName
      { components := { head := "9", tail := #[] } })
  match parseQualifiedName #["Foo", "Bar"] with
  | .ok qn =>
    expectOk "qname exact JCS array"
      (renderQualifiedNameJcs qn) "[\"Foo\",\"Bar\"]"
    expectOk "qname exact JCS roundtrip"
      (parseQualifiedNameJcs "[\"Foo\",\"Bar\"]") qn
  | .error e => throw <| IO.userError s!"qname JCS fixture: {e}"
  expectErr "qname JCS rejects empty array" (parseQualifiedNameJcs "[]")
  expectErr "qname JCS rejects non-string component"
    (parseQualifiedNameJcs "[\"Foo\",1]")
  expectErr "qname JCS rejects whitespace"
    (parseQualifiedNameJcs "[\"Foo\", \"Bar\"]")

-- ---------------------------------------------------------------------------
-- validateIdentifierComponent (shared SPEC-COMMON component rule)
-- ---------------------------------------------------------------------------

/-- Shared identifier component rule is the exact truth for QualifiedName
    components and SemanticProgramV1 declaration names. Pins NFC, length,
    anonymous `_`, and Lean.isIdFirst/isIdRest without inventing a second
    grammar. -/
private def testIdentifierComponent : IO Unit := do
  expectOk "ident ASCII" (validateIdentifierComponent "Counter") ()
  expectOk "ident underscore-prefixed" (validateIdentifierComponent "_value") ()
  expectOk "ident max 240 ASCII"
    (validateIdentifierComponent (repeated 240 'a')) ()
  expectOk "ident composed e-acute NFC"
    (validateIdentifierComponent (ofScalars [0x00E9])) ()
  expectErr "ident empty" (validateIdentifierComponent "")
  expectErr "ident anonymous underscore" (validateIdentifierComponent "_")
  expectErr "ident digit-first" (validateIdentifierComponent "1abc")
  expectErr "ident numeral" (validateIdentifierComponent "123")
  expectErr "ident space" (validateIdentifierComponent "a b")
  expectErr "ident punctuation hyphen" (validateIdentifierComponent "a-b")
  expectErr "ident punctuation slash" (validateIdentifierComponent "a/b")
  expectErr "ident decomposed e-acute non-NFC"
    (validateIdentifierComponent (ofScalars [0x0065, 0x0301]))
  expectErr "ident 241 ASCII"
    (validateIdentifierComponent (repeated 241 'a'))
  expectErr "ident multibyte over 240"
    (validateIdentifierComponent (repeated 121 (Char.ofNat 0x00E9)))
  -- Shared with QualifiedName: the same validator rejects the same vectors.
  expectErr "ident shared with qname numeral"
    (validateQualifiedName { components := { head := "9", tail := #[] } })
  expectErr "ident shared with qname anonymous"
    (parseQualifiedName #["_"])
  expectOk "ident shared with qname NFC component"
    (parseQualifiedName #[ofScalars [0x00E9]])
    { components := { head := ofScalars [0x00E9], tail := #[] } }

-- ---------------------------------------------------------------------------
-- ContentRef
-- ---------------------------------------------------------------------------

private def testContentRef : IO Unit := do
  let digest ← match digestFromHex sha256EmptyHex with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"contentref digest fixture: {e}"
  let schema ← match parseSchemaId "proof-forge.example.v1" with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"contentref schema fixture: {e}"
  let version ← match parseSemVer "1.2.3" with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"contentref version fixture: {e}"
  let good : ContentRef :=
    { schema := schema
      id := "payload-id"
      version := version
      digest := digest }
  expectOk "contentref valid" (validateContentRef good) ()
  expectErr "contentref bad schema grammar"
    (validateContentRef { good with schema := { value := "NotASchema" } })
  expectErr "contentref id uppercase"
    (validateContentRef { good with id := "Payload" })
  expectErr "contentref id empty"
    (validateContentRef { good with id := "" })
  expectErr "contentref id leading digit"
    (validateContentRef { good with id := "1payload" })
  expectErr "contentref bad version direct"
    (validateContentRef
      { good with version := { major := 1, minor := 2, patch := 3, prerelease := #[""], build := #[] } })
  expectErr "contentref digest wrong length"
    (validateContentRef
      { good with digest := { algorithm := .sha256, bytes := ByteArray.empty } })
  let wire :=
    "{\"digest\":\"sha256:" ++ sha256EmptyHex ++
    "\",\"id\":\"payload-id\",\"schema\":\"proof-forge.example.v1\"," ++
    "\"version\":\"1.2.3\"}"
  expectOk "contentref exact JCS" (renderContentRefJcs good) wire
  expectOk "contentref exact JCS roundtrip" (parseContentRefJcs wire) good
  expectErr "contentref JCS missing field"
    (parseContentRefJcs
      ("{\"digest\":\"sha256:" ++ sha256EmptyHex ++
       "\",\"id\":\"payload-id\",\"schema\":\"proof-forge.example.v1\"}"))
  expectErr "contentref JCS unknown field"
    (parseContentRefJcs
      ("{\"digest\":\"sha256:" ++ sha256EmptyHex ++
       "\",\"extra\":null,\"id\":\"payload-id\"," ++
       "\"schema\":\"proof-forge.example.v1\",\"version\":\"1.2.3\"}"))
  expectErr "contentref JCS duplicate field"
    (parseContentRefJcs
      ("{\"digest\":\"sha256:" ++ sha256EmptyHex ++
       "\",\"id\":\"payload-id\",\"id\":\"other\"," ++
       "\"schema\":\"proof-forge.example.v1\",\"version\":\"1.2.3\"}"))
  expectErr "contentref JCS alternate digest spelling"
    (parseContentRefJcs
      ("{\"digest\":\"sha256:ABCDEF\",\"id\":\"payload-id\"," ++
       "\"schema\":\"proof-forge.example.v1\",\"version\":\"1.2.3\"}"))

-- ---------------------------------------------------------------------------
-- SourceOrigin
-- ---------------------------------------------------------------------------

private def testSourceOrigin : IO Unit := do
  let path ← match parseProjectRelativePath "src/Main.lean" with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"origin path fixture: {e}"
  let node ← match parseNodeId "nodeid:00000000000000000000000000000000" with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"origin node fixture: {e}"
  let good : SourceOrigin :=
    { sourcePath := path
      startByte := 0
      endByte := 10
      nodeId := node }
  expectOk "origin valid span" (validateSourceOrigin good) ()
  expectOk "origin equal span endpoints"
    (validateSourceOrigin { good with startByte := 4, endByte := 4 }) ()
  expectErr "origin start after end"
    (validateSourceOrigin { good with startByte := 11, endByte := 10 })
  expectErr "origin invalid path member"
    (validateSourceOrigin { good with sourcePath := { value := "../x" } })
  expectErr "origin invalid node length"
    (validateSourceOrigin
      { good with nodeId := { bytes := ByteArray.empty } })
  match sourceOriginKey good with
  | .ok (pathKey, startKey, endKey, nodeBytes) =>
    expectTrue "origin key path" (pathKey == "src/Main.lean")
    expectTrue "origin key start" (startKey == 0)
    expectTrue "origin key end" (endKey == 10)
    expectTrue "origin key node 16 bytes" (nodeBytes.size == 16)
  | .error e => throw <| IO.userError s!"origin key: {e}"
  -- Key ignores any non-path identity; same path bytes must match UTF-8 value.
  match sourceOriginKey good, sourceOriginKey { good with startByte := 1 } with
  | .ok k1, .ok k2 =>
    expectTrue "origin keys differ on span" (k1 != k2)
  | _, _ => throw <| IO.userError "origin key compare fixtures failed"
  let wire :=
    "{\"endByte\":10,\"nodeId\":\"nodeid:00000000000000000000000000000000\"," ++
    "\"sourcePath\":\"src/Main.lean\",\"startByte\":0}"
  expectOk "origin exact JCS" (renderSourceOriginJcs good) wire
  expectOk "origin exact JCS roundtrip" (parseSourceOriginJcs wire) good
  let safeBoundary : SourceOrigin :=
    { good with startByte := 9007199254740991, endByte := 9007199254740991 }
  match renderSourceOriginJcs safeBoundary with
  | .ok safeWire =>
    expectOk "origin accepts maximum safe JSON integer"
      (parseSourceOriginJcs safeWire) safeBoundary
  | .error e => throw <| IO.userError s!"origin safe boundary render: {e}"
  expectErr "origin JCS missing field"
    (parseSourceOriginJcs
      ("{\"endByte\":10,\"nodeId\":\"nodeid:00000000000000000000000000000000\"," ++
       "\"sourcePath\":\"src/Main.lean\"}"))
  expectErr "origin JCS unknown field"
    (parseSourceOriginJcs
      ("{\"endByte\":10,\"extra\":null," ++
       "\"nodeId\":\"nodeid:00000000000000000000000000000000\"," ++
       "\"sourcePath\":\"src/Main.lean\",\"startByte\":0}"))
  expectErr "origin JCS duplicate field"
    (parseSourceOriginJcs
      ("{\"endByte\":10,\"endByte\":11," ++
       "\"nodeId\":\"nodeid:00000000000000000000000000000000\"," ++
       "\"sourcePath\":\"src/Main.lean\",\"startByte\":0}"))
  expectErr "origin JCS rejects unsafe JSON integer"
    (parseSourceOriginJcs
      ("{\"endByte\":9007199254740992," ++
       "\"nodeId\":\"nodeid:00000000000000000000000000000000\"," ++
       "\"sourcePath\":\"src/Main.lean\",\"startByte\":0}"))

-- ---------------------------------------------------------------------------
-- PF-JCS
-- ---------------------------------------------------------------------------

private def testPfJcs : IO Unit := do
  -- Independent RFC 8785 goldens (lexicographic keys, no whitespace).
  expectOk "jcs null" (renderPfJcs .null) "null"
  expectOk "jcs true" (renderPfJcs (.bool true)) "true"
  expectOk "jcs false" (renderPfJcs (.bool false)) "false"
  expectOk "jcs zero" (renderPfJcs (.int 0)) "0"
  expectOk "jcs positive" (renderPfJcs (.int 42)) "42"
  expectOk "jcs negative safe integer" (renderPfJcs (.int (-1))) "-1"
  expectOk "jcs maximum safe integer"
    (renderPfJcs (.int 9007199254740991)) "9007199254740991"
  expectOk "jcs minimum safe integer"
    (renderPfJcs (.int (-9007199254740991))) "-9007199254740991"
  expectErr "jcs render rejects positive unsafe integer"
    (renderPfJcs (.int 9007199254740992))
  expectErr "jcs render rejects negative unsafe integer"
    (renderPfJcs (.int (-9007199254740992)))
  expectOk "jcs empty array" (renderPfJcs (.array #[])) "[]"
  expectOk "jcs array order preserved"
    (renderPfJcs (.array #[.int 1, .int 2, .string "z"])) "[1,2,\"z\"]"
  expectOk "jcs empty object" (renderPfJcs (.object #[])) "{}"
  -- Unsorted input fields must emit sorted keys.
  expectOk "jcs object key sort"
    (renderPfJcs (.object #[("b", .int 1), ("a", .int 2)])) "{\"a\":2,\"b\":1}"
  expectErr "jcs renderer rejects duplicate keys"
    (renderPfJcs (.object #[("a", .int 1), ("a", .int 2)]))
  -- RFC 8785 orders object keys by UTF-16 code units. A supplementary scalar
  -- begins with D83D and therefore sorts before BMP U+E000, unlike scalar-value
  -- or UTF-8 byte ordering.
  let emojiKey := ofScalars [0x1F600]
  let privateUseKey := ofScalars [0xE000]
  let utf16OrderedWire :=
    "{\"" ++ emojiKey ++ "\":2,\"" ++ privateUseKey ++ "\":1}"
  expectOk "jcs UTF-16 object key ordering"
    (renderPfJcs (.object #[(privateUseKey, .int 1), (emojiKey, .int 2)]))
    utf16OrderedWire
  expectOk "jcs string escapes quote and backslash"
    (renderPfJcs (.string "a\"b\\c")) "\"a\\\"b\\\\c\""
  expectOk "jcs solidus unescaped per JCS"
    (renderPfJcs (.string "a/b")) "\"a/b\""
  expectOk "jcs string lf escape"
    (renderPfJcs (.string (ofScalars [0x61, 0x0A, 0x62]))) "\"a\\nb\""
  expectOk "jcs string backspace short escape"
    (renderPfJcs (.string (ofScalars [0x08]))) "\"\\b\""
  expectOk "jcs string tab short escape"
    (renderPfJcs (.string (ofScalars [0x09]))) "\"\\t\""
  expectOk "jcs string form-feed short escape"
    (renderPfJcs (.string (ofScalars [0x0C]))) "\"\\f\""
  expectOk "jcs string carriage-return short escape"
    (renderPfJcs (.string (ofScalars [0x0D]))) "\"\\r\""
  expectOk "jcs generic control escape"
    (renderPfJcs (.string (ofScalars [0x0001]))) "\"\\u0001\""
  expectOk "jcs DEL is emitted raw"
    (renderPfJcs (.string (ofScalars [0x007F])))
    ("\"" ++ ofScalars [0x007F] ++ "\"")
  -- Nested fixture used by domain-hash tests.
  expectOk "jcs nested object"
    (renderPfJcs
      (.object #[
        ("arr", .array #[.bool true, .null]),
        ("n", .int 0),
        ("s", .string "x")
      ]))
    "{\"arr\":[true,null],\"n\":0,\"s\":\"x\"}"

  -- Decode rejects non-canonical / duplicate / junk.
  expectOk "jcs parse null" (parsePfJcs "null") .null
  expectOk "jcs parse sorted object"
    (parsePfJcs "{\"a\":1,\"b\":2}")
    (.object #[("a", .int 1), ("b", .int 2)])
  expectErr "jcs parse rejects whitespace"
    (parsePfJcs "{ \"a\": 1 }")
  expectErr "jcs parse rejects unsorted keys"
    (parsePfJcs "{\"b\":1,\"a\":2}")
  expectErr "jcs parse rejects duplicate keys"
    (parsePfJcs "{\"a\":1,\"a\":2}")
  expectErr "jcs parse rejects trailing junk"
    (parsePfJcs "null true")
  expectErr "jcs parse rejects leading zero int"
    (parsePfJcs "01")
  expectErr "jcs parse rejects negative zero"
    (parsePfJcs "-0")
  expectOk "jcs parse negative safe integer"
    (parsePfJcs "-1") (.int (-1))
  expectErr "jcs parse rejects positive unsafe integer"
    (parsePfJcs "9007199254740992")
  expectErr "jcs parse rejects negative unsafe integer"
    (parsePfJcs "-9007199254740992")
  expectErr "jcs parse rejects float"
    (parsePfJcs "1.0")
  expectErr "jcs parse rejects exponent"
    (parsePfJcs "1e0")
  expectErr "jcs parse rejects capital True"
    (parsePfJcs "True")
  expectErr "jcs parse rejects single-quoted string"
    (parsePfJcs "'x'")
  expectErr "jcs parse rejects escaped solidus as noncanonical"
    (parsePfJcs "\"\\/\"")
  expectErr "jcs parse rejects escaped printable scalar as noncanonical"
    (parsePfJcs "\"\\u0041\"")
  expectErr "jcs parse rejects long control escape when short form exists"
    (parsePfJcs "\"\\u0008\"")
  expectErr "jcs parse rejects empty"
    (parsePfJcs "")
  expectErr "jcs byte parser rejects invalid UTF-8"
    (parsePfJcsBytes (bytesOf #[0xff]))
  expectErr "jcs parse rejects lone surrogate escape"
    (parsePfJcs "\"\\ud800\"")
  expectErr "jcs parse rejects escaped surrogate pair as noncanonical"
    (parsePfJcs "\"\\ud83d\\ude00\"")
  expectOk "jcs parse accepts raw supplementary scalar"
    (parsePfJcs ("\"" ++ emojiKey ++ "\"")) (.string emojiKey)
  expectOk "jcs parse accepts UTF-16 sorted supplementary keys"
    (parsePfJcs utf16OrderedWire)
    (.object #[(emojiKey, .int 2), (privateUseKey, .int 1)])

-- ---------------------------------------------------------------------------
-- Domain-separated SHA-256
-- ---------------------------------------------------------------------------

private def testDomainHash : IO Unit := do
  -- Raw SHA-256 known answers (NIST).
  match sha256Bytes (ByteArray.empty), digestFromHex sha256EmptyHex with
  | emptyDigest, .ok want =>
    expectTrue "sha256 empty KAT" (emptyDigest == want)
  | _, .error e => throw <| IO.userError s!"empty digest fixture: {e}"
  match sha256Bytes (utf8Bytes "abc"), digestFromHex sha256AbcHex with
  | abcDigest, .ok want =>
    expectTrue "sha256 abc KAT" (abcDigest == want)
  | _, .error e => throw <| IO.userError s!"abc digest fixture: {e}"
  let longMsg :=
    "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
  match sha256Bytes (utf8Bytes longMsg), digestFromHex sha256448Hex with
  | got, .ok want =>
    expectTrue "sha256 448-bit KAT" (got == want)
  | _, .error e => throw <| IO.userError s!"448 digest fixture: {e}"
  match sha256Bytes (bytesOf #[0]), digestFromHex sha256NullByteHex with
  | got, .ok want =>
    expectTrue "sha256 single NUL KAT" (got == want)
  | _, .error e => throw <| IO.userError s!"nul digest fixture: {e}"

  -- Domain tag rules + separation (no reliance on candidate digests for inequality).
  expectErr "domain empty tag" (domainSeparatedSha256 "" (utf8Bytes "x"))
  expectErr "domain uppercase tag" (domainSeparatedSha256 "Pf.Test" (utf8Bytes "x"))
  expectErr "domain space tag" (domainSeparatedSha256 "pf test" (utf8Bytes "x"))
  expectErr "domain leading digit" (domainSeparatedSha256 "1pf.test" (utf8Bytes "x"))
  expectErr "domain trailing separator" (domainSeparatedSha256 "pf.test-" (utf8Bytes "x"))
  expectErr "domain over 127 bytes"
    (domainSeparatedSha256 ("a" ++ repeated 127 'a') (utf8Bytes "x"))
  match domainSeparatedSha256 "pf.test" (utf8Bytes "payload"),
        domainSeparatedSha256 "pf.other" (utf8Bytes "payload") with
  | .ok d1, .ok d2 =>
    expectTrue "domain tag separation" (d1 != d2)
  | _, _ => throw <| IO.userError "domain tag separation failed to hash"
  match domainSeparatedSha256 "pf.test" (utf8Bytes "a"),
        domainSeparatedSha256 "pf.test" (utf8Bytes "b") with
  | .ok d1, .ok d2 =>
    expectTrue "domain payload separation" (d1 != d2)
  | _, _ => throw <| IO.userError "domain payload separation failed to hash"
  -- Domain preimage is not bare payload: must differ from sha256("payload").
  match domainSeparatedSha256 "pf.test" (utf8Bytes "abc"),
        sha256Bytes (utf8Bytes "abc") with
  | .ok dom, bare =>
    expectTrue "domain not bare payload hash" (dom != bare)
  | .error e, _ => throw <| IO.userError s!"domain vs bare: {e}"
  -- Definitional KAT: domainSeparatedSha256(tag, p) == sha256(tag||0x00||p).
  let tag := "pf.test"
  let payload := utf8Bytes "{}"
  -- Preimage = UTF8(tag) || 0x00 || payload (SPEC-COMMON-001 domain hash).
  let preimage := (utf8Bytes tag).push 0 |>.append payload
  match domainSeparatedSha256 tag payload with
  | .ok dom =>
    expectTrue "domain definitional preimage"
      (dom == sha256Bytes preimage)
    match digestFromHex sha256PfTestObjectHex with
    | .ok want => expectTrue "domain independent fixed KAT" (dom == want)
    | .error e => throw <| IO.userError s!"domain KAT fixture: {e}"
  | .error e => throw <| IO.userError s!"domain definitional: {e}"

-- ---------------------------------------------------------------------------
-- ResourceProfileV1
-- ---------------------------------------------------------------------------

/-- Fixed JCS golden for frontend hard profile (RFC 8785 key order). -/
private def frontendHardJcs : String :=
  "{\"maxAggregateMemoryBytes\":2147483648," ++
  "\"maxProcesses\":1," ++
  "\"maxProtocolBytes\":67108864," ++
  "\"maxPublishedBytes\":0," ++
  "\"maxStderrBytes\":65536," ++
  "\"maxWallMillis\":10000," ++
  "\"memoryMetric\":\"darwinPhysFootprintAggregate\"," ++
  "\"profileId\":\"proof-forge.resource.frontend.v1\"," ++
  "\"schema\":\"proof-forge.resource-profile.v1\"," ++
  "\"stage\":\"frontend\"}"

private def coreHardJcs : String :=
  "{\"maxAggregateMemoryBytes\":2147483648," ++
  "\"maxProcesses\":1," ++
  "\"maxProtocolBytes\":67108864," ++
  "\"maxPublishedBytes\":0," ++
  "\"maxStderrBytes\":65536," ++
  "\"maxWallMillis\":30000," ++
  "\"memoryMetric\":\"darwinPhysFootprintAggregate\"," ++
  "\"profileId\":\"proof-forge.resource.core.v1\"," ++
  "\"schema\":\"proof-forge.resource-profile.v1\"," ++
  "\"stage\":\"compilerCore\"}"

private def toolHardJcs : String :=
  "{\"maxAggregateMemoryBytes\":4294967296," ++
  "\"maxProcesses\":8," ++
  "\"maxProtocolBytes\":67108864," ++
  "\"maxPublishedBytes\":0," ++
  "\"maxStderrBytes\":65536," ++
  "\"maxWallMillis\":600000," ++
  "\"memoryMetric\":\"darwinPhysFootprintAggregate\"," ++
  "\"profileId\":\"proof-forge.resource.tool.v1\"," ++
  "\"schema\":\"proof-forge.resource-profile.v1\"," ++
  "\"stage\":\"externalTool\"}"

private def outputHardJcs : String :=
  "{\"maxAggregateMemoryBytes\":2147483648," ++
  "\"maxProcesses\":1," ++
  "\"maxProtocolBytes\":1048576," ++
  "\"maxPublishedBytes\":268435456," ++
  "\"maxStderrBytes\":65536," ++
  "\"maxWallMillis\":60000," ++
  "\"memoryMetric\":\"darwinPhysFootprintAggregate\"," ++
  "\"profileId\":\"proof-forge.resource.output.v1\"," ++
  "\"schema\":\"proof-forge.resource-profile.v1\"," ++
  "\"stage\":\"artifactOutput\"}"

private def testResourceStageMetricWires : IO Unit := do
  expectOk "stage frontend" (parseResourceStage "frontend") .frontend
  expectOk "stage core" (parseResourceStage "compilerCore") .compilerCore
  expectOk "stage tool" (parseResourceStage "externalTool") .externalTool
  expectOk "stage output" (parseResourceStage "artifactOutput") .artifactOutput
  expectErr "stage snake_case rejected" (parseResourceStage "compiler_core")
  expectErr "stage unknown" (parseResourceStage "backend")
  expectTrue "stage render frontend" (renderResourceStage .frontend == "frontend")
  expectTrue "stage render core" (renderResourceStage .compilerCore == "compilerCore")
  expectTrue "stage render tool" (renderResourceStage .externalTool == "externalTool")
  expectTrue "stage render output" (renderResourceStage .artifactOutput == "artifactOutput")
  expectOk "metric darwin"
    (parseMemoryMetric "darwinPhysFootprintAggregate") .darwinPhysFootprintAggregate
  expectOk "metric linux proc rss"
    (parseMemoryMetric "linuxProcRssAggregate") .linuxProcRssAggregate
  expectOk "metric linux"
    (parseMemoryMetric "linuxCgroupMemoryCurrent") .linuxCgroupMemoryCurrent
  expectOk "metric job"
    (parseMemoryMetric "jobObjectCommitAggregate") .jobObjectCommitAggregate
  expectErr "metric snake rejected"
    (parseMemoryMetric "darwin_phys_footprint_aggregate")
  expectErr "metric unknown" (parseMemoryMetric "rss")
  expectTrue "metric render darwin"
    (renderMemoryMetric .darwinPhysFootprintAggregate == "darwinPhysFootprintAggregate")
  expectTrue "metric render linux proc rss"
    (renderMemoryMetric .linuxProcRssAggregate == "linuxProcRssAggregate")
  expectTrue "metric render linux"
    (renderMemoryMetric .linuxCgroupMemoryCurrent == "linuxCgroupMemoryCurrent")
  expectTrue "metric render job"
    (renderMemoryMetric .jobObjectCommitAggregate == "jobObjectCommitAggregate")

private def testResourceHardMaxima : IO Unit := do
  let fe := hardFrontendProfile
  let core := hardCoreProfile
  let tool := hardToolProfile
  let out := hardOutputProfile
  expectOk "hard frontend validates" (validateResourceProfileV1 fe) ()
  expectOk "hard core validates" (validateResourceProfileV1 core) ()
  expectOk "hard tool validates" (validateResourceProfileV1 tool) ()
  expectOk "hard output validates" (validateResourceProfileV1 out) ()
  expectTrue "frontend wall" (fe.maxWallMillis == 10000)
  expectTrue "frontend mem 2GiB" (fe.maxAggregateMemoryBytes == 2147483648)
  expectTrue "frontend processes" (fe.maxProcesses == 1)
  expectTrue "frontend protocol 64MiB" (fe.maxProtocolBytes == 67108864)
  expectTrue "frontend stderr 64KiB" (fe.maxStderrBytes == 65536)
  expectTrue "frontend published 0" (fe.maxPublishedBytes == 0)
  expectTrue "frontend stage" (fe.stage == .frontend)
  expectTrue "core wall" (core.maxWallMillis == 30000)
  expectTrue "core stage" (core.stage == .compilerCore)
  expectTrue "tool wall" (tool.maxWallMillis == 600000)
  expectTrue "tool mem 4GiB" (tool.maxAggregateMemoryBytes == 4294967296)
  expectTrue "tool processes" (tool.maxProcesses == 8)
  expectTrue "tool stage" (tool.stage == .externalTool)
  expectTrue "output wall" (out.maxWallMillis == 60000)
  expectTrue "output protocol 1MiB" (out.maxProtocolBytes == 1048576)
  expectTrue "output published 256MiB" (out.maxPublishedBytes == 268435456)
  expectTrue "output stage" (out.stage == .artifactOutput)
  expectTrue "schema id"
    (fe.schema.value == "proof-forge.resource-profile.v1")
  expectTrue "frontend profile id"
    (fe.profileId.value == "proof-forge.resource.frontend.v1")
  expectTrue "core profile id"
    (core.profileId.value == "proof-forge.resource.core.v1")
  expectTrue "tool profile id"
    (tool.profileId.value == "proof-forge.resource.tool.v1")
  expectTrue "output profile id"
    (out.profileId.value == "proof-forge.resource.output.v1")

private def testResourceLowerOnly : IO Unit := do
  let hard := hardFrontendProfile
  -- Equal to hard accepted.
  expectOk "lower-only equal hard"
    (validateLowerOnlyResourceProfile hard hard) ()
  -- Strictly lower positive values accepted for nonzero hard fields.
  let lower : ResourceProfileV1 :=
    { hard with
      maxWallMillis := 1
      maxAggregateMemoryBytes := 1
      maxProcesses := 1
      maxProtocolBytes := 1
      maxStderrBytes := 1
      maxPublishedBytes := 0 }
  expectOk "lower-only positive below hard"
    (validateLowerOnlyResourceProfile hard lower) ()
  -- Cannot raise any budget.
  expectErr "lower-only rejects higher wall"
    (validateLowerOnlyResourceProfile hard { hard with maxWallMillis := 10001 })
  expectErr "lower-only rejects higher memory"
    (validateLowerOnlyResourceProfile hard
      { hard with maxAggregateMemoryBytes := 2147483649 })
  expectErr "lower-only rejects higher processes"
    (validateLowerOnlyResourceProfile hard { hard with maxProcesses := 2 })
  expectErr "lower-only rejects higher protocol"
    (validateLowerOnlyResourceProfile hard
      { hard with maxProtocolBytes := hard.maxProtocolBytes + 1 })
  expectErr "lower-only rejects higher stderr"
    (validateLowerOnlyResourceProfile hard
      { hard with maxStderrBytes := hard.maxStderrBytes + 1 })
  -- hard published = 0 ⇒ effective must stay 0 (not "unlimited").
  expectErr "lower-only zero hard forces zero effective published"
    (validateLowerOnlyResourceProfile hard { hard with maxPublishedBytes := 1 })
  expectOk "lower-only zero hard with zero effective"
    (validateLowerOnlyResourceProfile hard { hard with maxPublishedBytes := 0 }) ()
  expectErr "lower-only rejects published bytes above output hard maximum"
    (validateLowerOnlyResourceProfile hardOutputProfile
      { hardOutputProfile with
        maxPublishedBytes := hardOutputProfile.maxPublishedBytes + 1 })
  -- Zero is not allowed for nonzero hard budgets (must be positive when hard > 0).
  expectErr "lower-only rejects zero wall when hard > 0"
    (validateLowerOnlyResourceProfile hard { hard with maxWallMillis := 0 })
  expectErr "lower-only rejects zero protocol when hard > 0"
    (validateLowerOnlyResourceProfile hard { hard with maxProtocolBytes := 0 })
  expectErr "lower-only rejects stage mismatch"
    (validateLowerOnlyResourceProfile hard
      { hard with stage := .compilerCore })
  expectErr "lower-only rejects schema mismatch"
    (validateLowerOnlyResourceProfile hard
      { hard with schema := { value := "proof-forge.other.v1" } })
  expectErr "lower-only rejects profile id mismatch"
    (validateLowerOnlyResourceProfile hard
      { hard with profileId := { value := "proof-forge.resource.other.v1" } })
  expectErr "lower-only rejects memory metric mismatch"
    (validateLowerOnlyResourceProfile hard
      { hard with memoryMetric := .linuxCgroupMemoryCurrent })

private def testResourceValidation : IO Unit := do
  let hard := hardFrontendProfile
  expectErr "profile rejects wrong schema string"
    (validateResourceProfileV1
      { hard with schema := { value := "proof-forge.resource.frontend.v1" } })
  expectErr "profile rejects empty profile id"
    (validateResourceProfileV1
      { hard with profileId := { value := "" } })
  expectErr "profile rejects bad profile id grammar"
    (validateResourceProfileV1
      { hard with profileId := { value := "Not_Valid" } })
  expectErr "profile rejects zero wall budget"
    (validateResourceProfileV1 { hard with maxWallMillis := 0 })
  expectErr "profile rejects zero process budget"
    (validateResourceProfileV1 { hard with maxProcesses := 0 })
  -- Same profileId with different metric remains structurally valid as a value,
  -- but digest must differ (identity is not ID-only).
  let otherMetric := { hard with memoryMetric := .linuxCgroupMemoryCurrent }
  expectOk "profile other metric validates" (validateResourceProfileV1 otherMetric) ()
  match resourceProfileDigest hard, resourceProfileDigest otherMetric with
  | .ok d1, .ok d2 =>
    expectTrue "profile metric changes digest" (d1 != d2)
  | _, _ => throw <| IO.userError "profile metric digest compare failed"

private def testResourceJcsAndDigest : IO Unit := do
  expectOk "frontend jcs golden"
    (renderResourceProfileJcs hardFrontendProfile) frontendHardJcs
  expectOk "core jcs golden"
    (renderResourceProfileJcs hardCoreProfile) coreHardJcs
  expectOk "tool jcs golden"
    (renderResourceProfileJcs hardToolProfile) toolHardJcs
  expectOk "output jcs golden"
    (renderResourceProfileJcs hardOutputProfile) outputHardJcs
  expectOk "frontend resource exact JCS parse"
    (parseResourceProfileJcs frontendHardJcs) hardFrontendProfile
  expectOk "core resource exact JCS parse"
    (parseResourceProfileJcs coreHardJcs) hardCoreProfile
  expectOk "tool resource exact JCS parse"
    (parseResourceProfileJcs toolHardJcs) hardToolProfile
  expectOk "output resource exact JCS parse"
    (parseResourceProfileJcs outputHardJcs) hardOutputProfile
  let frontendBody := String.ofList frontendHardJcs.toList.tail
  expectErr "resource JCS duplicate field"
    (parseResourceProfileJcs
      ("{\"maxAggregateMemoryBytes\":2147483648," ++ frontendBody))
  expectErr "resource JCS unknown field"
    (parseResourceProfileJcs ("{\"extra\":0," ++ frontendBody))
  expectErr "resource JCS missing fields"
    (parseResourceProfileJcs
      "{\"schema\":\"proof-forge.resource-profile.v1\"}")
  -- Pretty / unsorted / alternate spellings are not the wire form.
  expectErr "jcs parse rejects pretty resource object"
    (parsePfJcs "{\n  \"schema\": \"proof-forge.resource-profile.v1\"\n}")
  -- Digest = domainSeparatedSha256(schema domain tag, UTF-8(JCS)).
  match resourceProfileDigest hardFrontendProfile,
        domainSeparatedSha256
          "proof-forge.resource-profile.v1" (utf8Bytes frontendHardJcs) with
  | .ok d1, .ok d2 =>
    expectTrue "frontend digest matches domain(JCS)" (d1 == d2)
    match digestFromHex frontendHardDigestHex with
    | .ok want => expectTrue "frontend digest independent fixed KAT" (d1 == want)
    | .error e => throw <| IO.userError s!"frontend digest fixture: {e}"
  | _, _ => throw <| IO.userError "frontend digest domain link failed"
  match resourceProfileDigest hardFrontendProfile,
        resourceProfileDigest hardCoreProfile with
  | .ok d1, .ok d2 =>
    expectTrue "frontend/core digests differ" (d1 != d2)
  | _, _ => throw <| IO.userError "frontend/core digest compare failed"
  -- Digest must not depend on pretty printing; only exact JCS bytes.
  match domainSeparatedSha256
          "proof-forge.resource-profile.v1" (utf8Bytes frontendHardJcs),
        domainSeparatedSha256
          "proof-forge.resource-profile.v1"
          (utf8Bytes (frontendHardJcs ++ " ")) with
  | .ok d1, .ok d2 =>
    expectTrue "trailing space changes domain digest" (d1 != d2)
  | _, _ => throw <| IO.userError "jcs space domain compare failed"

-- ---------------------------------------------------------------------------
-- Runner
-- ---------------------------------------------------------------------------

def run : IO Unit := do
  testProjectRelativePath
  testQualifiedName
  testIdentifierComponent
  testContentRef
  testSourceOrigin
  testPfJcs
  testDomainHash
  testResourceStageMetricWires
  testResourceHardMaxima
  testResourceLowerOnly
  testResourceValidation
  testResourceJcsAndDigest
  IO.println "Tests.Core.CommonRemaining: ok"

end Tests.Core.CommonRemaining
