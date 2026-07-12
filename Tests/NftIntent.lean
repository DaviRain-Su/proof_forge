import ProofForge.Contract

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

  -- Test 4: empty author identity is rejected before target selection
  let emptyName : NFTSpec := { name := "  ", symbol := "EMP" }
  match NFTSpec.validate emptyName with
  | .error e => require (e.contains "name") s!"empty-name diagnostic should name the field, got: {e}"
  | .ok _ => throw <| IO.userError "empty NFT name should not validate"
  let emptySymbol : NFTSpec := { name := "Empty", symbol := "\t" }
  match NFTSpec.validate emptySymbol with
  | .error e => require (e.contains "symbol") s!"empty-symbol diagnostic should name the field, got: {e}"
  | .ok _ => throw <| IO.userError "empty NFT symbol should not validate"

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
  require (NFTAssetModel.unique.id == "nft.asset_model.unique") "unique asset-model id should be stable"
  require (NFTAssetModel.multiToken.id == "nft.asset_model.multi_token") "multi-token asset-model id should be stable"

  -- Test 6: toIntentContract produces correct family and featureIds
  let spec : NFTSpec := { name := "MyNFT", symbol := "MNF", features := #[.mintable, .burnable] }
  let contract <- match NFTSpec.toIntentContract spec with
    | .ok contract => pure contract
    | .error e => throw <| IO.userError s!"valid NFT conversion failed: {e}"
  require (contract.family == .nonFungibleToken) "family should be nonFungibleToken"
  require (contract.name == "MyNFT") "name should be preserved"
  require (contract.symbol? == some "MNF") "symbol should be preserved"
  require (contract.featureIds.contains "nft.mintable") "featureIds should include mintable"
  require (contract.featureIds.contains "nft.burnable") "featureIds should include burnable"
  require (contract.featureIds.contains "nft.asset_model.unique") "featureIds should preserve unique asset model"

  match NFTSpec.toIntentContract conflictSpec with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "toIntentContract must not bypass validation"

  -- Test 7: multiToken asset model
  let multiSpec : NFTSpec := { name := "Multi", symbol := "MLT", assetModel := .multiToken, features := #[.mintable, .transferable] }
  match NFTSpec.validate multiSpec with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"multiToken spec should validate, got: {e}"
  match NFTSpec.toIntentContract multiSpec with
  | .ok contract =>
    require (contract.featureIds.contains "nft.asset_model.multi_token")
      "featureIds should preserve multi-token asset model"
    require (!contract.featureIds.contains "nft.asset_model.unique")
      "multi-token intent must not claim unique asset model"
  | .error e => throw <| IO.userError s!"multiToken conversion failed: {e}"

  IO.println "nft-intent: ok"
