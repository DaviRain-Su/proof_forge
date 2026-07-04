# EVM Target

Target id: **`evm`**

Stage: **Experimental** — CI smoke tests, target registry, portable IR
diagnostic/coverage gates, and EVM artifact metadata validation are wired.

Related: [Capability registry](../capability-registry.md),
[Shared scenario](../shared-scenario.md),
[RFC 0002](../rfcs/0002-target-implementation-design.md),
[RFC 0004](../rfcs/0004-evm-semantic-plan.md).

## Pipeline

```text
Lean contract_source / ContractSpec
  -> portable IR
  -> EVM semantic plan
  -> Yul AST
  -> Yul Printer
  -> solc --strict-assembly
  -> EVM runtime bytecode
  -> artifact + deploy metadata
  -> Foundry / Anvil smoke
```

The product entry is `contract_source` (or another producer of
`ContractSpec`). `proof-forge build --target evm` loads `spec` from the Lean
module through `ContractLoader`, lowers the resulting portable IR through the
EVM semantic plan, prints Yul from the shared Yul AST, then invokes
`solc --strict-assembly` for runtime bytecode. The same build writes
machine-readable artifact metadata and, for bytecode builds, a deploy manifest.

RFC 0004's semantic-plan architecture is the EVM product pipeline (Accepted;
see D-046). The removed `ProofForge.Evm` / `Lean.Evm` / LCNF `EmitYul` /
`.evm-methods` route is historical context only and is not in the current tree.

## EVM-Compatible Chain Profiles

EVM-compatible L1s, L2s, and app chains do not need separate compiler targets
when they execute standard EVM bytecode. ProofForge treats them as chain
profiles below the `evm` target:

```text
ProofForge target: evm
  -> EVM runtime bytecode + ABI
  -> EVM-compatible chain profile
  -> RPC deployment / explorer verification / chain metadata
```

The target profile owns compilation semantics and capabilities. The chain
profile owns deployment metadata such as chain id, RPC endpoints, native gas
symbol, explorer, rollup family, and verifier settings. Chain-specific L2
contracts, bridges, precompiles, account abstraction services, or gas
accounting differences should be modeled as profile metadata or optional
deployment capabilities, not as a second EVM compiler backend.

Implemented chain profiles:

| Chain profile id | Compiler target | Chain id | Native gas | Rollup family | Public RPC | Explorer / verifier |
|---|---|---:|---|---|---|---|
| `robinhood-chain-testnet` | `evm` | `46630` | `ETH` | Arbitrum Orbit L2, Ethereum blobs DA | `https://rpc.testnet.chain.robinhood.com` | `https://explorer.testnet.chain.robinhood.com`, Blockscout API `https://explorer.testnet.chain.robinhood.com/api/` |
| `anvil-local` | `evm` | `31337` | `ETH` | Local Foundry Anvil validation | `http://127.0.0.1:8545` | none |

Robinhood Chain is therefore already covered for ordinary contract compilation
by the EVM backend. EVM bytecode modes can select
`robinhood-chain-testnet` with `--evm-chain-profile` and record the profile in
the deploy manifest. Local Anvil deployment uses the `anvil-local` profile by
default in the smoke harness, proving the same profile metadata path can drive
local deployment validation. Full product support still needs live-network
deployment commands that pass the profile's RPC metadata to wallet/broadcast
tooling and record signed or broadcast transaction artifacts for the selected
chain.

## Build Commands

```sh
lake build

lake env proof-forge build --target evm --root . \
  --artifact-output build/evm/Counter.proof-forge-artifact.json \
  -o build/evm/Counter.bin Examples/Evm/Contracts/Counter.lean

scripts/evm/build-examples.sh
scripts/evm/foundry-smoke.sh
scripts/evm/anvil-deploy-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/assert-ir-smoke.sh
scripts/evm/assignment-ir-smoke.sh
scripts/evm/assign-op-ir-smoke.sh
scripts/evm/conditional-ir-smoke.sh
scripts/evm/loop-ir-smoke.sh
scripts/evm/context-ir-smoke.sh
scripts/evm/event-ir-smoke.sh
scripts/evm/crosscall-ir-smoke.sh
scripts/evm/hash-ir-smoke.sh
scripts/evm/map-ir-smoke.sh
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/typed-storage-ir-smoke.sh
scripts/evm/array-value-ir-smoke.sh
scripts/evm/struct-value-ir-smoke.sh
scripts/evm/abi-aggregate-ir-smoke.sh
```

## CLI modes

Target-first `contract_source` build:

```sh
proof-forge build --target evm [--root DIR] [--module Mod.Name] [--yul-output file] [--artifact-output file] [--evm-chain-profile id] [--evm-constructor-param name:type] [--evm-constructor-arg name=value] [--evm-constructor-args-hex hex] [-o output.bin] input.lean
```

Portable IR fixture modes:

```sh
proof-forge emit --target evm --fixture counter --format yul [-o output.yul]
proof-forge emit --target evm --fixture counter --format bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]
proof-forge emit --target evm --fixture <fixture-id> --format yul [-o output.yul]
proof-forge emit --target evm --fixture <fixture-id> --format bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]
```

The complete fixture list is available through `proof-forge --list-fixtures`.
Legacy aliases such as `--evm-bytecode`, `--bytecode`, and
`--emit-*-ir-yul` remain available during the RFC 0009 compatibility window,
but new scripts and docs should use the target-first surface.

`--solc <path>` and `--cast <path>` override external tool paths.
`--evm-chain-profile <id>` records a known EVM chain profile, such as
`robinhood-chain-testnet`, in the generated deploy manifest without signing or
broadcasting a transaction.

Deploy (broadcast or plan-only):

```sh
proof-forge deploy --target evm --deploy-manifest build/evm/Counter.proof-forge-deploy.json \
  --evm-chain-profile anvil-local --start-anvil \
  -o build/evm/Counter.proof-forge-deploy-run.json

proof-forge deploy --target evm --deploy-manifest build/evm/Counter.proof-forge-deploy.json \
  --evm-chain-profile robinhood-chain-testnet --plan-only \
  -o build/evm/Counter.proof-forge-deploy-plan.json
```

