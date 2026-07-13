# IR and Target Extension Boundary

Status: **Accepted design (2026-07-14)**

This design closes the gap between the declared target-neutral architecture and
the target-specific operations that accumulated in the legacy IR and Canonical
Core. It extends D-028, D-050, and D-052.

## Decision

The portable authoring IR and Canonical Core describe semantic operations, not
blockchain APIs or backend encodings. Selecting `--target` resolves those
semantics through a capability plan and a target-owned materializer.

```text
portable source / intent
  -> target-neutral legacy compatibility IR
  -> Canonical Core semantic operations
  -> capability resolution
  -> target extension registry + target plan
  -> target artifact
```

A chain-native SDK may expose names such as `Near.promiseTransfer` or
`Evm.eip712PermitDigest`, but those names must disappear before the checked
Canonical Core boundary. A genuinely target-only operation uses a typed,
versioned extension call whose signature and handler are registered by the
target. It does not add another constructor to the shared `Expr`, `Effect`, or
Core instruction inductive.

## Boundary Rules

### Shared authoring and IR layers

The following paths must contain only target-neutral semantic vocabulary:

- `ProofForge/IR/Contract.lean` public `ValueType`, `ContextField`, `Expr`,
  `Effect`, `Statement`, `Entrypoint`, and `Module` shapes;
- `ProofForge/IR/Core/{Type,Storage,Syntax,Validate}.lean`;
- `ProofForge/IR/Canonical.lean` interface and materialization contracts;
- portable `ProofForge.Contract.Surface` and `ProofForge.Contract.Source` APIs.

These layers may refer to open capability or HostOp identifiers, but must not
own target-specific signatures, handlers, ABI layouts, string pools, error
encodings, promise modes, CPI account layouts, or storage bindings.

### Target extension layer

Target-native vocabulary is allowed in:

- target SDK namespaces such as `ProofForge.Contract.Source.Near` and
  `ProofForge.Contract.Source.Solana`;
- `ProofForge/Target/*` registries and target profiles;
- `ProofForge/Backend/<Target>/*` plans, handlers, ABI layouts, and emitters;
- target fixtures, differential references, and runtime runners.

Every target extension must provide:

1. a stable typed operation identifier;
2. an exact signature and required semantic capabilities;
3. a target-owned handler;
4. fail-closed diagnostics on targets without a handler;
5. artifact metadata recording the extension use.

## Current Violations

The inventory below is based on the checked-in code on 2026-07-14. It is debt,
not an accepted exception to the boundary.

### P0: target constructors in shared expression/control syntax

| Current shared node | Problem | Destination |
|---|---|---|
| `nearCrosscallInvokePool`, `nearPromiseThen` | NEAR promise scheduling is encoded in `Expr` and in `CoreCrosscallMode` | target-neutral async call/continuation intent plus NEAR plan handler |
| `nearPromiseResultsCount`, `nearPromiseResultStatus`, `nearPromiseResultU64`, `nearPromiseResultU128` | callback API and payload codec are NEAR host details | typed async-result extension family |
| `nearAttachedDeposit` | duplicates portable call-value context with a NEAR-specific width workaround | target-neutral `ContextField.callValue` with an explicit portable type |
| `nearStorageUsage` | exposes one host API as an `Expr` constructor | typed resource-usage HostOp registered by NEAR |
| `nearPromiseTransfer` | exposes a NEAR batch action as an `Expr` constructor | target-neutral native transfer/async action or typed target extension |
| `ecrecover` | hardcodes the EVM API rather than the cryptographic semantic contract | algorithm-identified signature recovery operation and capability |
| `eip712PermitDigest` | embeds one Ethereum application standard in shared IR | EVM SDK desugaring or typed EVM extension |
| `crosscallAbiPacked` | stores EVM selector/memory offsets and ABI words in shared IR | EVM call ABI plan derived after target selection |
| `crosscallCreate`, `crosscallCreate2`, static/delegate variants | target call modes are mixed with portable invocation | portable call/deploy intent where semantics are common; otherwise target extension |
| `checkErc721Received`, `checkErc1155Received`, `checkErc1155BatchReceived` | ERC protocol hooks are shared `Effect` constructors | EVM stdlib desugaring to call/assert or typed EVM extension |

### P1: target fields in shared interface/materialization records

| Current field | Problem | Destination |
|---|---|---|
| `ContextField.prepaidGas`, `usedGas` | NEAR gas API names in the shared environment enum | neutral budget fields or NEAR HostOp |
| `baseFee`, `prevRandao`, `origin`, `coinbase`, `blockHash` | EVM execution-environment vocabulary in the shared enum | target environment extension IDs |
| `ErrorRef.solidity*` and canonical `ErrorEncoding.solidity*` | Solidity ABI payload layout crosses the canonical semantic boundary | EVM error ABI plan |
| `EntrypointKind.fallback`, `receive` | EVM dispatch modes are presented as portable entrypoint kinds | EVM dispatch extension metadata |
| `Module.proxyPattern?` | upgrade materialization is stored on the portable module | intent/materialization policy resolved by the target |
| `Module.nearCrosscallStrings` / `MaterializationContract.nearHostStrings` | NEAR emitter pool leaks into shared records | neutral constant pool or NEAR plan-owned pool |

