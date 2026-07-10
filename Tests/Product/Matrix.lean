/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Product multi-target matrix (Phase 3)

Every **Product** business module must materialize on primary hosts by changing
only `--target` semantics (plan / lower). Authors never write chain DSL.

Hosts: EVM plan · Solana sBPF · NEAR EmitWat · Soroban EmitWat · CosmWasm
remote (`execute_msg`). General peer remote is multi-host (not token-only).
TokenSpec: EVM · Solana · NEAR honesty only (no Soroban token lane).
-/
import Examples.Product.AccessControl
import Examples.Product.ArrayExample
import Examples.Product.AuthRemoteCall
import Examples.Product.Counter
import Examples.Product.EscrowVault
import Examples.Product.HostEnvProbe
import Examples.Product.ExternalTokenTransfer
import Examples.Product.ExternalVault
import Examples.Product.FeeToken
import Examples.Product.FungibleToken
import Examples.Product.GuestBook
import Examples.Product.HeightLockVault
import Examples.Product.Ownable
import Examples.Product.OwnableHash
import Examples.Product.OwnablePausable
import Examples.Product.Pausable
import Examples.Product.ProRataVault
import Examples.Product.ReentrancyGuard
import Examples.Product.RemoteCall
import Examples.Product.RoleGatedToken
import Examples.Product.SoulboundToken
import Examples.Product.SoulboundTokenBody
import Examples.Product.StakingVault
import Examples.Product.StatusMessage
import Examples.Product.StorageDeposit
import Examples.Product.TimelockVault
import Examples.Product.ValueVault
import Examples.Product.VestingVault
import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.Materialize
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Contract.Token
import ProofForge.IR.Contract
import ProofForge.IR.Examples.Counter
import ProofForge.Target.HostBridge
import ProofForge.Target.Materialize
import ProofForge.Target.Registry

namespace ProofForge.Tests.Product.Matrix

open ProofForge.IR
open ProofForge.Target
open ProofForge.Target.Materialize
open ProofForge.Backend.Solana.Manifest
open ProofForge.Contract.Token

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

/-- EVM + Wasm-host materialization shared by the full and partial matrices. -/
def assertEvmWasmHosts (label : String) (m : Module) : IO Unit := do
  match ProofForge.Backend.Evm.Plan.buildModulePlan m with
  | .error e => throw (IO.userError s!"{label} EVM plan: {e.message}")
  | .ok _ => pure ()
  match ProofForge.Backend.WasmHost.EmitWat.renderModule m with
  | .error e => throw (IO.userError s!"{label} NEAR: {e.message}")
  | .ok wat => require (wat.length > 0) s!"{label} NEAR empty wat"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule m .soroban with
  | .error e => throw (IO.userError s!"{label} Soroban: {e.message}")
  | .ok wat =>
      require (wat.length > 0) s!"{label} Soroban empty wat"
      require (!contains wat "promise_create")
        s!"{label} Soroban must not import NEAR promise_create"

/-- Primary four-host materialize for a portable IR module. -/
def assertFourHost (label : String) (m : Module) : IO Unit := do
  assertEvmWasmHosts label m
  match ProofForge.Backend.Solana.SbpfAsm.renderModule m with
  | .error e => throw (IO.userError s!"{label} Solana: {e.message}")
  | .ok src =>
      require (src.length > 0) s!"{label} Solana empty asm"
      require (contains src "account.validation" || contains src "entrypoint")
        s!"{label} Solana should emit entrypoint/account materialization"

/-- Storage binding reports for primary three (auto-portable). -/
def assertAutoPortablePrimary (label : String) (m : Module) : IO Unit := do
  let evmR := Materialize.forEvm m
  let solR := Materialize.forSolana m {}
  let nearR := Materialize.forWasmNear m
  require (evmR.mode == .autoPortable) s!"{label} EVM auto-portable"
  require (solR.mode == .autoPortable) s!"{label} Solana auto-portable"
  require (nearR.mode == .autoPortable) s!"{label} NEAR auto-portable"
  require (evmR.storageBinding == "contract-global") s!"{label} EVM binding"
  require (solR.storageBinding == "account-data") s!"{label} Solana binding"
  require (nearR.storageBinding == "host-key-value") s!"{label} NEAR binding"

