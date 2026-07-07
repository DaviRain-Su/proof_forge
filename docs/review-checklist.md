# Multi-chain Design Review Checklist

Use this checklist when reviewing ProofForge design docs and upcoming
implementation. Focus on whether the path is incrementally shippable, not whether
the vision is ambitious.

Settled decisions: [decisions.md](decisions.md).

## Questions to Confirm

### 1. Target classification is clear

Confirm:

- EVM is a direct compiler target.
- NEAR/CosmWasm are Wasm host targets.
- Solana is a binary toolchain target.
- Sui/Aptos are Move source-generation targets.
- Psy/DPN is a ZK circuit source-generation target.

If a design treats all of these as one backend kind, send it back.

### 2. Capabilities are explicit

Every chain-facing operation used by a contract should be listed via capability
ids from [capability-registry.md](capability-registry.md):

- storage
- caller/signer
- value/native token
- events/logs
- cross-contract call / CPI / submessage
- account/object/resource
- crypto / precompile / syscall

The compiler must reject unsupported targets, not silently change semantics.

### 3. Solana is not EVM-shaped

Solana review focus:

- Accounts must be explicit.
- Instruction data must be explicit.
- PDAs must be explicit.
- CPI must be explicit.
- Do not hide Solana state as generic contract storage.

Good direction:

```text
entrypoint manifest + accounts schema + generated validator + Lean handler
```

Risk direction:

```text
auto-map EVM slot storage to Solana accounts
```

### 4. Wasm family separates host ABIs

NEAR and CosmWasm are both Wasm but must not share one target id.

Confirm:

- NEAR has its own method exports, host KV, promises.
- CosmWasm has instantiate/execute/query, region ABI, submessages.
- Wasm runtime may be shared; host bridges must be separate.

Authoritative CosmWasm sketch: [targets/wasm-family.md](targets/wasm-family.md).

### 5. Move uses source generation

First Move phase generates Move source/packages, not a full Lean runtime on MoveVM.

Confirm:

- Lean proofs finish before codegen.
- Move carries executable logic only.
- IR expresses resource/object/ability explicitly.
- Sui and Aptos are handled separately.

### 6. ZK targets do not pretend to be Yul targets

Psy/DPN review focus:

- Generate `.psy` source first.
- Treat DPN circuit JSON as an artifact, not ProofForge's own IR.
- Keep ZK/circuit capabilities explicit.
- Do not directly emit Psy internal structures until the public compiler API is
  stable enough.

Authoritative Psy sketch: [targets/psy-dpn.md](targets/psy-dpn.md).

### 7. Artifact metadata from day one

Every target build should emit:

- target id
- artifact path and hash
- source module
- capabilities used
- toolchain versions
- proof/check status
- warnings

This feeds CI, cloud platform, and audit trails.

## Recommended Review Order

1. [RFC 0001](rfcs/0001-multichain-platform.md) — vision and boundaries.
2. [RFC 0002](rfcs/0002-target-implementation-design.md) — targets and pipelines.
3. [Portable IR](portable-ir.md) and [capability registry](capability-registry.md).
4. [Implementation backlog](implementation-backlog.md) — task slices.
5. Target notes:
   - [EVM](targets/evm.md)
   - [Wasm family](targets/wasm-family.md)
   - [Solana sBPF](targets/solana-sbf.md)
   - [Move family](targets/move-family.md)
   - [Psy DPN ZK target](targets/psy-dpn.md)
6. [Shared scenario: Counter](shared-scenario.md).

## Recorded Decisions

See [decisions.md](decisions.md) for:

- Phase 1 before non-EVM spikes
- Parallel CosmWasm + Solana spikes
- `solana-sbpf-linker` as primary Solana path
- Aptos-first Move POC
- `psy-dpn` as Experimental-stage ZK circuit sourcegen target

## Do Not Do Yet

- Cloud platform UI before two Experimental targets exist.
- Automatic Solana account inference.
- Direct Move bytecode generation as the first Move path.
- One Wasm target id for all Wasm chains.
- Direct Psy DPN internal emission before generated `.psy` source works.
- Promise "any Lean code runs on every chain."

## Good vs Bad Signals

Good:

- EVM baseline stays stable.
- Each new target has a smoke test.
- Unsupported capabilities produce clear errors.
- Artifact metadata converges across targets.
- Shared scenario works on at least two very different targets.

Bad:

- Backends accumulate special-case `if target == ...` branches.
- Capability ids are inconsistent across docs.
- Solana account logic hides in runtime.
- Move codegen is string templates without IR constraints.
- ZK targets hide proof/circuit restrictions from the capability checker.
- Docs and CLI drift apart.

### 8. Doc↔code sync (2026-07)

When reviewing PRs that touch registry, CLI, `justfile` gates, Stdlib, or shared
examples:

- [ ] Nearest English source-of-truth doc updated (see
      [development-standards.md](development-standards.md) Doc sync checklist).
- [ ] `just doc-sync-audit` run locally if target ids, gates, or capability
      matrix changed (advisory P0 mechanical drift).
- [ ] Unimplemented paths labeled **Planned** / **Research**, not current behavior.
