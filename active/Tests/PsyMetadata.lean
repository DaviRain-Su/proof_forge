import ProofForge.Backend.Psy.Metadata
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.MapProbe
import ProofForge.IR.Examples.EventProbe
import ProofForge.IR.Examples.ContextProbe

namespace ProofForge.Tests.PsyMetadata

open ProofForge.Backend.Psy.Metadata
open ProofForge.Backend.Psy.Plan (PlanError)
open ProofForge.IR

def requireOk (x : Except PlanError α) (msg : String) : IO α :=
  match x with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{msg}: {PlanError.render e}"

def assertEq [Repr α] [BEq α] (name : String) (expected actual : α) : IO Unit :=
  if expected == actual then
    IO.println s!"ok: {name}"
  else
    throw <| IO.userError s!"fail: {name}\n  expected: {repr expected}\n  actual:   {repr actual}"

def typedEventModule : Module := {
  name := "TypedEventTest"
  state := #[]
  entrypoints := #[
    {
      name := "emit_typed"
      returns := .unit
      body := #[
        .effect (.eventEmit "TypedEvent" #[
          ("count", .literal (.u64 42)),
          ("flag", .literal (.bool true)),
          ("pair", .structLit "Pair" #[
            ("left", .literal (.u64 1)),
            ("right", .literal (.u64 2))
          ])
        ])
      ]
    }
  ]
}

def hasDuplicate [BEq α] (arr : Array α) : Bool :=
  arr.any (fun x => (arr.filter (fun y => y == x)).size > 1)

def main : IO Unit := do
  let counterMeta ← requireOk (buildPlanArtifactMetadata Examples.Counter.module) "counter metadata"
  assertEq "counter targetId" "psy-dpn" counterMeta.targetId
  assertEq "counter moduleName" "Counter" counterMeta.moduleName
  assertEq "counter entrypoint names" #["initialize", "increment", "get"]
    (counterMeta.entrypoints.map (·.name))
  assertEq "counter return types" #["Unit", "Unit", "U64"]
    (counterMeta.entrypoints.map (·.returnType))
  assertEq "counter capabilities unique" false (hasDuplicate counterMeta.capabilities)

  let mapMeta ← requireOk (buildPlanArtifactMetadata Examples.MapProbe.module) "map metadata"
  assertEq "map has capabilities" false mapMeta.capabilities.isEmpty

  let eventMeta ← requireOk (buildPlanArtifactMetadata Examples.EventProbe.module) "event metadata"
  assertEq "event has events" false eventMeta.events.isEmpty
  assertEq "event has fields" false eventMeta.events[0]!.fields.isEmpty
  -- EventProbe's only Psy entrypoint emits a .local value, so type inference falls
  -- back to "Felt". Verify the fallback works.
  assertEq "event field fallback type" "Felt" (eventMeta.events[0]!.fields[0]!.type)

  let typedEventMeta ← requireOk (buildPlanArtifactMetadata typedEventModule) "typed event metadata"
  assertEq "typed event count field type" "U64" typedEventMeta.events[0]!.fields[0]!.type
  assertEq "typed event flag field type" "Bool" typedEventMeta.events[0]!.fields[1]!.type
  assertEq "typed event pair field type" "Pair" typedEventMeta.events[0]!.fields[2]!.type

  let ctxMeta ← requireOk (buildPlanArtifactMetadata Examples.ContextProbe.module) "context metadata"
  assertEq "context has contextOps" false ctxMeta.contextOps.isEmpty
  -- ContextProbe uses userId, contractId, and checkpointId.
  assertEq "context op names" #["userId", "contractId", "checkpointId"]
    (ctxMeta.contextOps.map (·.name))

  IO.println "PsyMetadata: all assertions passed"

end ProofForge.Tests.PsyMetadata

def main : IO UInt32 := do
  ProofForge.Tests.PsyMetadata.main
  pure 0