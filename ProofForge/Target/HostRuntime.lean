/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer A — Host runtime primitive catalog

Portable contracts never name chain syscalls. They express **host effects**
(storage, log, caller, remote, …) via IR + Capability. Each target materializes
those effects as native primitives:

| Host shape | EVM | Solana | NEAR (Wasm) |
|------------|-----|--------|-------------|
| Kind | opcode / Yul builtin | sBPF syscall | `env.*` host import |
| Examples | `SLOAD`, `CALL`, `LOG*` | `sol_log_*`, `sol_invoke_signed_c` | `storage_read`, `promise_create` |

This module is the **single inventory** of those mappings for the primary
triad. It does not replace backend lowering — it documents and gates “what
native symbol stands for this portable effect”.

**HostEnv** (below) is the de-EVM environment vocabulary: three buckets
(general / approximate / chainOnly) with `materializeEnv` honesty. IR
`ContextField` maps through `toHostEnv`.

See `docs/host-runtime.md` · `docs/protocols-layer.md` (Layer A) ·
`docs/zh/chain-agnostic-gap-analysis.md` §(B).
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Target.Capability

namespace ProofForge.Target.HostRuntime

open ProofForge.Target

/-- How a host exposes a runtime primitive. -/
inductive NativeKind where
  /-- EVM opcode or Yul builtin (`SLOAD`, `keccak256`, `call`). -/
  | opcode
  /-- Solana sBPF syscall (`sol_log_64_`, `sol_invoke_signed_c`). -/
  | syscall
  /-- Wasm host import (`env.storage_read`, `env.promise_create`). -/
  | hostImport
  deriving BEq, DecidableEq, Repr

def NativeKind.id : NativeKind → String
  | .opcode => "opcode"
  | .syscall => "syscall"
  | .hostImport => "host_import"

/-- One native binding of a portable host effect. -/
structure NativeBinding where
  /-- Target id (`evm`, `solana-sbpf-asm`, `wasm-near`, …). -/
  targetId : String
  kind : NativeKind
  /-- Canonical native symbol (opcode name, syscall name, or `env.foo`). -/
  symbol : String
  /-- Optional note (partial, spike, family-only). -/
  note? : Option String := none
  deriving BEq, Repr

/-- Portable host effects that backends must materialize (Layer A).

These are **finer** than Capability ids when one capability fans out to
several native ops (e.g. crypto.hash → keccak vs sha256 vs blake3). -/
inductive HostEffect where
  | storageRead
  | storageWrite
  | logEmit
  | caller
  | valueNative
  | envBlock
  | cryptoKeccak
  | cryptoSha256
  | remoteInvoke
  | remoteInvokeSigned
  | assertFail
  | memoryCopy
  | memorySet
  | returnDataGet
  | returnDataSet
  | computeRemaining
  | pda
  | pdaFind
  deriving BEq, DecidableEq, Repr

def HostEffect.id : HostEffect → String
  | .storageRead => "host.storage.read"
  | .storageWrite => "host.storage.write"
  | .logEmit => "host.log.emit"
  | .caller => "host.caller"
  | .valueNative => "host.value.native"
  | .envBlock => "host.env.block"
  | .cryptoKeccak => "host.crypto.keccak"
  | .cryptoSha256 => "host.crypto.sha256"
  | .remoteInvoke => "host.remote.invoke"
  | .remoteInvokeSigned => "host.remote.invoke_signed"
  | .assertFail => "host.assert.fail"
  | .memoryCopy => "host.memory.copy"
  | .memorySet => "host.memory.set"
  | .returnDataGet => "host.return_data.get"
  | .returnDataSet => "host.return_data.set"
  | .computeRemaining => "host.compute.remaining"
  | .pda => "host.pda.create"
  | .pdaFind => "host.pda.find"

instance : ToString HostEffect where
  toString e := e.id

