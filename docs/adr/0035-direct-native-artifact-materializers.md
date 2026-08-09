---
id: ADR-0035
title: Aleo Instructions and Psy DPN direct-only materializers
status: proposed
owner: architecture
updated: 2026-08-10
normative: true
---

# ADR-0035：Aleo Instructions and Psy DPN direct-only materializers

## Status

`proposed`

## Context

Aleo and Psy each accumulated two target-language paths：

- Aleo：target-owned Plan could emit an intermediate source language and later obtain Aleo
  Instructions from an external compiler；
- Psy：target-owned Plan could emit Psy source while a later direct path emitted DPN package JSON。

Those dual paths represented the same product semantics twice, created profile/artifact identity
splits, and allowed source-language behavior to become an accidental backend authority. They also
expanded Tool Lock、distribution、acceptance and runtime surfaces without changing product
finalization maturity.

The target-native artifacts already have target-owned schemas and lowerers：Aleo Instructions and
Psy `DPNFunctionCircuitDefinition` package JSON. Keeping the earlier source paths provides no product
capability that cannot be represented or honestly rejected at those native artifact boundaries.

## Decision

1. **Aleo direct-only**：the sole product route is
   `SemanticProgramV1 → AleoPlan → Aleo Instructions IR → {programId}.aleo`.
2. **Psy direct-only**：the sole product route is
   `SemanticProgramV1 → PsyPlan → DPN package → {programName}.dpn.json`.
3. Each target exposes one codegen profile：
   - Aleo：`aleo-instructions-v1`；
   - Psy：`psy-dpn-v1`。
4. Artifact encodings are closed：`aleoInstructions` and `psyDpn`. Source-language encodings are
   removed rather than deprecated.
5. Both finalizers remain zero-tool and `deployable=false`.
6. Remove source AST/printer modules、debug dual-write flags、compiler finalization、compiler/runtime
   acceptance recipes、distribution payloads、Tool Lock entries and source-only goldens.
7. Existing Plan validation and capability matrices remain authoritative. A shape not encoded by the
   direct lowerer fails closed；there is no fallback.
8. Aleo Instructions schema fixtures and the pinned Psy DPN schema/method-id revision remain valid
   native-artifact authorities. A schema authority pin is not an executable Tool Lock dependency.

## Compatibility and migration

This is a breaking codegen-profile/artifact migration：

| Removed surface | Replacement |
|---|---|
| Aleo source profiles | `aleo-instructions-v1` |
| Psy source/VM profiles | `psy-dpn-v1` |
| Aleo source artifact encoding | `aleoInstructions` |
| Psy source artifact encoding | `psyDpn` |
| source/compiler finalization extras | none |

Requests carrying a removed profile id return `PF-PROFILE-UNKNOWN`. Existing output manifests with
removed profile or encoding identities are not accepted as new builds and must be rebuilt. No alias,
shim or implicit default translation is provided.

## Consequences

- Registry、resolver、descriptor、BuildIdentity and output manifests have one profile identity per
  target.
- Product packages no longer distribute or discover the deleted source compilers/runtimes.
- Target tests move from source/compiler acceptance to direct IR codec、golden、materialization and
  fail-closed assertions.
- Fewer generated artifacts and smaller trusted/tool supply-chain closure.
- Historical runtime/compiler observations remain research history only and do not participate in
  product acceptance.

## Non-claims

This decision does not prove either native artifact executes correctly on a VM/network. It does not
add proof generation、UPS、deployment、network query、hermetic qualification or formal target
refinement. It also does not expand the accepted Phase 1 target set.
