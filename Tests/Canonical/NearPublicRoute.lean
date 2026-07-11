import ProofForge.Compiler.CanonicalPipeline
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.Contract.Spec
import ProofForge.Contract.Stdlib.NearFungibleToken
import ProofForge.Backend.WasmHost.NearModulePlan.Core
import ProofForge.Backend.WasmHost.NearModulePlan.HostOps
import ProofForge.Frontend.Surface
import ProofForge.Frontend.Surface.Host.Near
import ProofForge.IR.Core.HostOp
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Canonical
import ProofForge.Target
import ProofForge.Cli.ContractSourceArtifacts
import ProofForge.Cli.ContractLoader
import ProofForge.Cli.Options

/-! # NEAR Public Route Test

Verifies that the canonical pipeline owns the `wasm-near` public route:

- Public and explicit canonical Counter artifacts match and produce valid Wasm.
- ValueVault and portable RemoteCall materialize through NearModulePlan.
- A Surface contract with a `near.promise.create` hostCall does NOT report
  `missingHostOpHandler` on `wasm-near` (handler exists).
- The same contract DOES report `missingHostOpHandler` on `evm` and
  `solana-sbpf-asm` (no handler there).
- Adapter failures are terminal and cannot retry Legacy EmitWat.
- `buildFromCore` produces a valid NEAR `NearModulePlan` for Counter.
-/

open ProofForge.Compiler
open ProofForge.Contract
open ProofForge.Backend.WasmHost.NearModulePlan.Core
open ProofForge.Backend.WasmHost.NearModulePlan.HostOps
open ProofForge.Frontend.Surface
open ProofForge.IR.Core.HostOp
open ProofForge.Cli

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def withoutSelectors (module : ProofForge.IR.Module) : ProofForge.IR.Module :=
  { module with entrypoints := module.entrypoints.map (fun entrypoint =>
      { entrypoint with selector? := none }) }

/-- A Surface contract with a near.promise.create hostCall — supported on NEAR. -/
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

unsafe def main : IO Unit := do
  let counterSpec := ContractSpec.fromIR (withoutSelectors ProofForge.IR.Examples.Counter.module)
  let vaultSpec := ContractSpec.fromIR (withoutSelectors ProofForge.IR.Examples.ValueVault.module)

  /- Checks 1-2: public Counter WAT is the explicit canonical artifact and
  the public final build produces a non-empty Wasm binary. -/
  let out := System.FilePath.mk "build/canonical/near-public"
  let input := System.FilePath.mk "Examples/Product/Counter.lean"
  let opts : CliOptions := {
    output? := some out
    input? := some input
    root? := some (System.FilePath.mk ".")
    targetId? := some "wasm-near"
  }
  discard <| compileContractSourceEmitWat opts
  let publicWat ← IO.FS.readFile (out / "counter.wat")
  let wasmBytes ← IO.FS.readBinFile (out / "counter.wasm")
  let loadedCounter ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? none
  let canonicalCounter ← match renderCanonicalSpecNearWat loadedCounter with
    | .ok wat => pure wat
    | .error error => throw <| IO.userError error
  require (publicWat == canonicalCounter && !publicWat.isEmpty)
    "public Counter WAT differs from explicit canonical materialization"
  require (!wasmBytes.isEmpty) "public Counter Wasm is empty"

  let canonicalVault ← match renderCanonicalSpecNearWat vaultSpec with
    | .ok wat => pure wat
    | .error error => throw <| IO.userError error
  require (!canonicalVault.isEmpty) "canonical ValueVault WAT is empty"

  let remoteInput := System.FilePath.mk "Examples/Product/RemoteCall.lean"
  let remoteSpec ← ProofForge.Cli.ContractLoader.loadSpec remoteInput opts.root? none
  let canonicalRemote ← match renderCanonicalSpecNearWat remoteSpec with
    | .ok wat => pure wat
    | .error error => throw <| IO.userError error
  require (canonicalRemote.contains "promise_create" && canonicalRemote.contains "promise_return")
    "canonical portable RemoteCall did not materialize a returned NEAR Promise"

  let fungibleTokenSpec := ContractSpec.fromIR
    (withoutSelectors ProofForge.Contract.Stdlib.NearFungibleToken.module)
  let canonicalFungibleToken ← match renderCanonicalSpecNearWat fungibleTokenSpec with
    | .ok wat => pure wat
    | .error error => throw <| IO.userError error
  require (canonicalFungibleToken.contains "promise_create")
    "canonical NearFungibleToken omitted promise_create"
  require (canonicalFungibleToken.contains "promise_then")
    "canonical NearFungibleToken omitted promise_then"
  require (canonicalFungibleToken.contains "__pf_promise_result_u64")
    "canonical NearFungibleToken omitted promise-result U64 decoding"

  /- Check 3: buildFromCore produces a valid NEAR plan for Counter. -/
  match ProofForge.IR.Legacy.Adapter.adaptLegacy counterSpec with
  | .error e => throw <| IO.userError s!"adaptLegacy failed: {repr e}"
  | .ok bundle =>
    match ProofForge.IR.Canonical.validateCanonical bundle.contract.contract with
    | .error e => throw <| IO.userError s!"validateCanonical failed: {repr e}"
    | .ok checked =>
      let capPlan : ProofForge.Target.CapabilityPlan := {
        targetId := "wasm-near", calls := checked.contract.requirements, metadata := #[]
      }
      match buildFromCore checked capPlan with
      | .error e => throw <| IO.userError s!"buildFromCore failed: {e.message}"
      | .ok plan =>
        require (plan.targetId == "wasm-near") "plan target should be wasm-near"
        require (plan.functions.size > 0) "plan should have functions"
        require (plan.functions.all (fun fn => !fn.blocks.isEmpty)) "function has no blocks"

  /- Check 4: Surface contract with near.promise.create hostCall does NOT
  report missingHostOpHandler on NEAR (handler exists). -/
  let surfaceBundle ← match normalizeSurface promiseContract with
  | .ok b => pure b
  | .error e => throw <| IO.userError s!"normalizeSurface failed: {repr e}"
  let nearErrors := checkHostOpHandlers "wasm-near" surfaceBundle.contract
  require (nearErrors.size == 0) "NEAR should not report missingHostOpHandler"

  /- Check 5: EVM and Solana DO report missingHostOpHandler for the same contract. -/
  let evmErrors := checkHostOpHandlers "evm" surfaceBundle.contract
  require (evmErrors.size > 0) "EVM should report missingHostOpHandler"
  require (evmErrors.any (·.contains "missingHostOpHandler"))
    "EVM error should contain missingHostOpHandler"
  let solanaErrors := checkHostOpHandlers "solana-sbpf-asm" surfaceBundle.contract
  require (solanaErrors.size > 0) "Solana should report missingHostOpHandler"
  require (solanaErrors.any (·.contains "missingHostOpHandler"))
    "Solana error should contain missingHostOpHandler"

  /- Check 6: adapter failure is terminal; public routing cannot retry Legacy. -/
  let unsupportedModule : ProofForge.IR.Module := {
    name := "UnsupportedAdapter"
    state := #[]
    entrypoints := #[{
      name := "run"
      selector? := none
      body := #[.release "unbound"]
    }]
  }
  let unsupportedSpec := ContractSpec.fromIR unsupportedModule
  match renderCanonicalSpecNearWat unsupportedSpec with
  | .error error =>
      require (error.contains "canonical: adapt failed")
        s!"public NEAR route changed canonical rejection: {error}"
  | .ok _ => throw <| IO.userError "public NEAR route accepted unsupported Legacy input"

  IO.println "near-public-route: ok"
