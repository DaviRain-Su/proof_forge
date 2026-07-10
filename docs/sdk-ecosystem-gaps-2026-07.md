# SDK Ecosystem Gap Analysis (2026-07)

Status: **Planning document; audited 2026-07-04**

Gate P0 is closed — the three primary chains have production-grade
compilers, artifact emission, deploy manifests, testkit parity, and
resource budgets. But "production-grade compiler" ≠ "any contract can
be written and deployed." This page records the SDK / ecosystem feature
gaps that block the goal of full developer coverage on each chain.

Each section is ordered by priority (P0 = blocks "any contract", P1 =
blocks common patterns, P2 = polish / broader coverage).

---

## EVM

The EVM backend has the deepest IR coverage: 99 constructors classified
(98 validated, 1 unsupported by design). Foundry + Anvil gates are green.
But the SDK surface — what a Solidity developer would write — has large
gaps.

### Token standards

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| ERC-20 | Covered | `ProofForge/Contract/Stdlib/ERC20.lean` stdlib mixin (transfer/approve/transferFrom/mint/burn + Transfer/Approval events + `transfer_conserves_supply` Lean proof); `Examples/Backend/Evm/Contracts/stdlib/ERC20.lean` golden Yul; `token-intent-evm-vm-smoke.sh` exercises the shared Lean `TokenSpec` SDK path in a Rust/revm VM; `evm-mixin-compose` validates Ownable+ERC-20 composition. `ProofForge/Contract/Token/Evm.lean` is the legacy hand-written Yul path for the Token SDK and remains non-canonical | — |
| ERC-721 (NFT) | Covered | `ProofForge/Contract/Stdlib/ERC721.lean` stdlib mixin (ownerOf/transferFrom/safeTransferFrom/mint/burn + three-indexed Transfer event); `Examples/Backend/Evm/Contracts/stdlib/ERC721.lean` golden Yul. **PF-P2-02:** `safeTransferFrom` invokes `onERC721Received` when `extcodesize(to) > 0` (magic `0x150b7a02`); Foundry `testERC721SafeTransferToReceiver_{accepts,rejects}` in `scripts/evm/foundry-smoke.sh` | — |
| ERC-1155 (multi-token) | Covered (limited) | `ProofForge/Contract/Stdlib/ERC1155.lean` stdlib mixin covers balances, operator approvals, mint, burn, single `safeTransferFrom`, and **size-2 batch** `safeBatchTransferFrom2`; `Examples/Backend/Evm/Contracts/stdlib/ERC1155.lean` golden Yul. **PF-P2-02:** receiver `onERC1155Received` + Foundry accept/reject + `testERC1155SafeBatchTransferFrom2`. **Limitation:** arbitrary-length batch arrays and `onERC1155BatchReceived` remain open | P1 |
| ERC-4626 (vault standard) | Covered (v1 frozen) | **Call** peer: `IERC4626` / `external_vault`. **Deploy body:** `Stdlib.ERC4626` pro-rata + entry/exit feeBps + FOT vault+recipient deltas (`just product-erc4626-vault`). **v2:** fee-recipient re-measure; non-EVM vault body | — |
| ERC-2612 (permit) | Covered (EVM) | Peer client + stdlib body + **TokenSpec `moduleFor` merges ERC20Permit** when `permit` feature set (`Tests/TokenEvm`). DOMAIN still init-set; staged `setPermitSig` | — |
| ERC-1820 / ERC-777 | Missing | No hook registry or ERC-777 sender/recipient hooks | P2 |
| ERC-165 (supportsInterface) | Covered | `ProofForge/Contract/Stdlib/ERC165.lean` stdlib mixin (supportsInterface + registerInterface); `Examples/Backend/Evm/Contracts/stdlib/ERC165.lean` golden Yul | — |

