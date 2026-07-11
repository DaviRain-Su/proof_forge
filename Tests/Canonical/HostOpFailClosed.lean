import ProofForge.IR.Core.HostOp
import ProofForge.IR.Core.Type
import ProofForge.Target.Capability

open ProofForge.IR.Core
open ProofForge.IR.Core.HostOp

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- A basic external signature for testing. -/
def testSig : HostOpSig := {
  id := { namespace_ := "near.promise", name := "create", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.string, .string, .bytes, .u128, .u64]
  results := #[.u64]
  effectClass := .external
  requiredCapabilities := #[ProofForge.Target.Capability.nearPromise]
}

/-- A pure signature for testing effect-class mismatch. -/
def pureSig : HostOpSig := {
  id := { namespace_ := "math", name := "addMod", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.u64, .u64, .u64]
  results := #[.u64]
  effectClass := .pure
  requiredCapabilities := #[]
}

def main : IO Unit := do
  /- 1. Unknown namespace or name -/
  let catalog ← match HostOpCatalog.empty.register testSig with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"setup failed: {repr e}"

  let badNs := { namespace_ := "unknown.ns", name := "create", version := { major := 1, minor := 0, patch := 0 } }
  match catalog.lookup badNs with
  | .ok _ => throw <| IO.userError "unknown namespace should reject"
  | .error e => require (e matches .unknownId) s!"expected unknownId, got {repr e}"

  let badName := { namespace_ := "near.promise", name := "destroy", version := { major := 1, minor := 0, patch := 0 } }
  match catalog.lookup badName with
  | .ok _ => throw <| IO.userError "unknown name should reject"
  | .error e => require (e matches .unknownId) s!"expected unknownId, got {repr e}"

  /- 2. Unknown major, minor, or patch version -/
  let badMajor := { namespace_ := "near.promise", name := "create", version := { major := 2, minor := 0, patch := 0 } }
  match catalog.lookup badMajor with
  | .ok _ => throw <| IO.userError "unknown major should reject"
  | .error e => require (e matches .unknownId) s!"expected unknownId, got {repr e}"

  let badMinor := { namespace_ := "near.promise", name := "create", version := { major := 1, minor := 1, patch := 0 } }
  match catalog.lookup badMinor with
  | .ok _ => throw <| IO.userError "unknown minor should reject"
  | .error e => require (e matches .unknownId) s!"expected unknownId, got {repr e}"

  let badPatch := { namespace_ := "near.promise", name := "create", version := { major := 1, minor := 0, patch := 5 } }
  match catalog.lookup badPatch with
  | .ok _ => throw <| IO.userError "unknown patch should reject"
  | .error e => require (e matches .unknownId) s!"expected unknownId, got {repr e}"

  /- 3. Duplicate catalog ID -/
  match (HostOpCatalog.empty.register testSig >>= fun c => c.register testSig) with
  | .ok _ => throw <| IO.userError "duplicate ID should reject"
  | .error e => require (e matches .duplicateId) s!"expected duplicateId, got {repr e}"

  /- 4. Wrong argument arity -/
  match HostOpCatalog.validateCall testSig #[] with
  | .ok _ => throw <| IO.userError "wrong arity (too few) should reject"
  | .error e => require (e matches .wrongArity) s!"expected wrongArity, got {repr e}"

  match HostOpCatalog.validateCall testSig #[.string, .string] with
  | .ok _ => throw <| IO.userError "wrong arity (partial) should reject"
  | .error e => require (e matches .wrongArity) s!"expected wrongArity, got {repr e}"

  match HostOpCatalog.validateCall testSig #[.string, .string, .bytes, .u128, .u64, .u64] with
  | .ok _ => throw <| IO.userError "wrong arity (too many) should reject"
  | .error e => require (e matches .wrongArity) s!"expected wrongArity, got {repr e}"

  /- 5. Wrong argument type -/
  match HostOpCatalog.validateCall testSig #[.u64, .string, .bytes, .u128, .u64] with
  | .ok _ => throw <| IO.userError "wrong arg type (u64 for string) should reject"
  | .error e => require (e matches .typeMismatch) s!"expected typeMismatch, got {repr e}"

  match HostOpCatalog.validateCall testSig #[.string, .string, .bytes, .u64, .u64] with
  | .ok _ => throw <| IO.userError "wrong arg type (u64 for u128) should reject"
  | .error e => require (e matches .typeMismatch) s!"expected typeMismatch, got {repr e}"

  /- 6. Wrong instruction result arity -/
  match HostOpCatalog.validateResults testSig #[] with
  | .ok _ => throw <| IO.userError "wrong result arity (0 for 1) should reject"
  | .error e => require (e matches .resultArityMismatch) s!"expected resultArityMismatch, got {repr e}"

  match HostOpCatalog.validateResults testSig #[.u64, .u64] with
  | .ok _ => throw <| IO.userError "wrong result arity (2 for 1) should reject"
  | .error e => require (e matches .resultArityMismatch) s!"expected resultArityMismatch, got {repr e}"

  /- 7. Wrong instruction result type -/
  match HostOpCatalog.validateResults testSig #[.string] with
  | .ok _ => throw <| IO.userError "wrong result type should reject"
  | .error e => require (e matches .resultTypeMismatch) s!"expected resultTypeMismatch, got {repr e}"

  /- 8. Pure operation used with effectful signature -/
  match HostOpCatalog.validateCallUsage pureSig with
  | .ok _ => throw <| IO.userError "pure sig used as hostCall should reject"
  | .error e => require (e matches .pureEffectfulMismatch) s!"expected pureEffectfulMismatch, got {repr e}"

  IO.println "hostop-fail-closed: ok"