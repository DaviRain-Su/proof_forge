/-
  Tests.Core.DiagnosticV1 — focused tests for the typed diagnostic carrier.

  Covers:
    - wire uniqueness for the closed code enum
    - stable priority order for the closed code enum
    - human rendering golden strings matching existing `PF-*: message` output
    - canonical PF-JCS JSON exactness, deterministic re-rendering, and escaping
    - multi-origin serialization with normalized origin order
    - `SourceOrigin` JCS codec round-trip
    - total ordering, transitivity, origin-content tie-breaking,
      origin-array length tie-breaking, and origin deduplication
    - `sortAndDedupe` idempotence/dedupe
    - redaction: absolute host paths, inverted byte ranges, and malformed node ids
      are rejected by origin validation
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1

namespace Tests.Core.DiagnosticV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1

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

private def makeOrigin (path : String) (startByte endByte : Nat) (nodeHex : String) : IO SourceOrigin := do
  match parseProjectRelativePath path, parseNodeId s!"nodeid:{nodeHex}" with
  | .ok sourcePath, .ok nodeId =>
    pure {
      sourcePath,
      startByte := UInt64.ofNat startByte,
      endByte := UInt64.ofNat endByte,
      nodeId
    }
  | .error e, _ => throw <| IO.userError s!"origin path parse failed for {path}: {e}"
  | _, .error e => throw <| IO.userError s!"origin node id parse failed for {nodeHex}: {e}"

private def containsSubstr (s sub : String) : Bool :=
  let rec loop (cs : List Char) : Bool :=
    match cs with
    | [] => sub.isEmpty
    | _ :: rest =>
      if sub.toList.isPrefixOf cs then true else loop rest
  loop s.toList

private def codeWireGolden : Array (DiagnosticCodeV1 × String) := #[
  (.sourceInvalid, "PF-SRC-INVALID"),
  (.resourceBound, "PF-BOUND-001"),
  (.toolchainMissing, "PF-TOOLCHAIN-MISSING"),
  (.toolchainMismatch, "PF-TOOLCHAIN-MISMATCH"),
  (.targetNotImplemented, "PF-TARGET-NOT-IMPLEMENTED"),
  (.outputAtomicity, "PF-OUTPUT-ATOMICITY"),
  (.internal, "PF-INTERNAL")
]

private def testWireUniqueness : IO Unit := do
  let wires := codeWireGolden.map (·.2)
  for i in [0:wires.size] do
    for j in [i+1:wires.size] do
      if wires[i]! == wires[j]! then
        throw <| IO.userError s!"wire strings at {i} and {j} are not unique"

private def testCodeRank : IO Unit := do
  let expected := #[0, 1, 2, 3, 4, 5, 6]
  let got := codeWireGolden.map fun (code, _) => DiagnosticCodeV1.rank code
  unless got == expected do
    throw <| IO.userError s!"code rank order mismatch: expected {repr expected}, got {repr got}"

private def testHumanRendering : IO Unit := do
  for (code, wire) in codeWireGolden do
    let diag := { code := code, message := "msg", origins := #[] : DiagnosticV1 }
    let rendered := diag.renderHuman
    let expected := s!"{wire}: msg"
    unless rendered == expected do
      throw <| IO.userError s!"human render for {wire}: expected {repr expected}, got {repr rendered}"

private def testCanonicalJsonExactness : IO Unit := do
  let withoutOrigins : DiagnosticV1 := {
    code := .sourceInvalid,
    message := "source is invalid",
    origins := #[]
  }
  let withoutGolden :=
    "{\"code\":\"PF-SRC-INVALID\",\"message\":\"source is invalid\",\"origins\":[],\"schemaVersion\":1}"
  expectOk "json without origins" (withoutOrigins.toCanonicalJson) withoutGolden

  let origin ← makeOrigin "Counter.lean" 10 20 "00000000000000000000000000000001"
  let withOrigin : DiagnosticV1 := { code := .sourceInvalid, message := "bad", origins := #[origin] }
  let withOriginGolden :=
    "{\"code\":\"PF-SRC-INVALID\",\"message\":\"bad\",\"origins\":[{\"endByte\":20,\"nodeId\":\"nodeid:00000000000000000000000000000001\",\"sourcePath\":\"Counter.lean\",\"startByte\":10}],\"schemaVersion\":1}"
  match withOrigin.toCanonicalJson with
  | .ok rendered =>
    unless rendered == withOriginGolden do
      throw <| IO.userError s!"json with origin golden mismatch: {repr rendered}"
    -- Deterministic re-rendering.
    match parsePfJcs rendered with
    | .ok value =>
      match renderPfJcs value with
      | .ok rendered2 =>
        unless rendered2 == rendered do
          throw <| IO.userError "re-render changed canonical bytes"
      | .error e => throw <| IO.userError s!"re-render failed: {e}"
    | .error e => throw <| IO.userError s!"parse of canonical json failed: {e}"
    -- Exact field set/order check.
    match parsePfJcs rendered with
    | .ok (.object #[
        ("code", .string "PF-SRC-INVALID"),
        ("message", .string "bad"),
        ("origins", .array #[.object #[
          ("endByte", .int 20),
          ("nodeId", .string "nodeid:00000000000000000000000000000001"),
          ("sourcePath", .string "Counter.lean"),
          ("startByte", .int 10)
        ]]),
        ("schemaVersion", .int 1)
      ]) => pure ()
    | .ok other =>
      throw <| IO.userError s!"unexpected parsed shape: {repr other}"
    | .error e => throw <| IO.userError s!"shape parse failed: {e}"
  | .error e => throw <| IO.userError s!"json with origin render failed: {e}"

