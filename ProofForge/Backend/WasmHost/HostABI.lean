/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Host ABI — Bridge-specific host call name mapping

Centralizes the mapping from logical host operations (storage read, caller
identity, block info, crypto, input, return, event log, crosscall) to the
concrete host import names for each Wasm-host bridge (NEAR, Soroban, CosmWasm).

Helpers consume this abstraction instead of hardcoding NEAR-specific names.
Adding a new Wasm target means providing a `HostABI` entry — not hunting
hardcoded strings across Scalar/Map/Hash/Context/Params.

## Register ABI note

NEAR uses a register-based return convention: host calls write results into
numbered registers, then `read_register` copies them to memory. Soroban
and CosmWasm return values directly (on stack or via direct memory writes).
`usesRegisterABI` tells helpers whether the register dance is needed.
-/

import ProofForge.Target.HostBridge

namespace ProofForge.Backend.WasmHost

open ProofForge.Target

/-- Logical host operation categories. Each maps to concrete import names
and instruction sequences per bridge. -/
structure HostABI where
  /-- Whether this bridge uses NEAR's register ABI (read_register/register_len).
  Soroban and CosmWasm do not use registers. -/
  usesRegisterABI : Bool
  -- Storage (already handled by Scalar/Map helpers — listed for documentation)
  storageRead : String
  storageWrite : String
  -- Input: how the contract receives its invocation arguments
  input : String
  -- Return: how the contract returns data to the host
  returnData : String
  -- Caller identity: how to get the immediate caller's account bytes
  callerAccount : String
  -- Signer: how to get the transaction signer's account bytes (origin)
  signerAccount : String
  -- Contract self: how to get the current contract's account bytes
  currentAccount : String
  -- Block info
  blockTimestamp : String
  blockNumber : String
  epochHeight : String
  -- Crypto
  sha256 : String
  -- Random
  randomSeed : String
  -- Gas
  prepaidGas : String
  usedGas : String
  -- Event log
  logEvent : String
  -- Crosscall
  crosscall : String

/-- NEAR host ABI: register-based, with the full NEAR Protocol import set. -/
def HostABI.near : HostABI := {
  usesRegisterABI := true
  storageRead := "storage_read"
  storageWrite := "storage_write"
  input := "input"
  returnData := "value_return"
  callerAccount := "predecessor_account_id"
  signerAccount := "signer_account_id"
  currentAccount := "current_account_id"
  blockTimestamp := "block_timestamp"
  blockNumber := "block_index"
  epochHeight := "epoch_height"
  sha256 := "sha256"
  randomSeed := "random_seed"
  prepaidGas := "prepaid_gas"
  usedGas := "used_gas"
  logEvent := "log_utf8"
  crosscall := "promise_create"
}

/-- Soroban host ABI.

ProofForge's Soroban bridge uses a simplified custom ABI. Storage uses
`_get`/`_put` (Soroban-style). Crosscall uses `invoke_contract`. Auth uses
`require_auth_for_args`. Events use `log_from_slice`.

For context (caller/block/crypto), the bridge currently retains NEAR-style
imports (`predecessor_account_id`, `sha256`, `block_timestamp`, etc.) because
ProofForge's offline host model implements them. Real Soroban Env uses
different imports (`get_caller`, `sha256_hash`, `get_ledger_timestamp`, etc.)
— mapping to those is future work.

The register ABI is NOT used: Soroban's `_get` returns values directly.
However, context helpers still use `read_register` because they were written
for NEAR. A future refactor should make context helpers register-free for
non-NEAR bridges.
-/
def HostABI.soroban : HostABI := {
  usesRegisterABI := true  -- context helpers still use register ABI (TODO: make register-free)
  storageRead := "_get"
  storageWrite := "_put"
  input := "input"          -- retained NEAR import (Soroban uses different input, TODO)
  returnData := "set_return_data"  -- Soroban native return ABI (i32 ptr, i32 len)
  callerAccount := "predecessor_account_id"  -- retained (Soroban uses require_auth + get_caller)
  signerAccount := "signer_account_id"       -- retained
  currentAccount := "current_account_id"     -- retained
  blockTimestamp := "block_timestamp"        -- retained (Soroban uses get_ledger_timestamp)
  blockNumber := "block_index"               -- retained (Soroban uses get_ledger_sequence)
  epochHeight := "epoch_height"              -- retained
  sha256 := "sha256"                         -- retained (different calling convention)
  randomSeed := "n/a"                        -- NOT supported on Soroban (fail closed)
  prepaidGas := "n/a"                        -- NOT supported on Soroban
  usedGas := "n/a"                           -- NOT supported on Soroban
  logEvent := "log_from_slice"
  crosscall := "invoke_contract"
}

/-- CosmWasm host ABI. -/
def HostABI.cosmWasm : HostABI := {
  usesRegisterABI := false
  storageRead := "db_read"
  storageWrite := "db_write"
  input := "input"
  returnData := "set_return_data"
  callerAccount := "n/a"     -- via message envelope
  signerAccount := "n/a"
  currentAccount := "n/a"
  blockTimestamp := "n/a"
  blockNumber := "n/a"
  epochHeight := "n/a"
  sha256 := "n/a"
  randomSeed := "n/a"
  prepaidGas := "n/a"
  usedGas := "n/a"
  logEvent := "n/a"
  crosscall := "execute_msg"
}

/-- Resolve the HostABI for a given bridge. -/
def HostABI.for (bridge : HostBridge) : HostABI :=
  match bridge with
  | .near => .near
  | .soroban => .soroban
  | .cosmWasm => .cosmWasm

/-- The log event import name for a bridge. -/
def HostABI.logEventName (bridge : HostBridge) : String :=
  (HostABI.for bridge).logEvent

/-- The crosscall host call name for a bridge. -/
def HostABI.crosscallName (bridge : HostBridge) : String :=
  (HostABI.for bridge).crosscall

end ProofForge.Backend.WasmHost