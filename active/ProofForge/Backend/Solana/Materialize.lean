/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana auto-materialization (Phase B.2)

Product rule: authors write portable IR / `contract_source` business logic only.
`--target solana-sbpf-asm` synthesizes the Solana account schema without
requiring `import ProofForge.Contract.Source.Solana`.

Modes:

* `autoPortable` — no Solana extension metadata; state lives in a default
  program-owned writable account derived from portable `Module.state`.
* `extensionDeclared` — capability plan / Source.Solana declared accounts,
  PDAs, or CPIs; those merge on top of the portable default state account.

TokenSpec has its own plan materializer (`planForTarget`); this module covers
general portable `contract_source` modules (Counter, ValueVault, …).
-/
import ProofForge.IR.Contract
import ProofForge.Backend.Solana.Extension.Types
import ProofForge.Backend.Solana.Manifest
import ProofForge.Target.StorageBinding

namespace ProofForge.Backend.Solana.Materialize

open ProofForge.IR
open ProofForge.Backend.Solana.Extension
open ProofForge.Backend.Solana.Manifest
open ProofForge.Target

inductive MaterializationMode where
  | autoPortable
  | extensionDeclared
  deriving BEq, DecidableEq, Repr

def MaterializationMode.id : MaterializationMode → String
  | .autoPortable => "auto-portable"
  | .extensionDeclared => "extension-declared"

def MaterializationMode.describe : MaterializationMode → String
  | .autoPortable =>
      "accounts synthesized from portable IR state (no Source.Solana authoring)"
  | .extensionDeclared =>
      "accounts include Solana extension declarations (PDA/CPI/declared accounts)"

private def jsonStr (s : String) : String :=
  "\"" ++ s ++ "\""

private def jsonBool (b : Bool) : String :=
  if b then "true" else "false"

/-- True when the extension plan carries Solana-native surface beyond portable IR. -/
def hasDeclaredSurface (ext : ProgramExtensions) : Bool :=
  !(ext.accounts.isEmpty && ext.pdas.isEmpty && ext.cpis.isEmpty &&
    ext.pdaActions.isEmpty && ext.cpiActions.isEmpty &&
    ext.accountReallocActions.isEmpty && ext.pubkeyLogActions.isEmpty &&
    ext.transferHookExtraAccountMetaListActions.isEmpty)

def materializationMode (ext : ProgramExtensions) : MaterializationMode :=
  if hasDeclaredSurface ext then .extensionDeclared else .autoPortable

def materializePortableStateAccounts (module : Module) : Array AccountEntry :=
  buildDefaultAccounts module

def materializeModuleAccounts (module : Module) (ext : ProgramExtensions) : Array AccountEntry :=
  buildModuleAccounts module ext

structure MaterializationReport where
  mode : MaterializationMode
  storageBinding : String
  stateAccountCount : Nat
  accounts : Array AccountEntry
  note : String
  deriving Repr

/-- Extra product note when portable auth materialize synthesizes authority. -/
def callerIdentityNote (module : Module) (accounts : Array AccountEntry) : String :=
  if module.capabilities.any (fun c => c == .callerSender) &&
      accounts.any (fun a => a.name == "authority" && a.signer) then
    "callerIdentity=sha256(authority@0 full pubkey)→u64-le (portable handle from full identity)"
  else if module.capabilities.any (fun c => c == .callerSender) then
    "callerIdentity=sha256(account[0] full pubkey)→u64-le (portable handle from full identity)"
  else
    ""

/-- T3.2 product notes for transfer / remote / native-value auto-fill. -/
def portableIntentNote (module : Module) (accounts : Array AccountEntry) : String :=
  let parts : Array String := #[]
  let parts :=
    if module.capabilities.any (fun c => c == .crosscallInvoke) &&
        accounts.any (fun a => a.name == "callee_program") then
      parts.push "remote=callee_program auto-filled"
    else parts
  let parts :=
    if module.capabilities.any (fun c => c == .valueNative) &&
        (match accounts[0]? with | some a => a.signer && a.writable | none => false) then
      parts.push "nativeValue=writable signer@0 (fee payer / deposit source)"
    else parts
  let parts :=
    if module.capabilities.any (fun c => c == .callerSender) &&
        accounts.any (fun a => a.signer) then
      parts.push "transfer/auth=leading signer for caller"
    else parts
  String.intercalate "; " parts.toList

def report (module : Module) (ext : ProgramExtensions := {}) : MaterializationReport :=
  let mode := materializationMode ext
  let accounts := materializeModuleAccounts module ext
  let authNote := callerIdentityNote module accounts
  let intentNote := portableIntentNote module accounts
  let note :=
    let base := mode.describe
    let withAuth := if authNote.isEmpty then base else base ++ "; " ++ authNote
    if intentNote.isEmpty then withAuth else withAuth ++ "; " ++ intentNote
  { mode := mode
    storageBinding := StorageBinding.accountData.id
    stateAccountCount := if module.state.isEmpty then 0 else 1
    accounts := accounts
    note := note }

def accountEntryJson (a : AccountEntry) : String :=
  "{" ++
  "\"name\":" ++ jsonStr a.name ++ "," ++
  "\"index\":" ++ toString a.index ++ "," ++
  "\"signer\":" ++ jsonBool a.signer ++ "," ++
  "\"writable\":" ++ jsonBool a.writable ++ "," ++
  "\"owner\":" ++ jsonStr a.owner ++
  "}"

def reportJson (r : MaterializationReport) : String :=
  "{" ++
  "\"mode\":" ++ jsonStr r.mode.id ++ "," ++
  "\"storageBinding\":" ++ jsonStr r.storageBinding ++ "," ++
  "\"stateAccountCount\":" ++ toString r.stateAccountCount ++ "," ++
  "\"note\":" ++ jsonStr r.note ++ "," ++
  "\"accounts\":[" ++
    String.intercalate "," (r.accounts.toList.map accountEntryJson) ++
  "]}"

/-- Portable modules with state (or entrypoints) use the auto-portable path. -/
def supportsAutoPortable (module : Module) : Bool :=
  !module.state.isEmpty || !module.entrypoints.isEmpty

end ProofForge.Backend.Solana.Materialize
