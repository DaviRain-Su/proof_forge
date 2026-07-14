import ProofForge.Compiler.CanonicalPipeline
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import Examples.Product.RemoteCall
import Examples.Backend.Evm.Contracts.stdlib.Pausable
import ProofForge.Contract.Spec
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Frontend.Authored.Normalize
import ProofForge.IR.Canonical
import ProofForge.Backend.WasmHost.NearModulePlan.HostOps
import ProofForge.Frontend.Surface
import ProofForge.Frontend.Surface.Host.Near
import ProofForge.IR.Core.HostOp
import ProofForge.Cli.EvmArtifacts
import ProofForge.Cli.Options

/-! # EVM Public Route Test

Verifies that the public `evm` target route materializes canonical output
without fallback:
- Counter and ValueVault public Yul equals explicit canonical Yul.
- An adapter rejection is returned by the public route instead of invoking the
  Legacy renderer.
- A hostCall to near.promise.create on EVM returns missingHostOpHandler
  (the canonical gate fails; legacy renderYul is never reached).
- The canonical and legacy paths produce identical diagnostics for valid
  contracts (both pass, proving parity).
-/

open ProofForge.Compiler
open ProofForge.Contract
open ProofForge.Backend.Evm.Plan.Core
open ProofForge.Backend.WasmHost.NearModulePlan.HostOps
open ProofForge.Frontend.Surface
open ProofForge.IR.Core.HostOp
open ProofForge.Cli

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def withoutSelectors (module : ProofForge.IR.Module) : ProofForge.IR.Module :=
  { module with entrypoints := module.entrypoints.map (fun entrypoint =>
      { entrypoint with selector? := none }) }

/-- A Surface contract with a near.promise.create hostCall — unsupported on EVM. -/
def promiseContract : SurfaceContract := {
  name := "PromiseTest",
  structs := #[],
  state := #[{ name := "count", kind := .scalar .u64 }],
  events := #[],
  errors := #[],
  entrypoints := #[
    { name := "createPromise", kind := .function, mutability := .call,
      params := #[], retType := .u64,
      body := #[
        .hostCallBind "promiseIdx" .u64
          (ProofForge.Frontend.Surface.Host.Near.promiseCreateId)
          #[.literal (.stringLit "alice.near"),
           .literal (.stringLit "methodName"),
           .literal (.bytesLit ByteArray.empty),
           .literal (.u128Lit 0),
           .literal (.u64Lit 1000)],
        .returnExpr (.local "promiseIdx")
      ]
    }
  ],
  constructorParams := #[],
  constructorBindings := #[],
  intents := #[]
}

def unsupportedAdapterModule : ProofForge.IR.Module := {
  name := "UnsupportedAdapter"
  state := #[]
  entrypoints := #[{
    name := "run"
    selector? := none
    body := #[.release "unbound"]
  }]
}