Local Anvil deployments use `cast send --create`, record `cast send` receipts
and `eth_getTransactionByHash` creation transactions, and write
`*.proof-forge-deploy-run.json`. Public testnet profiles default to
`--plan-only`, which writes `*.proof-forge-deploy-plan.json` with the profile
RPC metadata and a documented `cast` broadcast command template instead of
signing live transactions.
`--evm-constructor-param <name:type>` records static-word constructor ABI
schema metadata in `abi.constructor.params`. Supported schema types are
`uint256`, `uint64`, `uint32`, `bool`, `bytes32`, and `address`.
`--evm-constructor-arg <name=value>` ABI-encodes one typed constructor value
using the declared schema. Unsigned integer values may be decimal or
`0x`-prefixed hex; `bool` accepts `true`, `false`, `1`, or `0`; `bytes32`
expects exactly 32 hex bytes; `address` expects exactly 20 hex bytes and is
left-padded to one ABI word. Typed constructor args cannot be combined with
`--evm-constructor-args-hex`.
`--evm-constructor-args-hex <hex>` appends an ABI-encoded constructor argument
blob to generated `.init.bin` creation bytecode and records the normalized hex,
byte length, SHA-256, and source flag in `proof-forge-deploy.json`.
`--artifact-output <path>` overrides the default EVM metadata path. Without an
override, bytecode modes write `proof-forge-artifact.json` next to the bytecode
output and `proof-forge-deploy.json` next to the metadata file. When smoke
scripts pass fixture-specific metadata paths such as
`Counter.proof-forge-artifact.json`, the deploy manifest is written as
`Counter.proof-forge-deploy.json`.

## ABI metadata and selectors

`contract_source` entrypoints, queries, constructor declarations, and events are
the selector-facing ABI source of truth. The EVM backend derives
Solidity-style signatures, 4-byte selectors, calldata word layout, return-data
word layout, event signatures, `topic0`, indexed/data field encodings, and
generated Yul dispatcher functions from the `ContractSpec` / portable IR. No
`.evm-methods` sidecar is required for new examples.

Legacy `.evm-methods` parsing remains only inside the RFC 0009 compatibility
window for older callers. New documentation, scripts, and examples should not
add sidecars or `@[export l_<Contract>_<method>]` entrypoints.

## Adding or changing an EVM example

1. Add or update the Lean contract under `Examples/Evm/Contracts/`.
2. Use `contract_source` directly, or define
   `spec : ProofForge.Contract.ContractSpec` by composing importable
   `contract_source`/stdlib modules.
3. Add or update the sibling `.golden.yul` file; `scripts/evm/build-examples.sh`
   diffs generated Yul against this fixture.
4. If the example is part of the baseline, add or update a case in
   `scripts/evm/foundry-smoke.sh`.
5. Run `scripts/evm/build-examples.sh`; run `scripts/evm/foundry-smoke.sh` when
   Foundry and `solc` are available.

## Implemented Capabilities

Mapped to [capability-registry](../capability-registry.md) ids:

| Capability id | `contract_source` / IR surface |
|---|---|
| `storage.scalar` | `contract_source state`; portable IR `Bool`/`U32`/`U64`/`Hash` scalar storage read/write, scalar storage compound assignment for numeric words, flat scalar storage struct field read/write, and whole flat scalar storage struct read/write |
| `storage.map` | `Storage.mapLoad`, `Storage.mapStore`; portable IR `Map<K, V, N>` get/set/insert/contains and one-or-more-segment consecutive `mapKey` storage paths where `K` and `V` are word types (`Bool`, `U32`, `U64`, or `Hash`); `contains` uses ProofForge-managed presence slots so zero-valued keys can still be present |
| `storage.array` | Partial: portable IR `Bool`/`U32`/`U64`/`Hash` fixed storage arrays and fixed arrays of flat structs lower to contiguous EVM storage slots with runtime index bounds checks; word and flat-struct storage arrays can feed fixed-array ABI returns and event aggregate fields through storage reads |
| `data.fixed_array` | Partial: used by portable IR fixed storage arrays, single-segment index storage paths over word arrays, index+field storage paths over struct arrays, immutable and mutable local fixed-array values, fixed-array literals, static and dynamic local/literal index reads, static and dynamic local element assignment/compound assignment, whole local fixed-array assignment with RHS snapshotting, static and dynamic nested scalar local fixed-array reads, static and dynamic nested scalar local leaf assignment/compound assignment, nested whole local fixed-array assignment with RHS snapshotting, local fixed arrays and nested local fixed arrays of flat structs with static/dynamic field reads and writes plus whole local assignment with RHS snapshotting, flat static fixed-array ABI parameters/returns over U64/U32/Hash leaves, nested scalar fixed-array ABI parameters/returns, fixed-array ABI parameters/returns whose elements are flat structs, storage-backed fixed-array ABI returns from word arrays and fixed arrays of flat structs, nested fixed-array typed crosscall arguments/returns whose leaves are scalar words or flat structs, scalar fixed-array event data fields, fixed-array event fields whose elements are flat structs, and nested fixed-array event fields whose leaves are scalar words or flat structs, including non-indexed data flattening and indexed topic hashing from local values, storage array reads, and storage array struct field reads; zero-length ABI arrays, nested local arrays with unsupported aggregate/non-flat leaves, nested crosscall fixed arrays with non-flat struct or unsupported leaves, and unsupported element shapes still reject explicitly |
| `data.struct` | Partial: portable IR flat immutable and mutable local struct values, flat struct elements inside local fixed arrays, struct literals, field access, static local field assignment/compound assignment, whole local struct assignment with RHS snapshotting, flat ABI-facing struct parameters/returns including Hash/bytes32 fields, fixed arrays of flat structs in ABI-facing parameters/returns, storage-backed fixed-array-of-flat-struct ABI returns, flat event data fields and indexed event topic hashing from local values, storage scalar struct reads, storage array struct field reads inside fixed arrays, and nested fixed-array event fields whose leaves are flat structs; flat scalar storage structs including whole read/write, and fixed storage arrays of flat structs lower by expanding supported fields to EVM words; nested fields and unsupported field shapes still reject explicitly |
| `caller.sender` | `contract_source`/portable IR caller context reads |
| `value.native` | `contract_source` `nativeValue` / payable call-value routing |
| `env.block` | Portable IR block/context reads |
| `crosscall.invoke` | SDK `call`, `staticcall`, `delegatecall`, `create`, `create2`; portable IR `crosscallInvoke` lowers to synchronous EVM `call` with a low-32-bit selector, 32-byte word arguments, failed-call reverts, and short-return reverts; typed crosscalls accept Bool/U32/U64/Hash scalar-word arguments plus flat struct, scalar fixed-array, fixed-array-of-flat-struct, and nested fixed-array arguments whose leaves are scalar words or flat structs, flattened to ABI words; typed normal/value/static/delegate calls return Bool/U32/U64/Hash scalar words with Bool/U32 return guards and support direct entrypoint returns of flat struct, scalar fixed-array, fixed-array-of-flat-struct, and nested fixed-array return data whose leaves are scalar words or flat structs; `crosscallInvokeValueTyped` forwards an explicit U64 call value through the EVM `call` value slot; `crosscallInvokeStaticTyped` preserves static-context state-write failure behavior; `crosscallInvokeDelegateTyped` preserves caller-storage context; `crosscallCreate` and `crosscallCreate2` deploy fixed init-code hex through Yul `create`/`create2`, revert on zero-address failure, and return the deployed address word |
| `events.emit` | `log0` through `log4`; portable IR `eventEmit` lowers to `log1`, `eventEmitIndexed` lowers up to `log4`, topic0 is derived from a Solidity-style event signature, non-indexed data fields can be U64/Bool/U32/Hash scalar words, flat structs from local values or storage scalar struct reads, scalar fixed arrays from local values or storage array reads, fixed arrays of flat structs from local literals or storage array struct field reads, or nested fixed arrays whose leaves are scalar words or flat structs, scalar indexed topics can be U64/Bool/U32/Hash words, indexed aggregate fields use `keccak256` over flattened ABI-style words including nested fixed arrays with scalar or flat-struct leaves, and portable IR artifacts record event ABI metadata in `abi.events` |
| `assertions.check` | Portable IR `assert` / `assert_eq` lower to Yul revert guards |
| `control.conditional` | Portable IR `if/else` lowers to Yul `switch` blocks |
| `control.bounded_loop` | Portable IR `boundedFor` lowers to Yul `for` loops with static bounds |
| `crypto.hash` | Portable IR `Hash` values lower to one-word EVM `bytes32`; `hash` / `hash_two_to_one` lower to Yul `keccak256` helpers |
| `data.dynamic_bytes` | Partial: portable IR `bytes` and `string` value types lower as dynamic ABI types with head-tail encoding for entrypoint parameters and returns; `address` is a static single-word type (like `Hash`); `EvmDynamicAbiProbe` validates ABI round-trip for `echo_bytes(bytes)`, `echo_string(string)`, and `transfer(address,uint256)` |
| `account.explicit` | Partial: portable IR `contractId` context reads lower to Yul `address()` |

