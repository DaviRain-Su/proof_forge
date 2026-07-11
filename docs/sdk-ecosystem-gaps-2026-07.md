# SDK Ecosystem Gap Analysis (2026-07)

Status: **Living gap inventory; EVM receiver/selector MVP closed under PF-P2-02
(2026-07). Last inventory pass: 2026-07-10.**

Gate P0 is closed: the three primary chains have scoped compiler, artifact,
deploy-manifest, testkit, and resource-budget gates for documented fragments.
They remain `experimental`; P0 is not a proof of universal compiler correctness
or production readiness. This page records the SDK / ecosystem feature gaps
that block the goal of broad developer coverage on each chain.

Each section is ordered by priority (P0 = blocks "any contract", P1 =
blocks common patterns, P2 = polish / broader coverage).

## Compliance vocabulary

Implementation coverage is not standard compliance. A source file, selector,
golden artifact, or named smoke proves only the behavior it actually executes.
`just standard-compliance` is the machine gate for standard claims:

- `exact`: every applicable requirement has passing evidence bound to the
  adapter version, artifact digest, oracle version, command, toolchain, and run
  result.
- `scoped`: the same evidence rule passes for an explicit requirement subset.
- `experimental`: evidence is missing, failed, skipped, or not yet bound at
  requirement level.

Current audit output is intentionally conservative. Existing smokes have not
yet been migrated into requirement-bound reports, so none of these standards
is currently `exact`:

| Manifest id | Machine level | Scope |
|---|---|---|
| `erc-20` | `experimental` | ERC-20 mandatory interface/behavior |
| `proof-forge-erc20-product` | `experimental` | Optional metadata and product policies |
| `erc-165` | `experimental` | Interface discovery |
| `erc-721` | `experimental` | NFT core |
| `erc-1155` | `experimental` | Multi-token core |
| `erc-2612` | `experimental` | Atomic permit |
| `erc-4626` | `experimental` | Tokenized vault |
| `erc-173` | `experimental` | Ownership interface |
| `proof-forge-role-access` | `experimental` | Role-access product profile |
| `nep-141` | `experimental` | NEAR fungible token |
| `nep-145` | `experimental` | NEAR storage management |
| `spl-token` | `experimental` | Solana Token Program |
| `spl-token-2022` | `experimental` | Solana Token-2022 extensions |

The tables below retain implementation details, but their status cells must not
be interpreted as a compliance level unless they use one of the three terms
above.

---

## EVM

The EVM backend has the deepest IR coverage: 99 constructors classified
(98 validated, 1 unsupported by design). Foundry + Anvil gates are green.
But the SDK surface — what a Solidity developer would write — has large
gaps.