private def testCanonicalJsonEscaping : IO Unit := do
  let origin ← makeOrigin "Counter.lean" 0 1 "00000000000000000000000000000001"
  let originalMessage := "quote\" backslash\\ newline\n tab\t control\x01 end"
  let diag : DiagnosticV1 := {
    code := .sourceInvalid,
    message := originalMessage,
    origins := #[origin]
  }
  match diag.toCanonicalJson with
  | .ok rendered =>
    unless containsSubstr rendered "\\\"" do
      throw <| IO.userError "escaped quote not found in rendered json"
    unless containsSubstr rendered "\\\\" do
      throw <| IO.userError "escaped backslash not found in rendered json"
    unless containsSubstr rendered "\\n" do
      throw <| IO.userError "escaped newline not found in rendered json"
    unless containsSubstr rendered "\\t" do
      throw <| IO.userError "escaped tab not found in rendered json"
    unless containsSubstr rendered "\\u0001" do
      throw <| IO.userError "escaped control character not found in rendered json"
    match parsePfJcs rendered with
    | .ok (.object #[
        ("code", _),
        ("message", .string parsedMessage),
        ("origins", _),
        ("schemaVersion", _)
      ]) =>
        unless parsedMessage == originalMessage do
          throw <| IO.userError s!"escaped message round-trip mismatch: {repr parsedMessage}"
    | .ok other =>
      throw <| IO.userError s!"unexpected parsed shape for escaped message: {repr other}"
    | .error e => throw <| IO.userError s!"parse of escaped json failed: {e}"
  | .error e => throw <| IO.userError s!"json escaping render failed: {e}"

private def testMultiOriginCanonicalJson : IO Unit := do
  let o2 ← makeOrigin "B.lean" 30 40 "00000000000000000000000000000002"
  let o1 ← makeOrigin "A.lean" 10 20 "00000000000000000000000000000001"
  let diag : DiagnosticV1 := { code := .sourceInvalid, message := "multi", origins := #[o2, o1] }
  match diag.toCanonicalJson with
  | .ok rendered =>
    match parsePfJcs rendered with
    | .ok (.object #[
        ("code", .string "PF-SRC-INVALID"),
        ("message", .string "multi"),
        ("origins", .array #[
          .object #[
            ("endByte", .int 20),
            ("nodeId", .string "nodeid:00000000000000000000000000000001"),
            ("sourcePath", .string "A.lean"),
            ("startByte", .int 10)
          ],
          .object #[
            ("endByte", .int 40),
            ("nodeId", .string "nodeid:00000000000000000000000000000002"),
            ("sourcePath", .string "B.lean"),
            ("startByte", .int 30)
          ]
        ]),
        ("schemaVersion", .int 1)
      ]) => pure ()
    | .ok other =>
      throw <| IO.userError s!"multi-origin shape mismatch: {repr other}"
    | .error e => throw <| IO.userError s!"multi-origin parse failed: {e}"
  | .error e => throw <| IO.userError s!"multi-origin render failed: {e}"

private def testOriginRoundTrip : IO Unit := do
  let origin ← makeOrigin "Counter.lean" 10 20 "00000000000000000000000000000001"
  match renderSourceOriginJcs origin with
  | .ok text =>
    expectOk "origin round-trip" (parseSourceOriginJcs text) origin
  | .error e => throw <| IO.userError s!"origin render failed: {e}"

