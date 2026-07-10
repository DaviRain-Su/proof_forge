# Capability Registry

Status: **Draft spec (Phase 1)**

Canonical capability ids for target profiles, artifact metadata, and compile-time
rejection. Semantic meanings align with the matrix in
[RFC 0002](rfcs/0002-target-implementation-design.md).

Legend: **Y** supported (planned or implemented), **P** partial/spike only,
**N** not supported, **—** not applicable.

## Relationship to target ids

- Target ids are recorded in `docs/decisions.md` and summarized by
  `docs/rfcs/0002-target-implementation-design.md`.
- This registry owns capability ids, not target lifecycle stages.
- Docs must not invent alternate ids for the same semantics.

## Relationship to Contract Intent and Target Extensions

Capability ids are the lower-level protocol used after target selection, not
the default user-facing SDK. Portable contracts should normally call the
chain-neutral Contract Intent API. The selected target adapter resolves those
intents into a capability plan, then checks this registry before lowering.

Target Extension SDKs may expose target-specific operations such as Solana
PDA/CPI/runtime allocator configuration, Move resources, or UTXO covenant
primitives. Those extensions still route through capability ids and target
metadata so diagnostics, artifact metadata, and cross-target support checks
remain uniform.

## Core Capabilities

> The **Solana** column reflects the canonical `solana-sbpf-asm` route (D-026):
> direct sBPF assembly codegen. Solana uses `crosscall.cpi` (not
> `crosscall.invoke`) and `storage.pda` — these are Solana-specific per D-027.
> The **CF Workers** column is the off-chain `wasm-cloudflare-workers` host
> (D-033). The current registry advertises only the executable Counter
> `storage.scalar` sourcegen subset; broader host mappings remain design work.

| Capability id | Portable meaning | EVM | NEAR | CosmWasm | Solana | Aptos | Sui | Psy DPN | CF Workers |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `storage.scalar` | Single persistent scalar | Y | Y | Y | Y | Y | Y | Y | Y |
| `storage.map` | Key-value or mapping storage | Y | Y | Y | P | P | N | P | N |
| `storage.array` | Fixed-size indexed storage array | P | P | N | Y | N | N | P | N |
| `caller.sender` | Transaction signer/caller | Y | Y | Y | Y | Y | N | P | N |
| `value.native` | Native token attached to call | Y | Y | Y | Y | Y | N | N | N |
| `events.emit` | Structured log/event output | Y | Y | Y | Y | Y | N | Y | N |
| `crosscall.invoke` | Call another contract/program | Y | Y | Y | Y | Y | N | P | N |
| `env.block` | Block height/time/chain id reads | Y | Y | P | P | P | N | P | N |
| `control.conditional` | Statement-level conditional branches with target-supported boolean predicates | P | P | N | Y | N | N | P | N |
| `control.bounded_loop` | Static bounded loops that can be flattened or unrolled by the target | P | P | N | P | N | N | P | N |
| `data.fixed_array` | Fixed-size array value type, literals, and index expressions | P | P | N | Y | N | N | P | N |
| `data.dynamic_bytes` | Dynamic-length bytes/string value type with head-tail ABI encoding | Y | N | N | N | N | N | N | N |
| `data.struct` | Struct value type, literals, and field access | P | P | N | Y | N | N | P | N |
| `crypto.hash` | Host or library hashing | Y | Y | Y | Y | Y | N | Y | N |
| `assertions.check` | Runtime or circuit assertions emitted from portable IR statements | Y | Y | N | Y | N | Y | Y | N |
| `account.explicit` | Named account/object/resource binding | P | Y | N | Y | Y | Y | P | N |
| `storage.pda` | Program-derived address state | N | N | N | Y | N | N | N | N |
| `runtime.allocator` | Target runtime heap allocator contract | N | N | N | Y | N | N | N | N |
| `runtime.memory` | Target runtime memory operations | N | N | N | Y | N | N | N | N |
| `runtime.return_data` | Target runtime return-data buffer operations | N | N | N | Y | N | N | N | N |
| `runtime.compute_units` | Target runtime compute-budget introspection | N | N | N | P | N | N | N | N |
| `crosscall.cpi` | Solana CPI with account metas | N | N | N | Y | N | N | N | N |
| `arith.checked` | Integer arithmetic reverts on overflow (Solidity 0.8 semantics) | Y | N | N | N | N | N | N | N |
| `zk.circuit` | Compile entrypoints into target circuit definitions | N | N | N | N | N | N | Y | N |
| `zk.proof` | Target proof generation or verification flow | N | N | N | N | N | N | P | N |

