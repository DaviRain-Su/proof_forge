import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Compiler.Pipeline

namespace Tests.Language.Declarations

open ProofForgeV2
open ProofForgeV2.Source

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectRejected (result : Except CompileError α) (message : String) : IO Unit :=
  match result with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError message

private def isIncrementAssign : Statement → Bool
  | .assign "count" (.checkedAdd (.variable "count") (.variable "delta")) => true
  | _ => false

private def isCountReturn : Statement → Bool
  | .returnValue (.variable "count") => true
  | _ => false

/-- TST-SRC-004/005: declaration + statement/expression grammar via shipped loader/elaborator. -/
unsafe def run : IO Unit := do
  expect (Examples.counter.state.map (·.name) == #["count"]) "state decl must elaborate"
  expect Examples.counter.initializer.isSome "init decl must elaborate"
  expect (Examples.counter.entries.map (·.name) == #["increment", "get"])
    "entry and view decls must elaborate in order"
  match Examples.counter.entries[0]? with
  | some increment =>
      expect (increment.mode == EntryMode.mutate) "entry mode must be mutate"
      expect (increment.body.size == 2) "increment body: assign + return"
      match increment.body[0]? with
      | some stmt =>
          expect (isIncrementAssign stmt) s!"unexpected increment assign: {repr stmt}"
      | none => throw <| IO.userError "missing assign"
      match increment.body[1]? with
      | some stmt =>
          expect (isCountReturn stmt) s!"unexpected increment return: {repr stmt}"
      | none => throw <| IO.userError "missing return"
  | none => throw <| IO.userError "missing increment"
  match Examples.counter.entries[1]? with
  | some viewDecl =>
      expect (viewDecl.mode == EntryMode.view) "view mode must be view"
      match viewDecl.body[0]? with
      | some stmt =>
          expect (isCountReturn stmt) s!"unexpected view body: {repr stmt}"
      | none => throw <| IO.userError "missing view body"
  | none => throw <| IO.userError "missing get view"

  let duplicateInit :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\nprogram Bad where\n  init() do\n  init() do\n  view get() : UInt64 do\n    return 0\n"
  expectRejected (← Language.Loader.parsePrograms duplicateInit "<dup-init>")
    "duplicate init must fail closed"

  let overflow :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\nprogram BadLit where\n  view get() : UInt64 do\n    return 18446744073709551616\n"
  expectRejected (← Language.Loader.parsePrograms overflow "<overflow-lit>")
    "out-of-range UInt64 literal must fail closed"

  let empty :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\nprogram Empty where\n  state x : UInt64\n"
  match ← Language.Loader.parsePrograms empty "<empty>" with
  | .ok programs =>
      match programs[0]? with
      | some src =>
          match Compiler.compile src with
          | .error error =>
              expect (error.code == "PF-SRC-INVALID")
                s!"empty callables must be invalid: {error.render}"
          | .ok _ => throw <| IO.userError "program without entry/view must not compile"
      | none => throw <| IO.userError "expected one program"
  | .error _ => pure ()

end Tests.Language.Declarations