/-- Map a host effect to the Capability that gates it (when one exists). -/
def HostEffect.capability? : HostEffect → Option Capability
  | .storageRead | .storageWrite => some .storageScalar
  | .logEmit => some .eventsEmit
  | .caller => some .callerSender
  | .valueNative => some .valueNative
  | .envBlock => some .envBlock
  | .cryptoKeccak | .cryptoSha256 => some .cryptoHash
  | .remoteInvoke => some .crosscallInvoke
  | .remoteInvokeSigned => some .crosscallCpi
  | .assertFail => some .assertions
  | .memoryCopy | .memorySet => some .runtimeMemory
  | .returnDataGet | .returnDataSet => some .runtimeReturnData
  | .computeRemaining => some .runtimeComputeUnits
  | .pda | .pdaFind => some .storagePda

/-- Primary-triad (EVM · Solana · NEAR) native bindings. -/
def HostEffect.primaryTriadBindings : HostEffect → Array NativeBinding
  | .storageRead => #[
      { targetId := "evm", kind := .opcode, symbol := "sload" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "account_data_load",
        note? := some "via input account data pointers (not a single sol_* syscall)" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "env.storage_read" }
    ]
  | .storageWrite => #[
      { targetId := "evm", kind := .opcode, symbol := "sstore" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "account_data_store",
        note? := some "via input account data pointers" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "env.storage_write" }
    ]
  | .logEmit => #[
      { targetId := "evm", kind := .opcode, symbol := "log0..log4" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "sol_log_64_" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "env.log_utf8" }
    ]
  | .caller => #[
      { targetId := "evm", kind := .opcode, symbol := "caller" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "tx_signer_account",
        note? := some "from instruction accounts (signer flag)" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "env.signer_account_id" }
    ]
  | .valueNative => #[
      { targetId := "evm", kind := .opcode, symbol := "callvalue" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "lamports_field",
        note? := some "account lamports; no msg.value equivalent" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "env.attached_deposit" }
    ]
  | .envBlock => #[
      { targetId := "evm", kind := .opcode, symbol := "number/timestamp" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "sol_get_clock_sysvar" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "env.block_timestamp" }
    ]
  | .cryptoKeccak => #[
      { targetId := "evm", kind := .opcode, symbol := "keccak256" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "sol_keccak256" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "env.keccak256",
        note? := some "when enabled by capability surface" }
    ]
  | .cryptoSha256 => #[
      { targetId := "evm", kind := .opcode, symbol := "sha256_precompile",
        note? := some "precompile 0x02" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "sol_sha256" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "env.sha256" }
    ]
  | .remoteInvoke => #[
      { targetId := "evm", kind := .opcode, symbol := "call" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "sol_invoke_signed_c",
        note? := some "portable peer CPI; seeds empty when unsigned" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "env.promise_create" }
    ]
  | .remoteInvokeSigned => #[
      { targetId := "evm", kind := .opcode, symbol := "call",
        note? := some "no PDA seeds; EVM uses msg.sender authority" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "sol_invoke_signed_c" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "env.promise_create",
        note? := some "NEAR has no PDA seed model; account id auth" }
    ]
  | .assertFail => #[
      { targetId := "evm", kind := .opcode, symbol := "revert" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "sol_panic_" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "env.panic",
        note? := some "or trap via unreachable" }
    ]
  | .memoryCopy => #[
      { targetId := "evm", kind := .opcode, symbol := "mcopy/mstore",
        note? := some "memory model in Yul" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "sol_memcpy_" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "memory.intrinsic",
        note? := some "Wasm memory ops; not env import" }
    ]
  | .memorySet => #[
      { targetId := "evm", kind := .opcode, symbol := "mstore" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "sol_memset_" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "memory.intrinsic" }
    ]
  | .returnDataGet => #[
      { targetId := "evm", kind := .opcode, symbol := "returndatacopy" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "sol_get_return_data" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "env.promise_result" }
    ]
  | .returnDataSet => #[
      { targetId := "evm", kind := .opcode, symbol := "return" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "sol_set_return_data" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "env.value_return" }
    ]
  | .computeRemaining => #[
      { targetId := "evm", kind := .opcode, symbol := "gas" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "sol_remaining_compute_units" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "env.prepaid_gas",
        note? := some "when enabled" }
    ]
  | .pda => #[
      { targetId := "evm", kind := .opcode, symbol := "create2",
        note? := some "address derivation only; not PDA" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "sol_create_program_address" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "n/a",
        note? := some "no PDA model on NEAR" }
    ]
  | .pdaFind => #[
      { targetId := "evm", kind := .opcode, symbol := "n/a" },
      { targetId := "solana-sbpf-asm", kind := .syscall, symbol := "sol_try_find_program_address" },
      { targetId := "wasm-near", kind := .hostImport, symbol := "n/a" }
    ]

