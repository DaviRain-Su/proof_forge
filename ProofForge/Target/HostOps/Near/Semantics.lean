import ProofForge.IR.Core.Semantics
import ProofForge.Target.HostOps.Near

/-! # NEAR Host-Operation Reference Semantics

Executable reference behavior for NEAR extensions. Canonical Core provides the
generic `HostSemantics` injection point; it does not own this trace or dispatch.
-/

namespace ProofForge.Target.HostOps.Near.Semantics

open ProofForge.IR.Core
open ProofForge.IR.Core.Semantics

structure PromiseTrace where
  accountId : String
  methodName : String
  args : ByteArray
  deposit : UInt128
  gas : UInt64
  promiseIndex : UInt64
  deriving Repr, BEq

/-- Reference handler for `near.promise/create@1.0.0`. -/
def handlePromiseCreate (traces : Array PromiseTrace) (call : HostOpCall)
    (args : Array CoreValue) : Except RuntimeError (CoreValue × Array PromiseTrace) :=
  if call.id != promiseCreateSig.id then
    .error (.unknownHostOp call.id)
  else if args.size != 5 then
    .error .argMismatch
  else
    match args[0]!, args[1]!, args[2]!, args[3]!, args[4]! with
    | .string accountId, .string methodName, .bytes argBytes, .u128 deposit, .u64 gas =>
      let idx := UInt64.ofNat traces.size
      let trace := { accountId, methodName, args := argBytes, deposit, gas, promiseIndex := idx }
      .ok (.u64 idx, traces.push trace)
    | _, _, _, _, _ => .error .typeMismatch

end ProofForge.Target.HostOps.Near.Semantics
