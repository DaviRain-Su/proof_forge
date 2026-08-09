/-
  Tests.Frontend.WorkerV1 — B10 standalone one-request frontend worker.

  Direct and real-subprocess coverage. The worker remains non-product and
  uncontained; tests never treat ordinary CI as containment evidence.
-/
import ProofForgeV2.Frontend.WorkerV1
import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Language.Loader
import ProofForgeV2.Source.WireCodecV1
import Tests.Language.ParserSession

namespace Tests.Frontend.WorkerV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Frontend.ProtocolV1
open ProofForgeV2.Frontend.WorkerV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireCodecV1
open System

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def lift (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

private def requestWith
    (source : ByteArray)
    (moduleName : String)
    (pathValue : String)
    (version : SemVer := languageVersion100V1)
    (programSelector : Option String := none) : IO FrontendRequestV1 := do
  let path ← lift "path" (parseProjectRelativePath pathValue)
  lift "request" <| mkFrontendRequestV1 version path moduleName programSelector source

private def stateCellRequest
    (source : ByteArray := Examples.stateCellSourceText.toUTF8)
    (version : SemVer := languageVersion100V1) : IO FrontendRequestV1 :=
  requestWith source Examples.stateCellModuleNameV1 "Examples/StateCell.lean" version

private def decodeResponse (bytes : ByteArray) : IO FrontendResponseV1 :=
  lift "decode response" (decodeFrontendResponseV1 bytes)

private def expectFailureCode
    (label : String) (expected : DiagnosticCodeV1) (response : ByteArray) : IO Unit := do
  match ← decodeResponse response with
  | .success _ => throw <| IO.userError s!"{label}: expected failure frame"
  | .failure failure =>
      let diagnostics := FrontendFailureV1.diagnostics failure
      expect (!diagnostics.isEmpty) s!"{label}: empty diagnostics"
      expect (diagnostics.any (fun d => d.code == expected))
        s!"{label}: missing {expected.wire} in {diagnostics.map (·.code.wire)}"

private unsafe def workerSuccess
    (request : FrontendRequestV1) : IO (ByteArray × FrontendSuccessV1) := do
  match ← processFrameV1 (← lift "encode request" (encodeFrontendRequestV1 request)) with
  | .error fault => throw <| IO.userError s!"worker fault: {repr fault}"
  | .ok response =>
      match ← decodeResponse response with
      | .failure failure =>
          throw <| IO.userError
            s!"unexpected diagnostic: {DiagnosticBundleV1.renderHuman (FrontendFailureV1.bundle failure)}"
      | .success success => pure (response, success)

private unsafe def testDirectStateCellSuccessAndParity : IO Unit := do
  let request ← stateCellRequest
  let (_response, success) ← workerSuccess request
  let (source, inv) ← lift "reconstruct" (reconstructFrontendSuccessV1 request success)
  let hash ← lift "hash" (sourceHashV1 source)
  expect (hash == originInventorySourceHashV1 inv)
    "worker success inventory binds sourceHash"
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1Product Examples.stateCellSourceText
      "Examples/StateCell.lean" Examples.stateCellModuleNameV1 none with
  | .error bundle =>
      throw <| IO.userError s!"product parity load: {DiagnosticBundleV1.renderHuman bundle}"
  | .ok (directSource, directInv) =>
      expect ((← lift "worker canonical" (canonicalValidatedSourceAstBytesV1 source)) ==
        (← lift "direct canonical" (canonicalValidatedSourceAstBytesV1 directSource)))
        "worker/product canonical source parity"
      expect (originInventoryOriginsV1 inv == originInventoryOriginsV1 directInv)
        "worker/product origin inventory parity"
  match ← session.selectProgramV1FrontendPayload Examples.stateCellSourceText
      "Examples/StateCell.lean" Examples.stateCellModuleNameV1 none with
  | .error bundle =>
      throw <| IO.userError s!"payload parity load: {DiagnosticBundleV1.renderHuman bundle}"
  | .ok (payloadSource, spans) =>
      expect (FrontendSuccessV1.spans success == spans)
        "worker carries Loader canonical-preorder spans"
      expect ((← lift "payload canonical" (canonicalValidatedSourceAstBytesV1 payloadSource)) ==
        FrontendSuccessV1.canonicalBytes success)
        "worker carries Loader canonical bytes"

private unsafe def testDirectFailureFrames : IO Unit := do
  let parserBad :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program Bad where\n  view get() : UInt64 do\n    return (\n"
  let parseReq ← requestWith parserBad.toUTF8 "Root" "tests/parser-bad.lean"
  match ← processFrameV1 (← lift "parse request" (encodeFrontendRequestV1 parseReq)) with
  | .error fault => throw <| IO.userError s!"parser failure became worker fault: {repr fault}"
  | .ok response => expectFailureCode "parser" .sourceInvalid response

  let utf8Req ← stateCellRequest (ByteArray.mk #[0xff, 0xfe, 0x00])
  match ← processFrameV1 (← lift "utf8 request" (encodeFrontendRequestV1 utf8Req)) with
  | .error fault => throw <| IO.userError s!"UTF-8 failure became worker fault: {repr fault}"
  | .ok response => expectFailureCode "utf8" .sourceInvalid response

  let unknown : SemVer := { major := 2, minor := 0, patch := 0 }
  -- Invalid source plus unknown version pins version resolution before UTF-8/parser.
  let versionReq ← stateCellRequest (ByteArray.mk #[0xff]) unknown
  match ← processFrameV1 (← lift "version request" (encodeFrontendRequestV1 versionReq)) with
  | .error fault => throw <| IO.userError s!"version failure became worker fault: {repr fault}"
  | .ok response => expectFailureCode "version" .languageVersionUnknown response

private def multiplePrograms : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
  "program A where\n  view get() : UInt64 do\n    return 0\n" ++
  "program B where\n  view get() : UInt64 do\n    return 1\n"

private unsafe def testExactProgramSelectionAndDeterminism : IO Unit := do
  let request ← requestWith multiplePrograms.toUTF8 "Root" "tests/multiple.lean"
    (programSelector := some "Root.B")
  let (bytes1, success1) ← workerSuccess request
  let (bytes2, _success2) ← workerSuccess request
  expect (bytes1 == bytes2) "same request produces deterministic worker bytes"
  let (source, _) ← lift "reconstruct selected"
    (reconstructFrontendSuccessV1 request success1)
  let components := NonEmptyArray.toArray source.programIdentity.components
  expect (components.back?.map (·.raw) == some "B")
    "worker applies exact --program selection"

private unsafe def testMalformedDirectFault : IO Unit := do
  match ← processFrameV1 (ByteArray.mk #[0x00]) with
  | .error .protocol => pure ()
  | .error other => throw <| IO.userError s!"malformed wrong fault: {repr other}"
  | .ok _ => throw <| IO.userError "malformed request unexpectedly produced response"

private def workerBin : FilePath :=
  FilePath.mk ".lake/build/bin/proof-forge-frontend-worker-v1"

private partial def readBinaryToEnd
    (handle : IO.FS.Handle) (acc : ByteArray := ByteArray.empty) : IO ByteArray := do
  let chunk ← handle.read (USize.ofNat (64 * 1024))
  if chunk.isEmpty then
    pure acc
  else
    let next := acc.append chunk
    if next.size > maxProtocolBytes + 1 then
      throw <| IO.userError "worker subprocess stdout exceeded protocol bound"
    readBinaryToEnd handle next

private def spawnWorkerProcess (args : Array String) :
    IO (IO.Process.Child {
      stdin := IO.Process.Stdio.piped
      stdout := IO.Process.Stdio.piped
      stderr := IO.Process.Stdio.piped
    }) :=
  IO.Process.spawn {
    cmd := workerBin.toString
    args := args
    stdin := .piped
    stdout := .piped
    stderr := .piped
  }

private def runWorkerProcess
    (input : ByteArray) (args : Array String := #[]) :
    IO (UInt32 × ByteArray × String) := do
  let child0 ← spawnWorkerProcess args
  -- `takeStdin` returns a child with stdin detached; the scoped stream is
  -- released after the inner block, delivering EOF deterministically.
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

private unsafe def testRealSubprocessSuccessFailureAndDeterminism : IO Unit := do
  expect (← workerBin.pathExists) s!"worker binary missing: {workerBin}"
  let request ← stateCellRequest
  let input ← lift "request bytes" (encodeFrontendRequestV1 request)
  let (ec1, out1, err1) ← runWorkerProcess input
  expect (ec1 == 0) s!"worker success exit={ec1} stderr={err1}"
  expect (err1 == "") s!"worker success stderr must be empty: {err1}"
  match ← decodeResponse out1 with
  | .failure f =>
      throw <| IO.userError <|
        s!"worker subprocess StateCell failed: {DiagnosticBundleV1.renderHuman (FrontendFailureV1.bundle f)}"
  | .success s =>
      let _ ← lift "subprocess reconstruct" (reconstructFrontendSuccessV1 request s)
      pure ()
  let (ec2, out2, err2) ← runWorkerProcess input
  expect (ec2 == 0 && err2 == "" && out2 == out1)
    "two worker processes produce exact deterministic bytes"

  let badSource :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program Bad where\n  view get() : UInt64 do\n    return (\n"
  let badReq ← requestWith badSource.toUTF8 "Root" "tests/subprocess-bad.lean"
  let (badEc, badOut, badErr) ←
    runWorkerProcess (← lift "bad bytes" (encodeFrontendRequestV1 badReq))
  expect (badEc == 0 && badErr == "")
    s!"valid diagnostic response must exit 0, got {badEc}, stderr={badErr}"
  expectFailureCode "subprocess parser" .sourceInvalid badOut

private unsafe def testRealSubprocessProtocolAndUsageExits : IO Unit := do
  let (malEc, malOut, malErr) ← runWorkerProcess (ByteArray.mk #[0x00])
  expect (malEc == exit32 protocolExitCodeV1)
    s!"malformed exit expected {protocolExitCodeV1}, got {malEc}"
  expect malOut.isEmpty "malformed request must produce zero stdout"
  expect (malErr == protocolStderrTokenV1 ++ "\n")
    s!"malformed stable stderr token: {repr malErr}"

  let request ← stateCellRequest
  let bytes ← lift "request" (encodeFrontendRequestV1 request)
  let truncated := bytes.extract 0 (bytes.size - 1)
  let (trEc, trOut, trErr) ← runWorkerProcess truncated
  expect (trEc == exit32 protocolExitCodeV1) "truncated request exit 65"
  expect trOut.isEmpty "truncated request zero stdout"
  expect (trErr == protocolStderrTokenV1 ++ "\n") "truncated stable token"

  -- Tiny declared 16MiB+1 source length bomb: protocol decoder rejects without copy.
  let verB ← lift "ver" (encodeString "1.0.0")
  let pathB ← lift "path" (encodeString "tests/a.lean")
  let moduleRaw := "Root".toUTF8
  let modB := (encodeU32le (UInt32.ofNat moduleRaw.size)).append moduleRaw
  let progB := encodeU8 0
  let srcHeader := encodeU32le (UInt32.ofNat (maxSourceBytes + 1))
  let bomb ← lift "bomb" (encodeTagged "Frontend.Req.v1"
    #[verB, pathB, modB, progB, srcHeader])
  let (ovEc, ovOut, ovErr) ← runWorkerProcess bomb
  expect (ovEc == exit32 protocolExitCodeV1) "oversize declaration exit 65"
  expect ovOut.isEmpty "oversize declaration zero stdout"
  expect (ovErr == protocolStderrTokenV1 ++ "\n") "oversize stable token"

  let (argEc, argOut, argErr) ← runWorkerProcess ByteArray.empty #["extra"]
  expect (argEc == exit32 usageExitCodeV1) "argv misuse exit 64"
  expect argOut.isEmpty "argv misuse zero stdout"
  expect (argErr == usageStderrTokenV1 ++ "\n") "argv stable usage token"

unsafe def run : IO Unit := do
  testDirectStateCellSuccessAndParity
  testDirectFailureFrames
  testExactProgramSelectionAndDeterminism
  testMalformedDirectFault
  testRealSubprocessSuccessFailureAndDeterminism
  testRealSubprocessProtocolAndUsageExits
  IO.println "Tests.Frontend.WorkerV1: ok"

end Tests.Frontend.WorkerV1
