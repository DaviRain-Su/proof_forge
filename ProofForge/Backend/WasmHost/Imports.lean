/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmHost.Plan
import ProofForge.Target.HostBridge

namespace ProofForge.Backend.WasmHost.Imports

open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.Plan

/-! Host-import construction and ModulePlan-driven import selection for
the Wasm-NEAR EmitWat backend. -/

def hostImport (name : String) (params results : Array ValType) : Import :=
  { module_ := "env", name := name, funcName := name, type := { params := params, results := results } }

def valTypeOfString : String → ValType
  | "i32" => .i32
  | "i64" => .i64
  | _ => .i32

def hostFunctionImport (hf : ProofForge.Target.HostFunction) : Import :=
  hostImport hf.name (hf.params.map valTypeOfString) (hf.results.map valTypeOfString)

def dedupeImports (imports : Array Import) : Array Import :=
  imports.foldl (fun acc import_ =>
    if acc.any (fun existing => existing.module_ == import_.module_ && existing.name == import_.name) then
      acc
    else
      acc.push import_) #[]

def bridgeBaseImports (bridge : ProofForge.Target.HostBridge) : Array Import :=
  bridge.hostFunctions.map hostFunctionImport

def nearImports : Array Import := bridgeBaseImports .near

def storageHasKeyImport : Import :=
  hostImport "storage_has_key" #[.i64, .i64] #[.i64]

def sha256Import : Import := hostImport "sha256" #[.i64, .i64, .i64] #[]
def logUtf8Import : Import := hostImport "log_utf8" #[.i64, .i64] #[]
def inputImport : Import := hostImport "input" #[.i64] #[]
def panicImport : Import := hostImport "panic" #[.i64, .i64] #[]
def predecessorImport : Import := hostImport "predecessor_account_id" #[.i64] #[]
def currentAcctImport : Import := hostImport "current_account_id" #[.i64] #[]
def signerImport : Import := hostImport "signer_account_id" #[.i64] #[]
/-- NEAR sys: `attached_deposit(balance_ptr)` writes little-endian u128 (16 bytes)
at `balance_ptr` (see `near-sys`). Not a zero-arg i64 return. -/
def depositImport : Import := hostImport "attached_deposit" #[.i64] #[]
def registerLenImport : Import := hostImport "register_len" #[.i64] #[.i64]
def blockHeightImport : Import := hostImport "block_index" #[] #[.i64]
def epochHeightImport : Import := hostImport "epoch_height" #[] #[.i64]
def randomSeedImport : Import := hostImport "random_seed" #[.i64] #[]
def prepaidGasImport : Import := hostImport "prepaid_gas" #[] #[.i64]
def usedGasImport : Import := hostImport "used_gas" #[] #[.i64]

def allocImportName : String := "pf_alloc"
def deallocImportName : String := "pf_dealloc"

def allocImport : Import :=
  hostImport allocImportName #[.i64] #[.i32]

def deallocImport : Import :=
  hostImport deallocImportName #[.i32, .i64] #[]

def modulePlanUsesSha256 (plan : ModulePlan) : Bool :=
  plan.usesHashPreimage || plan.usesHashTwoToOne ||
    plan.contextOps.contains .userId || plan.contextOps.contains .userIdHash ||
    plan.contextOps.contains .contractId || plan.contextOps.contains .origin

def nearImportsForModulePlan (plan : ModulePlan) : Array Import :=
  nearImports.filter fun import_ =>
    match import_.name with
    | "attached_deposit" => plan.usesNativeValue
    | "storage_read" => plan.usesStorageRead
    | "storage_write" => plan.usesStorageWrite
    | "storage_remove" => plan.usesStorageWrite
    | "value_return" => !plan.returnTypes.isEmpty
    | "promise_create" => plan.usesPromiseCreate
    | "promise_then" => plan.usesPromiseThen
    | "promise_results_count" | "promise_result" => plan.usesPromiseResults
    | "promise_return" => plan.usesPromiseReturn
    | "log_utf8" => plan.usesEventApi
    | "signer_account_id" => plan.contextOps.contains .origin
    | "block_timestamp" => plan.contextOps.contains .timestamp
    | "epoch_height" => plan.contextOps.contains .epochHeight
    | "random_seed" => plan.contextOps.contains .randomSeed
    | "prepaid_gas" => plan.contextOps.contains .prepaidGas
    | "used_gas" => plan.contextOps.contains .usedGas
    | _ => true

