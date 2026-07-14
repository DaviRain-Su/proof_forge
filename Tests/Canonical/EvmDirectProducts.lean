import TestFixtures.SurfaceProducts.Counter
import TestFixtures.SurfaceProducts.ValueVault
import TestFixtures.SurfaceProducts.RemoteCall
import TestFixtures.SurfaceProducts.Ownable
import TestFixtures.SurfaceProducts.Pausable
import TestFixtures.SurfaceProducts.ReentrancyGuard
import TestFixtures.SurfaceProducts.AccessControl
import TestFixtures.SurfaceProducts.OwnableHash
import TestFixtures.SurfaceProducts.OwnablePausable
import TestFixtures.SurfaceProducts.GuestBook
import TestFixtures.SurfaceProducts.StatusMessage
import TestFixtures.SurfaceProducts.HostEnvProbe
import TestFixtures.SurfaceProducts.HeightLockVault
import TestFixtures.SurfaceProducts.TimelockVault
import TestFixtures.SurfaceProducts.EscrowVault
import TestFixtures.SurfaceProducts.StakingVault
import TestFixtures.SurfaceProducts.StorageDeposit
import TestFixtures.SurfaceProducts.VestingVault
import TestFixtures.SurfaceProducts.ProRataVault
import TestFixtures.SurfaceProducts.AuthRemoteCall
import TestFixtures.SurfaceProducts.ExternalTokenTransfer
import TestFixtures.SurfaceProducts.ExternalVault
import TestFixtures.SurfaceProducts.RoleGatedToken
import TestFixtures.SurfaceProducts.SoulboundTokenBody
import TestFixtures.SurfaceProducts.Nft
import TestFixtures.SurfaceProducts.ERC4626Vault
import TestFixtures.SurfaceProducts.FungibleToken
import ProofForge.Frontend.Materialize.Evm.Nft
import ProofForge.Target.PeerMap
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Evm.IR
import ProofForge.Frontend.Surface.Normalize

open ProofForge.IR.Canonical
open ProofForge.Target

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def planDirect
    (contract : ProofForge.Frontend.Surface.SurfaceContract) :
    IO ProofForge.Backend.Evm.Plan.ModulePlan := do
  let bundle ← match ProofForge.Frontend.Surface.normalizeSurface contract with
    | .ok bundle => pure bundle
    | .error error => throw (IO.userError s!"{contract.name} Surface normalization failed: {repr error}")
  let capabilityPlan : CapabilityPlan := {
    targetId := "evm"
    calls := bundle.contract.contract.requirements
    metadata := (ProofForge.Target.PeerMap.ofList [
      ("peer.callee", "0x000000000000000000000000000000000000cA11"),
      ("usdc.peer", "0x000000000000000000000000000000000000cA12"),
      ("vault.peer", "0x000000000000000000000000000000000000cA13")
    ]).targetMetadata
  }
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore bundle.contract capabilityPlan with
  | .ok plan => pure plan
  | .error error => throw (IO.userError s!"direct EVM product planning failed: {error.message}")

private def checkProduct
    (contract : ProofForge.Frontend.Surface.SurfaceContract)
    (expectedEntrypoints : Nat) : IO Unit := do
  let plan ← planDirect contract
  require (plan.entrypoints.size == expectedEntrypoints)
    s!"{contract.name} EVM entrypoint count changed"
  require (plan.dispatch.entrypoints.size == expectedEntrypoints &&
      plan.dispatch.entrypoints.all (fun entrypoint => entrypoint.selector.length == 8))
    s!"{contract.name} direct EVM dispatch selectors are incomplete"
  match ProofForge.Backend.Evm.IR.renderCanonicalModuleWithPlan plan with
  | .ok yul =>
      require (yul.contains s!"object \"{contract.name}\"")
        s!"{contract.name} direct EVM renderer lost the product identity"
  | .error error => throw (IO.userError s!"direct EVM product render failed: {error.message}")

private def checkUnboundPeerRejected
    (contract : ProofForge.Frontend.Surface.SurfaceContract) : IO Unit := do
  let bundle ← match ProofForge.Frontend.Surface.normalizeSurface contract with
    | .ok bundle => pure bundle
    | .error error => throw (IO.userError s!"peer Surface normalization failed: {repr error}")
  let capabilityPlan : CapabilityPlan := {
    targetId := "evm", calls := bundle.contract.contract.requirements }
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore bundle.contract capabilityPlan with
  | .error error =>
      require (error.message.contains "unbound or invalid EVM crosscall target")
        "unbound peer did not produce the named EVM diagnostic"
  | .ok _ => throw (IO.userError "unbound EVM peer unexpectedly materialized")

