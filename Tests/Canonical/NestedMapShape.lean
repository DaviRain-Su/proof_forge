import ProofForge.IR.Core
import ProofForge.IR.Canonical
import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Backend.Stylus.RustSdk.Render
import ProofForge.Backend.Stylus.Package
import ProofForge.Compiler.Wasm.Printer

open ProofForge.IR.Core
open ProofForge.IR.Core.Semantics

def nestedModule : Module := {
  name := "NestedMapShape"
  state := #[{ id := ⟨0⟩, shape := .mapN #[.address, .address] .u128 (some 64) }]
  functions := #[{
    id := ⟨0⟩
    params := #[{ id := ⟨0⟩, type := .address }, { id := ⟨1⟩, type := .address }]
    retType := .u128
    entry := ⟨0⟩
    blocks := #[{
      id := ⟨0⟩
      instructions := #[{
        results := #[{ id := ⟨2⟩, type := .u128 }]
        op := .storageLoad {
          root := ⟨0⟩
          path := #[.mapKey { id := ⟨0⟩, type := .address },
            .mapKey { id := ⟨1⟩, type := .address }]
          resultType := .u128
        }
      }]
      terminator := .return #[{ id := ⟨2⟩, type := .u128 }]
    }]
  }, {
    id := ⟨1⟩
    params := #[{ id := ⟨3⟩, type := .address }, { id := ⟨4⟩, type := .address },
      { id := ⟨5⟩, type := .u128 }]
    retType := .unit
    entry := ⟨1⟩
    blocks := #[{
      id := ⟨1⟩
      instructions := #[{
        results := #[]
        op := .storageStore {
          root := ⟨0⟩
          path := #[.mapKey { id := ⟨3⟩, type := .address },
            .mapKey { id := ⟨4⟩, type := .address }]
          resultType := .u128
        } { id := ⟨5⟩, type := .u128 }
      }]
      terminator := .return #[]
    }]
  }]
}

def nestedContractBase : ProofForge.IR.Canonical.CanonicalContract := {
  schemaVersion := ProofForge.IR.Canonical.canonicalSchemaVersion
  module := nestedModule
  interface := {
    contractName := "NestedMapShape"
    entrypoints := #[
      { functionId := ⟨0⟩, name := "allowance", mutability := .view,
        selector? := some "dd62ed3e",
        params := #[{ valueId := ⟨0⟩, name := "owner", type := .address },
          { valueId := ⟨1⟩, name := "spender", type := .address }], retType := .u128 },
      { functionId := ⟨1⟩, name := "approve", mutability := .call,
        selector? := some "095ea7b3",
        params := #[{ valueId := ⟨3⟩, name := "owner", type := .address },
          { valueId := ⟨4⟩, name := "spender", type := .address },
          { valueId := ⟨5⟩, name := "value", type := .u128 }], retType := .unit }
    ]
  }
  materialization := { stateSymbols := #[{ stateId := ⟨0⟩, name := "allowances" }] }
  requirements := #[]
}

def nestedContract : ProofForge.IR.Canonical.CanonicalContract := {
  nestedContractBase with
  requirements := ProofForge.IR.Canonical.deriveCapabilityRequirements
    nestedContractBase.module nestedContractBase.materialization
}

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def expectInvalid (module : Module) : IO Unit :=
  match Validate.checkStateShapeReferences module with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError "invalid nested map path was accepted"

