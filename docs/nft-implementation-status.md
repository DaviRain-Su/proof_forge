# NFT Implementation Status

Status: **Audit complete (2026-07-12, Task A4)**

## Audit Scope

Each primary-target NFT implementation candidate was audited for the
minimal `unique + mintable + transferable` lifecycle. The audit checks
that the `ContractSpec` exports the expected entrypoints by name. It does
not verify runtime behavior — that is the responsibility of target-specific
gates (`just evm-all`, `just solana-light`, `just wasm-near-plan`).

## Implemented Semantics

### ERC721 (EVM) — `ProofForge/Contract/Stdlib/ERC721.lean`

| Entrypoint | Kind | Parameters | Returns | Semantics |
|---|---|---|---|---|
| `mint` | entry | recipient: address, tokenId: u64 | unit | Rejects zero recipient, rejects existing token, sets owner, emits Transfer |
| `transferFrom` | entry | holder: address, recipient: address, tokenId: u64 | unit | Rejects invalid token, wrong holder, unauthorized, zero recipient; transfers ownership, emits Transfer |
| `safeTransferFrom` | entry | holder: address, recipient: address, tokenId: u64 | unit | Same as transferFrom + `onERC721Received` check for contract recipients |
| `burn` | entry | tokenId: u64 | unit | Rejects non-owner; clears owner, emits Transfer |
| `ownerOf` | query | tokenId: u64 | u64 | Returns owner or rejects invalid token |

Storage: `tokenOwners` map (u64 → u64, tokenId → owner address handle).

### MetaplexNft (Solana) — `ProofForge/Contract/Stdlib/MetaplexNft.lean`

| Entrypoint | Kind | Parameters | Returns | Semantics |
|---|---|---|---|---|
| `init` | entry | (none) | unit | Sets totalSupply to 0 |
| `mint_nft` | entry | receiver_id: hash, token_id: u64, update_authority: hash | unit | Rejects existing token, sets owner, increments balance and supply, emits NftMint |
| `transfer_nft` | entry | receiver_id: hash, token_id: u64 | unit | Rejects non-owner; transfers ownership, adjusts balances, emits NftTransfer |
| `burn_nft` | entry | token_id: u64 | unit | Rejects non-owner; clears owner and authority, decrements balance and supply, emits NftBurn |
| `nft_owner_of` | query | token_id: u64 | hash | Returns owner account hash |
| `nft_total_supply` | query | (none) | u64 | Returns total NFT supply |
| `nft_balance_of` | query | account_id: hash | u64 | Returns NFT balance for account |

Storage: `metaplexTokenOwners` (u64 → hash), `metaplexNftBalances` (hash → u64),
`metaplexUpdateAuthorities` (u64 → hash), `metaplexTotalSupply` (scalar u64).

### NearNft (NEAR) — `ProofForge/Contract/Stdlib/NearNft.lean`

| Entrypoint | Kind | Parameters | Returns | Semantics |
|---|---|---|---|---|
| `init` | entry | (none) | unit | Sets totalSupply, contractName, contractSymbol to 0 |
| `nft_mint` | entry | receiver_id: hash, token_id: u64 | unit | Rejects existing token, sets owner, increments balance and supply, emits NftMint |
| `nft_transfer` | entry | receiver_id: hash, token_id: u64 | unit | Rejects non-owner; transfers ownership, adjusts balances, emits NftTransfer |
| `nft_burn` | entry | token_id: u64 | unit | Rejects non-owner; clears owner, decrements balance and supply, emits NftBurn |
| `nft_owner_of` | query | token_id: u64 | hash | Returns owner account hash |
| `nft_total_supply` | query | (none) | u64 | Returns total NFT supply |
| `nft_balance_of` | query | account_id: hash | u64 | Returns NFT balance for account |
| `nft_approve` | entry | spender_id: hash, token_id: u64 | unit | Rejects non-owner; sets approval, emits NftApproval |
| `nft_metadata` | query | (none) | u64 | Returns contract name (v0: u64 hash projection) |
| `nft_symbol` | query | (none) | u64 | Returns contract symbol (v0: u64 hash projection) |

Storage: `nftTokenOwners` (u64 → hash), `nftBalances` (hash → u64),
`nftApprovals` (u64 → hash), `nftTotalSupply` (scalar u64),
`nftContractName` (scalar u64), `nftContractSymbol` (scalar u64).

## Unsupported Features (Deferred)

| Feature | ERC721 | MetaplexNft | NearNft | Note |
|---|:---:|:---:|:---:|---|
| royalties | ❌ | ❌ | ❌ | Not implemented; deferred to feature promotion |
| enumerable | ❌ | ❌ | ❌ | Not implemented; deferred |
| collection | ❌ | ❌ | ❌ | Not implemented; deferred |
| metadataMutable | ❌ | ✅ (update_metadata) | ❌ | Metaplex has update_authority; others defer |
| approvals | ❌ | ❌ | ✅ (nft_approve) | NearNft has approve; ERC721 defers operator approval |
| multiToken (ERC-1155) | ❌ | ❌ | ❌ | Not implemented; requires separate asset model |
| soulbound | ❌ | ❌ | ❌ | Not implemented; contradicts transferable |

## Cross-Target Naming Convergence

The three implementations use different naming conventions:

| Concept | ERC721 | MetaplexNft | NearNft |
|---|---|---|---|
| mint | `mint` | `mint_nft` | `nft_mint` |
| transfer | `transferFrom` | `transfer_nft` | `nft_transfer` |
| burn | `burn` | `burn_nft` | `nft_burn` |
| ownerOf | `ownerOf` | `nft_owner_of` | `nft_owner_of` |
| totalSupply | (not exported) | `nft_total_supply` | `nft_total_supply` |
| balanceOf | (not exported) | `nft_balance_of` | `nft_balance_of` |

The NFT materializer (Task A5) will normalize these to a portable
interface. The implementations remain as-is; the materializer maps
the portable `NFTSpec` to the target-specific `ContractSpec`.

## Verification

- `Tests/NftImplementationContract.lean` — presence check for all
  expected entrypoints across all three implementations. Passes.
- Target-specific runtime behavior is verified by:
  - EVM: `just evm-all`
  - Solana: `just solana-light`
  - NEAR: `just wasm-near-plan`
- No code repairs were needed; all three implementations already
  support the minimal `unique + mintable + transferable` lifecycle.