import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry

-- UnitSurface covers exact Unit spelling across every declaration carrier position:
-- state, struct field, enum payload, const type, initializer parameter, and
-- entry/view/fn parameter and result. Omitted return materialization and dual
-- frontend parity are pinned separately below; this surface uses explicit : Unit.
namespace Tests.Language.UnitReturnTypesFixture

open ProofForgeV2.Language

program UnitSurface where
  state flag : Unit

  struct Pair where
    first : Unit
    second : UInt64

  enum Tag where
    | Empty(Unit)
    | Full(UInt64)

  const Seed : Unit := 0

  init(seed : Unit) do
    flag := seed

  entry echo(value : Unit) : Unit do
    return value

  view peek() : Unit do
    return flag

  fn ident(value : Unit) : Unit do
    return value

end Tests.Language.UnitReturnTypesFixture

-- Lean command fixtures for explicit vs omitted return forms. Their qualified
-- names differ (ExplicitUnitReturn vs OmittedUnitReturn); only the two
-- ParserSession source strings below use an identical program/name so that
-- explicit `: Unit` and omitted return materialize to the same Source.Program
-- and sourceHash after GREEN.
namespace Tests.Language.UnitReturnTypesFixture

open ProofForgeV2.Language

program ExplicitUnitReturn where
  entry echo(value : Unit) : Unit do
    return value

  view peek(value : Unit) : Unit do
    return value

  fn ident(value : Unit) : Unit do
    return value

end Tests.Language.UnitReturnTypesFixture

namespace Tests.Language.UnitReturnTypesFixture

open ProofForgeV2.Language

program OmittedUnitReturn where
  entry echo(value : Unit) do
    return value

  view peek(value : Unit) do
    return value

  fn ident(value : Unit) do
    return value

end Tests.Language.UnitReturnTypesFixture

-- UnitBoundary is the minimal stateless program: entry with Unit param, omitted
-- Unit result, body `return value` (no empty return / D2 Unit body semantics).
-- After GREEN it must compile with requirements #[] and pass every phase1
-- checkSupport, proving Unit itself adds zero requirement. It does NOT pin
-- Unit-specific materialize detail: Solana/Near reject earlier for missing
-- initializer/state before any Unit param/result check.
namespace Tests.Language.UnitReturnTypesFixture

open ProofForgeV2.Language

program UnitBoundary where
  entry echo(value : Unit) do
    return value

end Tests.Language.UnitReturnTypesFixture

-- Three stateful programs pin target Plan type boundaries independently. Each
-- carries UInt64 or Unit-matching initializer so Solana/Near reach type checks.
-- After GREEN all compile with #[.persistentState] only (Unit adds zero
-- requirement), pass every phase1 checkSupport, and fail materializeResult with
-- planInvariant before any artifact:
--   UnitStateBoundary  — Unit state → detail contains "is not UInt64"
--   UnitResultBoundary — Unit entry result (omitted) → "does not return UInt64"
--   UnitParamBoundary  — Unit entry param, UInt64 result → "is not UInt64"
-- All four targets check entry result before parameter; the param program uses
-- an explicit UInt64 result so the param check is reachable.
namespace Tests.Language.UnitReturnTypesFixture

open ProofForgeV2.Language

program UnitStateBoundary where
  state value : Unit

  init(initial : Unit) do
    value := initial

  view get() do
    return value

program UnitResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Unit) do
    return value

program UnitParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Unit) : UInt64 do
    return 0

end Tests.Language.UnitReturnTypesFixture

namespace Tests.Language.UnitReturnTypes

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- One-entry echo twin identical except the param/result type, so the
canonical/sourceHash delta isolates the Unit tag (catches tag aliasing and tag
renumbering of UInt64). Same qualified name/name for both types. -/
private def twin (t : Source.ValueType) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.UnitReturnTypesFixture.UnitTwin" "UnitTwin" #[
    .entry {
      name := "echo"
      params := #[{ name := "value", type := t }]
      result := t
      mode := .mutate
      body := #[.returnValue (.variable "value")]
    }
  ]

private def surfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.UnitReturnTypesFixture\n\n" ++
  "program UnitSurface where\n" ++
  "  state flag : Unit\n\n" ++
  "  struct Pair where\n" ++
  "    first : Unit\n" ++
  "    second : UInt64\n\n" ++
  "  enum Tag where\n" ++
  "    | Empty(Unit)\n" ++
  "    | Full(UInt64)\n\n" ++
  "  const Seed : Unit := 0\n\n" ++
  "  init(seed : Unit) do\n" ++
  "    flag := seed\n\n" ++
  "  entry echo(value : Unit) : Unit do\n" ++
  "    return value\n\n" ++
  "  view peek() : Unit do\n" ++
  "    return flag\n\n" ++
  "  fn ident(value : Unit) : Unit do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.UnitReturnTypesFixture\n"

