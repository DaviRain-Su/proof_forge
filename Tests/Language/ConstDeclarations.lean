import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

namespace Tests.Language.ConstDeclarationsFixture

open ProofForgeV2.Language

program ConstSurface where
  const Start : UInt64 := 40
  const Limit : UInt64 := Start + 2
  const Modulus : Field bn254_fr := 7

  entry ping() : UInt64 do
    return 0

end Tests.Language.ConstDeclarationsFixture

namespace Tests.Language.ConstDeclarations

open ProofForgeV2

private def const : Nat := 1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ConstDeclarationsFixture\n\n" ++
  "program ConstSurface where\n" ++
  "  const Start : UInt64 := 40\n" ++
  "  const Limit : UInt64 := Start + 2\n" ++
  "  const Modulus : Field bn254_fr := 7\n\n" ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n\n" ++
  "end Tests.Language.ConstDeclarationsFixture\n"

private def programSource (name declarations : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ declarations ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n"

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
  expect (const == 1)
    "const must remain a legal host Lean identifier outside the ProofForge DSL"

  let elaborated := Tests.Language.ConstDeclarationsFixture.ConstSurface
  match elaborated.consts with
  | #[start, limit, modulus] =>
      expect (start.name == "Start" && start.type == .u64 && start.value == .literal 40)
        "const name, type, and literal value must survive Lean command elaboration"
      expect (limit.name == "Limit" && limit.type == .u64 &&
          limit.value == .checkedAdd (.variable "Start") (.literal 2))
        "const variable/addition expression shape must survive Lean command elaboration"
      expect (modulus.name == "Modulus" && modulus.type == .field &&
          modulus.value == .literal 7)
        "const exact Field type must survive Lean command elaboration"
  | _ => throw <| IO.userError "ConstSurface must retain three const declarations"

  let session ← Language.Loader.ParserSession.create
  let decoded ← select session source "<const-declarations>"
  expect (decoded == elaborated)
    "Loader and Lean command must produce the same const Source.Program"
  expect (decoded.sourceHash == elaborated.sourceHash)
    "Loader and Lean command must produce the same const source hash"

  let base ← select session (programSource "CanonicalConst" "") "<const-base>"
  let constOne ← select session
    (programSource "CanonicalConst" "  const A : UInt64 := 1\n") "<const-one>"
  let constName ← select session
    (programSource "CanonicalConst" "  const B : UInt64 := 1\n") "<const-name>"
  let constType ← select session
    (programSource "CanonicalConst" "  const A : Bool := 1\n") "<const-type>"
  let constLiteral ← select session
    (programSource "CanonicalConst" "  const A : UInt64 := 2\n") "<const-literal>"
  let constVariable ← select session
    (programSource "CanonicalConst" "  const A : UInt64 := input\n") "<const-variable>"
  let constVariableName ← select session
    (programSource "CanonicalConst" "  const A : UInt64 := other\n")
    "<const-variable-name>"
  let constAddAB ← select session
    (programSource "CanonicalConst" "  const A : UInt64 := 1 + 2\n") "<const-add-ab>"
  let constAddBA ← select session
    (programSource "CanonicalConst" "  const A : UInt64 := 2 + 1\n") "<const-add-ba>"
  let constsAB ← select session
    (programSource "CanonicalConst"
      "  const A : UInt64 := 1\n  const B : UInt64 := 2\n")
    "<consts-ab>"
  let constsBA ← select session
    (programSource "CanonicalConst"
      "  const B : UInt64 := 2\n  const A : UInt64 := 1\n")
    "<consts-ba>"

  expect (base.sourceHash != constOne.sourceHash)
    "const presence and array count must bind the source hash"
  expect (constOne.sourceHash != constName.sourceHash &&
      constOne.sourceHash != constType.sourceHash &&
      constOne.sourceHash != constLiteral.sourceHash)
    "const declaration name, type, and literal value must bind the source hash"
  expect (constVariable.sourceHash != constVariableName.sourceHash &&
      constOne.sourceHash != constVariable.sourceHash)
    "const expression kind and variable name must bind the source hash"
  expect (constAddAB.sourceHash != constAddBA.sourceHash &&
      constOne.sourceHash != constAddAB.sourceHash)
    "const expression structure and operand order must bind the source hash"
  expect (constsAB.sourceHash != constsBA.sourceHash &&
      constOne.sourceHash != constsAB.sourceHash)
    "const declaration count and order must bind the source hash"

  expectInvalid "duplicate const declarations"
    "program 'DuplicateConst' contains duplicate const declarations"
    (← session.parsePrograms
      (programSource "DuplicateConst"
        "  const Value : UInt64 := 1\n  const Value : UInt64 := 2\n")
      "<duplicate-const>")
  expectInvalid "enum duplicate precedes const duplicate"
    "program 'PriorityEnumBeforeConst' contains duplicate enum declarations"
    (← session.parsePrograms
      (programSource "PriorityEnumBeforeConst"
        "  enum Choice where\n    | A\n  enum Choice where\n    | B\n  const Value : UInt64 := 1\n  const Value : UInt64 := 2\n")
      "<priority-enum-before-const>")
  expectInvalid "const duplicate precedes initializer parameter duplicate"
    "program 'PriorityConstBeforeInitializerParam' contains duplicate const declarations"
    (← session.parsePrograms
      (programSource "PriorityConstBeforeInitializerParam"
        "  const Value : UInt64 := 1\n  const Value : UInt64 := 2\n  init(value : UInt64, value : UInt64) do\n    return 0\n")
      "<priority-const-before-initializer-param>")
  expectInvalid "escaped const keyword" "unsupported portable program item"
    (← session.parsePrograms
      (programSource "EscapedConstKeyword" "  «const» Value : UInt64 := 1\n")
      "<escaped-const-keyword>")
  expectInvalid "ordinary reserved const identifier" "reserved portable identifier 'const'"
    (← session.parsePrograms
      (programSource "OrdinaryReservedConstIdentifier" "  const const : UInt64 := 1\n")
      "<ordinary-reserved-const-identifier>")
  expectInvalid "escaped reserved const identifier" "reserved portable identifier 'const'"
    (← session.parsePrograms
      (programSource "EscapedReservedConstIdentifier" "  const «const» : UInt64 := 1\n")
      "<escaped-reserved-const-identifier>")
  expectInvalid "reserved const expression" "reserved portable identifier 'const'"
    (← session.parsePrograms
      (programSource "ReservedConstExpression" "  const Value : UInt64 := const\n")
      "<reserved-const-expression>")
  expectInvalid "unknown const type" "unsupported portable type"
    (← session.parsePrograms
      (programSource "UnknownConstType" "  const Value : Unknown := 1\n")
      "<unknown-const-type>")
  expectInvalid "const literal overflow"
    "UInt64 literal is out of range: 18446744073709551616"
    (← session.parsePrograms
      (programSource "ConstLiteralOverflow"
        "  const Value : UInt64 := 18446744073709551616\n")
      "<const-literal-overflow>")

  match Typed.check elaborated with
  | .error (.invalidProgram "const declarations are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"const declarations reached the wrong failure: {other.render}"
  | .ok _ => throw <| IO.userError "Typed.check must not silently erase const declarations"
  match Compiler.compile elaborated with
  | .error (.invalidProgram "const declarations are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"const declarations bypassed the wrong compiler boundary: {other.render}"
  | .ok _ => throw <| IO.userError "Compiler.compile must not bypass const fail-closed checking"

end Tests.Language.ConstDeclarations
