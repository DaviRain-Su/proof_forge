import ProofForge.IR.Core.HostOp
import ProofForge.Target.HostOps.Solana.Payload

/-! # Solana Target Host-Operation Signatures

Typed operations whose semantics are provided by the Solana runtime. Account,
PDA, and CPI declarations are added only after their authored payloads are
typed; they must not be represented by metadata-only placeholder signatures.
-/

namespace ProofForge.Target.HostOps.Solana

open ProofForge.IR.Core
open ProofForge.IR.Core.HostOp

def accountDeclareId : ProofForge.Target.HostOpId := {
  namespace_ := "solana.account"
  name := "declare"
  version := { major := 1, minor := 0, patch := 0 }
}

def pdaDeriveId : ProofForge.Target.HostOpId := {
  namespace_ := "solana.pda"
  name := "derive"
  version := { major := 1, minor := 0, patch := 0 }
}

def cpiInvokeId : ProofForge.Target.HostOpId := {
  namespace_ := "solana.cpi"
  name := "invoke"
  version := { major := 1, minor := 0, patch := 0 }
}

def allocatorConfigureId : ProofForge.Target.HostOpId := {
  namespace_ := "solana.allocator"
  name := "configure"
  version := { major := 1, minor := 0, patch := 0 }
}

def accountReallocId : ProofForge.Target.HostOpId := {
  namespace_ := "solana.account"
  name := "realloc"
  version := { major := 1, minor := 0, patch := 0 }
}

def transferHookExtraAccountMetaId : ProofForge.Target.HostOpId := {
  namespace_ := "solana.transfer_hook"
  name := "initialize_extra_account_meta"
  version := { major := 1, minor := 0, patch := 0 }
}

def materializationIds : Array ProofForge.Target.HostOpId := #[
  accountDeclareId,
  pdaDeriveId,
  cpiInvokeId,
  allocatorConfigureId,
  accountReallocId,
  transferHookExtraAccountMetaId
]

def remainingComputeUnitsSig : HostOpSig := {
  id := {
    namespace_ := "solana.runtime"
    name := "remaining_compute_units"
    version := { major := 1, minor := 0, patch := 0 }
  }
  params := #[]
  results := #[.u64]
  effectClass := .context
  requiredCapabilities := #[.runtimeComputeUnits]
}

def sha256Sig : HostOpSig := {
  id := {
    namespace_ := "solana.crypto"
    name := "sha256"
    version := { major := 1, minor := 0, patch := 0 }
  }
  params := #[.bytes]
  results := #[.hash]
  effectClass := .pure
  requiredCapabilities := #[.cryptoHash]
}

def keccak256Sig : HostOpSig := {
  id := {
    namespace_ := "solana.crypto"
    name := "keccak256"
    version := { major := 1, minor := 0, patch := 0 }
  }
  params := #[.bytes]
  results := #[.hash]
  effectClass := .pure
  requiredCapabilities := #[.cryptoHash]
}

def blake3Sig : HostOpSig := {
  id := {
    namespace_ := "solana.crypto"
    name := "blake3"
    version := { major := 1, minor := 0, patch := 0 }
  }
  params := #[.bytes]
  results := #[.hash]
  effectClass := .pure
  requiredCapabilities := #[.cryptoHash]
}

def signatures : Array HostOpSig := #[
  remainingComputeUnitsSig,
  sha256Sig,
  keccak256Sig,
  blake3Sig
]

def catalog : Except HostOpError HostOpCatalog :=
  HostOpCatalog.empty.registerAll signatures

def supportedIds : Array ProofForge.Target.HostOpId :=
  materializationIds ++ signatures.map (·.id)

end ProofForge.Target.HostOps.Solana
