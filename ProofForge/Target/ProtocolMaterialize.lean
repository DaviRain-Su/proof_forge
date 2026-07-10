/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Protocol materialize (portable external-token intent → host packing)

Authors express **business** intent: transfer / approve / balance of an
*already-deployed* fungible token peer. They never import Layer B clients
(`Protocols.Evm.IERC20`, `Protocols.Near.FungibleToken`, SPL CPI builders).

Method identity is a **host string-pool entry** registered by
`Contract.Protocol.declareExternalToken` (canonical NEP-141-shaped names that
also act as portable protocol ids). Each host materializes:

| Pool method id   | EVM                          | NEAR (promise)              | Solana (γ.1 honesty)        |
|------------------|------------------------------|-----------------------------|-----------------------------|
| `ft_transfer`    | IERC20 `transfer` selector   | `ft_transfer` + JsonEncode  | portable CPI method tag     |
| `approve`        | IERC20 `approve`             | legacy JSON array (no NEP)  | portable CPI method tag     |
| `transferFrom`   | IERC20 `transferFrom`        | legacy JSON array           | portable CPI method tag     |
| `ft_balance_of`  | IERC20 `balanceOf`           | `ft_balance_of` + JsonEncode| portable CPI method tag     |
| `ft_total_supply`| IERC20 `totalSupply`         | `ft_total_supply` + `{}`    | portable CPI method tag     |
| `deposit` / vault | IERC4626 deposit / convert   | n/a (EVM-first)             | portable CPI smoke          |
| `permit`         | EIP-2612 permit              | n/a                         | portable CPI smoke          |

**Solana note:** real SPL `transfer_checked` needs account metas + per-program
`dataLayout` (TokenSpec / Source.Solana CPI). Portable `crosscall.invoke` still
packs LE method+args for general peer remote; protocol intent on Solana is
therefore **IR/CPI-shaped smoke**, not live Tokenkeg equivalence. Token product
loop for *being* the mint uses `just product-token-solana` (plan path).

Related: [protocols-layer](../../docs/protocols-layer.md),
[product-sdk-gap-plan](../../docs/product-sdk-gap-plan-2026-07.md) Wave γ / ε.
-/
import ProofForge.IR.Contract

namespace ProofForge.Target.ProtocolMaterialize

open ProofForge.IR

/-- Catalog id for docs / diagnostics. -/
def catalogId : String := "target.protocol_materialize"

/-- Canonical pool method ids (portable protocol intent). Prefer these over
hand-written IERC20 selectors in Product sources. -/
def methodFtTransfer : String := "ft_transfer"
def methodApprove : String := "approve"
def methodTransferFrom : String := "transferFrom"
def methodFtBalanceOf : String := "ft_balance_of"
def methodFtTotalSupply : String := "ft_total_supply"
def methodPermit : String := "permit"
def methodVaultDeposit : String := "deposit"
def methodVaultWithdraw : String := "withdraw"
def methodVaultConvertToShares : String := "convertToShares"
def methodVaultConvertToAssets : String := "convertToAssets"
def methodVaultTotalAssets : String := "totalAssets"
def methodVaultAsset : String := "asset"

/-- All portable FT protocol method ids registered by `declareExternalToken`. -/
def portableFtMethodIds : Array String := #[
  methodFtTransfer,
  methodApprove,
  methodTransferFrom,
  methodFtBalanceOf,
  methodFtTotalSupply
]

/-- Vault + permit pool method ids (`declareExternalVault` / permit). -/
def portableVaultMethodIds : Array String := #[
  methodVaultDeposit,
  methodVaultWithdraw,
  methodVaultConvertToShares,
  methodVaultConvertToAssets,
  methodVaultTotalAssets,
  methodVaultAsset
]

/-- IERC20 / EIP-2612 / IERC4626 4-byte selectors. -/
def evmSelector? : String → Option Nat
  | "ft_transfer" | "transfer" => some 0xa9059cbb
  | "approve" => some 0x095ea7b3
  | "transferFrom" | "ft_transfer_from" => some 0x23b872dd
  | "ft_balance_of" | "balanceOf" => some 0x70a08231
  | "ft_total_supply" | "totalSupply" => some 0x18160ddd
  | "permit" => some 0xd505accf
  | "nonces" => some 0x7ecebe00
  | "DOMAIN_SEPARATOR" => some 0x3644e515
  | "asset" => some 0x38d52e0f
  | "totalAssets" => some 0x01e1d114
  | "convertToShares" => some 0xc6e6f592
  | "convertToAssets" => some 0x07a2d13a
  | "maxDeposit" => some 0x402d267d
  | "maxWithdraw" => some 0xce96cb77
  | "deposit" => some 0x6e553f65
  | "mint" => some 0x94bf804d
  | "withdraw" => some 0xb460af94
  | "redeem" => some 0xba087652
  -- PF-P2-03: generic RemoteCall peer method (call_with_args → two uint256 words).
  | "remote_call" => some 0xf1ae0699
  | _ => none

