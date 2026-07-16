# RFC 0001: Lean-first multi-chain contract platform

Status: Accepted

Date: 2026-06-30

## Summary

ProofForge should evolve from an EVM backend experiment into a Lean-first
multi-chain contract platform. Developers write contract business logic,
state-machine rules, and proofs in Lean. At build time they choose a target
chain family, and ProofForge produces target-specific artifacts, tests, and
deployment packages.

The first architecture decision is to use a portable core plus capabilities
model:

- Portable core: pure business logic, arithmetic, state-machine transitions,
  invariants, and proofs that should stay chain-independent.
- Capabilities: explicit chain-facing operations such as storage, caller
  identity, value transfer, events, cross-contract calls, account access,
  object/resource access, and chain environment reads.
- Target adapters: ABI, artifact, test runner, deployment, and host-runtime
  glue for a specific chain family.

This model avoids pretending that EVM, Solana, Wasm chains, Move chains,
ZK/circuit targets, and Bitcoin-like systems have identical semantics. The goal
is not a weakest-common denominator language. The goal is one verified business
core with clear, auditable target boundaries.

## Current Baseline

The repository currently has an EVM baseline:

```text
Lean contract
  -> Lean frontend / LCNF
  -> EmitYul
  -> Yul
  -> solc --strict-assembly
  -> EVM runtime bytecode
  -> Foundry smoke tests
```

Implemented today:

- `ProofForge.Evm`: EVM SDK primitives and typed helpers.
- `ProofForge.Compiler.LCNF.EmitYul`: LCNF to Yul lowering.
- `proof-forge --evm-bytecode`: EVM bytecode CLI mode.
- `.evm-methods`: method dispatch metadata for ABI selectors.
- Foundry smoke tests using generated runtime bytecode.

Not implemented today:

- A target-independent contract IR.
- Solana/sBPF, Wasm-family, Move-family, or ZK/circuit backends.
- Cloud build, deployment, artifact registry, or hosted testnet flows.

## External Landscape

The multi-chain contract space has related projects, but no dominant
Lean-first verified multi-chain deployment platform.

| Area | Reference | Relevance |
|---|---|---|
| Multi-chain language | Reach, https://www.reach.sh/ | Closest high-level precedent for writing an application once and deploying to multiple chains. |
| Solidity multi-target compiler | Solang, https://solang.readthedocs.io/ | Shows that one source language can lower to non-EVM blockchain targets, but starts from Solidity rather than Lean/proofs. |
| EVM | Foundry and solc toolchains | Mature local testing and bytecode pipeline; current ProofForge baseline. |
| Solana | Programs docs, https://solana.com/docs/core/programs | High-value target with an account/instruction model very different from EVM. |
| Wasm chains | NEAR, https://docs.near.org/smart-contracts/what-is | Wasm contract model with chain-specific host ABI and account model. |
| Wasm chains | CosmWasm, https://cosmwasm.cosmos.network/ | Wasm contracts across Cosmos chains with a distinct message/storage model. |
| Wasm chains | ink!, https://use.ink/docs/v5/why-webassembly-for-smart-contracts/ | Polkadot/Substrate smart contracts via Wasm. |
| Move chains | Sui Move, https://docs.sui.io/concepts/sui-move-concepts | Object/resource semantics, strong type discipline, and a Move VM target family. |
| Move chains | Aptos smart contracts, https://aptos.dev/en/build/smart-contracts | Move module/resource model with a separate account and deployment model. |
| ZK/circuit targets | Psy compiler, https://github.com/PsyProtocol/psy-compiler | ZK-oriented contract compiler that emits DPN circuit function definitions rather than EVM-style bytecode. |
| Bitcoin ecosystem | Stacks Clarity, https://docs.stacks.co/learn/clarity | Bitcoin-adjacent smart contract language with decidability goals. |
| Bitcoin ecosystem | BitVM, https://bitvm.org/ | Research direction for Bitcoin computation verification, not a direct first backend target. |

## Target Architecture

