/-
  Tests.Compiler.InlineProofProtocolV1 — pure wire foundation for the inline
  proof-certifier protocol. No worker, Loader, Audit, or CLI cutover.
-/
import ProofForgeV2.Compiler.InlineProofProtocolV1
import ProofForgeV2.Source.WireCodecV1

namespace Tests.Compiler.InlineProofProtocolV1

open ProofForgeV2.Compiler.InlineProofProtocolV1
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.WireCodecV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def lift (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

private def expectErr (label : String) (result : Except String α) : IO String :=
  match result with
  | .error error => pure error
  | .ok _ => throw <| IO.userError s!"{label}: expected error"

private def expectErrContains (label needle : String) (result : Except String α) :
    IO Unit := do
  let error ← expectErr label result
  unless error.contains needle do
    throw <| IO.userError s!"{label}: expected error containing '{needle}', got '{error}'"

private def samplePath : IO ProjectRelativePath :=
  lift "path" (parseProjectRelativePath "tests/inline-proof/sample.pf")

private def otherPath : IO ProjectRelativePath :=
  lift "other-path" (parseProjectRelativePath "tests/inline-proof/other.pf")

private def digestOf (label : String) : IO Digest :=
  lift label (domainSeparatedSha256 "proof-forge.inline-proof-test.v1" label.toUTF8)

private def sampleTheoremName : IO QualifiedName :=
  lift "theorem-qn"
    (parseQualifiedName #["ProofedProof", "safe"])

private def sampleObligation : IO InlineProofObligationV1 := do
  let theoremName ← sampleTheoremName
  lift "obligation" <| mkInlineProofObligationV1 "safe" 0 theoremName "safe"

private def sampleRequest
    (sourceBytes : ByteArray := "program Proofed where\n".toUTF8)
    (obligations? : Option (Array InlineProofObligationV1) := none) :
    IO InlineProofRequestV1 := do
  let path ← samplePath
  let sourceHash ← digestOf "source"
  let semanticHash ← digestOf "semantic"
  let provenance ← digestOf "provenance"
  let obligations ← match obligations? with
    | some value => pure value
    | none => pure #[← sampleObligation]
  lift "mk-request" <| mkInlineProofRequestV1
    path "Tests.InlineProof" (some "Proofed") sourceBytes
    sourceHash semanticHash provenance obligations

private def flipByte (bytes : ByteArray) (index : Nat) : ByteArray :=
  Id.run do
    let mut out := bytes
    let previous := out.get! index
    out := out.set! index (previous ^^^ 0x01)
    pure out

private def rawField (bytes : ByteArray) : ByteArray :=
  (encodeU32le (UInt32.ofNat bytes.size)).append bytes

private def testConstants : IO Unit := do
  expect (maxProtocolBytesV1 == 64 * 1024 * 1024) "64 MiB protocol cap"
  expect (maxSourceBytesV1 == 16 * 1024 * 1024) "16 MiB source cap"
  expect (maxSelectorBytesV1 == maxProtocolBytesV1) "selector guard equals protocol"
  expect (maxObligationsV1 == 4096) "obligation cap"
  let policy ← lift "policy" fixedInlineProofPolicyDigestV1
  expect (policy.bytes.size == 32) "fixed policy digest width"
  -- Second evaluation must be identical (caller cannot choose another policy).
  let policy2 ← lift "policy2" fixedInlineProofPolicyDigestV1
  expect (policy == policy2) "fixed policy digest is stable"

private def testRequestRoundTrip : IO Unit := do
  let request ← sampleRequest
  let bytes ← lift "encode-request" (encodeInlineProofRequestV1 request)
  let decoded ← lift "decode-request" (decodeInlineProofRequestV1 bytes)
  let reencoded ← lift "re-encode-request" (encodeInlineProofRequestV1 decoded)
  expect (reencoded == bytes) "request full-consume re-encode identity"
  expect (decoded.sourcePath == request.sourcePath) "source path"
  expect (decoded.moduleSelector == "Tests.InlineProof") "module selector"
  expect (decoded.programSelector == some "Proofed") "program selector"
  expect (decoded.sourceBytes == request.sourceBytes) "source bytes"
  expect (decoded.sourceHash == request.sourceHash) "source hash"
  expect (decoded.semanticHash == request.semanticHash) "semantic hash"
  expect (decoded.semanticProvenanceDigest == request.semanticProvenanceDigest)
    "provenance digest"
  expect (decoded.obligations.size == 1) "one obligation"
  let obligation0 ← match decoded.obligations[0]? with
    | some value => pure value
    | none => throw <| IO.userError "missing obligation row"
  expect (obligation0.invariantName == "safe") "invariant name"
  expect (obligation0.ordinal == 0) "ordinal"
  expect (obligation0.expectedGeneratedName == "safe")
    "generated obligation name"
  let policy ← lift "policy" fixedInlineProofPolicyDigestV1
  expect (decoded.policyDigest == policy) "request binds fixed policy"
  let digest ← lift "request-digest" (inlineProofRequestDigestOfV1 request)
  expect (digest.bytes.size == 32) "request digest width"

private def testSuccessAndFailureRoundTrip : IO Unit := do
  let request ← sampleRequest
  let success ← lift "mk-success" (mkInlineProofSuccessV1 request)
  let successBytes ← lift "encode-success" (encodeInlineProofSuccessV1 success)
  let successDecoded ← lift "decode-success" (decodeInlineProofSuccessV1 successBytes)
  expect ((← lift "re-encode-success"
      (encodeInlineProofSuccessV1 successDecoded)) == successBytes)
    "success re-encode identity"
  expect (success.theoremCount == 1) "theorem count"
  let expectedSet ← lift "set" (theoremSetDigestV1 request.obligations)
  expect (success.theoremSetDigest == expectedSet) "theorem set digest"
  let expectedCert ← lift "cert" <|
    proofCertificationDigestV1 success.requestDigest success.theoremCount
      success.theoremSetDigest
  expect (success.proofCertificationDigest == expectedCert)
    "proofCertificationDigest matches formula"
  let requestDigest ← lift "req-dig" (inlineProofRequestDigestOfV1 request)
  expect (success.requestDigest == requestDigest) "success binds request"

  let failure ← lift "mk-failure"
    (mkInlineProofFailureV1 request .obligation)
  let failureBytes ← lift "encode-failure" (encodeInlineProofFailureV1 failure)
  let failureDecoded ← lift "decode-failure" (decodeInlineProofFailureV1 failureBytes)
  expect ((← lift "re-encode-failure"
      (encodeInlineProofFailureV1 failureDecoded)) == failureBytes)
    "failure re-encode identity"
  expect (failure.phase == .obligation) "failure phase"
  expect (failure.requestDigest == requestDigest) "failure binds request"

  let okResponse := InlineProofResponseV1.success success
  let okBytes ← lift "encode-response-ok" (encodeInlineProofResponseV1 okResponse)
  let okDecoded ← lift "decode-response-ok" (decodeInlineProofResponseV1 okBytes)
  match okDecoded with
  | .success value =>
      expect (value.requestDigest == requestDigest) "response success digest"
  | .failure _ => throw <| IO.userError "expected success response"

  let errResponse := InlineProofResponseV1.failure failure
  let errBytes ← lift "encode-response-err" (encodeInlineProofResponseV1 errResponse)
  let errDecoded ← lift "decode-response-err" (decodeInlineProofResponseV1 errBytes)
  match errDecoded with
  | .failure value =>
      expect (value.phase == .obligation) "response failure phase"
  | .success _ => throw <| IO.userError "expected failure response"

private def testCrossRequestReplay : IO Unit := do
  let requestA ← sampleRequest
  let requestB ← sampleRequest (sourceBytes := "program Other where\n".toUTF8)
  let successA ← lift "success-a" (mkInlineProofSuccessV1 requestA)
  let failureA ← lift "failure-a" (mkInlineProofFailureV1 requestA .subject)
  expectErrContains "bind-success-cross" "cross-request replay"
    (bindInlineProofResponseV1 requestB (.success successA))
  expectErrContains "bind-failure-cross" "cross-request replay"
    (bindInlineProofResponseV1 requestB (.failure failureA))
  let bound ← lift "bind-same"
    (bindInlineProofResponseV1 requestA (.success successA))
  match bound with
  | .success _ => pure ()
  | .failure _ => throw <| IO.userError "same-request success must bind"

private def testTamperAndNoncanonical : IO Unit := do
  let request ← sampleRequest
  let bytes ← lift "encode" (encodeInlineProofRequestV1 request)
  expectErrContains "trailing" "trailing"
    (decodeInlineProofRequestV1 (bytes.push 0))
  expectErrContains "truncated" "truncated"
    (decodeInlineProofRequestV1 (bytes.extract 0 (bytes.size - 1)))
  -- Flip a payload byte after the tag/field-count header. Decode must fail
  -- closed (noncanonical re-encode, path parse, or related structural error).
  let flipped := flipByte bytes (bytes.size - 1)
  match decodeInlineProofRequestV1 flipped with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "tampered request must fail closed"

  let success ← lift "success" (mkInlineProofSuccessV1 request)
  let successBytes ← lift "success-bytes" (encodeInlineProofSuccessV1 success)
  let successFlip := flipByte successBytes (successBytes.size - 1)
  match decodeInlineProofSuccessV1 successFlip with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "tampered success must fail closed"

  -- Wrong policy: craft a near-legal frame with a foreign policy digest.
  let foreignPolicy ← digestOf "foreign-policy"
  let pathS ← lift "path-render" (renderProjectRelativePath request.sourcePath)
  let pathB ← lift "path-enc" (encodeString pathS)
  let modB := rawField request.moduleSelector.toUTF8
  let progB :=
    match request.programSelector with
    | none => encodeU8 0
    | some p => (encodeU8 1).append (rawField p.toUTF8)
  let srcB := rawField request.sourceBytes
  let sourceHashB := request.sourceHash.bytes
  let semanticHashB := request.semanticHash.bytes
  let provenanceB := request.semanticProvenanceDigest.bytes
  let obligationsB ← do
    let ob ← match request.obligations[0]? with
      | some value => pure value
      | none => throw <| IO.userError "fixture missing obligation"
    let nameB ← lift "ob-name" (encodeIdent ob.invariantName)
    let ordB := encodeU32le ob.ordinal
    let thmB ← lift "ob-thm" (encodeQualifiedName ob.theoremName)
    let genB ← lift "ob-gen" (encodeIdent ob.expectedGeneratedName)
    pure ((encodeU32le 1).append
      (((nameB.append ordB).append thmB).append genB))
  let foreignFrame ← lift "foreign-frame" <| encodeTagged "InlineProof.Req.v1"
    #[pathB, modB, progB, srcB, sourceHashB, semanticHashB, provenanceB,
      obligationsB, foreignPolicy.bytes]
  expectErrContains "foreign-policy" "fixed authority"
    (decodeInlineProofRequestV1 foreignFrame)

  -- Noncanonical path spelling if any NFC/path normalization applies; empty
  -- path is rejected by ProjectRelativePath.
  let emptyPathFrame ← lift "empty-path-frame" <| encodeTagged "InlineProof.Req.v1"
    #[← lift "empty-path" (encodeString ""),
      modB, progB, srcB, sourceHashB, semanticHashB, provenanceB,
      obligationsB, (← lift "policy" fixedInlineProofPolicyDigestV1).bytes]
  match decodeInlineProofRequestV1 emptyPathFrame with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "empty sourcePath must fail closed"

