import ProofForge.Contract.Stdlib.ERC721
import ProofForge.Contract.Stdlib.MetaplexNft
import ProofForge.Contract.Stdlib.NearNft
import ProofForge.IR.Semantics

/-! Exact ContractSpec and executable lifecycle audit for the A4 NFT slice. -/

open ProofForge.IR
open ProofForge.IR.Semantics
open ProofForge.Contract.Stdlib

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def entrypoint (mod : Module) (name : String) : IO Entrypoint :=
  match mod.entrypoints.find? (·.name == name) with
  | some ep => pure ep
  | none => throw <| IO.userError s!"missing entrypoint `{name}` in `{mod.name}`"

def requireSignature (mod : Module) (name : String)
    (params : Array (String × ValueType)) (returnType : ValueType) : IO Unit := do
  let ep <- entrypoint mod name
  require (ep.params == params)
    s!"{mod.name}.{name} parameter contract changed: {repr ep.params}"
  require (ep.returns == returnType) s!"{mod.name}.{name} return contract changed"

def run (mod : Module) (name : String) (args : Array Value) (state : State) : IO State := do
  let ep <- entrypoint mod name
  match runEntrypointWithArgs state ep args mod.structs with
  | .ok (next, _) => pure next
  | .error e => throw <| IO.userError s!"{mod.name}.{name} failed: {e}"

def requireReject (mod : Module) (name : String) (args : Array Value)
    (state : State) (needle : String) : IO Unit := do
  let ep <- entrypoint mod name
  match runEntrypointWithArgs state ep args mod.structs with
  | .error e => require (e.contains needle) s!"{mod.name}.{name}: expected `{needle}`, got `{e}`"
  | .ok _ => throw <| IO.userError s!"{mod.name}.{name} unexpectedly succeeded"

def hashValue (n : Nat) : Value := .hash n 0 0 0

def auditErc721 : IO Unit := do
  let mod := ERC721.spec.module
  requireSignature mod "init" #[] .unit
  requireSignature mod "mint" #[("recipient", .u64), ("tokenId", .u64)] .unit
  requireSignature mod "transferFrom"
    #[("holder", .u64), ("recipient", .u64), ("tokenId", .u64)] .unit
  requireSignature mod "ownerOf" #[("tokenId", .u64)] .u64
  let base := (State.empty.write "erc721Initialized" (.u64 0))
    |>.write "erc721MintAuthority" (.u64 0)
    |>.write (mapKey "tokenOwners" "u64:1") (.u64 0)
  let initialized <- run mod "init" #[] { base with userId := .u64 10 }
  requireReject mod "init" #[] initialized "already initialized"
  requireReject mod "mint" #[.u64 7, .u64 1]
    { initialized with userId := .u64 11 } "not mint authority"
  let minted <- run mod "mint" #[.u64 7, .u64 1]
    { initialized with userId := .u64 10 }
  require (minted.read (mapKey "tokenOwners" "u64:1") == some (.u64 7))
    "ERC721 mint did not set owner"
  requireReject mod "mint" #[.u64 7, .u64 1] minted "token exists"
  let transferred <- run mod "transferFrom" #[.u64 7, .u64 8, .u64 1]
    { minted with userId := .u64 7 }
  require (transferred.read (mapKey "tokenOwners" "u64:1") == some (.u64 8))
    "ERC721 transfer did not move owner"
  require (transferred.logs.map (·.name) == #["Transfer", "Transfer"])
    "ERC721 lifecycle event sequence changed"
  require (transferred.logs[0]?.map (·.indexed) == some #[.u64 0, .u64 7, .u64 1])
    "ERC721 mint event payload changed"
  require (transferred.logs[1]?.map (·.indexed) == some #[.u64 7, .u64 8, .u64 1])
    "ERC721 transfer event payload changed"

def auditHashNft (mod : Module) (initName mintName transferName ownerName : String) : IO Unit := do
  requireSignature mod initName #[] .unit
  let mintParams := if mod.name == "MetaplexNft" then
    #[("receiver_id", .hash), ("token_id", .u64), ("update_authority", .hash)]
  else #[("receiver_id", .hash), ("token_id", .u64)]
  requireSignature mod mintName mintParams .unit
  requireSignature mod transferName #[("receiver_id", .hash), ("token_id", .u64)] .unit
  requireSignature mod ownerName #[("token_id", .u64)] .hash
  let initializedKey := if mod.name == "MetaplexNft" then "metaplexInitialized" else "nftInitialized"
  let authorityKey := if mod.name == "MetaplexNft" then "metaplexMintAuthority" else "nftMintAuthority"
  let supplyKey := if mod.name == "MetaplexNft" then "metaplexTotalSupply" else "nftTotalSupply"
  let ownerMap := if mod.name == "MetaplexNft" then "metaplexTokenOwners" else "nftTokenOwners"
  let balances := if mod.name == "MetaplexNft" then "metaplexNftBalances" else "nftBalances"
  let zeroHash := hashValue 0
  let base := (State.empty.write initializedKey (.u64 0))
    |>.write authorityKey zeroHash
    |>.write supplyKey (.u64 0)
    |>.write (mapKey ownerMap "u64:1") zeroHash
    |>.write (mapKey balances "hash:7:0:0:0") (.u64 0)
    |>.write (mapKey balances "hash:8:0:0:0") (.u64 0)
  let base := if mod.name == "MetaplexNft" then
    base.write (mapKey "metaplexUpdateAuthorities" "u64:1") zeroHash else base
  let initialized <- run mod initName #[] { base with userIdHash := hashValue 10 }
  requireReject mod initName #[] initialized "already initialized"
  let mintArgs : Array Value := if mod.name == "MetaplexNft" then
    #[hashValue 7, .u64 1, hashValue 10] else #[hashValue 7, .u64 1]
  requireReject mod mintName mintArgs { initialized with userIdHash := hashValue 11 }
    "not mint authority"
  let minted <- run mod mintName mintArgs { initialized with userIdHash := hashValue 10 }
  require (minted.read (mapKey ownerMap "u64:1") == some (hashValue 7))
    s!"{mod.name} mint did not set owner"
  requireReject mod mintName mintArgs minted "token already exists"
  let transferred <- run mod transferName #[hashValue 8, .u64 1]
    { minted with userIdHash := hashValue 7 }
  require (transferred.read (mapKey ownerMap "u64:1") == some (hashValue 8))
    s!"{mod.name} transfer did not move owner"
  require (transferred.read supplyKey == some (.u64 1))
    s!"{mod.name} transfer changed total supply"
  require (transferred.logs.size == 2) s!"{mod.name} lifecycle should emit mint and transfer"
  require (transferred.logs[0]?.map (fun log => (log.indexed, log.data)) ==
      some (#[hashValue 7], #[.u64 1]))
    s!"{mod.name} mint event payload changed"
  require (transferred.logs[1]?.map (fun log => (log.indexed, log.data)) ==
      some (#[hashValue 7, hashValue 8], #[.u64 1]))
    s!"{mod.name} transfer event payload changed"

def main : IO Unit := do
  auditErc721
  auditHashNft MetaplexNft.spec.module "init" "mint_nft" "transfer_nft" "nft_owner_of"
  auditHashNft NearNft.spec.module "init" "nft_mint" "nft_transfer" "nft_owner_of"
  IO.println "nft-implementation-contract: ok (exact ABI + authority + lifecycle)"
