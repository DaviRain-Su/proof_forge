import ProofForge.Contract.Nft
import ProofForge.Frontend.Surface

/-! Internal NFTSpec to EVM frontend materialization. ERC-721 storage,
authorization, selectors, and events are target-owned here; the portable
NFTSpec remains free of EVM concepts. -/

namespace ProofForge.Frontend.Materialize.Evm.Nft

open ProofForge.Contract
open ProofForge.Frontend.Surface

private def zeroAddress : SurfaceExpr := .literal (.addressLit "0")
private def tokenIdParam : SurfaceParam :=
  { name := "tokenId", type := .u64, abiWord? := some "uint256" }

private def transferEvent (fromAddr toAddr tokenId : SurfaceExpr) : SurfaceStmt :=
  .emit "Transfer" #[fromAddr, toAddr, tokenId]

def validate (nft : NFTSpec) : Except String Unit := do
  nft.validate
  unless nft.assetModel == .unique do
    throw "EVM NFT materializer requires the unique asset model"
  unless nft.hasFeature .mintable do
    throw "EVM NFT materializer requires mintable"
  unless nft.hasFeature .transferable do
    throw "EVM NFT materializer requires transferable"
  for feature in nft.features do
    unless feature == .mintable || feature == .transferable do
      throw s!"EVM NFT feature `{feature.id}` is not implemented"

private def entrypoints : Array SurfaceEntrypoint := #[
  { name := "init", kind := .function, mutability := .call,
    selector? := some "e1c7392a", params := #[], retType := .unit,
    body := #[
      .bind "already_initialized" .bool (.stateRead "initialized"),
      .assert (.unary .not (.local "already_initialized")) "already initialized",
      .bind "authority" .address (.contextRead .sender),
      .stateWrite "initialized" (.literal (.boolLit true)),
      .stateWrite "mint_authority" (.local "authority") ] },
  { name := "mint", kind := .function, mutability := .call,
    selector? := some "40c10f19",
    params := #[{ name := "recipient", type := .address }, tokenIdParam],
    retType := .unit, body := #[
      .bind "caller" .address (.contextRead .sender),
      .bind "authority" .address (.stateRead "mint_authority"),
      .assert (.compare .eq (.local "caller") (.local "authority")) "not mint authority",
      .assert (.compare .ne (.local "recipient") zeroAddress) "zero recipient",
      .bind "existing" .address (.mapRead "token_owners" (.local "tokenId")),
      .assert (.compare .eq (.local "existing") zeroAddress) "token exists",
      .mapWrite "token_owners" (.local "tokenId") (.local "recipient"),
      transferEvent zeroAddress (.local "recipient") (.local "tokenId") ] },
  { name := "transferFrom", kind := .function, mutability := .call,
    selector? := some "23b872dd",
    params := #[{ name := "holder", type := .address },
      { name := "recipient", type := .address }, tokenIdParam],
    retType := .unit, body := #[
      .bind "caller" .address (.contextRead .sender),
      .bind "owner" .address (.mapRead "token_owners" (.local "tokenId")),
      .assert (.compare .ne (.local "owner") zeroAddress) "invalid token",
      .assert (.compare .eq (.local "owner") (.local "holder")) "wrong from",
      .assert (.compare .eq (.local "caller") (.local "holder")) "not authorized",
      .assert (.compare .ne (.local "recipient") zeroAddress) "zero recipient",
      .mapWrite "token_owners" (.local "tokenId") (.local "recipient"),
      transferEvent (.local "holder") (.local "recipient") (.local "tokenId") ] },
  { name := "ownerOf", kind := .function, mutability := .view,
    selector? := some "6352211e", params := #[tokenIdParam],
    retType := .address, body := #[
      .bind "owner" .address (.mapRead "token_owners" (.local "tokenId")),
      .assert (.compare .ne (.local "owner") zeroAddress) "invalid token",
      .returnExpr (.local "owner") ] }
]

def materialize (nft : NFTSpec) : SurfaceContract := {
    name := nft.symbol
    structs := #[]
    state := #[
      { name := "initialized", kind := .scalar .bool },
      { name := "mint_authority", kind := .scalar .address },
      { name := "token_owners", kind := .map .u64 .address none }
    ]
    events := #[{ name := "Transfer", fields := #[
      { name := "from", type := .address, indexed := true },
      { name := "to", type := .address, indexed := true },
      { name := "tokenId", type := .u64, indexed := true, abiWord? := some "uint256" }] }]
    errors := #[]
    entrypoints := entrypoints
    constructorParams := #[]
    constructorBindings := #[]
  }

end ProofForge.Frontend.Materialize.Evm.Nft
