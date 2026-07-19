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

program NestedOptionArrayFieldSurface where
  state nestedScalars : Option Option Array Field bn254_fr 4

  event NestedOptionArrayFieldEvent(payload : Option Option Array Field bn254_fr 4)
  error NestedOptionArrayFieldError(payload : Option Option Array Field bn254_fr 4)

  struct NestedOptionArrayFieldBox where
    empty : Option Option Array Field bn254_fr 0
    ordinary : Option Option Array Field bn254_fr 4
    maximum : Option Option Array Field bn254_fr 4096

  enum NestedOptionArrayFieldTag where
    | MaybeNestedScalars(Option Option Array Field bn254_fr 4)
    | MaybeNestedMaximum(Option Option Array Field bn254_fr 4096)

  const NestedOptionArrayFieldSeed : Option Option Array Field bn254_fr 0 := 0

  init(initial : Option Option Array Field bn254_fr 4) do
    nestedScalars := initial

  entry echo(value : Option Option Array Field bn254_fr 4) : Option Option Array Field bn254_fr 4 do
    return value

  view get() : Option Option Array Field bn254_fr 4 do
    return nestedScalars

  fn ident(value : Option Option Array Field bn254_fr 4096) : Option Option Array Field bn254_fr 4096 do
    return value

program NestedOptionArrayFieldBoundary where
  entry echo(value : Option Option Array Field bn254_fr 4) : Option Option Array Field bn254_fr 4 do
    return value

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


program OptionArrayBytesSurface where
  state maybeBlobs : Option Array Bytes 8 4

  event OptionArrayBytesEvent(payload : Option Array Bytes 8 4)
  error OptionArrayBytesError(payload : Option Array Bytes 8 4)

  struct OptionArrayBytesBox where
    empty : Option Array Bytes 0 0
    ordinary : Option Array Bytes 8 4
    maximum : Option Array Bytes 4096 1

  enum OptionArrayBytesTag where
    | MaybeBlobs(Option Array Bytes 8 4)
    | MaybeMaximum(Option Array Bytes 4096 1)

  const OptionArrayBytesSeed : Option Array Bytes 0 0 := 0

  init(initial : Option Array Bytes 8 4) do
    maybeBlobs := initial

  entry echo(value : Option Array Bytes 8 4) : Option Array Bytes 8 4 do
    return value

  view get() : Option Array Bytes 8 4 do
    return maybeBlobs

  fn ident(value : Option Array Bytes 4096 1) : Option Array Bytes 4096 1 do
    return value

program OptionArrayBytesBoundary where
  entry echo(value : Option Array Bytes 8 4) : Option Array Bytes 8 4 do
    return value

program OptionArrayBytesStateBoundary where
  state value : Option Array Bytes 8 4

  init(initial : Option Array Bytes 8 4) do
    value := initial

  view get() : Option Array Bytes 8 4 do
    return value

program OptionArrayBytesResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Array Bytes 8 4) : Option Array Bytes 8 4 do
    return value

program OptionArrayBytesParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Array Bytes 8 4) : UInt64 do
    return 0


program OptionArrayArraySurface where
  state maybeMatrix : Option Array Array UInt64 4 4

  event OptionArrayArrayEvent(payload : Option Array Array UInt64 4 4)
  error OptionArrayArrayError(payload : Option Array Array UInt64 4 4)

  struct OptionArrayArrayBox where
    empty : Option Array Array UInt64 0 0
    ordinary : Option Array Array UInt64 4 4
    maximum : Option Array Array UInt64 4096 1
    flags : Option Array Array Bool 0 0

  enum OptionArrayArrayTag where
    | MaybeMatrices(Option Array Array UInt64 4 4)
    | MaybeFlags(Option Array Array Bool 0 0)
    | MaybeOwners(Option Array Array Principal 4096 1)

  const OptionArrayArraySeed : Option Array Array UInt64 0 0 := 0

  init(initial : Option Array Array UInt64 4 4) do
    maybeMatrix := initial

  entry echo(value : Option Array Array UInt64 4 4) : Option Array Array UInt64 4 4 do
    return value

  view get() : Option Array Array UInt64 4 4 do
    return maybeMatrix

  fn ident(value : Option Array Array Principal 4096 1) : Option Array Array Principal 4096 1 do
    return value

program OptionArrayArrayBoundary where
  entry echo(value : Option Array Array UInt64 4 4) : Option Array Array UInt64 4 4 do
    return value

program OptionArrayArrayBoolBoundary where
  entry echo(value : Option Array Array Bool 0 0) : Option Array Array Bool 0 0 do
    return value

program OptionArrayArrayStateBoundary where
  state value : Option Array Array UInt64 4 4

  init(initial : Option Array Array UInt64 4 4) do
    value := initial

  view get() : Option Array Array UInt64 4 4 do
    return value

program OptionArrayArrayResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Array Array UInt64 4 4) : Option Array Array UInt64 4 4 do
    return value

program OptionArrayArrayParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Array Array UInt64 4 4) : UInt64 do
    return 0


program TripleOptionSurface where
  state tripleCount : Option Option Option UInt64

  event TripleOptionEvent(payload : Option Option Option UInt64)
  error TripleOptionError(payload : Option Option Option UInt64)

  struct TripleOptionBox where
    counts : Option Option Option UInt64
    flags : Option Option Option Bool
    owners : Option Option Option Principal

  enum TripleOptionTag where
    | MaybeTripleCount(Option Option Option UInt64)
    | MaybeTripleFlag(Option Option Option Bool)
    | MaybeTripleOwner(Option Option Option Principal)

  const TripleOptionSeed : Option Option Option UInt64 := 0

  init(initial : Option Option Option UInt64) do
    tripleCount := initial

  entry echo(value : Option Option Option UInt64) : Option Option Option UInt64 do
    return value

  view get() : Option Option Option UInt64 do
    return tripleCount

  fn ident(value : Option Option Option Principal) : Option Option Option Principal do
    return value

program TripleOptionBoundary where
  entry echo(value : Option Option Option UInt64) : Option Option Option UInt64 do
    return value

program TripleOptionBoolBoundary where
  entry echo(value : Option Option Option Bool) : Option Option Option Bool do
    return value

program TripleOptionStateBoundary where
  state value : Option Option Option UInt64

  init(initial : Option Option Option UInt64) do
    value := initial

  view get() : Option Option Option UInt64 do
    return value

program TripleOptionResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Option Option UInt64) : Option Option Option UInt64 do
    return value

program TripleOptionParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Option Option UInt64) : UInt64 do
    return 0

program TripleOptionFieldSurface where
  state tripleScalar : Option Option Option Field bn254_fr

  event TripleOptionFieldEvent(payload : Option Option Option Field bn254_fr)
  error TripleOptionFieldError(payload : Option Option Option Field bn254_fr)

  struct TripleOptionFieldBox where
    value : Option Option Option Field bn254_fr

  enum TripleOptionFieldTag where
    | MaybeTripleScalar(Option Option Option Field bn254_fr)

  const TripleOptionFieldSeed : Option Option Option Field bn254_fr := 0

  init(initial : Option Option Option Field bn254_fr) do
    tripleScalar := initial

  entry echo(value : Option Option Option Field bn254_fr) : Option Option Option Field bn254_fr do
    return value

  view get() : Option Option Option Field bn254_fr do
    return tripleScalar

  fn ident(value : Option Option Option Field bn254_fr) : Option Option Option Field bn254_fr do
    return value

program TripleOptionFieldBoundary where
  entry echo(value : Option Option Option Field bn254_fr) : Option Option Option Field bn254_fr do
    return value

program TripleOptionBytesSurface where
  state tripleBlob : Option Option Option Bytes 8

  event TripleOptionBytesEvent(payload : Option Option Option Bytes 8)
  error TripleOptionBytesError(payload : Option Option Option Bytes 8)

  struct TripleOptionBytesBox where
    empty : Option Option Option Bytes 0
    ordinary : Option Option Option Bytes 8
    maximum : Option Option Option Bytes 4096

  enum TripleOptionBytesTag where
    | MaybeTripleBlob(Option Option Option Bytes 8)
    | MaybeTripleMax(Option Option Option Bytes 4096)

  const TripleOptionBytesSeed : Option Option Option Bytes 0 := 0

  init(initial : Option Option Option Bytes 8) do
    tripleBlob := initial

  entry echo(value : Option Option Option Bytes 8) : Option Option Option Bytes 8 do
    return value

  view get() : Option Option Option Bytes 8 do
    return tripleBlob

  fn ident(value : Option Option Option Bytes 4096) : Option Option Option Bytes 4096 do
    return value

program TripleOptionBytesBoundary where
  entry echo(value : Option Option Option Bytes 8) : Option Option Option Bytes 8 do
    return value

program TripleOptionBytesStateBoundary where
  state value : Option Option Option Bytes 8

  init(initial : Option Option Option Bytes 8) do
    value := initial

  view get() : Option Option Option Bytes 8 do
    return value

program TripleOptionBytesResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Option Option Bytes 8) : Option Option Option Bytes 8 do
    return value

program TripleOptionBytesParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Option Option Option Bytes 8) : UInt64 do
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

private def tripleOptionFieldSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.OptionDeclarationsFixture\n\n" ++
  "program TripleOptionFieldSurface where\n" ++
  "  state tripleScalar : Option Option Option Field bn254_fr\n\n" ++
  "  event TripleOptionFieldEvent(payload : Option Option Option Field bn254_fr)\n" ++
  "  error TripleOptionFieldError(payload : Option Option Option Field bn254_fr)\n\n" ++
  "  struct TripleOptionFieldBox where\n" ++
  "    value : Option Option Option Field bn254_fr\n\n" ++
  "  enum TripleOptionFieldTag where\n" ++
  "    | MaybeTripleScalar(Option Option Option Field bn254_fr)\n\n" ++
  "  const TripleOptionFieldSeed : Option Option Option Field bn254_fr := 0\n\n" ++
  "  init(initial : Option Option Option Field bn254_fr) do\n" ++
  "    tripleScalar := initial\n\n" ++
  "  entry echo(value : Option Option Option Field bn254_fr) : Option Option Option Field bn254_fr do\n" ++
  "    return value\n\n" ++
  "  view get() : Option Option Option Field bn254_fr do\n" ++
  "    return tripleScalar\n\n" ++
  "  fn ident(value : Option Option Option Field bn254_fr) : Option Option Option Field bn254_fr do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.OptionDeclarationsFixture\n"

private def tripleOptionBytesSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.OptionDeclarationsFixture\n\n" ++
  "program TripleOptionBytesSurface where\n" ++
  "  state tripleBlob : Option Option Option Bytes 8\n\n" ++
  "  event TripleOptionBytesEvent(payload : Option Option Option Bytes 8)\n" ++
  "  error TripleOptionBytesError(payload : Option Option Option Bytes 8)\n\n" ++
  "  struct TripleOptionBytesBox where\n" ++
  "    empty : Option Option Option Bytes 0\n" ++
  "    ordinary : Option Option Option Bytes 8\n" ++
  "    maximum : Option Option Option Bytes 4096\n\n" ++
  "  enum TripleOptionBytesTag where\n" ++
  "    | MaybeTripleBlob(Option Option Option Bytes 8)\n" ++
  "    | MaybeTripleMax(Option Option Option Bytes 4096)\n\n" ++
  "  const TripleOptionBytesSeed : Option Option Option Bytes 0 := 0\n\n" ++
  "  init(initial : Option Option Option Bytes 8) do\n" ++
  "    tripleBlob := initial\n\n" ++
  "  entry echo(value : Option Option Option Bytes 8) : Option Option Option Bytes 8 do\n" ++
  "    return value\n\n" ++
  "  view get() : Option Option Option Bytes 8 do\n" ++
  "    return tripleBlob\n\n" ++
  "  fn ident(value : Option Option Option Bytes 4096) : Option Option Option Bytes 4096 do\n" ++
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

private def nestedOptionArrayFieldSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.OptionDeclarationsFixture\n\n" ++
  "program NestedOptionArrayFieldSurface where\n" ++
  "  state nestedScalars : Option Option Array Field bn254_fr 4\n\n" ++
  "  event NestedOptionArrayFieldEvent(payload : Option Option Array Field bn254_fr 4)\n" ++
  "  error NestedOptionArrayFieldError(payload : Option Option Array Field bn254_fr 4)\n\n" ++
  "  struct NestedOptionArrayFieldBox where\n" ++
  "    empty : Option Option Array Field bn254_fr 0\n" ++
  "    ordinary : Option Option Array Field bn254_fr 4\n" ++
  "    maximum : Option Option Array Field bn254_fr 4096\n\n" ++
  "  enum NestedOptionArrayFieldTag where\n" ++
  "    | MaybeNestedScalars(Option Option Array Field bn254_fr 4)\n" ++
  "    | MaybeNestedMaximum(Option Option Array Field bn254_fr 4096)\n\n" ++
  "  const NestedOptionArrayFieldSeed : Option Option Array Field bn254_fr 0 := 0\n\n" ++
  "  init(initial : Option Option Array Field bn254_fr 4) do\n" ++
  "    nestedScalars := initial\n\n" ++
  "  entry echo(value : Option Option Array Field bn254_fr 4) : Option Option Array Field bn254_fr 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Option Option Array Field bn254_fr 4 do\n" ++
  "    return nestedScalars\n\n" ++
  "  fn ident(value : Option Option Array Field bn254_fr 4096) : Option Option Array Field bn254_fr 4096 do\n" ++
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


private def optionArrayBytesSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.OptionDeclarationsFixture\n\n" ++
  "program OptionArrayBytesSurface where\n" ++
  "  state maybeBlobs : Option Array Bytes 8 4\n\n" ++
  "  event OptionArrayBytesEvent(payload : Option Array Bytes 8 4)\n" ++
  "  error OptionArrayBytesError(payload : Option Array Bytes 8 4)\n\n" ++
  "  struct OptionArrayBytesBox where\n" ++
  "    empty : Option Array Bytes 0 0\n" ++
  "    ordinary : Option Array Bytes 8 4\n" ++
  "    maximum : Option Array Bytes 4096 1\n\n" ++
  "  enum OptionArrayBytesTag where\n" ++
  "    | MaybeBlobs(Option Array Bytes 8 4)\n" ++
  "    | MaybeMaximum(Option Array Bytes 4096 1)\n\n" ++
  "  const OptionArrayBytesSeed : Option Array Bytes 0 0 := 0\n\n" ++
  "  init(initial : Option Array Bytes 8 4) do\n" ++
  "    maybeBlobs := initial\n\n" ++
  "  entry echo(value : Option Array Bytes 8 4) : Option Array Bytes 8 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Option Array Bytes 8 4 do\n" ++
  "    return maybeBlobs\n\n" ++
  "  fn ident(value : Option Array Bytes 4096 1) : Option Array Bytes 4096 1 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.OptionDeclarationsFixture\n"


private def optionArrayArraySurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.OptionDeclarationsFixture\n\n" ++
  "program OptionArrayArraySurface where\n" ++
  "  state maybeMatrix : Option Array Array UInt64 4 4\n\n" ++
  "  event OptionArrayArrayEvent(payload : Option Array Array UInt64 4 4)\n" ++
  "  error OptionArrayArrayError(payload : Option Array Array UInt64 4 4)\n\n" ++
  "  struct OptionArrayArrayBox where\n" ++
  "    empty : Option Array Array UInt64 0 0\n" ++
  "    ordinary : Option Array Array UInt64 4 4\n" ++
  "    maximum : Option Array Array UInt64 4096 1\n" ++
  "    flags : Option Array Array Bool 0 0\n\n" ++
  "  enum OptionArrayArrayTag where\n" ++
  "    | MaybeMatrices(Option Array Array UInt64 4 4)\n" ++
  "    | MaybeFlags(Option Array Array Bool 0 0)\n" ++
  "    | MaybeOwners(Option Array Array Principal 4096 1)\n\n" ++
  "  const OptionArrayArraySeed : Option Array Array UInt64 0 0 := 0\n\n" ++
  "  init(initial : Option Array Array UInt64 4 4) do\n" ++
  "    maybeMatrix := initial\n\n" ++
  "  entry echo(value : Option Array Array UInt64 4 4) : Option Array Array UInt64 4 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Option Array Array UInt64 4 4 do\n" ++
  "    return maybeMatrix\n\n" ++
  "  fn ident(value : Option Array Array Principal 4096 1) : Option Array Array Principal 4096 1 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.OptionDeclarationsFixture\n"

