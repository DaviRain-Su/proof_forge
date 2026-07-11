import ProofForge.IR.Core.HostOp
import ProofForge.IR.Core.Type
import ProofForge.Target.Capability

open ProofForge.IR.Core
open ProofForge.IR.Core.HostOp

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- Two signatures with different exact versions. -/
def sigA : HostOpSig := {
  id := { namespace_ := "near.promise", name := "create", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.string, .string, .bytes, .u128, .u64]
  results := #[.u64]
  effectClass := .external
  requiredCapabilities := #[ProofForge.Target.Capability.nearPromise]
}

def sigB : HostOpSig := {
  id := { namespace_ := "near.promise", name := "create", version := { major := 1, minor := 0, patch := 1 } }
  params := #[.string, .string, .bytes, .u128, .u64]
  results := #[.u64]
  effectClass := .external
  requiredCapabilities := #[ProofForge.Target.Capability.nearPromise]
}

def expectCatalog : Except HostOpError HostOpCatalog :=
  HostOpCatalog.empty
    |> fun cat => cat.register sigA
    |> fun r => r.bind fun cat1 => cat1.register sigB

def main : IO Unit := do
  let catalog ← match expectCatalog with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"catalog setup failed: {repr e}"

  /- Deterministic lookup: exact version match. -/
  match catalog.lookup sigA.id with
  | .ok s => require (s == sigA) "sigA lookup mismatch"
  | .error e => throw <| IO.userError s!"sigA lookup failed: {repr e}"

  match catalog.lookup sigB.id with
  | .ok s => require (s == sigB) "sigB lookup mismatch"
  | .error e => throw <| IO.userError s!"sigB lookup failed: {repr e}"

  /- Wrong version must not find sigA. -/
  let badId := { namespace_ := "near.promise", name := "create", version := { major := 1, minor := 0, patch := 2 } }
  match catalog.lookup badId with
  | .ok _ => throw <| IO.userError "lookup should fail for unknown patch version"
  | .error e => require (e matches .unknownId) s!"expected unknownId, got {repr e}"

  /- Different namespace must fail. -/
  let otherNs := { namespace_ := "evm.pledge", name := "create", version := { major := 1, minor := 0, patch := 0 } }
  match catalog.lookup otherNs with
  | .ok _ => throw <| IO.userError "lookup should fail for unknown namespace"
  | .error e => require (e matches .unknownId) s!"expected unknownId, got {repr e}"

  /- Duplicate registration is an error, not last-write-wins. -/
  match catalog.register sigA with
  | .ok _ => throw <| IO.userError "duplicate registration should fail"
  | .error e => require (e matches .duplicateId) s!"unexpected error: {repr e}"

  /- Empty catalog rejects everything. -/
  match HostOpCatalog.empty.lookup sigA.id with
  | .ok _ => throw <| IO.userError "empty catalog should reject lookup"
  | .error _ => pure ()

  IO.println "hostop-catalog: ok"