## Id Naming Rules

- Format: `<domain>.<operation>` or `<domain>.<variant>` (lowercase, dot-separated).
- Domains: `storage`, `caller`, `value`, `events`, `crosscall`, `env`, `control`, `data`, `crypto`, `assertions`, `account`, `runtime`, `arith`, `zk`.
- Artifact metadata lists the ids used by a build (see RFC 0002 artifact schema).
- Diagnostics must cite capability id and target id on rejection.

## Semantic Divergence Notes

These capabilities document known cross-target semantic divergences that the
capability gate exposes but does not yet enforce per-node. They are the place
to look when a portable contract behaves differently across targets.

### `arith.checked` — integer overflow semantics

The portable IR `Expr.add/.sub/.mul` nodes each carry an explicit
`overflowChecked : Bool` field (default `true`, matching Solidity 0.8 / EVM
checked-arithmetic semantics). The `+!`/`-!`/`*!` surface operators and the
`Builder.add/sub/mul`/`Surface.add/sub/mul` helpers default to `true`, so a
plain `.add lhs rhs` lowers to checked-revert on EVM and to native wrapping on
Solana/NEAR. The lowering is per-node and no longer silently divergent:

- **EVM** lowers a node to Solidity-0.8-style checked arithmetic (`__pf_checked_add/sub/mul`) that reverts on overflow when `overflowChecked := true`, and to wrapping Yul builtins (`add`/`sub`/`mul`) when `overflowChecked := false`. EVM therefore declares `arith.checked`.
- **Solana (sBPF)** and **NEAR (Wasm)** ignore the per-node flag and always lower to native `add64/mul64` / `i64.add` which **wrap silently** on overflow. They do **not** declare `arith.checked`.

The per-node flag controls EVM lowering but does **not** declare the
`arith.checked` capability on its own (a portable contract using `+!` still
resolves to all targets, wrapping on Solana/NEAR).

This is the single most material cross-target semantic divergence in the
platform: the same `a.add(b)` expression reverts on EVM but silently produces a
wrapped value on Solana/NEAR. The `arith.checked` capability makes this
divergence visible at the profile and artifact-metadata layer.

A contract author declares the checked-overflow intent by setting
`Module.overflowChecked := true`. This makes the module declare the
`arith.checked` capability, and the capability gate in `Target.defaultResolve`
**rejects** such a module on any target profile that does not declare
`arith.checked` (currently Solana and NEAR). The default is `false` (portable
wrapping arithmetic), which is the safe cross-target default and routes to all
targets. Per-target lowering follows the per-node `overflowChecked` flag on
EVM (checked-revert when `true`, wrapping when `false`, matching Solidity 0.8
for the default `true`), and always wraps on Solana/NEAR; the flag + gate make
the *intent-vs-target* mismatch a
rejected resolution rather than a silent behavioral difference. FV-5 tracks
deepening this to width-aware IR reference semantics (overflow as an
observable trace outcome inside `evalNumericBinary`); see
[formal-verification.md](formal-verification.md) FV-5.

## Candidate Capabilities Not Yet Registered

These candidates are documented for target research only. Do not add them to
`ProofForge.Target.Capability` until a target profile and lowering rules are
accepted.

### Kaspa Toccata

See [Kaspa Toccata target](targets/kaspa-toccata.md).

