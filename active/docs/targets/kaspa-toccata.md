# Kaspa Toccata Target

Status: **Research (docs-first candidate)**

> **Status update 2026-07-02:** the Toccata hardfork activated on Kaspa
> mainnet on ~2026-06-30 (rusty-kaspa v2.0.0), shipping KIP-16 (ZK verifier
> opcodes), KIP-17, KIP-20, and KIP-21 (partitioned sequencing commitments),
> native L1 covenants, and transaction v1 fields
> (`TransactionOutput.covenant`, `TransactionInput.compute_commit`). The
> upstream ZK stack is tiered: inline ZK covenants (Noir/Groth16, ~1s local
> proving), based ZK apps (RISC Zero / SP1), based ZK rollups (Cairo). A
> second-phase upstream release (SMT RPC API, ZK SDK, first Silverscript
> version) is announced but not yet shipped — that release is this target's
> spike trigger. See the [target roadmap](../target-roadmap.md).

Candidate target id: **`kaspa-toccata`**

This note records the first ProofForge classification for Kaspa's Toccata
programmability stack. It does not add a Lean target profile yet. The purpose is
to decide what the target is before changing the registry or compiler.

Primary sources:

- [Toccata Dev Guide](https://docs.kaspa.org/toccata)
- [Transaction V1](https://docs.kaspa.org/toccata/transaction-v1)
- [Inline ZK](https://docs.kaspa.org/toccata/inline-zk)
- [Based Apps](https://docs.kaspa.org/toccata/based-apps)

## Classification

Toccata should not be treated as "a ZK chain" in the same sense as
`psy-dpn`.

The better first classification is:

```text
Kaspa L1 UTXO covenant target
  with transaction v1 support
  with optional inline proof verification
  with a separate based-app settlement architecture
```

ZK appears in Toccata as an L1 script capability and a settlement pattern:

- Inline ZK: a covenant spend verifies a proof directly and binds the proof
  output to the successor covenant state.
- Based apps: users submit ordinary L1 lane transactions; an off-chain state
  machine executes app logic; a settlement covenant verifies a proof over lane
  activity and the next state commitment.

That is different from a ZK circuit source-generation target like `psy-dpn`,
where the main target artifact is a circuit/proof-oriented program artifact.
For Toccata, the on-chain artifact is still a Kaspa covenant/transaction
package, optionally carrying proof verification.

## Why This Matters For ProofForge

ProofForge should not force Toccata into the existing `zk-circuit-sourcegen`
family. Doing so would hide the main target constraints:

- state is UTXO/covenant lineage, not account/object storage;
- transitions validate successor outputs, not only method return values;
- transaction v1 fields matter for app design: `compute_budget`, covenant
  output bindings, user lanes, `gas`, and payload commitments;
- proof verification is useful only when bound to the exact program, public
  inputs, old state commitment, new state commitment, and successor output;
- based apps require an off-chain executor/prover and L1 lane anchoring, not
  only a contract compiler.

## Candidate Target Family

Do not add this to `ProofForge.Target.Registry` until the target model can
express UTXO/covenant capabilities.

Candidate family:

```text
utxo-covenant
```

Candidate artifact shape:

```text
kaspa-covenant-package
  - covenant source or generated Silverscript
  - transaction v1 manifest
  - covenant lineage/state manifest
  - optional inline ZK verifier manifest
  - optional based-app lane/proof settlement manifest
```

The first artifact does not need to produce a deployable mainnet transaction.
The first useful artifact is a reviewable package that makes successor-output
validation explicit.

## Candidate Capabilities

These are research candidates, not canonical capability ids yet:

| Candidate capability | Meaning |
|---|---|
| `storage.utxo` | State is held by covenant-controlled UTXOs or P2SH state commitments. |
| `covenant.lineage` | A successor output remains in the authorized covenant family. |
| `tx.v1` | Target uses transaction v1 semantics. |
| `tx.compute_budget` | Script execution budget is explicit per v1 input. |
| `lane.user` | App operations can be submitted through user lanes. |
| `zk.verify` | Script verifies an L1-supported proof. |
| `zk.proof` | Target flow may include proof generation or settlement proof handling. |

The existing `zk.circuit` capability is not the right fit for the base
Toccata covenant path. It may apply only to an auxiliary proof-program target,
not to the Kaspa covenant package itself.

## Implementation Roads

### Road 1: L1 Covenant App

Use this road when app state can be split into small, public, local UTXO lanes.

First spike:

- choose a tiny Counter-like covenant state;
- generate or hand-author reviewable covenant source;
- model current state commitment and successor state commitment;
- validate that the successor output has the correct covenant lineage and
  state commitment;
- produce an artifact manifest describing transaction v1 fields and covenant
  bindings.

This road should start with Silverscript research rather than a custom Kaspa
script generator.

### Road 2: Inline ZK Covenant

Use this road when one covenant transition is private, expensive, or both.

First spike:

- define a proof-verifier manifest with proof system tag, verification key or
  image id, public inputs, and expected state commitments;
- require the covenant script to bind the proof result to the successor output;
- keep proof generation outside ProofForge until the verifier contract shape is
  understood.

The key rule: a valid proof for the wrong program or wrong public inputs is not
useful to the covenant.

### Road 3: Based App Settlement

Use this road when many users mutate shared off-chain state.

First spike:

- define an app-specific user lane and payload format;
- model app operations as transaction v1 payloads;
- define a settlement covenant manifest that commits to previous state root,
  next state root, lane witness, exits, and permissions;
- treat vprogs/RISC Zero as an evolving reference stack, not yet a stable
  external API.

This is an execution architecture, not a simple smart-contract backend.

## Non-Goals For The First Pass

- Do not add `kaspa-toccata` to the code registry before candidate
  capabilities are reviewed.
- Do not classify Toccata as a generic ZK circuit target.
- Do not model Kaspa covenant state as EVM-style contract storage.
- Do not model user lanes as account-chain shards.
- Do not make ProofForge responsible for proving-system internals in the first
  covenant spike.
- Do not claim full Kaspa support until there is a local reproducible build or
  validation script.

## Research Exit Criteria

Toccata can leave Research only when we have:

- a reviewed target profile proposal;
- a committed capability proposal for UTXO/covenant semantics;
- a minimal artifact manifest schema;
- a toolchain decision for covenant authoring, likely starting with
  Silverscript;
- one reproducible local command or script that validates a tiny covenant
  package, even if it is not yet a mainnet transaction flow.
