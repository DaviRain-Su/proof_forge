import ProofForge.Contract.Client

open ProofForge.IR

def echo : Entrypoint := {
  name := "echo"
  mutability := .view
  params := #[("value", .u64)]
  returns := .u64
  body := #[
    .assert (.literal (.bool true)) "codec" (some { assertionId := 1 }),
    .return (.local "value")
  ]
}

def spec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.ContractSpec.fromIR {
    name := "NearU64RoundTrip"
    state := #[]
    entrypoints := #[echo]
  }

def main (args : List String) : IO UInt32 := do
  let path := args[0]?.getD "build/near-abi-client/proof-forge-near.ts"
  IO.FS.writeFile path (ProofForge.Contract.Client.renderNearWrapper spec ++ "\n")
  IO.println s!"wrote {path}"
  return 0
