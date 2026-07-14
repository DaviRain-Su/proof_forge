import ProofForge.Compiler.CanonicalPipeline
import ProofForge.Contract.Stdlib.ERC721
import ProofForge.Frontend.Authored.Normalize
import ProofForge.Target.HostOps.Evm
import ProofForge.Target.Registry

open ProofForge.IR.Core

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def checkedErc721 : IO ProofForge.IR.Canonical.CheckedCanonicalContract := do
  match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec ProofForge.Contract.Stdlib.ERC721.spec with
  | .ok bundle => pure bundle.contract
  | .error error => throw (IO.userError s!"ERC721 canonical adaptation failed: {repr error}")

def main : IO Unit := do
  let checked ← checkedErc721
  let evmProfile := ProofForge.Target.evm
  require (evmProfile.hostOps.contains ProofForge.Target.HostOps.Evm.erc721ReceivedSig.id)
    "EVM registry does not advertise the ERC721 receiver HostOp"
  let evmErrors :=
    ProofForge.Compiler.checkHostOpHandlers "evm" checked
  require evmErrors.isEmpty s!"EVM rejected its receiver HostOp: {repr evmErrors}"
  let solanaErrors :=
    ProofForge.Compiler.checkHostOpHandlers "solana-sbpf-asm" checked
  require (solanaErrors.any (·.contains "evm.erc721/check_received@1.0.0"))
    "Solana did not reject the EVM receiver HostOp before planning"
  let nearErrors :=
    ProofForge.Compiler.checkHostOpHandlers "wasm-near" checked
  require (nearErrors.any (·.contains "evm.erc721/check_received@1.0.0"))
    "NEAR did not reject the EVM receiver HostOp before planning"
  IO.println "evm-effect-hostop: ok"
