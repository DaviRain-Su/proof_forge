# Bitcoin Cash CashScript Target

Status: **Research (docs-first candidate)**

Candidate target id: **`bch-cashscript`**

This note records the first ProofForge classification for Bitcoin Cash smart
contracts through CashScript. It does not add a Lean target profile yet.

Primary sources:

- [What is CashScript?](https://cashscript.org/docs/basics/about)
- [Intro to Bitcoin Cash](https://cashscript.org/docs/basics/about-bch)
- [Getting Started](https://cashscript.org/docs/basics/getting-started)
- [Contract Structure](https://cashscript.org/docs/language/contracts)
- [Covenants & Introspection](https://cashscript.org/docs/guides/covenants)
- [Global Variables](https://cashscript.org/docs/language/globals)
- [Global Functions](https://cashscript.org/docs/language/functions)
- [CashScript compiler](https://cashscript.org/docs/compiler)
- [TypeScript SDK](https://cashscript.org/docs/sdk)

## Classification

Bitcoin Cash through CashScript should be treated as a UTXO script/covenant
source-generation target.

```text
Bitcoin Cash CashScript target
  -> generated or wrapped .cash source
  -> cashc contract artifact JSON
  -> BCH Script locking bytecode
  -> TypeScript SDK transaction builder / unlockers
  -> local MockNetworkProvider, chipnet, or node-backed validation
```

BCH is not EVM, Wasm, Move, Solana, or a generic Bitcoin target. It shares the
UTXO model with Bitcoin, but BCH smart-contract programmability has diverged
through CashVM upgrades such as native introspection, larger arithmetic, script
limit changes, and CashTokens.

## Why This Matters For ProofForge

ProofForge should model BCH/CashScript around spending UTXOs, not calling
stateful contract methods.

Target-specific concerns:

- contracts lock UTXOs; contract functions are spend paths;
- there is no global mutable contract state;
- constructor arguments become part of the locking script;
- function arguments are provided by the unlocking script and are untrusted;
- covenants inspect and constrain the current transaction, especially outputs;
- local state may be represented through CashTokens NFT commitments or simulated
  state embedded in new P2SH locking bytecode;
- value is BCH satoshis attached to UTXOs;
- CashTokens expose token category, capability, NFT commitment, and fungible
  amount fields through introspection;
- time/sequence behavior uses transaction locktime, sequence numbers, and
  script checks;
- the SDK and transaction builder are part of the practical target surface.

## Candidate Target Family

Candidate family:

```text
utxo-script-sourcegen
```

Candidate artifact shape:

```text
bch-cashscript-package
  - generated .cash source
  - cashc artifact JSON
  - locking bytecode / script hash metadata
  - constructor and unlocker manifest
  - transaction-builder scenario manifest
  - optional covenant/introspection manifest
  - optional CashTokens/local-state manifest
  - mocknet, chipnet, or node-backed validation report
```

The first useful artifact should be reviewable and executable through
CashScript tooling before claiming broader BCH support.

## Candidate Capabilities

Some existing capabilities have rough BCH interpretations, but they need review:

| Existing capability | BCH/CashScript interpretation |
|---|---|
| `storage.scalar` | No global slot storage; only script constants, UTXO-local data, or token commitments. |
| `storage.map` | Not a native capability in the EVM sense. |
| `caller.sender` | Spender identity is usually proven through signatures, not a caller field. |
| `value.native` | Satoshis on UTXO inputs and outputs. |
| `events.emit` | No EVM-style event logs; use transactions and off-chain indexing. |
| `crosscall.invoke` | No synchronous contract call; compose UTXOs and outputs in a transaction. |
| `env.block` | Locktime, sequence, and transaction context are available through script rules. |
| `crypto.hash` | BCH Script/CashScript hash and signature checks. |

Candidate capabilities that may need explicit ids later:

| Candidate capability | Meaning |
|---|---|
| `storage.utxo` | State and value live in spendable UTXOs. |
| `script.p2sh` | Contract deployment/addressing uses P2SH locking scripts. |
| `script.unlocker` | Contract calls are unlocking scripts for selected UTXOs. |
| `tx.introspection` | Contract reads current transaction inputs/outputs and active input data. |
| `covenant.introspection` | Contract constrains successor outputs using native introspection. |
| `storage.local_state` | Local state is simulated through script data or CashTokens NFT commitments. |
| `asset.cashtoken` | Contract handles CashTokens categories, capabilities, NFT commitments, and token amounts. |
| `timelock.locktime` | Contract depends on locktime, sequence, or age checks. |
| `signature.checksig` | Contract verifies public-key signatures as a first-class spend condition. |
| `artifact.cashscript` | Build emits a CashScript artifact JSON and bytecode metadata. |
| `tx.builder` | Practical validation includes building and evaluating a spend transaction. |

Do not add these ids to `ProofForge.Target.Capability` until a target profile
and lowering rules are reviewed.

## Implementation Road

### Road 1: CashScript Sourcegen

This is the most conservative first spike. Generate or wrap a `.cash` contract
and validate it with CashScript tooling.

First spike:

- choose a simple `TransferWithTimeout` or Counter-like covenant scenario;
- generate a minimal `.cash` source file or manifest around hand-authored
  CashScript;
- compile with `cashc` into artifact JSON;
- use the TypeScript SDK with `MockNetworkProvider` to build and evaluate a
  transaction spending the contract UTXO;
- record source, artifact JSON, bytecode, transaction scenario, tool versions,
  and validation result in artifact metadata.

This path validates BCH semantics before any lower-level BCH Script generation.

### Road 2: Restricted UTXO Covenant IR

This road should follow after the sourcegen spike. It would model the common
UTXO/covenant ideas shared by BCH and some other UTXO targets while preserving
BCH-specific semantics.

First spike:

- define a restricted IR for UTXO spend paths and successor-output constraints;
- model active input, input/output introspection, token fields, and timelocks;
- keep complex multi-UTXO protocols and CashTokens-heavy designs out of the
  first direct path;
- generate CashScript from the IR before considering raw BCH Script emission.

## Non-Goals For The First Pass

- Do not add `bch-cashscript` to the code registry yet.
- Do not classify BCH as EVM, Wasm-host, Move, or generic Bitcoin.
- Do not model contract functions as stateful method calls.
- Do not model UTXO-local state as global storage.
- Do not hide transaction-builder requirements from artifact metadata.
- Do not treat CashTokens as generic ERC-20-like assets.
- Do not claim supported BCH output until a local compile/build-transaction
  smoke exists.

## Research Exit Criteria

BCH/CashScript can leave Research only when we have:

- a reviewed target profile proposal;
- a decided first spike path, likely CashScript sourcegen;
- a minimal UTXO spend scenario with at least one contract function;
- a transaction-builder validation policy;
- a covenant/introspection policy;
- a CashTokens/local-state policy, even if deferred from the first spike;
- a documented toolchain requirement set, including Node.js, `cashc`, and the
  CashScript SDK;
- at least one reproducible local validation command;
- artifact metadata for source, CashScript artifact JSON, bytecode,
  transaction scenario, toolchain versions, and validation result.
