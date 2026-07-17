import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry

-- WidthSurface covers all 11 integer-width spellings across every declaration
-- position: state (11 widths), struct field, enum payload, initializer parameter,
-- entry/view/fn parameter and result, and const type. Struct/enum/const/fn
-- positions use representative widths only (not 11x each); the shared
-- decodeTypeIdentifiers row set is pinned by state coverage plus the dual
-- frontend parity check.
namespace Tests.Language.IntegerWidthDeclarationsFixture

open ProofForgeV2.Language

program WidthSurface where
  state u8v : UInt8
  state u16v : UInt16
  state u32v : UInt32
  state u128v : UInt128
  state u256v : UInt256
  state i8v : Int8
  state i16v : Int16
  state i32v : Int32
  state i64v : Int64
  state i128v : Int128
  state i256v : Int256

  struct Pair where
    first : UInt8
    second : Int64

  enum Tag where
    | Small(UInt8)
    | Big(Int256)

  const Seed : UInt8 := 0

  init(seed : UInt8) do
    u8v := seed

  entry echo(value : UInt8) : UInt8 do
    return value

  view read() : Int64 do
    return i64v

  fn ident(value : UInt8) : UInt8 do
    return value

end Tests.Language.IntegerWidthDeclarationsFixture

-- WidthBoundary is the minimal boundary program: a single non-UInt64 state plus
-- a view that returns it by reference (no literal, since literals type as UInt64
-- and belong to D2). After GREEN it must compile with zero new requirements and
-- fail each phase1 target at plan time with "is not UInt64", before any artifact.
namespace Tests.Language.IntegerWidthDeclarationsFixture

open ProofForgeV2.Language

program WidthBoundary where
  state value : UInt8

  view get() : UInt8 do
    return value

end Tests.Language.IntegerWidthDeclarationsFixture

namespace Tests.Language.IntegerWidthDeclarations

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Source program twin identical in every field except the state type, so the
canonical/sourceHash delta isolates the width tag (catches tag aliasing and tag
renumbering of UInt64). Same qualified name/name for both widths. -/
private def twin (t : Source.ValueType) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.IntegerWidthDeclarationsFixture.WidthTwin" "WidthTwin" #[
    .stateDecl { name := "value", type := t },
    .entry {
      name := "get"
      params := #[]
      result := .u64
      mode := .view
      body := #[.returnValue (.variable "value")]
    }
  ]

/-- Mutation program identical except the state type; same name so the hash delta
is caused solely by the width/sign tag. -/
private def mutProgram (t : Source.ValueType) : Source.Program :=
  Source.Program.buildQualified "Mut" "Mut" #[
    .stateDecl { name := "v", type := t },
    .entry {
      name := "get"
      params := #[]
      result := .u64
      mode := .view
      body := #[.returnValue (.literal 0)]
    }
  ]

private def source : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.IntegerWidthDeclarationsFixture\n\n" ++
  "program WidthSurface where\n" ++
  "  state u8v : UInt8\n" ++
  "  state u16v : UInt16\n" ++
  "  state u32v : UInt32\n" ++
  "  state u128v : UInt128\n" ++
  "  state u256v : UInt256\n" ++
  "  state i8v : Int8\n" ++
  "  state i16v : Int16\n" ++
  "  state i32v : Int32\n" ++
  "  state i64v : Int64\n" ++
  "  state i128v : Int128\n" ++
  "  state i256v : Int256\n\n" ++
  "  struct Pair where\n" ++
  "    first : UInt8\n" ++
  "    second : Int64\n\n" ++
  "  enum Tag where\n" ++
  "    | Small(UInt8)\n" ++
  "    | Big(Int256)\n\n" ++
  "  const Seed : UInt8 := 0\n\n" ++
  "  init(seed : UInt8) do\n" ++
  "    u8v := seed\n\n" ++
  "  entry echo(value : UInt8) : UInt8 do\n" ++
  "    return value\n\n" ++
  "  view read() : Int64 do\n" ++
  "    return i64v\n\n" ++
  "  fn ident(value : UInt8) : UInt8 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.IntegerWidthDeclarationsFixture\n"

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

