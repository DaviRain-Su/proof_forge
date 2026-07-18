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
  state maybeBlob : Option Bytes 8

  struct Pair where
    enabled : Option Bool
    owner : Option Principal
    scalar : Option Field bn254_fr
    nestedEnabled : Option Option Bool
    arrayFlags : Option Array Bool 0
    blob : Option Bytes 8

  enum Tag where
    | MaybeUnit(Option Unit)
    | MaybeCount(Option UInt64)
    | MaybeScalar(Option Field bn254_fr)
    | MaybeNestedCount(Option Option UInt64)
    | MaybeArray(Option Array Principal 4096)
    | MaybeBlob(Option Bytes 4096)

  const Seed : Option UInt64 := 0
  const FieldSeed : Option Field bn254_fr := 0
  const NestedFlag : Option Option Bool := 0
  const ArraySeed : Option Array UInt64 0 := 0
  const BlobSeed : Option Bytes 0 := 0

  init(initial : Option UInt64, scalar : Option Field bn254_fr,
      nestedInitial : Option Option UInt64, arrayInitial : Option Array UInt64 4,
      blobInitial : Option Bytes 8) do
    maybeCount := initial
    maybeScalar := scalar
    nestedCount := nestedInitial
    maybeBatch := arrayInitial
    maybeBlob := blobInitial

  entry echo(value : Option UInt64) : Option UInt64 do
    return value

  entry echoField(value : Option Field bn254_fr) : Option Field bn254_fr do
    return value

  entry echoNested(value : Option Option UInt64) : Option Option UInt64 do
    return value

  entry echoArray(value : Option Array UInt64 4) : Option Array UInt64 4 do
    return value

  entry echoBytes(value : Option Bytes 8) : Option Bytes 8 do
    return value

  view get() : Option UInt64 do
    return maybeCount

  view getField() : Option Field bn254_fr do
    return maybeScalar

  view getNested() : Option Option UInt64 do
    return nestedCount

  view getArray() : Option Array UInt64 4 do
    return maybeBatch

  view getBytes() : Option Bytes 8 do
    return maybeBlob

  fn ident(value : Option Principal) : Option Principal do
    return value

  fn identField(value : Option Field bn254_fr) : Option Field bn254_fr do
    return value

  fn identNested(value : Option Option Bool) : Option Option Bool do
    return value

  fn identArray(value : Option Array Bool 0) : Option Array Bool 0 do
    return value

  fn identBytes(value : Option Bytes 4096) : Option Bytes 4096 do
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

program OptionBytesBoundary where
  entry echo(value : Option Bytes 32) : Option Bytes 32 do
    return value

program NestedOptionFieldSurface where
  state nestedScalar : Option Option Field bn254_fr

  struct NestedScalarBox where
    value : Option Option Field bn254_fr

  enum NestedScalarTag where
    | MaybeNestedScalar(Option Option Field bn254_fr)

  const NestedFieldSeed : Option Option Field bn254_fr := 0

  init(initial : Option Option Field bn254_fr) do
    nestedScalar := initial

  entry echo(value : Option Option Field bn254_fr) : Option Option Field bn254_fr do
    return value

  view get() : Option Option Field bn254_fr do
    return nestedScalar

  fn ident(value : Option Option Field bn254_fr) : Option Option Field bn254_fr do
    return value

program NestedOptionFieldBoundary where
  entry echo(value : Option Option Field bn254_fr) : Option Option Field bn254_fr do
    return value

program NestedOptionBytesSurface where
  state nestedBlob : Option Option Bytes 8

  event NestedBlobEvent(payload : Option Option Bytes 8)
  error NestedBlobError(payload : Option Option Bytes 8)

  struct NestedBlobBox where
    empty : Option Option Bytes 0
    ordinary : Option Option Bytes 8
    maximum : Option Option Bytes 4096

  enum NestedBlobTag where
    | MaybeNestedBlob(Option Option Bytes 8)
    | MaybeNestedMax(Option Option Bytes 4096)

  const NestedBlobSeed : Option Option Bytes 0 := 0

  init(initial : Option Option Bytes 8) do
    nestedBlob := initial

  entry echo(value : Option Option Bytes 8) : Option Option Bytes 8 do
    return value

  view get() : Option Option Bytes 8 do
    return nestedBlob

  fn ident(value : Option Option Bytes 4096) : Option Option Bytes 4096 do
    return value

program NestedOptionBytesBoundary where
  entry echo(value : Option Option Bytes 8) : Option Option Bytes 8 do
    return value

program NestedOptionBytesStateBoundary where
  state value : Option Option Bytes 8

  init(initial : Option Option Bytes 8) do
    value := initial

  view get() : Option Option Bytes 8 do
    return value

program NestedOptionBytesResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Option Bytes 8) : Option Option Bytes 8 do
    return value

program NestedOptionBytesParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Option Bytes 8) : UInt64 do
    return 0

program NestedOptionArraySurface where
  state nestedBatch : Option Option Array UInt64 4

  event NestedArrayEvent(payload : Option Option Array UInt64 4)
  error NestedArrayError(payload : Option Option Array UInt64 4)

  struct NestedArrayBox where
    empty : Option Option Array UInt64 0
    ordinary : Option Option Array UInt64 4
    maximum : Option Option Array UInt64 4096
    flags : Option Option Array Bool 0

  enum NestedArrayTag where
    | MaybeNestedBatch(Option Option Array UInt64 4)
    | MaybeNestedFlags(Option Option Array Bool 0)
    | MaybeNestedMax(Option Option Array Principal 4096)

  const NestedArraySeed : Option Option Array UInt64 0 := 0

  init(initial : Option Option Array UInt64 4) do
    nestedBatch := initial

  entry echo(value : Option Option Array UInt64 4) : Option Option Array UInt64 4 do
    return value

  view get() : Option Option Array UInt64 4 do
    return nestedBatch

  fn ident(value : Option Option Array Principal 4096) : Option Option Array Principal 4096 do
    return value

program NestedOptionArrayBoundary where
  entry echo(value : Option Option Array UInt64 4) : Option Option Array UInt64 4 do
    return value

program NestedOptionArrayBoolBoundary where
  entry echo(value : Option Option Array Bool 0) : Option Option Array Bool 0 do
    return value

program NestedOptionArrayStateBoundary where
  state value : Option Option Array UInt64 4

  init(initial : Option Option Array UInt64 4) do
    value := initial

  view get() : Option Option Array UInt64 4 do
    return value

program NestedOptionArrayResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Option Array UInt64 4) : Option Option Array UInt64 4 do
    return value

program NestedOptionArrayParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Option Array UInt64 4) : UInt64 do
    return 0

program OptionArrayFieldSurface where
  state scalars : Option Array Field bn254_fr 4

  event OptionArrayFieldEvent(payload : Option Array Field bn254_fr 4)
  error OptionArrayFieldError(payload : Option Array Field bn254_fr 4)

  struct OptionArrayFieldBox where
    empty : Option Array Field bn254_fr 0
    ordinary : Option Array Field bn254_fr 4
    maximum : Option Array Field bn254_fr 4096

  enum OptionArrayFieldTag where
    | MaybeScalars(Option Array Field bn254_fr 4)
    | MaybeMaximum(Option Array Field bn254_fr 4096)

  const OptionArrayFieldSeed : Option Array Field bn254_fr 0 := 0

  init(initial : Option Array Field bn254_fr 4) do
    scalars := initial

  entry echo(value : Option Array Field bn254_fr 4) : Option Array Field bn254_fr 4 do
    return value

  view get() : Option Array Field bn254_fr 4 do
    return scalars

  fn ident(value : Option Array Field bn254_fr 4096) : Option Array Field bn254_fr 4096 do
    return value

program OptionArrayFieldBoundary where
  entry echo(value : Option Array Field bn254_fr 4) : Option Array Field bn254_fr 4 do
    return value

program OptionArrayOptionSurface where
  state nestedCounts : Option Array Option UInt64 4

  event OptionArrayOptionEvent(payload : Option Array Option UInt64 4)
  error OptionArrayOptionError(payload : Option Array Option UInt64 4)

  struct OptionArrayOptionBox where
    empty : Option Array Option UInt64 0
    ordinary : Option Array Option UInt64 4
    maximum : Option Array Option UInt64 4096
    flags : Option Array Option Bool 0

  enum OptionArrayOptionTag where
    | MaybeNestedCounts(Option Array Option UInt64 4)
    | MaybeNestedFlags(Option Array Option Bool 0)
    | MaybeNestedOwners(Option Array Option Principal 4096)

  const OptionArrayOptionSeed : Option Array Option UInt64 0 := 0

  init(initial : Option Array Option UInt64 4) do
    nestedCounts := initial

  entry echo(value : Option Array Option UInt64 4) : Option Array Option UInt64 4 do
    return value

  view get() : Option Array Option UInt64 4 do
    return nestedCounts

  fn ident(value : Option Array Option Principal 4096) : Option Array Option Principal 4096 do
    return value

program OptionArrayOptionBoundary where
  entry echo(value : Option Array Option UInt64 4) : Option Array Option UInt64 4 do
    return value

program OptionArrayOptionBoolBoundary where
  entry echo(value : Option Array Option Bool 0) : Option Array Option Bool 0 do
    return value

program OptionArrayOptionStateBoundary where
  state value : Option Array Option UInt64 4

  init(initial : Option Array Option UInt64 4) do
    value := initial

  view get() : Option Array Option UInt64 4 do
    return value

program OptionArrayOptionResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Array Option UInt64 4) : Option Array Option UInt64 4 do
    return value

program OptionArrayOptionParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Array Option UInt64 4) : UInt64 do
    return 0

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

