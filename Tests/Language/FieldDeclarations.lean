import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry

namespace Tests.Language.FieldDeclarationsFixture

open ProofForgeV2.Language

program FieldSurface where
  state scalar : Field bn254_fr

  init(seed : Field bn254_fr) do
    scalar := seed

  entry set(private value : Field bn254_fr) : Field bn254_fr do
    scalar := value
    return scalar

  view get() : Field bn254_fr do
    return scalar

end Tests.Language.FieldDeclarationsFixture

namespace Tests.Language.FieldDeclarations

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.FieldDeclarationsFixture\n\n" ++
  "program FieldSurface where\n" ++
  "  state scalar : Field bn254_fr\n\n" ++
  "  init(seed : Field bn254_fr) do\n" ++
  "    scalar := seed\n\n" ++
  "  entry set(private value : Field bn254_fr) : Field bn254_fr do\n" ++
  "    scalar := value\n" ++
  "    return scalar\n\n" ++
  "  view get() : Field bn254_fr do\n" ++
  "    return scalar\n\n" ++
  "end Tests.Language.FieldDeclarationsFixture\n"

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
  | .error other => throw <| IO.userError s!"{label}: expected exact unsupported-type error, got {other.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

unsafe def run : IO Unit := do
  let elaborated := Tests.Language.FieldDeclarationsFixture.FieldSurface
  expect (elaborated.state.map (·.type) == #[.field])
    "Field bn254_fr state type must survive Lean command elaboration"
  match elaborated.initializer with
  | some initializer =>
      expect (initializer.params.map (·.type) == #[.field])
        "Field bn254_fr initializer type must survive Lean command elaboration"
  | none => throw <| IO.userError "FieldSurface must have an initializer"
  match elaborated.entries with
  | #[setEntry, getEntry] =>
      expect (setEntry.result == .field && getEntry.result == .field)
        "Field bn254_fr entry/view results must survive Lean command elaboration"
      match setEntry.params with
      | #[param] =>
          expect (param.type == .field && param.visibility == .proverWitness)
            "Field bn254_fr parameter must preserve its type and private label"
      | _ => throw <| IO.userError "FieldSurface.set must have one parameter"
  | _ => throw <| IO.userError "FieldSurface must have set and get entries"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram source "<field-declarations>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same Field Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same Field source hash"
  | .error error => throw <| IO.userError error.render

  for (label, name, spelling) in [
      ("escaped constructor", "FieldEscapedConstructor", "«Field» bn254_fr"),
      ("escaped identifier", "FieldEscapedId", "Field «bn254_fr»"),
      ("unknown constructor", "FieldUnknownConstructor", "Scalar bn254_fr"),
      ("alternate identifier", "FieldUnknownId", "Field bls12_381_fr"),
      ("qualified identifier", "FieldQualifiedId", "Field Curves.bn254_fr"),
      ("missing identifier", "FieldMissingId", "Field")
    ] do
    expectUnsupportedType label
      (← session.parsePrograms (negativeSource name spelling) s!"<field-{label}>")

  let semantic ← match Compiler.compile elaborated with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  expect (semantic.requirements == #[
      .persistentState, .fieldBn254, .privateWitness
    ])
    "Field state/type and private visibility must contribute distinct requirements"
  match Targets.checkSupport .noir semantic with
  | .error (.unsupportedRequirement .fieldBn254 .noir) => pure ()
  | _ => throw <| IO.userError "Noir must reject Field bn254_fr at support resolution before target planning"

end Tests.Language.FieldDeclarations
