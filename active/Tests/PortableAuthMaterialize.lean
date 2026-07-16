/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Portable business checks (Ownable / Pausable / require*) materialize on
EVM · Solana · NEAR · Soroban without chain DSL in source.
-/
import Examples.Product.AccessControl
import Examples.Product.Ownable
import Examples.Product.OwnableHash
import Examples.Product.OwnablePausable
import Examples.Product.Pausable
import Examples.Product.ReentrancyGuard
import Examples.Product.RemoteCall
import Examples.Product.RoleGatedToken
import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.Materialize
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Target.HostBridge
import ProofForge.Target.PeerMap
import ProofForge.Target.Preflight
import ProofForge.Target.Registry

open ProofForge.Target
open ProofForge.Target.Preflight
open ProofForge.Backend.Solana.Manifest

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def main : IO Unit := do
  let ownable := Examples.Product.Ownable.module
  let remote := Examples.Product.RemoteCall.module

  -- C.6: Shared holds logical peers; deploy PeerMap rewrites host ids.
  require (!remote.crosscallStrings.isEmpty)
    "declareRemoteUnit must populate host string pool for Wasm materialize"
  require (remote.crosscallStrings[0]? == some "peer.callee")
    "logical peer id in Shared (not chain account)"
  require (remote.crosscallStrings[1]? == some "remote_call")
    "method id registered"
  let deployed := PeerMap.applyToModule remote PeerMap.nearDemo
  require (deployed.crosscallStrings[0]? == some "callee.example.near")
    "PeerMap.nearDemo rewrites peer.callee → callee.example.near"
  require (deployed.crosscallStrings[1]? == some "remote_call")
    "unmapped method id stays as declared"

  -- Ownable: business guard_owner / require* → each backend's native fail.
  match ProofForge.Backend.Evm.Plan.buildModulePlan ownable with
  | .error e => throw (IO.userError s!"EVM Ownable plan: {e.message}")
  | .ok _ => pure ()

  -- C.3: portable Ownable synthesizes leading `authority` signer so userId
  -- is the tx authority, not the program state account.
  let ownableAccounts := buildModuleAccounts ownable {}
  require (ownableAccounts.any (fun a => a.name == "authority" && a.signer))
    "Ownable Solana schema must synthesize authority signer for caller"
  require (
      match ownableAccounts[0]? with
      | some a => a.signer
      | none => false)
    "authority/signer must lead account list so context.userId is correct"
  require (ownableAccounts.any (fun a => a.name == "owner" && a.owner == "program"))
    "Ownable state account remains program-owned data"
  let ownableMat := ProofForge.Backend.Solana.Materialize.report ownable {}
  require (ownableMat.note.contains "callerIdentity" || ownableMat.note.contains "sha256")
    "Solana materialize note must document sha256(full pubkey) caller identity"

  match ProofForge.Backend.Solana.SbpfAsm.renderModule ownable with
  | .error e => throw (IO.userError s!"Solana Ownable lower: {e.message}")
  | .ok src =>
      require (src.contains "assert" || src.contains "assert_fail" || src.contains "error_")
        "Solana Ownable should emit assert/trap materialization for business checks"
      require (src.contains "account.validation[0:authority]: signer=true" ||
          src.contains "signer=true")
        "Solana Ownable prologue validates authority signer"
      require (src.contains "control.assert" || src.contains "assert_eq" ||
          src.contains "assert_fail")
        "guard_owner materializes as control.assert"
      require (src.contains "sol_sha256")
        "Ownable caller identity must hash full authority pubkey"
      require (src.contains "error_syscall")
        "sha256 path must include error_syscall trap"

  match ProofForge.Backend.WasmHost.EmitWat.renderModule ownable with
  | .error e => throw (IO.userError s!"NEAR Ownable lower: {e.message}")
  | .ok wat =>
      -- assert without ErrorRef → `unreachable`; with ref → env.panic
      require (wat.contains "unreachable" || wat.contains "panic")
        "NEAR Ownable business checks materialize as unreachable/panic"
      require (!wat.contains "promise_create")
        "Ownable has no crosscall; no promise_create"

  match ProofForge.Backend.WasmHost.EmitWat.renderModule ownable .soroban with
  | .error e => throw (IO.userError s!"Soroban Ownable lower: {e.message}")
  | .ok wat =>
      require (wat.contains "unreachable" || wat.contains "panic")
        "Soroban Ownable reuses EmitWat assert fail for business checks"
      require (!wat.contains "promise_create")
        "Soroban Ownable must not import NEAR promise_create"
      require (!wat.contains "invoke_contract")
        "Ownable has no portable crosscall"
      -- C.8: scalar storage on Soroban host names, not NEAR storage_*.
      require (wat.contains "_get" || wat.contains "_put")
        "Soroban Ownable storage should import/call _get/_put"
      require (!wat.contains "storage_read" && !wat.contains "storage_write")
        "Soroban Ownable must not import NEAR storage_read/write"
      -- C.9: caller-using entrypoints emit require_auth_for_args prologue.
      require (wat.contains "require_auth_for_args")
        "Soroban Ownable with caller should emit require_auth_for_args"

  -- RemoteCall on Soroban host bridge: invoke_contract, not promise.
  match ProofForge.Backend.WasmHost.EmitWat.renderModule remote .soroban with
  | .error e => throw (IO.userError s!"Soroban RemoteCall: {e.message}")
  | .ok wat =>
      require (wat.contains "invoke_contract")
        "Soroban RemoteCall → invoke_contract"
      require (!wat.contains "promise_create")
        "Soroban RemoteCall must not use promise_create"
      require (wat.contains "peer.callee")
        "Soroban WAT keeps logical peer without PeerMap"
  -- Deploy map applied at emit: host account appears in pool data.
  match ProofForge.Backend.WasmHost.EmitWat.renderModule remote .near PeerMap.nearDemo with
  | .error e => throw (IO.userError s!"NEAR RemoteCall with PeerMap: {e.message}")
  | .ok wat =>
      require (wat.contains "promise_create") "NEAR still promise_create"
      require (wat.contains "callee.example.near")
        "PeerMap.nearDemo embeds host account in WAT"
      require (!wat.contains "peer.callee")
        "logical peer should be rewritten after PeerMap"

  -- Preflight primary + Soroban ready for Ownable and RemoteCall.
  for mod in #[ownable, remote] do
    let reps := runPrimaryWithSoroban mod
    require (reps.size == 4) "primary+soroban size"
    for r in reps do
      require r.readyToMaterialize
        s!"preflight should be ready for {r.targetId} on {mod.name}: {r.note}"

  -- Hash-width Ownable: callerHash / requireOwnerHash on NEAR · EVM · Solana.
  let ownableHash := Examples.Product.OwnableHash.module
  require (ownableHash.state.any (fun s => s.id == "owner" && s.type == .hash))
    "OwnableHash stores owner as Hash"

  -- EVM selectors (cast keccak of ABI sigs) so full IR lower can dispatch.
  let ownableHashEvm : ProofForge.IR.Module := {
    ownableHash with
    entrypoints := ownableHash.entrypoints.map fun ep =>
      match ep.name with
      | "owner" => { ep with selector? := some "8da5cb5b" }
      | "renounceOwnership" => { ep with selector? := some "715018a6" }
      | "init" => { ep with selector? := some "e1c7392a" }
      | _ => ep
  }
  match ProofForge.Backend.Evm.Plan.buildModulePlan ownableHashEvm with
  | .error e => throw (IO.userError s!"EVM OwnableHash plan: {e.message}")
  | .ok _ => pure ()
  match ProofForge.Backend.Evm.IR.renderModule ownableHashEvm with
  | .error e => throw (IO.userError s!"EVM OwnableHash Yul: {e.message}")
  | .ok yul =>
      require (yul.contains "__proof_forge_hash_word(caller())")
        "EVM OwnableHash userIdHash lowers as hashWord(caller)"
      require (yul.contains "keccak256")
        "EVM OwnableHash hashWord helper uses keccak256"
      require (yul.contains "sload" && yul.contains "sstore")
        "EVM OwnableHash stores hash owner in scalar slot"

  match ProofForge.Backend.WasmHost.EmitWat.renderModule ownableHash with
  | .error e => throw (IO.userError s!"NEAR OwnableHash: {e.message}")
  | .ok wat =>
      require (wat.contains "unreachable" || wat.contains "panic")
        "OwnableHash NEAR should assert"
      require (wat.contains "sha256" || wat.contains "predecessor")
        "OwnableHash NEAR uses host identity path"

  match ProofForge.Backend.Solana.SbpfAsm.renderModule ownableHash with
  | .error e => throw (IO.userError s!"Solana OwnableHash lower: {e.message}")
  | .ok src =>
      require (src.contains "hash4" || src.contains "limb0")
        "Solana OwnableHash should lower hash4 zero literal"
      require (src.contains "sol_sha256")
        "Solana OwnableHash callerHash uses full-pubkey sha256"
      require (src.contains "assert" || src.contains "assert_eq" || src.contains "assert_fail")
        "Solana OwnableHash requireOwnerHash materializes as assert"

  -- T1.1/T1.2: Pausable emergency-stop on four hosts (unauthenticated pause API).
  let pausable := Examples.Product.Pausable.module
  require (pausable.state.any (fun s => s.id == "paused" && s.type == .u64))
    "Pausable stores paused as u64"
  match ProofForge.Backend.Evm.Plan.buildModulePlan pausable with
  | .error e => throw (IO.userError s!"EVM Pausable plan: {e.message}")
  | .ok _ => pure ()
  let pausableEvm : ProofForge.IR.Module := {
    pausable with
    entrypoints := pausable.entrypoints.map fun ep =>
      match ep.name with
      | "paused" => { ep with selector? := some "5c975abb" }
      | "pause" => { ep with selector? := some "8456cb59" }
      | "unpause" => { ep with selector? := some "3f4ba83a" }
      | _ => ep
  }
  match ProofForge.Backend.Evm.IR.renderModule pausableEvm with
  | .error e => throw (IO.userError s!"EVM Pausable Yul: {e.message}")
  | .ok yul =>
      require (yul.contains "revert")
        "EVM Pausable guards materialize as revert"
      require (yul.contains "sload" && yul.contains "sstore")
        "EVM Pausable reads/writes paused slot"
  match ProofForge.Backend.Solana.SbpfAsm.renderModule pausable with
  | .error e => throw (IO.userError s!"Solana Pausable: {e.message}")
  | .ok src =>
      require (src.contains "assert" || src.contains "assert_eq" || src.contains "assert_fail")
        "Solana Pausable guard materializes as assert"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule pausable with
  | .error e => throw (IO.userError s!"NEAR Pausable: {e.message}")
  | .ok wat =>
      require (wat.contains "unreachable" || wat.contains "panic")
        "NEAR Pausable checks materialize as unreachable/panic"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule pausable .soroban with
  | .error e => throw (IO.userError s!"Soroban Pausable: {e.message}")
  | .ok wat =>
      require (wat.contains "unreachable" || wat.contains "panic")
        "Soroban Pausable checks materialize as unreachable/panic"
      require (wat.contains "_get" || wat.contains "_put")
        "Soroban Pausable uses host storage"

  -- T1.3: OwnablePausable — only owner may pause/unpause.
  let ownablePausable := Examples.Product.OwnablePausable.module
  require (ownablePausable.state.any (fun s => s.id == "owner"))
    "OwnablePausable has owner"
  require (ownablePausable.state.any (fun s => s.id == "paused"))
    "OwnablePausable has paused"
  match ProofForge.Backend.Evm.Plan.buildModulePlan ownablePausable with
  | .error e => throw (IO.userError s!"EVM OwnablePausable plan: {e.message}")
  | .ok _ => pure ()
  match ProofForge.Backend.Solana.SbpfAsm.renderModule ownablePausable with
  | .error e => throw (IO.userError s!"Solana OwnablePausable: {e.message}")
  | .ok src =>
      require (src.contains "sol_sha256")
        "OwnablePausable Solana uses caller digest for owner check"
      require (src.contains "assert" || src.contains "assert_eq" || src.contains "assert_fail")
        "OwnablePausable Solana asserts owner + pause guards"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule ownablePausable with
  | .error e => throw (IO.userError s!"NEAR OwnablePausable: {e.message}")
  | .ok wat =>
      require (wat.contains "unreachable" || wat.contains "panic")
        "NEAR OwnablePausable business checks"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule ownablePausable .soroban with
  | .error e => throw (IO.userError s!"Soroban OwnablePausable: {e.message}")
  | .ok wat =>
      require (wat.contains "require_auth_for_args")
        "Soroban OwnablePausable with caller emits require_auth"
      require (wat.contains "unreachable" || wat.contains "panic")
        "Soroban OwnablePausable fail path"

  -- T1.5: ReentrancyGuard lock-state materializes on four hosts (not EVM-only).
  let reent := Examples.Product.ReentrancyGuard.module
  match ProofForge.Backend.Evm.Plan.buildModulePlan reent with
  | .error e => throw (IO.userError s!"EVM ReentrancyGuard plan: {e.message}")
  | .ok _ => pure ()
  match ProofForge.Backend.Solana.SbpfAsm.renderModule reent with
  | .error e => throw (IO.userError s!"Solana ReentrancyGuard: {e.message}")
  | .ok _ => pure ()
  match ProofForge.Backend.WasmHost.EmitWat.renderModule reent with
  | .error e => throw (IO.userError s!"NEAR ReentrancyGuard: {e.message}")
  | .ok _ => pure ()
  match ProofForge.Backend.WasmHost.EmitWat.renderModule reent .soroban with
  | .error e => throw (IO.userError s!"Soroban ReentrancyGuard: {e.message}")
  | .ok wat =>
      require (wat.contains "_get" || wat.contains "_put")
        "Soroban ReentrancyGuard uses host storage for lock"

  -- T1.4: AccessControl / roles — nested map path on four hosts.
  let accessControl := Examples.Product.AccessControl.module
  match ProofForge.Backend.Evm.Plan.buildModulePlan accessControl with
  | .error e => throw (IO.userError s!"EVM AccessControl plan: {e.message}")
  | .ok _ => pure ()
  match ProofForge.Backend.Solana.SbpfAsm.renderModule accessControl with
  | .error e => throw (IO.userError s!"Solana AccessControl: {e.message}")
  | .ok src =>
      require (src.contains "assert" || src.contains "assert_eq" || src.contains "assert_fail")
        "Solana AccessControl role guards assert"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule accessControl with
  | .error e => throw (IO.userError s!"NEAR AccessControl: {e.message}")
  | .ok wat =>
      require (wat.contains "__pf_map_read_nested" || wat.contains "map_read_nested" ||
          wat.contains "__pf_map_write_nested")
        "NEAR AccessControl uses nested map helpers for role membership"
      require (wat.contains "unreachable" || wat.contains "panic")
        "NEAR AccessControl guard_role fails closed"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule accessControl .soroban with
  | .error e => throw (IO.userError s!"Soroban AccessControl: {e.message}")
  | .ok wat =>
      require (wat.contains "_get" || wat.contains "_put")
        "Soroban AccessControl map path uses host _get/_put (not NEAR storage_*)"
      require (!wat.contains "storage_read" && !wat.contains "storage_write")
        "Soroban AccessControl must not import NEAR storage_*"

  let roleGated := Examples.Product.RoleGatedToken.module
  match ProofForge.Backend.WasmHost.EmitWat.renderModule roleGated with
  | .error e => throw (IO.userError s!"NEAR RoleGatedToken: {e.message}")
  | .ok wat =>
      require (wat.contains "__pf_map_read_nested" || wat.contains "__pf_map_write_nested")
        "RoleGatedToken NEAR uses nested role map helpers"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule roleGated .soroban with
  | .error e => throw (IO.userError s!"Soroban RoleGatedToken: {e.message}")
  | .ok wat =>
      require (wat.contains "_get" || wat.contains "_put")
        "RoleGatedToken Soroban maps via host storage"

  for mod in #[pausable, ownablePausable, reent, accessControl, roleGated] do
    let reps := runPrimaryWithSoroban mod
    require (reps.size == 4) s!"preflight size for {mod.name}"
    for r in reps do
      require r.readyToMaterialize
        s!"preflight ready {r.targetId} on {mod.name}: {r.note}"

  IO.println "portable-auth-materialize: ok (policies·roles·OwnableHash + RemoteCall · EVM·Solana·NEAR·Soroban)"
