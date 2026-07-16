# TON TVM Target

Status: **Research (docs-first candidate)**

Candidate target id: **`ton-tvm`**

This note records the first ProofForge classification for TON smart contracts.
It does not add a Lean target profile yet.

Primary sources:

- [Smart contracts overview](https://docs.ton.org/contracts/overview)
- [Tolk language](https://docs.ton.org/tolk/overview)
- [TVM overview](https://docs.ton.org/blockchain-basics/tvm/overview)
- [TVM gas](https://docs.ton.org/blockchain-basics/tvm/gas)
- [Get methods](https://docs.ton.org/blockchain-basics/tvm/get-methods)
- [Messages overview](https://docs.ton.org/blockchain-basics/primitives/messages/overview)
- [Account status](https://docs.ton.org/blockchain-basics/account-status)
- [Execution phases](https://docs.ton.org/blockchain-basics/transactions/execution-phases)
- [Transaction fees](https://docs.ton.org/blockchain-basics/transactions/transaction-fees)
- [Blockchain sharding](https://docs.ton.org/blockchain-basics/blockchain-sharding)

## Classification

TON should not be treated as a Wasm-host target. The first classification should
be a TVM source/package-generation target.

```text
TON TVM target
  -> Tolk source or lower-level TON contract package
  -> Fift / TVM code through TON tooling
  -> cell/slice storage and TL-B serialization
  -> message handlers and get methods
  -> action list / outbound messages
```

The current TON docs present Tolk as the recommended smart-contract language
and Acton as the recommended all-in-one toolchain. Legacy FunC/Fift knowledge is
still relevant because TVM and cells remain the execution and data substrate.

## Why This Matters For ProofForge

ProofForge should not model TON like EVM, Wasm, Move, or Solana. The target
differences are not cosmetic:

- contract state is serialized into cells, not slots or account resources;
- entrypoints are message handlers and get methods, not ordinary method calls;
- inbound messages may be internal or external and carry TON-specific bodies,
  values, bounce behavior, and sender semantics;
- outbound effects are represented through an action list, especially message
  sends;
- serialization and ABI surfaces are TL-B/cell-oriented;
- gas and fees are tied to TVM execution, storage, forwarding, and message
  handling;
- account lifecycle and execution phases affect contract behavior;
- sharding and asynchronous messaging make direct cross-contract assumptions
  unsafe;
- standardized contracts such as wallets, jettons, and NFTs are target-native
  surfaces, not generic token interfaces.

## Candidate Target Family

Candidate family:

```text
tvm-sourcegen
```

Candidate artifact shape:

```text
ton-tvm-package
  - generated Tolk or lower-level TON source
  - compiled TVM code / BOC artifact
  - TL-B or interface manifest
  - initial state / StateInit manifest
  - get-method manifest
  - action/message schema
  - local test/deploy validation report
```

The first useful artifact should be a reviewable package that makes cell layout,
message decoding, and outbound actions explicit.

## Candidate Capabilities

Some existing capabilities have rough TON interpretations, but they need review:

| Existing capability | TON interpretation |
|---|---|
| `storage.scalar` | Field serialized into contract data cells. |
| `storage.map` | Dictionary/cell-based storage; semantics are not EVM mapping slots. |
| `caller.sender` | Message sender, subject to internal/external message form. |
| `value.native` | TON value attached to an inbound message. |
| `events.emit` | No direct EVM-style event log; use messages, traces, or off-chain indexing patterns. |
| `crosscall.invoke` | Send outbound messages through actions; asynchronous semantics. |
| `env.block` | Config, time, logical time, and chain context need target-specific review. |
| `crypto.hash` | TVM/Tolk hash and signature primitives where available. |

Candidate capabilities that may need explicit ids later:

| Candidate capability | Meaning |
|---|---|
| `storage.cell` | Contract state is encoded as cells/slices/builders. |
| `abi.tlb` | Build emits or validates TL-B/cell layout metadata. |
| `message.recv` | Contract handles internal/external inbound messages. |
| `message.send` | Contract emits outbound messages through action list semantics. |
| `method.get` | Contract exposes off-chain get methods. |
| `action.list` | Target effects are accumulated in TVM action lists. |
| `state.init` | Deployment requires code/data `StateInit` handling. |
| `account.status` | Account lifecycle/status affects contract behavior. |
| `gas.tvm` | TVM gas and fee model is explicit. |
| `asset.jetton` | Contract integrates TON jetton/token standards. |

Do not add these ids to `ProofForge.Target.Capability` until a target profile
and lowering rules are reviewed.

## Implementation Road

### Road 1: Tolk Package Sourcegen

This is the most conservative first spike. Generate or wrap a Tolk contract and
validate it through the recommended TON toolchain.

First spike:

- choose a Counter-like contract with one internal message and one get method;
- define the storage cell layout explicitly;
- generate a minimal Tolk package or manifest around hand-authored source;
- compile with Acton or the current TON compiler path;
- record TVM/BOC artifacts, interface metadata, initial state, and validation
  result in artifact metadata.

This road validates TON semantics before attempting lower-level TVM emission.

### Road 2: Lower-Level TVM/Cell IR

This road would target TVM more directly after the sourcegen spike clarifies the
contract shape.

First spike:

- define a restricted cell/slice serialization IR;
- model inbound message decoding and outbound action emission;
- keep sharding, advanced libraries, jettons, and upgrades out of the first
  direct TVM path;
- validate against a local TON toolchain or emulator.

This should wait until the source package route produces reviewable artifacts.

## Non-Goals For The First Pass

- Do not add `ton-tvm` to the code registry yet.
- Do not classify TON as Wasm-host, EVM, Move, or ZK circuit sourcegen.
- Do not model TON storage as EVM slots.
- Do not treat message sends as synchronous cross-contract calls.
- Do not treat get methods and message handlers as the same entrypoint kind.
- Do not hide cell/TL-B layout behind generic JSON ABI.
- Do not claim supported TON output until a local compile/test smoke exists.

## Research Exit Criteria

TON can leave Research only when we have:

- a reviewed target profile proposal;
- a decided first spike path: Tolk package sourcegen or direct TVM/cell IR;
- a minimal Counter-like scenario with an internal message and get method;
- a cell/TL-B layout policy;
- a StateInit/deployment artifact policy;
- a documented toolchain requirement set, likely starting with Acton/Tolk;
- at least one reproducible local validation command;
- artifact metadata for source, TVM/BOC output, interface metadata, initial
  state, and validation result.
