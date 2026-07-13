import ProofForge.Frontend.Surface.Syntax
import ProofForge.IR.Core
import ProofForge.IR.Core.HostOp
import ProofForge.Target.Capability
import ProofForge.Target.HostOps.Near

/-! # Surface NEAR Host Operations

Surface construction for the typed `near.promise.create@1.0.0` HostOp.
-/

namespace ProofForge.Frontend.Surface.Host.Near

open ProofForge.IR.Core
open ProofForge.IR.Core.HostOp

/-- The exact `near.promise.create@1.0.0` HostOpId. -/
def promiseCreateId : HostOpId := ProofForge.Target.HostOps.Near.promiseCreateSig.id

/-- The canonical `near.promise.create@1.0.0` HostOp signature. -/
def promiseCreateSig : HostOpSig := ProofForge.Target.HostOps.Near.promiseCreateSig

/-- A catalog containing only the `near.promise.create@1.0.0` signature. -/
def nearPromiseCatalog : Except HostOpError HostOpCatalog :=
  ProofForge.Target.HostOps.Near.catalog

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
