import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

namespace Tests.Language.FnDeclarationsFixture

open ProofForgeV2.Language

program FnSurface where
  fn addOne(value : UInt64) : UInt64 do
    return value + 1

  fn choose(flag : Bool, scalar : Field bn254_fr) : Bool do
    return flag

  entry ping() : UInt64 do
    return 0

end Tests.Language.FnDeclarationsFixture

namespace Tests.Language.FnDeclarations

open ProofForgeV2

private def fn : Nat := 1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.FnDeclarationsFixture\n\n" ++
  "program FnSurface where\n" ++
  "  fn addOne(value : UInt64) : UInt64 do\n" ++
  "    return value + 1\n\n" ++
  "  fn choose(flag : Bool, scalar : Field bn254_fr) : Bool do\n" ++
  "    return flag\n\n" ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n\n" ++
  "end Tests.Language.FnDeclarationsFixture\n"

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
  expect (fn == 1) "fn must remain a legal host Lean identifier outside the ProofForge DSL"

  let elaborated := Tests.Language.FnDeclarationsFixture.FnSurface
  match elaborated.fns with
  | #[addOne, choose] =>
      expect (addOne.name == "addOne" &&
          addOne.params.map (fun param => (param.name, param.type)) == #[("value", .u64)] &&
          addOne.result == .u64 &&
          addOne.body == #[.returnValue (.checkedAdd (.variable "value") (.literal 1))])
        "fn name, parameters, result, and body must survive Lean command elaboration"
      expect (choose.name == "choose" &&
          choose.params.map (fun param => (param.name, param.type)) ==
            #[("flag", .bool), ("scalar", .field)] &&
          choose.result == .bool && choose.body == #[.returnValue (.variable "flag")])
        "multiple fn signatures and source bodies must retain declaration order"
  | _ => throw <| IO.userError "FnSurface must retain two fn declarations"

  let session ← Language.Loader.ParserSession.create
  let decoded ← select session source "<fn-declarations>"
  expect (decoded == elaborated)
    "Loader and Lean command must produce the same fn Source.Program"
  expect (decoded.sourceHash == elaborated.sourceHash)
    "Loader and Lean command must produce the same fn source hash"

  let base ← select session (programSource "CanonicalFn" "") "<fn-base>"
  let fnOne ← select session
    (programSource "CanonicalFn"
      "  fn A(value : UInt64) : UInt64 do\n    return value\n")
    "<fn-one>"
  let sameSignatureEntry ← select session
    (programSource "CanonicalFn"
      "  entry A(value : UInt64) : UInt64 do\n    return value\n")
    "<fn-same-signature-entry>"
  let fnName ← select session
    (programSource "CanonicalFn"
      "  fn B(value : UInt64) : UInt64 do\n    return value\n")
    "<fn-name>"
  let fnParamName ← select session
    (programSource "CanonicalFn"
      "  fn A(other : UInt64) : UInt64 do\n    return other\n")
    "<fn-param-name>"
  let fnParamType ← select session
    (programSource "CanonicalFn"
      "  fn A(value : Bool) : UInt64 do\n    return 1\n")
    "<fn-param-type>"
  let fnPrivateParam ← select session
    (programSource "CanonicalFn"
      "  fn A(private value : UInt64) : UInt64 do\n    return value\n")
    "<fn-private-param>"
  let fnResult ← select session
    (programSource "CanonicalFn"
      "  fn A(value : UInt64) : Bool do\n    return value\n")
    "<fn-result>"
  let fnBodyLiteral ← select session
    (programSource "CanonicalFn"
      "  fn A(value : UInt64) : UInt64 do\n    return 1\n")
    "<fn-body-literal>"
  let fnBodyAddAB ← select session
    (programSource "CanonicalFn"
      "  fn A(value : UInt64) : UInt64 do\n    return 1 + 2\n")
    "<fn-body-add-ab>"
  let fnBodyAddBA ← select session
    (programSource "CanonicalFn"
      "  fn A(value : UInt64) : UInt64 do\n    return 2 + 1\n")
    "<fn-body-add-ba>"
  let fnBodyCount ← select session
    (programSource "CanonicalFn"
      "  fn A(value : UInt64) : UInt64 do\n    call \"host\"\n    return value\n")
    "<fn-body-count>"
  let fnParamsAB ← select session
    (programSource "CanonicalFn"
      "  fn A(first : UInt64, second : Bool) : UInt64 do\n    return first\n")
    "<fn-params-ab>"
  let fnParamsBA ← select session
    (programSource "CanonicalFn"
      "  fn A(second : Bool, first : UInt64) : UInt64 do\n    return first\n")
    "<fn-params-ba>"
  let fnsAB ← select session
    (programSource "CanonicalFn"
      "  fn A(value : UInt64) : UInt64 do\n    return value\n  fn B(flag : Bool) : Bool do\n    return flag\n")
    "<fns-ab>"
  let fnsBA ← select session
    (programSource "CanonicalFn"
      "  fn B(flag : Bool) : Bool do\n    return flag\n  fn A(value : UInt64) : UInt64 do\n    return value\n")
    "<fns-ba>"

  expect (base.sourceHash != fnOne.sourceHash &&
      fnOne.sourceHash != sameSignatureEntry.sourceHash)
    "fn presence, count, and dedicated declaration kind must bind the source hash"
  expect (fnOne.sourceHash != fnName.sourceHash &&
      fnOne.sourceHash != fnParamName.sourceHash &&
      fnOne.sourceHash != fnParamType.sourceHash &&
      fnOne.sourceHash != fnPrivateParam.sourceHash &&
      fnOne.sourceHash != fnResult.sourceHash)
    "fn name, parameter name/type/visibility, and result must bind the source hash"
  expect (fnOne.sourceHash != fnBodyLiteral.sourceHash &&
      fnOne.sourceHash != fnBodyCount.sourceHash &&
      fnBodyAddAB.sourceHash != fnBodyAddBA.sourceHash)
    "fn body statement count, expression kind/value, and operand order must bind the source hash"
  expect (fnParamsAB.sourceHash != fnParamsBA.sourceHash &&
      fnsAB.sourceHash != fnsBA.sourceHash)
    "fn parameter and declaration order must bind the source hash"

  expectInvalid "duplicate fn declarations"
    "program 'DuplicateFn' contains duplicate fn declarations"
    (← session.parsePrograms
      (programSource "DuplicateFn"
        "  fn helper(value : UInt64) : UInt64 do\n    return value\n  fn helper(other : UInt64) : UInt64 do\n    return other\n")
      "<duplicate-fn>")
  expectInvalid "fn parameter declaration order" "fn 'first' contains duplicate parameters"
    (← session.parsePrograms
      (programSource "DuplicateFnParam"
        "  fn first(value : UInt64, value : Bool) : UInt64 do\n    return 0\n  fn second(other : UInt64, other : Bool) : UInt64 do\n    return 0\n")
      "<duplicate-fn-param>")
  expectInvalid "empty fn body" "fn 'helper' must declare at least one statement"
    (← session.parsePrograms
      (programSource "EmptyFnBody" "  fn helper(value : UInt64) : UInt64 do\n")
      "<empty-fn-body>")
  expectInvalid "escaped fn keyword" "unsupported portable program item"
    (← session.parsePrograms
      (programSource "EscapedFnKeyword"
        "  «fn» helper(value : UInt64) : UInt64 do\n    return value\n")
      "<escaped-fn-keyword>")
  expectInvalid "ordinary reserved fn identifier" "reserved portable identifier 'fn'"
    (← session.parsePrograms
      (programSource "OrdinaryReservedFnIdentifier"
        "  fn fn(value : UInt64) : UInt64 do\n    return value\n")
      "<ordinary-reserved-fn-identifier>")
  expectInvalid "escaped reserved fn identifier" "reserved portable identifier 'fn'"
    (← session.parsePrograms
      (programSource "EscapedReservedFnIdentifier"
        "  fn «fn»(value : UInt64) : UInt64 do\n    return value\n")
      "<escaped-reserved-fn-identifier>")
  expectInvalid "unknown fn result type" "unsupported portable type"
    (← session.parsePrograms
      (programSource "UnknownFnResult"
        "  fn helper(value : UInt64) : Unknown do\n    return value\n")
      "<unknown-fn-result>")
  expectInvalid "fn literal overflow"
    "UInt64 literal is out of range: 18446744073709551616"
    (← session.parsePrograms
      (programSource "FnLiteralOverflow"
        "  fn helper(value : UInt64) : UInt64 do\n    return 18446744073709551616\n")
      "<fn-literal-overflow>")

  match Typed.check elaborated with
  | .error (.invalidProgram "fn declarations are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"fn declarations reached the wrong failure: {other.render}"
  | .ok _ => throw <| IO.userError "Typed.check must not silently erase fn declarations"
  match Compiler.compile elaborated with
  | .error (.invalidProgram "fn declarations are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"fn declarations bypassed the wrong compiler boundary: {other.render}"
  | .ok _ => throw <| IO.userError "Compiler.compile must not bypass fn fail-closed checking"

end Tests.Language.FnDeclarations
