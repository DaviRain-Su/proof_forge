import Examples.Product.Canonical.Counter
import Examples.Product.Canonical.ValueVault
import Examples.Product.Canonical.RemoteCall
import Examples.Product.Canonical.Ownable
import Examples.Product.Canonical.Pausable
import Examples.Product.Canonical.ReentrancyGuard
import Examples.Product.Canonical.AccessControl
import Examples.Product.Canonical.OwnableHash
import Examples.Product.Canonical.OwnablePausable
import Examples.Product.Canonical.GuestBook
import Examples.Product.Canonical.StatusMessage
import Examples.Product.Canonical.HostEnvProbe
import Examples.Product.Canonical.HeightLockVault
import Examples.Product.Canonical.TimelockVault
import Examples.Product.Canonical.ArrayExample
import Examples.Product.Canonical.EscrowVault
import Examples.Product.Canonical.StakingVault
import Examples.Product.Canonical.StorageDeposit
import Examples.Product.Canonical.VestingVault
import Examples.Product.Canonical.ProRataVault
import Examples.Product.Canonical.AuthRemoteCall
import Examples.Product.Canonical.ExternalTokenTransfer
import Examples.Product.Canonical.ExternalVault
import Examples.Product.Canonical.RoleGatedToken
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

def main : IO Unit := do
  checkProduct Examples.Product.Canonical.Counter.contract 3
  checkProduct Examples.Product.Canonical.ValueVault.contract 7
  checkProduct Examples.Product.Canonical.RemoteCall.contract 3
  checkProduct Examples.Product.Canonical.Ownable.contract 4
  checkProduct Examples.Product.Canonical.Pausable.contract 3
  checkProduct Examples.Product.Canonical.ReentrancyGuard.contract 3
  checkProduct Examples.Product.Canonical.AccessControl.contract 4
  checkProduct Examples.Product.Canonical.OwnableHash.contract 3
  checkProduct Examples.Product.Canonical.OwnablePausable.contract 6
  checkProduct Examples.Product.Canonical.GuestBook.contract 5
  checkProduct Examples.Product.Canonical.StatusMessage.contract 3
  checkProduct Examples.Product.Canonical.HostEnvProbe.contract 6
  checkProduct Examples.Product.Canonical.HeightLockVault.contract 7
  checkProduct Examples.Product.Canonical.TimelockVault.contract 7
  checkProduct Examples.Product.Canonical.ArrayExample.contract 3
  checkProduct Examples.Product.Canonical.EscrowVault.contract 10
  checkProduct Examples.Product.Canonical.StakingVault.contract 6
  checkProduct Examples.Product.Canonical.StorageDeposit.contract 5
  checkProduct Examples.Product.Canonical.VestingVault.contract 7
  checkProduct Examples.Product.Canonical.ProRataVault.contract 9
  checkProduct Examples.Product.Canonical.AuthRemoteCall.contract 2
  checkProduct Examples.Product.Canonical.ExternalTokenTransfer.contract 5
  checkProduct Examples.Product.Canonical.ExternalVault.contract 4
  checkProduct Examples.Product.Canonical.RoleGatedToken.contract 8
  checkUnboundPeerRejected Examples.Product.Canonical.AuthRemoteCall.contract
  IO.println "evm-direct-products: ok"
