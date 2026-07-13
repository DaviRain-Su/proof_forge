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

def ftBalanceEntrypoint : Entrypoint := {
  name := "ft_balance_of"
  mutability := .view
  params := #[("account_id", .string)]
  returns := .u128
  body := #[.return (.literal (.u128 100))]
}

def ftBalanceModule : Module := {
  name := "NearFtBalanceJson"
  state := #[]
  entrypoints := #[ftBalanceEntrypoint]
}

def ftTransferEntrypoint : Entrypoint := {
  name := "ft_transfer"
  mutability := .call
  params := #[("receiver_id", .string), ("amount", .u128)]
  returns := .unit
  body := #[]
}

def ftTransferModule : Module := {
  name := "NearFtTransferJson"
  state := #[]
  entrypoints := #[ftTransferEntrypoint]
}

def dynamicBytesModule : Module := {
  name := "DynamicBytesNearAbi"
  state := #[]
  entrypoints := #[{
    name := "echo_bytes"
    mutability := .view
    params := #[("value", .bytes)]
    returns := .bytes
    body := #[.return (.local "value")]
  }]
}

def mixedDynamicModule : Module := {
  name := "MixedDynamicNearAbi"
  state := #[]
  entrypoints := #[{
    name := "echo_bytes_with_tag"
    mutability := .view
    params := #[("value", .bytes), ("tag", .u64)]
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
  let ftAbi ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan #[] ftBalanceEntrypoint with
    | .ok plan => pure plan
    | .error message => throw <| IO.userError message
  require (ftAbi.inputCodec == .json && ftAbi.outputCodec == .json)
    "NEAR ft_balance_of must use the standard JSON codec"
  require (ftAbi.inputByteWidth == 0 && ftAbi.outputByteWidth == 0)
    "dynamic JSON codec widths must not claim a fixed Borsh payload"
  let ftPlan ← match ProofForge.Backend.WasmHost.NearModulePlan.buildNearModulePlan ftBalanceModule with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.message
  let ftWat ← match ProofForge.Backend.WasmHost.NearModulePlan.renderModuleFromPlan ftBalanceModule ftPlan with
    | .ok wat => pure wat
    | .error error => throw <| IO.userError error.message
  require (ftWat.contains "call $__pf_return_json_u128")
    "NEAR ft_balance_of must route U128 through the JSON decimal-string return helper"
  require (ftWat.contains "i32.const 123" && ftWat.contains "i32.const 125")
    "NEAR ft_balance_of JSON input must validate object braces"
  let invalidFtBalance := { ftBalanceEntrypoint with returns := .u64 }
  match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan #[] invalidFtBalance with
  | .error message =>
      require (message.contains "must have signature")
        "invalid standard ft_balance_of signature must be actionable"
  | .ok _ => throw <| IO.userError "invalid standard ft_balance_of signature did not fail closed"
  let transferAbi ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan #[] ftTransferEntrypoint with
    | .ok plan => pure plan
    | .error message => throw <| IO.userError message
  require (transferAbi.inputCodec == .json && transferAbi.outputCodec == .borsh)
    "NEAR ft_transfer must use JSON input without claiming a JSON return payload"
  require (transferAbi.inputByteWidth == 0 && transferAbi.outputByteWidth == 0)
    "NEAR ft_transfer JSON input and Unit output must have dynamic/zero codec widths"
  let transferPlan ← match ProofForge.Backend.WasmHost.NearModulePlan.buildNearModulePlan ftTransferModule with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.message
  let transferWat ← match ProofForge.Backend.WasmHost.NearModulePlan.renderModuleFromPlan ftTransferModule transferPlan with
    | .ok wat => pure wat
    | .error error => throw <| IO.userError error.message
  require (transferWat.contains "call $__pf_parse_u128_decimal")
    "NEAR ft_transfer must parse its JSON decimal-string amount into U128"
  require (transferWat.contains "i32.const 114" && transferWat.contains "i32.const 97")
    "NEAR ft_transfer must validate receiver_id and amount field bytes"
  let invalidFtTransfer := { ftTransferEntrypoint with returns := .u64 }
  match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan #[] invalidFtTransfer with
  | .error message =>
      require (message.contains "must have signature")
        "invalid standard ft_transfer signature must be actionable"
  | .ok _ => throw <| IO.userError "invalid standard ft_transfer signature did not fail closed"
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
  let dynamicPlans ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildModulePlans dynamicBytesModule with
    | .ok plans => pure plans
    | .error message => throw <| IO.userError message
  let some dynamicAbi := dynamicPlans[0]?
    | throw <| IO.userError "NEAR dynamic bytes plan is missing its entrypoint"
  require (dynamicPlans.size == 1 && dynamicAbi.inputByteWidth == 260 &&
      dynamicAbi.outputByteWidth == 260)
    "NEAR dynamic bytes plan must reserve a four-byte Borsh prefix plus bounded payload"
  let dynamicPlan ← match ProofForge.Backend.WasmHost.NearModulePlan.buildNearModulePlan dynamicBytesModule with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.message
  match ProofForge.Backend.WasmHost.NearModulePlan.lowerModuleFromPlan dynamicBytesModule dynamicPlan with
  | .error error => throw <| IO.userError error.message
  | .ok _ => pure ()
  let mixedPlan ← match ProofForge.Backend.WasmHost.NearModulePlan.buildNearModulePlan mixedDynamicModule with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.message
  match ProofForge.Backend.WasmHost.NearModulePlan.lowerModuleFromPlan mixedDynamicModule mixedPlan with
  | .error error =>
      require (error.message.contains "sole parameter")
        "mixed dynamic NEAR parameters must return an actionable lowering error"
  | .ok _ => throw <| IO.userError "mixed dynamic NEAR parameters did not fail closed"
  let bareCtx := { (ProofForge.Backend.WasmHost.ModuleAssembly.loweringCtxForModule echoModule .near) with
    entrypointAbis := #[] }
  match ProofForge.Backend.WasmHost.EmitWat.lowerEntrypoint bareCtx echoEntrypoint with
  | .error error =>
      require (error.message.contains "missing NEAR ABI plan")
        "a bare context with empty entrypointAbis must reject lowerEntrypoint"
  | .ok _ => throw <| IO.userError "lowerEntrypoint accepted a context with no NEAR ABI plan"
  IO.println "near-abi-plan: ok"
