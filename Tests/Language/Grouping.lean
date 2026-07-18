import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

-- GroupingSurface pins parenthesized expressions in every declaration body position:
-- init, entry, view, and fn. Covers return-value and let-value reachability for
-- literal, variable, Bool, and binary grouping sugar (no new Source.Expr ctor).
namespace Tests.Language.GroupingFixture

open ProofForgeV2.Language

program GroupingSurface where
  init() do
    let seed : UInt64 := (42)
    return seed

  entry run(x : UInt64) : UInt64 do
    return (x)

  view peek() : UInt64 do
    let flag := (true)
    return (0)

  fn helper() : UInt64 do
    return (2 + 3)

end Tests.Language.GroupingFixture

namespace Tests.Language.Grouping

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Fixed identity reused from D1-PA-22 for right-nested subtraction goldens. -/
private def subTwin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.CheckedSubFixture.CheckedSubTwin" "CheckedSubTwin" #[
    .entry {
      name := "run"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[.returnValue expr]
    }
  ]

/-- Fixed identity reused from D1-PA-23 for right-nested multiplication goldens. -/
private def mulTwin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.CheckedMulFixture.CheckedMulTwin" "CheckedMulTwin" #[
    .entry {
      name := "run"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[.returnValue expr]
    }
  ]

private def surfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.GroupingFixture\n\n" ++
  "program GroupingSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := (42)\n" ++
  "    return seed\n\n" ++
  "  entry run(x : UInt64) : UInt64 do\n" ++
  "    return (x)\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let flag := (true)\n" ++
  "    return (0)\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return (2 + 3)\n\n" ++
  "end Tests.Language.GroupingFixture\n"

