import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

namespace Tests.Language.FnDeclarationsFixture

open ProofForgeV2.Language

program FnSurface where
  init() do
    return 0

  fn addOne(value : UInt64) : UInt64 do
    return value + 1

  entry ping() : UInt64 do
    return 0

  fn choose(flag : Bool, scalar : Field bn254_fr) : Bool do
    return flag

  view peek() : UInt64 do
    return 0

  fn identity(value : UInt64) : UInt64 do
    return value

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
  "  init() do\n" ++
  "    return 0\n\n" ++
  "  fn addOne(value : UInt64) : UInt64 do\n" ++
  "    return value + 1\n\n" ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n\n" ++
  "  fn choose(flag : Bool, scalar : Field bn254_fr) : Bool do\n" ++
  "    return flag\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    return 0\n\n" ++
  "  fn identity(value : UInt64) : UInt64 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.FnDeclarationsFixture\n"

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
  expect (fn == 1) "fn must remain a legal host Lean identifier outside the ProofForge DSL"

  let elaborated := Tests.Language.FnDeclarationsFixture.FnSurface
  expect (elaborated.initializer == some {
      params := #[]
      body := #[.returnValue (.literal 0)] })
    "an initializer followed by fn must retain its exact body"
  match elaborated.functions with
  | #[addOne, choose, identity] =>
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
      expect (identity.name == "identity" &&
          identity.params.map (fun param => (param.name, param.type)) == #[("value", .u64)] &&
          identity.result == .u64 && identity.body == #[.returnValue (.variable "value")])
        "a view followed by fn must retain the fn declaration"
  | _ => throw <| IO.userError "FnSurface must retain three fn declarations"

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
  let fnParamBindingBase ← select session
    (programSource "CanonicalFn"
      "  fn A(value : UInt64) : UInt64 do\n    return 1\n")
    "<fn-param-binding-base>"
  let fnParamNameOnly ← select session
    (programSource "CanonicalFn"
      "  fn A(other : UInt64) : UInt64 do\n    return 1\n")
    "<fn-param-name-only>"
  let fnParamTypeOnly ← select session
    (programSource "CanonicalFn"
      "  fn A(value : Bool) : UInt64 do\n    return 1\n")
    "<fn-param-type-only>"
  let fnPrivateParam ← select session
    (programSource "CanonicalFn"
      "  fn A(private value : UInt64) : UInt64 do\n    return value\n")
    "<fn-private-param>"
  let fnPublicParam ← select session
    (programSource "CanonicalFn"
      "  fn A(public value : UInt64) : UInt64 do\n    return value\n")
    "<fn-public-param>"
  let fnCommitmentParam ← select session
    (programSource "CanonicalFn"
      "  fn A(commitment value : UInt64) : UInt64 do\n    return value\n")
    "<fn-commitment-param>"
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
  let fnCallA ← select session
    (programSource "CanonicalFn"
      "  fn A(value : UInt64) : UInt64 do\n    call \"host-a\"\n    return value\n")
    "<fn-call-a>"
  let fnCallB ← select session
    (programSource "CanonicalFn"
      "  fn A(value : UInt64) : UInt64 do\n    call \"host-b\"\n    return value\n")
    "<fn-call-b>"
  let fnParamsAB ← select session
    (programSource "CanonicalFn"
      "  fn A(first : UInt64, second : Bool) : UInt64 do\n    return first\n")
    "<fn-params-ab>"
  let fnParamsBA ← select session
    (programSource "CanonicalFn"
      "  fn A(second : Bool, first : UInt64) : UInt64 do\n    return first\n")
    "<fn-params-ba>"
  let fnParamCount ← select session
    (programSource "CanonicalFn"
      "  fn A(value : UInt64, extra : Bool) : UInt64 do\n    return value\n")
    "<fn-param-count>"
  let fnBodyOrderAB ← select session
    (programSource "CanonicalFn"
      "  fn A(value : UInt64) : UInt64 do\n    call \"host\"\n    return value\n")
    "<fn-body-order-ab>"
  let fnBodyOrderBA ← select session
    (programSource "CanonicalFn"
      "  fn A(value : UInt64) : UInt64 do\n    return value\n    call \"host\"\n")
    "<fn-body-order-ba>"
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
  expect (fnOne.canonicalBytes != sameSignatureEntry.canonicalBytes)
    "fn and entry declarations with the same signature/body must have different canonical bytes"
  expect (fnOne.sourceHash != fnName.sourceHash &&
      fnOne.sourceHash != fnParamName.sourceHash &&
      fnOne.sourceHash != fnParamType.sourceHash &&
      fnOne.sourceHash != fnResult.sourceHash)
    "fn name, parameter name/type, and result must bind the source hash"
  expect (fnParamBindingBase.sourceHash != fnParamNameOnly.sourceHash &&
      fnParamBindingBase.sourceHash != fnParamTypeOnly.sourceHash)
    "fn parameter name and type must bind independently of the body"
  expect (fnOne == fnPublicParam && fnOne.sourceHash == fnPublicParam.sourceHash)
    "omitted and explicit public fn parameters must canonicalize identically"
  expect (fnOne.sourceHash != fnPrivateParam.sourceHash &&
      fnOne.sourceHash != fnCommitmentParam.sourceHash &&
      fnPrivateParam.sourceHash != fnCommitmentParam.sourceHash)
    "private and commitment fn parameter visibility must bind distinctly"
  expect (fnOne.sourceHash != fnBodyLiteral.sourceHash &&
      fnOne.sourceHash != fnBodyCount.sourceHash &&
      fnBodyAddAB.sourceHash != fnBodyAddBA.sourceHash &&
      fnCallA.sourceHash != fnCallB.sourceHash)
    "fn body statement count, expression kind/value, operand order, and call callee must bind the source hash"
  expect (fnParamsAB.sourceHash != fnParamsBA.sourceHash &&
      fnOne.sourceHash != fnParamCount.sourceHash &&
      fnBodyOrderAB.sourceHash != fnBodyOrderBA.sourceHash &&
      fnsAB.sourceHash != fnsBA.sourceHash)
    "fn parameter count/order, body order, and declaration order must bind the source hash"
  expect (fnOne.sourceHash != fnsAB.sourceHash &&
      fnOne.sourceHash != fnBodyOrderBA.sourceHash)
    "same-prefix fn declaration and body statement counts must bind the source hash"

  expectInvalid "duplicate fn declarations"
    "program 'DuplicateFn' contains duplicate fn declarations"
    (← session.parsePrograms
      (programSource "DuplicateFn"
        "  fn helper(value : UInt64) : UInt64 do\n    return value\n  fn helper(other : UInt64) : UInt64 do\n    return other\n")
      "<duplicate-fn>")
  expectInvalid "entry and fn share one callable namespace"
    "program 'DuplicateEntryFnCallable' contains duplicate callable declarations"
    (← session.parsePrograms
      (programSource "DuplicateEntryFnCallable"
        "  entry helper(value : UInt64) : UInt64 do\n    return value\n  fn helper(other : UInt64) : UInt64 do\n    return other\n")
      "<duplicate-entry-fn-callable>")
  expectInvalid "view and fn share one callable namespace"
    "program 'DuplicateViewFnCallable' contains duplicate callable declarations"
    (← session.parsePrograms
      (programSource "DuplicateViewFnCallable"
        "  view helper(value : UInt64) : UInt64 do\n    return value\n  fn helper(other : UInt64) : UInt64 do\n    return other\n")
      "<duplicate-view-fn-callable>")
  expectInvalid "same-kind fn duplicate precedes cross-kind callable duplicate"
    "program 'PriorityFnBeforeCallable' contains duplicate fn declarations"
    (← session.parsePrograms
      (programSource "PriorityFnBeforeCallable"
        "  entry helper(value : UInt64) : UInt64 do\n    return value\n  fn helper(first : UInt64) : UInt64 do\n    return first\n  fn helper(second : UInt64) : UInt64 do\n    return second\n")
      "<priority-fn-before-callable>")
  expectInvalid "cross-kind callable duplicate precedes invariant duplicate"
    "program 'PriorityCallableBeforeInvariant' contains duplicate callable declarations"
    (← session.parsePrograms
      (programSource "PriorityCallableBeforeInvariant"
        "  entry helper(value : UInt64) : UInt64 do\n    return value\n  fn helper(other : UInt64) : UInt64 do\n    return other\n  invariant Holds : 1\n  invariant Holds : 2\n")
      "<priority-callable-before-invariant>")
  expectInvalid "fn does not satisfy the entry/view requirement"
    "program 'FnOnly' must declare at least one entry or view"
    (← session.parsePrograms
      (programWithoutEntrySource "FnOnly"
        "  fn helper(value : UInt64) : UInt64 do\n    return value\n")
      "<fn-only>")
  expectInvalid "const duplicate precedes fn duplicate"
    "program 'PriorityConstBeforeFn' contains duplicate const declarations"
    (← session.parsePrograms
      (programSource "PriorityConstBeforeFn"
        "  const Value : UInt64 := 1\n  const Value : UInt64 := 2\n  fn helper(value : UInt64) : UInt64 do\n    return value\n  fn helper(other : UInt64) : UInt64 do\n    return other\n")
      "<priority-const-before-fn>")
  expectInvalid "fn duplicate precedes initializer parameter duplicate"
    "program 'PriorityFnBeforeInitializerParam' contains duplicate fn declarations"
    (← session.parsePrograms
      (programSource "PriorityFnBeforeInitializerParam"
        "  fn helper(value : UInt64) : UInt64 do\n    return value\n  fn helper(other : UInt64) : UInt64 do\n    return other\n  init(value : UInt64, value : Bool) do\n    return 0\n")
      "<priority-fn-before-initializer-param>")
  expectInvalid "initializer parameter duplicate precedes fn parameter duplicate"
    "initializer contains duplicate parameters"
    (← session.parsePrograms
      (programSource "PriorityInitializerParamBeforeFnParam"
        "  fn helper(arg : UInt64, arg : Bool) : UInt64 do\n    return 0\n  init(value : UInt64, value : Bool) do\n    return 0\n")
      "<priority-initializer-param-before-fn-param>")
  expectInvalid "entry parameter duplicate precedes fn parameter duplicate"
    "entry 'run' contains duplicate parameters"
    (← session.parsePrograms
      (programSource "PriorityEntryParamBeforeFnParam"
        "  fn helper(arg : UInt64, arg : Bool) : UInt64 do\n    return 0\n  entry run(value : UInt64, value : Bool) : UInt64 do\n    return 0\n")
      "<priority-entry-param-before-fn-param>")
  expectInvalid "fn parameter duplicate precedes empty body"
    "fn 'helper' contains duplicate parameters"
    (← session.parsePrograms
      (programSource "PriorityFnParamBeforeEmptyBody"
        "  fn helper(value : UInt64, value : Bool) : UInt64 do\n")
      "<priority-fn-param-before-empty-body>")
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
  expectInvalid "fn name precedes parameter/result/body decoding"
    "reserved portable identifier 'const'"
    (← session.parsePrograms
      (programSource "PriorityFnNameBeforeParamResultBody"
        "  fn const(fn : UInt64) : Unknown do\n    return 18446744073709551616\n")
      "<priority-fn-name-before-param-result-body>")
  expectInvalid "fn parameter precedes result/body decoding"
    "reserved portable identifier 'fn'"
    (← session.parsePrograms
      (programSource "PriorityFnParamBeforeResultBody"
        "  fn helper(fn : UInt64) : Unknown do\n    return 18446744073709551616\n")
      "<priority-fn-param-before-result-body>")
  expectInvalid "fn result precedes body decoding" "unsupported portable type"
    (← session.parsePrograms
      (programSource "PriorityFnResultBeforeBody"
        "  fn helper(value : UInt64) : Unknown do\n    return 18446744073709551616\n")
      "<priority-fn-result-before-body>")

  match Typed.check elaborated with
  | .error (.invalidProgram "fn declarations are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"fn declarations reached the wrong failure: {other.render}"
  | .ok _ => throw <| IO.userError "Typed.check must not silently erase fn declarations"
  match Compiler.compile elaborated with
  | .error (.invalidProgram "fn declarations are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"fn declarations bypassed the wrong compiler boundary: {other.render}"
  | .ok _ => throw <| IO.userError "Compiler.compile must not bypass fn fail-closed checking"

end Tests.Language.FnDeclarations
