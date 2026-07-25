import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1ExternalStatements

open ProofForgeV2
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.QualifiedNameV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def rawParts (name : SourceQualifiedNameV1) : Array String :=
  name.components.toArray.map (·.raw)

private def source (body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program ExternalStatements where\n" ++
  "  state total : UInt64\n" ++
  "  entry run(a : UInt64) : UInt64 do\n" ++
  body ++
  "    return total\n"

private unsafe def decodeEntryStatements
    (session : ProofForgeV2.Language.Loader.ParserSession) (label body : String) :
    IO (Array StmtV1) := do
  match ← session.selectProgramV1 (source body)
      ("<program-v1-external-statements-" ++ label ++ ">")
      "Tests.ProgramV1ExternalStatements" none with
  | .ok value =>
      match value.program.items[1]? with
      | some (ProgramItemV1.entry declaration) => pure declaration.body.statements
      | other => throw <| IO.userError s!"'{label}' did not decode an entry: {repr other}"
  | .error error => throw <| IO.userError error.render

private unsafe def expectReject
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body expected : String) : IO Unit := do
  match ← session.selectProgramV1 (source body)
      ("<program-v1-external-negative-" ++ label ++ ">")
      "Tests.ProgramV1ExternalStatements" none with
  | .ok value =>
      throw <| IO.userError s!"negative '{label}' unexpectedly decoded: {repr value.program.items}"
  | .error error =>
      let rendered := error.render
      unless rendered.contains expected do
        throw <| IO.userError
          s!"negative '{label}' expected '{expected}', got '{rendered}'"

private def expectLiteralInteger (expr : ExprV1) (expected : Nat) (label : String) : IO Unit :=
  match expr with
  | .literal (.integer value) => expect (value == expected) label
  | other => throw <| IO.userError s!"{label}: {repr other}"

private def expectPlaceName (expr : ExprV1) (expected : String) (label : String) : IO Unit :=
  match expr with
  | .place (.name name) => expect (name.raw == expected) label
  | other => throw <| IO.userError s!"{label}: {repr other}"

private def expectCall (stmt : StmtV1) (expectedCallee : Array String) (expectedArgs : Nat)
    (label : String) : IO ExternalCallExprV1 := do
  match stmt with
  | StmtV1.call externalCall =>
      expect (rawParts externalCall.callee == expectedCallee)
        s!"{label}: call callee raw components were not preserved"
      expect (externalCall.args.size == expectedArgs) s!"{label}: call argument count mismatch"
      pure externalCall
  | other => throw <| IO.userError s!"{label}: expected call, got {repr other}"

private def expectSchedule (stmt : StmtV1) (expectedCallee : Array String) (expectedArgs : Nat)
    (label : String) : IO ExternalCallExprV1 := do
  match stmt with
  | StmtV1.schedule externalCall =>
      expect (rawParts externalCall.callee == expectedCallee)
        s!"{label}: schedule callee raw components were not preserved"
      expect (externalCall.args.size == expectedArgs) s!"{label}: schedule argument count mismatch"
      pure externalCall
  | other => throw <| IO.userError s!"{label}: expected schedule, got {repr other}"

private def stmtAt (statements : Array StmtV1) (index : Nat) (label : String) : IO StmtV1 :=
  match statements[index]? with
  | some stmt => pure stmt
  | none => throw <| IO.userError s!"{label}: missing statement {index}"