/-- Already-partial Wasm host adapters (Soroban · CosmWasm). Explicit `n/a` where
the host has no equivalent (PDA, compute budget, etc.). -/
def HostEffect.adapterBindings : HostEffect → Array NativeBinding
  | .storageRead => #[
      { targetId := "wasm-stellar-soroban", kind := .hostImport, symbol := "env._get" },
      { targetId := "wasm-cosmwasm", kind := .hostImport, symbol := "env.db_read" }
    ]
  | .storageWrite => #[
      { targetId := "wasm-stellar-soroban", kind := .hostImport, symbol := "env._put" },
      { targetId := "wasm-cosmwasm", kind := .hostImport, symbol := "env.db_write" }
    ]
  | .logEmit => #[
      { targetId := "wasm-stellar-soroban", kind := .hostImport, symbol := "env.log_from_slice" },
      { targetId := "wasm-cosmwasm", kind := .hostImport, symbol := "n/a",
        note? := some "events via response; no env.log host import in bridge yet" }
    ]
  | .caller => #[
      { targetId := "wasm-stellar-soroban", kind := .hostImport, symbol := "env.require_auth_for_args",
        note? := some "auth surface; not a pure caller id import" },
      { targetId := "wasm-cosmwasm", kind := .hostImport, symbol := "n/a",
        note? := some "msg.sender via CosmWasm message envelope (not env import)" }
    ]
  | .valueNative => #[
      { targetId := "wasm-stellar-soroban", kind := .hostImport, symbol := "n/a",
        note? := some "no attached_deposit equivalent on Soroban bridge" },
      { targetId := "wasm-cosmwasm", kind := .hostImport, symbol := "n/a",
        note? := some "funds via BankMsg / info.funds (not env import)" }
    ]
  | .envBlock => #[
      { targetId := "wasm-stellar-soroban", kind := .hostImport, symbol := "n/a" },
      { targetId := "wasm-cosmwasm", kind := .hostImport, symbol := "n/a",
        note? := some "env.block via CosmWasm Env (not HostBridge list)" }
    ]
  | .cryptoKeccak | .cryptoSha256 => #[
      { targetId := "wasm-stellar-soroban", kind := .hostImport, symbol := "n/a" },
      { targetId := "wasm-cosmwasm", kind := .hostImport, symbol := "n/a" }
    ]
  | .remoteInvoke | .remoteInvokeSigned => #[
      { targetId := "wasm-stellar-soroban", kind := .hostImport, symbol := "env.invoke_contract" },
      { targetId := "wasm-cosmwasm", kind := .hostImport, symbol := "env.execute_msg",
        note? := some "spike WasmMsg-shaped execute; not full CosmWasm Querier" }
    ]
  | .assertFail => #[
      -- EmitWat lowers assert-fail as Wasm `unreachable` (same as NEAR no-ErrorRef path).
      { targetId := "wasm-stellar-soroban", kind := .hostImport, symbol := "unreachable",
        note? := some "Wasm trap; EmitWat assert without ErrorRef" },
      { targetId := "wasm-cosmwasm", kind := .hostImport, symbol := "unreachable",
        note? := some "Wasm trap / ContractError return path" }
    ]
  | .memoryCopy | .memorySet => #[
      { targetId := "wasm-stellar-soroban", kind := .hostImport, symbol := "memory.intrinsic" },
      { targetId := "wasm-cosmwasm", kind := .hostImport, symbol := "memory.intrinsic" }
    ]
  | .returnDataGet => #[
      { targetId := "wasm-stellar-soroban", kind := .hostImport, symbol := "n/a",
        note? := some "invoke_contract result handle" },
      { targetId := "wasm-cosmwasm", kind := .hostImport, symbol := "n/a" }
    ]
  | .returnDataSet => #[
      { targetId := "wasm-stellar-soroban", kind := .hostImport, symbol := "n/a" },
      { targetId := "wasm-cosmwasm", kind := .hostImport, symbol := "n/a" }
    ]
  | .computeRemaining => #[
      { targetId := "wasm-stellar-soroban", kind := .hostImport, symbol := "n/a" },
      { targetId := "wasm-cosmwasm", kind := .hostImport, symbol := "n/a" }
    ]
  | .pda | .pdaFind => #[
      { targetId := "wasm-stellar-soroban", kind := .hostImport, symbol := "n/a" },
      { targetId := "wasm-cosmwasm", kind := .hostImport, symbol := "n/a" }
    ]

