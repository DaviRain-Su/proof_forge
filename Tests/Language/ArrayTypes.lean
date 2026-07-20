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


program ArrayOptionOptionSurface where
  state nestedOptionals : Array Option Option UInt64 4

  event ArrayOptionOptionEvent(payload : Array Option Option UInt64 4)
  error ArrayOptionOptionError(payload : Array Option Option UInt64 4)

  struct NestedOptionalLimits where
    emptyFlags : Array Option Option Bool 0
    ordinary : Array Option Option UInt64 4
    maximum : Array Option Option UInt64 4096
    owners : Array Option Option Principal 4096

  enum NestedOptionalBatch where
    | MaybeNestedCounters(Array Option Option UInt64 4)
    | MaybeNestedFlags(Array Option Option Bool 0)
    | MaybeNestedOwners(Array Option Option Principal 4096)

  const NestedOptionalEmpty : Array Option Option UInt64 0 := 0

  init(initial : Array Option Option UInt64 4) do
    nestedOptionals := initial

  entry echo(value : Array Option Option UInt64 4) : Array Option Option UInt64 4 do
    return value

  view get() : Array Option Option UInt64 4 do
    return nestedOptionals

  fn keepNested(value : Array Option Option Principal 4096) : Array Option Option Principal 4096 do
    return value

program ArrayOptionOptionBoundary where
  entry echo(value : Array Option Option UInt64 4) : Array Option Option UInt64 4 do
    return value

program ArrayOptionOptionBoolBoundary where
  entry echo(value : Array Option Option Bool 0) : Array Option Option Bool 0 do
    return value

program ArrayOptionOptionStateBoundary where
  state value : Array Option Option UInt64 4

  init(initial : Array Option Option UInt64 4) do
    value := initial

  view get() : Array Option Option UInt64 4 do
    return value

program ArrayOptionOptionResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Array Option Option UInt64 4) : Array Option Option UInt64 4 do
    return value

program ArrayOptionOptionParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Array Option Option UInt64 4) : UInt64 do
    return 0

program ArrayOptionOptionFieldSurface where
  state nestedScalars : Array Option Option Field bn254_fr 4

  event ArrayOptionOptionFieldEvent(payload : Array Option Option Field bn254_fr 4)
  error ArrayOptionOptionFieldError(payload : Array Option Option Field bn254_fr 4)

  struct NestedScalarOptionLimits where
    empty : Array Option Option Field bn254_fr 0
    ordinary : Array Option Option Field bn254_fr 4
    maximum : Array Option Option Field bn254_fr 4096

  enum NestedScalarOptionBatch where
    | MaybeNestedScalars(Array Option Option Field bn254_fr 4)
    | MaybeNestedMaximum(Array Option Option Field bn254_fr 4096)

  const NestedScalarOptionEmpty : Array Option Option Field bn254_fr 0 := 0

  init(initial : Array Option Option Field bn254_fr 4) do
    nestedScalars := initial

  entry echo(value : Array Option Option Field bn254_fr 4) : Array Option Option Field bn254_fr 4 do
    return value

  view get() : Array Option Option Field bn254_fr 4 do
    return nestedScalars

  fn keepNested(value : Array Option Option Field bn254_fr 4096) : Array Option Option Field bn254_fr 4096 do
    return value

program ArrayOptionOptionFieldBoundary where
  entry echo(value : Array Option Option Field bn254_fr 4) : Array Option Option Field bn254_fr 4 do
    return value


program ArrayOptionBytesSurface where
  state maybeBlobs : Array Option Bytes 8 4

  event ArrayOptionBytesEvent(payload : Array Option Bytes 8 4)
  error ArrayOptionBytesError(payload : Array Option Bytes 8 4)

  struct OptionalBlobLimits where
    empty : Array Option Bytes 0 0
    ordinary : Array Option Bytes 8 4
    maximum : Array Option Bytes 4096 1

  enum OptionalBlobBatch where
    | MaybeBlobs(Array Option Bytes 8 4)
    | MaybeMaximum(Array Option Bytes 4096 1)

  const EmptyOptionalBlobs : Array Option Bytes 0 0 := 0

  init(initial : Array Option Bytes 8 4) do
    maybeBlobs := initial

  entry echo(value : Array Option Bytes 8 4) : Array Option Bytes 8 4 do
    return value

  view get() : Array Option Bytes 8 4 do
    return maybeBlobs

  fn keepMaximum(value : Array Option Bytes 4096 1) : Array Option Bytes 4096 1 do
    return value

program ArrayOptionBytesBoundary where
  entry echo(value : Array Option Bytes 8 4) : Array Option Bytes 8 4 do
    return value

program ArrayOptionBytesStateBoundary where
  state value : Array Option Bytes 8 4

  init(initial : Array Option Bytes 8 4) do
    value := initial

  view get() : Array Option Bytes 8 4 do
    return value

program ArrayOptionBytesResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Array Option Bytes 8 4) : Array Option Bytes 8 4 do
    return value

program ArrayOptionBytesParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Array Option Bytes 8 4) : UInt64 do
    return 0

program ArrayOptionOptionBytesSurface where
  state nestedBlobs : Array Option Option Bytes 8 4
  event ArrayOptionOptionBytesEvent(payload : Array Option Option Bytes 8 4)
  error ArrayOptionOptionBytesError(payload : Array Option Option Bytes 8 4)
  struct NestedOptionalBlobLimits where
    empty : Array Option Option Bytes 0 0
    ordinary : Array Option Option Bytes 8 4
    maximum : Array Option Option Bytes 4096 1
  enum NestedOptionalBlobBatch where
    | MaybeNestedBlobs(Array Option Option Bytes 8 4)
    | MaybeNestedMaximum(Array Option Option Bytes 4096 1)
  const NestedOptionalBlobEmpty : Array Option Option Bytes 0 0 := 0
  init(initial : Array Option Option Bytes 8 4) do
    nestedBlobs := initial
  entry echo(value : Array Option Option Bytes 8 4) : Array Option Option Bytes 8 4 do
    return value
  view get() : Array Option Option Bytes 8 4 do
    return nestedBlobs
  fn keepMaximum(value : Array Option Option Bytes 4096 1) : Array Option Option Bytes 4096 1 do
    return value

program ArrayOptionOptionBytesBoundary where
  entry echo(value : Array Option Option Bytes 8 4) : Array Option Option Bytes 8 4 do
    return value

program ArrayOptionOptionBytesStateBoundary where
  state value : Array Option Option Bytes 8 4
  init(initial : Array Option Option Bytes 8 4) do
    value := initial
  view get() : Array Option Option Bytes 8 4 do
    return value

program ArrayOptionOptionBytesResultBoundary where
  state counter : UInt64
  init(initial : UInt64) do
    counter := initial
  entry echo(value : Array Option Option Bytes 8 4) : Array Option Option Bytes 8 4 do
    return value

program ArrayOptionOptionBytesParamBoundary where
  state counter : UInt64
  init(initial : UInt64) do
    counter := initial
  entry echo(value : Array Option Option Bytes 8 4) : UInt64 do
    return 0

program ArrayFieldSurface where
  state scalars : Array Field bn254_fr 4

  struct ScalarLimits where
    empty : Array Field bn254_fr 0
    maximum : Array Field bn254_fr 4096

  enum ScalarBatch where
    | Scalars(Array Field bn254_fr 4)
    | Maximum(Array Field bn254_fr 4096)

  const EmptyScalars : Array Field bn254_fr 0 := 0

  init(initial : Array Field bn254_fr 4) do
    scalars := initial

  entry echo(value : Array Field bn254_fr 4) : Array Field bn254_fr 4 do
    return value

  view get() : Array Field bn254_fr 4 do
    return scalars

  fn keepMaximum(value : Array Field bn254_fr 4096) : Array Field bn254_fr 4096 do
    return value

program ArrayFieldBoundary where
  entry echo(value : Array Field bn254_fr 4) : Array Field bn254_fr 4 do
    return value

program ArrayBytesSurface where
  state blobs : Array Bytes 32 4

  struct BlobLimits where
    empty : Array Bytes 0 0
    maximum : Array Bytes 4096 1

  enum BlobBatch where
    | Blobs(Array Bytes 32 4)
    | Maximum(Array Bytes 4096 1)

  const EmptyBlobs : Array Bytes 0 0 := 0

  init(initial : Array Bytes 32 4) do
    blobs := initial

  entry echo(value : Array Bytes 32 4) : Array Bytes 32 4 do
    return value

  view get() : Array Bytes 32 4 do
    return blobs

  fn keepMaximum(value : Array Bytes 4096 1) : Array Bytes 4096 1 do
    return value

program ArrayBytesBoundary where
  entry echo(value : Array Bytes 32 4) : Array Bytes 32 4 do
    return value

program ArrayBytesStateBoundary where
  state value : Array Bytes 32 4

  init(initial : Array Bytes 32 4) do
    value := initial

  view get() : Array Bytes 32 4 do
    return value

program ArrayBytesResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Array Bytes 32 4) : Array Bytes 32 4 do
    return value

program ArrayBytesParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Array Bytes 32 4) : UInt64 do
    return 0

program ArrayArraySurface where
  state matrix : Array Array UInt64 4 4

  event NestedMatrixEvent(payload : Array Array UInt64 4 4)
  error NestedMatrixError(payload : Array Array UInt64 4 4)

  struct NestedLimits where
    empty : Array Array UInt64 0 0
    ordinary : Array Array UInt64 4 4
    maximum : Array Array UInt64 4096 1
    flags : Array Array Bool 0 0

  enum NestedBatch where
    | Matrices(Array Array UInt64 4 4)
    | Flags(Array Array Bool 0 0)
    | Owners(Array Array Principal 4096 1)

  const EmptyMatrix : Array Array UInt64 0 0 := 0

  init(initial : Array Array UInt64 4 4) do
    matrix := initial

  entry echo(value : Array Array UInt64 4 4) : Array Array UInt64 4 4 do
    return value

  view get() : Array Array UInt64 4 4 do
    return matrix

  fn keepMaximum(value : Array Array Principal 4096 1) : Array Array Principal 4096 1 do
    return value

program ArrayArrayBoundary where
  entry echo(value : Array Array UInt64 4 4) : Array Array UInt64 4 4 do
    return value

program ArrayArrayBoolBoundary where
  entry echo(value : Array Array Bool 0 0) : Array Array Bool 0 0 do
    return value

program ArrayArrayStateBoundary where
  state value : Array Array UInt64 4 4

  init(initial : Array Array UInt64 4 4) do
    value := initial

  view get() : Array Array UInt64 4 4 do
    return value

program ArrayArrayResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Array Array UInt64 4 4) : Array Array UInt64 4 4 do
    return value

program ArrayArrayParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Array Array UInt64 4 4) : UInt64 do
    return 0

program ArrayArrayFieldSurface where
  state matrix : Array Array Field bn254_fr 4 4

  event NestedFieldMatrixEvent(payload : Array Array Field bn254_fr 4 4)
  error NestedFieldMatrixError(payload : Array Array Field bn254_fr 4 4)

  struct NestedFieldLimits where
    empty : Array Array Field bn254_fr 0 0
    ordinary : Array Array Field bn254_fr 4 4
    maximum : Array Array Field bn254_fr 4096 1

  enum NestedFieldBatch where
    | FieldMatrices(Array Array Field bn254_fr 4 4)
    | FieldMaximum(Array Array Field bn254_fr 4096 1)

  const EmptyFieldMatrix : Array Array Field bn254_fr 0 0 := 0

  init(initial : Array Array Field bn254_fr 4 4) do
    matrix := initial

  entry echo(value : Array Array Field bn254_fr 4 4) : Array Array Field bn254_fr 4 4 do
    return value

  view get() : Array Array Field bn254_fr 4 4 do
    return matrix

  fn keepMaximum(value : Array Array Field bn254_fr 4096 1) : Array Array Field bn254_fr 4096 1 do
    return value

program ArrayArrayFieldBoundary where
  entry echo(value : Array Array Field bn254_fr 4 4) : Array Array Field bn254_fr 4 4 do
    return value

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


private def arrayOptionOptionSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ArrayTypesFixture\n\n" ++
  "program ArrayOptionOptionSurface where\n" ++
  "  state nestedOptionals : Array Option Option UInt64 4\n\n" ++
  "  event ArrayOptionOptionEvent(payload : Array Option Option UInt64 4)\n" ++
  "  error ArrayOptionOptionError(payload : Array Option Option UInt64 4)\n\n" ++
  "  struct NestedOptionalLimits where\n" ++
  "    emptyFlags : Array Option Option Bool 0\n" ++
  "    ordinary : Array Option Option UInt64 4\n" ++
  "    maximum : Array Option Option UInt64 4096\n" ++
  "    owners : Array Option Option Principal 4096\n\n" ++
  "  enum NestedOptionalBatch where\n" ++
  "    | MaybeNestedCounters(Array Option Option UInt64 4)\n" ++
  "    | MaybeNestedFlags(Array Option Option Bool 0)\n" ++
  "    | MaybeNestedOwners(Array Option Option Principal 4096)\n\n" ++
  "  const NestedOptionalEmpty : Array Option Option UInt64 0 := 0\n\n" ++
  "  init(initial : Array Option Option UInt64 4) do\n" ++
  "    nestedOptionals := initial\n\n" ++
  "  entry echo(value : Array Option Option UInt64 4) : Array Option Option UInt64 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Array Option Option UInt64 4 do\n" ++
  "    return nestedOptionals\n\n" ++
  "  fn keepNested(value : Array Option Option Principal 4096) : Array Option Option Principal 4096 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.ArrayTypesFixture\n"

private def arrayOptionOptionFieldSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ArrayTypesFixture\n\n" ++
  "program ArrayOptionOptionFieldSurface where\n" ++
  "  state nestedScalars : Array Option Option Field bn254_fr 4\n\n" ++
  "  event ArrayOptionOptionFieldEvent(payload : Array Option Option Field bn254_fr 4)\n" ++
  "  error ArrayOptionOptionFieldError(payload : Array Option Option Field bn254_fr 4)\n\n" ++
  "  struct NestedScalarOptionLimits where\n" ++
  "    empty : Array Option Option Field bn254_fr 0\n" ++
  "    ordinary : Array Option Option Field bn254_fr 4\n" ++
  "    maximum : Array Option Option Field bn254_fr 4096\n\n" ++
  "  enum NestedScalarOptionBatch where\n" ++
  "    | MaybeNestedScalars(Array Option Option Field bn254_fr 4)\n" ++
  "    | MaybeNestedMaximum(Array Option Option Field bn254_fr 4096)\n\n" ++
  "  const NestedScalarOptionEmpty : Array Option Option Field bn254_fr 0 := 0\n\n" ++
  "  init(initial : Array Option Option Field bn254_fr 4) do\n" ++
  "    nestedScalars := initial\n\n" ++
  "  entry echo(value : Array Option Option Field bn254_fr 4) : Array Option Option Field bn254_fr 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Array Option Option Field bn254_fr 4 do\n" ++
  "    return nestedScalars\n\n" ++
  "  fn keepNested(value : Array Option Option Field bn254_fr 4096) : Array Option Option Field bn254_fr 4096 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.ArrayTypesFixture\n"

private def arrayFieldSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ArrayTypesFixture\n\n" ++
  "program ArrayFieldSurface where\n" ++
  "  state scalars : Array Field bn254_fr 4\n\n" ++
  "  struct ScalarLimits where\n" ++
  "    empty : Array Field bn254_fr 0\n" ++
  "    maximum : Array Field bn254_fr 4096\n\n" ++
  "  enum ScalarBatch where\n" ++
  "    | Scalars(Array Field bn254_fr 4)\n" ++
  "    | Maximum(Array Field bn254_fr 4096)\n\n" ++
  "  const EmptyScalars : Array Field bn254_fr 0 := 0\n\n" ++
  "  init(initial : Array Field bn254_fr 4) do\n" ++
  "    scalars := initial\n\n" ++
  "  entry echo(value : Array Field bn254_fr 4) : Array Field bn254_fr 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Array Field bn254_fr 4 do\n" ++
  "    return scalars\n\n" ++
  "  fn keepMaximum(value : Array Field bn254_fr 4096) : Array Field bn254_fr 4096 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.ArrayTypesFixture\n"