```text
                 +---------------------------+
                 | Lean contract + proofs    |
                 +-------------+-------------+
                               |
                               v
                 +---------------------------+
                 | Lean frontend / LCNF      |
                 +-------------+-------------+
                               |
                               v
                 +---------------------------+
                 | Portable Contract IR      |
              +------+------+------+------+------+
                     |      |      |      |      |
                     v      v      v      v      v
                  +-----+ +-------------+ +-------------+ +-------------+ +--------+
                  | EVM | | Solana/sBPF | | Wasm family | | Move family | | ZK/DPN |
                  +-----+ +-------------+ +-------------+ +-------------+ +--------+
                     |          |              |               |             |
                     v          v              v               v             v
                 Yul/solc  Solana program  NEAR/CosmWasm  Sui/Aptos     Psy/DPN
                                           Polkadot/ink!
```

The portable IR must sit above target ABI details and below Lean source syntax.
It should represent:

- Exported contract entrypoints and method metadata.
- Portable values, structs, enums, arrays, maps, and errors.
- State transition functions and declared invariants.
- Capability calls as typed effects rather than raw target opcodes.
- Proof-carrying facts that can be checked before backend lowering.

Target backends lower this IR to each chain family:

- EVM backend: Yul object, ABI selector dispatch, `solc` bytecode, Foundry tests.
- Solana backend: sBPF package, instruction dispatch, account metadata, PDA
  helpers, CPI boundaries, Solana local validator tests.
- Wasm backend family: shared Wasm lowering plus chain-specific host ABI
  adapters for NEAR, CosmWasm, and Polkadot/ink-style contracts.
- Move backend family: Move module/package adapters for Sui and Aptos, with a
  research phase for direct Move bytecode or generated Move source.
- ZK circuit backend family: target source generation plus target-native circuit
  artifact generation, starting with Psy/DPN.

## Capability Model

Portable code must not call raw EVM, Solana, Wasm, Move, or ZK VM host APIs
directly. It calls ProofForge capabilities. Each target declares which
capabilities it supports and how they lower.

Initial capability groups:

| Capability | Portable meaning | Target notes |
|---|---|---|
| Storage | Read/write contract state | EVM slots, Solana accounts, Wasm storage, Move resources/objects differ significantly. |
| Caller | Identify transaction signer/caller | EVM `caller`, Solana signer account, Wasm sender, Move transaction sender. |
| Value | Native token movement or received value | Not all chains expose EVM-style `msg.value`; adapters must make this explicit. |
| Events | Emit indexed or structured output | EVM logs, Solana logs/events, Wasm events, Move events. |
| Cross-call | Call another contract/program/module | EVM calls, Solana CPI, Wasm messages/promises, Move module calls. |
| Time/env | Block height, timestamp, chain id | Availability and finality semantics vary by target. |
| Crypto | Hashing, signature recovery, precompiles | Some targets expose host functions, others require library lowering. |
| Account/object/resource | Chain-native state containers | Especially important for Solana accounts and Move objects/resources. |
| ZK/circuit | Circuit artifact generation and proof flow | Especially important for Psy/DPN and future ZK VM targets. |

The compiler should reject a target build when a contract uses unsupported
capabilities. Rejection is preferable to silently changing semantics.

## CLI And Product Surface

The future local CLI should expose target selection as the stable public
interface:

```sh
proof-forge build --target evm --out build/evm
proof-forge build --target solana-sbpf-asm --out build/solana
proof-forge build --target wasm-near --out build/near
proof-forge build --target wasm-cosmwasm --out build/cosmwasm
proof-forge build --target move-sui --out build/sui
proof-forge build --target move-aptos --out build/aptos
proof-forge build --target psy-dpn --out build/psy-dpn
```

Polkadot/ink-style contracts (`wasm-polkadot`) remain research-only until a
target profile and spike are scheduled. See [decisions.md](../decisions.md).
Psy/DPN (`psy-dpn`) is now Experimental for a restricted portable IR subset:
generated `.psy` source plus Dargo, not a public Yul-like IR, remains the
integration route.

The current `proof-forge --evm-bytecode` mode remains the EVM baseline until
the target-oriented `build` command exists.

Future cloud platform surface:

