import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession
import ProofForgeV2.Targets.Registry

namespace Tests.Language.PrimitiveDeclarationsFixture

open ProofForgeV2.Language

program BoolCommitment where
  state enabled : Bool

  entry reveal(commitment witness : Bool) : Bool do
    return witness

program CommitmentOnly where
  entry reveal(commitment witness : UInt64) : UInt64 do
    return witness

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
  "  entry reveal(commitment witness : Bool) : Bool do\n" ++
  "    return witness\n\n" ++
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

  let session ← Tests.Language.ParserSession.shared
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
  expect (semantic.requirements == #[
      .persistentState, .boolValues, .commitmentDisclosure
    ])
    "Bool and commitment must contribute distinct target-neutral requirements"
  match Targets.checkSupport .evm semantic with
  | .error (.unsupportedRequirement .boolValues .evm) => pure ()
  | _ => throw <| IO.userError "EVM must reject Bool at support resolution before target planning"

  let commitmentOnly ← match Compiler.compile
      Tests.Language.PrimitiveDeclarationsFixture.CommitmentOnly with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  expect (commitmentOnly.requirements == #[.commitmentDisclosure])
    "commitment visibility must not be conflated with a private witness"
  match Targets.checkSupport .noir commitmentOnly with
  | .error (.unsupportedRequirement .commitmentDisclosure .noir) => pure ()
  | _ => throw <| IO.userError "Noir must reject commitment disclosure before target planning"

end Tests.Language.PrimitiveDeclarations
