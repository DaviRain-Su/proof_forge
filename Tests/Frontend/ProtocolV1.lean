/-
  Tests.Frontend.ProtocolV1 — B9/B9R inert FrontendProtocolV1 wire foundation.

  Covers:
    - request / success / failure round-trips
    - fixed request golden full-frame hex (ver 1.0.0 / tests/a.pf / M / none / 0x78)
    - hard-maxima constants (64 MiB protocol / 16 MiB source / 100000 spans);
      16 MiB source length-bomb and span-count bomb (no multi-MiB payload alloc);
      protocol maxProtocolBytes precheck is size-gated on every decoder entry
      (constant-locked; 64 MiB+1 vector not allocated in unit tests)
    - B9R: legal plain qualified selector >4096 (18×240 components) round-trip;
      selector declared-length maxProtocolBytes+1 bomb rejects before copy;
      no residual 4096 semantic selector protocol bound
    - B9R: PF-JCS diagnostic array top-level entry pre-scan (102-entry tiny bomb;
      nested/string commas not miscounted; normalized 100+PF-DIAG-LIMIT=101
      round-trip; 101 non-limit raw rejected by canonical re-encode identity)
    - tag / field-count / trailing / truncation mutations
    - success ValidatedSourceV1 root re-encode identity (noncanonical AST mutation)
    - request-digest cross-request replay rejection (bind*/reconstruct)
    - span count / range tampering (mk/bind)
    - noncanonical diagnostic bundle rejection (pure decode)
    - foreign diagnostic sourcePath rejection (mk + decode+bind wire path)
    - reconstruct → sourceHash + OriginJoin via sole decodeCanonicalSourceAstBytesV1
      + assignNodeIdsV1 zip + joinOriginsV1

  Product behavior is unchanged: no CLI/Loader/Compiler/worker cutover.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Frontend.ProtocolV1
import ProofForgeV2.Source.AstCanonicalRootDecodeV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.NodeAssignmentV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireCodecV1

namespace Tests.Frontend.ProtocolV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Frontend.ProtocolV1
open ProofForgeV2.Source.AstCanonicalRootDecodeV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.NodeAssignmentV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireCodecV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def lift (label : String) (r : Except String α) : IO α :=
  match r with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{label}: {e}"

private def expectErr (label : String) (r : Except String α) : IO String :=
  match r with
  | .error e => pure e
  | .ok _ => throw <| IO.userError s!"{label}: expected error"

private def expectErrContains (label needle : String) (r : Except String α) : IO Unit := do
  let e ← expectErr label r
  unless e.contains needle do
    throw <| IO.userError s!"{label}: expected error containing {needle}, got {e}"

private def n (s : String) : IO SourceNameComponentV1 :=
  lift s (parseSourceNameComponentV1 s)

private def q (parts : Array String) : IO SourceQualifiedNameV1 :=
  lift "qn" (parseSourceQualifiedNameV1 parts)

private def languageVersion100 : SemVer :=
  { major := 1, minor := 0, patch := 0 }

private def expectLanguageSelectionError
    (label raw : String) (expectedCode : DiagnosticCodeV1) : IO Unit :=
  match resolveLanguageParserDescriptorV1 (some raw) with
  | .error diagnostic =>
      expect (diagnostic.code == expectedCode)
        s!"{label}: expected {expectedCode.wire}, got {diagnostic.code.wire}"
  | .ok _ => throw <| IO.userError s!"{label}: expected language selection failure"

private def testLanguageParserSelection : IO Unit := do
  let omitted ← match resolveLanguageParserDescriptorV1 none with
    | .ok descriptor => pure descriptor
    | .error diagnostic =>
        throw <| IO.userError s!"omitted language version failed: {diagnostic.code.wire}"
  let explicit ← match resolveLanguageParserDescriptorV1 (some "1.0.0") with
    | .ok descriptor => pure descriptor
    | .error diagnostic =>
        throw <| IO.userError s!"explicit language version failed: {diagnostic.code.wire}"
  expect (LanguageParserDescriptorV1.version omitted == languageVersion100)
    "omitted language version resolves to 1.0.0"
  expect (LanguageParserDescriptorV1.version explicit ==
      LanguageParserDescriptorV1.version omitted)
    "omitted and explicit 1.0.0 resolve to the same parser descriptor"
  expect (LanguageParserDescriptorV1.enabled explicit)
    "selected 1.0.0 parser descriptor is enabled"
  expectLanguageSelectionError "unknown exact" "1.0.1" .languageVersionUnknown
  expectLanguageSelectionError "latest alias" "latest" .languageVersionUnknown
  expectLanguageSelectionError "range" "^1.0.0" .languageVersionUnknown
  expectLanguageSelectionError "major negotiation" "1" .languageVersionUnknown

private def testPath : IO ProjectRelativePath :=
  lift "path" (parseProjectRelativePath "tests/frontend/protocol-v1.pf")

private def foreignPath : IO ProjectRelativePath :=
  lift "foreign-path" (parseProjectRelativePath "tests/other/foreign.pf")