program OptionBytesStateBoundary where
  state value : Option Bytes 32

  init(initial : Option Bytes 32) do
    value := initial

  view get() : Option Bytes 32 do
    return value

program OptionBytesResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Bytes 32) : Option Bytes 32 do
    return value

program OptionBytesParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Bytes 32) : UInt64 do
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
  "  state maybeBlob : Option Bytes 8\n\n" ++
  "  struct Pair where\n" ++
  "    enabled : Option Bool\n" ++
  "    owner : Option Principal\n" ++
  "    scalar : Option Field bn254_fr\n" ++
  "    nestedEnabled : Option Option Bool\n" ++
  "    arrayFlags : Option Array Bool 0\n" ++
  "    blob : Option Bytes 8\n\n" ++
  "  enum Tag where\n" ++
  "    | MaybeUnit(Option Unit)\n" ++
  "    | MaybeCount(Option UInt64)\n" ++
  "    | MaybeScalar(Option Field bn254_fr)\n" ++
  "    | MaybeNestedCount(Option Option UInt64)\n" ++
  "    | MaybeArray(Option Array Principal 4096)\n" ++
  "    | MaybeBlob(Option Bytes 4096)\n\n" ++
  "  const Seed : Option UInt64 := 0\n\n" ++
  "  const FieldSeed : Option Field bn254_fr := 0\n\n" ++
  "  const NestedFlag : Option Option Bool := 0\n\n" ++
  "  const ArraySeed : Option Array UInt64 0 := 0\n\n" ++
  "  const BlobSeed : Option Bytes 0 := 0\n\n" ++
  "  init(initial : Option UInt64, scalar : Option Field bn254_fr,\n" ++
  "      nestedInitial : Option Option UInt64, arrayInitial : Option Array UInt64 4,\n" ++
  "      blobInitial : Option Bytes 8) do\n" ++
  "    maybeCount := initial\n\n" ++
  "    maybeScalar := scalar\n\n" ++
  "    nestedCount := nestedInitial\n\n" ++
  "    maybeBatch := arrayInitial\n\n" ++
  "    maybeBlob := blobInitial\n\n" ++
  "  entry echo(value : Option UInt64) : Option UInt64 do\n" ++
  "    return value\n\n" ++
  "  entry echoField(value : Option Field bn254_fr) : Option Field bn254_fr do\n" ++
  "    return value\n\n" ++
  "  entry echoNested(value : Option Option UInt64) : Option Option UInt64 do\n" ++
  "    return value\n\n" ++
  "  entry echoArray(value : Option Array UInt64 4) : Option Array UInt64 4 do\n" ++
  "    return value\n\n" ++
  "  entry echoBytes(value : Option Bytes 8) : Option Bytes 8 do\n" ++
  "    return value\n\n" ++
  "  view get() : Option UInt64 do\n" ++
  "    return maybeCount\n\n" ++
  "  view getField() : Option Field bn254_fr do\n" ++
  "    return maybeScalar\n\n" ++
  "  view getNested() : Option Option UInt64 do\n" ++
  "    return nestedCount\n\n" ++
  "  view getArray() : Option Array UInt64 4 do\n" ++
  "    return maybeBatch\n\n" ++
  "  view getBytes() : Option Bytes 8 do\n" ++
  "    return maybeBlob\n\n" ++
  "  fn ident(value : Option Principal) : Option Principal do\n" ++
  "    return value\n\n" ++
  "  fn identField(value : Option Field bn254_fr) : Option Field bn254_fr do\n" ++
  "    return value\n\n" ++
  "  fn identNested(value : Option Option Bool) : Option Option Bool do\n" ++
  "    return value\n\n" ++
  "  fn identArray(value : Option Array Bool 0) : Option Array Bool 0 do\n" ++
  "    return value\n\n" ++
  "  fn identBytes(value : Option Bytes 4096) : Option Bytes 4096 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.OptionDeclarationsFixture\n"

private def nestedOptionFieldSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.OptionDeclarationsFixture\n\n" ++
  "program NestedOptionFieldSurface where\n" ++
  "  state nestedScalar : Option Option Field bn254_fr\n\n" ++
  "  struct NestedScalarBox where\n" ++
  "    value : Option Option Field bn254_fr\n\n" ++
  "  enum NestedScalarTag where\n" ++
  "    | MaybeNestedScalar(Option Option Field bn254_fr)\n\n" ++
  "  const NestedFieldSeed : Option Option Field bn254_fr := 0\n\n" ++
  "  init(initial : Option Option Field bn254_fr) do\n" ++
  "    nestedScalar := initial\n\n" ++
  "  entry echo(value : Option Option Field bn254_fr) : Option Option Field bn254_fr do\n" ++
  "    return value\n\n" ++
  "  view get() : Option Option Field bn254_fr do\n" ++
  "    return nestedScalar\n\n" ++
  "  fn ident(value : Option Option Field bn254_fr) : Option Option Field bn254_fr do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.OptionDeclarationsFixture\n"

private def nestedOptionBytesSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.OptionDeclarationsFixture\n\n" ++
  "program NestedOptionBytesSurface where\n" ++
  "  state nestedBlob : Option Option Bytes 8\n\n" ++
  "  event NestedBlobEvent(payload : Option Option Bytes 8)\n" ++
  "  error NestedBlobError(payload : Option Option Bytes 8)\n\n" ++
  "  struct NestedBlobBox where\n" ++
  "    empty : Option Option Bytes 0\n" ++
  "    ordinary : Option Option Bytes 8\n" ++
  "    maximum : Option Option Bytes 4096\n\n" ++
  "  enum NestedBlobTag where\n" ++
  "    | MaybeNestedBlob(Option Option Bytes 8)\n" ++
  "    | MaybeNestedMax(Option Option Bytes 4096)\n\n" ++
  "  const NestedBlobSeed : Option Option Bytes 0 := 0\n\n" ++
  "  init(initial : Option Option Bytes 8) do\n" ++
  "    nestedBlob := initial\n\n" ++
  "  entry echo(value : Option Option Bytes 8) : Option Option Bytes 8 do\n" ++
  "    return value\n\n" ++
  "  view get() : Option Option Bytes 8 do\n" ++
  "    return nestedBlob\n\n" ++
  "  fn ident(value : Option Option Bytes 4096) : Option Option Bytes 4096 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.OptionDeclarationsFixture\n"

private def nestedOptionArraySurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.OptionDeclarationsFixture\n\n" ++
  "program NestedOptionArraySurface where\n" ++
  "  state nestedBatch : Option Option Array UInt64 4\n\n" ++
  "  event NestedArrayEvent(payload : Option Option Array UInt64 4)\n" ++
  "  error NestedArrayError(payload : Option Option Array UInt64 4)\n\n" ++
  "  struct NestedArrayBox where\n" ++
  "    empty : Option Option Array UInt64 0\n" ++
  "    ordinary : Option Option Array UInt64 4\n" ++
  "    maximum : Option Option Array UInt64 4096\n" ++
  "    flags : Option Option Array Bool 0\n\n" ++
  "  enum NestedArrayTag where\n" ++
  "    | MaybeNestedBatch(Option Option Array UInt64 4)\n" ++
  "    | MaybeNestedFlags(Option Option Array Bool 0)\n" ++
  "    | MaybeNestedMax(Option Option Array Principal 4096)\n\n" ++
  "  const NestedArraySeed : Option Option Array UInt64 0 := 0\n\n" ++
  "  init(initial : Option Option Array UInt64 4) do\n" ++
  "    nestedBatch := initial\n\n" ++
  "  entry echo(value : Option Option Array UInt64 4) : Option Option Array UInt64 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Option Option Array UInt64 4 do\n" ++
  "    return nestedBatch\n\n" ++
  "  fn ident(value : Option Option Array Principal 4096) : Option Option Array Principal 4096 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.OptionDeclarationsFixture\n"

private def optionArrayFieldSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.OptionDeclarationsFixture\n\n" ++
  "program OptionArrayFieldSurface where\n" ++
  "  state scalars : Option Array Field bn254_fr 4\n\n" ++
  "  event OptionArrayFieldEvent(payload : Option Array Field bn254_fr 4)\n" ++
  "  error OptionArrayFieldError(payload : Option Array Field bn254_fr 4)\n\n" ++
  "  struct OptionArrayFieldBox where\n" ++
  "    empty : Option Array Field bn254_fr 0\n" ++
  "    ordinary : Option Array Field bn254_fr 4\n" ++
  "    maximum : Option Array Field bn254_fr 4096\n\n" ++
  "  enum OptionArrayFieldTag where\n" ++
  "    | MaybeScalars(Option Array Field bn254_fr 4)\n" ++
  "    | MaybeMaximum(Option Array Field bn254_fr 4096)\n\n" ++
  "  const OptionArrayFieldSeed : Option Array Field bn254_fr 0 := 0\n\n" ++
  "  init(initial : Option Array Field bn254_fr 4) do\n" ++
  "    scalars := initial\n\n" ++
  "  entry echo(value : Option Array Field bn254_fr 4) : Option Array Field bn254_fr 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Option Array Field bn254_fr 4 do\n" ++
  "    return scalars\n\n" ++
  "  fn ident(value : Option Array Field bn254_fr 4096) : Option Array Field bn254_fr 4096 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.OptionDeclarationsFixture\n"

