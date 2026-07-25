import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1RevertEmitStatements

open ProofForgeV2
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source (body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program RevertEmitStatements where\n" ++
  "  error Err\n" ++
  "  error Multi(a : UInt64, b : UInt64)\n" ++
  "  event Event()\n" ++
  "  event Log(first : UInt64, second : UInt64)\n" ++
  "  entry run(a : UInt64) do\n" ++
  body

private unsafe def decodeEntryStatements
    (session : ProofForgeV2.Language.Loader.ParserSession) (label body : String) :
    IO (Array StmtV1) := do
  match ← session.selectProgramV1 (source body)
      ("<program-v1-revert-emit-statements-" ++ label ++ ">")
      "Tests.ProgramV1RevertEmitStatements" none with
  | .ok value =>
      let mut found? : Option (Array StmtV1) := none
      for item in value.program.items do
        match item with
        | ProgramItemV1.entry declaration => found? := some declaration.body.statements
        | _ => pure ()
      match found? with
      | some statements => pure statements
      | none => throw <| IO.userError s!"'{label}' did not decode an entry: {repr value.program.items}"
  | .error error => throw <| IO.userError error.render

private unsafe def expectRejectWithout
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body expected : String) (forbidden : Array String) : IO Unit := do
  match ← session.selectProgramV1 (source body)
      ("<program-v1-revert-emit-negative-" ++ label ++ ">")
      "Tests.ProgramV1RevertEmitStatements" none with
  | .ok value =>
      throw <| IO.userError s!"negative '{label}' unexpectedly decoded: {repr value.program.items}"
  | .error error =>
      let rendered := error.render
      unless rendered.contains expected do
        throw <| IO.userError
          s!"negative '{label}' expected '{expected}', got '{rendered}'"
      for unexpected in forbidden do
        if rendered.contains unexpected then
          throw <| IO.userError
            s!"negative '{label}' unexpectedly included lower-priority '{unexpected}', got '{rendered}'"

private unsafe def expectReject
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body expected : String) : IO Unit := do
  expectRejectWithout session label body expected #[]

private def stmtAt (statements : Array StmtV1) (index : Nat) (label : String) : IO StmtV1 :=
  match statements[index]? with
  | some stmt => pure stmt
  | none => throw <| IO.userError s!"{label}: missing statement {index}"

private def exprAt (exprs : Array ExprV1) (index : Nat) (label : String) : IO ExprV1 :=
  match exprs[index]? with
  | some expr => pure expr
  | none => throw <| IO.userError s!"{label}: missing expression {index}"

private def expectName (name : SourceNameComponentV1) (expected label : String) : IO Unit :=
  expect (name.raw == expected) s!"{label}: raw name identity changed to {name.raw}"

private def expectLiteralInteger (expr : ExprV1) (expected : Nat) (label : String) : IO Unit :=
  match expr with
  | .literal (.integer value) => expect (value == expected) label
  | other => throw <| IO.userError s!"{label}: expected integer literal, got {repr other}"

private def expectPlaceName (expr : ExprV1) (expected : String) (label : String) : IO Unit :=
  match expr with
  | .place (.name name) => expectName name expected label
  | other => throw <| IO.userError s!"{label}: expected place name, got {repr other}"

private def expectLocalCall (expr : ExprV1) (expectedCallee : String) (expectedArgs : Nat)
    (label : String) : IO (Array ExprV1) := do
  match expr with
  | .localCall callee args =>
      expectName callee expectedCallee s!"{label} callee"
      expect (args.size == expectedArgs) s!"{label}: argument count changed"
      pure args
  | other => throw <| IO.userError s!"{label}: expected localCall, got {repr other}"

private def expectRevert (stmt : StmtV1) (expectedError : String) (expectedArgs : Nat)
    (label : String) : IO (Array ExprV1) := do
  match stmt with
  | .revert error args =>
      expectName error expectedError s!"{label} error"
      expect (args.size == expectedArgs) s!"{label}: argument count changed"
      pure args
  | other => throw <| IO.userError s!"{label}: expected revert, got {repr other}"