### Arithmetic semantics

EVM `add`, `sub`, and `mul` lower to **checked** helpers (`__pf_checked_add`,
`__pf_checked_sub`, `__pf_checked_mul`) that revert on U256 overflow or
underflow, matching Solidity 0.8 semantics. The helpers are emitted once per
module that uses them. `div`, `mod`, exponentiation (`exp`), bitwise operators
(`and`, `or`, `xor`, `not`), and shifts (`shl`, `shr`, `sar`) use the raw EVM
builtins because they cannot overflow a 256-bit word. This checked-arithmetic
behavior is implemented in the portable IR EVM plan
(`Backend/Evm/IR.lean` `checkedArithmeticHelperFunctions`), so product builds
revert on add/sub/mul overflow rather than wrapping.

Not supported on EVM (by design for other targets):

- `storage.pda`, `crosscall.cpi`

## Module Layout

- `ProofForge/Contract/Source.lean` — product authoring syntax that emits
  `ContractSpec`.
- `ProofForge/Cli/ContractLoader.lean` — Lean source loader for
  `spec : ContractSpec`.
- `ProofForge/Backend/Evm/Plan.lean` — target semantic plan construction.
- `ProofForge/Backend/Evm/Lower.lean`,
  `ProofForge/Backend/Evm/ToYul.lean`, and `ProofForge/Backend/Evm/IR.lean` —
  portable IR to Yul AST lowering.
- `ProofForge/Backend/Evm/Metadata.lean` and
  `ProofForge/Backend/Evm/Validate.lean` — artifact metadata and validation
  helpers.
- `ProofForge/Compiler/Yul/` — Yul AST and printer shared by EVM codegen.
- `ProofForge/Cli.lean` — `proof-forge` CLI.

Contracts import `ProofForge.Contract.Source` and select the destination chain
through `proof-forge build --target evm`.

## Examples

See [Examples/Evm/README.md](../../Examples/Evm/README.md):

- `Counter.lean` — scalar storage
- `SimpleToken.lean` — ERC-20-style token with mappings
- `ArrayExample.lean` — in-memory arrays
- `VerifiedVault.lean` — proofs in contract module
- `stdlib/` — ERC20, Ownable, Pausable

## Known Limits