| Candidate id | Portable meaning | Why it is separate |
|---|---|---|
| `storage.utxo` | State lives in covenant-controlled UTXOs or state commitments | Not account/object storage and not EVM-style slots |
| `covenant.lineage` | Successor outputs remain in an authorized covenant family | Needed for transaction/output validation, not ordinary storage |
| `tx.v1` | Target uses Kaspa transaction v1 semantics | Transaction projection and payload rules affect correctness |
| `tx.compute_budget` | Per-input script compute budget is explicit | Budgeting is part of transaction design, not just gas metering |
| `lane.user` | App operations can use user lanes | Needed for based-app ordering and proof anchoring |
| `zk.verify` | Script verifies an L1-supported proof | Different from compiling the target itself into a circuit |

`zk.circuit` remains reserved for targets whose primary artifact is a circuit or
circuit-oriented source package. Toccata may use proofs, but its base target is
a Kaspa covenant package.

### Stellar Soroban

See [Stellar Soroban target](targets/stellar-soroban.md).

Most Soroban behavior can start from the existing Wasm-host capability set, but
several target semantics are not covered by the current registry.

| Candidate id | Portable meaning | Why it is separate |
|---|---|---|
| `auth.require` | A contract requires an address-level authorization payload | Stronger and more structured than reading a caller/sender |
| `auth.account_contract` | A contract account validates authorization through target-native account logic | Needed for Soroban account-contract flows |
| `storage.ttl` | State entries have TTL extension, archival, and restoration behavior | Not captured by scalar/map storage alone |
| `artifact.contract_spec` | Build output includes contract interface/spec metadata used by tooling and bindings | Artifact-level requirement, not runtime storage |
| `asset.stellar` | Contract uses Stellar Asset Contract or token-interface integration | Native asset surface differs from generic `value.native` |

### Internet Computer

See [Internet Computer target](targets/internet-computer.md).

ICP canisters overlap with the Wasm-host family, but several canister semantics
need explicit representation before a target profile is added.

| Candidate id | Portable meaning | Why it is separate |
|---|---|---|
| `abi.candid` | Build emits and validates a Candid service interface | Public ABI is not only exported Wasm symbols |
| `canister.method_mode` | Entry points distinguish update, query, and composite query methods | Call mode affects persistence, consensus, and call restrictions |
| `storage.stable_memory` | State uses stable memory or stable structures across upgrades | Not captured by scalar/map storage alone |
| `storage.orthogonal_persistence` | State follows Motoko-style orthogonal persistence semantics | Different from explicit key-value stores |
| `principal.id` | Caller/canister/user identity is a Principal | Not an EVM address or generic account id |
| `cycles.manage` | Target can inspect, accept, send, or account for cycles | Cycles are resource accounting, not ordinary `value.native` |
| `crosscall.async` | Cross-canister calls are asynchronous message flows | Different from synchronous contract calls |
| `canister.lifecycle` | Target supports install, upgrade, stop/start, and lifecycle hooks | Lifecycle is part of deployment and state safety |
| `certified.data` | Target exposes certified variables or certified data responses | Needed for IC certification patterns |
| `management.canister` | Target can call the virtual management canister | System lifecycle APIs are target-native |

### Algorand AVM

See [Algorand AVM target](targets/algorand-avm.md).

Algorand overlaps with generic contract capabilities, but AVM programs,
storage classes, transaction groups, and explicit resource references need
separate representation before a target profile is added.