def main : IO Unit := do
  match Validate.checkStateShapeReferences nestedModule with
  | .ok () => pure ()
  | .error error => throw <| IO.userError s!"valid nested map rejected: {repr error}"
  let some function := nestedModule.functions[0]? | throw <| IO.userError "fixture function missing"
  let some block := function.blocks[0]? | throw <| IO.userError "fixture block missing"
  let some instruction := block.instructions[0]? | throw <| IO.userError "fixture instruction missing"
  let shortPath := { instruction with op := .storageLoad {
    root := ⟨0⟩, path := #[.mapKey { id := ⟨0⟩, type := .address }], resultType := .u128 } }
  expectInvalid { nestedModule with functions := #[{ function with
    blocks := #[{ block with instructions := #[shortPath] }] }] }
  let wrongKey := { instruction with op := .storageLoad {
    root := ⟨0⟩, path := #[.mapKey { id := ⟨0⟩, type := .address },
      .mapKey { id := ⟨1⟩, type := .u64 }], resultType := .u128 } }
  expectInvalid { nestedModule with functions := #[{ function with
    blocks := #[{ block with instructions := #[wrongKey] }] }] }
  let env : Env := Std.HashMap.ofList [
    (⟨0⟩, .address "0x1111111111111111111111111111111111111111"),
    (⟨1⟩, .address "0x2222222222222222222222222222222222222222")]
  let path : StorageRef := {
    root := ⟨0⟩
    path := #[.mapKey { id := ⟨0⟩, type := .address },
      .mapKey { id := ⟨1⟩, type := .address }]
    resultType := .u128
  }
  let emptyState : LogicalState := { storage := fun _ => none }
  let written <- match writePath nestedModule env emptyState path (.u128 (BitVec.ofNat 128 42)) with
    | .ok state => pure state
    | .error error => throw <| IO.userError s!"nested map write failed: {repr error}"
  match readPath nestedModule env written path with
  | .ok (.u128 value) => unless value.toNat == 42 do throw <| IO.userError "nested map value changed"
  | result => throw <| IO.userError s!"nested map read failed: {repr result}"
  let otherEnv := env.insert ⟨1⟩ (.address "0x3333333333333333333333333333333333333333")
  match readPath nestedModule otherEnv written path with
  | .ok (.u128 value) => unless value.toNat == 0 do throw <| IO.userError "nested map keys were not isolated"
  | result => throw <| IO.userError s!"nested map isolation read failed: {repr result}"
  let checked <- match ProofForge.IR.Canonical.validateCanonical nestedContract with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"nested canonical validation failed: {repr error}"
  let capabilityPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-arbitrum-stylus", calls := checked.contract.requirements }
  let plan <- match ProofForge.Backend.Stylus.Plan.Core.buildFromCore checked capabilityPlan with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"nested Stylus plan failed: {error.message}"
  let some word := plan.storage.words[0]? | throw <| IO.userError "nested Stylus word missing"
  unless word.keyTypes == #[.address, .address] do
    throw <| IO.userError s!"nested Stylus key types changed: {repr word.keyTypes}"
  let crate <- match ProofForge.Backend.Stylus.RustSdk.renderCrate plan with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"nested Rust rendering failed: {error.message}"
  let some rust := crate.find? "src/lib.rs" | throw <| IO.userError "nested Rust source missing"
  require (rust.contains "StorageMap<Address, StorageMap<Address, StorageU128>> allowances;")
    "nested Rust storage type changed"
  require (rust.contains "self.allowances.get(v0).get(v1).to::<u128>()")
    "nested Rust read path changed"
  require (rust.contains "self.allowances.setter(v3).insert(v4, U128::from(v5));")
    "nested Rust write path changed"
  let direct <- match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan plan with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"nested direct lowering failed: {error.message}"
  let wat := ProofForge.Compiler.Wasm.Printer.render direct
  require ((wat.splitOn "call $native_keccak256").length >= 5)
    "nested direct lowering must derive both keys for reads and writes"
  IO.FS.createDirAll "build/stylus/nested-map"
  IO.FS.writeFile "build/stylus/nested-map/nested.wat" wat
  let cratePath := System.FilePath.mk "build/stylus/nested-map/rust"
  if ← cratePath.pathExists then IO.FS.removeDirAll cratePath
  match ← ProofForge.Backend.Stylus.writeCrateAtomic crate cratePath with
  | .ok () => pure ()
  | .error error => throw <| IO.userError error.message
  IO.println "canonical-nested-map-shape: ok"
