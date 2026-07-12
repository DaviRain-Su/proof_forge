import ProofForge.Contract.Stdlib.ERC721
import ProofForge.Contract.Stdlib.MetaplexNft
import ProofForge.Contract.Stdlib.NearNft
import ProofForge.Contract.Source

/-!
# NFT Implementation Contract Audit

Asserts that each primary-target NFT implementation candidate exports
the minimal `unique + mintable + transferable` lifecycle: init, mint,
transfer, owner-of, and burn. This is a presence check, not a runtime
behavior test — `contract_mixin` bodies are `ModuleM Unit` computations
that cannot be introspected at runtime.

The audit confirms the ContractSpec surface exists and names the expected
entrypoints. Runtime behavior is verified by target-specific gates
(`just evm-all`, `just solana-light`, `just wasm-near-plan`).
-/

open ProofForge.Contract.Stdlib

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- Check that a module's entrypoints include the named entry. -/
def hasEntrypoint (mod : ProofForge.IR.Module) (name : String) : Bool :=
  mod.entrypoints.any (·.name == name)

def main : IO Unit := do
  -- ERC721 audit (EVM)
  let ercMod := ERC721.spec.module
  require (ercMod.name == "ERC721") s!"ERC721 module name: {ercMod.name}"
  require (ercMod.entrypoints.size >= 5) "ERC721 should have at least 5 entrypoints"
  require (hasEntrypoint ercMod "mint") "ERC721 missing mint"
  require (hasEntrypoint ercMod "transferFrom") "ERC721 missing transferFrom"
  require (hasEntrypoint ercMod "safeTransferFrom") "ERC721 missing safeTransferFrom"
  require (hasEntrypoint ercMod "burn") "ERC721 missing burn"
  require (hasEntrypoint ercMod "ownerOf") "ERC721 missing ownerOf"

  -- MetaplexNft audit (Solana)
  let mplMod := MetaplexNft.spec.module
  require (mplMod.name == "MetaplexNft") s!"MetaplexNft module name: {mplMod.name}"
  require (hasEntrypoint mplMod "init") "MetaplexNft missing init"
  require (hasEntrypoint mplMod "mint_nft") "MetaplexNft missing mint_nft"
  require (hasEntrypoint mplMod "transfer_nft") "MetaplexNft missing transfer_nft"
  require (hasEntrypoint mplMod "burn_nft") "MetaplexNft missing burn_nft"
  require (hasEntrypoint mplMod "nft_owner_of") "MetaplexNft missing nft_owner_of"
  require (hasEntrypoint mplMod "nft_total_supply") "MetaplexNft missing nft_total_supply"
  require (hasEntrypoint mplMod "nft_balance_of") "MetaplexNft missing nft_balance_of"

  -- NearNft audit (NEAR)
  let nearMod := NearNft.spec.module
  require (nearMod.name == "NearNft") s!"NearNft module name: {nearMod.name}"
  require (hasEntrypoint nearMod "init") "NearNft missing init"
  require (hasEntrypoint nearMod "nft_mint") "NearNft missing nft_mint"
  require (hasEntrypoint nearMod "nft_transfer") "NearNft missing nft_transfer"
  require (hasEntrypoint nearMod "nft_burn") "NearNft missing nft_burn"
  require (hasEntrypoint nearMod "nft_owner_of") "NearNft missing nft_owner_of"
  require (hasEntrypoint nearMod "nft_total_supply") "NearNft missing nft_total_supply"
  require (hasEntrypoint nearMod "nft_balance_of") "NearNft missing nft_balance_of"

  IO.println "nft-implementation-contract: ok"