| Candidate id | Portable meaning | Why it is separate |
|---|---|---|
| `avm.application` | Target emits stateful application approval and clear-state programs | Application artifacts have two AVM programs and app lifecycle semantics |
| `avm.logicsig` | Target emits a stateless LogicSig program | LogicSig is a separate stateless authorization artifact, not an app call |
| `abi.arc4` | Build emits or validates ARC-4 ABI/app-spec metadata | Public method shape is tooling-visible metadata, not only exported code |
| `storage.global` | Contract uses application global state | Different limits and access rules from local or box state |
| `storage.local` | Contract uses account-local application state | State is keyed by account and app, not by a global contract map |
| `storage.box` | Contract uses box storage with explicit box references | Box access requires resource references and budget planning |
| `tx.group` | Contract depends on atomic transaction group ordering or inspection | Group semantics are target-native transaction context |
| `tx.resource_refs` | App call requires explicit accounts, assets, apps, or boxes references | Resource availability affects whether AVM execution can access data |
| `itxn.submit` | Application submits inner transactions | Inner effects are transaction-level, not synchronous method calls |
| `asset.asa` | Contract handles Algorand Standard Assets | Native asset model differs from generic `value.native` |
| `gas.avm_budget` | Lowering tracks AVM opcode budget, costs, and program limits | AVM budget constraints are not EVM gas or Wasm host fuel |
| `artifact.algokit` | Build emits AlgoKit/Puya app artifacts and validation metadata | Target tooling requires app spec and bytecode package metadata |

### Cardano Plutus/Aiken

See [Cardano Plutus/Aiken target](targets/cardano-plutus-aiken.md).

Cardano overlaps with UTXO covenant targets, but eUTXO validator roles, datum,
redeemer, script context, execution units, and Plutus blueprint metadata need
separate representation before a target profile is added.

| Candidate id | Portable meaning | Why it is separate |
|---|---|---|
| `storage.eutxo` | State and value live in eUTXO outputs | Not account/object storage or global contract state |
| `validator.spend` | Target emits a spending validator | Spending validators have datum/redeemer/script-context semantics |
| `validator.mint` | Target emits a minting policy | Minting policy semantics differ from spending validation |
| `validator.withdraw` | Target emits a withdrawal validator | Withdrawal validation has a distinct Cardano role |
| `datum.inline` | Contract depends on inline datum encoding | Datum placement affects transaction construction and validation |
| `redeemer.input` | Entrypoint arguments are redeemers | Arguments arrive as transaction redeemers, not method calldata |
| `tx.script_context` | Validator reads Cardano script context | Context is central to validation correctness |
| `tx.validity_range` | Validator constrains slot/time validity | Validity ranges differ from generic block reads |
| `tx.balancing` | Validation includes transaction balancing and fee handling | Off-chain transaction construction is part of practical correctness |
| `asset.native_token` | Contract handles Cardano native multi-assets | Native asset model differs from generic `value.native` |
| `budget.exunits` | Artifact records Plutus execution units | Execution-unit budgeting is target-specific |
| `artifact.plutus_blueprint` | Build emits CIP-57 blueprint metadata | Blueprint metadata is part of the Cardano tooling surface |

### Tezos Michelson/LIGO

See [Tezos Michelson/LIGO target](targets/tezos-michelson-ligo.md).

Tezos overlaps with generic contract storage and entrypoints, but Michelson's
typed data, operation-list effects, views, events, tickets, and gas/storage-burn
semantics need explicit representation before a target profile is added.

| Candidate id | Portable meaning | Why it is separate |
|---|---|---|
| `vm.michelson` | Target emits or validates Michelson code | Michelson is a typed stack VM with target-specific constraints |
| `abi.entrypoint` | Build emits entrypoint/parameter schema metadata | Public entrypoint shape is target-visible metadata |
| `storage.micheline` | Storage is encoded as typed Micheline data | Not EVM slots or generic JSON |
| `storage.big_map` | Contract uses Tezos `big_map` storage | `big_map` persistence/indexing differs from ordinary maps |
| `operation.list` | Entrypoint returns a list of Tezos operations | Effects are returned data, not direct synchronous calls |
| `view.contract` | Contract exposes Tezos views | Views are a separate public read surface |
| `events.tezos` | Contract emits Tezos events | Event payload and indexing semantics are target-native |
| `ticket.handle` | Contract creates, transfers, or consumes tickets | Tickets are native linear assets, not generic tokens |
| `privacy.sapling` | Contract uses Sapling state or transactions | Privacy state is target-native and non-generic |
| `delegate.set` | Contract can change or clear delegation | Delegation is a Tezos-specific operation |
| `gas.tezos` | Artifact records Tezos gas/storage-burn constraints | Fee model differs from EVM gas and Wasm fuel |
| `artifact.ligo` | Build emits LIGO and compiled Michelson metadata | Target tooling requirement |