### Access patterns

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| Ownable | Covered | `stdlib/Ownable.lean` — owner storage, onlyOwner, transfer, renounce | — |
| AccessControl (roles) | Covered | `stdlib/AccessControl.lean` — `grantRole`/`revokeRole`/`hasRole` + nested map `(role, account) → membership` + `guard_role` DSL statement; `Examples/Backend/Evm/Contracts/stdlib/AccessControl.lean` golden Yul | — |
| Pausable | Covered (limited) | `stdlib/Pausable.lean` has pause/unpause + `guard_not_paused`/`guard_paused` DSL statements + Lean proof (`not_paused_zero`); `Examples/Backend/Evm/Contracts/stdlib/Pausable.lean` golden Yul. **Limitation:** pause/unpause have no built-in owner/role auth (compose with Ownable/AccessControl for guarded pause) | P1 |
| ReentrancyGuard | Covered | `stdlib/ReentrancyGuard.lean` — reusable `acquireLock`/`releaseLock` mixin via `acquire_lock`/`release_lock` DSL statements; `Examples/Backend/Evm/Contracts/stdlib/ReentrancyGuard.lean` golden Yul. VerifiedVault hand-rolled guard predates the stdlib | — |

### Proxy / Upgrade patterns

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| UUPS proxy | Partial | `ProofForge/Contract/Stdlib/UUPSProxy.lean` and `UUPSUpgradeable.lean` stdlib mixins (ERC-1967 slot + delegatecall fallback); semantic-plan and golden Yul coverage exist. **Gap:** `UpgradePolicy` still rejects non-immutable EVM deployment policies for product contracts | P1 |
| Transparent proxy | Missing | Same rejection | P1 |
| Beacon proxy | Missing | Same rejection | P2 |
| Diamonds (EIP-2535) | Missing | No facet/loupe storage pattern | P2 |
| CREATE2 factory | Covered (limited) | `ProofForge/Contract/Stdlib/Create2Factory.lean` + IR `create2` lowering; Foundry proves deterministic deploy. **Limitation:** advanced factory templates / salt bookkeeping remain product follow-ups | P1 |

### DeFi primitives

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| AMM / swap | Missing | No pool/swap example | P1 |
| Flash loan | Missing | No flash/loan callback pattern | P2 |
| Staking | Missing | No staking example | P2 |
| Vault primitive | Covered (v1) | VerifiedVault + ValueVault + **ERC-4626 stdlib** (pro-rata, fees, FOT); see product v1 freeze | — |
| Oracle integration | Missing | No Chainlink/oracle example | P2 |

### ABI / constructor / errors

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| Custom errors (0.8.4+) | Covered (limited) | IR `revertWithError` + Solidity 4-byte custom-error selector surface (no-args); `scripts/evm/errors-ir-smoke.sh` `test_revertCustomError_selector` (selector `0x09caebf3`); client/metadata expose selector fields. **Limitation:** ABI-encoded custom-error *arguments* beyond selector remain open | P1 |
| Structured events | Covered | Named events, indexed topics, aggregate data — all lowered | — |
| Constructor args | Covered | CLI ABI-encodes static words and dynamic types (`string`/`bytes`/`uint256[]`, CS-3.4) into the initcode tail; deploy manifest records the schema; `DynamicConstructorProbe` exercises `cstring`/`cbytes`/`u256array` with `evmConstructorInitBindings`; deploy-object initcode reads the tail via `codesize()-argsSize` and binds storage at deploy time; Foundry (`foundry-smoke.sh`) and Anvil (`dynamic-constructor-anvil-smoke.sh`) positive smokes | — |
| Storage packing | Missing | One slot per field; no packing/layout optimizer | P1 |
| Batch operations | Partial | ERC-1155 size-2 batch MVP (`safeBatchTransferFrom2`) + Foundry smoke (PF-P2-02). Multicall3 peer packing exists as ABI helper; general multicall product body and arbitrary-length ERC-1155 batch remain open | P1 |
| Factory deployment | Partial | Foundry deploys init code; no reusable factory contract | P1 |

---

## Solana

The Solana backend has the richest SDK extension surface: PDA derivation,
CPI packing, sysvars, syscalls, IDL/client generation, and Pinocchio
reference-equivalence gates. But common ecosystem patterns are still
missing.