### Token standards

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| ERC-20 | Implemented subset; compliance `experimental` | `ProofForge/Contract/Stdlib/ERC20.lean` stdlib mixin (transfer/approve/transferFrom/mint/burn + Transfer/Approval events + `transfer_conserves_supply` Lean proof); `Examples/Backend/Evm/Contracts/stdlib/ERC20.lean` golden Yul; `token-intent-evm-vm-smoke.sh` exercises the shared Lean `TokenSpec` SDK path in a Rust/revm VM; `evm-mixin-compose` validates Ownable+ERC-20 composition. `ProofForge/Contract/Token/Evm.lean` is the legacy hand-written Yul path for the Token SDK and remains non-canonical | Bind every ERC-20 requirement to artifact/runtime evidence |
| ERC-721 (NFT) | Implemented transfer subset; compliance `experimental` | `ProofForge/Contract/Stdlib/ERC721.lean` stdlib mixin (ownerOf/transferFrom/safeTransferFrom/mint/burn + three-indexed Transfer event); mandatory balance/approval/operator surfaces and canonical address ABI remain incomplete. **PF-P2-02:** `safeTransferFrom` invokes `onERC721Received` when `extcodesize(to) > 0` (magic `0x150b7a02`); Foundry `testERC721SafeTransferToReceiver_{accepts,rejects}` in `scripts/evm/foundry-smoke.sh` | P0: mandatory core and requirement evidence |
| ERC-1155 (multi-token) | Implemented fixed-size subset; compliance `experimental` | `ProofForge/Contract/Stdlib/ERC1155.lean` covers balances, operator approvals, mint, burn, single `safeTransferFrom`, and custom size-2 `safeBatchTransferFrom2`; this is not the standard arbitrary-length dynamic batch/`TransferBatch` surface | P0: canonical dynamic batch, receiver data, discovery, and evidence |
| ERC-4626 (vault standard) | Implemented vault subset; compliance `experimental` | **Call** peer: `IERC4626` / `external_vault`. **Deploy body:** `Stdlib.ERC4626` pro-rata + entry/exit feeBps + FOT vault+recipient deltas (`just product-erc4626-vault`). Share allowance/delegated exits, total-assets policy, full-width math, and atomic init remain open | P0/P1: close manifest and bind evidence |
| ERC-2612 (permit) | Atomic implementation; default compliance remains `experimental` without a verified build claim | TokenSpec emits canonical `permit(address,address,uint256,uint256,uint8,bytes32,bytes32)`, nonce/domain/deadline checks, low-s/v enforcement, and Approval atomically. `just product-erc20-permit` executes valid, replay, expired, bad-domain, high-s, invalid-v, staging/front-run, and domain-overwrite cases in Foundry. `featureSupportOnTargetWithEvidence` promotes only a full passing claim for the canonical ERC-2612 manifest, exact `proof-forge.evm.erc2612@1` adapter and exact artifact digest | Make production build reports supply the verified claim; absent, partial, forged, wrong-adapter or wrong-artifact evidence stays `experimental` |
| ERC-1820 / ERC-777 | Missing | No hook registry or ERC-777 sender/recipient hooks | P2 |
| ERC-165 (supportsInterface) | Immutable identity implemented; compliance `experimental` pending requirement-bound evidence | `ProofForge/Contract/Stdlib/ERC165.lean` derives the supported set from the contract surface, has no public registration path, and rejects `0xffffffff`; `just evm-standard-identity` and Foundry cover base/custom/unknown/forbidden IDs | Bind exact artifact/runtime results to the ERC-165 manifest |

### Access patterns

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| Ownable / ERC-173 | Canonical identity surface implemented; compliance `experimental` pending requirement-bound evidence | `stdlib/Ownable.lean` keeps a portable u64 owner carrier with EVM `address` ABI metadata, emits `OwnershipTransferred`, and prevents initialization after transfer or renounce; Foundry covers unauthorized calls, stale owners, repeat init, and post-renounce re-init | Bind exact artifact/runtime results to the ERC-173 manifest |
| AccessControl (roles) | EVM standard adapter plus portable policy profile implemented; compliance `experimental` | `stdlib/AccessControl.lean` exposes bytes32 roles, admin lookup/update, grant/revoke/renounce, and canonical events; `AccessControlPortable.lean` retains u64 role handles for shared Solana/Wasm materialization. Foundry covers unauthorized/redundant/confirmation/re-init paths | Complete OZ behavioral equivalence and bind exact evidence; do not conflate the portable role profile with the EVM standard adapter |
| Pausable | Covered (limited) | `stdlib/Pausable.lean` has pause/unpause + `guard_not_paused`/`guard_paused` DSL statements + Lean proof (`not_paused_zero`); `Examples/Backend/Evm/Contracts/stdlib/Pausable.lean` golden Yul. **Limitation:** pause/unpause have no built-in owner/role auth (compose with Ownable/AccessControl for guarded pause) | P1 |
| ReentrancyGuard | Covered | `stdlib/ReentrancyGuard.lean` — reusable `acquireLock`/`releaseLock` mixin via `acquire_lock`/`release_lock` DSL statements; `Examples/Backend/Evm/Contracts/stdlib/ReentrancyGuard.lean` golden Yul. VerifiedVault hand-rolled guard predates the stdlib | — |