private def testUnknownPhase : IO Unit := do
  let request ← sampleRequest
  let requestDigest ← lift "digest" (inlineProofRequestDigestOfV1 request)
  let digB := requestDigest.bytes
  let unknownPhase := encodeU8 0xff
  let frame ← lift "unknown-phase-frame" <|
    encodeTagged "InlineProof.Err.v1" #[digB, unknownPhase]
  expectErrContains "unknown-phase" "unknown inline-proof failure phase"
    (decodeInlineProofFailureV1 frame)
  expectErrContains "unknown-phase-response" "unknown inline-proof failure phase"
    (decodeInlineProofResponseV1 frame)

  -- Every closed phase must round-trip.
  for phase in
      #[InlineProofFailurePhaseV1.request, .policy, .subject,
        .obligation, .certification, .internal] do
    let failure ← lift s!"mk-{repr phase}" (mkInlineProofFailureV1 request phase)
    let bytes ← lift s!"enc-{repr phase}" (encodeInlineProofFailureV1 failure)
    let decoded ← lift s!"dec-{repr phase}" (decodeInlineProofFailureV1 bytes)
    expect (decoded.phase == phase) s!"phase round-trip {repr phase}"

private def testOversizeBombs : IO Unit := do
  -- Protocol aggregate precheck: constant-locked (do not allocate 64 MiB+1).
  expect (maxProtocolBytesV1 == 67108864) "protocol cap constant lock"
  -- Source length bomb: declared length maxSourceBytes+1 rejects before copy.
  let path ← samplePath
  let pathS ← lift "path" (renderProjectRelativePath path)
  let pathB ← lift "pathB" (encodeString pathS)
  let modB := rawField "M".toUTF8
  let progB := encodeU8 0
  let bombLen := maxSourceBytesV1 + 1
  let srcBomb := encodeU32le (UInt32.ofNat bombLen)  -- no payload
  let zeroDigest := (← digestOf "z").bytes
  let emptyObligations := encodeU32le 0
  let policy ← lift "policy" fixedInlineProofPolicyDigestV1
  let bombFrame ← lift "source-bomb" <| encodeTagged "InlineProof.Req.v1"
    #[pathB, modB, progB, srcBomb, zeroDigest, zeroDigest, zeroDigest,
      emptyObligations, policy.bytes]
  expectErrContains "source-oversize" "exceeds limit"
    (decodeInlineProofRequestV1 bombFrame)

  -- Obligation count bomb: declared maxObligations+1 rejects before row decode.
  let srcB := rawField ByteArray.empty
  let oblBomb := encodeU32le (UInt32.ofNat (maxObligationsV1 + 1))
  let oblFrame ← lift "obligation-bomb" <| encodeTagged "InlineProof.Req.v1"
    #[pathB, modB, progB, srcB, zeroDigest, zeroDigest, zeroDigest,
      oblBomb, policy.bytes]
  expectErrContains "obligation-oversize" "exceeds limit"
    (decodeInlineProofRequestV1 oblFrame)

  -- mk/encode oversize for sourceBytes is covered by the declared-length bomb
  -- above (no multi-MiB allocation in this unit suite). Aggregate max is
  -- constant-locked to 64 MiB.
  expect (maxProtocolBytesV1 > maxSourceBytesV1) "source budget is nested"

