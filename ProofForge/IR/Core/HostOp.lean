import ProofForge.IR.Core.Type
import ProofForge.IR.Core.Id
import ProofForge.IR.Core.Syntax
import ProofForge.Target.Capability

/-! # Typed Versioned Host Operations

Exact versioned host-operation catalog. Catalog lookup is exact: there is no
implicit version range. Duplicate registration is an error, not last-write
wins.  `HostOpCall` contains only ID and typed argument references; result
definitions remain on the enclosing Core instruction. -/

namespace ProofForge.IR.Core.HostOp

open ProofForge.IR.Core
open ProofForge.Target

/-- Effect class of a host operation. -/
inductive HostOpEffectClass
  | pure
  | external
  deriving BEq, Repr

/-- Signature for a host operation. -/
structure HostOpSig where
  id : HostOpId
  params : Array CoreType
  results : Array CoreType
  effectClass : HostOpEffectClass
  requiredCapabilities : Array Capability
  deriving BEq, Repr

/-- Catalog error tag. -/
inductive HostOpError
  | unknownId
  | duplicateId
  | wrongArity
  | typeMismatch
  | resultArityMismatch
  | resultTypeMismatch
  | pureEffectfulMismatch
  deriving BEq, Repr

/-- A catalog of host-operation signatures. Lookup is exact by `HostOpId`. -/
structure HostOpCatalog where
  entries : Array HostOpSig := #[]
  deriving BEq, Repr

/-- Empty catalog. -/
def HostOpCatalog.empty : HostOpCatalog := { entries := #[] }

/-- Register a signature. Duplicate ID is an error. -/
def HostOpCatalog.register (cat : HostOpCatalog) (sig : HostOpSig) :
    Except HostOpError HostOpCatalog :=
  if cat.entries.any (·.id == sig.id) then
    .error .duplicateId
  else
    .ok { entries := cat.entries.push sig }

/-- Look up a signature by exact ID. -/
def HostOpCatalog.lookup (cat : HostOpCatalog) (id : HostOpId) :
    Except HostOpError HostOpSig :=
  match cat.entries.find? (·.id == id) with
  | some sig => .ok sig
  | none => .error .unknownId

/-- Validate that call argument types match the signature. -/
def HostOpCatalog.validateCall (sig : HostOpSig) (argTypes : Array CoreType) :
    Except HostOpError Unit :=
  if argTypes.size != sig.params.size then
    .error .wrongArity
  else
    let mismatches := argTypes.zip sig.params |>.filter (fun (a, b) => a != b)
    if mismatches.isEmpty then .ok () else .error .typeMismatch

/-- Validate that instruction result types match the signature. -/
def HostOpCatalog.validateResults (sig : HostOpSig) (resultTypes : Array CoreType) :
    Except HostOpError Unit :=
  if resultTypes.size != sig.results.size then
    .error .resultArityMismatch
  else
    let mismatches := resultTypes.zip sig.results |>.filter (fun (a, b) => a != b)
    if mismatches.isEmpty then .ok () else .error .resultTypeMismatch

/-- Validate that the effect class is not pure when used as a hostCall. -/
def HostOpCatalog.validateCallUsage (sig : HostOpSig) :
    Except HostOpError Unit :=
  match sig.effectClass with
  | .pure => .error .pureEffectfulMismatch
  | .external => .ok ()

/-- The canonical `near.promise.create@1.0.0` signature. -/
def nearPromiseCreateSig : HostOpSig := {
  id := { namespace_ := "near.promise", name := "create", version := { major := 1, minor := 0, patch := 0 } },
  params := #[.string, .string, .bytes, .u128, .u64],
  results := #[.u64],
  effectClass := .external,
  requiredCapabilities := #[.nearPromise]
}

def nearPromiseResultU64Sig : HostOpSig := {
  id := { namespace_ := "near.promise", name := "result_u64", version := { major := 1, minor := 0, patch := 0 } },
  params := #[.u64],
  results := #[.u64],
  effectClass := .external,
  requiredCapabilities := #[.nearPromise]
}

def nearPromiseResultsCountSig : HostOpSig := {
  id := { namespace_ := "near.promise", name := "results_count", version := { major := 1, minor := 0, patch := 0 } },
  params := #[], results := #[.u64], effectClass := .external,
  requiredCapabilities := #[.nearPromise]
}

def nearPromiseResultStatusSig : HostOpSig := {
  id := { namespace_ := "near.promise", name := "result_status", version := { major := 1, minor := 0, patch := 0 } },
  params := #[.u64], results := #[.u64], effectClass := .external,
  requiredCapabilities := #[.nearPromise]
}

def nearPromiseResultU128Sig : HostOpSig := {
  id := { namespace_ := "near.promise", name := "result_u128", version := { major := 1, minor := 0, patch := 0 } },
  params := #[.u64],
  results := #[.u128],
  effectClass := .external,
  requiredCapabilities := #[.nearPromise]
}

def nearStorageUsageSig : HostOpSig := {
  id := { namespace_ := "near.storage", name := "usage", version := { major := 1, minor := 0, patch := 0 } },
  params := #[], results := #[.u64], effectClass := .external,
  requiredCapabilities := #[.storageScalar]
}

def nearPromiseTransferSig : HostOpSig := {
  id := { namespace_ := "near.promise", name := "transfer", version := { major := 1, minor := 0, patch := 0 } },
  params := #[.string, .u128], results := #[.u64], effectClass := .external,
  requiredCapabilities := #[.nearPromise]
}

/-- The canonical host-op catalog containing all registered host operations.
Currently only `near.promise.create@1.0.0`. -/
def canonicalHostOpCatalog : HostOpCatalog :=
  match HostOpCatalog.empty.register nearPromiseCreateSig with
  | .ok cat => match cat.register nearPromiseResultU64Sig with
    | .ok cat => match cat.register nearPromiseResultsCountSig with
      | .ok cat => match cat.register nearPromiseResultStatusSig with
        | .ok cat => match cat.register nearPromiseResultU128Sig with
          | .ok cat => match cat.register nearStorageUsageSig with
            | .ok cat => match cat.register nearPromiseTransferSig with
              | .ok cat => cat
              | .error _ => HostOpCatalog.empty
            | .error _ => HostOpCatalog.empty
          | .error _ => HostOpCatalog.empty
        | .error _ => HostOpCatalog.empty
      | .error _ => HostOpCatalog.empty
    | .error _ => HostOpCatalog.empty
  | .error _ => HostOpCatalog.empty
end ProofForge.IR.Core.HostOp

/-- Render a HostOpId as `namespace/name@major.minor.patch`. -/
def ProofForge.IR.Core.HostOpId.render (id : ProofForge.IR.Core.HostOpId) : String :=
  s!"{id.namespace_}/{id.name}@{id.version.major}.{id.version.minor}.{id.version.patch}"

instance : ToString ProofForge.IR.Core.HostOpId where
  toString := ProofForge.IR.Core.HostOpId.render