/-- Full catalog: primary triad + Wasm host adapters. -/
def HostEffect.bindings (e : HostEffect) : Array NativeBinding :=
  e.primaryTriadBindings ++ e.adapterBindings

/-- All catalogued portable host effects. -/
def allEffects : Array HostEffect := #[
  .storageRead, .storageWrite, .logEmit, .caller, .valueNative, .envBlock,
  .cryptoKeccak, .cryptoSha256, .remoteInvoke, .remoteInvokeSigned, .assertFail,
  .memoryCopy, .memorySet, .returnDataGet, .returnDataSet, .computeRemaining,
  .pda, .pdaFind
]

def primaryTargetIds : Array String := #["evm", "solana-sbpf-asm", "wasm-near"]

/-- Wasm host adapters already partially lowered (not full product triad). -/
def adapterTargetIds : Array String := #["wasm-stellar-soroban", "wasm-cosmwasm"]

/-- All targets with HostRuntime rows. -/
def catalogTargetIds : Array String := primaryTargetIds ++ adapterTargetIds

/-- Bindings for one target (may be empty if effect is n/a). -/
def bindingsForTarget (effect : HostEffect) (targetId : String) : Array NativeBinding :=
  effect.bindings.filter (fun b => b.targetId == targetId)

/-- Primary binding row for a target (if any). -/
def binding? (effect : HostEffect) (targetId : String) : Option NativeBinding :=
  (bindingsForTarget effect targetId)[0]?

/-- Comment token for lowerers: links portable effect id to native symbol.
Emitted in assembly/WAT comments so smokes can assert catalog linkage. -/
def catalogRefComment (effect : HostEffect) (targetId : String) : String :=
  match binding? effect targetId with
  | some b =>
      s!"HostRuntime {effect.id} → {NativeKind.id b.kind}:{b.symbol}"
  | none =>
      s!"HostRuntime {effect.id} → (no binding for {targetId})"

/-- True when the binding is explicitly absent / not applicable. -/
def isNaSymbol (symbol : String) : Bool :=
  symbol == "n/a" || symbol == "N/A"

/-- True if this target has at least one real binding (not symbol `n/a`). -/
def supports (effect : HostEffect) (targetId : String) : Bool :=
  (bindingsForTarget effect targetId).any (fun b => !isNaSymbol b.symbol)

/-- Host effects that gate on a given Capability (inverse of `capability?`). -/
def effectsForCapability (cap : Capability) : Array HostEffect :=
  allEffects.filter (fun e => e.capability? == some cap)

/-- First HostEffect required by `cap` that this target does not support. -/
def firstUnsupportedEffect? (cap : Capability) (targetId : String) : Option HostEffect :=
  (effectsForCapability cap).find? (fun e => !supports e targetId)

/-- Capability is host-honest on `targetId` when every linked HostEffect has a
real native binding (not `n/a`). Capabilities with no HostEffect mapping are
treated as honest (gated only by the capability registry). -/
def capabilityHostHonest (cap : Capability) (targetId : String) : Bool :=
  (firstUnsupportedEffect? cap targetId).isNone

/-- Diagnostic when a capability is requested but HostRuntime has n/a. -/
def honestyError (targetId : String) (cap : Capability) (effect : HostEffect) : String :=
  let sym :=
    match binding? effect targetId with
    | some b => b.symbol
    | none => "(missing row)"
  s!"HostRuntime: target `{targetId}` cannot use capability `{cap.id}`: \
host effect `{effect.id}` has no native binding (symbol `{sym}`)"

/-- Targets with HostEffect catalog rows (primary triad + Wasm adapters).
Other registry targets (psy/aleo/move/…) use profile capabilities only. -/
def isHostRuntimeTarget (targetId : String) : Bool :=
  primaryTargetIds.contains targetId || adapterTargetIds.contains targetId

