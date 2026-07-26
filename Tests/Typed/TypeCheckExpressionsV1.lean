import Tests.Language.ParserSession
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1
import ProofForgeV2.Typed.TypeCheckV1

namespace Tests.Typed.TypeCheckExpressionsV1

open ProofForgeV2
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1
open ProofForgeV2.Typed.TypeCheckV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def messages (res : TypeCheckResultV1) : Array String :=
  res.diagnostics.map (·.message)

private def contains (haystack : Array String) (needle : String) : Bool :=
  haystack.any (·.contains needle)

private def source (body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program TypeCheckExpressions where\n" ++
  body ++
  "  entry run() : UInt64 do\n" ++
  "    return 0\n"

private unsafe def resolveProgram
    (session : Language.Loader.ParserSession) (label body : String) :
    IO NameResolutionResultV1 := do
  match ← session.selectProgramV1 (source body)
      ("<type-check-expressions-" ++ label ++ ">")
      "Tests.TypeCheckExpressionsV1" none with
  | .ok validated => pure (resolveProgramV1 validated)
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def findConst (tables : TypedDeclTablesV1) (raw : String) :
    Option ConstDeclV1 :=
  tables.const.entries.findSome? fun (name, _, decl) =>
    if name.raw == raw then some decl else none

private unsafe def typeCheckConst
    (session : Language.Loader.ParserSession) (label body raw : String) :
    IO TypeCheckResultV1 := do
  let resolved ← resolveProgram session label body
  unless resolved.ok do
    throw <| IO.userError s!"{label}: name resolution failed: {repr resolved.diagnostics}"
  let scope := scopeFromTables resolved.tables
  match findConst resolved.tables raw with
  | none => throw <| IO.userError s!"{label}: const '{raw}' not found"
  | some decl =>
      pure (typeCheckExpr scope resolved.tables (some decl.type_) decl.value)

private unsafe def expectConstOk
    (session : Language.Loader.ParserSession) (label body raw : String)
    (expectedType : TypeV1) : IO Unit := do
  let res ← typeCheckConst session label body raw
  unless res.diagnostics.isEmpty do
    throw <| IO.userError s!"{label}: expected no diagnostics, got {messages res}"
  unless res.type == expectedType do
    throw <| IO.userError s!"{label}: expected type {repr expectedType}, got {repr res.type}"

private unsafe def expectConstDiag
    (session : Language.Loader.ParserSession) (label body raw : String)
    (needle : String) : IO Unit := do
  let res ← typeCheckConst session label body raw
  if res.diagnostics.isEmpty then
    throw <| IO.userError s!"{label}: expected diagnostics, got clean result {repr res.type}"
  unless contains (messages res) needle do
    throw <| IO.userError s!"{label}: expected diagnostic containing '{needle}', got {messages res}"

private unsafe def testBoolLiteral (session : Language.Loader.ParserSession) : IO Unit :=
  expectConstOk session "bool-literal"
    "  const target : Bool := true\n"
    "target" .bool

private unsafe def testIntegerLiteralBoundaries (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  const u8ok : UInt8 := 255\n" ++
    "  const u8bad : UInt8 := 256\n" ++
    "  const i8ok : Int8 := -128\n" ++
    "  const i8bad : Int8 := -129\n" ++
    "  const i8pos : Int8 := 127\n" ++
    "  const i8posBad : Int8 := 128\n"
  expectConstOk session "u8ok" body "u8ok" (.uint 8)
  expectConstDiag session "u8bad" body "u8bad" "UInt8"
  expectConstDiag session "u8bad-range" body "u8bad" "out of range"
  expectConstOk session "i8ok" body "i8ok" (.int 8)
  expectConstDiag session "i8bad" body "i8bad" "Int8"
  expectConstDiag session "i8bad-range" body "i8bad" "out of range"
  expectConstOk session "i8pos" body "i8pos" (.int 8)
  expectConstDiag session "i8posBad" body "i8posBad" "out of range"

private unsafe def testArithmeticOperators (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state x : UInt64\n" ++
    "  state y : UInt64\n" ++
    "  const add_ : UInt64 := x + y\n" ++
    "  const sub_ : UInt64 := x - y\n" ++
    "  const mul_ : UInt64 := x * y\n" ++
    "  const div_ : UInt64 := x / y\n" ++
    "  const mod_ : UInt64 := x % y\n"
  expectConstOk session "add" body "add_" (.uint 64)
  expectConstOk session "sub" body "sub_" (.uint 64)
  expectConstOk session "mul" body "mul_" (.uint 64)
  expectConstOk session "div" body "div_" (.uint 64)
  expectConstOk session "mod" body "mod_" (.uint 64)

private unsafe def testShiftOperators (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state x : UInt64\n" ++
    "  const shl_ : UInt64 := x << 1\n" ++
    "  const shr_ : UInt64 := x >> 1\n"
  expectConstOk session "shl" body "shl_" (.uint 64)
  expectConstOk session "shr" body "shr_" (.uint 64)

private unsafe def testBitwiseOperators (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state x : UInt64\n" ++
    "  state y : UInt64\n" ++
    "  const and_ : UInt64 := x & y\n" ++
    "  const xor_ : UInt64 := x ^ y\n" ++
    "  const or_ : UInt64 := x | y\n" ++
    "  const not_ : UInt64 := ~x\n"
  expectConstOk session "and" body "and_" (.uint 64)
  expectConstOk session "xor" body "xor_" (.uint 64)
  expectConstOk session "or" body "or_" (.uint 64)
  expectConstOk session "not" body "not_" (.uint 64)

private unsafe def testEqualityOperators (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state x : UInt64\n" ++
    "  state y : UInt64\n" ++
    "  const eq_ : Bool := x == y\n" ++
    "  const ne_ : Bool := x != y\n"
  expectConstOk session "eq" body "eq_" .bool
  expectConstOk session "ne" body "ne_" .bool

private unsafe def testComparisonOperators (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state x : UInt64\n" ++
    "  state y : UInt64\n" ++
    "  const lt_ : Bool := x < y\n" ++
    "  const le_ : Bool := x <= y\n" ++
    "  const gt_ : Bool := x > y\n" ++
    "  const ge_ : Bool := x >= y\n"
  expectConstOk session "lt" body "lt_" .bool
  expectConstOk session "le" body "le_" .bool
  expectConstOk session "gt" body "gt_" .bool
  expectConstOk session "ge" body "ge_" .bool

private unsafe def testLogicalOperators (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state a : Bool\n" ++
    "  state b : Bool\n" ++
    "  const and_ : Bool := a && b\n" ++
    "  const or_ : Bool := a || b\n"
  expectConstOk session "logical-and" body "and_" .bool
  expectConstOk session "logical-or" body "or_" .bool

private unsafe def testMixedTypeBinaryRejection (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state x : UInt64\n" ++
    "  const y : UInt32 := 1\n" ++
    "  const bad : UInt64 := x + y\n"
  let res ← typeCheckConst session "mixed-type-binary" body "bad"
  expect (res.diagnostics.size >= 1) "mixed-type-binary: expected at least one diagnostic"
  let msgs := messages res
  unless contains msgs "UInt64" do
    throw <| IO.userError s!"mixed-type-binary: expected UInt64 in diagnostics, got {msgs}"
  unless contains msgs "UInt32" do
    throw <| IO.userError s!"mixed-type-binary: expected UInt32 in diagnostics, got {msgs}"

private unsafe def testStructFieldChain (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  struct Pair where\n" ++
    "    left : UInt64\n" ++
    "  state p : Pair\n" ++
    "  const ok : UInt64 := p.left\n"
  expectConstOk session "struct-field-chain" body "ok" (.uint 64)

private unsafe def testStructFieldWrongRejection (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  struct Pair where\n" ++
    "    left : UInt64\n" ++
    "  state p : Pair\n" ++
    "  const bad : UInt64 := p.right\n"
  expectConstDiag session "struct-field-wrong" body "bad" "right"

private unsafe def testArrayIndex (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state arr : Array UInt64 2\n" ++
    "  const ok : UInt64 := arr[0]\n"
  expectConstOk session "array-index" body "ok" (.uint 64)

private unsafe def testArrayIndexKeyTypeRejection (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state arr : Array UInt64 2\n" ++
    "  state b : Bool\n" ++
    "  const bad : UInt64 := arr[b]\n"
  expectConstDiag session "array-index-bool" body "bad" "UInt32"
  expectConstDiag session "array-index-bool" body "bad" "Bool"

private unsafe def testMapIndex (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state m : Map UInt64 Bool\n" ++
    "  const ok : Option Bool := m[1]\n"
  expectConstOk session "map-index" body "ok" (.option .bool)

private unsafe def testMapIndexKeyTypeRejection (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state m : Map UInt64 Bool\n" ++
    "  const bad : Bool := m[true]\n"
  expectConstDiag session "map-index-bool" body "bad" "UInt64"
  expectConstDiag session "map-index-bool" body "bad" "Bool"

private unsafe def testUnaryTypeGates (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state x : UInt64\n" ++
    "  state b : Bool\n" ++
    "  const negBad : UInt64 := -b\n" ++
    "  const notBad : UInt64 := !x\n" ++
    "  const bitNotBad : UInt64 := ~b\n"
  expectConstDiag session "neg-bool" body "negBad" "integer type"
  expectConstDiag session "not-int" body "notBad" "Bool"
  expectConstDiag session "bitnot-bool" body "bitNotBad" "integer type"

private unsafe def testBoolIntegerSeparation (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  const boolInInt : UInt64 := true\n" ++
    "  const intInBool : Bool := 1\n"
  expectConstDiag session "bool-in-int" body "boolInInt" "UInt64"
  expectConstDiag session "bool-in-int" body "boolInInt" "Bool"
  expectConstDiag session "int-in-bool" body "intInBool" "Bool"
  expectConstDiag session "int-in-bool" body "intInBool" "integer literal"

private unsafe def testSourceOrderDiagnostics (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state x : UInt64\n" ++
    "  const bad : Bool := true < x\n"
  let res ← typeCheckConst session "source-order" body "bad"
  expect (!res.diagnostics.isEmpty) "source-order: expected diagnostics"
  let msgs := messages res
  expect (msgs.size >= 2) "source-order: expected at least two diagnostics"
  unless msgs[0]!.contains "Bool" do
    throw <| IO.userError s!"source-order: first diagnostic should mention Bool, got {msgs}"
  unless msgs[1]!.contains "UInt64" do
    throw <| IO.userError s!"source-order: second diagnostic should mention UInt64, got {msgs}"

private unsafe def testUnknownPlaceRejection (session : Language.Loader.ParserSession) : IO Unit := do
  let resolved ← resolveProgram session "unknown-place" ""
  unless resolved.ok do
    throw <| IO.userError s!"unknown-place: name resolution failed unexpectedly"
  let name : SourceNameComponentV1 ←
    match parseSourceNameComponentV1 "doesNotExist" with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"unknown-place: {e}"
  let scope := ⟨ [] ⟩
  let expr := ExprV1.place (PlaceV1.name name)
  let res := typeCheckExpr scope resolved.tables (some (.uint 64)) expr
  if res.diagnostics.isEmpty then
    throw <| IO.userError s!"unknown-place: expected diagnostics, got clean result {repr res.type}"
  unless contains (messages res) "doesNotExist" do
    throw <| IO.userError s!"unknown-place: expected diagnostic mentioning doesNotExist, got {messages res}"

private def checkLiteral (tables : TypedDeclTablesV1) (type_ : TypeV1) (magnitude : Nat) : TypeCheckResultV1 :=
  typeCheckExpr ⟨[]⟩ tables (some type_) (ExprV1.literal (.integer magnitude))

private def checkNegatedLiteral (tables : TypedDeclTablesV1) (type_ : TypeV1) (magnitude : Nat) : TypeCheckResultV1 :=
  typeCheckExpr ⟨[]⟩ tables (some type_) (ExprV1.unary .neg (ExprV1.literal (.integer magnitude)))

private unsafe def testWiderIntegerLiteralBoundaries (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  const u16ok : UInt16 := 65535\n" ++
    "  const u256ok : UInt256 := 115792089237316195423570985008687907853269984665640564039457584007913129639935\n" ++
    "  const i16ok : Int16 := -32768\n" ++
    "  const i256ok : Int256 := -57896044618658097711785492504343953926634992332820282019728792003956564819968\n"
  expectConstOk session "u16ok" body "u16ok" (.uint 16)
  expectConstOk session "u256ok" body "u256ok" (.uint 256)
  expectConstOk session "i16ok" body "i16ok" (.int 16)
  expectConstOk session "i256ok" body "i256ok" (.int 256)
  let resolved ← resolveProgram session "wider-boundaries" ""
  let res := checkLiteral resolved.tables (.uint 16) 65536
  unless contains (messages res) "out of range" do
    throw <| IO.userError s!"u16bad: expected out of range, got {messages res}"
  let res := checkLiteral resolved.tables (.uint 256) (Nat.pow 2 256)
  unless contains (messages res) "out of range" do
    throw <| IO.userError s!"u256bad: expected out of range, got {messages res}"
  let res := checkLiteral resolved.tables (.int 16) 32769
  unless contains (messages res) "out of range" do
    throw <| IO.userError s!"i16bad: expected out of range, got {messages res}"
  let res := checkNegatedLiteral resolved.tables (.int 16) 32769
  unless contains (messages res) "out of range" do
    throw <| IO.userError s!"i16negBad: expected out of range, got {messages res}"
  let res := checkLiteral resolved.tables (.int 256) (Nat.pow 2 255 + 1)
  unless contains (messages res) "out of range" do
    throw <| IO.userError s!"i256bad: expected out of range, got {messages res}"
  let res := checkNegatedLiteral resolved.tables (.int 256) (Nat.pow 2 255 + 1)
  unless contains (messages res) "out of range" do
    throw <| IO.userError s!"i256negBad: expected out of range, got {messages res}"

private unsafe def testComparisonNonIntegerRejection (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state a : Bool\n" ++
    "  state b : Bool\n" ++
    "  const bad : Bool := a < b\n"
  expectConstDiag session "compare-bool" body "bad" "integer type"

private unsafe def testEqualityBoolIntegerRejection (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state x : UInt64\n" ++
    "  const bad : Bool := x == true\n"
  expectConstDiag session "eq-bool-int" body "bad" "UInt64"
  expectConstDiag session "eq-bool-int" body "bad" "Bool"

private unsafe def testShiftCountWidthCheck (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state x : UInt64\n" ++
    "  const ok : UInt64 := x << 63\n" ++
    "  const bad : UInt64 := x << 64\n"
  expectConstOk session "shift-ok" body "ok" (.uint 64)
  expectConstDiag session "shift-bad" body "bad" "shift count"
  expectConstDiag session "shift-bad" body "bad" "64"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testBoolLiteral session
  testIntegerLiteralBoundaries session
  testArithmeticOperators session
  testShiftOperators session
  testBitwiseOperators session
  testEqualityOperators session
  testComparisonOperators session
  testLogicalOperators session
  testMixedTypeBinaryRejection session
  testStructFieldChain session
  testStructFieldWrongRejection session
  testArrayIndex session
  testArrayIndexKeyTypeRejection session
  testMapIndex session
  testMapIndexKeyTypeRejection session
  testUnaryTypeGates session
  testBoolIntegerSeparation session
  testSourceOrderDiagnostics session
  testUnknownPlaceRejection session
  testWiderIntegerLiteralBoundaries session
  testComparisonNonIntegerRejection session
  testEqualityBoolIntegerRejection session
  testShiftCountWidthCheck session
  IO.println "Tests.Typed.TypeCheckExpressionsV1: ok"

end Tests.Typed.TypeCheckExpressionsV1
