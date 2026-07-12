import ProofForge.Contract.Nft
import ProofForge.Contract.Intent.Registry
import ProofForge.Contract.Nft.Materialize
import ProofForge.Contract.Stdlib.ERC721
import ProofForge.Contract.Stdlib.MetaplexNft
import ProofForge.Contract.Stdlib.NearNft
import ProofForge.Compiler.CanonicalPipeline
import ProofForge.Backend.Solana.Plan.Core

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
  let evmMat ← match materializeIntent registry "evm" contract with
    | .ok mat => pure mat
    | .error e => throw <| IO.userError s!"evm materialization failed: {e}"
  require (evmMat.targetId == "evm") "evm targetId"
  require (evmMat.standardId == "erc-721") s!"evm standardId should be erc-721, got {evmMat.standardId}"
  require (evmMat.contractSpec.name == "ERC721") s!"evm contractSpec name should be ERC721, got {evmMat.contractSpec.name}"
  let evmSelectors := evmMat.contractSpec.module.entrypoints.map fun ep => (ep.name, ep.selector?)
  require (evmSelectors.contains ("init", some "e1c7392a")) "evm init() selector"
  require (evmSelectors.contains ("mint", some "40c10f19")) "evm mint(address,uint256) selector"
  require (evmSelectors.contains ("transferFrom", some "23b872dd")) "evm transferFrom selector"
  require (evmSelectors.contains ("ownerOf", some "6352211e")) "evm ownerOf selector"

  -- Test 2: Solana materializer resolves to Metaplex standard
  let solResult ← match IntentRegistry.resolve registry "solana-sbpf-asm" .nonFungibleToken with
    | .ok m => pure m
    | .error e => throw <| IO.userError s!"solana materializer lookup failed: {e}"
  let solMat ← match materializeIntent registry "solana-sbpf-asm" contract with
    | .ok mat => pure mat
    | .error e => throw <| IO.userError s!"solana materialization failed: {e}"
  require (solMat.targetId == "solana-sbpf-asm") "solana targetId"
  require (solMat.standardId == "metaplex") s!"solana standardId should be metaplex, got {solMat.standardId}"
  require (solMat.contractSpec.name == "MetaplexNft") s!"solana contractSpec name should be MetaplexNft, got {solMat.contractSpec.name}"

  -- Test 3: NEAR materializer resolves to NEP-171 standard
  let nearResult ← match IntentRegistry.resolve registry "wasm-near" .nonFungibleToken with
    | .ok m => pure m
    | .error e => throw <| IO.userError s!"near materializer lookup failed: {e}"
  let nearMat ← match materializeIntent registry "wasm-near" contract with
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
  match evmResult.materialize multiContract with
  | .ok _ => throw <| IO.userError "EVM first slice should reject multiToken NFT"
  | .error e => require (e.contains "ERC-1155") s!"EVM rejection should name ERC-1155, got: {e}"

  -- Test 5: deferred features are rejected
  let royaltySpec : NFTSpec := { name := "Roy", symbol := "ROY", features := #[.mintable, .transferable, .royalties] }
  let royaltyContract ← match NFTSpec.toIntentContract royaltySpec with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"royalty toIntentContract failed: {e}"
  match evmResult.materialize royaltyContract with
  | .ok _ => throw <| IO.userError "EVM should reject royalties feature"
  | .error e => require (e.contains "royalties") s!"EVM royalty rejection should mention 'royalties', got: {e}"

  let deferred : Array NFTFeature := #[.burnable, .soulbound, .approvals,
    .enumerable, .metadataMutable, .royalties, .collection]
  for feature in deferred do
    let features := if feature == .soulbound then #[.mintable, feature]
      else #[.mintable, .transferable, feature]
    let featureSpec : NFTSpec := { name := "Deferred", symbol := "DFR", features }
    let featureContract ← match featureSpec.toIntentContract with
      | .ok value => pure value
      | .error e => throw <| IO.userError s!"deferred feature setup failed: {e}"
    for targetId in #["evm", "solana-sbpf-asm", "wasm-near"] do
      match materializeIntent registry targetId featureContract with
      | .ok _ => throw <| IO.userError s!"{targetId} accepted {feature.id}"
      | .error e => require (e.contains feature.id) s!"{targetId} rejection did not name {feature.id}: {e}"

  -- Test 6: missing target rejected
  match IntentRegistry.resolve registry "psy-dpn" .nonFungibleToken with
  | .ok _ => throw <| IO.userError "psy-dpn should have no NFT materializer"
  | .error e => require (e.contains "no materializer") s!"missing NFT materializer error should mention 'no materializer', got: {e}"

  -- Test 7: every primary target passes the strict canonical target gate.
  let canonicalTargets := #["evm", "solana-sbpf-asm", "wasm-near"]
  for targetId in canonicalTargets do
    let mat ← match IntentRegistry.resolve registry targetId .nonFungibleToken with
      | .ok m => match m.materialize contract with
        | .ok mat => pure mat
        | .error e => throw <| IO.userError s!"{targetId} materialization failed: {e}"
      | .error e => throw <| IO.userError s!"{targetId} lookup failed: {e}"
    require (mat.evidence.any (·.contains "strict"))
      s!"{targetId} materialization evidence should record strict gate"
    match ProofForge.Compiler.runStrictCanonicalTargetGate targetId mat.contractSpec with
    | .ok () => pure ()
    | .error e => throw <| IO.userError s!"{targetId} strict canonical gate failed: {e}"

  let hashNodes := ProofForge.Backend.Solana.Plan.lowerCanonicalHashAccount0
    { id := 999, typeName := "hash" }
  let hashAsm := ProofForge.Backend.Solana.Asm.renderNodes hashNodes
  require (hashAsm.contains "sha256(account[0] full 32-byte pubkey)")
    "Solana canonical sender hash must document the full pubkey input"
  require (hashAsm.contains "[r1+16]" && hashAsm.contains "[r1+24]" &&
      hashAsm.contains "[r1+32]" && hashAsm.contains "[r1+40]")
    "Solana canonical sender hash must load all four pubkey words"
  require (hashAsm.contains "call sol_sha256")
    "Solana canonical sender hash must invoke sol_sha256"
  require (hashAsm.contains "jne r0, 0, error_syscall")
    "Solana canonical sender hash must fail closed on syscall error"

  IO.println "nft-materialization: ok"
