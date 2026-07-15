import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Backend.Stylus.Validate
import ProofForge.IR.Examples.Counter
import ProofForge.Frontend.Authored.Normalize
import ProofForge.Contract.Spec

open ProofForge.Backend.Stylus
open ProofForge.IR.Core
open ProofForge.IR.Canonical

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def aggregateState : Array StateDecl := #[
  { id := ⟨0⟩, shape := .scalar .bytes },
  { id := ⟨1⟩, shape := .scalar .string },
  { id := ⟨2⟩, shape := .dynamicArray .u64 }
]

def rootPath (stateId : Nat) (type : CoreType) : StorageRef := {
  root := ⟨stateId⟩
  path := #[]
  resultType := type
}

def aggregateSetter (functionId stateId : Nat) (type : CoreType) : Function := {
  id := ⟨functionId⟩
  params := #[{ id := ⟨0⟩, type }]
  retType := .unit
  blocks := #[{
    id := ⟨0⟩
    instructions := #[{ results := #[], op := .storageStore (rootPath stateId type) { id := ⟨0⟩, type } }]
    terminator := .return #[]
  }]
  entry := ⟨0⟩
}

def aggregateGetter (functionId stateId : Nat) (type : CoreType) : Function := {
  id := ⟨functionId⟩
  params := #[]
  retType := type
  blocks := #[{
    id := ⟨0⟩
    instructions := #[{
      results := #[{ id := ⟨0⟩, type }]
      op := .storageLoad (rootPath stateId type)
    }]
    terminator := .return #[{ id := ⟨0⟩, type }]
  }]
  entry := ⟨0⟩
}

def aggregateFunctions : Array Function := #[
  aggregateSetter 0 0 .bytes,
  aggregateGetter 1 0 .bytes,
  aggregateSetter 2 1 .string,
  aggregateGetter 3 1 .string,
  aggregateSetter 4 2 (.array .u64),
  aggregateGetter 5 2 (.array .u64)
]

def aggregateEntrypoint (functionId : Nat) (name selector : String) (type : CoreType)
    (setter : Bool) : InterfaceEntrypoint := {
  functionId := ⟨functionId⟩
  name
  mutability := if setter then .call else .view
  selector? := some selector
  params := if setter then #[{ valueId := ⟨0⟩, name := "value", type }] else #[]
  retType := if setter then .unit else type
}

def aggregateInterface : InterfaceContract := {
  contractName := "StylusCanonicalAggregate"
  entrypoints := #[
    aggregateEntrypoint 0 "set_bytes" "10000000" .bytes true,
    aggregateEntrypoint 1 "get_bytes" "10000001" .bytes false,
    aggregateEntrypoint 2 "set_string" "10000002" .string true,
    aggregateEntrypoint 3 "get_string" "10000003" .string false,
    aggregateEntrypoint 4 "set_values" "10000004" (.array .u64) true,
    aggregateEntrypoint 5 "get_values" "10000005" (.array .u64) false
  ]
}

def checkedAggregateContract : Except String CheckedCanonicalContract := do
  let module : ProofForge.IR.Core.Module := {
    name := "StylusCanonicalAggregate"
    state := aggregateState
    functions := aggregateFunctions
  }
  let materialization : MaterializationContract := {
    stateSymbols := #[
      { stateId := ⟨0⟩, name := "payload" },
      { stateId := ⟨1⟩, name := "label" },
      { stateId := ⟨2⟩, name := "values" }
    ]
  }
  let contract : CanonicalContract := {
    schemaVersion := canonicalSchemaVersion
    module
    interface := aggregateInterface
    materialization
    requirements := deriveCapabilityRequirements module materialization
    -- Aggregate fixture uses only Core storage ops; empty catalog is enough.
    hostOpCatalog := .empty
  }
  match validateCanonical contract with
  | .ok checked => pure checked
  | .error error => throw s!"validateCanonical aggregate fixture failed: {repr error}"

def hasDynamicLoad (plan : StylusPlan) : Bool :=
  plan.functions.any fun function => function.blocks.any fun block =>
    block.operations.any fun operation => match operation with
      | .storageDynamicLoad _ _ 256 => true
      | _ => false

