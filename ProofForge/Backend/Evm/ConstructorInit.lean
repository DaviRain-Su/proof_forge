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
  params.zipIdx.toList.find? (fun (param, _idx) => param.name == name) |>.map (fun (param, idx) => (idx, param))

def findStorageState (layout : StorageLayout) (stateId : String) : Option StorageStatePlan :=
  layout.states.find? (fun state => state.id == stateId)

def u64Mask : String := "18446744073709551615"

def addressMask : String :=
  "1461501637330902918203684832716283019655932542975"

def eip1967ImplementationStateId : String := "$eip1967.implementation"

def eip1967ImplementationSlot : String :=
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"

def atomicUupsConstructorParams : Array EvmConstructorParam := #[
  { name := "implementation", abiType := "address" },
  { name := "admin", abiType := "address" }
]

def atomicUupsConstructorBindings : Array EvmConstructorInitBinding := #[
  {
    stateId := eip1967ImplementationStateId
    paramName := "implementation"
    kind := .addressWord
  },
  {
    stateId := "owner"
    paramName := "admin"
    kind := .addressKeccak
  }
]

/-- A UUPS dispatcher is deployable only through the single audited atomic
constructor shape. This gate is shared by source rendering and artifact paths
so custom UUPS modules cannot silently fall back to ordinary slot-zero initcode. -/
def validateAtomicUupsConstructor
    (module : Module)
    (params : Array EvmConstructorParam)
    (bindings : Array EvmConstructorInitBinding)
    (constructorArgsHex : String) : Except InitError Unit := do
  if module.proxyPattern? != some "uups" then
    return
  if !(params == atomicUupsConstructorParams) then
    .error {
      message :=
        "UUPS proxy requires exact atomic constructor params `implementation:address, admin:address`"
    }
  if !(bindings == atomicUupsConstructorBindings) then
    .error {
      message :=
        "UUPS proxy requires exact atomic constructor bindings for ERC-1967 implementation and hashed owner"
    }
  let some ownerState := module.state.find? (fun state => state.id == "owner")
    | .error { message := "UUPS proxy requires exact atomic constructor bindings and a scalar Hash `owner` state" }
  if ownerState.kind != .scalar || ownerState.type != .hash then
    .error { message := "UUPS proxy requires exact atomic constructor bindings and a scalar Hash `owner` state" }
  let some implementationState :=
      module.state.find? (fun state => state.id == eip1967ImplementationStateId)
    | .error { message := "UUPS proxy requires exact atomic constructor bindings and the ERC-1967 implementation state" }
  if implementationState.kind != .scalar then
    .error { message := "UUPS proxy requires exact atomic constructor bindings and the ERC-1967 implementation state" }
  if !module.entrypoints.isEmpty then
    .error {
      message :=
        "UUPS proxy runtime must expose no entrypoints; initialize all transport state through atomic constructor bindings"
    }
  let args := stripHexPrefix (trimAscii constructorArgsHex)
  if args.isEmpty then
    .error {
      message :=
        "UUPS proxy deployment requires constructor arguments for atomic implementation and admin initialization"
    }
  if args.length != 128 then
    .error { message := "UUPS proxy deployment requires exactly two 32-byte constructor arguments" }

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
  let shift := state.byteOffset * 8
  let mask := (1 <<< (8 * state.byteWidth)) - 1
  if state.byteWidth >= 32 || (state.byteOffset == 0 && state.byteWidth == 32) then
    s!"sstore({state.slot}, {valueExpr})"
  else
    s!"sstore({state.slot}, or(and(sload({state.slot}), not(shl({shift}, {mask}))), shl({shift}, and({valueExpr}, {mask}))))"

def storeFullWord (state : StorageStatePlan) (valueExpr : String) : String :=
  s!"sstore({state.slot}, {valueExpr})"

def storeFullWordForState
    (stateId : String) (state : StorageStatePlan) (valueExpr : String) : String :=
  if stateId == eip1967ImplementationStateId then
    s!"sstore({eip1967ImplementationSlot}, {valueExpr})"
  else
    storeFullWord state valueExpr

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
  | .addressWord =>
    if param.abiType != "address" then
      .error { message := s!"constructor_bind address_word requires address param `{binding.paramName}`" }
    else if binding.stateId != eip1967ImplementationStateId &&
        state.type != ValueType.address && state.type != ValueType.hash then
      .error { message := s!"constructor_bind address_word target `{binding.stateId}` must be .address or .hash" }
    else
      let value := codeLoadExpr dataPtr
      let implementationCodeGuard :=
        if binding.stateId == eip1967ImplementationStateId then
          "\n      if iszero(extcodesize(__pf_address)) { revert(0, 0) }"
        else
          ""
      .ok ("{\n      let __pf_address := " ++ value ++
        "\n      if iszero(__pf_address) { revert(0, 0) }" ++
        "\n      if gt(__pf_address, " ++ addressMask ++ ") { revert(0, 0) }" ++
        implementationCodeGuard ++ "\n      " ++
        storeFullWordForState binding.stateId state "__pf_address" ++ "\n    }")
  | .addressKeccak =>
    if param.abiType != "address" then
      .error { message := s!"constructor_bind address_keccak requires address param `{binding.paramName}`" }
    else if state.type != ValueType.hash then
      .error { message := s!"constructor_bind address_keccak target `{binding.stateId}` must be .hash" }
    else
      let value := codeLoadExpr dataPtr
      .ok ("{\n      let __pf_address := " ++ value ++
        "\n      if iszero(__pf_address) { revert(0, 0) }" ++
        "\n      if gt(__pf_address, " ++ addressMask ++ ") { revert(0, 0) }" ++
        "\n      mstore(0, __pf_address)\n      " ++
        storeFullWord state "keccak256(0, 32)" ++ "\n    }")
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
