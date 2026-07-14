import ProofForge.Target.HostOp

/-! EVM-owned interface extension identities. These are artifact/interface
annotations, not runtime HostOps. -/

namespace ProofForge.Target.InterfaceOps.Evm

def solidityCustomErrorId : ProofForge.Target.HostOpId := {
  namespace_ := "evm.error"
  name := "solidity_custom"
  version := { major := 1, minor := 0, patch := 0 }
}

def supportedIds : Array ProofForge.Target.HostOpId := #[solidityCustomErrorId]

end ProofForge.Target.InterfaceOps.Evm
