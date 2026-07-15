import ProofForgeV2.Core.Semantics
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter

namespace Tests.Core

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def run : IO Unit := do
  let counter ← match Compiler.compile Examples.counter with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"Counter compile failed: {error.render}"
  let initial := Semantics.initializeProgram counter #[7]
  match initial with
  | .ok currentState => expect (currentState.storage == #[7]) "Counter init must store the initial value"
  | .error error => throw <| IO.userError s!"Counter init failed: {error.render}"
  let incremented := initial.bind fun currentState => Semantics.invoke counter currentState "increment" #[5]
  match incremented with
  | .ok (currentState, result) =>
      expect (currentState.storage == #[12] && result == some 12) "increment must update and return count"
  | .error error => throw <| IO.userError s!"increment failed: {error.render}"
  let overflow := Semantics.invoke counter
    { storage := #[UInt64.ofNat 18446744073709551615] } "increment" #[1]
  match overflow with
  | .error .arithmeticOverflow => pure ()
  | _ => throw <| IO.userError "overflow must fail without a post-state"

end Tests.Core