def hasDynamicCache (plan : StylusPlan) : Bool :=
  plan.functions.any fun function => function.blocks.any fun block =>
    block.operations.any fun operation => match operation with
      | .storageDynamicCache _ _ 256 => true
      | _ => false

def hasArrayLoad (plan : StylusPlan) : Bool :=
  plan.functions.any fun function => function.blocks.any fun block =>
    block.operations.any fun operation => match operation with
      | .storageArrayLoad _ _ 8 => true
      | _ => false

def hasArrayCache (plan : StylusPlan) : Bool :=
  plan.functions.any fun function => function.blocks.any fun block =>
    block.operations.any fun operation => match operation with
      | .storageArrayCache _ _ 8 => true
      | _ => false

def main : IO Unit := do
  let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  let bundle <- match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec spec with
    | .ok value => pure value
    | .error e => throw <| IO.userError s!"normalizeContractSpec failed: {repr e}"
  let capPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-arbitrum-stylus"
    calls := bundle.contract.contract.requirements
  }
  let plan <- match ProofForge.Backend.Stylus.Plan.Core.buildFromCore bundle.contract capPlan with
    | .ok value => pure value
    | .error e => throw <| IO.userError s!"buildFromCore failed: {e.message}"
  require (plan.targetId == "wasm-arbitrum-stylus") "wrong Stylus target id"
  require (plan.moduleName == "Counter") "wrong module name"
  require (plan.abi.methods.map (fun method => method.name) == #["initialize", "increment", "get"])
    "Counter ABI method order changed"
  require (plan.abi.methods.all (fun method => method.selector.size == 4))
    "Stylus selectors must be four bytes"
  require (plan.storage.words.size == 1) "Counter must own one storage word"
  match plan.storage.words[0]? with
  | some word => require (word.type == .uint 64) "Counter state must remain uint64"
  | none => throw <| IO.userError "Counter storage word missing"
  require (plan.functions.size == 3) "Counter function plans missing"
  require (plan.hostOps.any (fun op => op.operation == .storageLoad)) "storage load HostOp missing"
  require (plan.hostOps.any (fun op => op.operation == .storageCache)) "storage cache HostOp missing"
  require (plan.hostOps.any (fun op => op.operation == .storageFlush)) "storage flush HostOp missing"
  require plan.resources.requiresStorageFlush "mutating Counter must require storage flush"
  match ProofForge.Backend.Stylus.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"validatePlan failed: {e.message}"
  let aggregateContract <- match checkedAggregateContract with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let aggregateCapPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-arbitrum-stylus"
    calls := aggregateContract.contract.requirements
  }
  let aggregatePlan <- match ProofForge.Backend.Stylus.Plan.Core.buildFromCore
      aggregateContract aggregateCapPlan with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"aggregate buildFromCore failed: {error.message}"
  require (aggregatePlan.storage.words.map (fun word => word.type) ==
      #[.bytes, .string, .dynamicArray (.uint 64)])
    "canonical aggregate state types did not reach the Stylus storage plan"
  match aggregatePlan.functions[4]?.bind (fun function => function.params[0]?) with
  | some param =>
      require (param.dynamicMaxLength? == some 8)
        "canonical dynamic-array parameter must use the eight-element carrier bound"
  | none => throw <| IO.userError "canonical dynamic-array setter parameter missing"
  require (hasDynamicLoad aggregatePlan && hasDynamicCache aggregatePlan)
    "canonical bytes/string root storage operations were not lowered"
  require (hasArrayLoad aggregatePlan && hasArrayCache aggregatePlan)
    "canonical dynamic-array root storage operations were not lowered"
  require (aggregatePlan.hostOps.any (fun op => op.operation == .keccak256))
    "canonical aggregate storage must request keccak host IO"
  require aggregatePlan.resources.requiresStorageFlush
    "canonical aggregate setters must request a storage flush"
  match ProofForge.Backend.Stylus.validatePlan aggregatePlan with
  | .ok () => pure ()
  | .error error => throw <| IO.userError s!"aggregate validatePlan failed: {error.message}"
  IO.println "stylus-core-plan: ok"
