import ProofForge.Contract.Nft
import ProofForge.Contract.Nft.Materialize
import ProofForge.Contract.Intent.Registry
import ProofForge.Compiler.CanonicalPipeline
import ProofForge.Frontend.Surface
import ProofForge.Frontend.Surface.Host.Near

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
  ProofForge.Contract.NftMaterialize.withErc721Selectors
    (ProofForge.Contract.NftMaterialize.projectEntrypoints
      ProofForge.Contract.Stdlib.ERC721.spec #["init", "mint", "transferFrom", "ownerOf"])

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

open ProofForge.Frontend.Surface

def capabilityContract : SurfaceContract := {
  name := "CapabilityOnly"
  structs := #[]
  state := #[]
  events := #[]
  errors := #[]
  entrypoints := #[{
    name := "run", kind := .function, mutability := .call,
    params := #[], retType := .unit, body := #[.returnUnit]
  }]
  constructorParams := #[]
  constructorBindings := #[]
  intents := #[{
    kind := .capability, label := "solana-pda",
    capability? := some .storagePda
  }]
}

def hostOpContract : SurfaceContract := {
  name := "HostOpOnly"
  structs := #[]
  state := #[]
  events := #[]
  errors := #[]
  entrypoints := #[{
    name := "createPromise", kind := .function, mutability := .call,
    params := #[], retType := .u64,
    body := #[
      .hostCallBind "promiseIdx" .u64
        ProofForge.Frontend.Surface.Host.Near.promiseCreateId
        #[.literal (.stringLit "alice.near"),
          .literal (.stringLit "method"),
          .literal (.bytesLit ByteArray.empty),
          .literal (.u128Lit 0),
          .literal (.u64Lit 1000)],
      .returnExpr (.local "promiseIdx")
    ]
  }]
  constructorParams := #[]
  constructorBindings := #[]
}

def builderContract : SurfaceContract := {
  name := "BuilderReject"
  structs := #[]
  state := #[]
  events := #[]
  errors := #[]
  entrypoints := #[{
    name := "hashLiteral", kind := .function, mutability := .view,
    params := #[], retType := .hash,
    body := #[.returnExpr (.literal (.hashLit "not-numeric"))]
  }]
  constructorParams := #[]
  constructorBindings := #[]
}

def normalizeRaw (contract : SurfaceContract) : IO ProofForge.IR.Canonical.CanonicalContract := do
  match ProofForge.Frontend.Surface.normalizeSurface contract with
  | .ok bundle => pure bundle.contract.contract
  | .error e => throw <| IO.userError s!"surface normalization failed: {repr e}"

def main : IO Unit := do
  -- Test 1: unknown target is a hard error
  requireErrorPrefix "canonical: unknown target"
    (ProofForge.Compiler.runStrictCanonicalTargetGate "missing-target" goodSpec)

  -- Test 2: adaptLegacy failure names the adapter stage.
  requireErrorPrefix "canonical: adapt failed"
    (ProofForge.Compiler.runStrictCanonicalTargetGate "evm" badAdaptSpec)

  -- Test 3: a known good spec must pass every strict stage.
  requireOk (ProofForge.Compiler.runStrictCanonicalTargetGate "evm" goodSpec)
    "strict EVM NFT slice"

  -- Test 4: raw canonical validation remains a named hard error.
  let goodCanonical ← normalizeRaw builderContract
  requireErrorPrefix "canonical: validation failed"
    (ProofForge.Compiler.runStrictCanonicalContractGate "evm"
      { goodCanonical with schemaVersion := 999 })

  -- Test 5: capability rejection is distinct from validation and builders.
  let capabilityCanonical ← normalizeRaw capabilityContract
  requireErrorPrefix "canonical: capability plan failed"
    (ProofForge.Compiler.runStrictCanonicalContractGate "evm" capabilityCanonical)

  -- Test 6: a valid typed HostOp without a target handler is rejected at the
  -- handler boundary rather than being hidden by a later builder failure.
  let hostCanonical ← normalizeRaw hostOpContract
  requireErrorPrefix "canonical: unhandled host op"
    (ProofForge.Compiler.runStrictCanonicalContractGate "evm" hostCanonical)

  -- Test 7: valid canonical input unsupported by the target builder names the
  -- final buildFromCore stage.
  requireErrorPrefix "canonical: buildFromCore failed"
    (ProofForge.Compiler.runStrictCanonicalContractGate "solana-sbpf-asm" goodCanonical)

  -- Test 8: strict gate differs from advisory gate
  -- The advisory gate would return .ok for badAdaptSpec; the strict gate must not.
  let advisoryResult := ProofForge.Compiler.runCanonicalValidationGate "evm" badAdaptSpec
  let strictResult := ProofForge.Compiler.runStrictCanonicalTargetGate "evm" badAdaptSpec
  match advisoryResult, strictResult with
  | .ok _, .ok _ =>
    throw <| IO.userError "strict gate should differ from advisory gate on badAdaptSpec"
  | _, .error _ => pure ()  /- strict gate correctly rejects what advisory swallows -/
  | .error _, .ok _ =>
    throw <| IO.userError "strict gate should not be weaker than advisory gate"

  -- Test 9: NFT materialization uses strict gate internally
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