private def testOrdering : IO Unit := do
  let a : DiagnosticV1 := { code := .sourceInvalid, message := "a", origins := #[] }
  let b : DiagnosticV1 := { code := .sourceInvalid, message := "b", origins := #[] }
  let c : DiagnosticV1 := { code := .toolchainMissing, message := "z", origins := #[] }

  unless DiagnosticV1.compare a b == .lt do
    throw <| IO.userError "expected a < b by message"
  unless DiagnosticV1.compare b a == .gt do
    throw <| IO.userError "expected b > a by message"
  unless DiagnosticV1.compare a a == .eq do
    throw <| IO.userError "expected a == a"

  -- Code rank dominates message when origins are empty.
  unless DiagnosticV1.compare c a == .gt do
    throw <| IO.userError "expected c > a by code rank"

  -- Transitivity on the adversarial triple.
  unless DiagnosticV1.compare a c == .lt && DiagnosticV1.compare b c == .lt do
    throw <| IO.userError "expected transitivity a < c and b < c"

  -- Origin content breaks ties before code rank.
  let oA ← makeOrigin "A.lean" 10 20 "00000000000000000000000000000001"
  let oB ← makeOrigin "B.lean" 10 20 "00000000000000000000000000000002"
  let diagA : DiagnosticV1 := { code := .sourceInvalid, message := "x", origins := #[oA] }
  let diagB : DiagnosticV1 := { code := .sourceInvalid, message := "x", origins := #[oB] }
  unless DiagnosticV1.compare diagA diagB == .lt do
    throw <| IO.userError "expected diagA < diagB by sourcePath"

  -- Shorter origin list breaks ties after normalized origins.
  let o1 ← makeOrigin "Counter.lean" 10 20 "00000000000000000000000000000001"
  let o2 ← makeOrigin "Counter.lean" 30 40 "00000000000000000000000000000002"
  let left : DiagnosticV1 := { code := .sourceInvalid, message := "x", origins := #[o1] }
  let right : DiagnosticV1 := { code := .sourceInvalid, message := "x", origins := #[o1, o2] }
  unless DiagnosticV1.compare left right == .lt do
    throw <| IO.userError "expected shorter origin list to compare less"

  -- Duplicate origins normalize away.
  let dupRight : DiagnosticV1 := { code := .sourceInvalid, message := "x", origins := #[o1, o1] }
  unless DiagnosticV1.compare left dupRight == .eq do
    throw <| IO.userError "expected duplicate origins to compare equal after normalization"

private def testSortAndDedupe : IO Unit := do
  let a : DiagnosticV1 := { code := .sourceInvalid, message := "a", origins := #[] }
  let b : DiagnosticV1 := { code := .sourceInvalid, message := "b", origins := #[] }
  let arr := #[b, a, a]
  let sorted := DiagnosticV1.sortAndDedupe arr
  unless sorted.size == 2 do
    throw <| IO.userError s!"dedupe expected size 2, got {sorted.size}"
  unless sorted[0]! == a && sorted[1]! == b do
    throw <| IO.userError "sortAndDedupe produced wrong order"
  let sortedAgain := DiagnosticV1.sortAndDedupe sorted
  unless sorted == sortedAgain do
    throw <| IO.userError "sortAndDedupe is not idempotent"

private def testRedaction : IO Unit := do
  expectErr "absolute path rejected at parser"
    (parseProjectRelativePath "/etc/passwd.lean")
  expectErr "absolute path with backslash rejected at parser"
    (parseProjectRelativePath "C:\\src\\Counter.lean")

  let badPath : ProjectRelativePath := { value := "/etc/passwd.lean" }
  let badNodeId : NodeId := { bytes := ByteArray.mk (Array.replicate 16 0) }
  let badOrigin : SourceOrigin := {
    sourcePath := badPath,
    startByte := 0,
    endByte := 1,
    nodeId := badNodeId
  }
  expectErr "validateSourceOrigin rejects absolute path"
    (validateSourceOrigin badOrigin)
  expectErr "renderSourceOriginJcs rejects absolute path"
    (renderSourceOriginJcs badOrigin)

  let badDiag : DiagnosticV1 := {
    code := .sourceInvalid,
    message := "leak",
    origins := #[badOrigin]
  }
  expectErr "toCanonicalJson redacts absolute origin path"
    (badDiag.toCanonicalJson)

  let validPath ← match parseProjectRelativePath "Counter.lean" with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"valid path parse failed: {e}"

  let badRangeOrigin : SourceOrigin := {
    sourcePath := validPath,
    startByte := 5,
    endByte := 0,
    nodeId := badNodeId
  }
  expectErr "validateSourceOrigin rejects startByte > endByte"
    (validateSourceOrigin badRangeOrigin)
  let badRangeDiag : DiagnosticV1 := {
    code := .sourceInvalid,
    message := "range",
    origins := #[badRangeOrigin]
  }
  expectErr "toCanonicalJson rejects startByte > endByte"
    (badRangeDiag.toCanonicalJson)

  let badNodeOrigin : SourceOrigin := {
    sourcePath := validPath,
    startByte := 0,
    endByte := 1,
    nodeId := { bytes := ByteArray.mk (Array.replicate 15 0) }
  }
  expectErr "validateSourceOrigin rejects bad nodeId length"
    (validateSourceOrigin badNodeOrigin)
  let badNodeDiag : DiagnosticV1 := {
    code := .sourceInvalid,
    message := "node",
    origins := #[badNodeOrigin]
  }
  expectErr "toCanonicalJson rejects bad nodeId length"
    (badNodeDiag.toCanonicalJson)

def run : IO Unit := do
  testWireUniqueness
  testCodeRank
  testHumanRendering
  testCanonicalJsonExactness
  testCanonicalJsonEscaping
  testMultiOriginCanonicalJson
  testOriginRoundTrip
  testOrdering
  testSortAndDedupe
  testRedaction
  IO.println "Tests.Core.DiagnosticV1: ok"

end Tests.Core.DiagnosticV1
