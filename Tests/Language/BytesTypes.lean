import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession
import ProofForgeV2.Targets.Registry

namespace Tests.Language.BytesTypesFixture

open ProofForgeV2.Language

program BytesSurface where
  state blob : Bytes 32

  struct Limits where
    empty : Bytes 0
    maximum : Bytes 4096

  enum BlobCase where
    | Empty(Bytes 0)
    | Full(Bytes 4096)

  const EmptyBlob : Bytes 0 := 0

  init(initial : Bytes 32) do
    blob := initial

  entry echo(value : Bytes 32) : Bytes 32 do
    return value

  view get() : Bytes 32 do
    return blob

  fn keepMaximum(value : Bytes 4096) : Bytes 4096 do
    return value

end Tests.Language.BytesTypesFixture

namespace Tests.Language.BytesTypesFixture

open ProofForgeV2.Language

program BytesBoundary where
  entry echo(value : Bytes 32) : Bytes 32 do
    return value

program BytesStateBoundary where
  state value : Bytes 32

  init(initial : Bytes 32) do
    value := initial

  view get() : Bytes 32 do
    return value

program BytesResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Bytes 32) : Bytes 32 do
    return value

program BytesParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Bytes 32) : UInt64 do
    return 0

program OptionBytesBoundary where
  entry echo(value : Option Bytes 32) : Option Bytes 32 do
    return value

end Tests.Language.BytesTypesFixture

namespace Tests.Language.BytesTypes

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def twin (type : Source.ValueType) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.BytesTypesFixture.BytesTwin" "BytesTwin" #[
    .entry {
      name := "echo"
      params := #[{ name := "value", type }]
      result := type
      mode := .mutate
      body := #[.returnValue (.variable "value")]
    }
  ]

private def surfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.BytesTypesFixture\n\n" ++
  "program BytesSurface where\n" ++
  "  state blob : Bytes 32\n\n" ++
  "  struct Limits where\n" ++
  "    empty : Bytes 0\n" ++
  "    maximum : Bytes 4096\n\n" ++
  "  enum BlobCase where\n" ++
  "    | Empty(Bytes 0)\n" ++
  "    | Full(Bytes 4096)\n\n" ++
  "  const EmptyBlob : Bytes 0 := 0\n\n" ++
  "  init(initial : Bytes 32) do\n" ++
  "    blob := initial\n\n" ++
  "  entry echo(value : Bytes 32) : Bytes 32 do\n" ++
  "    return value\n\n" ++
  "  view get() : Bytes 32 do\n" ++
  "    return blob\n\n" ++
  "  fn keepMaximum(value : Bytes 4096) : Bytes 4096 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.BytesTypesFixture\n"

