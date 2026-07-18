import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession
import ProofForgeV2.Targets.Registry

namespace Tests.Language.ArrayTypesFixture

open ProofForgeV2.Language

program ArraySurface where
  state values : Array UInt64 4

  struct Limits where
    empty : Array Bool 0
    maximum : Array Unit 4096
    u8s : Array UInt8 1
    u16s : Array UInt16 2
    u32s : Array UInt32 3
    u128s : Array UInt128 5
    u256s : Array UInt256 6
    i8s : Array Int8 7
    i16s : Array Int16 8
    i32s : Array Int32 9
    i64s : Array Int64 10
    i128s : Array Int128 11
    i256s : Array Int256 12

  enum Batch where
    | Counters(Array UInt64 4)
    | Owners(Array Principal 4096)

  const Empty : Array UInt64 0 := 0

  init(initial : Array UInt64 4) do
    values := initial

  entry echo(value : Array UInt64 4) : Array UInt64 4 do
    return value

  view get() : Array UInt64 4 do
    return values

  fn keepMaximum(value : Array Principal 4096) : Array Principal 4096 do
    return value

end Tests.Language.ArrayTypesFixture

namespace Tests.Language.ArrayTypesFixture

open ProofForgeV2.Language

program ArrayBoundary where
  entry echo(value : Array UInt64 4) : Array UInt64 4 do
    return value

program ArrayBoolBoundary where
  entry echo(value : Array Bool 0) : Array Bool 0 do
    return value

program ArrayStateBoundary where
  state value : Array UInt64 4

  init(initial : Array UInt64 4) do
    value := initial

  view get() : Array UInt64 4 do
    return value

program ArrayResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Array UInt64 4) : Array UInt64 4 do
    return value

program ArrayParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Array UInt64 4) : UInt64 do
    return 0

program ArrayOptionSurface where
  state maybeValues : Array Option UInt64 4

  struct OptionalLimits where
    emptyFlags : Array Option Bool 0
    owners : Array Option Principal 4096

  enum OptionalBatch where
    | MaybeCounters(Array Option UInt64 4)
    | MaybeOwners(Array Option Principal 4096)

  const OptionalEmpty : Array Option UInt64 0 := 0

  init(initial : Array Option UInt64 4) do
    maybeValues := initial

  entry echo(value : Array Option UInt64 4) : Array Option UInt64 4 do
    return value

  view get() : Array Option UInt64 4 do
    return maybeValues

  fn keepOptional(value : Array Option Principal 4096) : Array Option Principal 4096 do
    return value

program ArrayOptionBoundary where
  entry echo(value : Array Option UInt64 4) : Array Option UInt64 4 do
    return value

program ArrayOptionBoolBoundary where
  entry echo(value : Array Option Bool 0) : Array Option Bool 0 do
    return value

program ArrayOptionStateBoundary where
  state value : Array Option UInt64 4

  init(initial : Array Option UInt64 4) do
    value := initial

  view get() : Array Option UInt64 4 do
    return value

program ArrayOptionResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Array Option UInt64 4) : Array Option UInt64 4 do
    return value

program ArrayOptionParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Array Option UInt64 4) : UInt64 do
    return 0

end Tests.Language.ArrayTypesFixture

namespace Tests.Language.ArrayTypes

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private theorem arrayLengthAtMost4096 (length : Source.ArrayLength) :
    length.val ≤ 4096 := Nat.le_of_lt_succ length.isLt