/-- Parse a `0x`-prefixed EVM address (≤20 bytes) into a Nat word. -/
def parseEvmAddressHex? (s : String) : Option Nat :=
  let raw :=
    if s.startsWith "0x" || s.startsWith "0X" then s.drop 2 else s
  if raw.isEmpty || raw.length > 40 then none
  else if !raw.all fun c => c.isDigit || ('a' ≤ c && c ≤ 'f') || ('A' ≤ c && c ≤ 'F') then
    none
  else
    some <| raw.foldl (init := 0) fun acc c =>
      let v :=
        if c.isDigit then c.toNat - '0'.toNat
        else if 'a' ≤ c && c ≤ 'f' then c.toNat - 'a'.toNat + 10
        else c.toNat - 'A'.toNat + 10
      acc * 16 + v
/-- NEAR native method name for promise_create (identity for NEP-141 names). -/
def nearMethod? : String → Option String
  | "ft_transfer" => some "ft_transfer"
  | "ft_transfer_call" => some "ft_transfer_call"
  | "ft_balance_of" => some "ft_balance_of"
  | "ft_total_supply" => some "ft_total_supply"
  | "ft_metadata" => some "ft_metadata"
  | "transfer" => some "ft_transfer"  -- portable alias → NEP-141
  | "balanceOf" => some "ft_balance_of"
  | "totalSupply" => some "ft_total_supply"
  | _ => none

/-- Whether NEAR should use NEP-141 object JSON packing for this method id. -/
def nearUsesNep141JsonObject? (methodName : String) : Bool :=
  match nearMethod? methodName with
  | some "ft_transfer" | some "ft_transfer_call" | some "ft_balance_of"
  | some "ft_total_supply" | some "ft_metadata" => true
  | _ => false

/-- Resolve a crosscall method expr for EVM: pool address-handle → selector word
when the pool string is a known protocol method; otherwise leave unchanged
(generic remote keeps handle index as method id). -/
def resolveEvmMethodExpr (pool : Array String) (methodId : Expr) : Expr :=
  match methodId with
  | .literal (.address idx) =>
      match pool[idx]? with
      | some name =>
          match evmSelector? name with
          | some sel => .literal (.u64 sel)
          | none => methodId
      | none => methodId
  | _ => methodId

/-- Resolve a crosscall target for EVM (PF-P2-03): after `PeerMap` rewrites a
logical peer id to a `0x…` host address string, turn the pool handle into a
literal address word so CALL uses the real peer rather than index 0. -/
def resolveEvmTargetExpr (pool : Array String) (target : Expr) : Expr :=
  match target with
  | .literal (.address idx) =>
      match pool[idx]? with
      | some host =>
          match parseEvmAddressHex? host with
          | some addr => .literal (.address addr)
          | none => target
      | none => target
  | _ => target

/-- Materialize note for operators / JSON reports. -/
structure HostNote where
  hostId : String
  packing : String
  honesty : String
  deriving Repr

def hostNotes : Array HostNote := #[
  { hostId := "evm"
    packing := "CALL + 4-byte selector (IERC20) + ABI words"
    honesty := "pool method strings mapped via ProtocolMaterialize.evmSelector?" },
  { hostId := "wasm-near"
    packing := "promise_create + NEP-141 JsonEncode objects for ft_* methods"
    honesty := "canonical pool ids are NEP-141 method names" },
  { hostId := "solana-sbpf-asm"
    packing := "portable CPI (LE method tag + u64 args); not SPL dataLayout"
    honesty := "live Tokenkeg transfer_checked needs TokenSpec / Source.Solana CPI" }
]

def HostNote.json (n : HostNote) : String :=
  let esc (s : String) := "\"" ++ s ++ "\""
  "{" ++
  "\"hostId\":" ++ esc n.hostId ++ "," ++
  "\"packing\":" ++ esc n.packing ++ "," ++
  "\"honesty\":" ++ esc n.honesty ++
  "}"

end ProofForge.Target.ProtocolMaterialize