private def optionArrayOptionSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.OptionDeclarationsFixture\n\n" ++
  "program OptionArrayOptionSurface where\n" ++
  "  state nestedCounts : Option Array Option UInt64 4\n\n" ++
  "  event OptionArrayOptionEvent(payload : Option Array Option UInt64 4)\n" ++
  "  error OptionArrayOptionError(payload : Option Array Option UInt64 4)\n\n" ++
  "  struct OptionArrayOptionBox where\n" ++
  "    empty : Option Array Option UInt64 0\n" ++
  "    ordinary : Option Array Option UInt64 4\n" ++
  "    maximum : Option Array Option UInt64 4096\n" ++
  "    flags : Option Array Option Bool 0\n\n" ++
  "  enum OptionArrayOptionTag where\n" ++
  "    | MaybeNestedCounts(Option Array Option UInt64 4)\n" ++
  "    | MaybeNestedFlags(Option Array Option Bool 0)\n" ++
  "    | MaybeNestedOwners(Option Array Option Principal 4096)\n\n" ++
  "  const OptionArrayOptionSeed : Option Array Option UInt64 0 := 0\n\n" ++
  "  init(initial : Option Array Option UInt64 4) do\n" ++
  "    nestedCounts := initial\n\n" ++
  "  entry echo(value : Option Array Option UInt64 4) : Option Array Option UInt64 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Option Array Option UInt64 4 do\n" ++
  "    return nestedCounts\n\n" ++
  "  fn ident(value : Option Array Option Principal 4096) : Option Array Option Principal 4096 do\n" ++
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