### P1: target implementation in Canonical Core

- `CoreCrosscallMode.nearPoolInvoke` and `.nearPromiseThen` contradict the
  comment that NEAR promises remain HostOps.
- `IR.Core.HostOp.canonicalHostOpCatalog` centrally registers NEAR signatures.
  Adding a NEAR operation therefore changes the global Core module.
- `IR.Core.Semantics` defines `NearPromiseTrace` and a NEAR-specific host
  interpreter. Reference host semantics must be injected through an extension
  semantics environment instead.
- `Capability` is a closed inductive with entries such as `nearPromise`,
  `storagePda`, and `crosscallCpi`. The closed type forces unrelated modules to
  change when an extension is added. Portable capabilities should use stable
  semantic IDs; target-native extension requirements belong to an open
  registry.

## Repository-Wide Target Audit Scope

The migration is not a NEAR-only cleanup. NEAR exposed the coupling first, but
completion requires the same classification for every implemented target
family:

| Family | Target-owned concerns to remove or keep out of shared IR |
|---|---|
| EVM and Stylus | Solidity ABI/error/dispatch layout, EIP/ERC protocols, CALL mode details, CREATE/CREATE2, EVM environment fields, Stylus host ABI |
| Solana sBPF | PDA seeds/bumps, CPI account metas and signer seeds, sysvars, account ownership/realloc, instruction packing, SPL/Token-2022 protocol layouts |
| NEAR Wasm | promise scheduling/results, attached-deposit width, storage usage/refunds, JSON ABI, NEP protocols, host string/register plans |
| Other Wasm hosts | CosmWasm/Soroban/Cloudflare imports, storage bridges, ABI envelopes, environment and runtime conventions |
| Move Aptos/Sui | signer/resource/object/ability semantics, transaction context, module and entry-function conventions |
| Aleo/Psy | records/mappings/privacy, proof/public-input contracts, target metadata and execution-model constraints |
| Quint | verification projection, replay configuration, and trace adapters rather than executable target semantics |

The audit may conclude that an existing Solana or other-target feature is
already correctly isolated. That result still needs a focused boundary test;
absence of a chain name in the first grep is not sufficient evidence.

## Target-Neutral Semantic Vocabulary

The migration must distinguish common semantics from target-native APIs. It
must not merely remove chain prefixes.

| Semantic area | Shared operation | Target examples |
|---|---|---|
| invocation | invoke, read-only invoke, continuation, result | EVM CALL/STATICCALL, NEAR promise, Solana CPI |
| call context | caller, self, call value, block time/height, budget remaining | `msg.sender`, predecessor, signer, Clock sysvar |
| native value | read attached value, transfer value | ETH value, yoctoNEAR promise transfer, lamports transfer |
| cryptography | hash/signature operation with explicit algorithm and encoding | keccak256, SHA-256, secp256k1 recovery, ed25519 verify |
| resource usage | typed metric ID and unit | NEAR storage bytes, EVM gas, Solana compute units |
| deployment | deploy intent plus determinism/salt policy | EVM CREATE2 or target rejection |

Target selection does not silently change intent. It validates whether the
selected target can implement the requested semantics and rejects otherwise.

## Migration Constraints

- Existing target SDK source APIs remain source-compatible during migration;
  their implementations become wrappers over neutral operations or extension
  calls.
- Legacy fixtures may use a compatibility adapter, but checked Canonical Core
  cannot contain a chain-named constructor or target ABI layout.
- No backend receives a fake implementation merely to keep a multi-target gate
  green. Unsupported semantics fail at capability/handler resolution.
- A migration slice removes its old constructor and all exhaustive match arms;
  retaining both representations indefinitely is not completion.
- Tests must demonstrate both successful target materialization and named
  rejection on an unsupported target.

## Completion Criteria

This boundary repair is complete only when:

1. public shared IR/Core inductives contain no target or protocol names;
2. target-specific HostOp catalogs and handlers are owned by target modules;
3. Canonical Core semantics accepts an injected host semantics environment;
4. target SDK wrappers lower before the checked Core boundary;
5. a repository gate rejects new forbidden constructors/fields;
6. primary-triad product and focused target runtime gates preserve behavior;
7. the old match arms and compatibility fields are removed, not only deprecated;
8. EVM, Solana, every implemented Wasm-host profile, Move, Aleo, Psy, and Quint
   have an explicit ownership audit with focused acceptance evidence.
