/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Backend.Stylus.Plan
import ProofForge.Backend.Stylus.Validate
import ProofForge.IR.Canonical
import ProofForge.Target.Plan
import ProofForge.Target.ProtocolMaterialize

namespace ProofForge.Backend.Stylus.Plan.Core

open ProofForge.Backend.Stylus
open ProofForge.IR.Core
open ProofForge.IR.Canonical
open ProofForge.Target

private def fail (message : String) : Except PlanError α :=
  .error { message }

private def dynamicStorageMaxBytes : Nat := 256
private def dynamicStorageMaxElements : Nat := 8

private def stateFor (contract : CanonicalContract) (id : StateId) : Except PlanError StateDecl :=
  match contract.module.state.find? (fun state => state.id == id) with
  | some state => pure state
  | none => fail s!"Stylus storage path references missing state {id.value}"

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

def functionReadsValue (function : Function) : Bool :=
  function.blocks.any fun block => block.instructions.any fun instruction =>
    match instruction.op with | .contextRead .value => true | _ => false

private def buildMethod (entrypoint : InterfaceEntrypoint) (function : Function) : Except PlanError StylusAbiMethodPlan := do
  let params <- entrypoint.params.mapM fun param => do
    pure { name := param.name, type := (← coreTypeToAbi param.type) }
  let returns <- match entrypoint.retType with
    | .unit => pure #[]
    | type => pure #[← coreTypeToAbi type]
  let paramNames := (entrypoint.params.zip params).toList.map fun (source, param) =>
    source.abiWord?.getD (abiTypeName param.type)
  pure {
    name := entrypoint.name
    canonicalSignature := s!"{entrypoint.name}({String.intercalate "," paramNames})"
    selector := ← parseSelector entrypoint.name entrypoint.selector?
    params
    returns
    payable := functionReadsValue function
    mutability := match entrypoint.mutability with
      | .call => .call
      | .view => .view
  }

private def slotBytes (slot : Nat) : StylusBytes :=
  (List.range 32).toArray.map fun index =>
    UInt8.ofNat ((slot / (2 ^ (8 * (31 - index)))) % 256)

private def stateSymbol (contract : CanonicalContract) (id : StateId) : Except PlanError String :=
  match contract.materialization.stateSymbols.find? (fun symbol => symbol.stateId == id) with
  | some symbol => pure symbol.name
  | none => fail s!"Stylus plan is missing state symbol {id.value}"

private def resultId (instruction : Instruction) : Except PlanError StylusValueId :=
  match instruction.results with
  | #[result] => pure result.id.value
  | _ => fail "Stylus operation expected exactly one SSA result"

private def literalPlan : CoreLiteral -> Except PlanError (StylusAbiType × StylusLiteralPlan)
  | .boolLit value => pure (.bool, .bool value)
  | .u8Lit value => pure (.uint 8, .uint value)
  | .u32Lit value => pure (.uint 32, .uint value)
  | .u64Lit value => pure (.uint 64, .uint value)
  | .u128Lit value => pure (.uint 128, .uint value)
  | .addressLit value => pure (.address, .address value)
  | .hashLit value => pure (.fixedBytes 32, .fixedBytes value.toUTF8.data)
  | .unitLit => fail "Stylus unit literal cannot bind an SSA value"
  | .bytesLit value => pure (.bytes, .bytes value.data)
  | .stringLit value => pure (.string, .string value)

private inductive CrosscallLiteralRole where
  | target
  | method

private def crosscallLiteralRole? (function : Function) (id : ValueId) :
    Option CrosscallLiteralRole :=
  function.blocks.findSome? fun block =>
    block.instructions.findSome? fun instruction => match instruction.op with
      | .crosscall spec _ =>
          if spec.target.id == id then some .target
          else if spec.method.id == id then some .method
          else none
      | _ => none

