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
  | context
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

/-- Register a collection without bypassing duplicate checks. -/
def HostOpCatalog.registerAll (cat : HostOpCatalog) (signatures : Array HostOpSig) :
    Except HostOpError HostOpCatalog :=
  signatures.foldlM HostOpCatalog.register cat

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

/-- Validate that the signature can use the generic typed HostOp carrier.
All effect classes are legal here; view mutability is checked separately. -/
def HostOpCatalog.validateCallUsage (sig : HostOpSig) :
    Except HostOpError Unit :=
  match sig.effectClass with
  | .pure | .context | .external => .ok ()

end ProofForge.IR.Core.HostOp