- `Nat` capped at U256; no bignum on EVM.
- String manipulation APIs incomplete in Yul runtime.
- The EVM `contract_source` pipeline currently supports scalar storage/ABI,
  assertions, local assignment, local compound assignment, scalar storage
  compound assignment,
  conditionals, context reads, scalar and flat aggregate event data, `Hash`
  word values and hashing,
  word key/value `Map<K, V, N>` storage including managed key presence,
  `Bool`/`U32`/`U64`/`Hash` fixed
  storage arrays, flat scalar storage structs, fixed storage arrays of flat
  structs, immutable and mutable local fixed-array values with static and
  dynamic indexes, static and dynamic nested scalar/flat-struct local
  fixed-array reads and mutable leaf/whole-array updates,
  flat immutable and mutable local struct values over scalar/hash fields, local
  fixed arrays and nested fixed arrays of flat structs with static and dynamic
  field access, flat static
  aggregate ABI parameters and returns, including Hash/bytes32 aggregate leaves,
  nested scalar fixed-array ABI
  parameters and returns, storage-backed fixed-array ABI returns for word
  arrays and fixed arrays of flat structs, synchronous word-returning
  `crosscallInvoke`, typed `crosscallInvokeTyped` over scalar words, flat
  aggregate arguments, and nested fixed-array arguments/returns whose leaves
  are scalar words or flat structs,
  direct entrypoint returns of flat struct, scalar fixed-array, fixed-array of
  flat structs, and nested fixed-array typed normal-call return data whose
  leaves are scalar words or flat structs,
  value-bearing typed scalar and direct aggregate-return
  `crosscallInvokeValueTyped`, typed scalar and direct aggregate-return
  `crosscallInvokeStaticTyped`, typed scalar and direct aggregate-return
  `crosscallInvokeDelegateTyped`, fixed init-code
  `crosscallCreate` and `crosscallCreate2`, static bounded loops, and
  branch/loop-local early returns through Yul `leave`. It rejects wider
  portable IR nodes with explicit diagnostics.
- Portable IR EVM `address`, `bytes`, and `string` types are now supported for
  ABI parameters and returns with head-tail encoding. `address` is a static
  single-word type (like `Hash`); `bytes` and `string` are dynamic types requiring
  head-tail ABI encoding. `EvmDynamicAbiProbe` validates round-trip ABI encoding
  for `echo_bytes(bytes)`, `echo_string(string)`, and `transfer(address,uint256)`
  through Foundry tests including empty, short, multi-word, and special-character
  data, plus malformed calldata and unknown-selector reverts.
- Portable IR EVM still lacks nested local arrays with
  unsupported aggregate or non-flat leaves, nested crosscall fixed
  arrays with non-flat struct or unsupported leaves,
  non-word or aggregate map shapes, nested
  local structs beyond flat struct arrays, richer event declarations,
  dynamic constructor ABI types, variable-length cross-call return data, and
  first-class signed transaction or public-RPC broadcast manifests.

## EVM Gates

The EVM backend is guarded by target-first diagnostics, coverage manifests,
golden Yul snapshots, bytecode compilation, metadata validation, Foundry
runtime tests, and Anvil deployment smoke:

```sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/assert-ir-smoke.sh
scripts/evm/assignment-ir-smoke.sh
scripts/evm/assign-op-ir-smoke.sh
scripts/evm/conditional-ir-smoke.sh
scripts/evm/loop-ir-smoke.sh
scripts/evm/context-ir-smoke.sh
scripts/evm/event-ir-smoke.sh
scripts/evm/crosscall-ir-smoke.sh
scripts/evm/expression-ir-smoke.sh
scripts/evm/hash-ir-smoke.sh
scripts/evm/map-ir-smoke.sh
scripts/evm/typed-map-ir-smoke.sh
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
scripts/evm/typed-storage-ir-smoke.sh
scripts/evm/array-value-ir-smoke.sh
scripts/evm/struct-value-ir-smoke.sh
scripts/evm/abi-aggregate-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
scripts/evm/dynamic-abi-ir-smoke.sh
```

`Tests/EvmCoverage.tsv` records every portable IR constructor as `lowered`,
`validated`, `unsupported`, or `structural` for EVM. New portable IR nodes must
update this manifest before CI passes.

`Tests/EvmDiagnostics.lean` locks the current unsupported-surface behavior so
unsupported EVM IR shapes fail before Yul generation instead of silently
omitting behavior.

`scripts/evm/diagnostic-smoke.sh` also locks EVM constructor CLI diagnostics at
the artifact boundary, including unsupported dynamic constructor ABI types,
missing or duplicate typed values, mixed typed/raw constructor argument sources,
integer overflow, and malformed static-word values such as short addresses.

`AbiScalarProbe` is the first portable IR EVM ABI fixture beyond Counter. It
validates dispatcher calldata decoding for `U64`, `U32`, and `Bool` parameters,
one-word return data for `U64` and `Bool`, golden Yul reproducibility, solc
bytecode generation, and Foundry runtime behavior including malformed calldata
reverts.

`EvmAbiAggregateProbe` validates static aggregate ABI lowering. Struct
parameters, fixed-array parameters, nested scalar fixed arrays such as
`Array<Array<U64,2>,2>`, and fixed arrays whose elements are flat structs
flatten to contiguous calldata words. `U32` and `Bool` words retain dispatcher
range guards, `Hash` leaves lower as Solidity `bytes32` ABI words inside
flat structs and fixed arrays, and flat struct/fixed-array returns, nested
scalar fixed-array returns, and fixed arrays of flat structs encode as
multi-word ABI return data. The smoke checks golden Yul reproducibility,
`solc --strict-assembly`, artifact metadata capabilities `data.struct` and
`data.fixed_array`, structured `abi.entrypoints` selector signatures,
flattened calldata word counts, and return-data word counts, Foundry calls for
struct, hash-struct, array, hash-array, nested-array, and tuple-array
parameters/returns, malformed calldata reverts, and unknown-selector reverts.

`AssertProbe` validates portable IR `assert` and `assert_eq` lowering to Yul
`if iszero(...) { revert(0, 0) }` guards, including Foundry coverage for the
passing path and the assertion-failure revert path.

`AssignmentProbe` validates portable IR mutable scalar local bindings and local
assignment lowering to Yul `let` declarations and `:=` assignments. The smoke
checks golden Yul reproducibility, `solc --strict-assembly` bytecode generation,
successful Foundry execution, and the revert path when the assigned bool guard
is false.

`EvmAssignOpProbe` validates portable IR compound assignment for mutable
`U32`/`U64` locals and `U64` scalar storage. Local compound assignment lowers
to Yul `name := op(name, value)`, while scalar storage compound assignment
lowers to `sstore(slot, op(sload(slot), value))`. Shift operators preserve EVM
operand ordering through `shl(shift, value)` and `shr(shift, value)`. The
smoke checks golden Yul reproducibility, `solc --strict-assembly` bytecode
generation, metadata capability `storage.scalar`, Foundry return values, raw
storage slot updates, and unknown-selector revert behavior. Aggregate targets
remain explicit diagnostics.

