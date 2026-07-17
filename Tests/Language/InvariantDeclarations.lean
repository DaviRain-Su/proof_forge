import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

namespace Tests.Language.InvariantDeclarationsFixture

open ProofForgeV2.Language

program InvariantSurface where
  state count : UInt64

  invariant CountSeen : count
  invariant Offset : count + 1
  invariant Limit : 7

  entry ping() : UInt64 do
    return 0

end Tests.Language.InvariantDeclarationsFixture

namespace Tests.Language.InvariantDeclarations

open ProofForgeV2

private def invariant : Nat := 1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.InvariantDeclarationsFixture\n\n" ++
  "program InvariantSurface where\n" ++
  "  state count : UInt64\n\n" ++
  "  invariant CountSeen : count\n" ++
  "  invariant Offset : count + 1\n" ++
  "  invariant Limit : 7\n\n" ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n\n" ++
  "end Tests.Language.InvariantDeclarationsFixture\n"

private def programSource (name declarations : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ declarations ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n"

private def programWithoutEntrySource (name declarations : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ declarations

private unsafe def select (session : Language.Loader.ParserSession)
    (input path : String) : IO Source.Program := do
  match ← session.selectProgram input path none with
  | .ok sourceProgram => pure sourceProgram
  | .error error => throw <| IO.userError error.render

private def expectInvalid (label expected : String)
    (result : CompileResult (Array Source.Program)) : IO Unit := do
  match result with
  | .error (.invalidProgram actual) =>
      expect (actual == expected)
        s!"{label}: expected invalid-program '{expected}', got '{actual}'"
  | .error other =>
      throw <| IO.userError s!"{label}: expected invalid-program, got {other.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

unsafe def run : IO Unit := do
  expect (invariant == 1)
    "invariant must remain a legal host Lean identifier outside the ProofForge DSL"

  let elaborated := Tests.Language.InvariantDeclarationsFixture.InvariantSurface
  match elaborated.invariants with
  | #[countSeen, offset, limit] =>
      expect (countSeen.name == "CountSeen" && countSeen.predicate == .variable "count")
        "invariant name and variable predicate must survive Lean command elaboration"
      expect (offset.name == "Offset" &&
          offset.predicate == .checkedAdd (.variable "count") (.literal 1))
        "invariant expression constructor and operand order must survive elaboration"
      expect (limit.name == "Limit" && limit.predicate == .literal 7)
        "multiple invariant declarations must retain their source order"
  | _ => throw <| IO.userError "InvariantSurface must retain three invariant declarations"

  let session ← Language.Loader.ParserSession.create
  let decoded ← select session source "<invariant-declarations>"
  expect (decoded == elaborated)
    "Loader and Lean command must produce the same invariant Source.Program"
  expect (decoded.sourceHash == elaborated.sourceHash)
    "Loader and Lean command must produce the same invariant source hash"

  let base ← select session (programSource "CanonicalInvariant" "") "<invariant-base>"
  let invariantOne ← select session
    (programSource "CanonicalInvariant" "  invariant A : 1\n")
    "<invariant-one>"
  let invariantName ← select session
    (programSource "CanonicalInvariant" "  invariant B : 1\n")
    "<invariant-name>"
  let invariantLiteral ← select session
    (programSource "CanonicalInvariant" "  invariant A : 2\n")
    "<invariant-literal>"
  let invariantVariable ← select session
    (programSource "CanonicalInvariant" "  invariant A : value\n")
    "<invariant-variable>"
  let invariantVariableName ← select session
    (programSource "CanonicalInvariant" "  invariant A : other\n")
    "<invariant-variable-name>"
  let invariantAddAB ← select session
    (programSource "CanonicalInvariant" "  invariant A : 1 + 2\n")
    "<invariant-add-ab>"
  let invariantAddBA ← select session
    (programSource "CanonicalInvariant" "  invariant A : 2 + 1\n")
    "<invariant-add-ba>"
  let invariantsAB ← select session
    (programSource "CanonicalInvariant"
      "  invariant A : 1\n  invariant B : value\n")
    "<invariants-ab>"
  let invariantsBA ← select session
    (programSource "CanonicalInvariant"
      "  invariant B : value\n  invariant A : 1\n")
    "<invariants-ba>"

  expect (base.sourceHash != invariantOne.sourceHash &&
      invariantOne.sourceHash != invariantsAB.sourceHash)
    "invariant presence and same-prefix declaration count must bind the source hash"
  expect (invariantOne.sourceHash != invariantName.sourceHash)
    "invariant declaration name must bind the source hash"
  expect (invariantOne.sourceHash != invariantLiteral.sourceHash &&
      invariantOne.sourceHash != invariantVariable.sourceHash &&
      invariantVariable.sourceHash != invariantVariableName.sourceHash)
    "invariant predicate constructor and literal/variable values must bind the source hash"
  expect (invariantOne.sourceHash != invariantAddAB.sourceHash &&
      invariantAddAB.sourceHash != invariantAddBA.sourceHash)
    "invariant predicate structure and operand order must bind the source hash"
  expect (invariantsAB.sourceHash != invariantsBA.sourceHash)
    "invariant declaration order must bind the source hash"

  expectInvalid "invariant does not satisfy the entry/view requirement"
    "program 'InvariantOnly' must declare at least one entry or view"
    (← session.parsePrograms
      (programWithoutEntrySource "InvariantOnly" "  invariant Holds : 1\n")
      "<invariant-only>")
  expectInvalid "duplicate invariant declarations"
    "program 'DuplicateInvariant' contains duplicate invariant declarations"
    (← session.parsePrograms
      (programSource "DuplicateInvariant"
        "  invariant Holds : 1\n  invariant Holds : 2\n")
      "<duplicate-invariant>")
  expectInvalid "fn duplicate precedes invariant duplicate"
    "program 'PriorityFnBeforeInvariant' contains duplicate fn declarations"
    (← session.parsePrograms
      (programSource "PriorityFnBeforeInvariant"
        "  fn helper(value : UInt64) : UInt64 do\n    return value\n  fn helper(other : UInt64) : UInt64 do\n    return other\n  invariant Holds : 1\n  invariant Holds : 2\n")
      "<priority-fn-before-invariant>")
  expectInvalid "invariant duplicate precedes initializer parameter duplicate"
    "program 'PriorityInvariantBeforeInitializerParam' contains duplicate invariant declarations"
    (← session.parsePrograms
      (programSource "PriorityInvariantBeforeInitializerParam"
        "  invariant Holds : 1\n  invariant Holds : 2\n  init(value : UInt64, value : Bool) do\n    return 0\n")
      "<priority-invariant-before-initializer-param>")
  expectInvalid "escaped invariant keyword" "unsupported portable program item"
    (← session.parsePrograms
      (programSource "EscapedInvariantKeyword" "  «invariant» Holds : 1\n")
      "<escaped-invariant-keyword>")
  expectInvalid "ordinary reserved invariant identifier"
    "reserved portable identifier 'invariant'"
    (← session.parsePrograms
      (programSource "OrdinaryReservedInvariantIdentifier"
        "  invariant invariant : 1\n")
      "<ordinary-reserved-invariant-identifier>")
  expectInvalid "escaped reserved invariant identifier"
    "reserved portable identifier 'invariant'"
    (← session.parsePrograms
      (programSource "EscapedReservedInvariantIdentifier"
        "  invariant «invariant» : 1\n")
      "<escaped-reserved-invariant-identifier>")
  expectInvalid "reserved invariant predicate" "reserved portable identifier 'invariant'"
    (← session.parsePrograms
      (programSource "ReservedInvariantPredicate"
        "  invariant Holds : invariant\n")
      "<reserved-invariant-predicate>")
  expectInvalid "invariant literal overflow"
    "UInt64 literal is out of range: 18446744073709551616"
    (← session.parsePrograms
      (programSource "InvariantLiteralOverflow"
        "  invariant Holds : 18446744073709551616\n")
      "<invariant-literal-overflow>")
  expectInvalid "invariant name precedes predicate decoding"
    "reserved portable identifier 'invariant'"
    (← session.parsePrograms
      (programSource "PriorityInvariantNameBeforePredicate"
        "  invariant invariant : 18446744073709551616\n")
      "<priority-invariant-name-before-predicate>")

  match Typed.check elaborated with
  | .error (.invalidProgram "invariant declarations are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError s!"invariant declarations reached the wrong failure: {other.render}"
  | .ok _ => throw <| IO.userError "Typed.check must not silently erase invariant declarations"
  match Compiler.compile elaborated with
  | .error (.invalidProgram "invariant declarations are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError s!"invariant declarations bypassed the wrong compiler boundary: {other.render}"
  | .ok _ => throw <| IO.userError "Compiler.compile must not bypass invariant fail-closed checking"

end Tests.Language.InvariantDeclarations