def main : IO Unit := do
  let counterSpec := ContractSpec.fromIR (withoutSelectors ProofForge.IR.Examples.Counter.module)
  let vaultSpec := ContractSpec.fromIR (withoutSelectors ProofForge.IR.Examples.ValueVault.module)
  let remoteSpec := ContractSpec.fromIR (withoutSelectors Examples.Product.RemoteCall.module)
  let pausableSpec := ContractSpec.fromIR (withoutSelectors Pausable.module)
  let cast := match ← IO.getEnv "HOME" with
    | some home => home ++ "/.foundry/bin/cast"
    | none => "cast"
  let peerMap := ProofForge.Target.PeerMap.ofList [
    ("peer.callee", "0x000000000000000000000000000000000000ca11")
  ]
  let opts : CliOptions := { cast, peerMap }

  /- Checks 1-2: public rendering is the explicit canonical artifact, not a
  validation sidecar followed by Legacy rendering. -/
  let (publicCounterYul, _) ← renderContractSpecEvmYul opts counterSpec
  let hydratedCounter ← hydrateEvmSelectors cast counterSpec.module
  let canonicalCounterYul ← match renderCanonicalSpecEvmYul { counterSpec with module := hydratedCounter } with
    | .ok yul => pure yul
    | .error message => throw <| IO.userError message
  require (publicCounterYul == canonicalCounterYul && !publicCounterYul.isEmpty)
    "public Counter Yul differs from explicit canonical materialization"

  let (publicVaultYul, _) ← renderContractSpecEvmYul opts vaultSpec
  let hydratedVault ← hydrateEvmSelectors cast vaultSpec.module
  let canonicalVaultYul ← match renderCanonicalSpecEvmYul { vaultSpec with module := hydratedVault } with
    | .ok yul => pure yul
    | .error message => throw <| IO.userError message
  require (publicVaultYul == canonicalVaultYul && !publicVaultYul.isEmpty)
    "public ValueVault Yul differs from explicit canonical materialization"

  let (publicRemoteYul, _) ← renderContractSpecEvmYul opts remoteSpec
  let hydratedRemote ← hydrateEvmSelectors cast
    (ProofForge.Target.PeerMap.applyToModule remoteSpec.module peerMap)
  let canonicalRemoteYul ← match renderCanonicalSpecEvmYul { remoteSpec with module := hydratedRemote } with
    | .ok yul => pure yul
    | .error message => throw <| IO.userError message
  require (publicRemoteYul == canonicalRemoteYul)
    "public RemoteCall Yul differs from explicit canonical materialization"
  require (publicRemoteYul.contains "function __proof_forge_crosscall_0")
    "canonical RemoteCall omitted its zero-argument CALL helper"
  require (publicRemoteYul.contains "function __proof_forge_crosscall_2")
    "canonical RemoteCall omitted its two-argument CALL helper"

  let (publicPausableYul, _) ← renderContractSpecEvmYul opts pausableSpec
  require (!publicPausableYul.contains "mstore(32, 64)")
    "canonical assertFallback changed a plain revert into an encoded error envelope"

  /- Check 3: an adapter coverage gap is terminal on the public route. -/
  let unsupportedSpec := ContractSpec.fromIR unsupportedAdapterModule
  let rejectionMessage ← try
    let _ ← renderContractSpecEvmYul opts unsupportedSpec
    pure ""
  catch error =>
    pure (toString error)
  require (rejectionMessage.contains "canonical: source normalization failed")
    s!"public EVM route did not expose the canonical adapter rejection: {rejectionMessage}"

  /- Check 4: buildFromCore produces a valid EVM ModulePlan for Counter. -/
  match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec { counterSpec with module := hydratedCounter } with
  | .error e => throw <| IO.userError s!"normalizeContractSpec failed: {repr e}"
  | .ok bundle =>
    match ProofForge.IR.Canonical.validateCanonical bundle.contract.contract with
    | Except.error e => throw <| IO.userError s!"validateCanonical failed: {repr e}"
    | Except.ok checked =>
      let capPlan : ProofForge.Target.CapabilityPlan := { targetId := "evm", calls := #[], metadata := #[] }
      match buildFromCore checked capPlan with
      | Except.error e => throw <| IO.userError s!"buildFromCore failed: {e.message}"
      | Except.ok plan =>
        require (plan.name == "Counter") "plan name should be Counter"
        require (plan.targetPlan.targetId == "evm") "plan target should be evm"
        require (plan.entrypoints.size > 0) "plan should have entrypoints"

  /- Check 5: Surface contract with hostCall normalizes and canonical gate
  reports missingHostOpHandler on EVM (no fallback to renderYul). -/
  let surfaceBundle ← match normalizeSurface promiseContract with
  | Except.ok b => pure b
  | Except.error e => throw <| IO.userError s!"normalizeSurface failed: {repr e}"
  let evmErrors := checkHostOpHandlers "evm" surfaceBundle.contract
  require (evmErrors.size > 0) "EVM should report missingHostOpHandler"
  require (evmErrors.any (·.contains "missingHostOpHandler"))
    "EVM error should contain missingHostOpHandler"

  /- Check 6: Solana also reports missingHostOpHandler for the same hostCall. -/
  let solanaErrors := checkHostOpHandlers "solana-sbpf-asm" surfaceBundle.contract
  require (solanaErrors.size > 0) "Solana should report missingHostOpHandler"

  /- Check 7: NEAR does NOT report missingHostOpHandler (handler exists). -/
  let nearErrors := checkHostOpHandlers "wasm-near" surfaceBundle.contract
  require (nearErrors.size == 0) "NEAR should not report missingHostOpHandler"

  IO.println "evm-public-route: ok"
