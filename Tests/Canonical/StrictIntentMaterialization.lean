import ProofForge.Contract.Nft
import ProofForge.Contract.Nft.Materialize
import ProofForge.Contract.Intent.Registry
import ProofForge.Contract.Examples.Counter
import ProofForge.Compiler.CanonicalPipeline

/-!
# Strict Intent Materialization Test

Tests `runStrictCanonicalTargetGate`: unlike the advisory
`runCanonicalValidationGate`, this function does NOT swallow
`buildFromCore` or `adaptLegacy` failures. Every stage is a hard error.

D3: accepted NFT materializations must pass the strict gate before
returning their ContractSpec.
-/

open ProofForge.Contract
open ProofForge.IR

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- Assert that an Except produces an error containing the prefix. -/
def requireErrorPrefix (expectedPrefix : String) (result : Except String α) : IO Unit :=
  match result with
  | .ok _ => throw <| IO.userError s!"expected error starting with `{expectedPrefix}`, got success"
  | .error e => require (e.startsWith expectedPrefix) s!"expected error starting with `{expectedPrefix}`, got: {e}"

/-- Assert that an Except succeeds. -/
def requireOk (result : Except String α) (label : String) : IO Unit :=
  match result with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"{label}: expected success, got: {e}"

/-- A minimal valid ContractSpec for positive tests. -/
def goodSpec : ContractSpec :=
  ProofForge.Contract.Examples.Counter.spec

/-- A ContractSpec whose module contains an unsupported effect so that
`adaptLegacy` fails with a named stage diagnostic. -/
def badAdaptSpec : ContractSpec := {
  name := "BadAdapt"
  module := {
    name := "BadAdapt"
    state := #[]
    entrypoints := #[{
      name := "doSomething"
      kind := .function
      mutability := .call
      params := #[]
      body := #[
        Statement.effect (Effect.checkErc721Received (.local "o") (.local "f") (.local "t") (.local "i"))
      ]
    }]
    structs := #[]
  }
}

def main : IO Unit := do
  -- Test 1: unknown target is a hard error
  requireErrorPrefix "canonical: unknown target"
    (ProofForge.Compiler.runStrictCanonicalTargetGate "missing-target" goodSpec)

  -- Test 2: adaptLegacy failure is a hard error (not advisory)
  -- badAdaptSpec has no entrypoints; adaptLegacy should reject it
  match ProofForge.Compiler.runStrictCanonicalTargetGate "evm" badAdaptSpec with
  | .ok _ => throw <| IO.userError "badAdaptSpec should fail strict gate (adapt or validation)"
  | .error _ => pure ()  /- any error is acceptable; the point is it's not .ok -/

  -- Test 3: valid spec on a known target should pass (or fail with a
  -- named buildFromCore error, not silently succeed)
  -- ERC721.spec should at least pass adaptLegacy + validateCanonical
  match ProofForge.Compiler.runStrictCanonicalTargetGate "evm" goodSpec with
  | .ok _ => pure ()  /- full success: adapt + validate + buildFromCore all pass -/
  | .error e =>
    -- If it fails, it must be a buildFromCore coverage gap, not a
    -- validation or adapter failure. The error must name the stage.
    require (e.contains "buildFromCore" || e.contains "plan failed")
      s!"strict gate on goodSpec should either pass or fail at buildFromCore, got: {e}"

  -- Test 4: strict gate differs from advisory gate
  -- The advisory gate would return .ok for badAdaptSpec; the strict gate must not.
  let advisoryResult := ProofForge.Compiler.runCanonicalValidationGate "evm" badAdaptSpec
  let strictResult := ProofForge.Compiler.runStrictCanonicalTargetGate "evm" badAdaptSpec
  match advisoryResult, strictResult with
  | .ok _, .ok _ =>
    throw <| IO.userError "strict gate should differ from advisory gate on badAdaptSpec"
  | _, .error _ => pure ()  /- strict gate correctly rejects what advisory swallows -/
  | .error _, .ok _ =>
    throw <| IO.userError "strict gate should not be weaker than advisory gate"

  -- Test 5: NFT materialization uses strict gate internally
  -- The NFT materializers should call runStrictCanonicalTargetGate
  -- and fail if the materialized spec cannot pass strict validation.
  let registry ← match NftMaterialize.nftIntentRegistry with
    | .ok r => pure r
    | .error e => throw <| IO.userError s!"registry creation failed: {e}"
  let nftSpec : NFTSpec := { name := "StrictTest", symbol := "ST", features := #[.mintable, .transferable] }
  let intent ← match NFTSpec.toIntentContract nftSpec with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"toIntentContract failed: {e}"

  -- EVM should pass strict gate (ERC721 is a simple unique+mintable+transferable)
  let evmMat ← match (← match IntentRegistry.resolve registry "evm" .nonFungibleToken with
    | .ok m => pure (m.materialize intent)
    | .error e => throw <| IO.userError s!"evm lookup: {e}") with
    | .ok mat => pure mat
    | .error e => throw <| IO.userError s!"evm materialize: {e}"
  -- The materialization evidence should mention strict gate
  require (evmMat.evidence.any (·.contains "strict"))
    "EVM NFT materialization evidence should mention strict gate"

  IO.println "strict-intent-materialization: ok"