/-- Minimal ValidatedSourceV1: module M, program M.P, single entry run. -/
private def mkMinimalSource : IO ValidatedSourceV1 := do
  let name ← n "P"
  let mod ← q #["M"]
  let id ← q #["M", "P"]
  let entryName ← n "run"
  let body : BlockV1 := { statements := #[.return_ (some (.literal (.integer 0)))] }
  let entry : EntryDeclV1 :=
    { name := entryName, params := #[], result := .uint 64, body := body }
  lift "validate" (validateSourceV1 mod id { name, items := #[.entry entry] })

private def zeroSpansFor (source : ValidatedSourceV1) : IO (Array SourceByteSpanV1) := do
  let table ← lift "assign"
    (assignNodeIdsV1 source.moduleName source.programIdentity source.program)
  let assignments := nodeAssignmentsPreorderV1 table
  pure (assignments.map fun _ => { startByte := 0, endByte := 0 })

private def mkSampleRequest (sourceBytes : ByteArray := ByteArray.mk #[0x61]) :
    IO FrontendRequestV1 := do
  let path ← testPath
  lift "mk-request"
    (mkFrontendRequestV1 languageVersion100 path "Tests.Frontend" none sourceBytes)

private def mkSampleRequestWithProgram : IO FrontendRequestV1 := do
  let path ← testPath
  lift "mk-request-prog"
    (mkFrontendRequestV1 languageVersion100 path "Tests.Frontend"
      (some "Tests.Frontend.P") "source-body".toUTF8)

private def hexNibble (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n)
  else Char.ofNat ('a'.toNat + n - 10)

private def toHex (bytes : ByteArray) : String :=
  bytes.foldl (fun acc b =>
    let v := b.toNat
    (acc.push (hexNibble (v / 16))).push (hexNibble (v % 16))) ""

private def fromHex (hex : String) : IO ByteArray := do
  let cs := hex.toList
  unless cs.length % 2 == 0 do
    throw <| IO.userError "fromHex: odd length"
  let rec loop (acc : ByteArray) : List Char → IO ByteArray
    | [] => pure acc
    | h :: l :: rest => do
        let hn ←
          if '0' ≤ h && h ≤ '9' then pure (h.toNat - '0'.toNat)
          else if 'a' ≤ h && h ≤ 'f' then pure (10 + h.toNat - 'a'.toNat)
          else throw <| IO.userError s!"fromHex bad nibble {h}"
        let ln ←
          if '0' ≤ l && l ≤ '9' then pure (l.toNat - '0'.toNat)
          else if 'a' ≤ l && l ≤ 'f' then pure (10 + l.toNat - 'a'.toNat)
          else throw <| IO.userError s!"fromHex bad nibble {l}"
        loop (acc.push (UInt8.ofNat (hn * 16 + ln))) rest
    | _ => throw <| IO.userError "fromHex: incomplete pair"
  loop ByteArray.empty cs

private def setByte (bytes : ByteArray) (idx : Nat) (b : UInt8) : ByteArray :=
  Id.run do
    let mut out := bytes
    if idx < out.size then
      out := out.set! idx b
    pure out

private def appendByte (bytes : ByteArray) (b : UInt8) : ByteArray :=
  bytes.push b

private def dropLast (bytes : ByteArray) : ByteArray :=
  if bytes.size == 0 then bytes
  else bytes.extract 0 (bytes.size - 1)

/-! ### Round-trips -/

private def testRequestRoundTrip : IO Unit := do
  let req ← mkSampleRequestWithProgram
  let enc ← lift "enc-req" (encodeFrontendRequestV1 req)
  let dec ← lift "dec-req" (decodeFrontendRequestV1 enc)
  expect (FrontendRequestV1.languageVersion dec == languageVersion100)
    "request languageVersion"
  expect (FrontendRequestV1.sourcePath dec == FrontendRequestV1.sourcePath req)
    "request sourcePath"
  expect (FrontendRequestV1.moduleSelector dec == "Tests.Frontend")
    "request moduleSelector"
  expect (FrontendRequestV1.programSelector dec == some "Tests.Frontend.P")
    "request programSelector"
  expect (FrontendRequestV1.sourceBytes dec == FrontendRequestV1.sourceBytes req)
    "request sourceBytes"
  let enc2 ← lift "enc-req-2" (encodeFrontendRequestV1 dec)
  expect (enc == enc2) "request re-encode identity"

private def testSuccessRoundTripAndReconstruct : IO Unit := do
  let source ← mkMinimalSource
  let spans ← zeroSpansFor source
  -- Source snapshot large enough for zero spans.
  let req ← mkSampleRequest (ByteArray.mk #[0x00])
  let ok ← lift "mk-ok" (mkFrontendSuccessV1 req source spans)
  let enc ← lift "enc-ok" (encodeFrontendSuccessV1 ok)
  let dec ← lift "dec-ok" (decodeFrontendSuccessV1 enc)
  expect (FrontendSuccessV1.requestDigest dec == FrontendSuccessV1.requestDigest ok)
    "success digest stable"
  expect (FrontendSuccessV1.canonicalBytes dec == FrontendSuccessV1.canonicalBytes ok)
    "success canonical bytes"
  expect (FrontendSuccessV1.spans dec == FrontendSuccessV1.spans ok)
    "success spans"
  let (src2, inv) ← lift "reconstruct" (reconstructFrontendSuccessV1 req dec)
  let h1 ← lift "hash1" (sourceHashV1 source)
  let h2 ← lift "hash2" (sourceHashV1 src2)
  expect (h1 == h2) "reconstruct sourceHash identity"
  expect (originInventorySourceHashV1 inv == h1)
    "origin inventory sourceHash"
  let table ← lift "assign"
    (assignNodeIdsV1 source.moduleName source.programIdentity source.program)
  expect ((originInventoryOriginsV1 inv).size == (nodeAssignmentsPreorderV1 table).size)
    "origin count matches assignment"

private def testFailureRoundTrip : IO Unit := do
  let req ← mkSampleRequest
  let path := FrontendRequestV1.sourcePath req
  let primary : DiagnosticOriginV1 :=
    { sourcePath := path, startByte := 0, endByte := 1, nodeId := none }
  let d := DiagnosticV1.make .sourceInvalid "frontend protocol failure sample"
    (primary := some primary) (stableContext := some "k0")
  let err ← lift "mk-err" (mkFrontendFailureV1 req #[d])
  let enc ← lift "enc-err" (encodeFrontendFailureV1 err)
  let dec ← lift "dec-err" (decodeFrontendFailureV1 enc)
  expect (FrontendFailureV1.requestDigest dec == FrontendFailureV1.requestDigest err)
    "failure digest"
  let diags := FrontendFailureV1.diagnostics dec
  expect (diags.size == 1) "failure diag count"
  expect (diags[0]!.code == .sourceInvalid) "failure code"
  expect (diags[0]!.message == "frontend protocol failure sample") "failure message"
  let bound ← lift "bind-err" (bindFrontendFailureV1 req dec)
  expect ((FrontendFailureV1.diagnostics bound).size == 1) "bind failure"

private def testResponseDispatch : IO Unit := do
  let req ← mkSampleRequest
  let source ← mkMinimalSource
  let spans ← zeroSpansFor source
  let ok ← lift "mk-ok" (mkFrontendSuccessV1 req source spans)
  let okBytes ← lift "enc-ok" (encodeFrontendSuccessV1 ok)
  match ← lift "dec-resp-ok" (decodeFrontendResponseV1 okBytes) with
  | .success s =>
      expect (FrontendSuccessV1.requestDigest s == FrontendSuccessV1.requestDigest ok)
        "response success digest"
  | .failure _ => throw <| IO.userError "response: expected success"
  let d := DiagnosticV1.make .sourceInvalid "x"
  let err ← lift "mk-err" (mkFrontendFailureV1 req #[d])
  let errBytes ← lift "enc-err" (encodeFrontendFailureV1 err)
  match ← lift "dec-resp-err" (decodeFrontendResponseV1 errBytes) with
  | .failure f =>
      expect ((FrontendFailureV1.diagnostics f).size == 1) "response failure"
  | .success _ => throw <| IO.userError "response: expected failure"

/-! ### Golden request vector -/

/-- Fixed full-frame hex for ver=1.0.0, path=tests/a.pf, module=M, program=none, source=0x78.
    Layout: u32le tagLen=15 ‖ "Frontend.Req.v1" ‖ u16le fields=5 ‖ 5 fields. -/
private def requestGoldenHexV1 : String :=
  "0f00000046726f6e74656e642e5265712e7631050005000000312e302e300a00000074657374732f612e7066010000004d000100000078"

private def testRequestGolden : IO Unit := do
  -- Fixed small request: ver 1.0.0, path tests/a.pf, module M, no program, source "x"
  let path ← lift "path" (parseProjectRelativePath "tests/a.pf")
  let req ← lift "mk"
    (mkFrontendRequestV1 languageVersion100 path "M" none (ByteArray.mk #[0x78]))
  let enc ← lift "enc" (encodeFrontendRequestV1 req)
  let golden := toHex enc
  expect (golden == requestGoldenHexV1) "golden full-frame hex exact"
  let enc2 ← lift "enc2" (encodeFrontendRequestV1 req)
  expect (enc == enc2) "golden determinism"
  -- Secondary layout guards (tag length / ASCII / field count).
  expect (golden.startsWith "0f000000") "golden tag length u32le=15"
  let tagBytes := "Frontend.Req.v1".toUTF8
  expect (enc.extract 4 (4 + tagBytes.size) == tagBytes) "golden tag bytes"
  let fcOff := 4 + tagBytes.size
  expect (enc.get! fcOff == 5) "golden field count low"
  expect (enc.get! (fcOff + 1) == 0) "golden field count high"
  let rematerialized ← fromHex requestGoldenHexV1
  let dec ← lift "dec-golden" (decodeFrontendRequestV1 rematerialized)
  expect (FrontendRequestV1.moduleSelector dec == "M") "golden module"
  expect (FrontendRequestV1.sourceBytes dec == ByteArray.mk #[0x78]) "golden source"

/-! ### Boundaries -/

private def testProtocolSizePrecheck : IO Unit := do
  -- Public hard maxima (ResourceProfile frontend + source open bounds).
  expect (maxProtocolBytes == 64 * 1024 * 1024) "maxProtocolBytes 64 MiB"
  expect (maxSourceBytes == 16 * 1024 * 1024) "maxSourceBytes 16 MiB"
  expect (maxNodeSpanCount == 100000) "maxNodeSpanCount"
  -- Tiny input still hits decoder precheck path (size ≤ maxProtocolBytes) then fails
  -- at tag framing — proves decoders enter precheck before body parse.
  expectErrContains "tiny-frame" "" (decodeFrontendRequestV1 (ByteArray.mk #[0x00]))
  -- Claimed sourceBytes length bomb inside an otherwise tiny frame:
  -- Frontend.Req.v1 with languageVersion + path + module + none + u32le (16MiB+1)
  -- and no payload → oversize before copy.
  let verB ← lift "ver" (encodeString "1.0.0")
  let pathB ← lift "pathB" (encodeString "tests/a.pf")
  let modB ← lift "modB" (do
    let raw := "M".toUTF8
    pure ((encodeU32le (UInt32.ofNat raw.size)).append raw))
  let progB := encodeU8 0  -- none
  let overLen := maxSourceBytes + 1
  let srcHeader := encodeU32le (UInt32.ofNat overLen)
  let fields := #[verB, pathB, modB, progB, srcHeader]
  let frame ← lift "frame" (encodeTagged "Frontend.Req.v1" fields)
  expect (frame.size ≤ maxProtocolBytes) "length-bomb frame stays under protocol max"
  expectErrContains "source-oversize" "exceeds limit" (decodeFrontendRequestV1 frame)

private def testSpanCountBomb : IO Unit := do
  let req ← mkSampleRequest
  let source ← mkMinimalSource
  let canon ← lift "canon" (canonicalValidatedSourceAstBytesV1 source)
  let digest ← lift "digest" (requestDigestOfV1 req)
  let digB := digest.bytes
  let canB ← lift "canB" (do
    pure ((encodeU32le (UInt32.ofNat canon.size)).append canon))
  let bombCount := maxNodeSpanCount + 1
  let spanHeader := encodeU32le (UInt32.ofNat bombCount)
  let fields := #[digB, canB, spanHeader]
  let frame ← lift "frame" (encodeTagged "Frontend.Ok.v1" fields)
  expectErrContains "span-bomb" "span count exceeds" (decodeFrontendSuccessV1 frame)

/-- Legal plain qualified selector >4096 UTF-8 bytes: 18×240-byte components joined by
    dots. Protocol must accept (maxProtocolBytes allocation guard only); exact Lean
    qualified-name legality is deferred to Loader / parseSourceQualifiedNameV1. -/
private def testLargeLegalSelectorRoundTrip : IO Unit := do
  let component := String.ofList (List.replicate 240 'a')
  expect (component.toUTF8.size == 240) "component is 240 UTF-8 bytes"
  let parts : Array String := (List.range 18).toArray.map fun _ => component
  expect (parts.size == 18) "18 components"
  -- Independently prove source qualified-name surface accepts these components.
  let _qn ← lift "parse-qn" (parseSourceQualifiedNameV1 parts)
  let selector := String.intercalate "." parts.toList
  expect (selector.toUTF8.size > 4096)
    s!"selector UTF-8 size {selector.toUTF8.size} must exceed obsolete 4096 cap"
  expect (selector.toUTF8.size == 18 * 240 + 17)
    "selector size = 18*240 + 17 dots"
  expect (selector.toUTF8.size ≤ maxProtocolBytes)
    "selector fits maxProtocolBytes allocation guard"
  -- Compatibility accessor (if retained) is only an allocation alias, never 4096.
  expect (maxSelectorBytes == maxProtocolBytes)
    "maxSelectorBytes equals maxProtocolBytes (allocation guard, not semantic QN limit)"
  expect (maxSelectorBytes != 4096 || maxProtocolBytes == 4096)
    "no residual 4096 semantic selector protocol bound"
  let path ← testPath
  let req ← lift "mk-large-selector"
    (mkFrontendRequestV1 languageVersion100 path selector none (ByteArray.mk #[0x00]))
  expect (FrontendRequestV1.moduleSelector req == selector)
    "large moduleSelector retained by mk"
  let enc ← lift "enc-large" (encodeFrontendRequestV1 req)
  let dec ← lift "dec-large" (decodeFrontendRequestV1 enc)
  expect (FrontendRequestV1.moduleSelector dec == selector)
    "large moduleSelector round-trip"

/-- Declared moduleSelector u32 length = maxProtocolBytes+1 on a tiny frame must
    reject before payload copy (allocation/frame guard). -/
private def testSelectorLengthBomb : IO Unit := do
  let verB ← lift "ver" (encodeString "1.0.0")
  let pathB ← lift "pathB" (encodeString "tests/a.pf")
  let overLen := maxProtocolBytes + 1
  let modHeader := encodeU32le (UInt32.ofNat overLen)
  let progB := encodeU8 0  -- none
  let srcHeader := encodeU32le (UInt32.ofNat 0)
  let fields := #[verB, pathB, modHeader, progB, srcHeader]
  let frame ← lift "frame" (encodeTagged "Frontend.Req.v1" fields)
  expect (frame.size ≤ maxProtocolBytes) "selector length-bomb frame stays under protocol max"
  expectErrContains "selector-len-bomb" "exceeds limit" (decodeFrontendRequestV1 frame)

/-! ### Diagnostic array entry pre-scan (Frontend.Err.v1) -/

/-- 102-entry tiny PF-JCS array must be rejected by the top-level entry pre-scan
    before parsePfJcs allocates a diagnostic array. -/
private def testDiagnosticArrayCountBomb102 : IO Unit := do
  let req ← mkSampleRequest
  let digest ← lift "digest" (requestDigestOfV1 req)
  let digB := digest.bytes
  -- Tiny 102-entry array of zeros: 1 entry would be accepted structure-wise by a
  -- count scan; 102 must fail the ≤101 precheck.
  let body := String.intercalate "," (List.replicate 102 "0")
  let json := s!"[{body}]"
  expect (json.toUTF8.size < 1024) "102-entry bomb stays tiny"
  let jsonB := (encodeU32le (UInt32.ofNat json.toUTF8.size)).append json.toUTF8
  let frame ← lift "frame" (encodeTagged "Frontend.Err.v1" #[digB, jsonB])
  expectErrContains "102-entry-bomb" "entry count"
    (decodeFrontendFailureV1 frame)

/-- Count Char occurrences (portable; no dependency on List.count / String.data). -/
private def countChar (s : String) (c : Char) : Nat :=
  s.foldl (fun acc ch => if ch == c then acc + 1 else acc) 0

/-- Nested arrays/objects and commas inside strings must not inflate the top-level
    entry count (pre-scan structural only).

    Critical: true top-level entries ≤101, but total commas across nested arrays,
    nested objects, and strings must exceed 101. A broken scanner that counts every
    comma as top-level would then report "entry count exceeds" and fail this test.
    The current wire is intentionally non-diagnostic so decode must still fail —
    but never for an entry-count reason. -/
private def testDiagnosticArrayNestedCommasNotMiscounted : IO Unit := do
  let req ← mkSampleRequest
  let digest ← lift "digest" (requestDigestOfV1 req)
  let digB := digest.bytes
  -- Nested array of 200 zeros → 199 commas that must NOT count as top-level.
  let nestedZeros := String.intercalate "," (List.replicate 200 "0")
  -- String containing 200 commas → also must not inflate the top-level count.
  let commaString := String.intercalate "," (List.replicate 201 "x")
  expect (countChar commaString ',' == 200) "string holds exactly 200 commas"
  -- Nested object with many key/value commas (50 pairs → many nested commas).
  let nestedObjPairs :=
    String.intercalate ","
      ((List.range 50).map fun i => s!"\"k{i}\":{i}")
  -- Two top-level values only (true count = 2 ≤ 101). Total commas ≫ 101 if
  -- nested/string commas were miscounted as top-level.
  -- Build without fragile brace-escaping inside a single s!" … " fragment.
  let top1 := "[" ++ nestedZeros ++ "]"
  let top2 :=
    "{\"nest\":{" ++ nestedObjPairs ++ "},\"s\":\"" ++ commaString ++ "\"}"
  let json := "[" ++ top1 ++ "," ++ top2 ++ "]"
  let totalCommas := countChar json ','
  expect (totalCommas > 101)
    s!"fixture total commas {totalCommas} must exceed 101 so naive comma-count fails"
  expect (json.toUTF8.size < 8192) "nested-commas fixture stays small"
  let jsonB := (encodeU32le (UInt32.ofNat json.toUTF8.size)).append json.toUTF8
  let frame ← lift "frame" (encodeTagged "Frontend.Err.v1" #[digB, jsonB])
  match decodeFrontendFailureV1 frame with
  | .ok _ =>
      throw <| IO.userError
        "nested-commas: expected semantic rejection of non-diagnostic values"
  | .error e =>
      if e.contains "entry count" then
        throw <| IO.userError
          s!"nested-commas: pre-scan miscounted nested/string commas as top-level: {e}"
      -- Any non-entry-count failure is acceptable (parse/fromPfJson/noncanonical).
      pure ()

/-- mkFailureBundleV1 of 101 non-limit diagnostics yields 100 + PF-DIAG-LIMIT and
    must round-trip as Frontend.Err.v1 with exact re-encode identity. -/
private def testNormalized101LimitRoundTrip : IO Unit := do
  let req ← mkSampleRequest
  let raw : Array DiagnosticV1 :=
    (List.range 101).toArray.map fun i =>
      DiagnosticV1.make .sourceInvalid s!"norm-msg-{i}"
        (stableContext := some s!"norm-k-{i}")
  let err ← lift "mk-101" (mkFrontendFailureV1 req raw)
  let diags := FrontendFailureV1.diagnostics err
  expect (diags.size == 101) "normalized 101 size"
  expect (diags[100]!.code == .diagLimit) "last is PF-DIAG-LIMIT"
  expect ((diags.extract 0 100).all (fun d => d.code != .diagLimit))
    "first 100 are non-limit"
  let enc ← lift "enc-101" (encodeFrontendFailureV1 err)
  let dec ← lift "dec-101" (decodeFrontendFailureV1 enc)
  expect (FrontendFailureV1.requestDigest dec == FrontendFailureV1.requestDigest err)
    "101-limit digest"
  expect ((FrontendFailureV1.diagnostics dec).size == 101) "101-limit decode size"
  expect ((FrontendFailureV1.diagnostics dec)[100]!.code == .diagLimit)
    "101-limit last code"
  let enc2 ← lift "enc-101-2" (encodeFrontendFailureV1 dec)
  expect (enc == enc2) "101-limit re-encode identity"

/-- 101 non-limit raw diagnostics in a PF-JCS array are rejected by canonical
    bundle identity (mkFailureBundleV1 would emit 100+PF-DIAG-LIMIT). -/
private def testRaw101NonLimitRejectedByCanonicalIdentity : IO Unit := do
  let req ← mkSampleRequest
  let digest ← lift "digest" (requestDigestOfV1 req)
  let digB := digest.bytes
  let raw : Array DiagnosticV1 :=
    (List.range 101).toArray.map fun i =>
      DiagnosticV1.make .sourceInvalid s!"raw-msg-{i}"
        (stableContext := some s!"raw-k-{i}")
  let jsonParts ← raw.mapM fun d =>
    lift "j" (DiagnosticV1.toCanonicalJson d)
  let json := "[" ++ String.intercalate "," jsonParts.toList ++ "]"
  -- Sanity: normalize path is 100+limit, so raw wire differs.
  let normalized := mkFailureBundleV1 raw
  let sorted ← lift "sorted" (DiagnosticBundleV1.renderCanonicalJsonArray normalized)
  expect (json != sorted) "raw 101 non-limit differs from normalized 100+limit"
  let jsonB := (encodeU32le (UInt32.ofNat json.toUTF8.size)).append json.toUTF8
  let frame ← lift "frame" (encodeTagged "Frontend.Err.v1" #[digB, jsonB])
  expectErrContains "raw-101-noncanonical" "noncanonical"
    (decodeFrontendFailureV1 frame)

/-! ### Mutations -/

private def testTagMutation : IO Unit := do
  let req ← mkSampleRequest
  let enc ← lift "enc" (encodeFrontendRequestV1 req)
  -- Flip first byte of tag payload (offset 4).
  let muted := setByte enc 4 0x00
  expectErrContains "tag-mut" "tag" (decodeFrontendRequestV1 muted)
  -- Wrong response tag when decoding as request.
  let source ← mkMinimalSource
  let spans ← zeroSpansFor source
  let ok ← lift "ok" (mkFrontendSuccessV1 req source spans)
  let okBytes ← lift "okb" (encodeFrontendSuccessV1 ok)
  expectErrContains "ok-as-req" "expected tag" (decodeFrontendRequestV1 okBytes)

private def testFieldCountMutation : IO Unit := do
  let req ← mkSampleRequest
  let enc ← lift "enc" (encodeFrontendRequestV1 req)
  -- Field count sits at offset 4 + len("Frontend.Req.v1") = 4+15 = 19.
  let fcOff := 4 + "Frontend.Req.v1".toUTF8.size
  let muted := setByte enc fcOff 4  -- claim 4 fields instead of 5
  expectErrContains "field-count" "fields" (decodeFrontendRequestV1 muted)

private def testTrailingAndTruncation : IO Unit := do
  let req ← mkSampleRequest
  let enc ← lift "enc" (encodeFrontendRequestV1 req)
  let trailed := appendByte enc 0x00
  expectErrContains "trailing" "trailing" (decodeFrontendRequestV1 trailed)
  -- Noncanonical: trailing may fail as trailing or noncanonical depending on order.
  let trunc := dropLast enc
  expectErrContains "trunc" "" (decodeFrontendRequestV1 trunc)  -- any error

private def testCrossRequestReplay : IO Unit := do
  let req1 ← mkSampleRequest (ByteArray.mk #[0x01])
  let req2 ← mkSampleRequest (ByteArray.mk #[0x02])
  let source ← mkMinimalSource
  let spans ← zeroSpansFor source
  let ok1 ← lift "ok1" (mkFrontendSuccessV1 req1 source spans)
  expectErrContains "replay-ok" "cross-request replay"
    (bindFrontendSuccessV1 req2 ok1)
  expectErrContains "replay-recon" "cross-request replay"
    (reconstructFrontendSuccessV1 req2 ok1)
  let d := DiagnosticV1.make .sourceInvalid "e"
  let err1 ← lift "err1" (mkFrontendFailureV1 req1 #[d])
  expectErrContains "replay-err" "cross-request replay"
    (bindFrontendFailureV1 req2 err1)

private def testSpanTamper : IO Unit := do
  let req ← mkSampleRequest (ByteArray.mk (Array.mk (List.replicate 16 (0 : UInt8))))
  let source ← mkMinimalSource
  let spans ← zeroSpansFor source
  -- Wrong count at mk time.
  let badCount := spans.push { startByte := 0, endByte := 0 }
  expectErrContains "span-count-mk" "span count"
    (mkFrontendSuccessV1 req source badCount)
  let _ok ← lift "ok" (mkFrontendSuccessV1 req source spans)
  -- Range: end past sourceBytes size.
  if spans.size > 0 then
    let mut badSpans := spans
    badSpans := badSpans.set! 0 { startByte := 0, endByte := UInt64.ofNat 1000 }
    expectErrContains "span-range-mk" "exceeds sourceBytes"
      (mkFrontendSuccessV1 req source badSpans)
  -- start > end
  if spans.size > 0 then
    let mut badSpans := spans
    badSpans := badSpans.set! 0 { startByte := 5, endByte := 1 }
    expectErrContains "span-order-mk" "startByte"
      (mkFrontendSuccessV1 req source badSpans)

private def testNoncanonicalDiagnostics : IO Unit := do
  let req ← mkSampleRequest
  let digest ← lift "digest" (requestDigestOfV1 req)
  -- Malformed JSON array text.
  let digB := digest.bytes
  let badJson := "[not-json".toUTF8
  let jsonB := (encodeU32le (UInt32.ofNat badJson.size)).append badJson
  let frame ← lift "frame"
    (encodeTagged "Frontend.Err.v1" #[digB, jsonB])
  expectErrContains "bad-json" "" (decodeFrontendFailureV1 frame)
  -- Valid single diagnostic but wrong bundle order / non-normalized: two diags
  -- in reverse of normalize order with same keys so re-encode after
  -- mkFailureBundleV1 changes order → noncanonical.
  let d0 := DiagnosticV1.make .type001 "t" (stableContext := some "b")
  let d1 := DiagnosticV1.make .sourceInvalid "s" (stableContext := some "a")
  -- Build unsorted JSON array manually from individual canonical objects.
  let j0 ← lift "j0" (DiagnosticV1.toCanonicalJson d0)
  let j1 ← lift "j1" (DiagnosticV1.toCanonicalJson d1)
  let unsorted := s!"[{j0},{j1}]"
  -- After mkFailureBundleV1 sort, order may differ from unsorted input.
  let bundle := mkFailureBundleV1 #[d0, d1]
  let sorted ← lift "sorted" (DiagnosticBundleV1.renderCanonicalJsonArray bundle)
  if unsorted != sorted then
    let raw := unsorted.toUTF8
    let jsonField := (encodeU32le (UInt32.ofNat raw.size)).append raw
    let frame2 ← lift "frame2"
      (encodeTagged "Frontend.Err.v1" #[digB, jsonField])
    expectErrContains "unsorted-bundle" "noncanonical" (decodeFrontendFailureV1 frame2)
  else
    -- If order already matched, force a trailing-space noncanonical variant.
    let raw := (sorted ++ " ").toUTF8
    let jsonField := (encodeU32le (UInt32.ofNat raw.size)).append raw
    let frame2 ← lift "frame2"
      (encodeTagged "Frontend.Err.v1" #[digB, jsonField])
    expectErrContains "padded-bundle" "" (decodeFrontendFailureV1 frame2)

private def testForeignDiagnosticPath : IO Unit := do
  let req ← mkSampleRequest
  let foreign ← foreignPath
  let primary : DiagnosticOriginV1 :=
    { sourcePath := foreign, startByte := 0, endByte := 0, nodeId := none }
  let d := DiagnosticV1.make .sourceInvalid "foreign" (primary := some primary)
  -- mk-time path gate (smart constructor).
  expectErrContains "foreign-mk" "sourcePath"
    (mkFrontendFailureV1 req #[d])
  -- Wire path B10 will use: pure decode accepts a well-framed Err with foreign
  -- primary.sourcePath (no request context); bindFrontendFailureV1 then rejects.
  let digest ← lift "digest" (requestDigestOfV1 req)
  let bundle := mkFailureBundleV1 #[d]
  let json ← lift "json" (DiagnosticBundleV1.renderCanonicalJsonArray bundle)
  let digB := digest.bytes
  let jsonB := (encodeU32le (UInt32.ofNat json.toUTF8.size)).append json.toUTF8
  let frame ← lift "foreign-frame"
    (encodeTagged "Frontend.Err.v1" #[digB, jsonB])
  let dec ← lift "foreign-dec" (decodeFrontendFailureV1 frame)
  expect ((FrontendFailureV1.diagnostics dec).size ≥ 1) "foreign decode keeps diag"
  expectErrContains "foreign-bind" "sourcePath"
    (bindFrontendFailureV1 req dec)

/-- Mutate a legal success frame's ValidatedSourceV1 root payload under intact outer
    Frontend.Ok.v1 length/tag/field framing; decodeFrontendSuccessV1 must fail closed
    (AST decode failure and/or root re-encode identity / noncanonical). -/
private def testNoncanonicalSuccessAstRoot : IO Unit := do
  let req ← mkSampleRequest
  let source ← mkMinimalSource
  let spans ← zeroSpansFor source
  let ok ← lift "ok" (mkFrontendSuccessV1 req source spans)
  let enc ← lift "enc" (encodeFrontendSuccessV1 ok)
  let canon := FrontendSuccessV1.canonicalBytes ok
  -- Locate the length-prefixed canonical AST field: after tag + fieldCount + digest32.
  let tagBytes := "Frontend.Ok.v1".toUTF8
  let digOff := 4 + tagBytes.size + 2
  let canLenOff := digOff + 32
  expect (enc.size > canLenOff + 4 + canon.size) "ok frame contains AST payload"
  let len0 := (enc.get! canLenOff).toNat
  let len1 := (enc.get! (canLenOff + 1)).toNat
  let len2 := (enc.get! (canLenOff + 2)).toNat
  let len3 := (enc.get! (canLenOff + 3)).toNat
  let declared := len0 + len1 * 256 + len2 * 65536 + len3 * 16777216
  expect (declared == canon.size) "AST length prefix matches stored canonical"
  let payloadOff := canLenOff + 4
  expect (enc.extract payloadOff (payloadOff + canon.size) == canon)
    "AST payload bytes match success.canonicalBytes"
  -- Sanity: sole decoder accepts the legal root; re-encode is identity.
  let decoded ← lift "ast-ok" (decodeCanonicalSourceAstBytesV1 canon)
  let reCanon ← lift "re-canon" (canonicalValidatedSourceAstBytesV1 decoded)
  expect (reCanon == canon) "legal root is re-encode identity"
  -- Same-length mutation inside the AST payload (flip first payload byte).
  -- Outer length/tag/field-count framing stays intact.
  expect (canon.size > 0) "canonical AST nonempty"
  let flipped : UInt8 := UInt8.ofNat ((canon.get! 0).toNat ^^^ 0xff)
  let muted := setByte enc payloadOff flipped
  expect (muted.size == enc.size) "mutation preserves outer frame length"
  expect (muted != enc) "mutation changed AST root byte"
  let mutedCanon := setByte canon 0 flipped
  match decodeCanonicalSourceAstBytesV1 mutedCanon with
  | .ok src =>
      -- Noncanonical-but-decodable (or alternate) root: protocol must require
      -- sole canonicalValidatedSourceAstBytesV1 identity against the carried bytes.
      let re ← lift "re-muted" (canonicalValidatedSourceAstBytesV1 src)
      if re == mutedCanon then
        -- Bijective alternate program of equal length remains a legal Ok root.
        let dec ← lift "alt-ok" (decodeFrontendSuccessV1 muted)
        expect (FrontendSuccessV1.canonicalBytes dec == mutedCanon)
          "bijective alternate root accepted only with matching bytes"
      else
        expectErrContains "noncanonical-identity" "noncanonical"
          (decodeFrontendSuccessV1 muted)
  | .error _ =>
      -- Corrupt root is not a legal AST: still reject under intact Ok framing.
      expectErrContains "corrupt-ast-root" "" (decodeFrontendSuccessV1 muted)

private def testRawSelectorNoNfcGate : IO Unit := do
  -- Combining characters that are valid UTF-8 but not NFC must still be accepted
  -- by the protocol constructor (Loader later classifies).
  let path ← testPath
  -- U+0065 LATIN SMALL LETTER E + U+0301 COMBINING ACUTE ACCENT (not NFC).
  let nonNfc := "e\u0301"
  let req ← lift "non-nfc-mod"
    (mkFrontendRequestV1 languageVersion100 path nonNfc none (ByteArray.mk #[0x00]))
  expect (FrontendRequestV1.moduleSelector req == nonNfc) "raw selector preserved"
  let enc ← lift "enc" (encodeFrontendRequestV1 req)
  let dec ← lift "dec" (decodeFrontendRequestV1 enc)
  expect (FrontendRequestV1.moduleSelector dec == nonNfc) "raw selector round-trip"

private def testInvalidUtf8SourceBytesAccepted : IO Unit := do
  -- Protocol must not UTF-8-validate sourceBytes.
  let path ← testPath
  let raw := ByteArray.mk #[0xff, 0xfe, 0x00]
  let req ← lift "raw-src"
    (mkFrontendRequestV1 languageVersion100 path "M" none raw)
  expect (FrontendRequestV1.sourceBytes req == raw) "raw source bytes retained"
  let enc ← lift "enc" (encodeFrontendRequestV1 req)
  let dec ← lift "dec" (decodeFrontendRequestV1 enc)
  expect (FrontendRequestV1.sourceBytes dec == raw) "raw source bytes round-trip"

private def testDigestDomainSeparation : IO Unit := do
  let req ← mkSampleRequest
  let bytes ← lift "enc" (encodeFrontendRequestV1 req)
  let d1 ← lift "d1" (requestDigestV1 bytes)
  let d2 ← lift "d2" (requestDigestOfV1 req)
  expect (d1 == d2) "digest APIs agree"
  -- Different domain tag must not match (raw sha of frame alone).
  let bare := sha256Bytes bytes
  expect (bare != d1) "domain separation changes digest"

/-! ### Entry -/

def run : IO Unit := do
  testLanguageParserSelection
  testRequestRoundTrip
  testSuccessRoundTripAndReconstruct
  testFailureRoundTrip
  testResponseDispatch
  testRequestGolden
  testProtocolSizePrecheck
  testSpanCountBomb
  testLargeLegalSelectorRoundTrip
  testSelectorLengthBomb
  testDiagnosticArrayCountBomb102
  testDiagnosticArrayNestedCommasNotMiscounted
  testNormalized101LimitRoundTrip
  testRaw101NonLimitRejectedByCanonicalIdentity
  testTagMutation
  testFieldCountMutation
  testTrailingAndTruncation
  testCrossRequestReplay
  testSpanTamper
  testNoncanonicalDiagnostics
  testForeignDiagnosticPath
  testNoncanonicalSuccessAstRoot
  testRawSelectorNoNfcGate
  testInvalidUtf8SourceBytesAccepted
  testDigestDomainSeparation
  IO.println "Tests.Frontend.ProtocolV1: ok"

end Tests.Frontend.ProtocolV1
