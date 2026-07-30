/-
  Tests.Frontend.SafeOpenWorkerV1 — B11b2 safe-open protocol/process suite.

  Independent coverage for the standalone helper: closed wire round-trips,
  direct safe-open processing, bounded stdin chunking, and real subprocess
  success/failure/abnormal exits. This suite intentionally imports neither
  Frontend.WorkerV1 nor Language.Loader.

  Non-claims: not CLI cutover, containment, formal TST-RESOURCE-001, or
  TASK-D1-08 completion.
-/
import ProofForgeV2.Frontend.SafeOpenWorkerV1
import ProofForgeV2.Source.WireCodecV1

namespace Tests.Frontend.SafeOpenWorkerV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Frontend.ProtocolV1
open ProofForgeV2.Frontend.SafeOpenV1
open ProofForgeV2.Frontend.SafeOpenWorkerProtocolV1
open ProofForgeV2.Frontend.SafeOpenWorkerV1
open ProofForgeV2.Source.WireCodecV1
open System

private def expect (condition : Bool) (message : String) : IO Unit := do
  unless condition do throw <| IO.userError message

private def lift (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

private def exceptIsError : Except α β → Bool
  | .error _ => true
  | .ok _ => false

private def fixtureRoot : FilePath :=
  FilePath.mk "build/v2/safe-open-worker-tests"

private def workerBin : FilePath :=
  FilePath.mk ".lake/build/bin/proof-forge-frontend-safe-open-worker-v1"

private def resetFixtureRoot : IO Unit := do
  try IO.FS.removeDirAll fixtureRoot catch _ => pure ()
  IO.FS.createDirAll fixtureRoot

private def cleanupFixtureRoot : IO Unit := do
  try IO.FS.removeDirAll fixtureRoot catch _ => pure ()

private def requestFor
    (root : FilePath) (relative : String) : IO SafeOpenWorkerRequestV1 := do
  let path ← lift "relative path" (parseProjectRelativePath relative)
  lift "safe-open request" (mkSafeOpenWorkerRequestV1 root path)

private def repeatedByte (size : Nat) (value : UInt8) : ByteArray :=
  ByteArray.mk (Array.replicate size value)

private def testProtocolRoundTrips : IO Unit := do
  resetFixtureRoot
  let root ← IO.FS.realPath fixtureRoot
  let request ← requestFor root "nested/source.lean"
  let requestBytes ← lift "encode request" (encodeSafeOpenWorkerRequestV1 request)
  let decoded ← lift "decode request" (decodeSafeOpenWorkerRequestV1 requestBytes)
  expect (SafeOpenWorkerRequestV1.root decoded == root)
    "request root round-trip"
  expect (SafeOpenWorkerRequestV1.maxSourceBytes decoded == maxSourceBytes)
    "request maxSourceBytes is frozen"
  expect ((← lift "render decoded path"
      (renderProjectRelativePath (SafeOpenWorkerRequestV1.path decoded))) ==
      "nested/source.lean")
    "request relative path round-trip"

  let foreignRequest ← requestFor root "nested/foreign.lean"
  let payload := "safe-open-worker-payload\n".toUTF8
  let success ← lift "success" (mkSafeOpenWorkerSuccessV1 request payload)
  let successBytes ← lift "encode success" (encodeSafeOpenWorkerSuccessV1 success)
  let successResponse ← lift "decode success response"
    (decodeSafeOpenWorkerResponseV1 successBytes)
  match successResponse with
  | .failure _ => throw <| IO.userError "success decoded as failure"
  | .success decoded =>
      expect (SafeOpenWorkerSuccessV1.bytes decoded == payload)
        "success payload identity"
  let _ ← lift "bind success to request"
    (bindSafeOpenWorkerResponseV1 request successResponse)
  expect (exceptIsError (bindSafeOpenWorkerResponseV1 foreignRequest successResponse))
    "canonical success replay across safe-open requests must be rejected"

  let faults : Array SafeOpenFaultV1 := #[
    .invalidRoot, .notFound, .permissionDenied, .unsafePath, .nonRegular,
    .multipleLinks, .tooLarge, .shortRead, .grewDuringRead,
    .changedDuringRead, .io, .nativeProtocol
  ]
  for fault in faults do
    let failure ← lift "failure" (mkSafeOpenWorkerFailureV1 request fault)
    let bytes ← lift "encode failure" (encodeSafeOpenWorkerFailureV1 failure)
    let failureResponse ← lift "decode failure response"
      (decodeSafeOpenWorkerResponseV1 bytes)
    match failureResponse with
    | .success _ => throw <| IO.userError s!"{fault.wire}: decoded as success"
    | .failure decoded =>
        expect (SafeOpenWorkerFailureV1.fault decoded == fault)
          s!"{fault.wire}: fault identity"
    let _ ← lift "bind failure to request"
      (bindSafeOpenWorkerResponseV1 request failureResponse)
    expect (exceptIsError (bindSafeOpenWorkerResponseV1 foreignRequest failureResponse))
      s!"{fault.wire}: canonical failure replay must be rejected"

  match mkSafeOpenWorkerRequestV1 (FilePath.mk "relative-root")
      (SafeOpenWorkerRequestV1.path request) with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "relative root must be rejected"
  match mkSafeOpenWorkerSuccessV1 request
      (repeatedByte (maxSourceBytes + 1) 0x61) with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "oversize success must be rejected"

  let truncated := requestBytes.extract 0 (requestBytes.size - 1)
  expect (exceptIsError (decodeSafeOpenWorkerRequestV1 truncated))
    "truncated request rejected"
  expect (exceptIsError (decodeSafeOpenWorkerRequestV1 (requestBytes.push 0)))
    "trailing request byte rejected"
  let unknownWire ← lift "unknown wire" (encodeString "undefined")
  let requestDigest ← lift "unknown wire request digest"
    (safeOpenWorkerRequestDigestOfV1 request)
  let unknownFrame ← lift "unknown failure frame"
    (encodeTagged "SafeOpen.Err.v1" #[requestDigest.bytes, unknownWire])
  expect (exceptIsError (decodeSafeOpenWorkerResponseV1 unknownFrame))
    "unknown SafeOpenFault wire rejected"
  let rootBomb := encodeU32le (UInt32.ofNat (maxSafeOpenProtocolBytesV1 + 1))
  let declaredBomb ← lift "declared root bomb"
    (encodeTagged "SafeOpen.Req.v1" #[rootBomb, ByteArray.empty, ByteArray.empty])
  expect (exceptIsError (decodeSafeOpenWorkerRequestV1 declaredBomb))
    "declared root length over protocol cap rejected before allocation"

private def testIndependentBoundedRead : IO Unit := do
  let input := repeatedByte (130 * 1024) 0x5a
  let offset ← IO.mkRef 0
  let calls ← IO.mkRef 0
  let largestRequest ← IO.mkRef 0
  let stream : IO.FS.Stream := {
    flush := pure ()
    read := fun wanted => do
      calls.modify (· + 1)
      largestRequest.modify (max · wanted.toNat)
      let currentOffset ← offset.get
      if currentOffset ≥ input.size then
        pure ByteArray.empty
      else
        let next := Nat.min input.size (currentOffset + wanted.toNat)
        offset.set next
        pure (input.extract currentOffset next)
    write := fun _ => pure ()
    getLine := pure ""
    putStr := fun _ => pure ()
    isTty := pure false
  }
  match ← readProtocolFrameV1 stream with
  | .error fault => throw <| IO.userError s!"bounded read fault: {repr fault}"
  | .ok bytes => expect (bytes == input) "bounded read preserves input bytes"
  expect ((← calls.get) ≥ 4) "bounded read must use multiple chunks plus EOF probe"
  expect ((← largestRequest.get) ≤ 64 * 1024)
    "bounded read must never request more than its fixed chunk"

private def decodeWorkerResponse
    (label : String) (bytes : ByteArray) : IO SafeOpenWorkerResponseV1 :=
  lift label (decodeSafeOpenWorkerResponseV1 bytes)

private def testDirectProcessing : IO Unit := do
  resetFixtureRoot
  let root ← IO.FS.realPath fixtureRoot
  let payload := "direct-safe-open\n".toUTF8
  IO.FS.writeBinFile (fixtureRoot / "source.lean") payload
  let request ← requestFor root "source.lean"
  let input ← lift "direct request bytes" (encodeSafeOpenWorkerRequestV1 request)
  match ← processFrameV1 input with
  | .error fault => throw <| IO.userError s!"direct worker fault: {repr fault}"
  | .ok response =>
      match ← decodeWorkerResponse "direct success response" response with
      | .failure failure =>
          throw <| IO.userError s!"direct open failed: {repr (SafeOpenWorkerFailureV1.fault failure)}"
      | .success success =>
          expect (SafeOpenWorkerSuccessV1.bytes success == payload)
            "direct process snapshot identity"

  let missing ← requestFor root "missing.lean"
  let missingInput ← lift "missing request bytes"
    (encodeSafeOpenWorkerRequestV1 missing)
  match ← processFrameV1 missingInput with
  | .error fault => throw <| IO.userError s!"missing became abnormal: {repr fault}"
  | .ok response =>
      match ← decodeWorkerResponse "missing response" response with
      | .success _ => throw <| IO.userError "missing source unexpectedly succeeded"
      | .failure failure =>
          expect (SafeOpenWorkerFailureV1.fault failure == .notFound)
            "missing source carries closed not-found fault"

  match ← processFrameV1 (ByteArray.mk #[0]) with
  | .error .protocol => pure ()
  | .error other => throw <| IO.userError s!"malformed wrong fault: {repr other}"
  | .ok _ => throw <| IO.userError "malformed frame unexpectedly succeeded"

private partial def readBinaryToEnd
    (handle : IO.FS.Handle) (acc : ByteArray := ByteArray.empty) : IO ByteArray := do
  let chunk ← handle.read (USize.ofNat (64 * 1024))
  if chunk.isEmpty then
    pure acc
  else
    let next := acc.append chunk
    if next.size > maxSafeOpenProtocolBytesV1 + 1 then
      throw <| IO.userError "safe-open worker stdout exceeded protocol bound"
    readBinaryToEnd handle next

private def runWorkerProcess
    (input : ByteArray) (args : Array String := #[]) :
    IO (UInt32 × ByteArray × String) := do
  let child0 ← IO.Process.spawn {
    cmd := workerBin.toString
    args
    stdin := .piped
    stdout := .piped
    stderr := .piped
    inheritEnv := false
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

private def exit32 (code : UInt8) : UInt32 := UInt32.ofNat code.toNat

private def testRealProcess : IO Unit := do
  expect (← workerBin.pathExists) s!"safe-open worker missing: {workerBin}"
  resetFixtureRoot
  let root ← IO.FS.realPath fixtureRoot
  let payload := "subprocess-safe-open\n".toUTF8
  IO.FS.writeBinFile (fixtureRoot / "source.lean") payload
  let request ← requestFor root "source.lean"
  let input ← lift "subprocess request" (encodeSafeOpenWorkerRequestV1 request)

  let (ec1, out1, err1) ← runWorkerProcess input
  expect (ec1 == 0 && err1.isEmpty)
    s!"valid open process exit={ec1}, stderr={repr err1}"
  match ← decodeWorkerResponse "subprocess success" out1 with
  | .failure failure =>
      throw <| IO.userError s!"subprocess open failed: {repr (SafeOpenWorkerFailureV1.fault failure)}"
  | .success success =>
      expect (SafeOpenWorkerSuccessV1.bytes success == payload)
        "subprocess snapshot identity"
  let (ec2, out2, err2) ← runWorkerProcess input
  expect (ec2 == 0 && err2.isEmpty && out2 == out1)
    "two safe-open worker processes produce deterministic bytes"

  let missing ← requestFor root "missing.lean"
  let missingInput ← lift "subprocess missing request"
    (encodeSafeOpenWorkerRequestV1 missing)
  let (missingEc, missingOut, missingErr) ← runWorkerProcess missingInput
  expect (missingEc == 0 && missingErr.isEmpty)
    "canonical SafeOpen.Err.v1 exits zero with empty stderr"
  match ← decodeWorkerResponse "subprocess missing" missingOut with
  | .success _ => throw <| IO.userError "subprocess missing unexpectedly succeeded"
  | .failure failure =>
      expect (SafeOpenWorkerFailureV1.fault failure == .notFound)
        "subprocess missing closed fault"

  let (malEc, malOut, malErr) ← runWorkerProcess (ByteArray.mk #[0])
  expect (malEc == exit32 protocolExitCodeV1)
    s!"malformed exit expected {protocolExitCodeV1}, got {malEc}"
  expect malOut.isEmpty "malformed process stdout must be empty"
  expect (malErr == protocolStderrTokenV1 ++ "\n")
    "malformed process stable protocol token"

  let truncated := input.extract 0 (input.size - 1)
  let (trEc, trOut, trErr) ← runWorkerProcess truncated
  expect (trEc == exit32 protocolExitCodeV1 && trOut.isEmpty &&
      trErr == protocolStderrTokenV1 ++ "\n")
    "truncated process request is closed protocol exit"

  let rootBomb := encodeU32le (UInt32.ofNat (maxSafeOpenProtocolBytesV1 + 1))
  let declaredBomb ← lift "process declared bomb"
    (encodeTagged "SafeOpen.Req.v1" #[rootBomb, ByteArray.empty, ByteArray.empty])
  let (bombEc, bombOut, bombErr) ← runWorkerProcess declaredBomb
  expect (bombEc == exit32 protocolExitCodeV1 && bombOut.isEmpty &&
      bombErr == protocolStderrTokenV1 ++ "\n")
    "declared length bomb is closed protocol exit"

  let (argEc, argOut, argErr) ← runWorkerProcess ByteArray.empty #["extra"]
  expect (argEc == exit32 usageExitCodeV1 && argOut.isEmpty &&
      argErr == usageStderrTokenV1 ++ "\n")
    "argv misuse is stable usage exit"

private def runMatrix : IO Unit := do
  try
    testProtocolRoundTrips
    testIndependentBoundedRead
    testDirectProcessing
    testRealProcess
  finally
    cleanupFixtureRoot

unsafe def runFast : IO Unit := do
  runMatrix
  IO.println "Tests.Frontend.SafeOpenWorkerV1 (fast): ok"

unsafe def run : IO Unit := do
  runMatrix
  IO.println "Tests.Frontend.SafeOpenWorkerV1: ok"

end Tests.Frontend.SafeOpenWorkerV1