private def testDuplicateObligations : IO Unit := do
  let theoremName ← sampleTheoremName
  let a ← lift "a" (mkInlineProofObligationV1 "safe" 0 theoremName "safe")
  let b ← lift "b" (mkInlineProofObligationV1 "safe" 1 theoremName "safe")
  let path ← samplePath
  let sourceHash ← digestOf "source"
  let semanticHash ← digestOf "semantic"
  let provenance ← digestOf "provenance"
  expectErrContains "dup-name" "duplicate invariant name"
    (mkInlineProofRequestV1 path "M" none "x".toUTF8
      sourceHash semanticHash provenance #[a, b])
  let c ← lift "c" (mkInlineProofObligationV1 "other" 0 theoremName "other")
  expectErrContains "dup-ordinal" "duplicate ordinal"
    (mkInlineProofRequestV1 path "M" none "x".toUTF8
      sourceHash semanticHash provenance #[a, c])
  let d ← lift "d" (mkInlineProofObligationV1 "other" 1 theoremName "other")
  expectErrContains "dup-theorem" "duplicate theorem name"
    (mkInlineProofRequestV1 path "M" none "x".toUTF8
      sourceHash semanticHash provenance #[a, d])

private def testWrongTagAndFieldCount : IO Unit := do
  let request ← sampleRequest
  let pathS ← lift "path" (renderProjectRelativePath request.sourcePath)
  let pathB ← lift "pathB" (encodeString pathS)
  let modB := rawField request.moduleSelector.toUTF8
  let progB :=
    match request.programSelector with
    | none => encodeU8 0
    | some p => (encodeU8 1).append (rawField p.toUTF8)
  let srcB := rawField request.sourceBytes
  let policy ← lift "policy" fixedInlineProofPolicyDigestV1
  let wrongTag ← lift "wrong-tag" <| encodeTagged "InlineProof.Bad.v1"
    #[pathB, modB, progB, srcB, request.sourceHash.bytes,
      request.semanticHash.bytes, request.semanticProvenanceDigest.bytes,
      encodeU32le 0, policy.bytes]
  expectErrContains "wrong-tag" "expected tag"
    (decodeInlineProofRequestV1 wrongTag)

  -- Field-count mismatch: fewer fields than the 9-field request layout.
  let short ← lift "short-fields" <| encodeTagged "InlineProof.Req.v1"
    #[pathB, modB, progB, srcB, request.sourceHash.bytes,
      request.semanticHash.bytes, request.semanticProvenanceDigest.bytes,
      encodeU32le 0]
  match decodeInlineProofRequestV1 short with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "field-count mismatch must fail closed"

def run : IO Unit := do
  testConstants
  testRequestRoundTrip
  testSuccessAndFailureRoundTrip
  testCrossRequestReplay
  testTamperAndNoncanonical
  testUnknownPhase
  testOversizeBombs
  testDuplicateObligations
  testWrongTagAndFieldCount

end Tests.Compiler.InlineProofProtocolV1
