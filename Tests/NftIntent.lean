import ProofForge.Contract.Nft
import ProofForge.Contract.Intent.Registry

open ProofForge.Contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  -- Test 1: default NFTSpec has transferable feature
  let default : NFTSpec := { name := "TestNFT", symbol := "TNT" }
  require (default.assetModel == .unique) "default asset model should be unique"
  require (default.features.contains .transferable) "default features should include transferable"

  -- Test 2: duplicate features are rejected
  let dupSpec : NFTSpec := { name := "Dup", symbol := "DUP", features := #[.mintable, .mintable] }
  match NFTSpec.validate dupSpec with
  | .error e => require (e.contains "duplicate") s!"duplicate feature error should mention 'duplicate', got: {e}"
  | .ok _ => throw <| IO.userError "duplicate features should not validate"

  -- Test 3: soulbound + transferable is rejected
  let conflictSpec : NFTSpec := { name := "Conflict", symbol := "CFT", features := #[.soulbound, .transferable] }
  match NFTSpec.validate conflictSpec with
  | .error e => require (e.contains "soulbound") s!"soulbound+transferable error should mention 'soulbound', got: {e}"
  | .ok _ => throw <| IO.userError "soulbound + transferable should not validate"

  -- Test 4: empty spec validates (defaults are sane)
  let emptySpec : NFTSpec := { name := "Empty", symbol := "EMP" }
  match NFTSpec.validate emptySpec with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"empty spec with defaults should validate, got: {e}"

  -- Test 5: stable feature IDs
  require (NFTFeature.mintable.id == "nft.mintable") "mintable id should be nft.mintable"
  require (NFTFeature.burnable.id == "nft.burnable") "burnable id should be nft.burnable"
  require (NFTFeature.transferable.id == "nft.transferable") "transferable id should be nft.transferable"
  require (NFTFeature.soulbound.id == "nft.soulbound") "soulbound id should be nft.soulbound"
  require (NFTFeature.approvals.id == "nft.approvals") "approvals id should be nft.approvals"
  require (NFTFeature.enumerable.id == "nft.enumerable") "enumerable id should be nft.enumerable"
  require (NFTFeature.metadataMutable.id == "nft.metadata_mutable") "metadataMutable id should be nft.metadata_mutable"
  require (NFTFeature.royalties.id == "nft.royalties") "royalties id should be nft.royalties"
  require (NFTFeature.collection.id == "nft.collection") "collection id should be nft.collection"

  -- Test 6: toIntentContract produces correct family and featureIds
  let spec : NFTSpec := { name := "MyNFT", symbol := "MNF", features := #[.mintable, .burnable] }
  let contract := NFTSpec.toIntentContract spec
  require (contract.family == .nonFungibleToken) "family should be nonFungibleToken"
  require (contract.name == "MyNFT") "name should be preserved"
  require (contract.symbol? == some "MNF") "symbol should be preserved"
  require (contract.featureIds.contains "nft.mintable") "featureIds should include mintable"
  require (contract.featureIds.contains "nft.burnable") "featureIds should include burnable"

  -- Test 7: multiToken asset model
  let multiSpec : NFTSpec := { name := "Multi", symbol := "MLT", assetModel := .multiToken, features := #[.mintable, .transferable] }
  match NFTSpec.validate multiSpec with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"multiToken spec should validate, got: {e}"

  IO.println "nft-intent: ok"