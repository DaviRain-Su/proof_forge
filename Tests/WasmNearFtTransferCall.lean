import ProofForge.Backend.WasmNear.EmitWat
import ProofForge.Backend.WasmNear.Plan
import ProofForge.Contract.Stdlib.NearFungibleToken

namespace ProofForge.Tests.WasmNearFtTransferCall

open ProofForge.IR
open ProofForge.Backend.WasmNear.EmitWat

def requireContains (wat : String) (needle : String) (msg : String) : IO Unit :=
  if wat.contains needle then pure () else
    throw <| IO.userError s!"{msg}: missing `{needle}`"

def main : IO UInt32 := do
  let module := ProofForge.Contract.Stdlib.NearFungibleToken.module
  if module.nearCrosscallStrings != #["ft_on_transfer", "ft_resolve_transfer", "demo.receiver.testnet"] then
    throw <| IO.userError "NearFungibleToken must register ft methods and demo receiver in nearCrosscallStrings"
  match ProofForge.Backend.WasmNear.Plan.buildModulePlan module with
  | .ok plan =>
      if !plan.usesPromiseCreate then throw <| IO.userError "FT module must use promise_create"
      if !plan.usesPromiseThen then throw <| IO.userError "FT module must use promise_then"
      if !plan.usesPromiseResultU64 then throw <| IO.userError "FT module must decode promise result U64"
      if !plan.usesCrosscallHash then throw <| IO.userError "FT module must encode sender hash in ft_on_transfer args"
  | .error err => throw <| IO.userError s!"plan failed: {err.message}"
  let wat ←
    match renderModule module with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat render failed: {err.message}"
  requireContains wat "ft_on_transfer" "FT WAT must include ft_on_transfer string"
  requireContains wat "ft_resolve_transfer" "FT WAT must include ft_resolve_transfer string"
  requireContains wat "demo.receiver.testnet" "FT WAT must include demo receiver account"
  requireContains wat "__pf_crosscall_pool_ptr" "FT WAT must emit crosscall pool ptr helper"
  requireContains wat "call $promise_create" "FT WAT must call promise_create"
  requireContains wat "call $promise_then" "FT WAT must call promise_then"
  requireContains wat "__pf_crosscall_args_puthash" "FT WAT must encode sender hash arg"
  requireContains wat "call $__pf_crosscall_args_puthash" "FT WAT must pass sender hash to ft_on_transfer"
  requireContains wat "call $__pf_crosscall_args_putu64" "FT WAT must pass amount to ft_on_transfer"
  requireContains wat "__pf_promise_result_u64" "FT WAT must decode callback promise payload"
  IO.println "wasm-near-ft-transfer-call: ok"
  return 0

end ProofForge.Tests.WasmNearFtTransferCall

def main : IO UInt32 :=
  ProofForge.Tests.WasmNearFtTransferCall.main
