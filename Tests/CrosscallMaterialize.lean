/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Phase B.3 / U2: portable crosscall **target materialization** on primary chains.
Does **not** exercise IR `Semantics` crosscall stubs (see `Tests/IRCrosscallStub.lean`).
-/
import ProofForge.IR.Examples.CrosscallProbe
import ProofForge.IR.Examples.NearCrosscallProbe
import ProofForge.IR.Examples.Counter
import Examples.Product.RemoteCall
import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.PortableCrosscall
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Backend.WasmHost.PortableCrosscall
import ProofForge.Backend.WasmHost.CosmWasm.EmitWat
import ProofForge.Backend.Psy.IR
import ProofForge.Target.CrosscallMaterialize
import ProofForge.Target.Preflight
import ProofForge.Target.Registry

open ProofForge.Target
open ProofForge.Target.CrosscallMaterialize
open ProofForge.Target.Preflight
open ProofForge.Backend.Solana.PortableCrosscall
open ProofForge.Backend.Solana.Manifest
open ProofForge.Backend.Solana.StateLayout
open ProofForge.Backend.WasmHost.PortableCrosscall

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def main : IO Unit := do
  let probe := ProofForge.IR.Examples.CrosscallProbe.module
  let nearProbe := ProofForge.IR.Examples.NearCrosscallProbe.module

  -- EVM: portable crosscall plan builds (CALL materialization).
  match ProofForge.Backend.Evm.Plan.buildModulePlan probe with
  | .error e => throw (IO.userError s!"EVM plan for CrosscallProbe failed: {e.message}")
  | .ok _ => pure ()
  require ((forProfile evm).nativeForm == NativeForm.evmCall) "EVM native form"

  -- Solana: portable scalar subset → CPI materialization (not EVM STATIC/DELEGATE/create).
  let solProbe := ProofForge.IR.Examples.CrosscallProbe.solanaPortableModule
  require (moduleHasPortableCrosscall solProbe) "solanaPortableModule has portable sites"
  let sites := collectSites solProbe
  require (sites.size > 0) "expected crosscall sites"
  match ProofForge.Target.resolveModule solanaSbpfAsm solProbe with
  | .error e => throw (IO.userError s!"Solana should accept portable crosscall.invoke: {e.render}")
  | .ok _ => pure ()
  let modAccounts := buildModuleAccounts solProbe {}
  require (modAccounts.any (fun a => a.name == "callee_program"))
    "Solana materialization should add callee_program for portable crosscall"
  require (modAccounts.any (fun a => a.name == "payer" || a.signer))
    "Solana materialization should synthesize a payer/signer role for portable crosscall"
  match ProofForge.Backend.Solana.SbpfAsm.renderModule solProbe with
  | .error e => throw (IO.userError s!"Solana lower solanaPortableModule failed: {e.message}")
  | .ok src =>
      require (src.contains "portable crosscall") "asm should mark CPI materialization"
      require (src.contains "sol_invoke_signed_c") "asm packs real sol_invoke_signed_c"
      -- Pure peer method+args CPI: empty AccountMeta pack (PF-P2-03). Host accounts
      -- are not forwarded; program_id is copied from the target input account.
      require (src.contains "AccountMeta") "asm documents AccountMeta packing policy"
      require (src.contains "empty AccountMeta pack" || src.contains "accounts=0")
        "pure peer asm uses empty AccountMeta pack (no host-account forward)"
      require (src.contains "sol_get_return_data") "asm decodes return data"
      require (src.contains "error_cpi") "asm traps CPI failures"
      -- Anchor/Pinocchio-style checks live in entrypoint prologue (materialize → lower).
      require (src.contains "account.validation") "entrypoint emits account.validation prologue"
      require (src.contains "error_signer") "signer trap present"
      require (src.contains "error_owner") "owner trap present"
      require (src.contains "signer=true") "payer role gets signer check"
      require (src.contains "owner=executable") "callee_program gets executable check"
      -- program_id comes from the runtime target account index (peer/callee).
      require (src.contains "program_id" || src.contains "peer/callee" ||
          src.contains "input account")
        "asm resolves CPI program_id from input account target index"
  -- NEAR: portable invoke → promise_create; full fixture still works.
  require ((forProfile wasmNear).nativeForm == NativeForm.nearPromise) "NEAR form"
  let nearPortable := ProofForge.IR.Examples.NearCrosscallProbe.portableModule
  require (moduleUsesPortableInvoke nearPortable) "portable NEAR uses crosscall.invoke"
  require (!moduleUsesPromiseExtension nearPortable) "portable NEAR has no promise constructors"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule nearPortable with
  | .error e => throw (IO.userError s!"NEAR EmitWat portableModule failed: {e.message}")
  | .ok wat =>
      require (wat.contains "promise_create") "NEAR materializes promise_create"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule nearProbe with
  | .error e => throw (IO.userError s!"NEAR EmitWat full NearCrosscallProbe failed: {e.message}")
  | .ok wat =>
      require (wat.contains "promise_create") "full fixture promise_create"
      require (wat.contains "promise_then") "extension path materializes promise_then"
  -- Honest reject when nearCrosscallStrings is empty (no silent EVM CALL).
  let bareNear : ProofForge.IR.Module := {
    name := "BareNearCrosscall"
    state := nearProbe.state
    entrypoints := #[ProofForge.IR.Examples.NearCrosscallProbe.callRemote]
  }
  match ProofForge.Backend.WasmHost.EmitWat.renderModule bareNear with
  | .ok _ => throw (IO.userError "NEAR bare crosscall without nearCrosscallStrings must fail")
  | .error e =>
      require (e.message.contains "nearCrosscallStrings" || e.message.contains "promise")
        s!"expected nearCrosscallStrings / promise diagnostic, got: {e.message}"

  -- Solana: EVM-only STATICCALL is rejected (not silently remapped to CPI).
  -- Peer declared so PortableHonesty empty-peer does not fire before policy.
  let staticOnly : ProofForge.IR.Module := {
    name := "StaticOnly"
    state := probe.state
    entrypoints := #[ProofForge.IR.Examples.CrosscallProbe.callRemoteStatic]
    nearCrosscallStrings := #["TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"]
  }
  match ProofForge.Backend.Solana.SbpfAsm.renderModule staticOnly with
  | .ok _ => throw (IO.userError "Solana must reject STATICCALL")
  | .error e =>
      require (e.message.contains "STATICCALL" || e.message.contains "EVM-only" ||
          e.message.contains "static")
        s!"expected STATICCALL reject, got: {e.message}"

  -- CosmWasm: general portable remote → execute_msg (Wasm family host, not token-only).
  require ((forProfile wasmCosmWasm).nativeForm == NativeForm.cosmWasmMsg) "CosmWasm form"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule nearPortable .cosmWasm with
  | .error e => throw (IO.userError s!"CosmWasm should lower portable crosscall to execute_msg: {e.message}")
  | .ok wat =>
      require (wat.contains "execute_msg")
        "CosmWasm WAT must import/call execute_msg for portable crosscall"
      require (!wat.contains "promise_create")
        "CosmWasm must not import NEAR promise_create"

  -- Psy: untyped U64 crosscall accepted; typed/create rejected.
  require ((forProfile psyDpn).nativeForm == NativeForm.zkCircuitCall) "Psy form"
  let psyMod := ProofForge.IR.Examples.CrosscallProbe.psyModule
  match ProofForge.Backend.Psy.IR.buildModule psyMod with
  | .error e => throw (IO.userError s!"Psy should accept untyped crosscall.invoke: {e.message}")
  | .ok _ => pure ()
  match ProofForge.Backend.Psy.IR.buildModule staticOnly with
  | .ok _ => throw (IO.userError "Psy must reject STATICCALL-shaped crosscall")
  | .error e =>
      require (e.message.contains "static" || e.message.contains "not supported" ||
          e.message.contains "U64")
        s!"expected Psy static reject, got: {e.message}"

  require ((forProfile aleoLeo).nativeForm == NativeForm.zkCircuitCall) "Aleo form"
  require ((forProfile solanaSbpfAsm).nativeForm == NativeForm.solanaCpi) "Solana form"
  -- Solana account ceilings used by portable CPI packing.
  require (MAX_TX_ACCOUNT_LOCKS == 64) "Solana tx lock limit is 64"
  require (MAX_CPI_ACCOUNT_INFOS == 128) "Solana CPI account infos ceiling is 128"
  require (MAX_PORTABLE_CPI_ACCOUNTS == MAX_TX_ACCOUNT_LOCKS)
    "portable CPI max equals full tx lock limit (heap infos)"
  require (MAX_PORTABLE_CPI_ACCOUNTS == 64)
    "heap-backed infos pack full MAX_TX_ACCOUNT_LOCKS (64)"
  require (HEAP_START_ADDRESS == 0x300000000) "Solana heap base"
  require (PORTABLE_CPI_INFO_HEAP_BYTES == 64 * 56) "heap reserve for 64 AccountInfos"
  require ((forProfile moveAptos).nativeForm == NativeForm.moveCall) "Aptos form"
  require ((forProfile moveSui).nativeForm == NativeForm.moveCall) "Sui form"
  -- Soroban is next host adapter: honest form, never alias NEAR promise.
  require (NativeForm.sorobanInvoke.id == "soroban-invoke") "Soroban form id"
  require (NativeForm.sorobanInvoke != NativeForm.nearPromise)
    "Soroban must not be mapped as near-promise"
  require ((forProfile wasmCosmWasm).note.contains "execute_msg" ||
      (forProfile wasmCosmWasm).nativeForm == NativeForm.cosmWasmMsg)
    "CosmWasm form documents execute_msg portable remote"
  -- Soroban: portable crosscall → invoke_contract, never promise_create.
  match ProofForge.Backend.WasmHost.EmitWat.renderModule nearPortable .soroban with
  | .error e => throw (IO.userError s!"Soroban should lower portable crosscall to invoke_contract: {e.message}")
  | .ok wat =>
      require (wat.contains "invoke_contract")
        "Soroban WAT must import/call invoke_contract for portable crosscall"
      require (!wat.contains "promise_create")
        "Soroban WAT must not emit NEAR promise_create"
      require (!wat.contains "promise_then")
        "Soroban portable path must not emit promise_then"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule
      ProofForge.IR.Examples.NearCrosscallProbe.promiseExtensionModule .soroban with
  | .ok _ => throw (IO.userError "Soroban bridge must reject NEAR Promise constructors")
  | .error e =>
      require (e.message.contains "Soroban" || e.message.contains "Promise")
        s!"expected Soroban Promise reject, got: {e.message}"
  -- Storage-only modules still lower on Soroban bridge (host adapter path).
  match ProofForge.Backend.WasmHost.EmitWat.renderModule
      ProofForge.IR.Examples.Counter.module .soroban with
  | .error e => throw (IO.userError s!"Counter should still lower on Soroban bridge: {e.message}")
  | .ok wat =>
      require (!wat.contains "promise_create")
        "Counter Soroban WAT should not import NEAR promise_create for storage-only module"
      require (!wat.contains "invoke_contract")
        "Counter storage-only Soroban WAT should not import invoke_contract"

  -- Shared portable RemoteCall (contract_source + remoteCall) multi-target.
  let shared := Examples.Product.RemoteCall.module
  require (moduleHasPortableCrosscall shared) "Shared.RemoteCall has portable crosscall"
  -- L0+L1 preflight on primary targets before materialize/emit.
  let pref := runPrimary shared
  require (pref.size == 3) "primary preflight = evm · solana · near"
  -- EVM + Solana accept portable crosscall.invoke; NEAR needs string pool (has it).
  for r in pref do
    require r.readyToMaterialize s!"preflight should be ready for {r.targetId}: {r.note}"
  require ((run solanaSbpfAsm shared).crosscallNativeForm == "solana-cpi") "preflight solana form"
  require ((run evm shared).crosscallNativeForm == "evm-call") "preflight evm form"
  require ((run wasmNear shared).crosscallNativeForm == "near-promise") "preflight near form"
  -- Unified map: primary triad + Soroban host-adapter profile.
  let withSoroban := runPrimaryWithSoroban nearPortable
  require (withSoroban.size == 4) "primary+soroban preflight size"
  require ((run wasmStellarSoroban nearPortable).crosscallNativeForm == "soroban-invoke")
    "preflight soroban form"
  require ((run wasmStellarSoroban nearPortable).readyToMaterialize)
    "portable crosscall ready on Soroban host profile"
  require ((forProfile wasmStellarSoroban).nativeForm == NativeForm.sorobanInvoke)
    "forProfile wasmStellarSoroban → soroban-invoke"
  require ((forProfile wasmStellarSoroban).note.contains "invoke_contract")
    "Soroban note names invoke_contract"
  -- Family-only Promise module must fail Solana/EVM preflight portability.
  let nearExt := ProofForge.IR.Examples.NearCrosscallProbe.promiseExtensionModule
  require (!(run solanaSbpfAsm nearExt).portabilityOk)
    "NEAR promise extension must fail Solana portability preflight"
  require (!(run evm nearExt).portabilityOk)
    "NEAR promise extension must fail EVM portability preflight"
  match ProofForge.Backend.Evm.Plan.buildModulePlan shared with
  | .error e => throw (IO.userError s!"EVM plan Shared.RemoteCall failed: {e.message}")
  | .ok _ => pure ()
  -- T3.1: Shared.RemoteCall.call_with_args passes portable u64 literals.
  require (shared.entrypoints.any (fun ep => ep.name == "call_with_args"))
    "Shared.RemoteCall exposes call_with_args"
  match ProofForge.Backend.Evm.IR.renderModule {
    shared with
    entrypoints := shared.entrypoints.map fun ep =>
      match ep.name with
      | "initialize" => { ep with selector? := some "8129fc1c" }
      | "call_remote" => { ep with selector? := some "e8902e74" }
      | "call_with_args" => { ep with selector? := some "728f8748" }
      | _ => ep
  } with
  | .error e => throw (IO.userError s!"EVM Yul Shared.RemoteCall: {e.message}")
  | .ok yul =>
      require (yul.contains "__proof_forge_crosscall_2(0, 1, 42, 7)" ||
          (yul.contains "42" && yul.contains "7" && yul.contains "crosscall"))
        "EVM remote scalar ABI materializes u64 args 42 and 7"
  match ProofForge.Target.resolveModule solanaSbpfAsm shared with
  | .error e => throw (IO.userError s!"Solana resolve Shared.RemoteCall: {e.render}")
  | .ok _ => pure ()
  match ProofForge.Backend.Solana.SbpfAsm.renderModule shared with
  | .error e => throw (IO.userError s!"Solana lower Shared.RemoteCall: {e.message}")
  | .ok src =>
      require (src.contains "sol_invoke_signed_c") "Shared.RemoteCall Solana CPI"
      require (src.contains "sol_get_return_data") "Shared.RemoteCall return-data"
  -- NEAR needs string-pool metadata for account/method names; use portable IR probe.
  match ProofForge.Backend.WasmHost.EmitWat.renderModule nearPortable with
  | .error e => throw (IO.userError s!"NEAR portable path for multi-target failed: {e.message}")
  | .ok wat => require (wat.contains "promise_create") "NEAR multi-target promise_create"
  -- Shared RemoteCall NEAR + Soroban: scalar args in host crosscall path.
  match ProofForge.Backend.WasmHost.EmitWat.renderModule shared with
  | .error e => throw (IO.userError s!"NEAR Shared.RemoteCall: {e.message}")
  | .ok wat =>
      require (wat.contains "promise_create") "Shared.RemoteCall NEAR promise"
      require (wat.contains "i64.const 42")
        "NEAR remote scalar ABI embeds u64 arg 42"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule shared .soroban with
  | .error e => throw (IO.userError s!"Soroban Shared.RemoteCall: {e.message}")
  | .ok wat =>
      require (wat.contains "invoke_contract") "Shared.RemoteCall Soroban invoke"
      require (wat.contains "i64.const 42")
        "Soroban remote scalar ABI embeds u64 arg 42"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule shared .cosmWasm with
  | .error e => throw (IO.userError s!"CosmWasm Shared.RemoteCall: {e.message}")
  | .ok wat =>
      require (wat.contains "execute_msg") "Shared.RemoteCall CosmWasm execute_msg"
      require (wat.contains "i64.const 42")
        "CosmWasm remote scalar ABI embeds u64 arg 42"

  IO.println "crosscall-materialize: ok (evm·solana·near·soroban·cosmwasm general remote + scalar args)"
