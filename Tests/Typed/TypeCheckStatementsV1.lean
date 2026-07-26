import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1
import ProofForgeV2.Typed.TypeCheckV1

namespace Tests.Typed.TypeCheckStatementsV1

open ProofForgeV2
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

private def messages (res : TypeCheckProgramResultV1) : Array String :=
  res.diagnostics.map (·.message)

private def contains (haystack : Array String) (needle : String) : Bool :=
  haystack.any (·.contains needle)

private def unitProgram (prelude body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program TypeCheckStatements where\n" ++
  prelude ++
  "  entry run() do\n" ++
  body

private def resultProgram (prelude body result : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program TypeCheckStatements where\n" ++
  prelude ++
  "  entry run() : " ++ result ++ " do\n" ++
  body

private unsafe def typeCheckUnit
    (session : Language.Loader.ParserSession) (label prelude body : String) :
    IO TypeCheckProgramResultV1 := do
  match ← session.selectProgramV1 (unitProgram prelude body)
      ("<type-check-statements-" ++ label ++ ">")
      "Tests.TypeCheckStatementsV1" none with
  | .ok validated => pure (typeCheckProgramV1 validated.program (resolveProgramV1 validated))
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private unsafe def typeCheckResult
    (session : Language.Loader.ParserSession) (label prelude body result : String) :
    IO TypeCheckProgramResultV1 := do
  match ← session.selectProgramV1 (resultProgram prelude body result)
      ("<type-check-statements-" ++ label ++ ">")
      "Tests.TypeCheckStatementsV1" none with
  | .ok validated => pure (typeCheckProgramV1 validated.program (resolveProgramV1 validated))
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private unsafe def expectOk
    (session : Language.Loader.ParserSession) (label prelude body : String) :
    IO Unit := do
  let res ← typeCheckUnit session label prelude body
  unless res.ok do
    throw <| IO.userError s!"{label}: expected ok, got {messages res}"

private unsafe def expectDiag
    (res : TypeCheckProgramResultV1) (label needle : String) : IO Unit := do
  if res.diagnostics.isEmpty then
    throw <| IO.userError s!"{label}: expected diagnostics, got ok"
  unless contains (messages res) needle do
    throw <| IO.userError s!"{label}: expected diagnostic containing '{needle}', got {messages res}"

private unsafe def testPositiveStatementTyping
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  state flag : Bool\n" ++
    "  state total : UInt64\n" ++
    "  state start : UInt64\n" ++
    "  state stop : UInt64\n" ++
    "  error Err()\n" ++
    "  event Ev()\n"
  let body :=
    "    let annotated : UInt64 := 1\n" ++
    "    let omitted := annotated\n" ++
    "    total := 2\n" ++
    "    assert flag\n" ++
    "    if flag then\n" ++
    "      total := 3\n" ++
    "    else\n" ++
    "      total := 4\n" ++
    "    for i in start ..< stop bounded 10 do\n" ++
    "      total := i\n" ++
    "    call External.Use(total)\n" ++
    "    schedule External.Use(flag)\n" ++
    "    return\n"
  expectOk session "positive-statements" prelude body

private unsafe def testLetAnnotationMismatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let res ← typeCheckUnit session "let-mismatch" "" "    let x : UInt64 := true\n"
  expectDiag res "let-mismatch" "UInt64"
  expectDiag res "let-mismatch" "Bool"

private unsafe def testAssignTargetValueMismatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude := "  state total : UInt64\n  state flag : Bool\n"
  let res ← typeCheckUnit session "assign-mismatch" prelude "    total := flag\n"
  expectDiag res "assign-mismatch" "UInt64"
  expectDiag res "assign-mismatch" "Bool"

private unsafe def testReturnResultMismatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let res ← typeCheckResult session "return-mismatch" "" "    return true\n" "UInt64"
  expectDiag res "return-mismatch" "UInt64"
  expectDiag res "return-mismatch" "Bool"

private unsafe def testValueReturnInUnitRejection
    (session : Language.Loader.ParserSession) : IO Unit := do
  let res ← typeCheckUnit session "value-return-unit" "" "    return 1\n"
  expectDiag res "value-return-unit" "Unit"
  expectDiag res "value-return-unit" "integer literal"

private unsafe def testEmptyReturnInNonUnitRejection
    (session : Language.Loader.ParserSession) : IO Unit := do
  let res ← typeCheckResult session "empty-return-nonunit" "" "    return\n" "UInt64"
  expectDiag res "empty-return-nonunit" "UInt64"
  expectDiag res "empty-return-nonunit" "empty return"

private unsafe def testRevertUnknownName
    (session : Language.Loader.ParserSession) : IO Unit := do
  let res ← typeCheckUnit session "revert-unknown" "" "    revert Unknown()\n"
  expectDiag res "revert-unknown" "unknown name 'Unknown'"

private unsafe def testRevertWrongCount
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude := "  error Err(a : UInt64)\n"
  let res ← typeCheckUnit session "revert-wrong-count" prelude "    revert Err()\n"
  expectDiag res "revert-wrong-count" "1"
  expectDiag res "revert-wrong-count" "0"

private unsafe def testRevertWrongArgType
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude := "  error Err(a : UInt64)\n"
  let res ← typeCheckUnit session "revert-wrong-type" prelude "    revert Err(true)\n"
  expectDiag res "revert-wrong-type" "UInt64"
  expectDiag res "revert-wrong-type" "Bool"

private unsafe def testEmitUnknownName
    (session : Language.Loader.ParserSession) : IO Unit := do
  let res ← typeCheckUnit session "emit-unknown" "" "    emit Unknown()\n"
  expectDiag res "emit-unknown" "unknown name 'Unknown'"

private unsafe def testEmitWrongCount
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude := "  event Ev(a : UInt64)\n"
  let res ← typeCheckUnit session "emit-wrong-count" prelude "    emit Ev()\n"
  expectDiag res "emit-wrong-count" "1"
  expectDiag res "emit-wrong-count" "0"

private unsafe def testEmitWrongArgType
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude := "  event Ev(a : UInt64)\n"
  let res ← typeCheckUnit session "emit-wrong-type" prelude "    emit Ev(true)\n"
  expectDiag res "emit-wrong-type" "UInt64"
  expectDiag res "emit-wrong-type" "Bool"

private unsafe def testAssertNonBool
    (session : Language.Loader.ParserSession) : IO Unit := do
  let res ← typeCheckUnit session "assert-non-bool" "" "    assert 1\n"
  expectDiag res "assert-non-bool" "Bool"
  expectDiag res "assert-non-bool" "integer literal"

private unsafe def testAssertUnknownElseError
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude := "  error Known()\n"
  let res ← typeCheckUnit session "assert-unknown-else" prelude "    assert true else Unknown\n"
  expectDiag res "assert-unknown-else" "unknown name 'Unknown'"

private unsafe def testIfNonBoolCondition
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    if 1 then\n" ++
    "      return 0\n" ++
    "    else\n" ++
    "      return 0\n"
  let res ← typeCheckResult session "if-non-bool" "" body "UInt64"
  expectDiag res "if-non-bool" "Bool"
  expectDiag res "if-non-bool" "integer literal"

private unsafe def testForMismatchedEndpointWidths
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  state lo : UInt64\n" ++
    "  state hi : UInt32\n"
  let body :=
    "    for i in lo ..< hi bounded 10 do\n" ++
    "      return\n"
  let res ← typeCheckUnit session "for-width-mismatch" prelude body
  expectDiag res "for-width-mismatch" "UInt64"
  expectDiag res "for-width-mismatch" "UInt32"

private unsafe def testForIteratorLeakRejection
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  state start : UInt64\n" ++
    "  state stop : UInt64\n"
  let body :=
    "    for i in start ..< stop bounded 10 do\n" ++
    "      return\n" ++
    "    return i\n"
  let res ← typeCheckUnit session "for-iterator-leak" prelude body
  expectDiag res "for-iterator-leak" "unknown name 'i'"

private unsafe def testIfBranchBinderNonLeak
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    if true then\n" ++
    "      let x := 1\n" ++
    "      return\n" ++
    "    return x\n"
  let res ← typeCheckUnit session "if-binder-leak" "" body
  expectDiag res "if-binder-leak" "unknown name 'x'"

private unsafe def testCallArgsTypeChecked
    (session : Language.Loader.ParserSession) : IO Unit := do
  let res ← typeCheckUnit session "call-args" "" "    call External.Foo(1)\n"
  expectDiag res "call-args" "integer type"
  expectDiag res "call-args" "integer literal"

private unsafe def testScheduleArgsTypeChecked
    (session : Language.Loader.ParserSession) : IO Unit := do
  let res ← typeCheckUnit session "schedule-args" "" "    schedule External.Foo(1)\n"
  expectDiag res "schedule-args" "integer type"
  expectDiag res "schedule-args" "integer literal"

private unsafe def testInvariantNonBool
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TypeCheckStatements where\n" ++
    "  invariant inv : 1\n" ++
    "  entry run() do\n" ++
    "    return\n"
  let res ← match ← session.selectProgramV1 src
      "<type-check-statements-invariant-non-bool>"
      "Tests.TypeCheckStatementsV1" none with
  | .ok validated => pure (typeCheckProgramV1 validated.program (resolveProgramV1 validated))
  | .error error => throw <| IO.userError s!"invariant-non-bool: {error.render}"
  expectDiag res "invariant-non-bool" "Bool"
  expectDiag res "invariant-non-bool" "integer literal"

private unsafe def testConstBodyWiring
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TypeCheckStatements where\n" ++
    "  const c : UInt64 := 1\n" ++
    "  entry run() do\n" ++
    "    return\n"
  let res ← match ← session.selectProgramV1 src
      "<type-check-statements-const-ok>"
      "Tests.TypeCheckStatementsV1" none with
  | .ok validated => pure (typeCheckProgramV1 validated.program (resolveProgramV1 validated))
  | .error error => throw <| IO.userError s!"const-ok: {error.render}"
  unless res.ok do
    throw <| IO.userError s!"const-ok: expected ok, got {messages res}"

private unsafe def testConstBodyMismatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TypeCheckStatements where\n" ++
    "  const c : UInt64 := true\n" ++
    "  entry run() do\n" ++
    "    return\n"
  let res ← match ← session.selectProgramV1 src
      "<type-check-statements-const-mismatch>"
      "Tests.TypeCheckStatementsV1" none with
  | .ok validated => pure (typeCheckProgramV1 validated.program (resolveProgramV1 validated))
  | .error error => throw <| IO.userError s!"const-mismatch: {error.render}"
  expectDiag res "const-mismatch" "UInt64"
  expectDiag res "const-mismatch" "Bool"

private unsafe def testInitBodyWiring
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  init() do\n" ++
    "    return\n"
  expectOk session "init-wiring" prelude "    return\n"

private unsafe def testViewBodyResultMismatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  view get() : UInt64 do\n" ++
    "    return true\n"
  let res ← typeCheckUnit session "view-mismatch" prelude "    return\n"
  expectDiag res "view-mismatch" "UInt64"
  expectDiag res "view-mismatch" "Bool"

private unsafe def testFnBodyWiring
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  fn helper(value : UInt64) : UInt64 do\n" ++
    "    return value\n"
  expectOk session "fn-wiring" prelude "    return\n"

private unsafe def testFnBodyResultMismatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  fn helper(value : UInt64) : UInt64 do\n" ++
    "    return true\n"
  let res ← typeCheckUnit session "fn-mismatch" prelude "    return\n"
  expectDiag res "fn-mismatch" "UInt64"
  expectDiag res "fn-mismatch" "Bool"

private unsafe def testSourceOrderConditionBeforeBranches
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    if 1 then\n" ++
    "      return true\n" ++
    "    else\n" ++
    "      return 0\n"
  let res ← typeCheckResult session "order-condition" "" body "UInt64"
  let msgs := messages res
  unless msgs.size >= 2 do
    throw <| IO.userError s!"order-condition: expected >=2 diagnostics, got {msgs}"
  unless msgs[0]!.contains "integer literal" do
    throw <| IO.userError s!"order-condition: first diag should mention integer literal, got {msgs}"
  unless msgs[1]!.contains "UInt64" && msgs[1]!.contains "Bool" do
    throw <| IO.userError s!"order-condition: second diag should mention UInt64 and Bool, got {msgs}"

private unsafe def testSourceOrderTargetBeforeValue
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude := "  state flag : Bool\n"
  let res ← typeCheckUnit session "order-target-value" prelude
    "    flag[0] := true\n"
  let msgs := messages res
  unless msgs.size == 1 do
    throw <| IO.userError s!"order-target-value: expected exactly 1 diagnostic, got {msgs}"
  unless msgs[0]!.contains "Array or Map" do
    throw <| IO.userError s!"order-target-value: expected target-place diagnostic, got {msgs}"

private unsafe def testSourceOrderNameBeforeArgs
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude := "  error Err(a : UInt64)\n"
  let res ← typeCheckUnit session "order-name-args" prelude "    revert Err(true, 2)\n"
  let msgs := messages res
  unless msgs.size >= 2 do
    throw <| IO.userError s!"order-name-args: expected >=2 diagnostics, got {msgs}"
  unless msgs[0]!.contains "1" && msgs[0]!.contains "2" do
    throw <| IO.userError s!"order-name-args: first diag should be count mismatch, got {msgs}"
  unless msgs[1]!.contains "integer literal" do
    throw <| IO.userError s!"order-name-args: second diag should mention integer literal, got {msgs}"

private unsafe def testSourceOrderEarlierBeforeLater
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    let x : UInt64 := true\n" ++
    "    let y : Bool := 1\n"
  let res ← typeCheckUnit session "order-earlier-later" "" body
  let msgs := messages res
  unless msgs.size >= 2 do
    throw <| IO.userError s!"order-earlier-later: expected >=2 diagnostics, got {msgs}"
  unless msgs[0]!.contains "UInt64" do
    throw <| IO.userError s!"order-earlier-later: first diag should mention UInt64, got {msgs}"
  unless msgs[1]!.contains "integer literal" do
    throw <| IO.userError s!"order-earlier-later: second diag should mention integer literal, got {msgs}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testPositiveStatementTyping session
  testLetAnnotationMismatch session
  testAssignTargetValueMismatch session
  testReturnResultMismatch session
  testValueReturnInUnitRejection session
  testEmptyReturnInNonUnitRejection session
  testRevertUnknownName session
  testRevertWrongCount session
  testRevertWrongArgType session
  testEmitUnknownName session
  testEmitWrongCount session
  testEmitWrongArgType session
  testAssertNonBool session
  testAssertUnknownElseError session
  testIfNonBoolCondition session
  testForMismatchedEndpointWidths session
  testForIteratorLeakRejection session
  testIfBranchBinderNonLeak session
  testCallArgsTypeChecked session
  testScheduleArgsTypeChecked session
  testInvariantNonBool session
  testConstBodyWiring session
  testConstBodyMismatch session
  testInitBodyWiring session
  testViewBodyResultMismatch session
  testFnBodyWiring session
  testFnBodyResultMismatch session
  testSourceOrderConditionBeforeBranches session
  testSourceOrderTargetBeforeValue session
  testSourceOrderNameBeforeArgs session
  testSourceOrderEarlierBeforeLater session
  IO.println "Tests.Typed.TypeCheckStatementsV1: ok"

end Tests.Typed.TypeCheckStatementsV1
