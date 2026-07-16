# Algorand AVM Target

Status: **Research (docs-first candidate)**

Candidate target id: **`algorand-avm`**

This note records the first ProofForge classification for Algorand smart
contracts. It does not add a Lean target profile yet.

Primary sources:

- [Smart contracts overview](https://dev.algorand.co/concepts/smart-contracts/overview/)
- [Algorand Virtual Machine](https://dev.algorand.co/concepts/smart-contracts/avm/)
- [Algorand Python](https://dev.algorand.co/concepts/smart-contracts/languages/python/)
- [Algorand TypeScript](https://dev.algorand.co/concepts/smart-contracts/languages/typescript/)
- [Applications](https://dev.algorand.co/concepts/smart-contracts/apps/)
- [Logic Signatures](https://dev.algorand.co/concepts/smart-contracts/logic-sigs/)
- [ABI](https://dev.algorand.co/concepts/smart-contracts/abi/)
- [On-chain storage](https://dev.algorand.co/concepts/smart-contracts/storage/overview/)
- [Inner transactions](https://dev.algorand.co/concepts/smart-contracts/inner-txn/)
- [Resource usage](https://dev.algorand.co/concepts/smart-contracts/resource-usage/)
- [Costs and constraints](https://dev.algorand.co/concepts/smart-contracts/costs-constraints/)
- [Atomic transaction groups](https://dev.algorand.co/concepts/transactions/atomic-txn-groups/)
- [AlgoKit compile](https://dev.algorand.co/algokit/cli/compile/)
- [AlgoKit LocalNet](https://dev.algorand.co/algokit/cli/localnet/)

## Classification

Algorand should be treated as an AVM/TEAL source or package-generation target.
It is not EVM, Wasm-host, Move, Solana sBPF, TVM, UTXO script, or a ZK circuit
target.

```text
Algorand AVM target
  -> generated or wrapped Algorand Python / TypeScript / TEAL package
  -> Puya / AlgoKit compile path
  -> approval + clear-state AVM programs, or LogicSig program
  -> ARC-4 / ABI and app spec metadata
  -> localnet or simulator-backed application call validation
```

The high-level language surface matters because current Algorand development is
centered on Algorand Python and Algorand TypeScript, but the target boundary for
ProofForge should be the AVM execution and artifact model.

## Why This Matters For ProofForge

ProofForge should not model Algorand as an account-state EVM clone or a generic
Wasm runtime.

Target-specific concerns:

- stateful applications have approval and clear-state programs;
- stateless smart signatures use LogicSig programs and are a separate artifact
  shape;
- public method dispatch is normally described through ABI / ARC-4 conventions;
- persistent data can be global state, account-local state, or box storage;
- application calls must include explicit resource references when touching
  accounts, assets, boxes, or other apps;
- transactions can be grouped atomically, and contracts can inspect grouped
  transactions;
- applications can issue inner transactions;
- native assets are Algorand Standard Assets, not ERC-20-like contracts;
- AVM opcode costs, program limits, and minimum balance requirements affect
  lowering and validation;
- local validation should use AlgoKit LocalNet, an AVM simulator path, or a
  sandboxed app-call workflow before claiming support.

Algorand has cryptographic primitives and consensus-level state proofs, but this
target is not a ZK circuit sourcegen target. A future Algorand proof-related
feature should be modeled as a capability only if the application target
actually verifies or consumes that proof data.

## Candidate Target Family

Candidate family:

```text
avm-sourcegen
```

Candidate artifact shape:

```text
algorand-avm-package
  - generated Algorand Python, Algorand TypeScript, or TEAL source
  - approval program bytecode
  - clear-state program bytecode when stateful
  - LogicSig program bytecode when stateless
  - ARC-4 / ABI / app spec metadata
  - schema for global, local, and box storage
  - resource-reference and atomic-group manifest
  - inner-transaction manifest when used
  - toolchain versions and localnet or simulator validation report
```

The first useful artifact should make the app-vs-LogicSig choice explicit and
should record the ABI, storage schema, and resource references needed to run the
contract.

## Candidate Capabilities

Some existing capabilities have rough Algorand interpretations, but they need
review:

| Existing capability | Algorand interpretation |
|---|---|
| `storage.scalar` | Global, local, or box-backed state item, depending on target policy. |
| `storage.map` | Box-backed maps or encoded app state; not EVM mapping slots. |
| `caller.sender` | Transaction sender or application-call sender. |
| `value.native` | Algo payment in the transaction group or inner transaction, not call value. |
| `events.emit` | Logs through AVM logging and off-chain indexing conventions. |
| `crosscall.invoke` | App calls or inner transactions; semantics are not synchronous EVM calls. |
| `env.block` | Round, timestamp, group, and transaction context through AVM/global fields. |
| `crypto.hash` | AVM cryptographic opcodes and supported hashing/signature checks. |

Candidate capabilities that may need explicit ids later:

| Candidate capability | Meaning |
|---|---|
| `avm.application` | Target emits stateful application approval and clear-state programs. |
| `avm.logicsig` | Target emits a stateless LogicSig program. |
| `abi.arc4` | Build emits or validates ARC-4 ABI/app-spec metadata. |
| `storage.global` | Contract uses application global state. |
| `storage.local` | Contract uses account-local application state. |
| `storage.box` | Contract uses box storage with explicit box references. |
| `tx.group` | Contract depends on atomic transaction group ordering or inspection. |
| `tx.resource_refs` | App call requires explicit accounts, assets, apps, or boxes references. |
| `itxn.submit` | Application submits inner transactions. |
| `asset.asa` | Contract handles Algorand Standard Assets. |
| `gas.avm_budget` | Lowering tracks AVM opcode budget, costs, and program limits. |
| `artifact.algokit` | Build emits AlgoKit/Puya app artifacts and validation metadata. |

Do not add these ids to `ProofForge.Target.Capability` until a target profile
and lowering rules are reviewed.

## Implementation Road

### Road 1: Algorand Python Or TypeScript Package Sourcegen

This is the most conservative first spike. Generate or wrap a small Algorand
Python or Algorand TypeScript application and validate it through AlgoKit/Puya.

First spike:

- choose a Counter-like stateful application with one increment method and one
  read method;
- generate source or a manifest around hand-authored source;
- compile with AlgoKit/Puya into approval and clear-state AVM programs;
- emit ABI/app spec and storage schema metadata;
- run a localnet or simulator-backed create/call/query validation;
- record source, bytecode, app spec, storage schema, resource references, tool
  versions, and validation result in artifact metadata.

This path validates Algorand-specific application semantics before any direct
TEAL emission.

### Road 2: Restricted TEAL/AVM Emitter

This road should follow only after the package route has clarified the exact
artifact and validation shape.

First spike:

- define a restricted AVM-friendly IR subset;
- lower simple arithmetic, storage reads/writes, assertions, logs, and ABI
  routing;
- keep dynamic resource discovery, complex grouped transactions, inner asset
  flows, and LogicSig support out of the first direct path;
- validate generated TEAL against the same localnet or simulator scenario.

## Non-Goals For The First Pass

- Do not add `algorand-avm` to the code registry yet.
- Do not classify Algorand as Wasm-host, EVM, Move, Solana, TVM, UTXO, or ZK
  circuit sourcegen.
- Do not model Algo payment as EVM call value.
- Do not treat global, local, and box storage as one undifferentiated map.
- Do not hide app-call resource references from artifact metadata.
- Do not claim LogicSig support from a stateful application-only spike.
- Do not claim supported Algorand output until a local compile and app-call
  smoke exists.

## Research Exit Criteria

Algorand can leave Research only when we have:

- a reviewed target profile proposal;
- a decided first spike path, likely Algorand Python or TypeScript sourcegen;
- an app-vs-LogicSig policy;
- a minimal Counter-like application scenario;
- an ABI/app-spec and storage-schema policy;
- a resource-reference and transaction-group policy;
- an inner-transaction policy, even if deferred from the first spike;
- a documented toolchain requirement set, including AlgoKit and the chosen
  language compiler path;
- at least one reproducible local validation command;
- artifact metadata for source, AVM bytecode, ABI/app spec, storage schema,
  resource references, toolchain versions, and validation result.
