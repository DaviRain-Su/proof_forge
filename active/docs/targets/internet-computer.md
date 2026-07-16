# Internet Computer Target

Status: **Research (docs-first candidate)**

Candidate target id: **`wasm-icp-canister`**

This note records the first ProofForge classification for Internet Computer
canisters. It does not add a Lean target profile yet.

Primary sources:

- [Languages & CDKs](https://docs.internetcomputer.org/languages/)
- [Canisters](https://docs.internetcomputer.org/concepts/canisters/)
- [Orthogonal persistence](https://docs.internetcomputer.org/concepts/orthogonal-persistence/)
- [Candid interface](https://docs.internetcomputer.org/guides/canister-calls/candid/)
- [Inter-canister calls](https://docs.internetcomputer.org/guides/canister-calls/inter-canister-calls/)
- [Rust CDK](https://docs.internetcomputer.org/languages/rust/)
- [IC interface specification](https://docs.internetcomputer.org/references/ic-interface-spec/)
- [Management canister](https://docs.internetcomputer.org/references/ic-interface-spec/management-canister/)
- [Developer tools](https://docs.internetcomputer.org/developer-tools/)

## Classification

Internet Computer canisters belong in the Wasm-host family, but they must be a
separate target from NEAR, CosmWasm, and Stellar/Soroban.

```text
Internet Computer canister target
  -> Motoko or CDK authoring model today
  -> Wasm canister module
  -> Candid service/interface metadata
  -> IC System API and management canister
  -> local replica / PocketIC / ICP CLI validation
```

ICP is not a generic Wasm chain. Canisters are Wasm smart contracts with
persistent state, a Candid interface, query/update/composite-query call modes,
principal identities, cycles accounting, async inter-canister calls, and a
management canister lifecycle.

## Why This Matters For ProofForge

The current Wasm-family model still applies: share common Wasm runtime pieces,
but keep the host adapter and contract ABI target-specific.

For ICP, the target-specific concerns are:

- any language that targets Wasm can be used, but production development is
  normally through Motoko or a CDK such as Rust `ic-cdk`;
- Motoko has first-class actor, async/await, Candid, and orthogonal persistence
  support;
- Rust canisters use macros and CDK glue for exposing methods, Candid
  serialization, stable memory, and System API calls;
- public methods are not just functions: update, query, and composite query
  modes have different persistence, consensus, cost, and call restrictions;
- canisters identify users and canisters through principals;
- persistent state is canister memory, stable memory, or CDK-managed stable
  structures, not an EVM-style slot store;
- inter-canister calls are asynchronous message flows, not direct synchronous
  calls;
- cycles pay for compute, memory, messages, and lifecycle operations;
- deployment and upgrades go through canister lifecycle and management canister
  APIs;
- Candid service/interface metadata is part of the public contract surface.

## Candidate Target Family

Candidate family:

```text
wasm-host
```

Candidate artifact shape:

```text
icp-canister-package
  - Wasm canister module
  - Candid .did service interface
  - canister manifest / icp.yaml or dfx-style metadata
  - stable-state or upgrade manifest
  - optional generated client bindings
  - local replica, PocketIC, or ICP CLI validation report
```

The first artifact should be reviewable and runnable locally before claiming
mainnet-ready Internet Computer support.

## Candidate Capabilities

Some existing capabilities overlap with the canister model:

| Existing capability | ICP interpretation |
|---|---|
| `storage.scalar` | Canister memory or stable structure entry for scalar state. |
| `storage.map` | Stable structure or CDK-managed map storage. |
| `caller.sender` | Caller principal. |
| `events.emit` | Logs, certified data, or target-specific observable output; semantics need review. |
| `crosscall.invoke` | Inter-canister calls, but async semantics need explicit handling. |
| `env.block` | Not a block model; ledger time, subnet context, and randomness need separate review. |
| `crypto.hash` | Host/CDK crypto helpers where available. |

Candidate capabilities that may need explicit ids later:

| Candidate capability | Meaning |
|---|---|
| `abi.candid` | Build emits and validates a Candid service interface. |
| `canister.method_mode` | Entry points distinguish update, query, and composite query methods. |
| `storage.stable_memory` | State uses stable memory or stable structures across upgrades. |
| `storage.orthogonal_persistence` | State persistence follows Motoko-style orthogonal persistence semantics. |
| `principal.id` | Caller/canister/user identity is a Principal, not an address. |
| `cycles.manage` | Target can inspect, accept, send, or account for cycles. |
| `crosscall.async` | Cross-canister calls are asynchronous message flows with callback/error behavior. |
| `canister.lifecycle` | Target supports install, upgrade, stop/start, and lifecycle hooks. |
| `certified.data` | Target exposes certified variables or certified HTTP/data responses. |
| `management.canister` | Target can call the virtual management canister for lifecycle and system APIs. |

Do not add these ids to `ProofForge.Target.Capability` until a target profile
and lowering rules are reviewed.

## Implementation Road

### Road 1: Native Canister Package Sourcegen

This is the most conservative first spike. Generate or wrap a Motoko or Rust CDK
canister package and validate it with ICP tooling.

First spike:

- choose a Counter-like canister with one update method and one query method;
- emit or wrap a Candid interface;
- validate with a local replica, PocketIC, or ICP CLI command;
- record Wasm, Candid, canister manifest, tool versions, and validation result
  in artifact metadata.

This path validates canister semantics before committing to a direct Lean
runtime bridge.

### Road 2: Direct Wasm Host Bridge

This road mirrors the broader Wasm-host direction: Lean lowers to a Wasm
canister module plus an ICP-specific host bridge.

First spike:

- define the minimal `Lean.ICP` SDK surface;
- map caller principals, update/query methods, stable memory, and Candid
  encoding explicitly;
- keep inter-canister calls out of the first direct bridge unless async
  semantics are modeled;
- emit a Wasm canister module and `.did` file accepted by local ICP tooling.

This should wait until the Wasm runtime split avoids force-linking NEAR,
CosmWasm, or Soroban host code.

## Non-Goals For The First Pass

- Do not add `wasm-icp-canister` to the code registry yet.
- Do not merge ICP with `wasm-near`, `wasm-cosmwasm`, or
  `wasm-stellar-soroban`.
- Do not model query and update methods as the same kind of entrypoint.
- Do not treat cycles as ordinary native token value.
- Do not ignore upgrade and stable-memory behavior when modeling storage.
- Do not treat inter-canister calls as synchronous cross-contract calls.
- Do not claim supported ICP output until a local canister build/call smoke
  exists.

## Research Exit Criteria

ICP can leave Research only when we have:

- a reviewed target profile proposal;
- a decided first spike path: native Motoko/Rust CDK package sourcegen or direct
  Wasm host bridge;
- a minimal Counter-like shared scenario with update/query calls;
- a Candid artifact policy;
- a stable memory / upgrade policy;
- a documented toolchain requirement set;
- at least one reproducible local validation command;
- artifact metadata for Wasm, Candid, canister manifest, toolchain versions, and
  validation result.
