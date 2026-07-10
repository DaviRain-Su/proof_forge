/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Host bridge metadata for Wasm-family targets.

A host bridge captures the chain-specific imports and required exports that a
Wasm module must provide to run on a given host (e.g. NEAR, CosmWasm). The
ProofForge compiler uses this metadata to decide which host functions to import
and which contract entrypoints/exports to emit.
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic

namespace ProofForge.Target

/-- The host bridge used by a Wasm-family target profile.

Each variant lists the standard imports and required exports for that host so
that the generic Wasm backend can be driven by the target profile instead of
hard-coding NEAR semantics. -/
inductive HostBridge where
  | near
  | cosmWasm
  | soroban
  deriving BEq, DecidableEq, Repr

def HostBridge.id : HostBridge → String
  | .near => "near"
  | .cosmWasm => "cosmwasm"
  | .soroban => "soroban"

/-- A host function import description. `params`/`results` use WAT type names
(`i32`, `i64`) so that the bridge module stays independent of the Wasm AST. -/
structure HostFunction where
  name : String
  params : Array String
  results : Array String
  deriving BEq, DecidableEq, Repr

/-- Required Wasm exports for each host bridge. These are checked by the
respective chain validation tools (e.g. `near-cli`, `cosmwasm-check`). -/
def HostBridge.requiredExports : HostBridge → Array String
  | .near => #["main"]
  | .cosmWasm => #["interface_version_8", "allocate", "deallocate", "instantiate", "execute", "query"]
  | .soroban => #["_start", "__contract_spec_setup"]

/-- Standard host function imports required by each bridge. This is a
metadata-only list; the actual lowering is backend-specific. -/
def HostBridge.requiredImports : HostBridge → Array String
  | .near => #[
      "env.storage_read",
      "env.storage_write",
      "env.read_register",
      "env.value_return",
      "env.signer_account_id",
      "env.attached_deposit",
      "env.block_timestamp",
      "env.epoch_height",
      "env.random_seed",
      "env.promise_create",
      "env.promise_then",
      "env.promise_results_count",
      "env.promise_result",
      "env.promise_return"
    ]
  | .cosmWasm => #[
      "env.db_read",
      "env.db_write",
      -- Portable crosscall.invoke → WasmMsg-shaped host execute (spike ABI).
      "env.execute_msg"
    ]
  | .soroban => #[
      "env._put",
      "env._get",
      "env.log_from_slice",
      "env.require_auth_for_args",
      "env.invoke_contract"
    ]

/-- Full host-function signatures for each bridge. Used by generic Wasm
backends to build the import section without hard-coding a particular host.

For NEAR this covers the core storage/register/return ABI; auxiliary
functions such as `sha256`, `log_utf8`, context accessors, and the
optional `storage_has_key` are still emitted by the NEAR-specific backend
because they depend on the exact capability surface being lowered. -/
def HostBridge.hostFunctions : HostBridge → Array HostFunction
  | .near => #[
      { name := "storage_read",  params := #["i64", "i64", "i64"], results := #["i64"] },
      { name := "storage_write", params := #["i64", "i64", "i64", "i64", "i64"], results := #["i64"] },
      { name := "read_register", params := #["i64", "i64"], results := #[] },
      { name := "value_return",  params := #["i64", "i64"], results := #[] },
      { name := "signer_account_id", params := #["i64"], results := #[] },
      -- near-sys: void attached_deposit(uint64_t balance_ptr) — writes u128 LE.
      { name := "attached_deposit", params := #["i64"], results := #[] },
      { name := "block_timestamp", params := #[], results := #["i64"] },
      { name := "epoch_height", params := #[], results := #["i64"] },
      { name := "random_seed", params := #["i64"], results := #[] },
      { name := "promise_create", params := #["i64", "i64", "i64", "i64", "i64", "i64", "i64", "i64"], results := #["i64"] },
      { name := "promise_then", params := #["i64", "i64", "i64", "i64", "i64", "i64", "i64", "i64", "i64"], results := #["i64"] },
      { name := "promise_results_count", params := #[], results := #["i64"] },
      { name := "promise_result", params := #["i64", "i64"], results := #["i64"] },
      { name := "promise_return", params := #["i64"], results := #[] }
    ]
  | .cosmWasm => #[
      { name := "db_read",  params := #["i32"], results := #["i32"] },
      { name := "db_write", params := #["i32", "i32"], results := #[] },
      -- Same packing as Soroban invoke_contract: contract/method string pool +
      -- JSON args scratch → host result handle. Real CosmWasm WasmMsg encoding
      -- lands as a later spike; this host surface unblocks general peer remote.
      { name := "execute_msg",
        params := #["i64", "i64", "i64", "i64", "i64", "i64"],
        results := #["i64"] }
    ]
  | .soroban => #[
      { name := "_put",  params := #["i32", "i32", "i32", "i32"], results := #[] },
      { name := "_get",  params := #["i32", "i32"], results := #["i32"] },
      { name := "log_from_slice", params := #["i32", "i32"], results := #[] },
      { name := "require_auth_for_args", params := #["i32", "i32"], results := #["i32"] },
      -- Portable crosscall.invoke materializes here (not NEAR promise_create).
      -- Contract/method names come from the shared nearCrosscallStrings pool;
      -- args are the same JSON scratch buffer used by NEAR. Returns a host
      -- result handle (i64) — real Env::invoke_contract lands as a later spike.
      { name := "invoke_contract",
        params := #["i64", "i64", "i64", "i64", "i64", "i64"],
        results := #["i64"] }
    ]

end ProofForge.Target