- Import from GitHub.
- Select target matrix.
- Run deterministic builds in isolated workers.
- Run target-native local/testnet smoke tests.
- Store artifacts, ABIs, proofs, deployment metadata, and verification reports.
- Deploy to configured testnets/mainnets after explicit signing or wallet
  approval.
- Show a Vercel/Cloudflare-like project dashboard with builds, environments,
  deployments, logs, and chain-specific health checks.

## Roadmap

### Phase 0: EVM baseline

Status: implemented in this repository.

- Keep EVM examples compiling through `proof-forge --evm-bytecode`.
- Keep Foundry smoke tests as the mature EVM test harness.
- Treat current EVM SDK primitives as the first concrete capability source.

### Phase 1: Target model and portable IR

- Introduce a target registry and target identifiers.
- Split EVM-specific SDK calls from portable contract capabilities.
- Define the portable contract IR ([spec](../portable-ir.md)) and artifact
  metadata.
- Add compile-time errors for unsupported target capabilities ([registry](../capability-registry.md)).
- Define the Counter [shared scenario](../shared-scenario.md).

### Phase 2: Parallel target spikes (CosmWasm + Solana)

Requires Phase 1 complete. CosmWasm and Solana spikes may proceed in parallel.

**CosmWasm (`wasm-cosmwasm`):**

- Wasm-host adapter with region ABI and JSON messages.
- Counter smoke through `cosmwasm-check`.

**Solana (`solana-sbpf-linker`):**

- Map portable entrypoints to instruction dispatch with explicit accounts.
- Produce a minimal sBPF artifact via stock Zig + `sbpf-linker`.
- Run under Mollusk or Solana local validator.

Both spikes use the same portable IR Counter module. See
[decisions.md](../decisions.md).

### Phase 3: Move family

- Generate Move source from restricted portable IR (Aptos POC first, then Sui).
- Model Sui objects and Aptos resources as target capabilities.
- Validate Counter (or successor scenario) on EVM and Aptos.

### Phase 3.5: ZK circuit target research

- Generate Psy-compatible `.psy` source from restricted portable IR.
- Compile through Dargo to DPN circuit JSON.
- Decide whether in-memory Psy execution is sufficient before local node/prover
  deployment smoke.

### Phase 4: Cross-target scenario hardening

- Shared scenario tests across EVM and at least two non-EVM targets.
- Golden IR and artifact snapshots.
- Capability matrix coverage for Counter v1 (events, access control optional).

### Phase 5: Cloud platform

- Add hosted target-matrix builds.
- Add artifact registry and deploy history.
- Add testnet deployment flows.
- Add verification reports that show proof status, target capabilities used,
  and chain-specific warnings.

## Non-goals

- Do not promise that every contract compiles to every chain.
- Do not hide chain economics, finality, account models, or resource models.
- Do not translate arbitrary EVM bytecode to every target.
- Do not target Bitcoin L1 execution as an early backend.
- Do not replace mature target-native tools such as Foundry, Solana local
  validator tooling, NEAR tooling, CosmWasm tooling, or Move CLIs. Integrate
  with them first.

## Testing Strategy

Every target family should have four test layers:

- Lean checks: proofs, pure logic, and state-machine invariants.
- Golden artifacts: stable IR and backend output snapshots for small examples.
- Target-native smoke tests: Foundry for EVM, Solana local validator for sBPF,
  chain-specific Wasm runners, Move local/testnet tooling, and Dargo/Psy
  tooling for `psy-dpn`.
- Cross-target scenario tests: the same portable contract scenario should
  produce equivalent high-level outcomes across supported targets.

CI should start with EVM only, then expand into a target matrix as new backends
land. A target is not considered supported until it has at least one local smoke
test and one shared portable scenario test.

## Open Questions

- How much of Lean's LCNF should be preserved in the portable contract IR?
- Should target adapters be written in Lean only, or can some adapters use
  Zig/Rust/Go when chain tooling makes that more reliable?
- For Move, is generated Move source acceptable for the first backend, or is
  direct Move bytecode required for the platform story?
- For Wasm, should the compiler emit one generic Wasm core plus adapters, or
  separate Wasm per chain from the beginning?
- How should cloud deployment handle private keys, multisig workflows, and
  user-controlled signing?