### Starknet Cairo

See [Starknet Cairo target](targets/starknet-cairo.md).

Starknet overlaps with contract storage, events, and calls, but Cairo/Sierra/CASM
artifacts, class hashes, account abstraction, syscalls, and L1/L2 messaging need
explicit representation before a target profile is added.

| Candidate id | Portable meaning | Why it is separate |
|---|---|---|
| `vm.cairo` | Target emits Cairo source for Starknet | Cairo is the source language and execution model boundary |
| `artifact.sierra` | Build emits Sierra contract class artifacts | Sierra is required intermediate contract class metadata |
| `artifact.casm` | Build emits CASM artifacts | CASM is a target artifact distinct from source and ABI |
| `class.declare` | Deployment flow includes class declaration | Starknet separates declaring a class from deploying an instance |
| `class.hash` | Artifact records class hash and class identity | Class hash is part of deployment and upgrade semantics |
| `abi.starknet` | Build emits Starknet ABI and selector metadata | ABI shape is not EVM ABI |
| `storage.starknet` | Contract uses Starknet storage paths/maps/components | Storage paths and components are target-native |
| `account.abstraction` | Target depends on Starknet account-contract semantics | Accounts are contract-level protocol participants |
| `syscall.starknet` | Contract uses Starknet syscalls | Calls, deploys, events, storage, and messaging use syscall surfaces |
| `message.l1_l2` | Contract sends or consumes L1/L2 messages | Messaging differs from ordinary contract calls |
| `fee.starknet` | Artifact records Starknet fee/resource constraints | Fee/resource model is target-specific |
| `test.snforge` | Validation uses Starknet Foundry or devnet | Local smoke tooling is part of target validation |

### Aleo Leo

See [Aleo Leo target](targets/aleo-leo.md) and
[docs/superpowers/specs/2026-07-01-aleo-leo-design.md](superpowers/specs/2026-07-01-aleo-leo-design.md).

Aleo overlaps with source-generation and ZK targets, but its contract model has
an explicit proof/finalization split. Private execution creates transitions and
proofs; public finalization updates mappings or storage on-chain. Records,
program ids, imports, Aleo Instructions, Aleo VM bytecode, ABI, prover/verifier
artifacts, fees, and devnet validation still need explicit representation
before those native surfaces can be claimed.

#### Current profile and Aleo-native research vocabulary

The registered `aleo-leo` profile currently uses shared portable capabilities,
including `data.linear_record` and `crosscall.named`; metadata is emitted only
after the same function plan as codegen validates. The Aleo-native ids below
remain design vocabulary, not entries in `ProofForge.Target.Capability` and not
claims made by the Counter fail-closed smoke.

| Design id | Portable meaning | Why it is separate |
|---|---|---|
| `lang.leo` | Target emits Leo source packages | Leo is the first stable sourcegen boundary |
| `vm.aleo_avm` | Target runs on the Aleo VM | Avoids ambiguity with Algorand AVM |
| `artifact.avm` | Build emits Aleo VM bytecode | Deployment artifact is target-native |
| `artifact.aleo_abi` | Build emits Aleo ABI metadata | ABI shape follows Aleo program interfaces |
| `execution.finalize` | Program has public on-chain finalization logic | Finalization is public and validator-executed |
| `state.mapping` | Public state is held in mappings | Mappings are on-chain public key-value state |
| `input.public` | Function input is public data | Public inputs are visible in transaction context |
| `output.public` | Function output is public | Public outputs need explicit metadata |
| `test.leo` | Validation uses Leo tests | Local validation is target tooling |

#### Research candidate capabilities (future spikes)