private def twin (type : Source.ValueType) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.ArrayTypesFixture.ArrayTwin" "ArrayTwin" #[
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
  "namespace Tests.Language.ArrayTypesFixture\n\n" ++
  "program ArraySurface where\n" ++
  "  state values : Array UInt64 4\n\n" ++
  "  struct Limits where\n" ++
  "    empty : Array Bool 0\n" ++
  "    maximum : Array Unit 4096\n" ++
  "    u8s : Array UInt8 1\n" ++
  "    u16s : Array UInt16 2\n" ++
  "    u32s : Array UInt32 3\n" ++
  "    u128s : Array UInt128 5\n" ++
  "    u256s : Array UInt256 6\n" ++
  "    i8s : Array Int8 7\n" ++
  "    i16s : Array Int16 8\n" ++
  "    i32s : Array Int32 9\n" ++
  "    i64s : Array Int64 10\n" ++
  "    i128s : Array Int128 11\n" ++
  "    i256s : Array Int256 12\n\n" ++
  "  enum Batch where\n" ++
  "    | Counters(Array UInt64 4)\n" ++
  "    | Owners(Array Principal 4096)\n\n" ++
  "  const Empty : Array UInt64 0 := 0\n\n" ++
  "  init(initial : Array UInt64 4) do\n" ++
  "    values := initial\n\n" ++
  "  entry echo(value : Array UInt64 4) : Array UInt64 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Array UInt64 4 do\n" ++
  "    return values\n\n" ++
  "  fn keepMaximum(value : Array Principal 4096) : Array Principal 4096 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.ArrayTypesFixture\n"

