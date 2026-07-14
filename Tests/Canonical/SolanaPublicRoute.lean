import ProofForge.Compiler.CanonicalPipeline
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.Contract.Spec
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Backend.WasmHost.NearModulePlan.HostOps
import ProofForge.Frontend.Surface
import ProofForge.Frontend.Surface.Host.Near
import ProofForge.IR.Core.HostOp
import ProofForge.Frontend.Authored.Normalize
import ProofForge.IR.Canonical
import ProofForge.Target
import ProofForge.Cli.SolanaArtifacts
import ProofForge.Cli.SolanaCommands
import ProofForge.Cli.Options
import ProofForge.Cli.ContractSourceArtifacts
import ProofForge.Cli.ContractLoader
import Examples.Backend.Solana.Contracts.SystemCpi

/-! # Solana Public Route Test

Verifies that the canonical pipeline owns the `solana-sbpf-asm` public route:

- Public and explicit canonical artifacts match.
- A Surface contract with a `near.promise.create` hostCall reports
  `missingHostOpHandler` on `solana-sbpf-asm`.
- Adapter and intent-only CPI failures are terminal.
- `buildFromCore` produces a valid Solana `SolanaModulePlan` for Counter.
-/

open ProofForge.Compiler
open ProofForge.Contract
open ProofForge.Backend.Solana.Plan.Core
open ProofForge.Backend.WasmHost.NearModulePlan.HostOps
open ProofForge.Frontend.Surface
open ProofForge.IR.Core.HostOp
open ProofForge.Cli

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def withoutSelectors (module : ProofForge.IR.Module) : ProofForge.IR.Module :=
  { module with entrypoints := module.entrypoints.map (fun entrypoint =>
      { entrypoint with selector? := none }) }

/-- A Surface contract with a near.promise.create hostCall — unsupported on Solana. -/
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

  /- Checks 1-2: public assembly is the explicit canonical artifact. -/
  let out := System.FilePath.mk "build/canonical/solana-public/Counter.s"
  let input := System.FilePath.mk "Examples/Product/Counter.lean"
  let opts : CliOptions := {
    output? := some out
    input? := some input
    root? := some (System.FilePath.mk ".")
  }
  discard <| compileContractSourceSbpf opts
  let publicCounter ← IO.FS.readFile out
  let loadedCounter ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? none
  let canonicalCounter ← match renderCanonicalSpecSolanaAsm loadedCounter with
    | .ok source => pure source
    | .error error => throw <| IO.userError error
  require (publicCounter == canonicalCounter && !publicCounter.isEmpty)
    "public Counter assembly differs from explicit canonical materialization"
  let canonicalVault ← match renderCanonicalSpecSolanaAsm vaultSpec with
    | .ok source => pure source
    | .error error => throw <| IO.userError error
  require (!canonicalVault.isEmpty) "canonical ValueVault assembly is empty"

  /- Check 3: buildFromCore produces a valid Solana plan for Counter. -/
  match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec counterSpec with
  | .error e => throw <| IO.userError s!"normalizeContractSpec failed: {repr e}"
  | .ok bundle =>
    match ProofForge.IR.Canonical.validateCanonical bundle.contract.contract with
    | .error e => throw <| IO.userError s!"validateCanonical failed: {repr e}"
    | .ok checked =>
      let capPlan : ProofForge.Target.CapabilityPlan := { targetId := "solana-sbpf-asm", calls := checked.contract.requirements, metadata := #[] }
      match buildFromCore checked capPlan with
      | .error e => throw <| IO.userError s!"buildFromCore failed: {e.message}"
      | .ok plan =>
        require (plan.targetId == "solana-sbpf-asm") "plan target should be solana-sbpf-asm"
        require (plan.entrypoints.size > 0) "plan should have entrypoints"

  /- Check 4: Surface contract with near.promise.create hostCall reports
  missingHostOpHandler on Solana (same as EVM). -/
  let surfaceBundle ← match normalizeSurface promiseContract with
  | .ok b => pure b
  | .error e => throw <| IO.userError s!"normalizeSurface failed: {repr e}"
  let solanaErrors := checkHostOpHandlers "solana-sbpf-asm" surfaceBundle.contract
  require (solanaErrors.size > 0) "Solana should report missingHostOpHandler"
  require (solanaErrors.any (·.contains "missingHostOpHandler"))
    "Solana error should contain missingHostOpHandler"

  /- Check 5: NEAR does NOT report missingHostOpHandler (handler exists). -/
  let nearErrors := checkHostOpHandlers "wasm-near" surfaceBundle.contract
  require (nearErrors.size == 0) "NEAR should not report missingHostOpHandler"

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
  match renderCanonicalSpecSolanaAsm unsupportedSpec with
  | .error error =>
      require (error.contains "canonical: source normalization failed")
        s!"public Solana route changed canonical rejection: {error}"
  | .ok _ => throw <| IO.userError "public Solana route accepted unsupported Legacy input"

  /- Check 7: public Solana authoring reaches typed canonical CPI lowering. -/
  match renderCanonicalAuthoredSolanaAsm Examples.Backend.Solana.Contracts.SystemCpi.contract with
  | .error error => throw <| IO.userError s!"direct Authored Solana CPI failed: {error}"
  | .ok source =>
      require (source.contains "solana.cpi.action lamport_transfer" &&
          source.contains "sol_cpi_lamport_transfer")
        "direct Authored Solana CPI disappeared before sBPF lowering"

  IO.println "solana-public-route: ok"
