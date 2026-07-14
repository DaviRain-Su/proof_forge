/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

D-050: portable IR stays chain-neutral; `--target` selects storage binding.
-/
import ProofForge.IR.Portability
import ProofForge.IR.NearHost
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.NearCrosscallProbe
import ProofForge.Backend.Evm.Validate
import ProofForge.Target.Registry
import ProofForge.Target.StorageBinding

open ProofForge.IR
open ProofForge.IR.Portability
open ProofForge.IR.NearHost
open ProofForge.Target

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def counterModule : Module := ProofForge.IR.Examples.Counter.module

def main : IO Unit := do
  -- Same portable Counter IR for every primary target.
  require (isPortableCoreModule counterModule)
    "Counter module must classify as portable-core (+ neutral selector metadata)"
  require (familyOnlyViolations counterModule .evm).isEmpty
    "Counter must not carry non-EVM family-only constructors"
  require (familyOnlyViolations counterModule .solana).isEmpty
    "Counter must not carry non-Solana family-only constructors"
  require (familyOnlyViolations counterModule .wasmHost).isEmpty
    "Counter must not carry non-Wasm family-only constructors"

  -- Target (not author) chooses native storage binding.
  require (evm.storageBinding == .contractGlobal)
    "evm must bind portable state as contract-global storage"
  require (solanaSbpfAsm.storageBinding == .accountData)
    "solana-sbpf-asm must bind portable state as account data"
  require (wasmNear.storageBinding == .hostKeyValue)
    "wasm-near must bind portable state as host key/value"

  -- Same IR accepted by EVM adapter.
  match ProofForge.Backend.Evm.Validate.validateState counterModule with
  | .ok _ => pure ()
  | .error e => throw (IO.userError s!"EVM must accept portable Counter: {e.message}")

  -- Portable scalar state declares only storage.scalar — never chain-native caps.
  require (counterModule.capabilities.all fun c =>
      !(c == .storagePda))
    "portable Counter must not require Solana-only storage.pda"
  require (!(counterModule.capabilities.any fun c => c.id == "storage.resource"))
    "portable IR must not emit storage.resource"
  require (!(counterModule.capabilities.any fun c => c.id == "storage.object"))
    "portable IR must not emit storage.object"

  -- Product portable-core env = HostRuntime triad materialize only (auto-derived).
  require ContextField.userId.isPortableEnv "userId must be portable-core env"
  require ContextField.userIdHash.isPortableEnv "userIdHash must be portable-core env"
  require ContextField.checkpointId.isPortableEnv "checkpointId must be portable-core env"
  require ContextField.timestamp.isPortableEnv
    "timestamp must be portable-core (EVM + Solana Clock + NEAR)"
  require ContextField.contractId.isPortableEnv
    "contractId must be portable-core after Solana program_id lower (U1.2)"
  require (!ContextField.chainId.isPortableEnv) "chainId is EVM-only materialize"
  require (!ContextField.epochHeight.isPortableEnv) "epochHeight is NEAR-only"
  require ContextField.signer.isPortableEnv "signer must be portable across the primary triad"
  require (!ContextField.gasLeft.isPortableEnv) "gasLeft must be EVM-only"
  require (!ContextField.randomSeed.isPortableEnv) "randomSeed must not be portable-core"

  let envReadEp : Entrypoint := {
    name := "envRead", returns := .u64,
    body := #[.return (.effect (.contextRead .timestamp))]
  }
  let portableEnvReadModule : Module := { counterModule with entrypoints := #[envReadEp] }
  require (isPortableCoreModule portableEnvReadModule)
    "module reading a triad portable-core env field must stay portable-core"
  require (ValueType.isPortableIdentity ValueType.address)
    "ValueType.address must be a portable identity handle"
  require (!ValueType.isPortableIdentity ValueType.u64)
    "ValueType.u64 must not be a portable identity handle"
  require (familyOnlyViolations counterModule .solana).isEmpty
    "Counter (uses no .address) stays portable across families"

  require (evm.storageBinding.id == "contract-global")
    "evm storageBinding id must be contract-global"
  require (solanaSbpfAsm.storageBinding.id == "account-data")
    "solana-sbpf-asm storageBinding id must be account-data"
  require (wasmNear.storageBinding.id == "host-key-value")
    "wasm-near storageBinding id must be host-key-value"

  -- Slice 3 (NEAR Promise out of portable product path)
  let nearPortable := ProofForge.IR.Examples.NearCrosscallProbe.portableModule
  let nearExt := ProofForge.IR.Examples.NearCrosscallProbe.promiseExtensionModule
  require ((familyOnlyViolations nearExt .solana).size > 0)
    "NEAR promise constructors must violate Solana family"
  require ((familyOnlyViolations nearExt .evm).size > 0)
    "NEAR promise constructors must violate EVM family"
  require ((familyOnlyViolations nearExt .wasmHost).isEmpty)
    "NEAR promise constructors must be legal for wasmHost"
  require (!isPortableCoreModule nearExt)
    "promise extension module is not portable-core"
  require ((familyOnlyViolations nearPortable .solana).any fun f =>
      f.path == "module.crosscallStrings")
    "portable NEAR crosscall still flags crosscallStrings as wasmHost metadata"
  require (!(classifyModule nearPortable).any fun f =>
      match f.class_ with
      | .targetFamilyOnly _ =>
          f.detail.startsWith "target extension near.promise/" ||
            f.detail.startsWith "crosscall.continue"
      | _ => false)
    "portable NEAR module must not use promise HostOps or continuations"
  require (usesPromiseExtension nearExt) "NearHost.usesPromiseExtension on extension fixture"
  require (!usesPromiseExtension nearPortable) "NearHost: portable probe has no promise extension"
  require (isPortableNearCrosscall nearPortable) "NearHost: portable probe is portable NEAR crosscall"
  require (!isPortableNearCrosscall nearExt) "NearHost: extension module is not portable-only"

  IO.println "ir-portability: ok"