### Account model

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| PDA derivation | Covered | `Surface.lean` typed seeds; Rust `pda-rust-smoke.sh` validation | — |
| Account constraints (signer/writable/owner) | Covered | Signer/writable checks lower to the sBPF prologue; owner checks now cover current-program ownership, executable program accounts, and named owner-account references, with missing owner references rejected during lowering | — |
| Multi-account schemas | Covered | Manifest composes state + PDA + CPI + declared accounts | — |
| Close account | Covered | `spl_token_close_account` builder/surface/Learn syntax and CLI fixture routes lower to `spl-token.close_account` metadata and sBPF instruction tag `9`; `just solana-spl-token-close-account-cpi-web3` deploys the generated program on Surfpool, uses the Rust live RPC harness to close an empty SPL Token account through CPI, verifies the account is removed, destination lamports receive rent, and marker state is recorded. Pinocchio equivalence remains a reference-breadth follow-up | — |
| Reallocation | Covered | `reallocAccount` builder/surface helpers and `contract_source` `realloc account to N;` statements emit `solana.account_realloc` metadata, manifest/IDL action records, static `new_size` checks against `MAX_PERMITTED_DATA_INCREASE`, and sBPF data-length stores; Surfpool behavior remains a live validation follow-up | — |
| Address lookup tables | Missing | No ALT support in client or examples | P2 |

### CPI coverage

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| System transfer | Covered | Live Surfpool + Pinocchio reference | — |
| System create_account | Covered | Live Surfpool + Pinocchio reference | — |
| SPL Token transfer_checked | Covered | Live Surfpool + Pinocchio reference | — |
| SPL Token mint_to/burn/approve/revoke | Covered | Live Surfpool + Pinocchio reference | — |
| SPL Token set_authority | Covered | Live Surfpool/Rust + Pinocchio reference | — |
| Associated Token create_idempotent | Covered | `associatedTokenCreate` builder/surface helper and `contract_source` `associated_token_create_idempotent` syntax emit the Associated Token Program CPI account order, `associated-token.create_idempotent` data layout, token-program metadata, and separated 6-account CPI frame; `solana-associated-token-cpi-web3` deploys the generated program on Surfpool, uses the Rust live RPC harness to create the canonical ATA, and invokes the idempotent path twice | — |
| Memo | Covered (one-word payload) | `memo`/`invokeMemo` builder and `contract_source` syntax lower to `memo.memo` CPI metadata, `solana-memo-cpi` target-first fixture, static CPI packing coverage, and `solana-memo-cpi-web3` Surfpool/Rust behavior gate. **Limitation:** current sBPF lowering copies one `u64`/eight-byte raw payload; arbitrary-length memo buffers remain future work | — |
| Stake / Vote / Config | Missing | Extension lowering covers System, Memo, Associated Token, SPL Token, and the Token-2022 transfer-fee/non-transferable/metadata-pointer/default-account-state/immutable-owner/permanent-delegate/interest-bearing/memo-transfer direct CPI subset | P1 |
| ComputeBudgetInstruction | Covered | Solana manifest/IDL/client/package metadata exposes per-entrypoint compute-unit limit and priority-fee advice; generated TS clients emit `ComputeBudgetProgram` pre-instructions | — |

