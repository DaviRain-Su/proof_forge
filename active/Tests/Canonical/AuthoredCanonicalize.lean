import ProofForge.Frontend.Authored
import TestFixtures.SurfaceProducts.Counter

namespace ProofForge.Tests.Canonical.AuthoredCanonicalize

open ProofForge.Frontend.Authored
open ProofForge.Frontend.Authored.Canonicalize

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def run : IO Unit := do
  let bundle ← match normalizeAuthored TestFixtures.SurfaceProducts.Counter.contract with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"authored canonicalization failed: {repr error}"
  let contract := bundle.contract.contract
  require (contract.module.name == "Counter")
    "authored canonicalization lost the contract name"
  require (contract.module.state.size == 1)
    "authored canonicalization lost Counter state"
  require (contract.module.functions.size == 3)
    "authored canonicalization lost Counter entrypoints"
  require (contract.interface.entrypoints.map (·.name) == #["initialize", "increment", "get"])
    "authored canonicalization changed the public interface order"
  IO.println "authored-canonicalize: ok"

end ProofForge.Tests.Canonical.AuthoredCanonicalize

def main : IO Unit :=
  ProofForge.Tests.Canonical.AuthoredCanonicalize.run