private def tripleOptionSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.OptionDeclarationsFixture\n\n" ++
  "program TripleOptionSurface where\n" ++
  "  state tripleCount : Option Option Option UInt64\n\n" ++
  "  event TripleOptionEvent(payload : Option Option Option UInt64)\n" ++
  "  error TripleOptionError(payload : Option Option Option UInt64)\n\n" ++
  "  struct TripleOptionBox where\n" ++
  "    counts : Option Option Option UInt64\n" ++
  "    flags : Option Option Option Bool\n" ++
  "    owners : Option Option Option Principal\n\n" ++
  "  enum TripleOptionTag where\n" ++
  "    | MaybeTripleCount(Option Option Option UInt64)\n" ++
  "    | MaybeTripleFlag(Option Option Option Bool)\n" ++
  "    | MaybeTripleOwner(Option Option Option Principal)\n\n" ++
  "  const TripleOptionSeed : Option Option Option UInt64 := 0\n\n" ++
  "  init(initial : Option Option Option UInt64) do\n" ++
  "    tripleCount := initial\n\n" ++
  "  entry echo(value : Option Option Option UInt64) : Option Option Option UInt64 do\n" ++
  "    return value\n\n" ++
  "  view get() : Option Option Option UInt64 do\n" ++
  "    return tripleCount\n\n" ++
  "  fn ident(value : Option Option Option Principal) : Option Option Option Principal do\n" ++
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

  let nestedOptionArrayFieldSurface :=
    Tests.Language.OptionDeclarationsFixture.NestedOptionArrayFieldSurface
  expect (nestedOptionArrayFieldSurface.state.map (·.type) ==
      #[.option (.option (.array .field 4))])
    "Option Option Array Field bn254_fr 4 state must survive Lean command elaboration"
  match nestedOptionArrayFieldSurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "NestedOptionArrayFieldEvent" &&
          eventDecl.params.map (·.type) == #[.option (.option (.array .field 4))])
        "Option Option Array Field event must preserve Option/Option/Array/Field tags and length"
  | _ => throw <| IO.userError "NestedOptionArrayFieldSurface must retain NestedOptionArrayFieldEvent"
  match nestedOptionArrayFieldSurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "NestedOptionArrayFieldError" &&
          errorDecl.params.map (·.type) == #[.option (.option (.array .field 4))])
        "Option Option Array Field error must preserve Option/Option/Array/Field tags and length"
  | _ => throw <| IO.userError "NestedOptionArrayFieldSurface must retain NestedOptionArrayFieldError"
  match nestedOptionArrayFieldSurface.structs with
  | #[box] =>
      expect (box.name == "NestedOptionArrayFieldBox" &&
          box.fields.map (·.type) ==
            #[.option (.option (.array .field 0)),
              .option (.option (.array .field 4)),
              .option (.option (.array .field 4096))])
        "Option Option Array Field struct fields must preserve lengths 0/4/4096"
  | _ => throw <| IO.userError "NestedOptionArrayFieldSurface must retain one struct"
  match nestedOptionArrayFieldSurface.enums with
  | #[tag] =>
      expect (tag.name == "NestedOptionArrayFieldTag" &&
          tag.variants.map (·.payloadTypes) ==
            #[#[.option (.option (.array .field 4))],
              #[.option (.option (.array .field 4096))]])
        "Option Option Array Field enum payloads must preserve lengths 4/4096"
  | _ => throw <| IO.userError "NestedOptionArrayFieldSurface must retain one enum"
  match nestedOptionArrayFieldSurface.consts with
  | #[seed] =>
      expect (seed.name == "NestedOptionArrayFieldSeed" &&
          seed.type == .option (.option (.array .field 0)))
        "Option Option Array Field const type must survive elaboration"
  | _ => throw <| IO.userError "NestedOptionArrayFieldSurface must retain NestedOptionArrayFieldSeed"
  match nestedOptionArrayFieldSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.option (.option (.array .field 4))])
        "Option Option Array Field initializer parameter must survive elaboration"
  | none => throw <| IO.userError "NestedOptionArrayFieldSurface must retain initializer"
  match nestedOptionArrayFieldSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.option (.option (.array .field 4))] &&
          echoEntry.result == .option (.option (.array .field 4)) &&
          getView.result == .option (.option (.array .field 4)) && getView.mode == .view)
        "Option Option Array Field entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "NestedOptionArrayFieldSurface must retain echo and get"
  match nestedOptionArrayFieldSurface.functions with
  | #[identFn] =>
      expect (identFn.params.map (·.type) == #[.option (.option (.array .field 4096))] &&
          identFn.result == .option (.option (.array .field 4096)))
        "Option Option Array Field fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "NestedOptionArrayFieldSurface must retain ident"
  match ← session.selectProgram nestedOptionArrayFieldSurfaceSource
      "<nested-option-array-field>" none with
  | .ok decoded =>
      expect (decoded == nestedOptionArrayFieldSurface)
        "Loader and Lean command must produce the same nested Option Array Field Source.Program"
      expect (decoded.sourceHash == nestedOptionArrayFieldSurface.sourceHash)
        "Loader and Lean command must produce the same nested Option Array Field sourceHash"
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


  let optionArrayBytesSurface := Tests.Language.OptionDeclarationsFixture.OptionArrayBytesSurface
  expect (optionArrayBytesSurface.state.map (·.type) ==
      #[.option (.array (.bytes 8) 4)])
    "Option Array Bytes 8 4 state must survive Lean command elaboration"
  match optionArrayBytesSurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "OptionArrayBytesEvent" &&
          eventDecl.params.map (·.type) == #[.option (.array (.bytes 8) 4)])
        "Option Array Bytes event parameter must preserve Option/Array/Bytes tags and dual lengths"
  | _ => throw <| IO.userError "OptionArrayBytesSurface must retain OptionArrayBytesEvent"
  match optionArrayBytesSurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "OptionArrayBytesError" &&
          errorDecl.params.map (·.type) == #[.option (.array (.bytes 8) 4)])
        "Option Array Bytes error parameter must preserve Option/Array/Bytes tags and dual lengths"
  | _ => throw <| IO.userError "OptionArrayBytesSurface must retain OptionArrayBytesError"
  match optionArrayBytesSurface.structs with
  | #[box] =>
      expect (box.name == "OptionArrayBytesBox" &&
          box.fields.map (·.type) ==
            #[.option (.array (.bytes 0) 0), .option (.array (.bytes 8) 4),
              .option (.array (.bytes 4096) 1)])
        "Option Array Bytes struct fields must preserve dual lengths 0/0, 8/4, 4096/1"
  | _ => throw <| IO.userError "OptionArrayBytesSurface must retain one struct"
  match optionArrayBytesSurface.enums with
  | #[tag] =>
      expect (tag.name == "OptionArrayBytesTag" &&
          tag.variants.map (·.payloadTypes) ==
            #[#[.option (.array (.bytes 8) 4)],
              #[.option (.array (.bytes 4096) 1)]])
        "Option Array Bytes enum payloads must preserve dual length matrix"
  | _ => throw <| IO.userError "OptionArrayBytesSurface must retain one enum"
  match optionArrayBytesSurface.consts with
  | #[seed] =>
      expect (seed.name == "OptionArrayBytesSeed" &&
          seed.type == .option (.array (.bytes 0) 0))
        "Option Array Bytes 0 0 const type must survive elaboration"
  | _ => throw <| IO.userError "OptionArrayBytesSurface must retain OptionArrayBytesSeed"
  match optionArrayBytesSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.option (.array (.bytes 8) 4)])
        "Option Array Bytes initializer parameter must survive elaboration"
  | none => throw <| IO.userError "OptionArrayBytesSurface must retain initializer"
  match optionArrayBytesSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.option (.array (.bytes 8) 4)] &&
          echoEntry.result == .option (.array (.bytes 8) 4) &&
          getView.result == .option (.array (.bytes 8) 4) && getView.mode == .view)
        "Option Array Bytes entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "OptionArrayBytesSurface must retain echo and get"
  match optionArrayBytesSurface.functions with
  | #[identFn] =>
      expect (identFn.params.map (·.type) == #[.option (.array (.bytes 4096) 1)] &&
          identFn.result == .option (.array (.bytes 4096) 1))
        "Option Array Bytes 4096 1 fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "OptionArrayBytesSurface must retain ident"
  match ← session.selectProgram optionArrayBytesSurfaceSource "<option-array-bytes>" none with
  | .ok decoded =>
      expect (decoded == optionArrayBytesSurface)
        "Loader and Lean command must produce the same Option Array Bytes Source.Program"
      expect (decoded.sourceHash == optionArrayBytesSurface.sourceHash)
        "Loader and Lean command must produce the same Option Array Bytes sourceHash"
  | .error error => throw <| IO.userError error.render


  let optionArrayArraySurface := Tests.Language.OptionDeclarationsFixture.OptionArrayArraySurface
  expect (optionArrayArraySurface.state.map (·.type) ==
      #[.option (.array (.array .u64 4) 4)])
    "Option Array Array UInt64 4 4 state must survive Lean command elaboration"
  match optionArrayArraySurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "OptionArrayArrayEvent" &&
          eventDecl.params.map (·.type) == #[.option (.array (.array .u64 4) 4)])
        "Option Array Array event parameter must preserve Option/Array/Array tags and dual lengths"
  | _ => throw <| IO.userError "OptionArrayArraySurface must retain OptionArrayArrayEvent"
  match optionArrayArraySurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "OptionArrayArrayError" &&
          errorDecl.params.map (·.type) == #[.option (.array (.array .u64 4) 4)])
        "Option Array Array error parameter must preserve Option/Array/Array tags and dual lengths"
  | _ => throw <| IO.userError "OptionArrayArraySurface must retain OptionArrayArrayError"
  match optionArrayArraySurface.structs with
  | #[box] =>
      expect (box.name == "OptionArrayArrayBox" &&
          box.fields.map (·.type) ==
            #[.option (.array (.array .u64 0) 0), .option (.array (.array .u64 4) 4),
              .option (.array (.array .u64 4096) 1), .option (.array (.array .bool 0) 0)])
        "Option Array Array struct fields must preserve dual lengths and Bool flags"
  | _ => throw <| IO.userError "OptionArrayArraySurface must retain one struct"
  match optionArrayArraySurface.enums with
  | #[tag] =>
      expect (tag.name == "OptionArrayArrayTag" &&
          tag.variants.map (·.payloadTypes) ==
            #[#[.option (.array (.array .u64 4) 4)],
              #[.option (.array (.array .bool 0) 0)],
              #[.option (.array (.array .principal 4096) 1)]])
        "Option Array Array enum payloads must preserve element and dual length matrix"
  | _ => throw <| IO.userError "OptionArrayArraySurface must retain one enum"
  match optionArrayArraySurface.consts with
  | #[seed] =>
      expect (seed.name == "OptionArrayArraySeed" &&
          seed.type == .option (.array (.array .u64 0) 0))
        "Option Array Array UInt64 0 0 const type must survive elaboration"
  | _ => throw <| IO.userError "OptionArrayArraySurface must retain OptionArrayArraySeed"
  match optionArrayArraySurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.option (.array (.array .u64 4) 4)])
        "Option Array Array initializer parameter must survive elaboration"
  | none => throw <| IO.userError "OptionArrayArraySurface must retain initializer"
  match optionArrayArraySurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.option (.array (.array .u64 4) 4)] &&
          echoEntry.result == .option (.array (.array .u64 4) 4) &&
          getView.result == .option (.array (.array .u64 4) 4) && getView.mode == .view)
        "Option Array Array entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "OptionArrayArraySurface must retain echo and get"
  match optionArrayArraySurface.functions with
  | #[identFn] =>
      expect (identFn.params.map (·.type) == #[.option (.array (.array .principal 4096) 1)] &&
          identFn.result == .option (.array (.array .principal 4096) 1))
        "Option Array Array Principal 4096 1 fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "OptionArrayArraySurface must retain ident"
  match ← session.selectProgram optionArrayArraySurfaceSource "<option-array-array>" none with
  | .ok decoded =>
      expect (decoded == optionArrayArraySurface)
        "Loader and Lean command must produce the same Option Array Array Source.Program"
      expect (decoded.sourceHash == optionArrayArraySurface.sourceHash)
        "Loader and Lean command must produce the same Option Array Array sourceHash"
  | .error error => throw <| IO.userError error.render

  let tripleOptionSurface := Tests.Language.OptionDeclarationsFixture.TripleOptionSurface
  expect (tripleOptionSurface.state.map (·.type) ==
      #[.option (.option (.option .u64))])
    "Option Option Option UInt64 state must survive Lean command elaboration"
  match tripleOptionSurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "TripleOptionEvent" &&
          eventDecl.params.map (·.type) == #[.option (.option (.option .u64))])
        "Option Option Option event parameter must preserve three Option tags and UInt64 element"
  | _ => throw <| IO.userError "TripleOptionSurface must retain TripleOptionEvent"
  match tripleOptionSurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "TripleOptionError" &&
          errorDecl.params.map (·.type) == #[.option (.option (.option .u64))])
        "Option Option Option error parameter must preserve three Option tags and UInt64 element"
  | _ => throw <| IO.userError "TripleOptionSurface must retain TripleOptionError"
  match tripleOptionSurface.structs with
  | #[box] =>
      expect (box.name == "TripleOptionBox" &&
          box.fields.map (·.type) ==
            #[.option (.option (.option .u64)), .option (.option (.option .bool)),
              .option (.option (.option .principal))])
        "Option Option Option struct fields must preserve UInt64/Bool/Principal elements"
  | _ => throw <| IO.userError "TripleOptionSurface must retain one struct"
  match tripleOptionSurface.enums with
  | #[tag] =>
      expect (tag.name == "TripleOptionTag" &&
          tag.variants.map (·.payloadTypes) ==
            #[#[.option (.option (.option .u64))],
              #[.option (.option (.option .bool))],
              #[.option (.option (.option .principal))]])
        "Option Option Option enum payloads must preserve UInt64/Bool/Principal matrix"
  | _ => throw <| IO.userError "TripleOptionSurface must retain one enum"
  match tripleOptionSurface.consts with
  | #[seed] =>
      expect (seed.name == "TripleOptionSeed" &&
          seed.type == .option (.option (.option .u64)))
        "Option Option Option UInt64 const type must survive elaboration"
  | _ => throw <| IO.userError "TripleOptionSurface must retain TripleOptionSeed"
  match tripleOptionSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.option (.option (.option .u64))])
        "Option Option Option initializer parameter must survive elaboration"
  | none => throw <| IO.userError "TripleOptionSurface must retain initializer"
  match tripleOptionSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.option (.option (.option .u64))] &&
          echoEntry.result == .option (.option (.option .u64)) &&
          getView.result == .option (.option (.option .u64)) && getView.mode == .view)
        "Option Option Option entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "TripleOptionSurface must retain echo and get"
  match tripleOptionSurface.functions with
  | #[identFn] =>
      expect (identFn.params.map (·.type) == #[.option (.option (.option .principal))] &&
          identFn.result == .option (.option (.option .principal)))
        "Option Option Option Principal fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "TripleOptionSurface must retain ident"
  match ← session.selectProgram tripleOptionSurfaceSource "<triple-option>" none with
  | .ok decoded =>
      expect (decoded == tripleOptionSurface)
        "Loader and Lean command must produce the same Option Option Option Source.Program"
      expect (decoded.sourceHash == tripleOptionSurface.sourceHash)
        "Loader and Lean command must produce the same Option Option Option sourceHash"
  | .error error => throw <| IO.userError error.render

  let tripleOptionFieldSurface :=
    Tests.Language.OptionDeclarationsFixture.TripleOptionFieldSurface
  expect (tripleOptionFieldSurface.state.map (·.type) ==
      #[.option (.option (.option .field))])
    "Option Option Option Field bn254_fr state must survive Lean command elaboration"
  match tripleOptionFieldSurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "TripleOptionFieldEvent" &&
          eventDecl.params.map (·.type) == #[.option (.option (.option .field))])
        "Option Option Option Field event parameter must preserve three Option tags and Field"
  | _ => throw <| IO.userError "TripleOptionFieldSurface must retain TripleOptionFieldEvent"
  match tripleOptionFieldSurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "TripleOptionFieldError" &&
          errorDecl.params.map (·.type) == #[.option (.option (.option .field))])
        "Option Option Option Field error parameter must preserve three Option tags and Field"
  | _ => throw <| IO.userError "TripleOptionFieldSurface must retain TripleOptionFieldError"
  match tripleOptionFieldSurface.structs with
  | #[box] =>
      expect (box.name == "TripleOptionFieldBox" &&
          box.fields.map (·.type) == #[.option (.option (.option .field))])
        "Option Option Option Field struct field must preserve three Option tags and Field"
  | _ => throw <| IO.userError "TripleOptionFieldSurface must retain one struct"
  match tripleOptionFieldSurface.enums with
  | #[tag] =>
      expect (tag.name == "TripleOptionFieldTag" &&
          tag.variants.map (·.payloadTypes) ==
            #[#[.option (.option (.option .field))]])
        "Option Option Option Field enum payload must preserve three Option tags and Field"
  | _ => throw <| IO.userError "TripleOptionFieldSurface must retain one enum"
  match tripleOptionFieldSurface.consts with
  | #[seed] =>
      expect (seed.name == "TripleOptionFieldSeed" &&
          seed.type == .option (.option (.option .field)))
        "Option Option Option Field const type must survive elaboration"
  | _ => throw <| IO.userError "TripleOptionFieldSurface must retain TripleOptionFieldSeed"
  match tripleOptionFieldSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.option (.option (.option .field))])
        "Option Option Option Field initializer parameter must survive elaboration"
  | none => throw <| IO.userError "TripleOptionFieldSurface must retain initializer"
  match tripleOptionFieldSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.option (.option (.option .field))] &&
          echoEntry.result == .option (.option (.option .field)) &&
          getView.result == .option (.option (.option .field)) && getView.mode == .view)
        "Option Option Option Field entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "TripleOptionFieldSurface must retain echo and get"
  match tripleOptionFieldSurface.functions with
  | #[identFn] =>
      expect (identFn.params.map (·.type) == #[.option (.option (.option .field))] &&
          identFn.result == .option (.option (.option .field)))
        "Option Option Option Field fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "TripleOptionFieldSurface must retain ident"
  match ← session.selectProgram tripleOptionFieldSurfaceSource
      "<triple-option-field>" none with
  | .ok decoded =>
      expect (decoded == tripleOptionFieldSurface)
        "Loader and Lean command must produce the same triple Option Field Source.Program"
      expect (decoded.sourceHash == tripleOptionFieldSurface.sourceHash)
        "Loader and Lean command must produce the same triple Option Field sourceHash"
  | .error error => throw <| IO.userError error.render

  let tripleOptionBytesSurface :=
    Tests.Language.OptionDeclarationsFixture.TripleOptionBytesSurface
  expect (tripleOptionBytesSurface.state.map (·.type) ==
      #[.option (.option (.option (.bytes 8)))])
    "Option Option Option Bytes 8 state must survive Lean command elaboration"
  match tripleOptionBytesSurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "TripleOptionBytesEvent" &&
          eventDecl.params.map (·.type) == #[.option (.option (.option (.bytes 8)))])
        "Option Option Option Bytes event parameter must preserve three Option tags and Bytes length"
  | _ => throw <| IO.userError "TripleOptionBytesSurface must retain TripleOptionBytesEvent"
  match tripleOptionBytesSurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "TripleOptionBytesError" &&
          errorDecl.params.map (·.type) == #[.option (.option (.option (.bytes 8)))])
        "Option Option Option Bytes error parameter must preserve three Option tags and Bytes length"
  | _ => throw <| IO.userError "TripleOptionBytesSurface must retain TripleOptionBytesError"
  match tripleOptionBytesSurface.structs with
  | #[box] =>
      expect (box.name == "TripleOptionBytesBox" &&
          box.fields.map (·.type) ==
            #[.option (.option (.option (.bytes 0))),
              .option (.option (.option (.bytes 8))),
              .option (.option (.option (.bytes 4096)))])
        "Option Option Option Bytes struct fields must preserve lengths 0/8/4096"
  | _ => throw <| IO.userError "TripleOptionBytesSurface must retain one struct"
  match tripleOptionBytesSurface.enums with
  | #[tag] =>
      expect (tag.name == "TripleOptionBytesTag" &&
          tag.variants.map (·.payloadTypes) ==
            #[#[.option (.option (.option (.bytes 8)))],
              #[.option (.option (.option (.bytes 4096)))]])
        "Option Option Option Bytes enum payloads must preserve lengths 8/4096"
  | _ => throw <| IO.userError "TripleOptionBytesSurface must retain one enum"
  match tripleOptionBytesSurface.consts with
  | #[seed] =>
      expect (seed.name == "TripleOptionBytesSeed" &&
          seed.type == .option (.option (.option (.bytes 0))))
        "Option Option Option Bytes const type must survive elaboration"
  | _ => throw <| IO.userError "TripleOptionBytesSurface must retain TripleOptionBytesSeed"
  match tripleOptionBytesSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.option (.option (.option (.bytes 8)))])
        "Option Option Option Bytes initializer parameter must survive elaboration"
  | none => throw <| IO.userError "TripleOptionBytesSurface must retain initializer"
  match tripleOptionBytesSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.option (.option (.option (.bytes 8)))] &&
          echoEntry.result == .option (.option (.option (.bytes 8))) &&
          getView.result == .option (.option (.option (.bytes 8))) && getView.mode == .view)
        "Option Option Option Bytes entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "TripleOptionBytesSurface must retain echo and get"
  match tripleOptionBytesSurface.functions with
  | #[identFn] =>
      expect (identFn.params.map (·.type) == #[.option (.option (.option (.bytes 4096)))] &&
          identFn.result == .option (.option (.option (.bytes 4096))))
        "Option Option Option Bytes fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "TripleOptionBytesSurface must retain ident"
  match ← session.selectProgram tripleOptionBytesSurfaceSource
      "<triple-option-bytes>" none with
  | .ok decoded =>
      expect (decoded == tripleOptionBytesSurface)
        "Loader and Lean command must produce the same triple Option Bytes Source.Program"
      expect (decoded.sourceHash == tripleOptionBytesSurface.sourceHash)
        "Loader and Lean command must produce the same triple Option Bytes sourceHash"
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

  let tripleFieldType : Source.ValueType := .option (.option (.option .field))
  let tripleFieldSource := twin tripleFieldType
  expect (tripleFieldSource.canonicalBytes.size == 245 &&
      tripleFieldSource.sourceHash ==
        "85c34b3dd740b76b06ee4061b32105c0067e6c53da11bb44e1c89139331eeb87")
    s!"Option Option Option Field source tag16+tag16+tag16+tag2 golden is unbound: size={tripleFieldSource.canonicalBytes.size}, hash={tripleFieldSource.sourceHash}"
  let tripleFieldSourceCanon (type : Source.ValueType) : ByteArray × String :=
    ((twin type).canonicalBytes, (twin type).sourceHash)
  let tripleFieldSourceDistinct (other : Source.ValueType) (message : String) : IO Unit := do
    let left := tripleFieldSourceCanon tripleFieldType
    let right := tripleFieldSourceCanon other
    expect (left.1 != right.1 && left.2 != right.2) message
  tripleFieldSourceDistinct .field
    "Option Option Option Field Source must non-alias bare Field (bytes+hash)"
  tripleFieldSourceDistinct (.option .field)
    "Option Option Option Field Source must non-alias Option Field (bytes+hash)"
  tripleFieldSourceDistinct (.option (.option .field))
    "Option Option Option Field Source must non-alias Option Option Field (bytes+hash)"
  tripleFieldSourceDistinct (.option (.option (.option .u64)))
    "Option Option Option Field Source must non-alias triple Option UInt64 (bytes+hash)"
  tripleFieldSourceDistinct (.option (.option (.option .bool)))
    "Option Option Option Field Source must non-alias triple Option Bool (bytes+hash)"
  let tripleFieldSemantic ← match Compiler.compile tripleFieldSource with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError
          s!"Option Option Option Field semantic twin must compile: {error.render}"
  expect (tripleFieldSemantic.canonicalBytes.size == 195 &&
      tripleFieldSemantic.semanticHash ==
        "f3e03abd85c77362313c72f789d3bb36c40ee9e4fed6aeff80eba8b31695f223")
    s!"Option Option Option Field semantic tag16+tag16+tag16+tag2 golden is unbound: size={tripleFieldSemantic.canonicalBytes.size}, hash={tripleFieldSemantic.semanticHash}"
  let tripleFieldSemanticCanon (type : Source.ValueType) : IO (ByteArray × String) := do
    match Compiler.compile (twin type) with
    | .ok value => pure (value.canonicalBytes, value.semanticHash)
    | .error error =>
        throw <| IO.userError
          s!"triple Option Field semantic non-alias twin must compile: {error.render}"
  let tripleFieldSemanticDistinct (other : Source.ValueType) (message : String) : IO Unit := do
    let left ← tripleFieldSemanticCanon tripleFieldType
    let right ← tripleFieldSemanticCanon other
    expect (left.1 != right.1 && left.2 != right.2) message
  tripleFieldSemanticDistinct .field
    "Option Option Option Field Semantic must non-alias bare Field (bytes+hash)"
  tripleFieldSemanticDistinct (.option .field)
    "Option Option Option Field Semantic must non-alias Option Field (bytes+hash)"
  tripleFieldSemanticDistinct (.option (.option .field))
    "Option Option Option Field Semantic must non-alias Option Option Field (bytes+hash)"
  tripleFieldSemanticDistinct (.option (.option (.option .u64)))
    "Option Option Option Field Semantic must non-alias triple Option UInt64 (bytes+hash)"
  tripleFieldSemanticDistinct (.option (.option (.option .bool)))
    "Option Option Option Field Semantic must non-alias triple Option Bool (bytes+hash)"

  let tripleBytesSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Option Option Bytes 0", .option (.option (.option (.bytes 0))), 261,
      "1d72684412b3f2105d651777f624ca116739787c9cd8ce344fedaddfa0bfdc85"),
    ("Option Option Option Bytes 8", .option (.option (.option (.bytes 8))), 261,
      "efb75c6ef16e8c71b8cefd07085406c0060441ba1ea0dd8d52e5a7df0108bf99"),
    ("Option Option Option Bytes 4096", .option (.option (.option (.bytes 4096))), 261,
      "9d1e4ee905f7b5f70ea9ddbd57c8aee77e3b4c6d24533113a4c6023805ac095d")
  ]
  for (label, type, expectedSize, expectedHash) in tripleBytesSourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag16+tag16+tag16+tag17 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  let tripleBytesSourceCanon (type : Source.ValueType) : ByteArray × String :=
    ((twin type).canonicalBytes, (twin type).sourceHash)
  let tripleBytesSourceDistinct (left right : Source.ValueType) (message : String) : IO Unit := do
    let leftPair := tripleBytesSourceCanon left
    let rightPair := tripleBytesSourceCanon right
    expect (leftPair.1 != rightPair.1 && leftPair.2 != rightPair.2) message
  let tob0 : Source.ValueType := .option (.option (.option (.bytes 0)))
  let tob8 : Source.ValueType := .option (.option (.option (.bytes 8)))
  let tobMax : Source.ValueType := .option (.option (.option (.bytes 4096)))
  tripleBytesSourceDistinct tob0 tob8
    "Option Option Option Bytes 0 vs 8 Source must non-alias (bytes+hash)"
  tripleBytesSourceDistinct tob8 tobMax
    "Option Option Option Bytes 8 vs 4096 Source must non-alias (bytes+hash)"
  tripleBytesSourceDistinct tob0 tobMax
    "Option Option Option Bytes 0 vs 4096 Source must non-alias (bytes+hash)"
  tripleBytesSourceDistinct tob8 (.bytes 8)
    "Option Option Option Bytes 8 Source must non-alias bare Bytes 8 (bytes+hash)"
  tripleBytesSourceDistinct tob8 (.option (.bytes 8))
    "Option Option Option Bytes 8 Source must non-alias Option Bytes 8 (bytes+hash)"
  tripleBytesSourceDistinct tob8 (.option (.option (.bytes 8)))
    "Option Option Option Bytes 8 Source must non-alias Option Option Bytes 8 (bytes+hash)"
  tripleBytesSourceDistinct tob8 (.option (.option (.option .u64)))
    "Option Option Option Bytes 8 Source must non-alias triple Option UInt64 (bytes+hash)"
  tripleBytesSourceDistinct tob8 (.option (.option (.option .field)))
    "Option Option Option Bytes 8 Source must non-alias triple Option Field (bytes+hash)"

  let tripleBytesSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Option Option Bytes 0", .option (.option (.option (.bytes 0))), 210,
      "b11f3d1923eb30e0b331d6653eaad1060f619142ec3776026e033a194de92292"),
    ("Option Option Option Bytes 8", .option (.option (.option (.bytes 8))), 210,
      "e140c3f196bf6125cd680df6b518475d2156d6e56473f0dd47f0bf136217e553"),
    ("Option Option Option Bytes 4096", .option (.option (.option (.bytes 4096))), 210,
      "e0f99b2cf713c93928915ac2df2cf16df2873becd9b115f75a28851114594864")
  ]
  for (label, type, expectedSize, expectedHash) in tripleBytesSemanticVectors do
    let sourceProgram := twin type
    let semantic ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (semantic.canonicalBytes.size == expectedSize && semantic.semanticHash == expectedHash)
      s!"{label} semantic tag16+tag16+tag16+tag17 golden is unbound: size={semantic.canonicalBytes.size}, hash={semantic.semanticHash}"
  let tripleBytesSemanticCanon (type : Source.ValueType) : IO (ByteArray × String) := do
    match Compiler.compile (twin type) with
    | .ok value => pure (value.canonicalBytes, value.semanticHash)
    | .error error =>
        throw <| IO.userError
          s!"triple Option Bytes semantic non-alias twin must compile: {error.render}"
  let tripleBytesSemanticDistinct (left right : Source.ValueType) (message : String) : IO Unit := do
    let leftPair ← tripleBytesSemanticCanon left
    let rightPair ← tripleBytesSemanticCanon right
    expect (leftPair.1 != rightPair.1 && leftPair.2 != rightPair.2) message
  tripleBytesSemanticDistinct tob0 tob8
    "Option Option Option Bytes 0 vs 8 Semantic must non-alias (bytes+hash)"
  tripleBytesSemanticDistinct tob8 tobMax
    "Option Option Option Bytes 8 vs 4096 Semantic must non-alias (bytes+hash)"
  tripleBytesSemanticDistinct tob0 tobMax
    "Option Option Option Bytes 0 vs 4096 Semantic must non-alias (bytes+hash)"
  tripleBytesSemanticDistinct tob8 (.bytes 8)
    "Option Option Option Bytes 8 Semantic must non-alias bare Bytes 8 (bytes+hash)"
  tripleBytesSemanticDistinct tob8 (.option (.bytes 8))
    "Option Option Option Bytes 8 Semantic must non-alias Option Bytes 8 (bytes+hash)"
  tripleBytesSemanticDistinct tob8 (.option (.option (.bytes 8)))
    "Option Option Option Bytes 8 Semantic must non-alias Option Option Bytes 8 (bytes+hash)"
  tripleBytesSemanticDistinct tob8 (.option (.option (.option .u64)))
    "Option Option Option Bytes 8 Semantic must non-alias triple Option UInt64 (bytes+hash)"
  tripleBytesSemanticDistinct tob8 (.option (.option (.option .field)))
    "Option Option Option Bytes 8 Semantic must non-alias triple Option Field (bytes+hash)"

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

  let noafSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Option Array Field bn254_fr 0", .option (.option (.array .field 0)), 261,
      "6d63aac74ce61f061de11288097f18de7f7043623ceb0ed3596cd13a938676aa"),
    ("Option Option Array Field bn254_fr 4", .option (.option (.array .field 4)), 261,
      "bef51596dc72dc5e0d39730297278d4d7839b872d16bf269f5783f471234765f"),
    ("Option Option Array Field bn254_fr 4096", .option (.option (.array .field 4096)), 261,
      "ee225041fce0de31bc20b8bb53c1d137ec05f3a7826fc2d20cba4f79b167ce98")
  ]
  for (label, type, expectedSize, expectedHash) in noafSourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag16+tag16+tag18+tag2 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  let noafSourceCanon (type : Source.ValueType) : ByteArray × String :=
    ((twin type).canonicalBytes, (twin type).sourceHash)
  let noafSourceDistinct (left right : Source.ValueType) (message : String) : IO Unit := do
    let leftPair := noafSourceCanon left
    let rightPair := noafSourceCanon right
    expect (leftPair.1 != rightPair.1 && leftPair.2 != rightPair.2) message
  let noaf0 : Source.ValueType := .option (.option (.array .field 0))
  let noaf4 : Source.ValueType := .option (.option (.array .field 4))
  let noafMax : Source.ValueType := .option (.option (.array .field 4096))
  noafSourceDistinct noaf0 noaf4
    "Option Option Array Field 0 vs 4 Source must non-alias (bytes+hash)"
  noafSourceDistinct noaf4 noafMax
    "Option Option Array Field 4 vs 4096 Source must non-alias (bytes+hash)"
  noafSourceDistinct noaf0 noafMax
    "Option Option Array Field 0 vs 4096 Source must non-alias (bytes+hash)"
  noafSourceDistinct noaf4 (.option (.array .field 4))
    "Option Option Array Field 4 Source must non-alias Option Array Field 4 (bytes+hash)"
  noafSourceDistinct noaf4 (.option (.option (.array .u64 4)))
    "Option Option Array Field 4 Source must non-alias Option Option Array UInt64 4 (bytes+hash)"
  noafSourceDistinct noaf4 (.option (.option .field))
    "Option Option Array Field 4 Source must non-alias Option Option Field bn254_fr (bytes+hash)"
  noafSourceDistinct noaf4 (.array (.option (.option .field)) 4)
    "Option Option Array Field 4 Source must non-alias Array Option Option Field 4 (bytes+hash)"

  let noafSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Option Array Field bn254_fr 0", .option (.option (.array .field 0)), 211,
      "a7ed080b84e6e5906e8a13c30e57a30a07f06a0993ba2cc6567a6a56b80f29f8"),
    ("Option Option Array Field bn254_fr 4", .option (.option (.array .field 4)), 211,
      "6151f2d68d43876455fa3f08a300c6b5f552e52178d984d2a5d4346ae6cf0ebd"),
    ("Option Option Array Field bn254_fr 4096", .option (.option (.array .field 4096)), 211,
      "a065a9cd0fa0201ffde3576f5939a31717fc9a3a2adac6ee218a42c4149ef6d5")
  ]
  for (label, type, expectedSize, expectedHash) in noafSemanticVectors do
    let sourceProgram := twin type
    let semantic ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (semantic.canonicalBytes.size == expectedSize && semantic.semanticHash == expectedHash)
      s!"{label} semantic tag16+tag16+tag18+tag2 golden is unbound: size={semantic.canonicalBytes.size}, hash={semantic.semanticHash}"
  let noafSemanticCanon (type : Source.ValueType) : IO (ByteArray × String) := do
    match Compiler.compile (twin type) with
    | .ok value => pure (value.canonicalBytes, value.semanticHash)
    | .error error =>
        throw <| IO.userError
          s!"nested Option Array Field semantic non-alias twin must compile: {error.render}"
  let noafSemanticDistinct (left right : Source.ValueType) (message : String) : IO Unit := do
    let leftPair ← noafSemanticCanon left
    let rightPair ← noafSemanticCanon right
    expect (leftPair.1 != rightPair.1 && leftPair.2 != rightPair.2) message
  noafSemanticDistinct noaf0 noaf4
    "Option Option Array Field 0 vs 4 Semantic must non-alias (bytes+hash)"
  noafSemanticDistinct noaf4 noafMax
    "Option Option Array Field 4 vs 4096 Semantic must non-alias (bytes+hash)"
  noafSemanticDistinct noaf0 noafMax
    "Option Option Array Field 0 vs 4096 Semantic must non-alias (bytes+hash)"
  noafSemanticDistinct noaf4 (.option (.array .field 4))
    "Option Option Array Field 4 Semantic must non-alias Option Array Field 4 (bytes+hash)"
  noafSemanticDistinct noaf4 (.option (.option (.array .u64 4)))
    "Option Option Array Field 4 Semantic must non-alias Option Option Array UInt64 4 (bytes+hash)"
  noafSemanticDistinct noaf4 (.option (.option .field))
    "Option Option Array Field 4 Semantic must non-alias Option Option Field bn254_fr (bytes+hash)"
  noafSemanticDistinct noaf4 (.array (.option (.option .field)) 4)
    "Option Option Array Field 4 Semantic must non-alias Array Option Option Field 4 (bytes+hash)"

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


  let optionArrayBytesSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Array Bytes 0 0", .option (.array (.bytes 0) 0), 275,
      "9a501b89cd94fbb38a0fc895447ba4398f275cb3805eb1cf67b50b6210139003"),
    ("Option Array Bytes 8 4", .option (.array (.bytes 8) 4), 275,
      "c9df46d40c57e0322a66509a8325df949d993e2aa3c23d41ef30aec968548e84"),
    ("Option Array Bytes 4096 1", .option (.array (.bytes 4096) 1), 275,
      "98cda144856a7bdbf6369e94d0e08e0c3244539295356ce271fc0afa4b6e6543")
  ]
  for (label, type, expectedSize, expectedHash) in optionArrayBytesSourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag16+tag18+tag17 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  expect ((twin (.option (.array (.bytes 0) 0))).sourceHash !=
        (twin (.option (.bytes 0))).sourceHash &&
      (twin (.option (.array (.bytes 0) 0))).sourceHash !=
        (twin (.array (.bytes 0) 0)).sourceHash &&
      (twin (.option (.array (.bytes 0) 0))).sourceHash !=
        (twin (.option (.array .u64 0))).sourceHash &&
      (twin (.option (.array (.bytes 0) 0))).sourceHash !=
        (twin (.option (.option (.bytes 0)))).sourceHash &&
      (twin (.option (.array (.bytes 0) 0))).sourceHash !=
        (twin (.option (.array (.bytes 8) 4))).sourceHash &&
      (twin (.option (.array (.bytes 8) 4))).sourceHash !=
        (twin (.option (.array (.bytes 8) 0))).sourceHash &&
      (twin (.option (.array (.bytes 8) 4))).sourceHash !=
        (twin (.option (.array (.bytes 0) 4))).sourceHash)
    "Option Array Bytes must bind Option/Array/Bytes tags and both length payloads"

  let optionArrayBytesSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Array Bytes 0 0", .option (.array (.bytes 0) 0), 224,
      "0ef2abf0962545937b0fdb21520f870aaaae56cfe0421f3db523db1ecaaa82a6"),
    ("Option Array Bytes 8 4", .option (.array (.bytes 8) 4), 224,
      "47c667ffb5935fa571e3df303bb58a27dd8cd339f23ca78d2a2195734f0e6cd4"),
    ("Option Array Bytes 4096 1", .option (.array (.bytes 4096) 1), 224,
      "3f9694b1f83c3e9714d12d80d612965a2a941ef5fc3e05e18b2e772411ec543f")
  ]
  for (label, type, expectedSize, expectedHash) in optionArrayBytesSemanticVectors do
    let sourceProgram := twin type
    let semantic ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (semantic.canonicalBytes.size == expectedSize && semantic.semanticHash == expectedHash)
      s!"{label} semantic tag16+tag18+tag17 golden is unbound: size={semantic.canonicalBytes.size}, hash={semantic.semanticHash}"


  let optionArrayArraySourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Array Array UInt64 0 0", .option (.array (.array .u64 0) 0), 277,
      "c41d358a00638c4027c477ad509c1755de8e4910bf2c19de28fafc2f9ef532d5"),
    ("Option Array Array UInt64 4 4", .option (.array (.array .u64 4) 4), 277,
      "307c217dae5a427c9b0b9db061ca84458c4803609b38cd513cdd0359b1d7e6ba"),
    ("Option Array Array UInt64 4096 1", .option (.array (.array .u64 4096) 1), 277,
      "19cfa92d3b3c1f89587c6fb8c3004e4757d1e4cce06ef436bfed37e161feb90d"),
    ("Option Array Array Bool 0 0", .option (.array (.array .bool 0) 0), 277,
      "2afcabdfbfcf953b3d373aee00ef59b1b26be0838eedba3f3827859b6f4b5c17"),
    ("Option Array Array Bool 4 4", .option (.array (.array .bool 4) 4), 277,
      "12939052290b1f381d62617de03f28d7d100038c3731c3a60799a1c6573e17d0")
  ]
  for (label, type, expectedSize, expectedHash) in optionArrayArraySourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag16+tag18+tag18 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  expect ((twin (.option (.array (.array .u64 0) 0))).sourceHash !=
        (twin (.array (.array .u64 0) 0)).sourceHash &&
      (twin (.option (.array (.array .u64 0) 0))).sourceHash !=
        (twin (.option (.array .u64 0))).sourceHash &&
      (twin (.option (.array (.array .u64 0) 0))).sourceHash !=
        (twin (.option (.option (.array .u64 0)))).sourceHash &&
      (twin (.option (.array (.array .u64 0) 0))).sourceHash !=
        (twin (.option (.array (.array .u64 4) 4))).sourceHash &&
      (twin (.option (.array (.array .u64 4) 4))).sourceHash !=
        (twin (.option (.array (.array .u64 4) 0))).sourceHash &&
      (twin (.option (.array (.array .u64 4) 4))).sourceHash !=
        (twin (.option (.array (.array .u64 0) 4))).sourceHash &&
      (twin (.option (.array (.array .u64 0) 0))).sourceHash !=
        (twin (.option (.array (.array .bool 0) 0))).sourceHash)
    "Option Array Array must bind Option/Array/Array tags, element and both length payloads"

  let optionArrayArraySemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Array Array UInt64 0 0", .option (.array (.array .u64 0) 0), 226,
      "be7ed61bb6de2afe9d4879e80d60d8b9a48d03c8a8df2fe43ee2f261617d9084"),
    ("Option Array Array UInt64 4 4", .option (.array (.array .u64 4) 4), 226,
      "ca7aa5a225dd187156543116b85b4d303a20800121a808599681cddcf8fd9cbb"),
    ("Option Array Array UInt64 4096 1", .option (.array (.array .u64 4096) 1), 226,
      "f9d4e0d7ac2f8e0f10229acac4a7746b015fb4a3d9dd0e9ee7a15216d0af1ac3"),
    ("Option Array Array Bool 0 0", .option (.array (.array .bool 0) 0), 227,
      "af837a2665647f26d58592965c307023c900a003c11d7316e6b96ed0bf3b594c"),
    ("Option Array Array Bool 4 4", .option (.array (.array .bool 4) 4), 227,
      "7a5a8d93fc72f087f0654d84c7f38f1c0f99a3e6c9d961d92fb5abdb8eb8cb27")
  ]
  for (label, type, expectedSize, expectedHash) in optionArrayArraySemanticVectors do
    let sourceProgram := twin type
    let semantic ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (semantic.canonicalBytes.size == expectedSize && semantic.semanticHash == expectedHash)
      s!"{label} semantic tag16+tag18+tag18 golden is unbound: size={semantic.canonicalBytes.size}, hash={semantic.semanticHash}"


  let tripleOptionSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Option Option UInt64", .option (.option (.option .u64)), 245,
      "aed4e6041b4f39d706f65499ce32262c7eb8bf14d0e8f04a67a80bfbe1a6b04a"),
    ("Option Option Option Bool", .option (.option (.option .bool)), 245,
      "c95fac336a5dc2f31f7b41a727e80a309aa33a107e37de85cc5bc706a5074b5c"),
    ("Option Option Option Principal", .option (.option (.option .principal)), 245,
      "8e5f195ff45d2281fa707f3f5770e8d556e11d65f3d70d8bbac11df1518b545d"),
    ("Option Option Option UInt8", .option (.option (.option .u8)), 245,
      "6ff56b4154675189da735318791d00f502d5251a920315a46efd43600ff0f223"),
    ("Option Option Option UInt16", .option (.option (.option .u16)), 245,
      "ed13aecdc2509b2137668ae08f2b141746b2f16d467f320fe726a12097f2f033"),
    ("Option Option Option UInt32", .option (.option (.option .u32)), 245,
      "e5a1b7ca2750addb8aad910b011780e5115a296ccfd7c9bc952f1644f8c3a452"),
    ("Option Option Option UInt128", .option (.option (.option .u128)), 245,
      "af79c24830ed9a0e8632112f13778490aead627756ca9523aaae043a7f6cc355"),
    ("Option Option Option UInt256", .option (.option (.option .u256)), 245,
      "7335b704c20b540e8e20db84ee7e698d29ab45c12aff91040ab69f2cdd53695c"),
    ("Option Option Option Int8", .option (.option (.option .i8)), 245,
      "17551d5323b8d6003f4102505e12c7220fd49c2046d183a85219fa83dc613239"),
    ("Option Option Option Int16", .option (.option (.option .i16)), 245,
      "c3bb30f8d33443e524400a1499896421c425246cdac17c5b78045b662ae1bb8e"),
    ("Option Option Option Int32", .option (.option (.option .i32)), 245,
      "8ee9c6d7dc1022aa752050928a3ae86f39d865cb6b16e2fdf6488962ae917808"),
    ("Option Option Option Int64", .option (.option (.option .i64)), 245,
      "bdcdb581b5edf73585ca71402ef4374c257cb7032dec56b121fbaf08e35ce8d8"),
    ("Option Option Option Int128", .option (.option (.option .i128)), 245,
      "bcf35f7c320011fbdef39543c2ebd7f93a4035d77c70a685c6073d212064d83c"),
    ("Option Option Option Int256", .option (.option (.option .i256)), 245,
      "2eff90a5f9ef15f0a3333e4a3290e98d8e2739b3f7e4543aef1d37da24109df8"),
    ("Option Option Option Unit", .option (.option (.option .unit)), 245,
      "5d57651998b5de0c8b3345c9c05a5c0b28956d79e20a5aca16204cc47afbc7bd")
  ]
  for (label, type, expectedSize, expectedHash) in tripleOptionSourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag16+tag16+tag16 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  expect ((twin (.option (.option (.option .u64)))).sourceHash !=
        (twin (.option (.option .u64))).sourceHash &&
      (twin (.option (.option (.option .u64)))).sourceHash !=
        (twin (.option .u64)).sourceHash &&
      (twin (.option (.option (.option .u64)))).sourceHash !=
        (twin (.option (.option (.option .bool)))).sourceHash &&
      (twin (.option (.option (.option .u64)))).sourceHash !=
        (twin (.option (.option (.option .principal)))).sourceHash &&
      (twin (.option (.option (.option .bool)))).sourceHash !=
        (twin (.option (.option (.option .unit)))).sourceHash)
    "Option Option Option must bind three Option tags and complete PrimitiveAtom element payload"
  expect (tripleOptionSourceVectors.size == 15)
    "Option Option Option source goldens must cover the closed 15-atom PrimitiveAtom matrix"

  let tripleOptionSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Option Option Option UInt64", .option (.option (.option .u64)), 194,
      "cce922baf7bbee4fbc7b450a228a8f4da0b8259efa69dcb3ecccd8ead1d438eb"),
    ("Option Option Option Bool", .option (.option (.option .bool)), 195,
      "2e1428169172d44f0e01ce797585eb6146753778ac32be9371415cd0b2065a3d"),
    ("Option Option Option Principal", .option (.option (.option .principal)), 194,
      "f3a95ff06890bc82e7a8517968b20bc38a7fdb378251dd87886d2f9d3f82e18a"),
    ("Option Option Option UInt8", .option (.option (.option .u8)), 194,
      "d91c6e9a02bd8cba04f7c8855bf7656b3148979f0d3593017ecabe0306eb3b06"),
    ("Option Option Option UInt16", .option (.option (.option .u16)), 194,
      "b0c1ce13566e02780130f8c1731699abb5a4020acebd04728ddb06f8822921e4"),
    ("Option Option Option UInt32", .option (.option (.option .u32)), 194,
      "713847b58cb0292ea938136c01bed90a8222746e067290e5dd024200283e3b11"),
    ("Option Option Option UInt128", .option (.option (.option .u128)), 194,
      "a8fdf105b5806e2dc2ae220bf8e0ec5e1dff8b73d76cfbcb08f122349fe2a0de"),
    ("Option Option Option UInt256", .option (.option (.option .u256)), 194,
      "1e159424e45b366c08628f9fd8876b8d0bb2db8ebb5187e824b65e7d4ff52b32"),
    ("Option Option Option Int8", .option (.option (.option .i8)), 194,
      "7f88dd9cd940a1289cfdcb15f48cd4ccb8d39984897da28a80181c7aff8e8cd2"),
    ("Option Option Option Int16", .option (.option (.option .i16)), 194,
      "29efc5149060d6528f2135242a60556abc7785831858e4317fbfd19068522201"),
    ("Option Option Option Int32", .option (.option (.option .i32)), 194,
      "5edbc695ae842f42468a93438717f64126bae65032a0278d3c2c8ce911ee1e48"),
    ("Option Option Option Int64", .option (.option (.option .i64)), 194,
      "4d433c300b28c7176bb8b1e44526a40dc719741d33496068305bf21046b25213"),
    ("Option Option Option Int128", .option (.option (.option .i128)), 194,
      "fa2bef5aaf1759e1db59400665bd61d4f011f27872d468aa52cac72be2b5e86c"),
    ("Option Option Option Int256", .option (.option (.option .i256)), 194,
      "4b681d31591b0086f6ba580a1791745a6cd280e1453b8c1300cc18fec9607983"),
    ("Option Option Option Unit", .option (.option (.option .unit)), 194,
      "eb0a697063cd458d184c1bff3fe47caa444e455a669c0e5a20b7c750b35494e9")
  ]
  for (label, type, expectedSize, expectedHash) in tripleOptionSemanticVectors do
    let sourceProgram := twin type
    let semantic ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (semantic.canonicalBytes.size == expectedSize && semantic.semanticHash == expectedHash)
      s!"{label} semantic tag16+tag16+tag16 golden is unbound: size={semantic.canonicalBytes.size}, hash={semantic.semanticHash}"
  expect (tripleOptionSemanticVectors.size == 15)
    "Option Option Option semantic goldens must cover the closed 15-atom PrimitiveAtom matrix"

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
      ("alternate nested Option Array Field id", "AlternateNestedOptionArrayFieldId",
        "Option Option Array Field bls12_381_fr 4"),
      ("escaped nested Option Array Field id", "EscapedNestedOptionArrayFieldId",
        "Option Option Array Field «bn254_fr» 4"),
      ("qualified nested Option Array Field id", "QualifiedNestedOptionArrayFieldId",
        "Option Option Array Field Curves.bn254_fr 4"),
      ("over-bound nested Option Array Field length", "OverBoundNestedOptionArrayField",
        "Option Option Array Field bn254_fr 4097"),
      ("leading-zero nested Option Array Field length", "LeadingZeroNestedOptionArrayField",
        "Option Option Array Field bn254_fr 01"),
      ("hex nested Option Array Field length", "HexNestedOptionArrayField",
        "Option Option Array Field bn254_fr 0x10"),
      ("underscore nested Option Array Field length", "UnderscoreNestedOptionArrayField",
        "Option Option Array Field bn254_fr 4_096"),
      ("bare Bytes nested Option Array Field prefix", "BareBytesNestedOptionArrayField",
        "Option Option Array Bytes 4"),
      ("bare Option nested Option Array Field prefix", "BareOptionNestedOptionArrayField",
        "Option Option Array Option 4"),
      ("bare Array nested Option Array Field prefix", "BareArrayNestedOptionArrayField",
        "Option Option Array Array 4"),
      ("bare Map nested Option Array Field prefix", "BareMapNestedOptionArrayField",
        "Option Option Array Map 4"),
      ("Widget nested Option Array Field leaf", "WidgetNestedOptionArrayField",
        "Option Option Array Widget 4"),
      ("over-bound nested Array length", "OverBoundNestedOptionArray", "Option Option Array UInt64 4097"),
      ("leading-zero nested Array length", "LeadingZeroNestedOptionArray", "Option Option Array UInt64 01"),
      ("hex nested Array length", "HexNestedOptionArray", "Option Option Array UInt64 0x10"),
      ("underscore nested Array length", "UnderscoreNestedOptionArray", "Option Option Array UInt64 4_096"),
      ("missing Option Array Bytes outer length", "MissingOptionArrayBytesOuter",
        "Option Array Bytes 8"),
      ("over-bound Option Array Bytes inner length", "OverBoundOptionArrayBytesInner",
        "Option Array Bytes 4097 4"),
      ("leading-zero Option Array Bytes inner length", "LeadingZeroOptionArrayBytesInner",
        "Option Array Bytes 01 4"),
      ("hex Option Array Bytes inner length", "HexOptionArrayBytesInner",
        "Option Array Bytes 0x10 4"),
      ("underscore Option Array Bytes inner length", "UnderscoreOptionArrayBytesInner",
        "Option Array Bytes 4_096 4"),
      ("over-bound Option Array Bytes outer length", "OverBoundOptionArrayBytesOuter",
        "Option Array Bytes 8 4097"),
      ("leading-zero Option Array Bytes outer length", "LeadingZeroOptionArrayBytesOuter",
        "Option Array Bytes 8 01"),
      ("hex Option Array Bytes outer length", "HexOptionArrayBytesOuter",
        "Option Array Bytes 8 0x10"),
      ("underscore Option Array Bytes outer length", "UnderscoreOptionArrayBytesOuter",
        "Option Array Bytes 8 4_096"),
      ("unknown Option Array Array element", "UnknownOptionArrayArrayElement",
        "Option Array Array Mystery 4 4"),
      ("over-bound Option Array Array inner length", "OverBoundOptionArrayArrayInner",
        "Option Array Array UInt64 4097 4"),
      ("leading-zero Option Array Array inner length", "LeadingZeroOptionArrayArrayInner",
        "Option Array Array UInt64 01 4"),
      ("hex Option Array Array inner length", "HexOptionArrayArrayInner",
        "Option Array Array UInt64 0x10 4"),
      ("underscore Option Array Array inner length", "UnderscoreOptionArrayArrayInner",
        "Option Array Array UInt64 4_096 4"),
      ("over-bound Option Array Array outer length", "OverBoundOptionArrayArrayOuter",
        "Option Array Array UInt64 4 4097"),
      ("leading-zero Option Array Array outer length", "LeadingZeroOptionArrayArrayOuter",
        "Option Array Array UInt64 4 01"),
      ("hex Option Array Array outer length", "HexOptionArrayArrayOuter",
        "Option Array Array UInt64 4 0x10"),
      ("underscore Option Array Array outer length", "UnderscoreOptionArrayArrayOuter",
        "Option Array Array UInt64 4 4_096"),
      ("unknown Triple Option element", "UnknownTripleOptionElement",
        "Option Option Option Mystery"),
      ("Field Triple Option element", "FieldTripleOptionElement",
        "Option Option Option Field"),
      ("alternate Field Triple Option identifier", "AlternateFieldTripleOptionId",
        "Option Option Option Field bls12_381_fr"),
      ("escaped Field Triple Option identifier", "EscapedFieldTripleOptionId",
        "Option Option Option Field «bn254_fr»"),
      ("qualified Field Triple Option identifier", "QualifiedFieldTripleOptionId",
        "Option Option Option Field Curves.bn254_fr"),
      ("split Triple Option Field third Option", "SplitTripleOptionFieldThird",
        "Option Option Option\n  Field bn254_fr"),
      ("escaped third Triple Option Field constructor", "EscapedThirdTripleOptionField",
        "Option Option «Option» Field bn254_fr"),
      ("qualified third Triple Option Field constructor", "QualifiedThirdTripleOptionField",
        "Option Option Std.Option Field bn254_fr"),
      ("missing Triple Option element", "MissingTripleOptionElement",
        "Option Option Option"),
      ("bare fourth nested option", "BareFourthNestedOption",
        "Option Option Option Option"),
      ("qualified Triple Option element", "QualifiedTripleOptionElement",
        "Option Option Option Std.Bool"),
      ("escaped Triple Option element", "EscapedTripleOptionElement",
        "Option Option Option «Bool»"),
      ("bare Bytes Triple Option element", "BareBytesTripleOptionElement",
        "Option Option Option Bytes"),
      ("over-bound Triple Option Bytes length", "OverBoundTripleOptionBytes",
        "Option Option Option Bytes 4097"),
      ("leading-zero Triple Option Bytes length", "LeadingZeroTripleOptionBytes",
        "Option Option Option Bytes 01"),
      ("hex Triple Option Bytes length", "HexTripleOptionBytes",
        "Option Option Option Bytes 0x10"),
      ("underscore Triple Option Bytes length", "UnderscoreTripleOptionBytes",
        "Option Option Option Bytes 4_096"),
      ("bare Array Triple Option element", "BareArrayTripleOptionElement",
        "Option Option Option Array"),
      ("bare Map Triple Option element", "BareMapTripleOptionElement",
        "Option Option Option Map"),
      ("Map Triple Option element", "MapTripleOptionElement",
        "Option Option Option Map UInt64 Bool"),
      ("split Triple Option outer", "SplitTripleOptionOuter",
        "Option Option\n  Option Bool"),
      ("escaped outer Triple Option", "EscapedOuterTripleOption",
        "«Option» Option Option Bool"),
      ("qualified outer Triple Option", "QualifiedOuterTripleOption",
        "Std.Option Option Option Bool"),
      ("escaped middle Triple Option", "EscapedMiddleTripleOption",
        "Option «Option» Option Bool"),
      ("qualified middle Triple Option constructor", "QualifiedMiddleTripleOption",
        "Option Std.Option Option Bool"),
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

  let migratedNestedOptionArrayFieldSource :=
    negativeSource "MigratedNestedOptionArrayField" "Option Option Array Field bn254_fr 4"
  match ← session.parsePrograms migratedNestedOptionArrayFieldSource
      "<migrated-nested-option-array-field>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) ==
          #[.option (.option (.array .field 4))])
        "migrated Option Option Array Field bn254_fr 4 pin must now parse as existing option(option(array(field,4)))"
  | .ok programs =>
      throw <| IO.userError
        s!"migrated Option Option Array Field bn254_fr 4 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError
        s!"migrated Option Option Array Field bn254_fr 4 must parse: {error.render}"

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

  let migratedOptionArrayBytesSource :=
    negativeSource "MigratedOptionArrayBytes" "Option Array Bytes 8 4"
  match ← session.parsePrograms migratedOptionArrayBytesSource "<migrated-option-array-bytes>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) == #[.option (.array (.bytes 8) 4)])
        "migrated Option Array Bytes 8 4 pin must now parse as existing option(array(bytes(8),4))"
  | .ok programs =>
      throw <| IO.userError s!"migrated Option Array Bytes 8 4 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError s!"migrated Option Array Bytes 8 4 must parse: {error.render}"

  let migratedOptionArrayArraySource :=
    negativeSource "MigratedOptionArrayArray" "Option Array Array UInt64 4 4"
  match ← session.parsePrograms migratedOptionArrayArraySource "<migrated-option-array-array>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) == #[.option (.array (.array .u64 4) 4)])
        "migrated Option Array Array UInt64 4 4 pin must now parse as existing option(array(array(u64,4),4))"
  | .ok programs =>
      throw <| IO.userError s!"migrated Option Array Array UInt64 4 4 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError s!"migrated Option Array Array UInt64 4 4 must parse: {error.render}"

  let migratedTripleOptionSource :=
    negativeSource "MigratedTripleOption" "Option Option Option Bool"
  match ← session.parsePrograms migratedTripleOptionSource "<migrated-triple-option>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) == #[.option (.option (.option .bool))])
        "migrated Option Option Option Bool pin must now parse as existing option(option(option(bool)))"
  | .ok programs =>
      throw <| IO.userError s!"migrated Option Option Option Bool produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError s!"migrated Option Option Option Bool must parse: {error.render}"

  let migratedTripleOptionFieldSource :=
    negativeSource "MigratedTripleOptionField" "Option Option Option Field bn254_fr"
  match ← session.parsePrograms migratedTripleOptionFieldSource
      "<migrated-triple-option-field>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) ==
          #[.option (.option (.option .field))])
        "migrated Option Option Option Field bn254_fr pin must now parse as existing option(option(option(field)))"
  | .ok programs =>
      throw <| IO.userError
        s!"migrated Option Option Option Field bn254_fr produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError
        s!"migrated Option Option Option Field bn254_fr must parse: {error.render}"

  let migratedTripleOptionBytesSource :=
    negativeSource "MigratedTripleOptionBytes" "Option Option Option Bytes 8"
  match ← session.parsePrograms migratedTripleOptionBytesSource
      "<migrated-triple-option-bytes>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) ==
          #[.option (.option (.option (.bytes 8)))])
        "migrated Option Option Option Bytes 8 pin must now parse as existing option(option(option(bytes(8))))"
  | .ok programs =>
      throw <| IO.userError
        s!"migrated Option Option Option Bytes 8 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError
        s!"migrated Option Option Option Bytes 8 must parse: {error.render}"

  for (label, spelling) in [
      ("fourth nested option", "Option Option Option Option Bool"),
      ("Array Triple Option element", "Option Option Option Array UInt64 4"),
      ("extra Triple Option payload", "Option Option Option Bool Principal"),
      ("extra Triple Option Field payload", "Option Option Option Field bn254_fr Principal"),
      ("extra Triple Option Bytes payload", "Option Option Option Bytes 8 Principal"),
      ("negative Triple Option Bytes length", "Option Option Option Bytes -1"),
      ("identifier Triple Option Bytes length", "Option Option Option Bytes N"),
      ("split Triple Option Bytes outer Option", "Option\n  Option Option Bytes 8"),
      ("split Triple Option Bytes middle Option", "Option Option\n  Option Bytes 8"),
      ("split Triple Option Bytes third Option", "Option Option Option\n  Bytes 8"),
      ("split Triple Option Bytes length", "Option Option Option Bytes\n  8"),
      ("escaped outer Triple Option Bytes", "«Option» Option Option Bytes 8"),
      ("qualified outer Triple Option Bytes", "Std.Option Option Option Bytes 8"),
      ("escaped middle Triple Option Bytes", "Option «Option» Option Bytes 8"),
      ("qualified middle Triple Option Bytes", "Option Std.Option Option Bytes 8"),
      ("escaped third Triple Option Bytes", "Option Option «Option» Bytes 8"),
      ("qualified third Triple Option Bytes", "Option Option Std.Option Bytes 8"),
      ("escaped Bytes Triple Option constructor", "Option Option Option «Bytes» 8"),
      ("qualified Bytes Triple Option constructor", "Option Option Option Std.Bytes 8"),
      ("split Triple Option Field outer Option", "Option\n  Option Option Field bn254_fr"),
      ("split Triple Option Field middle Option", "Option Option\n  Option Field bn254_fr"),
      ("split Triple Option Field identifier", "Option Option Option Field\n  bn254_fr"),
      ("escaped outer Triple Option Field", "«Option» Option Option Field bn254_fr"),
      ("qualified outer Triple Option Field", "Std.Option Option Option Field bn254_fr"),
      ("escaped middle Triple Option Field", "Option «Option» Option Field bn254_fr"),
      ("qualified middle Triple Option Field", "Option Std.Option Option Field bn254_fr"),
      ("escaped Field Triple Option constructor", "Option Option Option «Field» bn254_fr"),
      ("qualified Field Triple Option constructor", "Option Option Option Std.Field bn254_fr"),
      ("escaped inner Triple Option", "Option Option «Option» Bool"),
      ("qualified inner Triple Option constructor", "Option Option Std.Option Bool"),
      ("split Triple Option middle", "Option\n  Option Option Bool"),
      ("split Triple Option third constructor", "Option Option Option\n  Bool"),
      ("extra nested option payload", "Option Option UInt64 Principal"),
      ("split nested option", "Option Option\n  UInt64"),
      ("escaped inner Option constructor", "Option «Option» Bool"),
      ("escaped outer Option constructor", "«Option» Option Bool"),
      ("qualified outer Option constructor", "Std.Option Option Bool"),
      ("missing Option Array length", "Option Array UInt64"),
      ("negative Option Array length", "Option Array UInt64 -1"),
      ("extra Option Array payload", "Option Array UInt64 4 Principal"),
      ("Map Option Array element", "Option Array Map UInt64 Bool 4"),
      ("missing Option Array Array element", "Option Array Array"),
      ("missing Option Array Array lengths", "Option Array Array UInt64"),
      ("missing Option Array Array outer length", "Option Array Array UInt64 4"),
      ("full Field Option Array Array element", "Option Array Array Field bn254_fr 4 4"),
      ("Bytes Option Array Array element", "Option Array Array Bytes 8 4 4"),
      ("Option Option Array Array element", "Option Array Array Option Bool 4 4"),
      ("Array Option Array Array element", "Option Array Array Array UInt64 4 4 4"),
      ("Map Option Array Array element", "Option Array Array Map UInt64 Bool 4 4"),
      ("negative Option Array Array inner length", "Option Array Array UInt64 -1 4"),
      ("negative Option Array Array outer length", "Option Array Array UInt64 4 -1"),
      ("extra Option Array Array payload", "Option Array Array UInt64 4 4 Principal"),
      ("split Option Array Array element", "Option Array Array\n  UInt64 4 4"),
      ("split Option Array Array inner length", "Option Array Array UInt64\n  4 4"),
      ("split Option Array Array outer length", "Option Array Array UInt64 4\n  4"),
      ("escaped inner Array in Option Array Array", "Option Array «Array» UInt64 4 4"),
      ("qualified inner Array in Option Array Array", "Option Array Std.Array UInt64 4 4"),
      ("escaped Array in Option Array Array", "Option «Array» Array UInt64 4 4"),
      ("qualified Array in Option Array Array", "Option Std.Array Array UInt64 4 4"),
      ("escaped outer Option Array Array", "«Option» Array Array UInt64 4 4"),
      ("qualified outer Option Array Array", "Std.Option Array Array UInt64 4 4"),
      ("missing Option Array Bytes lengths", "Option Array Bytes"),
      ("negative Option Array Bytes inner length", "Option Array Bytes -1 4"),
      ("negative Option Array Bytes outer length", "Option Array Bytes 8 -1"),
      ("extra Option Array Bytes payload", "Option Array Bytes 8 4 Principal"),
      ("split Option Array Bytes inner length", "Option Array Bytes\n  8 4"),
      ("split Option Array Bytes outer length", "Option Array Bytes 8\n  4"),
      ("escaped Bytes in Option Array Bytes", "Option Array «Bytes» 8 4"),
      ("qualified Bytes in Option Array Bytes", "Option Array Std.Bytes 8 4"),
      ("escaped Array in Option Array Bytes", "Option «Array» Bytes 8 4"),
      ("qualified Array in Option Array Bytes", "Option Std.Array Bytes 8 4"),
      ("escaped outer Option Array Bytes", "«Option» Array Bytes 8 4"),
      ("qualified outer Option Array Bytes", "Std.Option Array Bytes 8 4"),
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
      ("missing nested Option Array Field length", "Option Option Array Field bn254_fr"),
      ("negative nested Option Array Field length", "Option Option Array Field bn254_fr -1"),
      ("identifier nested Option Array Field length", "Option Option Array Field bn254_fr N"),
      ("extra nested Option Array Field payload",
        "Option Option Array Field bn254_fr 4 Principal"),
      ("split nested Option Array Field outer Option",
        "Option\n  Option Array Field bn254_fr 4"),
      ("split nested Option Array Field middle Option",
        "Option Option\n  Array Field bn254_fr 4"),
      ("split nested Option Array Field Array",
        "Option Option Array\n  Field bn254_fr 4"),
      ("split nested Option Array Field constructor",
        "Option Option Array Field\n  bn254_fr 4"),
      ("split nested Option Array Field length",
        "Option Option Array Field bn254_fr\n  4"),
      ("escaped outer Option nested Option Array Field",
        "«Option» Option Array Field bn254_fr 4"),
      ("qualified outer Option nested Option Array Field",
        "Std.Option Option Array Field bn254_fr 4"),
      ("escaped middle Option nested Option Array Field",
        "Option «Option» Array Field bn254_fr 4"),
      ("qualified middle Option nested Option Array Field",
        "Option Std.Option Array Field bn254_fr 4"),
      ("escaped Array nested Option Array Field",
        "Option Option «Array» Field bn254_fr 4"),
      ("qualified Array nested Option Array Field",
        "Option Option Std.Array Field bn254_fr 4"),
      ("escaped Field nested Option Array Field",
        "Option Option Array «Field» bn254_fr 4"),
      ("qualified Field nested Option Array Field",
        "Option Option Array Std.Field bn254_fr 4"),
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

  let tripleOptionFieldBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.TripleOptionFieldBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"TripleOptionFieldBoundary must compile: {error.render}"
  expect (tripleOptionFieldBoundary.requirements == #[.fieldBn254])
    "Option Option Option Field must recursively propagate fieldBn254 exactly once"
  match tripleOptionFieldBoundary.entries with
  | #[echoEntry] =>
      expect (echoEntry.params.map (·.type) == #[.option (.option (.option .field))] &&
          echoEntry.result == .option (.option (.option .field)))
        "Source-to-Semantic adaptation must preserve triple Option Field tags"
  | _ => throw <| IO.userError "TripleOptionFieldBoundary must retain one semantic entry"
  for target in Targets.phase1 do
    match Targets.checkSupport target tripleOptionFieldBoundary with
    | .error (.unsupportedRequirement .fieldBn254 actual) =>
        expect (actual == target)
          s!"Option Option Option Field support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError
          s!"Option Option Option Field/{target} checkSupport wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError
          s!"Option Option Option Field/{target} unexpectedly passed checkSupport"
    match Targets.materializeResult target tripleOptionFieldBoundary with
    | .error (.unsupportedRequirement .fieldBn254 actual) =>
        expect (actual == target)
          s!"Option Option Option Field materialize rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError
          s!"Option Option Option Field/{target} materializeResult wrong failure: {other.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"Option Option Option Field/{target} must not materialize or emit artifact"

  let nestedOptionArrayFieldBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.NestedOptionArrayFieldBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"NestedOptionArrayFieldBoundary must compile: {error.render}"
  expect (nestedOptionArrayFieldBoundary.requirements == #[.fieldBn254])
    "Option Option Array Field must recursively propagate fieldBn254 exactly once"
  match nestedOptionArrayFieldBoundary.entries with
  | #[echoEntry] =>
      expect (echoEntry.params.map (·.type) == #[.option (.option (.array .field 4))] &&
          echoEntry.result == .option (.option (.array .field 4)))
        "Source-to-Semantic adaptation must preserve nested Option Array Field tags and length"
  | _ => throw <| IO.userError "NestedOptionArrayFieldBoundary must retain one semantic entry"
  for target in Targets.phase1 do
    match Targets.checkSupport target nestedOptionArrayFieldBoundary with
    | .error (.unsupportedRequirement .fieldBn254 actual) =>
        expect (actual == target)
          s!"Option Option Array Field support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError
          s!"Option Option Array Field/{target} checkSupport wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError
          s!"Option Option Array Field/{target} unexpectedly passed checkSupport"
    match Targets.materializeResult target nestedOptionArrayFieldBoundary with
    | .error (.unsupportedRequirement .fieldBn254 actual) =>
        expect (actual == target)
          s!"Option Option Array Field materialize rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError
          s!"Option Option Array Field/{target} materializeResult wrong failure: {other.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"Option Option Array Field/{target} must not materialize or emit artifact"

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


  let optionArrayBytesBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.OptionArrayBytesBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"OptionArrayBytesBoundary must compile: {error.render}"
  expect (optionArrayBytesBoundary.requirements == #[])
    "Option Array Bytes must recursively propagate zero requirements"
  for target in Targets.phase1 do
    match Targets.checkSupport target optionArrayBytesBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError
          s!"{target} must support zero-requirement Option Array Bytes carrier: {error.render}"


  let optionArrayArrayBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.OptionArrayArrayBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"OptionArrayArrayBoundary must compile: {error.render}"
  expect (optionArrayArrayBoundary.requirements == #[])
    "Option Array Array UInt64 must recursively propagate zero requirements"
  for target in Targets.phase1 do
    match Targets.checkSupport target optionArrayArrayBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError
          s!"{target} must support zero-requirement Option Array Array UInt64 carrier: {error.render}"

  let optionArrayArrayBoolBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.OptionArrayArrayBoolBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"OptionArrayArrayBoolBoundary must compile: {error.render}"
  expect (optionArrayArrayBoolBoundary.requirements == #[.boolValues])
    "Option Array Array Bool must recursively propagate boolValues exactly once"
  for target in Targets.phase1 do
    match Targets.checkSupport target optionArrayArrayBoolBoundary with
    | .error (.unsupportedRequirement .boolValues actual) =>
        expect (actual == target)
          s!"Option Array Array Bool support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError
          s!"Option Array Array Bool/{target} reached wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError
          s!"Option Array Array Bool/{target} unexpectedly passed support"


  let tripleOptionBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.TripleOptionBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"TripleOptionBoundary must compile: {error.render}"
  expect (tripleOptionBoundary.requirements == #[])
    "Option Option Option UInt64 must recursively propagate zero requirements"
  for target in Targets.phase1 do
    match Targets.checkSupport target tripleOptionBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError
          s!"{target} must support zero-requirement Option Option Option UInt64 carrier: {error.render}"

  let tripleOptionBoolBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.TripleOptionBoolBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"TripleOptionBoolBoundary must compile: {error.render}"
  expect (tripleOptionBoolBoundary.requirements == #[.boolValues])
    "Option Option Option Bool must recursively propagate boolValues exactly once"
  for target in Targets.phase1 do
    match Targets.checkSupport target tripleOptionBoolBoundary with
    | .error (.unsupportedRequirement .boolValues actual) =>
        expect (actual == target)
          s!"Option Option Option Bool support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError
          s!"Option Option Option Bool/{target} reached wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError
          s!"Option Option Option Bool/{target} unexpectedly passed support"

  let tripleOptionBytesBoundary ← match Compiler.compile
      Tests.Language.OptionDeclarationsFixture.TripleOptionBytesBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"TripleOptionBytesBoundary must compile: {error.render}"
  expect (tripleOptionBytesBoundary.requirements == #[])
    "Option Option Option Bytes must recursively propagate zero requirements"
  match tripleOptionBytesBoundary.entries with
  | #[echoEntry] =>
      expect (echoEntry.params.map (·.type) == #[.option (.option (.option (.bytes 8)))] &&
          echoEntry.result == .option (.option (.option (.bytes 8))))
        "Source-to-Semantic adaptation must preserve triple Option Bytes tags and length"
  | _ => throw <| IO.userError "TripleOptionBytesBoundary must retain one semantic entry"
  for target in Targets.phase1 do
    match Targets.checkSupport target tripleOptionBytesBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError
          s!"{target} must support zero-requirement Option Option Option Bytes carrier: {error.render}"

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
        "is not UInt64"),
      ("OptionArrayBytesStateBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionArrayBytesStateBoundary,
        "is not UInt64"),
      ("OptionArrayBytesResultBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionArrayBytesResultBoundary,
        "does not return UInt64"),
      ("OptionArrayBytesParamBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionArrayBytesParamBoundary,
        "is not UInt64"),
      ("OptionArrayArrayStateBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionArrayArrayStateBoundary,
        "is not UInt64"),
      ("OptionArrayArrayResultBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionArrayArrayResultBoundary,
        "does not return UInt64"),
      ("OptionArrayArrayParamBoundary",
        Tests.Language.OptionDeclarationsFixture.OptionArrayArrayParamBoundary,
        "is not UInt64"),
      ("TripleOptionStateBoundary",
        Tests.Language.OptionDeclarationsFixture.TripleOptionStateBoundary,
        "is not UInt64"),
      ("TripleOptionResultBoundary",
        Tests.Language.OptionDeclarationsFixture.TripleOptionResultBoundary,
        "does not return UInt64"),
      ("TripleOptionParamBoundary",
        Tests.Language.OptionDeclarationsFixture.TripleOptionParamBoundary,
        "is not UInt64"),
      ("TripleOptionBytesStateBoundary",
        Tests.Language.OptionDeclarationsFixture.TripleOptionBytesStateBoundary,
        "is not UInt64"),
      ("TripleOptionBytesResultBoundary",
        Tests.Language.OptionDeclarationsFixture.TripleOptionBytesResultBoundary,
        "does not return UInt64"),
      ("TripleOptionBytesParamBoundary",
        Tests.Language.OptionDeclarationsFixture.TripleOptionBytesParamBoundary,
        "is not UInt64"),
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