private def checkUnsupportedNftRejected : IO Unit := do
  let unsupported : ProofForge.Contract.NFTSpec := {
    name := "Unsupported", symbol := "UNSUPPORTED",
    features := #[.mintable, .transferable, .approvals] }
  match ProofForge.Frontend.Materialize.Evm.Nft.validate unsupported with
  | .error error =>
      require (error.contains "nft.approvals")
        "unsupported EVM NFT feature did not produce a named diagnostic"
  | .ok _ => throw (IO.userError "unsupported EVM NFT feature unexpectedly validated")

private def checkStandardAbiOverrides : IO Unit := do
  for (contract, entrypointName, paramName) in #[
      (TestFixtures.SurfaceProducts.FungibleToken.contract, "transfer", "amount"),
      (TestFixtures.SurfaceProducts.Nft.contract, "mint", "tokenId") ] do
    let bundle ← match ProofForge.Frontend.Surface.normalizeSurface contract with
      | .ok bundle => pure bundle
      | .error error => throw (IO.userError s!"standard ABI normalization failed: {repr error}")
    let some entrypoint := bundle.contract.contract.interface.entrypoints.find?
        (·.name == entrypointName)
      | throw (IO.userError s!"missing standard entrypoint {entrypointName}")
    let some param := entrypoint.params.find? (·.name == paramName)
      | throw (IO.userError s!"missing standard parameter {paramName}")
    require (param.abiWord? == some "uint256")
      s!"{entrypointName}.{paramName} lost its uint256 ABI carrier"

def main : IO Unit := do
  checkProduct TestFixtures.SurfaceProducts.Counter.contract 3
  checkProduct TestFixtures.SurfaceProducts.ValueVault.contract 7
  checkProduct TestFixtures.SurfaceProducts.RemoteCall.contract 3
  checkProduct TestFixtures.SurfaceProducts.Ownable.contract 4
  checkProduct TestFixtures.SurfaceProducts.Pausable.contract 3
  checkProduct TestFixtures.SurfaceProducts.ReentrancyGuard.contract 3
  checkProduct TestFixtures.SurfaceProducts.AccessControl.contract 4
  checkProduct TestFixtures.SurfaceProducts.OwnableHash.contract 3
  checkProduct TestFixtures.SurfaceProducts.OwnablePausable.contract 6
  checkProduct TestFixtures.SurfaceProducts.GuestBook.contract 5
  checkProduct TestFixtures.SurfaceProducts.StatusMessage.contract 3
  checkProduct TestFixtures.SurfaceProducts.HostEnvProbe.contract 6
  checkProduct TestFixtures.SurfaceProducts.HeightLockVault.contract 7
  checkProduct TestFixtures.SurfaceProducts.TimelockVault.contract 7
  checkProduct TestFixtures.SurfaceProducts.EscrowVault.contract 10
  checkProduct TestFixtures.SurfaceProducts.StakingVault.contract 6
  checkProduct TestFixtures.SurfaceProducts.StorageDeposit.contract 5
  checkProduct TestFixtures.SurfaceProducts.VestingVault.contract 7
  checkProduct TestFixtures.SurfaceProducts.ProRataVault.contract 9
  checkProduct TestFixtures.SurfaceProducts.AuthRemoteCall.contract 2
  checkProduct TestFixtures.SurfaceProducts.ExternalTokenTransfer.contract 5
  checkProduct TestFixtures.SurfaceProducts.ExternalVault.contract 4
  checkProduct TestFixtures.SurfaceProducts.RoleGatedToken.contract 8
  checkProduct TestFixtures.SurfaceProducts.SoulboundTokenBody.contract 5
  checkProduct TestFixtures.SurfaceProducts.Nft.contract 4
  checkProduct TestFixtures.SurfaceProducts.ERC4626Vault.contract 23
  checkProduct TestFixtures.SurfaceProducts.FungibleToken.contract 10
  checkUnsupportedNftRejected
  checkStandardAbiOverrides
  checkUnboundPeerRejected TestFixtures.SurfaceProducts.AuthRemoteCall.contract
  IO.println "evm-direct-products: ok"
