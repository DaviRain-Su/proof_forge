import ProofForge.Frontend.Surface.Syntax
import ProofForge.IR.Core
import ProofForge.IR.Core.HostOp
import ProofForge.Target.Capability

/-! # Surface NEAR Host Operations

Surface construction for the typed `near.promise.create@1.0.0` HostOp.
-/

namespace ProofForge.Frontend.Surface.Host.Near

open ProofForge.IR.Core
open ProofForge.IR.Core.HostOp

/-- The exact `near.promise.create@1.0.0` HostOpId. -/
def promiseCreateId : HostOpId := {
  namespace_ := "near.promise",
  name := "create",
  version := { major := 1, minor := 0, patch := 0 }
}

/-- The canonical `near.promise.create@1.0.0` HostOp signature. -/
def promiseCreateSig : HostOpSig := {
  id := promiseCreateId,
  params := #[.string, .string, .bytes, .u128, .u64],
  results := #[.u64],
  effectClass := .external,
  requiredCapabilities := #[.nearPromise]
}

/-- A catalog containing only the `near.promise.create@1.0.0` signature. -/
def nearPromiseCatalog : Except HostOpError HostOpCatalog :=
  HostOpCatalog.empty.register promiseCreateSig

/-- Surface constructor for `near.promise.create@1.0.0`.
Accepts account ID, method name, serialized args, deposit, gas, and a
result local name. Normalization emits one `hostCall` instruction whose
result is `u64`. -/
def promiseCreate (accountId : SurfaceExpr) (methodName : SurfaceExpr)
    (serializedArgs : SurfaceExpr) (deposit : SurfaceExpr) (gas : SurfaceExpr)
    (resultName : String) : SurfaceStmt :=
  .hostCallBind resultName .u64 promiseCreateId
    #[accountId, methodName, serializedArgs, deposit, gas]

end ProofForge.Frontend.Surface.Host.Near