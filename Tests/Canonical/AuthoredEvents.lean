import ProofForge.Frontend.Authored

namespace ProofForge.Tests.Canonical.AuthoredEvents

open ProofForge.Frontend.Authored
open ProofForge.Frontend.Authored.Builder
open ProofForge.Frontend.Authored.Canonicalize
open ProofForge.IR.Core

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def transferredFields (amount : AuthoredExpr) : Array AuthoredEventArgument := #[
  { name := "from", indexed := true, abiWord? := some "address", value := .local "sender" },
  { name := "amount", abiWord? := some "uint128", value := amount }
]

def inferredEvent : AuthoredContract := build "InferredEvent" do
  entryFull "transfer" #[
      { name := "sender", type := .address },
      { name := "amount", type := .u128 }
    ] .unit (do
      emitFields "Transferred" (transferredFields (.local "amount"))
      retUnit)
  entryFull "mint" #[
      { name := "sender", type := .address },
      { name := "amount", type := .u128 }
    ] .unit (do
      emitFields "Transferred" (transferredFields (.local "amount"))
      retUnit)

def mismatchedEvent : AuthoredContract := {
  inferredEvent with
  name := "MismatchedEvent"
  entrypoints := inferredEvent.entrypoints.push {
    name := "bad"
    kind := .function
    mutability := .call
    params := #[
      { name := "sender", type := .address },
      { name := "amount", type := .u64 }
    ]
    retType := .unit
    body := #[
      .emitFields "Transferred" (transferredFields (.local "amount")),
      .returnUnit
    ]
  }
}

def explicitEvent : AuthoredContract := {
  inferredEvent with
  name := "ExplicitEvent"
  events := #[{
    name := "Transferred"
    fields := #[
      { name := "from", type := .address, indexed := true, abiWord? := some "address" },
      { name := "amount", type := .u128, indexed := false, abiWord? := some "uint128" }
    ]
  }]
  entrypoints := #[{
    name := "transfer"
    kind := .function
    mutability := .call
    params := #[
      { name := "sender", type := .address },
      { name := "amount", type := .u128 }
    ]
    retType := .unit
    body := #[
      .emit "Transferred" #[.local "sender", .local "amount"],
      .returnUnit
    ]
  }]
}

def run : IO Unit := do
  let bundle ← match normalizeAuthored inferredEvent with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"inferred event normalization failed: {repr error}"
  let canonical := bundle.contract.contract
  require (canonical.module.events.size == 1 && canonical.interface.events.size == 1)
    "inferred event schema was not emitted to Core and Interface"
  let event := canonical.interface.events[0]!
  require (event.name == "Transferred" && event.fields.map (·.name) == #["from", "amount"])
    "inferred event field names were not preserved"
  require (event.fields.map (·.type) == #[.address, .u128] &&
      event.fields.map (·.indexed) == #[true, false])
    "inferred event types or indexing metadata were not preserved"
  require (event.fields.map (·.abiWord?) == #[some "address", some "uint128"])
    "inferred event ABI metadata was not preserved"
  match canonical.module.events[0]? with
  | some coreEvent =>
      require (coreEvent.fields.map (·.type) == #[.address, .u128])
        "inferred event schema disagrees with Core"
  | none => throw <| IO.userError "missing inferred Core event"
  match normalizeAuthored mismatchedEvent with
  | .ok _ => throw <| IO.userError "conflicting event schemas were accepted"
  | .error _ => pure ()
  match normalizeAuthored explicitEvent with
  | .ok bundle =>
      require (bundle.contract.contract.interface.events[0]!.fields.map (·.name) ==
          #["from", "amount"])
        "explicit event compatibility lost field metadata"
  | .error error =>
      throw <| IO.userError s!"explicit event normalization failed: {repr error}"
  IO.println "authored-events: ok"

end ProofForge.Tests.Canonical.AuthoredEvents

def main : IO Unit :=
  ProofForge.Tests.Canonical.AuthoredEvents.run
