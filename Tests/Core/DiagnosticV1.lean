/-
  Tests.Core.DiagnosticV1 — SPEC-DIAG-001 / ADR-0022 structured diagnostic carrier.

  Covers:
    - full closed code catalog uniqueness (wire + rank + default severity/phase)
    - DiagnosticOriginV1 nullable nodeId and related total order
    - exact all-field PF-JCS encode/decode + unknown/trailing/noncanonical reject
    - message-independent order/dedupe
    - structural redaction (paths/ranges/node ids)
    - normalizeDiagnosticBundleV1 cap 100/101/200/idempotent PF-DIAG-LIMIT
    - renderHuman remains `CODE: message`
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.DiagnosticV1

namespace Tests.Core.DiagnosticV1

open ProofForgeV2
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

private def containsSubstr (s sub : String) : Bool :=
  let rec loop (cs : List Char) : Bool :=
    match cs with
    | [] => sub.isEmpty
    | _ :: rest =>
      if sub.toList.isPrefixOf cs then true else loop rest
  loop s.toList

private def makeOrigin (path : String) (startByte endByte : Nat)
    (nodeHex? : Option String) : IO DiagnosticOriginV1 := do
  match parseProjectRelativePath path with
  | .error e => throw <| IO.userError s!"origin path parse failed for {path}: {e}"
  | .ok sourcePath =>
    let nodeId ← match nodeHex? with
      | none => pure none
      | some nodeHex =>
        match parseNodeId s!"nodeid:{nodeHex}" with
        | .ok n => pure (some n)
        | .error e => throw <| IO.userError s!"origin node id parse failed: {e}"
    pure {
      sourcePath,
      startByte := UInt64.ofNat startByte,
      endByte := UInt64.ofNat endByte,
      nodeId
    }

private def zeroDigest : Digest :=
  { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 32 (0 : UInt8)) }

private def codeWireGolden : Array (DiagnosticCodeV1 × String × Nat ×
    DiagnosticSeverityV1 × DiagnosticPhaseV1) :=
  DiagnosticCodeV1.all.map fun code =>
    (code, code.wire, code.rank, code.defaultSeverity, code.defaultPhase)

private def testCatalogUniqueness : IO Unit := do
  let codes := DiagnosticCodeV1.all
  unless codes.size == 59 do
    throw <| IO.userError s!"catalog size: expected 59, got {codes.size}"
  let wires := codes.map (·.wire)
  for i in [0:wires.size] do
    for j in [i+1:wires.size] do
      if wires[i]! == wires[j]! then
        throw <| IO.userError s!"wire strings at {i} and {j} are not unique"
  -- Ranks are exact 0..n-1 in table order.
  for i in [0:codes.size] do
    unless codes[i]!.rank == i do
      throw <| IO.userError
        s!"rank mismatch at {i}: {codes[i]!.wire} rank={codes[i]!.rank}"
  -- Default severity is error for every catalog code.
  for code in codes do
    unless code.defaultSeverity == .error do
      throw <| IO.userError s!"default severity for {code.wire} is not error"
  -- Default phase is one of the closed phase enum (validated by type); spot-check
  -- representative families.
  unless DiagnosticCodeV1.sourceInvalid.defaultPhase == .source do
    throw <| IO.userError "PF-SRC-INVALID default phase must be source"
  unless DiagnosticCodeV1.type001.defaultPhase == .type do
    throw <| IO.userError "PF-TYPE-001 default phase must be type"
  unless DiagnosticCodeV1.effectDisallowed.defaultPhase == .effect do
    throw <| IO.userError "PF-EFFECT-001 default phase must be effect"
  unless DiagnosticCodeV1.visibilityViolation.defaultPhase == .effect do
    throw <| IO.userError "PF-VIS-001 default phase must be effect"
  unless DiagnosticCodeV1.semanticsMismatch.defaultPhase == .semantic do
    throw <| IO.userError "PF-SEMANTICS-MISMATCH default phase must be semantic"
  unless DiagnosticCodeV1.targetUnknown.defaultPhase == .resolve do
    throw <| IO.userError "PF-TARGET-UNKNOWN default phase must be resolve"
  unless DiagnosticCodeV1.planInvariant.defaultPhase == .plan do
    throw <| IO.userError "PF-PLAN-INVARIANT default phase must be plan"
  unless DiagnosticCodeV1.lowerInvariant.defaultPhase == .lower do
    throw <| IO.userError "PF-LOWER-INVARIANT default phase must be lower"
  unless DiagnosticCodeV1.outputAtomicity.defaultPhase == .emit do
    throw <| IO.userError "PF-OUTPUT-ATOMICITY default phase must be emit"
  unless DiagnosticCodeV1.toolchainMissing.defaultPhase == .tool do
    throw <| IO.userError "PF-TOOLCHAIN-MISSING default phase must be tool"
  unless DiagnosticCodeV1.diagLimit.defaultPhase == .tool do
    throw <| IO.userError "PF-DIAG-LIMIT default phase must be tool"
  -- Forbidden alpha runtime / CLI codes must not parse (assembled so allowlist
  -- rg on continuous `PF-SEM-*` tokens stays clean in this suite).
  let forbidden := #[
    "PF-" ++ "SEM-UNKNOWN-ENTRY",
    "PF-" ++ "SEM-WRONG-ARITY",
    "PF-" ++ "SEM-ARITHMETIC-OVERFLOW",
    "PF-" ++ "SEM-INVALID-STATE",
    "PF-" ++ "CLI-USAGE",
    "PF-" ++ "OUTPUT-MANIFEST"
  ]
  for bad in forbidden do
    match DiagnosticCodeV1.parse bad with
    | some _ => throw <| IO.userError s!"forbidden code {bad} must not parse"
    | none => pure ()