`ConditionalProbe` validates portable IR statement-level `if/else` lowering to
Yul `switch condition case 0 { else } default { then }` blocks. The smoke checks
golden Yul reproducibility, `solc --strict-assembly` bytecode generation,
Foundry execution of then/else storage updates, and unknown-selector revert
behavior. EVM-specific branch-local early returns are validated by
`EvmLoopProbe`.

`EvmLoopProbe` validates portable IR `boundedFor` lowering to Yul `for` loops:
the loop prelude declares the index, the condition compares it with the static
exclusive stop bound, and the post block increments it by one. It also validates
branch-local and loop-local early returns by lowering nested `return` statements
to return-value assignments followed by Yul `leave`. The smoke checks golden Yul
reproducibility, `solc --strict-assembly` bytecode generation, metadata
capabilities (`storage.scalar`, `control.conditional`, `control.bounded_loop`),
Foundry runtime storage updates, early-return storage effects, and
unknown-selector revert behavior. Invalid loop ranges remain explicit
diagnostics.

`ContextProbe` validates portable IR context reads through EVM opcodes:
`userId` lowers to `caller()`, `contractId` lowers to `address()`,
`checkpointId` lowers to `number()`, `timestamp` lowers to `timestamp()`,
`chainId` lowers to `chainid()`, `gasPrice` lowers to `gasprice()`, `gasLeft`
lowers to `gas()`, `baseFee` lowers to `basefee()`, `prevRandao`
lowers to `prevrandao()`, `origin` lowers to `origin()`, `coinbase` lowers to
`coinbase()`, and `blockHash(n)` lowers to `blockhash(<n>)`. It also validates
`nativeValue` lowering to `callvalue()` through the `native_value()` selector.
The smoke checks golden Yul reproducibility, `solc --strict-assembly` bytecode
generation, metadata capabilities (`caller.sender`, `account.explicit`,
`env.block`, `value.native`), Foundry runtime context values through
`vm.prank`/`vm.startPrank`/`vm.roll`/`vm.warp`/`vm.chainId`/`vm.txGasPrice`/
`vm.fee`/`vm.prevrandao`/`vm.coinbase`, value-bearing calls through
`probe.call{value: ...}`, and unknown-selector revert behavior.

`EvmHashProbe` validates portable IR `Hash` values as a one-word EVM ABI and
storage representation. Four-limb `hash4` literals and dynamic `hashValue`
expressions pack into a single 256-bit word, while `hash` and
`hash_two_to_one` lower to Yul helpers that call `keccak256` over one or two
32-byte memory words. The smoke checks golden Yul reproducibility,
`solc --strict-assembly` bytecode generation, metadata capabilities
(`crypto.hash`, `storage.scalar`), ABI `bytes32` parameters/returns, scalar
Hash storage through `sload`/`sstore`, Foundry `vm.load` raw slots, and
unknown-selector revert behavior.

`EventProbe` validates portable IR event emission through Yul logs. EVM IR v0
derives topic0 from a Solidity-style event signature generated from the event
name and field types, for example `ValueEvent(uint64)`,
`TypedScalarEvent(bool,uint32,bytes32)`,
`PairEvent((uint64,uint64))`, `StoragePairEvent((uint64,uint64))`,
`StorageArrayEvent(uint64[2])`, `ArrayEvent(uint64[2])`,
`PairArrayEvent((uint64,uint64)[2])`,
`MatrixEvent(uint64[2][2])`,
`PairMatrixEvent((uint64,uint64)[2][2])`,
`StoragePairArrayEvent((uint64,uint64)[2])`,
`IndexedPair((uint64,uint64),uint64)`,
`IndexedStoragePair((uint64,uint64),uint64)`,
`IndexedTypedScalar(bool,uint32,bytes32,uint64)`,
`IndexedTwoValues(uint64,uint64,uint64)`,
`IndexedThreeValues(uint64,uint64,uint64,uint64)`,
`IndexedStorageArray(uint64[2],uint64)`,
`IndexedArray(uint64[2],uint64)`,
`IndexedStoragePairArray((uint64,uint64)[2],uint64)`, or
`IndexedPairArray((uint64,uint64)[2],uint64)`,
`IndexedMatrix(uint64[2][2],uint64)`, or
`IndexedPairMatrix((uint64,uint64)[2][2],uint64)`. Plain `eventEmit` lowers to
`log1`, while `eventEmitIndexed` snapshots up to three indexed fields into
topics, producing `log2`, `log3`, or `log4`. Scalar indexed fields become direct
topics for U64, Bool, U32, and Hash values. Flat structs, including
storage-backed scalar struct reads, scalar fixed arrays, and fixed arrays of flat
structs, and nested fixed arrays with scalar or flat-struct leaves flatten into
ABI-style 32-byte words and use `keccak256` of those words as the indexed
topic; storage-backed fixed arrays do the same from storage array reads and
storage array struct field reads. Non-indexed data fields can be scalar words,
flat structs from local values or storage reads, scalar fixed arrays, fixed
arrays of flat structs, or nested fixed arrays whose leaves are scalar words or
flat structs, and aggregate values flatten in ABI order before the Yul log call.
Portable IR EVM artifacts and deploy manifests also record `abi.events` entries
with the Solidity-style signature, `topic0`, indexed/data fields, flattened ABI
word types, and topic/data encoding. The
smoke checks golden Yul reproducibility, `solc --strict-assembly` bytecode
generation, metadata capability `events.emit`, `abi.events` signatures and
`topic0` values using `cast keccak`, Foundry recorded logs (`emitter`,
signature topic, scalar indexed
topics across U64/Bool/U32/Hash values and one, two, or three indexed fields,
indexed aggregate topic hash, Bool/U32/Hash scalar event data with dispatcher
range guards, flat struct data from local values and storage reads, scalar
fixed-array data from local values and storage array
reads, fixed-array-of-struct data from local literals and storage array struct
field reads, nested fixed-array data from scalar and flat-struct leaves, and
decoded scalar data), ABI selector dispatch, and unknown-selector revert
behavior. Aggregate event fields with unsupported or non-flat leaves and richer
event declarations remain explicit unsupported surfaces for the portable IR.

