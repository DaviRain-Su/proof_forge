/-
  Canonical compiler proof-worker protocol/direct/subprocess engineering tests.
  These tests do not claim process containment or formal TST-PROOF-001 evidence.
-/
import ProofForgeV2.Compiler.ProofWorkerV1
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Source.WireCodecV1
import Tests.Language.ParserSession

namespace Tests.Compiler.ProofWorkerV1

open ProofForgeV2
open ProofForgeV2.Compiler.ProofSubjectFilesV1
open ProofForgeV2.Compiler.ProofWorkerProtocolV1
open ProofForgeV2.Compiler.ProofWorkerV1
open ProofForgeV2.Core.Common
open ProofForgeV2.Frontend.ProtocolV1
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ProofSubjectV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireCodecV1
open ProofForgeV2.Source.WireV1
open System

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def lift (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

private def sourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program ProofWorker where\n" ++
  "  entry truth() : UInt64 do\n" ++
  "    return 17\n"

private def sourcePathString : String := "tests/proof-worker-source.pf"
private def moduleSelector : String := "Tests.ProofWorkerV1"

private structure Fixture where
  root : FilePath
  request : ProofWorkerRequestV1
  requestBytes : ByteArray
  frontendRequestBytes : ByteArray
  frontendSuccessBytes : ByteArray
  subject : ProofSubjectV1

private def resetRoot (path : FilePath) : IO FilePath := do
  try IO.FS.removeDirAll path catch _ => pure ()
  IO.FS.createDirAll path
  IO.FS.realPath path

private unsafe def makeFixture : IO Fixture := do
  let path ← lift "path" (parseProjectRelativePath sourcePathString)
  let frontendRequest ← lift "frontend request" <| mkFrontendRequestV1
    { major := 1, minor := 0, patch := 0 } path moduleSelector none
    sourceText.toUTF8
  let session ← Tests.Language.ParserSession.shared
  let (source, rawSpans) ← match ← session.selectProgramV1FrontendPayload
      sourceText sourcePathString moduleSelector none with
    | .ok value => pure value
    | .error bundle => throw <| IO.userError s!"frontend fixture: {bundle.renderHuman}"
  let frontendSuccess ← lift "frontend success"
    (mkFrontendSuccessV1 frontendRequest source rawSpans)
  let frontendRequestBytes ← lift "encode frontend request"
    (encodeFrontendRequestV1 frontendRequest)
  let frontendSuccessBytes ← lift "encode frontend success"
    (encodeFrontendSuccessV1 frontendSuccess)
  let (_, spans) ← lift "trusted reconstruction"
    (reconstructFrontendSourceSpansV1 frontendRequest frontendSuccess)
  let (carrier, provenance) ← match
      normalizeProgramWithProvenanceV1 source path spans with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"normalize: {repr error}"
  let provenanceBytes ← match encodeSemanticProvenanceV1 provenance with
    | .ok bytes => pure bytes
    | .error error => throw <| IO.userError s!"provenance encode: {repr error}"
  let cwd ← IO.currentDir
  let root ← resetRoot (cwd / "build/proof-worker-v1")
  IO.FS.writeBinFile (root / semanticProgramFileNameV1) carrier.canonicalBytes
  IO.FS.writeBinFile (root / semanticProvenanceFileNameV1) provenanceBytes
  let subject ← match buildProofSubjectV1 source path spans
      carrier.canonicalBytes provenanceBytes with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"direct subject: {repr error}"
  let request ← lift "proof request" <| mkProofWorkerRequestV1 root
    frontendRequestBytes frontendSuccessBytes
  let requestBytes ← lift "encode proof request"
    (encodeProofWorkerRequestV1 request)
  pure ⟨root, request, requestBytes, frontendRequestBytes,
    frontendSuccessBytes, subject⟩

private def decodeResponse (bytes : ByteArray) : IO ProofWorkerResponseV1 :=
  lift "decode proof response" (decodeProofWorkerResponseV1 bytes)

private def rawField (bytes : ByteArray) : ByteArray :=
  (ProofForgeV2.Source.WireCodecV1.encodeU32le
    (UInt32.ofNat bytes.size)).append bytes

private def rawOuterRequest
    (root : FilePath) (frontendRequest frontendSuccess : ByteArray) : IO ByteArray :=
  lift "raw outer request" <| encodeTagged "CompilerProof.Req.v1"
    #[rawField root.toString.toUTF8, rawField frontendRequest,
      rawField frontendSuccess]