### Token-2022 extensions

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| transfer_fee | Covered | Plan/Surfpool execution plus direct sBPF CPI layouts for initialize config, transfer_checked_with_fee, withdraw/harvest, and set_transfer_fee; `solana-spl-token-2022-cpi-live` deploys the generated program on Surfpool and executes the transfer-fee direct-CPI behavior path through the Rust live RPC harness | — |
| non_transferable | Covered | Plan/Surfpool execution plus direct sBPF CPI layout for initialize_non_transferable_mint; `solana-spl-token-2022-cpi-live` verifies the generated direct-CPI helper through Rust extension parsing | — |
| metadata_pointer | Covered | `splToken2022InitializeMetadataPointer` builder/surface helper emits `token-2022.initialize_metadata_pointer`; sBPF packs `[39, 0, authority, metadata_address]` and `solana-spl-token-2022-cpi-live` verifies the initialized extension through Rust extension parsing | — |
| default_account_state | Covered | `splToken2022InitializeDefaultAccountState` builder/surface helper emits `token-2022.initialize_default_account_state`; sBPF packs `[28, 0, state]` and `solana-spl-token-2022-cpi-live` verifies the initialized frozen default state through Rust extension parsing | — |
| immutable_owner | Covered | `splToken2022InitializeImmutableOwner` builder/surface helper emits top-level Token-2022 `InitializeImmutableOwner` tag 22 and `solana-spl-token-2022-cpi-live` verifies the token-account extension through Rust extension parsing | — |
| permanent_delegate | Covered | `splToken2022InitializePermanentDelegate` builder/surface helper emits top-level Token-2022 `InitializePermanentDelegate` tag 35, packs the delegate pubkey, and `solana-spl-token-2022-cpi-live` verifies the mint extension through Rust extension parsing | — |
| interest_bearing | Covered | `splToken2022InitializeInterestBearingMint` builder/surface helper emits `InterestBearingMintExtension` tag 33 sub-instruction 0, packs the rate authority pubkey plus initial i16 rate, and `solana-spl-token-2022-cpi-live` verifies the initialized rate authority and current rate through Rust extension parsing | — |
| memo_transfer | Covered | `splToken2022EnableRequiredMemoTransfers` builder/surface helper emits `MemoTransferExtension` tag 30 sub-instruction 0 and `solana-spl-token-2022-cpi-live` verifies `requireIncomingTransferMemos` through Rust extension parsing | — |
| pausable | Covered | `splToken2022InitializePausableConfig`, `splToken2022Pause`, and `splToken2022Resume` builder/surface helpers emit `token-2022.initialize_pausable_config`, `token-2022.pause`, and `token-2022.resume`; sBPF packs `[44,0,authority]`, `[44,1]`, and `[44,2]`, and `solana-spl-token-2022-pausable-cpi-live` verifies `PausableConfig.paused` transitions false -> true -> false through the Rust live RPC harness | — |
| confidential_transfer | Missing | No plan or backend support | P1 |
| transfer_hook | Covered | `splToken2022InitializeTransferHook` builder/surface helper emits `token-2022.initialize_transfer_hook`; sBPF packs `[36, 0, authority, transfer_hook_program_id]` and `solana-spl-token-2022-cpi-live` verifies the initialized mint extension through Rust extension parsing. The generated transfer-hook fixture also lowers the external `Execute` discriminator, initializes the validation PDA with two static extra-account metas, routes those metas through a Rust-built Token-2022 transfer-checked instruction with hook accounts, accepts an allowed amount, and rejects an over-limit amount in `just solana-spl-token-2022-transfer-hook-live`; `just solana-spl-token-2022-transfer-hook-web3` remains a compatibility alias. Dynamic extra-account-list mutation remains future polish. | — |

### Ecosystem

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| Metaplex NFT / token metadata | Missing | No Metaplex helpers in Surface or Extension | P1 |
| Compressed NFTs (Bubblegum) | Missing | No Bubblegum support | P2 |
| SPL Governance | Missing | No governance program support | P2 |
| Anchor-style derive constraints | Partial | Manual `accountConstraint` / `pdaAccount` primitives; no derive macro | P1 |
| Pinocchio reference breadth | Partial | 5 reference programs; target ≥10 | P1 |

---

## NEAR / Wasm

The NEAR/Wasm backend has the shallowest SDK surface. EmitWat covers
scalar state, events, hash, context, control flow, arrays, and structs
— but NEAR's real contract model (Promise API, tokens, account model,
economics) is almost entirely missing.

### Contract model

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| Entrypoint ABI (Borsh params + returns) | Partial | Only u32/u64/bool/hash decoded; no aggregate ABI | P0 |
| State storage (scalar/map/hash) | Covered | storage_read/write/has_key lowered | — |
| Generic events via log_utf8 | Covered | EmitWat event lowering + offline host | — |
| Cross-contract calls (Promise API) | Partial | Host imports for `promise_create`/`promise_then`/`promise_results_count`/`promise_result`/`promise_return` in HostBridge. EmitWat crosscall stub lowering (logs intent). Full async promise execution needs account-id string passing | P1 |
| Callback handling | Partial | `promise_result` host import exists; offline host returns `2` (Failed). Full callback dispatch deferred | P1 |

### Token standards

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| NEP-141 (fungible token) | Missing | No FT example or fixture | P0 |
| NEP-145 (storage management) | Partial | `Tests/ContractSource/NearStorageDeposit.lean` covers `storage_deposit`, `storage_balance_of`, and `storage_balance_bounds` with U64 projected balances, Hash-key storage, target-first metadata, and offline-host smoke. Full JSON `StorageBalance`, withdraw/refund, and storage byte accounting remain open | P1 |
| NEP-148 (metadata) | Missing | No metadata fixture | P1 |
| NEP-171 (NFT) | Missing | No NFT example | P1 |
| NEP-178 (NFT enumeration) | Missing | No enumeration example | P2 |
| NEP-448 (multi-token) | Missing | No multi-token example | P2 |