These remain candidates until private records, transitions, proofs, imports,
deployment, or devnet validation are scoped.

| Candidate id | Portable meaning | Why it is separate |
|---|---|---|
| `ir.aleo_instructions` | Build emits or consumes Aleo Instructions | Lower-level Aleo compiler target distinct from Leo |
| `proof.prover_key` | Build or execute flow produces prover artifacts | Proof generation has target-owned artifacts |
| `proof.verifier_key` | Build or deploy flow records verifier artifacts | Verification keys are part of deployment/execution metadata |
| `execution.transition` | Entry execution produces a transition and proof | Transition is the Aleo function-call unit |
| `state.record` | Private state is held in encrypted records | Records are UTXO-like and not EVM storage |
| `state.storage` | Public state may use storage variables or storage vectors | Aleo storage differs from mappings and private records |
| `input.private` | Function input is private proof-context data | Privacy is part of the function signature |
| `output.private` | Function output is private by default | Output visibility is target semantics |
| `program.import` | Program imports and calls another Aleo program | Cross-program calls produce composed transitions/finalization |
| `program.upgrade` | Deployment may support explicit program upgrades | Upgrade rules are program/deploy metadata |
| `transaction.execute` | Validation can produce an execute transaction | Execute transactions carry transitions and proofs |
| `transaction.deploy` | Validation can produce or inspect a deploy transaction | Deploy publishes program code and verification metadata |
| `fee.credits` | Fees are paid in Aleo Credits, publicly or privately | Fee visibility and source affect privacy and validation |
| `test.aleo_devnet` | Validation uses Leo devnet or devnode-backed flows | Network-backed smoke differs from local compile/test |

The existing `zk.circuit` capability is not enough for Aleo. It may describe
part of the proof surface, but Aleo also needs program, transaction,
state-record, finalization, and artifact capabilities.

### TON TVM

See [TON TVM target](targets/ton-tvm.md).

TON overlaps with generic contract capabilities, but TVM cells, messages, and
actions need explicit representation before a target profile is added.

| Candidate id | Portable meaning | Why it is separate |
|---|---|---|
| `storage.cell` | Contract state is encoded as TVM cells, slices, and builders | Not EVM slot storage or host KV |
| `abi.tlb` | Build emits or validates TL-B/cell layout metadata | Public data shape is cell-oriented |
| `message.recv` | Contract handles internal or external inbound messages | Entrypoint shape is message-driven |
| `message.send` | Contract emits outbound messages through action semantics | Not synchronous cross-contract calls |
| `method.get` | Contract exposes off-chain get methods | Different from state-changing message handlers |
| `action.list` | Target effects are accumulated in TVM action lists | Needed for send/deploy/reserve effects |
| `state.init` | Deployment requires code/data `StateInit` handling | Deployment artifact is target-native |
| `account.status` | Account lifecycle/status affects behavior | Needed for uninit/active/frozen/deleted handling |
| `gas.tvm` | TVM gas and fee model is explicit | Not generic EVM gas or host fee metering |
| `asset.jetton` | Contract integrates TON jetton/token standards | Native token standards differ from `value.native` |

### Bitcoin Script/Miniscript

See [Bitcoin Script/Miniscript target](targets/bitcoin-script-miniscript.md).

Bitcoin overlaps with UTXO script targets, but base-layer Script is best modeled
as spending policy rather than general contract execution. Miniscript,
descriptors, Taproot/Tapscript, PSBT flows, standardness, and weight/fee checks
need explicit representation before a target profile is added.