### Proxy / Upgrade patterns

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| UUPS proxy | Partial (backend transport spike, E1.4) | `Stdlib/UUPSProxy` + `UUPSUpgradeable` exercise ERC-1967 delegatecall transport. Proxy deployment atomically binds full-width `implementation` and `admin`, rejects zero addresses and implementations without runtime code, and exposes no runtime entrypoint. `upgradeTo` evaluates its candidate once and rejects EOAs and proxy self; `just evm-uups-atomic-init` covers attacker-first calls, constructor/runtime EOA rejection, self rejection, full-width admin authorization, upgrade, and storage preservation. Product EVM builds still reject every `authority` policy, including `proxy_pattern uups`, because `keyRef` remains metadata rather than the constructor-bound runtime authority (`just evm-upgrade-policy-honesty`, `Tests/UpgradePolicy.lean`). The spike does not call `proxiableUUID`, so code-bearing but incompatible implementations can still brick the proxy; implementations must also be valid at zero state because arbitrary initializer delegatecall remains unsupported. Transparent proxy and governance remain unsupported | P1: bind declared `keyRef` to constructor authority, validate UUPS compatibility, and add atomic initializer calldata |
| Transparent proxy | Missing | Same rejection | P1 |
| Beacon proxy | Missing | Same rejection | P2 |
| Diamonds (EIP-2535) | Missing | No facet/loupe storage pattern | P2 |
| CREATE2 factory | Covered (limited, E1.5) | `Stdlib/Create2Factory` + IR `create2`; `deploy(bytes32)` returns ABI `address`, emits `Deployed(address,bytes32)`, and Foundry verifies the deterministic address, event, and deployed runtime. **Explicit defer:** multi-template factories, salt registries, CREATE3 | P2 |

### DeFi primitives

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| AMM / swap | Missing | No pool/swap example | P1 |
| Flash loan | Missing | No flash/loan callback pattern | P2 |
| Staking | Covered (E1.6) | Product `Examples/Product/StakingVault.lean` (1:1 shares, `nativeValue` deposit); triad multi-target `just portable-staking-vault-multi-target`; EVM testkit `staking-vault` scenario; NEAR compare `just near-compare-staking-vault`. Yield/rebase/reward rates deferred | — |
| Vault primitive | Covered (v1) | VerifiedVault + ValueVault + **ERC-4626 stdlib** (pro-rata, fees, FOT); see product v1 freeze | — |
| Oracle integration | Missing | No Chainlink/oracle example | P2 |

### ABI / constructor / errors

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| Custom errors (0.8.4+) | Partial (validated static scalar subset) | **E1.1 static slice:** `ErrorRef.solidityArgWords` + `solidityArgTypes` lower selector + ABI words for `uint8/32/64/128/256`, `bool`, `address`, and `bytes32`. EVM validation rejects malformed selectors, arity/type/range mismatches, and unsupported types. `scripts/evm/errors-ir-smoke.sh` checks a `uint64` value above JS safe-integer range; ContractSpec/client expose schema only, while `scripts/ts/evm-contract-client-smoke.sh` type-checks and executes payload decoding. **Limitation:** the fields are still a transitional EVM annotation on portable `ErrorRef`; typed runtime expression args remain P0. Signed integers, other uint widths, `bytes1..31`, arrays/tuples, dynamic args, and standard ABI `error` entries remain unsupported | P0 remain: typed runtime args through EVM Plan; P1: broader static/dynamic shapes and standard ABI entries |
| Structured events | Covered | Named events, indexed topics, aggregate data — all lowered | — |
| Constructor args | Covered | CLI ABI-encodes static words and dynamic types (`string`/`bytes`/`uint256[]`, CS-3.4) into the initcode tail; deploy manifest records the schema; `DynamicConstructorProbe` exercises `cstring`/`cbytes`/`u256array` with `evmConstructorInitBindings`; deploy-object initcode reads the tail via `codesize()-argsSize` and binds storage at deploy time; Foundry (`foundry-smoke.sh`) and Anvil (`dynamic-constructor-anvil-smoke.sh`) positive smokes | — |
| Storage packing | Covered (D-051) | EVM consecutive small-scalar packing in `Plan/Storage.lean` uses Solidity low-order offsets. Runtime/constructor writes mask field width; checked direct writes and compound assignments reject narrow overflow, while wrapping writes truncate without corrupting neighbors. Evidence: `Tests/Backend/Evm/EvmPackedStorage.lean`, `scripts/evm/packed-storage-ir-smoke.sh`, and `storageLayout` metadata. Hash/map/array/struct remain full-slot; NEAR/WasmHost uses separate `__pf_pack_*` key packing | — |
| Batch operations | Partial | ERC-1155 size-2 batch + `onERC1155BatchReceived` (E1.2); Foundry verifies exact operator/from/id/amount/empty-data callback values and atomic balance rollback on rejection. The current event surface rejects dynamic-array fields, so standard `TransferBatch` and arbitrary-length batch ABI remain open. Multicall3 peer packing exists as an ABI helper; a general multicall product body remains open | P1 |
| Factory deployment | Covered (limited, E1.5) | `Stdlib/Create2Factory` is the reusable fixed-template factory path; ABI/metadata use `address`, and Foundry covers deterministic lifecycle plus `Deployed(address,bytes32)`. Multi-template registries, salt bookkeeping, and CREATE3 remain explicitly deferred | P2 |

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

