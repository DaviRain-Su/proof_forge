import ProofForge.IR.Core.HostOp

/-! # EVM Target Host-Operation Signatures

EVM protocol callbacks are target-owned operations. Canonical Core owns only
the generic typed catalog protocol and never names ERC standards.
-/

namespace ProofForge.Target.HostOps.Evm

open ProofForge.IR.Core
open ProofForge.IR.Core.HostOp

/-- Legacy `contract_source` currently canonicalizes EVM account handles to
`u64`; the EVM plan widens them to full words. The HostOp signature records
that real boundary instead of claiming Core `.address` values prematurely. -/
def erc721ReceivedSig : HostOpSig := {
  id := { namespace_ := "evm.erc721", name := "check_received", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.u64, .u64, .u64, .u64]
  results := #[]
  effectClass := .external
  requiredCapabilities := #[.crosscallInvoke]
}

def erc1155ReceivedSig : HostOpSig := {
  id := { namespace_ := "evm.erc1155", name := "check_received", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.u64, .u64, .u64, .u64, .u64]
  results := #[]
  effectClass := .external
  requiredCapabilities := #[.crosscallInvoke]
}

def erc1155BatchReceivedSig : HostOpSig := {
  id := { namespace_ := "evm.erc1155", name := "check_batch_received", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.u64, .u64, .u64, .fixedArray .u64 2, .fixedArray .u64 2]
  results := #[]
  effectClass := .external
  requiredCapabilities := #[.crosscallInvoke, .dataFixedArray]
}

def signatures : Array HostOpSig := #[
  erc721ReceivedSig,
  erc1155ReceivedSig,
  erc1155BatchReceivedSig
]

def catalog : Except HostOpError HostOpCatalog :=
  HostOpCatalog.empty.registerAll signatures

def supportedIds : Array ProofForge.Target.HostOpId := signatures.map (·.id)

end ProofForge.Target.HostOps.Evm
