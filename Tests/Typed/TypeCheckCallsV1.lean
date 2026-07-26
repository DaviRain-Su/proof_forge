import Tests.Language.ParserSession
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1
import ProofForgeV2.Typed.TypeCheckV1

namespace Tests.Typed.TypeCheckCallsV1

open ProofForgeV2
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
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

private def mkName (raw : String) : IO SourceNameComponentV1 :=
  match parseSourceNameComponentV1 raw with
  | .ok n => pure n
  | .error e => throw <| IO.userError s!"mkName: {e}"

private def mkQn (raws : Array String) : IO SourceQualifiedNameV1 :=
  match parseSourceQualifiedNameV1 raws with
  | .ok q => pure q
  | .error e => throw <| IO.userError s!"mkQn: {e}"

private def u (n : Nat) : ExprV1 := .literal (.integer n)
private def b (v : Bool) : ExprV1 := .literal (.bool v)
private def place (raw : String) : IO ExprV1 := do
  pure (.place (.name (← mkName raw)))

private def source (body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program TypeCheckCalls where\n" ++
  body ++
  "  entry run() : UInt64 do\n" ++
  "    return 0\n"

private unsafe def resolveRawProgram
    (session : Language.Loader.ParserSession) (label source : String) :
    IO NameResolutionResultV1 := do
  match ← session.selectProgramV1 source
      ("<type-check-calls-raw-" ++ label ++ ">")
      "Tests.TypeCheckCallsV1" none with
  | .ok validated => pure (resolveProgramV1 validated)
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private unsafe def resolveProgram
    (session : Language.Loader.ParserSession) (label body : String) :
    IO NameResolutionResultV1 := do
  match ← session.selectProgramV1 (source body)
      ("<type-check-calls-" ++ label ++ ">")
      "Tests.TypeCheckCallsV1" none with
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

private unsafe def expectExprOk
    (label : String) (res : TypeCheckResultV1) (expectedType : TypeV1) : IO Unit := do
  unless res.diagnostics.isEmpty do
    throw <| IO.userError s!"{label}: expected no diagnostics, got {messages res}"
  unless res.type == expectedType do
    throw <| IO.userError s!"{label}: expected type {repr expectedType}, got {repr res.type}"

private unsafe def expectExprDiag
    (label : String) (res : TypeCheckResultV1) (needle : String) : IO Unit := do
  if res.diagnostics.isEmpty then
    throw <| IO.userError s!"{label}: expected diagnostics, got clean result {repr res.type}"
  unless contains (messages res) needle do
    throw <| IO.userError s!"{label}: expected diagnostic containing '{needle}', got {messages res}"

private unsafe def testEnumVariantWithPayload
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  enum Choice where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  const target : Choice := Choice.Some(1)\n"
  expectConstOk session "enum-with-payload" body "target" (.named (← mkName "Choice"))

private unsafe def testEnumVariantWithoutPayload
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  enum Choice where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  const target : Choice := Choice.None()\n"
  expectConstOk session "enum-without-payload" body "target" (.named (← mkName "Choice"))

private unsafe def testEnumWrongCount
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  enum Choice where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  const target : Choice := Choice.Some(1, 2)\n"
  let res ← typeCheckConst session "enum-wrong-count" body "target"
  expectExprDiag "enum-wrong-count" res "1"
  expectExprDiag "enum-wrong-count" res "2"

private unsafe def testEnumWrongType
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  enum Choice where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  const target : Choice := Choice.Some(true)\n"
  let res ← typeCheckConst session "enum-wrong-type" body "target"
  expectExprDiag "enum-wrong-type" res "UInt64"
  expectExprDiag "enum-wrong-type" res "Bool"

private unsafe def testStructConstructorExact
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  struct Pair where\n" ++
    "    left : UInt64\n" ++
    "    right : UInt64\n"
  let resolved ← resolveProgram session "struct-ctor-exact" body
  let pairType : TypeV1 := .named (← mkName "Pair")
  let expr := ExprV1.constructor (← mkQn #["Pair"]) #[u 1, u 2]
  let res := typeCheckExpr emptyScope resolved.tables (some pairType) expr
  expectExprOk "struct-ctor-exact" res pairType

private unsafe def testStructConstructorNested
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  struct Pair where\n" ++
    "    left : UInt64\n" ++
    "    right : UInt64\n" ++
    "  struct Wrapper where\n" ++
    "    pair : Pair\n"
  let resolved ← resolveProgram session "struct-ctor-nested" body
  let wrapperType : TypeV1 := .named (← mkName "Wrapper")
  let inner := ExprV1.constructor (← mkQn #["Pair"]) #[u 1, u 2]
  let expr := ExprV1.constructor (← mkQn #["Wrapper"]) #[inner]
  let res := typeCheckExpr emptyScope resolved.tables (some wrapperType) expr
  expectExprOk "struct-ctor-nested" res wrapperType

private unsafe def testStructWrongCount
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  struct Pair where\n" ++
    "    left : UInt64\n" ++
    "    right : UInt64\n"
  let resolved ← resolveProgram session "struct-wrong-count" body
  let pairType : TypeV1 := .named (← mkName "Pair")
  let expr := ExprV1.constructor (← mkQn #["Pair"]) #[u 1]
  let res := typeCheckExpr emptyScope resolved.tables (some pairType) expr
  expectExprDiag "struct-wrong-count" res "2"
  expectExprDiag "struct-wrong-count" res "1"

private unsafe def testStructWrongType
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  struct Pair where\n" ++
    "    left : UInt64\n" ++
    "    right : UInt64\n"
  let resolved ← resolveProgram session "struct-wrong-type" body
  let pairType : TypeV1 := .named (← mkName "Pair")
  let expr := ExprV1.constructor (← mkQn #["Pair"]) #[b true, u 1]
  let res := typeCheckExpr emptyScope resolved.tables (some pairType) expr
  expectExprDiag "struct-wrong-type" res "UInt64"
  expectExprDiag "struct-wrong-type" res "Bool"

private unsafe def testNamedTypeResultFeedsPlace
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  struct Pair where\n" ++
    "    left : UInt64\n" ++
    "    right : UInt64\n" ++
    "  state p : Pair\n"
  let resolved ← resolveProgram session "named-type-feeds-place" body
  let ctor := ExprV1.constructor (← mkQn #["Pair"]) #[u 1, u 2]
  let cmp := ExprV1.binary .eq ctor (← place "p")
  let res := typeCheckExpr (scopeFromTables resolved.tables) resolved.tables (some .bool) cmp
  expectExprOk "named-type-feeds-place" res .bool

private unsafe def testLocalCallExactParams
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  fn add(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return 0\n" ++
    "  const target : UInt64 := add(1, 2)\n"
  expectConstOk session "local-call-exact" body "target" (.uint 64)

private unsafe def testLocalCallZeroArg
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  fn zero() : UInt64 do\n" ++
    "    return 0\n" ++
    "  const target : UInt64 := zero()\n"
  expectConstOk session "local-call-zero" body "target" (.uint 64)

private unsafe def testLocalCallResultInBinary
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  fn add(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return 0\n" ++
    "  const target : UInt64 := add(1, 2) + 3\n"
  expectConstOk session "local-call-binary" body "target" (.uint 64)

private unsafe def testLocalCallWrongCount
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  fn add(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return 0\n" ++
    "  const target : UInt64 := add(1)\n"
  let res ← typeCheckConst session "local-call-wrong-count" body "target"
  expectExprDiag "local-call-wrong-count" res "2"
  expectExprDiag "local-call-wrong-count" res "1"

private unsafe def testLocalCallWrongType
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  fn add(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return 0\n" ++
    "  const target : UInt64 := add(true, 1)\n"
  let res ← typeCheckConst session "local-call-wrong-type" body "target"
  expectExprDiag "local-call-wrong-type" res "UInt64"
  expectExprDiag "local-call-wrong-type" res "Bool"

private unsafe def testWrongCategoryCalleeEntry
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  entry g() : UInt64 do\n" ++
    "    return 0\n"
  let resolved ← resolveProgram session "callee-entry" body
  let expr := ExprV1.localCall (← mkName "g") #[]
  let res := typeCheckExpr emptyScope resolved.tables (some (.uint 64)) expr
  expectExprDiag "callee-entry" res "entry"
  expectExprDiag "callee-entry" res "function"

private unsafe def testWrongCategoryCalleeView
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  view v() : UInt64 do\n" ++
    "    return 0\n"
  let resolved ← resolveProgram session "callee-view" body
  let expr := ExprV1.localCall (← mkName "v") #[]
  let res := typeCheckExpr emptyScope resolved.tables (some (.uint 64)) expr
  expectExprDiag "callee-view" res "view"
  expectExprDiag "callee-view" res "function"

private unsafe def testWrongCategoryCalleeState
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state s : UInt64\n"
  let resolved ← resolveProgram session "callee-state" body
  let expr := ExprV1.localCall (← mkName "s") #[]
  let res := typeCheckExpr emptyScope resolved.tables (some (.uint 64)) expr
  expectExprDiag "callee-state" res "state"
  expectExprDiag "callee-state" res "function"

private unsafe def testWrongCategoryCalleeConst
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  const c : UInt64 := 0\n"
  let resolved ← resolveProgram session "callee-const" body
  let expr := ExprV1.localCall (← mkName "c") #[]
  let res := typeCheckExpr emptyScope resolved.tables (some (.uint 64)) expr
  expectExprDiag "callee-const" res "const"
  expectExprDiag "callee-const" res "function"

private unsafe def testParamShadowsFnCall
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ParamShadowFn where\n" ++
    "  fn helper() : UInt64 do\n" ++
    "    return 0\n" ++
    "  entry run(helper : UInt64) : UInt64 do\n" ++
    "    return helper\n"
  let resolved ← resolveRawProgram session "param-shadow-fn" body
  let scope ← match scopeFromCallable resolved.tables (← mkName "run") with
    | .ok s => pure s
    | .error e => throw <| IO.userError e
  let expr := ExprV1.localCall (← mkName "helper") #[]
  let res := typeCheckExpr scope resolved.tables (some (.uint 64)) expr
  expectExprDiag "param-shadow-fn" res "parameter"
  expectExprDiag "param-shadow-fn" res "function"

private unsafe def testLocalShadowsFnCall
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  fn helper() : UInt64 do\n" ++
    "    return 0\n"
  let resolved ← resolveProgram session "local-shadow-fn" body
  let scope := addBinding (scopeFromTables resolved.tables)
    (← mkName "helper") (.uint 64)
  let expr := ExprV1.localCall (← mkName "helper") #[]
  let res := typeCheckExpr scope resolved.tables (some (.uint 64)) expr
  expectExprDiag "local-shadow-fn" res "local"
  expectExprDiag "local-shadow-fn" res "function"

private unsafe def testWrongCategoryEnumName
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  struct S where\n" ++
    "    x : UInt64\n"
  let resolved ← resolveProgram session "wrong-category-enum-name" body
  let expr := ExprV1.constructor (← mkQn #["S", "V"]) #[u 1]
  let res := typeCheckExpr emptyScope resolved.tables none expr
  expectExprDiag "wrong-category-enum-name" res "struct"
  expectExprDiag "wrong-category-enum-name" res "constructor"

private unsafe def testConstructorResultTypeMismatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  struct Pair where\n" ++
    "    left : UInt64\n" ++
    "    right : UInt64\n"
  let resolved ← resolveProgram session "ctor-result-mismatch" body
  let expr := ExprV1.constructor (← mkQn #["Pair"]) #[u 1, u 2]
  let res := typeCheckExpr emptyScope resolved.tables (some .bool) expr
  expectExprDiag "ctor-result-mismatch" res "Bool"
  expectExprDiag "ctor-result-mismatch" res "Pair"

private unsafe def testLocalCallResultTypeMismatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  fn f() : UInt64 do\n" ++
    "    return 0\n" ++
    "  const target : Bool := f()\n"
  let res ← typeCheckConst session "local-call-result-mismatch" body "target"
  expectExprDiag "local-call-result-mismatch" res "Bool"
  expectExprDiag "local-call-result-mismatch" res "UInt64"

private unsafe def testAmbiguousConstructorStructEnum
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  struct Foo where\n" ++
    "    x : UInt64\n" ++
    "  enum Foo where\n" ++
    "    | Foo\n"
  let resolved ← resolveProgram session "ctor-ambiguous" body
  let expr := ExprV1.constructor (← mkQn #["Foo"]) #[]
  let res := typeCheckExpr emptyScope resolved.tables none expr
  expectExprDiag "ctor-ambiguous" res "ambiguous"
  expectExprDiag "ctor-ambiguous" res "Foo"

private unsafe def testSourceOrderConstructorPathBeforeArgs
    (session : Language.Loader.ParserSession) : IO Unit := do
  let resolved ← resolveProgram session "ctor-path-before-args" ""
  let expr := ExprV1.constructor (← mkQn #["Unknown", "C"]) #[u 1]
  let res := typeCheckExpr emptyScope resolved.tables none expr
  let msgs := messages res
  unless msgs.size == 2 do
    throw <| IO.userError s!"ctor-path-before-args: expected exactly two diagnostics, got {msgs}"
  unless msgs[0]! == "unknown name 'Unknown' (expected constructor enum)" do
    throw <| IO.userError s!"ctor-path-before-args: first diag mismatch, got {msgs}"
  unless msgs[1]! == "type mismatch: expected integer type, got integer literal" do
    throw <| IO.userError s!"ctor-path-before-args: second diag mismatch, got {msgs}"

private unsafe def testSourceOrderCalleeBeforeArgs
    (session : Language.Loader.ParserSession) : IO Unit := do
  let resolved ← resolveProgram session "callee-before-args" ""
  let expr := ExprV1.localCall (← mkName "unknown") #[u 1]
  let res := typeCheckExpr emptyScope resolved.tables none expr
  let msgs := messages res
  unless msgs.size == 2 do
    throw <| IO.userError s!"callee-before-args: expected exactly two diagnostics, got {msgs}"
  unless msgs[0]! == "unknown name 'unknown' (expected function)" do
    throw <| IO.userError s!"callee-before-args: first diag mismatch, got {msgs}"
  unless msgs[1]! == "type mismatch: expected integer type, got integer literal" do
    throw <| IO.userError s!"callee-before-args: second diag mismatch, got {msgs}"

private unsafe def testSourceOrderArgsEarlierBeforeLater
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state x : Bool\n" ++
    "  state y : UInt32\n" ++
    "  fn add(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return 0\n"
  let resolved ← resolveProgram session "args-order" body
  let expr := ExprV1.localCall (← mkName "add") #[← place "x", ← place "y"]
  let res := typeCheckExpr (scopeFromTables resolved.tables) resolved.tables (some (.uint 64)) expr
  let msgs := messages res
  unless msgs.size == 2 do
    throw <| IO.userError s!"args-order: expected exactly two diagnostics, got {msgs}"
  unless msgs[0]! == "type mismatch: expected UInt64, got Bool" do
    throw <| IO.userError s!"args-order: first diag mismatch, got {msgs}"
  unless msgs[1]! == "type mismatch: expected UInt64, got UInt32" do
    throw <| IO.userError s!"args-order: second diag mismatch, got {msgs}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testEnumVariantWithPayload session
  testEnumVariantWithoutPayload session
  testEnumWrongCount session
  testEnumWrongType session
  testStructConstructorExact session
  testStructConstructorNested session
  testStructWrongCount session
  testStructWrongType session
  testNamedTypeResultFeedsPlace session
  testLocalCallExactParams session
  testLocalCallZeroArg session
  testLocalCallResultInBinary session
  testLocalCallWrongCount session
  testLocalCallWrongType session
  testWrongCategoryCalleeEntry session
  testWrongCategoryCalleeView session
  testWrongCategoryCalleeState session
  testWrongCategoryCalleeConst session
  testParamShadowsFnCall session
  testLocalShadowsFnCall session
  testWrongCategoryEnumName session
  testConstructorResultTypeMismatch session
  testLocalCallResultTypeMismatch session
  testAmbiguousConstructorStructEnum session
  testSourceOrderConstructorPathBeforeArgs session
  testSourceOrderCalleeBeforeArgs session
  testSourceOrderArgsEarlierBeforeLater session
  IO.println "Tests.Typed.TypeCheckCallsV1: ok"

end Tests.Typed.TypeCheckCallsV1