The `Covered` labels in this table mean that the named instruction slice has a
test. They do not make the aggregate SPL Token manifest exact; its current
machine compliance level is `experimental` until the evidence rows are bound.

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| System transfer | Covered | Live Surfpool + Pinocchio reference | — |
| System create_account | Covered | Live Surfpool + Pinocchio reference | — |
| SPL Token transfer_checked | Covered | Live Surfpool + Pinocchio reference | — |
| SPL Token mint_to/burn/approve/revoke | Covered | Live Surfpool + Pinocchio reference | — |
| SPL Token set_authority | Covered | Live Surfpool/Rust + Pinocchio reference | — |
| Associated Token create_idempotent | Covered | `associatedTokenCreate` builder/surface helper and `contract_source` `associated_token_create_idempotent` syntax emit the Associated Token Program CPI account order, `associated-token.create_idempotent` data layout, token-program metadata, and separated 6-account CPI frame; `solana-associated-token-cpi-web3` deploys the generated program on Surfpool, uses the Rust live RPC harness to create the canonical ATA, and invokes the idempotent path twice | — |
| Memo | Covered (L1.1–L1.3) | `memo`/`invokeMemo` + `memo.memo` CPI; **L1.3** multi-byte via `fixedArray .u8 N` (`raw-bytes` encoding, up to 128 B stack window). Fixture `SolanaMemoCpi`: `log_memo` (u64) + `log_memo_bytes` (16 B). Static: `Tests/Backend/Solana/SolanaCpiPacking.lean`. Live: `just solana-memo-cpi-live` (Surfpool; 8-byte + 16-byte memo program logs). **L1.1 choice:** memo multi-byte over Metaplex (higher-frequency CPI gap; Metaplex deferred P1) | — |
| Stake / Vote / Config | Missing | Extension lowering covers System, Memo, Associated Token, SPL Token, and the Token-2022 transfer-fee/non-transferable/metadata-pointer/default-account-state/immutable-owner/permanent-delegate/interest-bearing/memo-transfer direct CPI subset | P1 |
| ComputeBudgetInstruction | Covered | Solana manifest/IDL/client/package metadata exposes per-entrypoint compute-unit limit and priority-fee advice; generated TS clients emit `ComputeBudgetProgram` pre-instructions | — |

### Token-2022 extensions

Each row below is extension-level implementation evidence, not an aggregate
Token-2022 compliance claim. The versioned extension schema, compatibility,
account-space, initialization-order, and authority requirements remain
`experimental` in `just standard-compliance`.

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
| Metaplex NFT / token metadata | Missing (deferred L1.1) | No Metaplex helpers yet. **L1.1 priority (2026-07-10):** chose **memo arbitrary-length** over Metaplex as the Solana P1 ecosystem surface (smaller CPI delta, live Surfpool gate already present). Metaplex remains next high-value follow-up | P1 |
| Compressed NFTs (Bubblegum) | Missing | No Bubblegum support | P2 |
| SPL Governance | Missing | No governance program support | P2 |
| Anchor-style derive constraints | Partial | Manual `accountConstraint` / `pdaAccount` primitives; no derive macro | P1 |
| Pinocchio reference breadth | Partial (7/10) | L1.4 added `spl-token-close-account` + `memo` (7 total with system-transfer, system-create-account, spl-token-transfer, spl-token-ops, spl-token-authority). Suite: `just solana-pinocchio-reference-equivalence` (7 CI-safe smokes). Remaining toward ≥10: ATA, Token-2022, sysvar, or further SPL helpers | P1 |

---

## NEAR / Wasm

