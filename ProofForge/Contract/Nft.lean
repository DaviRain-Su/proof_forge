import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Contract.Intent.Registry

/-!
# Portable NFT Intent

Target-neutral NFT specification. Authors describe asset model and
features; `--target` resolves to ERC-721 / ERC-1155 / Metaplex / NEP-171
through the intent materializer registry.

The first vertical slice supports only `unique + mintable + transferable`.
Additional features are promoted one at a time with runtime evidence.
-/

namespace ProofForge.Contract

/-- NFT asset model: unique (ERC-721 style) or multi-token (ERC-1155 style).
`batch` must not silently change standards as an incidental feature. -/
inductive NFTAssetModel where
  | unique
  | multiToken
  deriving BEq, Repr

/-- NFT features. Each has a stable string ID for diagnostics and registry
dispatch. -/
inductive NFTFeature where
  | mintable
  | burnable
  | transferable
  | soulbound
  | approvals
  | enumerable
  | metadataMutable
  | royalties
  | collection
  deriving BEq, Repr

/-- Stable feature ID string for diagnostics and registry dispatch. -/
def NFTFeature.id : NFTFeature → String
  | .mintable => "nft.mintable"
  | .burnable => "nft.burnable"
  | .transferable => "nft.transferable"
  | .soulbound => "nft.soulbound"
  | .approvals => "nft.approvals"
  | .enumerable => "nft.enumerable"
  | .metadataMutable => "nft.metadata_mutable"
  | .royalties => "nft.royalties"
  | .collection => "nft.collection"

/-- Portable NFT intent spec. No standard field; resolved by `--target`. -/
structure NFTSpec where
  name : String
  symbol : String
  assetModel : NFTAssetModel := .unique
  features : Array NFTFeature := #[.transferable]
  deriving Repr

/-- Check if an NFTSpec has a feature. -/
def NFTSpec.hasFeature (spec : NFTSpec) (feature : NFTFeature) : Bool :=
  spec.features.any (· == feature)

/-- Validate an NFTSpec, returning all deterministic authoring errors
before target selection. -/
def NFTSpec.validate (spec : NFTSpec) : Except String Unit := do
  -- Check for duplicate features
  let ids := spec.features.map NFTFeature.id
  let hasDup := ids.any (fun id => (ids.filter (· == id)).size > 1)
  if hasDup then
    throw "duplicate NFT features in spec"
  -- soulbound + transferable is contradictory
  if spec.hasFeature .soulbound && spec.hasFeature .transferable then
    throw "soulbound and transferable are mutually exclusive"
  -- multiToken + soulbound is contradictory
  if spec.assetModel == .multiToken && spec.hasFeature .soulbound then
    throw "multiToken asset model is incompatible with soulbound"

/-- Convert an NFTSpec to an IntentContract for materializer dispatch. -/
def NFTSpec.toIntentContract (spec : NFTSpec) : IntentContract := {
  family := .nonFungibleToken
  name := spec.name
  symbol? := some spec.symbol
  featureIds := spec.features.map NFTFeature.id
}

end ProofForge.Contract