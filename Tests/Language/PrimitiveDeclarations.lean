import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

namespace Tests.Language.PrimitiveDeclarationsFixture

open ProofForgeV2.Language

program BoolCommitment where
  state enabled : Bool

  entry reveal(commitment proof : Bool) : Bool do
    return proof

end Tests.Language.PrimitiveDeclarationsFixture

namespace Tests.Language.PrimitiveDeclarations

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.PrimitiveDeclarationsFixture\n\n" ++
  "program BoolCommitment where\n" ++
  "  state enabled : Bool\n\n" ++
  "  entry reveal(commitment proof : Bool) : Bool do\n" ++
  "    return proof\n\n" ++
  "end Tests.Language.PrimitiveDeclarationsFixture\n"

unsafe def run : IO Unit := do
  let elaborated := Tests.Language.PrimitiveDeclarationsFixture.BoolCommitment
  expect (elaborated.state.map (·.type) == #[.bool])
    "Bool state type must survive Lean command elaboration"
  match elaborated.entries with
  | #[sourceEntry] =>
      expect (sourceEntry.result == .bool)
        "Bool result type must survive Lean command elaboration"
      match sourceEntry.params with
      | #[param] =>
          expect (param.type == .bool && param.visibility == .commitmentOnly)
            "commitment Bool parameter must preserve type and disclosure label"
      | _ => throw <| IO.userError "BoolCommitment must have one parameter"
  | _ => throw <| IO.userError "BoolCommitment must have one entry"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram source "<primitive-declarations>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same Bool/commitment Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same Bool/commitment source hash"
  | .error error => throw <| IO.userError error.render

  let semantic ← match Compiler.compile elaborated with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  expect (semantic.requirements.contains .persistentState)
    "Bool state must still infer persistent-state requirements"
  expect (semantic.requirements.contains .privateWitness)
    "commitment visibility must infer the private-witness requirement"

end Tests.Language.PrimitiveDeclarations
