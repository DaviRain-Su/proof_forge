import ProofForge.Frontend.Authored

namespace ProofForge.Tests.Canonical.AuthoredStorageLifecycle

open ProofForge.Frontend.Authored
open ProofForge.Frontend.Authored.Canonicalize
open ProofForge.IR.Core

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def contract : AuthoredContract := {
  name := "StorageLifecycle"
  structs := #[{
    name := "Profile"
    fields := #[{ name := "quota", type := .u64 }]
  }]
  state := #[
    { name := "balances", kind := .map .address .u128 (some 32) },
    { name := "allowances", kind := .mapN #[.address, .address] .u128 (some 32) },
    { name := "slots", kind := .dynamicArray .u64 },
    { name := "profile", kind := .record "Profile" }
  ]
  events := #[]
  errors := #[]
  entrypoints := #[{
    name := "update"
    kind := .function
    mutability := .call
    params := #[
      { name := "owner", type := .address },
      { name := "spender", type := .address },
      { name := "index", type := .u64 },
      { name := "amount", type := .u128 }
    ]
    retType := .unit
    body := #[
      .storageStore "balances" #[.mapKey (.local "owner")] (.local "amount"),
      .bind "present" .bool
        (.storageContains "balances" #[.mapKey (.local "owner")]),
      .storageStore "allowances"
        #[.mapKey (.local "owner"), .mapKey (.local "spender")] (.local "amount"),
      .bind "allowance" .u128 (.storageLoad "allowances"
        #[.mapKey (.local "owner"), .mapKey (.local "spender")]),
      .storageRemove "balances" #[.mapKey (.local "owner")],
      .storageResize "slots" (.literal (.u64Lit 4)),
      .storageStore "slots" #[.index (.local "index")] (.literal (.u64Lit 7)),
      .bind "slotCount" .u64 (.storageLength "slots"),
      .storageStore "profile" #[.field "quota"] (.literal (.u64Lit 9)),
      .bind "buffer" (.memoryRef .u64)
        (.memoryAlloc .u64 (.literal (.u64Lit 2))),
      .memoryStore (.local "buffer") (.literal (.u64Lit 0)) (.local "slotCount"),
      .memoryRelease (.local "buffer"),
      .returnUnit
    ]
  }]
  constructorParams := #[]
  constructorBindings := #[]
}

def badKeyContract : AuthoredContract := {
  contract with
  name := "BadStorageKey"
  entrypoints := #[{
    name := "bad"
    kind := .function
    mutability := .view
    params := #[]
    retType := .u128
    body := #[.returnExpr (.storageLoad "balances"
      #[.mapKey (.literal (.u64Lit 1))])]
  }]
}

def run : IO Unit := do
  let bundle ← match normalizeAuthored contract with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"normalization failed: {repr error}"
  let function ← match bundle.contract.contract.module.functions[0]? with
    | some function => pure function
    | none => throw <| IO.userError "missing update function"
  let operations := function.blocks.flatMap (·.instructions) |>.map (·.op)
  require (operations.any fun op => match op with
    | .storageContains { path := #[.mapKey _], .. } => true | _ => false)
    "map presence path was not preserved"
  require (operations.any fun op => match op with
    | .storageStore { path := #[.mapKey _, .mapKey _], .. } _ => true | _ => false)
    "nested-map path was not preserved"
  require (operations.any fun op => match op with
    | .storageLoad { path := #[.mapKey _, .mapKey _], resultType := .u128, .. } => true
    | _ => false)
    "nested-map load was not preserved"
  require (operations.any fun op => match op with
    | .storageStore { path := #[.field ⟨0⟩], resultType := .u64, .. } _ => true | _ => false)
    "record-field path was not resolved"
  require (operations.any fun op => match op with | .storageRemove _ => true | _ => false)
    "storage remove was not emitted"
  require (operations.any fun op => match op with | .storageResize _ _ => true | _ => false)
    "storage resize was not emitted"
  require (operations.any fun op => match op with | .memoryAlloc _ _ => true | _ => false)
    "memory allocation was not emitted"
  require (operations.any fun op => match op with | .memoryStore _ _ _ => true | _ => false)
    "memory store was not emitted"
  require (operations.any fun op => match op with | .memoryRelease _ => true | _ => false)
    "memory release was not emitted"
  match normalizeAuthored badKeyContract with
  | .ok _ => throw <| IO.userError "wrong map-key type was accepted"
  | .error _ => pure ()
  IO.println "authored-storage-lifecycle: ok"

end ProofForge.Tests.Canonical.AuthoredStorageLifecycle

def main : IO Unit :=
  ProofForge.Tests.Canonical.AuthoredStorageLifecycle.run