private def exprAt (exprs : Array ExprV1) (index : Nat) (label : String) : IO ExprV1 :=
  match exprs[index]? with
  | some expr => pure expr
  | none => throw <| IO.userError s!"{label}: missing expression {index}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  let callStatements ← decodeEntryStatements session "call-forms"
    ("    call External.Zero()\n" ++
     "    call External.One(1)\n" ++
     "    call External.Many(1, a, total + 2)\n" ++
     "    call Alpha.Beta.Gamma(3)\n" ++
     "    call External.«component.with.dot»(4)\n")
  expect (callStatements.size == 6) "call positive source did not retain all statements"
  discard <| expectCall (← stmtAt callStatements 0 "call zero args") #["External", "Zero"] 0
    "call zero args"
  let oneCall ← expectCall (← stmtAt callStatements 1 "call one arg") #["External", "One"] 1
    "call one arg"
  expectLiteralInteger (← exprAt oneCall.args 0 "call one arg") 1
    "call one arg literal was not retained"
  let manyCall ← expectCall (← stmtAt callStatements 2 "call multiple args")
    #["External", "Many"] 3 "call multiple args"
  expectLiteralInteger (← exprAt manyCall.args 0 "call first arg") 1 "call first arg order changed"
  expectPlaceName (← exprAt manyCall.args 1 "call second arg") "a" "call second arg order changed"
  match (← exprAt manyCall.args 2 "call third arg") with
  | .binary .add (.place (.name name)) (.literal (.integer value)) =>
      expect (name.raw == "total" && value == 2) "call third arg expression changed"
  | other => throw <| IO.userError s!"call third arg expression changed: {repr other}"
  discard <| expectCall (← stmtAt callStatements 3 "call ordered qualified callee")
    #["Alpha", "Beta", "Gamma"] 1 "call ordered qualified callee"
  discard <| expectCall (← stmtAt callStatements 4 "call escaped raw callee")
    #["External", "component.with.dot"] 1 "call escaped raw callee"

  let scheduleStatements ← decodeEntryStatements session "schedule-forms"
    ("    schedule External.Zero()\n" ++
     "    schedule External.One(1)\n" ++
     "    schedule External.Many(1, a, total + 2)\n" ++
     "    schedule Alpha.Beta.Gamma(3)\n" ++
     "    schedule External.«component.with.dot»(4)\n")
  expect (scheduleStatements.size == 6) "schedule positive source did not retain all statements"
  discard <| expectSchedule (← stmtAt scheduleStatements 0 "schedule zero args")
    #["External", "Zero"] 0 "schedule zero args"
  let oneSchedule ← expectSchedule (← stmtAt scheduleStatements 1 "schedule one arg")
    #["External", "One"] 1 "schedule one arg"
  expectLiteralInteger (← exprAt oneSchedule.args 0 "schedule one arg") 1
    "schedule one arg literal was not retained"
  let manySchedule ← expectSchedule (← stmtAt scheduleStatements 2 "schedule multiple args")
    #["External", "Many"] 3 "schedule multiple args"
  expectLiteralInteger (← exprAt manySchedule.args 0 "schedule first arg") 1
    "schedule first arg order changed"
  expectPlaceName (← exprAt manySchedule.args 1 "schedule second arg") "a"
    "schedule second arg order changed"
  match (← exprAt manySchedule.args 2 "schedule third arg") with
  | .binary .add (.place (.name name)) (.literal (.integer value)) =>
      expect (name.raw == "total" && value == 2) "schedule third arg expression changed"
  | other => throw <| IO.userError s!"schedule third arg expression changed: {repr other}"
  discard <| expectSchedule (← stmtAt scheduleStatements 3 "schedule ordered qualified callee")
    #["Alpha", "Beta", "Gamma"] 1 "schedule ordered qualified callee"
  discard <| expectSchedule (← stmtAt scheduleStatements 4 "schedule escaped raw callee")
    #["External", "component.with.dot"] 1 "schedule escaped raw callee"

  expectReject session "call-one-component" "    call LocalOnly()\n"
    "source qualified id must contain 2..256 components"
  expectReject session "schedule-one-component" "    schedule LocalOnly()\n"
    "source qualified id must contain 2..256 components"
  expectReject session "call-reserved-component" "    call External.«call»()\n"
    "reserved portable identifier 'call'"
  expectReject session "schedule-reserved-component" "    schedule External.«schedule»()\n"
    "reserved portable identifier 'schedule'"
  expectReject session "call-malformed-missing-parens" "    call External.MissingParens\n"
    "failed to parse file"
  expectReject session "schedule-malformed-missing-parens" "    schedule External.MissingParens\n"
    "failed to parse file"
  expectReject session "legacy-call-string" "    call \"legacy.effect\"\n"
    "portable ProgramV1 calls require a qualified source identity"

end Tests.Language.ProgramV1ExternalStatements
