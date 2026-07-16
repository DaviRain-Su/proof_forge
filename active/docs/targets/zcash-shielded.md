# Zcash Shielded Target

Status: **Research (docs-first candidate)**

Candidate target id: **`zcash-shielded`**

This note records the first ProofForge classification for Zcash. It does not
add a Lean target profile yet. The purpose is to decide how Zcash's ZK privacy
model fits the target system before changing the registry or compiler.

Primary sources:

- [How is Zcash different than Bitcoin?](https://z.cash/learn/how-is-zcash-different-than-bitcoin/)
- [Zcash protocol specification](https://zips.z.cash/protocol/protocol.pdf)
- [ZIP 224: Orchard Shielded Protocol](https://zips.z.cash/zip-0224)
- [Zcash RPC documentation](https://zcash.github.io/rpc/)
- [z_sendmany RPC](https://zcash.github.io/rpc/z_sendmany.html)

## Classification

Zcash is closer to Bitcoin than to account-based smart-contract chains, but it
should not be folded into the Bitcoin Script/Miniscript target.

The better first classification is:

```text
Zcash privacy UTXO payment target
  with Bitcoin-derived transparent transaction support
  with Sapling/Orchard shielded pools
  with consensus-verified ZK proofs for shielded spends and outputs
```

The ZK part is not a generic "verify arbitrary proof in script" capability.
Zcash consensus verifies proofs that are part of the Zcash transaction format.
Those proofs prove protocol-specific statements about shielded notes, nullifiers,
commitment trees, value balance, and authorization.

That makes Zcash different from these existing ProofForge target families:

- Bitcoin Script/Miniscript: spending policy only, no shielded note system.
- BCH/CashScript: UTXO script/covenant sourcegen, no native shielded pools.
- Kaspa Toccata: optional inline proof verification inside covenant execution.
- Psy/DPN: target program compiles into ZK circuit artifacts.

## How ZK Fits A JDL-Z11-Like Script

The user-facing script must not pretend that Zcash exposes a general on-chain
contract method with private storage. A JDL-Z11-like script should use Zcash ZK
through a constrained privacy transaction DSL:

```text
shielded zcash OrchardPayment {
  spend note input0 proving:
    owner_authorized(input0)
    note_in_commitment_tree(input0, anchor)
    nullifier_is_fresh(input0)

  create note output0:
    recipient = bob_unified_address
    value = private amount
    memo = private memo

  public:
    pool = orchard
    anchor = current_orchard_anchor
    nullifiers = [nf(input0)]
    value_balance = 0
    fee = transparent fee
}
```

The script describes proof obligations and transaction shape. The backend does
not lower this to Bitcoin Script or a Zcash "contract function." It lowers it
to a shielded transaction manifest:

```text
ProofForge script
  -> privacy-aware portable IR subset
  -> Zcash Orchard/Sapling transaction builder inputs
  -> proving manifest and witness requirements
  -> Zcash transaction with shielded proof bundle
  -> zcashd / lightwallet / library-backed validation
```

The important boundary:

- private note value, recipient data, memo, and witness path remain off-chain
  witness data;
- public transaction data includes anchors, nullifiers, value balance, fees,
  and pool/action metadata exposed by the protocol;
- ProofForge can prove its own source-level invariants about which payment
  policy is intended;
- Zcash consensus verifies the protocol ZK proof, not arbitrary ProofForge
  business logic.

In other words, Zcash ZK is usable from a script as **a built-in confidential
payment primitive**, not as an arbitrary programmable verifier.

## Why This Matters For ProofForge

Treating Zcash as "Bitcoin plus ZK" is too coarse. The transparent side can
reuse Bitcoin-like UTXO concepts, but the shielded side needs target-specific
modeling:

- shielded state is a note set plus commitment trees, not global contract
  storage;
- note spends reveal nullifiers to prevent double spends without revealing the
  spent note;
- proof statements are fixed by Sapling/Orchard protocol rules;
- value conservation is enforced through shielded value balances and
  transparent turnstiles;
- viewing keys and wallet scanning are off-chain observability tools, not
  contract state;
- privacy depends on transaction construction policy, not only on whether a
  proof verifies.

## Candidate Target Family

Do not add this to `ProofForge.Target.Registry` until the target model can
express shielded note and privacy capabilities.

Candidate family:

```text
privacy-utxo-zk-payment
```

Candidate artifact shape:

```text
zcash-shielded-package
  - transparent input/output manifest
  - shielded pool selection: Sapling or Orchard
  - shielded note input/output schema
  - nullifier and anchor manifest
  - value-balance and fee manifest
  - proving/witness manifest
  - viewing-key and disclosure policy metadata
  - zcashd or library validation result
```

The first artifact should not attempt to be a deployable smart contract. The
first useful artifact is a reviewable transaction/proof package for a tiny
shielded payment policy.

## Candidate Capabilities

These are research candidates, not canonical capability ids yet.

Existing UTXO and Bitcoin candidate capabilities can apply to transparent Zcash
flows where the semantics match, including `storage.utxo`, `tx.builder`,
`signature.checksig`, `fee.weight`, and `test.bitcoin_core`-style local node
validation. The shielded path needs additional capabilities:

| Candidate capability | Meaning |
|---|---|
| `privacy.shielded` | Target uses a shielded value pool. |
| `privacy.transparent` | Target also handles transparent Zcash inputs or outputs. |
| `pool.sapling` | Target uses Sapling shielded semantics. |
| `pool.orchard` | Target uses Orchard shielded semantics. |
| `note.shielded` | State/value unit is a shielded note. |
| `note.commitment` | Artifact records note commitment semantics. |
| `nullifier.reveal` | Spend reveals a nullifier as the double-spend guard. |
| `anchor.commitment_tree` | Spend proves membership against a commitment tree anchor. |
| `zk.zcash_proof` | Transaction carries a Zcash protocol proof. |
| `zk.witness` | Build requires private witness data for proving. |
| `value.balance` | Artifact records shielded value-balance constraints. |
| `key.viewing` | Validation/disclosure can use viewing keys. |
| `address.unified` | Target handles unified addresses and receiver selection. |
| `privacy.policy` | Artifact records allowed information leakage. |
| `test.zcashd` | Validation uses zcashd RPC or a compatible local library. |

`zk.circuit` is not the first capability for Zcash. It may apply only if a
future auxiliary target generates or verifies a custom circuit outside the
Zcash consensus proof system. For normal Zcash transfers, the proof circuit is
protocol-defined.

## Implementation Roads

### Road 1: Transparent Zcash UTXO

Use this road to validate Bitcoin-derived transaction handling without touching
shielded proofs.

First spike:

- construct one transparent Zcash transaction scenario;
- reuse Bitcoin-like UTXO and fee metadata where safe;
- record Zcash network, address, fee, and transaction-version differences;
- validate with zcashd RPC or a compatible local library.

This is a stepping stone only. It does not prove ProofForge can use Zcash's ZK
capabilities.

### Road 2: Orchard Shielded Payment Manifest

Use this road for the first real Zcash ZK integration.

First spike:

- define a one-input, one-output shielded payment policy;
- model a shielded note, commitment anchor, nullifier, value balance, fee, and
  recipient;
- generate a transaction/proving manifest rather than raw proving internals;
- call zcashd RPC, a lightwallet flow, or a Rust library boundary to produce or
  validate the transaction;
- record what is public, what remains private witness data, and what viewing-key
  disclosure can reveal.

This road should start with Orchard unless a toolchain blocker makes Sapling
much easier locally.

### Road 3: JDL-Z11-Like Privacy DSL Frontend

Use this road once the transaction manifest shape is understood.

First spike:

- define script-level primitives such as `shield`, `spendNote`, `createNote`,
  `revealNullifier`, `selectAnchor`, and `privacyPolicy`;
- statically reject unsupported patterns such as global mutable shielded storage,
  contract method dispatch, arbitrary proof verification, and reading private
  note data from public code;
- lower the script to the Road 2 manifest;
- keep the proof generation boundary explicit so users can audit which witness
  fields are required.

The script is a policy and transaction-construction DSL, not an on-chain
contract language.

## Non-Goals For The First Pass

- Do not add `zcash-shielded` to the code registry before candidate
  capabilities are reviewed.
- Do not classify Zcash as a generic smart-contract chain.
- Do not lower Zcash shielded logic to Bitcoin Script or Miniscript.
- Do not make ProofForge responsible for implementing Orchard/Sapling proving
  internals in the first spike.
- Do not claim arbitrary ZK verification on Zcash.
- Do not model shielded notes as EVM-style global storage.
- Do not claim privacy if a transaction crosses transparent and shielded pools
  in a way that reveals sender, recipient, or amount information.

## Research Exit Criteria

Zcash can leave Research only when we have:

- a reviewed target profile proposal;
- a committed capability proposal for shielded notes, nullifiers, anchors,
  value balance, and privacy policy;
- a minimal artifact manifest schema for transparent and shielded transaction
  paths;
- a toolchain decision for local validation, likely zcashd RPC or a Rust
  wallet/protocol library boundary;
- one reproducible local command or script that validates a tiny shielded
  payment manifest or records an external-tool blocker.
