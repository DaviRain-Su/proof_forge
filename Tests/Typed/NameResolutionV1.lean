import Tests.Language.ParserSession
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1

namespace Tests.Typed.NameResolutionV1

open ProofForgeV2
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def findOrdinal? {α} (raw : String)
    (table : DeclTableV1 SourceNameComponentV1 α) : Option Nat := do
  let name ← match parseSourceNameComponentV1 raw with | .ok n => some n | .error _ => none
  let (o, _) ← table.find? name
  some o

private def findQnOrdinal? {α} (raws : Array String)
    (table : DeclTableV1 SourceQualifiedNameV1 α) : Option Nat := do
  let qn ← match parseSourceQualifiedNameV1 raws with | .ok q => some q | .error _ => none
  let (o, _) ← table.find? qn
  some o

private def moduleName : String := "Tests.NameResolutionV1"

private unsafe def resolveSource
    (session : Language.Loader.ParserSession) (label source : String) :
    IO NameResolutionResultV1 := do
  match ← session.selectProgramV1 source ("<name-resolution-" ++ label ++ ">") moduleName none with
  | .ok validated => pure (resolveProgramV1 validated)
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def expectOk (result : NameResolutionResultV1) (label : String) : IO Unit := do
  unless result.ok do
    throw <| IO.userError s!"{label}: expected ok, got diagnostics {repr result.diagnostics}"

private def expectNotOk (result : NameResolutionResultV1) (label : String) : IO Unit := do
  if result.ok then
    throw <| IO.userError s!"{label}: expected diagnostics, got ok"

private def messages (result : NameResolutionResultV1) : Array String :=
  result.diagnostics.map (·.message)

private def contains (haystack : Array String) (needle : String) : Bool :=
  haystack.any (·.contains needle)

private def allDeclarationsSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Full where\n" ++
  "  state total : UInt64\n" ++
  "  struct Pair where\n" ++
  "    left : UInt64\n" ++
  "  enum Choice where\n" ++
  "    | None\n" ++
  "    | Some(UInt64)\n" ++
  "  const one : UInt64 := 1\n" ++
  "  event Changed(private value : UInt64)\n" ++
  "  error Failed\n" ++
  "  init(seed : UInt64) do\n" ++
  "    total := seed\n" ++
  "  entry add(amount : UInt64) : UInt64 do\n" ++
  "    return amount\n" ++
  "  view current() : UInt64 do\n" ++
  "    return total\n" ++
  "  fn identity(value : UInt64) : UInt64 do\n" ++
  "    return value\n" ++
  "  invariant initialized : true\n" ++
  "  requires extension proof.forge.feature version \"1.0.0\"\n" ++
  "    digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"\n" ++
  "  proof initialized using Tests.Theorems.initialized\n"

