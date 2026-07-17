import ProofForgeV2.Core.Common

namespace Tests.Core.CommonScalars

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

private def repeated (count : Nat) (value : Char) : String :=
  String.ofList (List.replicate count value)

private def testNonEmptyArray : IO Unit := do
  expectErr "nonempty rejects empty" (NonEmptyArray.ofArray (#[] : Array Nat))
  match NonEmptyArray.ofArray #[7] with
  | .ok values =>
    unless values.toArray == #[7] do
      throw <| IO.userError "nonempty singleton roundtrip mismatch"
  | .error e => throw <| IO.userError s!"nonempty singleton rejected: {e}"
  match NonEmptyArray.ofArray #[1, 2, 3] with
  | .ok values =>
    unless values.head == 1 && values.tail == #[2, 3] && values.toArray == #[1, 2, 3] do
      throw <| IO.userError "nonempty array did not preserve declaration order"
  | .error e => throw <| IO.userError s!"nonempty multi rejected: {e}"

private def testSchemaId : IO Unit := do
  expectOk "schema minimum" (parseSchemaId "a.a") { value := "a.a" }
  expectOk "schema representative" (parseSchemaId "proof-forge.output.v1")
    { value := "proof-forge.output.v1" }
  let maxValue := "a." ++ repeated 125 'a'
  expectOk "schema maximum bytes" (parseSchemaId maxValue) { value := maxValue }
  expectErr "schema empty" (parseSchemaId "")
  expectErr "schema over maximum" (parseSchemaId ("a." ++ repeated 126 'a'))
  expectErr "schema requires dot" (parseSchemaId "alpha")
  expectErr "schema uppercase" (parseSchemaId "a.B")
  expectErr "schema non-ascii letter" (parseSchemaId "a.α")
  expectErr "schema fullwidth letter" (parseSchemaId "a.ａ")
  expectErr "schema empty segment" (parseSchemaId "a..b")
  expectErr "schema leading hyphen" (parseSchemaId "a.-b")
  expectErr "schema trailing hyphen" (parseSchemaId "a.b-")
  expectErr "schema consecutive hyphen" (parseSchemaId "a.b--c")
  expectErr "schema renderer validates direct construction"
    (renderSchemaId { value := "invalid" })

private def testAcceptanceProfileId : IO Unit := do
  expectOk "profile minimum" (parseAcceptanceProfileId "a") { value := "a" }
  expectOk "profile representative" (parseAcceptanceProfileId "proof-forge.acceptance.v1")
    { value := "proof-forge.acceptance.v1" }
  let maxValue := "a" ++ repeated 126 'a'
  expectOk "profile maximum bytes" (parseAcceptanceProfileId maxValue) { value := maxValue }
  expectErr "profile empty" (parseAcceptanceProfileId "")
  expectErr "profile over maximum" (parseAcceptanceProfileId ("a" ++ repeated 127 'a'))
  expectErr "profile leading digit" (parseAcceptanceProfileId "1alpha")
  expectErr "profile uppercase" (parseAcceptanceProfileId "Alpha")
  expectErr "profile non-ascii letter" (parseAcceptanceProfileId "α")
  expectErr "profile trailing separator" (parseAcceptanceProfileId "alpha-")
  expectErr "profile consecutive separators" (parseAcceptanceProfileId "alpha-.beta")
  expectErr "profile renderer validates direct construction"
    (renderAcceptanceProfileId { value := "Alpha" })

private def testEvidenceId : IO Unit := do
  expectOk "evidence leap day" (parseEvidenceId "EV-20240229-0000")
    { value := "EV-20240229-0000" }
  expectOk "evidence Gregorian 2000 leap day" (parseEvidenceId "EV-20000229-9999")
    { value := "EV-20000229-9999" }
  expectOk "evidence maximum date and sequence" (parseEvidenceId "EV-99991231-9999")
    { value := "EV-99991231-9999" }
  expectErr "evidence empty" (parseEvidenceId "")
  expectErr "evidence 1900 non-leap" (parseEvidenceId "EV-19000229-0001")
  expectErr "evidence 2023 non-leap" (parseEvidenceId "EV-20230229-0001")
  expectErr "evidence month zero" (parseEvidenceId "EV-20230001-0001")
  expectErr "evidence day zero" (parseEvidenceId "EV-20240100-0001")
  expectErr "evidence April 31" (parseEvidenceId "EV-20240431-0001")
  expectErr "evidence lowercase prefix" (parseEvidenceId "ev-20240101-0001")
  expectErr "evidence wrong sequence width" (parseEvidenceId "EV-20240101-001")
  expectErr "evidence over width" (parseEvidenceId "EV-20240101-00000")
  expectErr "evidence non-ascii digits" (parseEvidenceId "EV-2024٠١٠١-0001")
  expectErr "evidence renderer validates direct construction"
    (renderEvidenceId { value := "EV-20230229-0001" })

private def testUtcInstant : IO Unit := do
  expectOk "utc epoch-style minimum year" (parseUtcInstant "0000-01-01T00:00:00Z")
    { value := "0000-01-01T00:00:00Z" }
  expectOk "utc leap day" (parseUtcInstant "2024-02-29T23:59:59Z")
    { value := "2024-02-29T23:59:59Z" }
  expectOk "utc maximum" (parseUtcInstant "9999-12-31T23:59:59Z")
    { value := "9999-12-31T23:59:59Z" }
  expectErr "utc empty" (parseUtcInstant "")
  expectErr "utc invalid day" (parseUtcInstant "2023-02-29T00:00:00Z")
  expectErr "utc month over" (parseUtcInstant "2024-13-01T00:00:00Z")
  expectErr "utc day over" (parseUtcInstant "2024-01-32T00:00:00Z")
  expectErr "utc April 31" (parseUtcInstant "2024-04-31T00:00:00Z")
  expectErr "utc invalid hour" (parseUtcInstant "2024-01-01T24:00:00Z")
  expectErr "utc invalid minute" (parseUtcInstant "2024-01-01T00:60:00Z")
  expectErr "utc leap second" (parseUtcInstant "2024-01-01T00:00:60Z")
  expectErr "utc fraction" (parseUtcInstant "2024-01-01T00:00:00.0Z")
  expectErr "utc offset" (parseUtcInstant "2024-01-01T00:00:00+00:00")
  expectErr "utc lowercase separators" (parseUtcInstant "2024-01-01t00:00:00z")
  expectErr "utc non-ascii digits" (parseUtcInstant "2024-01-01T00:00:٠٠Z")
  expectErr "utc renderer validates direct construction"
    (renderUtcInstant { value := "2024-01-01T24:00:00Z" })

private def testNodeId : IO Unit := do
  let raw := ByteArray.mk #[
    0x00, 0x09, 0x0a, 0x0f, 0x10, 0x7f, 0x80, 0xff,
    0x00, 0x09, 0x0a, 0x0f, 0x10, 0x7f, 0x80, 0xff]
  let wire := "nodeid:00090a0f107f80ff00090a0f107f80ff"
  match parseNodeId wire with
  | .ok nodeId =>
    unless nodeId.bytes == raw do
      throw <| IO.userError "node id raw bytes mismatch"
    expectOk "node id render" (renderNodeId nodeId) wire
  | .error e => throw <| IO.userError s!"node id golden rejected: {e}"
  expectOk "node id direct raw golden" (renderNodeId { bytes := raw }) wire
  expectErr "node id empty" (parseNodeId "")
  expectErr "node id bad tag" (parseNodeId "node:00090a0f107f80ff00090a0f107f80ff")
  expectErr "node id uppercase" (parseNodeId "nodeid:00090A0F107F80FF00090a0f107f80ff")
  expectErr "node id invalid hex" (parseNodeId "nodeid:g0090a0f107f80ff00090a0f107f80ff")
  expectErr "node id short" (parseNodeId "nodeid:00")
  expectErr "node id long" (parseNodeId "nodeid:00090a0f107f80ff00090a0f107f80ff00")
  expectErr "node id renderer rejects 15 bytes"
    (renderNodeId { bytes := ByteArray.mk (Array.replicate 15 0) })
  expectErr "node id renderer rejects 17 bytes"
    (renderNodeId { bytes := ByteArray.mk (Array.replicate 17 0) })

private def testEnums : IO Unit := do
  let documentWires := #[
    ("not_started", DocumentStatus.notStarted),
    ("draft", .draft),
    ("proposed", .proposed),
    ("in_review", .inReview),
    ("accepted", .accepted),
    ("superseded", .superseded),
    ("archived", .archived)]
  for index in [:documentWires.size] do
    let (wire, status) := documentWires[index]!
    expectOk s!"document status parse {wire}" (parseDocumentStatus wire) status
    unless renderDocumentStatus status == wire && documentStatusRank status == index do
      throw <| IO.userError s!"document status wire/rank mismatch for {wire}"
  expectErr "document status unknown" (parseDocumentStatus "in-review")
  expectErr "document status empty" (parseDocumentStatus "")
  expectErr "document status uppercase" (parseDocumentStatus "DRAFT")
  expectErr "document status whitespace" (parseDocumentStatus " draft")
  let deployabilityWires := #[
    ("deployable", ArtifactDeployability.deployable),
    ("verifiable-workload", .verifiableWorkload),
    ("intermediate-only", .intermediateOnly),
    ("non-deployable", .nonDeployable)]
  for index in [:deployabilityWires.size] do
    let (wire, value) := deployabilityWires[index]!
    expectOk s!"deployability parse {wire}" (parseArtifactDeployability wire) value
    unless renderArtifactDeployability value == wire && artifactDeployabilityRank value == index do
      throw <| IO.userError s!"deployability wire/rank mismatch for {wire}"
  expectErr "deployability unknown" (parseArtifactDeployability "non_deployable")
  expectErr "deployability empty" (parseArtifactDeployability "")
  expectErr "deployability uppercase" (parseArtifactDeployability "DEPLOYABLE")
  expectErr "deployability whitespace" (parseArtifactDeployability "deployable ")

def run : IO Unit := do
  testNonEmptyArray
  testSchemaId
  testAcceptanceProfileId
  testEvidenceId
  testUtcInstant
  testNodeId
  testEnums
  IO.println "Tests.Core.CommonScalars: ok"

end Tests.Core.CommonScalars
