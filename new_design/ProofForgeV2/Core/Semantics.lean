import ProofForgeV2.Core.SemanticIR

namespace ProofForgeV2.Semantics

open ProofForgeV2 Semantic

structure State where
  storage : Array UInt64
  deriving BEq, Inhabited, Repr

private def optionToResult (value : Option α) (error : CompileError) : CompileResult α :=
  match value with
  | some result => .ok result
  | none => .error error

private def stateIndex (program : Program) (id : StateId) : CompileResult Nat := do
  let declaration ← optionToResult program.state[id.value]?
    (.invalidState s!"state-id:{id.value}")
  unless declaration.id == id do
    throw <| .invalidState s!"state-id:{id.value}"
  return id.value

private partial def evalExpr (program : Program) (state : State)
    (params : Array UInt64) : Expr → CompileResult UInt64
  | .literal value => .ok value
  | .param id => optionToResult params[id.value]? (.invalidState s!"param-id:{id.value}")
  | .state id => do
      let index ← stateIndex program id
      optionToResult state.storage[index]? (.invalidState s!"state-id:{id.value}")
  | .checkedAdd lhs rhs => do
      let left ← evalExpr program state params lhs
      let right ← evalExpr program state params rhs
      let sum := left.toNat + right.toNat
      if sum > 18446744073709551615 then
        .error .arithmeticOverflow
      else
        .ok (UInt64.ofNat sum)

private def bindParams (decls : Array Param) (values : Array UInt64) : CompileResult (Array UInt64) := do
  if decls.size != values.size then
    throw <| .wrongArity decls.size values.size
  for index in [0:decls.size] do
    let declaration := decls[index]!
    unless declaration.id.value == index do
      throw <| .invalidProgram s!"non-canonical parameter id {declaration.id.value} at position {index}"
  return values

private partial def executeFrom (program : Program) (params : Array UInt64)
    (statements : Array Statement) (pc : Nat) (state : State) :
    CompileResult (State × Option UInt64) := do
  match statements[pc]? with
  | none => return (state, none)
  | some (.store id expr) =>
      let value ← evalExpr program state params expr
      let slot ← stateIndex program id
      executeFrom program params statements (pc + 1)
        { storage := state.storage.set! slot value }
  | some (.returnValue expr) =>
      return (state, some (← evalExpr program state params expr))
  | some (.synchronousCall callee) =>
      throw <| .invalidProgram
        s!"reference interpreter requires an explicit response for synchronous call '{callee}'"

private def execute (program : Program) (initial : State) (params : Array UInt64)
    (statements : Array Statement) : CompileResult (State × Option UInt64) :=
  executeFrom program params statements 0 initial

def initializeProgram (program : Program) (values : Array UInt64) : CompileResult State := do
  let initializer ← optionToResult program.initializer (.invalidProgram "program does not define init")
  let params ← bindParams initializer.params values
  let empty : State := { storage := Array.replicate program.state.size 0 }
  return (← execute program empty params initializer.body).1

def invoke (program : Program) (preState : State) (entryName : String)
    (values : Array UInt64) : CompileResult (State × Option UInt64) := do
  let entry ← optionToResult (program.entries.find? (fun candidate => candidate.name == entryName))
    (.unknownEntry entryName)
  let params ← bindParams entry.params values
  execute program preState params entry.body

end ProofForgeV2.Semantics
