/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmNear.Plan
import ProofForge.Target.HostBridge

namespace ProofForge.Backend.WasmNear.Imports

open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmNear.Plan

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
def depositImport : Import := hostImport "attached_deposit" #[] #[.i64]
def registerLenImport : Import := hostImport "register_len" #[.i64] #[.i64]
def blockHeightImport : Import := hostImport "block_index" #[] #[.i64]
def epochHeightImport : Import := hostImport "epoch_height" #[] #[.i64]
def randomSeedImport : Import := hostImport "random_seed" #[.i64] #[]

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
    | _ => true

def ctxImportsForModulePlan (plan : ModulePlan) : Array Import :=
  (if plan.contextOps.contains .userId || plan.contextOps.contains .userIdHash then #[predecessorImport] else #[]) ++
    (if plan.contextOps.contains .contractId then #[currentAcctImport] else #[]) ++
    (if plan.contextOps.contains .userId || plan.contextOps.contains .userIdHash ||
        plan.contextOps.contains .contractId || plan.contextOps.contains .origin then #[registerLenImport] else #[]) ++
    (if plan.contextOps.contains .checkpointId then #[blockHeightImport] else #[])

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

def importsForModulePlan
    (plan : ModulePlan) (cfg : ProofForge.IR.AllocatorConfig) (hasPanic : Bool) : Array Import :=
  let sha256Imports := if modulePlanUsesSha256 plan then #[sha256Import] else #[]
  let baseImportsCore :=
    (nearImportsForModulePlan plan ++ sha256Imports).push inputImport
      |> fun imports =>
        if plan.usesEventApi then
          imports.push logUtf8Import
        else
          imports
  let baseImports := baseImportsCore ++ (if hasPanic then #[panicImport] else #[])
  dedupeImports <|
    baseImports ++ ctxImportsForModulePlan plan ++ promiseCtxImportsForModulePlan plan ++
      promiseResultImportsForModulePlan plan ++
      (if plan.usesU64IndexedContains || plan.usesHashIndexedContains then
        #[storageHasKeyImport]
      else
        #[]) ++
      hostAllocatorImportsForModulePlan plan cfg

end ProofForge.Backend.WasmNear.Imports
