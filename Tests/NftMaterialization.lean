import ProofForge.Contract.Nft
import ProofForge.Contract.Intent.Registry
import ProofForge.Contract.Nft.Materialize
import ProofForge.Contract.Stdlib.ERC721
import ProofForge.Contract.Stdlib.MetaplexNft
import ProofForge.Contract.Stdlib.NearNft
import ProofForge.Compiler.CanonicalPipeline

open ProofForge.Contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  -- Build the NFT intent registry
  let registry ← match NftMaterialize.nftIntentRegistry with
    | .ok r => pure r
    | .error e => throw <| IO.userError s!"NFT registry creation failed: {e}"

  -- Test 1: EVM materializer resolves to ERC-721 standard
  let spec : NFTSpec := { name := "TestNFT", symbol := "TNT", features := #[.mintable, .transferable] }
  let contract ← match NFTSpec.toIntentContract spec with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"toIntentContract failed: {e}"

  let evmResult ← match IntentRegistry.resolve registry "evm" .nonFungibleToken with
    | .ok m => pure m
    | .error e => throw <| IO.userError s!"evm materializer lookup failed: {e}"
  let evmMat ← match evmResult.materialize contract with
    | .ok mat => pure mat
    | .error e => throw <| IO.userError s!"evm materialization failed: {e}"
  require (evmMat.targetId == "evm") "evm targetId"
  require (evmMat.standardId == "erc-721") s!"evm standardId should be erc-721, got {evmMat.standardId}"
  require (evmMat.contractSpec.name == "ERC721") s!"evm contractSpec name should be ERC721, got {evmMat.contractSpec.name}"

  -- Test 2: Solana materializer resolves to Metaplex standard
  let solResult ← match IntentRegistry.resolve registry "solana-sbpf-asm" .nonFungibleToken with
    | .ok m => pure m
    | .error e => throw <| IO.userError s!"solana materializer lookup failed: {e}"
  let solMat ← match solResult.materialize contract with
    | .ok mat => pure mat
    | .error e => throw <| IO.userError s!"solana materialization failed: {e}"
  require (solMat.targetId == "solana-sbpf-asm") "solana targetId"
  require (solMat.standardId == "metaplex") s!"solana standardId should be metaplex, got {solMat.standardId}"
  require (solMat.contractSpec.name == "MetaplexNft") s!"solana contractSpec name should be MetaplexNft, got {solMat.contractSpec.name}"

  -- Test 3: NEAR materializer resolves to NEP-171 standard
  let nearResult ← match IntentRegistry.resolve registry "wasm-near" .nonFungibleToken with
    | .ok m => pure m
    | .error e => throw <| IO.userError s!"near materializer lookup failed: {e}"
  let nearMat ← match nearResult.materialize contract with
    | .ok mat => pure mat
    | .error e => throw <| IO.userError s!"near materialization failed: {e}"
  require (nearMat.targetId == "wasm-near") "near targetId"
  require (nearMat.standardId == "nep-171") s!"near standardId should be nep-171, got {nearMat.standardId}"
  require (nearMat.contractSpec.name == "NearNft") s!"near contractSpec name should be NearNft, got {nearMat.contractSpec.name}"

  -- Test 4: multiToken rejected on Solana and NEAR (no ERC-1155 equivalent)
  let multiSpec : NFTSpec := { name := "Multi", symbol := "MLT", assetModel := .multiToken, features := #[.mintable, .transferable] }
  let multiContract ← match NFTSpec.toIntentContract multiSpec with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"multiToken toIntentContract failed: {e}"
  match solResult.materialize multiContract with
  | .ok _ => throw <| IO.userError "Solana should reject multiToken NFT"
  | .error e => require (e.contains "multi") s!"Solana multiToken rejection should mention 'multi', got: {e}"
  match nearResult.materialize multiContract with
  | .ok _ => throw <| IO.userError "NEAR should reject multiToken NFT"
  | .error e => require (e.contains "multi") s!"NEAR multiToken rejection should mention 'multi', got: {e}"

  -- Test 5: deferred features are rejected
  let royaltySpec : NFTSpec := { name := "Roy", symbol := "ROY", features := #[.mintable, .transferable, .royalties] }
  let royaltyContract ← match NFTSpec.toIntentContract royaltySpec with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"royalty toIntentContract failed: {e}"
  match evmResult.materialize royaltyContract with
  | .ok _ => throw <| IO.userError "EVM should reject royalties feature"
  | .error e => require (e.contains "royalties") s!"EVM royalty rejection should mention 'royalties', got: {e}"

  -- Test 6: missing target rejected
  match IntentRegistry.resolve registry "psy-dpn" .nonFungibleToken with
  | .ok _ => throw <| IO.userError "psy-dpn should have no NFT materializer"
  | .error e => require (e.contains "no materializer") s!"missing NFT materializer error should mention 'no materializer', got: {e}"

  -- Test 7: canonical pipeline validation on materialized specs
  -- For each target, run adaptLegacy → validateCanonical → buildFromCore
  -- via runCanonicalValidationGate (advisory: buildFromCore failures are ok)
  let canonicalTargets := #["evm", "solana-sbpf-asm", "wasm-near"]
  for targetId in canonicalTargets do
    let mat ← match IntentRegistry.resolve registry targetId .nonFungibleToken with
      | .ok m => match m.materialize contract with
        | .ok mat => pure mat
        | .error e => throw <| IO.userError s!"{targetId} materialization failed: {e}"
      | .error e => throw <| IO.userError s!"{targetId} lookup failed: {e}"
    match ProofForge.Compiler.runCanonicalValidationGate targetId mat.contractSpec with
    | .ok () => pure ()
    | .error e => throw <| IO.userError s!"{targetId} canonical gate failed on materialized NFT spec: {e}"

  IO.println "nft-materialization: ok"