private def arrayOptionBytesSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ArrayTypesFixture\n\n" ++
  "program ArrayOptionBytesSurface where\n" ++
  "  state maybeBlobs : Array Option Bytes 8 4\n\n" ++
  "  event ArrayOptionBytesEvent(payload : Array Option Bytes 8 4)\n" ++
  "  error ArrayOptionBytesError(payload : Array Option Bytes 8 4)\n\n" ++
  "  struct OptionalBlobLimits where\n" ++
  "    empty : Array Option Bytes 0 0\n" ++
  "    ordinary : Array Option Bytes 8 4\n" ++
  "    maximum : Array Option Bytes 4096 1\n\n" ++
  "  enum OptionalBlobBatch where\n" ++
  "    | MaybeBlobs(Array Option Bytes 8 4)\n" ++
  "    | MaybeMaximum(Array Option Bytes 4096 1)\n\n" ++
  "  const EmptyOptionalBlobs : Array Option Bytes 0 0 := 0\n\n" ++
  "  init(initial : Array Option Bytes 8 4) do\n" ++
  "    maybeBlobs := initial\n\n" ++
  "  entry echo(value : Array Option Bytes 8 4) : Array Option Bytes 8 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Array Option Bytes 8 4 do\n" ++
  "    return maybeBlobs\n\n" ++
  "  fn keepMaximum(value : Array Option Bytes 4096 1) : Array Option Bytes 4096 1 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.ArrayTypesFixture\n"

private def arrayOptionOptionBytesSurfaceSource : String :=
  "import ProofForgeV2\n\nopen ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ArrayTypesFixture\n\n" ++
  "program ArrayOptionOptionBytesSurface where\n" ++
  "  state nestedBlobs : Array Option Option Bytes 8 4\n" ++
  "  event ArrayOptionOptionBytesEvent(payload : Array Option Option Bytes 8 4)\n" ++
  "  error ArrayOptionOptionBytesError(payload : Array Option Option Bytes 8 4)\n" ++
  "  struct NestedOptionalBlobLimits where\n" ++
  "    empty : Array Option Option Bytes 0 0\n" ++
  "    ordinary : Array Option Option Bytes 8 4\n" ++
  "    maximum : Array Option Option Bytes 4096 1\n" ++
  "  enum NestedOptionalBlobBatch where\n" ++
  "    | MaybeNestedBlobs(Array Option Option Bytes 8 4)\n" ++
  "    | MaybeNestedMaximum(Array Option Option Bytes 4096 1)\n" ++
  "  const NestedOptionalBlobEmpty : Array Option Option Bytes 0 0 := 0\n" ++
  "  init(initial : Array Option Option Bytes 8 4) do\n" ++
  "    nestedBlobs := initial\n" ++
  "  entry echo(value : Array Option Option Bytes 8 4) : Array Option Option Bytes 8 4 do\n" ++
  "    return value\n" ++
  "  view get() : Array Option Option Bytes 8 4 do\n" ++
  "    return nestedBlobs\n" ++
  "  fn keepMaximum(value : Array Option Option Bytes 4096 1) : Array Option Option Bytes 4096 1 do\n" ++
  "    return value\n" ++
  "end Tests.Language.ArrayTypesFixture\n"

private def arrayBytesSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ArrayTypesFixture\n\n" ++
  "program ArrayBytesSurface where\n" ++
  "  state blobs : Array Bytes 32 4\n\n" ++
  "  struct BlobLimits where\n" ++
  "    empty : Array Bytes 0 0\n" ++
  "    maximum : Array Bytes 4096 1\n\n" ++
  "  enum BlobBatch where\n" ++
  "    | Blobs(Array Bytes 32 4)\n" ++
  "    | Maximum(Array Bytes 4096 1)\n\n" ++
  "  const EmptyBlobs : Array Bytes 0 0 := 0\n\n" ++
  "  init(initial : Array Bytes 32 4) do\n" ++
  "    blobs := initial\n\n" ++
  "  entry echo(value : Array Bytes 32 4) : Array Bytes 32 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Array Bytes 32 4 do\n" ++
  "    return blobs\n\n" ++
  "  fn keepMaximum(value : Array Bytes 4096 1) : Array Bytes 4096 1 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.ArrayTypesFixture\n"

private def arrayArraySurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ArrayTypesFixture\n\n" ++
  "program ArrayArraySurface where\n" ++
  "  state matrix : Array Array UInt64 4 4\n\n" ++
  "  event NestedMatrixEvent(payload : Array Array UInt64 4 4)\n" ++
  "  error NestedMatrixError(payload : Array Array UInt64 4 4)\n\n" ++
  "  struct NestedLimits where\n" ++
  "    empty : Array Array UInt64 0 0\n" ++
  "    ordinary : Array Array UInt64 4 4\n" ++
  "    maximum : Array Array UInt64 4096 1\n" ++
  "    flags : Array Array Bool 0 0\n\n" ++
  "  enum NestedBatch where\n" ++
  "    | Matrices(Array Array UInt64 4 4)\n" ++
  "    | Flags(Array Array Bool 0 0)\n" ++
  "    | Owners(Array Array Principal 4096 1)\n\n" ++
  "  const EmptyMatrix : Array Array UInt64 0 0 := 0\n\n" ++
  "  init(initial : Array Array UInt64 4 4) do\n" ++
  "    matrix := initial\n\n" ++
  "  entry echo(value : Array Array UInt64 4 4) : Array Array UInt64 4 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Array Array UInt64 4 4 do\n" ++
  "    return matrix\n\n" ++
  "  fn keepMaximum(value : Array Array Principal 4096 1) : Array Array Principal 4096 1 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.ArrayTypesFixture\n"

private def arrayArrayFieldSurfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ArrayTypesFixture\n\n" ++
  "program ArrayArrayFieldSurface where\n" ++
  "  state matrix : Array Array Field bn254_fr 4 4\n\n" ++
  "  event NestedFieldMatrixEvent(payload : Array Array Field bn254_fr 4 4)\n" ++
  "  error NestedFieldMatrixError(payload : Array Array Field bn254_fr 4 4)\n\n" ++
  "  struct NestedFieldLimits where\n" ++
  "    empty : Array Array Field bn254_fr 0 0\n" ++
  "    ordinary : Array Array Field bn254_fr 4 4\n" ++
  "    maximum : Array Array Field bn254_fr 4096 1\n\n" ++
  "  enum NestedFieldBatch where\n" ++
  "    | FieldMatrices(Array Array Field bn254_fr 4 4)\n" ++
  "    | FieldMaximum(Array Array Field bn254_fr 4096 1)\n\n" ++
  "  const EmptyFieldMatrix : Array Array Field bn254_fr 0 0 := 0\n\n" ++
  "  init(initial : Array Array Field bn254_fr 4 4) do\n" ++
  "    matrix := initial\n\n" ++
  "  entry echo(value : Array Array Field bn254_fr 4 4) : Array Array Field bn254_fr 4 4 do\n" ++
  "    return value\n\n" ++
  "  view get() : Array Array Field bn254_fr 4 4 do\n" ++
  "    return matrix\n\n" ++
  "  fn keepMaximum(value : Array Array Field bn254_fr 4096 1) : Array Array Field bn254_fr 4096 1 do\n" ++
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