private def poolEntryForLiteral? (contract : CanonicalContract) : CoreLiteral -> Option String
  | .addressLit value => do
      let index <- value.toNat?
      contract.materialization.crosscallStrings[index]?
  | .stringLit value => do
      let index <- value.toNat?
      contract.materialization.crosscallStrings[index]?
  | _ => none

private def contextHostOp : ContextField -> Option StylusHostOp
  | .sender => some .msgSender | .value => some .msgValue
  | .blockNumber => some .blockNumber | .blockTimestamp => some .blockTimestamp
  | .origin => some .txOrigin | .gas => some .gasLeft
  | .contractAddress => some .contractAddress
  | .epochHeight | .randomSeed | .accountId => none

private def instructionPlan (contract : CanonicalContract) (function : Function)
    (instruction : Instruction) :
    Except PlanError StylusOpPlan :=
  match instruction.op with
  | .pure (.literal literal) => do
      let result <- resultId instruction
      match crosscallLiteralRole? function { value := result } with
      | some .target => match poolEntryForLiteral? contract literal with
        | some host =>
            let some address := ProofForge.Target.ProtocolMaterialize.parseEvmAddressHex? host
              | fail s!"Stylus crosscall target `{host}` is not an address; bind the logical peer with --peer logical=0x..."
            pure (.literal result .address (.address (toString address)))
        | none =>
            let (type, value) <- literalPlan literal
            pure (.literal result type value)
      | some .method => match poolEntryForLiteral? contract literal with
        | some method => pure (.literal result .string (.string method))
        | none =>
            let (type, value) <- literalPlan literal
            pure (.literal result type value)
      | none =>
        let (type, value) <- literalPlan literal
        pure (.literal result type value)
  | .pure (.cast target value) => do
      pure (.cast (← resultId instruction) (← coreTypeToAbi value.type)
        (← coreTypeToAbi target) value.id.value)
  | .pure (.arithmetic operation mode lhs rhs) => do
      let type <- match instruction.results with
        | #[result] => coreTypeToAbi result.type
        | _ => fail "Stylus add expected exactly one SSA result"
      let mode := match mode with
        | .wrapping => StylusOverflowMode.wrapping
        | .checked => StylusOverflowMode.checked
      let result <- resultId instruction
      match operation with
      | .add => pure (.add result type mode lhs.id.value rhs.id.value)
      | .sub => pure (.sub result type mode lhs.id.value rhs.id.value)
      | .mul => pure (.mul result type mode lhs.id.value rhs.id.value)
      | .div => pure (.div result type mode lhs.id.value rhs.id.value)
      | operation => fail s!"Stylus arithmetic `{repr operation}` is not implemented"
  | .storageLoad path => do
      let state <- stateFor contract path.root
      let wordId <- stateSymbol contract path.root
      if path.path.isEmpty then
        match state.shape with
        | .scalar .bytes | .scalar .string =>
            return .storageDynamicLoad (← resultId instruction) wordId dynamicStorageMaxBytes
        | .dynamicArray _ =>
            return .storageArrayLoad (← resultId instruction) wordId dynamicStorageMaxElements
        | _ => pure ()
      let keys := path.path.filterMap fun segment => match segment with
        | .mapKey key => some key.id.value | _ => none
      unless keys.size == path.path.size do fail "Stylus storage paths support map keys only"
      if keys.isEmpty then pure (.storageLoad (← resultId instruction) wordId)
      else pure (.storagePathLoad (← resultId instruction) wordId keys)
  | .storageStore path value => do
      let state <- stateFor contract path.root
      let wordId <- stateSymbol contract path.root
      if path.path.isEmpty then
        match state.shape with
        | .scalar .bytes | .scalar .string =>
            return .storageDynamicCache wordId value.id.value dynamicStorageMaxBytes
        | .dynamicArray _ =>
            return .storageArrayCache wordId value.id.value dynamicStorageMaxElements
        | _ => pure ()
      let keys := path.path.filterMap fun segment => match segment with
        | .mapKey key => some key.id.value | _ => none
      unless keys.size == path.path.size do fail "Stylus storage paths support map keys only"
      if keys.isEmpty then pure (.storageCache wordId value.id.value)
      else pure (.storagePathCache wordId keys value.id.value)
  | .contextRead field => do
      let operation <- match contextHostOp field with
        | some operation => pure operation
        | none => fail s!"Stylus plan has no context handler for `{repr field}`"
      let type <- match instruction.results with
        | #[result] => coreTypeToAbi result.type
        | _ => fail "Stylus context read expected exactly one SSA result"
      pure (.contextRead (← resultId instruction) type operation)
  | .pure (.compare op lhs rhs) => do
      let operation := match op with
        | .eq => StylusCompareOp.eq | .ne => .ne | .lt => .lt
        | .le => .le | .gt => .gt | .ge => .ge
      pure (.compare (← resultId instruction) (← coreTypeToAbi lhs.type) operation lhs.id.value rhs.id.value)
  | .assert condition error =>
      let message := (contract.interface.errors.find? (fun item => item.errorId == error.id)).map
        (fun item => item.message) |>.getD s!"error-{error.id.value}"
      pure (.assert_ condition.id.value message)
  | .emit event values => do
      let some declaration := contract.interface.events.find? (fun item => item.eventId == event)
        | fail s!"Stylus emit references missing event {event.value}"
      pure (.emitEvent declaration.name (values.map fun value => value.id.value))
  | .crosscall _ _ => do
      let result <- resultId instruction
      let type <- match instruction.results with
        | #[value] => coreTypeToAbi value.type
        | _ => fail "Stylus crosscall expected exactly one result"
      pure (.call result type s!"call-{result}")
  | op => fail s!"Stylus function lowering has no plan operation for `{repr op}`"