`EvmCrosscallProbe` validates portable IR `crosscallInvoke`,
`crosscallInvokeTyped`, `crosscallInvokeValueTyped`,
`crosscallInvokeStaticTyped`, `crosscallInvokeDelegateTyped`,
`crosscallCreate`, and `crosscallCreate2`. Call-like expressions lower to
arity-, return-type-, value-mode-, static-mode-, and delegate-mode-specific Yul
helpers. EVM IR v0 interprets the target expression as an address word, the
method expression as a low-32-bit selector, scalar arguments as 32-byte ABI
words, flat struct, scalar fixed-array, fixed-array-of-flat-struct, and nested
fixed-array arguments whose leaves are scalar words or flat structs as
ABI-flattened word sequences, and
value-bearing call value as a U64 word. The helper packs calldata,
executes either `call(gas(), target, 0, ...)`,
`call(gas(), target, call_value, ...)`, `staticcall(gas(), target, ...)`, or
`delegatecall(gas(), target, ...)`, reverts on call failure or returns shorter
than the expected return-data size, and decodes one or more 32-byte return
words. Typed helpers cover `Bool`, `U32`, `U64`, `Hash`, direct entrypoint
returns of flat structs, scalar fixed arrays, fixed arrays of flat structs, and
nested fixed arrays whose leaves are scalar words or flat structs
across normal, value-bearing, static, and delegate modes; Bool and U32 helpers reject out-of-range return
words before returning to the dispatcher. The smoke checks golden Yul reproducibility,
`solc --strict-assembly` bytecode generation, metadata capability
`crosscall.invoke`, metadata entrypoints, Foundry U64 calls with zero/one/two
arguments, typed Bool/U32/Hash calls, flat struct, scalar fixed-array,
fixed-array-of-flat-struct, and nested fixed-array aggregate typed
returns in normal/value/static/delegate modes, flat struct, scalar fixed-array,
fixed-array-of-flat-struct, and nested fixed-array typed-call arguments whose
leaves are scalar words or flat structs,
aggregate Bool/U32 malformed-return
guards in normal/value/static/delegate modes, native-value forwarding to a
payable callee, value-bearing flat struct and nested flat-struct arguments, U64 read-only staticcall
return behavior, Bool/U32/Hash static typed returns, static flat struct
arguments, invalid static Bool/U32 return guards, static-context state-write
failure, caller-storage delegatecall read/write behavior, Bool/U32/Hash delegate
typed returns, delegate flat struct and nested flat-struct arguments, invalid delegate Bool/U32 return
guards, fixed init-code `create` deployment, deterministic `create2` address
validation, calls into the deployed runtime, callee reverts, short-return
reverts, invalid typed return reverts, and unknown-selector reverts.

`EvmExpressionProbe` validates scalar expression lowering directly rather than
through storage or assignment side effects. It covers `U64` and `U32`
arithmetic (`add`, `sub`, `mul` via checked helpers that revert on overflow or
underflow, plus `div`, `mod` via raw builtins), `U64` exponentiation through
Yul `exp`, `U64`/`U32` bitwise operators and shifts with EVM operand ordering,
predicate expressions (`eq`, `ne`, `lt`, `le`, `gt`, `ge`), boolean
`and`/`or`/`not`, scalar literals, immutable local reads, supported
`U32`/`U64`/`Bool` casts, one-word scalar returns, dispatcher guards for
`U32`/`Bool` calldata, and assertion guards. The smoke checks golden Yul
reproducibility, `solc --strict-assembly` bytecode generation, metadata
capability `assertions.check`, Foundry runtime results, malformed calldata
reverts, and unknown-selector reverts.

`EvmMapProbe` validates portable IR `Map<U64, U64, N>` storage through the same
Solidity-style value slot layout used by the SDK: `keccak256(key || slot)` after
writing `key` and `slot` as two 32-byte memory words. `storage.map.contains`
uses a ProofForge-managed presence mapping rooted at
`keccak256(slot || PROOF_FORGE_MAP_PRESENCE)` so inserted or set keys remain
present even when their stored value is zero. The smoke checks golden Yul
reproducibility, `solc --strict-assembly` bytecode generation, metadata
capabilities (`storage.scalar`, `storage.map`, `assertions.check`), ABI
get/set/insert/contains behavior, single-segment and nested consecutive
`mapKey` storage path reads, writes, and compound assignment, raw Foundry
`vm.load` value and presence storage slots, and unknown-selector revert
behavior. Nested map value slots fold the same Solidity-style mapping helper,
for example `keccak256(inner || keccak256(outer || slot))`; nested presence
slots use the parent value slot as the presence root before hashing the final
key. Mixed map/aggregate storage paths remain explicit diagnostics.

`EvmTypedMapProbe` extends the same mapping slot layout to word key/value maps.
It validates `U32`, `Bool`, and `Hash` map keys and values using the same
`keccak256(key || slot)` helper, with one declared mapping slot per state and a
domain-separated presence mapping for `contains`. The smoke checks golden Yul
reproducibility, `solc --strict-assembly` bytecode generation, metadata
capabilities (`storage.scalar`, `storage.map`, `assertions.check`), ABI
dispatcher guards for `U32` and `Bool` map parameters, statement and expression
map writes, previous-value returns, `Hash`/`bytes32` map values,
single-segment `mapKey` path reads/writes, numeric `U32` map-path compound
assignment, nested `U32` mapKey path read/write/compound assignment with
dispatcher range guards, typed `contains`, raw Foundry `vm.load` value and
presence storage slots, and unknown-selector revert behavior. Aggregate or
non-word key/value shapes and mixed map/aggregate storage paths remain explicit
diagnostics.

`EvmStorageArrayProbe` validates portable IR `U64` fixed storage arrays through
contiguous EVM storage slots. Array state occupies `length` slots, so state
declared after an array starts after the full array span. Direct
`storageArrayRead`/`storageArrayWrite` effects and single-segment `index`
storage paths lower through `__proof_forge_array_slot(base, length, index)`,
which reverts when the index is out of bounds before calling `sload` or
`sstore`. It also validates `return_values()`, which writes storage elements,
reads them back, and encodes those reads as a fixed-array ABI return. The smoke
checks golden Yul reproducibility, `solc --strict-assembly` bytecode
generation, metadata capabilities (`storage.scalar`, `storage.array`,
`data.fixed_array`), ABI read/write/return selectors, generic path read/write
and compound assignment, Foundry raw slot layout, out-of-bounds reverts, and
unknown-selector revert behavior.