set_option maxRecDepth 2048 in
unsafe def run : IO Unit := do
  let elaborated := Tests.Language.OptionDeclarationsFixture.OptionSurface
  expect (elaborated.state.map (·.type) ==
      #[.option .u64, .option .field, .option (.option .u64), .option (.array .u64 4),
        .option (.bytes 8)])
    "Option UInt64/Field/nested/Array/Bytes state must survive Lean command elaboration"
  match elaborated.structs with
  | #[pair] =>
      expect (pair.name == "Pair" &&
          pair.fields.map (·.type) ==
            #[.option .bool, .option .principal, .option .field, .option (.option .bool),
              .option (.array .bool 0), .option (.bytes 8)])
        "Option Bool/Principal/Field/nested/Array/Bytes struct fields must preserve element types"
  | _ => throw <| IO.userError "OptionSurface must retain one struct"
  match elaborated.enums with
  | #[tag] =>
      expect (tag.name == "Tag" && tag.variants.map (·.payloadTypes) ==
          #[#[.option .unit], #[.option .u64], #[.option .field],
            #[.option (.option .u64)], #[.option (.array .principal 4096)],
            #[.option (.bytes 4096)]])
        "Option Unit/UInt64/Field/nested/Array/Bytes enum payloads must preserve element types"
  | _ => throw <| IO.userError "OptionSurface must retain one enum"
  match elaborated.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) ==
          #[.option .u64, .option .field, .option (.option .u64),
            .option (.array .u64 4), .option (.bytes 8)])
        "Option UInt64/Field/nested/Array/Bytes initializer parameters must survive elaboration"
  | none => throw <| IO.userError "OptionSurface must retain initializer"
  match elaborated.entries with
  | #[echoEntry, echoField, echoNested, echoArray, echoBytes, getView, getField, getNested,
      getArray, getBytes] =>
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
          getArray.result == .option (.array .u64 4) && getArray.mode == .view &&
          echoBytes.params.map (·.type) == #[.option (.bytes 8)] &&
          echoBytes.result == .option (.bytes 8) &&
          getBytes.result == .option (.bytes 8) && getBytes.mode == .view)
        "Option UInt64/Field/nested/Array/Bytes entry/view types must survive elaboration"
  | _ => throw <| IO.userError "OptionSurface must retain ten entries/views"
  match elaborated.functions with
  | #[identFn, identField, identNested, identArray, identBytes] =>
      expect (identFn.params.map (·.type) == #[.option .principal] &&
          identFn.result == .option .principal &&
          identField.params.map (·.type) == #[.option .field] &&
          identField.result == .option .field &&
          identNested.params.map (·.type) == #[.option (.option .bool)] &&
          identNested.result == .option (.option .bool) &&
          identArray.params.map (·.type) == #[.option (.array .bool 0)] &&
          identArray.result == .option (.array .bool 0) &&
          identBytes.params.map (·.type) == #[.option (.bytes 4096)] &&
          identBytes.result == .option (.bytes 4096))
        "Option Principal/Field/nested/Array/Bytes fn parameter/results must survive elaboration"
  | _ =>
      throw <| IO.userError
        "OptionSurface must retain ident, identField, identNested, identArray and identBytes"
  match elaborated.consts with
  | #[seed, fieldSeed, nestedFlag, arraySeed, blobSeed] =>
      expect (seed.name == "Seed" && seed.type == .option .u64 &&
          fieldSeed.name == "FieldSeed" && fieldSeed.type == .option .field &&
          nestedFlag.name == "NestedFlag" && nestedFlag.type == .option (.option .bool) &&
          arraySeed.name == "ArraySeed" && arraySeed.type == .option (.array .u64 0) &&
          blobSeed.name == "BlobSeed" && blobSeed.type == .option (.bytes 0))
        "Option UInt64/Field/nested/Array/Bytes const types must survive elaboration"
  | _ =>
      throw <| IO.userError
        "OptionSurface must retain Seed, FieldSeed, NestedFlag, ArraySeed and BlobSeed"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<option-declarations>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same Option Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same Option sourceHash"
  | .error error => throw <| IO.userError error.render

  let nestedFieldSurface := Tests.Language.OptionDeclarationsFixture.NestedOptionFieldSurface
  expect (nestedFieldSurface.state.map (·.type) == #[.option (.option .field)])
    "Option Option Field bn254_fr state must survive Lean command elaboration"
  match nestedFieldSurface.structs with
  | #[box] =>
      expect (box.name == "NestedScalarBox" &&
          box.fields.map (·.type) == #[.option (.option .field)])
        "Option Option Field struct field must preserve both Option tags and Field"
  | _ => throw <| IO.userError "NestedOptionFieldSurface must retain one struct"
  match nestedFieldSurface.enums with
  | #[tag] =>
      expect (tag.name == "NestedScalarTag" &&
          tag.variants.map (·.payloadTypes) == #[#[.option (.option .field)]])
        "Option Option Field enum payload must preserve both Option tags and Field"
  | _ => throw <| IO.userError "NestedOptionFieldSurface must retain one enum"
  match nestedFieldSurface.consts with
  | #[seed] =>
      expect (seed.name == "NestedFieldSeed" && seed.type == .option (.option .field))
        "Option Option Field const type must survive elaboration"
  | _ => throw <| IO.userError "NestedOptionFieldSurface must retain NestedFieldSeed"
  match nestedFieldSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.option (.option .field)])
        "Option Option Field initializer parameter must survive elaboration"
  | none => throw <| IO.userError "NestedOptionFieldSurface must retain initializer"
  match nestedFieldSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.option (.option .field)] &&
          echoEntry.result == .option (.option .field) &&
          getView.result == .option (.option .field) && getView.mode == .view)
        "Option Option Field entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "NestedOptionFieldSurface must retain echo and get"
  match nestedFieldSurface.functions with
  | #[identFn] =>
      expect (identFn.params.map (·.type) == #[.option (.option .field)] &&
          identFn.result == .option (.option .field))
        "Option Option Field fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "NestedOptionFieldSurface must retain ident"
  match ← session.selectProgram nestedOptionFieldSurfaceSource "<nested-option-field>" none with
  | .ok decoded =>
      expect (decoded == nestedFieldSurface)
        "Loader and Lean command must produce the same nested Option Field Source.Program"
      expect (decoded.sourceHash == nestedFieldSurface.sourceHash)
        "Loader and Lean command must produce the same nested Option Field sourceHash"
  | .error error => throw <| IO.userError error.render

  let nestedBytesSurface := Tests.Language.OptionDeclarationsFixture.NestedOptionBytesSurface
  expect (nestedBytesSurface.state.map (·.type) == #[.option (.option (.bytes 8))])
    "Option Option Bytes 8 state must survive Lean command elaboration"
  match nestedBytesSurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "NestedBlobEvent" &&
          eventDecl.params.map (·.type) == #[.option (.option (.bytes 8))])
        "Option Option Bytes event parameter must preserve both Option tags and Bytes length"
  | _ => throw <| IO.userError "NestedOptionBytesSurface must retain NestedBlobEvent"
  match nestedBytesSurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "NestedBlobError" &&
          errorDecl.params.map (·.type) == #[.option (.option (.bytes 8))])
        "Option Option Bytes error parameter must preserve both Option tags and Bytes length"
  | _ => throw <| IO.userError "NestedOptionBytesSurface must retain NestedBlobError"
  match nestedBytesSurface.structs with
  | #[box] =>
      expect (box.name == "NestedBlobBox" &&
          box.fields.map (·.type) ==
            #[.option (.option (.bytes 0)), .option (.option (.bytes 8)),
              .option (.option (.bytes 4096))])
        "Option Option Bytes struct fields must preserve lengths 0/8/4096"
  | _ => throw <| IO.userError "NestedOptionBytesSurface must retain one struct"
  match nestedBytesSurface.enums with
  | #[tag] =>
      expect (tag.name == "NestedBlobTag" &&
          tag.variants.map (·.payloadTypes) ==
            #[#[.option (.option (.bytes 8))], #[.option (.option (.bytes 4096))]])
        "Option Option Bytes enum payloads must preserve lengths 8/4096"
  | _ => throw <| IO.userError "NestedOptionBytesSurface must retain one enum"
  match nestedBytesSurface.consts with
  | #[seed] =>
      expect (seed.name == "NestedBlobSeed" && seed.type == .option (.option (.bytes 0)))
        "Option Option Bytes 0 const type must survive elaboration"
  | _ => throw <| IO.userError "NestedOptionBytesSurface must retain NestedBlobSeed"
  match nestedBytesSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.option (.option (.bytes 8))])
        "Option Option Bytes initializer parameter must survive elaboration"
  | none => throw <| IO.userError "NestedOptionBytesSurface must retain initializer"
  match nestedBytesSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.option (.option (.bytes 8))] &&
          echoEntry.result == .option (.option (.bytes 8)) &&
          getView.result == .option (.option (.bytes 8)) && getView.mode == .view)
        "Option Option Bytes entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "NestedOptionBytesSurface must retain echo and get"
  match nestedBytesSurface.functions with
  | #[identFn] =>
      expect (identFn.params.map (·.type) == #[.option (.option (.bytes 4096))] &&
          identFn.result == .option (.option (.bytes 4096)))
        "Option Option Bytes 4096 fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "NestedOptionBytesSurface must retain ident"
  match ← session.selectProgram nestedOptionBytesSurfaceSource "<nested-option-bytes>" none with
  | .ok decoded =>
      expect (decoded == nestedBytesSurface)
        "Loader and Lean command must produce the same nested Option Bytes Source.Program"
      expect (decoded.sourceHash == nestedBytesSurface.sourceHash)
        "Loader and Lean command must produce the same nested Option Bytes sourceHash"
  | .error error => throw <| IO.userError error.render

  let nestedArraySurface := Tests.Language.OptionDeclarationsFixture.NestedOptionArraySurface
  expect (nestedArraySurface.state.map (·.type) == #[.option (.option (.array .u64 4))])
    "Option Option Array UInt64 4 state must survive Lean command elaboration"
  match nestedArraySurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "NestedArrayEvent" &&
          eventDecl.params.map (·.type) == #[.option (.option (.array .u64 4))])
        "Option Option Array event parameter must preserve both Option tags, Array element and length"
  | _ => throw <| IO.userError "NestedOptionArraySurface must retain NestedArrayEvent"
  match nestedArraySurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "NestedArrayError" &&
          errorDecl.params.map (·.type) == #[.option (.option (.array .u64 4))])
        "Option Option Array error parameter must preserve both Option tags, Array element and length"
  | _ => throw <| IO.userError "NestedOptionArraySurface must retain NestedArrayError"
  match nestedArraySurface.structs with
  | #[box] =>
      expect (box.name == "NestedArrayBox" &&
          box.fields.map (·.type) ==
            #[.option (.option (.array .u64 0)), .option (.option (.array .u64 4)),
              .option (.option (.array .u64 4096)), .option (.option (.array .bool 0))])
        "Option Option Array struct fields must preserve UInt64 lengths 0/4/4096 and Bool 0"
  | _ => throw <| IO.userError "NestedOptionArraySurface must retain one struct"
  match nestedArraySurface.enums with
  | #[tag] =>
      expect (tag.name == "NestedArrayTag" &&
          tag.variants.map (·.payloadTypes) ==
            #[#[.option (.option (.array .u64 4))],
              #[.option (.option (.array .bool 0))],
              #[.option (.option (.array .principal 4096))]])
        "Option Option Array enum payloads must preserve element and length matrix"
  | _ => throw <| IO.userError "NestedOptionArraySurface must retain one enum"
  match nestedArraySurface.consts with
  | #[seed] =>
      expect (seed.name == "NestedArraySeed" && seed.type == .option (.option (.array .u64 0)))
        "Option Option Array UInt64 0 const type must survive elaboration"
  | _ => throw <| IO.userError "NestedOptionArraySurface must retain NestedArraySeed"
  match nestedArraySurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.option (.option (.array .u64 4))])
        "Option Option Array initializer parameter must survive elaboration"
  | none => throw <| IO.userError "NestedOptionArraySurface must retain initializer"
  match nestedArraySurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.option (.option (.array .u64 4))] &&
          echoEntry.result == .option (.option (.array .u64 4)) &&
          getView.result == .option (.option (.array .u64 4)) && getView.mode == .view)
        "Option Option Array entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "NestedOptionArraySurface must retain echo and get"
  match nestedArraySurface.functions with
  | #[identFn] =>
      expect (identFn.params.map (·.type) == #[.option (.option (.array .principal 4096))] &&
          identFn.result == .option (.option (.array .principal 4096)))
        "Option Option Array Principal 4096 fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "NestedOptionArraySurface must retain ident"
  match ← session.selectProgram nestedOptionArraySurfaceSource "<nested-option-array>" none with
  | .ok decoded =>
      expect (decoded == nestedArraySurface)
        "Loader and Lean command must produce the same nested Option Array Source.Program"
      expect (decoded.sourceHash == nestedArraySurface.sourceHash)
        "Loader and Lean command must produce the same nested Option Array sourceHash"
  | .error error => throw <| IO.userError error.render

  let optionArrayFieldSurface := Tests.Language.OptionDeclarationsFixture.OptionArrayFieldSurface
  expect (optionArrayFieldSurface.state.map (·.type) == #[.option (.array .field 4)])
    "Option Array Field bn254_fr 4 state must survive Lean command elaboration"
  match optionArrayFieldSurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "OptionArrayFieldEvent" &&
          eventDecl.params.map (·.type) == #[.option (.array .field 4)])
        "Option Array Field event parameter must preserve Option/Array/Field tags and length"
  | _ => throw <| IO.userError "OptionArrayFieldSurface must retain OptionArrayFieldEvent"
  match optionArrayFieldSurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "OptionArrayFieldError" &&
          errorDecl.params.map (·.type) == #[.option (.array .field 4)])
        "Option Array Field error parameter must preserve Option/Array/Field tags and length"
  | _ => throw <| IO.userError "OptionArrayFieldSurface must retain OptionArrayFieldError"
  match optionArrayFieldSurface.structs with
  | #[box] =>
      expect (box.name == "OptionArrayFieldBox" &&
          box.fields.map (·.type) ==
            #[.option (.array .field 0), .option (.array .field 4), .option (.array .field 4096)])
        "Option Array Field struct fields must preserve lengths 0/4/4096"
  | _ => throw <| IO.userError "OptionArrayFieldSurface must retain one struct"
  match optionArrayFieldSurface.enums with
  | #[tag] =>
      expect (tag.name == "OptionArrayFieldTag" &&
          tag.variants.map (·.payloadTypes) ==
            #[#[.option (.array .field 4)], #[.option (.array .field 4096)]])
        "Option Array Field enum payloads must preserve lengths 4/4096"
  | _ => throw <| IO.userError "OptionArrayFieldSurface must retain one enum"
  match optionArrayFieldSurface.consts with
  | #[seed] =>
      expect (seed.name == "OptionArrayFieldSeed" && seed.type == .option (.array .field 0))
        "Option Array Field 0 const type must survive elaboration"
  | _ => throw <| IO.userError "OptionArrayFieldSurface must retain OptionArrayFieldSeed"
  match optionArrayFieldSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.option (.array .field 4)])
        "Option Array Field initializer parameter must survive elaboration"
  | none => throw <| IO.userError "OptionArrayFieldSurface must retain initializer"
  match optionArrayFieldSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.option (.array .field 4)] &&
          echoEntry.result == .option (.array .field 4) &&
          getView.result == .option (.array .field 4) && getView.mode == .view)
        "Option Array Field entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "OptionArrayFieldSurface must retain echo and get"
  match optionArrayFieldSurface.functions with
  | #[identFn] =>
      expect (identFn.params.map (·.type) == #[.option (.array .field 4096)] &&
          identFn.result == .option (.array .field 4096))
        "Option Array Field 4096 fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "OptionArrayFieldSurface must retain ident"
  match ← session.selectProgram optionArrayFieldSurfaceSource "<option-array-field>" none with
  | .ok decoded =>
      expect (decoded == optionArrayFieldSurface)
        "Loader and Lean command must produce the same Option Array Field Source.Program"
      expect (decoded.sourceHash == optionArrayFieldSurface.sourceHash)
        "Loader and Lean command must produce the same Option Array Field sourceHash"
  | .error error => throw <| IO.userError error.render

  let optionArrayOptionSurface := Tests.Language.OptionDeclarationsFixture.OptionArrayOptionSurface
  expect (optionArrayOptionSurface.state.map (·.type) ==
      #[.option (.array (.option .u64) 4)])
    "Option Array Option UInt64 4 state must survive Lean command elaboration"
  match optionArrayOptionSurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "OptionArrayOptionEvent" &&
          eventDecl.params.map (·.type) == #[.option (.array (.option .u64) 4)])
        "Option Array Option event parameter must preserve Option/Array/Option tags and length"
  | _ => throw <| IO.userError "OptionArrayOptionSurface must retain OptionArrayOptionEvent"
  match optionArrayOptionSurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "OptionArrayOptionError" &&
          errorDecl.params.map (·.type) == #[.option (.array (.option .u64) 4)])
        "Option Array Option error parameter must preserve Option/Array/Option tags and length"
  | _ => throw <| IO.userError "OptionArrayOptionSurface must retain OptionArrayOptionError"
  match optionArrayOptionSurface.structs with
  | #[box] =>
      expect (box.name == "OptionArrayOptionBox" &&
          box.fields.map (·.type) ==
            #[.option (.array (.option .u64) 0), .option (.array (.option .u64) 4),
              .option (.array (.option .u64) 4096), .option (.array (.option .bool) 0)])
        "Option Array Option struct fields must preserve lengths 0/4/4096 and Bool flags"
  | _ => throw <| IO.userError "OptionArrayOptionSurface must retain one struct"
  match optionArrayOptionSurface.enums with
  | #[tag] =>
      expect (tag.name == "OptionArrayOptionTag" &&
          tag.variants.map (·.payloadTypes) ==
            #[#[.option (.array (.option .u64) 4)],
              #[.option (.array (.option .bool) 0)],
              #[.option (.array (.option .principal) 4096)]])
        "Option Array Option enum payloads must preserve element and length matrix"
  | _ => throw <| IO.userError "OptionArrayOptionSurface must retain one enum"
  match optionArrayOptionSurface.consts with
  | #[seed] =>
      expect (seed.name == "OptionArrayOptionSeed" &&
          seed.type == .option (.array (.option .u64) 0))
        "Option Array Option UInt64 0 const type must survive elaboration"
  | _ => throw <| IO.userError "OptionArrayOptionSurface must retain OptionArrayOptionSeed"
  match optionArrayOptionSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.option (.array (.option .u64) 4)])
        "Option Array Option initializer parameter must survive elaboration"
  | none => throw <| IO.userError "OptionArrayOptionSurface must retain initializer"
  match optionArrayOptionSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.option (.array (.option .u64) 4)] &&
          echoEntry.result == .option (.array (.option .u64) 4) &&
          getView.result == .option (.array (.option .u64) 4) && getView.mode == .view)
        "Option Array Option entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "OptionArrayOptionSurface must retain echo and get"
  match optionArrayOptionSurface.functions with
  | #[identFn] =>
      expect (identFn.params.map (·.type) == #[.option (.array (.option .principal) 4096)] &&
          identFn.result == .option (.array (.option .principal) 4096))
        "Option Array Option Principal 4096 fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "OptionArrayOptionSurface must retain ident"
  match ← session.selectProgram optionArrayOptionSurfaceSource "<option-array-option>" none with
  | .ok decoded =>
      expect (decoded == optionArrayOptionSurface)
        "Loader and Lean command must produce the same Option Array Option Source.Program"
      expect (decoded.sourceHash == optionArrayOptionSurface.sourceHash)
        "Loader and Lean command must produce the same Option Array Option sourceHash"
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

  let retainedArrayOptionSource :=
    negativeSource "RetainedArrayOptionElement" "Array Option Bool 4"
  match ← session.parsePrograms retainedArrayOptionSource "<retained-array-option>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) == #[.array (.option .bool) 4])
        "retained Array Option Bool 4 pin must now parse as existing array(option(bool),4)"
  | .ok programs =>
      throw <| IO.userError s!"retained Array Option Bool 4 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError s!"retained Array Option Bool 4 must parse: {error.render}"

  let retainedArrayFieldSource :=
    negativeSource "RetainedArrayFieldElement" "Array Field bn254_fr 4"
  match ← session.parsePrograms retainedArrayFieldSource "<retained-array-field>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) == #[.array .field 4])
        "retained Array Field bn254_fr 4 pin must now parse as existing array(field,4)"
  | .ok programs =>
      throw <| IO.userError s!"retained Array Field bn254_fr 4 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError s!"retained Array Field bn254_fr 4 must parse: {error.render}"

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

  let nestedFieldSource := twin (.option (.option .field))
  expect (nestedFieldSource.canonicalBytes.size == 243 &&
      nestedFieldSource.sourceHash == "09409ade24acaf6a14c98ee63d23087c04ab8da990f56a47e438ae9be66d2b73")
    s!"Option Option Field source tag16+tag16+tag2 golden is unbound: size={nestedFieldSource.canonicalBytes.size}, hash={nestedFieldSource.sourceHash}"
  expect (nestedFieldSource.sourceHash != (twin .field).sourceHash &&
      nestedFieldSource.sourceHash != (twin (.option .field)).sourceHash &&
      nestedFieldSource.sourceHash != (twin (.option (.option .u64))).sourceHash &&
      nestedFieldSource.sourceHash != (twin (.option (.option .bool))).sourceHash)
    "Option Option Field must bind both Option tags and the Field tag"
  let nestedFieldSemantic ← match Compiler.compile nestedFieldSource with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"Option Option Field semantic twin must compile: {error.render}"
  expect (nestedFieldSemantic.canonicalBytes.size == 193 &&
      nestedFieldSemantic.semanticHash ==
        "6f639e0d5025222f9c65f88ed9d56808b0ff8c8f019f0c7f885cdf2ad7332db3")
    s!"Option Option Field semantic tag16+tag16+tag2 golden is unbound: size={nestedFieldSemantic.canonicalBytes.size}, hash={nestedFieldSemantic.semanticHash}"

  let nestedBytesSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Option Bytes 0", .option (.option (.bytes 0)), 259,
      "cbbe9286f8e957275d0ac6cd418209499606d8b8c6c01531425426f019ea21ae"),
    ("Option Option Bytes 8", .option (.option (.bytes 8)), 259,
      "040cf33318c71730959487be305f69a4c128270a3c27e7d93ab1bfad8d3eb14f"),
    ("Option Option Bytes 4096", .option (.option (.bytes 4096)), 259,
      "14ab68853f03fbb38ec832333716255f3f22302402f4e591d18d24fbbe17831a")
  ]
  for (label, type, expectedSize, expectedHash) in nestedBytesSourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag16+tag16+tag17 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  expect ((twin (.option (.option (.bytes 0)))).sourceHash != (twin (.bytes 0)).sourceHash &&
      (twin (.option (.option (.bytes 0)))).sourceHash !=
        (twin (.option (.bytes 0))).sourceHash &&
      (twin (.option (.option (.bytes 0)))).sourceHash !=
        (twin (.option (.option .u64))).sourceHash &&
      (twin (.option (.option (.bytes 0)))).sourceHash !=
        (twin (.option (.option .field))).sourceHash &&
      (twin (.option (.option (.bytes 0)))).sourceHash !=
        (twin (.option (.option (.bytes 8)))).sourceHash)
    "Option Option Bytes must bind both Option tags, Bytes tag and complete length payload"

  let nestedBytesSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Option Bytes 0", .option (.option (.bytes 0)), 208,
      "7900d72d34b10dcd28c9c7bb66e7f756850e115c065783bcf7c7595879fba42c"),
    ("Option Option Bytes 8", .option (.option (.bytes 8)), 208,
      "758d60858e11526e7f920efb03c796bb50635b2c4e3f014d3928e2ae95cf0d13"),
    ("Option Option Bytes 4096", .option (.option (.bytes 4096)), 208,
      "568b065f3a8d149b189834b632d78237ecfaec50c82598ffeb2460904ce58e9f")
  ]
  for (label, type, expectedSize, expectedHash) in nestedBytesSemanticVectors do
    let sourceProgram := twin type
    let semantic ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (semantic.canonicalBytes.size == expectedSize && semantic.semanticHash == expectedHash)
      s!"{label} semantic tag16+tag16+tag17 golden is unbound: size={semantic.canonicalBytes.size}, hash={semantic.semanticHash}"

  let nestedArraySourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Option Array UInt64 0", .option (.option (.array .u64 0)), 261,
      "91e1335dc7c231c7ca6106d45a55e34fe6264cd81bf23bd96012eb4e9a0da9be"),
    ("Option Option Array UInt64 4", .option (.option (.array .u64 4)), 261,
      "646ead3a3d0849ef7d59056841b55ed904cc1e1f52903821ce49c6bddfe17437"),
    ("Option Option Array UInt64 4096", .option (.option (.array .u64 4096)), 261,
      "dbafb03f61f3dc818b18d9db0a32acc304c262c695ef029e8533ee341c786fc1"),
    ("Option Option Array Bool 0", .option (.option (.array .bool 0)), 261,
      "423f49bfb2dbe64cbf4eb5545d23b9bda194d715ca08653a175d662c64328467")
  ]
  for (label, type, expectedSize, expectedHash) in nestedArraySourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag16+tag16+tag18 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  expect ((twin (.option (.option (.array .u64 0)))).sourceHash !=
        (twin (.option (.array .u64 0))).sourceHash &&
      (twin (.option (.option (.array .u64 0)))).sourceHash !=
        (twin (.option (.option .u64))).sourceHash &&
      (twin (.option (.option (.array .u64 0)))).sourceHash !=
        (twin (.option (.option (.bytes 0)))).sourceHash &&
      (twin (.option (.option (.array .u64 0)))).sourceHash !=
        (twin (.option (.option (.array .u64 4)))).sourceHash &&
      (twin (.option (.option (.array .u64 0)))).sourceHash !=
        (twin (.option (.option (.array .bool 0)))).sourceHash)
    "Option Option Array must bind both Option tags, Array tag, element and complete length payload"

  let nestedArraySemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Option Array UInt64 0", .option (.option (.array .u64 0)), 210,
      "e618343536fd197f75752375e62e47d724f2696dd52f62cf51dd8dba50899e5c"),
    ("Option Option Array UInt64 4", .option (.option (.array .u64 4)), 210,
      "fcafc27cecf27d57a0e4614bd81bf683585294869c0b351fd44aed704e29564a"),
    ("Option Option Array UInt64 4096", .option (.option (.array .u64 4096)), 210,
      "f280603177b1e0c252778d07b9b8a7fb3e076d9461613257efea99f16ae61e34"),
    ("Option Option Array Bool 0", .option (.option (.array .bool 0)), 211,
      "1149d58e31a402b298be0a8baf5a1b6479bb14522294e7e9144c90e532273248")
  ]
  for (label, type, expectedSize, expectedHash) in nestedArraySemanticVectors do
    let sourceProgram := twin type
    let semantic ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (semantic.canonicalBytes.size == expectedSize && semantic.semanticHash == expectedHash)
      s!"{label} semantic tag16+tag16+tag18 golden is unbound: size={semantic.canonicalBytes.size}, hash={semantic.semanticHash}"

  let optionArrayFieldSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Array Field bn254_fr 0", .option (.array .field 0), 259,
      "7af10a115ef40c8d50825cee9dedf87c64252e60534712bed73de354c13330f3"),
    ("Option Array Field bn254_fr 4", .option (.array .field 4), 259,
      "42c2f85620ed390c8ace928918e798216b187b218403cce1c42bfe99363fc994"),
    ("Option Array Field bn254_fr 4096", .option (.array .field 4096), 259,
      "1924e8f96feef77088e09b7e94988d8675ff071e51877272fdf0d3d99c951eca")
  ]
  for (label, type, expectedSize, expectedHash) in optionArrayFieldSourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag16+tag18+tag2 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  expect ((twin (.option (.array .field 0))).sourceHash != (twin (.array .field 0)).sourceHash &&
      (twin (.option (.array .field 0))).sourceHash != (twin (.option .field)).sourceHash &&
      (twin (.option (.array .field 0))).sourceHash !=
        (twin (.option (.array .u64 0))).sourceHash &&
      (twin (.option (.array .field 0))).sourceHash !=
        (twin (.option (.array .field 4))).sourceHash)
    "Option Array Field must bind Option/Array/Field tags and complete length payload"

  let optionArrayFieldSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Array Field bn254_fr 0", .option (.array .field 0), 209,
      "6da88f12a83e36234a66ec519a795821fe039492a1c04163e96ba94aa596b901"),
    ("Option Array Field bn254_fr 4", .option (.array .field 4), 209,
      "9b632ec1308d232ea2084c0051df30e65fefa7427f6a30f3576005c5f56c1bf8"),
    ("Option Array Field bn254_fr 4096", .option (.array .field 4096), 209,
      "b96c7c9f44c11b05b9ee880cc183628cec68981a9a6df5fd7adc91aa1d168ca7")
  ]
  for (label, type, expectedSize, expectedHash) in optionArrayFieldSemanticVectors do
    let sourceProgram := twin type
    let semantic ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (semantic.canonicalBytes.size == expectedSize && semantic.semanticHash == expectedHash)
      s!"{label} semantic tag16+tag18+tag2 golden is unbound: size={semantic.canonicalBytes.size}, hash={semantic.semanticHash}"

  let optionArrayOptionSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Array Option UInt64 0", .option (.array (.option .u64) 0), 261,
      "a11aecf5dcea854f169a6f61ca75bc01f5c4ff640c87f561015bdf58be5070b5"),
    ("Option Array Option UInt64 4", .option (.array (.option .u64) 4), 261,
      "3bf0308d1e0d05fe7f910974dacdfb62b83648ebedcfa4317606b4a92d10b8fa"),
    ("Option Array Option UInt64 4096", .option (.array (.option .u64) 4096), 261,
      "5832f3ef92e52d6067b31ab4e8c2fbe300d75d3ff6c2f1232de91f9ff3190d32"),
    ("Option Array Option Bool 0", .option (.array (.option .bool) 0), 261,
      "ee00066b4d78be5e2e247fdab3f802967e867a7cf7aaf9bf5c9a9b7b1c1380ba"),
    ("Option Array Option Bool 4", .option (.array (.option .bool) 4), 261,
      "431354f3a6adcddfe6b4d5ee22afcb913076017c4a69722a3520ff4dba229768")
  ]
  for (label, type, expectedSize, expectedHash) in optionArrayOptionSourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag16+tag18+tag16 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  expect ((twin (.option (.array (.option .u64) 0))).sourceHash !=
        (twin (.option (.array .u64 0))).sourceHash &&
      (twin (.option (.array (.option .u64) 0))).sourceHash !=
        (twin (.option (.option .u64))).sourceHash &&
      (twin (.option (.array (.option .u64) 0))).sourceHash !=
        (twin (.array (.option .u64) 0)).sourceHash &&
      (twin (.option (.array (.option .u64) 0))).sourceHash !=
        (twin (.option (.array (.option .u64) 4))).sourceHash &&
      (twin (.option (.array (.option .u64) 0))).sourceHash !=
        (twin (.option (.array (.option .bool) 0))).sourceHash)
    "Option Array Option must bind Option/Array/Option tags, element and complete length payload"

  let optionArrayOptionSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Array Option UInt64 0", .option (.array (.option .u64) 0), 210,
      "60e047f0cfb97a38c2b811ddf2d3bd594710f733b0f01e5a11243e32a0042419"),
    ("Option Array Option UInt64 4", .option (.array (.option .u64) 4), 210,
      "ddcc48af0bd00c646fa2b8b6cd00b3ed120cc802d7e608b0da38340a148014b3"),
    ("Option Array Option UInt64 4096", .option (.array (.option .u64) 4096), 210,
      "5e2c4332a93d2e1fba8bca0e93347eb7dbd13556bd76a3f01247b26d9d400c1d"),
    ("Option Array Option Bool 0", .option (.array (.option .bool) 0), 211,
      "7a683a32e88d36413853145fa551652e382ae00d84618827c9419e26b8a77921"),
    ("Option Array Option Bool 4", .option (.array (.option .bool) 4), 211,
      "3db7f00df27c4e90dfbb1d62f43f7733f5e703284e56f95d883b22b3b3b88991")
  ]
  for (label, type, expectedSize, expectedHash) in optionArrayOptionSemanticVectors do
    let sourceProgram := twin type
    let semantic ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (semantic.canonicalBytes.size == expectedSize && semantic.semanticHash == expectedHash)
      s!"{label} semantic tag16+tag18+tag16 golden is unbound: size={semantic.canonicalBytes.size}, hash={semantic.semanticHash}"

  let optionArraySourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Array UInt64 0", .option (.array .u64 0), 259,
      "f22ada30b9fcf58e2b1f55ac7417fb13864354032f7096fe33a0aa6c4bd0fa90"),
    ("Option Array UInt64 4", .option (.array .u64 4), 259,
      "1c3ae508743fbdb68c87e06487f98689fe257546db0f547c14a2020d9dbbc3e9"),
    ("Option Array UInt64 4096", .option (.array .u64 4096), 259,
      "885e14c9ae561f9aa499d6efad47c2c196685828060f27bc334cc6adccac8ef5"),
    ("Option Array Bool 0", .option (.array .bool 0), 259,
      "28937fa712d8f151aab179b012841958899a5468970f21a71457c07c27717292")
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
    ("Option Array UInt64 0", .option (.array .u64 0), 208,
      "9b7a7f860fb116e40d5a2b25e5e80378c88de55ed2875eea239ff11b97eb22b2"),
    ("Option Array UInt64 4", .option (.array .u64 4), 208,
      "5cd5f520f435c29fce98069a3a78203c2bf73e2ddf092b10391c035db76aff9d"),
    ("Option Array UInt64 4096", .option (.array .u64 4096), 208,
      "e8b1fc098d8b41d85e55a8f5bd53a570fd0f34388831e34c116e6b98e734422b"),
    ("Option Array Bool 0", .option (.array .bool 0), 209,
      "0594d1fc0e604b30c0bc2da344c6cdfda004437c0bd1bf539ce92c890de3bc7b")
  ]
  for (label, type, expectedSize, expectedHash) in optionArraySemanticVectors do
    let sourceProgram := twin type
    let semantic ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (semantic.canonicalBytes.size == expectedSize && semantic.semanticHash == expectedHash)
      s!"{label} semantic tag16+tag18 golden is unbound: size={semantic.canonicalBytes.size}, hash={semantic.semanticHash}"

  let optionBytesSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Bytes 0", .option (.bytes 0), 257,
      "17902c1fe40da65b620a8005a595f957e23101cc186597c338f1d1de66cf8d57"),
    ("Option Bytes 8", .option (.bytes 8), 257,
      "fdeaa16c4e891ffac8179e9b3f83086f51b03765ad9029100c02114247166754"),
    ("Option Bytes 32", .option (.bytes 32), 257,
      "4634c603c403cba66d1243193c835f5d6ee8827f66a59696526dd6cdb1df8334"),
    ("Option Bytes 4096", .option (.bytes 4096), 257,
      "5aeb3692b33316440837c2ca69f68a6b1ff53b529044f170bf1f0bbe3272bc35")
  ]
  for (label, type, expectedSize, expectedHash) in optionBytesSourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag16+tag17 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  expect ((twin (.option (.bytes 0))).sourceHash != (twin (.bytes 0)).sourceHash &&
      (twin (.option (.bytes 0))).sourceHash != (twin (.option .u64)).sourceHash &&
      (twin (.option (.bytes 0))).sourceHash !=
        (twin (.option (.array .u64 0))).sourceHash &&
      (twin (.option (.bytes 0))).sourceHash != (twin (.option (.bytes 8))).sourceHash)
    "Option Bytes must bind Option/Bytes tags and complete length payload"

  let optionBytesSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Bytes 0", .option (.bytes 0), 206,
      "8bf703f9490bb378ff816a62de7ba406dae03b5f18d48697f85e9ddd48b556e5"),
    ("Option Bytes 8", .option (.bytes 8), 206,
      "8225233436aad7fedd34dacdb0d0e0e758973c7281340a390ab1bc9400459885"),
    ("Option Bytes 32", .option (.bytes 32), 206,
      "60aabc823097c35ca6fbc67bc507f30346f363ddc137e086f78eb11296196543"),
    ("Option Bytes 4096", .option (.bytes 4096), 206,
      "9a809c983cfe801d2954cad3aa581d2ccd02c70b2cf3829894d071455e652e95")
  ]
  for (label, type, expectedSize, expectedHash) in optionBytesSemanticVectors do
    let sourceProgram := twin type
    let semantic ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (semantic.canonicalBytes.size == expectedSize && semantic.semanticHash == expectedHash)
      s!"{label} semantic tag16+tag17 golden is unbound: size={semantic.canonicalBytes.size}, hash={semantic.semanticHash}"

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
      ("alternate nested Field identifier", "AlternateNestedOptionFieldId",
        "Option Option Field bls12_381_fr"),
      ("escaped nested Field identifier", "EscapedNestedOptionFieldId",
        "Option Option Field «bn254_fr»"),
      ("qualified nested Field identifier", "QualifiedNestedOptionFieldId",
        "Option Option Field Curves.bn254_fr"),
      ("escaped nested element", "EscapedNestedOptionElement", "Option Option «Bool»"),
      ("qualified nested element", "QualifiedNestedOptionElement", "Option Option Std.Bool"),
      ("full Map nested option", "FullMapNestedOption", "Option Option Map UInt64 Bool"),
      ("missing Option Array element", "MissingOptionArrayElement", "Option Array"),
      ("unknown Option Array element", "UnknownOptionArrayElement", "Option Array Mystery 4"),
      ("Field Option Array element", "FieldOptionArrayElement", "Option Array Field 4"),
      ("alternate Option Array Field id", "AlternateOptionArrayFieldId",
        "Option Array Field bls12_381_fr 4"),
      ("escaped Option Array Field id", "EscapedOptionArrayFieldId",
        "Option Array Field «bn254_fr» 4"),
      ("qualified Option Array Field id", "QualifiedOptionArrayFieldId",
        "Option Array Field Curves.bn254_fr 4"),
      ("over-bound Option Array Field length", "OverBoundOptionArrayField",
        "Option Array Field bn254_fr 4097"),
      ("leading-zero Option Array Field length", "LeadingZeroOptionArrayField",
        "Option Array Field bn254_fr 01"),
      ("hex Option Array Field length", "HexOptionArrayField", "Option Array Field bn254_fr 0x10"),
      ("underscore Option Array Field length", "UnderscoreOptionArrayField",
        "Option Array Field bn254_fr 4_096"),
      ("escaped Option Array element", "EscapedOptionArrayElement", "Option Array «UInt64» 4"),
      ("qualified Option Array element", "QualifiedOptionArrayElement", "Option Array Std.UInt64 4"),
      ("over-bound Option Array length", "OverBoundOptionArray", "Option Array UInt64 4097"),
      ("leading-zero Option Array length", "LeadingZeroOptionArray", "Option Array UInt64 01"),
      ("hex Option Array length", "HexOptionArray", "Option Array UInt64 0x10"),
      ("underscore Option Array length", "UnderscoreOptionArray", "Option Array UInt64 4_096"),
      ("unknown Option Array Option element", "UnknownOptionArrayOptionElement",
        "Option Array Option Mystery 4"),
      ("Field Option Array Option element", "FieldOptionArrayOptionElement",
        "Option Array Option Field 4"),
      ("over-bound Option Array Option length", "OverBoundOptionArrayOption",
        "Option Array Option Bool 4097"),
      ("leading-zero Option Array Option length", "LeadingZeroOptionArrayOption",
        "Option Array Option Bool 01"),
      ("hex Option Array Option length", "HexOptionArrayOption",
        "Option Array Option Bool 0x10"),
      ("underscore Option Array Option length", "UnderscoreOptionArrayOption",
        "Option Array Option Bool 4_096"),
      ("missing Option Bytes length", "MissingOptionBytesLength", "Option Bytes"),
      ("over-bound Option Bytes length", "OverBoundOptionBytes", "Option Bytes 4097"),
      ("leading-zero Option Bytes length", "LeadingZeroOptionBytes", "Option Bytes 01"),
      ("hex Option Bytes length", "HexOptionBytes", "Option Bytes 0x10"),
      ("underscore Option Bytes length", "UnderscoreOptionBytes", "Option Bytes 4_096"),
      ("missing nested Bytes length", "MissingNestedOptionBytesLength", "Option Option Bytes"),
      ("over-bound nested Bytes length", "OverBoundNestedOptionBytes", "Option Option Bytes 4097"),
      ("leading-zero nested Bytes length", "LeadingZeroNestedOptionBytes", "Option Option Bytes 01"),
      ("hex nested Bytes length", "HexNestedOptionBytes", "Option Option Bytes 0x10"),
      ("underscore nested Bytes length", "UnderscoreNestedOptionBytes", "Option Option Bytes 4_096"),
      ("missing nested Array element", "MissingNestedOptionArrayElement", "Option Option Array"),
      ("unknown nested Array element", "UnknownNestedOptionArrayElement", "Option Option Array Mystery 4"),
      ("Field nested Array element", "FieldNestedOptionArrayElement", "Option Option Array Field 4"),
      ("over-bound nested Array length", "OverBoundNestedOptionArray", "Option Option Array UInt64 4097"),
      ("leading-zero nested Array length", "LeadingZeroNestedOptionArray", "Option Option Array UInt64 01"),
      ("hex nested Array length", "HexNestedOptionArray", "Option Option Array UInt64 0x10"),
      ("underscore nested Array length", "UnderscoreNestedOptionArray", "Option Option Array UInt64 4_096"),
      ("Map option element", "MapOptionElement", "Option Map UInt64 Bool")
    ] do
    expectUnsupportedType label
      (← session.parsePrograms (negativeSource name spelling) s!"<option-{label}>")

  let migratedNestedBytesSource :=
    negativeSource "MigratedNestedOptionBytes" "Option Option Bytes 8"
  match ← session.parsePrograms migratedNestedBytesSource "<migrated-nested-option-bytes>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) == #[.option (.option (.bytes 8))])
        "migrated Option Option Bytes 8 pin must now parse as existing option(option(bytes(8)))"
  | .ok programs =>
      throw <| IO.userError s!"migrated Option Option Bytes 8 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError s!"migrated Option Option Bytes 8 must parse: {error.render}"

  let migratedNestedArraySource :=
    negativeSource "MigratedNestedOptionArray" "Option Option Array UInt64 4"
  match ← session.parsePrograms migratedNestedArraySource "<migrated-nested-option-array>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) == #[.option (.option (.array .u64 4))])
        "migrated Option Option Array UInt64 4 pin must now parse as existing option(option(array(u64,4)))"
  | .ok programs =>
      throw <| IO.userError s!"migrated Option Option Array UInt64 4 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError s!"migrated Option Option Array UInt64 4 must parse: {error.render}"

  let migratedOptionArrayFieldSource :=
    negativeSource "MigratedOptionArrayField" "Option Array Field bn254_fr 4"
  match ← session.parsePrograms migratedOptionArrayFieldSource "<migrated-option-array-field>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) == #[.option (.array .field 4)])
        "migrated Option Array Field bn254_fr 4 pin must now parse as existing option(array(field,4))"
  | .ok programs =>
      throw <| IO.userError s!"migrated Option Array Field bn254_fr 4 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError s!"migrated Option Array Field bn254_fr 4 must parse: {error.render}"

  let migratedOptionArrayOptionSource :=
    negativeSource "MigratedOptionArrayOption" "Option Array Option Bool 4"
  match ← session.parsePrograms migratedOptionArrayOptionSource "<migrated-option-array-option>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) == #[.option (.array (.option .bool) 4)])
        "migrated Option Array Option Bool 4 pin must now parse as existing option(array(option(bool),4))"
  | .ok programs =>
      throw <| IO.userError s!"migrated Option Array Option Bool 4 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError s!"migrated Option Array Option Bool 4 must parse: {error.render}"

  for (label, spelling) in [
      ("third nested option", "Option Option Option Bool"),
      ("extra nested option payload", "Option Option UInt64 Principal"),
      ("split nested option", "Option Option\n  UInt64"),
      ("escaped inner Option constructor", "Option «Option» Bool"),
      ("escaped outer Option constructor", "«Option» Option Bool"),
      ("qualified outer Option constructor", "Std.Option Option Bool"),
      ("missing Option Array length", "Option Array UInt64"),
      ("negative Option Array length", "Option Array UInt64 -1"),
      ("extra Option Array payload", "Option Array UInt64 4 Principal"),
      ("nested Bytes Option Array element", "Option Array Bytes 8 4"),
      ("nested Array Option Array element", "Option Array Array UInt64 4 4"),
      ("Map Option Array element", "Option Array Map UInt64 Bool 4"),
      ("split Option Array element", "Option Array\n  UInt64 4"),
      ("split Option Array length", "Option Array UInt64\n  4"),
      ("escaped Array constructor in Option", "Option «Array» UInt64 4"),
      ("qualified Array constructor in Option", "Option Std.Array UInt64 4"),
      ("escaped Option Array constructor", "«Option» Array UInt64 4"),
      ("qualified Option Array constructor", "Std.Option Array UInt64 4"),
      ("missing Option Array Option element", "Option Array Option"),
      ("missing Option Array Option length", "Option Array Option Bool"),
      ("negative Option Array Option length", "Option Array Option Bool -1"),
      ("extra Option Array Option payload", "Option Array Option Bool 4 Principal"),
      ("split Option Array Option element", "Option Array Option\n  Bool 4"),
      ("split Option Array Option length", "Option Array Option Bool\n  4"),
      ("escaped Option in Option Array Option", "Option Array «Option» Bool 4"),
      ("qualified Option in Option Array Option", "Option Array Std.Option Bool 4"),
      ("escaped Array in Option Array Option", "Option «Array» Option Bool 4"),
      ("qualified Array in Option Array Option", "Option Std.Array Option Bool 4"),
      ("escaped outer Option Array Option", "«Option» Array Option Bool 4"),
      ("qualified outer Option Array Option", "Std.Option Array Option Bool 4"),
      ("missing Option Array Field length", "Option Array Field bn254_fr"),
      ("negative Option Array Field length", "Option Array Field bn254_fr -1"),
      ("extra Option Array Field payload", "Option Array Field bn254_fr 4 UInt64"),
      ("split Option Array Field id", "Option Array Field\n  bn254_fr 4"),
      ("split Option Array Field length", "Option Array Field bn254_fr\n  4"),
      ("escaped Field constructor in Option Array", "Option Array «Field» bn254_fr 4"),
      ("qualified Field constructor in Option Array", "Option Array Std.Field bn254_fr 4"),
      ("escaped Array constructor in Option Array Field", "Option «Array» Field bn254_fr 4"),
      ("qualified Array constructor in Option Array Field", "Option Std.Array Field bn254_fr 4"),
      ("escaped Option Array Field constructor", "«Option» Array Field bn254_fr 4"),
      ("qualified Option Array Field constructor", "Std.Option Array Field bn254_fr 4"),
      ("negative Option Bytes length", "Option Bytes -1"),
      ("identifier Option Bytes length", "Option Bytes Foo"),
      ("extra Option Bytes payload", "Option Bytes 8 UInt64"),
      ("split Option Bytes length", "Option Bytes\n  8"),
      ("escaped Bytes constructor in Option", "Option «Bytes» 8"),
      ("qualified Bytes constructor in Option", "Option Std.Bytes 8"),
      ("escaped Option Bytes constructor", "«Option» Bytes 8"),
      ("qualified Option Bytes constructor", "Std.Option Bytes 8"),
      ("negative nested Bytes length", "Option Option Bytes -1"),
      ("identifier nested Bytes length", "Option Option Bytes Foo"),
      ("extra nested Bytes payload", "Option Option Bytes 8 UInt64"),
      ("split nested Bytes length", "Option Option Bytes\n  8"),
      ("escaped Bytes constructor in nested Option", "Option Option «Bytes» 8"),
      ("qualified Bytes constructor in nested Option", "Option Option Std.Bytes 8"),
      ("escaped outer Option nested Bytes", "«Option» Option Bytes 8"),
      ("qualified outer Option nested Bytes", "Std.Option Option Bytes 8"),
      ("escaped middle Option nested Bytes", "Option «Option» Bytes 8"),
      ("negative nested Array length", "Option Option Array UInt64 -1"),
      ("missing nested Array length", "Option Option Array UInt64"),
      ("extra nested Array payload", "Option Option Array UInt64 4 Principal"),
      ("full Field nested Array element", "Option Option Array Field bn254_fr 4"),
      ("nested Option nested Array element", "Option Option Array Option Bool 4"),
      ("nested Bytes nested Array element", "Option Option Array Bytes 8 4"),
      ("nested Array nested Array element", "Option Option Array Array UInt64 4 4"),
      ("Map nested Array element", "Option Option Array Map UInt64 Bool 4"),
      ("split nested Array element", "Option Option Array\n  UInt64 4"),
      ("split nested Array length", "Option Option Array UInt64\n  4"),
      ("escaped Array constructor in nested Option", "Option Option «Array» UInt64 4"),
      ("qualified Array constructor in nested Option", "Option Option Std.Array UInt64 4"),
      ("escaped outer Option nested Array", "«Option» Option Array UInt64 4"),
      ("qualified outer Option nested Array", "Std.Option Option Array UInt64 4"),
      ("escaped middle Option nested Array", "Option «Option» Array UInt64 4"),
      ("extra option payload", "Option UInt64 Principal"),
      ("extra Field option payload", "Option Field bn254_fr UInt64"),
      ("split Field option", "Option Field\n  bn254_fr"),
      ("escaped Field constructor", "Option «Field» bn254_fr"),
      ("qualified Option constructor", "Std.Option Field bn254_fr")
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

  let nestedFieldBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.NestedOptionFieldBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"NestedOptionFieldBoundary must compile: {error.render}"
  expect (nestedFieldBoundary.requirements == #[.fieldBn254])
    "Option Option Field must recursively propagate fieldBn254 exactly once"
  for target in Targets.phase1 do
    match Targets.checkSupport target nestedFieldBoundary with
    | .error (.unsupportedRequirement .fieldBn254 actual) =>
        expect (actual == target)
          s!"Option Option Field support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError s!"Option Option Field/{target} reached wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError s!"Option Option Field/{target} unexpectedly passed support"

  let optionBytesBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.OptionBytesBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"OptionBytesBoundary must compile: {error.render}"
  expect (optionBytesBoundary.requirements == #[])
    "Option Bytes must recursively propagate zero requirements"
  for target in Targets.phase1 do
    match Targets.checkSupport target optionBytesBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError s!"{target} must support zero-requirement Option Bytes carrier: {error.render}"

  let nestedBytesBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.NestedOptionBytesBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"NestedOptionBytesBoundary must compile: {error.render}"
  expect (nestedBytesBoundary.requirements == #[])
    "Option Option Bytes must recursively propagate zero requirements"
  for target in Targets.phase1 do
    match Targets.checkSupport target nestedBytesBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError
          s!"{target} must support zero-requirement Option Option Bytes carrier: {error.render}"

  let nestedArrayBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.NestedOptionArrayBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"NestedOptionArrayBoundary must compile: {error.render}"
  expect (nestedArrayBoundary.requirements == #[])
    "Option Option Array UInt64 must recursively propagate zero requirements"
  for target in Targets.phase1 do
    match Targets.checkSupport target nestedArrayBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError
          s!"{target} must support zero-requirement Option Option Array UInt64 carrier: {error.render}"

  let nestedArrayBoolBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.NestedOptionArrayBoolBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"NestedOptionArrayBoolBoundary must compile: {error.render}"
  expect (nestedArrayBoolBoundary.requirements == #[.boolValues])
    "Option Option Array Bool must recursively propagate boolValues exactly once"
  for target in Targets.phase1 do
    match Targets.checkSupport target nestedArrayBoolBoundary with
    | .error (.unsupportedRequirement .boolValues actual) =>
        expect (actual == target)
          s!"Option Option Array Bool support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError
          s!"Option Option Array Bool/{target} reached wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError
          s!"Option Option Array Bool/{target} unexpectedly passed support"

  let optionArrayFieldBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.OptionArrayFieldBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"OptionArrayFieldBoundary must compile: {error.render}"
  expect (optionArrayFieldBoundary.requirements == #[.fieldBn254])
    "Option Array Field must recursively propagate fieldBn254 exactly once"
  for target in Targets.phase1 do
    match Targets.checkSupport target optionArrayFieldBoundary with
    | .error (.unsupportedRequirement .fieldBn254 actual) =>
        expect (actual == target)
          s!"Option Array Field support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError
          s!"Option Array Field/{target} reached wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError
          s!"Option Array Field/{target} unexpectedly passed support"

  let optionArrayOptionBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.OptionArrayOptionBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"OptionArrayOptionBoundary must compile: {error.render}"
  expect (optionArrayOptionBoundary.requirements == #[])
    "Option Array Option UInt64 must recursively propagate zero requirements"
  for target in Targets.phase1 do
    match Targets.checkSupport target optionArrayOptionBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError
          s!"{target} must support zero-requirement Option Array Option UInt64 carrier: {error.render}"

  let optionArrayOptionBoolBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.OptionArrayOptionBoolBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"OptionArrayOptionBoolBoundary must compile: {error.render}"
  expect (optionArrayOptionBoolBoundary.requirements == #[.boolValues])
    "Option Array Option Bool must recursively propagate boolValues exactly once"
  for target in Targets.phase1 do
    match Targets.checkSupport target optionArrayOptionBoolBoundary with
    | .error (.unsupportedRequirement .boolValues actual) =>
        expect (actual == target)
          s!"Option Array Option Bool support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError
          s!"Option Array Option Bool/{target} reached wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError
          s!"Option Array Option Bool/{target} unexpectedly passed support"

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
        "is not UInt64"),
      ("OptionBytesStateBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionBytesStateBoundary,
        "is not UInt64"),
      ("OptionBytesResultBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionBytesResultBoundary,
        "does not return UInt64"),
      ("OptionBytesParamBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionBytesParamBoundary,
        "is not UInt64"),
      ("NestedOptionBytesStateBoundary",
        Tests.Language.OptionDeclarationsFixture.NestedOptionBytesStateBoundary,
        "is not UInt64"),
      ("NestedOptionBytesResultBoundary",
        Tests.Language.OptionDeclarationsFixture.NestedOptionBytesResultBoundary,
        "does not return UInt64"),
      ("NestedOptionBytesParamBoundary",
        Tests.Language.OptionDeclarationsFixture.NestedOptionBytesParamBoundary,
        "is not UInt64"),
      ("NestedOptionArrayStateBoundary",
        Tests.Language.OptionDeclarationsFixture.NestedOptionArrayStateBoundary,
        "is not UInt64"),
      ("NestedOptionArrayResultBoundary",
        Tests.Language.OptionDeclarationsFixture.NestedOptionArrayResultBoundary,
        "does not return UInt64"),
      ("NestedOptionArrayParamBoundary",
        Tests.Language.OptionDeclarationsFixture.NestedOptionArrayParamBoundary,
        "is not UInt64"),
      ("OptionArrayOptionStateBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionArrayOptionStateBoundary,
        "is not UInt64"),
      ("OptionArrayOptionResultBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionArrayOptionResultBoundary,
        "does not return UInt64"),
      ("OptionArrayOptionParamBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionArrayOptionParamBoundary,
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
