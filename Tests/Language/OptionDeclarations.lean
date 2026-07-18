import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession
import ProofForgeV2.Targets.Registry

namespace Tests.Language.OptionDeclarationsFixture

open ProofForgeV2.Language

program OptionSurface where
  state maybeCount : Option UInt64
  state maybeScalar : Option Field bn254_fr
  state nestedCount : Option Option UInt64
  state maybeBatch : Option Array UInt64 4

  struct Pair where
    enabled : Option Bool
    owner : Option Principal
    scalar : Option Field bn254_fr
    nestedEnabled : Option Option Bool
    arrayFlags : Option Array Bool 0

  enum Tag where
    | MaybeUnit(Option Unit)
    | MaybeCount(Option UInt64)
    | MaybeScalar(Option Field bn254_fr)
    | MaybeNestedCount(Option Option UInt64)
    | MaybeArray(Option Array Principal 4096)

  const Seed : Option UInt64 := 0
  const FieldSeed : Option Field bn254_fr := 0
  const NestedFlag : Option Option Bool := 0
  const ArraySeed : Option Array UInt64 0 := 0

  init(initial : Option UInt64, scalar : Option Field bn254_fr,
      nestedInitial : Option Option UInt64, arrayInitial : Option Array UInt64 4) do
    maybeCount := initial
    maybeScalar := scalar
    nestedCount := nestedInitial
    maybeBatch := arrayInitial

  entry echo(value : Option UInt64) : Option UInt64 do
    return value

  entry echoField(value : Option Field bn254_fr) : Option Field bn254_fr do
    return value

  entry echoNested(value : Option Option UInt64) : Option Option UInt64 do
    return value

  entry echoArray(value : Option Array UInt64 4) : Option Array UInt64 4 do
    return value

  view get() : Option UInt64 do
    return maybeCount

  view getField() : Option Field bn254_fr do
    return maybeScalar

  view getNested() : Option Option UInt64 do
    return nestedCount

  view getArray() : Option Array UInt64 4 do
    return maybeBatch

  fn ident(value : Option Principal) : Option Principal do
    return value

  fn identField(value : Option Field bn254_fr) : Option Field bn254_fr do
    return value

  fn identNested(value : Option Option Bool) : Option Option Bool do
    return value

  fn identArray(value : Option Array Bool 0) : Option Array Bool 0 do
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

program NestedOptionBoundary where
  entry echo(value : Option Option UInt64) : Option Option UInt64 do
    return value

program NestedOptionBoolBoundary where
  entry echo(value : Option Option Bool) : Option Option Bool do
    return value

program OptionArrayBoundary where
  entry echo(value : Option Array UInt64 4) : Option Array UInt64 4 do
    return value

program OptionArrayBoolBoundary where
  entry echo(value : Option Array Bool 0) : Option Array Bool 0 do
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

program NestedOptionStateBoundary where
  state value : Option Option UInt64

  init(initial : Option Option UInt64) do
    value := initial

  view get() : Option Option UInt64 do
    return value

program NestedOptionResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Option UInt64) : Option Option UInt64 do
    return value

program NestedOptionParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Option UInt64) : UInt64 do
    return 0

program OptionArrayStateBoundary where
  state value : Option Array UInt64 4

  init(initial : Option Array UInt64 4) do
    value := initial

  view get() : Option Array UInt64 4 do
    return value

program OptionArrayResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Array UInt64 4) : Option Array UInt64 4 do
    return value

program OptionArrayParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Array UInt64 4) : UInt64 do
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
  "  state nestedCount : Option Option UInt64\n\n" ++
  "  state maybeBatch : Option Array UInt64 4\n\n" ++
  "  struct Pair where\n" ++
  "    enabled : Option Bool\n" ++
  "    owner : Option Principal\n" ++
  "    scalar : Option Field bn254_fr\n" ++
  "    nestedEnabled : Option Option Bool\n" ++
  "    arrayFlags : Option Array Bool 0\n\n" ++
  "  enum Tag where\n" ++
  "    | MaybeUnit(Option Unit)\n" ++
  "    | MaybeCount(Option UInt64)\n" ++
  "    | MaybeScalar(Option Field bn254_fr)\n" ++
  "    | MaybeNestedCount(Option Option UInt64)\n" ++
  "    | MaybeArray(Option Array Principal 4096)\n\n" ++
  "  const Seed : Option UInt64 := 0\n\n" ++
  "  const FieldSeed : Option Field bn254_fr := 0\n\n" ++
  "  const NestedFlag : Option Option Bool := 0\n\n" ++
  "  const ArraySeed : Option Array UInt64 0 := 0\n\n" ++
  "  init(initial : Option UInt64, scalar : Option Field bn254_fr,\n" ++
  "      nestedInitial : Option Option UInt64, arrayInitial : Option Array UInt64 4) do\n" ++
  "    maybeCount := initial\n\n" ++
  "    maybeScalar := scalar\n\n" ++
  "    nestedCount := nestedInitial\n\n" ++
  "    maybeBatch := arrayInitial\n\n" ++
  "  entry echo(value : Option UInt64) : Option UInt64 do\n" ++
  "    return value\n\n" ++
  "  entry echoField(value : Option Field bn254_fr) : Option Field bn254_fr do\n" ++
  "    return value\n\n" ++
  "  entry echoNested(value : Option Option UInt64) : Option Option UInt64 do\n" ++
  "    return value\n\n" ++
  "  entry echoArray(value : Option Array UInt64 4) : Option Array UInt64 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Option UInt64 do\n" ++
  "    return maybeCount\n\n" ++
  "  view getField() : Option Field bn254_fr do\n" ++
  "    return maybeScalar\n\n" ++
  "  view getNested() : Option Option UInt64 do\n" ++
  "    return nestedCount\n\n" ++
  "  view getArray() : Option Array UInt64 4 do\n" ++
  "    return maybeBatch\n\n" ++
  "  fn ident(value : Option Principal) : Option Principal do\n" ++
  "    return value\n\n" ++
  "  fn identField(value : Option Field bn254_fr) : Option Field bn254_fr do\n" ++
  "    return value\n\n" ++
  "  fn identNested(value : Option Option Bool) : Option Option Bool do\n" ++
  "    return value\n\n" ++
  "  fn identArray(value : Option Array Bool 0) : Option Array Bool 0 do\n" ++
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
  expect (elaborated.state.map (·.type) ==
      #[.option .u64, .option .field, .option (.option .u64), .option (.array .u64 4)])
    "Option UInt64/Field/nested/Array state must survive Lean command elaboration"
  match elaborated.structs with
  | #[pair] =>
      expect (pair.name == "Pair" &&
          pair.fields.map (·.type) ==
            #[.option .bool, .option .principal, .option .field, .option (.option .bool),
              .option (.array .bool 0)])
        "Option Bool/Principal/Field/nested/Array struct fields must preserve element types"
  | _ => throw <| IO.userError "OptionSurface must retain one struct"
  match elaborated.enums with
  | #[tag] =>
      expect (tag.name == "Tag" && tag.variants.map (·.payloadTypes) ==
          #[#[.option .unit], #[.option .u64], #[.option .field],
            #[.option (.option .u64)], #[.option (.array .principal 4096)]])
        "Option Unit/UInt64/Field/nested/Array enum payloads must preserve element types"
  | _ => throw <| IO.userError "OptionSurface must retain one enum"
  match elaborated.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) ==
          #[.option .u64, .option .field, .option (.option .u64),
            .option (.array .u64 4)])
        "Option UInt64/Field/nested/Array initializer parameters must survive elaboration"
  | none => throw <| IO.userError "OptionSurface must retain initializer"
  match elaborated.entries with
  | #[echoEntry, echoField, echoNested, echoArray, getView, getField, getNested, getArray] =>
      expect (echoEntry.params.map (·.type) == #[.option .u64] &&
          echoEntry.result == .option .u64 && getView.result == .option .u64 &&
          getView.mode == .view &&
          echoField.params.map (·.type) == #[.option .field] &&
          echoField.result == .option .field && getField.result == .option .field &&
          getField.mode == .view &&
          echoNested.params.map (·.type) == #[.option (.option .u64)] &&
          echoNested.result == .option (.option .u64) &&
          getNested.result == .option (.option .u64) && getNested.mode == .view &&
          echoArray.params.map (·.type) == #[.option (.array .u64 4)] &&
          echoArray.result == .option (.array .u64 4) &&
          getArray.result == .option (.array .u64 4) && getArray.mode == .view)
        "Option UInt64/Field/nested/Array entry/view types must survive elaboration"
  | _ => throw <| IO.userError "OptionSurface must retain eight entries/views"
  match elaborated.functions with
  | #[identFn, identField, identNested, identArray] =>
      expect (identFn.params.map (·.type) == #[.option .principal] &&
          identFn.result == .option .principal &&
          identField.params.map (·.type) == #[.option .field] &&
          identField.result == .option .field &&
          identNested.params.map (·.type) == #[.option (.option .bool)] &&
          identNested.result == .option (.option .bool) &&
          identArray.params.map (·.type) == #[.option (.array .bool 0)] &&
          identArray.result == .option (.array .bool 0))
        "Option Principal/Field/nested/Array fn parameter/results must survive elaboration"
  | _ =>
      throw <| IO.userError "OptionSurface must retain ident, identField, identNested and identArray"
  match elaborated.consts with
  | #[seed, fieldSeed, nestedFlag, arraySeed] =>
      expect (seed.name == "Seed" && seed.type == .option .u64 &&
          fieldSeed.name == "FieldSeed" && fieldSeed.type == .option .field &&
          nestedFlag.name == "NestedFlag" && nestedFlag.type == .option (.option .bool) &&
          arraySeed.name == "ArraySeed" && arraySeed.type == .option (.array .u64 0))
        "Option UInt64/Field/nested/Array const types must survive elaboration"
  | _ =>
      throw <| IO.userError "OptionSurface must retain Seed, FieldSeed, NestedFlag and ArraySeed"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<option-declarations>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same Option Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same Option sourceHash"
  | .error error => throw <| IO.userError error.render

  let optionArrayElements : Array (String × Source.ValueType) := #[
    ("Bool", .bool),
    ("UInt8", .u8), ("UInt16", .u16), ("UInt32", .u32), ("UInt64", .u64),
    ("UInt128", .u128), ("UInt256", .u256),
    ("Int8", .i8), ("Int16", .i16), ("Int32", .i32), ("Int64", .i64),
    ("Int128", .i128), ("Int256", .i256),
    ("Unit", .unit), ("Principal", .principal)
  ]
  expect (optionArrayElements.size == 15)
    "Option Array PrimitiveAtom matrix must contain exactly 15 elements"
  for (spelling, element) in optionArrayElements do
    let source := negativeSource s!"OptionArray{spelling}" s!"Option Array {spelling} 4"
    match ← session.parsePrograms source s!"<option-array-{spelling}>" with
    | .ok #[decodedProgram] =>
        expect (decodedProgram.state.map (·.type) == #[.option (.array element 4)])
          s!"Option Array {spelling} 4 must preserve its exact element and length"
    | .ok programs =>
        throw <| IO.userError s!"Option Array {spelling} 4 produced {programs.size} programs"
    | .error error =>
        throw <| IO.userError s!"Option Array {spelling} 4 must parse: {error.render}"

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
  expect (optionFieldSource.canonicalBytes.size == 241 && optionFieldSource.sourceHash ==
      "8d83aba16ec5c8f4694fbce7a3847903ca492d2af7ffc5030029f4485a71c79a")
    s!"Option Field source golden is unbound: size={optionFieldSource.canonicalBytes.size}, hash={optionFieldSource.sourceHash}"
  expect (optionFieldSource.sourceHash != (twin .field).sourceHash &&
      optionFieldSource.sourceHash != (twin (.option .bool)).sourceHash &&
      optionFieldSource.sourceHash != (twin (.option .u64)).sourceHash)
    "Option Field must bind both Option tag16 and Field tag2"
  let optionFieldSemantic ← match Compiler.compile optionFieldSource with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"Option Field semantic twin must compile: {error.render}"
  expect (optionFieldSemantic.canonicalBytes.size == 191 &&
      optionFieldSemantic.semanticHash ==
        "c50aab8c944ed3db26737aa7f9edcfbd7122cd828b7c4c859237bbc3537b6229")
    s!"Option Field semantic golden is unbound: size={optionFieldSemantic.canonicalBytes.size}, hash={optionFieldSemantic.semanticHash}"

  let nestedSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Option UInt64", .option (.option .u64), 243,
      "d480f1267bd8753f9bae0f6f21439836a0d11f2d39eeef908ccec94875c5daf4"),
    ("Option Option Bool", .option (.option .bool), 243,
      "3110c1ed382a8b002e2248b84744a8aa1716122215c43f4c09d474efaaff7960")
  ]
  for (label, type, expectedSize, expectedHash) in nestedSourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag16+tag16 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  expect ((twin (.option (.option .u64))).sourceHash != (twin .u64).sourceHash &&
      (twin (.option (.option .u64))).sourceHash != (twin (.option .u64)).sourceHash &&
      (twin (.option (.option .u64))).sourceHash !=
        (twin (.option (.option .bool))).sourceHash)
    "nested Option must bind both tag16 layers and the element payload"

  let nestedSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Option UInt64", .option (.option .u64), 192,
      "5b5eacce6a48158bbbaab3490044613d35323e278c42d7d1d4594ffb5ce9ed18"),
    ("Option Option Bool", .option (.option .bool), 193,
      "0caaecffaab09d481ef117347b885196ba00e8df0b43b090c4643ece3831b959")
  ]
  for (label, type, expectedSize, expectedHash) in nestedSemanticVectors do
    let sourceProgram := twin type
    let semantic ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (semantic.canonicalBytes.size == expectedSize && semantic.semanticHash == expectedHash)
      s!"{label} semantic tag16+tag16 golden is unbound: size={semantic.canonicalBytes.size}, hash={semantic.semanticHash}"

  let optionArraySourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Array UInt64 0", .option (.array .u64 0), 0, "UNBOUND"),
    ("Option Array UInt64 4", .option (.array .u64 4), 0, "UNBOUND"),
    ("Option Array UInt64 4096", .option (.array .u64 4096), 0, "UNBOUND"),
    ("Option Array Bool 0", .option (.array .bool 0), 0, "UNBOUND")
  ]
  for (label, type, expectedSize, expectedHash) in optionArraySourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag16+tag18 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  expect ((twin (.option (.array .u64 0))).sourceHash != (twin (.array .u64 0)).sourceHash &&
      (twin (.option (.array .u64 0))).sourceHash != (twin (.option .u64)).sourceHash &&
      (twin (.option (.array .u64 0))).sourceHash !=
        (twin (.option (.option .u64))).sourceHash &&
      (twin (.option (.array .u64 0))).sourceHash !=
        (twin (.option (.array .u64 4))).sourceHash &&
      (twin (.option (.array .u64 0))).sourceHash !=
        (twin (.option (.array .bool 0))).sourceHash)
    "Option Array must bind Option/Array tags, element and complete length payload"

  let optionArraySemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Array UInt64 0", .option (.array .u64 0), 0, "UNBOUND"),
    ("Option Array UInt64 4", .option (.array .u64 4), 0, "UNBOUND"),
    ("Option Array UInt64 4096", .option (.array .u64 4096), 0, "UNBOUND"),
    ("Option Array Bool 0", .option (.array .bool 0), 0, "UNBOUND")
  ]
  for (label, type, expectedSize, expectedHash) in optionArraySemanticVectors do
    let sourceProgram := twin type
    let semantic ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (semantic.canonicalBytes.size == expectedSize && semantic.semanticHash == expectedHash)
      s!"{label} semantic tag16+tag18 golden is unbound: size={semantic.canonicalBytes.size}, hash={semantic.semanticHash}"

  for (label, name, spelling) in [
      ("plural option", "PluralOptionType", "Options UInt64"),
      ("escaped option", "EscapedOptionType", "«Option» UInt64"),
      ("unknown option element", "UnknownOptionElement", "Option Mystery"),
      ("missing option element", "MissingOptionElement", "Option"),
      ("qualified option", "QualifiedOptionType", "Std.Option UInt64"),
      ("missing Field identifier", "MissingOptionFieldId", "Option Field"),
      ("alternate Field identifier", "AlternateOptionFieldId", "Option Field bls12_381_fr"),
      ("escaped Field identifier", "EscapedOptionFieldId", "Option Field «bn254_fr»"),
      ("qualified Field identifier", "QualifiedOptionFieldId", "Option Field Curves.bn254_fr"),
      ("missing nested element", "MissingNestedOptionElement", "Option Option"),
      ("unknown nested element", "UnknownNestedOptionElement", "Option Option Mystery"),
      ("Field nested element", "FieldNestedOptionElement", "Option Option Field"),
      ("escaped nested element", "EscapedNestedOptionElement", "Option Option «Bool»"),
      ("qualified nested element", "QualifiedNestedOptionElement", "Option Option Std.Bool"),
      ("full Map nested option", "FullMapNestedOption", "Option Option Map UInt64 Bool"),
      ("missing Option Array element", "MissingOptionArrayElement", "Option Array"),
      ("unknown Option Array element", "UnknownOptionArrayElement", "Option Array Mystery 4"),
      ("Field Option Array element", "FieldOptionArrayElement", "Option Array Field 4"),
      ("escaped Option Array element", "EscapedOptionArrayElement", "Option Array «UInt64» 4"),
      ("qualified Option Array element", "QualifiedOptionArrayElement", "Option Array Std.UInt64 4"),
      ("over-bound Option Array length", "OverBoundOptionArray", "Option Array UInt64 4097"),
      ("leading-zero Option Array length", "LeadingZeroOptionArray", "Option Array UInt64 01"),
      ("hex Option Array length", "HexOptionArray", "Option Array UInt64 0x10"),
      ("underscore Option Array length", "UnderscoreOptionArray", "Option Array UInt64 4_096"),
      ("Map option element", "MapOptionElement", "Option Map UInt64 Bool")
    ] do
    expectUnsupportedType label
      (← session.parsePrograms (negativeSource name spelling) s!"<option-{label}>")

  for (label, spelling) in [
      ("third nested option", "Option Option Option Bool"),
      ("full Field nested option", "Option Option Field bn254_fr"),
      ("full Bytes nested option", "Option Option Bytes 8"),
      ("full Array nested option", "Option Option Array UInt64 4"),
      ("extra nested option payload", "Option Option UInt64 Principal"),
      ("split nested option", "Option Option\n  UInt64"),
      ("escaped inner Option constructor", "Option «Option» Bool"),
      ("escaped outer Option constructor", "«Option» Option Bool"),
      ("qualified outer Option constructor", "Std.Option Option Bool"),
      ("missing Option Array length", "Option Array UInt64"),
      ("negative Option Array length", "Option Array UInt64 -1"),
      ("extra Option Array payload", "Option Array UInt64 4 Principal"),
      ("full Field Option Array element", "Option Array Field bn254_fr 4"),
      ("nested Option Option Array element", "Option Array Option Bool 4"),
      ("nested Bytes Option Array element", "Option Array Bytes 8 4"),
      ("nested Array Option Array element", "Option Array Array UInt64 4 4"),
      ("Map Option Array element", "Option Array Map UInt64 Bool 4"),
      ("split Option Array element", "Option Array\n  UInt64 4"),
      ("split Option Array length", "Option Array UInt64\n  4"),
      ("escaped Array constructor in Option", "Option «Array» UInt64 4"),
      ("qualified Array constructor in Option", "Option Std.Array UInt64 4"),
      ("escaped Option Array constructor", "«Option» Array UInt64 4"),
      ("qualified Option Array constructor", "Std.Option Array UInt64 4"),
      ("retained Array Option element", "Array Option Bool 4"),
      ("retained Array Field element", "Array Field bn254_fr 4"),
      ("extra option payload", "Option UInt64 Principal"),
      ("extra Field option payload", "Option Field bn254_fr UInt64"),
      ("split Field option", "Option Field\n  bn254_fr"),
      ("escaped Field constructor", "Option «Field» bn254_fr"),
      ("qualified Option constructor", "Std.Option Field bn254_fr"),
      ("Bytes option", "Option Bytes 8")
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

  let nestedBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.NestedOptionBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"NestedOptionBoundary must compile: {error.render}"
  expect (nestedBoundary.requirements == #[])
    "Option Option UInt64 must recursively propagate zero requirements"
  for target in Targets.phase1 do
    match Targets.checkSupport target nestedBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError s!"{target} must support zero-requirement nested Option carrier: {error.render}"

  let nestedBoolBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.NestedOptionBoolBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"NestedOptionBoolBoundary must compile: {error.render}"
  expect (nestedBoolBoundary.requirements == #[.boolValues])
    "Option Option Bool must recursively propagate boolValues exactly once"
  for target in Targets.phase1 do
    match Targets.checkSupport target nestedBoolBoundary with
    | .error (.unsupportedRequirement .boolValues actual) =>
        expect (actual == target)
          s!"nested Option Bool support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError s!"nested Option Bool/{target} reached wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError s!"nested Option Bool/{target} unexpectedly passed support"

  let optionArrayBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.OptionArrayBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"OptionArrayBoundary must compile: {error.render}"
  expect (optionArrayBoundary.requirements == #[])
    "Option Array UInt64 must recursively propagate zero requirements"
  for target in Targets.phase1 do
    match Targets.checkSupport target optionArrayBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError s!"{target} must support zero-requirement Option Array carrier: {error.render}"

  let optionArrayBoolBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.OptionArrayBoolBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"OptionArrayBoolBoundary must compile: {error.render}"
  expect (optionArrayBoolBoundary.requirements == #[.boolValues])
    "Option Array Bool must recursively propagate boolValues exactly once"
  for target in Targets.phase1 do
    match Targets.checkSupport target optionArrayBoolBoundary with
    | .error (.unsupportedRequirement .boolValues actual) =>
        expect (actual == target)
          s!"Option Array Bool support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError s!"Option Array Bool/{target} reached wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError s!"Option Array Bool/{target} unexpectedly passed support"

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
        "is not UInt64"),
      ("NestedOptionStateBoundary",
        Tests.Language.OptionDeclarationsFixture.NestedOptionStateBoundary,
        "is not UInt64"),
      ("NestedOptionResultBoundary",
        Tests.Language.OptionDeclarationsFixture.NestedOptionResultBoundary,
        "does not return UInt64"),
      ("NestedOptionParamBoundary",
        Tests.Language.OptionDeclarationsFixture.NestedOptionParamBoundary,
        "is not UInt64"),
      ("OptionArrayStateBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionArrayStateBoundary,
        "is not UInt64"),
      ("OptionArrayResultBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionArrayResultBoundary,
        "does not return UInt64"),
      ("OptionArrayParamBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionArrayParamBoundary,
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
