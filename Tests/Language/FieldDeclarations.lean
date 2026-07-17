import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry

namespace Tests.Language.FieldDeclarationsFixture

open ProofForgeV2.Language

program FieldIdentity where
  entry identity(private value : Field bn254_fr) : Field bn254_fr do
    return value

end Tests.Language.FieldDeclarationsFixture

namespace Tests.Language.FieldDeclarations

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.FieldDeclarationsFixture\n\n" ++
  "program FieldIdentity where\n" ++
  "  entry identity(private value : Field bn254_fr) : Field bn254_fr do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.FieldDeclarationsFixture\n"

unsafe def run : IO Unit := do
  let elaborated := Tests.Language.FieldDeclarationsFixture.FieldIdentity
  match elaborated.entries with
  | #[sourceEntry] =>
      expect (sourceEntry.result == .field)
        "Field bn254_fr result must survive Lean command elaboration"
      match sourceEntry.params with
      | #[param] =>
          expect (param.type == .field && param.visibility == .proverWitness)
            "Field bn254_fr parameter must preserve its type and private label"
      | _ => throw <| IO.userError "FieldIdentity must have one parameter"
  | _ => throw <| IO.userError "FieldIdentity must have one entry"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram source "<field-declarations>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same Field Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same Field source hash"
  | .error error => throw <| IO.userError error.render

  let semantic ← match Compiler.compile elaborated with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  expect (semantic.requirements == #[.fieldBn254, .privateWitness])
    "Field bn254_fr and private visibility must contribute distinct requirements"
  match Targets.checkSupport .noir semantic with
  | .error (.unsupportedRequirement .fieldBn254 .noir) => pure ()
  | _ => throw <| IO.userError "Noir must reject Field bn254_fr at support resolution before target planning"

end Tests.Language.FieldDeclarations