private def expectSuccessParity
    (fixture : Fixture) (bytes : ByteArray) : IO Unit := do
  let response ← decodeResponse bytes
  let response ← lift "bind proof response"
    (bindProofWorkerResponseV1 fixture.request response)
  match response with
  | .failure failure =>
      throw <| IO.userError s!"unexpected failure: {failure.phase}"
  | .success success => do
      expect (success.sourceHash == fixture.subject.sourceHash)
        "worker sourceHash parity"
      expect (success.semanticHash == fixture.subject.semanticHash)
        "worker semanticHash parity"
      expect (success.semanticProvenanceDigest ==
        fixture.subject.semanticProvenanceDigest)
        "worker semantic provenance digest parity"
      expect (success.requestDigest ==
        (← lift "request digest" (proofWorkerRequestDigestV1 fixture.request)))
        "worker response binds exact request"

private unsafe def testProtocolAndDirect : IO Unit := do
  let fixture ← makeFixture
  let decoded ← lift "request decode"
    (decodeProofWorkerRequestV1 fixture.requestBytes)
  expect ((← lift "request re-encode" (encodeProofWorkerRequestV1 decoded)) ==
    fixture.requestBytes) "request canonical round-trip"
  expect (match decodeProofWorkerRequestV1
      (fixture.requestBytes.push 0) with
    | .error _ => true | .ok _ => false) "request trailing byte rejected"
  expect (match decodeProofWorkerRequestV1
      (fixture.requestBytes.extract 0 (fixture.requestBytes.size - 1)) with
    | .error _ => true | .ok _ => false)
    "request truncation rejected"

  -- Cross-request replay is rejected by the smart constructor before any root
  -- file is opened, even when the supplied root does not exist.
  let path ← lift "other path" (parseProjectRelativePath sourcePathString)
  let other ← lift "other frontend request" <| mkFrontendRequestV1
    { major := 1, minor := 0, patch := 0 } path moduleSelector none
    (sourceText ++ "\n").toUTF8
  let otherBytes ← lift "other bytes" (encodeFrontendRequestV1 other)
  expect (match mkProofWorkerRequestV1 (FilePath.mk "/definitely/not/read")
      otherBytes fixture.frontendSuccessBytes with
    | .error _ => true | .ok _ => false)
    "frontend request/success mismatch rejected before filesystem access"
  let malformedNested ← rawOuterRequest (FilePath.mk "/definitely/not/read")
    fixture.frontendRequestBytes (fixture.frontendSuccessBytes.push 0)
  expect (match decodeProofWorkerRequestV1 malformedNested with
    | .error _ => true | .ok _ => false)
    "noncanonical nested frontend success rejected before filesystem access"
  let malformedRequest ← rawOuterRequest (FilePath.mk "/definitely/not/read")
    (fixture.frontendRequestBytes.push 0) fixture.frontendSuccessBytes
  expect (match decodeProofWorkerRequestV1 malformedRequest with
    | .error _ => true | .ok _ => false)
    "noncanonical nested frontend request rejected before filesystem access"

  let output ← match ← processFrameV1 fixture.requestBytes with
    | .ok bytes => pure bytes
    | .error fault => throw <| IO.userError s!"direct worker fault: {repr fault}"
  expectSuccessParity fixture output
  let output2 ← match ← processFrameV1 fixture.requestBytes with
    | .ok bytes => pure bytes
    | .error fault => throw <| IO.userError s!"repeat worker fault: {repr fault}"
  expect (output == output2) "direct worker response determinism"

  match ← processFrameV1 (ByteArray.mk #[0]) with
  | .error .protocol => pure ()
  | .error fault => throw <| IO.userError s!"malformed wrong fault: {repr fault}"
  | .ok _ => throw <| IO.userError "malformed frame unexpectedly succeeded"

  let missingRequest ← lift "missing-root request" <| mkProofWorkerRequestV1
    (FilePath.mk "/definitely/missing/proof-worker-root")
    fixture.frontendRequestBytes fixture.frontendSuccessBytes
  let outputResponse ← decodeResponse output
  expect (match bindProofWorkerResponseV1 missingRequest outputResponse with
    | .error _ => true | .ok _ => false)
    "success response rejected for a different proof-worker request"
  let missingBytes ← lift "missing-root bytes" (encodeProofWorkerRequestV1 missingRequest)
  let missingOutput ← match ← processFrameV1 missingBytes with
    | .ok bytes => pure bytes
    | .error fault => throw <| IO.userError s!"missing root worker fault: {repr fault}"
  match ← decodeResponse missingOutput with
  | .failure failure => do
      expect (failure.phase == "root") "root failure phase preserved"
      expect (failure.fault == some .notFound) "root not-found detail preserved"
  | .success _ => throw <| IO.userError "missing root unexpectedly succeeded"

  -- Semantic authority failures are valid deterministic response frames.
  IO.FS.writeBinFile (fixture.root / semanticProvenanceFileNameV1) ByteArray.empty
  let semanticOutput ← match ← processFrameV1 fixture.requestBytes with
    | .ok bytes => pure bytes
    | .error fault => throw <| IO.userError s!"semantic worker fault: {repr fault}"
  match ← decodeResponse semanticOutput with
  | .failure failure =>
      expect (failure.phase == "semantic-provenance-wire")
        "semantic provenance phase preserved"
  | .success _ => throw <| IO.userError "empty provenance unexpectedly succeeded"
  pure ()

private def workerBin : FilePath :=
  FilePath.mk ".lake/build/bin/proof-forge-compiler-proof-worker-v1"

private partial def readBinaryToEnd
    (handle : IO.FS.Handle) (acc : ByteArray := ByteArray.empty) : IO ByteArray := do
  let chunk ← handle.read (USize.ofNat (64 * 1024))
  if chunk.isEmpty then pure acc
  else
    let next := acc.append chunk
    if next.size > maxProofWorkerProtocolBytesV1 + 1 then
      throw <| IO.userError "proof worker stdout exceeded protocol bound"
    readBinaryToEnd handle next

private def runWorkerProcess (input : ByteArray) :
    IO (UInt32 × ByteArray × String) := do
  let child0 ← IO.Process.spawn {
    cmd := workerBin.toString
    stdin := .piped
    stdout := .piped
    stderr := .piped
  }
  let child ← do
    let (childIn, child) ← child0.takeStdin
    childIn.write input
    childIn.flush
    pure child
  let stdoutHandle : IO.FS.Handle := by
    simpa [IO.Process.Stdio.toHandleType] using child.stdout
  let stderrHandle : IO.FS.Handle := by
    simpa [IO.Process.Stdio.toHandleType] using child.stderr
  let stdout ← readBinaryToEnd stdoutHandle
  let stderr ← stderrHandle.readToEnd
  let exitCode ← child.wait
  pure (exitCode, stdout, stderr)

private unsafe def testSubprocess : IO Unit := do
  expect (← workerBin.pathExists) s!"proof worker binary missing: {workerBin}"
  -- Restore the positive pair after the direct semantic-failure check.
  let fresh ← makeFixture
  let direct ← match ← processFrameV1 fresh.requestBytes with
    | .ok bytes => pure bytes
    | .error fault => throw <| IO.userError s!"subprocess direct fault: {repr fault}"
  let (exitCode, stdout, stderr) ← runWorkerProcess fresh.requestBytes
  expect (exitCode == 0) s!"proof worker exit={exitCode}, stderr={stderr}"
  expect (stderr == "") s!"proof worker success stderr: {repr stderr}"
  expect (stdout == direct) "real subprocess exact direct-worker parity"
  expectSuccessParity fresh stdout

  let missingRequest ← lift "subprocess missing request" <|
    mkProofWorkerRequestV1 (FilePath.mk "/definitely/missing/proof-worker-root")
      fresh.frontendRequestBytes fresh.frontendSuccessBytes
  let missingInput ← lift "subprocess missing input"
    (encodeProofWorkerRequestV1 missingRequest)
  let missingDirect ← match ← processFrameV1 missingInput with
    | .ok bytes => pure bytes
    | .error fault => throw <| IO.userError s!"missing direct fault: {repr fault}"
  let (missingExit, missingOut, missingErr) ← runWorkerProcess missingInput
  expect (missingExit == 0 && missingErr == "")
    "valid filesystem failure exits zero with empty stderr"
  expect (missingOut == missingDirect)
    "filesystem failure subprocess/direct exact parity"
  match ← decodeResponse missingOut with
  | .failure failure =>
      expect (failure.phase == "root" && failure.fault == some .notFound)
        "subprocess root failure preserved"
  | .success _ => throw <| IO.userError "missing subprocess root succeeded"

  let (badExit, badOut, badErr) ← runWorkerProcess (ByteArray.mk #[0])
  expect (badExit == UInt32.ofNat protocolExitCodeV1.toNat)
    "malformed subprocess protocol exit"
  expect badOut.isEmpty "malformed subprocess stdout empty"
  expect (badErr == protocolStderrTokenV1 ++ "\n")
    "malformed subprocess stable stderr token"

unsafe def run : IO Unit := do
  testProtocolAndDirect
  testSubprocess
  IO.println "Tests.Compiler.ProofWorkerV1: ok"

end Tests.Compiler.ProofWorkerV1
