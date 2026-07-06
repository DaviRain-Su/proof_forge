import ProofForge.Backend.WasmNear.EmitWat
import ProofForge.Backend.WasmNear.Plan
import ProofForge.IR.Contract
import ProofForge.IR.Examples.ArrayProbe
import ProofForge.IR.Examples.HashStorageProbe
import ProofForge.IR.Examples.StructProbe
import ProofForge.IR.Examples.NearCrosscallProbe

namespace ProofForge.Tests.WasmNearPlan

open ProofForge.IR
open ProofForge.Backend.WasmNear.EmitWat

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def requireContains (haystack needle : String) (message : String) : IO Unit :=
  require (haystack.contains needle) message

def requireNotContains (haystack needle : String) (message : String) : IO Unit :=
  require (!haystack.contains needle) message

def unsupportedChainId : Entrypoint := {
  name := "chainId", returns := .u64,
  body := #[.return (.effect (.contextRead .chainId))] }

def unsupportedChainIdModule : Module := {
  name := "UnsupportedChainId", state := #[],
  entrypoints := #[unsupportedChainId] }

def depositProbe : Entrypoint := {
  name := "depositProbe", returns := .u64,
  body := #[.return .nativeValue] }

def depositModule : Module := {
  name := "DepositProbe", state := #[],
  entrypoints := #[depositProbe] }

def counterGet : Entrypoint := {
  name := "get", returns := .u64,
  body := #[.return (.effect (.storageScalarRead "count"))] }

def counterBump : Entrypoint := {
  name := "bump", returns := .unit,
  body := #[.effect (.storageScalarAssignOp "count" .add (.literal (.u64 1)))] }

def counterModule : Module := {
  name := "CounterPlanProbe",
  state := #[{ id := "count", kind := .scalar, type := .u64 }],
  entrypoints := #[counterGet, counterBump] }

def constZero : Entrypoint := {
  name := "constZero", returns := .u64,
  body := #[.return (.literal (.u64 0))] }

def containsScore : Entrypoint := {
  name := "containsScore", returns := .bool,
  body := #[.return (.effect (.storageMapContains "scores" (.literal (.u64 7))))] }

def getScore : Entrypoint := {
  name := "getScore", returns := .u64,
  body := #[.return (.effect (.storageMapGet "scores" (.literal (.u64 7))))] }

def setScore : Entrypoint := {
  name := "setScore", returns := .unit,
  body := #[.effect (.storageMapSet "scores" (.literal (.u64 7)) (.literal (.u64 11)))] }

def getRoot : Entrypoint := {
  name := "getRoot", returns := .u64,
  body := #[.return (.effect (.storageMapGet "roots" (.literal (.hash4 1 2 3 4))))] }

def emitBoolEvent : Entrypoint := {
  name := "emitBoolEvent", returns := .unit,
  body := #[.effect (.eventEmit "FlagChanged" #[("enabled", .literal (.bool true))])] }

def emitU64Event : Entrypoint := {
  name := "emitU64Event", returns := .unit,
  body := #[.effect (.eventEmit "CountChanged" #[("count", .literal (.u64 7))])] }

def unusedMapModule : Module := {
  name := "UnusedMapProbe",
  state := #[{ id := "scores", kind := .map .u64 8, type := .u64 }],
  entrypoints := #[constZero] }

def getOnlyMapModule : Module := {
  name := "GetOnlyMapProbe",
  state := #[{ id := "scores", kind := .map .u64 8, type := .u64 }],
  entrypoints := #[getScore] }

def setOnlyMapModule : Module := {
  name := "SetOnlyMapProbe",
  state := #[{ id := "scores", kind := .map .u64 8, type := .u64 }],
  entrypoints := #[setScore] }

def unusedHashMapModule : Module := {
  name := "UnusedHashMapProbe",
  state := #[{ id := "roots", kind := .map .hash 8, type := .u64 }],
  entrypoints := #[constZero] }

def getOnlyHashMapModule : Module := {
  name := "GetOnlyHashMapProbe",
  state := #[{ id := "roots", kind := .map .hash 8, type := .u64 }],
  entrypoints := #[getRoot] }

def unusedArrayModule : Module := {
  name := "UnusedArrayProbe",
  state := #[{ id := "values", kind := .array 4, type := .u64 }],
  entrypoints := #[constZero] }

def containsOnlyMapModule : Module := {
  name := "ContainsOnlyMapProbe",
  state := #[{ id := "scores", kind := .map .u64 8, type := .u64 }],
  entrypoints := #[containsScore] }

def boolEventModule : Module := {
  name := "BoolEventProbe",
  entrypoints := #[emitBoolEvent],
  state := #[] }

def u64EventModule : Module := {
  name := "U64EventProbe",
  entrypoints := #[emitU64Event],
  state := #[] }

def hashLiteralGet : Entrypoint := {
  name := "hashLiteralGet", returns := .hash,
  body := #[.return (.literal (.hash4 1 2 3 4))] }

def hashPreimageGet : Entrypoint := {
  name := "hashPreimageGet", returns := .hash,
  body := #[
    .letBind "data" .hash (.literal (.hash4 1 2 3 4)),
    .return (.hash (.local "data"))] }

def hashPairGet : Entrypoint := {
  name := "hashPairGet", returns := .hash,
  body := #[
    .letBind "left" .hash (.literal (.hash4 1 2 3 4)),
    .letBind "right" .hash (.literal (.hash4 5 6 7 8)),
    .return (.hashTwoToOne (.local "left") (.local "right"))] }

def hashEqProbe : Entrypoint := {
  name := "hashEqProbe", returns := .u64,
  body := #[
    .assertEq (.literal (.hash4 1 2 3 4)) (.literal (.hash4 1 2 3 4)) "hash mismatch",
    .return (.literal (.u64 1))] }

def hashLiteralModule : Module := {
  name := "HashLiteralProbe",
  entrypoints := #[hashLiteralGet],
  state := #[] }

def hashPreimageModule : Module := {
  name := "HashPreimageProbe",
  entrypoints := #[hashPreimageGet],
  state := #[] }

def hashPairModule : Module := {
  name := "HashPairProbe",
  entrypoints := #[hashPairGet],
  state := #[] }

def hashEqModule : Module := {
  name := "HashEqProbe",
  entrypoints := #[hashEqProbe],
  state := #[] }

def powU64Probe : Entrypoint := {
  name := "powU64", returns := .u64,
  body := #[.return (.pow (.literal (.u64 17)) (.literal (.u64 2)))] }

def powU32Probe : Entrypoint := {
  name := "powU32", returns := .u32,
  body := #[.return (.pow (.literal (.u32 17)) (.literal (.u32 2)))] }

def powU64Module : Module := {
  name := "PowU64Probe",
  entrypoints := #[powU64Probe],
  state := #[] }

def powU32Module : Module := {
  name := "PowU32Probe",
  entrypoints := #[powU32Probe],
  state := #[] }

def testDepositRenderPrunesUnusedContextSurface : IO Unit := do
  let wat ←
    match renderModule depositModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat deposit render failed: {err.message}"
  requireContains wat "(import \"env\" \"attached_deposit\"" "deposit module must import attached_deposit"
  requireContains wat "(import \"env\" \"value_return\"" "deposit module must import value_return for U64 returns"
  requireContains wat "__pf_return_u64" "deposit module must emit the U64 return helper"
  requireNotContains wat "__pf_ctx_user_id" "deposit module should not emit caller context helper"
  requireNotContains wat "__pf_ctx_contract_id" "deposit module should not emit contract context helper"
  requireNotContains wat "__pf_ctx_signer_id" "deposit module should not emit signer context helper"
  requireNotContains wat "__pf_ctx_random_seed" "deposit module should not emit random-seed context helper"
  requireNotContains wat "__pf_read_u32" "deposit module should not emit U32 scalar read helper"
  requireNotContains wat "__pf_write_u32" "deposit module should not emit U32 scalar write helper"
  requireNotContains wat "__pf_read_u64" "deposit module should not emit U64 scalar read helper"
  requireNotContains wat "__pf_write_u64" "deposit module should not emit U64 scalar write helper"
  requireNotContains wat "__pf_read_bool" "deposit module should not emit Bool scalar read helper"
  requireNotContains wat "__pf_write_bool" "deposit module should not emit Bool scalar write helper"
  requireNotContains wat "__pf_read_hash" "deposit module should not emit Hash scalar read helper"
  requireNotContains wat "__pf_write_hash" "deposit module should not emit Hash scalar write helper"
  requireNotContains wat "(import \"env\" \"predecessor_account_id\"" "deposit module should not import predecessor_account_id"
  requireNotContains wat "(import \"env\" \"current_account_id\"" "deposit module should not import current_account_id"
  requireNotContains wat "(import \"env\" \"register_len\"" "deposit module should not import register_len"
  requireNotContains wat "(import \"env\" \"block_index\"" "deposit module should not import block_index"
  requireNotContains wat "(import \"env\" \"signer_account_id\"" "deposit module should not import signer_account_id"
  requireNotContains wat "(import \"env\" \"block_timestamp\"" "deposit module should not import block_timestamp"
  requireNotContains wat "(import \"env\" \"epoch_height\"" "deposit module should not import epoch_height"
  requireNotContains wat "(import \"env\" \"random_seed\"" "deposit module should not import random_seed"
  requireNotContains wat "(import \"env\" \"storage_read\"" "deposit module should not import storage_read"
  requireNotContains wat "(import \"env\" \"storage_write\"" "deposit module should not import storage_write"
  requireNotContains wat "(import \"env\" \"log_utf8\"" "deposit module should not import log_utf8"
  requireNotContains wat "(import \"env\" \"promise_create\"" "deposit module should not import promise_create"
  requireNotContains wat "(import \"env\" \"promise_then\"" "deposit module should not import promise_then"
  requireNotContains wat "(import \"env\" \"promise_results_count\"" "deposit module should not import promise_results_count"
  requireNotContains wat "(import \"env\" \"promise_result\"" "deposit module should not import promise_result"
  requireNotContains wat "(import \"env\" \"promise_return\"" "deposit module should not import promise_return"
  requireNotContains wat "__pf_evt_start" "deposit module should not emit event helpers"
  requireNotContains wat "__pf_evt_log" "deposit module should not emit event logging helpers"

def testCounterRenderKeepsOnlyU64ScalarHelpers : IO Unit := do
  let wat ←
    match renderModule counterModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat counter render failed: {err.message}"
  requireContains wat "(import \"env\" \"storage_read\"" "counter module must import storage_read"
  requireContains wat "(import \"env\" \"storage_write\"" "counter module must import storage_write"
  requireContains wat "(import \"env\" \"value_return\"" "counter module must import value_return"
  requireContains wat "__pf_read_u64" "counter module must emit U64 scalar read helper"
  requireContains wat "__pf_write_u64" "counter module must emit U64 scalar write helper"
  requireContains wat "__pf_return_u64" "counter module must emit U64 return helper"
  requireNotContains wat "__pf_read_u32" "counter module should not emit U32 scalar read helper"
  requireNotContains wat "__pf_write_u32" "counter module should not emit U32 scalar write helper"
  requireNotContains wat "__pf_read_bool" "counter module should not emit Bool scalar read helper"
  requireNotContains wat "__pf_write_bool" "counter module should not emit Bool scalar write helper"
  requireNotContains wat "__pf_return_u32" "counter module should not emit U32 return helper"
  requireNotContains wat "__pf_return_bool" "counter module should not emit Bool return helper"
  requireNotContains wat "__pf_read_hash" "counter module should not emit Hash scalar read helper"
  requireNotContains wat "__pf_write_hash" "counter module should not emit Hash scalar write helper"
  requireNotContains wat "(import \"env\" \"log_utf8\"" "counter module should not import log_utf8"
  requireNotContains wat "(import \"env\" \"promise_create\"" "counter module should not import promise_create"
  requireNotContains wat "(import \"env\" \"promise_then\"" "counter module should not import promise_then"
  requireNotContains wat "(import \"env\" \"promise_results_count\"" "counter module should not import promise_results_count"
  requireNotContains wat "(import \"env\" \"promise_result\"" "counter module should not import promise_result"
  requireNotContains wat "(import \"env\" \"promise_return\"" "counter module should not import promise_return"
  requireNotContains wat "(import \"env\" \"pf_alloc\"" "counter module should not import pf_alloc"
  requireNotContains wat "(import \"env\" \"pf_dealloc\"" "counter module should not import pf_dealloc"
  requireNotContains wat "__pf_evt_start" "counter module should not emit event helpers"
  requireNotContains wat "__pf_evt_log" "counter module should not emit event logging helpers"
  requireNotContains wat "__pf_pow_u32" "counter module should not emit U32 pow helper"
  requireNotContains wat "__pf_pow_u64" "counter module should not emit U64 pow helper"
  requireNotContains wat "__pf_hash_alloc" "counter module should not emit hash alloc helper"
  requireNotContains wat "__pf_hash_make" "counter module should not emit hash make helper"
  requireNotContains wat "(func $__pf_hash " "counter module should not emit hash preimage helper"
  requireNotContains wat "__pf_hash_two_to_one" "counter module should not emit hash two-to-one helper"
  requireNotContains wat "__pf_hash_eq" "counter module should not emit hash equality helper"
  requireNotContains wat "__pf_memcpy" "counter module should not emit memcpy helper"
  requireNotContains wat "(import \"env\" \"sha256\"" "counter module should not import sha256"
  requireNotContains wat "(global $arr_ptr" "counter module should not emit arr_ptr global"
  requireNotContains wat "__pf_arr_alloc" "counter module should not emit arr alloc helper"
  requireNotContains wat "__pf_arr_dealloc" "counter module should not emit arr dealloc helper"
  requireNotContains wat "__pf_arr_lit_" "counter module should not emit array literal helpers"
  requireNotContains wat "__pf_arr_eq_" "counter module should not emit array equality helpers"
  requireNotContains wat "__pf_struct_lit_" "counter module should not emit struct literal helpers"

def testUnusedIndexedStorageRenderPrunesMapHelperSurface : IO Unit := do
  let unusedMapWat ←
    match renderModule unusedMapModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat unused map render failed: {err.message}"
  requireNotContains unusedMapWat "(import \"env\" \"storage_has_key\"" "unused map module should not import storage_has_key"
  requireNotContains unusedMapWat "(import \"env\" \"storage_read\"" "unused map module should not import storage_read"
  requireNotContains unusedMapWat "(import \"env\" \"storage_write\"" "unused map module should not import storage_write"
  requireNotContains unusedMapWat "__pf_map_buildkey" "unused map module should not emit u64-key map buildkey helper"
  requireNotContains unusedMapWat "__pf_map_read_u64" "unused map module should not emit u64-key map read helper"
  requireNotContains unusedMapWat "__pf_map_write_u64" "unused map module should not emit u64-key map write helper"
  requireNotContains unusedMapWat "__pf_map_contains" "unused map module should not emit u64-key map contains helper"
  let unusedHashMapWat ←
    match renderModule unusedHashMapModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat unused hash-map render failed: {err.message}"
  requireNotContains unusedHashMapWat "__pf_map_buildkey_hash" "unused hash-map module should not emit hash-key map buildkey helper"
  requireNotContains unusedHashMapWat "__pf_map_read_hash_u64" "unused hash-map module should not emit hash-key map read helper"
  requireNotContains unusedHashMapWat "__pf_map_write_hash_u64" "unused hash-map module should not emit hash-key map write helper"
  requireNotContains unusedHashMapWat "__pf_map_contains_hash" "unused hash-map module should not emit hash-key map contains helper"
  let unusedArrayWat ←
    match renderModule unusedArrayModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat unused array render failed: {err.message}"
  requireNotContains unusedArrayWat "__pf_map_buildkey" "unused array module should not emit indexed-storage buildkey helper"
  requireNotContains unusedArrayWat "(import \"env\" \"storage_read\"" "unused array module should not import storage_read"
  requireNotContains unusedArrayWat "(import \"env\" \"storage_write\"" "unused array module should not import storage_write"
  requireNotContains unusedArrayWat "__pf_map_read_u64" "unused array module should not emit indexed-storage read helper"
  requireNotContains unusedArrayWat "__pf_map_write_u64" "unused array module should not emit indexed-storage write helper"

def testContainsOnlyMapRenderKeepsContainsSurface : IO Unit := do
  let wat ←
    match renderModule containsOnlyMapModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat contains-only map render failed: {err.message}"
  requireContains wat "(import \"env\" \"storage_has_key\"" "contains-only map module must import storage_has_key"
  requireContains wat "__pf_map_buildkey" "contains-only map module must emit the u64-key buildkey helper"
  requireContains wat "__pf_map_contains" "contains-only map module must emit the u64-key contains helper"
  requireNotContains wat "(import \"env\" \"storage_read\"" "contains-only map module should not import storage_read"
  requireNotContains wat "(import \"env\" \"storage_write\"" "contains-only map module should not import storage_write"
  requireNotContains wat "__pf_map_read_u64" "contains-only map module should not emit the u64-key read helper"
  requireNotContains wat "__pf_map_write_u64" "contains-only map module should not emit the u64-key write helper"

def testIndexedStorageRenderKeepsOnlyReadWriteHelperSurface : IO Unit := do
  let getOnlyMapWat ←
    match renderModule getOnlyMapModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat get-only map render failed: {err.message}"
  requireNotContains getOnlyMapWat "(import \"env\" \"storage_has_key\"" "get-only map module should not import storage_has_key"
  requireContains getOnlyMapWat "(import \"env\" \"storage_read\"" "get-only map module must import storage_read"
  requireNotContains getOnlyMapWat "(import \"env\" \"storage_write\"" "get-only map module should not import storage_write"
  requireContains getOnlyMapWat "__pf_map_buildkey" "get-only map module must emit the u64-key buildkey helper"
  requireContains getOnlyMapWat "__pf_map_read_u64" "get-only map module must emit the u64-key read helper"
  requireNotContains getOnlyMapWat "__pf_map_write_u64" "get-only map module should not emit the u64-key write helper"
  requireNotContains getOnlyMapWat "__pf_map_contains" "get-only map module should not emit the u64-key contains helper"
  let setOnlyMapWat ←
    match renderModule setOnlyMapModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat set-only map render failed: {err.message}"
  requireNotContains setOnlyMapWat "(import \"env\" \"storage_has_key\"" "set-only map module should not import storage_has_key"
  requireContains setOnlyMapWat "(import \"env\" \"storage_read\"" "set-only map module must import storage_read"
  requireContains setOnlyMapWat "(import \"env\" \"storage_write\"" "set-only map module must import storage_write"
  requireContains setOnlyMapWat "__pf_map_buildkey" "set-only map module must emit the u64-key buildkey helper"
  requireContains setOnlyMapWat "__pf_map_write_u64" "set-only map module must emit the u64-key write helper"
  requireNotContains setOnlyMapWat "__pf_map_read_u64" "set-only map module should not emit the u64-key read helper"
  requireNotContains setOnlyMapWat "__pf_map_contains" "set-only map module should not emit the u64-key contains helper"
  let getOnlyHashMapWat ←
    match renderModule getOnlyHashMapModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat get-only hash-map render failed: {err.message}"
  requireNotContains getOnlyHashMapWat "(import \"env\" \"storage_has_key\"" "get-only hash-map module should not import storage_has_key"
  requireContains getOnlyHashMapWat "(import \"env\" \"storage_read\"" "get-only hash-map module must import storage_read"
  requireNotContains getOnlyHashMapWat "(import \"env\" \"storage_write\"" "get-only hash-map module should not import storage_write"
  requireContains getOnlyHashMapWat "__pf_map_buildkey_hash" "get-only hash-map module must emit the hash-key buildkey helper"
  requireContains getOnlyHashMapWat "__pf_map_read_hash_u64" "get-only hash-map module must emit the hash-key read helper"
  requireNotContains getOnlyHashMapWat "__pf_map_write_hash_u64" "get-only hash-map module should not emit the hash-key write helper"
  requireNotContains getOnlyHashMapWat "__pf_map_contains_hash" "get-only hash-map module should not emit the hash-key contains helper"

def testEventRenderKeepsOnlyNeededEventSurface : IO Unit := do
  let boolEventWat ←
    match renderModule boolEventModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat bool-event render failed: {err.message}"
  requireContains boolEventWat "(import \"env\" \"log_utf8\"" "bool-event module must import log_utf8"
  requireContains boolEventWat "__pf_evt_start" "bool-event module must emit event start helper"
  requireContains boolEventWat "__pf_evt_putc" "bool-event module must emit event putc helper"
  requireContains boolEventWat "__pf_evt_putstr" "bool-event module must emit event putstr helper"
  requireContains boolEventWat "__pf_evt_putbool" "bool-event module must emit event bool helper"
  requireContains boolEventWat "__pf_evt_log" "bool-event module must emit event log helper"
  requireNotContains boolEventWat "__pf_fmt_u64" "bool-event module should not emit numeric event formatting helper"
  requireNotContains boolEventWat "__pf_evt_putu64" "bool-event module should not emit numeric event writer helper"
  let u64EventWat ←
    match renderModule u64EventModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat u64-event render failed: {err.message}"
  requireContains u64EventWat "(import \"env\" \"log_utf8\"" "u64-event module must import log_utf8"
  requireContains u64EventWat "__pf_evt_start" "u64-event module must emit event start helper"
  requireContains u64EventWat "__pf_evt_putstr" "u64-event module must emit event putstr helper"
  requireContains u64EventWat "__pf_fmt_u64" "u64-event module must emit numeric event formatting helper"
  requireContains u64EventWat "__pf_evt_putu64" "u64-event module must emit numeric event writer helper"
  requireContains u64EventWat "__pf_evt_log" "u64-event module must emit event log helper"
  requireNotContains u64EventWat "__pf_evt_putbool" "u64-event module should not emit bool event helper"

def testHashLiteralRenderKeepsMakeSurfaceOnly : IO Unit := do
  let wat ←
    match renderModule hashLiteralModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat hash-literal render failed: {err.message}"
  requireNotContains wat "(import \"env\" \"sha256\"" "hash-literal module should not import sha256"
  requireContains wat "__pf_hash_alloc" "hash-literal module must emit hash alloc helper"
  requireContains wat "__pf_hash_make" "hash-literal module must emit hash make helper"
  requireNotContains wat "(func $__pf_hash " "hash-literal module should not emit hash preimage helper"
  requireNotContains wat "__pf_hash_two_to_one" "hash-literal module should not emit hash two-to-one helper"
  requireNotContains wat "__pf_hash_eq" "hash-literal module should not emit hash equality helper"
  requireNotContains wat "__pf_memcpy" "hash-literal module should not emit memcpy helper"

def testHashPreimageRenderKeepsSha256AndPreimageHelper : IO Unit := do
  let wat ←
    match renderModule hashPreimageModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat hash-preimage render failed: {err.message}"
  requireContains wat "(import \"env\" \"sha256\"" "hash-preimage module must import sha256"
  requireContains wat "__pf_hash_alloc" "hash-preimage module must emit hash alloc helper"
  requireContains wat "__pf_hash_make" "hash-preimage module must emit hash make helper"
  requireContains wat "(func $__pf_hash " "hash-preimage module must emit hash preimage helper"
  requireNotContains wat "__pf_hash_two_to_one" "hash-preimage module should not emit hash two-to-one helper"
  requireNotContains wat "__pf_hash_eq" "hash-preimage module should not emit hash equality helper"

def testHashPairRenderKeepsTwoToOneAndMemcpySurface : IO Unit := do
  let wat ←
    match renderModule hashPairModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat hash-pair render failed: {err.message}"
  requireContains wat "(import \"env\" \"sha256\"" "hash-pair module must import sha256"
  requireContains wat "__pf_hash_alloc" "hash-pair module must emit hash alloc helper"
  requireContains wat "__pf_hash_make" "hash-pair module must emit hash make helper"
  requireContains wat "__pf_hash_two_to_one" "hash-pair module must emit hash two-to-one helper"
  requireContains wat "__pf_memcpy" "hash-pair module must emit memcpy helper"
  requireNotContains wat "(func $__pf_hash " "hash-pair module should not emit hash preimage helper"
  requireNotContains wat "__pf_hash_eq" "hash-pair module should not emit hash equality helper"

def testHashEqRenderKeepsEqualityHelperOnly : IO Unit := do
  let wat ←
    match renderModule hashEqModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat hash-eq render failed: {err.message}"
  requireContains wat "__pf_hash_alloc" "hash-eq module must emit hash alloc helper"
  requireContains wat "__pf_hash_make" "hash-eq module must emit hash make helper"
  requireContains wat "__pf_hash_eq" "hash-eq module must emit hash equality helper"
  requireNotContains wat "(import \"env\" \"sha256\"" "hash-eq module should not import sha256"
  requireNotContains wat "(func $__pf_hash " "hash-eq module should not emit hash preimage helper"
  requireNotContains wat "__pf_hash_two_to_one" "hash-eq module should not emit hash two-to-one helper"
  requireNotContains wat "__pf_memcpy" "hash-eq module should not emit memcpy helper"

def testHashStorageRenderKeepsMemcpyForHashArrayWrites : IO Unit := do
  let wat ←
    match renderModule ProofForge.IR.Examples.HashStorageProbe.module with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat hash-storage render failed: {err.message}"
  requireContains wat "__pf_map_write_hash" "hash-storage module must emit hash-valued indexed-storage write helper"
  requireContains wat "__pf_memcpy" "hash-storage module must emit memcpy helper for hash-valued indexed-storage writes"

def testArrayLiteralRenderKeepsOnlyMatchingArrayLitSurface : IO Unit := do
  let wat ←
    match renderModule ProofForge.IR.Examples.ArrayProbe.emitWatSumModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat array-literal render failed: {err.message}"
  requireContains wat "(global $arr_ptr" "array-literal module must emit arr_ptr global"
  requireContains wat "__pf_arr_alloc" "array-literal module must emit arr alloc helper"
  requireContains wat "__pf_arr_lit_u64_3" "array-literal module must emit u64[3] literal helper"
  requireNotContains wat "__pf_arr_eq_u64_3" "array-literal module should not emit array equality helper"
  requireNotContains wat "__pf_arr_dealloc" "array-literal module should not emit arr dealloc helper"
  requireNotContains wat "__pf_struct_lit_" "array-literal module should not emit struct literal helpers"

def arrayPredicatesOnlyModule : Module := {
  name := "ArrayPredicatesProbe",
  entrypoints := #[ProofForge.IR.Examples.ArrayProbe.arrayPredicates],
  state := #[] }

def releaseThenSumOnlyModule : Module := {
  name := "ReleaseThenSumProbe",
  entrypoints := #[ProofForge.IR.Examples.ArrayProbe.releaseThenSum],
  state := #[] }

def testArrayPredicateRenderKeepsEqualityAndDeallocSurface : IO Unit := do
  let eqWat ←
    match renderModule arrayPredicatesOnlyModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat array-predicate render failed: {err.message}"
  requireContains eqWat "__pf_arr_lit_u64_3" "array-predicate module must emit u64[3] literal helper"
  requireContains eqWat "__pf_arr_eq_u64_3" "array-predicate module must emit u64[3] equality helper"
  requireNotContains eqWat "__pf_arr_dealloc" "array-predicate module should not emit arr dealloc helper"
  let releaseWat ←
    match renderModule releaseThenSumOnlyModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat array-release render failed: {err.message}"
  requireContains releaseWat "__pf_arr_lit_u64_3" "array-release module must emit u64[3] literal helper"
  requireContains releaseWat "__pf_arr_dealloc" "array-release module must emit arr dealloc helper"
  requireNotContains releaseWat "__pf_arr_eq_u64_3" "array-release module should not emit array equality helper"

def hostBumpScalarModule : Module := {
  counterModule with allocator := ProofForge.IR.AllocatorConfig.hostBump }

def testHostBumpScalarRenderOmitsHostAllocatorImports : IO Unit := do
  let wat ←
    match renderModule hostBumpScalarModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat host-bump scalar render failed: {err.message}"
  requireNotContains wat "(import \"env\" \"pf_alloc\"" "host-bump scalar module should not import pf_alloc"
  requireNotContains wat "(import \"env\" \"pf_dealloc\"" "host-bump scalar module should not import pf_dealloc"
  requireNotContains wat "__pf_arr_alloc" "host-bump scalar module should not emit arr alloc helper"

def testHostBumpArrayLiteralRenderKeepsOnlyPfAllocImport : IO Unit := do
  let wat ←
    match renderModule ProofForge.IR.Examples.ArrayProbe.emitWatSumExternalModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat host-bump array-literal render failed: {err.message}"
  requireContains wat "(import \"env\" \"pf_alloc\"" "host-bump array-literal module must import pf_alloc"
  requireContains wat "__pf_arr_alloc" "host-bump array-literal module must emit arr alloc helper"
  requireNotContains wat "(import \"env\" \"pf_dealloc\"" "host-bump array-literal module should not import pf_dealloc"
  requireNotContains wat "__pf_arr_dealloc" "host-bump array-literal module should not emit arr dealloc helper"

def testHostJemallocReleaseRenderKeepsPfAllocAndDeallocImports : IO Unit := do
  let wat ←
    match renderModule ProofForge.IR.Examples.ArrayProbe.emitWatReleaseExternalModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat host-jemalloc release render failed: {err.message}"
  requireContains wat "(import \"env\" \"pf_alloc\"" "host-jemalloc release module must import pf_alloc"
  requireContains wat "(import \"env\" \"pf_dealloc\"" "host-jemalloc release module must import pf_dealloc"
  requireContains wat "__pf_arr_alloc" "host-jemalloc release module must emit arr alloc helper"
  requireContains wat "__pf_arr_dealloc" "host-jemalloc release module must emit arr dealloc helper"

def testCrosscallRenderEncodesU64ArgsJson : IO Unit := do
  let wat ←
    match renderModule ProofForge.IR.Examples.NearCrosscallProbe.module with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat crosscall-args render failed: {err.message}"
  requireContains wat "__pf_crosscall_args_start" "crosscall-args module must emit args builder start helper"
  requireContains wat "__pf_crosscall_args_putu64" "crosscall-args module must emit args u64 helper"
  requireContains wat "__pf_fmt_u64" "crosscall-args module must emit decimal formatter helper"
  requireContains wat "(global $crosscall_ptr" "crosscall-args module must emit crosscall_ptr global"

def crosscallCreateOnlyModule : Module := {
  name := "NearCrosscallCreateOnly"
  state := #[]
  entrypoints := #[ProofForge.IR.Examples.NearCrosscallProbe.callRemote]
  nearCrosscallStrings := #["callee.testnet", "remote_call"]
}

def testCrosscallRenderKeepsOnlyCreatePromiseSurface : IO Unit := do
  let wat ←
    match renderModule crosscallCreateOnlyModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat crosscall render failed: {err.message}"
  requireContains wat "(import \"env\" \"promise_create\"" "crosscall module must import promise_create"
  requireContains wat "(import \"env\" \"promise_return\"" "crosscall module must import promise_return"
  requireContains wat "(data (i32.const 49000) \"callee.testnet\")" "crosscall module must emit target account data"
  requireContains wat "(data (i32.const 49015) \"remote_call\")" "crosscall module must emit method name data"
  requireContains wat "(data (i32.const 48100) \"[]\")" "crosscall module must emit empty JSON args data"
  requireContains wat "call $promise_create" "crosscall module must call promise_create"
  requireContains wat "call $promise_return" "crosscall module must call promise_return"
  requireNotContains wat "(import \"env\" \"promise_then\"" "create-only crosscall module should not import promise_then"
  requireNotContains wat "(import \"env\" \"promise_results_count\"" "create-only crosscall module should not import promise_results_count"
  requireNotContains wat "(import \"env\" \"promise_result\"" "create-only crosscall module should not import promise_result"
  requireNotContains wat "(import \"env\" \"log_utf8\"" "create-only crosscall module should not import log_utf8"
  requireNotContains wat "(import \"env\" \"current_account_id\"" "create-only crosscall module should not import current_account_id"

def testNearPromisePlanSurface : IO Unit := do
  let plan ←
    match ProofForge.Backend.WasmNear.Plan.buildModulePlan ProofForge.IR.Examples.NearCrosscallProbe.module with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError s!"wasm-near plan failed: {err.message}"
  if !plan.usesPromiseThen then
    throw <| IO.userError "NearCrosscallProbe plan must set usesPromiseThen"
  if !plan.usesPromiseResults then
    throw <| IO.userError "NearCrosscallProbe plan must set usesPromiseResults"
  if !plan.usesPromiseResultU64 then
    throw <| IO.userError "NearCrosscallProbe plan must set usesPromiseResultU64"
  if !plan.usesPromiseReceiverAccount then
    throw <| IO.userError "NearCrosscallProbe plan must set usesPromiseReceiverAccount"

def testNearPromiseRenderChainsCallback : IO Unit := do
  let wat ←
    match renderModule ProofForge.IR.Examples.NearCrosscallProbe.module with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat near-promise render failed: {err.message}"
  requireContains wat "(import \"env\" \"promise_then\"" "near-promise module must import promise_then"
  requireContains wat "(import \"env\" \"promise_results_count\"" "near-promise module must import promise_results_count"
  requireContains wat "(import \"env\" \"promise_result\"" "near-promise module must import promise_result"
  requireContains wat "(import \"env\" \"current_account_id\"" "near-promise module must import current_account_id"
  requireContains wat "(data (i32.const 49027) \"handle_remote\")" "near-promise module must emit callback method data"
  requireContains wat "__pf_promise_current_account" "near-promise module must emit current-account helper"
  requireContains wat "call $promise_then" "near-promise module must call promise_then"
  requireContains wat "call $promise_results_count" "near-promise module must call promise_results_count"
  requireContains wat "__pf_promise_result_u64" "near-promise module must emit promise result U64 helper"
  requireContains wat "call $promise_result" "near-promise module must call promise_result via helper"

def testStructLiteralRenderKeepsOnlyMatchingStructLitSurface : IO Unit := do
  let wat ←
    match renderModule ProofForge.IR.Examples.StructProbe.emitWatLocalSumModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat struct-literal render failed: {err.message}"
  requireContains wat "(global $arr_ptr" "struct-literal module must emit arr_ptr global"
  requireContains wat "__pf_arr_alloc" "struct-literal module must emit arr alloc helper"
  requireContains wat "__pf_struct_lit_Point" "struct-literal module must emit Point struct literal helper"
  requireNotContains wat "__pf_arr_lit_" "struct-literal module should not emit array literal helpers"
  requireNotContains wat "__pf_arr_eq_" "struct-literal module should not emit array equality helpers"
  requireNotContains wat "__pf_arr_dealloc" "struct-literal module should not emit arr dealloc helper"

def testPowRenderKeepsOnlyMatchingNumericPowHelper : IO Unit := do
  let u64Wat ←
    match renderModule powU64Module with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat pow-u64 render failed: {err.message}"
  requireContains u64Wat "__pf_pow_u64" "pow-u64 module must emit U64 pow helper"
  requireNotContains u64Wat "__pf_pow_u32" "pow-u64 module should not emit U32 pow helper"
  requireNotContains u64Wat "__pf_hash_alloc" "pow-u64 module should not emit hash alloc helper"
  let u32Wat ←
    match renderModule powU32Module with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError s!"EmitWat pow-u32 render failed: {err.message}"
  requireContains u32Wat "__pf_pow_u32" "pow-u32 module must emit U32 pow helper"
  requireNotContains u32Wat "__pf_pow_u64" "pow-u32 module should not emit U64 pow helper"
  requireNotContains u32Wat "__pf_hash_alloc" "pow-u32 module should not emit hash alloc helper"

def testUnsupportedContextDiagnostic : IO Unit := do
  match renderModule unsupportedChainIdModule with
  | .ok _ =>
      throw <| IO.userError "chainId context read should not lower on wasm-near EmitWat"
  | .error err =>
      require (err.message == "EmitWat: wasm-near context read `chainId` is not supported; supported fields are userId, userIdHash, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin")
        s!"unsupported context diagnostic mismatch: {err.message}"

def main : IO UInt32 := do
  testDepositRenderPrunesUnusedContextSurface
  testCounterRenderKeepsOnlyU64ScalarHelpers
  testUnusedIndexedStorageRenderPrunesMapHelperSurface
  testContainsOnlyMapRenderKeepsContainsSurface
  testIndexedStorageRenderKeepsOnlyReadWriteHelperSurface
  testEventRenderKeepsOnlyNeededEventSurface
  testHashLiteralRenderKeepsMakeSurfaceOnly
  testHashPreimageRenderKeepsSha256AndPreimageHelper
  testHashPairRenderKeepsTwoToOneAndMemcpySurface
  testHashEqRenderKeepsEqualityHelperOnly
  testHashStorageRenderKeepsMemcpyForHashArrayWrites
  testPowRenderKeepsOnlyMatchingNumericPowHelper
  testArrayLiteralRenderKeepsOnlyMatchingArrayLitSurface
  testArrayPredicateRenderKeepsEqualityAndDeallocSurface
  testHostBumpScalarRenderOmitsHostAllocatorImports
  testHostBumpArrayLiteralRenderKeepsOnlyPfAllocImport
  testHostJemallocReleaseRenderKeepsPfAllocAndDeallocImports
  testCrosscallRenderEncodesU64ArgsJson
  testCrosscallRenderKeepsOnlyCreatePromiseSurface
  testNearPromisePlanSurface
  testNearPromiseRenderChainsCallback
  testStructLiteralRenderKeepsOnlyMatchingStructLitSurface
  testUnsupportedContextDiagnostic
  IO.println "wasm-near-plan: ok"
  return 0

end ProofForge.Tests.WasmNearPlan

def main : IO UInt32 :=
  ProofForge.Tests.WasmNearPlan.main