### Account model

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| current_account_id / predecessor_account_id | Partial | Hashed context IDs only; no full account-id string | P1 |
| signer_account_id | Covered | `signer_account_id` host import + `ctxSignerFunc` + `Surface.signer` | — |
| Access keys | Missing | No function-call/full-access key APIs | P1 |
| Storage staking / byte accounting | Missing | No storage_usage / staking host APIs | P1 |

### Economics

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| attached_deposit (native value) | Covered | `attached_deposit` host import + `.nativeValue` EmitWat lowering (U64 truncation of U128); `StoragePathWrite` supports nested `mapKey+mapKey` paths | — |
| balance_of / balance_change | Missing | No balance host APIs | P1 |
| prepaid_gas / used_gas / GAS_PRICE | Missing | Only external fuel reporting; no in-contract gas APIs | P1 |

### Crypto / misc

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| sha256 | Covered | EmitWat + offline host | — |
| keccak256 | Missing | No import beyond sha256 | P1 |
| ripemd160 / ecrecover / ed25519_verify | Missing | No host imports | P1 |
| block_height | Covered | EmitWat + offline host | — |
| block_timestamp | Covered | `block_timestamp` host import + `.contextRead .timestamp` EmitWat lowering + `Surface.timestamp` | — |
| epoch_height | Covered | `epoch_height` host import + `.contextRead .epochHeight` EmitWat lowering + `Surface.epochHeight` | — |
| random_seed | Covered | `random_seed(register_id)` host import + `.contextRead .randomSeed` EmitWat lowering + `Surface.randomSeed`, returning the 32-byte register payload as `Hash` | — |
| storage_remove | Missing | No remove host import | P1 |

### Deployment

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| Real NEAR broadcast smoke | Missing | Deploy metadata is offline-only | P1 |
| near-api-js client wrapper | Covered | Generated `proof-forge-near.ts` exposes `NearViewOptions` for view calls and `NearCallOptions` for gas/attached-deposit mutating calls | — |

---

## Summary: P0 blockers per chain

**EVM (0 open P0, 5 closed):** ERC-20 (closed — stdlib mixin + compose), ERC-721 NFT (closed — stdlib mixin + `onERC721Received` PF-P2-02), ERC-165 (closed — stdlib mixin), AccessControl roles (closed — stdlib mixin), Constructor dynamic args (closed — CS-3.4 runtime init + Foundry/Anvil smokes). **Open:** none at P0. Remaining P1: arbitrary ERC-1155 batch/`onERC1155BatchReceived`, custom-error ABI args, storage packing, full multicall body.

**Solana (0 open P0, 5 closed P0):** Account constraint owner validation, user-facing realloc API, SPL Token close-account lowering, ComputeBudgetInstruction, and Token-2022 direct sBPF CPI lowering for transfer_fee + non_transferable + metadata_pointer + default_account_state + immutable_owner + permanent_delegate + interest_bearing + memo_transfer + transfer_hook initialization + pausable are closed. The P1 Associated Token `create_idempotent` CPI gap and Token-2022 transfer-hook `Execute`/extra-account-meta routing are also now covered.

**NEAR (0 open P0, 6 closed):** Promise API host imports + crosscall stub (closed — P1 for full async), Callback handling (closed — P1 for full dispatch), NEP-141 FT (closed — stdlib mixin), signer_account_id (closed), attached_deposit (closed), Aggregate ABI (closed).

Total: 0 open P0 blockers across three chains (0 EVM + 0 Solana + 0 NEAR).
All three primary chains now have zero open P0 blockers. Remaining work is
P1 feature expansion. PF-P2-02 closed EVM receiver callbacks (`onERC721Received`,
`onERC1155Received`), custom-error 4-byte selector surface, and ERC-1155 size-2
batch MVP; PF-P2-03 closed EVM/Solana real peer `call_with_args → 49`. NEAR
sandbox peer/Promise gates remain external-tool blocked.
