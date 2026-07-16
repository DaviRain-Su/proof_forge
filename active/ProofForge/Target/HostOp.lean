import Init.Data.String.Basic

/-! # Open Target Host-Operation Identity

Stable, typed identity shared by source extensions, Canonical Core, capability
resolution, and target handlers. The identity belongs to the target-extension
protocol rather than to Core or any individual backend.
-/

namespace ProofForge.Target

structure HostOpVersion where
  major : Nat
  minor : Nat
  patch : Nat
  deriving BEq, DecidableEq, Repr

structure HostOpId where
  namespace_ : String
  name : String
  version : HostOpVersion
  deriving BEq, DecidableEq, Repr

def HostOpId.render (id : HostOpId) : String :=
  s!"{id.namespace_}/{id.name}@{id.version.major}.{id.version.minor}.{id.version.patch}"

instance : ToString HostOpId where
  toString := HostOpId.render

end ProofForge.Target
