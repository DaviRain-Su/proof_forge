import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Backend.WasmHost.NearAbiPlan
import ProofForge.Backend.WasmHost.NearModulePlan
import ProofForge.Backend.WasmHost.WasmInterpreter

open ProofForge.IR
open ProofForge.Backend.Refinement
open ProofForge.Backend.WasmHost.WasmInterpreter

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

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

def unsupportedDynamicModule : Module := {
  name := "UnsupportedDynamicNearAbi"
  state := #[]
  entrypoints := #[{
    name := "echo_bytes"
    mutability := .view
    params := #[("value", .bytes)]
    returns := .bytes
    body := #[.return (.local "value")]
  }]
}

def main : IO Unit := do
  let abi ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan #[] echoEntrypoint with
    | .ok plan => pure plan
    | .error message => throw <| IO.userError message
  require (abi.inputCodec == .borsh && abi.outputCodec == .borsh)
    "NEAR entrypoint codecs must be Borsh"
  require (abi.inputByteWidth == 8 && abi.outputByteWidth == 8)
    "NEAR u64 round-trip must use exact 8-byte input/output widths"
  let plan ← match ProofForge.Backend.WasmHost.NearModulePlan.buildNearModulePlan echoModule with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.message
  require (plan.entrypointAbis == #[abi]) "NearModulePlan must own the entrypoint ABI plan"
  let wat ← match ProofForge.Backend.WasmHost.NearModulePlan.renderModuleFromPlan echoModule plan with
    | .ok wat => pure wat
    | .error error => throw <| IO.userError error.message
  require (wat.contains "call $register_len") "NEAR input must inspect the host payload length"
  require (wat.contains "i64.const 8") "NEAR input must enforce the planned 8-byte payload"
  let mismatchedAbi := { abi with params := #[], inputByteWidth := 0 }
  match ProofForge.Backend.WasmHost.Params.loadParams #[] echoEntrypoint.params mismatchedAbi with
  | .error error =>
      require (error.message.contains "does not match")
        "NEAR parameter/codec plan mismatch must be actionable"
  | .ok _ => throw <| IO.userError "NEAR parameter/codec plan mismatch did not fail closed"
  let mismatchedOutput := { abi with returnType := .u32, outputByteWidth := 4 }
  let mismatchedPlan := { plan with entrypointAbis := #[mismatchedOutput] }
  match ProofForge.Backend.WasmHost.NearModulePlan.lowerModuleFromPlan echoModule mismatchedPlan with
  | .error error =>
      require (error.message.contains "does not match its signature")
        "NEAR return codec plan mismatch must be actionable"
  | .ok _ => throw <| IO.userError "NEAR return codec plan mismatch did not fail closed"
  let wasm ← match ProofForge.Backend.WasmHost.NearModulePlan.lowerModuleFromPlan echoModule plan with
    | .ok wasm => pure wasm
    | .error error => throw <| IO.userError error.message
  let call : TraceCall := { entrypoint := echoEntrypoint, args := #[.u64 42] }
  let (_, steps) ← match runTraceList wasm [call] (initialState wasm) with
    | .ok result => pure result
    | .error message => throw <| IO.userError message
  require (steps[0]?.map (fun step => step.returnValue) == some (.u64 42))
    "NEAR planned Borsh codec must round-trip a nonzero u64 result"
  let some echoFunc := findExportedFunc? wasm "echo"
    | throw <| IO.userError "missing echo export"
  let initial := initialState wasm
  let malformed := { initial with host := initial.host.beginCall #[1] }
  match evalFunc wasm echoFunc #[] defaultFuel malformed with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "NEAR ABI accepted a malformed one-byte u64 payload"
  match ProofForge.Backend.WasmHost.NearAbiPlan.buildModulePlans unsupportedDynamicModule with
  | .error message =>
      require (message.contains "does not support dynamic")
        "unsupported NEAR codec must return an actionable build error"
  | .ok _ => throw <| IO.userError "unsupported dynamic NEAR codec did not fail closed"
  let bareCtx := { (ProofForge.Backend.WasmHost.ModuleAssembly.loweringCtxForModule echoModule .near) with
    entrypointAbis := #[] }
  match ProofForge.Backend.WasmHost.EmitWat.lowerEntrypoint bareCtx echoEntrypoint with
  | .error error =>
      require (error.message.contains "missing NEAR ABI plan")
        "a bare context with empty entrypointAbis must reject lowerEntrypoint"
  | .ok _ => throw <| IO.userError "lowerEntrypoint accepted a context with no NEAR ABI plan"
  IO.println "near-abi-plan: ok"
