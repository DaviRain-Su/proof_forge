import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1ExpressionForms

open ProofForgeV2
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.QualifiedNameV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def rawParts (name : SourceQualifiedNameV1) : Array String :=
  name.components.toArray.map (·.raw)

private def source (expr : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program ExpressionForms where\n" ++
  "  entry run(a : UInt64) : UInt64 do\n" ++
  "    return " ++ expr ++ "\n"

private def qualifiedPath (count : Nat) : Array String :=
  (List.range count).toArray.map fun index => s!"C{index}"

private def constructorExprSource (parts : Array String) : String :=
  String.intercalate "." parts.toList ++ "()"

private unsafe def decodeReturnExpr
    (session : ProofForgeV2.Language.Loader.ParserSession) (label expr : String) :
    IO ExprV1 := do
  match ← session.selectProgramV1 (source expr)
      ("<program-v1-expression-forms-" ++ label ++ ">")
      "Tests.ProgramV1ExpressionForms" none with
  | .ok value =>
      match value.program.items[0]? with
      | some (ProgramItemV1.entry declaration) =>
          match declaration.body.statements with
          | #[.return_ (some value)] => pure value
          | other => throw <| IO.userError s!"'{label}' did not decode one return: {repr other}"
      | other => throw <| IO.userError s!"'{label}' did not decode an entry: {repr other}"
  | .error error => throw <| IO.userError error.render

private unsafe def decodeValidatedSource
    (session : ProofForgeV2.Language.Loader.ParserSession) (label expr : String) :
    IO ProofForgeV2.Source.ValidatedSourceV1.ValidatedSourceV1 := do
  match ← session.selectProgramV1 (source expr)
      ("<program-v1-expression-forms-" ++ label ++ ">")
      "Tests.ProgramV1ExpressionForms" none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def canonicalBytes
    (source : ProofForgeV2.Source.ValidatedSourceV1.ValidatedSourceV1)
    (label : String) : IO ByteArray :=
  match ProofForgeV2.Source.ValidatedSourceV1.canonicalValidatedSourceAstBytesV1 source with
  | .ok bytes => pure bytes
  | .error error => throw <| IO.userError s!"{label}: canonical bytes failed: {error}"

private def sourceDigest
    (source : ProofForgeV2.Source.ValidatedSourceV1.ValidatedSourceV1)
    (label : String) : IO ProofForgeV2.Core.Common.Digest :=
  match ProofForgeV2.Source.ValidatedSourceV1.sourceHashV1 source with
  | .ok digest => pure digest
  | .error error => throw <| IO.userError s!"{label}: sourceHashV1 failed: {error}"

private def expectSameProgramBytesAndHash
    (left right : ProofForgeV2.Source.ValidatedSourceV1.ValidatedSourceV1)
    (label : String) : IO Unit := do
  expect (left.program == right.program) s!"{label}: ProgramV1 AST changed"
  expect ((← canonicalBytes left (label ++ " left")) ==
    (← canonicalBytes right (label ++ " right")))
    s!"{label}: canonical bytes changed"
  expect ((← sourceDigest left (label ++ " left")) ==
    (← sourceDigest right (label ++ " right")))
    s!"{label}: sourceHashV1 changed"

private unsafe def expectReject
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label expr expected : String) : IO Unit := do
  match ← session.selectProgramV1 (source expr)
      ("<program-v1-expression-negative-" ++ label ++ ">")
      "Tests.ProgramV1ExpressionForms" none with
  | .ok value =>
      throw <| IO.userError s!"negative '{label}' unexpectedly decoded: {repr value.program.items}"
  | .error error =>
      let rendered := error.render
      unless rendered.contains expected do
        throw <| IO.userError
          s!"negative '{label}' expected '{expected}', got '{rendered}'"

private def exprAt (exprs : Array ExprV1) (index : Nat) (label : String) : IO ExprV1 :=
  match exprs[index]? with
  | some expr => pure expr
  | none => throw <| IO.userError s!"{label}: missing expression {index}"