def ctxImportsForModulePlan (plan : ModulePlan) : Array Import :=
  (if plan.contextOps.contains .userId || plan.contextOps.contains .userIdHash then #[predecessorImport] else #[]) ++
    (if plan.contextOps.contains .contractId then #[currentAcctImport] else #[]) ++
    (if plan.contextOps.contains .userId || plan.contextOps.contains .userIdHash ||
        plan.contextOps.contains .contractId || plan.contextOps.contains .origin then #[registerLenImport] else #[]) ++
    (if plan.contextOps.contains .checkpointId then #[blockHeightImport] else #[]) ++
    (if plan.contextOps.contains .prepaidGas then #[prepaidGasImport] else #[]) ++
    (if plan.contextOps.contains .usedGas then #[usedGasImport] else #[])

def promiseCtxImportsForModulePlan (plan : ModulePlan) : Array Import :=
  if !plan.usesPromiseReceiverAccount then
    #[]
  else
    (if plan.contextOps.contains .contractId then #[] else #[currentAcctImport]) ++
      (if plan.contextOps.contains .userId || plan.contextOps.contains .contractId || plan.contextOps.contains .origin then
        #[] else #[registerLenImport])

def promiseResultImportsForModulePlan (plan : ModulePlan) : Array Import :=
  if !plan.usesPromiseResultU64 then
    #[]
  else if plan.contextOps.contains .userId || plan.contextOps.contains .contractId ||
      plan.contextOps.contains .origin || plan.usesPromiseReceiverAccount then
    #[]
  else
    #[registerLenImport]

/-- Offline host-provided allocators forward heap helpers to `pf_alloc` /
    `pf_dealloc`. Only emit the imports actually referenced by the planned arr
    heap surface. -/
def hostAllocatorImportsForModulePlan (plan : ModulePlan) (cfg : ProofForge.IR.AllocatorConfig) : Array Import :=
  if !cfg.requiresHost then
    #[]
  else
    (if plan.usesArrAlloc then #[allocImport] else #[]) ++
      (if plan.usesArrDealloc then #[deallocImport] else #[])

/-- Host import for portable `crosscall.invoke` on the Soroban bridge.
Signature matches `HostBridge.hostFunctions .soroban` / EmitWat packing
(contract len/ptr, method len/ptr, args len/ptr → result handle i64). -/
def sorobanInvokeContractImport : Import :=
  hostImport "invoke_contract" #[.i64, .i64, .i64, .i64, .i64, .i64] #[.i64]

/-- Drop NEAR Promise host imports — Soroban never materializes them. -/
def stripNearPromiseImports (imports : Array Import) : Array Import :=
  imports.filter fun import_ =>
    match import_.name with
    | "promise_create" | "promise_then" | "promise_results_count"
    | "promise_result" | "promise_return" => false
    | _ => true

/-- C.8: drop NEAR storage_* ABI; Soroban scalars use `_get`/`_put`.
Keep `read_register` — entry param prologue still uses NEAR input+register
shape until Soroban-specific input encoding lands. -/
def stripNearStorageImports (imports : Array Import) : Array Import :=
  imports.filter fun import_ =>
    match import_.name with
    | "storage_read" | "storage_write" | "storage_has_key" | "storage_remove" => false
    | _ => true

def sorobanGetImport : Import :=
  hostImport "_get" #[.i32, .i32] #[.i32]

def sorobanPutImport : Import :=
  hostImport "_put" #[.i32, .i32, .i32, .i32] #[]

def sorobanRequireAuthImport : Import :=
  hostImport "require_auth_for_args" #[.i32, .i32] #[.i32]

/-- CosmWasm host storage (matches WasmInterpreter / CosmWasmHost arity).
`db_read(key_ptr, key_len) → i64` le-word; `db_write(key_ptr, key_len, val_ptr, val_len)`. -/
def cosmWasmDbReadImport : Import :=
  hostImport "db_read" #[.i32, .i32] #[.i64]

def cosmWasmDbWriteImport : Import :=
  hostImport "db_write" #[.i32, .i32, .i32, .i32] #[]

def cosmWasmSetReturnDataImport : Import :=
  hostImport "set_return_data" #[.i32, .i32] #[]

def cosmWasmLogImport : Import :=
  hostImport "log" #[.i32, .i32] #[]

/-- Portable `crosscall.invoke` on CosmWasm: WasmMsg-shaped host execute stub.
Same arg packing as Soroban `invoke_contract` (string pool + JSON scratch). -/
def cosmWasmExecuteMsgImport : Import :=
  hostImport "execute_msg" #[.i64, .i64, .i64, .i64, .i64, .i64] #[.i64]

def importsForModulePlan
    (plan : ModulePlan) (cfg : ProofForge.IR.AllocatorConfig) (hasPanic : Bool)
    (bridge : ProofForge.Target.HostBridge := .near) : Array Import :=
  let sha256Imports := if modulePlanUsesSha256 plan then #[sha256Import] else #[]
  let baseImportsCore :=
    (nearImportsForModulePlan plan ++ sha256Imports).push inputImport
      |> fun imports =>
        if plan.usesEventApi then
          imports.push logUtf8Import
        else
          imports
  let baseImports := baseImportsCore ++ (if hasPanic then #[panicImport] else #[])
  let nearFamily :=
    baseImports ++ ctxImportsForModulePlan plan ++ promiseCtxImportsForModulePlan plan ++
      promiseResultImportsForModulePlan plan ++
      (if plan.usesU64IndexedContains || plan.usesHashIndexedContains then
        #[storageHasKeyImport]
      else
        #[]) ++
      hostAllocatorImportsForModulePlan plan cfg
  match bridge with
  | .soroban =>
      -- C.8: scalar storage → _get/_put. Promise_* never. Crosscall → invoke_contract.
      -- C.9: require_auth_for_args when caller/userId is used.
      let withoutPromise := stripNearPromiseImports nearFamily
      let withoutNearStorage := stripNearStorageImports withoutPromise
      let withStorage :=
        let acc := withoutNearStorage
        let acc := if plan.usesStorageRead then acc.push sorobanGetImport else acc
        if plan.usesStorageWrite then acc.push sorobanPutImport else acc
      let withAuth :=
        if plan.contextOps.contains .userId || plan.contextOps.contains .userIdHash ||
            plan.contextOps.contains .origin then
          withStorage.push sorobanRequireAuthImport
        else
          withStorage
      let withInvoke :=
        if plan.usesPromiseCreate then withAuth.push sorobanInvokeContractImport
        else withAuth
      dedupeImports withInvoke
  | .cosmWasm =>
      -- CosmWasm: db_read/db_write + portable crosscall → execute_msg (no NEAR promise).
      let withoutPromise := stripNearPromiseImports nearFamily
      let withoutNearStorage := stripNearStorageImports withoutPromise
      -- Drop NEAR input / value_return / log_utf8 when CosmWasm-shaped.
      let stripped := withoutNearStorage.filter fun import_ =>
        match import_.name with
        | "input" | "value_return" | "log_utf8" | "read_register"
        | "signer_account_id" | "predecessor_account_id" | "current_account_id"
        | "block_timestamp" | "block_index" | "epoch_height" | "random_seed"
        | "prepaid_gas" | "used_gas"
        | "attached_deposit" | "sha256" => false
        | _ => true
      let withStorage :=
        let acc := stripped
        let acc := if plan.usesStorageRead then acc.push cosmWasmDbReadImport else acc
        let acc := if plan.usesStorageWrite then acc.push cosmWasmDbWriteImport else acc
        let acc := if plan.usesEventApi then acc.push cosmWasmLogImport else acc
        if plan.returnTypes.isEmpty then acc
        else acc.push cosmWasmSetReturnDataImport
      let withRemote :=
        if plan.usesPromiseCreate then withStorage.push cosmWasmExecuteMsgImport
        else withStorage
      dedupeImports withRemote
  | .near => dedupeImports nearFamily

end ProofForge.Backend.WasmHost.Imports
