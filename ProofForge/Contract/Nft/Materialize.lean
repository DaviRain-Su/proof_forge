import ProofForge.Contract.Nft
import ProofForge.Contract.Intent.Registry
import ProofForge.Contract.Stdlib.ERC721
import ProofForge.Contract.Stdlib.MetaplexNft
import ProofForge.Contract.Stdlib.NearNft

/-!
# NFT Materializers

Target-specific materializers that map a portable `NFTSpec` (via
`IntentContract`) to a real `ContractSpec` from the audited stdlib
implementation candidates.

Each materializer:
- Accepts `unique + mintable + transferable` (the first vertical slice)
- Rejects `multiToken` on targets without an equivalent standard
- Rejects every deferred feature (royalties, enumerable, collection, etc.)
- Returns the existing stdlib `ContractSpec` as the materialization result
-/

namespace ProofForge.Contract.NftMaterialize

open ProofForge.Contract

/-- Supported features for the first NFT vertical slice. -/
def supportedFeatures : Array String := #[
  "nft.asset_model.unique",
  "nft.mintable",
  "nft.transferable"
]

/-- Check if a feature ID is supported in the first slice. -/
def isSupportedFeature (featureId : String) : Bool :=
  supportedFeatures.contains featureId

/-- Reject unsupported features with a named diagnostic. -/
def checkFeatures (contract : IntentContract) : Except String Unit := do
  unless contract.family == .nonFungibleToken do
    throw "NFT materializer requires nonFungibleToken intent family"
  let uniqueCount := contract.featureIds.filter (· == "nft.asset_model.unique") |>.size
  let multiCount := contract.featureIds.filter (· == "nft.asset_model.multi_token") |>.size
  unless uniqueCount + multiCount == 1 do
    throw "NFT intent must contain exactly one asset-model discriminator"
  let distinct := contract.featureIds.foldl (fun ids fid =>
    if ids.contains fid then ids else ids.push fid) #[]
  unless distinct.size == contract.featureIds.size do
    throw "NFT intent contains duplicate feature IDs"
  for fid in contract.featureIds do
    unless isSupportedFeature fid do
      throw s!"NFT feature `{fid}` is not supported in the first slice"
  unless contract.featureIds.contains "nft.mintable" do
    throw "NFT first slice requires feature `nft.mintable`"
  unless contract.featureIds.contains "nft.transferable" do
    throw "NFT first slice requires feature `nft.transferable`"

/-- Check that the asset model is unique (not multiToken). -/
def checkUniqueAssetModel (contract : IntentContract) : Except String Unit := do
  if contract.featureIds.contains "nft.asset_model.multi_token" then
    throw "multiToken asset model is not supported on this target"

/-- Keep only the audited first-slice entrypoints from a larger stdlib candidate. -/
def projectEntrypoints (spec : ContractSpec) (names : Array String) : ContractSpec :=
  { spec with module := {
      spec.module with
      entrypoints := spec.module.entrypoints.filter (fun ep => names.contains ep.name)
    } }

def withErc721Selectors (spec : ContractSpec) : ContractSpec :=
  { spec with module := { spec.module with
      entrypoints := spec.module.entrypoints.map fun ep =>
        match ep.name with
        | "init" => { ep with selector? := some "e1c7392a" }
        | "mint" => { ep with selector? := some "40c10f19" }
        | "transferFrom" => { ep with selector? := some "23b872dd" }
        | "ownerOf" => { ep with selector? := some "6352211e" }
        | _ => ep
    } }

/-- EVM NFT materializer: unique → ERC-721. -/
def evmNftMaterializer : IntentMaterializer := {
  targetId := "evm"
  family := .nonFungibleToken
  materialize := fun contract => do
    -- EVM supports ERC-1155 for multiToken, but the first slice defers it
    if contract.featureIds.contains "nft.asset_model.multi_token" then
      throw "multiToken (ERC-1155) is deferred for EVM; use unique asset model"
    checkFeatures contract
    pure {
      targetId := "evm"
      standardId := "erc-721"
      contractSpec := withErc721Selectors <|
        projectEntrypoints Stdlib.ERC721.spec #["init", "mint", "transferFrom", "ownerOf"]
      evidence := #["materialized-from-nft-spec", "standard:erc-721"]
    }
}

/-- Solana NFT materializer: unique → Metaplex. -/
def solanaNftMaterializer : IntentMaterializer := {
  targetId := "solana-sbpf-asm"
  family := .nonFungibleToken
  materialize := fun contract => do
    checkUniqueAssetModel contract
    checkFeatures contract
    pure {
      targetId := "solana-sbpf-asm"
      standardId := "metaplex"
      contractSpec := projectEntrypoints Stdlib.MetaplexNft.spec
        #["init", "mint_nft", "transfer_nft", "nft_owner_of", "nft_total_supply", "nft_balance_of"]
      evidence := #["materialized-from-nft-spec", "standard:metaplex"]
    }
}

/-- NEAR NFT materializer: unique → NEP-171. -/
def nearNftMaterializer : IntentMaterializer := {
  targetId := "wasm-near"
  family := .nonFungibleToken
  materialize := fun contract => do
    checkUniqueAssetModel contract
    checkFeatures contract
    pure {
      targetId := "wasm-near"
      standardId := "nep-171"
      contractSpec := projectEntrypoints Stdlib.NearNft.spec
        #["init", "nft_mint", "nft_transfer", "nft_owner_of", "nft_total_supply", "nft_balance_of"]
      evidence := #["materialized-from-nft-spec", "standard:nep-171"]
    }
}

/-- The NFT intent registry: dispatches (targetId, nonFungibleToken)
to the correct materializer. -/
def nftIntentRegistry : Except String IntentRegistry :=
  IntentRegistry.create #[
    evmNftMaterializer,
    solanaNftMaterializer,
    nearNftMaterializer
  ]

end ProofForge.Contract.NftMaterialize
