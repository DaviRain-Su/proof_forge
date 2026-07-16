import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.Target.Check
import ProofForge.Target.Registry

namespace ProofForge.Backend.WasmHost.CosmWasm.IR

open ProofForge.IR
open ProofForge.Target

structure LowerError where
  message : String
  deriving Repr, Inhabited

def LowerError.render (err : LowerError) : String :=
  err.message

def capabilityError (err : CapabilityError) : LowerError := {
  message := err.render
}

def validateCapabilities (module : Module) : Except LowerError Unit :=
  match requireCapabilities Target.wasmCosmWasm module.capabilities with
  | .ok () => .ok ()
  | .error err => .error (capabilityError err)

end ProofForge.Backend.WasmHost.CosmWasm.IR
