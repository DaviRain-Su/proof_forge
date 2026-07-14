import ProofForge.IR.Core.HostOp

/-! # EVM Target Host-Operation Signatures

EVM protocol callbacks are target-owned operations. Canonical Core owns only
the generic typed catalog protocol and never names ERC standards.
-/

namespace ProofForge.Target.HostOps.Evm

open ProofForge.IR.Core
open ProofForge.IR.Core.HostOp

def originSig : HostOpSig := {
  id := { namespace_ := "evm.context", name := "origin", version := { major := 1, minor := 0, patch := 0 } }
  params := #[]
  results := #[.address]
  effectClass := .context
  requiredCapabilities := #[.callerSender]
}

def prevRandaoSig : HostOpSig := {
  id := { namespace_ := "evm.context", name := "prevrandao", version := { major := 1, minor := 0, patch := 0 } }
  params := #[]
  results := #[.hash]
  effectClass := .context
  requiredCapabilities := #[.envBlock]
}

def gasPriceSig : HostOpSig := {
  id := { namespace_ := "evm.context", name := "gas_price", version := { major := 1, minor := 0, patch := 0 } }
  params := #[]
  results := #[.u64]
  effectClass := .context
  requiredCapabilities := #[.envBlock]
}

def baseFeeSig : HostOpSig := {
  id := { namespace_ := "evm.context", name := "base_fee", version := { major := 1, minor := 0, patch := 0 } }
  params := #[]
  results := #[.u64]
  effectClass := .context
  requiredCapabilities := #[.envBlock]
}

def coinbaseSig : HostOpSig := {
  id := { namespace_ := "evm.context", name := "coinbase", version := { major := 1, minor := 0, patch := 0 } }
  params := #[]
  results := #[.hash]
  effectClass := .context
  requiredCapabilities := #[.envBlock]
}

def blockHashSig : HostOpSig := {
  id := { namespace_ := "evm.context", name := "block_hash", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.u64]
  results := #[.hash]
  effectClass := .context
  requiredCapabilities := #[.envBlock]
}

def ecrecoverSig : HostOpSig := {
  id := { namespace_ := "evm.crypto", name := "ecrecover", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.hash, .u64, .hash, .hash]
  results := #[.u64]
  effectClass := .pure
  requiredCapabilities := #[.cryptoEcrecover]
}

def eip712PermitDigestSig : HostOpSig := {
  id := { namespace_ := "evm.crypto", name := "eip712_permit_digest", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.address, .address, .u64, .u64, .u64, .hash]
  results := #[.hash]
  effectClass := .pure
  requiredCapabilities := #[.cryptoEcrecover]
}

def createSig : HostOpSig := {
  id := { namespace_ := "evm.create", name := "create", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.u128, .string]
  results := #[.address]
  effectClass := .external
  requiredCapabilities := #[.crosscallInvoke]
}

def create2Sig : HostOpSig := {
  id := { namespace_ := "evm.create", name := "create2", version := { major := 1, minor := 0, patch := 0 } }
  params := #[.u128, .hash, .string]
  results := #[.address]
  effectClass := .external
  requiredCapabilities := #[.crosscallInvoke]
}

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
  originSig,
  prevRandaoSig,
  gasPriceSig,
  baseFeeSig,
  coinbaseSig,
  blockHashSig,
  ecrecoverSig,
  eip712PermitDigestSig,
  createSig,
  create2Sig,
  erc721ReceivedSig,
  erc1155ReceivedSig,
  erc1155BatchReceivedSig
]

def catalog : Except HostOpError HostOpCatalog :=
  HostOpCatalog.empty.registerAll signatures

def supportedIds : Array ProofForge.Target.HostOpId := signatures.map (·.id)

end ProofForge.Target.HostOps.Evm
