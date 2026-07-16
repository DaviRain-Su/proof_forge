/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Portable Address / Identity (gap-analysis route step 2)

Authors use `ValueType.address` and HostEnv `caller` / `selfAddress` as a
**portable identity handle**. Native encodings differ fundamentally:

| Target | Encoding | Width |
|--------|----------|-------|
| EVM | 20-byte address | 20 |
| Solana | 32-byte pubkey | 32 |
| NEAR | named account id (UTF-8 string) | variable |

This module is the single materialize-or-reject table for that handle.
No portable authoring surface exposes EVM-20 / Solana-32 / NEAR-name forms
as distinct types — adapters pick encoding via `materializeIdentity`.

See `docs/zh/chain-agnostic-gap-analysis.md` § ⑤ and `docs/host-runtime.md`.
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic

namespace ProofForge.Target.Identity

/-- Role of a portable identity read / value. -/
inductive IdentityRole where
  /-- Immediate caller (msg.sender · signer · predecessor). -/
  | caller
  /-- This contract / program / account. -/
  | self
  /-- Cross-call peer handle (logical peer id, not native encoding). -/
  | peer
  deriving BEq, DecidableEq, Repr

def IdentityRole.id : IdentityRole → String
  | .caller => "identity.caller"
  | .self => "identity.self"
  | .peer => "identity.peer"

/-- How a target encodes portable identity natively. -/
inductive NativeIdentityEncoding where
  | evmAddress20
  | solanaPubkey32
  | nearAccountId
  | unsupported
  deriving BEq, DecidableEq, Repr

def NativeIdentityEncoding.id : NativeIdentityEncoding → String
  | .evmAddress20 => "evm-address-20"
  | .solanaPubkey32 => "solana-pubkey-32"
  | .nearAccountId => "near-account-id"
  | .unsupported => "unsupported"

/-- Materialization of a portable identity handle on one target. -/
structure IdentityMaterialization where
  targetId : String
  role : IdentityRole
  encoding : NativeIdentityEncoding
  /-- Fixed byte width when known; `none` for variable-length (NEAR names). -/
  byteWidth? : Option Nat
  /-- Host / IR surface used for this role when known. -/
  hostSymbol? : Option String := none
  semanticsNote? : Option String := none
  deriving Repr, BEq

/-- Diagnostic when identity cannot materialize. -/
def identityReject (targetId : String) (role : IdentityRole) (reason : String) : String :=
  s!"Identity: target `{targetId}` cannot materialize `{role.id}`: {reason}"

/-- Encode form for a target id (independent of role). -/
def encodingForTarget (targetId : String) : NativeIdentityEncoding :=
  match targetId with
  | "evm" => .evmAddress20
  | "solana-sbpf-asm" => .solanaPubkey32
  | "wasm-near" => .nearAccountId
  | _ => .unsupported

def byteWidthForEncoding : NativeIdentityEncoding → Option Nat
  | .evmAddress20 => some 20
  | .solanaPubkey32 => some 32
  | .nearAccountId => none
  | .unsupported => none

/-- Materialize portable identity for `role` on `targetId`.

Honesty: only primary triad has full rows. Unknown targets reject.
Solana `self` uses `contextRead.contractId` → program-id sha256 limb0
(HostEnv.selfAddress / OwnableHash convention). -/
def materializeIdentity (targetId : String) (role : IdentityRole) :
    Except String IdentityMaterialization :=
  let enc := encodingForTarget targetId
  match enc, targetId, role with
  | .unsupported, _, _ =>
      .error (identityReject targetId role
        s!"no Identity encoding row for target `{targetId}`")
  | .evmAddress20, "evm", .caller =>
      .ok {
        targetId := targetId, role := role, encoding := enc
        byteWidth? := some 20, hostSymbol? := some "caller"
        semanticsNote? := some "msg.sender 20-byte"
      }
  | .evmAddress20, "evm", .self =>
      .ok {
        targetId := targetId, role := role, encoding := enc
        byteWidth? := some 20, hostSymbol? := some "address"
      }
  | .evmAddress20, "evm", .peer =>
      .ok {
        targetId := targetId, role := role, encoding := enc
        byteWidth? := some 20, hostSymbol? := some "call.target"
        semanticsNote? := some "crosscall peer as address word"
      }
  | .solanaPubkey32, "solana-sbpf-asm", .caller =>
      .ok {
        targetId := targetId, role := role, encoding := enc
        byteWidth? := some 32, hostSymbol? := some "tx_signer_account"
        semanticsNote? := some "first signer pubkey (sha256 limb0 in u64 context path)"
      }
  | .solanaPubkey32, "solana-sbpf-asm", .self =>
      .ok {
        targetId := targetId, role := role, encoding := enc
        byteWidth? := some 32, hostSymbol? := some "program_id"
        semanticsNote? := some "program id pubkey; contextRead.contractId uses sha256 limb0 u64"
      }
  | .solanaPubkey32, "solana-sbpf-asm", .peer =>
      .ok {
        targetId := targetId, role := role, encoding := enc
        byteWidth? := some 32, hostSymbol? := some "cpi.program_id"
        semanticsNote? := some "peer as program/account pubkey in CPI frame"
      }
  | .nearAccountId, "wasm-near", .caller =>
      .ok {
        targetId := targetId, role := role, encoding := enc
        byteWidth? := none, hostSymbol? := some "env.predecessor_account_id"
        semanticsNote? := some "UTF-8 account id; predecessor under async receipts"
      }
  | .nearAccountId, "wasm-near", .self =>
      .ok {
        targetId := targetId, role := role, encoding := enc
        byteWidth? := none, hostSymbol? := some "env.current_account_id"
      }
  | .nearAccountId, "wasm-near", .peer =>
      .ok {
        targetId := targetId, role := role, encoding := enc
        byteWidth? := none, hostSymbol? := some "env.promise_create"
        semanticsNote? := some "peer account id string in crosscallStrings pool"
      }
  | _, _, _ =>
      .error (identityReject targetId role "no Identity materialize row")

def supportsIdentity (targetId : String) (role : IdentityRole) : Bool :=
  match materializeIdentity targetId role with
  | .ok _ => true
  | .error _ => false

/-- Portable IR type for identity handles (alias of `ValueType.address` concept). -/
def portableTypeName : String := "Address"

/-- All primary triad target ids for identity tests. -/
def primaryTargetIds : Array String := #["evm", "solana-sbpf-asm", "wasm-near"]

/-- All identity roles. -/
def allRoles : Array IdentityRole := #[.caller, .self, .peer]

end ProofForge.Target.Identity
