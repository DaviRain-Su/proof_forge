import Init.Data.Array.Basic
import ProofForge.Backend.Evm.Plan
import ProofForge.Contract.EvmConstructorInit
import ProofForge.Contract.Spec
import ProofForge.IR.Contract
import ProofForge.Util.StringUtil

namespace ProofForge.Backend.Evm.ConstructorInit

open ProofForge.IR
open ProofForge.Contract
open ProofForge.Util.StringUtil
open ProofForge.Backend.Evm.Plan

structure InitError where
  message : String
  deriving Repr, Inhabited

def InitError.render (err : InitError) : String := err.message

def paramIsDynamic (abiType : String) : Bool :=
  abiType == "string" || abiType == "bytes" || abiType == "uint256[]"

def paramWithIndex? (params : Array EvmConstructorParam) (name : String) : Option (Nat × EvmConstructorParam) :=
  params.zipIdx.toList.find? (fun (param, idx) => param.name == name) |>.map (fun (param, idx) => (idx, param))

def findStorageState (layout : StorageLayout) (stateId : String) : Option StorageStatePlan :=
  layout.states.find? (fun state => state.id == stateId)

def u64Mask : String := "18446744073709551615"

def headWordOffsetExpr (paramIdx : Nat) : String :=
  s!"add(__pf_args_off, {32 * paramIdx})"

def codeLoadExpr (offsetExpr : String) : String :=
  s!"__pf_code_load({offsetExpr})"

def paramDataPtrExpr (param : EvmConstructorParam) (paramIdx : Nat) : String :=
  let head := headWordOffsetExpr paramIdx
  if paramIsDynamic param.abiType then
    s!"add(__pf_args_off, {codeLoadExpr head})"
  else
    head

def storePackedU64 (state : StorageStatePlan) (valueExpr : String) : String :=
  let shift := (32 - (state.byteOffset + state.byteWidth)) * 8
  let mask := (1 <<< (8 * state.byteWidth)) - 1
  if state.byteWidth >= 32 || (state.byteOffset == 0 && state.byteWidth == 32) then
    s!"sstore({state.slot}, {valueExpr})"
  else
    s!"sstore({state.slot}, or(and(sload({state.slot}), not(shl({shift}, {mask}))), shl({shift}, and({valueExpr}, {mask}))))"

def storeFullWord (state : StorageStatePlan) (valueExpr : String) : String :=
  s!"sstore({state.slot}, {valueExpr})"