`EvmTypedStorageProbe` extends the storage-array gate beyond the original `U64`
case. It validates `Bool` scalar storage and `U32`/`Bool`/`Hash` fixed storage
arrays using the same contiguous word-slot layout and
`__proof_forge_array_slot(base, length, index)` helper. The smoke checks golden
Yul reproducibility, `solc --strict-assembly` bytecode generation, metadata
capabilities (`storage.scalar`, `storage.array`, `data.fixed_array`,
`assertions.check`), raw Foundry slot layout for word arrays, ABI `Bool` and
`Hash` returns, `U32` calldata range guards on writes, storage-path reads/writes
over typed arrays, numeric `U32` storage-path compound assignment,
out-of-bounds reverts, and unknown-selector revert behavior.

`EvmStorageStructProbe` validates portable IR flat storage structs. Scalar
storage structs reserve one EVM storage slot per supported field in declaration
order, and fixed storage arrays of structs reserve `length * field_count` slots.
Direct `storageStructFieldRead`/`storageStructFieldWrite`,
`storageArrayStructFieldRead`/`storageArrayStructFieldWrite`, scalar `field`
storage paths, `index`+`field` storage paths, and whole scalar storage struct
reads/writes lower to deterministic `sload`/`sstore` expressions. Whole writes
snapshot RHS fields before writing target slots, so self-referential storage
struct updates observe the original RHS values. Struct arrays use
`__proof_forge_struct_array_slot(base, length, field_count, field_offset,
index)`, which reverts on out-of-bounds indexes before deriving
`base + index * field_count + field_offset`. It also validates
`return_points()`, which reads fields from a fixed storage array of flat structs
and encodes those reads as a fixed-array-of-struct ABI return. The smoke checks
golden Yul reproducibility, `solc --strict-assembly` bytecode generation,
metadata capabilities (`storage.scalar`, `storage.array`, `data.fixed_array`,
`data.struct`), scalar and array struct field reads/writes, field path compound
assignment, whole scalar storage struct read/write, ABI struct return encoding
from storage, storage-backed fixed-array-of-struct returns,
`Bool`/`U32`/`Hash` fields, Foundry raw slot layout, out-of-bounds reverts, and
unknown-selector revert behavior. Nested struct fields and non-flat struct
storage remain explicit diagnostics.

`EvmArrayValueProbe` validates portable IR local fixed-array values. Immutable
and mutable local fixed-array bindings expand into one Yul local per element.
`arrayGet` over local arrays or array literals supports static `U32`/`U64`
literal indexes and dynamic word indexes. Dynamic reads lower through
length-specific Yul helpers with default revert cases; dynamic mutable local
element assignment and numeric compound assignment lower to `switch` blocks over
the expanded locals. Whole local fixed-array assignment from another local
fixed-array or from a fixed-array literal snapshots RHS words into temporary
locals before assigning elements back to the target. The smoke covers `U64`,
`U32`, `Bool`, and `Hash` element arrays, static and dynamic mutable element
writes, whole-local assignment, static and dynamic nested scalar local
fixed-array reads, static and dynamic nested scalar leaf assignment/compound
assignment, nested whole-local assignment with RHS snapshotting, golden Yul
reproducibility,
`solc --strict-assembly`, artifact metadata, Foundry runtime calls, dynamic
out-of-bounds reverts, and unknown-selector revert behavior. Nested local
fixed arrays with flat struct leaves are covered by `EvmStructArrayValueProbe`;
other unsupported aggregate or non-flat leaves remain explicit diagnostics.

`EvmStructArrayValueProbe` validates portable IR local fixed arrays and nested
local fixed arrays of flat struct values. Immutable and mutable local bindings
expand into one Yul local per element field, for example `people[1].score` or
`grid[1][0].age` becomes a deterministic internal local.
`field(arrayGet(localArray, index), name)` and nested
`field(arrayGet(arrayGet(localArray, row), col), name)` support static literal
indexes and dynamic word indexes; dynamic reads use length-specific local-array
getter helpers, and dynamic mutable field assignment/compound assignment lowers
to `switch` blocks with default revert cases. The smoke covers `U64`, `U32`,
`Bool`, and `Hash` fields, static and dynamic field reads, static and dynamic
mutable field writes, numeric field compound assignment, nested struct-array
field reads/writes, golden Yul reproducibility, `solc --strict-assembly`,
artifact metadata capabilities (`data.fixed_array`, `data.struct`,
`assertions.check`), Foundry runtime calls, dynamic out-of-bounds reverts, and
unknown-selector revert behavior. Whole local assignment from another local
struct array and from self-referential struct-array literals snapshots RHS
fields before writing target fields, including nested fixed arrays. Nested
struct fields and non-flat struct leaves remain explicit diagnostics.

`EvmStructValueProbe` validates portable IR flat local struct values. Immutable
and mutable struct local bindings expand into one internal Yul local per
supported field, and `field` access over a local struct or direct struct literal
lowers to the corresponding scalar/hash word expression. Static local field
assignment and numeric compound assignment lower to assignments to those
expanded locals. Whole local struct assignment from another local struct or from
a struct literal snapshots RHS field words into temporary locals before assigning
fields back to the target. The smoke covers `U64`, `U32`, `Bool`, and `Hash`
fields, mutable field writes, whole-local assignment, golden Yul
reproducibility, `solc --strict-assembly`, artifact metadata capability
`data.struct`, Foundry runtime calls, and unknown-selector revert behavior.
Nested struct fields remain explicit diagnostics.

