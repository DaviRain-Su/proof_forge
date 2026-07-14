/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer B — NEAR NEP-141 fungible token *peer* client

Promise/remote helpers for calling an **already-deployed** FT contract.

This is **not** `Contract.Stdlib.NearFungibleToken` (Layer C: *you* implement
NEP-141). Method names follow NEP-141 / NEP-148 / common NEP-145 surfaces.

Uses Layer A `declareRemote` so Wasm-NEAR materializes `promise_create` with
the method string in the host pool. Bind the FT account with
`--peer my_ft=token.near` at deploy time.

## Arg packing (EmitWat + JsonEncode)

For known NEP-141 methods, EmitWat builds a `JsonEncode.Node` object schema and
lowers it once via `WasmHost/JsonEncode` (shared putc/putstr/putu64 sink). Call
sites must not hand-roll JSON ASCII. Resulting **JSON objects** (not a bare array):

| Method | Args (portable) | JSON args |
|--------|-----------------|-----------|
| `ft_transfer` | `[receiverPoolIdx, amount]` | `{"receiver_id":"…","amount":"…","memo":null}` |
| `ft_transfer_call` | `[receiver, amount]` or `+ msgU64` | `{"receiver_id","amount","msg"}` |
| `ft_balance_of` | `[accountPoolIdx]` | `{"account_id":"…"}` |
| `ft_total_supply` / `ft_metadata` | `[]` | `{}` |

Account ids are **string pool indices** (`registerAccountId` / `peerHandle`).
Amount is a portable U64 rendered as a decimal JSON string.
Full arbitrary Borsh/JSON remains out of scope — wrong arity → EmitWat reject.
-/
import ProofForge.Contract.Source.Internal

namespace ProofForge.Protocols.Near.FungibleToken

open ProofForge.Contract.Source.Internal

/-- Catalog id for docs / diagnostics. -/
def catalogId : String := "protocols.near.fungible_token"

def methodFtTransfer : String := "ft_transfer"
def methodFtTransferCall : String := "ft_transfer_call"
def methodFtBalanceOf : String := "ft_balance_of"
def methodFtTotalSupply : String := "ft_total_supply"
def methodFtMetadata : String := "ft_metadata"
def methodStorageDeposit : String := "storage_deposit"

/-- Bound peer + method (`RemoteRef` from Layer A). -/
abbrev FtMethod := RemoteRef

/-- Register a NEAR account id into the host string pool; returns a handle expr
for use as `receiver_id` / `account_id` pool index. -/
def registerAccountId (accountId : String) : ModuleM ProofForge.IR.Expr := do
  let idx ← ProofForge.Contract.Builder.ensureCrosscallString accountId
  pure (peerHandle idx)

/-- Register `ft_transfer` against a logical FT peer. -/
def declareFtTransfer (peerId : String) : ModuleM FtMethod :=
  declareRemote peerId methodFtTransfer

/-- Register `ft_transfer_call` against a logical FT peer. -/
def declareFtTransferCall (peerId : String) : ModuleM FtMethod :=
  declareRemote peerId methodFtTransferCall

/-- Register `ft_balance_of` against a logical FT peer. -/
def declareFtBalanceOf (peerId : String) : ModuleM FtMethod :=
  declareRemote peerId methodFtBalanceOf

/-- Register `ft_total_supply` against a logical FT peer. -/
def declareFtTotalSupply (peerId : String) : ModuleM FtMethod :=
  declareRemote peerId methodFtTotalSupply

/-- Register `ft_metadata` against a logical FT peer. -/
def declareFtMetadata (peerId : String) : ModuleM FtMethod :=
  declareRemote peerId methodFtMetadata

/-- Register `storage_deposit` (NEP-145) against a logical FT peer. -/
def declareStorageDeposit (peerId : String) : ModuleM FtMethod :=
  declareRemote peerId methodStorageDeposit

/-- Packing mode for NEP-141 methods with EmitWat object JSON. -/
inductive ArgPackingBound where
  /-- NEP-141 JSON objects for known methods; legacy scalar JSON array otherwise. -/
  | nep141JsonObject
  deriving BEq, Repr

def argPackingBound : ArgPackingBound := .nep141JsonObject

def argPackingBoundId : String := "nep141_json_object"

/-- Max portable scalar args for **non**-NEP-141 legacy array packing. -/
def maxPortableScalarArgs : Nat := 8

/-- Honesty for legacy scalar-array path (unknown methods). -/
def requireArgPackingHonest (argCount : Nat) : Except String Unit :=
  if argCount > maxPortableScalarArgs then
    .error s!"NEAR FT peer client: arg packing honesty — at most \
{maxPortableScalarArgs} portable scalar args (bound `{argPackingBoundId}`); \
got {argCount}."
  else
    .ok ()

/-- Low-level invoke (prefer `ftTransfer` / `ftBalanceOf`). -/
def call (m : FtMethod) (args : Array ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCallRef m args

/-- `ft_transfer`: receiver pool handle + amount (U64). -/
def ftTransfer (m : FtMethod) (receiverPoolIdx amount : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  call m #[receiverPoolIdx, amount]

/-- `ft_transfer_call` without msg (empty string). -/
def ftTransferCall (m : FtMethod) (receiverPoolIdx amount : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  call m #[receiverPoolIdx, amount]

/-- `ft_transfer_call` with msg as decimal U64 string. -/
def ftTransferCallWithMsg (m : FtMethod) (receiverPoolIdx amount msgU64 : ProofForge.IR.Expr) :
    ProofForge.IR.Expr :=
  call m #[receiverPoolIdx, amount, msgU64]

/-- `ft_balance_of`: account pool handle. -/
def ftBalanceOf (m : FtMethod) (accountPoolIdx : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  call m #[accountPoolIdx]

/-- `ft_total_supply`. -/
def ftTotalSupply (m : FtMethod) : ProofForge.IR.Expr :=
  call m #[]

/-- Same as `call` but fails when arg count exceeds the legacy scalar honesty bound. -/
def callHonest (m : FtMethod) (args : Array ProofForge.IR.Expr) : Except String ProofForge.IR.Expr :=
  match requireArgPackingHonest args.size with
  | .error e => .error e
  | .ok () => .ok (call m args)

end ProofForge.Protocols.Near.FungibleToken
