---
id: ADR-0036
title: Engineering target scope and EVM-first formal lighthouse
status: proposed
owner: architecture
updated: 2026-08-10
normative: true
---

# ADR-0036：Engineering target scope and EVM-first formal lighthouse

## Status

`proposed`

## Context

The accepted Phase 1 PRD names four product targets: EVM, Solana, NEAR and Noir. The
engineering registry subsequently grew to nine implemented materializers plus three design-only
targets. That implementation fact was repeatedly routed through a scope placeholder, but no
document owned that identifier. The placeholder therefore became a
dangling authority reference rather than a decision.

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
2. **Engineering scope remains 9 + 3.** EVM, Solana, NEAR, Noir, Aleo, Psy, Quint, CosmWasm and
   TON remain implemented materializer leaves. Soroban, ICP and OpenVM remain design-only. An
   implemented label means a target-owned Plan/IR/materializer exists; it is not a release,
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

- Current engineering users retain all nine materializers and their existing honest maturity
  labels.
- Formal planning has one lighthouse instead of nine competing target lanes.
- Accepted PRD prose is not silently rewritten by an engineering registry expansion.
- The removed frontend supervisor is no longer carried as an open scope ambiguity.
- A future target-scope expansion, alternate formal lighthouse or containment boundary requires a
  new reviewed decision.

## Non-claims

EVM-first does not mean EVM formal tasks are complete. It does not close D1-D4, establish
candidate-bound evidence, make any artifact deployable, or qualify a release host. The other eight
implemented materializers remain engineering surfaces with the maturity and fail-closed limits
stated in their target dossiers.