private def testHumanRendering : IO Unit := do
  for (code, wire, _, _, _) in codeWireGolden do
    let diag := DiagnosticV1.make code "msg"
    let rendered := diag.renderHuman
    let expected := s!"{wire}: msg"
    unless rendered == expected do
      throw <| IO.userError s!"human render for {wire}: expected {repr expected}, got {repr rendered}"

private def testNullableNodeIdAndRelatedOrder : IO Unit := do
  let noneOrigin ← makeOrigin "A.lean" 10 20 none
  let someOrigin ← makeOrigin "A.lean" 10 20
    (some "00000000000000000000000000000001")
  unless DiagnosticOriginV1.compare noneOrigin someOrigin == .lt do
    throw <| IO.userError "none nodeId must compare less than some"
  unless DiagnosticOriginV1.compare someOrigin noneOrigin == .gt do
    throw <| IO.userError "some nodeId must compare greater than none"
  let later ← makeOrigin "A.lean" 10 30 none
  unless DiagnosticOriginV1.compare noneOrigin later == .lt do
    throw <| IO.userError "endByte must participate in origin order"
  let oB ← makeOrigin "B.lean" 0 1 none
  let oA ← makeOrigin "A.lean" 5 6 none
  let oA2 ← makeOrigin "A.lean" 5 6 none
  let diag := DiagnosticV1.make .sourceInvalid "x" (related := #[oB, oA, oA2, oA])
  unless diag.related.size == 2 do
    throw <| IO.userError s!"related normalize expected size 2, got {diag.related.size}"
  unless diag.related[0]! == oA && diag.related[1]! == oB do
    throw <| IO.userError "related must sort by origin total order and dedupe"

private def testCanonicalJsonAllFields : IO Unit := do
  let primary ← makeOrigin "Counter.lean" 10 20
    (some "00000000000000000000000000000001")
  let related ← makeOrigin "Helper.lean" 0 4 none
  let program ← match parseQualifiedName #["Root", "Counter"] with
    | .ok p => pure p
    | .error e => throw <| IO.userError e
  let req : RequirementKeyV1 := {
    id := "state.persistent"
    version := { major := 1, minor := 0, patch := 0 }
    digest := zeroDigest
  }
  let ext : ExtensionKeyV1 := {
    id := "ext.demo"
    version := { major := 0, minor := 1, patch := 0 }
    digest := zeroDigest
  }
  let diag := DiagnosticV1.make .type001 "type mismatch"
    (primary := some primary)
    (related := #[related])
    (program := some program)
    (target := some .evm)
    (requirement := some req)
    (extension := some ext)
    (expected := some (.string "UInt64"))
    (actual := some (.string "Bool"))
    (context := some (.object #[("k", .string "v")]))
    (stableContext := some "type:uint64")
    (suggestion := some "cast explicitly")
  match diag.toCanonicalJson with
  | .error e => throw <| IO.userError s!"encode failed: {e}"
  | .ok rendered =>
    -- All field names present.
    for key in #["actual", "code", "context", "expected", "extension", "message",
        "phase", "primary", "program", "related", "requirement", "schemaVersion",
        "severity", "stableContext", "suggestion", "target"] do
      unless containsSubstr rendered s!"\"{key}\"" do
        throw <| IO.userError s!"missing JSON field {key} in {rendered}"
    unless containsSubstr rendered "\"code\":\"PF-TYPE-001\"" do
      throw <| IO.userError "code wire missing"
    unless containsSubstr rendered "\"severity\":\"error\"" do
      throw <| IO.userError "severity missing"
    unless containsSubstr rendered "\"phase\":\"type\"" do
      throw <| IO.userError "phase missing"
    unless containsSubstr rendered "\"schemaVersion\":1" do
      throw <| IO.userError "schemaVersion missing"
    unless containsSubstr rendered "\"nodeId\":null" do
      throw <| IO.userError "related null nodeId missing"
    unless containsSubstr rendered "nodeid:00000000000000000000000000000001" do
      throw <| IO.userError "primary nodeId missing"
    -- Round-trip.
    match DiagnosticV1.fromCanonicalJson rendered with
    | .error e => throw <| IO.userError s!"decode failed: {e}"
    | .ok decoded =>
      unless decoded.code == diag.code do
        throw <| IO.userError "round-trip code mismatch"
      unless decoded.message == diag.message do
        throw <| IO.userError "round-trip message mismatch"
      unless decoded.primary == diag.primary do
        throw <| IO.userError "round-trip primary mismatch"
      unless decoded.related == diag.related do
        throw <| IO.userError "round-trip related mismatch"
      unless decoded.stableContext == diag.stableContext do
        throw <| IO.userError "round-trip stableContext mismatch"
      unless decoded.target == some .evm do
        throw <| IO.userError "round-trip target mismatch"
      match decoded.toCanonicalJson with
      | .ok rendered2 =>
        unless rendered2 == rendered do
          throw <| IO.userError "re-encode changed canonical bytes"
      | .error e => throw <| IO.userError e

  -- Minimal empty/null fields encode explicitly as null.
  let empty := DiagnosticV1.make .sourceInvalid "source is invalid"
  match empty.toCanonicalJson with
  | .error e => throw <| IO.userError e
  | .ok text =>
    unless containsSubstr text "\"primary\":null" do
      throw <| IO.userError "primary null missing"
    unless containsSubstr text "\"related\":[]" do
      throw <| IO.userError "related empty array missing"
    unless containsSubstr text "\"target\":null" do
      throw <| IO.userError "target null missing"
    unless containsSubstr text "\"stableContext\":null" do
      throw <| IO.userError "stableContext null missing"
    match DiagnosticV1.fromCanonicalJson text with
    | .error e => throw <| IO.userError s!"minimal decode failed: {e}"
    | .ok d =>
      unless d.primary == none && d.related == #[] do
        throw <| IO.userError "minimal round-trip origin mismatch"

private def testDecoderRejects : IO Unit := do
  let empty := DiagnosticV1.make .sourceInvalid "x"
  let base ← match empty.toCanonicalJson with
    | .ok text => pure text
    | .error e => throw <| IO.userError s!"base encode failed: {e}"
  -- Unknown field (append before final `}`).
  let withExtra :=
    if base.endsWith "}" then
      String.ofList base.toList.dropLast ++ ",\"extra\":1}"
    else base ++ ",\"extra\":1}"
  expectErr "unknown field" (DiagnosticV1.fromCanonicalJson withExtra)

  -- Unknown code.
  let badCode :=
    "{\"actual\":null,\"code\":\"PF-NOPE\",\"context\":null,\"expected\":null,\"extension\":null,\"message\":\"x\",\"phase\":\"source\",\"primary\":null,\"program\":null,\"related\":[],\"requirement\":null,\"schemaVersion\":1,\"severity\":\"error\",\"stableContext\":null,\"suggestion\":null,\"target\":null}"
  expectErr "unknown code" (DiagnosticV1.fromCanonicalJson badCode)
  -- Unknown phase.
  let badPhase :=
    "{\"actual\":null,\"code\":\"PF-SRC-INVALID\",\"context\":null,\"expected\":null,\"extension\":null,\"message\":\"x\",\"phase\":\"nope\",\"primary\":null,\"program\":null,\"related\":[],\"requirement\":null,\"schemaVersion\":1,\"severity\":\"error\",\"stableContext\":null,\"suggestion\":null,\"target\":null}"
  expectErr "unknown phase" (DiagnosticV1.fromCanonicalJson badPhase)
  -- Unknown severity.
  let badSev :=
    "{\"actual\":null,\"code\":\"PF-SRC-INVALID\",\"context\":null,\"expected\":null,\"extension\":null,\"message\":\"x\",\"phase\":\"source\",\"primary\":null,\"program\":null,\"related\":[],\"requirement\":null,\"schemaVersion\":1,\"severity\":\"fatal\",\"stableContext\":null,\"suggestion\":null,\"target\":null}"
  expectErr "unknown severity" (DiagnosticV1.fromCanonicalJson badSev)
  -- Bad schemaVersion.
  let badSchema :=
    "{\"actual\":null,\"code\":\"PF-SRC-INVALID\",\"context\":null,\"expected\":null,\"extension\":null,\"message\":\"x\",\"phase\":\"source\",\"primary\":null,\"program\":null,\"related\":[],\"requirement\":null,\"schemaVersion\":2,\"severity\":\"error\",\"stableContext\":null,\"suggestion\":null,\"target\":null}"
  expectErr "bad schema" (DiagnosticV1.fromCanonicalJson badSchema)
  -- Trailing bytes after JSON (parsePfJcs rejects non-canonical).
  expectErr "trailing" (DiagnosticV1.fromCanonicalJson (base ++ " "))
  -- Noncanonical field order / whitespace via alternate spelling.
  let noncanon :=
    "{ \"actual\": null, \"code\": \"PF-SRC-INVALID\", \"context\": null, \"expected\": null, \"extension\": null, \"message\": \"x\", \"phase\": \"source\", \"primary\": null, \"program\": null, \"related\": [], \"requirement\": null, \"schemaVersion\": 1, \"severity\": \"error\", \"stableContext\": null, \"suggestion\": null, \"target\": null }"
  expectErr "noncanonical whitespace" (DiagnosticV1.fromCanonicalJson noncanon)

private def testMessageIndependentOrder : IO Unit := do
  let o ← makeOrigin "A.lean" 10 20 none
  let a := DiagnosticV1.make .sourceInvalid "alpha message"
    (primary := some o) (stableContext := some "k")
  let b := DiagnosticV1.make .sourceInvalid "zeta message that sorts later as prose"
    (primary := some o) (stableContext := some "k")
  -- Equal order keys: compareOrderKey is eq regardless of message.
  unless DiagnosticV1.compareOrderKey a b == .eq do
    throw <| IO.userError "order key must ignore message"
  -- sortAndDedupe collapses equal keys to one representative.
  let sorted := DiagnosticV1.sortAndDedupe #[b, a, b]
  unless sorted.size == 1 do
    throw <| IO.userError s!"dedupe by key expected 1, got {sorted.size}"
  -- Representative is deterministic (total-order minimum by message here).
  unless sorted[0]!.message == "alpha message" do
    throw <| IO.userError s!"expected alpha representative, got {sorted[0]!.message}"

  let c := DiagnosticV1.make .sourceInvalid "same"
    (primary := some o) (stableContext := none)
  let d := DiagnosticV1.make .sourceInvalid "same"
    (primary := some o) (stableContext := some "")
  unless DiagnosticV1.compareOrderKey c d == .eq do
    throw <| IO.userError "none and empty stableContext must share order key"

  let early := DiagnosticV1.make .sourceInvalid "z"
    (primary := some (← makeOrigin "A.lean" 1 2 none))
  let late := DiagnosticV1.make .sourceInvalid "a"
    (primary := some (← makeOrigin "A.lean" 9 10 none))
  unless DiagnosticV1.compareOrderKey early late == .lt do
    throw <| IO.userError "startByte must order diagnostics"
  -- Message must not flip startByte order.
  let ordered := DiagnosticV1.sortAndDedupe #[late, early]
  unless ordered[0]! == early do
    throw <| IO.userError "message-independent order violated"

  -- Transitivity on order keys.
  let x := DiagnosticV1.make .src001 "m" (stableContext := some "a")
  let y := DiagnosticV1.make .src010 "m" (stableContext := some "a")
  let z := DiagnosticV1.make .src020 "m" (stableContext := some "a")
  unless DiagnosticV1.compareOrderKey x y == .lt &&
      DiagnosticV1.compareOrderKey y z == .lt &&
      DiagnosticV1.compareOrderKey x z == .lt do
    throw <| IO.userError "order-key transitivity failed"

/-- Requirement/extension keys participate in the total order after the
    message-independent order key: digest and full SemVer wire identity
    (prerelease/build) must not compare equal when structurally distinct,
    so `sortAndDedupe` representative selection is qsort-stable. -/
private def testRequirementExtensionTotalOrder : IO Unit := do
  let digLow : Digest :=
    { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 32 (0 : UInt8)) }
  let digHigh : Digest :=
    { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 32 (1 : UInt8)) }
  let verCore : SemVer := { major := 1, minor := 0, patch := 0 }
  let reqLow : RequirementKeyV1 :=
    { id := "state.persistent", version := verCore, digest := digLow }
  let reqHigh : RequirementKeyV1 :=
    { id := "state.persistent", version := verCore, digest := digHigh }
  -- Same order key; messages would invert if digests were ignored.
  let withHighDigest := DiagnosticV1.make .sourceInvalid "aaa"
    (requirement := some reqHigh)
  let withLowDigest := DiagnosticV1.make .sourceInvalid "zzz"
    (requirement := some reqLow)
  unless DiagnosticV1.compareOrderKey withHighDigest withLowDigest == .eq do
    throw <| IO.userError "digest fixtures must share order key"
  unless DiagnosticV1.compare withLowDigest withHighDigest == .lt do
    throw <| IO.userError "lower requirement.digest must total-order before higher"
  -- Both input orders must keep the total-order minimum (low digest).
  for input in #[#[withHighDigest, withLowDigest], #[withLowDigest, withHighDigest]] do
    let sorted := DiagnosticV1.sortAndDedupe input
    unless sorted.size == 1 do
      throw <| IO.userError s!"digest dedupe expected size 1, got {sorted.size}"
    unless sorted[0]!.requirement == some reqLow do
      throw <| IO.userError "sortAndDedupe must keep lower requirement.digest representative"

  -- Extension digest total order (same shape).
  let extLow : ExtensionKeyV1 :=
    { id := "ext.demo", version := verCore, digest := digLow }
  let extHigh : ExtensionKeyV1 :=
    { id := "ext.demo", version := verCore, digest := digHigh }
  let withHighExt := DiagnosticV1.make .sourceInvalid "aaa" (extension := some extHigh)
  let withLowExt := DiagnosticV1.make .sourceInvalid "zzz" (extension := some extLow)
  unless DiagnosticV1.compare withLowExt withHighExt == .lt do
    throw <| IO.userError "lower extension.digest must total-order before higher"
  let extSorted := DiagnosticV1.sortAndDedupe #[withHighExt, withLowExt]
  unless extSorted.size == 1 && extSorted[0]!.extension == some extLow do
    throw <| IO.userError "sortAndDedupe must keep lower extension.digest representative"

  -- Prerelease/build wire identity: 1.0.0 < 1.0.0+build < 1.0.0-rc1 would be
  -- wrong for SemVer *precedence*, but for *identity* empty arrays sort first,
  -- so core < core+build and core < core-rc1; between build and prerelease the
  -- prerelease array is compared before build, so core+build (empty prerelease,
  -- nonempty build) vs core-rc1 (nonempty prerelease) ranks core+build first.
  let verBuild : SemVer :=
    { major := 1, minor := 0, patch := 0, prerelease := #[], build := #["build"] }
  let verPre : SemVer :=
    { major := 1, minor := 0, patch := 0, prerelease := #["rc1"], build := #[] }
  let reqCore : RequirementKeyV1 :=
    { id := "state.persistent", version := verCore, digest := digLow }
  let reqBuild : RequirementKeyV1 :=
    { id := "state.persistent", version := verBuild, digest := digLow }
  let reqPre : RequirementKeyV1 :=
    { id := "state.persistent", version := verPre, digest := digLow }
  let dCore := DiagnosticV1.make .sourceInvalid "zzz" (requirement := some reqCore)
  let dBuild := DiagnosticV1.make .sourceInvalid "aaa" (requirement := some reqBuild)
  let dPre := DiagnosticV1.make .sourceInvalid "mmm" (requirement := some reqPre)
  unless DiagnosticV1.compare dCore dBuild == .lt do
    throw <| IO.userError "1.0.0 must total-order before 1.0.0+build"
  unless DiagnosticV1.compare dCore dPre == .lt do
    throw <| IO.userError "1.0.0 must total-order before 1.0.0-rc1"
  unless DiagnosticV1.compare dBuild dPre == .lt do
    throw <| IO.userError "1.0.0+build (empty prerelease) must total-order before 1.0.0-rc1"
  let verSorted := DiagnosticV1.sortAndDedupe #[dPre, dBuild, dCore, dPre]
  unless verSorted.size == 1 do
    throw <| IO.userError s!"version-identity dedupe expected size 1, got {verSorted.size}"
  unless verSorted[0]!.requirement == some reqCore do
    throw <| IO.userError "sortAndDedupe must keep core SemVer as total-order minimum"
  -- Pairwise: build vs pre alone keeps build as minimum.
  let buildPre := DiagnosticV1.sortAndDedupe #[dPre, dBuild]
  unless buildPre.size == 1 && buildPre[0]!.requirement == some reqBuild do
    throw <| IO.userError "sortAndDedupe must keep 1.0.0+build over 1.0.0-rc1"

private def testStructuralRedaction : IO Unit := do
  let badPath : ProjectRelativePath := { value := "/etc/passwd.lean" }
  let badOrigin : DiagnosticOriginV1 := {
    sourcePath := badPath,
    startByte := 0,
    endByte := 1,
    nodeId := none
  }
  expectErr "validate absolute path"
    (DiagnosticOriginV1.validate badOrigin)
  let badDiag := DiagnosticV1.make .sourceInvalid "leak" (primary := some badOrigin)
  expectErr "toCanonicalJson absolute path" (badDiag.toCanonicalJson)

  let validPath ← match parseProjectRelativePath "Counter.lean" with
    | .ok p => pure p
    | .error e => throw <| IO.userError e
  let badRange : DiagnosticOriginV1 := {
    sourcePath := validPath,
    startByte := 5,
    endByte := 0,
    nodeId := none
  }
  expectErr "inverted range" (DiagnosticOriginV1.validate badRange)
  expectErr "encode inverted range"
    ((DiagnosticV1.make .sourceInvalid "r" (primary := some badRange)).toCanonicalJson)

  let badNode : DiagnosticOriginV1 := {
    sourcePath := validPath,
    startByte := 0,
    endByte := 1,
    nodeId := some { bytes := ByteArray.mk (Array.replicate 15 0) }
  }
  expectErr "bad nodeId length" (DiagnosticOriginV1.validate badNode)
  expectErr "encode bad nodeId"
    ((DiagnosticV1.make .sourceInvalid "n" (primary := some badNode)).toCanonicalJson)

private def testNormalizeCap : IO Unit := do
  let mkAt (i : Nat) : DiagnosticV1 :=
    DiagnosticV1.make .sourceInvalid s!"msg-{i}"
      (stableContext := some s!"ctx-{i}")
  -- Exactly 100: no limit.
  let hundred := (List.range 100).toArray.map mkAt
  let n100 := DiagnosticV1.normalizeDiagnosticBundleV1 hundred
  unless n100.size == 100 do
    throw <| IO.userError s!"100-cap: expected 100, got {n100.size}"
  unless n100.all (fun d => d.code != .diagLimit) do
    throw <| IO.userError "100-cap must not append PF-DIAG-LIMIT"
  -- 101 → 100 + limit.
  let n101 := DiagnosticV1.normalizeDiagnosticBundleV1 ((List.range 101).toArray.map mkAt)
  unless n101.size == 101 do
    throw <| IO.userError s!"101-cap: expected 101, got {n101.size}"
  unless n101[100]!.code == .diagLimit do
    throw <| IO.userError "101-cap last must be PF-DIAG-LIMIT"
  unless n101[100]!.renderHuman ==
      "PF-DIAG-LIMIT: diagnostic limit exceeded; remaining diagnostics truncated" do
    throw <| IO.userError "PF-DIAG-LIMIT human text mismatch"
  -- 200 → 100 + limit.
  let n200 := DiagnosticV1.normalizeDiagnosticBundleV1 ((List.range 200).toArray.map mkAt)
  unless n200.size == 101 do
    throw <| IO.userError s!"200-cap: expected 101, got {n200.size}"
  unless n200[100]!.code == .diagLimit do
    throw <| IO.userError "200-cap last must be PF-DIAG-LIMIT"
  -- Idempotent.
  let again := DiagnosticV1.normalizeDiagnosticBundleV1 n200
  unless again == n200 do
    throw <| IO.userError "normalizeDiagnosticBundleV1 is not idempotent"
  let again101 := DiagnosticV1.normalizeDiagnosticBundleV1 n101
  unless again101 == n101 do
    throw <| IO.userError "normalize 101 is not idempotent"

private def testEscaping : IO Unit := do
  let originalMessage := "quote\" backslash\\ newline\n tab\t control\x01 end"
  let diag := DiagnosticV1.make .sourceInvalid originalMessage
  match diag.toCanonicalJson with
  | .error e => throw <| IO.userError e
  | .ok rendered =>
    unless containsSubstr rendered "\\\"" do
      throw <| IO.userError "escaped quote not found"
    unless containsSubstr rendered "\\\\" do
      throw <| IO.userError "escaped backslash not found"
    unless containsSubstr rendered "\\n" do
      throw <| IO.userError "escaped newline not found"
    unless containsSubstr rendered "\\t" do
      throw <| IO.userError "escaped tab not found"
    unless containsSubstr rendered "\\u0001" do
      throw <| IO.userError "escaped control not found"
    match DiagnosticV1.fromCanonicalJson rendered with
    | .error e => throw <| IO.userError e
    | .ok d =>
      unless d.message == originalMessage do
        throw <| IO.userError "escaped message round-trip mismatch"

def run : IO Unit := do
  testCatalogUniqueness
  testHumanRendering
  testNullableNodeIdAndRelatedOrder
  testCanonicalJsonAllFields
  testDecoderRejects
  testMessageIndependentOrder
  testRequirementExtensionTotalOrder
  testStructuralRedaction
  testNormalizeCap
  testEscaping
  IO.println "Tests.Core.DiagnosticV1: ok"

end Tests.Core.DiagnosticV1
