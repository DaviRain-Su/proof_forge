# Cardano Plutus/Aiken Target

Status: **Research (docs-first candidate)**

Candidate target id: **`cardano-plutus-aiken`**

This note records the first ProofForge classification for Cardano smart
contracts through the Plutus/eUTXO model, with Aiken as the preferred first
source-generation path. It does not add a Lean target profile yet.

Primary sources:

- [Cardano smart contracts overview](https://developers.cardano.org/docs/developers/curriculum/smart-contracts/overview/)
- [Extended UTXO model](https://developers.cardano.org/docs/developers/curriculum/fundamentals/core-concepts/eutxo/)
- [Datum, redeemer, and context](https://developers.cardano.org/docs/developers/curriculum/smart-contracts/datum-redeemer-context/)
- [Choose a smart contract language](https://developers.cardano.org/docs/developers/curriculum/smart-contracts/choose-a-language/)
- [Untyped Plutus Core](https://developers.cardano.org/docs/build/smart-contracts/advanced/uplc/)
- [Lock and spend](https://developers.cardano.org/docs/developers/curriculum/smart-contracts/lock-and-spend/)
- [Smart contract design patterns](https://developers.cardano.org/docs/build/smart-contracts/advanced/design-patterns/overview/)
- [CIP-57: Plutus contract blueprints](https://cips.cardano.org/cip/CIP-0057)
- [Aiken validators](https://aiken-lang.org/language-tour/validators)
- [Aiken common design patterns](https://aiken-lang.org/fundamentals/common-design-patterns)

## Classification

Cardano should be treated as an eUTXO validator source-generation target. It is
not EVM, Wasm-host, Move, Solana sBPF, TVM, Algorand AVM, or a generic UTXO
script target.

```text
Cardano Plutus/Aiken target
  -> generated or wrapped Aiken source
  -> compiled validators / UPLC artifacts
  -> Plutus blueprint metadata
  -> transaction-building scenario with datum, redeemer, and script context
  -> local emulator, cardano-node, or SDK-backed validation
```

The first spike should use Aiken because it gives ProofForge a reviewable source
package and blueprint output before any lower-level UPLC emitter is attempted.

## Why This Matters For ProofForge

ProofForge should model Cardano contracts around validation of UTXO spends and
policy scripts, not around mutable contract objects or method calls.

Target-specific concerns:

- contract logic validates transactions against datum, redeemer, and script
  context;
- persistent state is represented by UTXOs and successor outputs;
- spending, minting, withdrawal, and publishing validators have different
  purposes;
- value can contain ADA and multi-asset native tokens;
- transaction validity ranges and signatories are part of correctness;
- execution units and transaction balancing are practical validation concerns;
- Plutus blueprints describe validator interfaces and should be captured in
  artifact metadata;
- off-chain transaction construction is part of the target surface.

## Candidate Target Family

Candidate family:

```text
eutxo-validator-sourcegen
```

Candidate artifact shape:

```text
cardano-plutus-aiken-package
  - generated Aiken source or wrapped source package
  - compiled UPLC / Plutus validator artifacts
  - CIP-57 Plutus blueprint
  - validator role manifest
  - datum / redeemer / script-context schema
  - transaction-building scenario manifest
  - execution-units and toolchain validation report
```

## Candidate Capabilities

Some existing capabilities have rough Cardano interpretations, but they need
review:

| Existing capability | Cardano interpretation |
|---|---|
| `storage.scalar` | UTXO datum field or script parameter, not global storage. |
| `storage.map` | Encoded datum or off-chain indexed UTXO set, not native map storage. |
| `caller.sender` | Signatories or required witnesses in transaction context. |
| `value.native` | ADA and native assets carried by inputs and outputs. |
| `events.emit` | No EVM-style logs; rely on transactions, metadata, and indexing. |
| `crosscall.invoke` | No synchronous calls; compose validators and scripts in one transaction. |
| `env.block` | Validity range, slot, and transaction context. |
| `crypto.hash` | Plutus/Aiken hash and signature primitives. |

Candidate capabilities that may need explicit ids later:

| Candidate capability | Meaning |
|---|---|
| `storage.eutxo` | State and value live in eUTXO outputs. |
| `validator.spend` | Target emits a spending validator. |
| `validator.mint` | Target emits a minting policy. |
| `validator.withdraw` | Target emits a withdrawal validator. |
| `datum.inline` | Contract depends on inline datum encoding. |
| `redeemer.input` | Entrypoint arguments are redeemers. |
| `tx.script_context` | Validator reads Cardano script context. |
| `tx.validity_range` | Validator constrains slot/time validity. |
| `tx.balancing` | Validation includes transaction balancing and fee handling. |
| `asset.native_token` | Contract handles Cardano native multi-assets. |
| `budget.exunits` | Artifact records Plutus execution units. |
| `artifact.plutus_blueprint` | Build emits CIP-57 blueprint metadata. |

Do not add these ids to `ProofForge.Target.Capability` until a target profile
and lowering rules are reviewed.

## Implementation Road

### Road 1: Aiken Sourcegen

This is the most conservative first spike.

First spike:

- choose a Counter-like state machine encoded as a UTXO datum;
- generate or wrap one Aiken spending validator;
- compile the package and capture UPLC plus blueprint output;
- build a two-step transaction scenario: lock initial state, then spend to a
  successor output with incremented datum;
- record datum/redeemer schema, validator role, execution units, tool versions,
  and validation result in artifact metadata.

### Road 2: Restricted Plutus/UPLC IR

This road should wait until the source package route clarifies artifact and
transaction semantics.

First spike:

- define a restricted eUTXO validator IR;
- model datum, redeemer, script context, values, and successor-output checks;
- keep minting policies, staking scripts, reference scripts, and complex
  multi-validator protocols out of the first direct path.

## Non-Goals For The First Pass

- Do not add `cardano-plutus-aiken` to the code registry yet.
- Do not classify Cardano as EVM, Wasm-host, Move, Solana, TVM, AVM, or generic
  Bitcoin-like UTXO.
- Do not model UTXO datum as global mutable storage.
- Do not hide off-chain transaction-building requirements from metadata.
- Do not claim direct UPLC support before the Aiken sourcegen route is validated.

## Research Exit Criteria

Cardano can leave Research only when we have:

- a reviewed target profile proposal;
- a decided first spike path, likely Aiken sourcegen;
- a minimal eUTXO state-machine scenario;
- a datum/redeemer/script-context schema policy;
- an execution-unit and transaction-balancing policy;
- a documented toolchain requirement set;
- at least one reproducible local validation command;
- artifact metadata for source, validators, blueprint, transaction scenario,
  execution units, toolchain versions, and validation result.