private unsafe def testAllDeclarationTables
    (session : Language.Loader.ParserSession) : IO Unit := do
  let result ← resolveSource session "all-declarations" allDeclarationsSource
  expectOk result "all-declarations"
  let tables := result.tables
  expect (tables.state.size == 1) "state table size"
  expect (findOrdinal? "total" tables.state == some 0) "state ordinal"
  expect (tables.struct.size == 1) "struct table size"
  expect ((findOrdinal? "Pair" tables.struct).isSome) "struct lookup"
  expect (tables.enum.size == 1) "enum table size"
  expect ((findOrdinal? "Choice" tables.enum).isSome) "enum lookup"
  expect (tables.const.size == 1) "const table size"
  expect ((findOrdinal? "one" tables.const).isSome) "const lookup"
  expect (tables.event.size == 1) "event table size"
  expect ((findOrdinal? "Changed" tables.event).isSome) "event lookup"
  expect (tables.error.size == 1) "error table size"
  expect ((findOrdinal? "Failed" tables.error).isSome) "error lookup"
  expect (tables.init.size == 1) "init table size"
  expect (tables.entry.size == 1) "entry table size"
  expect ((findOrdinal? "add" tables.entry).isSome) "entry lookup"
  expect (tables.view.size == 1) "view table size"
  expect ((findOrdinal? "current" tables.view).isSome) "view lookup"
  expect (tables.fn.size == 1) "fn table size"
  expect ((findOrdinal? "identity" tables.fn).isSome) "fn lookup"
  expect (tables.invariant.size == 1) "invariant table size"
  expect ((findOrdinal? "initialized" tables.invariant).isSome) "invariant lookup"
  expect (tables.extensionReq.size == 1) "extension table size"
  expect ((findQnOrdinal? #["proof", "forge", "feature"] tables.extensionReq).isSome)
    "extension lookup"
  expect (tables.proof.size == 1) "proof table size"
  expect ((findOrdinal? "initialized" tables.proof).isSome) "proof lookup"

private unsafe def testParamShadowsState
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ParamShadow where\n" ++
    "  state x : UInt64\n" ++
    "  entry f(x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  let result ← resolveSource session "param-shadow" source
  expectOk result "param-shadow"

private unsafe def testLetShadowing
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program LetShadow where\n" ++
    "  state x : UInt64\n" ++
    "  entry f() : UInt64 do\n" ++
    "    let x := 1\n" ++
    "    return x\n"
  let result ← resolveSource session "let-shadow" source
  expectOk result "let-shadow"

private unsafe def testMatchBinderDoesNotLeak
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MatchLeak where\n" ++
    "  entry f(flag : Bool) : UInt64 do\n" ++
    "    match flag with\n" ++
    "    | y => do\n" ++
    "      return 0\n" ++
    "    return y\n"
  let result ← resolveSource session "match-leak" source
  expectNotOk result "match-leak"
  unless contains (messages result) "unknown name 'y'" do
    throw <| IO.userError s!"match-leak: expected unknown 'y', got {messages result}"

private unsafe def testForIteratorDoesNotLeak
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ForLeak where\n" ++
    "  entry f() : UInt64 do\n" ++
    "    for i in 0 ..< 1 bounded 1 do\n" ++
    "      return i\n" ++
    "    return i\n"
  let result ← resolveSource session "for-leak" source
  expectNotOk result "for-leak"
  unless contains (messages result) "unknown name 'i'" do
    throw <| IO.userError s!"for-leak: expected unknown 'i', got {messages result}"

private unsafe def testLocalCallAcceptsFn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program FnCall where\n" ++
    "  fn helper() : UInt64 do\n" ++
    "    return 0\n" ++
    "  entry run() : UInt64 do\n" ++
    "    let r := helper()\n" ++
    "    return r\n"
  let result ← resolveSource session "fn-call" source
  expectOk result "fn-call"

private unsafe def testLocalCallRejectsEntry
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EntryCall where\n" ++
    "  entry g() : UInt64 do\n" ++
    "    return 0\n" ++
    "  fn h() : UInt64 do\n" ++
    "    return g()\n"
  let result ← resolveSource session "entry-call" source
  expectNotOk result "entry-call"
  unless contains (messages result) "name 'g' resolved to entry but expected function" do
    throw <| IO.userError s!"entry-call: got {messages result}"

private unsafe def testLocalCallRejectsState
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program StateCall where\n" ++
    "  state s : UInt64\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return s()\n"
  let result ← resolveSource session "state-call" source
  expectNotOk result "state-call"
  unless contains (messages result) "name 's' resolved to state but expected function" do
    throw <| IO.userError s!"state-call: got {messages result}"

private unsafe def testLocalCallRejectsConst
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ConstCall where\n" ++
    "  const c : UInt64 := 0\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return c()\n"
  let result ← resolveSource session "const-call" source
  expectNotOk result "const-call"
  unless contains (messages result) "name 'c' resolved to const but expected function" do
    throw <| IO.userError s!"const-call: got {messages result}"

private unsafe def testParamShadowsFnCall
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ParamShadowFn where\n" ++
    "  state total : UInt64\n" ++
    "  fn helper() : UInt64 do\n" ++
    "    return 0\n" ++
    "  entry run(helper : UInt64) : UInt64 do\n" ++
    "    return helper()\n"
  let result ← resolveSource session "param-shadow-fn" source
  expectNotOk result "param-shadow-fn"
  unless contains (messages result) "name 'helper' is bound as a parameter but used as a function" do
    throw <| IO.userError s!"param-shadow-fn: got {messages result}"

private unsafe def testUnknownConstructorExpr
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program UnknownCtorExpr where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return Unknown.C(1)\n"
  let result ← resolveSource session "unknown-ctor-expr" source
  expectNotOk result "unknown-ctor-expr"
  unless contains (messages result) "unknown name 'Unknown' (expected constructor enum)" do
    throw <| IO.userError s!"unknown-ctor-expr: got {messages result}"

private unsafe def testWrongCategoryConstructorExpr
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program WrongCategoryCtorExpr where\n" ++
    "  state x : UInt64\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return x.C(1)\n"
  let result ← resolveSource session "wrong-category-ctor-expr" source
  expectNotOk result "wrong-category-ctor-expr"
  unless contains (messages result) "name 'x' resolved to state but expected constructor" do
    throw <| IO.userError s!"wrong-category-ctor-expr: got {messages result}"

private unsafe def testUnknownConstructorPattern
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program UnknownCtorPattern where\n" ++
    "  entry run(flag : Bool) : UInt64 do\n" ++
    "    match flag with\n" ++
    "    | Unknown.X() => do\n" ++
    "      return 0\n"
  let result ← resolveSource session "unknown-ctor-pattern" source
  expectNotOk result "unknown-ctor-pattern"
  unless contains (messages result) "unknown name 'Unknown' (expected constructor enum)" do
    throw <| IO.userError s!"unknown-ctor-pattern: got {messages result}"

private unsafe def testWrongCategoryConstructorPattern
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program WrongCategoryCtorPattern where\n" ++
    "  state x : UInt64\n" ++
    "  entry run(flag : Bool) : UInt64 do\n" ++
    "    match flag with\n" ++
    "    | x.Y() => do\n" ++
    "      return 0\n"
  let result ← resolveSource session "wrong-category-ctor-pattern" source
  expectNotOk result "wrong-category-ctor-pattern"
  unless contains (messages result) "name 'x' resolved to state but expected constructor" do
    throw <| IO.userError s!"wrong-category-ctor-pattern: got {messages result}"

private unsafe def testUnknownErrorAssert
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program UnknownErrorAssert where\n" ++
    "  entry run(flag : Bool) : UInt64 do\n" ++
    "    assert flag else UnknownError\n" ++
    "    return 0\n"
  let result ← resolveSource session "unknown-error-assert" source
  expectNotOk result "unknown-error-assert"
  unless contains (messages result) "unknown name 'UnknownError' (expected error)" do
    throw <| IO.userError s!"unknown-error-assert: got {messages result}"

private unsafe def testUnknownErrorRevert
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program UnknownErrorRevert where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    revert UnknownError\n"
  let result ← resolveSource session "unknown-error-revert" source
  expectNotOk result "unknown-error-revert"
  unless contains (messages result) "unknown name 'UnknownError' (expected error)" do
    throw <| IO.userError s!"unknown-error-revert: got {messages result}"

private unsafe def testUnknownEventEmit
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program UnknownEventEmit where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    emit UnknownEvent()\n"
  let result ← resolveSource session "unknown-event-emit" source
  expectNotOk result "unknown-event-emit"
  unless contains (messages result) "unknown name 'UnknownEvent' (expected event)" do
    throw <| IO.userError s!"unknown-event-emit: got {messages result}"

private unsafe def testAmbiguousStateConst
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program AmbiguousVal where\n" ++
    "  state x : UInt64\n" ++
    "  const x : UInt64 := 0\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return x\n"
  let result ← resolveSource session "ambiguous-state-const" source
  expectNotOk result "ambiguous-state-const"
  unless contains (messages result) "ambiguous name 'x' (expected value)" do
    throw <| IO.userError s!"ambiguous-state-const: got {messages result}"

private unsafe def testNamedTypeResolution
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program NamedTypes where\n" ++
    "  struct S where x : UInt64\n" ++
    "  enum E where | A\n" ++
    "  const C : UInt64 := 0\n" ++
    "  state s : UInt64\n" ++
    "  state goodS : S\n" ++
    "  state goodE : E\n" ++
    "  state badC : C\n" ++
    "  state badS : s\n" ++
    "  state badU : Unknown\n" ++
    "  entry ok() : UInt64 do return 0\n"
  let result ← resolveSource session "named-types" source
  expectNotOk result "named-types"
  let msgs := messages result
  unless contains msgs "name 'C' resolved to const but expected type" do
    throw <| IO.userError s!"named-types: expected const-wrong-category, got {msgs}"
  unless contains msgs "name 's' resolved to state but expected type" do
    throw <| IO.userError s!"named-types: expected state-wrong-category, got {msgs}"
  unless contains msgs "unknown name 'Unknown' (expected type)" do
    throw <| IO.userError s!"named-types: expected unknown type, got {msgs}"

private unsafe def testDiagnosticSourceOrder
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program SourceOrder where\n" ++
    "  entry f() : UInt64 do\n" ++
    "    let a := unknown1\n" ++
    "    return unknown2\n"
  let result ← resolveSource session "source-order" source
  expectNotOk result "source-order"
  let msgs := messages result
  unless msgs.size >= 2 do
    throw <| IO.userError s!"source-order: expected at least two diagnostics, got {msgs}"
  unless msgs[0]!.contains "unknown1" do
    throw <| IO.userError s!"source-order: first diagnostic should mention unknown1, got {msgs}"
  unless msgs[1]!.contains "unknown2" do
    throw <| IO.userError s!"source-order: second diagnostic should mention unknown2, got {msgs}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testAllDeclarationTables session
  testParamShadowsState session
  testLetShadowing session
  testMatchBinderDoesNotLeak session
  testForIteratorDoesNotLeak session
  testLocalCallAcceptsFn session
  testLocalCallRejectsEntry session
  testLocalCallRejectsState session
  testLocalCallRejectsConst session
  testParamShadowsFnCall session
  testUnknownConstructorExpr session
  testWrongCategoryConstructorExpr session
  testUnknownConstructorPattern session
  testWrongCategoryConstructorPattern session
  testUnknownErrorAssert session
  testUnknownErrorRevert session
  testUnknownEventEmit session
  testAmbiguousStateConst session
  testNamedTypeResolution session
  testDiagnosticSourceOrder session
  IO.println "Tests.Typed.NameResolutionV1: ok"

end Tests.Typed.NameResolutionV1