`EvmDynamicAbiProbe` validates portable IR dynamic ABI types `address`, `bytes`,
and `string` for entrypoint parameters and returns. `address` is a static
single-word type (like `Hash`) that participates in ABI parameters with standard
Solidity `address` encoding. `bytes` and `string` are dynamic types requiring
head-tail ABI encoding: the dispatcher decodes calldata by reading the offset
from the head, loading the length from the tail, allocating memory via the free
memory pointer, and copying data from calldata to memory. Dynamic returns encode
as head-tail: the head stores the offset (32), the tail stores the length followed
by data words. The probe has three entrypoints: `echo_bytes(bytes)` returns the
input bytes unchanged, `echo_string(string)` returns the input string unchanged,
and `transfer(address,uint256)` returns `true` to validate address ABI round-trip.
The smoke checks golden Yul reproducibility, `solc --strict-assembly` bytecode
generation, metadata capability `data.dynamic_bytes`, structured `abi.entrypoints`
with `abi-dynamic-bytes` encoding for bytes/string params and returns, Foundry
round-trip tests for empty, short, multi-word, and padded data, malformed
calldata reverts, and unknown-selector reverts.

## Metadata

EVM bytecode modes emit a ProofForge artifact metadata JSON file and a
ProofForge EVM deploy manifest. The default metadata path is
`proof-forge-artifact.json` next to the bytecode output; smoke scripts pass
fixture-specific `--artifact-output` paths to avoid parallel-run collisions.
The deploy manifest path is derived from the metadata path, for example
`Counter.proof-forge-deploy.json`.

The current EVM metadata schema records:

- `schemaVersion: 1`
- `target: evm`, `targetFamily: evm`, and `artifactKind: evm-bytecode`
- source kind (`contract-sdk` or `portable-ir`), source module, and `irVersion`
  (`portable-ir-v0` for portable IR fixtures)
- portable IR capability ids when available
- constructor ABI schema, structured selector-facing portable IR entrypoint ABI
  metadata in `abi.entrypoints` with Solidity-style signatures, selector
  values, IR type names, ABI parameter/return types, flattened calldata
  word types/counts, and flattened return-data word types/counts, plus event
  ABI metadata in `abi.events`
- `solc` path/version
- Yul, runtime bytecode, deployable initcode, source when available, and
  deploy-manifest artifact paths, byte sizes, and SHA-256 hashes
- validation flags for `solc --strict-assembly`, bytecode generation, initcode
  generation, and deploy-manifest generation

The EVM deploy manifest records:

- `kind: proof-forge-evm-deploy-manifest`
- source kind/module, `irVersion`, capabilities, constructor ABI schema, and
  ABI entrypoints/events, including calldata/return word layouts when available
- optional `chainProfile` metadata copied from the EVM target registry when
  `--evm-chain-profile` is provided, including profile id, chain id, RPC URLs,
  native gas symbol, explorer, verifier, and notes
- Yul/source inputs plus runtime bytecode and initcode hash/size
- `creation.mode: init-code`, optional static-word constructor ABI schema from
  `--evm-constructor-param`, optional ABI-encoded constructor args from typed
  `--evm-constructor-arg` values or raw `--evm-constructor-args-hex`, an
  artifact-linked initcode file, and the referenced runtime bytecode
- `deployment.profileId`, `deployment.chainId`, `deployment.rpcUrls`,
  `deployment.blockExplorerUrl`, and verifier fields when a chain profile is
  selected
- `deployment.broadcast: not-generated`, because transaction signing,
  broadcast JSON, deployed address recording, and explorer verification are not
  generated by `proof-forge build`. Use `proof-forge deploy --target evm` to
  broadcast on `anvil-local` or emit a documented testnet deploy plan.

`scripts/evm/validate-artifact-metadata.py` validates these metadata files and
their referenced deploy manifests in the EVM IR smoke scripts and in
`scripts/evm/build-examples.sh`. The validators parse the initcode header and
check that it copies and returns the exact runtime bytecode artifact, and that
any constructor-argument tail matches the deploy manifest. When constructor ABI
schema metadata is present, they also verify each static-word parameter and
check that the ABI-encoded constructor blob has the expected 32-byte word
length. They also accept and can assert whether constructor args came from raw
hex or typed constructor values. When a chain profile is selected, they also
verify that `chainProfile` and `deployment` agree on profile id, chain id, RPC
URLs, explorer, and verifier metadata. ABI validation also checks 4-byte
selector shape, duplicate selectors, entrypoint Solidity-style signatures,
`cast sig` selector matches, entrypoint parameter/return ABI types, flattened
calldata/return word counts, generated Yul function names, event signatures,
`topic0` hashes, and event indexed/data field encodings; contract-source
example and Anvil gates require generated ABI signatures in artifact metadata.
`scripts/evm/validate-deploy-manifest.py` can validate a deploy manifest
directly.

`scripts/evm/anvil-deploy-smoke.sh` consumes the generated Counter deploy
manifest and `.init.bin`, regenerates Counter with a deterministic non-empty
typed `initial=123` constructor argument plus a static `initial:uint256`
constructor schema by default, and runs `proof-forge deploy --target evm
--start-anvil` to broadcast initcode through `cast send --create`, validate the
receipt and deployed runtime code, run the Counter lifecycle through JSON-RPC
calls, and write
`build/anvil-deploy-smoke/Counter.proof-forge-deploy-run.json`.
`scripts/evm/deploy-plan-smoke.sh` records
`build/evm-deploy-plan-smoke/Counter.proof-forge-deploy-plan.json` for the
documented `robinhood-chain-testnet` profile without live broadcast.
`scripts/evm/validate-deploy-run.py` validates that deploy-run artifact. The
original deploy manifest remains a reproducible plan with
`deployment.broadcast: not-generated`; the deploy-run artifact records one
observed local Anvil deployment execution, including the constructor ABI schema
and constructor args that were used. It also links the `cast send` receipt and
the `eth_getTransactionByHash` creation transaction JSON, and validates that
the chain profile, deployment chain id, actual Anvil chain id, transaction hash,
sender, null creation `to`, block metadata, and input initcode match the
generated deploy artifacts. By default it uses the `anvil-local` chain profile
when the Anvil chain id is `31337`; set `EVM_ANVIL_CHAIN_PROFILE=` to disable
that profile link or provide a different profile explicitly.

Target-first `contract_source` builds derive method dispatch and ABI metadata
from `ContractSpec`; no `.evm-methods` sidecar is required for new code.