/-- Phase 2: Product is author source; IR fixture shares shape (not body/selectors). -/
def testCounterSingleSource : IO Unit := do
  let product := Examples.Product.Counter.module
  let ir := ProofForge.IR.Examples.Counter.module
  require (product.name == ir.name) "Counter name Product=IR fixture"
  require (product.state.map (·.id) == ir.state.map (·.id))
    "Counter state ids Product=IR fixture"
  require (product.entrypoints.map (·.name) == ir.entrypoints.map (·.name))
    "Counter entrypoint names Product=IR fixture"
  require (product.entrypoints.map (·.name) == #["initialize", "increment", "get"])
    "Product Counter entrypoint names"
  -- Authors do not pin selectors; IR fixture may keep them for EVM CLI goldens.
  require (product.entrypoints.all (fun e => e.selector?.isNone))
    "Product Counter must be name-only (no author selectors)"
  assertAutoPortablePrimary "Counter" product
  assertFourHost "Counter" product
  assertFourHost "HostEnvProbe" Examples.Product.HostEnvProbe.module
  assertAutoPortablePrimary "HostEnvProbe" Examples.Product.HostEnvProbe.module
  -- Triad HostEnv fields must lower on Solana (U1.1–U1.2).
  match ProofForge.Backend.Solana.SbpfAsm.renderModule Examples.Product.HostEnvProbe.module with
  | .error e => throw (IO.userError s!"HostEnvProbe Solana: {e.message}")
  | .ok src =>
      require (contains src "Clock.unix_timestamp" || contains src "sol_get_clock_sysvar")
        "HostEnvProbe Solana must lower timestamp via Clock"
      require (contains src "program_id" || contains src "contractId")
        "HostEnvProbe Solana must lower contractId / program_id"

def testPolicies : IO Unit := do
  for (label, m) in #[
    ("Ownable", Examples.Product.Ownable.module),
    ("OwnableHash", Examples.Product.OwnableHash.module),
    ("Pausable", Examples.Product.Pausable.module),
    ("OwnablePausable", Examples.Product.OwnablePausable.module),
    ("AccessControl", Examples.Product.AccessControl.module),
    ("ReentrancyGuard", Examples.Product.ReentrancyGuard.module)
  ] do
    assertFourHost label m
  -- Ownable: Solana synthesizes authority without Source.Solana
  let ownable := Examples.Product.Ownable.module
  let accounts := buildModuleAccounts ownable {}
  require (accounts.any (fun a => a.name == "authority" && a.signer))
    "Ownable Solana authority auto-fill"

def testVaultsAndTokens : IO Unit := do
  for (label, module) in #[
    ("ValueVault", Examples.Product.ValueVault.module),
    ("StakingVault", Examples.Product.StakingVault.module),
    ("RoleGatedToken", Examples.Product.RoleGatedToken.module),
    ("ArrayExample", Examples.Product.ArrayExample.module),
    ("EscrowVault", Examples.Product.EscrowVault.module),
    ("GuestBook", Examples.Product.GuestBook.module),
    ("HeightLockVault", Examples.Product.HeightLockVault.module),
    ("ProRataVault", Examples.Product.ProRataVault.module),
    ("SoulboundTokenBody", Examples.Product.SoulboundTokenBody.module),
    ("StatusMessage", Examples.Product.StatusMessage.module),
    ("TimelockVault", Examples.Product.TimelockVault.module),
    ("VestingVault", Examples.Product.VestingVault.module)
  ] do
    assertFourHost label module
  assertEvmWasmHosts "StorageDeposit" Examples.Product.StorageDeposit.module
  -- nativeValue → writable signer@0
  let stakeAccounts := buildModuleAccounts Examples.Product.StakingVault.module {}
  match stakeAccounts[0]? with
  | some a =>
      require a.signer "StakingVault leading signer"
      require a.writable "StakingVault nativeValue writable fee payer"
  | none => throw (IO.userError "StakingVault empty accounts")

