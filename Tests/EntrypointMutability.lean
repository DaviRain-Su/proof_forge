import ProofForge.Contract.Source
import ProofForge.IR.Mutability
import ProofForge.Target
import Examples.Product.ValueVault

namespace ProofForge.Tests.MutabilitySource

open ProofForge.Contract.Source

contract_source MutabilityArityProbe do
  entry call0 do
    do pure ();
  entry call1 (a : .u64) do
    do pure ();
  entry call2 (a : .u64, b : .u64) do
    do pure ();
  entry call3 (a : .u64, b : .u64, c : .u64) do
    do pure ();
  entry call4 (a : .u64, b : .u64, c : .u64, d : .u64) do
    do pure ();
  entry call5 (a : .u64, b : .u64, c : .u64, d : .u64, e : .u64) do
    do pure ();
  entry call6 (a : .u64, b : .u64, c : .u64, d : .u64, e : .u64, f : .u64) do
    do pure ();

  query view0 returns(.u64) do
    return u64 0;
  query view1 (a : .u64) returns(.u64) do
    return a;
  query view2 (a : .u64, b : .u64) returns(.u64) do
    return a;
  query view3 (a : .u64, b : .u64, c : .u64) returns(.u64) do
    return a;
  query view4 (a : .u64, b : .u64, c : .u64, d : .u64) returns(.u64) do
    return a;
  query view5 (a : .u64, b : .u64, c : .u64, d : .u64, e : .u64) returns(.u64) do
    return a;
  query view6 (a : .u64, b : .u64, c : .u64, d : .u64, e : .u64, f : .u64) returns(.u64) do
    return a;

end ProofForge.Tests.MutabilitySource

namespace ProofForge.Tests.EntrypointMutability

open ProofForge.IR

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def requireInvalidView (entrypoint : Entrypoint) (needle : String) : IO Unit := do
  match ProofForge.IR.Mutability.validateEntrypoint entrypoint with
  | .ok () => throw <| IO.userError s!"invalid view `{entrypoint.name}` was accepted"
  | .error error =>
      require (error.contains needle)
        s!"view diagnostic `{error}` did not contain `{needle}`"

def main : IO UInt32 := do
  let module := ProofForge.Tests.MutabilitySource.module
  let calls := module.entrypoints.filter (fun ep => ep.name.startsWith "call")
  let views := module.entrypoints.filter (fun ep => ep.name.startsWith "view")
  require (calls.size == 7 && calls.all (fun ep => ep.mutability == .call))
    "contract_source entry 0-6 must propagate call mutability"
  require (views.size == 7 && views.all (fun ep => ep.mutability == .view))
    "contract_source query 0-6 must propagate view mutability"

  requireInvalidView {
    name := "writes"
    mutability := .view
    body := #[.effect (.storageScalarWrite "count" (.literal (.u64 1)))]
  } "storage write"
  requireInvalidView {
    name := "events"
    mutability := .view
    body := #[.effect (.eventEmit "Changed" #[])]
  } "event"
  requireInvalidView {
    name := "promise"
    mutability := .view
    «returns» := .u64
    body := #[.return (.nearPromiseResultsCount)]
  } "promise"
  requireInvalidView {
    name := "callRemote"
    mutability := .view
    «returns» := .u64
    body := #[.return (.crosscallInvokeTyped
      (.literal (.address 1)) (.literal (.u64 2)) #[] .u64)]
  } "non-static crosscall"
  requireInvalidView {
    name := "attachedValue"
    mutability := .view
    «returns» := .u64
    body := #[.return .nativeValue]
  } "native value"

  let invalidModule : Module := {
    name := "InvalidView"
    state := #[{ id := "count", kind := .scalar, type := .u64 }]
    entrypoints := #[{
      name := "badQuery"
      mutability := .view
      body := #[.effect (.storageScalarWrite "count" (.literal (.u64 1)))]
    }]
  }
  match ProofForge.Target.resolveModule ProofForge.Target.evm invalidModule with
  | .ok _ => throw <| IO.userError "target resolution accepted a mutating view"
  | .error diagnostic =>
      require (diagnostic.render.contains "view entrypoint `badQuery` contains storage write")
        s!"target resolution lost mutability diagnostic: {diagnostic.render}"

  let staticView : Entrypoint := {
    name := "readRemote"
    mutability := .view
    «returns» := .u64
    body := #[.return (.crosscallInvokeStaticTyped
      (.literal (.address 1)) (.literal (.u64 2)) #[] .u64)]
  }
  match ProofForge.IR.Mutability.validateEntrypoint staticView with
  | .ok () => pure ()
  | .error error => throw <| IO.userError s!"static view was rejected: {error}"

  let some snapshot := Examples.Product.ValueVault.module.entrypoints.find?
      (fun entrypoint => entrypoint.name == "snapshot")
    | throw <| IO.userError "ValueVault snapshot entrypoint missing"
  require (snapshot.mutability == .call)
    "ValueVault snapshot writes last_checkpoint and emits an event, so it must remain a call"
  match ProofForge.IR.Mutability.validateEntrypoint snapshot with
  | .ok () => pure ()
  | .error error => throw <| IO.userError s!"ValueVault call snapshot rejected: {error}"

  IO.println "entrypoint-mutability: ok"
  return 0

end ProofForge.Tests.EntrypointMutability

def main : IO UInt32 :=
  ProofForge.Tests.EntrypointMutability.main