/-- Reject when any requested capability maps to an n/a HostEffect on this target.
Only applies to `isHostRuntimeTarget` hosts; Psy/Aleo/Move skip this gate so
backend-specific diagnostics still fire first. -/
def requireHostRuntimeHonesty (targetId : String) (capabilities : Array Capability) :
    Except String Unit :=
  if !isHostRuntimeTarget targetId then
    .ok ()
  else
    capabilities.foldlM
      (fun _ cap =>
        match firstUnsupportedEffect? cap targetId with
        | some effect => .error (honestyError targetId cap effect)
        | none => .ok ())
      ()

/-- Count supported effects on a target (for smoke metrics). -/
def supportedCount (targetId : String) : Nat :=
  allEffects.foldl (fun n e => if supports e targetId then n + 1 else n) 0

/-- Catalog id for docs / diagnostics. -/
def catalogId : String := "host.runtime"

/-! ### HostEnv — chain-agnostic environment vocabulary (gap-analysis step 1)

Authors should think in portable **HostEnv** terms, not EVM opcodes
(`gasprice`, `coinbase`, `prevrandao`, …). Three buckets:

* **general** — every primary-triad chain has a direct native analogue
* **approximate** — similar semantics, different name/units; materialize with notes
* **chainOnly** — honest reject (or target opt-in) when the host has no concept

See `docs/host-runtime.md` § HostEnv and
`docs/zh/chain-agnostic-gap-analysis.md` §(B).
IR `ContextField` maps onto this vocabulary via `ContextField.toHostEnv`.
-/

/-- Portability bucket for a host-environment term. -/
inductive HostEnvBucket where
  | general
  | approximate
  | chainOnly
  deriving BEq, DecidableEq, Repr

def HostEnvBucket.id : HostEnvBucket → String
  | .general => "general"
  | .approximate => "approximate"
  | .chainOnly => "chainOnly"

instance : ToString HostEnvBucket where
  toString b := b.id

/-- Portable host-environment vocabulary (de-EVM'd).

General and approximate terms are chain-neutral names. Chain-only terms keep
host-specific names on purpose so materialize can reject honestly. -/
inductive HostEnv where
  /-- Wall-clock / block time (`block.timestamp` · Clock.unix_timestamp · block_timestamp). -/
  | blockTime
  /-- Block / slot / height identity (`block.number` · Clock.slot · block_index). -/
  | blockHeight
  /-- Chain id. -/
  | chainId
  /-- Immediate caller / signer / predecessor (`msg.sender` · signer · predecessor). -/
  | caller
  /-- This contract's address / program id / account id. -/
  | selfAddress
  /-- Attached native value (`msg.value` · lamports · attached_deposit). -/
  | attachedValue
  /-- Epoch / epoch height (units differ; approximate). -/
  | epoch
  /-- Remaining compute budget (`gasleft` · remaining CU · prepaid_gas). -/
  | gasOrComputeBudgetLeft
  /-- Historical block / slot hash (approximate; availability varies). -/
  | blockHash
  /-- Host randomness (`prevrandao` · slot hashes · random_seed) — **untrusted**. -/
  | randomness
  /-- EVM `gasprice` only. -/
  | gasPrice
  /-- EVM `basefee` only. -/
  | baseFee
  /-- EVM `tx.origin` only. -/
  | txOrigin
  /-- EVM `coinbase` / fee recipient only. -/
  | coinbase
  /-- Solana rent / rent-exempt minimum (no EVM/NEAR analogue). -/
  | solanaRent
  /-- NEAR predecessor when distinct from signer (async receipt model). -/
  | nearPredecessor
  /-- NEAR prepaid_gas (gas prepaid for the call; no EVM/Solana analogue). -/
  | nearPrepaidGas
  /-- NEAR used_gas (gas already consumed in the call; no EVM/Solana analogue). -/
  | nearUsedGas
  deriving BEq, DecidableEq, Repr

def HostEnv.id : HostEnv → String
  | .blockTime => "env.blockTime"
  | .blockHeight => "env.blockHeight"
  | .chainId => "env.chainId"
  | .caller => "env.caller"
  | .selfAddress => "env.selfAddress"
  | .attachedValue => "env.attachedValue"
  | .epoch => "env.epoch"
  | .gasOrComputeBudgetLeft => "env.gasOrComputeBudgetLeft"
  | .blockHash => "env.blockHash"
  | .randomness => "env.randomness"
  | .gasPrice => "env.gasPrice"
  | .baseFee => "env.baseFee"
  | .txOrigin => "env.txOrigin"
  | .coinbase => "env.coinbase"
  | .solanaRent => "env.solanaRent"
  | .nearPredecessor => "env.nearPredecessor"
  | .nearPrepaidGas => "env.nearPrepaidGas"
  | .nearUsedGas => "env.nearUsedGas"

instance : ToString HostEnv where
  toString e := e.id

/-- Bucket classification (gap-analysis three buckets). -/
def HostEnv.bucket : HostEnv → HostEnvBucket
  | .blockTime | .blockHeight | .chainId | .caller | .selfAddress | .attachedValue =>
      .general
  | .epoch | .gasOrComputeBudgetLeft | .blockHash | .randomness =>
      .approximate
  | .gasPrice | .baseFee | .txOrigin | .coinbase | .solanaRent | .nearPredecessor
  | .nearPrepaidGas | .nearUsedGas =>
      .chainOnly

/-- Full HostEnv catalog (for tests / enumeration). -/
def allHostEnvs : Array HostEnv := #[
  .blockTime, .blockHeight, .chainId, .caller, .selfAddress, .attachedValue,
  .epoch, .gasOrComputeBudgetLeft, .blockHash, .randomness,
  .gasPrice, .baseFee, .txOrigin, .coinbase, .solanaRent, .nearPredecessor,
  .nearPrepaidGas, .nearUsedGas
]

