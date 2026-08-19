---
id: ADR-0036
title: Engineering target scope and EVM-first formal lighthouse
status: proposed
owner: architecture
updated: 2026-08-19
normative: true
---

# ADR-0036：Engineering target scope and EVM-first formal lighthouse

## Status

`proposed`

## Context

The accepted Phase 1 PRD names four product targets: EVM, Solana, NEAR and Noir. The
engineering registry subsequently grew to thirteen implemented materializers plus zero design-only
targets (Soroban via ADR-0044; OpenVM via ADR-0045/0046; ICP via ADR-0047; XRPL via ADR-0049/0050). That implementation fact was
repeatedly routed through a scope placeholder, but no document owned that identifier. The
placeholder therefore became a dangling authority reference rather than a decision.

At the same time, the repository accumulated two independent scope ambiguities:

- engineering implementation was easy to misread as accepted product or formal scope;
- the retired B11/B12 contained-frontend design remained in older accepted prose after the sole
  product path moved to an in-process, single-snapshot Loader and inline proof gate.

The formal D1-D4 program is still incomplete. Advancing every implemented target in parallel
would multiply the identity, refinement and evidence surface before one end-to-end formal lane is
closed.

## Decision

1. **Accepted product scope remains explicit.** The accepted Phase 1 PRD continues to name EVM,
   Solana, NEAR and Noir until a separately reviewed PRD revision changes it. Engineering
   implementation does not silently amend accepted scope.
2. **Engineering scope is 13 + 0.** EVM, Solana, NEAR, Noir, Aleo, Psy, Quint, CosmWasm, TON, Soroban (source-only S0), OpenVM (guest-source default + opt-in guest-elf), ICP (`icp-wasm-candid-u64-v1`), and XRPL (Bedrock source-only Q0 + opt-in WASM Q1) are implemented materializer leaves.
   OpenVM default profile is guest-source only (ADR-0045): zero-tool finalize, no prove; opt-in
   `openvm-guest-elf-v1` (ADR-0046) may emit ELF/VmExe via locked cargo-openvm without prove.
   XRPL default profile is Bedrock source-only (ADR-0049): zero-tool finalize, no AlphaNet; opt-in
   `xrpl-bedrock-wasm-u64-v1` (ADR-0050) may emit a `.wasm` extra via ambient rustc without deploy.
   An implemented label means a target-owned Plan/IR/materializer exists; it is not a release,
   network, proof or formal claim.
3. **The formal lighthouse is EVM-first.** Shared D2/D3 formal prerequisites are advanced in the
   order needed to close the EVM D4 identity-bound reference-to-artifact differential. Engineering
   evidence from another target does not substitute for that lane and does not promote that target
   to formal scope.
4. **The retired contained frontend stays retired.** The sole product source authority remains one
   in-process file read followed by Loader/ProgramV1, CheckV1/Normalize and the inline proof gate.
   This path makes no sandbox, process-containment, host-race or hermetic claim. Reintroducing a
   supervised frontend requires a new ADR and an explicit product decision; historical B11/B12
   text is not an implementation instruction.
5. **This ADR is the scope pointer.** All live references to the former placeholder are replaced by
   `ADR-0036`; no parallel scope ticket or alias remains.
6. **Business validation remains separate.** This ADR does not create a founder exception or mark
   Phase 0 experiments complete. It only fixes product/formal execution scope.

## Consequences

- Current engineering users retain all thirteen materializers and their existing honest maturity
  labels (Soroban S0 is source-only / non-deployable per ADR-0044; OpenVM maturity remains
  source-only even when the opt-in elf profile emits build extras per ADR-0046; ICP remains
  source-only in the registry label even with host-optional PocketIC per ADR-0047; XRPL remains
  source-only even when the opt-in wasm profile emits a `.wasm` extra per ADR-0049/0050).
- Formal planning has one lighthouse instead of thirteen competing target lanes.
- Accepted PRD prose is not silently rewritten by an engineering registry expansion.
- The removed frontend supervisor is no longer carried as an open scope ambiguity.
- A future target-scope expansion, alternate formal lighthouse or containment boundary requires a
  new reviewed decision.

## Non-claims

EVM-first does not mean EVM formal tasks are complete. It does not close D1-D4, establish
candidate-bound evidence, make any artifact deployable, or qualify a release host. The other twelve
implemented materializers remain engineering surfaces with the maturity and fail-closed limits
stated in their target dossiers. Soroban S0 source-only evidence does not promote Soroban to
accepted Phase 1 or formal scope. OpenVM O0/O1 does not claim proof, VK, or
`verifiable-workload` maturity. XRPL Q0/Q1 does not claim AlphaNet, mainnet, or
`B-CALL-SEM` alignment.
