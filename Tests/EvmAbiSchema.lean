import ProofForge.Cli.EvmAbi
import ProofForge.Contract.Spec

open ProofForge.Cli
open ProofForge.IR

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def probe (selector? : Option String) : Module := {
  name := "SelectorSchemaProbe"
  state := #[]
  entrypoints := #[{
    name := "setValue"
    selector? := selector?
    params := #[("value", .u64)]
    body := #[]
  }]
}

def main : IO Unit := do
  let cast := (← IO.getEnv "HOME").map (· ++ "/.foundry/bin/cast") |>.getD "cast"
  try
    let _ ← hydrateEvmSelectors cast (probe (some "deadbeef"))
    throw <| IO.userError "mismatched selector and parameter schema was accepted"
  catch error =>
    require (error.toString.contains "does not match ABI signature `setValue(uint256)`")
      s!"unexpected selector mismatch diagnostic: {error}"

  let hydrated ← hydrateEvmSelectors cast (probe none)
  let some entrypoint := hydrated.entrypoints[0]?
    | throw <| IO.userError "hydrated module lost entrypoint"
  require (entrypoint.selector? == some "55241077")
    s!"unexpected canonical setValue(uint256) selector: {entrypoint.selector?}"
  let json ← match entrypointJson hydrated entrypoint with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  require (json.contains "\"signature\": \"setValue(uint256)\"")
    s!"ABI JSON signature diverged: {json}"
  require (json.contains "\"selector\": \"55241077\"")
    s!"ABI JSON selector diverged: {json}"
  IO.println "evm-abi-schema: ok"
