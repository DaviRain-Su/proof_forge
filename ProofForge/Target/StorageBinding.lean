/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Target-resolved storage binding (D-050)

Portable IR state is chain-neutral (`StateKind` + `ValueType` only). Each
target adapter maps that abstract persistent state onto a native binding
model at lowering time. Authors never pick "object" vs "resource" vs
"storage slot" in source — `--target` does.

This module is the single vocabulary for that resolution so backends,
plans, and docs share one name for "how this target materializes
`storage.scalar` / `storage.map` / …".
-/
import ProofForge.Target.Registry

namespace ProofForge.Target

/-- How a target materializes portable persistent state. -/
inductive StorageBinding where
  /-- EVM-style contract-global storage (slots / layouts). -/
  | contractGlobal
  /-- Solana account data layout (plus PDA/CPI via extensions). -/
  | accountData
  /-- Wasm-host key/value storage (NEAR, and similar hosts). -/
  | hostKeyValue
  /-- ZK / circuit storage mapping (felt-backed or similar). -/
  | circuitMapping
  deriving BEq, DecidableEq, Repr

def StorageBinding.id : StorageBinding → String
  | .contractGlobal => "contract-global"
  | .accountData => "account-data"
  | .hostKeyValue => "host-key-value"
  | .circuitMapping => "circuit-mapping"

def StorageBinding.describe : StorageBinding → String
  | .contractGlobal => "EVM contract storage slots"
  | .accountData => "Solana account data layout"
  | .hostKeyValue => "Wasm host key/value storage"
  | .circuitMapping => "ZK circuit storage mapping"

/-- Resolve the native storage binding for a target profile. Pure function of
the selected target — never of author annotations on portable IR. -/
def TargetProfile.storageBinding (profile : TargetProfile) : StorageBinding :=
  match profile.id with
  | "evm" => .contractGlobal
  | "solana-sbpf-asm" | "solana-sbpf-linker" | "solana-zig-fork" => .accountData
  | "wasm-near" | "wasm-cosmwasm"
  | "wasm-stellar-soroban" => .hostKeyValue
  | "psy-dpn" | "aleo-leo" => .circuitMapping
  | _ =>
      match profile.family with
      | .evm => .contractGlobal
      | .solana => .accountData
      | .wasmHost => .hostKeyValue
      | .zkCircuitSourcegen => .circuitMapping

def storageBindingForTargetId? (targetId : String) : Option StorageBinding :=
  (find? targetId).map (·.storageBinding)

end ProofForge.Target
