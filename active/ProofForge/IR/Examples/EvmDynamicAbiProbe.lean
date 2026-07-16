import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmDynamicAbiProbe

open ProofForge.IR

def echoBytes : Entrypoint := {
  name := "echo_bytes"
  selector? := some "1cc09e37"
  params := #[
    ("data", .bytes)
  ]
  returns := .bytes
  body := #[
    .return (.local "data")
  ]
}

def echoString : Entrypoint := {
  name := "echo_string"
  selector? := some "41ccc945"
  params := #[
    ("data", .string)
  ]
  returns := .string
  body := #[
    .return (.local "data")
  ]
}

def transfer : Entrypoint := {
  name := "transfer"
  selector? := some "a9059cbb"
  params := #[
    ("to", .address),
    ("amount", .u64)
  ]
  returns := .bool
  body := #[
    .return (.literal (.bool true))
  ]
}

def module : Module := {
  name := "EvmDynamicAbiProbe"
  state := #[]
  entrypoints := #[echoBytes, echoString, transfer]
}

end ProofForge.IR.Examples.EvmDynamicAbiProbe