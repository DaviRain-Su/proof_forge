import ProofForge.Contract.Nft
import ProofForge.Contract.Nft.Materialize
import ProofForge.Contract.Intent.Registry

/-!
# Intent Product Boundary Test

Asserts that target selection occurs only through the intent materializer
registry, not through direct `ContractSpec` construction or `targetId`
dispatch in product code.
-/

open ProofForge.Contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  -- Build the NFT intent registry
  let registry ← match NftMaterialize.nftIntentRegistry with
    | .ok r => pure r
    | .error e => throw <| IO.userError s!"registry creation failed: {e}"

  -- Target selection occurs only in registry lookup
  let nftSpec : NFTSpec := { name := "BoundaryTest", symbol := "BT", features := #[.mintable, .transferable] }
  let intent ← match NFTSpec.toIntentContract nftSpec with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"toIntentContract failed: {e}"

  -- Each target is selected through the registry, not by branching on targetId
  for targetId in #["evm", "solana-sbpf-asm", "wasm-near"] do
    let materializer ← match IntentRegistry.resolve registry targetId intent.family with
      | .ok m => pure m
      | .error e => throw <| IO.userError s!"registry lookup for {targetId} failed: {e}"
    let result ← match materializer.materialize intent with
      | .ok mat => pure mat
      | .error e => throw <| IO.userError s!"materialization for {targetId} failed: {e}"
    require (result.targetId == targetId)
      s!"registry selected wrong target for {targetId}: got {result.targetId}"
    require (result.contractSpec.name.length > 0)
      s!"materialized spec for {targetId} has empty name"

  -- Missing target is a named diagnostic, not a silent fallback
  match IntentRegistry.resolve registry "psy-dpn" intent.family with
  | .ok _ => throw <| IO.userError "psy-dpn should not have an NFT materializer"
  | .error e =>
    require (e.contains "no materializer")
      s!"missing materializer diagnostic should mention 'no materializer', got: {e}"

  -- The IntentContract itself does not carry a targetId
  require (intent.featureIds.contains "nft.asset_model.unique")
    "IntentContract must carry asset model discriminator"
  require (!intent.featureIds.contains "evm") "IntentContract must not carry target-specific identifiers"

  IO.println "intent-product-boundary: ok"