unsafe def run : IO Unit := do
  let elaborated := Tests.Language.IntegerWidthDeclarationsFixture.WidthSurface
  expect (elaborated.state.map (·.type) ==
      #[.u8, .u16, .u32, .u128, .u256, .i8, .i16, .i32, .i64, .i128, .i256])
    "all 11 integer width spellings must survive Lean command elaboration in state order"
  match elaborated.structs with
  | #[pair] =>
      expect (pair.name == "Pair" && pair.fields.map (·.type) == #[.u8, .i64])
        "UInt8/Int64 struct field types must survive Lean command elaboration"
  | _ => throw <| IO.userError "WidthSurface must retain one struct declaration"
  match elaborated.enums with
  | #[tag] =>
      expect (tag.name == "Tag" && tag.variants.map (·.payloadTypes) == #[#[.u8], #[.i256]])
        "UInt8/Int256 enum payload types must survive Lean command elaboration"
  | _ => throw <| IO.userError "WidthSurface must retain one enum declaration"
  match elaborated.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.u8])
        "UInt8 initializer parameter type must survive Lean command elaboration"
  | none => throw <| IO.userError "WidthSurface must have an initializer"
  match elaborated.entries with
  | #[echoEntry, readView] =>
      expect (echoEntry.params.map (·.type) == #[.u8] && echoEntry.result == .u8
          && readView.result == .i64 && readView.mode == .view)
        "UInt8 entry parameter/result and Int64 view result must survive Lean command elaboration"
  | _ => throw <| IO.userError "WidthSurface must have echo entry and read view"
  match elaborated.functions with
  | #[identFn] =>
      expect (identFn.params.map (·.type) == #[.u8] && identFn.result == .u8)
        "UInt8 fn parameter/result must survive Lean command elaboration"
  | _ => throw <| IO.userError "WidthSurface must retain the ident fn declaration"
  match elaborated.consts with
  | #[seed] =>
      expect (seed.name == "Seed" && seed.type == .u8)
        "UInt8 const type must survive Lean command elaboration"
  | _ => throw <| IO.userError "WidthSurface must retain the Seed const declaration"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram source "<integer-width-declarations>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same integer-width Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same integer-width source hash"
  | .error error => throw <| IO.userError error.render

  -- Golden: the UInt64 twin's exact sourceHash pins the u64 tag (tag 0). Any
  -- renumbering of the existing u64 tag rewrites this hash and is caught here.
  expect ((twin .u64).sourceHash ==
      "89ce98102d576317548ab26a651ea04a09789f4d15704464434a239eb0865494")
    "UInt64 twin source hash golden must remain stable (u64 tag unchanged)"
  -- Relational: the UInt8 twin must differ from the UInt64 twin, proving the new
  -- width is not aliased onto the existing u64 tag.
  expect ((twin .u8).sourceHash != (twin .u64).sourceHash)
    "UInt8 twin must hash distinctly from the UInt64 twin (no tag aliasing)"
  -- Mutation matrix: width and sign must each bind the hash. Same program name
  -- for both members so the delta is caused solely by the type tag.
  let pairs : Array (Source.ValueType × Source.ValueType) :=
    #[(.u64, .u8), (.u8, .u16), (.u8, .i8), (.i64, .u64)]
  for (a, b) in pairs do
    expect ((mutProgram a).sourceHash != (mutProgram b).sourceHash)
      "integer width/sign must bind the source hash: distinct types must hash distinctly"

  for (label, name, spelling) in [
      ("invalid width", "InvalidUintWidth", "UInt7"),
      ("out-of-range width", "OutOfRangeUintWidth", "UInt512"),
      ("zero width", "ZeroIntWidth", "Int0"),
      ("leading-zero width", "LeadingZeroUintWidth", "UInt064"),
      ("lowercase uint8", "LowercaseUint8", "uint8"),
      ("bare uint", "BareUint", "UInt"),
      ("bare int", "BareInt", "Int"),
      ("escaped uint8", "EscapedUint8", "«UInt8»"),
      ("qualified uint8", "QualifiedUint8", "Std.UInt8"),
      ("uint8 second token", "Uint8SecondToken", "UInt8 bn254_fr")
    ] do
    expectUnsupportedType label
      (← session.parsePrograms (negativeSource name spelling) s!"<int-width-{label}>")

  -- Boundary: the minimal UInt8 program must compile with zero new requirements
  -- (reference return, no literal) and be rejected by every phase1 target at
  -- plan time before any artifact.
  let boundary := Tests.Language.IntegerWidthDeclarationsFixture.WidthBoundary
  let semantic ← match Compiler.compile boundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"WidthBoundary must compile: {error.render}"
  expect (semantic.requirements == #[.persistentState])
    "UInt8 state must contribute only persistent state (zero new requirements)"
  for target in Targets.phase1 do
    match Targets.materializeResult target semantic with
    | .error (.planInvariant _ detail) =>
        expect (detail.contains "is not UInt64")
          s!"{target} must reject non-UInt64 state at plan time with 'is not UInt64'"
    | .error other =>
        throw <| IO.userError s!"{target} must fail with planInvariant, got {other.render}"
    | .ok _ =>
        throw <| IO.userError s!"{target} must not materialize a non-UInt64 state program"

end Tests.Language.IntegerWidthDeclarations
