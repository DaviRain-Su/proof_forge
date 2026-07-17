import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Examples.PrivateSum4

namespace Tests.Compiler

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectInvalid (result : CompileResult α) (message : String) : IO Unit :=
  match result with
  | .error (.invalidProgram _) => pure ()
  | .error error => throw <| IO.userError s!"{message}: unexpected {error.render}"
  | .ok _ => throw <| IO.userError message

private def mkProgram (name : String) (states : Array Source.StateDecl)
    (entries : Array Source.Entry) : Source.Program := {
  qualifiedName := s!"Tests.{name}"
  name
  «state» := states
  initializer := none
  entries
}

private def mkEntry (name : String) (params : Array Source.Param)
    (body : Array Source.Statement) (mode : Source.EntryMode := .mutate)
    (result : Source.ValueType := .u64) : Source.Entry := {
  name, params, result, mode, body
}

def run : IO Unit := do
  let counter ← match Compiler.compile Examples.counter with
    | .ok counter => pure counter
    | .error error => throw <| IO.userError s!"Counter compile failed: {error.render}"
  expect (counter.qualifiedName == "ProofForgeV2.Examples.Counter")
    "semantic program must preserve the fully-qualified source identity"
  expect (counter.name == "Counter" && counter.schemaVersion == Semantic.schemaVersion)
    "semantic program must preserve its display name and schema"
  expect (counter.state.map (·.id.value) == #[0])
    "state declarations must receive stable declaration-order IDs"
  match counter.initializer with
  | some initializer =>
      match initializer.body with
      | #[.store cell (.param parameter)] =>
          expect (cell.value == 0 && parameter.value == 0)
            "initializer references must resolve to StateId 0 and ParamId 0"
      | _ => throw <| IO.userError s!"unexpected typed initializer: {repr initializer.body}"
  | none => throw <| IO.userError "Counter initializer was lost"
  match counter.entries[0]? with
  | some entryDecl =>
      match entryDecl.body with
      | #[.store cell (.checkedAdd (.state oldState) (.param delta)), .returnValue (.state returned)] =>
          expect (cell.value == 0 && oldState.value == 0 && returned.value == 0 && delta.value == 0)
            "increment must use resolved StateId/ParamId references"
      | other => throw <| IO.userError s!"unexpected Counter semantic body: {repr other}"
  | none => throw <| IO.userError "Counter increment entry was lost"
  expect (counter.requirements.contains .persistentState)
    "persistent state requirement must derive from semantic state"
  expect (counter.requirements.contains .checkedArithmetic &&
      counter.requirements.contains .transactionalRollback)
    "checkedAdd must explicitly require checked arithmetic and rollback"
  expect (!counter.requirements.contains .callerContext)
    "requirements absent from checked semantic operations must not be invented"
  expect (counter.sourceHash == Examples.counter.sourceHash)
    "semantic provenance must retain the decoded Source AST hash"

  let counterAgain ← match Compiler.compile Examples.counter with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  expect (counter.semanticHash == counterAgain.semanticHash && counter.semanticHash.length == 64)
    "semantic SHA-256 must be stable and use 64 lower-case hex characters"
  expect (counter.semanticHash ==
      "c3b58be1a12e9d4f87a7e4730746b1b4f538d6a9e971a637f92cd508349ebcf8")
    "Counter semantic serialization must match its canonical SHA-256 golden"
  let renamed := { Examples.counter with qualifiedName := "Other.Counter" }
  let renamed ← match Compiler.compile renamed with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  expect (counter.semanticHash != renamed.semanticHash)
    "qualified identity must participate in semantic hashing"

  let synchronous ← match Compiler.compile Examples.counterWithSynchronousCall with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  expect (synchronous.requirements.contains .synchronousCall &&
      synchronous.requirements.contains .transactionalRollback)
    "synchronous calls must explicitly require call support and rollback"

  let privateSum ← match Compiler.compile Examples.privateSum4 with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  expect (privateSum.requirements.contains .privateWitness)
    "private parameter visibility must derive the private-witness requirement"

  let unknown := mkProgram "Unknown" #[] #[mkEntry "run" #[] #[.returnValue (.variable "missing")]]
  expectInvalid (Compiler.compile unknown) "unknown values must be rejected"

  let duplicateState := mkProgram "DuplicateState"
    #[{ name := "value", type := .u64 }, { name := "value", type := .u64 }]
    #[mkEntry "run" #[] #[.returnValue (.literal 0)]]
  expectInvalid (Compiler.compile duplicateState) "duplicate state declarations must be rejected"

  let duplicateEntry := mkProgram "DuplicateEntry" #[] #[
    mkEntry "run" #[] #[.returnValue (.literal 0)],
    mkEntry "run" #[] #[.returnValue (.literal 1)]]
  expectInvalid (Compiler.compile duplicateEntry) "duplicate entries must be rejected"

  let duplicateParam := mkProgram "DuplicateParam" #[] #[mkEntry "run"
    #[{ name := "x", type := .u64 }, { name := "x", type := .u64 }]
    #[.returnValue (.variable "x")]]
  expectInvalid (Compiler.compile duplicateParam) "duplicate parameters must be rejected"

  let viewWrite := mkProgram "ViewWrite" #[{ name := "value", type := .u64 }] #[
    mkEntry "get" #[] #[.assign "value" (.literal 1), .returnValue (.variable "value")] .view]
  expectInvalid (Compiler.compile viewWrite) "view state writes must be rejected"

  let missingReturn := mkProgram "MissingReturn" #[] #[mkEntry "run" #[] #[.synchronousCall "peer"]]
  expectInvalid (Compiler.compile missingReturn) "entries without return must be rejected"

  let illegalAssignment := mkProgram "IllegalAssignment" #[] #[mkEntry "run" #[]
    #[.assign "missing" (.literal 1), .returnValue (.literal 1)]]
  expectInvalid (Compiler.compile illegalAssignment) "assignment to undeclared state must be rejected"

  let typeMismatch := mkProgram "TypeMismatch" #[{ name := "flag", type := .bool }] #[
    mkEntry "run" #[] #[.assign "flag" (.literal 1), .returnValue (.literal 1)]]
  expectInvalid (Compiler.compile typeMismatch) "assignment type mismatches must be rejected"

end Tests.Compiler