/-- Explicit `: Unit` return forms for entry/view/fn. Paired with omittedSource. -/
private def explicitReturnSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.UnitReturnTypesFixture\n\n" ++
  "program ExplicitUnitReturn where\n" ++
  "  entry echo(value : Unit) : Unit do\n" ++
  "    return value\n\n" ++
  "  view peek(value : Unit) : Unit do\n" ++
  "    return value\n\n" ++
  "  fn ident(value : Unit) : Unit do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.UnitReturnTypesFixture\n"

/-- Omitted return types on entry/view/fn must materialize to Source.ValueType.unit
and, with the same program/name shape as the explicit form, yield identical AST. -/
private def omittedReturnSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.UnitReturnTypesFixture\n\n" ++
  "program ExplicitUnitReturn where\n" ++
  "  entry echo(value : Unit) do\n" ++
  "    return value\n\n" ++
  "  view peek(value : Unit) do\n" ++
  "    return value\n\n" ++
  "  fn ident(value : Unit) do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.UnitReturnTypesFixture\n"

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
  let elaborated := Tests.Language.UnitReturnTypesFixture.UnitSurface
  expect (elaborated.state.map (·.type) == #[.unit])
    "Unit state type must survive Lean command elaboration"
  match elaborated.structs with
  | #[pair] =>
      expect (pair.name == "Pair" && pair.fields.map (·.type) == #[.unit, .u64])
        "Unit/UInt64 struct field types must survive Lean command elaboration"
  | _ => throw <| IO.userError "UnitSurface must retain one struct declaration"
  match elaborated.enums with
  | #[tag] =>
      expect (tag.name == "Tag" && tag.variants.map (·.payloadTypes) == #[#[.unit], #[.u64]])
        "Unit/UInt64 enum payload types must survive Lean command elaboration"
  | _ => throw <| IO.userError "UnitSurface must retain one enum declaration"
  match elaborated.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.unit])
        "Unit initializer parameter type must survive Lean command elaboration"
  | none => throw <| IO.userError "UnitSurface must have an initializer"
  match elaborated.entries with
  | #[echoEntry, peekView] =>
      expect (echoEntry.params.map (·.type) == #[.unit] && echoEntry.result == .unit
          && peekView.result == .unit && peekView.mode == .view)
        "Unit entry parameter/result and Unit view result must survive Lean command elaboration"
  | _ => throw <| IO.userError "UnitSurface must have echo entry and peek view"
  match elaborated.functions with
  | #[identFn] =>
      expect (identFn.params.map (·.type) == #[.unit] && identFn.result == .unit)
        "Unit fn parameter/result must survive Lean command elaboration"
  | _ => throw <| IO.userError "UnitSurface must retain the ident fn declaration"
  match elaborated.consts with
  | #[seed] =>
      expect (seed.name == "Seed" && seed.type == .unit)
        "Unit const type must survive Lean command elaboration"
  | _ => throw <| IO.userError "UnitSurface must retain the Seed const declaration"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<unit-return-types>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same Unit Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same Unit source hash"
  | .error error => throw <| IO.userError error.render

  -- Explicit `: Unit` versus omitted return: identical qualified program/name
  -- shape must yield identical Source.Program and sourceHash (omitted materializes
  -- to Source.ValueType.unit).
  let explicitElaborated := Tests.Language.UnitReturnTypesFixture.ExplicitUnitReturn
  let omittedElaborated := Tests.Language.UnitReturnTypesFixture.OmittedUnitReturn
  expect (explicitElaborated.entries.map (·.result) == #[.unit, .unit])
    "explicit entry/view results must be Source.ValueType.unit"
  expect (omittedElaborated.entries.map (·.result) == #[.unit, .unit])
    "omitted entry/view return types must materialize to Source.ValueType.unit"
  expect (explicitElaborated.functions.map (·.result) == #[.unit])
    "explicit fn result must be Source.ValueType.unit"
  expect (omittedElaborated.functions.map (·.result) == #[.unit])
    "omitted fn return type must materialize to Source.ValueType.unit"
  match ← session.selectProgram explicitReturnSource "<unit-explicit-return>" none with
  | .ok explicitDecoded =>
      expect (explicitDecoded == explicitElaborated)
        "Loader and Lean command must produce the same explicit-Unit-return Source.Program"
      match ← session.selectProgram omittedReturnSource "<unit-omitted-return>" none with
      | .ok omittedDecoded =>
          -- Same program name ExplicitUnitReturn in both sources so identity matches.
          expect (omittedDecoded == explicitDecoded)
            "ParserSession explicit : Unit versus omitted return must yield identical Source.Program"
          expect (omittedDecoded.sourceHash == explicitDecoded.sourceHash)
            "ParserSession explicit : Unit versus omitted return must yield identical sourceHash"
          expect (omittedElaborated.entries.map (·.result) == explicitElaborated.entries.map (·.result)
              && omittedElaborated.functions.map (·.result) ==
                explicitElaborated.functions.map (·.result))
            "Lean command omitted return must match explicit : Unit result carriers"
      | .error error => throw <| IO.userError error.render
  | .error error => throw <| IO.userError error.render

  -- Golden: the UInt64 one-entry echo twin pins the u64 tag (tag 0). Any
  -- renumbering of the existing u64 tag rewrites this hash and is caught here.
  expect ((twin .u64).sourceHash ==
      "91f17e1b7d027ed05cdea72f5d23d48effb6ed981c651eb7318405d1b761b9a1")
    "UInt64 twin source hash golden must remain stable (u64 tag unchanged)"
  -- Golden: Unit/tag14 prospective sourceHash for the same echo twin shape.
  -- Relational inequality below catches tag aliasing onto u64 even if this pin drifts.
  expect ((twin .unit).sourceHash ==
      "6e745638a42bf2a64c004fd001cf3072abb83d2c70a3b285d24966f98ef3a1c8")
    "Unit twin source hash golden must remain stable (Unit tag append-only)"
  -- Relational: the Unit twin must differ from the UInt64 twin, proving the new
  -- type is not aliased onto the existing u64 tag.
  expect ((twin .unit).sourceHash != (twin .u64).sourceHash)
    "Unit twin must hash distinctly from the UInt64 twin (no tag aliasing)"

  for (label, name, spelling) in [
      ("unit64 spelling", "Unit64Type", "Unit64"),
      ("escaped unit", "EscapedUnitType", "«Unit»"),
      ("qualified unit", "QualifiedUnitType", "Std.Unit"),
      ("unit second token", "UnitSecondToken", "Unit bn254_fr")
    ] do
    expectUnsupportedType label
      (← session.parsePrograms (negativeSource name spelling) s!"<unit-{label}>")

  -- Stateless support boundary only: prove Unit adds zero requirement. No
  -- materialize assertion (Solana/Near reject earlier for missing init/state).
  let boundary := Tests.Language.UnitReturnTypesFixture.UnitBoundary
  let semantic ← match Compiler.compile boundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"UnitBoundary must compile: {error.render}"
  expect (semantic.requirements == #[])
    "Unit param/result must contribute zero requirements"
  for target in Targets.phase1 do
    match Targets.checkSupport target semantic with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError s!"{target} checkSupport must accept zero-requirement UnitBoundary, got {error.render}"

  -- Stateful Plan matrix: independently pin Unit state / result / param.
  -- Each row expects #[.persistentState] (Unit itself adds nothing), support ok,
  -- and planInvariant detail containing the row needle before any artifact.
  for (label, sourceProgram, needle) in [
      ("UnitStateBoundary",
        Tests.Language.UnitReturnTypesFixture.UnitStateBoundary,
        "is not UInt64"),
      ("UnitResultBoundary",
        Tests.Language.UnitReturnTypesFixture.UnitResultBoundary,
        "does not return UInt64"),
      ("UnitParamBoundary",
        Tests.Language.UnitReturnTypesFixture.UnitParamBoundary,
        "is not UInt64")
    ] do
    let compiled ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} must compile: {error.render}"
    expect (compiled.requirements == #[.persistentState])
      s!"{label} must contribute only persistentState (Unit adds zero requirements)"
    for target in Targets.phase1 do
      match Targets.checkSupport target compiled with
      | .ok () => pure ()
      | .error error =>
          throw <| IO.userError s!"{label}/{target} checkSupport must accept, got {error.render}"
      match Targets.materializeResult target compiled with
      | .error (.planInvariant _ detail) =>
          expect (detail.contains needle)
            s!"{label}/{target} must fail planInvariant containing '{needle}', got {detail}"
      | .error other =>
          throw <| IO.userError s!"{label}/{target} must fail with planInvariant, got {other.render}"
      | .ok _ =>
          throw <| IO.userError s!"{label}/{target} must not materialize before planInvariant"

end Tests.Language.UnitReturnTypes
