import ProofForge.Backend.WasmNear.EmitWat
import ProofForge.IR.Contract

namespace ProofForge.Tests.WasmNearPlan

open ProofForge.IR
open ProofForge.Backend.WasmNear.EmitWat

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def requireContains (haystack needle : String) (message : String) : IO Unit :=
  require (haystack.contains needle) message

def requireNotContains (haystack needle : String) (message : String) : IO Unit :=
  require (!haystack.contains needle) message

def unsupportedChainId : Entrypoint := {
  name := "chainId", returns := .u64,
  body := #[.return (.effect (.contextRead .chainId))] }

def unsupportedChainIdModule : Module := {
  name := "UnsupportedChainId", state := #[],
  entrypoints := #[unsupportedChainId] }

def depositProbe : Entrypoint := {
  name := "depositProbe", returns := .u64,
  body := #[.return .nativeValue] }

def depositModule : Module := {
  name := "DepositProbe", state := #[],
  entrypoints := #[depositProbe] }

def testDepositRenderPrunesUnusedContextSurface : IO Unit := do
  let wat ←
    match renderModule depositModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat deposit render failed: {err.message}"
  requireContains wat "(import \"env\" \"attached_deposit\"" "deposit module must import attached_deposit"
  requireNotContains wat "__pf_ctx_user_id" "deposit module should not emit caller context helper"
  requireNotContains wat "__pf_ctx_contract_id" "deposit module should not emit contract context helper"
  requireNotContains wat "__pf_ctx_signer_id" "deposit module should not emit signer context helper"
  requireNotContains wat "__pf_ctx_random_seed" "deposit module should not emit random-seed context helper"
  requireNotContains wat "(import \"env\" \"predecessor_account_id\"" "deposit module should not import predecessor_account_id"
  requireNotContains wat "(import \"env\" \"current_account_id\"" "deposit module should not import current_account_id"
  requireNotContains wat "(import \"env\" \"register_len\"" "deposit module should not import register_len"
  requireNotContains wat "(import \"env\" \"block_index\"" "deposit module should not import block_index"
  requireNotContains wat "(import \"env\" \"signer_account_id\"" "deposit module should not import signer_account_id"
  requireNotContains wat "(import \"env\" \"block_timestamp\"" "deposit module should not import block_timestamp"
  requireNotContains wat "(import \"env\" \"epoch_height\"" "deposit module should not import epoch_height"
  requireNotContains wat "(import \"env\" \"random_seed\"" "deposit module should not import random_seed"

def testUnsupportedContextDiagnostic : IO Unit := do
  match renderModule unsupportedChainIdModule with
  | .ok _ =>
      throw <| IO.userError "chainId context read should not lower on wasm-near EmitWat"
  | .error err =>
      require (err.message == "EmitWat: wasm-near context read `chainId` is not supported; supported fields are userId, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin")
        s!"unsupported context diagnostic mismatch: {err.message}"

def main : IO UInt32 := do
  testDepositRenderPrunesUnusedContextSurface
  testUnsupportedContextDiagnostic
  IO.println "wasm-near-plan: ok"
  return 0

end ProofForge.Tests.WasmNearPlan

def main : IO UInt32 :=
  ProofForge.Tests.WasmNearPlan.main