The NEAR/Wasm backend has the shallowest SDK surface of the primary triad.
EmitWat covers scalar/map state, events, hash, context, control flow, arrays,
and many product sources — but NEP economics, full Promise peer execution, and
dynamic Borsh values and full target-native identity/amount widths remain main
depth gaps.

### N1.1 product × wasm-near inventory (2026-07-10)

Probe: `proof-forge build --target wasm-near` on Product sources after S0 merge.

| Source | Authoring | Build | Notes / ABI shape |
|--------|-----------|------:|-------------------|
| `Counter.lean` | contract_source | OK | scalar u64; offline-host lifecycle green |
| `ValueVault.lean` | contract_source | OK | multi-entrypoint; multi-i64 params present in WAT |
| `Ownable.lean` / policies | contract_source | OK | caller/auth portable path |
| `ArrayExample.lean` | contract_source | OK | fixed array ops |
| `RemoteCall.lean` | contract_source | OK | Promise encoding in WAT; standalone offline peer returns 49, testkit peer integration still N1.4 |
| `StakingVault.lean` | contract_source | OK | `nativeValue` path |
| `RoleGatedToken.lean` | contract_source | OK | maps + multi-param entries |
| `EscrowVault.lean` (+ other NEAR-compare vaults) | contract_source | OK | product compile |
| `SoulboundTokenBody.lean` | contract_source | OK | body balances (no TokenSpec) |
| `FungibleToken.lean` / `FeeToken` / `SoulboundToken` | **TokenSpec** | **FAIL** as bare `build` (actionable diagnostic) | needs `--token` / `just product-token-near`; N1.3 message points at TokenSpec path |
| NEP-141 body | stdlib + TokenSpec plan | OK via `just product-token-near` | plan JSON + `NearFungibleToken.wat` |

**Gap classes for N1 (ordered):**

1. **TokenSpec CLI UX** — bare `build` on TokenSpec modules throws ContractSpec missing; authors need a single documented path (N1.3).
2. **Dynamic Borsh** — one authoritative plan now drives Wasm and generated clients for fixed-width values; bytes/string remain unsupported (N1.2).
3. **Promise peer correctness** — materialize exists; sandbox/offline peer returns need N1.4.
4. **NEP-141/145 product depth** — plan+WAT exist; full FT lifecycle + storage deposit economics still shallow (N1.3/N1.5).
5. **Budget honesty** — offline `wasmtimeFuel*` only; real `nearGas` from sandbox (N1.6).

### Contract model

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| Entrypoint ABI (Borsh params + returns) | Partial (N1.2) | `NearAbiPlan` is authoritative for Wasm input validation and generated TypeScript encoding/decoding. `just near-abi-plan` checks malformed input and unsupported-schema rejection; `just near-abi-client-sandbox` proves generated `echo(42n) -> 42n` through raw RPC on near-sandbox. Flat struct/fixedArray are supported; dynamic `bytes`/`string` fail closed | P1 remain: dynamic bytes/string |
| State storage (scalar/map/hash) | Covered | Hash-valued U64/Hash-keyed reads and old-value returns allocate stable per-entrypoint copies; the hash bump allocator resets on every affected entrypoint. `just near-map-hash-alias` and `just near-map-hash-alias-sandbox` retain two reads across later map operations | — |
| Generic events via log_utf8 | Covered | EmitWat event lowering + offline host | — |
| Cross-contract calls (Promise API) | Partial (N1.4) | Host imports + materialize; **offline** `just near-remote-call-offline-peer` (`call_with_args → 49`); **testkit** `just testkit-remote-call` includes NEAR peer observation (N1.4 closed: offline-host materializes promise_create/return → 49 alongside EVM/Solana peers); **sandbox** `just near-sandbox-peer` real PeerOracle; IR semantics remain sum stub (not a peer VM; see `docs/formal-verification.md` § Crosscall honesty) | P1 remain: richer multi-hop peer simulation |
| Callback handling | Partial | `promise_result` host import exists; offline host returns `2` (Failed). Full callback dispatch deferred | P1 |

### Token standards