private def negativeSource (name typeSpelling : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  state value : " ++ typeSpelling ++ "\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return 0\n"

private def expectUnsupportedType (label : String)
    (result : CompileResult (Array Source.Program)) : IO Unit := do
  match result with
  | .error (.invalidProgram "unsupported portable type") => pure ()
  | .error other =>
      throw <| IO.userError s!"{label}: expected exact unsupported-type error, got {other.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private def expectParserRejected (label source : String)
    (result : CompileResult (Array Source.Program)) : IO Unit := do
  match result with
  | .error (.invalidProgram message) =>
      expect (message.startsWith "Lean parser rejected source: failed to parse file")
        s!"{label}: expected parser-boundary rejection, got {message}"
  | .error other =>
      throw <| IO.userError s!"{label}: reached wrong failure for {source}: {other.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

unsafe def run : IO Unit := do
  let elaborated := Tests.Language.BytesTypesFixture.BytesSurface
  expect (elaborated.state.map (·.type) == #[.bytes 32])
    "Bytes 32 state must survive Lean command elaboration"
  match elaborated.structs with
  | #[limits] =>
      expect (limits.name == "Limits" &&
          limits.fields.map (·.type) == #[.bytes 0, .bytes 4096])
        "Bytes 0/4096 struct fields must preserve exact lengths"
  | _ => throw <| IO.userError "BytesSurface must retain one struct"
  match elaborated.enums with
  | #[blobCase] =>
      expect (blobCase.name == "BlobCase" && blobCase.variants.map (·.payloadTypes) ==
          #[#[.bytes 0], #[.bytes 4096]])
        "Bytes 0/4096 enum payloads must preserve exact lengths"
  | _ => throw <| IO.userError "BytesSurface must retain one enum"
  match elaborated.consts with
  | #[emptyBlob] =>
      expect (emptyBlob.name == "EmptyBlob" && emptyBlob.type == .bytes 0)
        "Bytes 0 const type must survive elaboration"
  | _ => throw <| IO.userError "BytesSurface must retain EmptyBlob"
  match elaborated.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.bytes 32])
        "Bytes initializer parameter must survive elaboration"
  | none => throw <| IO.userError "BytesSurface must retain initializer"
  match elaborated.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.bytes 32] &&
          echoEntry.result == .bytes 32 && getView.result == .bytes 32 &&
          getView.mode == .view)
        "Bytes entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "BytesSurface must retain echo and get"
  match elaborated.functions with
  | #[keepMaximum] =>
      expect (keepMaximum.params.map (·.type) == #[.bytes 4096] &&
          keepMaximum.result == .bytes 4096)
        "Bytes 4096 fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "BytesSurface must retain keepMaximum"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<bytes-types>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same Bytes Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same Bytes sourceHash"
  | .error error => throw <| IO.userError error.render

  expect ((twin .u64).sourceHash ==
      "5087d5f55dff32c65d073fe17f4394df78172e7f077343047cdccfdd40b60838")
    "BytesTwin UInt64/tag0 sourceHash golden must remain stable"
  expect ((twin (.bytes 0)).sourceHash ==
      "f1b674b004bf9ea73e04d8ba259bb15ea6d2e02dffbd2c6b853d408eb31c7f77")
    "Bytes 0 tag17+BE-u64 sourceHash golden must remain stable"
  expect ((twin (.bytes 1)).sourceHash ==
      "60a764e482c81aa2a30fb38dc9dbfab0c674df9bc9fa3d36b538356229949dcc")
    "Bytes 1 tag17+BE-u64 sourceHash golden must remain stable"
  expect ((twin (.bytes 4096)).sourceHash ==
      "3fe714facd3a9c6da07b5aafad460431f2bf8e6e39abec045a69c481def1dba4")
    "Bytes 4096 tag17+BE-u64 sourceHash golden must remain stable"
  expect ((twin (.bytes 0)).sourceHash != (twin .u64).sourceHash &&
      (twin (.bytes 0)).sourceHash != (twin (.bytes 1)).sourceHash &&
      (twin (.bytes 1)).sourceHash != (twin (.bytes 4096)).sourceHash)
    "Bytes tag and complete length payload must bind sourceHash without aliases"
  expect ((twin .u64).canonicalBytes.size == 229 &&
      (twin (.bytes 0)).canonicalBytes.size == 245 &&
      (twin (.bytes 1)).canonicalBytes.size == 245 &&
      (twin (.bytes 4096)).canonicalBytes.size == 245)
    "Bytes source canonical bytes must include two complete BE-u64 length payloads"

  for (label, type, byteSize, expectedHash) in [
      ("UInt64", .u64, 178,
        "3f94b3895e74c237e17cc734c40c93bd026b92a8202a07bfde76b3985d06d735"),
      ("Bytes 0", .bytes 0, 194,
        "a0d095785a535fc1cf821d0ba106c904dac8aac0eb3ba3f14f458499c405af93"),
      ("Bytes 1", .bytes 1, 194,
        "0f7b37ecc8ab5cb335ff1721abedaa71d7a3d0c0a4110c34a057acc3d808bff3"),
      ("Bytes 32", .bytes 32, 194,
        "0849d407e4d47ca2b066f3d2f73069018bd34c34cd14b6b2dca389cef70499fa"),
      ("Bytes 4096", .bytes 4096, 194,
        "ddb99aa12fb552185a542c75f72800f98182123c27dd3ac99e10377b0357469c")
    ] do
    let compiled ← match Compiler.compile (twin type) with
      | .ok value => pure value
      | .error error =>
          throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (compiled.canonicalBytes.size == byteSize && compiled.semanticHash == expectedHash)
      s!"{label} semantic tag17+LE-u64 canonical golden must remain stable"

  for (label, spelling) in [
      ("bare Bytes", "Bytes"),
      ("Bytes64 spelling", "Bytes64"),
      ("escaped Bytes", "«Bytes» 32"),
      ("qualified Bytes", "Std.Bytes 32"),
      ("identifier Bytes length", "Bytes Foo"),
      ("hex Bytes length", "Bytes 0x20"),
      ("leading-zero Bytes length", "Bytes 007"),
      ("over-bound Bytes length", "Bytes 4097")
    ] do
    expectUnsupportedType label
      (← session.parsePrograms (negativeSource "RejectedBytesType" spelling) s!"<bytes-{label}>")

  for (label, spelling) in [
      ("negative Bytes length", "Bytes -1"),
      ("extra Bytes payload", "Bytes 32 UInt64"),
      ("split Bytes payload", "Bytes\n  32")
    ] do
    let source := negativeSource "RejectedBytesShape" spelling
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<bytes-{label}>")
    expectParserRejected label source result

  let boundary ← match Compiler.compile Tests.Language.BytesTypesFixture.BytesBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"BytesBoundary must compile: {error.render}"
  expect (boundary.requirements == #[])
    "Bytes declaration carrier must add zero requirements"
  match boundary.entries with
  | #[echoEntry] =>
      expect (echoEntry.params.map (·.type) == #[.bytes 32] && echoEntry.result == .bytes 32)
        "Source-to-Semantic adaptation must preserve Bytes length"
  | _ => throw <| IO.userError "BytesBoundary must retain one semantic entry"
  for target in Targets.phase1 do
    match Targets.checkSupport target boundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError s!"{target} must support zero-requirement Bytes carrier: {error.render}"

  let optionBytesBoundary ← match Compiler.compile Tests.Language.BytesTypesFixture.OptionBytesBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"OptionBytesBoundary must compile: {error.render}"
  expect (optionBytesBoundary.requirements == #[])
    "Option Bytes must add zero requirements through the Bytes carrier"
  match optionBytesBoundary.entries with
  | #[echoEntry] =>
      expect (echoEntry.params.map (·.type) == #[.option (.bytes 32)] &&
          echoEntry.result == .option (.bytes 32))
        "Source-to-Semantic adaptation must preserve Option Bytes length"
  | _ => throw <| IO.userError "OptionBytesBoundary must retain one semantic entry"
  for target in Targets.phase1 do
    match Targets.checkSupport target optionBytesBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError s!"{target} must support zero-requirement Option Bytes carrier: {error.render}"

  for (label, sourceProgram, needle) in [
      ("BytesStateBoundary", Tests.Language.BytesTypesFixture.BytesStateBoundary, "is not UInt64"),
      ("BytesResultBoundary", Tests.Language.BytesTypesFixture.BytesResultBoundary,
        "does not return UInt64"),
      ("BytesParamBoundary", Tests.Language.BytesTypesFixture.BytesParamBoundary, "is not UInt64")
    ] do
    let compiled ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} must compile: {error.render}"
    expect (compiled.requirements == #[.persistentState])
      s!"{label} must propagate only persistentState"
    for target in Targets.phase1 do
      match Targets.checkSupport target compiled with
      | .ok () => pure ()
      | .error error =>
          throw <| IO.userError s!"{label}/{target} checkSupport must accept: {error.render}"
      match Targets.materializeResult target compiled with
      | .error (.planInvariant _ detail) =>
          expect (detail.contains needle)
            s!"{label}/{target} must fail planInvariant containing '{needle}', got {detail}"
      | .error other =>
          throw <| IO.userError s!"{label}/{target} must fail planInvariant, got {other.render}"
      | .ok _ =>
          throw <| IO.userError s!"{label}/{target} must not materialize before planInvariant"

end Tests.Language.BytesTypes