private def expectLiteral (expr : ExprV1) (expected : Nat) (label : String) : IO Unit :=
  match expr with
  | .literal (.integer value) => expect (value == expected) label
  | other => throw <| IO.userError s!"{label}: expected literal, got {repr other}"

private def expectPlaceName (expr : ExprV1) (expected : String) (label : String) : IO Unit :=
  match expr with
  | .place (.name name) => expect (name.raw == expected) label
  | other => throw <| IO.userError s!"{label}: expected place name, got {repr other}"

private def expectLocalCall (expr : ExprV1) (expectedCallee : String) (expectedArgs : Nat)
    (label : String) : IO (Array ExprV1) := do
  match expr with
  | .localCall callee args =>
      expect (callee.raw == expectedCallee) s!"{label}: callee raw identity changed"
      expect (args.size == expectedArgs) s!"{label}: argument count changed"
      pure args
  | other => throw <| IO.userError s!"{label}: expected localCall, got {repr other}"

private def expectConstructor (expr : ExprV1) (expectedPath : Array String) (expectedArgs : Nat)
    (label : String) : IO (Array ExprV1) := do
  match expr with
  | .constructor ctor args =>
      expect (rawParts ctor == expectedPath) s!"{label}: constructor raw path changed"
      expect (args.size == expectedArgs) s!"{label}: argument count changed"
      pure args
  | other => throw <| IO.userError s!"{label}: expected constructor, got {repr other}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  for (label, spelling, expected) in [
      ("integer-decimal-sixteen", "16", 16),
      ("integer-hex-sixteen", "0x10", 16),
      ("integer-decimal-255", "255", 255),
      ("integer-hex-255", "0xff", 255),
      ("integer-hex-uppercase-digits-255", "0xFF", 255),
      ("integer-decimal-zero", "0", 0),
      ("integer-hex-zero", "0x0", 0)
    ] do
    expectLiteral (← decodeReturnExpr session label spelling) expected
      s!"{label}: integer magnitude changed"

  expectSameProgramBytesAndHash
    (← decodeValidatedSource session "integer-equivalent-sixteen-decimal" "16")
    (← decodeValidatedSource session "integer-equivalent-sixteen-hex" "0x10")
    "decimal 16 and hexadecimal 0x10 must canonicalize equally"
  expectSameProgramBytesAndHash
    (← decodeValidatedSource session "integer-equivalent-255-decimal" "255")
    (← decodeValidatedSource session "integer-equivalent-255-hex" "0xff")
    "decimal 255 and hexadecimal 0xff must canonicalize equally"
  expectSameProgramBytesAndHash
    (← decodeValidatedSource session "integer-equivalent-255-lower-hex" "0xff")
    (← decodeValidatedSource session "integer-equivalent-255-upper-digits" "0xFF")
    "hex digit case must not change canonical identity"
  expectSameProgramBytesAndHash
    (← decodeValidatedSource session "integer-equivalent-zero-decimal" "0")
    (← decodeValidatedSource session "integer-equivalent-zero-hex" "0x0")
    "decimal 0 and hexadecimal 0x0 must canonicalize equally"

  let uint256MaxDecimal :=
    "115792089237316195423570985008687907853269984665640564039457584007913129639935"
  let uint256MaxHex :=
    "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  let uint256OverflowDecimal :=
    "115792089237316195423570985008687907853269984665640564039457584007913129639936"
  let uint256OverflowHex :=
    "0x10000000000000000000000000000000000000000000000000000000000000000"
  expectSameProgramBytesAndHash
    (← decodeValidatedSource session "integer-u256-max-decimal" uint256MaxDecimal)
    (← decodeValidatedSource session "integer-u256-max-hex" uint256MaxHex)
    "UInt256 maximum decimal and hexadecimal spelling must canonicalize equally"

  -- These are legal Lean numeral tokens but forbidden ProgramV1 spellings, so
  -- they must reach the shared expression/pattern integer decoder rather than
  -- being mislabeled as parser-boundary failures.
  for (label, spelling) in [
      ("integer-uppercase-prefix", "0X10"),
      ("integer-binary-prefix", "0b10"),
      ("integer-octal-prefix", "0o10"),
      ("integer-decimal-underscore", "1_0"),
      ("integer-hex-underscore", "0x_10")
    ] do
    expectReject session label spelling
      "integer literal must use unsigned decimal or lowercase 0x hexadecimal spelling"
  for (label, spelling) in [
      ("integer-u256-overflow-decimal", uint256OverflowDecimal),
      ("integer-u256-overflow-hex", uint256OverflowHex)
    ] do
    expectReject session label spelling "integer literal exceeds UInt256"
  expectReject session "integer-overflow-before-invalid-rhs"
    (uint256OverflowHex ++ " + «if»") "integer literal exceeds UInt256"

  discard <| expectLocalCall (← decodeReturnExpr session "local-zero" "f()") "f" 0
    "local zero args"
  let localOne ← expectLocalCall (← decodeReturnExpr session "local-one" "f(1)") "f" 1
    "local one arg"
  expectLiteral (← exprAt localOne 0 "local one arg") 1 "local one arg value changed"
  let localMany ← expectLocalCall (← decodeReturnExpr session "local-many" "f(1, a, 3)")
    "f" 3 "local many args"
  expectLiteral (← exprAt localMany 0 "local first arg") 1 "local first arg order changed"
  expectPlaceName (← exprAt localMany 1 "local second arg") "a" "local second arg order changed"
  expectLiteral (← exprAt localMany 2 "local third arg") 3 "local third arg order changed"
  let localNested ← expectLocalCall (← decodeReturnExpr session "local-nested" "f(g(1), 2)")
    "f" 2 "local nested args"
  let nestedInner ← expectLocalCall (← exprAt localNested 0 "local nested inner") "g" 1
    "local nested inner"
  expectLiteral (← exprAt nestedInner 0 "local nested inner arg") 1
    "local nested inner arg changed"
  expectLiteral (← exprAt localNested 1 "local nested second") 2
    "local nested second arg changed"
  let escapedLocal ← expectLocalCall
    (← decodeReturnExpr session "local-escaped-dot" "«local.with.dot»(1)")
    "local.with.dot" 1 "single escaped dotted component must stay localCall"
  expectLiteral (← exprAt escapedLocal 0 "escaped local arg") 1 "escaped local arg changed"

  discard <| expectConstructor (← decodeReturnExpr session "ctor-zero" "A.B()")
    #["A", "B"] 0 "constructor zero args"
  let ctorOne ← expectConstructor (← decodeReturnExpr session "ctor-one" "A.B(1)")
    #["A", "B"] 1 "constructor one arg"
  expectLiteral (← exprAt ctorOne 0 "constructor one arg") 1 "constructor one arg changed"
  let ctorMany ← expectConstructor (← decodeReturnExpr session "ctor-many" "A.B(1, a, 3)")
    #["A", "B"] 3 "constructor many args"
  expectLiteral (← exprAt ctorMany 0 "constructor first arg") 1
    "constructor first arg order changed"
  expectPlaceName (← exprAt ctorMany 1 "constructor second arg") "a"
    "constructor second arg order changed"
  expectLiteral (← exprAt ctorMany 2 "constructor third arg") 3
    "constructor third arg order changed"
  let ctorNested ← expectConstructor
    (← decodeReturnExpr session "ctor-nested" "A.B(C.D(1), 2)")
    #["A", "B"] 2 "constructor nested args"
  let ctorNestedInner ← expectConstructor (← exprAt ctorNested 0 "constructor nested inner")
    #["C", "D"] 1 "constructor nested inner"
  expectLiteral (← exprAt ctorNestedInner 0 "constructor nested inner arg") 1
    "constructor nested inner arg changed"
  expectLiteral (← exprAt ctorNested 1 "constructor nested second") 2
    "constructor nested second arg changed"
  let ctorEscaped ← expectConstructor
    (← decodeReturnExpr session "ctor-escaped-dot" "A.«component.with.dot»(1)")
    #["A", "component.with.dot"] 1 "constructor escaped dotted component"
  expectLiteral (← exprAt ctorEscaped 0 "constructor escaped arg") 1
    "constructor escaped component arg changed"
  discard <| expectConstructor
    (← decodeReturnExpr session "ctor-multi-escaped-dot" "A.«component.with.dot».C(1)")
    #["A", "component.with.dot", "C"] 1 "constructor multi escaped dotted component"
  let maxConstructorParts := qualifiedPath 256
  discard <| expectConstructor
    (← decodeReturnExpr session "ctor-max-components" (constructorExprSource maxConstructorParts))
    maxConstructorParts 0 "constructor 256-component boundary"

  match ← decodeReturnExpr session "index-literal" "x[0]" with
  | .place (.index (.name base) index) =>
      expect (base.raw == "x") "index base raw identity changed"
      expectLiteral index 0 "index literal changed"
  | other => throw <| IO.userError s!"index literal shape changed: {repr other}"
  match ← decodeReturnExpr session "index-escaped-base" "«base.with.dot»[0]" with
  | .place (.index (.name base) index) =>
      expect (base.raw == "base.with.dot") "escaped index base raw identity changed"
      expectLiteral index 0 "escaped base index literal changed"
  | other => throw <| IO.userError s!"escaped index base shape changed: {repr other}"
  match ← decodeReturnExpr session "index-recursive" "x[y[0]]" with
  | .place (.index (.name base) (.place (.index (.name innerBase) innerIndex))) =>
      expect (base.raw == "x") "outer index base changed"
      expect (innerBase.raw == "y") "inner index base changed"
      expectLiteral innerIndex 0 "inner index literal changed"
  | other => throw <| IO.userError s!"recursive index shape changed: {repr other}"

  for (label, expr) in [
      ("local-missing-close", "f(1"),
      ("local-leading-comma", "f(,1)"),
      ("local-trailing-comma", "f(1,)"),
      ("local-double-comma", "f(1,,2)"),
      ("ctor-missing-close", "A.B(1"),
      ("ctor-leading-comma", "A.B(,1)"),
      ("ctor-trailing-comma", "A.B(1,)"),
      ("ctor-double-comma", "A.B(1,,2)"),
      ("index-missing-close", "x[0"),
      ("index-empty", "x[]")
    ] do
    expectReject session label expr "failed to parse file"

  expectReject session "reserved-local-callee" "«if»(1)"
    "reserved portable identifier 'if'"
  expectReject session "reserved-local-before-arg" "«if»(«else»)"
    "reserved portable identifier 'if'"
  expectReject session "reserved-constructor-path" "A.«if»(1)"
    "reserved portable identifier 'if'"
  expectReject session "reserved-constructor-before-arg" "A.«if»(«else»)"
    "reserved portable identifier 'if'"
  expectReject session "reserved-index-base" "«if»[0]"
    "reserved portable identifier 'if'"
  expectReject session "reserved-index-base-before-index" "«if»[«else»]"
    "reserved portable identifier 'if'"
  match ← decodeReturnExpr session "qualified-index-base" "A.B[0]" with
  | .place (.index (.field (.name root) field) index) =>
      expect (root.raw == "A") "qualified index base root raw changed"
      expect (field.raw == "B") "qualified index base field raw changed"
      expectLiteral index 0 "qualified index literal changed"
  | other => throw <| IO.userError s!"qualified index base shape changed: {repr other}"
  expectReject session "ctor-over-max-components" (constructorExprSource (qualifiedPath 257))
    "limit 256"

end Tests.Language.ProgramV1ExpressionForms
