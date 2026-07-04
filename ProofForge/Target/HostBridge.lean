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
  deriving BEq, DecidableEq, Repr

def HostBridge.id : HostBridge → String
  | .near => "near"
  | .cosmWasm => "cosmwasm"

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

/-- Standard host function imports required by each bridge. This is a
metadata-only list; the actual lowering is backend-specific. -/
def HostBridge.requiredImports : HostBridge → Array String
  | .near => #[
      "env.storage_read",
      "env.storage_write",
      "env.read_register",
      "env.value_return",
      "env.signer_account_id",
      "env.attached_deposit"
    ]
  | .cosmWasm => #[
      "env.db_read",
      "env.db_write"
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
      { name := "attached_deposit", params := #[], results := #["i64"] }
    ]
  | .cosmWasm => #[
      { name := "db_read",  params := #["i32"], results := #["i32"] },
      { name := "db_write", params := #["i32", "i32"], results := #[] }
    ]

end ProofForge.Target
