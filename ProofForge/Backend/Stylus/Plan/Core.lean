/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Backend.Stylus.Plan
import ProofForge.Backend.Stylus.Validate
import ProofForge.IR.Canonical
import ProofForge.Target.Plan

namespace ProofForge.Backend.Stylus.Plan.Core

open ProofForge.Backend.Stylus
open ProofForge.IR.Core
open ProofForge.IR.Canonical
open ProofForge.Target

private def fail (message : String) : Except PlanError α :=
  .error { message }

def coreTypeToAbi : CoreType -> Except PlanError StylusAbiType
  | .bool => pure .bool
  | .u8 => pure (.uint 8)
  | .u32 => pure (.uint 32)
  | .u64 => pure (.uint 64)
  | .u128 => pure (.uint 128)
  | .address => pure .address
  | .hash => pure (.fixedBytes 32)
  | .bytes => pure .bytes
  | .string => pure .string
  | .fixedArray elem size => do
      pure (.fixedArray (← coreTypeToAbi elem) size)
  | .array elem | .memoryRef elem => do
      pure (.dynamicArray (← coreTypeToAbi elem))
  | .unit => fail "unit is not a value ABI type"
  | .structType id => fail s!"Core struct type {id.value} needs a resolved Stylus tuple layout"

partial def abiTypeName : StylusAbiType -> String
  | .bool => "bool"
  | .uint bits => s!"uint{bits}"
  | .address => "address"
  | .fixedBytes bytes => s!"bytes{bytes}"
  | .bytes => "bytes"
  | .string => "string"
  | .fixedArray elem size => s!"{abiTypeName elem}[{size}]"
  | .dynamicArray elem => s!"{abiTypeName elem}[]"
  | .tuple fields => s!"({String.intercalate "," (fields.toList.map abiTypeName)})"

private def hexValue? : Char -> Option Nat
  | '0' => some 0 | '1' => some 1 | '2' => some 2 | '3' => some 3
  | '4' => some 4 | '5' => some 5 | '6' => some 6 | '7' => some 7
  | '8' => some 8 | '9' => some 9 | 'a' | 'A' => some 10
  | 'b' | 'B' => some 11 | 'c' | 'C' => some 12 | 'd' | 'D' => some 13
  | 'e' | 'E' => some 14 | 'f' | 'F' => some 15 | _ => none