private def terminatorPlan : Terminator -> Except PlanError StylusTerminatorPlan
  | .jump target args _ => do
      unless args.isEmpty do
        fail "Stylus block-argument jumps are not implemented"
      pure (.jump target.value)
  | .branch condition onTrue onFalse =>
      pure (.branch condition.id.value onTrue.value onFalse.value)
  | .return values => pure (.return (values.map fun value => value.id.value))
  | .revert error => pure (.revert s!"error-{error.id.value}")

private def blockPlan (contract : CanonicalContract) (function : Function) (block : Block) :
    Except PlanError StylusBlockPlan := do
  pure {
    id := block.id.value
    operations := ← block.instructions.mapM (instructionPlan contract function)
    terminator := ← terminatorPlan block.terminator
  }

private def buildStorage (contract : CanonicalContract) : Except PlanError StylusStoragePlan := do
  let mut words := #[]
  let mut index := 0
  for state in contract.module.state do
    let type <- match state.shape with
      | .scalar type => coreTypeToAbi type
      | .map _ value _ => coreTypeToAbi value
      | .mapN _ value _ => coreTypeToAbi value
      | .dynamicArray element => pure (.dynamicArray (← coreTypeToAbi element))
      | .fixedArray .. | .record .. =>
          fail "Stylus aggregate storage is scheduled for the aggregate slice"
    let keyTypes <- match state.shape with
      | .map key _ _ => pure #[← coreTypeToAbi key]
      | .mapN keys _ _ => keys.mapM coreTypeToAbi
      | _ => pure #[]
    words := words.push {
      id := ← stateSymbol contract state.id
      slot := .literal (slotBytes index)
      type
      keyTypes
      byteWidth := match type with
        | .bool => 1 | .uint bits => bits / 8 | .address => 20 | .fixedBytes n => n
        | _ => 32
    }
    index := index + 1
  pure { words }