/-- Successful materialization of a HostEnv term on a target. -/
structure HostEnvMaterialization where
  /-- Native binding row (kind + symbol). -/
  binding : NativeBinding
  /-- Optional semantic note (units, untrusted randomness, weak analogue). -/
  semanticsNote? : Option String := none
  deriving Repr, BEq

/-- Linked HostEffect when one exists (for catalog cross-ref). -/
def HostEnv.hostEffect? : HostEnv → Option HostEffect
  | .caller => some .caller
  | .attachedValue => some .valueNative
  | .blockTime | .blockHeight | .chainId | .epoch => some .envBlock
  | .gasOrComputeBudgetLeft => some .computeRemaining
  | .randomness | .blockHash => some .envBlock
  | .selfAddress | .gasPrice | .baseFee | .txOrigin | .coinbase
  | .solanaRent | .nearPredecessor | .nearPrepaidGas | .nearUsedGas => none

/-- Diagnostic when a HostEnv term cannot materialize on `targetId`. -/
def hostEnvReject (targetId : String) (env : HostEnv) (reason : String) : String :=
  s!"HostEnv: target `{targetId}` cannot materialize `{env.id}` \
({HostEnvBucket.id env.bucket}): {reason}"

/-- Materialize a portable HostEnv term for `targetId`, or honest-reject.

**Honesty rule:** `.ok` only when this target already has a real lower / host
path for the term (or a documented native symbol used by that path). Never
alias another field (e.g. `chainId` ↛ `block_index`) and never invent syscalls
the lowerer does not emit. General-bucket membership is **portable intent**;
triad coverage grows as lowers land — until then, reject.