set_option maxRecDepth 2048 in
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


  let arrayOptionOptionSurface := Tests.Language.ArrayTypesFixture.ArrayOptionOptionSurface
  expect (arrayOptionOptionSurface.state.map (·.type) ==
      #[.array (.option (.option .u64)) 4])
    "Array Option Option UInt64 4 state must survive Lean command elaboration"
  match arrayOptionOptionSurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "ArrayOptionOptionEvent" &&
          eventDecl.params.map (·.type) == #[.array (.option (.option .u64)) 4])
        "Array Option Option event parameter must preserve nested Option tags and length"
  | _ => throw <| IO.userError "ArrayOptionOptionSurface must retain ArrayOptionOptionEvent"
  match arrayOptionOptionSurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "ArrayOptionOptionError" &&
          errorDecl.params.map (·.type) == #[.array (.option (.option .u64)) 4])
        "Array Option Option error parameter must preserve nested Option tags and length"
  | _ => throw <| IO.userError "ArrayOptionOptionSurface must retain ArrayOptionOptionError"
  match arrayOptionOptionSurface.structs with
  | #[limits] =>
      expect (limits.name == "NestedOptionalLimits" &&
          limits.fields.map (·.type) ==
            #[.array (.option (.option .bool)) 0, .array (.option (.option .u64)) 4,
              .array (.option (.option .u64)) 4096, .array (.option (.option .principal)) 4096])
        "Array Option Option struct fields must preserve element and length matrix"
  | _ => throw <| IO.userError "ArrayOptionOptionSurface must retain one struct"
  match arrayOptionOptionSurface.enums with
  | #[batch] =>
      expect (batch.name == "NestedOptionalBatch" && batch.variants.map (·.payloadTypes) ==
          #[#[.array (.option (.option .u64)) 4], #[.array (.option (.option .bool)) 0],
            #[.array (.option (.option .principal)) 4096]])
        "Array Option Option enum payloads must preserve element and length matrix"
  | _ => throw <| IO.userError "ArrayOptionOptionSurface must retain one enum"
  match arrayOptionOptionSurface.consts with
  | #[emptyConst] =>
      expect (emptyConst.name == "NestedOptionalEmpty" &&
          emptyConst.type == .array (.option (.option .u64)) 0)
        "Array Option Option UInt64 0 const type must survive elaboration"
  | _ => throw <| IO.userError "ArrayOptionOptionSurface must retain NestedOptionalEmpty"
  match arrayOptionOptionSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.array (.option (.option .u64)) 4])
        "Array Option Option initializer parameter must survive elaboration"
  | none => throw <| IO.userError "ArrayOptionOptionSurface must retain initializer"
  match arrayOptionOptionSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.array (.option (.option .u64)) 4] &&
          echoEntry.result == .array (.option (.option .u64)) 4 &&
          getView.result == .array (.option (.option .u64)) 4 && getView.mode == .view)
        "Array Option Option entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "ArrayOptionOptionSurface must retain echo and get"
  match arrayOptionOptionSurface.functions with
  | #[keepNested] =>
      expect (keepNested.params.map (·.type) == #[.array (.option (.option .principal)) 4096] &&
          keepNested.result == .array (.option (.option .principal)) 4096)
        "Array Option Option Principal 4096 fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "ArrayOptionOptionSurface must retain keepNested"
  match ← session.selectProgram arrayOptionOptionSurfaceSource "<array-option-option-types>" none with
  | .ok decoded =>
      expect (decoded == arrayOptionOptionSurface)
        "Loader and Lean command must produce the same Array Option Option Source.Program"
      expect (decoded.sourceHash == arrayOptionOptionSurface.sourceHash)
        "Loader and Lean command must produce the same Array Option Option sourceHash"
  | .error error => throw <| IO.userError error.render

  let arrayOptionOptionFieldSurface :=
    Tests.Language.ArrayTypesFixture.ArrayOptionOptionFieldSurface
  expect (arrayOptionOptionFieldSurface.state.map (·.type) ==
      #[.array (.option (.option .field)) 4])
    "Array Option Option Field bn254_fr 4 state must survive Lean command elaboration"
  match arrayOptionOptionFieldSurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "ArrayOptionOptionFieldEvent" &&
          eventDecl.params.map (·.type) == #[.array (.option (.option .field)) 4])
        "Array Option Option Field event must preserve Array/Option/Option/Field tags and length"
  | _ => throw <| IO.userError "ArrayOptionOptionFieldSurface must retain ArrayOptionOptionFieldEvent"
  match arrayOptionOptionFieldSurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "ArrayOptionOptionFieldError" &&
          errorDecl.params.map (·.type) == #[.array (.option (.option .field)) 4])
        "Array Option Option Field error must preserve Array/Option/Option/Field tags and length"
  | _ => throw <| IO.userError "ArrayOptionOptionFieldSurface must retain ArrayOptionOptionFieldError"
  match arrayOptionOptionFieldSurface.structs with
  | #[box] =>
      expect (box.name == "NestedScalarOptionLimits" &&
          box.fields.map (·.type) ==
            #[.array (.option (.option .field)) 0,
              .array (.option (.option .field)) 4,
              .array (.option (.option .field)) 4096])
        "Array Option Option Field struct fields must preserve lengths 0/4/4096"
  | _ => throw <| IO.userError "ArrayOptionOptionFieldSurface must retain one struct"
  match arrayOptionOptionFieldSurface.enums with
  | #[tag] =>
      expect (tag.name == "NestedScalarOptionBatch" &&
          tag.variants.map (·.payloadTypes) ==
            #[#[.array (.option (.option .field)) 4],
              #[.array (.option (.option .field)) 4096]])
        "Array Option Option Field enum payloads must preserve lengths 4/4096"
  | _ => throw <| IO.userError "ArrayOptionOptionFieldSurface must retain one enum"
  match arrayOptionOptionFieldSurface.consts with
  | #[seed] =>
      expect (seed.name == "NestedScalarOptionEmpty" &&
          seed.type == .array (.option (.option .field)) 0)
        "Array Option Option Field const type must survive elaboration"
  | _ => throw <| IO.userError "ArrayOptionOptionFieldSurface must retain NestedScalarOptionEmpty"
  match arrayOptionOptionFieldSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.array (.option (.option .field)) 4])
        "Array Option Option Field initializer parameter must survive elaboration"
  | none => throw <| IO.userError "ArrayOptionOptionFieldSurface must retain initializer"
  match arrayOptionOptionFieldSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.array (.option (.option .field)) 4] &&
          echoEntry.result == .array (.option (.option .field)) 4 &&
          getView.result == .array (.option (.option .field)) 4 && getView.mode == .view)
        "Array Option Option Field entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "ArrayOptionOptionFieldSurface must retain echo and get"
  match arrayOptionOptionFieldSurface.functions with
  | #[keepFn] =>
      expect (keepFn.params.map (·.type) == #[.array (.option (.option .field)) 4096] &&
          keepFn.result == .array (.option (.option .field)) 4096)
        "Array Option Option Field fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "ArrayOptionOptionFieldSurface must retain keepNested"
  match ← session.selectProgram arrayOptionOptionFieldSurfaceSource
      "<array-option-option-field-types>" none with
  | .ok decoded =>
      expect (decoded == arrayOptionOptionFieldSurface)
        "Loader and Lean command must produce the same Array Option Option Field Source.Program"
      expect (decoded.sourceHash == arrayOptionOptionFieldSurface.sourceHash)
        "Loader and Lean command must produce the same Array Option Option Field sourceHash"
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


  let arrayOptionOptionElements : Array (String × Source.ValueType) := #[
    ("Bool", .bool),
    ("UInt8", .u8), ("UInt16", .u16), ("UInt32", .u32), ("UInt64", .u64),
    ("UInt128", .u128), ("UInt256", .u256),
    ("Int8", .i8), ("Int16", .i16), ("Int32", .i32), ("Int64", .i64),
    ("Int128", .i128), ("Int256", .i256),
    ("Unit", .unit), ("Principal", .principal)
  ]
  expect (arrayOptionOptionElements.size == 15)
    "Array Option Option PrimitiveAtom matrix must contain exactly 15 elements"
  for (spelling, element) in arrayOptionOptionElements do
    let source := negativeSource s!"ArrayOptionOption{spelling}" s!"Array Option Option {spelling} 4"
    match ← session.parsePrograms source s!"<array-option-option-{spelling}>" with
    | .ok #[decodedProgram] =>
        expect (decodedProgram.state.map (·.type) == #[.array (.option (.option element)) 4])
          s!"Array Option Option {spelling} 4 must preserve its exact element and length"
    | .ok programs =>
        throw <| IO.userError s!"Array Option Option {spelling} 4 produced {programs.size} programs"
    | .error error =>
        throw <| IO.userError s!"Array Option Option {spelling} 4 must parse: {error.render}"

  let arrayFieldSurface := Tests.Language.ArrayTypesFixture.ArrayFieldSurface
  expect (arrayFieldSurface.state.map (·.type) == #[.array .field 4])
    "Array Field bn254_fr 4 state must survive Lean command elaboration"
  match arrayFieldSurface.structs with
  | #[limits] =>
      expect (limits.name == "ScalarLimits" &&
          limits.fields.map (·.type) == #[.array .field 0, .array .field 4096])
        "Array Field struct fields must preserve exact field id and length"
  | _ => throw <| IO.userError "ArrayFieldSurface must retain one struct"
  match arrayFieldSurface.enums with
  | #[batch] =>
      expect (batch.name == "ScalarBatch" && batch.variants.map (·.payloadTypes) ==
          #[#[.array .field 4], #[.array .field 4096]])
        "Array Field enum payloads must preserve exact field id and length"
  | _ => throw <| IO.userError "ArrayFieldSurface must retain one enum"
  match arrayFieldSurface.consts with
  | #[emptyScalars] =>
      expect (emptyScalars.name == "EmptyScalars" && emptyScalars.type == .array .field 0)
        "Array Field bn254_fr 0 const type must survive elaboration"
  | _ => throw <| IO.userError "ArrayFieldSurface must retain EmptyScalars"
  match arrayFieldSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.array .field 4])
        "Array Field initializer parameter must survive elaboration"
  | none => throw <| IO.userError "ArrayFieldSurface must retain initializer"
  match arrayFieldSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.array .field 4] &&
          echoEntry.result == .array .field 4 &&
          getView.result == .array .field 4 && getView.mode == .view)
        "Array Field entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "ArrayFieldSurface must retain echo and get"
  match arrayFieldSurface.functions with
  | #[keepMaximum] =>
      expect (keepMaximum.params.map (·.type) == #[.array .field 4096] &&
          keepMaximum.result == .array .field 4096)
        "Array Field 4096 fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "ArrayFieldSurface must retain keepMaximum"
  match ← session.selectProgram arrayFieldSurfaceSource "<array-field-types>" none with
  | .ok decoded =>
      expect (decoded == arrayFieldSurface)
        "Loader and Lean command must produce the same Array Field Source.Program"
      expect (decoded.sourceHash == arrayFieldSurface.sourceHash)
        "Loader and Lean command must produce the same Array Field sourceHash"
  | .error error => throw <| IO.userError error.render

  let arrayBytesSurface := Tests.Language.ArrayTypesFixture.ArrayBytesSurface
  expect (arrayBytesSurface.state.map (·.type) == #[.array (.bytes 32) 4])
    "Array Bytes 32 4 state must survive Lean command elaboration"
  match arrayBytesSurface.structs with
  | #[limits] =>
      expect (limits.name == "BlobLimits" &&
          limits.fields.map (·.type) == #[.array (.bytes 0) 0, .array (.bytes 4096) 1])
        "Array Bytes struct fields must preserve exact inner and outer lengths"
  | _ => throw <| IO.userError "ArrayBytesSurface must retain one struct"
  match arrayBytesSurface.enums with
  | #[batch] =>
      expect (batch.name == "BlobBatch" && batch.variants.map (·.payloadTypes) ==
          #[#[.array (.bytes 32) 4], #[.array (.bytes 4096) 1]])
        "Array Bytes enum payloads must preserve exact inner and outer lengths"
  | _ => throw <| IO.userError "ArrayBytesSurface must retain one enum"
  match arrayBytesSurface.consts with
  | #[emptyBlobs] =>
      expect (emptyBlobs.name == "EmptyBlobs" && emptyBlobs.type == .array (.bytes 0) 0)
        "Array Bytes 0 0 const type must survive elaboration"
  | _ => throw <| IO.userError "ArrayBytesSurface must retain EmptyBlobs"
  match arrayBytesSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.array (.bytes 32) 4])
        "Array Bytes initializer parameter must survive elaboration"
  | none => throw <| IO.userError "ArrayBytesSurface must retain initializer"
  match arrayBytesSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.array (.bytes 32) 4] &&
          echoEntry.result == .array (.bytes 32) 4 &&
          getView.result == .array (.bytes 32) 4 && getView.mode == .view)
        "Array Bytes entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "ArrayBytesSurface must retain echo and get"
  match arrayBytesSurface.functions with
  | #[keepMaximum] =>
      expect (keepMaximum.params.map (·.type) == #[.array (.bytes 4096) 1] &&
          keepMaximum.result == .array (.bytes 4096) 1)
        "Array Bytes 4096 1 fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "ArrayBytesSurface must retain keepMaximum"
  match ← session.selectProgram arrayBytesSurfaceSource "<array-bytes-types>" none with
  | .ok decoded =>
      expect (decoded == arrayBytesSurface)
        "Loader and Lean command must produce the same Array Bytes Source.Program"
      expect (decoded.sourceHash == arrayBytesSurface.sourceHash)
        "Loader and Lean command must produce the same Array Bytes sourceHash"
  | .error error => throw <| IO.userError error.render


  let arrayOptionBytesSurface := Tests.Language.ArrayTypesFixture.ArrayOptionBytesSurface
  expect (arrayOptionBytesSurface.state.map (·.type) ==
      #[.array (.option (.bytes 8)) 4])
    "Array Option Bytes 8 4 state must survive Lean command elaboration"
  match arrayOptionBytesSurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "ArrayOptionBytesEvent" &&
          eventDecl.params.map (·.type) == #[.array (.option (.bytes 8)) 4])
        "Array Option Bytes event parameter must preserve Option/Bytes tags and dual lengths"
  | _ => throw <| IO.userError "ArrayOptionBytesSurface must retain ArrayOptionBytesEvent"
  match arrayOptionBytesSurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "ArrayOptionBytesError" &&
          errorDecl.params.map (·.type) == #[.array (.option (.bytes 8)) 4])
        "Array Option Bytes error parameter must preserve Option/Bytes tags and dual lengths"
  | _ => throw <| IO.userError "ArrayOptionBytesSurface must retain ArrayOptionBytesError"
  match arrayOptionBytesSurface.structs with
  | #[limits] =>
      expect (limits.name == "OptionalBlobLimits" &&
          limits.fields.map (·.type) ==
            #[.array (.option (.bytes 0)) 0, .array (.option (.bytes 8)) 4,
              .array (.option (.bytes 4096)) 1])
        "Array Option Bytes struct fields must preserve dual lengths 0/0, 8/4, 4096/1"
  | _ => throw <| IO.userError "ArrayOptionBytesSurface must retain one struct"
  match arrayOptionBytesSurface.enums with
  | #[batch] =>
      expect (batch.name == "OptionalBlobBatch" && batch.variants.map (·.payloadTypes) ==
          #[#[.array (.option (.bytes 8)) 4], #[.array (.option (.bytes 4096)) 1]])
        "Array Option Bytes enum payloads must preserve dual length matrix"
  | _ => throw <| IO.userError "ArrayOptionBytesSurface must retain one enum"
  match arrayOptionBytesSurface.consts with
  | #[emptyConst] =>
      expect (emptyConst.name == "EmptyOptionalBlobs" &&
          emptyConst.type == .array (.option (.bytes 0)) 0)
        "Array Option Bytes 0 0 const type must survive elaboration"
  | _ => throw <| IO.userError "ArrayOptionBytesSurface must retain EmptyOptionalBlobs"
  match arrayOptionBytesSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.array (.option (.bytes 8)) 4])
        "Array Option Bytes initializer parameter must survive elaboration"
  | none => throw <| IO.userError "ArrayOptionBytesSurface must retain initializer"
  match arrayOptionBytesSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.array (.option (.bytes 8)) 4] &&
          echoEntry.result == .array (.option (.bytes 8)) 4 &&
          getView.result == .array (.option (.bytes 8)) 4 && getView.mode == .view)
        "Array Option Bytes entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "ArrayOptionBytesSurface must retain echo and get"
  match arrayOptionBytesSurface.functions with
  | #[keepMaximum] =>
      expect (keepMaximum.params.map (·.type) == #[.array (.option (.bytes 4096)) 1] &&
          keepMaximum.result == .array (.option (.bytes 4096)) 1)
        "Array Option Bytes 4096 1 fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "ArrayOptionBytesSurface must retain keepMaximum"
  match ← session.selectProgram arrayOptionBytesSurfaceSource "<array-option-bytes-types>" none with
  | .ok decoded =>
      expect (decoded == arrayOptionBytesSurface)
        "Loader and Lean command must produce the same Array Option Bytes Source.Program"
      expect (decoded.sourceHash == arrayOptionBytesSurface.sourceHash)
        "Loader and Lean command must produce the same Array Option Bytes sourceHash"
  | .error error => throw <| IO.userError error.render

  let arrayOptionOptionBytesSurface :=
    Tests.Language.ArrayTypesFixture.ArrayOptionOptionBytesSurface
  expect (arrayOptionOptionBytesSurface.state.map (·.type) ==
      #[.array (.option (.option (.bytes 8))) 4])
    "Array Option Option Bytes 8 4 state must survive Lean command elaboration"
  match arrayOptionOptionBytesSurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "ArrayOptionOptionBytesEvent" &&
          eventDecl.params.map (·.type) == #[.array (.option (.option (.bytes 8))) 4])
        "Array Option Option Bytes event must preserve dual length tags"
  | _ => throw <| IO.userError "ArrayOptionOptionBytesSurface must retain event"
  match arrayOptionOptionBytesSurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "ArrayOptionOptionBytesError" &&
          errorDecl.params.map (·.type) == #[.array (.option (.option (.bytes 8))) 4])
        "Array Option Option Bytes error must preserve dual length tags"
  | _ => throw <| IO.userError "ArrayOptionOptionBytesSurface must retain error"
  match arrayOptionOptionBytesSurface.structs with
  | #[limits] =>
      expect (limits.name == "NestedOptionalBlobLimits" &&
          limits.fields.map (·.type) ==
            #[.array (.option (.option (.bytes 0))) 0,
              .array (.option (.option (.bytes 8))) 4,
              .array (.option (.option (.bytes 4096))) 1])
        "Array Option Option Bytes struct fields must preserve 0/0, 8/4, 4096/1"
  | _ => throw <| IO.userError "ArrayOptionOptionBytesSurface must retain one struct"
  match arrayOptionOptionBytesSurface.enums with
  | #[batch] =>
      expect (batch.name == "NestedOptionalBlobBatch" && batch.variants.map (·.payloadTypes) ==
          #[#[.array (.option (.option (.bytes 8))) 4],
            #[.array (.option (.option (.bytes 4096))) 1]])
        "Array Option Option Bytes enum payloads must preserve dual length matrix"
  | _ => throw <| IO.userError "ArrayOptionOptionBytesSurface must retain one enum"
  match arrayOptionOptionBytesSurface.consts with
  | #[emptyConst] =>
      expect (emptyConst.name == "NestedOptionalBlobEmpty" &&
          emptyConst.type == .array (.option (.option (.bytes 0))) 0)
        "Array Option Option Bytes 0 0 const type must survive elaboration"
  | _ => throw <| IO.userError "ArrayOptionOptionBytesSurface must retain const"
  match arrayOptionOptionBytesSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.array (.option (.option (.bytes 8))) 4])
        "Array Option Option Bytes initializer parameter must survive elaboration"
  | none => throw <| IO.userError "ArrayOptionOptionBytesSurface must retain initializer"
  match arrayOptionOptionBytesSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.array (.option (.option (.bytes 8))) 4] &&
          echoEntry.result == .array (.option (.option (.bytes 8))) 4 &&
          getView.result == .array (.option (.option (.bytes 8))) 4 && getView.mode == .view)
        "Array Option Option Bytes entry/view types must survive elaboration"
  | _ => throw <| IO.userError "ArrayOptionOptionBytesSurface must retain echo and get"
  match arrayOptionOptionBytesSurface.functions with
  | #[keepMaximum] =>
      expect (keepMaximum.params.map (·.type) ==
          #[.array (.option (.option (.bytes 4096))) 1] &&
          keepMaximum.result == .array (.option (.option (.bytes 4096))) 1)
        "Array Option Option Bytes 4096 1 fn types must survive elaboration"
  | _ => throw <| IO.userError "ArrayOptionOptionBytesSurface must retain keepMaximum"
  match ← session.selectProgram arrayOptionOptionBytesSurfaceSource
      "<array-option-option-bytes-types>" none with
  | .ok decoded =>
      expect (decoded == arrayOptionOptionBytesSurface)
        "Loader and Lean command must produce the same Array Option Option Bytes Source.Program"
      expect (decoded.sourceHash == arrayOptionOptionBytesSurface.sourceHash)
        "Loader and Lean command must produce the same Array Option Option Bytes sourceHash"
  | .error error => throw <| IO.userError error.render

  let arrayArraySurface := Tests.Language.ArrayTypesFixture.ArrayArraySurface
  expect (arrayArraySurface.state.map (·.type) == #[.array (.array .u64 4) 4])
    "Array Array UInt64 4 4 state must survive Lean command elaboration"
  match arrayArraySurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "NestedMatrixEvent" &&
          eventDecl.params.map (·.type) == #[.array (.array .u64 4) 4])
        "Array Array event parameter must preserve nested Array element and dual lengths"
  | _ => throw <| IO.userError "ArrayArraySurface must retain NestedMatrixEvent"
  match arrayArraySurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "NestedMatrixError" &&
          errorDecl.params.map (·.type) == #[.array (.array .u64 4) 4])
        "Array Array error parameter must preserve nested Array element and dual lengths"
  | _ => throw <| IO.userError "ArrayArraySurface must retain NestedMatrixError"
  match arrayArraySurface.structs with
  | #[limits] =>
      expect (limits.name == "NestedLimits" &&
          limits.fields.map (·.type) ==
            #[.array (.array .u64 0) 0, .array (.array .u64 4) 4,
              .array (.array .u64 4096) 1, .array (.array .bool 0) 0])
        "Array Array struct fields must preserve dual lengths and Bool element"
  | _ => throw <| IO.userError "ArrayArraySurface must retain one struct"
  match arrayArraySurface.enums with
  | #[batch] =>
      expect (batch.name == "NestedBatch" && batch.variants.map (·.payloadTypes) ==
          #[#[.array (.array .u64 4) 4], #[.array (.array .bool 0) 0],
            #[.array (.array .principal 4096) 1]])
        "Array Array enum payloads must preserve element and dual length matrix"
  | _ => throw <| IO.userError "ArrayArraySurface must retain one enum"
  match arrayArraySurface.consts with
  | #[emptyMatrix] =>
      expect (emptyMatrix.name == "EmptyMatrix" && emptyMatrix.type == .array (.array .u64 0) 0)
        "Array Array UInt64 0 0 const type must survive elaboration"
  | _ => throw <| IO.userError "ArrayArraySurface must retain EmptyMatrix"
  match arrayArraySurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.array (.array .u64 4) 4])
        "Array Array initializer parameter must survive elaboration"
  | none => throw <| IO.userError "ArrayArraySurface must retain initializer"
  match arrayArraySurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.array (.array .u64 4) 4] &&
          echoEntry.result == .array (.array .u64 4) 4 &&
          getView.result == .array (.array .u64 4) 4 && getView.mode == .view)
        "Array Array entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "ArrayArraySurface must retain echo and get"
  match arrayArraySurface.functions with
  | #[keepMaximum] =>
      expect (keepMaximum.params.map (·.type) == #[.array (.array .principal 4096) 1] &&
          keepMaximum.result == .array (.array .principal 4096) 1)
        "Array Array Principal 4096 1 fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "ArrayArraySurface must retain keepMaximum"
  match ← session.selectProgram arrayArraySurfaceSource "<array-array-types>" none with
  | .ok decoded =>
      expect (decoded == arrayArraySurface)
        "Loader and Lean command must produce the same Array Array Source.Program"
      expect (decoded.sourceHash == arrayArraySurface.sourceHash)
        "Loader and Lean command must produce the same Array Array sourceHash"
  | .error error => throw <| IO.userError error.render

  let arrayArrayFieldSurface := Tests.Language.ArrayTypesFixture.ArrayArrayFieldSurface
  expect (arrayArrayFieldSurface.state.map (·.type) == #[.array (.array .field 4) 4])
    "Array Array Field bn254_fr 4 4 state must survive Lean command elaboration"
  match arrayArrayFieldSurface.events with
  | #[eventDecl] =>
      expect (eventDecl.name == "NestedFieldMatrixEvent" &&
          eventDecl.params.map (·.type) == #[.array (.array .field 4) 4])
        "Array Array Field event must preserve nested Array/Field tags and dual lengths"
  | _ => throw <| IO.userError "ArrayArrayFieldSurface must retain NestedFieldMatrixEvent"
  match arrayArrayFieldSurface.errors with
  | #[errorDecl] =>
      expect (errorDecl.name == "NestedFieldMatrixError" &&
          errorDecl.params.map (·.type) == #[.array (.array .field 4) 4])
        "Array Array Field error must preserve nested Array/Field tags and dual lengths"
  | _ => throw <| IO.userError "ArrayArrayFieldSurface must retain NestedFieldMatrixError"
  match arrayArrayFieldSurface.structs with
  | #[limits] =>
      expect (limits.name == "NestedFieldLimits" &&
          limits.fields.map (·.type) ==
            #[.array (.array .field 0) 0, .array (.array .field 4) 4,
              .array (.array .field 4096) 1])
        "Array Array Field struct fields must preserve dual lengths 0/0, 4/4, 4096/1"
  | _ => throw <| IO.userError "ArrayArrayFieldSurface must retain one struct"
  match arrayArrayFieldSurface.enums with
  | #[batch] =>
      expect (batch.name == "NestedFieldBatch" && batch.variants.map (·.payloadTypes) ==
          #[#[.array (.array .field 4) 4], #[.array (.array .field 4096) 1]])
        "Array Array Field enum payloads must preserve dual length matrix"
  | _ => throw <| IO.userError "ArrayArrayFieldSurface must retain one enum"
  match arrayArrayFieldSurface.consts with
  | #[emptyMatrix] =>
      expect (emptyMatrix.name == "EmptyFieldMatrix" &&
          emptyMatrix.type == .array (.array .field 0) 0)
        "Array Array Field 0 0 const type must survive elaboration"
  | _ => throw <| IO.userError "ArrayArrayFieldSurface must retain EmptyFieldMatrix"
  match arrayArrayFieldSurface.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.array (.array .field 4) 4])
        "Array Array Field initializer parameter must survive elaboration"
  | none => throw <| IO.userError "ArrayArrayFieldSurface must retain initializer"
  match arrayArrayFieldSurface.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.array (.array .field 4) 4] &&
          echoEntry.result == .array (.array .field 4) 4 &&
          getView.result == .array (.array .field 4) 4 && getView.mode == .view)
        "Array Array Field entry/view parameter and result types must survive elaboration"
  | _ => throw <| IO.userError "ArrayArrayFieldSurface must retain echo and get"
  match arrayArrayFieldSurface.functions with
  | #[keepMaximum] =>
      expect (keepMaximum.params.map (·.type) == #[.array (.array .field 4096) 1] &&
          keepMaximum.result == .array (.array .field 4096) 1)
        "Array Array Field 4096 1 fn parameter/result must survive elaboration"
  | _ => throw <| IO.userError "ArrayArrayFieldSurface must retain keepMaximum"
  match ← session.selectProgram arrayArrayFieldSurfaceSource "<array-array-field-types>" none with
  | .ok decoded =>
      expect (decoded == arrayArrayFieldSurface)
        "Loader and Lean command must produce the same Array Array Field Source.Program"
      expect (decoded.sourceHash == arrayArrayFieldSurface.sourceHash)
        "Loader and Lean command must produce the same Array Array Field sourceHash"
  | .error error => throw <| IO.userError error.render

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


  let arrayOptionOptionSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Option Option UInt64 0", .array (.option (.option .u64)) 0, 251,
      "8892ca6e9b9dfc07d6e5b9cd3e1eb6141a0d5a9285545e88fdf4510436dddad6"),
    ("Array Option Option UInt64 4", .array (.option (.option .u64)) 4, 251,
      "b61a146b5be1bf559c8c93b95d03fe9196dd8ff055c42801ff12cfdb79833fe6"),
    ("Array Option Option UInt64 4096", .array (.option (.option .u64)) 4096, 251,
      "e9e9c741663b977d78a470228883d3d45a8b2cef13c6e5b2760eb25aa81389e1"),
    ("Array Option Option Bool 0", .array (.option (.option .bool)) 0, 251,
      "c5264de4fa8673cacfe0a41ec1531155c5163771459cf8ce8dbc5399c6a0caa7"),
    ("Array Option Option Principal 4096", .array (.option (.option .principal)) 4096, 251,
      "be000b509343817a7f2ff46310d060e6c8e88e665aecd3341ab3b3987d71548e")
  ]
  for (label, type, expectedSize, expectedHash) in arrayOptionOptionSourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag18+tag16+tag16 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  expect ((twin (.array (.option (.option .u64)) 4)).sourceHash !=
        (twin (.array (.option .u64) 4)).sourceHash &&
      (twin (.array (.option (.option .u64)) 4)).sourceHash !=
        (twin (.option (.array (.option .u64) 4))).sourceHash &&
      (twin (.array (.option (.option .u64)) 4)).sourceHash !=
        (twin (.option (.option .u64))).sourceHash &&
      (twin (.array (.option (.option .u64)) 0)).sourceHash !=
        (twin (.array (.option (.option .u64)) 4)).sourceHash &&
      (twin (.array (.option (.option .u64)) 0)).sourceHash !=
        (twin (.array (.option (.option .u64)) 4096)).sourceHash &&
      (twin (.array (.option (.option .u64)) 4)).sourceHash !=
        (twin (.array (.option (.option .u64)) 4096)).sourceHash &&
      (twin (.array (.option (.option .u64)) 0)).sourceHash !=
        (twin (.array (.option (.option .bool)) 0)).sourceHash &&
      (twin (.array (.option (.option .u64)) 4096)).sourceHash !=
        (twin (.array (.option (.option .principal)) 4096)).sourceHash)
    "Array Option Option must bind Array/Option/Option tags, element and complete length payload"

  let arrayOptionOptionSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Option Option UInt64 0", .array (.option (.option .u64)) 0, 200,
      "6de2e7eae903013b49d9bc4971c5dcdcca00dc0165aecb84eb2a33db2476d2e2"),
    ("Array Option Option UInt64 4", .array (.option (.option .u64)) 4, 200,
      "2cd8ce38fdc66f441f7b585a0a9b2809ae3593b72e6a0ef8aaf7a0652f52461b"),
    ("Array Option Option UInt64 4096", .array (.option (.option .u64)) 4096, 200,
      "a2a03629e67d01b46ba099cc5cfd3426ee4e3c8ed8a86da4bb0d63ba8fde6f8e"),
    ("Array Option Option Bool 0", .array (.option (.option .bool)) 0, 201,
      "7a721080c0424521e1ce4766f5c0f0319d2678eea82943059ae858c7e6cee692"),
    ("Array Option Option Principal 4096", .array (.option (.option .principal)) 4096, 200,
      "72e319da48d68103d76d9b349a2255fd8a59f6efe4496c4dcce03b059027c036")
  ]
  for (label, type, expectedSize, expectedHash) in arrayOptionOptionSemanticVectors do
    let compiled ← match Compiler.compile (twin type) with
      | .ok value => pure value
      | .error error =>
          throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (compiled.canonicalBytes.size == expectedSize && compiled.semanticHash == expectedHash)
      s!"{label} semantic tag18+tag16+tag16 golden is unbound: size={compiled.canonicalBytes.size}, hash={compiled.semanticHash}"
  let semanticHashOf (type : Source.ValueType) : IO String := do
    match Compiler.compile (twin type) with
    | .ok value => pure value.semanticHash
    | .error error =>
        throw <| IO.userError s!"semantic non-alias twin must compile: {error.render}"
  let nestedU64Zero ← semanticHashOf (.array (.option (.option .u64)) 0)
  let nestedU64Four ← semanticHashOf (.array (.option (.option .u64)) 4)
  let nestedU64Maximum ← semanticHashOf (.array (.option (.option .u64)) 4096)
  let nestedBoolZero ← semanticHashOf (.array (.option (.option .bool)) 0)
  let nestedPrincipalMaximum ← semanticHashOf (.array (.option (.option .principal)) 4096)
  expect (nestedU64Four != (← semanticHashOf (.array (.option .u64) 4)) &&
      nestedU64Four != (← semanticHashOf (.option (.array (.option .u64) 4))) &&
      nestedU64Four != (← semanticHashOf (.option (.option .u64))) &&
      nestedU64Zero != nestedU64Four &&
      nestedU64Zero != nestedU64Maximum &&
      nestedU64Four != nestedU64Maximum &&
      nestedU64Zero != nestedBoolZero &&
      nestedU64Maximum != nestedPrincipalMaximum)
    "Semantic Array Option Option must bind wrapper depth/order, element and complete length payload"

  let aoofSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Option Option Field bn254_fr 0", .array (.option (.option .field)) 0, 251,
      "908528b873654efaf9dd45b6223fb646ea47fc773844541d0ef46956a24d8ca4"),
    ("Array Option Option Field bn254_fr 4", .array (.option (.option .field)) 4, 251,
      "de7bdfa60b9ba9599b1a52cede5552f3733d7333dfcc0b65f7caa9c2fde2e457"),
    ("Array Option Option Field bn254_fr 4096", .array (.option (.option .field)) 4096, 251,
      "f7e01b5656e2cc833e72fb4a2ab8095e80a968b1573b2cdac50d6a8fa19f17b2")
  ]
  for (label, type, expectedSize, expectedHash) in aoofSourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag18+tag16+tag16+tag2 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  let aoofSourceCanon (type : Source.ValueType) : ByteArray × String :=
    ((twin type).canonicalBytes, (twin type).sourceHash)
  let aoofSourceDistinct (left right : Source.ValueType) (message : String) : IO Unit := do
    let leftPair := aoofSourceCanon left
    let rightPair := aoofSourceCanon right
    expect (leftPair.1 != rightPair.1 && leftPair.2 != rightPair.2) message
  let aoof0 : Source.ValueType := .array (.option (.option .field)) 0
  let aoof4 : Source.ValueType := .array (.option (.option .field)) 4
  let aoofMax : Source.ValueType := .array (.option (.option .field)) 4096
  aoofSourceDistinct aoof0 aoof4
    "Array Option Option Field 0 vs 4 Source must non-alias (bytes+hash)"
  aoofSourceDistinct aoof4 aoofMax
    "Array Option Option Field 4 vs 4096 Source must non-alias (bytes+hash)"
  aoofSourceDistinct aoof0 aoofMax
    "Array Option Option Field 0 vs 4096 Source must non-alias (bytes+hash)"
  aoofSourceDistinct aoof4 (.array (.option .field) 4)
    "Array Option Option Field 4 Source must non-alias Array Option Field 4 (bytes+hash)"
  aoofSourceDistinct aoof4 (.array (.option (.option .u64)) 4)
    "Array Option Option Field 4 Source must non-alias Array Option Option UInt64 4 (bytes+hash)"
  aoofSourceDistinct aoof4 (.option (.option (.array .field 4)))
    "Array Option Option Field 4 Source must non-alias Option Option Array Field 4 (bytes+hash)"
  aoofSourceDistinct aoof4 (.option (.option .field))
    "Array Option Option Field 4 Source must non-alias Option Option Field bn254_fr (bytes+hash)"

  let aoofSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Option Option Field bn254_fr 0", .array (.option (.option .field)) 0, 201,
      "30be1cfa0c542a100b25b9bd43efc5d29be152b88b7a7b02f186f64567694b7b"),
    ("Array Option Option Field bn254_fr 4", .array (.option (.option .field)) 4, 201,
      "58e6e067f5a77d667aab1dbefb8188fa3448a97455f24a014bcab4b8f42895fb"),
    ("Array Option Option Field bn254_fr 4096", .array (.option (.option .field)) 4096, 201,
      "84685c8432ef274b8ab3a7243369a861c549c0278edd8b87d53c68f8924f8af3")
  ]
  for (label, type, expectedSize, expectedHash) in aoofSemanticVectors do
    let compiled ← match Compiler.compile (twin type) with
      | .ok value => pure value
      | .error error =>
          throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (compiled.canonicalBytes.size == expectedSize && compiled.semanticHash == expectedHash)
      s!"{label} semantic tag18+tag16+tag16+tag2 golden is unbound: size={compiled.canonicalBytes.size}, hash={compiled.semanticHash}"
  let aoofSemanticCanon (type : Source.ValueType) : IO (ByteArray × String) := do
    match Compiler.compile (twin type) with
    | .ok value => pure (value.canonicalBytes, value.semanticHash)
    | .error error =>
        throw <| IO.userError
          s!"Array Option Option Field semantic non-alias twin must compile: {error.render}"
  let aoofSemanticDistinct (left right : Source.ValueType) (message : String) : IO Unit := do
    let leftPair ← aoofSemanticCanon left
    let rightPair ← aoofSemanticCanon right
    expect (leftPair.1 != rightPair.1 && leftPair.2 != rightPair.2) message
  aoofSemanticDistinct aoof0 aoof4
    "Array Option Option Field 0 vs 4 Semantic must non-alias (bytes+hash)"
  aoofSemanticDistinct aoof4 aoofMax
    "Array Option Option Field 4 vs 4096 Semantic must non-alias (bytes+hash)"
  aoofSemanticDistinct aoof0 aoofMax
    "Array Option Option Field 0 vs 4096 Semantic must non-alias (bytes+hash)"
  aoofSemanticDistinct aoof4 (.array (.option .field) 4)
    "Array Option Option Field 4 Semantic must non-alias Array Option Field 4 (bytes+hash)"
  aoofSemanticDistinct aoof4 (.array (.option (.option .u64)) 4)
    "Array Option Option Field 4 Semantic must non-alias Array Option Option UInt64 4 (bytes+hash)"
  aoofSemanticDistinct aoof4 (.option (.option (.array .field 4)))
    "Array Option Option Field 4 Semantic must non-alias Option Option Array Field 4 (bytes+hash)"
  aoofSemanticDistinct aoof4 (.option (.option .field))
    "Array Option Option Field 4 Semantic must non-alias Option Option Field bn254_fr (bytes+hash)"

  let arrayFieldSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Field bn254_fr 0", .array .field 0, 247,
      "ca81f1a556dd65993592ae93ba8df3363d63ca4dc2c465cbb3263027cc856b9a"),
    ("Array Field bn254_fr 4", .array .field 4, 247,
      "ed93d99bf36d608229c816a4ebd4e7129cb20cd5fe243bfc5897f360f6b5b690"),
    ("Array Field bn254_fr 4096", .array .field 4096, 247,
      "6fc6c91736ac2a204e9bdedc0ca86e9dba8ade93ee30ec298dce8edcd09694c6")
  ]
  for (label, type, expectedSize, expectedHash) in arrayFieldSourceVectors do
    let sourceProgram := twin type
    unless sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash do
      goldensBound := false
      IO.eprintln
        s!"{label} source: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  expect ((twin (.array .field 0)).sourceHash != (twin .field).sourceHash &&
      (twin (.array .field 0)).sourceHash != (twin (.array .u64 0)).sourceHash &&
      (twin (.array .field 0)).sourceHash != (twin (.option .field)).sourceHash &&
      (twin (.array .field 0)).sourceHash != (twin (.array (.option .u64) 0)).sourceHash &&
      (twin (.array .field 0)).sourceHash != (twin (.array .field 4)).sourceHash)
    "Array Field must bind Array/Field tags and complete length payload"

  let arrayFieldSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Field bn254_fr 0", .array .field 0, 197,
      "17c91204da22dd6116d91f60298307bee5216a96b9a70e7fdca05b9cb78ab14e"),
    ("Array Field bn254_fr 4", .array .field 4, 197,
      "219f5d374027ef6bdfd664b0a58828b8a63cdedd76b23e2020400480de3b94fd"),
    ("Array Field bn254_fr 4096", .array .field 4096, 197,
      "1a9106c9e43bf319c4adf316d7ee31b445f8f764e6f5d7c6ca9c226c9b3bec7e")
  ]
  for (label, type, expectedSize, expectedHash) in arrayFieldSemanticVectors do
    let compiled ← match Compiler.compile (twin type) with
      | .ok value => pure value
      | .error error =>
          throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    unless compiled.canonicalBytes.size == expectedSize && compiled.semanticHash == expectedHash do
      goldensBound := false
      IO.eprintln
        s!"{label} semantic: size={compiled.canonicalBytes.size}, hash={compiled.semanticHash}"
  expect goldensBound "Array Field tag18+tag2 canonical goldens must be bound"

  let arrayBytesSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Bytes 0 0", .array (.bytes 0) 0, 263,
      "38b0e6a7588ed1b2b21b63c39e405a4a369a610b0d38e97a5e88960e10e6a227"),
    ("Array Bytes 32 4", .array (.bytes 32) 4, 263,
      "4553cff0a87ab20cf747cab24d5b517cf05f8862d1120ed27b0f32238ca2209c"),
    ("Array Bytes 4096 1", .array (.bytes 4096) 1, 263,
      "f630aa9d6a1b1f9a9587359de57fc42d307831accb150d9f81a48bb927c95272")
  ]
  for (label, type, expectedSize, expectedHash) in arrayBytesSourceVectors do
    let sourceProgram := twin type
    unless sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash do
      goldensBound := false
      IO.eprintln
        s!"{label} source: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  expect ((twin (.array (.bytes 0) 0)).sourceHash != (twin (.bytes 0)).sourceHash &&
      (twin (.array (.bytes 0) 0)).sourceHash != (twin (.array .u64 0)).sourceHash &&
      (twin (.array (.bytes 0) 0)).sourceHash != (twin (.option (.bytes 0))).sourceHash &&
      (twin (.array (.bytes 0) 0)).sourceHash != (twin (.array .field 0)).sourceHash &&
      (twin (.array (.bytes 0) 0)).sourceHash != (twin (.array (.bytes 32) 0)).sourceHash &&
      (twin (.array (.bytes 0) 0)).sourceHash != (twin (.array (.bytes 0) 4)).sourceHash)
    "Array Bytes must bind Array/Bytes tags and both inner and outer length payloads"

  let arrayBytesSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Bytes 0 0", .array (.bytes 0) 0, 212,
      "0ef6122b555e5316c9bd1ff9168b957968a5166934c69565ac120182f9e4f63f"),
    ("Array Bytes 32 4", .array (.bytes 32) 4, 212,
      "83adee65905a51bbb1447cd0ce3e1deda2e46db91ace73303917f4e6f1a4f06b"),
    ("Array Bytes 4096 1", .array (.bytes 4096) 1, 212,
      "74e2d48c9d062b665c31ddadd671b66994cda58200702515df13e82c8e2183cd")
  ]
  for (label, type, expectedSize, expectedHash) in arrayBytesSemanticVectors do
    let compiled ← match Compiler.compile (twin type) with
      | .ok value => pure value
      | .error error =>
          throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    unless compiled.canonicalBytes.size == expectedSize && compiled.semanticHash == expectedHash do
      goldensBound := false
      IO.eprintln
        s!"{label} semantic: size={compiled.canonicalBytes.size}, hash={compiled.semanticHash}"
  expect goldensBound "Array Bytes tag18+tag17 canonical goldens must be bound"


  let arrayOptionBytesSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Option Bytes 0 0", .array (.option (.bytes 0)) 0, 265,
      "f581d48f1ad258e6048775ff5e49d616da749e0ec14f940d38ecd52023031917"),
    ("Array Option Bytes 8 4", .array (.option (.bytes 8)) 4, 265,
      "b6724eb9c3639b7f829396e0c2541ce529c8124580b3bcd909449a268585ec8b"),
    ("Array Option Bytes 4096 1", .array (.option (.bytes 4096)) 1, 265,
      "3d55918eaaa9e53941e06aeb29ff143d7c2f0370f34befb0fcc5cbdc147f0e13")
  ]
  for (label, type, expectedSize, expectedHash) in arrayOptionBytesSourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag18+tag16+tag17 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  let sourceCanon (type : Source.ValueType) : ByteArray × String :=
    ((twin type).canonicalBytes, (twin type).sourceHash)
  let sourceDistinct (left right : Source.ValueType) (message : String) : IO Unit := do
    let leftPair := sourceCanon left
    let rightPair := sourceCanon right
    expect (leftPair.1 != rightPair.1 && leftPair.2 != rightPair.2) message
  let aob00 : Source.ValueType := .array (.option (.bytes 0)) 0
  let aob84 : Source.ValueType := .array (.option (.bytes 8)) 4
  let aobMax : Source.ValueType := .array (.option (.bytes 4096)) 1
  let aob04 : Source.ValueType := .array (.option (.bytes 0)) 4
  let aob80 : Source.ValueType := .array (.option (.bytes 8)) 0
  let aob48 : Source.ValueType := .array (.option (.bytes 4)) 8
  sourceDistinct aob84 (.array (.bytes 8) 4)
    "Array Option Bytes 8 4 Source must non-alias Array Bytes 8 4 (size+hash)"
  sourceDistinct aob84 (.option (.array (.bytes 8) 4))
    "Array Option Bytes 8 4 Source must non-alias Option Array Bytes 8 4 (size+hash)"
  sourceDistinct aob84 (.array (.option .u64) 4)
    "Array Option Bytes 8 4 Source must non-alias Array Option UInt64 4 (size+hash)"
  sourceDistinct aob84 (.option (.bytes 8))
    "Array Option Bytes 8 4 Source must non-alias Option Bytes 8 (size+hash)"
  sourceDistinct aob00 aob84
    "Array Option Bytes candidates 0/0 vs 8/4 Source must non-alias (size+hash)"
  sourceDistinct aob84 aobMax
    "Array Option Bytes candidates 8/4 vs 4096/1 Source must non-alias (size+hash)"
  sourceDistinct aob00 aobMax
    "Array Option Bytes candidates 0/0 vs 4096/1 Source must non-alias (size+hash)"
  sourceDistinct aob84 aob04
    "Array Option Bytes one-axis inner 8/4 vs 0/4 Source must non-alias (size+hash)"
  sourceDistinct aob84 aob80
    "Array Option Bytes one-axis outer 8/4 vs 8/0 Source must non-alias (size+hash)"
  sourceDistinct aob84 aob48
    "Array Option Bytes dual-length order 8/4 vs 4/8 Source must non-alias (size+hash)"

  let arrayOptionBytesSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Option Bytes 0 0", .array (.option (.bytes 0)) 0, 214,
      "d8b17bcd41e856d3198931c1108cd935a52a57c128ae0185ccd5b704e0867477"),
    ("Array Option Bytes 8 4", .array (.option (.bytes 8)) 4, 214,
      "2a91d6123521921650b3df5367f6be2a7276c4b5a43e0febbb28366e8495bade"),
    ("Array Option Bytes 4096 1", .array (.option (.bytes 4096)) 1, 214,
      "de7da383f867606102e4fc30cd50136de345ff39fc75e4ffa2d614b0559ded59")
  ]
  for (label, type, expectedSize, expectedHash) in arrayOptionBytesSemanticVectors do
    let compiled ← match Compiler.compile (twin type) with
      | .ok value => pure value
      | .error error =>
          throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (compiled.canonicalBytes.size == expectedSize && compiled.semanticHash == expectedHash)
      s!"{label} semantic tag18+tag16+tag17 golden is unbound: size={compiled.canonicalBytes.size}, hash={compiled.semanticHash}"
  let semanticCanon (type : Source.ValueType) : IO (ByteArray × String) := do
    match Compiler.compile (twin type) with
    | .ok value => pure (value.canonicalBytes, value.semanticHash)
    | .error error =>
        throw <| IO.userError s!"semantic non-alias twin must compile: {error.render}"
  let semanticDistinct (left right : Source.ValueType) (message : String) : IO Unit := do
    let (leftBytes, leftHash) ← semanticCanon left
    let (rightBytes, rightHash) ← semanticCanon right
    expect (leftBytes != rightBytes && leftHash != rightHash) message
  semanticDistinct aob84 (.array (.bytes 8) 4)
    "Array Option Bytes 8 4 Semantic must non-alias Array Bytes 8 4 (size+hash)"
  semanticDistinct aob84 (.option (.array (.bytes 8) 4))
    "Array Option Bytes 8 4 Semantic must non-alias Option Array Bytes 8 4 (size+hash)"
  semanticDistinct aob84 (.array (.option .u64) 4)
    "Array Option Bytes 8 4 Semantic must non-alias Array Option UInt64 4 (size+hash)"
  semanticDistinct aob84 (.option (.bytes 8))
    "Array Option Bytes 8 4 Semantic must non-alias Option Bytes 8 (size+hash)"
  semanticDistinct aob00 aob84
    "Array Option Bytes candidates 0/0 vs 8/4 Semantic must non-alias (size+hash)"
  semanticDistinct aob84 aobMax
    "Array Option Bytes candidates 8/4 vs 4096/1 Semantic must non-alias (size+hash)"
  semanticDistinct aob00 aobMax
    "Array Option Bytes candidates 0/0 vs 4096/1 Semantic must non-alias (size+hash)"
  semanticDistinct aob84 aob04
    "Array Option Bytes one-axis inner 8/4 vs 0/4 Semantic must non-alias (size+hash)"
  semanticDistinct aob84 aob80
    "Array Option Bytes one-axis outer 8/4 vs 8/0 Semantic must non-alias (size+hash)"
  semanticDistinct aob84 aob48
    "Array Option Bytes dual-length order 8/4 vs 4/8 Semantic must non-alias (size+hash)"

  let aoobSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Option Option Bytes 0 0", .array (.option (.option (.bytes 0))) 0, 267,
      "630625a53708a089ae2b27a0ed68b755a6d85c8c486dc514a12c4f5b07cef702"),
    ("Array Option Option Bytes 8 4", .array (.option (.option (.bytes 8))) 4, 267,
      "ff9404258d2b06b25e45f9dbd60114a930acc80bd48bfccc95637a4b77cdf603"),
    ("Array Option Option Bytes 4096 1", .array (.option (.option (.bytes 4096))) 1, 267,
      "88879a1bc391c1ce53bd674a05ea10b87f0f7bf57f7adf8767e9353f9b34acd7")
  ]
  for (label, type, expectedSize, expectedHash) in aoobSourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag18+tag16+tag16+tag17 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  let aoob00 : Source.ValueType := .array (.option (.option (.bytes 0))) 0
  let aoob84 : Source.ValueType := .array (.option (.option (.bytes 8))) 4
  let aoobMax : Source.ValueType := .array (.option (.option (.bytes 4096))) 1
  let aoob04 : Source.ValueType := .array (.option (.option (.bytes 0))) 4
  let aoob80 : Source.ValueType := .array (.option (.option (.bytes 8))) 0
  let aoob48 : Source.ValueType := .array (.option (.option (.bytes 4))) 8
  sourceDistinct aoob00 aoob84
    "Array Option Option Bytes candidates 0/0 vs 8/4 Source must non-alias (size+hash)"
  sourceDistinct aoob84 aoobMax
    "Array Option Option Bytes candidates 8/4 vs 4096/1 Source must non-alias (size+hash)"
  sourceDistinct aoob00 aoobMax
    "Array Option Option Bytes candidates 0/0 vs 4096/1 Source must non-alias (size+hash)"
  sourceDistinct aoob84 (.array (.option (.bytes 8)) 4)
    "Array Option Option Bytes 8 4 Source must non-alias Array Option Bytes 8 4 (size+hash)"
  sourceDistinct aoob84 (.array (.option (.option .u64)) 4)
    "Array Option Option Bytes 8 4 Source must non-alias Array Option Option UInt64 4 (size+hash)"
  sourceDistinct aoob84 (.array (.option (.option .field)) 4)
    "Array Option Option Bytes 8 4 Source must non-alias Array Option Option Field bn254_fr 4 (size+hash)"
  sourceDistinct aoob84 (.option (.option (.bytes 8)))
    "Array Option Option Bytes 8 4 Source must non-alias Option Option Bytes 8 (size+hash)"
  sourceDistinct aoob84 (.array (.bytes 8) 4)
    "Array Option Option Bytes 8 4 Source must non-alias Array Bytes 8 4 (size+hash)"
  sourceDistinct aoob84 aoob04
    "Array Option Option Bytes one-axis inner 8/4 vs 0/4 Source must non-alias (size+hash)"
  sourceDistinct aoob84 aoob80
    "Array Option Option Bytes one-axis outer 8/4 vs 8/0 Source must non-alias (size+hash)"
  sourceDistinct aoob84 aoob48
    "Array Option Option Bytes dual-length order 8/4 vs 4/8 Source must non-alias (size+hash)"

  let aoobSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Option Option Bytes 0 0", .array (.option (.option (.bytes 0))) 0, 216,
      "a2f9037cbce3e824b9e0ccae9410a56378d55d98e2a76467e99103f43257234c"),
    ("Array Option Option Bytes 8 4", .array (.option (.option (.bytes 8))) 4, 216,
      "4f7690c3ac3aa52a1f69f91c6523ac22f5fd408eee2a84c2e11312459c327f6f"),
    ("Array Option Option Bytes 4096 1", .array (.option (.option (.bytes 4096))) 1, 216,
      "df59c86ac811fc098e364a0d56b4f5139b640e2f39ac8f9a6b7ff9d48d521b16")
  ]
  for (label, type, expectedSize, expectedHash) in aoobSemanticVectors do
    let compiled ← match Compiler.compile (twin type) with
      | .ok value => pure value
      | .error error =>
          throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (compiled.canonicalBytes.size == expectedSize && compiled.semanticHash == expectedHash)
      s!"{label} semantic tag18+tag16+tag16+tag17 golden is unbound: size={compiled.canonicalBytes.size}, hash={compiled.semanticHash}"
  semanticDistinct aoob00 aoob84
    "Array Option Option Bytes candidates 0/0 vs 8/4 Semantic must non-alias (size+hash)"
  semanticDistinct aoob84 aoobMax
    "Array Option Option Bytes candidates 8/4 vs 4096/1 Semantic must non-alias (size+hash)"
  semanticDistinct aoob00 aoobMax
    "Array Option Option Bytes candidates 0/0 vs 4096/1 Semantic must non-alias (size+hash)"
  semanticDistinct aoob84 (.array (.option (.bytes 8)) 4)
    "Array Option Option Bytes 8 4 Semantic must non-alias Array Option Bytes 8 4 (size+hash)"
  semanticDistinct aoob84 (.array (.option (.option .u64)) 4)
    "Array Option Option Bytes 8 4 Semantic must non-alias Array Option Option UInt64 4 (size+hash)"
  semanticDistinct aoob84 (.array (.option (.option .field)) 4)
    "Array Option Option Bytes 8 4 Semantic must non-alias Array Option Option Field bn254_fr 4 (size+hash)"
  semanticDistinct aoob84 (.option (.option (.bytes 8)))
    "Array Option Option Bytes 8 4 Semantic must non-alias Option Option Bytes 8 (size+hash)"
  semanticDistinct aoob84 (.array (.bytes 8) 4)
    "Array Option Option Bytes 8 4 Semantic must non-alias Array Bytes 8 4 (size+hash)"
  semanticDistinct aoob84 aoob04
    "Array Option Option Bytes one-axis inner 8/4 vs 0/4 Semantic must non-alias (size+hash)"
  semanticDistinct aoob84 aoob80
    "Array Option Option Bytes one-axis outer 8/4 vs 8/0 Semantic must non-alias (size+hash)"
  semanticDistinct aoob84 aoob48
    "Array Option Option Bytes dual-length order 8/4 vs 4/8 Semantic must non-alias (size+hash)"

  let arrayArraySourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Array UInt64 0 0", .array (.array .u64 0) 0, 265, "82bebef7609b3dd4588252e737f8f12e813f43b0d811c607f7ec9b5725d2d1ca"),
    ("Array Array UInt64 4 4", .array (.array .u64 4) 4, 265, "ca15c383708945969f97236fae7778a1a67f7239e898136904b94782d1d17e6b"),
    ("Array Array UInt64 4096 1", .array (.array .u64 4096) 1, 265, "e779fb2145435c85c7dd00e445e3948441a3e37f90d3fdfdf6aba2690a4fef86"),
    ("Array Array Bool 0 0", .array (.array .bool 0) 0, 265, "d41c6c8a10295f2319f75a07fcd6dacfaaec620e261b896289e96afa1dee9c9b")
  ]
  for (label, type, expectedSize, expectedHash) in arrayArraySourceVectors do
    let sourceProgram := twin type
    unless sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash do
      goldensBound := false
      IO.eprintln
        s!"{label} source tag18+tag18 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  expect ((twin (.array (.array .u64 0) 0)).sourceHash != (twin (.array .u64 0)).sourceHash &&
      (twin (.array (.array .u64 0) 0)).sourceHash !=
        (twin (.array (.bytes 0) 0)).sourceHash &&
      (twin (.array (.array .u64 0) 0)).sourceHash !=
        (twin (.array (.array .u64 4) 4)).sourceHash &&
      (twin (.array (.array .u64 0) 0)).sourceHash !=
        (twin (.array (.array .bool 0) 0)).sourceHash &&
      (twin (.array (.array .u64 4) 4)).sourceHash !=
        (twin (.array (.array .u64 4) 1)).sourceHash)
    "Array Array must bind nested Array tags, element and both length payloads"

  let arrayArraySemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Array UInt64 0 0", .array (.array .u64 0) 0, 214, "4c2629b142ef236638be38fe5d2e7bd36dfe5e5fdc5b61ce98d19e375d013822"),
    ("Array Array UInt64 4 4", .array (.array .u64 4) 4, 214, "b5133659b9e12e6cfc436ed96288dba53ec817b46e64444bcaa87b46b27d2f20"),
    ("Array Array UInt64 4096 1", .array (.array .u64 4096) 1, 214, "2bcfee645da388f3e3fb0c936637a85cf21a1128105b2f88d6f239820dc412ca"),
    ("Array Array Bool 0 0", .array (.array .bool 0) 0, 215, "453ce5b5d3e5ada18b2be5e3e5c05962b3cfe2aa3168aee43af5685ecbee333a")
  ]
  for (label, type, expectedSize, expectedHash) in arrayArraySemanticVectors do
    let compiled ← match Compiler.compile (twin type) with
      | .ok value => pure value
      | .error error =>
          throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    unless compiled.canonicalBytes.size == expectedSize && compiled.semanticHash == expectedHash do
      goldensBound := false
      IO.eprintln
        s!"{label} semantic tag18+tag18 golden is unbound: size={compiled.canonicalBytes.size}, hash={compiled.semanticHash}"
  expect goldensBound "Array Array tag18+tag18 canonical goldens must be bound"

  let aafSourceVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Array Field bn254_fr 0 0", .array (.array .field 0) 0, 265,
      "891c549138882df1fdb4da2b494f72dbdbcb508d7e234dbc6290385246fa3cba"),
    ("Array Array Field bn254_fr 4 4", .array (.array .field 4) 4, 265,
      "7540d6061a85b4a08e95ee63d6d78f946fcdc7a3e498038c3057072db4e70ec8"),
    ("Array Array Field bn254_fr 4096 1", .array (.array .field 4096) 1, 265,
      "6b3ba12ac632e0faa5dbf3865bf7586389d12157f5b3bf18bce1816edb2882ea")
  ]
  for (label, type, expectedSize, expectedHash) in aafSourceVectors do
    let sourceProgram := twin type
    expect (sourceProgram.canonicalBytes.size == expectedSize &&
        sourceProgram.sourceHash == expectedHash)
      s!"{label} source tag18+tag18+tag2 golden is unbound: size={sourceProgram.canonicalBytes.size}, hash={sourceProgram.sourceHash}"
  let aafSourceCanon (type : Source.ValueType) : ByteArray × String :=
    ((twin type).canonicalBytes, (twin type).sourceHash)
  let aafSourceDistinct (left right : Source.ValueType) (message : String) : IO Unit := do
    let leftPair := aafSourceCanon left
    let rightPair := aafSourceCanon right
    expect (leftPair.1 != rightPair.1 && leftPair.2 != rightPair.2) message
  let aaf00 : Source.ValueType := .array (.array .field 0) 0
  let aaf44 : Source.ValueType := .array (.array .field 4) 4
  let aafMax : Source.ValueType := .array (.array .field 4096) 1
  let aaf84 : Source.ValueType := .array (.array .field 8) 4
  let aaf04 : Source.ValueType := .array (.array .field 0) 4
  let aaf80 : Source.ValueType := .array (.array .field 8) 0
  let aaf48 : Source.ValueType := .array (.array .field 4) 8
  aafSourceDistinct aaf00 aaf44
    "Array Array Field candidates 0/0 vs 4/4 Source must non-alias (bytes+hash)"
  aafSourceDistinct aaf44 aafMax
    "Array Array Field candidates 4/4 vs 4096/1 Source must non-alias (bytes+hash)"
  aafSourceDistinct aaf00 aafMax
    "Array Array Field candidates 0/0 vs 4096/1 Source must non-alias (bytes+hash)"
  aafSourceDistinct aaf44 (.array (.array .u64 4) 4)
    "Array Array Field 4 4 Source must non-alias Array Array UInt64 4 4 (bytes+hash)"
  aafSourceDistinct aaf44 (.array .field 4)
    "Array Array Field 4 4 Source must non-alias Array Field bn254_fr 4 (bytes+hash)"
  aafSourceDistinct aaf44 (.option (.array .field 4))
    "Array Array Field 4 4 Source must non-alias Option Array Field bn254_fr 4 (bytes+hash)"
  aafSourceDistinct aaf84 aaf04
    "Array Array Field one-axis inner 8/4 vs 0/4 Source must non-alias (bytes+hash)"
  aafSourceDistinct aaf84 aaf80
    "Array Array Field one-axis outer 8/4 vs 8/0 Source must non-alias (bytes+hash)"
  aafSourceDistinct aaf84 aaf48
    "Array Array Field dual-length order 8/4 vs 4/8 Source must non-alias (bytes+hash)"

  let aafSemanticVectors : Array (String × Source.ValueType × Nat × String) := #[
    ("Array Array Field bn254_fr 0 0", .array (.array .field 0) 0, 215,
      "992b1055cefeb34dcd044cec714ed6d9019db98dac7c43d7c814705544cce82f"),
    ("Array Array Field bn254_fr 4 4", .array (.array .field 4) 4, 215,
      "ff74d64876fa3f5949e998d72299740637b0bd82e1347ff3dca1ec6b3e1d02db"),
    ("Array Array Field bn254_fr 4096 1", .array (.array .field 4096) 1, 215,
      "a203fe6bf6462eeefea8b0c61297be5b74116230c21d89903f802a44d6e4c8aa")
  ]
  for (label, type, expectedSize, expectedHash) in aafSemanticVectors do
    let compiled ← match Compiler.compile (twin type) with
      | .ok value => pure value
      | .error error =>
          throw <| IO.userError s!"{label} semantic twin must compile: {error.render}"
    expect (compiled.canonicalBytes.size == expectedSize && compiled.semanticHash == expectedHash)
      s!"{label} semantic tag18+tag18+tag2 golden is unbound: size={compiled.canonicalBytes.size}, hash={compiled.semanticHash}"
  let aafSemanticCanon (type : Source.ValueType) : IO (ByteArray × String) := do
    match Compiler.compile (twin type) with
    | .ok value => pure (value.canonicalBytes, value.semanticHash)
    | .error error =>
        throw <| IO.userError
          s!"Array Array Field semantic non-alias twin must compile: {error.render}"
  let aafSemanticDistinct (left right : Source.ValueType) (message : String) : IO Unit := do
    let leftPair ← aafSemanticCanon left
    let rightPair ← aafSemanticCanon right
    expect (leftPair.1 != rightPair.1 && leftPair.2 != rightPair.2) message
  aafSemanticDistinct aaf00 aaf44
    "Array Array Field candidates 0/0 vs 4/4 Semantic must non-alias (bytes+hash)"
  aafSemanticDistinct aaf44 aafMax
    "Array Array Field candidates 4/4 vs 4096/1 Semantic must non-alias (bytes+hash)"
  aafSemanticDistinct aaf00 aafMax
    "Array Array Field candidates 0/0 vs 4096/1 Semantic must non-alias (bytes+hash)"
  aafSemanticDistinct aaf44 (.array (.array .u64 4) 4)
    "Array Array Field 4 4 Semantic must non-alias Array Array UInt64 4 4 (bytes+hash)"
  aafSemanticDistinct aaf44 (.array .field 4)
    "Array Array Field 4 4 Semantic must non-alias Array Field bn254_fr 4 (bytes+hash)"
  aafSemanticDistinct aaf44 (.option (.array .field 4))
    "Array Array Field 4 4 Semantic must non-alias Option Array Field bn254_fr 4 (bytes+hash)"
  aafSemanticDistinct aaf84 aaf04
    "Array Array Field one-axis inner 8/4 vs 0/4 Semantic must non-alias (bytes+hash)"
  aafSemanticDistinct aaf84 aaf80
    "Array Array Field one-axis outer 8/4 vs 8/0 Semantic must non-alias (bytes+hash)"
  aafSemanticDistinct aaf84 aaf48
    "Array Array Field dual-length order 8/4 vs 4/8 Semantic must non-alias (bytes+hash)"

  for (label, spelling) in [
      ("bare Array", "Array"),
      ("missing Array element", "Array 4"),
      ("missing Array length", "Array UInt64"),
      ("unknown Array element", "Array Mystery 4"),
      ("Field Array element", "Array Field 4"),
      ("alternate Array Field id", "Array Field bls12_381_fr 4"),
      ("escaped Array Field id", "Array Field «bn254_fr» 4"),
      ("qualified Array Field id", "Array Field Curves.bn254_fr 4"),
      ("over-bound Array Field length", "Array Field bn254_fr 4097"),
      ("leading-zero Array Field length", "Array Field bn254_fr 01"),
      ("hex Array Field length", "Array Field bn254_fr 0x10"),
      ("underscore Array Field length", "Array Field bn254_fr 4_096"),
      ("Bytes Array element", "Array Bytes 4"),
      ("missing Array Bytes outer length", "Array Bytes 32"),
      ("over-bound Array Bytes inner length", "Array Bytes 4097 4"),
      ("leading-zero Array Bytes inner length", "Array Bytes 01 4"),
      ("hex Array Bytes inner length", "Array Bytes 0x10 4"),
      ("underscore Array Bytes inner length", "Array Bytes 4_096 4"),
      ("over-bound Array Bytes outer length", "Array Bytes 32 4097"),
      ("leading-zero Array Bytes outer length", "Array Bytes 32 01"),
      ("hex Array Bytes outer length", "Array Bytes 32 0x10"),
      ("underscore Array Bytes outer length", "Array Bytes 32 4_096"),
      ("Option Array element", "Array Option 4"),
      ("unknown Array Option element", "Array Option Mystery 4"),
      ("Field Array Option element", "Array Option Field 4"),
      ("escaped Array Option element", "Array Option «UInt64» 4"),
      ("qualified Array Option element", "Array Option Std.UInt64 4"),
      ("over-bound Array Option length", "Array Option UInt64 4097"),
      ("leading-zero Array Option length", "Array Option UInt64 01"),
      ("hex Array Option length", "Array Option UInt64 0x10"),
      ("underscore Array Option length", "Array Option UInt64 4_096"),
      ("unknown Array Option Option element", "Array Option Option Mystery 4"),
      ("Field Array Option Option element", "Array Option Option Field 4"),
      ("alternate Array Option Option Field id", "Array Option Option Field bls12_381_fr 4"),
      ("escaped Array Option Option Field id", "Array Option Option Field «bn254_fr» 4"),
      ("qualified Array Option Option Field id", "Array Option Option Field Curves.bn254_fr 4"),
      ("over-bound Array Option Option Field length", "Array Option Option Field bn254_fr 4097"),
      ("leading-zero Array Option Option Field length", "Array Option Option Field bn254_fr 01"),
      ("hex Array Option Option Field length", "Array Option Option Field bn254_fr 0x10"),
      ("underscore Array Option Option Field length", "Array Option Option Field bn254_fr 4_096"),
      ("Widget Array Option Option Field leaf", "Array Option Option Widget 4"),
      ("bare Bytes Array Option Option element", "Array Option Option Bytes 4"),
      ("bare Array Array Option Option element", "Array Option Option Array 4"),
      ("bare Option Array Option Option element", "Array Option Option Option 4"),
      ("bare Map Array Option Option element", "Array Option Option Map 4"),
      ("escaped Array Option Option element", "Array Option Option «Bool» 4"),
      ("qualified Array Option Option element", "Array Option Option Std.Bool 4"),
      ("over-bound Array Option Option length", "Array Option Option Bool 4097"),
      ("leading-zero Array Option Option length", "Array Option Option Bool 01"),
      ("hex Array Option Option length", "Array Option Option Bool 0x10"),
      ("underscore Array Option Option length", "Array Option Option Bool 4_096"),
      ("over-bound Array Option Bytes inner length", "Array Option Bytes 4097 4"),
      ("leading-zero Array Option Bytes inner length", "Array Option Bytes 01 4"),
      ("hex Array Option Bytes inner length", "Array Option Bytes 0x10 4"),
      ("underscore Array Option Bytes inner length", "Array Option Bytes 4_096 4"),
      ("over-bound Array Option Bytes outer length", "Array Option Bytes 8 4097"),
      ("leading-zero Array Option Bytes outer length", "Array Option Bytes 8 01"),
      ("hex Array Option Bytes outer length", "Array Option Bytes 8 0x10"),
      ("underscore Array Option Bytes outer length", "Array Option Bytes 8 4_096"),
      ("missing Array Option Bytes outer length", "Array Option Bytes 8"),
      ("Array element", "Array Array 4"),
      ("unknown Array Array element", "Array Array Mystery 4 4"),
      ("Field Array Array element", "Array Array Field 4 4"),
      ("alternate Array Array Field id", "Array Array Field bls12_381_fr 4 4"),
      ("escaped Array Array Field id", "Array Array Field «bn254_fr» 4 4"),
      ("qualified Array Array Field id", "Array Array Field Curves.bn254_fr 4 4"),
      ("over-bound Array Array Field inner length", "Array Array Field bn254_fr 4097 4"),
      ("leading-zero Array Array Field inner length", "Array Array Field bn254_fr 01 4"),
      ("hex Array Array Field inner length", "Array Array Field bn254_fr 0x10 4"),
      ("underscore Array Array Field inner length", "Array Array Field bn254_fr 4_096 4"),
      ("over-bound Array Array Field outer length", "Array Array Field bn254_fr 4 4097"),
      ("leading-zero Array Array Field outer length", "Array Array Field bn254_fr 4 01"),
      ("hex Array Array Field outer length", "Array Array Field bn254_fr 4 0x10"),
      ("underscore Array Array Field outer length", "Array Array Field bn254_fr 4 4_096"),
      ("Widget Array Array Field leaf", "Array Array Widget 4 4"),
      ("bare Bytes Array Array element", "Array Array Bytes 4 4"),
      ("bare Option Array Array element", "Array Array Option 4 4"),
      ("bare Array Array Array element", "Array Array Array 4 4"),
      ("bare Map Array Array element", "Array Array Map 4 4"),
      ("over-bound Array Array inner length", "Array Array UInt64 4097 4"),
      ("leading-zero Array Array inner length", "Array Array UInt64 01 4"),
      ("hex Array Array inner length", "Array Array UInt64 0x10 4"),
      ("underscore Array Array inner length", "Array Array UInt64 4_096 4"),
      ("over-bound Array Array outer length", "Array Array UInt64 4 4097"),
      ("leading-zero Array Array outer length", "Array Array UInt64 4 01"),
      ("hex Array Array outer length", "Array Array UInt64 4 0x10"),
      ("underscore Array Array outer length", "Array Array UInt64 4 4_096"),
      ("qualified Array element", "Array Std.UInt64 4"),
      ("reserved Array element", "Array «const» 4"),
      ("over-bound Array length", "Array UInt64 4097"),
      ("leading-zero Array length", "Array UInt64 01"),
      ("hex Array length", "Array UInt64 0x10"),
      ("underscore Array length", "Array UInt64 4_096")
    ] do
    expectUnsupportedType label
      (← session.parsePrograms (negativeSource "RejectedArrayType" spelling) s!"<array-{label}>")

  let migratedArrayArraySource :=
    negativeSource "MigratedArrayArray" "Array Array UInt64 4 4"
  match ← session.parsePrograms migratedArrayArraySource "<migrated-array-array>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) == #[.array (.array .u64 4) 4])
        "migrated Array Array UInt64 4 4 pin must now parse as existing array(array(u64,4),4)"
  | .ok programs =>
      throw <| IO.userError s!"migrated Array Array UInt64 4 4 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError s!"migrated Array Array UInt64 4 4 must parse: {error.render}"

  let migratedArrayOptionOptionSource :=
    negativeSource "MigratedArrayOptionOption" "Array Option Option Bool 4"
  match ← session.parsePrograms migratedArrayOptionOptionSource "<migrated-array-option-option>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) == #[.array (.option (.option .bool)) 4])
        "migrated Array Option Option Bool 4 pin must now parse as existing array(option(option(bool)),4)"
  | .ok programs =>
      throw <| IO.userError s!"migrated Array Option Option Bool 4 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError s!"migrated Array Option Option Bool 4 must parse: {error.render}"

  let migratedArrayOptionOptionFieldSource :=
    negativeSource "MigratedArrayOptionOptionField" "Array Option Option Field bn254_fr 4"
  match ← session.parsePrograms migratedArrayOptionOptionFieldSource
      "<migrated-array-option-option-field>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) ==
          #[.array (.option (.option .field)) 4])
        "migrated Array Option Option Field bn254_fr 4 pin must now parse as existing array(option(option(field)),4)"
  | .ok programs =>
      throw <| IO.userError
        s!"migrated Array Option Option Field bn254_fr 4 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError
        s!"migrated Array Option Option Field bn254_fr 4 must parse: {error.render}"

  let migratedArrayArrayFieldSource :=
    negativeSource "MigratedArrayArrayField" "Array Array Field bn254_fr 4 4"
  match ← session.parsePrograms migratedArrayArrayFieldSource
      "<migrated-array-array-field>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) ==
          #[.array (.array .field 4) 4])
        "migrated Array Array Field bn254_fr 4 4 pin must now parse as existing array(array(field,4),4)"
  | .ok programs =>
      throw <| IO.userError
        s!"migrated Array Array Field bn254_fr 4 4 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError
        s!"migrated Array Array Field bn254_fr 4 4 must parse: {error.render}"

  let migratedArrayOptionBytesSource :=
    negativeSource "MigratedArrayOptionBytes" "Array Option Bytes 8 4"
  match ← session.parsePrograms migratedArrayOptionBytesSource "<migrated-array-option-bytes>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) == #[.array (.option (.bytes 8)) 4])
        "migrated Array Option Bytes 8 4 pin must now parse as existing array(option(bytes(8)),4)"
  | .ok programs =>
      throw <| IO.userError s!"migrated Array Option Bytes 8 4 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError s!"migrated Array Option Bytes 8 4 must parse: {error.render}"

  let migratedArrayOptionOptionBytesSource :=
    negativeSource "MigratedArrayOptionOptionBytes" "Array Option Option Bytes 8 4"
  match ← session.parsePrograms migratedArrayOptionOptionBytesSource
      "<migrated-array-option-option-bytes>" with
  | .ok #[decodedProgram] =>
      expect (decodedProgram.state.map (·.type) ==
          #[.array (.option (.option (.bytes 8))) 4])
        "migrated Array Option Option Bytes 8 4 pin must parse as array(option(option(bytes(8))),4)"
  | .ok programs =>
      throw <| IO.userError
        s!"migrated Array Option Option Bytes 8 4 produced {programs.size} programs"
  | .error error =>
      throw <| IO.userError
        s!"migrated Array Option Option Bytes 8 4 must parse: {error.render}"

  for (label, name, spelling) in [
      ("over-bound Array Option Option Bytes inner length", "OverBoundAOOBInner",
        "Array Option Option Bytes 4097 4"),
      ("leading-zero Array Option Option Bytes inner length", "LeadingZeroAOOBInner",
        "Array Option Option Bytes 01 4"),
      ("hex Array Option Option Bytes inner length", "HexAOOBInner",
        "Array Option Option Bytes 0x10 4"),
      ("underscore Array Option Option Bytes inner length", "UnderscoreAOOBInner",
        "Array Option Option Bytes 4_096 4"),
      ("over-bound Array Option Option Bytes outer length", "OverBoundAOOBOuter",
        "Array Option Option Bytes 8 4097"),
      ("leading-zero Array Option Option Bytes outer length", "LeadingZeroAOOBOuter",
        "Array Option Option Bytes 8 01"),
      ("hex Array Option Option Bytes outer length", "HexAOOBOuter",
        "Array Option Option Bytes 8 0x10"),
      ("underscore Array Option Option Bytes outer length", "UnderscoreAOOBOuter",
        "Array Option Option Bytes 8 4_096"),
      ("missing Array Option Option Bytes outer length", "MissingOuterAOOB",
        "Array Option Option Bytes 8")
    ] do
    expectUnsupportedType label
      (← session.parsePrograms (negativeSource name spelling) s!"<array-{label}>")

  for (label, spelling) in [
      ("negative Array length", "Array UInt64 -1"),
      ("extra Array payload", "Array UInt64 4 Principal"),
      ("missing Array Field length", "Array Field bn254_fr"),
      ("negative Array Field length", "Array Field bn254_fr -1"),
      ("extra Array Field payload", "Array Field bn254_fr 4 UInt64"),
      ("split Array Field id", "Array Field\n  bn254_fr 4"),
      ("split Array Field length", "Array Field bn254_fr\n  4"),
      ("escaped Array Field constructor", "«Array» Field bn254_fr 4"),
      ("qualified Array Field constructor", "Std.Array Field bn254_fr 4"),
      ("escaped Field constructor in Array", "Array «Field» bn254_fr 4"),
      ("qualified Field constructor in Array", "Array Std.Field bn254_fr 4"),
      ("negative Array Bytes inner length", "Array Bytes -1 4"),
      ("negative Array Bytes outer length", "Array Bytes 32 -1"),
      ("extra Array Bytes payload", "Array Bytes 32 4 UInt64"),
      ("split Array Bytes inner length", "Array Bytes\n  32 4"),
      ("split Array Bytes outer length", "Array Bytes 32\n  4"),
      ("escaped Array Bytes constructor", "«Array» Bytes 32 4"),
      ("qualified Array Bytes constructor", "Std.Array Bytes 32 4"),
      ("escaped Bytes constructor in Array", "Array «Bytes» 32 4"),
      ("qualified Bytes constructor in Array", "Array Std.Bytes 32 4"),
      ("nested Array Array Option element", "Array Option Array UInt64 4 4"),
      ("Map Array Option element", "Array Option Map UInt64 Bool 4"),
      ("missing Array Option Bytes lengths", "Array Option Bytes"),
      ("negative Array Option Bytes inner length", "Array Option Bytes -1 4"),
      ("negative Array Option Bytes outer length", "Array Option Bytes 8 -1"),
      ("extra Array Option Bytes payload", "Array Option Bytes 8 4 Principal"),
      ("split Array Option Bytes inner length", "Array Option Bytes\n  8 4"),
      ("split Array Option Bytes outer length", "Array Option Bytes 8\n  4"),
      ("split Array Option Bytes option", "Array Option\n  Bytes 8 4"),
      ("split Array Option Bytes array", "Array\n  Option Bytes 8 4"),
      ("escaped Array Option Bytes constructor", "«Array» Option Bytes 8 4"),
      ("qualified Array Option Bytes constructor", "Std.Array Option Bytes 8 4"),
      ("escaped Option in Array Option Bytes", "Array «Option» Bytes 8 4"),
      ("qualified Option in Array Option Bytes", "Array Std.Option Bytes 8 4"),
      ("escaped Bytes in Array Option Bytes", "Array Option «Bytes» 8 4"),
      ("qualified Bytes in Array Option Bytes", "Array Option Std.Bytes 8 4"),
      ("missing Array Option Option length", "Array Option Option Bool"),
      ("negative Array Option Option length", "Array Option Option Bool -1"),
      ("extra Array Option Option payload", "Array Option Option Bool 4 Principal"),
      ("missing Array Option Option Field length", "Array Option Option Field bn254_fr"),
      ("negative Array Option Option Field length", "Array Option Option Field bn254_fr -1"),
      ("identifier Array Option Option Field length", "Array Option Option Field bn254_fr N"),
      ("extra Array Option Option Field payload", "Array Option Option Field bn254_fr 4 Principal"),
      ("split Array Option Option Field array", "Array\n  Option Option Field bn254_fr 4"),
      ("split Array Option Option Field outer Option", "Array Option\n  Option Field bn254_fr 4"),
      ("split Array Option Option Field inner Option", "Array Option Option\n  Field bn254_fr 4"),
      ("split Array Option Option Field constructor", "Array Option Option Field\n  bn254_fr 4"),
      ("split Array Option Option Field length", "Array Option Option Field bn254_fr\n  4"),
      ("escaped Array Option Option Field constructor", "«Array» Option Option Field bn254_fr 4"),
      ("qualified Array Option Option Field constructor", "Std.Array Option Option Field bn254_fr 4"),
      ("escaped outer Option Array Option Option Field", "Array «Option» Option Field bn254_fr 4"),
      ("qualified outer Option Array Option Option Field", "Array Std.Option Option Field bn254_fr 4"),
      ("escaped inner Option Array Option Option Field", "Array Option «Option» Field bn254_fr 4"),
      ("qualified inner Option Array Option Option Field", "Array Option Std.Option Field bn254_fr 4"),
      ("escaped Field Array Option Option Field", "Array Option Option «Field» bn254_fr 4"),
      ("qualified Field Array Option Option Field", "Array Option Option Std.Field bn254_fr 4"),
      ("full Array Array Option Option element", "Array Option Option Array UInt64 4 4"),
      ("full Map Array Option Option element", "Array Option Option Map UInt64 Bool 4"),
      ("third Option Array Option Option element", "Array Option Option Option Bool 4"),
      ("missing Array Option Option Bytes lengths", "Array Option Option Bytes"),
      ("negative Array Option Option Bytes inner length", "Array Option Option Bytes -1 4"),
      ("negative Array Option Option Bytes outer length", "Array Option Option Bytes 8 -1"),
      ("identifier Array Option Option Bytes inner length", "Array Option Option Bytes N 4"),
      ("identifier Array Option Option Bytes outer length", "Array Option Option Bytes 8 M"),
      ("extra Array Option Option Bytes payload", "Array Option Option Bytes 8 4 Principal"),
      ("Widget Array Option Option Bytes leaf", "Array Option Option Widget 8 4"),
      ("bare Field Array Option Option Bytes leaf", "Array Option Option Field 8 4"),
      ("bare Option Array Option Option Bytes leaf", "Array Option Option Option 8 4"),
      ("bare Array Array Option Option Bytes leaf", "Array Option Option Array 8 4"),
      ("bare Map Array Option Option Bytes leaf", "Array Option Option Map 8 4"),
      ("split Array Option Option Bytes array", "Array\n  Option Option Bytes 8 4"),
      ("split Array Option Option Bytes outer Option", "Array Option\n  Option Bytes 8 4"),
      ("split Array Option Option Bytes inner Option", "Array Option Option\n  Bytes 8 4"),
      ("split Array Option Option Bytes constructor", "Array Option Option Bytes\n  8 4"),
      ("split Array Option Option Bytes inner length", "Array Option Option Bytes 8\n  4"),
      ("escaped Array Option Option Bytes constructor", "«Array» Option Option Bytes 8 4"),
      ("qualified Array Option Option Bytes constructor", "Std.Array Option Option Bytes 8 4"),
      ("escaped outer Option Array Option Option Bytes", "Array «Option» Option Bytes 8 4"),
      ("qualified outer Option Array Option Option Bytes", "Array Std.Option Option Bytes 8 4"),
      ("escaped inner Option Array Option Option Bytes", "Array Option «Option» Bytes 8 4"),
      ("qualified inner Option Array Option Option Bytes", "Array Option Std.Option Bytes 8 4"),
      ("escaped Bytes Array Option Option Bytes", "Array Option Option «Bytes» 8 4"),
      ("qualified Bytes Array Option Option Bytes", "Array Option Option Std.Bytes 8 4"),
      ("full Field Array Option Option Bytes element", "Array Option Option Field bn254_fr 4 4"),
      ("full Option Array Option Option Bytes element", "Array Option Option Option Bool 4 4"),
      ("full Array Array Option Option Bytes element", "Array Option Option Array UInt64 4 4 4"),
      ("full Map Array Option Option Bytes element", "Array Option Option Map UInt64 Bool 4 4"),
      ("split Array Option Option element", "Array Option Option\n  Bool 4"),
      ("split Array Option Option length", "Array Option Option Bool\n  4"),
      ("split Array Option Option middle", "Array Option\n  Option Bool 4"),
      ("split after Array Option Option", "Array\n  Option Option Bool 4"),
      ("escaped Array Option Option constructor", "«Array» Option Option Bool 4"),
      ("qualified Array Option Option constructor", "Std.Array Option Option Bool 4"),
      ("escaped outer Option in Array Option Option", "Array «Option» Option Bool 4"),
      ("escaped inner Option in Array Option Option", "Array Option «Option» Bool 4"),
      ("qualified outer Option in Array Option Option", "Array Std.Option Option Bool 4"),
      ("qualified inner Option in Array Option Option", "Array Option Std.Option Bool 4"),
      ("negative Array Option length", "Array Option UInt64 -1"),
      ("missing Array Option length", "Array Option UInt64"),
      ("extra Array Option payload", "Array Option UInt64 4 Principal"),
      ("split Array Option element", "Array Option\n  UInt64 4"),
      ("split Array Option length", "Array Option UInt64\n  4"),
      ("escaped Array Option constructor", "«Array» Option UInt64 4"),
      ("qualified Array Option constructor", "Std.Array Option UInt64 4"),
      ("escaped Option constructor in Array", "Array «Option» UInt64 4"),
      ("qualified Option constructor in Array", "Array Std.Option UInt64 4"),
      ("negative Array Array inner length", "Array Array UInt64 -1 4"),
      ("negative Array Array outer length", "Array Array UInt64 4 -1"),
      ("missing Array Array outer length", "Array Array UInt64 4"),
      ("extra Array Array payload", "Array Array UInt64 4 4 Principal"),
      ("missing Array Array Field outer length", "Array Array Field bn254_fr 4"),
      ("missing Array Array Field lengths", "Array Array Field bn254_fr"),
      ("negative Array Array Field inner length", "Array Array Field bn254_fr -1 4"),
      ("negative Array Array Field outer length", "Array Array Field bn254_fr 4 -1"),
      ("identifier Array Array Field inner length", "Array Array Field bn254_fr N 4"),
      ("identifier Array Array Field outer length", "Array Array Field bn254_fr 4 M"),
      ("extra Array Array Field payload", "Array Array Field bn254_fr 4 4 Principal"),
      ("split Array Array Field outer Array", "Array\n  Array Field bn254_fr 4 4"),
      ("split Array Array Field inner Array", "Array Array\n  Field bn254_fr 4 4"),
      ("split Array Array Field constructor", "Array Array Field\n  bn254_fr 4 4"),
      ("split Array Array Field id", "Array Array Field bn254_fr\n  4 4"),
      ("split Array Array Field outer length", "Array Array Field bn254_fr 4\n  4"),
      ("escaped Array Array Field outer constructor", "«Array» Array Field bn254_fr 4 4"),
      ("qualified Array Array Field outer constructor", "Std.Array Array Field bn254_fr 4 4"),
      ("escaped Array Array Field inner constructor", "Array «Array» Field bn254_fr 4 4"),
      ("qualified Array Array Field inner constructor", "Array Std.Array Field bn254_fr 4 4"),
      ("escaped Field Array Array Field", "Array Array «Field» bn254_fr 4 4"),
      ("qualified Field Array Array Field", "Array Array Std.Field bn254_fr 4 4"),
      ("nested Option Array Array element", "Array Array Option Bool 4 4"),
      ("nested Bytes Array Array element", "Array Array Bytes 8 4 4"),
      ("nested Array Array Array element", "Array Array Array UInt64 4 4 4"),
      ("Map Array Array element", "Array Array Map UInt64 Bool 4 4"),
      ("split Array Array element", "Array Array\n  UInt64 4 4"),
      ("split Array Array inner length", "Array Array UInt64\n  4 4"),
      ("split Array Array outer length", "Array Array UInt64 4\n  4"),
      ("escaped Array Array constructor", "«Array» Array UInt64 4 4"),
      ("qualified Array Array constructor", "Std.Array Array UInt64 4 4"),
      ("escaped inner Array constructor", "Array «Array» UInt64 4 4"),
      ("qualified inner Array constructor", "Array Std.Array UInt64 4 4"),
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


  let arrayOptionOptionBoundary ← match Compiler.compile
      Tests.Language.ArrayTypesFixture.ArrayOptionOptionBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"ArrayOptionOptionBoundary must compile: {error.render}"
  expect (arrayOptionOptionBoundary.requirements == #[])
    "Array Option Option UInt64 must recursively propagate zero requirements"
  for target in Targets.phase1 do
    match Targets.checkSupport target arrayOptionOptionBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError
          s!"{target} must support zero-requirement Array Option Option carrier: {error.render}"

  let arrayOptionOptionBoolBoundary ← match Compiler.compile
      Tests.Language.ArrayTypesFixture.ArrayOptionOptionBoolBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"ArrayOptionOptionBoolBoundary must compile: {error.render}"
  expect (arrayOptionOptionBoolBoundary.requirements == #[.boolValues])
    "Array Option Option Bool must recursively propagate boolValues exactly once"
  for target in Targets.phase1 do
    match Targets.checkSupport target arrayOptionOptionBoolBoundary with
    | .error (.unsupportedRequirement .boolValues actual) =>
        expect (actual == target)
          s!"Array Option Option Bool support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError
          s!"Array Option Option Bool/{target} reached wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError
          s!"Array Option Option Bool/{target} unexpectedly passed support"

  let arrayFieldBoundary ← match Compiler.compile
      Tests.Language.ArrayTypesFixture.ArrayFieldBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"ArrayFieldBoundary must compile: {error.render}"
  expect (arrayFieldBoundary.requirements == #[.fieldBn254])
    "Array Field must propagate fieldBn254 exactly once"
  match arrayFieldBoundary.entries with
  | #[echoEntry] =>
      expect (echoEntry.params.map (·.type) == #[.array .field 4] &&
          echoEntry.result == .array .field 4)
        "Source-to-Semantic adaptation must preserve Array Field id and length"
  | _ => throw <| IO.userError "ArrayFieldBoundary must retain one semantic entry"
  for target in Targets.phase1 do
    match Targets.checkSupport target arrayFieldBoundary with
    | .error (.unsupportedRequirement .fieldBn254 actual) =>
        expect (actual == target)
          s!"Array Field support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError s!"Array Field/{target} reached wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError s!"Array Field/{target} unexpectedly passed support"

  let arrayOptionOptionFieldBoundary ← match Compiler.compile
      Tests.Language.ArrayTypesFixture.ArrayOptionOptionFieldBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"ArrayOptionOptionFieldBoundary must compile: {error.render}"
  expect (arrayOptionOptionFieldBoundary.requirements == #[.fieldBn254])
    "Array Option Option Field must recursively propagate fieldBn254 exactly once"
  match arrayOptionOptionFieldBoundary.entries with
  | #[echoEntry] =>
      expect (echoEntry.params.map (·.type) == #[.array (.option (.option .field)) 4] &&
          echoEntry.result == .array (.option (.option .field)) 4)
        "Source-to-Semantic adaptation must preserve Array Option Option Field tags and length"
  | _ => throw <| IO.userError "ArrayOptionOptionFieldBoundary must retain one semantic entry"
  for target in Targets.phase1 do
    match Targets.checkSupport target arrayOptionOptionFieldBoundary with
    | .error (.unsupportedRequirement .fieldBn254 actual) =>
        expect (actual == target)
          s!"Array Option Option Field support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError
          s!"Array Option Option Field/{target} checkSupport wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError
          s!"Array Option Option Field/{target} unexpectedly passed checkSupport"
    match Targets.materializeResult target arrayOptionOptionFieldBoundary with
    | .error (.unsupportedRequirement .fieldBn254 actual) =>
        expect (actual == target)
          s!"Array Option Option Field materialize rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError
          s!"Array Option Option Field/{target} materializeResult wrong failure: {other.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"Array Option Option Field/{target} must not materialize or emit artifact"

  let arrayBytesBoundary ← match Compiler.compile
      Tests.Language.ArrayTypesFixture.ArrayBytesBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"ArrayBytesBoundary must compile: {error.render}"
  expect (arrayBytesBoundary.requirements == #[])
    "Array Bytes must recursively propagate zero requirements"
  match arrayBytesBoundary.entries with
  | #[echoEntry] =>
      expect (echoEntry.params.map (·.type) == #[.array (.bytes 32) 4] &&
          echoEntry.result == .array (.bytes 32) 4)
        "Source-to-Semantic adaptation must preserve Array Bytes inner and outer lengths"
  | _ => throw <| IO.userError "ArrayBytesBoundary must retain one semantic entry"
  for target in Targets.phase1 do
    match Targets.checkSupport target arrayBytesBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError
          s!"{target} must support zero-requirement Array Bytes carrier: {error.render}"


  let arrayOptionBytesBoundary ← match Compiler.compile
      Tests.Language.ArrayTypesFixture.ArrayOptionBytesBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"ArrayOptionBytesBoundary must compile: {error.render}"
  expect (arrayOptionBytesBoundary.requirements == #[])
    "Array Option Bytes must recursively propagate zero requirements"
  for target in Targets.phase1 do
    match Targets.checkSupport target arrayOptionBytesBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError
          s!"{target} must support zero-requirement Array Option Bytes carrier: {error.render}"

  let arrayOptionOptionBytesBoundary ← match Compiler.compile
      Tests.Language.ArrayTypesFixture.ArrayOptionOptionBytesBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"ArrayOptionOptionBytesBoundary must compile: {error.render}"
  expect (arrayOptionOptionBytesBoundary.requirements == #[])
    "Array Option Option Bytes must recursively propagate zero requirements"
  match arrayOptionOptionBytesBoundary.entries with
  | #[echoEntry] =>
      expect (echoEntry.params.map (·.type) == #[.array (.option (.option (.bytes 8))) 4] &&
          echoEntry.result == .array (.option (.option (.bytes 8))) 4)
        "Source-to-Semantic must preserve Array Option Option Bytes dual lengths"
  | _ => throw <| IO.userError "ArrayOptionOptionBytesBoundary must retain one semantic entry"
  for target in Targets.phase1 do
    match Targets.checkSupport target arrayOptionOptionBytesBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError
          s!"{target} must support zero-requirement Array Option Option Bytes carrier: {error.render}"

  let arrayArrayBoundary ← match Compiler.compile
      Tests.Language.ArrayTypesFixture.ArrayArrayBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"ArrayArrayBoundary must compile: {error.render}"
  expect (arrayArrayBoundary.requirements == #[])
    "Array Array UInt64 must recursively propagate zero requirements"
  match arrayArrayBoundary.entries with
  | #[echoEntry] =>
      expect (echoEntry.params.map (·.type) == #[.array (.array .u64 4) 4] &&
          echoEntry.result == .array (.array .u64 4) 4)
        "Source-to-Semantic adaptation must preserve nested Array element and dual lengths"
  | _ => throw <| IO.userError "ArrayArrayBoundary must retain one semantic entry"
  for target in Targets.phase1 do
    match Targets.checkSupport target arrayArrayBoundary with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError
          s!"{target} must support zero-requirement Array Array UInt64 carrier: {error.render}"

  let arrayArrayFieldBoundary ← match Compiler.compile
      Tests.Language.ArrayTypesFixture.ArrayArrayFieldBoundary with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"ArrayArrayFieldBoundary must compile: {error.render}"
  expect (arrayArrayFieldBoundary.requirements == #[.fieldBn254])
    "Array Array Field must recursively propagate fieldBn254 exactly once"
  match arrayArrayFieldBoundary.entries with
  | #[echoEntry] =>
      expect (echoEntry.params.map (·.type) == #[.array (.array .field 4) 4] &&
          echoEntry.result == .array (.array .field 4) 4)
        "Source-to-Semantic adaptation must preserve nested Array Field tags and dual lengths"
  | _ => throw <| IO.userError "ArrayArrayFieldBoundary must retain one semantic entry"
  for target in Targets.phase1 do
    match Targets.checkSupport target arrayArrayFieldBoundary with
    | .error (.unsupportedRequirement .fieldBn254 actual) =>
        expect (actual == target)
          s!"Array Array Field support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError
          s!"Array Array Field/{target} checkSupport wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError
          s!"Array Array Field/{target} unexpectedly passed checkSupport"
    match Targets.materializeResult target arrayArrayFieldBoundary with
    | .error (.unsupportedRequirement .fieldBn254 actual) =>
        expect (actual == target)
          s!"Array Array Field materialize rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError
          s!"Array Array Field/{target} materializeResult wrong failure: {other.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"Array Array Field/{target} must not materialize or emit artifact"

  let arrayArrayBoolBoundary ← match Compiler.compile
      Tests.Language.ArrayTypesFixture.ArrayArrayBoolBoundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"ArrayArrayBoolBoundary must compile: {error.render}"
  expect (arrayArrayBoolBoundary.requirements == #[.boolValues])
    "Array Array Bool must recursively propagate boolValues exactly once"
  for target in Targets.phase1 do
    match Targets.checkSupport target arrayArrayBoolBoundary with
    | .error (.unsupportedRequirement .boolValues actual) =>
        expect (actual == target)
          s!"Array Array Bool support rejection must name {target}, got {actual}"
    | .error other =>
        throw <| IO.userError s!"Array Array Bool/{target} reached wrong failure: {other.render}"
    | .ok () =>
        throw <| IO.userError s!"Array Array Bool/{target} unexpectedly passed support"

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
        "is not UInt64"),
      ("ArrayOptionOptionStateBoundary",
        Tests.Language.ArrayTypesFixture.ArrayOptionOptionStateBoundary,
        "is not UInt64"),
      ("ArrayOptionOptionResultBoundary",
        Tests.Language.ArrayTypesFixture.ArrayOptionOptionResultBoundary,
        "does not return UInt64"),
      ("ArrayOptionOptionParamBoundary",
        Tests.Language.ArrayTypesFixture.ArrayOptionOptionParamBoundary,
        "is not UInt64"),
      ("ArrayBytesStateBoundary",
        Tests.Language.ArrayTypesFixture.ArrayBytesStateBoundary,
        "is not UInt64"),
      ("ArrayBytesResultBoundary",
        Tests.Language.ArrayTypesFixture.ArrayBytesResultBoundary,
        "does not return UInt64"),
      ("ArrayBytesParamBoundary",
        Tests.Language.ArrayTypesFixture.ArrayBytesParamBoundary,
        "is not UInt64"),
      ("ArrayOptionBytesStateBoundary",
        Tests.Language.ArrayTypesFixture.ArrayOptionBytesStateBoundary,
        "is not UInt64"),
      ("ArrayOptionBytesResultBoundary",
        Tests.Language.ArrayTypesFixture.ArrayOptionBytesResultBoundary,
        "does not return UInt64"),
      ("ArrayOptionBytesParamBoundary",
        Tests.Language.ArrayTypesFixture.ArrayOptionBytesParamBoundary,
        "is not UInt64"),
      ("ArrayOptionOptionBytesStateBoundary",
        Tests.Language.ArrayTypesFixture.ArrayOptionOptionBytesStateBoundary,
        "is not UInt64"),
      ("ArrayOptionOptionBytesResultBoundary",
        Tests.Language.ArrayTypesFixture.ArrayOptionOptionBytesResultBoundary,
        "does not return UInt64"),
      ("ArrayOptionOptionBytesParamBoundary",
        Tests.Language.ArrayTypesFixture.ArrayOptionOptionBytesParamBoundary,
        "is not UInt64"),
      ("ArrayArrayStateBoundary",
        Tests.Language.ArrayTypesFixture.ArrayArrayStateBoundary,
        "is not UInt64"),
      ("ArrayArrayResultBoundary",
        Tests.Language.ArrayTypesFixture.ArrayArrayResultBoundary,
        "does not return UInt64"),
      ("ArrayArrayParamBoundary",
        Tests.Language.ArrayTypesFixture.ArrayArrayParamBoundary,
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
