import ProofForge.Backend.WasmHost.EmitWat

open ProofForge.IR

def echoEntrypoint : Entrypoint := {
  name := "echo"
  mutability := .view
  params := #[("value", .u64)]
  returns := .u64
  body := #[.return (.local "value")]
}

def echoModule : Module := {
  name := "NearU64RoundTrip"
  state := #[]
  entrypoints := #[echoEntrypoint]
}

def main (args : List String) : IO UInt32 := do
  let path := args[0]?.getD "build/near-abi-client/echo.wat"
  let wat <- match ProofForge.Backend.WasmHost.EmitWat.renderModule echoModule with
    | .ok wat => pure wat
    | .error error => throw <| IO.userError error.message
  IO.FS.writeFile path (wat ++ "\n")
  IO.println s!"wrote {path}"
  return 0