| Candidate id | Portable meaning | Why it is separate |
|---|---|---|
| `script.bitcoin` | Target emits Bitcoin Script or script fragments | Bitcoin Script has distinct consensus and standardness rules |
| `script.miniscript` | Target emits analyzable Miniscript policy | Safer first artifact than raw Script for spending policies |
| `descriptor.output` | Target emits Bitcoin Core output descriptors | Descriptors drive wallet/address/script workflows |
| `script.segwit` | Target emits SegWit v0 script paths such as P2WPKH/P2WSH | SegWit witness semantics differ from legacy script paths |
| `script.taproot` | Target emits Taproot key-path or script-path outputs | Taproot changes address, commitment, and spend semantics |
| `script.tapscript` | Target emits or validates Tapscript semantics | Tapscript changes opcode and signature behavior |
| `witness.stack` | Artifact declares required witness stack items | Unlocking data is part of spend validation |
| `sighash.mode` | Signature semantics depend on explicit sighash flags | Sighash choice affects what the signature commits to |
| `hashlock.preimage` | Spending policy depends on revealing hash preimages | Common Bitcoin contract primitive |
| `multisig.threshold` | Spending policy uses threshold signatures or multisig structure | Not equivalent to account-level authorization |
| `psbt.flow` | Validation uses PSBT creation, signing, and finalization | Practical Bitcoin workflows are transaction-construction heavy |
| `policy.standardness` | Artifact checks relay/mining standardness policy | Consensus-valid scripts may still be non-standard |
| `fee.weight` | Artifact records transaction weight, vbytes, fee, and dust constraints | Fee and relay viability are part of practical correctness |
| `test.bitcoin_core` | Validation uses Bitcoin Core regtest or RPC checks | Target validation depends on Bitcoin Core behavior |

Bitcoin should reuse existing UTXO candidate ids where the semantics match,
including `storage.utxo`, `script.p2sh`, `script.unlocker`,
`timelock.locktime`, `signature.checksig`, and `tx.builder`.

### Zcash Shielded

See [Zcash Shielded target](targets/zcash-shielded.md).

Zcash overlaps with Bitcoin-derived UTXO flows, but its shielded pools are not
ordinary Bitcoin Script or a generic ZK circuit target. Sapling/Orchard notes,
nullifiers, commitment tree anchors, value-balance constraints, viewing-key
disclosure, and protocol-defined proofs need explicit representation before a
target profile is added.

| Candidate id | Portable meaning | Why it is separate |
|---|---|---|
| `privacy.shielded` | Target uses a shielded value pool | Privacy is a transaction construction property, not only a proof flag |
| `privacy.transparent` | Target also handles transparent Zcash inputs or outputs | Transparent and shielded pools leak different information |
| `pool.sapling` | Target uses Sapling shielded semantics | Sapling has distinct notes, keys, and proof semantics |
| `pool.orchard` | Target uses Orchard shielded semantics | Orchard has action bundles and Halo 2 proof semantics |
| `note.shielded` | State/value unit is a shielded note | Not EVM storage, account state, or plain UTXO script data |
| `note.commitment` | Artifact records note commitment semantics | Needed for tree membership and output construction |
| `nullifier.reveal` | Spend reveals a nullifier as the double-spend guard | Public nullifiers are core to shielded spend validity |
| `anchor.commitment_tree` | Spend proves membership against a commitment tree anchor | Membership anchor is part of the public proof statement |
| `zk.zcash_proof` | Transaction carries a Zcash protocol proof | The circuit is protocol-defined, not arbitrary application code |
| `zk.witness` | Build requires private witness data for proving | Witness data must stay off-chain and auditable as a boundary |
| `value.balance` | Artifact records shielded value-balance constraints | Conservation across shielded pools and transparent turnstiles is target-specific |
| `key.viewing` | Validation/disclosure can use viewing keys | Off-chain observability is not contract state |
| `address.unified` | Target handles unified addresses and receiver selection | Address semantics affect pool choice and recipient leakage |
| `privacy.policy` | Artifact records allowed information leakage | zcashd exposes privacy-policy choices during transaction construction |
| `test.zcashd` | Validation uses zcashd RPC or a compatible local library | Target validation depends on Zcash tooling, not Bitcoin Core alone |

Zcash should reuse existing UTXO candidate ids for transparent flows where the
semantics match, including `storage.utxo`, `tx.builder`,
`signature.checksig`, and `fee.weight`. The existing `zk.circuit` capability is
not the right first abstraction for ordinary Zcash shielded transfers; it only
fits future auxiliary proof-program work outside the Zcash consensus proof
system.

