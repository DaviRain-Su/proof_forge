import ProofForge.Backend.Move.Aptos
import ProofForge.IR.Contract

namespace ProofForge.Tests.AptosDiagnostics

open ProofForge.IR
open ProofForge.Backend.Move.Aptos

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def crosscallEntrypoint : Entrypoint := {
  name := "call_remote"
  returns := .u64
  params := #[("target", .u64), ("method", .u64)]
  body := #[
    .return (.crosscallInvoke (.local "target") (.local "method") #[])
  ]
}

def crosscallOnlyModule : Module := {
  name := "AptosCrosscallDiagnostics"
  state := #[]
  entrypoints := #[crosscallEntrypoint]
}

def main : IO UInt32 := do
  let expected := "Aptos Counter spike: capability `crosscall.invoke` is not supported"
  match renderPackage crosscallOnlyModule with
  | .ok _ => throw <| IO.userError "Aptos backend unexpectedly accepted crosscall.invoke"
  | .error err =>
      require (err.message == expected) s!"unexpected Aptos diagnostic: {err.message}"

  IO.println "aptos-diagnostics: ok: crosscall.invoke unsupported"
  return 0

end ProofForge.Tests.AptosDiagnostics

def main : IO UInt32 :=
  ProofForge.Tests.AptosDiagnostics.main
