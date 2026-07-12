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
  for fid in contract.featureIds do
    unless isSupportedFeature fid do
      throw s!"NFT feature `{fid}` is not supported in the first slice"

/-- Check that the asset model is unique (not multiToken). -/
def checkUniqueAssetModel (contract : IntentContract) : Except String Unit := do
  if contract.featureIds.contains "nft.asset_model.multi_token" then
    throw "multiToken asset model is not supported on this target"

/-- EVM NFT materializer: unique → ERC-721. -/
def evmNftMaterializer : IntentMaterializer := {
  targetId := "evm"
  family := .nonFungibleToken
  materialize := fun contract => do
    checkFeatures contract
    -- EVM supports ERC-1155 for multiToken, but the first slice defers it
    if contract.featureIds.contains "nft.asset_model.multi_token" then
      throw "multiToken (ERC-1155) is deferred for EVM; use unique asset model"
    pure {
      targetId := "evm"
      standardId := "erc-721"
      contractSpec := Stdlib.ERC721.spec
      evidence := #["materialized-from-nft-spec", "standard:erc-721"]
    }
}

/-- Solana NFT materializer: unique → Metaplex. -/
def solanaNftMaterializer : IntentMaterializer := {
  targetId := "solana-sbpf-asm"
  family := .nonFungibleToken
  materialize := fun contract => do
    checkFeatures contract
    checkUniqueAssetModel contract
    pure {
      targetId := "solana-sbpf-asm"
      standardId := "metaplex"
      contractSpec := Stdlib.MetaplexNft.spec
      evidence := #["materialized-from-nft-spec", "standard:metaplex"]
    }
}

/-- NEAR NFT materializer: unique → NEP-171. -/
def nearNftMaterializer : IntentMaterializer := {
  targetId := "wasm-near"
  family := .nonFungibleToken
  materialize := fun contract => do
    checkFeatures contract
    checkUniqueAssetModel contract
    pure {
      targetId := "wasm-near"
      standardId := "nep-171"
      contractSpec := Stdlib.NearNft.spec
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