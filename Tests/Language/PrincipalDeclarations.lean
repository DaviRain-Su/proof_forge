import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry

namespace Tests.Language.PrincipalDeclarationsFixture

open ProofForgeV2.Language

program PrincipalSurface where
  state owner : Principal

  struct Pair where
    first : Principal
    second : Unit

  enum Tag where
    | Owner(Principal)
    | Empty(Unit)

  const DefaultOwner : Principal := 0

  init(initial : Principal) do
    owner := initial

  entry echo(value : Principal) : Principal do
    return value

  view get() : Principal do
    return owner

  fn ident(value : Principal) : Principal do
    return value

end Tests.Language.PrincipalDeclarationsFixture

namespace Tests.Language.PrincipalDeclarationsFixture

open ProofForgeV2.Language

program PrincipalBoundary where
  entry echo(value : Principal) : Principal do
    return value

end Tests.Language.PrincipalDeclarationsFixture

namespace Tests.Language.PrincipalDeclarationsFixture

open ProofForgeV2.Language

program PrincipalStateBoundary where
  state owner : Principal

  init(initial : Principal) do
    owner := initial

  view get() : Principal do
    return owner

program PrincipalResultBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Principal) : Principal do
    return value

program PrincipalParamBoundary where
  state counter : UInt64

  init(initial : UInt64) do
    counter := initial

  entry echo(value : Principal) : UInt64 do
    return 0

end Tests.Language.PrincipalDeclarationsFixture

namespace Tests.Language.PrincipalDeclarations

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def twin (type : Source.ValueType) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.PrincipalDeclarationsFixture.PrincipalTwin" "PrincipalTwin" #[
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
  "namespace Tests.Language.PrincipalDeclarationsFixture\n\n" ++
  "program PrincipalSurface where\n" ++
  "  state owner : Principal\n\n" ++
  "  struct Pair where\n" ++
  "    first : Principal\n" ++
  "    second : Unit\n\n" ++
  "  enum Tag where\n" ++
  "    | Owner(Principal)\n" ++
  "    | Empty(Unit)\n\n" ++
  "  const DefaultOwner : Principal := 0\n\n" ++
  "  init(initial : Principal) do\n" ++
  "    owner := initial\n\n" ++
  "  entry echo(value : Principal) : Principal do\n" ++
  "    return value\n\n" ++
  "  view get() : Principal do\n" ++
  "    return owner\n\n" ++
  "  fn ident(value : Principal) : Principal do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.PrincipalDeclarationsFixture\n"

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
  let elaborated := Tests.Language.PrincipalDeclarationsFixture.PrincipalSurface
  expect (elaborated.state.map (·.type) == #[.principal])
    "Principal state type must survive Lean command elaboration"
  match elaborated.structs with
  | #[pair] =>
      expect (pair.name == "Pair" && pair.fields.map (·.type) == #[.principal, .unit])
        "Principal/Unit struct field types must survive Lean command elaboration"
  | _ => throw <| IO.userError "PrincipalSurface must retain one struct declaration"
  match elaborated.enums with
  | #[tag] =>
      expect (tag.name == "Tag" &&
          tag.variants.map (·.payloadTypes) == #[#[.principal], #[.unit]])
        "Principal/Unit enum payload types must survive Lean command elaboration"
  | _ => throw <| IO.userError "PrincipalSurface must retain one enum declaration"
  match elaborated.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.principal])
        "Principal initializer parameter must survive Lean command elaboration"
  | none => throw <| IO.userError "PrincipalSurface must have an initializer"
  match elaborated.entries with
  | #[echoEntry, getView] =>
      expect (echoEntry.params.map (·.type) == #[.principal] &&
          echoEntry.result == .principal && getView.result == .principal &&
          getView.mode == .view)
        "Principal entry/view parameters and results must survive elaboration"
  | _ => throw <| IO.userError "PrincipalSurface must retain echo and get"
  match elaborated.functions with
  | #[identFn] =>
      expect (identFn.params.map (·.type) == #[.principal] && identFn.result == .principal)
        "Principal fn parameter/result must survive Lean command elaboration"
  | _ => throw <| IO.userError "PrincipalSurface must retain ident"
  match elaborated.consts with
  | #[defaultOwner] =>
      expect (defaultOwner.name == "DefaultOwner" && defaultOwner.type == .principal)
        "Principal const type must survive Lean command elaboration"
  | _ => throw <| IO.userError "PrincipalSurface must retain DefaultOwner"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<principal-declarations>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same Principal Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same Principal sourceHash"
  | .error error => throw <| IO.userError error.render

  expect ((twin .u64).sourceHash ==
      "a194b458092b540ab8e4de2bb91d8ca32b197968f058c93bb7bbfe934340fbc6")
    "PrincipalTwin UInt64/tag0 sourceHash golden must remain stable"
  expect ((twin .unit).sourceHash ==
      "5770bbff593e607d1eb48567c8d17d973fff62c5f1a6dbb013a0d1aa44d5e793")
    "PrincipalTwin Unit/tag14 sourceHash golden must remain stable"
  expect ((twin .principal).sourceHash ==
      "e7385343712f257d337e738f575d39c5086be34efe807279d1e52dd1a653ffef")
    "PrincipalTwin Principal/tag15 sourceHash golden must remain stable"
  expect ((twin .principal).sourceHash != (twin .unit).sourceHash &&
      (twin .principal).sourceHash != (twin .u64).sourceHash)
    "Principal canonical tag must not alias Unit or UInt64"

  for (label, name, spelling) in [
      ("principal64 spelling", "Principal64Type", "Principal64"),
      ("escaped principal", "EscapedPrincipalType", "«Principal»"),
      ("qualified principal", "QualifiedPrincipalType", "Std.Principal"),
      ("principal second token", "PrincipalSecondToken", "Principal bn254_fr")
    ] do
    expectUnsupportedType label
      (← session.parsePrograms (negativeSource name spelling) s!"<principal-{label}>")

  let boundary := Tests.Language.PrincipalDeclarationsFixture.PrincipalBoundary
  let semantic ← match Compiler.compile boundary with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"PrincipalBoundary must compile: {error.render}"
  expect (semantic.requirements == #[])
    "Principal parameter/result declarations must contribute zero requirements"
  expect (!semantic.requirements.contains .callerContext)
    "Principal declarations must not imply callerContext"
  for target in Targets.phase1 do
    match Targets.checkSupport target semantic with
    | .ok () => pure ()
    | .error error =>
        throw <| IO.userError s!"{target} must support zero-requirement Principal carrier: {error.render}"

  for (label, sourceProgram, needle) in [
      ("PrincipalStateBoundary",
        Tests.Language.PrincipalDeclarationsFixture.PrincipalStateBoundary,
        "is not UInt64"),
      ("PrincipalResultBoundary",
        Tests.Language.PrincipalDeclarationsFixture.PrincipalResultBoundary,
        "does not return UInt64"),
      ("PrincipalParamBoundary",
        Tests.Language.PrincipalDeclarationsFixture.PrincipalParamBoundary,
        "is not UInt64")
    ] do
    let compiled ← match Compiler.compile sourceProgram with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} must compile: {error.render}"
    expect (compiled.requirements == #[.persistentState])
      s!"{label} must contribute only persistentState"
    expect (!compiled.requirements.contains .callerContext)
      s!"{label} must not infer callerContext from Principal declarations"
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

end Tests.Language.PrincipalDeclarations
