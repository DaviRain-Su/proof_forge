import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession
import ProofForgeV2.Targets.Registry

namespace Tests.Language.OptionDeclarationsFixture

open ProofForgeV2.Language

program OptionSurface where
  state maybeCount : Option UInt64
  state maybeScalar : Option Field bn254_fr

  struct Pair where
    enabled : Option Bool
    owner : Option Principal
    scalar : Option Field bn254_fr

  enum Tag where
    | MaybeUnit(Option Unit)
    | MaybeCount(Option UInt64)
    | MaybeScalar(Option Field bn254_fr)

  const Seed : Option UInt64 := 0
  const FieldSeed : Option Field bn254_fr := 0

  init(initial : Option UInt64, scalar : Option Field bn254_fr) do
    maybeCount := initial
    maybeScalar := scalar

  entry echo(value : Option UInt64) : Option UInt64 do
    return value

  entry echoField(value : Option Field bn254_fr) : Option Field bn254_fr do
    return value

  view get() : Option UInt64 do
    return maybeCount

  view getField() : Option Field bn254_fr do
    return maybeScalar

  fn ident(value : Option Principal) : Option Principal do
    return value

  fn identField(value : Option Field bn254_fr) : Option Field bn254_fr do
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

program OptionFieldBoundary where
  entry echo(value : Option Field bn254_fr) : Option Field bn254_fr do
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
  "  state maybeScalar : Option Field bn254_fr\n\n" ++
  "  struct Pair where\n" ++
  "    enabled : Option Bool\n" ++
  "    owner : Option Principal\n" ++
  "    scalar : Option Field bn254_fr\n\n" ++
  "  enum Tag where\n" ++
  "    | MaybeUnit(Option Unit)\n" ++
  "    | MaybeCount(Option UInt64)\n" ++
  "    | MaybeScalar(Option Field bn254_fr)\n\n" ++
  "  const Seed : Option UInt64 := 0\n\n" ++
  "  const FieldSeed : Option Field bn254_fr := 0\n\n" ++
  "  init(initial : Option UInt64, scalar : Option Field bn254_fr) do\n" ++
  "    maybeCount := initial\n\n" ++
  "    maybeScalar := scalar\n\n" ++
  "  entry echo(value : Option UInt64) : Option UInt64 do\n" ++
  "    return value\n\n" ++
  "  entry echoField(value : Option Field bn254_fr) : Option Field bn254_fr do\n" ++
  "    return value\n\n" ++
  "  view get() : Option UInt64 do\n" ++
  "    return maybeCount\n\n" ++
  "  view getField() : Option Field bn254_fr do\n" ++
  "    return maybeScalar\n\n" ++
  "  fn ident(value : Option Principal) : Option Principal do\n" ++
  "    return value\n\n" ++
  "  fn identField(value : Option Field bn254_fr) : Option Field bn254_fr do\n" ++
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
  expect (elaborated.state.map (·.type) == #[.option .u64, .option .field])
    "Option UInt64/Field state must survive Lean command elaboration"
  match elaborated.structs with
  | #[pair] =>
      expect (pair.name == "Pair" &&
          pair.fields.map (·.type) == #[.option .bool, .option .principal, .option .field])
        "Option Bool/Principal/Field struct fields must preserve element types"
  | _ => throw <| IO.userError "OptionSurface must retain one struct"
  match elaborated.enums with
  | #[tag] =>
      expect (tag.name == "Tag" && tag.variants.map (·.payloadTypes) ==
          #[#[.option .unit], #[.option .u64], #[.option .field]])
        "Option Unit/UInt64/Field enum payloads must preserve element types"
  | _ => throw <| IO.userError "OptionSurface must retain one enum"
  match elaborated.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.option .u64, .option .field])
        "Option UInt64/Field initializer parameters must survive elaboration"
  | none => throw <| IO.userError "OptionSurface must retain initializer"
  match elaborated.entries with
  | #[echoEntry, echoField, getView, getField] =>
      expect (echoEntry.params.map (·.type) == #[.option .u64] &&
          echoEntry.result == .option .u64 && getView.result == .option .u64 &&
          getView.mode == .view &&
          echoField.params.map (·.type) == #[.option .field] &&
          echoField.result == .option .field && getField.result == .option .field &&
          getField.mode == .view)
        "Option UInt64/Field entry/view types must survive elaboration"
  | _ => throw <| IO.userError "OptionSurface must retain four entries/views"
  match elaborated.functions with
  | #[identFn, identField] =>
      expect (identFn.params.map (·.type) == #[.option .principal] &&
          identFn.result == .option .principal &&
          identField.params.map (·.type) == #[.option .field] &&
          identField.result == .option .field)
        "Option Principal/Field fn parameter/results must survive elaboration"
  | _ => throw <| IO.userError "OptionSurface must retain ident and identField"
  match elaborated.consts with
  | #[seed, fieldSeed] =>
      expect (seed.name == "Seed" && seed.type == .option .u64 &&
          fieldSeed.name == "FieldSeed" && fieldSeed.type == .option .field)
        "Option UInt64/Field const types must survive elaboration"
  | _ => throw <| IO.userError "OptionSurface must retain Seed and FieldSeed"

  let session ← Tests.Language.ParserSession.shared
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
  let optionFieldSource := twin (.option .field)
  expect (optionFieldSource.canonicalBytes.size == 0 && optionFieldSource.sourceHash == "UNBOUND")
    s!"Option Field source golden is unbound: size={optionFieldSource.canonicalBytes.size}, hash={optionFieldSource.sourceHash}"
  expect (optionFieldSource.sourceHash != (twin .field).sourceHash &&
      optionFieldSource.sourceHash != (twin (.option .bool)).sourceHash &&
      optionFieldSource.sourceHash != (twin (.option .u64)).sourceHash)
    "Option Field must bind both Option tag16 and Field tag2"
  let optionFieldSemantic ← match Compiler.compile optionFieldSource with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"Option Field semantic twin must compile: {error.render}"
  expect (optionFieldSemantic.canonicalBytes.size == 0 &&
      optionFieldSemantic.semanticHash == "UNBOUND")
    s!"Option Field semantic golden is unbound: size={optionFieldSemantic.canonicalBytes.size}, hash={optionFieldSemantic.semanticHash}"

  for (label, name, spelling) in [
      ("plural option", "PluralOptionType", "Options UInt64"),
      ("escaped option", "EscapedOptionType", "«Option» UInt64"),
      ("unknown option element", "UnknownOptionElement", "Option Mystery"),
      ("missing option element", "MissingOptionElement", "Option"),
      ("qualified option", "QualifiedOptionType", "Std.Option UInt64"),
      ("missing Field identifier", "MissingOptionFieldId", "Option Field"),
      ("alternate Field identifier", "AlternateOptionFieldId", "Option Field bls12_381_fr"),
      ("escaped Field identifier", "EscapedOptionFieldId", "Option Field «bn254_fr»"),
      ("qualified Field identifier", "QualifiedOptionFieldId", "Option Field Curves.bn254_fr")
    ] do
    expectUnsupportedType label
      (← session.parsePrograms (negativeSource name spelling) s!"<option-{label}>")

  for (label, spelling) in [
      ("nested option", "Option Option UInt64"),
      ("extra option payload", "Option UInt64 Principal"),
      ("extra Field option payload", "Option Field bn254_fr UInt64"),
      ("split Field option", "Option Field\n  bn254_fr"),
      ("escaped Field constructor", "Option «Field» bn254_fr"),
      ("qualified Option constructor", "Std.Option Field bn254_fr"),
      ("Bytes option", "Option Bytes 8"),
      ("Array option", "Option Array UInt64 4"),
      ("Map option", "Option Map UInt64 Bool")
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

  let fieldBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.OptionFieldBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"OptionFieldBoundary must compile: {error.render}"
  expect (fieldBoundary.requirements == #[.fieldBn254])
    "Option Field must propagate fieldBn254 exactly once"
  for target in Targets.phase1 do
    match Targets.checkSupport target fieldBoundary with
    | .error (.unsupportedRequirement .fieldBn254 actual) =>
        expect (actual == target)
          s!"Option Field support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError s!"Option Field/{target} reached wrong failure: {other.render}"
    | .ok () => throw <| IO.userError s!"Option Field/{target} unexpectedly passed support"

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