private def arrayOptionSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ArrayTypesFixture\n\n" ++
  "program ArrayOptionSurface where\n" ++
  "  state maybeValues : Array Option UInt64 4\n\n" ++
  "  struct OptionalLimits where\n" ++
  "    emptyFlags : Array Option Bool 0\n" ++
  "    owners : Array Option Principal 4096\n\n" ++
  "  enum OptionalBatch where\n" ++
  "    | MaybeCounters(Array Option UInt64 4)\n" ++
  "    | MaybeOwners(Array Option Principal 4096)\n\n" ++
  "  const OptionalEmpty : Array Option UInt64 0 := 0\n\n" ++
  "  init(initial : Array Option UInt64 4) do\n" ++
  "    maybeValues := initial\n\n" ++
  "  entry echo(value : Array Option UInt64 4) : Array Option UInt64 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Array Option UInt64 4 do\n" ++
  "    return maybeValues\n\n" ++
  "  fn keepOptional(value : Array Option Principal 4096) : Array Option Principal 4096 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.ArrayTypesFixture\n"

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
  let maximum : Source.ArrayLength := 4096
  let _ := arrayLengthAtMost4096 maximum
  expect (maximum.val == 4096)
    "ArrayLength must retain 4096 while excluding larger values by type"

  let elaborated := Tests.Language.ArrayTypesFixture.ArraySurface
  expect (elaborated.state.map (·.type) == #[.array .u64 4])
    "Array UInt64 4 state must survive Lean command elaboration"
  match elaborated.structs with
  | #[limits] =>
      expect (limits.name == "Limits" &&
          limits.fields.map (·.type) == #[
            .array .bool 0, .array .unit 4096,
            .array .u8 1, .array .u16 2, .array .u32 3,
            .array .u128 5, .array .u256 6,
            .array .i8 7, .array .i16 8, .array .i32 9,
            .array .i64 10, .array .i128 11, .array .i256 12
          ])
        "all bounded Array PrimitiveAtom fields must preserve element and length"
  | _ => throw <| IO.userError "ArraySurface must retain one struct"
  match elaborated.enums with
  | #[batch] =>
      expect (batch.name == "Batch" && batch.variants.map (·.payloadTypes) ==
          #[#[.array .u64 4], #[.array .principal 4096]])
        "Array enum payloads must preserve element and length"
  | _ => throw <| IO.userError "ArraySurface must retain one enum"
  match elaborated.consts with
  | #[empty] =>
      expect (empty.name == "Empty" && empty.type == .array .u64 0)
        "Array UInt64 0 const type must survive elaboration"
  | _ => throw <| IO.userError "ArraySurface must retain Empty"
  match elaborated.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.array .u64 4])
        "Array initializer parameter must survive elaboration"
  | none => throw <| IO.userError "ArraySurface must retain initializer"
  match elaborated.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.array .u64 4] &&
          echoEntry.result == .array .u64 4 && getView.result == .array .u64 4 &&
          getView.mode == .view)
        "Array entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "ArraySurface must retain echo and get"
  match elaborated.functions with
  | #[keepMaximum] =>
      expect (keepMaximum.params.map (·.type) == #[.array .principal 4096] &&
          keepMaximum.result == .array .principal 4096)
        "Array Principal 4096 fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "ArraySurface must retain keepMaximum"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<array-types>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same Array Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same Array sourceHash"
  | .error error => throw <| IO.userError error.render

  let arrayOptionSurface := Tests.Language.ArrayTypesFixture.ArrayOptionSurface
  expect (arrayOptionSurface.state.map (·.type) == #[.array (.option .u64) 4])
    "Array Option UInt64 4 state must survive Lean command elaboration"
  match arrayOptionSurface.structs with
  | #[limits] =>
      expect (limits.name == "OptionalLimits" &&
          limits.fields.map (·.type) == #[.array (.option .bool) 0,
            .array (.option .principal) 4096])
        "Array Option Bool/Principal struct fields must preserve element and length"
  | _ => throw <| IO.userError "ArrayOptionSurface must retain one struct"
  match arrayOptionSurface.enums with
  | #[batch] =>
      expect (batch.name == "OptionalBatch" && batch.variants.map (·.payloadTypes) ==
          #[#[.array (.option .u64) 4], #[.array (.option .principal) 4096]])
        "Array Option enum payloads must preserve element and length"
  | _ => throw <| IO.userError "ArrayOptionSurface must retain one enum"
  match arrayOptionSurface.consts with
  | #[optionalEmpty] =>
      expect (optionalEmpty.name == "OptionalEmpty" &&
          optionalEmpty.type == .array (.option .u64) 0)
        "Array Option UInt64 0 const type must survive elaboration"
  | _ => throw <| IO.userError "ArrayOptionSurface must retain OptionalEmpty"
  match arrayOptionSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.array (.option .u64) 4])
        "Array Option initializer parameter must survive elaboration"
  | none => throw <| IO.userError "ArrayOptionSurface must retain initializer"
  match arrayOptionSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.array (.option .u64) 4] &&
          echoEntry.result == .array (.option .u64) 4 &&
          getView.result == .array (.option .u64) 4 && getView.mode == .view)
        "Array Option entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "ArrayOptionSurface must retain echo and get"
  match arrayOptionSurface.functions with
  | #[keepOptional] =>
      expect (keepOptional.params.map (·.type) == #[.array (.option .principal) 4096] &&
          keepOptional.result == .array (.option .principal) 4096)
        "Array Option Principal 4096 fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "ArrayOptionSurface must retain keepOptional"
  match ← session.selectProgram arrayOptionSurfaceSource "<array-option-types>" none with
  | .ok decoded =>
      expect (decoded == arrayOptionSurface)
        "Loader and Lean command must produce the same Array Option Source.Program"
      expect (decoded.sourceHash == arrayOptionSurface.sourceHash)
        "Loader and Lean command must produce the same Array Option sourceHash"
  | .error error => throw <| IO.userError error.render

  let arrayOptionElements : Array (String × Source.ValueType) := #[
    ("Bool", .bool),
    ("UInt8", .u8), ("UInt16", .u16), ("UInt32", .u32), ("UInt64", .u64),
    ("UInt128", .u128), ("UInt256", .u256),
    ("Int8", .i8), ("Int16", .i16), ("Int32", .i32), ("Int64", .i64),
    ("Int128", .i128), ("Int256", .i256),
    ("Unit", .unit), ("Principal", .principal)
  ]
  expect (arrayOptionElements.size == 15)
    "Array Option PrimitiveAtom matrix must contain exactly 15 elements"
  for (spelling, element) in arrayOptionElements do
    let source := negativeSource s!"ArrayOption{spelling}" s!"Array Option {spelling} 4"
    match ← session.parsePrograms source s!"<array-option-{spelling}>" with
    | .ok #[decodedProgram] =>
        expect (decodedProgram.state.map (·.type) == #[.array (.option element) 4])
          s!"Array Option {spelling} 4 must preserve its exact element and length"
    | .ok programs =>
        throw <| IO.userError s!"Array Option {spelling} 4 produced {programs.size} programs"
    | .error error =>
        throw <| IO.userError s!"Array Option {spelling} 4 must parse: {error.render}"

  let sourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array UInt64 0", .array .u64 0, 247,
      "3ceb8bd535df35be7ffc11b0936fbb350edab1bbb5506400e0946e4404f7551f"),
    ("Array UInt64 4", .array .u64 4, 247,
      "337a745e0ef4f48bd8c768ba0b57d529839e083681378f49772b435530b490ed"),
    ("Array UInt64 4096", .array .u64 4096, 247,
      "8c4013931a98a37bab4ad7172ffd35f214c285ccce75a4cc82e24f476783357c"),
    ("Array Bool 0", .array .bool 0, 247,
      "5a753558596d74f964ebfa91412d91fdf0f4a6ffe2360b04eac13b8137fe3f9b")
  ]
  let mut goldensBound := true
  for (label, type, expectedSize, expectedHash) in sourceVectors do
    let sourceProgram := twin type
    unless sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash do
      goldensBound := false
      IO.eprintln
        s!"{label} source: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"

  expect ((twin (.array .u64 0)).sourceHash != (twin .u64).sourceHash &&
      (twin (.array .u64 0)).sourceHash != (twin (.option .u64)).sourceHash &&
      (twin (.array .u64 0)).sourceHash != (twin (.bytes 0)).sourceHash &&
      (twin (.array .u64 0)).sourceHash != (twin (.array .u64 4)).sourceHash &&
      (twin (.array .u64 0)).sourceHash != (twin (.array .bool 0)).sourceHash)
    "Array tag, element and complete length payload must bind sourceHash without aliases"

  let semanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array UInt64 0", .array .u64 0, 196,
      "a46564015716999f07e757ebed47cfe72b23f339dad4da1158eea4a2af08f663"),
    ("Array UInt64 4", .array .u64 4, 196,
      "74cb1feb33e426bd600e499c789853c86a37e643989ef53f6c8af6efce9f675b"),
    ("Array UInt64 4096", .array .u64 4096, 196,
      "c9f689ce43d78c100366d90296ef5b6f37a9f8c0612d43d4bec3a5eb0d74d3aa"),
    ("Array Bool 0", .array .bool 0, 197,
      "d5557eb2a9ccabb38305d976ec9b6bc0e48f97650bb9d4d2cecd98594b3ff24e")
  ]
  for (label, type, expectedSize, expectedHash) in semanticVectors do
    let compiled ← match Compiler.compile (twin type) with
      | .ok value => pure value
      | .error error =>
          throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    unless compiled.canonicalBytes.size == expectedSize && compiled.semanticHash == expectedHash do
      goldensBound := false
      IO.eprintln
        s!"{label} semantic: size={compiled.canonicalBytes.size}, hash={compiled.semanticHash}"
  expect goldensBound "Array tag18 canonical goldens must be bound"

  let arrayOptionSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Option UInt64 0", .array (.option .u64) 0, 249,
      "0b3153ecbbd19f8d92ee224de6dded402da99f88c4d4fb1b8a9e5f8628ead58e"),
    ("Array Option UInt64 4", .array (.option .u64) 4, 249,
      "d31d81e088af346649d938334cf796f3f33beb50d866ef3adefb5ee156c5bd6d"),
    ("Array Option UInt64 4096", .array (.option .u64) 4096, 249,
      "0b95929e3a5cc05e18ac6acf22d56103409e56b324b5fa1753c9093fc87b6040"),
    ("Array Option Bool 0", .array (.option .bool) 0, 249,
      "9a0a7cc57a9b67243fcbfeb39b5438949bea65d58fc92989afbd8a4820cbb61a")
  ]
  for (label, type, expectedSize, expectedHash) in arrayOptionSourceVectors do
    let sourceProgram := twin type
    unless sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash do
      goldensBound := false
      IO.eprintln
        s!"{label} source: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  expect ((twin (.array (.option .u64) 0)).sourceHash != (twin (.array .u64 0)).sourceHash &&
      (twin (.array (.option .u64) 0)).sourceHash !=
        (twin (.option (.array .u64 0))).sourceHash &&
      (twin (.array (.option .u64) 0)).sourceHash != (twin (.option .u64)).sourceHash &&
      (twin (.array (.option .u64) 0)).sourceHash !=
        (twin (.array (.option .u64) 4)).sourceHash &&
      (twin (.array (.option .u64) 0)).sourceHash !=
        (twin (.array (.option .bool) 0)).sourceHash)
    "Array Option must bind Array/Option tags, element and complete length payload"

  let arrayOptionSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Option UInt64 0", .array (.option .u64) 0, 198,
      "c0a334ef09579cb80c7314a501f442ce0f490504e0d3f0c9a25bbba421f34213"),
    ("Array Option UInt64 4", .array (.option .u64) 4, 198,
      "930eb439b69fbe899d0c81c847ce72e1175c480fd33d5648be1b3c169d169c7b"),
    ("Array Option UInt64 4096", .array (.option .u64) 4096, 198,
      "64b9ae5a68b1329c4ed50bb4c44b1fe7499cea5c009f9ca8644dc3f3d8368470"),
    ("Array Option Bool 0", .array (.option .bool) 0, 199,
      "2f1dec9116e2cc84d903436da7c5a08a735902affe1895e9e392bb43cc2db809")
  ]
  for (label, type, expectedSize, expectedHash) in arrayOptionSemanticVectors do
    let compiled ← match Compiler.compile (twin type) with
      | .ok value => pure value
      | .error error =>
          throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    unless compiled.canonicalBytes.size == expectedSize && compiled.semanticHash == expectedHash do
      goldensBound := false
      IO.eprintln
        s!"{label} semantic: size={compiled.canonicalBytes.size}, hash={compiled.semanticHash}"
  expect goldensBound "Array Option tag18+tag16 canonical goldens must be bound"

  for (label, spelling) in [
      ("bare Array", "Array"),
      ("missing Array element", "Array 4"),
      ("missing Array length", "Array UInt64"),
      ("unknown Array element", "Array Mystery 4"),
      ("Field Array element", "Array Field 4"),
      ("Bytes Array element", "Array Bytes 4"),
      ("Option Array element", "Array Option 4"),
      ("unknown Array Option element", "Array Option Mystery 4"),
      ("Field Array Option element", "Array Option Field 4"),
      ("escaped Array Option element", "Array Option «UInt64» 4"),
      ("qualified Array Option element", "Array Option Std.UInt64 4"),
      ("over-bound Array Option length", "Array Option UInt64 4097"),
      ("leading-zero Array Option length", "Array Option UInt64 01"),
      ("hex Array Option length", "Array Option UInt64 0x10"),
      ("underscore Array Option length", "Array Option UInt64 4_096"),
      ("Array element", "Array Array 4"),
      ("qualified Array element", "Array Std.UInt64 4"),
      ("reserved Array element", "Array «const» 4"),
      ("over-bound Array length", "Array UInt64 4097"),
      ("leading-zero Array length", "Array UInt64 01"),
      ("hex Array length", "Array UInt64 0x10"),
      ("underscore Array length", "Array UInt64 4_096")
    ] do
    expectUnsupportedType label
      (← session.parsePrograms (negativeSource "RejectedArrayType" spelling) s!"<array-{label}>")

  for (label, spelling) in [
      ("negative Array length", "Array UInt64 -1"),
      ("extra Array payload", "Array UInt64 4 Principal"),
      ("full Field Array element", "Array Field bn254_fr 4"),
      ("nested Bytes Array element", "Array Bytes 32 4"),
      ("nested Array Option element", "Array Option Option Bool 4"),
      ("nested Bytes Array Option element", "Array Option Bytes 8 4"),
      ("nested Array Array Option element", "Array Option Array UInt64 4 4"),
      ("Map Array Option element", "Array Option Map UInt64 Bool 4"),
      ("negative Array Option length", "Array Option UInt64 -1"),
      ("missing Array Option length", "Array Option UInt64"),
      ("extra Array Option payload", "Array Option UInt64 4 Principal"),
      ("split Array Option element", "Array Option\n  UInt64 4"),
      ("split Array Option length", "Array Option UInt64\n  4"),
      ("escaped Array Option constructor", "«Array» Option UInt64 4"),
      ("qualified Array Option constructor", "Std.Array Option UInt64 4"),
      ("escaped Option constructor in Array", "Array «Option» UInt64 4"),
      ("qualified Option constructor in Array", "Array Std.Option UInt64 4"),
      ("nested Array element", "Array Array UInt64 4 4"),
      ("parenthesized Array element", "Array (Array UInt64 4) 2"),
      ("Map Array element", "Array Map UInt64 Bool 4"),
      ("split Array element", "Array\n  UInt64 4"),
      ("split Array length", "Array UInt64\n  4"),
      ("escaped Array", "«Array» UInt64 4"),
      ("qualified Array", "Std.Array UInt64 4"),
      ("existing Option extra payload", "Option UInt64 Principal")
    ] do
    let source := negativeSource "RejectedArrayShape" spelling
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<array-{label}>")
    expectParserRejected label source result

  let boundary ← match Compiler.compile Tests.Language.ArrayTypesFixture.ArrayBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"ArrayBoundary must compile: {error.render}"
  expect (boundary.requirements == #[])
    "Array UInt64 must propagate the element's zero requirements"
  match boundary.entries with
  | #[echoEntry] =>
      expect (echoEntry.params.map (·.type) == #[.array .u64 4] &&
          echoEntry.result == .array .u64 4)
        "Source-to-Semantic adaptation must preserve Array element and length"
  | _ => throw <| IO.userError "ArrayBoundary must retain one semantic entry"
  for target in Targets.phase1 do
    match Targets.checkSupport target boundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError s!"{target} must support zero-requirement Array carrier: {error.render}"

  let boolBoundary ← match Compiler.compile Tests.Language.ArrayTypesFixture.ArrayBoolBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"ArrayBoolBoundary must compile: {error.render}"
  expect (boolBoundary.requirements == #[.boolValues])
    "Array Bool must propagate boolValues exactly once"
  for target in Targets.phase1 do
    match Targets.checkSupport target boolBoundary with
    | .error (.unsupportedRequirement .boolValues actual) =>
        expect (actual == target)
          s!"Array Bool support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError s!"Array Bool/{target} reached wrong failure: {other.render}"
    | .ok () => throw <| IO.userError s!"Array Bool/{target} unexpectedly passed support"

  let arrayOptionBoundary ← match Compiler.compile
      Tests.Language.ArrayTypesFixture.ArrayOptionBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"ArrayOptionBoundary must compile: {error.render}"
  expect (arrayOptionBoundary.requirements == #[])
    "Array Option UInt64 must recursively propagate zero requirements"
  match arrayOptionBoundary.entries with
  | #[echoEntry] =>
      expect (echoEntry.params.map (·.type) == #[.array (.option .u64) 4] &&
          echoEntry.result == .array (.option .u64) 4)
        "Source-to-Semantic adaptation must preserve Array Option element and length"
  | _ => throw <| IO.userError "ArrayOptionBoundary must retain one semantic entry"
  for target in Targets.phase1 do
    match Targets.checkSupport target arrayOptionBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError
          s!"{target} must support zero-requirement Array Option carrier: {error.render}"

  let arrayOptionBoolBoundary ← match Compiler.compile
      Tests.Language.ArrayTypesFixture.ArrayOptionBoolBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"ArrayOptionBoolBoundary must compile: {error.render}"
  expect (arrayOptionBoolBoundary.requirements == #[.boolValues])
    "Array Option Bool must recursively propagate boolValues exactly once"
  for target in Targets.phase1 do
    match Targets.checkSupport target arrayOptionBoolBoundary with
    | .error (.unsupportedRequirement .boolValues actual) =>
        expect (actual == target)
          s!"Array Option Bool support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError s!"Array Option Bool/{target} reached wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError s!"Array Option Bool/{target} unexpectedly passed support"

  for (label, sourceProgram, needle) in [
      ("ArrayStateBoundary", Tests.Language.ArrayTypesFixture.ArrayStateBoundary,
        "is not UInt64"),
      ("ArrayResultBoundary", Tests.Language.ArrayTypesFixture.ArrayResultBoundary,
        "does not return UInt64"),
      ("ArrayParamBoundary", Tests.Language.ArrayTypesFixture.ArrayParamBoundary,
        "is not UInt64"),
      ("ArrayOptionStateBoundary",
        Tests.Language.ArrayTypesFixture.ArrayOptionStateBoundary,
        "is not UInt64"),
      ("ArrayOptionResultBoundary",
        Tests.Language.ArrayTypesFixture.ArrayOptionResultBoundary,
        "does not return UInt64"),
      ("ArrayOptionParamBoundary",
        Tests.Language.ArrayTypesFixture.ArrayOptionParamBoundary,
        "is not UInt64")
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

end Tests.Language.ArrayTypes
