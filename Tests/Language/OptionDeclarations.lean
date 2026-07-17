import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry

namespace Tests.Language.OptionDeclarationsFixture

open ProofForgeV2.Language

program OptionSurface where
  state maybeCount : Option UInt64

  struct Pair where
    enabled : Option Bool
    owner : Option Principal

  enum Tag where
    | MaybeUnit(Option Unit)
    | MaybeCount(Option UInt64)

  const Seed : Option UInt64 := 0

  init(initial : Option UInt64) do
    maybeCount := initial

  entry echo(value : Option UInt64) : Option UInt64 do
    return value

  view get() : Option UInt64 do
    return maybeCount

  fn ident(value : Option Principal) : Option Principal do
    return value

end Tests.Language.OptionDeclarationsFixture

namespace Tests.Language.OptionDeclarationsFixture

open ProofForgeV2.Language

program OptionBoundary where
  entry echo(value : Option UInt64) : Option UInt64 do
    return value

program OptionBoolBoundary where
  entry echo(value : Option Bool) : Option Bool do
    return value

end Tests.Language.OptionDeclarationsFixture

namespace Tests.Language.OptionDeclarationsFixture

open ProofForgeV2.Language

program OptionStateBoundary where
  state value : Option UInt64

  init(initial : Option UInt64) do
    value := initial

  view get() : Option UInt64 do
    return value

program OptionResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option UInt64) : Option UInt64 do
    return value

program OptionParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option UInt64) : UInt64 do
    return 0

end Tests.Language.OptionDeclarationsFixture

namespace Tests.Language.OptionDeclarations

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def twin (type : Source.ValueType) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.OptionDeclarationsFixture.OptionTwin" "OptionTwin" #[
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
  "namespace Tests.Language.OptionDeclarationsFixture\n\n" ++
  "program OptionSurface where\n" ++
  "  state maybeCount : Option UInt64\n\n" ++
  "  struct Pair where\n" ++
  "    enabled : Option Bool\n" ++
  "    owner : Option Principal\n\n" ++
  "  enum Tag where\n" ++
  "    | MaybeUnit(Option Unit)\n" ++
  "    | MaybeCount(Option UInt64)\n\n" ++
  "  const Seed : Option UInt64 := 0\n\n" ++
  "  init(initial : Option UInt64) do\n" ++
  "    maybeCount := initial\n\n" ++
  "  entry echo(value : Option UInt64) : Option UInt64 do\n" ++
  "    return value\n\n" ++
  "  view get() : Option UInt64 do\n" ++
  "    return maybeCount\n\n" ++
  "  fn ident(value : Option Principal) : Option Principal do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.OptionDeclarationsFixture\n"

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
  let elaborated := Tests.Language.OptionDeclarationsFixture.OptionSurface
  expect (elaborated.state.map (·.type) == #[.option .u64])
    "Option UInt64 state must survive Lean command elaboration"
  match elaborated.structs with
  | #[pair] =>
      expect (pair.name == "Pair" &&
          pair.fields.map (·.type) == #[.option .bool, .option .principal])
        "Option Bool/Principal struct fields must preserve element types"
  | _ => throw <| IO.userError "OptionSurface must retain one struct"
  match elaborated.enums with
  | #[tag] =>
      expect (tag.name == "Tag" && tag.variants.map (·.payloadTypes) ==
          #[#[.option .unit], #[.option .u64]])
        "Option Unit/UInt64 enum payloads must preserve element types"
  | _ => throw <| IO.userError "OptionSurface must retain one enum"
  match elaborated.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.option .u64])
        "Option initializer parameter must survive elaboration"
  | none => throw <| IO.userError "OptionSurface must retain initializer"
  match elaborated.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.option .u64] &&
          echoEntry.result == .option .u64 && getView.result == .option .u64 &&
          getView.mode == .view)
        "Option entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "OptionSurface must retain echo and get"
  match elaborated.functions with
  | #[identFn] =>
      expect (identFn.params.map (·.type) == #[.option .principal] &&
          identFn.result == .option .principal)
        "Option Principal fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "OptionSurface must retain ident"
  match elaborated.consts with
  | #[seed] =>
      expect (seed.name == "Seed" && seed.type == .option .u64)
        "Option const type must survive elaboration"
  | _ => throw <| IO.userError "OptionSurface must retain Seed"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<option-declarations>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same Option Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same Option sourceHash"
  | .error error => throw <| IO.userError error.render

  expect ((twin .u64).sourceHash ==
      "8bbe116fabb9ea37ec1c6a12c8283c56e62e6b2476d15b80b1d6bc09d8ff1c1a")
    "OptionTwin UInt64/tag0 sourceHash golden must remain stable"
  expect ((twin (.option .u64)).sourceHash ==
      "d90a6882abbf68c541eebb8a29a5af5667ed91b0862b385be2e5674ccd2b3318")
    "Option UInt64 tag16+element sourceHash golden must remain stable"
  expect ((twin (.option .unit)).sourceHash ==
      "37d1b79cbb1e7a184e24dd5898954030b5d503033727ee3965fafe7bb0e3c6e6")
    "Option Unit tag16+element sourceHash golden must remain stable"
  expect ((twin (.option .u64)).sourceHash != (twin .u64).sourceHash &&
      (twin (.option .u64)).sourceHash != (twin (.option .unit)).sourceHash)
    "Option tag and element payload must both bind sourceHash"

  for (label, name, spelling) in [
      ("plural option", "PluralOptionType", "Options UInt64"),
      ("escaped option", "EscapedOptionType", "«Option» UInt64"),
      ("unknown option element", "UnknownOptionElement", "Option Mystery"),
      ("missing option element", "MissingOptionElement", "Option"),
      ("qualified option", "QualifiedOptionType", "Std.Option UInt64")
    ] do
    expectUnsupportedType label
      (← session.parsePrograms (negativeSource name spelling) s!"<option-{label}>")

  for (label, spelling) in [
      ("nested option", "Option Option UInt64"),
      ("field option", "Option Field bn254_fr"),
      ("extra option payload", "Option UInt64 Principal")
    ] do
    let source := negativeSource "RejectedOptionShape" spelling
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<option-{label}>")
    expectParserRejected label source result

  let boundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.OptionBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"OptionBoundary must compile: {error.render}"
  expect (boundary.requirements == #[])
    "Option UInt64 must propagate the element's zero requirements"
  for target in Targets.phase1 do
    match Targets.checkSupport target boundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError s!"{target} must support zero-requirement Option carrier: {error.render}"

  let boolBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.OptionBoolBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"OptionBoolBoundary must compile: {error.render}"
  expect (boolBoundary.requirements == #[.boolValues])
    "Option Bool must propagate boolValues exactly once"
  for target in Targets.phase1 do
    match Targets.checkSupport target boolBoundary with
    | .error (.unsupportedRequirement .boolValues actual) =>
        expect (actual == target)
          s!"Option Bool support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError s!"Option Bool/{target} reached wrong failure: {other.render}"
    | .ok () => throw <| IO.userError s!"Option Bool/{target} unexpectedly passed support"

  for (label, sourceProgram, needle) in [
      ("OptionStateBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionStateBoundary,
        "is not UInt64"),
      ("OptionResultBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionResultBoundary,
        "does not return UInt64"),
      ("OptionParamBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionParamBoundary,
        "is not UInt64")
    ] do
    let compiled ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} must compile: {error.render}"
    expect (compiled.requirements == #[.persistentState])
      s!"{label} must propagate only UInt64/persistentState requirements"
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

end Tests.Language.OptionDeclarations