Primary triad matrix (context / nativeValue paths as of HostEnv step U1.4):
* `blockTime` — triad (EVM `timestamp` · Solana `Clock.unix_timestamp` · NEAR `block_timestamp`)
* `blockHeight` — triad (EVM `number` · Solana `Clock.slot` · NEAR `block_index`)
* `chainId` — EVM only (Solana/NEAR plan reject `contextRead.chainId`)
* `caller` / `attachedValue` / `selfAddress` — triad
* `gasOrComputeBudgetLeft` — EVM `gas` + Solana `sol_remaining_compute_units`; NEAR permanent reject
* `epoch` — NEAR only (`epoch_height`); EVM/Solana reject
* `blockHash` — EVM only; Solana/NEAR reject
* `randomness` — EVM `prevrandao` + NEAR `random_seed`; Solana reject
-/
def materializeEnv (targetId : String) (env : HostEnv) :
    Except String HostEnvMaterialization :=
  let mk (kind : NativeKind) (symbol : String) (note? : Option String := none)
      (sem? : Option String := none) : HostEnvMaterialization :=
    { binding := { targetId := targetId, kind := kind, symbol := symbol, note? := note? }
      semanticsNote? := sem? }
  match env, targetId with
  -- ── general ──────────────────────────────────────────────────────────
  | .blockTime, "evm" =>
      .ok (mk .opcode "timestamp" none (some "block.timestamp (seconds)"))
  | .blockTime, "wasm-near" =>
      .ok (mk .hostImport "env.block_timestamp" none (some "nanoseconds; divide for seconds"))
  | .blockTime, "solana-sbpf-asm" =>
      .ok (mk .syscall "sol_get_clock_sysvar"
        (some "Clock.unix_timestamp via contextRead.timestamp")
        (some "i64 seconds from Clock; portable u64 (NEAR is nanoseconds)"))
  | .blockHeight, "evm" =>
      .ok (mk .opcode "number" none (some "block.number"))
  | .blockHeight, "solana-sbpf-asm" =>
      .ok (mk .syscall "sol_get_clock_sysvar" (some "Clock.slot via contextRead.checkpointId")
        (some "slot, not EVM block number"))
  | .blockHeight, "wasm-near" =>
      .ok (mk .hostImport "env.block_index" none none)
  | .chainId, "evm" =>
      .ok (mk .opcode "chainid" none none)
  | .chainId, "solana-sbpf-asm" =>
      .error (hostEnvReject targetId env
        "no chainId context lower; Solana has no EIP-155 chainid (cluster is off-chain)")
  | .chainId, "wasm-near" =>
      .error (hostEnvReject targetId env
        "wasm-near plan rejects contextRead.chainId; no native chainId host import \
(must not alias block-height host reads)")
  | .caller, "evm" =>
      .ok (mk .opcode "caller" none (some "msg.sender 20-byte"))
  | .caller, "solana-sbpf-asm" =>
      .ok (mk .syscall "tx_signer_account" (some "signer account key via contextRead.userId")
        (some "32-byte pubkey; first signer"))
  | .caller, "wasm-near" =>
      .ok (mk .hostImport "env.predecessor_account_id" none
        (some "predecessor (not always signer under async receipts)"))
  | .selfAddress, "evm" =>
      .ok (mk .opcode "address" none none)
  | .selfAddress, "wasm-near" =>
      .ok (mk .hostImport "env.current_account_id" none none)
  | .selfAddress, "solana-sbpf-asm" =>
      .ok (mk .syscall "program_id"
        (some "contextRead.contractId → sha256(program_id) limb0")
        (some "32-byte program id; portable u64 handle matches OwnableHash limb0"))
  | .attachedValue, "evm" =>
      .ok (mk .opcode "callvalue" none none)
  | .attachedValue, "solana-sbpf-asm" =>
      .ok (mk .syscall "lamports_field" (some "nativeValue → account[0] lamports")
        (some "weak analogue: account lamports, not msg.value"))
  | .attachedValue, "wasm-near" =>
      .ok (mk .hostImport "env.attached_deposit" none none)
  -- ── approximate ──────────────────────────────────────────────────────
  | .epoch, "wasm-near" =>
      .ok (mk .hostImport "env.epoch_height" none none)
  | .epoch, "evm" =>
      .error (hostEnvReject targetId env
        "EVM has no epoch-height opcode; contextRead.epochHeight rejects")
  | .epoch, "solana-sbpf-asm" =>
      .error (hostEnvReject targetId env
        "no contextRead.epochHeight lower; Clock.epoch not wired")
  | .gasOrComputeBudgetLeft, "evm" =>
      .ok (mk .opcode "gas" none (some "gasleft()"))
  | .gasOrComputeBudgetLeft, "solana-sbpf-asm" =>
      .ok (mk .syscall "sol_remaining_compute_units"
        (some "contextRead.gasLeft → remaining CU as portable u64")
        (some "approximate: CU not EVM gas; extension compute_units path shares this syscall"))
  | .gasOrComputeBudgetLeft, "wasm-near" =>
      .error (hostEnvReject targetId env
        "permanent reject: prepaid_gas not wired as HostEnv context lower \
(use offline fuel budgets / host economics outside portable product path)")
  | .blockHash, "evm" =>
      .ok (mk .opcode "blockhash" none (some "only last 256 blocks"))
  | .blockHash, "solana-sbpf-asm" =>
      .error (hostEnvReject targetId env
        "no contextRead.blockHash lower; SlotHashes sysvar not wired as HostEnv")
  | .blockHash, "wasm-near" =>
      .error (hostEnvReject targetId env
        "wasm-near plan rejects contextRead.blockHash; use env.randomness for random_seed")
  | .randomness, "evm" =>
      .ok (mk .opcode "prevrandao" none
        (some "UNTRUSTED: prevrandao / difficulty legacy; not VRF"))
  | .randomness, "wasm-near" =>
      .ok (mk .hostImport "env.random_seed" none
        (some "UNTRUSTED: host random_seed is not VRF"))
  | .randomness, "solana-sbpf-asm" =>
      .error (hostEnvReject targetId env
        "no contextRead.randomness lower; SlotHashes not wired as HostEnv")
  -- ── chainOnly ────────────────────────────────────────────────────────
  | .gasPrice, "evm" =>
      .ok (mk .opcode "gasprice" none none)
  | .gasPrice, _ =>
      .error (hostEnvReject targetId env "EVM-only gasprice; no portable analogue")
  | .baseFee, "evm" =>
      .ok (mk .opcode "basefee" none none)
  | .baseFee, _ =>
      .error (hostEnvReject targetId env "EVM-only basefee (EIP-1559)")
  | .txOrigin, "evm" =>
      .ok (mk .opcode "origin" none none)
  | .txOrigin, "solana-sbpf-asm" =>
      -- Backend already lowers ContextField.origin as first-signer pubkey digest
      -- (same path as userId). Not EVM tx.origin semantics — document the alias.
      .ok (mk .syscall "tx_signer_account" (some "alias of first signer / userId")
        (some "NOT EVM tx.origin; same as env.caller on Solana"))
  | .txOrigin, _ =>
      .error (hostEnvReject targetId env "EVM-only tx.origin; use env.caller")
  | .coinbase, "evm" =>
      .ok (mk .opcode "coinbase" none none)
  | .coinbase, _ =>
      .error (hostEnvReject targetId env "EVM-only coinbase / fee recipient")
  | .solanaRent, "solana-sbpf-asm" =>
      .ok (mk .syscall "sol_get_rent_sysvar" none
        (some "syscall exists; not a portable ContextField"))
  | .solanaRent, _ =>
      .error (hostEnvReject targetId env "Solana-only rent sysvar")
  | .nearPredecessor, "wasm-near" =>
      .ok (mk .hostImport "env.predecessor_account_id" none
        (some "distinct from signer under async; portable caller prefers predecessor"))
  | .nearPredecessor, _ =>
      .error (hostEnvReject targetId env
        "NEAR-only predecessor≠signer distinction; use env.caller")
  | .nearPrepaidGas, "wasm-near" =>
      .ok (mk .hostImport "prepaid_gas" none
        (some "NEAR prepaid_gas(): gas attached to the call"))
  | .nearPrepaidGas, _ =>
      .error (hostEnvReject targetId env
        "NEAR-only prepaid_gas; no portable analogue")
  | .nearUsedGas, "wasm-near" =>
      .ok (mk .hostImport "used_gas" none
        (some "NEAR used_gas(): gas consumed so far in the call"))
  | .nearUsedGas, _ =>
      .error (hostEnvReject targetId env
        "NEAR-only used_gas; no portable analogue")
  -- unknown target
  | _, _ =>
      .error (hostEnvReject targetId env s!"no HostEnv row for target `{targetId}`")

/-- True when `materializeEnv` succeeds (real native symbol, not reject). -/
def supportsHostEnv (targetId : String) (env : HostEnv) : Bool :=
  match materializeEnv targetId env with
  | .ok _ => true
  | .error _ => false

/-- Convenience: materialize or return the reject string. -/
def requireHostEnv (targetId : String) (env : HostEnv) :
    Except String HostEnvMaterialization :=
  materializeEnv targetId env

end ProofForge.Target.HostRuntime
