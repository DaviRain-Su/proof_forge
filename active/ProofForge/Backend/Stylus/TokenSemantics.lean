import ProofForge.Backend.Stylus.Semantics

namespace ProofForge.Backend.Stylus.TokenSemantics

structure State where
  totalSupply : Nat := 0
  alice : Nat := 0
  bob : Nat := 0
  allowance : Nat := 0
  deriving Repr, BEq

structure Step where
  call : String
  status : Nat
  state : State
  event? : Option String := none
  deriving Repr, BEq

private def stepJson (step : Step) : String :=
  "{\"call\":\"" ++ step.call ++ "\",\"status\":" ++ toString step.status ++
    ",\"totalSupply\":" ++ toString step.state.totalSupply ++
    ",\"alice\":" ++ toString step.state.alice ++
    ",\"bob\":" ++ toString step.state.bob ++
    ",\"allowance\":" ++ toString step.state.allowance ++
    ",\"event\":" ++ (step.event?.map (fun value => "\"" ++ value ++ "\"")).getD "null" ++ "}"

def mint (state : State) (amount : Nat) : State × Step :=
  let next := { state with totalSupply := state.totalSupply + amount, alice := state.alice + amount }
  let step : Step := {
    call := "mint"
    status := 0
    state := next
    event? := some s!"transfer:0:1:{amount}" }
  (next, step)

def transfer (state : State) (amount : Nat) : State × Step :=
  if amount > state.alice then
    let step : Step := { call := "transfer-failure", status := 1, state := state }
    (state, step)
  else
    let next := { state with alice := state.alice - amount, bob := state.bob + amount }
    let step : Step := {
      call := "transfer"
      status := 0
      state := next
      event? := some s!"transfer:1:2:{amount}" }
    (next, step)

def approve (state : State) (amount : Nat) : State × Step :=
  let next := { state with allowance := amount }
  let step : Step := {
    call := "approve"
    status := 0
    state := next
    event? := some s!"approval:1:3:{amount}" }
  (next, step)

def transferFrom (state : State) (amount : Nat) : State × Step :=
  if amount > state.alice || amount > state.allowance then
    let step : Step := { call := "transferFrom-failure", status := 1, state := state }
    (state, step)
  else
    let next := { state with
      alice := state.alice - amount
      bob := state.bob + amount
      allowance := state.allowance - amount }
    let step : Step := {
      call := "transferFrom"
      status := 0
      state := next
      event? := some s!"transfer:1:2:{amount}" }
    (next, step)

def normalizedScenario : Array Step :=
  let minted := mint {} 100
  let transferred := transfer minted.1 30
  let approved := approve transferred.1 40
  let spent := transferFrom approved.1 25
  let rejected := transferFrom spent.1 20
  #[minted.2, transferred.2, approved.2, spent.2, rejected.2]

def normalizedScenarioJson : String :=
  "{\"steps\":[" ++ String.intercalate "," (normalizedScenario.map stepJson).toList ++ "]}"

end ProofForge.Backend.Stylus.TokenSemantics
