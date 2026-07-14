import ProofForge.IR.Core.HostOp

/-! # NEAR Target Host-Operation Signatures

NEAR owns these exact signatures and their catalog. Canonical Core owns only
the generic typed catalog protocol.
-/

namespace ProofForge.Target.HostOps.Near

open ProofForge.IR.Core
open ProofForge.IR.Core.HostOp

def predecessorAccountIdSig : HostOpSig := {
  id := { namespace_ := "near.context", name := "predecessor_account_id", version := { major := 1, minor := 0, patch := 0 } }
  params := #[]
  results := #[.string]
  effectClass := .context
  requiredCapabilities := #[.callerSender]
}

def currentAccountIdSig : HostOpSig := {
  id := { namespace_ := "near.context", name := "current_account_id", version := { major := 1, minor := 0, patch := 0 } }
  params := #[]
  results := #[.string]
  effectClass := .context
  requiredCapabilities := #[.accountExplicit]
}

def epochHeightSig : HostOpSig := {
  id := { namespace_ := "near.context", name := "epoch_height", version := { major := 1, minor := 0, patch := 0 } }
  params := #[]
  results := #[.u64]
  effectClass := .context
  requiredCapabilities := #[.envBlock]
}

def randomSeedSig : HostOpSig := {
  id := { namespace_ := "near.context", name := "random_seed", version := { major := 1, minor := 0, patch := 0 } }
  params := #[]
  results := #[.hash]
  effectClass := .context
  requiredCapabilities := #[.envBlock]
}

def prepaidGasSig : HostOpSig := {
  id := { namespace_ := "near.context", name := "prepaid_gas", version := { major := 1, minor := 0, patch := 0 } }
  params := #[]
  results := #[.u64]
  effectClass := .context
  requiredCapabilities := #[.runtimeComputeUnits]
}

def usedGasSig : HostOpSig := {
  id := { namespace_ := "near.context", name := "used_gas", version := { major := 1, minor := 0, patch := 0 } }
  params := #[]
  results := #[.u64]
  effectClass := .context
  requiredCapabilities := #[.runtimeComputeUnits]
}

def promiseCreateSig : HostOpSig := {
  id := { namespace_ := "near.promise", name := "create", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.string, .string, .bytes, .u128, .u64]
  results := #[.u64]
  effectClass := .external
  requiredCapabilities := #[.nearPromise]
}

def promiseResultU64Sig : HostOpSig := {
  id := { namespace_ := "near.promise", name := "result_u64", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.u64]
  results := #[.u64]
  effectClass := .external
  requiredCapabilities := #[.nearPromise]
}

def promiseResultsCountSig : HostOpSig := {
  id := { namespace_ := "near.promise", name := "results_count", version := { major := 1, minor := 0, patch := 0 } }
  params := #[]
  results := #[.u64]
  effectClass := .external
  requiredCapabilities := #[.nearPromise]
}

def promiseResultStatusSig : HostOpSig := {
  id := { namespace_ := "near.promise", name := "result_status", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.u64]
  results := #[.u64]
  effectClass := .external
  requiredCapabilities := #[.nearPromise]
}

def promiseResultU128Sig : HostOpSig := {
  id := { namespace_ := "near.promise", name := "result_u128", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.u64]
  results := #[.u128]
  effectClass := .external
  requiredCapabilities := #[.nearPromise]
}

def storageUsageSig : HostOpSig := {
  id := { namespace_ := "near.storage", name := "usage", version := { major := 1, minor := 0, patch := 0 } }
  params := #[]
  results := #[.u64]
  effectClass := .external
  requiredCapabilities := #[.storageScalar]
}

def promiseTransferSig : HostOpSig := {
  id := { namespace_ := "near.promise", name := "transfer", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.string, .u128]
  results := #[.u64]
  effectClass := .external
  requiredCapabilities := #[.nearPromise]
}

def signatures : Array HostOpSig := #[
  predecessorAccountIdSig,
  currentAccountIdSig,
  epochHeightSig,
  randomSeedSig,
  prepaidGasSig,
  usedGasSig,
  promiseCreateSig,
  promiseResultU64Sig,
  promiseResultsCountSig,
  promiseResultStatusSig,
  promiseResultU128Sig,
  storageUsageSig,
  promiseTransferSig
]

def catalog : Except HostOpError HostOpCatalog :=
  HostOpCatalog.empty.registerAll signatures

def supportedIds : Array ProofForge.Target.HostOpId := signatures.map (·.id)

end ProofForge.Target.HostOps.Near