private def returnProgramSource (name expr : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  entry run() : UInt64 do\n" ++
  "    return " ++ expr ++ "\n"

private def varReturnProgramSource (name expr : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  entry run(x : UInt64) : UInt64 do\n" ++
  "    return " ++ expr ++ "\n"

private def qualifiedReturnProgramSource (namespaceName name expr : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace " ++ namespaceName ++ "\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  entry run() : UInt64 do\n" ++
  "    return " ++ expr ++ "\n\n" ++
  "end " ++ namespaceName ++ "\n"

private def expectParserRejected (label source : String)
    (result : CompileResult (Array Source.Program)) : IO Unit := do
  match result with
  | .error (.invalidProgram message) =>
      expect (message.startsWith "Lean parser rejected source: failed to parse file")
        s!"{label}: expected parser-boundary rejection, got {message}"
  | .error other =>
      throw <| IO.userError s!"{label}: reached wrong failure for {source}: {other.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private unsafe def select (session : Language.Loader.ParserSession)
    (input path : String) : IO Source.Program := do
  match ← session.selectProgram input path none with
  | .ok sourceProgram => pure sourceProgram
  | .error error => throw <| IO.userError error.render

/-- Assert entry body is exactly `return <expr>`. -/
private def expectReturnExpr (label : String) (sourceProgram : Source.Program)
    (expr : Source.Expr) : IO Unit := do
  match sourceProgram.entries with
  | #[runEntry] =>
      expect (runEntry.body == #[.returnValue expr])
        s!"{label}: entry body must be return of expected expression"
  | _ => throw <| IO.userError s!"{label}: expected a single entry"

/-- Full program equality for bare vs grouped sugar under identical identities. -/
private def expectDesugarEqual (label : String) (bare grouped : Source.Program) : IO Unit := do
  expect (bare == grouped)
    s!"{label}: bare and grouped programs must share the same Source AST"
  expect (bare.canonicalBytes == grouped.canonicalBytes)
    s!"{label}: bare and grouped programs must share canonical bytes"
  expect (bare.sourceHash == grouped.sourceHash)
    s!"{label}: bare and grouped programs must share sourceHash"

unsafe def run : IO Unit := do
  let elaborated := Tests.Language.GroupingFixture.GroupingSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64) (.literal 42),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must desugar let seed : UInt64 := (42) to literal 42"
  | none => throw <| IO.userError "GroupingSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.variable "x")] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must desugar return (x) to variable x"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "flag" none (.boolLiteral true),
          .returnValue (.literal 0)] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must desugar let flag := (true) and return (0)"
  | _ => throw <| IO.userError "GroupingSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue (.checkedAdd (.literal 2) (.literal 3))] => pure ()
      | _ =>
          throw <| IO.userError
            "fn body must desugar return (2 + 3) to checkedAdd"
  | _ => throw <| IO.userError "GroupingSurface must retain helper fn"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<grouping>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same grouping Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same grouping sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Redundant grouping desugars to identical AST / bytes / sourceHash.
  let bare42 ← select session
    (returnProgramSource "EqLit" "42") "<eq-lit-bare>"
  let group42 ← select session
    (returnProgramSource "EqLit" "(42)") "<eq-lit-group>"
  expectDesugarEqual "(42) == 42" bare42 group42
  expectReturnExpr "(42)" group42 (.literal 42)

  let bareX ← select session
    (varReturnProgramSource "EqVar" "x") "<eq-var-bare>"
  let groupX ← select session
    (varReturnProgramSource "EqVar" "((x))") "<eq-var-group>"
  expectDesugarEqual "((x)) == x" bareX groupX
  expectReturnExpr "((x))" groupX (.variable "x")

  let bareAdd ← select session
    (returnProgramSource "EqAdd" "2 + 3") "<eq-add-bare>"
  let groupAdd ← select session
    (returnProgramSource "EqAdd" "((2 + 3))") "<eq-add-group>"
  expectDesugarEqual "((2 + 3)) == 2 + 3" bareAdd groupAdd
  expectReturnExpr "((2 + 3))" groupAdd
    (.checkedAdd (.literal 2) (.literal 3))

  -- Grouping override AST pins (inner pfExpr:0 must accept full + expression).
  let addThenMul ← select session
    (returnProgramSource "AddThenMul" "(2 + 3) * 4") "<group-add-then-mul>"
  expectReturnExpr "(2 + 3) * 4" addThenMul
    (.checkedMul (.checkedAdd (.literal 2) (.literal 3)) (.literal 4))

  let rightSub ← select session
    (returnProgramSource "RightSub" "7 - (3 - 1)") "<group-right-sub>"
  expectReturnExpr "7 - (3 - 1)" rightSub
    (.checkedSub (.literal 7) (.checkedSub (.literal 3) (.literal 1)))

  let rightMul ← select session
    (returnProgramSource "RightMul" "2 * (3 * 4)") "<group-right-mul>"
  expectReturnExpr "2 * (3 * 4)" rightMul
    (.checkedMul (.literal 2) (.checkedMul (.literal 3) (.literal 4)))

  let mulOfAdd ← select session
    (returnProgramSource "MulOfAdd" "2 * (3 + 4)") "<group-mul-of-add>"
  expectReturnExpr "2 * (3 + 4)" mulOfAdd
    (.checkedMul (.literal 2) (.checkedAdd (.literal 3) (.literal 4)))

  -- Reuse CheckedSubTwin / CheckedMulTwin identities for right-nest goldens.
  let rightSubTwin := subTwin
    (.checkedSub (.literal 7) (.checkedSub (.literal 3) (.literal 1)))
  let leftSubTwin := subTwin
    (.checkedSub (.checkedSub (.literal 7) (.literal 3)) (.literal 1))
  let groupedRightSubTwin ← select session
    (qualifiedReturnProgramSource "Tests.Language.CheckedSubFixture"
      "CheckedSubTwin" "7 - (3 - 1)")
    "<group-checked-sub-twin>"
  expectDesugarEqual "grouped CheckedSubTwin right nest"
    rightSubTwin groupedRightSubTwin
  expect (rightSubTwin.sourceHash ==
      "7e6a2c24a6cad28e5984f2279dce0df9fdd863c6ea1062334cb32b69027e7e3a")
    s!"CheckedSubTwin right nest sourceHash golden must remain stable; got {rightSubTwin.sourceHash}"
  expect (rightSubTwin.canonicalBytes.size == 238)
    s!"CheckedSubTwin right nest size golden must remain stable; got {rightSubTwin.canonicalBytes.size}"
  expect (rightSubTwin.sourceHash != leftSubTwin.sourceHash)
    "right-nested 7-(3-1) must not alias left-nested (7-3)-1"

  let rightMulTwin := mulTwin
    (.checkedMul (.literal 2) (.checkedMul (.literal 3) (.literal 4)))
  let leftMulTwin := mulTwin
    (.checkedMul (.checkedMul (.literal 2) (.literal 3)) (.literal 4))
  let groupedRightMulTwin ← select session
    (qualifiedReturnProgramSource "Tests.Language.CheckedMulFixture"
      "CheckedMulTwin" "2 * (3 * 4)")
    "<group-checked-mul-right-twin>"
  expectDesugarEqual "grouped CheckedMulTwin right nest"
    rightMulTwin groupedRightMulTwin
  expect (rightMulTwin.sourceHash ==
      "f4b9a861619b742361e41f69342f07dc9c338daa9b9a520073b8aa2fa990c13c")
    s!"CheckedMulTwin right nest sourceHash golden must remain stable; got {rightMulTwin.sourceHash}"
  expect (rightMulTwin.canonicalBytes.size == 238)
    s!"CheckedMulTwin right nest size golden must remain stable; got {rightMulTwin.canonicalBytes.size}"
  expect (rightMulTwin.sourceHash != leftMulTwin.sourceHash)
    "right-nested 2*(3*4) must not alias left-nested 2*3*4"

  let mulOfAddTwin := mulTwin
    (.checkedMul (.literal 2) (.checkedAdd (.literal 3) (.literal 4)))
  let defaultAddMul := mulTwin
    (.checkedAdd (.literal 2) (.checkedMul (.literal 3) (.literal 4)))
  let defaultMulAdd := mulTwin
    (.checkedAdd (.checkedMul (.literal 2) (.literal 3)) (.literal 4))
  let groupedAddMul := mulTwin
    (.checkedMul (.checkedAdd (.literal 2) (.literal 3)) (.literal 4))
  let groupedMulOfAddTwin ← select session
    (qualifiedReturnProgramSource "Tests.Language.CheckedMulFixture"
      "CheckedMulTwin" "2 * (3 + 4)")
    "<group-checked-mul-of-add-twin>"
  let groupedAddThenMulTwin ← select session
    (qualifiedReturnProgramSource "Tests.Language.CheckedMulFixture"
      "CheckedMulTwin" "(2 + 3) * 4")
    "<group-checked-add-then-mul-twin>"
  expectDesugarEqual "grouped CheckedMulTwin multiplication of addition"
    mulOfAddTwin groupedMulOfAddTwin
  expectDesugarEqual "grouped CheckedMulTwin addition before multiplication"
    groupedAddMul groupedAddThenMulTwin
  expect (mulOfAddTwin.sourceHash ==
      "7f86e7a891dcbe523eb1d608f3e4ffe864c66dce2bf53bffb671c977cd800aa3")
    s!"CheckedMulTwin 2*(3+4) sourceHash golden must remain stable; got {mulOfAddTwin.sourceHash}"
  expect (mulOfAddTwin.canonicalBytes.size == 238)
    s!"CheckedMulTwin 2*(3+4) size golden must remain stable; got {mulOfAddTwin.canonicalBytes.size}"
  expect (mulOfAddTwin.sourceHash != defaultAddMul.sourceHash)
    "2*(3+4) must not alias default-precedence 2+3*4"
  expect (mulOfAddTwin.sourceHash != defaultMulAdd.sourceHash)
    "2*(3+4) must not alias left 2*3+4"
  expect (mulOfAddTwin.sourceHash != groupedAddMul.sourceHash)
    "2*(3+4) must not alias (2+3)*4"
  expect (groupedAddMul.sourceHash != defaultAddMul.sourceHash)
    "(2+3)*4 must not alias default-precedence 2+3*4"

  -- Parser-boundary negatives (no new expression kinds).
  for (label, source) in [
      ("empty group", returnProgramSource "Bad" "()"),
      ("whitespace-only group", returnProgramSource "Bad" "(   )"),
      ("missing open", returnProgramSource "Bad" "1)"),
      ("missing close", returnProgramSource "Bad" "(1"),
      ("nested unmatched", returnProgramSource "Bad" "((1)"),
      ("tuple comma", returnProgramSource "Bad" "(1, 2)"),
      ("extra inner payload", returnProgramSource "Bad" "(1 2)"),
      ("trailing after group", returnProgramSource "Bad" "(1) 2"),
      -- call-like `f(1)` migrated to LocalFnCalls positives (D1-PA-45).
      -- Inner slash `(2 / 3)` migrated to CheckedDiv positives (D1-PA-29).
      -- Inner percent `(2 % 3)` migrated to CheckedMod positives (D1-PA-30).

      -- Grouped unary `(- 3)` migrated to CheckedNeg positives (D1-PA-25).
      ("type-position group",
        "import ProofForgeV2\n\n" ++
        "open ProofForgeV2.Language\n\n" ++
        "program TypeGroup where\n" ++
        "  entry run(x : (UInt64)) : UInt64 do\n" ++
        "    return 0\n")
    ] do
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<group-{label}>")
    expectParserRejected label source result

  -- Typed controls: grouping adds no Typed arm; inner expression boundary remains.
  match Compiler.compile groupAdd with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError
        s!"grouped checkedAdd twin must still compile, got {error.render}"

  let groupedBool ← select session
    (returnProgramSource "GroupedBool" "(true)") "<group-bool-typed>"
  match Compiler.compile groupedBool with
  | .error (.invalidProgram
      "boolean literals are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"grouped bool must retain exact Typed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "grouped boolLiteral must remain Typed fail-closed"

  match Compiler.compile groupedRightSubTwin with
  | .error (.invalidProgram
      "checked subtraction is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"grouped checkedSub must retain exact Typed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "grouped checkedSub must remain Typed fail-closed"

  match Compiler.compile groupedRightMulTwin with
  | .error (.invalidProgram
      "checked multiplication is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"grouped checkedMul must retain exact Typed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "grouped checkedMul must remain Typed fail-closed"

end Tests.Language.Grouping