private def instructionHostOps (contract : CanonicalContract) (instruction : Instruction) :
    Except PlanError (Array StylusHostOp) := do
  match instruction.op with
  | .storageLoad path | .storageContains path =>
      let state <- stateFor contract path.root
      pure <| if path.path.isEmpty then
        match state.shape with
        | .scalar .bytes | .scalar .string | .dynamicArray _ => #[.keccak256, .storageLoad]
        | _ => #[.storageLoad]
      else #[.keccak256, .storageLoad]
  | .storageStore path _ =>
      let state <- stateFor contract path.root
      pure <| if path.path.isEmpty then
        match state.shape with
        | .scalar .bytes | .scalar .string | .dynamicArray _ =>
            #[.storageLoad, .keccak256, .storageCache]
        | _ => #[.storageCache]
      else #[.keccak256, .storageCache]
  | .contextRead field => match contextHostOp field with
      | some op => pure #[op]
      | none => fail s!"Stylus plan has no context HostIO handler for `{repr field}`"
  | .emit .. => pure #[.keccak256, .emitLog]
  | .crosscall spec .. => match spec.mode with
      | .invoke => pure #[.keccak256, .storageFlush, .callContract, .readReturnData]
      | .staticInvoke => pure #[.keccak256, .storageFlush, .staticCallContract, .readReturnData]
      | .delegateInvoke => pure #[.keccak256, .storageFlush, .delegateCallContract, .readReturnData]
      | .namedInvoke | .continuation =>
          fail "Stylus plan rejects NEAR promise crosscall modes"
  | .pure (.hash ..) | .pure (.hashTwoToOne ..) => pure #[.keccak256]
  | .hostCall call => fail s!"Stylus plan has no handler for HostOp `{call.id.render}`"
  | _ => pure #[]

private def collectFunctionHostOps (contract : CanonicalContract) (functionName : String) (function : Function) :
    Except PlanError (Array StylusHostOpPlan) := do
  let mut operations := #[]
  for block in function.blocks do
    for instruction in block.instructions do
      operations := operations ++ (← instructionHostOps contract instruction)
  let finalOperations :=
    let operations := if operations.contains .storageCache then operations.push .storageFlush else operations
    operations.push .writeResult
  pure <| finalOperations.mapIdx fun index operation => {
    id := s!"{functionName}.host.{index}"
    functionId := functionName
    operation
    support := { rustSdk := .implemented, directWasm := .implemented }
  }

private def buildFunctions (contract : CanonicalContract) : Except PlanError (Array StylusFunctionPlan) :=
  contract.interface.entrypoints.mapM fun entrypoint => do
    let some function := contract.module.functions.find? (fun fn => fn.id == entrypoint.functionId)
      | fail s!"Stylus interface method `{entrypoint.name}` has no Core function"
    pure {
      id := entrypoint.name
      abiMethod := entrypoint.name
      params := ← entrypoint.params.mapM fun param => do
        let type <- coreTypeToAbi param.type
        pure {
          valueId := param.valueId.value, name := param.name, type
          dynamicMaxLength? := match type with
            | .dynamicArray _ => some dynamicStorageMaxElements
            | _ => if type.isDynamic then some 4096 else none
        }
      entryBlock := function.entry.value
      blocks := ← function.blocks.mapM (blockPlan contract function)
      support := { rustSdk := .implemented, directWasm := .implemented }
    }

private def buildEvents (contract : CanonicalContract) : Except PlanError (Array StylusEventPlan) :=
  contract.interface.events.mapM fun event => do
    let fields <- event.fields.mapM fun field => do
      pure { name := field.name, type := (← coreTypeToAbi field.type), indexed := field.indexed }
    let typeNames := (event.fields.zip fields).toList.map fun (source, field) =>
      source.abiWord?.getD (abiTypeName field.type)
    pure {
      id := event.name
      canonicalSignature := s!"{event.name}({String.intercalate "," typeNames})"
      topic0 := #[]
      fields
      support := { rustSdk := .implemented, directWasm := .implemented }
    }

private def stringLiteralFor (contract : CanonicalContract) (function : Function)
    (id : ValueId) : Except PlanError String := do
  for block in function.blocks do
    for instruction in block.instructions do
      match instruction.results, instruction.op with
      | #[result], .pure (.literal literal) =>
          if result.id == id then
            match poolEntryForLiteral? contract literal, literal with
            | some value, _ => return value
            | none, .stringLit value => return value
            | none, _ => pure ()
      | _, _ => pure ()
  fail s!"Stylus call method value {id.value} must be a canonical string literal"