### Bitcoin Cash CashScript

See [Bitcoin Cash CashScript target](targets/bitcoin-cash-cashscript.md).

BCH/CashScript overlaps with UTXO covenant targets, but its CashVM,
transaction-introspection, CashTokens, and transaction-builder semantics need
explicit representation before a target profile is added.

| Candidate id | Portable meaning | Why it is separate |
|---|---|---|
| `storage.utxo` | State and value live in spendable UTXOs | Not account/object storage or global contract state |
| `script.p2sh` | Contract deployment/addressing uses P2SH locking scripts | Deployment/address surface is target-native |
| `script.unlocker` | Contract calls are unlocking scripts for selected UTXOs | Not ordinary method dispatch |
| `tx.introspection` | Contract reads current transaction inputs/outputs and active input data | Core covenant mechanism in BCH CashVM |
| `covenant.introspection` | Contract constrains successor outputs through introspection | Needed for covenant-style state transitions |
| `storage.local_state` | Local state is simulated through script data or CashTokens commitments | Not persistent global storage |
| `asset.cashtoken` | Contract handles CashTokens category, capability, NFT commitment, and token amount | Native asset model differs from generic `value.native` |
| `timelock.locktime` | Contract depends on locktime, sequence, or age checks | Separate from ordinary block reads |
| `signature.checksig` | Contract verifies signatures as spend conditions | UTXO spend authorization is script-level |
| `artifact.cashscript` | Build emits a CashScript artifact JSON and bytecode metadata | Target tooling requirement |
| `tx.builder` | Validation includes building and evaluating a spend transaction | Practical target semantics require transaction construction |

## EVM Mapping (baseline)

| Capability id | EVM lowering |
|---|---|
| `storage.scalar` | `Storage.load` / `Storage.store` (sload/sstore) |
| `storage.map` | `Storage.mapLoad` / `Storage.mapStore` |
| `caller.sender` | `Env.sender` |
| `value.native` | `Env.value` |
| `events.emit` | `log0`–`log4` |
| `crosscall.invoke` | `call`, `staticcall`, `delegatecall`, `create`, `create2` |
| `env.block` | `Env.blockNumber`, `timestamp()`, `chainid()`, `gasprice()`, `gas()`, `basefee()`, `prevrandao()`, `coinbase()`, `blockhash(n)` |
| `account.explicit` | `address()` |

Implemented today via `ProofForge.Evm` / `Lean.Evm` — see
[targets/evm.md](targets/evm.md).

## Toolchain Capabilities

These capabilities describe verification and modeling artifacts produced by the
ProofForge toolchain, not runtime behavior of a deployed target. They are
attached to the `quint` pseudo-target or to the verification stage of any real
target.

| Capability id | Portable meaning | Status |
|---|---|:---:|
| `model.quint` | Target emits a Quint state-machine model from portable IR. | Implemented |
| `verify.model_check` | Generated model can be checked with Apalache/TLC via `quint verify`. | Implemented (Java 17+ required) |
| `verify.simulation` | Generated model can be simulated with `quint run`. | Implemented |
| `test.mbt_trace` | Generated model can produce ITF traces for replay against IR semantics. | Implemented |

## Phase 1 Acceptance Criteria

- [ ] Every id in this table appears in `TargetProfile.capabilities` for at least
      one target.
- [ ] EVM Counter build lists `storage.scalar` (and others used) in artifact
      metadata.
- [ ] Attempting `storage.pda` on EVM fails with `capability unsupported` diagnostic.
- [ ] Registry stays in sync when RFC 0002 semantic matrix changes.

## Changelog

| Date | Change |
|---|---|
| 2026-06-30 | Initial registry; supersedes ad hoc ids in Chinese technical plan |
| 2026-06-30 | Added Psy DPN research column and ZK capability ids |