private partial def parseHexPairs : List Char -> Option StylusBytes
  | [] => some #[]
  | hi :: lo :: rest => do
      let hi <- hexValue? hi
      let lo <- hexValue? lo
      let tail <- parseHexPairs rest
      pure (#[UInt8.ofNat (hi * 16 + lo)] ++ tail)
  | _ => none

private def parseSelector (method : String) (selector : Option String) : Except PlanError StylusBytes := do
  let some selector := selector
    | fail s!"Stylus ABI method `{method}` has no Solidity selector"
  unless selector.length == 8 do
    fail s!"Stylus ABI method `{method}` selector must have eight hex digits"
  let some bytes := parseHexPairs selector.toList
    | fail s!"Stylus ABI method `{method}` has malformed selector `{selector}`"
  pure bytes

private def buildMethod (entrypoint : InterfaceEntrypoint) : Except PlanError StylusAbiMethodPlan := do
  let params <- entrypoint.params.mapM fun param => do
    pure { name := param.name, type := (← coreTypeToAbi param.type) }
  let returns <- match entrypoint.retType with
    | .unit => pure #[]
    | type => pure #[← coreTypeToAbi type]
  let paramNames := params.toList.map (fun param => abiTypeName param.type)
  pure {
    name := entrypoint.name
    canonicalSignature := s!"{entrypoint.name}({String.intercalate "," paramNames})"
    selector := ← parseSelector entrypoint.name entrypoint.selector?
    params
    returns
  }

private def slotBytes (slot : Nat) : StylusBytes :=
  (List.range 32).toArray.map fun index =>
    UInt8.ofNat ((slot / (2 ^ (8 * (31 - index)))) % 256)

private def stateSymbol (contract : CanonicalContract) (id : StateId) : Except PlanError String :=
  match contract.materialization.stateSymbols.find? (fun symbol => symbol.stateId == id) with
  | some symbol => pure symbol.name
  | none => fail s!"Stylus plan is missing state symbol {id.value}"

private def buildStorage (contract : CanonicalContract) : Except PlanError StylusStoragePlan := do
  let mut words := #[]
  let mut index := 0
  for state in contract.module.state do
    let type <- match state.shape with
      | .scalar type => coreTypeToAbi type
      | .map .. => fail "Stylus mapping storage is scheduled for the Token slice"
      | .fixedArray .. | .dynamicArray .. | .record .. =>
          fail "Stylus aggregate storage is scheduled for the aggregate slice"
    words := words.push {
      id := ← stateSymbol contract state.id
      slot := .literal (slotBytes index)
      type
      byteWidth := match type with
        | .bool => 1 | .uint bits => bits / 8 | .address => 20 | .fixedBytes n => n
        | _ => 32
    }
    index := index + 1
  pure { words }

private def contextHostOp : ContextField -> Option StylusHostOp
  | .sender => some .msgSender | .value => some .msgValue
  | .blockNumber => some .blockNumber | .blockTimestamp => some .blockTimestamp
  | .origin => some .txOrigin | .gas => some .gasLeft
  | .contractAddress => some .contractAddress
  | .epochHeight | .randomSeed => none

private def instructionHostOps (instruction : Instruction) : Except PlanError (Array StylusHostOp) :=
  match instruction.op with
  | .storageLoad .. | .storageContains .. => pure #[.storageLoad]
  | .storageStore .. => pure #[.storageCache]
  | .contextRead field => match contextHostOp field with
      | some op => pure #[op]
      | none => fail s!"Stylus plan has no context HostIO handler for `{repr field}`"
  | .emit .. => pure #[.emitLog]
  | .crosscall spec .. => match spec.mode with
      | .invoke => pure #[.callContract]
      | .staticInvoke => pure #[.staticCallContract]
      | .delegateInvoke => pure #[.delegateCallContract]
      | .nearPoolInvoke | .nearPromiseThen =>
          fail "Stylus plan rejects NEAR promise crosscall modes"
  | .pure (.hash ..) | .pure (.hashTwoToOne ..) => pure #[.keccak256]
  | .hostCall call => fail s!"Stylus plan has no handler for HostOp `{call.id.render}`"
  | _ => pure #[]

private def collectFunctionHostOps (functionName : String) (function : Function) :
    Except PlanError (Array StylusHostOpPlan) := do
  let mut operations := #[]
  for block in function.blocks do
    for instruction in block.instructions do
      operations := operations ++ (← instructionHostOps instruction)
  let finalOperations :=
    if operations.contains .storageCache then operations.push .storageFlush else operations
  pure <| finalOperations.mapIdx fun index operation => {
    id := s!"{functionName}.host.{index}"
    functionId := functionName
    operation
  }

private def buildFunctions (contract : CanonicalContract) : Except PlanError (Array StylusFunctionPlan) :=
  contract.interface.entrypoints.mapM fun entrypoint => do
    let some function := contract.module.functions.find? (fun fn => fn.id == entrypoint.functionId)
      | fail s!"Stylus interface method `{entrypoint.name}` has no Core function"
    pure {
      id := entrypoint.name
      abiMethod := entrypoint.name
      entryBlock := function.entry.value
      blockIds := function.blocks.map (fun block => block.id.value)
    }

def buildFromCore (checked : CheckedCanonicalContract) (capPlan : CapabilityPlan) :
    Except PlanError StylusPlan := do
  unless capPlan.targetId == "wasm-arbitrum-stylus" do
    fail s!"Stylus buildFromCore received wrong target `{capPlan.targetId}`"
  let contract := checked.contract
  unless capPlan.calls == contract.requirements do
    fail "Stylus capability plan does not match canonical requirements"
  let methods <- contract.interface.entrypoints.mapM buildMethod
  let storage <- buildStorage contract
  let functions <- buildFunctions contract
  let mut hostOps := #[]
  for entrypoint in contract.interface.entrypoints do
    let some function := contract.module.functions.find? (fun fn => fn.id == entrypoint.functionId)
      | fail s!"Stylus interface method `{entrypoint.name}` has no Core function"
    hostOps := hostOps ++ (← collectFunctionHostOps entrypoint.name function)
  let requiresStorageFlush := hostOps.any (fun op => op.operation == .storageFlush)
  let plan : StylusPlan := {
    targetId := capPlan.targetId
    moduleName := contract.module.name
    abi := { methods, errors := #[] }
    storage
    functions
    events := #[]
    calls := #[]
    hostOps
    resources := { maxMemoryPages := 1, requiresStorageFlush }
    artifacts := { solidityAbi := true, typescriptClient := true }
  }
  validatePlan plan
  pure plan

end ProofForge.Backend.Stylus.Plan.Core