def genBindingInit
    (params : Array EvmConstructorParam)
    (layout : StorageLayout)
    (binding : EvmConstructorInitBinding) : Except InitError String := do
  let some (paramIdx, param) := paramWithIndex? params binding.paramName
    | .error { message := s!"constructor_bind references unknown param `{binding.paramName}`" }
  let some state := findStorageState layout binding.stateId
    | .error { message := s!"constructor_bind references unknown state `{binding.stateId}`" }
  let dataPtr := paramDataPtrExpr param paramIdx
  match binding.kind with
  | .scalarU64 =>
    if paramIsDynamic param.abiType then
      .error { message := s!"constructor_bind scalar requires static param `{binding.paramName}`" }
    else
      .ok (storePackedU64 state s!"and({codeLoadExpr dataPtr}, {u64Mask})")
  | .stringLength | .bytesLength =>
    if param.abiType != "string" && param.abiType != "bytes" then
      .error { message := s!"constructor_bind length requires string/bytes param `{binding.paramName}`" }
    else if state.type != ValueType.u64 then
      .error { message := s!"constructor_bind length target `{binding.stateId}` must be .u64" }
    else
      .ok (storePackedU64 state s!"and({codeLoadExpr dataPtr}, {u64Mask})")
  | .stringKeccak | .bytesKeccak =>
    if param.abiType != "string" && param.abiType != "bytes" then
      .error { message := s!"constructor_bind keccak requires string/bytes param `{binding.paramName}`" }
    else if state.type != ValueType.hash then
      .error { message := s!"constructor_bind keccak target `{binding.stateId}` must be .hash" }
    else
      let hashStore :=
        "{\n      let __pf_len := " ++ codeLoadExpr dataPtr ++
        "\n      codecopy(64, add(" ++ dataPtr ++ ", 32), __pf_len)\n      " ++
        storeFullWord state "keccak256(64, __pf_len)" ++ "\n    }"
      .ok hashStore
  | .arrayLength =>
    if param.abiType != "uint256[]" then
      .error { message := s!"constructor_bind array_length requires uint256[] param `{binding.paramName}`" }
    else if state.type != ValueType.u64 then
      .error { message := s!"constructor_bind array_length target `{binding.stateId}` must be .u64" }
    else
      .ok (storePackedU64 state s!"and({codeLoadExpr dataPtr}, {u64Mask})")
  | .arraySumU64 =>
    if param.abiType != "uint256[]" then
      .error { message := s!"constructor_bind array_sum requires uint256[] param `{binding.paramName}`" }
    else if state.type != ValueType.u64 then
      .error { message := s!"constructor_bind array_sum target `{binding.stateId}` must be .u64" }
    else
      let arrPtr := dataPtr
      let elemOff := s!"add({arrPtr}, add(32, mul(__pf_arr_i, 32)))"
      let store := storePackedU64 state "__pf_arr_sum"
      .ok ("{\n  let __pf_arr_count := and(" ++ codeLoadExpr arrPtr ++ ", " ++ u64Mask ++ ")\n  let __pf_arr_sum := 0\n  for { let __pf_arr_i := 0 } lt(__pf_arr_i, __pf_arr_count) { __pf_arr_i := add(__pf_arr_i, 1) } {\n    let __pf_arr_elem := " ++ codeLoadExpr elemOff ++ "\n    __pf_arr_sum := add(__pf_arr_sum, and(__pf_arr_elem, " ++ u64Mask ++ "))\n  }\n  " ++ store ++ "\n}")

def genInitBody
    (params : Array EvmConstructorParam)
    (layout : StorageLayout)
    (bindings : Array EvmConstructorInitBinding) : Except InitError String := do
  let mut lines : Array String := #[]
  for binding in bindings do
    let line ← genBindingInit params layout binding
    lines := lines.push line
  .ok (String.intercalate "\n    " lines.toList)

def renderDeployObject
    (moduleName : String)
    (module : Module)
    (params : Array EvmConstructorParam)
    (bindings : Array EvmConstructorInitBinding)
    (runtimeBytecodeHex : String)
    (constructorArgsByteLen : Nat) : Except InitError String := do
  if bindings.isEmpty then
    .error { message := "renderDeployObject requires at least one constructor_bind" }
  let layout := storageLayout module
  let initBody ← genInitBody params layout bindings
  let runtime := stripHexPrefix runtimeBytecodeHex
  if runtime.isEmpty then
    .error { message := "runtime bytecode must be non-empty for deploy object generation" }
  .ok ("object \"" ++ moduleName ++ "_deploy\" {\n  code {\n    function __pf_code_load(off) -> w {\n      codecopy(0, off, 32)\n      w := mload(0)\n    }\n    let __pf_args_size := " ++ toString constructorArgsByteLen ++
    "\n    let __pf_args_off := sub(codesize(), __pf_args_size)\n    " ++ initBody ++
    "\n    let __pf_rt_off := dataoffset(\"runtime\")\n    let __pf_rt_size := datasize(\"runtime\")\n    codecopy(0, __pf_rt_off, __pf_rt_size)\n    return(0, __pf_rt_size)\n  }\n  data \"runtime\" hex\"" ++ runtime ++ "\"\n}")

def shouldUseDeployObject
    (bindings : Array EvmConstructorInitBinding) (constructorArgsHex : String) : Bool :=
  !bindings.isEmpty && !constructorArgsHex.isEmpty

end ProofForge.Backend.Evm.ConstructorInit
