# Bitcoin Script/Miniscript Target

Status: **Research (docs-first candidate)**

Candidate target id: **`bitcoin-script-miniscript`**

This note records the first ProofForge classification for Bitcoin base-layer
contracts. It does not add a Lean target profile yet.

Primary sources:

- [Bitcoin contracts guide](https://developer.bitcoin.org/devguide/contracts.html)
- [Bitcoin transaction reference](https://developer.bitcoin.org/reference/transactions.html)
- [Bitcoin Core output descriptors](https://github.com/bitcoin/bitcoin/blob/master/doc/descriptors.md)
- [BIP 379: Miniscript](https://bips.dev/379/)
- [BIP 342: Tapscript](https://bips.dev/342/)
- [Bitcoin Core RPC reference](https://developer.bitcoin.org/reference/rpc/index.html)

## Classification

Bitcoin should be treated as a limited UTXO spending-policy target, not as a
general smart-contract chain.

```text
Bitcoin Script/Miniscript target
  -> generated or wrapped policy / Miniscript / descriptor
  -> Script, witness script, or Tapscript output
  -> PSBT or raw transaction scenario
  -> Bitcoin Core regtest / testmempoolaccept / script verification validation
```

The useful ProofForge boundary is spending-condition generation and validation:
multisig, hash locks, time locks, Taproot script paths, descriptors, and PSBT
flows. Bitcoin Script intentionally lacks general mutable state, rich method
dispatch, unbounded computation, and synchronous cross-contract calls.

## Why This Matters For ProofForge

ProofForge can support Bitcoin, but the support should be honest about the
expressive ceiling.

Target-specific concerns:

- state and value live in UTXOs, not accounts or contract storage;
- scripts lock outputs and witnesses unlock them;
- policy is usually about who can spend, when they can spend, and which preimage
  or signature data must be revealed;
- standardness, relay policy, transaction weight, fee rate, dust, and script
  limits affect whether an artifact is practical even when consensus-valid;
- Taproot and Tapscript have different signature and script semantics from
  legacy P2SH/P2WSH;
- output descriptors and Miniscript are safer first artifacts than raw hand-made
  Script for many spending policies;
- PSBT or raw transaction construction is part of validation.

## Candidate Target Family

Candidate family:

```text
bitcoin-script-policy-sourcegen
```

Candidate artifact shape:

```text
bitcoin-script-miniscript-package
  - generated policy, Miniscript, descriptor, or raw script
  - address/output script metadata
  - witness or redeem-script manifest
  - PSBT/raw transaction validation scenario
  - timelock, hashlock, and sighash policy metadata
  - weight/fee/standardness report
  - Bitcoin Core regtest validation report
```

## Candidate Capabilities

Some existing UTXO candidate capabilities also apply to Bitcoin, but need
Bitcoin-specific lowering rules:

| Existing candidate capability | Bitcoin interpretation |
|---|---|
| `storage.utxo` | State and value live in spendable UTXOs. |
| `script.p2sh` | Legacy script-hash locking path. |
| `script.unlocker` | Spending data is `scriptSig` or witness stack data. |
| `timelock.locktime` | Absolute or relative locktime through CLTV/CSV and transaction fields. |
| `signature.checksig` | ECDSA or Schnorr signature checks depending on script version. |
| `tx.builder` | Practical validation includes constructing and testing spends. |

Candidate capabilities that may need explicit ids later:

| Candidate capability | Meaning |
|---|---|
| `script.bitcoin` | Target emits Bitcoin Script or script fragments. |
| `script.miniscript` | Target emits analyzable Miniscript policy. |
| `descriptor.output` | Target emits Bitcoin Core output descriptors. |
| `script.segwit` | Target emits SegWit v0 script paths such as P2WPKH/P2WSH. |
| `script.taproot` | Target emits Taproot key-path or script-path outputs. |
| `script.tapscript` | Target emits or validates Tapscript semantics. |
| `witness.stack` | Artifact declares required witness stack items. |
| `sighash.mode` | Signature semantics depend on explicit sighash flags. |
| `hashlock.preimage` | Spending policy depends on revealing hash preimages. |
| `multisig.threshold` | Spending policy uses threshold signatures or multisig structure. |
| `psbt.flow` | Validation uses PSBT creation, signing, and finalization. |
| `policy.standardness` | Artifact checks relay/mining standardness policy. |
| `fee.weight` | Artifact records transaction weight, vbytes, fee, and dust constraints. |
| `test.bitcoin_core` | Validation uses Bitcoin Core regtest or RPC checks. |

Do not add these ids to `ProofForge.Target.Capability` until a target profile
and lowering rules are reviewed.

## Implementation Road

### Road 1: Miniscript/Descriptor Sourcegen

This is the most conservative first spike.

First spike:

- choose a small policy such as "A can spend immediately, or B can spend after a
  relative timelock";
- generate Miniscript and a descriptor, not raw Script;
- derive the output script/address;
- build and sign a regtest PSBT or raw transaction spend;
- validate with Bitcoin Core RPC such as `testmempoolaccept` or a regtest spend;
- record descriptor, script, witness requirements, transaction scenario,
  weight/fee, tool versions, and validation result in artifact metadata.

### Road 2: Restricted Script/Tapscript Emitter

This road should follow only after the policy route proves the artifact shape.

First spike:

- define a restricted policy IR for signatures, thresholds, hash locks, and
  time locks;
- emit Script or Tapscript only for policies that can be statically analyzed;
- keep covenants, vault protocols, DLCs, CoinJoin coordination, Lightning
  channel protocols, and future soft-fork opcodes out of the first direct path.

## Non-Goals For The First Pass

- Do not add `bitcoin-script-miniscript` to the code registry yet.
- Do not classify Bitcoin as EVM, Wasm-host, Move, Solana, TVM, AVM, or a
  general smart-contract platform.
- Do not model UTXO data as global mutable storage.
- Do not claim covenant/state-machine support from basic Script support.
- Do not treat BCH/CashScript semantics as Bitcoin semantics.
- Do not hide PSBT/transaction-building requirements from artifact metadata.
- Do not claim support until a regtest or equivalent Bitcoin Core validation
  flow exists.

## Research Exit Criteria

Bitcoin can leave Research only when we have:

- a reviewed target profile proposal;
- a decided first spike path, likely Miniscript/descriptor sourcegen;
- a minimal spending-policy scenario;
- a script version policy covering P2SH, P2WSH, and Taproot/Tapscript scope;
- a PSBT/raw-transaction validation policy;
- a standardness, weight, fee, and dust policy;
- a documented toolchain requirement set, including Bitcoin Core regtest;
- at least one reproducible local validation command;
- artifact metadata for policy, descriptor, script, witness/PSBT scenario,
  weight/fee, toolchain versions, and validation result.
