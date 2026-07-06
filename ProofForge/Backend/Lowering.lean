/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Phase 0 lowering-stage design stub (RFC 0014)

This module is a **design-only** artifact that documents the five-stage
lowering contract every primary ProofForge backend is being aligned onto
under [RFC 0014](../../docs/rfcs/0014-unified-semantic-lowering-contract.md).
The contract is elaborated in
[`docs/target-lowering-interface.md`](../../docs/target-lowering-interface.md).

The five stages are:

1. `resolveCapabilities` — shared, via `ProofForge.Target.Adapter`
   (`defaultResolve`, `requireCapabilityPlan`, `resolveModule`).
2. `validateModule` — shared subset (future `SharedValidate.lean`) plus
   per-backend checks (e.g. `Evm.Validate`, `WasmNear.IR.validateModule`,
   Solana `SbpfAsm.validateCapabilities`).
3. `buildModulePlan` — inspectable pure target-semantic plan
   (e.g. `Evm.Plan.ModulePlan`, future `Solana.Plan.SolanaModulePlan`).
4. `lowerToAst` — plan-driven lowering to the target syntax AST
   (e.g. `Evm.IR.lowerModuleWithPlan`, `Solana.SbpfAsm.lowerModuleCore`).
5. `buildArtifactMetadata` — plan-driven artifact/deploy metadata
   (e.g. `Evm.Metadata`, `Psy.MetadataJson`).

This file introduces NO behavior and NO typeclass. The constructors below
exist purely as documentation-as-code so reviewers, golden tests, and the
`*-semantic-plan` smoke recipes (see
[`docs/target-lowering-interface.md`](../../docs/target-lowering-interface.md)
"Smoke gate pattern") can cite a single canonical name for each stage.

Encoding the lowering contract as a Lean typeclass is **deferred to Phase 6**
of RFC 0014 ("Open questions"), after the Phase 0–4 plan shapes for EVM,
Psy, NEAR, and Solana have stabilized. Locking a typeclass in before the
Solana/NEAR plans exist would be premature abstraction (RFC 0014
"Alternatives considered").
-/

namespace ProofForge.Backend.Lowering

/-- The five-stage lowering contract from RFC 0014, as a design-only
inductive. Each constructor names one stage; there is no data and no
recursion. Phase 6 may replace this with a typeclass encoding once
Phase 0–4 plan shapes are stable. -/
inductive LoweringStage where
  /-- Stage 1: fold `IR.Module` capabilities into a `Target.CapabilityPlan`
  and reject unsupported capabilities / target-extension metadata
  (`Target.Adapter.requireCapabilityPlan`, V-GATE-SOLANA-05, D-027). -/
  | resolveCapabilities
  /-- Stage 2: shared subset (identifiers, return paths,
  unsupported-type-by-profile, ownership hook) plus per-backend checks.
  Pure; may annotate the module; must not construct AST. -/
  | validateModule
  /-- Stage 3: build the inspectable, pure target-semantic plan
  (`<Target>ModulePlan`). No AST construction. -/
  | buildModulePlan
  /-- Stage 4: lower the plan to the target syntax AST
  (`Yul.Object` / `Wasm.Module` / `Solana.Asm.AstNode` / `Psy.Module`).
  Plan-driven; pure; printers untouched. -/
  | lowerToAst
  /-- Stage 5: derive artifact/deploy metadata from the plan, not from
  rendered AST or printed text. -/
  | buildArtifactMetadata

end ProofForge.Backend.Lowering