private def buildCalls (contract : CanonicalContract) : Except PlanError (Array StylusCallPlan) := do
  let mut calls := #[]
  for function in contract.module.functions do
    for block in function.blocks do
      for instruction in block.instructions do
        match instruction.op with
        | .crosscall spec arguments =>
            let result <- resultId instruction
            let mode <- match spec.mode with
              | .invoke => pure StylusCallMode.call
              | .staticInvoke => pure .staticCall
              | .delegateInvoke => pure .delegateCall
              | .namedInvoke | .continuation => fail "Stylus rejects named or continuation crosscall modes"
            let methodName <- stringLiteralFor contract function spec.method.id
            let paramTypes <- spec.paramTypes.mapM coreTypeToAbi
            let returnType <- coreTypeToAbi spec.returnType
            let valueType? <- match spec.value with
              | some value => pure (some (← coreTypeToAbi value.type))
              | none => pure none
            let signature := s!"{methodName}({String.intercalate "," (paramTypes.toList.map abiTypeName)})"
            calls := calls.push {
              id := s!"call-{result}", mode, canonicalSignature := signature,
              target := spec.target.id.value,
              method := spec.method.id.value,
              arguments := arguments.map fun value => value.id.value,
              paramTypes,
              returnType,
              returnMaxLength? := if returnType.isDynamic then some 4096 else none,
              value? := spec.value.map fun value => value.id.value,
              valueType?,
              gas? := spec.gas.map fun value => value.id.value,
              cachePolicy := match mode with
                | .staticCall => .flush
                | .call | .delegateCall => .clear
              support := { rustSdk := .implemented, directWasm := .implemented }
            }
        | _ => pure ()
  pure calls

def buildFromCore (checked : CheckedCanonicalContract) (capPlan : CapabilityPlan) :
    Except PlanError StylusPlan := do
  unless capPlan.targetId == "wasm-arbitrum-stylus" do
    fail s!"Stylus buildFromCore received wrong target `{capPlan.targetId}`"
  let contract := checked.contract
  unless capPlan.calls == contract.requirements do
    fail "Stylus capability plan does not match canonical requirements"
  let methods <- contract.interface.entrypoints.mapM fun entrypoint => do
    let some function := contract.module.functions.find? (fun fn => fn.id == entrypoint.functionId)
      | fail s!"Stylus interface method `{entrypoint.name}` has no Core function"
    buildMethod entrypoint function
  let storage <- buildStorage contract
  let functions <- buildFunctions contract
  let events <- buildEvents contract
  let calls <- buildCalls contract
  let mut hostOps := #[]
  for entrypoint in contract.interface.entrypoints do
    let some function := contract.module.functions.find? (fun fn => fn.id == entrypoint.functionId)
      | fail s!"Stylus interface method `{entrypoint.name}` has no Core function"
    hostOps := hostOps ++ (← collectFunctionHostOps contract entrypoint.name function)
  for method in methods do
    if !method.payable && !hostOps.any (fun op => op.functionId == method.name && op.operation == .msgValue) then
      hostOps := hostOps.push {
        id := s!"{method.name}.host.nonpayable"
        functionId := method.name
        operation := .msgValue
        support := { rustSdk := .implemented, directWasm := .implemented }
      }
  let requiresStorageFlush := hostOps.any (fun op => op.operation == .storageFlush)
  let plan : StylusPlan := {
    targetId := capPlan.targetId
    moduleName := contract.module.name
    abi := { methods, errors := #[] }
    storage
    functions
    events
    calls
    hostOps
    resources := { maxMemoryPages := 1, requiresStorageFlush }
    artifacts := { solidityAbi := true, typescriptClient := true }
  }
  validatePlan plan
  pure plan

end ProofForge.Backend.Stylus.Plan.Core
