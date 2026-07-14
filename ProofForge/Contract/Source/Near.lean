/-
# NEAR host-extension entrypoint for `contract_source` (opt-in)

Import **this** module when a contract intentionally uses NEAR Promise
chaining / result decode beyond portable `remoteCall`:

```lean
import ProofForge.Contract.Source.Near

contract_source MyNearProgram do
  -- may use crosscallContinue / nearPromiseResultU64 / nearCrosscallPool
```

Portable Shared examples must keep:

```lean
import ProofForge.Contract.Source
```

and use only `declareRemoteUnit` + `peerHandle` + `remoteCall` on the portable
path. Host string-pool registration is automatic. `just portable-default`
forbids importing this file from `Examples/Product`.

The shared IR contains no NEAR-specific expression constructors. This facade
maps NEAR-only behavior to target-owned HostOps while keeping portable
cross-call operations on the shared semantic surface.
-/
import ProofForge.Contract.Source
import ProofForge.Target.HostOps.Near

namespace ProofForge.Contract.Source.Near

open ProofForge.Contract.Source

def registerNearCrosscallString (value : String) : ModuleM Unit := do
  let _ ← ProofForge.Contract.Builder.ensureCrosscallString value
  pure ()

def nearAddressLit (idx : Nat) : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.peerHandle idx

def nearCrosscallPool (account methodId : ProofForge.IR.Expr) (args : Array ProofForge.IR.Expr)
    (deposit : ProofForge.IR.Expr) (argNames : Array String := #[]) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.crosscallInvokeNamedValue account methodId args deposit argNames

/-- Source-compatible NEAR name for asynchronous continuation. -/
def nearPromiseThen (parentPromise callbackMethod : ProofForge.IR.Expr)
    (args : Array ProofForge.IR.Expr) (deposit : ProofForge.IR.Expr)
    (argNames : Array String := #[]) : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.crosscallContinue
    parentPromise callbackMethod args deposit argNames

def nearPromiseResultsCount : ProofForge.IR.Expr :=
  .hostCall _root_.ProofForge.Target.HostOps.Near.promiseResultsCountSig.id #[] .u64 #[.nearPromise]

def nearPromiseResultStatus (index : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  .hostCall _root_.ProofForge.Target.HostOps.Near.promiseResultStatusSig.id #[index] .u64 #[.nearPromise]

def nearPromiseResultU64 (index : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  .hostCall _root_.ProofForge.Target.HostOps.Near.promiseResultU64Sig.id #[index] .u64 #[.nearPromise]

def nearPromiseResultU128 (index : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  .hostCall _root_.ProofForge.Target.HostOps.Near.promiseResultU128Sig.id #[index] .u128 #[.nearPromise]

/-- Source-compatible NEAR name for the full-width call value. -/
def nearAttachedDeposit : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.callValueU128

def nearStorageUsage : ProofForge.IR.Expr :=
  .hostCall _root_.ProofForge.Target.HostOps.Near.storageUsageSig.id #[] .u64 #[.storageScalar]

def nearPromiseTransfer (account amount : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  .hostCall _root_.ProofForge.Target.HostOps.Near.promiseTransferSig.id #[account, amount] .u64 #[.nearPromise]

end ProofForge.Contract.Source.Near