/-- General peer remote (not token CPI): native form on every product host family. -/
def testRemote : IO Unit := do
  let remote := Examples.Product.RemoteCall.module
  let authRemote := Examples.Product.AuthRemoteCall.module
  let extFt := Examples.Product.ExternalTokenTransfer.module
  let extVault := Examples.Product.ExternalVault.module
  assertFourHost "RemoteCall" remote
  assertFourHost "AuthRemoteCall" authRemote
  assertFourHost "ExternalTokenTransfer" extFt
  assertFourHost "ExternalVault" extVault
  require (extFt.nearCrosscallStrings.any (· == "ft_transfer"))
    "ExternalTokenTransfer registers protocol method ft_transfer"
  -- EVM CALL (product sources are name-only; pin selectors for Yul emit only)
  let remoteEvm : Module := {
    remote with
    entrypoints := remote.entrypoints.map fun (ep : Entrypoint) =>
      if ep.name == "initialize" then { ep with selector? := some "8129fc1c" }
      else if ep.name == "call_remote" then { ep with selector? := some "e8902e74" }
      else if ep.name == "call_with_args" then { ep with selector? := some "728f8748" }
      else ep
  }
  match ProofForge.Backend.Evm.IR.renderModule remoteEvm with
  | Except.error e => throw (IO.userError s!"RemoteCall EVM Yul: {e.message}")
  | Except.ok yul =>
      require (contains yul "call(" || contains yul "__proof_forge_crosscall")
        "RemoteCall EVM must emit CALL / crosscall helper"
      require (contains yul "__proof_forge_crosscall_2" || contains yul "42")
        "RemoteCall multi-arg path on EVM"
  -- Solana general CPI (any program via account index — not SPL-only)
  match ProofForge.Backend.Solana.SbpfAsm.renderModule remote with
  | .ok src =>
      require (contains src "sol_invoke_signed_c") "RemoteCall Solana CPI"
      require (contains src "data_len=24" || contains src "portable crosscall")
        "RemoteCall multi-arg Solana ix packing"
  | .error e => throw (IO.userError e.message)
  -- NEAR Promise
  match ProofForge.Backend.WasmHost.EmitWat.renderModule remote with
  | .ok wat => require (contains wat "promise_create") "RemoteCall NEAR promise"
  | .error e => throw (IO.userError e.message)
  -- Soroban invoke_contract
  match ProofForge.Backend.WasmHost.EmitWat.renderModule remote .soroban with
  | .ok wat => require (contains wat "invoke_contract") "RemoteCall Soroban invoke"
  | .error e => throw (IO.userError e.message)
  -- CosmWasm execute_msg (Wasm host family, general peer remote)
  match ProofForge.Backend.WasmHost.EmitWat.renderModule remote .cosmWasm with
  | .ok wat =>
      require (contains wat "execute_msg") "RemoteCall CosmWasm execute_msg"
      require (!contains wat "promise_create") "CosmWasm must not use NEAR promise"
  | .error e => throw (IO.userError s!"RemoteCall CosmWasm: {e.message}")
  let authAccounts := buildModuleAccounts authRemote {}
  require (authAccounts.any (·.signer)) "AuthRemoteCall authority"
  require (authAccounts.any (fun a => a.name == "callee_program"))
    "AuthRemoteCall callee_program auto-fill"

def testTokenIntent : IO Unit := do
  -- Fungible: three-host plan (no Soroban lane)
  match planForTarget evm Examples.Product.FungibleToken.spec with
  | .error e => throw (IO.userError s!"Fungible EVM: {e}")
  | .ok _ => pure ()
  match planForTarget solanaSbpfAsm Examples.Product.FungibleToken.spec with
  | .error e => throw (IO.userError s!"Fungible Solana: {e}")
  | .ok _ => pure ()
  match planForTarget wasmNear Examples.Product.FungibleToken.spec with
  | .error e => throw (IO.userError s!"Fungible NEAR: {e}")
  | .ok _ => pure ()
  -- Fee / soulbound: Solana ok; EVM honest reject
  match planForTarget solanaSbpfAsm Examples.Product.FeeToken.spec with
  | .error e => throw (IO.userError s!"Fee Solana: {e}")
  | .ok _ => pure ()
  match planForTarget evm Examples.Product.FeeToken.spec with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError "FeeToken must reject on EVM")
  match planForTarget evm Examples.Product.SoulboundToken.spec with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError "Soulbound must reject on EVM")
  match planForTarget wasmStellarSoroban Examples.Product.FungibleToken.spec with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError "Soroban must have no TokenSpec lane")

def main : IO UInt32 := do
  testCounterSingleSource
  testPolicies
  testVaultsAndTokens
  testRemote
  testTokenIntent
  IO.println "product-matrix: ok (Counter·policies·vaults·remote·token × catalog-declared hosts)"
  return 0

end ProofForge.Tests.Product.Matrix

def main : IO UInt32 :=
  ProofForge.Tests.Product.Matrix.main
