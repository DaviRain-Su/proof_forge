import ProofForge.Contract.Nft
import ProofForge.Contract.Nft.Materialize
import ProofForge.Contract.Intent.Registry
import ProofForge.Contract.Stdlib.ERC721
import ProofForge.Contract.Stdlib.MetaplexNft
import ProofForge.Contract.Stdlib.NearNft
import ProofForge.Cli.TargetFirst

/-!
# NFT Artifact Schema Test

Verifies that the NFT materialization produces ContractSpecs with the
correct artifact metadata for each primary target. This is a schema
check — it inspects the returned ContractSpec's module name, entrypoint
surface, and materialization evidence, not the rendered artifacts.
-/

open ProofForge.Contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  for targetId in #["evm", "solana-sbpf-asm", "wasm-near"] do
    let parsed ← match ProofForge.Cli.parseNewOptions
        ["--target", targetId, "--nft", "Examples/Product/Nft.lean"] {} with
      | .ok state => pure state
      | .error e => throw <| IO.userError s!"{targetId} --nft parse failed: {e}"
    let (resolvedTarget, request) ← match ProofForge.Cli.resolveBuildRequest parsed with
      | .ok result => pure result
      | .error e => throw <| IO.userError s!"{targetId} --nft request failed: {e}"
    let expectedOp := match targetId with
      | "evm" => ProofForge.Cli.NativeBuildOp.nftEvmBytecode
      | "solana-sbpf-asm" => .nftSolanaSbpf
      | _ => .nftNearEmitWat
    match ProofForge.Cli.resolveBuild resolvedTarget request with
    | .ok { dispatchKind := .native, nativeOp? := some op, .. } =>
        require (op == expectedOp) s!"{targetId} selected the wrong native NFT operation"
    | .ok result => throw <| IO.userError s!"{targetId} NFT build was not native: {repr result}"
    | .error e => throw <| IO.userError s!"{targetId} --nft routing failed: {e}"
    require (parsed.nft) s!"{targetId} route dropped --nft"
    require (parsed.input? == some "Examples/Product/Nft.lean") s!"{targetId} route dropped source"

  let registry ← match NftMaterialize.nftIntentRegistry with
    | .ok r => pure r
    | .error e => throw <| IO.userError s!"registry failed: {e}"

  let nftSpec : NFTSpec := { name := "Proof NFT", symbol := "PNFT", features := #[.mintable, .transferable] }
  let contract ← match NFTSpec.toIntentContract nftSpec with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"toIntentContract failed: {e}"

  -- EVM artifact schema
  let evmMat ← match (← match IntentRegistry.resolve registry "evm" .nonFungibleToken with
    | .ok m => pure (m.materialize contract)
    | .error e => throw <| IO.userError s!"evm lookup: {e}") with
    | .ok mat => pure mat
    | .error e => throw <| IO.userError s!"evm materialize: {e}"
  require (evmMat.standardId == "erc-721") "evm standardId"
  require (evmMat.contractSpec.name == "ERC721") "evm contract name"
  require (evmMat.evidence.contains "materialized-from-nft-spec") "evm evidence"
  -- ERC721 must have the minimal unique + mintable + transferable lifecycle:
  -- mint, transferFrom, ownerOf. Burn may be present but is not required
  -- in the materialized spec surface (contract_mixin composition may filter
  -- features not declared in the NFTSpec feature set).
  let evmMod := evmMat.contractSpec.module
  require (evmMod.entrypoints.any (·.name == "mint")) "evm: mint entrypoint"
  require (evmMod.entrypoints.any (·.name == "transferFrom")) "evm: transferFrom entrypoint"
  require (evmMod.entrypoints.any (·.name == "ownerOf")) "evm: ownerOf entrypoint"

  -- Solana artifact schema
  let solMat ← match (← match IntentRegistry.resolve registry "solana-sbpf-asm" .nonFungibleToken with
    | .ok m => pure (m.materialize contract)
    | .error e => throw <| IO.userError s!"solana lookup: {e}") with
    | .ok mat => pure mat
    | .error e => throw <| IO.userError s!"solana materialize: {e}"
  require (solMat.standardId == "metaplex") "solana standardId"
  require (solMat.contractSpec.name == "MetaplexNft") "solana contract name"
  let solMod := solMat.contractSpec.module
  require (solMod.entrypoints.any (·.name == "mint_nft")) "solana: mint_nft entrypoint"
  require (solMod.entrypoints.any (·.name == "transfer_nft")) "solana: transfer_nft entrypoint"
  require (solMod.entrypoints.any (·.name == "nft_owner_of")) "solana: nft_owner_of entrypoint"

  -- NEAR artifact schema
  let nearMat ← match (← match IntentRegistry.resolve registry "wasm-near" .nonFungibleToken with
    | .ok m => pure (m.materialize contract)
    | .error e => throw <| IO.userError s!"near lookup: {e}") with
    | .ok mat => pure mat
    | .error e => throw <| IO.userError s!"near materialize: {e}"
  require (nearMat.standardId == "nep-171") "near standardId"
  require (nearMat.contractSpec.name == "NearNft") "near contract name"
  let nearMod := nearMat.contractSpec.module
  require (nearMod.entrypoints.any (·.name == "nft_mint")) "near: nft_mint entrypoint"
  require (nearMod.entrypoints.any (·.name == "nft_transfer")) "near: nft_transfer entrypoint"
  require (nearMod.entrypoints.any (·.name == "nft_owner_of")) "near: nft_owner_of entrypoint"

  -- Rejection: soulbound + transferable fails at NFTSpec.validate
  let badSpec : NFTSpec := { name := "Bad", symbol := "BAD", features := #[.soulbound, .transferable] }
  match NFTSpec.toIntentContract badSpec with
  | .ok _ => throw <| IO.userError "soulbound + transferable should not pass validate"
  | .error e => require (e.contains "soulbound") s!"soulbound rejection should mention 'soulbound', got: {e}"

  IO.println "nft-artifact-schema: ok"
