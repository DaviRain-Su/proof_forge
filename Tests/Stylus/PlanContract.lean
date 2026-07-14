import ProofForge.Backend.Stylus.Plan

open ProofForge.Backend.Stylus

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def emptyPlan : StylusPlan := {
  targetId := "wasm-arbitrum-stylus"
  moduleName := "Empty"
  abi := { methods := #[], errors := #[] }
  storage := { words := #[] }
  functions := #[]
  events := #[]
  calls := #[]
  hostOps := #[]
  resources := { maxMemoryPages := 1, requiresStorageFlush := false }
  artifacts := { solidityAbi := true, typescriptClient := true }
}

def main : IO Unit := do
  require (emptyPlan.targetId == "wasm-arbitrum-stylus")
    "StylusPlan target id drifted"
  require (StylusAbiType.uint? 256 |>.isSome) "uint256 should be valid"
  require (StylusAbiType.uint? 24 |>.isNone) "uint24 should fail closed"
  require (StylusAbiType.fixedBytes? 1 |>.isSome) "bytes1 should be valid"
  require (StylusAbiType.fixedBytes? 32 |>.isSome) "bytes32 should be valid"
  require (StylusAbiType.fixedBytes? 0 |>.isNone) "bytes0 should be invalid"
  require (StylusAbiType.fixedBytes? 33 |>.isNone) "bytes33 should be invalid"
  IO.println "stylus-plan-contract: ok"