private def expectEmit (stmt : StmtV1) (expectedEvent : String) (expectedArgs : Nat)
    (label : String) : IO (Array ExprV1) := do
  match stmt with
  | .emit event args =>
      expectName event expectedEvent s!"{label} event"
      expect (args.size == expectedArgs) s!"{label}: argument count changed"
      pure args
  | other => throw <| IO.userError s!"{label}: expected emit, got {repr other}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  let statements ← decodeEntryStatements session "positive-order"
    ("    revert Err\n" ++
     "    revert Err()\n" ++
     "    revert Multi(a)\n" ++
     "    revert Multi(1, a, f(2 + 3))\n" ++
     "    revert «error.with.dot»(4)\n" ++
     "    emit Event()\n" ++
     "    emit Log(1, a)\n" ++
     "    emit «event.with.dot»(f(1), 2 + a)\n")
  expect (statements.size == 8) "revert/emit statement source order changed"

  discard <| expectRevert (← stmtAt statements 0 "bare revert") "Err" 0 "bare revert"
  discard <| expectRevert (← stmtAt statements 1 "empty-paren revert") "Err" 0
    "empty-paren revert"

  let oneRevert ← expectRevert (← stmtAt statements 2 "one-arg revert") "Multi" 1
    "one-arg revert"
  expectPlaceName (← exprAt oneRevert 0 "one-arg revert arg") "a"
    "one-arg revert argument value changed"

  let manyRevert ← expectRevert (← stmtAt statements 3 "multi-arg revert") "Multi" 3
    "multi-arg revert"
  expectLiteralInteger (← exprAt manyRevert 0 "multi-arg revert first") 1
    "multi-arg revert first argument changed"
  expectPlaceName (← exprAt manyRevert 1 "multi-arg revert second") "a"
    "multi-arg revert second argument changed"
  let nestedRevert ← expectLocalCall (← exprAt manyRevert 2 "multi-arg revert third") "f" 1
    "multi-arg revert nested"
  match ← exprAt nestedRevert 0 "multi-arg revert nested value" with
  | .binary .add (.literal (.integer lhs)) (.literal (.integer rhs)) =>
      expect (lhs == 2 && rhs == 3) "multi-arg revert nested expression shape changed"
  | other => throw <| IO.userError s!"multi-arg revert nested expression changed: {repr other}"

  let escapedRevert ← expectRevert (← stmtAt statements 4 "escaped-dot revert")
    "error.with.dot" 1 "escaped-dot revert"
  expectLiteralInteger (← exprAt escapedRevert 0 "escaped-dot revert arg") 4
    "escaped-dot revert arg changed"

  discard <| expectEmit (← stmtAt statements 5 "empty emit") "Event" 0 "empty emit"
  let twoEmit ← expectEmit (← stmtAt statements 6 "two-arg emit") "Log" 2 "two-arg emit"
  expectLiteralInteger (← exprAt twoEmit 0 "two-arg emit first") 1
    "two-arg emit first argument changed"
  expectPlaceName (← exprAt twoEmit 1 "two-arg emit second") "a"
    "two-arg emit second argument changed"

  let escapedEmit ← expectEmit (← stmtAt statements 7 "escaped-dot emit") "event.with.dot" 2
    "escaped-dot emit"
  let nestedEmit ← expectLocalCall (← exprAt escapedEmit 0 "escaped-dot emit first") "f" 1
    "escaped-dot emit nested"
  expectLiteralInteger (← exprAt nestedEmit 0 "escaped-dot emit nested arg") 1
    "escaped-dot emit nested arg changed"
  match ← exprAt escapedEmit 1 "escaped-dot emit second" with
  | .binary .add (.literal (.integer lhs)) (.place (.name rhs)) =>
      expect (lhs == 2 && rhs.raw == "a") "escaped-dot emit expression shape changed"
  | other => throw <| IO.userError s!"escaped-dot emit expression changed: {repr other}"

  expectReject session "qualified-revert-name" "    revert A.Err()\n"
    "source name component must contain exactly one Lean Name component"
  expectReject session "qualified-emit-name" "    emit A.Event()\n"
    "source name component must contain exactly one Lean Name component"
  expectReject session "reserved-revert-name" "    revert «revert»()\n"
    "reserved portable identifier 'revert'"
  expectReject session "reserved-emit-name" "    emit «emit»()\n"
    "reserved portable identifier 'emit'"

  expectReject session "emit-missing-parens" "    emit Event\n"
    "failed to parse file"
  expectReject session "revert-missing-close" "    revert Err(1\n"
    "failed to parse file"
  expectReject session "emit-missing-close" "    emit Event(1\n"
    "failed to parse file"
  expectReject session "revert-leading-comma" "    revert Err(,1)\n"
    "failed to parse file"
  expectReject session "emit-leading-comma" "    emit Event(,1)\n"
    "failed to parse file"
  expectReject session "revert-trailing-comma" "    revert Err(1,)\n"
    "failed to parse file"
  expectReject session "emit-trailing-comma" "    emit Event(1,)\n"
    "failed to parse file"
  expectReject session "revert-double-comma" "    revert Err(1,,2)\n"
    "failed to parse file"
  expectReject session "emit-double-comma" "    emit Event(1,,2)\n"
    "failed to parse file"
  expectReject session "revert-extra-payload" "    revert Err() 1\n"
    "failed to parse file"
  expectReject session "revert-bare-extra-payload" "    revert Err 1\n"
    "failed to parse file"
  expectReject session "emit-extra-payload" "    emit Event() 1\n"
    "failed to parse file"
  expectReject session "revert-empty-parens-extra-open" "    revert Err()(1)\n"
    "failed to parse file"
  expectReject session "emit-empty-parens-extra-open" "    emit Event()(1)\n"
    "failed to parse file"

  expectRejectWithout session "revert-name-before-args" "    revert A.Err(«if»)\n"
    "source name component must contain exactly one Lean Name component"
    #["reserved portable identifier 'if'"]
  expectRejectWithout session "emit-name-before-args" "    emit A.Event(«if»)\n"
    "source name component must contain exactly one Lean Name component"
    #["reserved portable identifier 'if'"]
  expectRejectWithout session "revert-reserved-name-before-args" "    revert «revert»(A.x)\n"
    "reserved portable identifier 'revert'"
    #["source name component must contain exactly one Lean Name component"]
  expectRejectWithout session "emit-reserved-name-before-args" "    emit «emit»(A.x)\n"
    "reserved portable identifier 'emit'"
    #["source name component must contain exactly one Lean Name component"]
  expectRejectWithout session "revert-args-left-to-right-qualified-first" "    revert Err(A.x, «if»)\n"
    "source name component must contain exactly one Lean Name component"
    #["reserved portable identifier 'if'"]
  expectRejectWithout session "emit-args-left-to-right-qualified-first" "    emit Event(A.x, «if»)\n"
    "source name component must contain exactly one Lean Name component"
    #["reserved portable identifier 'if'"]
  expectRejectWithout session "revert-args-left-to-right-reserved-first" "    revert Err(«if», A.x)\n"
    "reserved portable identifier 'if'"
    #["source name component must contain exactly one Lean Name component"]
  expectRejectWithout session "emit-args-left-to-right-reserved-first" "    emit Event(«if», A.x)\n"
    "reserved portable identifier 'if'"
    #["source name component must contain exactly one Lean Name component"]

end Tests.Language.ProgramV1RevertEmitStatements