| Feature | Status | Evidence | Priority |
|---|---|---|---|
| NEP-141 (fungible token) | Implemented lite subset; compliance `experimental` | One-shot init, mint authority, private keyed resolver, bounded refunds and out-of-order callback isolation are executable via `just near-ft-security`, `just wasm-near-ft-transfer-call-e2e`, and `just near-ft-security-sandbox`. Current Borsh/Hash/U64 shape is not the standard JSON AccountId/U128 contract | P0: parameterized interoperable runtime and bound evidence |
| NEP-145 (storage management) | Implemented ledger subset; compliance `experimental` | Product `storage_deposit` plus caller-bound `storage_withdraw` ledger debit; canonical JSON objects, refunds, unregister, complete one-yocto behavior, and requirement evidence remain open | P0/P1 |
| NEP-148 (metadata) | Missing | No metadata fixture | P1 |
| NEP-171 (NFT) | Missing | No NFT example | P1 |
| NEP-178 (NFT enumeration) | Missing | No enumeration example | P2 |
| NEP-245 (multi-token) | Missing | No multi-token example | P2 |

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
| prepaid_gas / used_gas / GAS_PRICE | Missing | No in-contract host imports or portable IR operations | P1 |
| Execution budget reporting (N1.6) | Partial | Offline host reports `wasmtimeFuelCumulative`/`wasmtimeFuelDelta` only (`just near-budget-honesty`); sandbox reports real `nearGas` via `just near-sandbox-peer` | P1 remain: required sandbox budget regression bands |

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
| Deploy metadata honesty (N1.7) | Covered | Build-time `proof-forge-deploy.json` labels `mode=local-offline-host`, `status=not-broadcast`, `broadcast=not-generated`, `networkDeploy=not-generated`, `nearSandbox=not-generated`, `nearAccountId=null`. `validation.deployManifest=passed` only means the manifest JSON was written — not a live deploy. `just near-deploy-honesty` + `scripts/near/validate-emitwat-metadata.py` | — |
| Real NEAR broadcast smoke | Missing | No network broadcast tool for wasm-near; sandbox dual-deploy is compare/live only | P1 |
| near-api-js client wrapper | Covered | Generated `proof-forge-near.ts` exposes `NearViewOptions` for view calls and `NearCallOptions` for gas/attached-deposit mutating calls | — |

---

## Summary: P0 blockers per chain

**EVM (0 open P0, 6 closed):** ERC-20, ERC-721 receiver behavior, immutable ERC-165, separated standard/portable access profiles, dynamic constructor args, and typed runtime custom-error arguments are closed at the implementation level. Runtime error args now enforce static/runtime exclusivity, inferred IR-to-ABI type/range compatibility, structural equality, selector/schema parity, and exact Foundry revert payloads. Remaining P1: arbitrary-length ERC-1155 dynamic batch ABI, dynamic custom-error args / standard ABI entries, and full multicall body. Standards compliance remains requirement-evidence-bound rather than inferred from this P0 count.

**Solana (0 open P0, 5 closed P0):** Account constraint owner validation, user-facing realloc API, SPL Token close-account lowering, ComputeBudgetInstruction, and Token-2022 direct sBPF CPI lowering for transfer_fee + non_transferable + metadata_pointer + default_account_state + immutable_owner + permanent_delegate + interest_bearing + memo_transfer + transfer_hook initialization + pausable are closed. The P1 Associated Token `create_idempotent` CPI gap and Token-2022 transfer-hook `Execute`/extra-account-meta routing are also now covered.

**NEAR (2 open P0, 7 closed):** **Open:** TokenSpec must produce one parameterized runtime artifact; storage withdrawal still needs the predecessor refund Promise. The 1-yocto guard, codec parity, one-shot FT initialization, mint authority, private keyed resolver, bounded refunds, non-aliasing hash-map reads, Promise materialization, signer_account_id, attached_deposit, and fixed-width aggregate ABI have executable coverage.

Total: 2 open P0 blockers across three chains (0 EVM + 0 Solana + 2 NEAR).
Remaining work includes these product-path P0 gaps plus P1 feature expansion.
PF-P2-02 closed EVM receiver callbacks (`onERC721Received`,
`onERC1155Received`), custom-error 4-byte selector surface, and ERC-1155 size-2
batch MVP; PF-P2-03 closed EVM/Solana/NEAR real peer `call_with_args → 49`
(`just testkit-remote-call`, `just near-sandbox-peer`).
